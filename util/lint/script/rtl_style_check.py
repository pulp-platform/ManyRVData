#!/usr/bin/env python3
# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""RTL coding-style checker for CachePool SystemVerilog sources.

Modes:
    scan [PATH ...]       check every in-scope .sv/.svh file under PATH (default: hardware)
    scan --changed-since REF
                          only report violations on lines changed since merge-base(REF, HEAD)
    hook                  pre-commit: check staged files, only on staged changed lines
    install-hook          install the pre-commit hook into this repository
    rules                 list the rules and their severities

Waivers:
    inline   a comment line `// style-waive: RULE[,RULE] <reason>` waives the next line
             (or the block/comment block starting on the next line)
    file     a comment line `// style-waive-file: RULE[,RULE] <reason>` waives the whole file
    list     util/lint/script/rtl_style_waivers.txt, one `RULE | path-glob | line-regex | reason`
             per line

Scope, severities and options are configured in util/lint/script/rtl_style.cfg.
The checker is lexical (no elaboration): it strips comments/strings, tracks `ifdef and
translate_off regions, and recovers procedural block / loop / module-header extents.
"""

import argparse
import configparser
import os
import re
import stat
import subprocess
import sys
from dataclasses import dataclass, field

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CFG = os.path.join(SCRIPT_DIR, 'rtl_style.cfg')
DEFAULT_WAIVERS = os.path.join(SCRIPT_DIR, 'rtl_style_waivers.txt')
HOOK_MARKER = 'rtl_style_check.py hook'

RULES = {
    'BLOCKING_IN_FF': 'blocking assignment in always_ff, use <=',
    'FF_NO_RESET': 'flip-flop without reset, use the `FF macros',
    'UNPACKED_STRUCT': 'unpacked struct/union, declare it packed',
    'AUTOMATIC': '`automatic` outside a loop-index declaration',
    'EOL_COMMENT': 'end-of-line comment, move it to its own line above',
    'COMMENT_BLOCK': 'comment block longer than {comment_max_lines} lines, condense it',
    'INDENT_TAB': 'tab character, indent with spaces',
    'INDENT_ODD': 'indentation is not a multiple of {indent} spaces',
    'PORT_NAMING': 'port name must end in {suffixes}',
    'DEBUG_PROBE': 'debug tracer/probe left in RTL, remove it once debugging is done',
    'DEBUG_UNGUARDED': 'check/assertion not guarded by `ifndef TARGET_SYNTHESIS',
    'WAIVER_INVALID': 'waiver is ignored: unknown rule or missing reason',
}

PROC_KW = {'always_ff', 'always_comb', 'always_latch', 'always', 'initial', 'final'}
END_KW = {
    'end', 'endcase', 'endmodule', 'endfunction', 'endtask', 'endgenerate', 'endpackage',
    'endinterface', 'join', 'join_any', 'join_none', 'endclocking', 'endproperty', 'endsequence',
    'endprogram', 'endclass', 'endgroup'
}
CTRL_KW = {
    'if', 'for', 'foreach', 'while', 'repeat', 'case', 'casez', 'casex', '@', 'always', 'always_ff',
    'always_latch'
}
STMT_END_KW = END_KW | {'begin', 'else', 'generate', 'fork', 'default'}
BLOCKING_OPS = {
    '=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<=', '>>=', '<<<=', '>>>=', '++', '--'
}
PROBE_RE = re.compile(r'^\$(display[bho]?|write[bho]?|monitor[bho]?|strobe[bho]?|'
                      r'fdisplay[bho]?|fwrite[bho]?|fmonitor[bho]?|fstrobe[bho]?|'
                      r'fopen|fclose|fflush|dump\w*)$')
CHECK_TASKS = {'$error', '$fatal', '$warning', '$info'}
ASSERT_KW = {'assert', 'assume', 'cover'}
PORT_SUFFIX = {'input': ('_i', '_ni'), 'output': ('_o', '_no'), 'inout': ('_io', )}
WAIVE_RE = re.compile(r'style-waive(-file)?\s*:\s*([A-Za-z_*]+(?:\s*,\s*[A-Za-z_*]+)*)'
                      r'\s*:?\s*(.*)')
WAIVER_LINE_RE = re.compile(r'^([^|]+)\|([^|]+)\|(.*)\|([^|]*)$')
SEPARATOR_RE = re.compile(r'^[\s/*\-=#~_+]*$')
TRANSLATE_RE = re.compile(r'\b(?:pragma|synopsys|synthesis)\s+translate_(off|on)\b')

OPERATORS = [
    '<<<=', '>>>=', '===', '!==', '==?', '!=?', '<<<', '>>>', '<<=', '>>=', '|->', '|=>', '<->',
    '->>', '##', '::', '+:', '-:', '->', '<=', '>=', '==', '!=', '&&', '||', '**', '<<', '>>', '++',
    '--', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '~&', '~|', '~^', '^~', '.*'
]
OPERATORS.sort(key=len, reverse=True)
IDENT_START = re.compile(r'[A-Za-z_]')
IDENT = re.compile(r'[A-Za-z_][A-Za-z0-9_$]*')
NUMBER = re.compile(
    r"\d[\d_]*(\.\d[\d_]*)?([eE][+-]?\d+)?(\s*'[sS]?[bBoOdDhH]\s*[0-9a-fA-FxXzZ?_]+)?"
    r"(fs|ps|ns|us|ms|s|step)?(?![A-Za-z0-9_])")
BASED = re.compile(r"'[sS]?[bBoOdDhH]\s*[0-9a-fA-FxXzZ?_]+|'[01xXzZ](?![A-Za-z0-9_])")


@dataclass
class Tok:
    kind: str
    text: str
    line: int
    col: int
    nonsynth: bool = False


@dataclass
class Violation:
    rule: str
    path: str
    line: int
    col: int
    msg: str
    end_line: int = 0
    severity: str = 'error'
    lines: frozenset = None

    def span(self):
        return self.lines or range(self.line, max(self.line, self.end_line) + 1)


@dataclass
class Source:
    """Lexed view of one file."""
    path: str
    lines: list
    toks: list = field(default_factory=list)
    code: list = field(default_factory=list)
    line_code: set = field(default_factory=set)
    line_directive: set = field(default_factory=set)
    comments: dict = field(default_factory=dict)
    block_comment_lines: set = field(default_factory=set)
    block_comment_starts: set = field(default_factory=set)


# -----
# Lexer
# -----
def lex(path, text):
    src = Source(path, text.split('\n'))
    n = len(text)
    i = 0
    line = 1
    line_start = 0
    toks = src.toks

    def add_comment(ln, col, body):
        src.comments.setdefault(ln, []).append((col, body))
        m = TRANSLATE_RE.search(body)
        if m:
            toks.append(Tok('dir', 'translate_' + m.group(1), ln, col))

    def skip_to_eol(j):
        # Consume a directive body up to EOL (honouring `\` continuations), stop before `//`.
        nonlocal line, line_start
        while j < n and text[j] != '\n':
            if text.startswith('//', j):
                return j
            if text[j] == '\\' and j + 1 < n and text[j + 1] == '\n':
                j += 2
                line += 1
                line_start = j
                src.line_code.add(line)
                src.line_directive.add(line)
                continue
            j += 1
        return j

    while i < n:
        c = text[i]
        col = i - line_start
        if c == '\n':
            line += 1
            i += 1
            line_start = i
            continue
        if c in ' \t\r\f':
            i += 1
            continue
        if text.startswith('//', i):
            j = text.find('\n', i)
            j = n if j < 0 else j
            add_comment(line, col, text[i + 2:j])
            i = j
            continue
        if text.startswith('/*', i):
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            body = text[i + 2:j - 2]
            add_comment(line, col, body)
            src.block_comment_starts.add((line, col))
            for k in range(text.count('\n', i, j)):
                src.block_comment_lines.add(line + k + 1)
            line += text.count('\n', i, j)
            nl = text.rfind('\n', i, j)
            if nl >= 0:
                line_start = nl + 1
            i = j
            continue
        src.line_code.add(line)
        if c == '"':
            j = i + 1
            while j < n and text[j] not in '"\n':
                j += 2 if text[j] == '\\' else 1
            toks.append(Tok('str', text[i:j + 1], line, col))
            i = j + 1
            continue
        if c == '`':
            m = IDENT.match(text, i + 1)
            name = m.group(0) if m else ''
            j = i + 1 + len(name)
            if name in ('ifdef', 'ifndef', 'elsif'):
                m2 = IDENT.match(text, j + len(text[j:]) - len(text[j:].lstrip(' \t')))
                arg = m2.group(0) if m2 else ''
                toks.append(Tok('dir', name + ' ' + arg, line, col))
                src.line_directive.add(line)
                i = m2.end() if m2 else j
            elif name in ('else', 'endif'):
                toks.append(Tok('dir', name, line, col))
                src.line_directive.add(line)
                i = j
            elif name in ('define', 'include', 'timescale', 'undef', 'undefineall', 'resetall',
                          'default_nettype', 'pragma', 'line', 'celldefine', 'endcelldefine'):
                src.line_directive.add(line)
                i = skip_to_eol(j)
            else:
                toks.append(Tok('macro', '`' + name, line, col))
                i = j
            continue
        if c == '$':
            m = IDENT.match(text, i + 1)
            name = m.group(0) if m else ''
            toks.append(Tok('sys', '$' + name, line, col))
            i += 1 + len(name)
            continue
        if c == '\\':
            j = i
            while j < n and not text[j].isspace():
                j += 1
            toks.append(Tok('id', text[i:j], line, col))
            i = j
            continue
        if IDENT_START.match(c):
            m = IDENT.match(text, i)
            toks.append(Tok('id', m.group(0), line, col))
            i = m.end()
            continue
        if c.isdigit():
            m = NUMBER.match(text, i)
            j = m.end() if m else i + 1
            toks.append(Tok('num', text[i:j], line, col))
            i = j
            continue
        if c == "'":
            m = BASED.match(text, i)
            if m:
                toks.append(Tok('num', m.group(0), line, col))
                i = m.end()
                continue
        for op in OPERATORS:
            if text.startswith(op, i):
                break
        else:
            op = c
        toks.append(Tok('op', op, line, col))
        i += len(op)
    return src


def annotate_nonsynth(src, cfg):
    """Flag tokens sitting in simulation-only regions and drop directive tokens."""
    undef_macros = set(cfg['nonsynth_if_undefined'])
    def_macros = set(cfg['nonsynth_if_defined'])
    stack = []
    translate_off = False
    for t in src.toks:
        if t.kind == 'dir':
            parts = t.text.split()
            if parts[0] in ('ifdef', 'ifndef'):
                stack.append([parts[1] if len(parts) > 1 else '', parts[0] == 'ifdef'])
            elif parts[0] == 'elsif' and stack:
                stack[-1] = [parts[1] if len(parts) > 1 else '', True]
            elif parts[0] == 'else' and stack:
                stack[-1][1] = not stack[-1][1]
            elif parts[0] == 'endif' and stack:
                stack.pop()
            elif parts[0] == 'translate_off':
                translate_off = True
            elif parts[0] == 'translate_on':
                translate_off = False
            continue
        t.nonsynth = translate_off or any(
            (m in undef_macros and not d) or (m in def_macros and d) for m, d in stack)
    src.code = [t for t in src.toks if t.kind != 'dir']


# ---------
# Structure
# ---------
class Structure:
    """Extents of procedural blocks, loops, functions and module headers."""
    def __init__(self, code):
        self.C = code
        self.T = [t.text for t in code]
        self.match = self._match_brackets()
        self.procs = []
        self.fors = []
        self.headers = []
        self._scan()

    def _match_brackets(self):
        match = [-1] * len(self.T)
        stack = []
        pairs = {')': '(', ']': '[', '}': '{'}
        for i, (t, tok) in enumerate(zip(self.T, self.C)):
            if tok.kind != 'op':
                continue
            if t in '([{':
                stack.append(i)
            elif t in pairs:
                while stack and self.T[stack[-1]] != pairs[t]:
                    stack.pop()
                if stack:
                    j = stack.pop()
                    match[i], match[j] = j, i
        return match

    def tok(self, i):
        return self.T[i] if 0 <= i < len(self.T) else ''

    def close(self, i):
        j = self.match[i] if 0 <= i < len(self.T) else -1
        return j if j > i else len(self.T) - 1

    def block_end(self, i, openers, closers):
        depth = 0
        for j in range(i, len(self.T)):
            if self.T[j] in openers:
                depth += 1
            elif self.T[j] in closers:
                depth -= 1
                if depth == 0:
                    return j
        return len(self.T) - 1

    def stmt_end(self, i):
        """Index of the last token of the statement starting at i."""
        T, n = self.T, len(self.T)
        if i >= n:
            return n - 1
        t = T[i]
        if t == 'begin':
            e = self.block_end(i, ('begin', ), ('end', ))
            return e + 2 if self.tok(e + 1) == ':' else e
        if t in ('unique', 'unique0', 'priority'):
            return self.stmt_end(i + 1)
        if t == 'if':
            j = self.close(i + 1) if self.tok(i + 1) == '(' else i
            e = self.stmt_end(j + 1)
            return self.stmt_end(e + 2) if self.tok(e + 1) == 'else' else e
        if t in ('case', 'casez', 'casex', 'randcase'):
            return self.block_end(i, ('case', 'casez', 'casex', 'randcase'), ('endcase', ))
        if t in ('for', 'foreach', 'while', 'repeat'):
            j = self.close(i + 1) if self.tok(i + 1) == '(' else i
            return self.stmt_end(j + 1)
        if t == 'forever':
            return self.stmt_end(i + 1)
        if t == 'fork':
            return self.block_end(i, ('fork', ), ('join', 'join_any', 'join_none'))
        if t in ('@', '#'):
            j = i + 1
            j = self.close(j) if self.tok(j) == '(' else j
            return self.stmt_end(j + 1)
        if self.C[i].kind == 'macro':
            j = self.close(i + 1) if self.tok(i + 1) == '(' else i
            return j + 1 if self.tok(j + 1) == ';' else j
        j = i
        while j < n:
            if self.C[j].kind == 'op' and T[j] in '([{':
                j = self.close(j)
            elif T[j] == ';':
                return j
            elif j > i and T[j] in END_KW:
                return j - 1
            j += 1
        return n - 1

    def _scan(self):
        T, C = self.T, self.C
        i = 0
        while i < len(T):
            t = T[i]
            if C[i].kind != 'id':
                i += 1
                continue
            if t in PROC_KW:
                j = i + 1
                sens = None
                if self.tok(j) == '@':
                    if self.tok(j + 1) == '(':
                        sens = (j + 2, self.close(j + 1))
                        j = self.close(j + 1) + 1
                    else:
                        j += 2
                self.procs.append((t, i, j, self.stmt_end(j), sens))
            elif t == 'for' and self.tok(i + 1) == '(':
                body = self.close(i + 1) + 1
                self.fors.append((body, self.stmt_end(body)))
            elif t in ('function', 'task') and self.tok(i - 1) not in ('import', 'export', 'extern',
                                                                       'pure', 'virtual'):
                closer = 'end' + t
                i = next((k for k in range(i, len(T)) if T[k] == closer), len(T) - 1)
            elif t in ('module', 'macromodule'):
                self._module_header(i)
            i += 1

    def _module_header(self, i):
        j = i + 1
        if self.tok(j) in ('automatic', 'static'):
            j += 1
        j += 1
        while self.tok(j) == 'import':
            while j < len(self.T) and self.T[j] != ';':
                j += 1
            j += 1
        if self.tok(j) == '#' and self.tok(j + 1) == '(':
            j = self.close(j + 1) + 1
        if self.tok(j) == '(':
            self.headers.append((j + 1, self.close(j) - 1))

    def inside(self, regions, i):
        return any(s <= i <= e for s, e in regions)

    def proc_of(self, i):
        """Start index of the procedural block containing token i, or None."""
        return next((s for _, s, _, e, _ in self.procs if s <= i <= e), None)


# -----
# Rules
# -----
class Checker:
    def __init__(self, cfg):
        self.cfg = cfg

    def check(self, path, text):
        src = lex(path, text)
        annotate_nonsynth(src, self.cfg)
        st = Structure(src.code)
        out = []
        self._ff_rules(src, st, out)
        self._token_rules(src, st, out)
        self._ports(src, st, out)
        self._line_rules(src, st, out)
        self._comment_blocks(src, out)
        return src, out

    def v(self, out, rule, path, tok_or_line, msg=None, col=0, end_line=0, lines=None):
        if isinstance(tok_or_line, Tok):
            line, col = tok_or_line.line, tok_or_line.col
        else:
            line = tok_or_line
        msg = msg or RULES[rule].format(**self.cfg)
        out.append(Violation(rule, path, line, col + 1, msg, end_line, lines=lines))

    def _ff_rules(self, src, st, out):
        C, T = st.C, st.T
        reset_re = self.cfg['reset_re']
        for kind, start, body, end, sens in st.procs:
            if kind != 'always_ff' or C[start].nonsynth:
                continue
            has_reset = sens is not None and any(C[k].kind == 'id' and reset_re.search(T[k])
                                                 for k in range(sens[0], sens[1]))
            if not has_reset:
                k = body + 1 if st.tok(body) == 'begin' else body
                if st.tok(k) == 'if' and st.tok(k + 1) == '(':
                    has_reset = any(reset_re.search(T[m]) for m in range(k + 2, st.close(k + 1)))
            if not has_reset:
                self.v(out, 'FF_NO_RESET', src.path, C[start])
            depth = 0
            for k in range(body, end + 1):
                if C[k].kind != 'op':
                    continue
                if T[k] in '([{':
                    depth += 1
                elif T[k] in ')]}':
                    depth -= 1
                elif depth == 0 and T[k] in BLOCKING_OPS:
                    self.v(out, 'BLOCKING_IN_FF', src.path, C[k])
        for t in C:
            if t.kind == 'macro' and re.fullmatch(r'`FFL?NR\w*', t.text) and not t.nonsynth:
                self.v(out, 'FF_NO_RESET', src.path, t)

    def _token_rules(self, src, st, out):
        C = st.C
        # Debug findings are grouped per procedural block: one report at the block start.
        groups = {}
        for i, t in enumerate(C):
            if t.kind == 'sys' and PROBE_RE.match(t.text):
                groups.setdefault(('DEBUG_PROBE', st.proc_of(i)), []).append(t)
                continue
            if t.nonsynth:
                continue
            if t.text in ('struct', 'union') and t.kind == 'id':
                k = i + 1
                while st.tok(k) in ('tagged', 'soft'):
                    k += 1
                if st.tok(k) != 'packed':
                    self.v(out, 'UNPACKED_STRUCT', src.path, t)
            elif t.text == 'automatic' and t.kind == 'id':
                if st.tok(i - 1) in ('function', 'task', 'module') or not st.inside(st.fors, i):
                    self.v(out, 'AUTOMATIC', src.path, t)
            elif (t.kind == 'sys' and t.text in CHECK_TASKS and st.proc_of(i) is not None) or \
                    (t.kind == 'id' and t.text in ASSERT_KW):
                groups.setdefault(('DEBUG_UNGUARDED', st.proc_of(i)), []).append(t)
        for (rule, proc), toks in groups.items():
            names = ', '.join(sorted({t.text for t in toks}))
            if rule == 'DEBUG_PROBE':
                msg = f'debug print ({names}) left in RTL, remove it once debugging is done'
            else:
                msg = (f'check ({names}) not guarded by `ifndef TARGET_SYNTHESIS, '
                       'or use `ASSERT macros')
            if proc is None:
                for t in toks:
                    self.v(out, rule, src.path, t, msg)
            else:
                self.v(out, rule, src.path, C[proc], msg, lines=frozenset(t.line for t in toks))
        for t in src.toks:
            if (t.kind == 'dir' and t.text.split()[0] in ('ifdef', 'ifndef', 'elsif')
                    and self.cfg['debug_macro_re'].search(t.text.split()[-1])):
                self.v(out, 'DEBUG_PROBE', src.path, t,
                       f'debug-only region `{t.text}, remove it once debugging is done')

    def _ports(self, src, st, out):
        C, T = st.C, st.T
        for s, e in st.headers:
            direction = None
            k = s
            while k <= e:
                item_end = k
                while item_end <= e and T[item_end] != ',':
                    if C[item_end].kind == 'op' and T[item_end] in '([{':
                        item_end = st.close(item_end)
                    item_end += 1
                self_dir, name_tok = self._port_item(st, k, item_end - 1)
                direction = self_dir or direction
                if (direction in PORT_SUFFIX and name_tok is not None and not name_tok.nonsynth
                        and not name_tok.text.endswith(PORT_SUFFIX[direction])):
                    sfx = '/'.join(PORT_SUFFIX[direction])
                    self.v(out, 'PORT_NAMING', src.path, name_tok,
                           f'{direction} port `{name_tok.text}` must end in {sfx}')
                k = item_end + 1

    def _port_item(self, st, s, e):
        T, C = st.T, st.C
        if s > e:
            return None, None
        direction = T[s] if T[s] in ('input', 'output', 'inout', 'ref') else None
        for k in range(s, e + 1):
            if T[k] == '=':
                e = k - 1
                break
        while e > s and T[e] == ']':
            e = st.match[e] - 1
        if direction is None and any(T[k] == '.' for k in range(s, e)):
            return 'interface', None
        return direction, (C[e] if C[e].kind == 'id' else None)

    def _line_rules(self, src, st, out):
        pragma = self.cfg['pragma_re']
        first, last, cols = {}, {}, {}
        for idx, t in enumerate(src.code):
            first.setdefault(t.line, idx)
            last[t.line] = idx
        for t in src.toks:
            cols.setdefault(t.line, []).append(t.col)
        prev_line = None
        for ln, raw in enumerate(src.lines, 1):
            if '\t' in raw:
                self.v(out, 'INDENT_TAB', src.path, ln, col=raw.index('\t'))
            if ln in src.line_code and ln in src.comments:
                for col, body in src.comments[ln]:
                    # A /* */ comment followed by more code (e.g. `/* unused */ )`) is inline.
                    if (ln, col) in src.block_comment_starts and any(
                            c > col for c in cols.get(ln, [])):
                        continue
                    if not pragma.search(body):
                        self.v(out, 'EOL_COMMENT', src.path, ln, col=col)
                        break
            if ln not in first or ln in src.line_directive or '\t' in raw:
                if ln in first:
                    prev_line = ln
                continue
            indent = len(raw) - len(raw.lstrip(' '))
            if indent % self.cfg['indent'] and self._starts_statement(st, last.get(prev_line)):
                self.v(out, 'INDENT_ODD', src.path, ln, col=indent)
            prev_line = ln

    @staticmethod
    def _starts_statement(st, p):
        """True if the code line after token index p starts a new statement."""
        code, T, match = st.C, st.T, st.match
        if p is None:
            return True
        t = T[p]
        if t in (';', ) or t in STMT_END_KW:
            return True
        if code[p].kind == 'id' and p >= 2 and T[p - 1] == ':' and T[p - 2] in STMT_END_KW:
            return True
        if t == ':' and p >= 1 and (T[p - 1] == 'default' or code[p - 1].kind in ('id', 'num')):
            return False
        if t == ')' and match[p] > 0:
            before = T[match[p] - 1]
            return before in CTRL_KW
        return False

    def _comment_blocks(self, src, out):
        limit = self.cfg['comment_max_lines']
        first_code = min(src.line_code) if src.line_code else len(src.lines) + 1
        pragma = self.cfg['pragma_re']
        start = None
        count = 0
        for ln in range(1, len(src.lines) + 2):
            bodies = src.comments.get(ln, [])
            is_comment = ln < len(src.lines) + 1 and ln not in src.line_code and (
                bool(bodies) or ln in src.block_comment_lines) and not any(
                    WAIVE_RE.search(b) or pragma.search(b) for _, b in bodies)
            if is_comment:
                start = start or ln
                # Separator lines such as `// -----` or ` *****/` carry no text and do not count.
                count += not SEPARATOR_RE.match(src.lines[ln - 1])
                continue
            if start and count > limit and start > first_code:
                col = len(src.lines[start - 1]) - len(src.lines[start - 1].lstrip())
                msg = f'{count}-line comment block (max {limit}), condense it'
                self.v(out, 'COMMENT_BLOCK', src.path, start, msg, col=col, end_line=ln - 1)
            start, count = None, 0


# -------
# Waivers
# -------
@dataclass
class Waiver:
    rules: set
    glob: str
    regex: object
    reason: str


def load_waivers(path):
    waivers, problems = [], []
    if not path or not os.path.exists(path):
        return waivers, problems
    with open(path) as f:
        for n, raw in enumerate(f, 1):
            text = raw.strip()
            if not text or text.startswith('#'):
                continue
            # The regex is everything between the 2nd and the last `|`, so it may use alternation.
            m = WAIVER_LINE_RE.match(text)
            if not m or not m.group(4):
                problems.append(f'{path}:{n}: expected `RULE | path-glob | line-regex | reason`')
                continue
            parts = [g.strip() for g in m.groups()]
            try:
                regex = re.compile(parts[2]) if parts[2] else None
            except re.error as e:
                problems.append(f'{path}:{n}: bad line-regex: {e}')
                continue
            rules = {r.strip() for r in parts[0].split(',')}
            problem = waiver_problem(rules, parts[3])
            if problem:
                problems.append(f'{path}:{n}: {problem}')
                continue
            waivers.append(Waiver(rules, parts[1], regex, parts[3]))
    return waivers, problems


def waiver_problem(rules, reason):
    """Why a waiver is unusable, or None."""
    unknown = sorted(r for r in rules if r != '*' and r not in RULES)
    if unknown:
        return f'unknown rule {", ".join(unknown)} (see `rtl_style_check.py rules`)'
    if not reason.strip():
        return 'a reason is required'
    return None


def inline_waivers(src, out):
    """Collect inline waivers: {line: rules}, file-wide rules."""
    per_line, file_rules = {}, set()
    for ln in sorted(src.comments):
        for col, body in src.comments[ln]:
            m = WAIVE_RE.search(body)
            if not m:
                continue
            rules = {r.strip() for r in m.group(2).split(',')}
            problem = waiver_problem(rules, m.group(3))
            if problem:
                out.append(Violation('WAIVER_INVALID', src.path, ln, col + 1,
                                     f'waiver is ignored: {problem}'))
                continue
            if m.group(1):
                file_rules |= rules
                continue
            target = ln + 1
            while target <= len(src.lines) and (not src.lines[target - 1].strip() or any(
                    WAIVE_RE.search(b) for _, b in src.comments.get(target, []))):
                target += 1
            per_line.setdefault(target, set()).update(rules)
    return per_line, file_rules


def is_waived(v, src, per_line, file_rules, waivers):
    if v.rule == 'WAIVER_INVALID':
        return False

    def hit(rules):
        return v.rule in rules or '*' in rules

    if hit(file_rules) or hit(per_line.get(v.line, set())):
        return True
    text = src.lines[v.line - 1] if v.line - 1 < len(src.lines) else ''
    return any(
        hit(w.rules) and glob_match(w.glob, v.path) and (w.regex is None or w.regex.search(text))
        for w in waivers)


# ------------
# Config/scope
# ------------
def glob_to_re(pattern):
    out = ''
    i = 0
    while i < len(pattern):
        if pattern.startswith('**/', i):
            out += '(?:.*/)?'
            i += 3
        elif pattern.startswith('**', i):
            out += '.*'
            i += 2
        elif pattern[i] == '*':
            out += '[^/]*'
            i += 1
        elif pattern[i] == '?':
            out += '[^/]'
            i += 1
        else:
            out += re.escape(pattern[i])
            i += 1
    return re.compile(out + '$')


def glob_match(pattern, path):
    return bool(glob_to_re(pattern).match(path))


def load_config(path):
    cp = configparser.ConfigParser(interpolation=None)
    cp.optionxform = str
    cp.read(path)
    opt = cp['options'] if cp.has_section('options') else {}
    pragma = r'^\s*(verilator|spyglass|synopsys|pragma|synthesis|cadence|verible|lint)\b'
    scope = cp.get('scope', 'paths', fallback='')
    cfg = {
        'scope': [p.strip() for p in scope.splitlines() if p.strip()],
        'severity': {r: 'error' for r in RULES},
        'indent': int(opt.get('indent', 2)),
        'comment_max_lines': int(opt.get('comment_max_lines', 3)),
        'reset_re': re.compile(opt.get('reset_pattern', r'(?i)rst|reset')),
        'debug_macro_re': re.compile(opt.get('debug_macro_pattern', r'(?i)debug')),
        'pragma_re': re.compile(opt.get('pragma_pattern', pragma)),
        'nonsynth_if_undefined': opt.get('nonsynth_if_undefined', 'TARGET_SYNTHESIS').split(),
        'nonsynth_if_defined': opt.get('nonsynth_if_defined', '').split(),
        'suffixes': '_i/_ni (input), _o/_no (output), _io (inout)',
    }
    if cp.has_section('rules'):
        for rule, sev in cp['rules'].items():
            if rule not in RULES:
                sys.exit(f'{path}: unknown rule {rule}')
            if sev not in ('error', 'warning', 'off'):
                sys.exit(f'{path}: severity of {rule} must be error, warning or off')
            cfg['severity'][rule] = sev
    return cfg


def in_scope(cfg, rel):
    keep = False
    for pat in cfg['scope']:
        neg = pat.startswith('!')
        if glob_match(pat.lstrip('!'), rel):
            keep = not neg
    return keep


# ---
# Git
# ---
def git(*args, check=True):
    r = subprocess.run(['git', *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       encoding='utf-8', errors='replace')
    if check and r.returncode:
        sys.exit(f'git {" ".join(args)} failed: {r.stderr.strip()}')
    return r.stdout


def repo_root():
    out = git('rev-parse', '--show-toplevel', check=False).strip()
    return out or os.path.abspath(os.path.join(SCRIPT_DIR, '..', '..', '..'))


def changed_lines(diff_args):
    """Parse `git diff -U0` into {path: set(lines)}."""
    out = git('diff', '-U0', '--no-color', '--no-ext-diff', '-M', '--diff-filter=ACMR',
              '--src-prefix=a/', '--dst-prefix=b/', *diff_args)
    changes, path = {}, None
    for raw in out.splitlines():
        if raw.startswith('+++ '):
            path = None if raw[4:] == '/dev/null' else raw[6:]
            if path:
                changes.setdefault(path, set())
        elif raw.startswith('@@') and path:
            m = re.search(r'\+(\d+)(?:,(\d+))?', raw)
            start, count = int(m.group(1)), int(m.group(2) or 1)
            changes[path].update(range(start, start + count))
    return changes


# ------
# Driver
# ------
def run(checker, files, waivers, only_lines=None):
    """files: list of (rel_path, text). only_lines: {rel_path: set} or None."""
    results, waived = [], 0
    for rel, text in files:
        src, found = checker.check(rel, text)
        per_line, file_rules = inline_waivers(src, found)
        seen = set()
        for v in sorted(found, key=lambda x: (x.line, x.col, x.rule)):
            v.severity = checker.cfg['severity'].get(v.rule, v.severity)
            if v.severity == 'off' or (v.rule, v.line) in seen:
                continue
            seen.add((v.rule, v.line))
            if only_lines is not None and not set(v.span()) & only_lines.get(rel, set()):
                continue
            if is_waived(v, src, per_line, file_rules, waivers):
                waived += 1
                continue
            results.append(v)
    return results, waived


def report(results, waived, nfiles, strict):
    for v in results:
        print(f'{v.path}:{v.line}:{v.col}: {v.severity}: {v.rule}: {v.msg}')
    sys.stdout.flush()
    errors = sum(v.severity == 'error' for v in results)
    warnings = len(results) - errors
    print(f'rtl-style: {errors} error(s), {warnings} warning(s) in {nfiles} file(s), '
          f'{waived} waived', file=sys.stderr)
    return 1 if errors or (strict and warnings) else 0


def collect(root, cfg, paths):
    files = []
    for p in paths:
        ap = os.path.join(root, p) if not os.path.isabs(p) else p
        if os.path.isfile(ap):
            cands = [ap]
        else:
            cands = [os.path.join(d, f) for d, _, fs in os.walk(ap) for f in fs]
        for f in sorted(cands):
            rel = os.path.relpath(f, root)
            if in_scope(cfg, rel):
                files.append(rel)
    return sorted(set(files))


def cmd_scan(args, cfg, checker, waivers, root):
    rels = collect(root, cfg, args.paths or ['hardware'])
    only = None
    if args.changed_since:
        base = git('merge-base', args.changed_since, 'HEAD').strip()
        only = changed_lines([base])
        rels = [r for r in rels if r in only]
    files = []
    for rel in rels:
        with open(os.path.join(root, rel), encoding='utf-8', errors='replace') as f:
            files.append((rel, f.read()))
    results, waived = run(checker, files, waivers, only)
    return report(results, waived, len(files), args.strict)


def cmd_hook(args, cfg, checker, waivers, root):
    only = changed_lines(['--cached'])
    rels = [r for r in sorted(only) if in_scope(cfg, r)]
    files = [(r, git('show', f':{r}')) for r in rels]
    results, waived = run(checker, files, waivers, None if args.full_file else only)
    rc = report(results, waived, len(files), args.strict)
    if rc:
        print('rtl-style: commit blocked. Fix the violations, or add a '
              '`// style-waive: RULE reason` line above them '
              '(bypass once with `git commit --no-verify`).', file=sys.stderr)
    return rc


def cmd_install_hook(args, root):
    hooks = git('rev-parse', '--git-path', 'hooks').strip()
    hooks = hooks if os.path.isabs(hooks) else os.path.join(os.getcwd(), hooks)
    os.makedirs(hooks, exist_ok=True)
    dst = os.path.join(hooks, 'pre-commit')
    if os.path.exists(dst):
        with open(dst) as f:
            if HOOK_MARKER not in f.read() and not args.force:
                sys.exit(f'{dst} exists and was not installed by this script; rerun with --force '
                         '(the old hook is kept as pre-commit.bak)')
        if args.force:
            os.replace(dst, dst + '.bak')
    script = os.path.relpath(os.path.abspath(__file__), root)
    with open(dst, 'w') as f:
        f.write('#!/bin/sh\n'
                f'# Installed by {script} install-hook\n'
                'root=$(git rev-parse --show-toplevel) || exit 1\n'
                f'exec "${{PYTHON:-python3}}" "$root/{script}" hook\n')
    os.chmod(dst, os.stat(dst).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    print(f'installed {dst}')
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog='\n'.join(__doc__.split('\n')[2:]))
    ap.add_argument('--config', default=DEFAULT_CFG)
    ap.add_argument('--waivers', default=DEFAULT_WAIVERS)
    ap.add_argument('--strict', action='store_true', help='warnings also fail')
    sub = ap.add_subparsers(dest='cmd', required=True)
    sp = sub.add_parser('scan', help='full scan of the given paths')
    sp.add_argument('paths', nargs='*')
    sp.add_argument('--changed-since', metavar='REF',
                    help='only report violations on lines changed since merge-base(REF, HEAD)')
    hp = sub.add_parser('hook', help='pre-commit mode: staged files and lines only')
    hp.add_argument('--full-file', action='store_true',
                    help='report the whole staged file, not only changed lines')
    ip = sub.add_parser('install-hook', help='install the git pre-commit hook')
    ip.add_argument('--force', action='store_true', help='replace a foreign pre-commit hook')
    sub.add_parser('rules', help='list rules and severities')
    args = ap.parse_args()

    root = repo_root()
    os.chdir(root)
    cfg = load_config(args.config)
    if args.cmd == 'rules':
        for r, desc in RULES.items():
            print(f'{r:18} {cfg["severity"][r]:8} {desc.format(**cfg)}')
        return 0
    if args.cmd == 'install-hook':
        return cmd_install_hook(args, root)
    waivers, problems = load_waivers(args.waivers)
    for p in problems:
        print(p, file=sys.stderr)
    if problems:
        return 1
    checker = Checker(cfg)
    if args.cmd == 'scan':
        return cmd_scan(args, cfg, checker, waivers, root)
    return cmd_hook(args, cfg, checker, waivers, root)


if __name__ == '__main__':
    sys.exit(main())
