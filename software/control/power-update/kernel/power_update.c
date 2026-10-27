// Copyright 2025 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Power update of the control algorithm (see ../../README.md), integer and
// scaled by 100. After user w wins subcarrier k*, with n its subcarrier
// count and inv(g) = 100 / g:
//
//   sum      = 100 + sum of inv(G[w][k]) over the subcarriers of w
//   Delta[w] = sum / n
//   P[w][k*] = max(0, Delta[w] - inv(G[w][k*]))
//   P[w][k]  = max(0, (sum + inv(G[w][k])) / (n + 1) - inv(G[w][k]))  free k
//
// No division in the vector part: inv(g) is 0 for g > 100, so it is a
// lookup in pu_inv_tab with index min(g, 101); dividing by n + 1 is a
// vmulhu by m = (2^32 - 1) / (n + 1) + 1, exact for numerators up to
// 100 + 128 * 100 + 100 and n + 1 <= 129. Allocated columns keep their P
// through a blend with ResAllocMap instead of a masked store.
//
// The sum runs over the user's subcarrier list (klist, nalloc) in scalar
// code: users hold few subcarriers, so this avoids a vector reduction.

#include <stdint.h>

#include "control.h"

#define PU_TAB_SIZE 102

// pu_inv_tab[g] = 100 / g for 1 <= g <= 100, 0 at 0 and 101
static int32_t pu_inv_tab[PU_TAB_SIZE]
    __attribute__((section(".data"), aligned(64)));

void pu_init_tab(void) {
  pu_inv_tab[0] = 0;
  for (int g = 1; g <= 100; ++g)
    pu_inv_tab[g] = CTRL_P_SCALE / g;
  pu_inv_tab[101] = 0;
}

static inline int32_t pu_inv(int32_t g) {
  return g <= 100 ? pu_inv_tab[g] : 0;
}

static inline unsigned int pu_vl(unsigned int n) {
  unsigned int avl = n < UV_VLMAX ? n : UV_VLMAX;
  unsigned int vl;
  asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(avl));
  return vl;
}

// Update after user w wins subcarrier k. p_row, g_row, ua_row and klist are
// row w of P, G, UserResAllocMap and of the subcarrier lists; nalloc points
// to w's count. Returns the new Delta[w].
int32_t pu_update(int32_t *p_row, const int32_t *g_row, int32_t *res_alloc,
                  int32_t *ua_row, int32_t *klist, int32_t *nalloc,
                  unsigned int k, unsigned int N) {
  res_alloc[k] = 1;
  ua_row[k] = 1;
  const int32_t n = *nalloc + 1;
  klist[n - 1] = k;
  *nalloc = n;
  // the vector loads below must see ResAllocMap[k] = 1
  snrt_fence_snitch();

  int32_t sum = CTRL_P_SCALE;
  for (int32_t j = 0; j < n; ++j)
    sum += pu_inv(g_row[klist[j]]);
  const int32_t delta = sum / n;
  const uint32_t m = 0xFFFFFFFFu / (uint32_t)(n + 1) + 1;

  for (unsigned int p = 0; p < N;) {
    unsigned int vl = pu_vl(N - p);
    // v4 = inv(g). Spatz hangs on vloxei32 with vl % 4 != 0, so the gather
    // runs on vl rounded up to 4 (up to 3 words past the row are read, only
    // as clamped table indices) and the rest on vl.
    if (vl & 3)
      pu_vl((vl + 3) & ~3u);
    asm volatile("vle32.v v0, (%0)" ::"r"(g_row + p));
    asm volatile("vminu.vx v0, v0, %0" ::"r"(PU_TAB_SIZE - 1));
    asm volatile("vsll.vi v0, v0, 2");
    asm volatile("vloxei32.v v4, (%0), v0" ::"r"(pu_inv_tab));
    if (vl & 3)
      pu_vl(vl);
    // v8 = max(0, (sum + inv) / (n + 1) - inv)
    asm volatile("vadd.vx v8, v4, %0" ::"r"(sum));
    asm volatile("vmulhu.vx v8, v8, %0" ::"r"(m));
    asm volatile("vsub.vv v8, v8, v4");
    asm volatile("vmax.vx v8, v8, zero");
    // keep P where allocated: v8 += alloc * (P - v8)
    asm volatile("vle32.v v12, (%0)" ::"r"(res_alloc + p));
    asm volatile("vle32.v v16, (%0)" ::"r"(p_row + p));
    asm volatile("vsub.vv v16, v16, v8");
    asm volatile("vmacc.vv v8, v12, v16");
    asm volatile("vse32.v v8, (%0)" ::"r"(p_row + p) : "memory");
    p += vl;
  }
  // P[w][k] after the vector store of the same row
  snrt_fence_spatz();
  int32_t pk = delta - pu_inv(g_row[k]);
  p_row[k] = pk > 0 ? pk : 0;
  return delta;
}

// Finalization of users [i0, i1): Delta[i] = sum_i / n_i and
// P[i][k] = max(0, Delta[i] - inv(G[i][k])) for the subcarriers of i.
// Users without subcarriers keep their P row and Delta.
void pu_finalize(int32_t *P, const int32_t *G, const int32_t *klist,
                 const int32_t *nalloc, int32_t *delta, unsigned int i0,
                 unsigned int i1, unsigned int N) {
  for (unsigned int i = i0; i < i1; ++i) {
    const int32_t n = nalloc[i];
    if (n == 0)
      continue;
    const int32_t *kl = klist + i * N;
    const int32_t *g = G + i * N;
    int32_t sum = CTRL_P_SCALE;
    for (int32_t j = 0; j < n; ++j)
      sum += pu_inv(g[kl[j]]);
    const int32_t d = sum / n;
    delta[i] = d;
    for (int32_t j = 0; j < n; ++j) {
      int32_t pk = d - pu_inv(g[kl[j]]);
      P[i * N + kl[j]] = pk > 0 ? pk : 0;
    }
  }
}
