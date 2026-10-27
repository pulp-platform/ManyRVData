#!/usr/bin/env python3
# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Restructured control algorithm, checked bit-exactly against golden.py:
# - R and G are computed once per iteration (they do not depend on the user)
# - R2 only changes after odd iterations: (x + j) % 2 keeps x for even j and
#   flips the whole row for odd j
# - the unclamped U = R1 * R2 + C and V = A * R + D are updated in place:
#   flipping row w of R2 adds s[k] * R1[:, w] to column k of U (s = +1 for a
#   0 -> 1 flip, -1 otherwise); while no R clamp binds, V changes by the
#   rank-1 term (A * R1[:, w]) s^T, and columns whose clamp state changes are
#   recomputed in full.

import numpy as np
import golden as g


def control_algo_fast(R1, R2, A, C, D, stats=None):
    n, m = R1.shape
    R2 = R2.copy()
    U = R1.astype(np.int64) @ R2 + C
    R = np.clip(U, g.MIN_R, g.MAX_R)
    V = A.astype(np.int64) @ R + D
    G = np.clip(V >> g.G_SHIFT, g.MIN_G, g.MAX_G)
    ops = {"init_mac": n * m * n + m * n * n, "u_add": 0, "v_mac": 0,
           "col_fix": 0, "g_updates": 0}

    P = np.full((m, n), g.P_INIT, dtype=np.int64)
    res_alloc = np.zeros(n, dtype=np.int64)
    user_alloc = np.zeros((m, n), dtype=np.int64)
    delta = [g.P_SCALE] * m
    winners = []

    for j in range(n):
        if res_alloc.all():
            break
        sel = g.select(P, G, res_alloc)
        if sel is None:
            break
        s_max, w, k_star = sel
        winners.append((w, k_star, int(s_max)))
        g.update_winner(P, G, res_alloc, user_alloc, delta, w, k_star)
        if j % 2:
            s = 1 - 2 * R2[w]
            R2[w] = 1 - R2[w]
            U += np.outer(R1[:, w], s)
            R_new = np.clip(U, g.MIN_R, g.MAX_R)
            dR = R_new - R
            rank1 = np.outer(R1[:, w], s)
            exact = np.all(dR == rank1, axis=0)
            # rank-1 part for columns where no clamp is involved
            V += np.outer(A @ R1[:, w], s * exact)
            ops["u_add"] += n * n
            ops["v_mac"] += m * n + m * n
            # full recompute of the other columns
            for k in np.nonzero(~exact)[0]:
                V[:, k] = A @ R_new[:, k] + D[k]
                ops["col_fix"] += 1
                ops["v_mac"] += m * n
            R = R_new
            G = np.clip(V >> g.G_SHIFT, g.MIN_G, g.MAX_G)
            ops["g_updates"] += 1
        else:
            R2[w] = (R2[w] + j) % 2

    g.finalize(P, G, user_alloc, delta)
    if stats is not None:
        stats.update(ops)
    return {"P": P, "ResAllocMap": res_alloc, "UserResAllocMap": user_alloc,
            "R2": R2, "winners": winners}


if __name__ == "__main__":
    for (m, n) in [(1, 1), (2, 3), (1, 100), (8, 16), (16, 64), (48, 100), (80, 100)]:
        for seed in range(3):
            inp = g.gen_inputs(m, n, seed)
            ref = g.control_algo(**inp)
            st = {}
            out = control_algo_fast(**inp, stats=st)
            for key in ["P", "ResAllocMap", "UserResAllocMap", "R2"]:
                assert np.array_equal(ref[key], out[key]), (m, n, seed, key)
            assert ref["winners"] == out["winners"], (m, n, seed)
        print(f"M={m:3d} N={n:3d}: exact over 3 seeds; last seed ops {st}")
