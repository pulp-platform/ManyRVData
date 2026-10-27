#!/usr/bin/env python3
# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Generates data/<cfg>.h for the gain-select kernel: the state at the start
# of iteration J of the golden algorithm (P, the current G and ResAllocMap),
# the expected Gain = ln(1 + P * G) in Q16 and the expected winner.

import argparse
import pathlib
import sys

import hjson
import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "common"))
import golden  # noqa: E402


def c_array(name, a):
    a = np.asarray(a)
    vals = ", ".join(str(int(v)) for v in a.flat)
    return (f'static int32_t {name}[{a.size}] '
            f'__attribute__((section(".data"), aligned(64))) = {{{vals}}};\n\n')


def state_at(inp, iters):
    """P, G and ResAllocMap at the start of iteration `iters`."""
    n, m = inp["R1"].shape
    R2 = inp["R2"].copy()
    P = np.full((m, n), golden.P_INIT, dtype=np.int64)
    res_alloc = np.zeros(n, dtype=np.int64)
    user_alloc = np.zeros((m, n), dtype=np.int64)
    delta = [golden.P_SCALE] * m
    for j in range(iters):
        G = golden.calc_g(inp["A"], golden.calc_r(inp["R1"], R2, inp["C"]), inp["D"])
        _, w, k = golden.select(P, G, res_alloc)
        golden.update_winner(P, G, res_alloc, user_alloc, delta, w, k)
        R2[w] = (R2[w] + j) % 2
    G = golden.calc_g(inp["A"], golden.calc_r(inp["R1"], R2, inp["C"]), inp["D"])
    return P, G, res_alloc


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--cfg", type=pathlib.Path, required=True)
    args = parser.parse_args()
    cfg = hjson.loads(args.cfg.read_text())
    m, n = cfg["M"], cfg["N"]
    assert m <= 128 and n <= 128, "7-bit user field in the key, two vector strips"

    P, G, res_alloc = state_at(golden.gen_inputs(m, n, cfg.get("seed", 1)), cfg["J"])
    gain = golden.ilog(P * G)
    best, w, k = golden.select(P, G, res_alloc)
    print(f"{args.cfg.stem}: J {cfg['J']}, {int(res_alloc.sum())} allocated, "
          f"winner user {w} subcarrier {k} gain {best}")

    out = ("// Copyright 2025 ETH Zurich and University of Bologna.\n"
           "// Licensed under the Apache License, Version 2.0, see LICENSE for details.\n"
           "// SPDX-License-Identifier: Apache-2.0\n\n"
           "// This file was generated automatically by script/gen_data.py.\n\n"
           "#include <stdint.h>\n\n"
           f"#define CTRL_M {m}\n#define CTRL_N {n}\n\n"
           f"#define CTRL_W_EXP {w}\n#define CTRL_K_EXP {k}\n#define CTRL_GAIN_EXP {best}\n\n")
    out += c_array("ctrl_P", P)
    out += c_array("ctrl_G", G)
    out += c_array("ctrl_res_alloc", res_alloc)
    out += c_array("ctrl_gain", np.zeros_like(gain))
    out += c_array("ctrl_gain_exp", gain)

    dst = pathlib.Path(__file__).resolve().parents[1] / "data" / (args.cfg.stem + ".h")
    dst.write_text(out)


if __name__ == "__main__":
    main()
