// Copyright 2025 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Power-update kernel of the control algorithm, on one core (it touches one
// row of N elements per iteration, less work than a barrier):
//
//   - CTRL_CASES updates taken from a golden run at early, middle and late
//     iterations. Each case restores its input state outside the timed
//     region and runs NUM_RUNS times; the last run is hot.
//   - The finalization of all M users on the final state.
//
// Both are checked against the golden model.

#include <benchmark.h>
#include <snrt.h>
#include <stdio.h>

#include DATAHEADER
#include "kernel/power_update.c"

#define NUM_RUNS 2

static int32_t p_row[CTRL_N] __attribute__((section(".data"), aligned(64)));
static int32_t res_alloc[CTRL_N] __attribute__((section(".data"), aligned(64)));
static int32_t ua_row[CTRL_N] __attribute__((section(".data"), aligned(64)));
static int32_t klist[CTRL_N] __attribute__((section(".data"), aligned(64)));
static int32_t delta_fin[CTRL_M] __attribute__((section(".data")));

static void copy(int32_t *dst, const int32_t *src, unsigned int n) {
  for (unsigned int i = 0; i < n; ++i)
    dst[i] = src[i];
}

static int check(const char *name, const int32_t *got, const int32_t *exp,
                 unsigned int n) {
  int err = 0;
  for (unsigned int i = 0; i < n; ++i) {
    if (got[i] != exp[i]) {
      if (err == 0)
        printf("%s[%u] = %d, expected %d\n", name, i, got[i], exp[i]);
      ++err;
    }
  }
  return err;
}

int main() {
  const unsigned int cid = snrt_cluster_vpu_idx();
  int err = 0;

  if (cid == 0) {
    pu_init_tab();
    printf("power update, M %u N %u, 1 core\n", CTRL_M, CTRL_N);

    for (unsigned int c = 0; c < CTRL_CASES; ++c) {
      const unsigned int k = ctrl_case_k[c];
      int32_t nalloc = 0, delta = 0;
      unsigned int cyc = 0;
#pragma clang loop unroll(disable)
      for (int run = 0; run < NUM_RUNS; ++run) {
        copy(p_row, ctrl_case_p + c * CTRL_N, CTRL_N);
        copy(res_alloc, ctrl_case_res + c * CTRL_N, CTRL_N);
        copy(klist, ctrl_case_kl + c * CTRL_N, CTRL_N);
        for (unsigned int i = 0; i < CTRL_N; ++i)
          ua_row[i] = 0;
        nalloc = ctrl_case_nal[c];
        snrt_fence();

        unsigned int t0 = benchmark_get_cycle();
        delta = pu_update(p_row, ctrl_case_g + c * CTRL_N, res_alloc, ua_row,
                          klist, &nalloc, k, CTRL_N);
        snrt_fence();
        cyc = benchmark_get_cycle() - t0;
      }

      int e = check("P", p_row, ctrl_case_p_exp + c * CTRL_N, CTRL_N);
      if (delta != ctrl_case_d_exp[c]) {
        printf("Delta = %d, expected %d\n", delta, ctrl_case_d_exp[c]);
        ++e;
      }
      if (!res_alloc[k] || !ua_row[k] || nalloc != ctrl_case_nal[c] + 1 ||
          klist[nalloc - 1] != (int32_t)k) {
        printf("allocation maps not updated\n");
        ++e;
      }
      printf("iteration %3d: user %2d subcarrier %3d, n %2d -> %2d: %u cycles%s\n",
             ctrl_case_j[c], ctrl_case_w[c], k, ctrl_case_nal[c], nalloc, cyc,
             e ? " MISMATCH" : "");
      err += e;
    }

    // Finalization of all users, NUM_RUNS times on the same input
    unsigned int cyc = 0;
#pragma clang loop unroll(disable)
    for (int run = 0; run < NUM_RUNS; ++run) {
      copy(delta_fin, ctrl_fin_delta, CTRL_M);
      snrt_fence();
      unsigned int t0 = benchmark_get_cycle();
      pu_finalize(ctrl_fin_P, ctrl_fin_G, ctrl_fin_klist, ctrl_fin_nalloc,
                  delta_fin, 0, CTRL_M, CTRL_N);
      snrt_fence();
      cyc = benchmark_get_cycle() - t0;
    }
    int e = check("final P", ctrl_fin_P, ctrl_fin_P_exp, CTRL_M * CTRL_N);
    e += check("final Delta", delta_fin, ctrl_fin_delta_exp, CTRL_M);
    printf("finalization of %u users: %u cycles%s\n", CTRL_M, cyc,
           e ? " MISMATCH" : "");
    err += e;
    printf(err ? "Check Failed!\n" : "Check passed.\n");
  }
  snrt_cluster_hw_barrier();
  return err ? -1 : 0;
}
