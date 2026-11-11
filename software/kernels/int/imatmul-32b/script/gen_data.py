#!/usr/bin/env python3
# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Integer GEMM data, the 32-bit integer counterpart of kernels/fp/fmatmul-32b.
# C = A (M x K) * B (K x N), all row-major. C starts with random values the kernel overwrites;
# the full result is emitted, so the check is exact per element.

import argparse
import pathlib

import hjson
import numpy as np

np.random.seed(42)

# Small operands keep every partial sum far from the int32 range
VAL_MIN, VAL_MAX = -16, 16


def array_to_cstr(a):
    return "{" + ", ".join(str(int(el)) for el in np.asarray(a).flat) + "}"


def main():
    parser = argparse.ArgumentParser(description="Generate data for the imatmul kernel")
    parser.add_argument("-c", "--cfg", type=pathlib.Path, required=True,
                        help="Select param config file kernel")
    args = parser.parse_args()

    with args.cfg.open() as f:
        param = hjson.loads(f.read())
    if param["prec"] != 32:
        raise ValueError("imatmul only supports 32-bit integers")

    m, n, k = param["M"], param["N"], param["K"]
    mat_a = np.random.randint(VAL_MIN, VAL_MAX, size=(m, k), dtype=np.int64)
    mat_b = np.random.randint(VAL_MIN, VAL_MAX, size=(k, n), dtype=np.int64)
    mat_c = np.random.randint(VAL_MIN, VAL_MAX, size=(m, n), dtype=np.int64)
    result = mat_a @ mat_b

    name = "imatmul"
    attr = '__attribute__((section(".data"), aligned(1024)))'
    out = (
        "// Copyright 2026 ETH Zurich and University of Bologna.\n"
        "// Licensed under the Apache License, Version 2.0, see LICENSE for details.\n"
        "// SPDX-License-Identifier: Apache-2.0\n\n"
        "// This file was generated automatically.\n\n"
        '#include "layer.h"\n\n'
        f"const imatmul_layer {name}_l = {{\n\t.M = {m},\n\t.N = {n},\n\t.K = {k},\n}};\n\n"
        f"static int32_t {name}_A_dram [{m}*{k}] {attr} = " + array_to_cstr(mat_a) + ";\n\n"
        f"static int32_t {name}_B_dram [{k}*{n}] {attr} = " + array_to_cstr(mat_b) + ";\n\n"
        f"static int32_t {name}_C_dram [{m}*{n}] {attr} = " + array_to_cstr(mat_c) + ";\n\n"
        f'static int32_t {name}_result [{m}*{n}] __attribute__((section(".data"))) = '
        + array_to_cstr(result) + ";\n"
    )
    file = pathlib.Path(__file__).parent.parent / "data" / f"data_{m}_{n}_{k}.h"
    file.write_text(out)


if __name__ == "__main__":
    main()
