#!/usr/bin/env python3

# Copyright 2026 ETH Zurich and University of Bologna.
#
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
generate_average_log.py

Scans sim/bin/logs/{core,noc,others} for the per-instance "monitor_*.txt"
report files (e.g. one monitor_core_*.txt per core, one monitor_l1noc_*.txt
per group, one monitor_dram_ch*.txt per DRAM channel) and, for each family
of files that share the same report structure, writes a single averaged
report where every numeric field is the arithmetic mean of that field
across all instances in the family.

A "family" is identified by stripping the trailing group/tile/core/channel
index suffix off the filename, e.g.:
  monitor_core_g0_0_t0_c0.txt, monitor_core_g0_0_t0_c1.txt, ...  -> monitor_core
  monitor_l1noc_g0.txt, monitor_l1noc_g1.txt, ...                -> monitor_l1noc
  monitor_dram_ch0.txt, monitor_dram_ch1.txt, ...                -> monitor_dram
  monitor_tile_traffic_g0_0_t0.txt, ...                          -> monitor_tile_traffic

All files within a family are expected to share an identical line-by-line
text skeleton (only the numeric values differ), which holds for the
monitor_*.txt reports emitted by the simulator. Files whose line skeleton
doesn't match (e.g. a mismatched numeric-token count on some line) are
left untouched on that line -- the first file's line is kept verbatim.

Usage:
  generate_average_log.py [--logs-dir sim/bin/logs] [--out-dir sim/bin/logs/average]
"""

import argparse
import os
import re
import sys
from collections import defaultdict

NUM_RE = re.compile(r'-?\d+\.\d+|-?\d+')
SUFFIX_RE = re.compile(r'_(?:ch\d+|g\d+(?:_\d+)?(?:_t\d+)?(?:_c\d+)?)$')


def parse_args():
    parser = argparse.ArgumentParser(
        description='Average per-core/per-tile/per-group monitor_*.txt logs')
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(script_dir, '..', '..'))
    default_logs_dir = os.path.join(repo_root, 'sim', 'bin', 'logs')
    parser.add_argument('--logs-dir', default=default_logs_dir,
                         help=f'Root directory containing the log subfolders '
                              f'(default: {default_logs_dir})')
    parser.add_argument('--out-dir', default=None,
                         help='Output directory (default: <logs-dir>/average)')
    return parser.parse_args()


def family_key(filename):
    """Strip the trailing _g<N>[_<N>][_t<N>][_c<N>] or _ch<N> index suffix."""
    base = filename[:-len('.txt')] if filename.endswith('.txt') else filename
    stripped = SUFFIX_RE.sub('', base)
    return stripped


def split_numeric(line):
    """Split a line into alternating (text, number-text) parts."""
    parts = []
    last = 0
    for m in NUM_RE.finditer(line):
        parts.append(line[last:m.start()])
        parts.append(m.group())
        last = m.end()
    parts.append(line[last:])
    return parts


def format_avg(values, original_token):
    value = sum(values) / len(values)
    if '.' not in original_token and min(values) == max(values):
        # Constant integer field across the whole family (e.g. session
        # index, cycle-range bounds) -- keep it as a plain integer.
        avg_str = str(int(value))
    else:
        decimals = len(original_token.split('.', 1)[1]) if '.' in original_token else 2
        avg_str = f'{value:.{decimals}f}'
    # Right-justify to at least the original field width so alignment is
    # roughly preserved for the common "label: <padded value>" layout.
    return avg_str.rjust(len(original_token))


def average_family(paths):
    """Return the averaged file content (list of lines) for one family."""
    all_lines = []
    for p in paths:
        with open(p) as f:
            all_lines.append(f.readlines())

    num_lines = len(all_lines[0])
    if any(len(lines) != num_lines for lines in all_lines):
        print(f"Warning: line-count mismatch in family containing {paths[0]}; "
              f"truncating to shortest file", file=sys.stderr)
        num_lines = min(len(lines) for lines in all_lines)

    out_lines = []
    for i in range(num_lines):
        line_variants = [lines[i] for lines in all_lines]
        parts_variants = [split_numeric(line) for line in line_variants]
        ref_parts = parts_variants[0]

        same_shape = all(len(p) == len(ref_parts) for p in parts_variants)
        if not same_shape:
            out_lines.append(line_variants[0])
            continue

        rebuilt = []
        for idx, ref_part in enumerate(ref_parts):
            if idx % 2 == 0:
                # text segment -- taken verbatim from the reference file
                rebuilt.append(ref_part)
            else:
                # numeric segment -- average across all files in the family
                values = [float(pv[idx]) for pv in parts_variants]
                rebuilt.append(format_avg(values, ref_part))
        out_lines.append(''.join(rebuilt))

    return out_lines


def collect_families(logs_dir):
    families = defaultdict(list)
    for root, _dirs, files in os.walk(logs_dir):
        if os.path.basename(root) == 'average':
            continue
        for fname in sorted(files):
            if not fname.endswith('.txt') or not fname.startswith('monitor_'):
                continue
            key = family_key(fname)
            families[(root, key)].append(os.path.join(root, fname))
    return families


def main():
    args = parse_args()
    logs_dir = args.logs_dir
    out_dir = args.out_dir or os.path.join(logs_dir, 'average')

    if not os.path.isdir(logs_dir):
        print(f"Error: logs directory not found: {logs_dir}", file=sys.stderr)
        sys.exit(1)

    families = collect_families(logs_dir)
    if not families:
        print(f"No monitor_*.txt files found under {logs_dir}", file=sys.stderr)
        sys.exit(1)

    for (root, key), paths in sorted(families.items()):
        rel_dir = os.path.relpath(root, logs_dir)
        target_dir = out_dir if rel_dir == '.' else os.path.join(out_dir, rel_dir)
        os.makedirs(target_dir, exist_ok=True)
        out_path = os.path.join(target_dir, f'{key}_average.txt')

        avg_lines = average_family(paths)
        with open(out_path, 'w') as f:
            f.writelines(avg_lines)

        print(f"Generated {out_path} (averaged over {len(paths)} files)")


if __name__ == '__main__':
    main()
