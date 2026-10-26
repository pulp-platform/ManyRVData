#!/usr/bin/env python3
# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Golden model of the control algorithm (see ../README.md), written literally
# from the algorithm description. Everything is int32: P and Delta are scaled
# by 100 and every division truncates like C integer division.

import numpy as np

MIN_R, MAX_R = -4096, 4096
MIN_G, MAX_G = 1, 1 << 20
# G = clamp((A[i] * R + D) >> G_SHIFT, MinG, MaxG): A * R + D has a standard
# deviation of about 3e7, so without the shift S = P * G could not stay in 32
# bits without saturating most of G.
G_SHIFT = 7
P_SCALE = 100
P_INIT = 100

INT32_MIN, INT32_MAX = -(1 << 31), (1 << 31) - 1


def check_i32(x, what):
    x = np.asarray(x, dtype=np.int64)
    if x.size and (x.min() < INT32_MIN or x.max() > INT32_MAX):
        raise OverflowError(f"{what} leaves the int32 range")
    return x


def gen_inputs(m, n, seed):
    rng = np.random.default_rng(seed)
    return {
        "R1": rng.integers(-50, 51, size=(n, m)),
        "R2": rng.integers(0, 2, size=(m, n)),
        "A": rng.integers(-3000, 3001, size=(m, n)),
        "C": rng.integers(-3000, 3001, size=(n, n)),
        "D": rng.integers(-3000, 3001, size=(n,)),
    }


def calc_r(R1, R2, C):
    u = check_i32(R1.astype(np.int64) @ R2.astype(np.int64) + C, "R1 * R2 + C")
    return np.clip(u, MIN_R, MAX_R)


def calc_g(A, R, D):
    g = check_i32(A.astype(np.int64) @ R + D, "A * R + D")
    return np.clip(g >> G_SHIFT, MIN_G, MAX_G)


def div(a, b):
    # C integer division (truncates toward zero); here both operands are >= 0
    assert a >= 0 and b > 0
    return a // b


def inv_g(g):
    # 1/g scaled by 100
    return div(P_SCALE, int(g))


def recip_sum(g_row, alloc_row):
    # 100 * (1 + sum of 1/g over the allocated k)
    return P_SCALE + sum(inv_g(g_row[k]) for k in np.nonzero(alloc_row)[0])


def power(delta, ig):
    # max(0, delta - 1/g), everything scaled by 100
    return max(0, delta - ig)


# ln(1 + S) in Q16 with 32-bit integer operations, as the gain-select kernel
# computes it (only the int -> float conversion that finds the exponent uses
# the FPU):
#   1 + S = 2^e * m, m in [1, 2), from the bits of float(1 + S)
#   ln m  = ln 1.5 + ln(1 + u), u = (m - 1.5) * 2/3, |u| <= 1/3
#   ln(1 + u) = u * sum (-1)^k u^k / (k + 1), LOG_TERMS terms, Horner in Q30
#   Gain  = (e * ln 2 + ln m) in Q24, rounded to Q16
LOG_TERMS = 3
LOG_Q30 = 1 << 30
LOG_COEF = [int(round((-1) ** k / (k + 1) * LOG_Q30)) for k in range(LOG_TERMS)]
LOG_LN15_Q30 = int(round(np.log(1.5) * LOG_Q30))
LOG_LN2_Q24 = int(round(np.log(2) * (1 << 24)))
LOG_TWO_THIRDS_U32 = int(round(2 / 3 * 2 ** 32))


def _mulh(a, b):
    # high 32 bits of the 64-bit product (vmulh, vmulhsu)
    return (np.asarray(a, dtype=np.int64) * np.int64(b)) >> 32


def ilog(S):
    """Gain = ln(1 + S) in Q16 for an int array S >= 0."""
    x = np.asarray(S, dtype=np.int64) + 1
    assert x.max() < (1 << 32)
    y = x.astype(np.uint32).astype(np.float32).view(np.uint32).astype(np.int64)
    e = (y >> 23) - 127
    f = y & 0x7FFFFF
    u = _mulh((f << 9) - (1 << 31), LOG_TWO_THIRDS_U32)
    p = np.full_like(u, LOG_COEF[-1])
    for c in LOG_COEF[-2::-1]:
        p = c + _mulh(u, p)
    lnm = LOG_LN15_Q30 + _mulh(u, p)
    return check_i32((e * LOG_LN2_Q24 + (lnm >> 6) + 128) >> 8, "Gain")


def select(P, G, res_alloc):
    """Per-user masked argmax of Gain = ln(1 + P * G) (lowest k on ties), then
    the best user with a strict > (lowest user on ties). Returns (Gain, w, k)
    or None."""
    m, n = P.shape
    S = ilog(check_i32(P.astype(np.int64) * G, "P * G"))
    max_gain, w, kw = -1, -1, -1
    for i in range(m):
        best, bk = -1, -1
        for k in range(n):
            if res_alloc[k] == 0 and S[i][k] > best:
                best, bk = S[i][k], k
        if bk >= 0 and best > max_gain:
            max_gain, w, kw = best, i, bk
    if w < 0:
        return None
    return max_gain, w, kw


def update_winner(P, G, res_alloc, user_alloc, delta, w, k_star):
    res_alloc[k_star] = 1
    user_alloc[w][k_star] = 1
    n_w = int(user_alloc[w].sum())
    s = recip_sum(G[w], user_alloc[w])
    delta[w] = div(s, n_w)
    P[w][k_star] = power(delta[w], inv_g(G[w][k_star]))
    for k in range(P.shape[1]):
        if res_alloc[k] == 0:
            ig = inv_g(G[w][k])
            P[w][k] = power(div(s + ig, n_w + 1), ig)


def finalize(P, G, user_alloc, delta):
    m, n = P.shape
    for i in range(m):
        n_i = int(user_alloc[i].sum())
        if n_i == 0:
            continue
        delta[i] = div(recip_sum(G[i], user_alloc[i]), n_i)
        for k in range(n):
            if user_alloc[i][k]:
                P[i][k] = power(delta[i], inv_g(G[i][k]))


def control_algo(R1, R2, A, C, D, trace=None, iters=None):
    """Literal algorithm with the synthetic R/G stages. Returns the outputs
    and, per iteration, the winner (w, k, S). iters < N stops the greedy
    loop early (shorter benchmark runs of the same shape)."""
    n, m = R1.shape
    R2 = R2.copy()
    P = np.full((m, n), P_INIT, dtype=np.int64)
    res_alloc = np.zeros(n, dtype=np.int64)
    user_alloc = np.zeros((m, n), dtype=np.int64)
    delta = [P_SCALE] * m
    winners = []

    for j in range(n if iters is None else iters):
        if res_alloc.all():
            break
        # R does not depend on the user, so it is computed once here
        R = calc_r(R1, R2, C)
        G = calc_g(A, R, D)
        sel = select(P, G, res_alloc)
        if sel is None:
            break
        s_max, w, k_star = sel
        winners.append((w, k_star, int(s_max)))
        update_winner(P, G, res_alloc, user_alloc, delta, w, k_star)
        R2[w] = (R2[w] + j) % 2

    G = calc_g(A, calc_r(R1, R2, C), D)
    finalize(P, G, user_alloc, delta)
    return {"P": P, "ResAllocMap": res_alloc, "UserResAllocMap": user_alloc,
            "R2": R2, "winners": winners}


def paper_example():
    """The example of Kim et al.: M = 2, N = 3 with fixed gains, integer x100
    arithmetic."""
    G = np.array([[8, 4, 2], [4, 2, 1]])
    P = np.full((2, 3), P_INIT, dtype=np.int64)
    res_alloc = np.zeros(3, dtype=np.int64)
    user_alloc = np.zeros((2, 3), dtype=np.int64)
    delta = [P_SCALE] * 2
    order = []
    while not res_alloc.all():
        _, w, k_star = select(P, G, res_alloc)
        order.append((w, k_star))
        if res_alloc.sum() == len(res_alloc) - 1:
            res_alloc[k_star] = 1
            user_alloc[w][k_star] = 1
            break
        update_winner(P, G, res_alloc, user_alloc, delta, w, k_star)
    finalize(P, G, user_alloc, delta)
    return order, P, delta


def self_test():
    # exact values x100 are 68.75, 31.25, 100, 81.25 and 150; integer
    # truncation of each 1/g and each division may lose up to a few units
    order, P, delta = paper_example()
    assert order == [(0, 0), (1, 1), (0, 2)], order
    expect = {(0, 0): 68.75, (0, 2): 31.25, (1, 1): 100}
    for (i, k), v in expect.items():
        assert abs(P[i][k] - v) <= 2, (i, k, P[i][k], v)
    assert abs(delta[0] - 81.25) <= 2 and delta[1] == 150, delta
    return P, delta


if __name__ == "__main__":
    print('paper example (x100):', *self_test())
    for (m, n) in [(2, 3), (8, 16), (48, 100), (80, 100)]:
        out = control_algo(**gen_inputs(m, n, seed=1))
        print(f"M={m:3d} N={n:3d}: {len(out['winners'])} iterations, "
              f"P sum {int(out['P'].sum())}, first winners {out['winners'][:3]}")
    print("golden model self-test passed")
