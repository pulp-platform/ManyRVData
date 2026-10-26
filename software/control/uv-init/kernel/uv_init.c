// Copyright 2025 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Kernel 1 of the control algorithm (see ../../README.md): the initial int32
// products
//
//   U = R1 * R2 + C,  R = clamp(U, MinR, MaxR)                 (N x N)
//   V = A * R + D,    G = clamp(V >> G_SHIFT, MinG, MaxG)      (M x N)
//
// Both are out = bias + a * b with a row-major (rows x K, row pitch lda) and
// b row-major (K x P). The scalar loads of a step through four rows at
// once; a pitch of an odd number of cache lines puts the four rows in
// different L1 banks (see kernels/fp/fmatmul-32b/main.c). Each call computes rows [r0, r1) and columns [c0, c1), four rows
// at a time with vmacc.vx, in strips of at most one LMUL-4 register group.
// The accumulators start from the bias rows (C rows for U, D for every row of
// V), so there is no vector move. U and V are stored unclamped because the
// later rank-1 updates need them; R and G are stored clamped.

#include <stdint.h>

#include "control.h"

// Bias row of out row r: C row r (stride P) for U, D (stride 0) for V
#define UV_BIAS(bias, stride, r) ((bias) + (r) * (stride))

// Store the accumulator group `acc` to out_row, clamp it (U -> R, or
// V -> G) and store it to aux_row
#define UV_EPILOGUE(acc, out_row, aux_row)                                     \
  do {                                                                         \
    asm volatile("vse32.v " acc ", (%0)" ::"r"(out_row) : "memory");           \
    if (mode == UV_MODE_RAW) {                                                 \
    } else if (mode == UV_MODE_U) {                                            \
      asm volatile("vmax.vx " acc ", " acc ", %0" ::"r"(CTRL_MIN_R));          \
      asm volatile("vmin.vx " acc ", " acc ", %0" ::"r"(CTRL_MAX_R));          \
    } else {                                                                   \
      asm volatile("vsra.vi " acc ", " acc ", %0" ::"i"(CTRL_G_SHIFT));        \
      asm volatile("vmax.vx " acc ", " acc ", %0" ::"r"(CTRL_MIN_G));          \
      asm volatile("vmin.vx " acc ", " acc ", %0" ::"r"(CTRL_MAX_G));          \
    }                                                                          \
    if (mode != UV_MODE_RAW)                                                   \
      asm volatile("vse32.v " acc ", (%0)" ::"r"(aux_row) : "memory");         \
  } while (0)

// Four rows: accumulators v0, v4, v8, v12; b rows alternate between v16 and
// v20 so the next row loads while the current one is consumed. The a
// elements for the next k are loaded while the vmacc of this k is issued.
static inline void uv_rows4(int32_t *out, int32_t *aux, const int32_t *a,
                            const int32_t *b, const int32_t *bias,
                            unsigned int bias_stride, unsigned int r,
                            unsigned int K, unsigned int lda, unsigned int P,
                            unsigned int p, int mode) {
  const int32_t *a0 = a + r * lda;
  const int32_t *a1 = a0 + lda;
  const int32_t *a2 = a1 + lda;
  const int32_t *a3 = a2 + lda;
  const int32_t *bp = b + p;

  asm volatile("vle32.v v0, (%0)" ::"r"(UV_BIAS(bias, bias_stride, r) + p));
  asm volatile("vle32.v v4, (%0)" ::"r"(UV_BIAS(bias, bias_stride, r + 1) + p));
  asm volatile("vle32.v v8, (%0)" ::"r"(UV_BIAS(bias, bias_stride, r + 2) + p));
  asm volatile("vle32.v v12, (%0)" ::"r"(UV_BIAS(bias, bias_stride, r + 3) + p));
  asm volatile("vle32.v v16, (%0)" ::"r"(bp));

  int32_t t0 = a0[0], t1 = a1[0], t2 = a2[0], t3 = a3[0];
  unsigned int k = 0;
  while (1) {
    // k is even here; b row k is in v16
    unsigned int kn = k + 1;
    if (kn < K)
      asm volatile("vle32.v v20, (%0)" ::"r"(bp + kn * P));
    unsigned int kl = kn < K ? kn : k;
    asm volatile("vmacc.vx v0, %0, v16" ::"r"(t0));
    t0 = a0[kl];
    asm volatile("vmacc.vx v4, %0, v16" ::"r"(t1));
    t1 = a1[kl];
    asm volatile("vmacc.vx v8, %0, v16" ::"r"(t2));
    t2 = a2[kl];
    asm volatile("vmacc.vx v12, %0, v16" ::"r"(t3));
    t3 = a3[kl];
    if (kn == K)
      break;

    // b row kn is in v20
    k = kn + 1;
    if (k < K)
      asm volatile("vle32.v v16, (%0)" ::"r"(bp + k * P));
    kl = k < K ? k : kn;
    asm volatile("vmacc.vx v0, %0, v20" ::"r"(t0));
    t0 = a0[kl];
    asm volatile("vmacc.vx v4, %0, v20" ::"r"(t1));
    t1 = a1[kl];
    asm volatile("vmacc.vx v8, %0, v20" ::"r"(t2));
    t2 = a2[kl];
    asm volatile("vmacc.vx v12, %0, v20" ::"r"(t3));
    t3 = a3[kl];
    if (k == K)
      break;
  }

  int32_t *o = out + r * P + p;
  int32_t *x = aux + r * P + p;
  UV_EPILOGUE("v0", o, x);
  UV_EPILOGUE("v4", o + P, x + P);
  UV_EPILOGUE("v8", o + 2 * P, x + 2 * P);
  UV_EPILOGUE("v12", o + 3 * P, x + 3 * P);
}

// One row, for the rows left over when r1 - r0 is not a multiple of four
static inline void uv_rows1(int32_t *out, int32_t *aux, const int32_t *a,
                            const int32_t *b, const int32_t *bias,
                            unsigned int bias_stride, unsigned int r,
                            unsigned int K, unsigned int lda, unsigned int P,
                            unsigned int p, int mode) {
  const int32_t *a0 = a + r * lda;
  const int32_t *bp = b + p;
  asm volatile("vle32.v v0, (%0)" ::"r"(UV_BIAS(bias, bias_stride, r) + p));
  for (unsigned int k = 0; k < K; ++k) {
    asm volatile("vle32.v v16, (%0)" ::"r"(bp + k * P));
    asm volatile("vmacc.vx v0, %0, v16" ::"r"(a0[k]));
  }
  UV_EPILOGUE("v0", out + r * P + p, aux + r * P + p);
}

void uv_matmul(int32_t *out, int32_t *aux, const int32_t *a, const int32_t *b,
               const int32_t *bias, unsigned int bias_stride, unsigned int r0,
               unsigned int r1, unsigned int c0, unsigned int c1,
               unsigned int K, unsigned int lda, unsigned int P, int mode) {
  for (unsigned int p = c0; p < c1;) {
    // Always an explicit AVL that fits one LMUL-4 group (see spatz quirks)
    unsigned int avl = c1 - p < UV_VLMAX ? c1 - p : UV_VLMAX;
    unsigned int vl;
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(avl));
    unsigned int r = r0;
    for (; r + 4 <= r1; r += 4)
      uv_rows4(out, aux, a, b, bias, bias_stride, r, K, lda, P, p, mode);
    for (; r < r1; ++r)
      uv_rows1(out, aux, a, b, bias, bias_stride, r, K, lda, P, p, mode);
    p += vl;
  }
}

