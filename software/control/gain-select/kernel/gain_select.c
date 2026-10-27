// Copyright 2025 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Gain and selection kernel of the control algorithm (see ../../README.md):
//
//   Gain[i][k] = ln(1 + P[i][k] * G[i][k])   (Q16, integer, as ilog in
//                                               common/golden.py)
//   (w, k*)    = the user and free subcarrier with the largest Gain; ties go
//                to the lowest user, then the lowest subcarrier
//
// ln is evaluated with 32-bit integer vector operations: the exponent and
// mantissa of 1 + S come from the bits of its float conversion, ln of the
// mantissa from a degree-3 Taylor series around 1.5 in Q30 (Horner with
// vmulh). No precision is specified; the error is below 4.3e-3 in ln.
//
// The selection needs neither masks nor reductions: every row's Gain is
// packed with its user into key = Gain << 7 | (127 - i), and an element-wise
// vmax over rows keeps the best key of every column (largest Gain, lowest
// user). Allocation is per column: subtracting ResAllocMap << 30 pushes the
// allocated columns below every valid key, and a scalar scan over the column
// keys picks the winner.

#include <stdint.h>

#include "control.h"

#define LOG_LN15_Q30 435364845
#define LOG_LN2_Q24 11629080
#define LOG_TWO_THIRDS_U32 2863311531u
// rounding and the -127 exponent bias folded into one constant:
// 128 - 127 * LN2_Q24
#define LOG_BIAS (128 - 127 * LOG_LN2_Q24)
// ln(1 + u) = u * (C0 + C1 u + C2 u^2), Taylor coefficients 1, -1/2, 1/3 in
// Q30
#define LOG_C0 1073741824
#define LOG_C1 (-536870912)
#define LOG_C2 357913941

#define KEY_USER_BITS 7

// One Horner step in v12: p = c + mulh(u, p), u in vu
#define LOG_HORNER(vu, c)                                                      \
  do {                                                                         \
    asm volatile("vmulh.vv v12, " vu ", v12");                                 \
    asm volatile("vadd.vx v12, v12, %0" ::"r"(c));                             \
  } while (0)

// Gain of one row strip from P in vp and G in vg (both clobbered), into v12
// and stored to `gain`; folds the row's keys into the column-best register
// group `acc`. v8 and v12 are scratch.
#define GAIN_CORE_R(vp, vg, acc, gain, ukey)                                   \
  do {                                                                         \
    /* x = P * G + 1 and its float bits */                                     \
    asm volatile("vmul.vv " vp ", " vp ", " vg);                               \
    asm volatile("vadd.vi " vp ", " vp ", 1");                                 \
    asm volatile("vfcvt.f.xu.v " vg ", " vp);                                  \
    /* v8 = biased exponent, vg = u = (m - 1.5) * 2/3 in Q32 */                \
    asm volatile("vsrl.vi v8, " vg ", 23");                                    \
    asm volatile("vand.vx " vg ", " vg ", %0" ::"r"(0x7FFFFF));                \
    asm volatile("vsll.vi " vg ", " vg ", 9");                                 \
    asm volatile("vadd.vx " vg ", " vg ", %0" ::"r"(INT32_MIN));               \
    asm volatile("vmulhsu.vx " vg ", " vg ", %0" ::"r"(LOG_TWO_THIRDS_U32));   \
    /* v12 = ln(1 + u) / u, then ln m, in Q30 */                               \
    asm volatile("vmulh.vx v12, " vg ", %0" ::"r"(LOG_C2));                    \
    asm volatile("vadd.vx v12, v12, %0" ::"r"(LOG_C1));                        \
    LOG_HORNER(vg, LOG_C0);                                                    \
    LOG_HORNER(vg, LOG_LN15_Q30);                                              \
    /* Gain = (e * ln 2 in Q24 + ln m in Q24 + 128) >> 8 */                    \
    asm volatile("vsra.vi v12, v12, 6");                                       \
    asm volatile("vmacc.vx v12, %0, v8" ::"r"(LOG_LN2_Q24));                   \
    asm volatile("vadd.vx v12, v12, %0" ::"r"(LOG_BIAS));                      \
    asm volatile("vsra.vi v12, v12, 8");                                       \
    asm volatile("vse32.v v12, (%0)" ::"r"(gain) : "memory");                  \
    /* key = Gain << 7 | (127 - i) */                                          \
    asm volatile("vsll.vi v12, v12, %0" ::"i"(KEY_USER_BITS));                 \
    asm volatile("vadd.vx v12, v12, %0" ::"r"(ukey));                          \
    asm volatile("vmax.vv " acc ", " acc ", v12");                             \
  } while (0)

#define GAIN_CORE(acc, gain, ukey) GAIN_CORE_R("v0", "v4", acc, gain, ukey)

#define GAIN_ROW(acc, prow, grow, gain, ukey)                                  \
  do {                                                                         \
    asm volatile("vle32.v v0, (%0)" ::"r"(prow));                              \
    asm volatile("vle32.v v4, (%0)" ::"r"(grow));                              \
    GAIN_CORE(acc, gain, ukey);                                                \
  } while (0)

static inline unsigned int gs_vl(unsigned int n) {
  unsigned int avl = n < UV_VLMAX ? n : UV_VLMAX;
  unsigned int vl;
  asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(avl));
  return vl;
}

// Gain of rows [r0, r1) and their column-best keys, stored to colkey[N]
// (N <= 128: the two strips use v16 and v20)
void gain_rows(int32_t *gain, int32_t *colkey, const int32_t *P,
               const int32_t *G, unsigned int r0, unsigned int r1,
               unsigned int N) {
  for (unsigned int p = 0, j = 0; p < N; ++j) {
    unsigned int vl = gs_vl(N - p);
    if (j == 0) {
      asm volatile("vxor.vv v16, v16, v16");
      asm volatile("vadd.vi v16, v16, -1");
    } else {
      asm volatile("vxor.vv v20, v20, v20");
      asm volatile("vadd.vi v20, v20, -1");
    }
    for (unsigned int i = r0; i < r1; ++i) {
      const unsigned int o = i * N + p;
      const int32_t ukey = (1 << KEY_USER_BITS) - 1 - i;
      if (j == 0)
        GAIN_ROW("v16", P + o, G + o, gain + o, ukey);
      else
        GAIN_ROW("v20", P + o, G + o, gain + o, ukey);
    }
    if (j == 0)
      asm volatile("vse32.v v16, (%0)" ::"r"(colkey + p) : "memory");
    else
      asm volatile("vse32.v v20, (%0)" ::"r"(colkey + p) : "memory");
    p += vl;
  }
}

// Merge the column keys of `cores` cores (rows of colkey, stride N) with
// vmax and push allocated columns below every valid key (key - 2^30 < 0),
// then scan. Returns the best key and its column in *k_best (-1 if every
// subcarrier is allocated). The scan keeps GS_SCAN loads in flight, as a
// dependent scalar load costs at least the L1 latency.
#define GS_SCAN 8
int32_t gain_select(int32_t *colkey, const int32_t *res_alloc,
                    unsigned int cores, unsigned int N, int *k_best) {
  for (unsigned int p = 0; p < N;) {
    unsigned int vl = gs_vl(N - p);
    asm volatile("vle32.v v16, (%0)" ::"r"(colkey + p));
    for (unsigned int c = 1; c < cores; ++c) {
      asm volatile("vle32.v v20, (%0)" ::"r"(colkey + c * N + p));
      asm volatile("vmax.vv v16, v16, v20");
    }
    asm volatile("vle32.v v20, (%0)" ::"r"(res_alloc + p));
    asm volatile("vsll.vi v20, v20, 30");
    asm volatile("vsub.vv v16, v16, v20");
    asm volatile("vse32.v v16, (%0)" ::"r"(colkey + p) : "memory");
    p += vl;
  }
  snrt_fence_spatz();

  // strict > in increasing k keeps the lowest column on ties
  int32_t best = -1;
  int kb = -1;
  unsigned int k = 0;
  for (; k + GS_SCAN <= N; k += GS_SCAN) {
    int32_t key[GS_SCAN];
#pragma clang loop unroll(full)
    for (unsigned int j = 0; j < GS_SCAN; ++j)
      key[j] = ((volatile int32_t *)colkey)[k + j];
#pragma clang loop unroll(full)
    for (unsigned int j = 0; j < GS_SCAN; ++j) {
      if (key[j] > best) {
        best = key[j];
        kb = k + j;
      }
    }
  }
  for (; k < N; ++k) {
    if (colkey[k] > best) {
      best = colkey[k];
      kb = k;
    }
  }
  *k_best = kb;
  return best;
}
