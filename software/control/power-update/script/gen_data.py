#!/usr/bin/env python3
# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Generates data/<cfg>.h for the power-update kernel from one run of the
# golden algorithm:
# - for each iteration j in cfg "cases": the winner (w, k), the state the
#   update reads (row w of P and G, ResAllocMap, the subcarrier list of w)
#   and the expected row w of P and Delta[w] after the update;
# - the state before finalization (P, final G, subcarrier lists) and the
#   expected P and Delta after it.

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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--cfg", type=pathlib.Path, required=True)
    args = parser.parse_args()
    cfg = hjson.loads(args.cfg.read_text())
    m, n = cfg["M"], cfg["N"]
    cases = sorted(cfg["cases"])

    inp = golden.gen_inputs(m, n, cfg.get("seed", 1))
    R2 = inp["R2"].copy()
    P = np.full((m, n), golden.P_INIT, dtype=np.int64)
    res_alloc = np.zeros(n, dtype=np.int64)
    user_alloc = np.zeros((m, n), dtype=np.int64)
    delta = [golden.P_SCALE] * m
    klist = [[] for _ in range(m)]
    rec = {k: [] for k in ["w", "k", "p", "g", "res", "kl", "nal", "p_exp", "d_exp"]}

    for j in range(n):
        if res_alloc.all():
            break
        G = golden.calc_g(inp["A"], golden.calc_r(inp["R1"], R2, inp["C"]), inp["D"])
        _, w, k = golden.select(P, G, res_alloc)
        if j in cases:
            kl = np.zeros(n, dtype=np.int64)
            kl[:len(klist[w])] = klist[w]
            for key, val in [("w", w), ("k", k), ("p", P[w].copy()), ("g", G[w].copy()),
                             ("res", res_alloc.copy()), ("kl", kl), ("nal", len(klist[w]))]:
                rec[key].append(val)
        golden.update_winner(P, G, res_alloc, user_alloc, delta, w, k)
        klist[w].append(k)
        if j in cases:
            rec["p_exp"].append(P[w].copy())
            rec["d_exp"].append(delta[w])
        R2[w] = (R2[w] + j) % 2

    G = golden.calc_g(inp["A"], golden.calc_r(inp["R1"], R2, inp["C"]), inp["D"])
    fin_kl = np.zeros((m, n), dtype=np.int64)
    for i in range(m):
        fin_kl[i, :len(klist[i])] = klist[i]
    fin_nal = [len(x) for x in klist]
    fin_p, fin_d = P.copy(), list(delta)
    golden.finalize(P, G, user_alloc, delta)

    # the outputs must equal the plain golden run
    ref = golden.control_algo(**inp)
    assert np.array_equal(ref["P"], P)

    print(f"{args.cfg.stem}: cases {cases}, n before update "
          f"{rec['nal']}, users with subcarriers {sum(1 for x in fin_nal if x)}")

    out = ("// Copyright 2025 ETH Zurich and University of Bologna.\n"
           "// Licensed under the Apache License, Version 2.0, see LICENSE for details.\n"
           "// SPDX-License-Identifier: Apache-2.0\n\n"
           "// This file was generated automatically by script/gen_data.py.\n\n"
           "#include <stdint.h>\n\n"
           f"#define CTRL_M {m}\n#define CTRL_N {n}\n#define CTRL_CASES {len(cases)}\n\n")
    out += c_array("ctrl_case_j", cases)
    for key in ["w", "k", "nal", "d_exp"]:
        out += c_array(f"ctrl_case_{key}", rec[key])
    for key in ["p", "g", "res", "kl", "p_exp"]:
        out += c_array(f"ctrl_case_{key}", np.array(rec[key]))
    out += c_array("ctrl_fin_P", fin_p)
    out += c_array("ctrl_fin_G", G)
    out += c_array("ctrl_fin_klist", fin_kl)
    out += c_array("ctrl_fin_nalloc", fin_nal)
    out += c_array("ctrl_fin_delta", fin_d)
    out += c_array("ctrl_fin_P_exp", P)
    out += c_array("ctrl_fin_delta_exp", delta)

    dst = pathlib.Path(__file__).resolve().parents[1] / "data" / (args.cfg.stem + ".h")
    dst.write_text(out)


if __name__ == "__main__":
    main()
