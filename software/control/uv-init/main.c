// Copyright 2025 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Kernel 1 of the control algorithm: U = R1 * R2 + C, R = clamp(U), then
// V = A * R + D, G = clamp(V >> G_SHIFT).
//
// The L1 is all-private (L1D_PRIVATE = 1, default) with the private banks
// folded per tile or per group (L1D_FOLD), or all-shared. Private data is
// only visible inside one folding domain, so the work is split by columns
// across domains and by rows inside a domain: V[:, cols] only needs
// R[:, cols], which the same domain computes. R never crosses a domain and
// the barrier between the two products needs no flush. The final check
// flushes the L1 so that every core sees the results.
//
// Runs twice: the first run starts from a cold L1 (the inputs change every
// TTI), the second is hot. Both runs write the same outputs, which all cores
// of the cluster check against the golden model after the second run.
//
// IPU utilization = multiply-accumulates / (cycles * 4 lanes * cores).

#include <benchmark.h>
#include <snrt.h>
#include <stdio.h>

#include DATAHEADER
#include "kernel/uv_init.c"

#ifndef ACTIVE_CORES
#define ACTIVE_CORES 1
#endif

#define NUM_RUNS 2

// L1 configuration, as in kernels/fp/fmatmul-32b/main.c
#ifndef L1D_PRIVATE
#define L1D_PRIVATE 1
#endif
#ifndef L1D_FOLD
#define L1D_FOLD L1D_FOLD_TILE
#endif
// 0 keeps the default bank-select offset
#ifndef XBAR_OFFSET
#define XBAR_OFFSET 0
#endif

// Multiply-accumulates of U = R1 * R2 + C and of V = A * R + D
#define MAC_U (CTRL_N * CTRL_N * CTRL_M)
#define MAC_V (CTRL_M * CTRL_N * CTRL_N)
#define IPU_LANES 4

static int errors[1024] __attribute__((section(".data")));
// first mismatch of each core: offset, got, expected, matrix name
static int32_t bad[1024][4] __attribute__((section(".data")));
static int32_t *first_bad;

// Rows [r0, r1) of `rows` for core lc of `cores`, in blocks of four rows
static void split_rows(unsigned int rows, unsigned int lc, unsigned int cores,
                       unsigned int *r0, unsigned int *r1) {
  unsigned int blocks = (rows + 3) / 4;
  unsigned int b0 = blocks * lc / cores;
  unsigned int b1 = blocks * (lc + 1) / cores;
  *r0 = snrt_min(4 * b0, rows);
  *r1 = snrt_min(4 * b1, rows);
}

// Compare the block rows [r0, r1) x columns [c0, c1) of got and exp. Each
// core checks the block it computed, which its own L1 domain holds, so the
// check needs no flush of the private partition.
static int check(const char *name, const int32_t *got, const int32_t *exp,
                 unsigned int r0, unsigned int r1, unsigned int c0,
                 unsigned int c1, unsigned int cols) {
  int err = 0;
  for (unsigned int i = r0; i < r1; ++i) {
    for (unsigned int j = c0; j < c1; ++j) {
      const unsigned int o = i * cols + j;
      if (got[o] != exp[o]) {
        if (err == 0) {
          first_bad[0] = (int32_t)o;
          first_bad[1] = got[o];
          first_bad[2] = exp[o];
          first_bad[3] = name[0];
        }
        ++err;
      }
    }
  }
  return err;
}

// Utilization in per mille of the peak of `cores` cores
static unsigned int util(unsigned int mac, unsigned int cycles,
                         unsigned int cores) {
  return (unsigned int)(1000ULL * mac / ((unsigned long long)cycles *
                                          IPU_LANES * cores));
}

int main() {
  const unsigned int cid = snrt_cluster_vpu_idx();
  const unsigned int num_cores = snrt_cluster_vpu_num();
  const int active = snrt_cluster_is_primary() && cid < ACTIVE_CORES;

  // Cores per folding domain; the active cores fill whole domains
  const unsigned int domain =
      !L1D_PRIVATE ? ACTIVE_CORES
      : L1D_FOLD == L1D_FOLD_TILE
          ? snrt_cluster_vpu_per_tile()
          : snrt_cluster_vpu_num() / snrt_cluster_group_num();
  const unsigned int dcores = snrt_min(ACTIVE_CORES, domain);
  const unsigned int ndom = ACTIVE_CORES / dcores;
  const unsigned int d = cid / dcores, lc = cid % dcores;
  unsigned int u0, u1, v0, v1;
  split_rows(CTRL_N, lc, dcores, &u0, &u1);
  split_rows(CTRL_M, lc, dcores, &v0, &v1);
  const unsigned int c0 = CTRL_N * d / ndom, c1 = CTRL_N * (d + 1) / ndom;

  // Both calls flush, so run 0 starts from a cold L1 either way
  snrt_cluster_hw_barrier();
  if (XBAR_OFFSET)
    l1d_xbar_config(XBAR_OFFSET);
  if (L1D_PRIVATE)
    l1d_part_folded(snrt_cluster_vpu_per_tile(), L1D_FOLD);

  // Not unrolled: every run executes the same (warm) instructions
#pragma clang loop unroll(disable)
  for (int run = 0; run < NUM_RUNS; ++run) {
    snrt_cluster_hw_barrier();
    unsigned int t0 = benchmark_get_cycle();
    if (cid == 0)
      start_kernel();

    // U = R1 * R2 + C, rows of U split over the cores
    // The outputs are vector stores only: drain Spatz before each barrier
    if (active)
      uv_matmul(ctrl_U, ctrl_R, ctrl_R1, ctrl_R2, ctrl_C, CTRL_N, u0, u1, c0,
                c1, CTRL_M, CTRL_LDA_R1, CTRL_N, UV_MODE_U);
    snrt_fence_spatz();
    snrt_cluster_hw_barrier();
    unsigned int t1 = benchmark_get_cycle();

    // V = A * R + D, rows of V split over the cores
    if (active)
      uv_matmul(ctrl_V, ctrl_G, ctrl_A, ctrl_R, ctrl_D, 0, v0, v1, c0, c1,
                CTRL_N, CTRL_LDA_A, CTRL_N, UV_MODE_V);
    snrt_fence_spatz();
    snrt_cluster_hw_barrier();
    unsigned int t2 = benchmark_get_cycle();

    if (cid == 0) {
      stop_kernel();
      printf("run %d (%s): %u cores, U %ux%ux%u, V %ux%ux%u, L1 %s xbar %d\n",
             run, run ? "hot" : "cold", ACTIVE_CORES, CTRL_N, CTRL_M, CTRL_N,
             CTRL_M, CTRL_N, CTRL_N,
             L1D_PRIVATE ? (L1D_FOLD == L1D_FOLD_TILE ? "tile" : "group")
                         : "shared",
             XBAR_OFFSET);
      printf("  U+R %u cycles, IPU util %u permille\n", t1 - t0,
             util(MAC_U, t1 - t0, ACTIVE_CORES));
      printf("  V+G %u cycles, IPU util %u permille\n", t2 - t1,
             util(MAC_V, t2 - t1, ACTIVE_CORES));
      printf("  total %u cycles, IPU util %u permille\n", t2 - t0,
             util(MAC_U + MAC_V, t2 - t0, ACTIVE_CORES));
    }
  }

  // Write the private banks back so that every checking core sees the
  // results (must be called by all cores)
  // Each active core checks its own block (see check); the per-core error
  // counts are then read by core 0, which needs a flush in private mode
  if (active) {
    first_bad = bad[cid];
    int err = check("U", ctrl_U, ctrl_U_exp, u0, u1, c0, c1, CTRL_N);
    err += check("R", ctrl_R, ctrl_R_exp, u0, u1, c0, c1, CTRL_N);
    err += check("V", ctrl_V, ctrl_V_exp, v0, v1, c0, c1, CTRL_N);
    err += check("G", ctrl_G, ctrl_G_exp, v0, v1, c0, c1, CTRL_N);
    errors[cid] = err;
    snrt_fence_snitch();
  }
  // errors[] and bad[] leave one dirty line per set, which the flush writes
  // back (it loses lines when several ways of a set are dirty)
  if (L1D_PRIVATE)
    l1d_cluster_flush();
  else
    snrt_cluster_hw_barrier();

  int total = 0;
  if (cid == 0) {
    for (unsigned int c = 0; c < num_cores; ++c) {
      if (errors[c])
        printf("core %u: %d mismatches, first %c[%d][%d] = %d, expected %d\n",
               c, errors[c], (char)bad[c][3], bad[c][0] / CTRL_N,
               bad[c][0] % CTRL_N, bad[c][1], bad[c][2]);
      total += errors[c];
    }
    printf(total ? "Check Failed!\n" : "Check passed.\n");
  }
  snrt_cluster_hw_barrier();
  return total ? -1 : 0;
}
