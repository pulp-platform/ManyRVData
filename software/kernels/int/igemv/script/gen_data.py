#!/usr/bin/env python3
# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Integer GEMV data, the 32-bit integer counterpart of kernels/fp/gemv.
# A (M x N) is stored column-major, like the fp version; the result is exact.

import argparse
import pathlib

import hjson
import numpy as np

np.random.seed(42)

# Small operands keep every partial sum far from the int32 range
VAL_MIN, VAL_MAX = -16, 16


def array_to_cstr(a):
    return "{" + ", ".join(str(int(el)) for el in np.asarray(a).flat) + "}"


def emit_header_file(m, n, prec, mat_a, vec_b, result):
    file_path = pathlib.Path(__file__).parent.parent / "data"
    name = "igemv"
    out = (
        "// Copyright 2026 ETH Zurich and University of Bologna.\n"
        "// Licensed under the Apache License, Version 2.0, see LICENSE for details.\n"
        "// SPDX-License-Identifier: Apache-2.0\n\n"
        "// This file was generated automatically.\n\n"
        '#include "layer.h"\n\n'
        f"igemv_layer {name}_l = {{\n\t.M = {m},\n\t.N = {n},\n}};\n\n"
        f'static int32_t {name}_A_dram [{m} * {n}] __attribute__((section(".pdcp_src"))) = '
        + array_to_cstr(mat_a) + ";\n\n"
        f'static int32_t {name}_B_dram [{n}] __attribute__((section(".pdcp_src"))) = '
        + array_to_cstr(vec_b) + ";\n\n"
        f'static int32_t {name}_result [{m}] __attribute__((section(".pdcp_src"))) = '
        + array_to_cstr(result) + ";\n"
    )
    file = file_path / f"data_{m}_{n}_{prec}.h"
    file.write_text(out)


def main():
    parser = argparse.ArgumentParser(description="Generate data for the igemv kernel")
    parser.add_argument("-c", "--cfg", type=pathlib.Path, required=True,
                        help="Select param config file kernel")
    args = parser.parse_args()

    with args.cfg.open() as f:
        param = hjson.loads(f.read())
    if param["prec"] != 32:
        raise ValueError("igemv only supports 32-bit integers")

    m, n = param["M"], param["N"]
    mat_a = np.random.randint(VAL_MIN, VAL_MAX, size=(m, n), dtype=np.int64)
    vec_b = np.random.randint(VAL_MIN, VAL_MAX, size=(n,), dtype=np.int64)
    result = mat_a @ vec_b

    # Column-major A, as the kernel walks it column by column
    emit_header_file(m, n, param["prec"], mat_a.T, vec_b, result)


if __name__ == "__main__":
    main()
