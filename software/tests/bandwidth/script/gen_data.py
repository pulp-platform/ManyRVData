#!/usr/bin/env python3
# Copyright 2022 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Diyou Shen         <dishen@iis.ee.ethz.ch>
#
# Generate data/data.h for the CachePool random-load bandwidth benchmark.
#
# Layout in the generated header:
#   const uint32_t M  = <data elements>;
#   const uint32_t R  = <measurement rounds per core>;
#   static int data_dram[M]                 — random payload in DRAM
#   static uint32_t offset_dram[R * cores] — interleaved per-core offsets
#
# Each offset is a v_len-aligned element index into data_dram (step = v_len).
# Offsets span the full data_dram range so that repeated accesses across all
# rounds cover more than the L1 cache capacity and exercise DRAM bandwidth.

import numpy as np
import argparse
import pathlib
import hjson

np.random.seed(42)


def array_to_cstr(a):
    """Format a numpy integer array as a C initialiser list."""
    out = '{\n'
    values_per_line = 16
    flat = a.flatten()
    for i in range(0, len(flat), values_per_line):
        chunk = flat[i:i + values_per_line]
        line = ', '.join(str(v) for v in chunk)
        if i + values_per_line < len(flat):
            out += '  ' + line + ',\n'
        else:
            out += '  ' + line + '\n'
    out += '}'
    return out


def rand_data_generator(shape, prec):
    """Return a random integer numpy array of the requested precision."""
    dtype_map = {64: np.int64, 32: np.int32, 16: np.int16, 8: np.int8}
    dtype = dtype_map[prec]
    return np.random.randint(-100, 100, size=shape, dtype=dtype)


def rand_offset_generator(num_entries, data_elems, step):
    """Return v_len-aligned random element offsets that span data_dram.

    Each offset satisfies:
        offset + step <= data_elems   (in-bounds for a v_len-wide load)
    Offsets are expressed in elements (not bytes).

    Parameters
    ----------
    num_entries : int
        Total number of offset entries (cores * rounds).
    data_elems  : int
        Size of data_dram in elements.
    step        : int
        Load granularity in elements (= v_len, e.g. 64 for lmul=4 + VLEN=512).
    """
    max_idx = data_elems // step - 1   # last valid aligned block index
    if max_idx < 0:
        raise ValueError(f"data_elems ({data_elems}) < step ({step})")
    indices = np.random.randint(0, max_idx + 1, size=num_entries, dtype=np.uint32)
    return indices * step


def emit_header(data_arr, offset_arr, M, R, cores, prec):
    ctypes = {64: 'int64_t', 32: 'int', 16: 'int16_t', 8: 'int8_t'}
    dtype = ctypes[prec]

    offset_size = R * cores

    s  = '// Copyright 2022 ETH Zurich and University of Bologna.\n'
    s += '// Licensed under the Apache License, Version 2.0, see LICENSE for details.\n'
    s += '// SPDX-License-Identifier: Apache-2.0\n'
    s += '// This file was generated automatically by script/gen_data.py.\n\n'
    s += '#include <stdint.h>\n\n'
    s += f'const uint32_t M = {M};\n'
    s += f'const uint32_t R = {R};\n\n'
    # data_dram: payload array accessed by random vector loads
    s += (f'static {dtype} data_dram[{M}]'
          f' __attribute__((section(".data"))) = '
          + array_to_cstr(data_arr) + ';\n\n')
    # offset_dram: interleaved per-core random element offsets
    # Layout: [core0_r0, core1_r0, ..., coreN_r0, core0_r1, ...]
    s += (f'static uint32_t offset_dram[{offset_size}]'
          f' __attribute__((section(".data"))) = '
          + array_to_cstr(offset_arr) + ';\n\n')
    return s


def main():
    parser = argparse.ArgumentParser(
        description='Generate data.h for the CachePool bandwidth benchmark')
    parser.add_argument('-c', '--cfg', type=pathlib.Path, required=True,
                        help='Path to parameter JSON (e.g. script/bw.json)')
    args = parser.parse_args()

    with args.cfg.open() as f:
        p = hjson.loads(f.read())

    M     = p['M']       # elements in data_dram
    R     = p['round']   # measurement rounds per core
    prec  = p['prec']    # element width in bits (32)
    cores = p['core']    # number of active cores
    step  = p['step']    # load granularity in elements (= v_len)

    data_arr   = rand_data_generator((M,), prec)
    offset_arr = rand_offset_generator(R * cores, M, step)

    out_path = pathlib.Path(__file__).parent.parent / 'data' / 'data.h'
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open('w') as f:
        f.write(emit_header(data_arr, offset_arr, M, R, cores, prec))

    print(f'Generated {out_path}  (M={M}, R={R}, cores={cores}, step={step})')


if __name__ == '__main__':
    main()
