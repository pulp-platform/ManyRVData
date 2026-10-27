#!/usr/bin/env python3
# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Generates data/<cfg>.h for kernel 1 (uv-init): the control-algorithm inputs
# and the expected U, R, V and G from common/golden.py.

import argparse
import pathlib
import sys

import hjson
import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "common"))
import golden  # noqa: E402


# Row pitch (in int32) of the a matrices: a whole number of 64-byte cache
# lines, and an odd one, so that the four rows a core reads at once fall in
# different L1 banks
LINE = 16


def pitch(k):
    lines = (k + LINE - 1) // LINE
    return LINE * (lines if lines % 2 else lines + 1)


def padded(a, lda):
    out = np.zeros((a.shape[0], lda), dtype=np.int64)
    out[:, :a.shape[1]] = a
    return out


def c_array(name, a, section=".data"):
    vals = ", ".join(str(int(v)) for v in np.asarray(a).flat)
    return (f'static int32_t {name}[{np.asarray(a).size}] '
            f'__attribute__((section("{section}"), aligned(64))) = {{{vals}}};\n\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--cfg", type=pathlib.Path, required=True)
    args = parser.parse_args()
    cfg = hjson.loads(args.cfg.read_text())
    m, n = cfg["M"], cfg["N"]

    if cfg.get("init", "random") == "const":
        # small exact values, easy to read back in a failing run
        inp = {"R1": np.ones((n, m), int), "R2": np.ones((m, n), int),
               "A": np.ones((m, n), int), "C": np.zeros((n, n), int),
               "D": np.zeros(n, int)}
    else:
        inp = golden.gen_inputs(m, n, cfg.get("seed", 1))

    U = inp["R1"] @ inp["R2"] + inp["C"]
    R = golden.calc_r(inp["R1"], inp["R2"], inp["C"])
    V = golden.check_i32(inp["A"] @ R + inp["D"], "V")
    G = golden.calc_g(inp["A"], R, inp["D"])

    out = ("// Copyright 2025 ETH Zurich and University of Bologna.\n"
           "// Licensed under the Apache License, Version 2.0, see LICENSE for details.\n"
           "// SPDX-License-Identifier: Apache-2.0\n\n"
           "// This file was generated automatically by script/gen_data.py.\n\n"
           "#include <stdint.h>\n\n"
           f"#define CTRL_M {m}\n#define CTRL_N {n}\n"
           f"#define CTRL_LDA_R1 {pitch(m)}\n#define CTRL_LDA_A {pitch(n)}\n\n")
    out += c_array("ctrl_R1", padded(inp["R1"], pitch(m)))
    out += c_array("ctrl_A", padded(inp["A"], pitch(n)))
    for key in ["R2", "C", "D"]:
        out += c_array(f"ctrl_{key}", inp[key])
    for key, val in [("U", U), ("R", R), ("V", V), ("G", G)]:
        out += c_array(f"ctrl_{key}", np.zeros_like(val))
        out += c_array(f"ctrl_{key}_exp", val)

    dst = pathlib.Path(__file__).resolve().parents[1] / "data" / (args.cfg.stem + ".h")
    dst.write_text(out)


if __name__ == "__main__":
    main()
