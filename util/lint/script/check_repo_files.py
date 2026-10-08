#!/usr/bin/env python3
# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Keep notes, worklogs and other stray documents out of the repository.

Modes:
    scan --changed-since REF   check files added since merge-base(REF, HEAD) (CI)
    hook                       check staged files (pre-commit)

Rules:
    NEW_DOC_FILE   a new documentation-like file (.md, .txt, NOTES, ...) that does not match
                   util/lint/script/repo_files_allowlist.txt
    CLAUDE_MD      a change to CLAUDE.md. CLAUDE.md is gitignored and only updated on purpose:
                   force-add it, and commit with ALLOW_CLAUDE_MD=1. In CI this is a warning.
"""

import argparse
import os
import re
import sys

from rtl_style_check import git, glob_match, repo_root

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ALLOWLIST = os.path.join(SCRIPT_DIR, 'repo_files_allowlist.txt')
DOC_EXT = {'.md', '.markdown', '.rst', '.org', '.txt', '.log'}
DOC_NAME_RE = re.compile(r'(?i)^(notes?|worklog|todo|plan|scratch|journal|log)$')


def is_doc(path):
    base = os.path.basename(path)
    stem, ext = os.path.splitext(base)
    return ext.lower() in DOC_EXT or (not ext and DOC_NAME_RE.match(stem))


def is_claude_md(path):
    return os.path.basename(path) == 'CLAUDE.md'


def load_allowlist(path):
    with open(path) as f:
        return [ln.strip() for ln in f if ln.strip() and not ln.lstrip().startswith('#')]


def changed_files(diff_args):
    """{path: status letter} of files added, renamed in, or modified."""
    out = git('diff', '--name-status', '--no-renames', '--diff-filter=AM', *diff_args)
    files = {}
    for line in out.splitlines():
        status, path = line.split('\t', 1)
        files[path] = status[0]
    return files


def check(files, allow, claude_allowed, ci):
    errors, warnings = [], []
    for path, status in sorted(files.items()):
        if is_claude_md(path):
            msg = (f'{path}: CLAUDE_MD: CLAUDE.md changed; it is only updated on purpose '
                   '(force-add, commit with ALLOW_CLAUDE_MD=1)')
            if ci:
                warnings.append(msg)
            elif not claude_allowed:
                errors.append(msg)
            continue
        if status == 'A' and is_doc(path) and not any(glob_match(g, path) for g in allow):
            errors.append(f'{path}: NEW_DOC_FILE: new documentation-like file not in '
                          'util/lint/script/repo_files_allowlist.txt (notes and worklogs '
                          'stay out of the repo)')
    return errors, warnings


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog='\n'.join(__doc__.split('\n')[2:]))
    ap.add_argument('--allowlist', default=DEFAULT_ALLOWLIST)
    sub = ap.add_subparsers(dest='cmd', required=True)
    sp = sub.add_parser('scan', help='check files added since a reference (CI)')
    sp.add_argument('--changed-since', metavar='REF', required=True)
    sub.add_parser('hook', help='pre-commit mode: staged files')
    args = ap.parse_args()

    os.chdir(repo_root())
    allow = load_allowlist(args.allowlist)
    if args.cmd == 'scan':
        base = git('merge-base', args.changed_since, 'HEAD').strip()
        files = changed_files([base, 'HEAD'])
    else:
        files = changed_files(['--cached'])
    ci = args.cmd == 'scan'
    errors, warnings = check(files, allow, os.environ.get('ALLOW_CLAUDE_MD') == '1', ci)
    for w in warnings:
        # GitHub Actions turns this into an annotation on the PR
        print(f'::warning::{w}' if os.environ.get('GITHUB_ACTIONS') else f'warning: {w}')
    for e in errors:
        print(f'error: {e}')
    sys.stdout.flush()
    print(f'repo-files: {len(errors)} error(s), {len(warnings)} warning(s) in {len(files)} '
          'changed file(s)', file=sys.stderr)
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
