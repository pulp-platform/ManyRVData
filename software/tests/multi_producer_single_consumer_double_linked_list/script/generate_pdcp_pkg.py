#!/usr/bin/env python3

# Copyright 2025 ETH Zurich and University of Bologna.
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
# distributed under the License distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: Zexin Fu <zexifu@iis.ee.ethz.ch>

"""
generate_pdcp_pkg_header.py

Reads a JSON config (default: pdcp_pkg.json), strips C-style comments, and emits a C header defining:
  - `pdcp_pkg_t pdcp_pkgs[]` in the .dram section
  - A 2D array `pdcp_src_data[NUM_SRC_SLOTS][PDU_SIZE]` in its own .pdcp_src section (so its [0] element begins at src_addr)

Config fields:
  active_user_number   (int)
  pkg_length           (int bytes)
  pdcp_header_length   (int bytes)
  src_addr             (hex or int base address)
  src_length           (int bytes)
  tgt_addr             (hex or int base address)
  tgt_length           (int bytes)
  total_pkg_number     (optional int): explicit number of PDCP packages to generate

If `total_pkg_number` is absent, it's derived as `src_length // (pdcp_header_length + pkg_length)`.
"""

import os
import json
import argparse
import random
import re
import sys

LICENSE_HEADER = '''
// Copyright 2025 ETH Zurich and University of Bologna.
//
// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Author: Zexin Fu <zexifu@iis.ee.ethz.ch>
'''


def parse_args():
    parser = argparse.ArgumentParser(
        description='Generate a PDCP-package header from JSON config')
    parser.add_argument('config', nargs='?', default='pdcp_pkg.json',
                        help='JSON config file (default: pdcp_pkg.json)')
    parser.add_argument('-o', '--output',
                        help='Output header file (default: ../data/data_<users>_<len>_<pkgs>.h)')
    parser.add_argument('-f', '--fill-zero',
                        help='Fill unused slots with zeroes (default: True)', action='store_true', default=False)
    parser.add_argument('--seed', type=int, default=42,
                        help='Optional seed for random generator for reproducibility')
    return parser.parse_args()


def load_config(path):
    text = open(path).read()
    cleaned = re.sub(r'//.*', '', text)
    return json.loads(cleaned)


def main():
    args = parse_args()
    # Load config
    try:
        cfg = load_config(args.config)
    except Exception as e:
        print(f"Error loading config: {e}", file=sys.stderr)
        sys.exit(1)

    # Seed randomness
    random.seed(args.seed)

    # parse parameters
    active_users = int(cfg['active_user_number'])
    pkg_len = int(cfg['pkg_length'])
    hdr_len = int(cfg['pdcp_header_length'])
    src_base = int(cfg['src_addr'], 0)
    src_len = int(cfg['src_length'])
    tgt_base = int(cfg['tgt_addr'], 0)
    tgt_len = int(cfg['tgt_length'])

    # PDU configuration
    pdu_size = hdr_len + pkg_len
    num_src_slots = src_len // pdu_size
    num_pkgs = min(int(cfg.get('total_pkg_number', num_src_slots)), num_src_slots)

    # derive output path if not provided
    if args.output:
        out_path = args.output
    else:
        data_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'data'))
        os.makedirs(data_dir, exist_ok=True)
        filename = f"data_{active_users}_{pkg_len}_{num_pkgs}.h"
        out_path = os.path.join(data_dir, filename)

    # select unique slots
    slots = random.sample(range(num_src_slots), k=num_pkgs)

    # assemble metadata and data buffer
    entries = []
    pdu_buf = [[0] * pdu_size for _ in range(num_src_slots)]
    for uid, slot in zip((random.randrange(active_users) for _ in range(num_pkgs)), slots):
        src_addr = src_base + slot * pdu_size
        tgt_addr = tgt_base + slot * pdu_size
        entries.append((uid, src_addr, tgt_addr, pdu_size))
        for i in range(hdr_len, pdu_size):
            pdu_buf[slot][i] = slot & 0xFF

    # write header
    with open(out_path, 'w') as h:
        # license
        h.write(LICENSE_HEADER + '\n')
        # include guard
        h.write('#ifndef PDCP_PKG_H\n')
        h.write('#define PDCP_PKG_H\n\n')

        # type definition
        h.write('typedef struct {\n')
        h.write('    int           user_id;\n')
        h.write('    unsigned int  src_addr;\n')
        h.write('    unsigned int  tgt_addr;\n')
        h.write('    unsigned int  pkg_length;\n')
        h.write('} pdcp_pkg_t;\n\n')

        # constants
        h.write(f'#define NUM_SRC_SLOTS {num_src_slots}\n')
        h.write(f'#define PDU_SIZE      {pdu_size}\n')
        h.write(f'#define NUM_PKGS      {num_pkgs}\n\n')

        # metadata in .pdcp_info
        h.write('static const pdcp_pkg_t __attribute__((section(".pdcp_info"), used)) pdcp_pkgs[NUM_PKGS] = {\n')
        for uid, s, t, plen in entries:
            h.write(f'    {{ {uid}, 0x{s:08X}, 0x{t:08X}, {plen} }},\n')
        h.write('};\n\n')

        # src data in its own section so .pdcp_src can be located at src_base
        h.write('static const uint8_t __attribute__((section(".pdcp_src"), used)) '
               'pdcp_src_data[NUM_SRC_SLOTS][PDU_SIZE] = {\n')
        for slot in range(num_src_slots):
            if args.fill_zero:
                row = ', '.join(f'0x{b:02X}' for b in pdu_buf[slot])
                if any(pdu_buf[slot]):
                    h.write(f'    {{ {row} }}, // [{slot}]\n')
                else:
                    h.write(f'    {{ {row} }},\n')
            else:
                if any(pdu_buf[slot]):
                    row = ', '.join(f'0x{b:02X}' for b in pdu_buf[slot])
                    h.write(f'    [{slot}] = {{ {row} }},\n')
        h.write('};\n\n')

        # end guard
        h.write('#endif // PDCP_PKG_H\n')

    print(f"Generated {out_path} ({num_pkgs} pkgs, {num_src_slots} slots)")


if __name__ == '__main__':
    main()
