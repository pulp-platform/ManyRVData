// Copyright 2025 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Gain and selection kernel of the control algorithm, on the state of one
// iteration: Gain = ln(1 + P * G) for all M x N elements, then the best user
// and free subcarrier.
//
//   1. ACTIVE_CORES cores split the M user rows; each computes the Gain of
//      its rows and the best key of every column, then a cluster barrier.
//   2. Core 0 merges the cores' column keys and scans the free columns.
//
// Runs NUM_RUNS times (cold, then hot L1). All cores of the cluster check the Gain
// matrix against the golden model; core 0 checks the winner.
//
// IPU utilization of phase 1 = element operations / (cycles * 4 * cores),
// with GAIN_OPS vector operations per element.

#include <benchmark.h>
#include <snrt.h>
#include <stdio.h>

#include DATAHEADER
#include "kernel/gain_select.c"

#ifndef ACTIVE_CORES
#define ACTIVE_CORES 1
#endif

#define NUM_RUNS 3
#define MAX_CORES 1024
#define IPU_LANES 4
// vmul, vadd, vfcvt, vsrl, vand, vsll, vadd, vmulhsu, 3 x (vmulh, vadd),
// vsra, vmacc, vadd, vsra, vsll, vadd, vmax
#define GAIN_OPS 21

static int32_t colkey[ACTIVE_CORES][CTRL_N]
    __attribute__((section(".data"), aligned(64)));
static int errors[MAX_CORES] __attribute__((section(".data")));
static unsigned int cycles[NUM_RUNS][2] __attribute__((section(".data")));

static void split(unsigned int n, unsigned int cid, unsigned int cores,
                  unsigned int *x0, unsigned int *x1) {
  *x0 = n * cid / cores;
  *x1 = n * (cid + 1) / cores;
}

static unsigned int util(unsigned int ops, unsigned int cycles,
                         unsigned int cores) {
  return (unsigned int)(1000ULL * ops /
                        ((unsigned long long)cycles * IPU_LANES * cores));
}

int main() {
  const unsigned int cid = snrt_cluster_vpu_idx();
  const unsigned int num_cores = snrt_cluster_vpu_num();
  const int active = snrt_cluster_is_primary() && cid < ACTIVE_CORES;
  unsigned int r0, r1;
  split(CTRL_M, cid, ACTIVE_CORES, &r0, &r1);
  int w = -1, k = -1, best = -1;

  // Not unrolled: every run executes the same (warm) instructions
#pragma clang loop unroll(disable)
  for (int run = 0; run < NUM_RUNS; ++run) {
    snrt_cluster_hw_barrier();
    unsigned int t0 = benchmark_get_cycle();

    // Phase 1: Gain of this core's rows and its column-best keys
    if (active) {
      gain_rows(ctrl_gain, colkey[cid], ctrl_P, ctrl_G, r0, r1, CTRL_N);
      snrt_fence_spatz();
    }
    snrt_cluster_hw_barrier();
    unsigned int t1 = benchmark_get_cycle();

    // Phase 2: merge the column keys and pick the winner
    if (cid == 0) {
      int32_t key = gain_select(&colkey[0][0], ctrl_res_alloc, ACTIVE_CORES,
                                CTRL_N, &k);
      best = key >> KEY_USER_BITS;
      w = (1 << KEY_USER_BITS) - 1 - (key & ((1 << KEY_USER_BITS) - 1));
      unsigned int t2 = benchmark_get_cycle();
      cycles[run][0] = t1 - t0;
      cycles[run][1] = t2 - t1;
    }
    // keep the other cores (and the check below) off the memory system
    // while core 0 selects
    snrt_cluster_hw_barrier();
  }

  // Printed after all runs, so that no run starts while the UART drains
  if (cid == 0) {
    for (int run = 0; run < NUM_RUNS; ++run) {
      printf("run %d (%s): %u cores, M %u N %u\n", run, run ? "hot" : "cold",
             ACTIVE_CORES, CTRL_M, CTRL_N);
      printf("  gain %u cycles, IPU util %u permille\n", cycles[run][0],
             util(GAIN_OPS * CTRL_M * CTRL_N, cycles[run][0], ACTIVE_CORES));
      printf("  select %u cycles, total %u cycles\n", cycles[run][1],
             cycles[run][0] + cycles[run][1]);
    }
  }

  // Every core of the cluster checks a slice of the Gain matrix
  if (snrt_cluster_is_primary()) {
    unsigned int i0, i1;
    split(CTRL_M * CTRL_N, cid, num_cores, &i0, &i1);
    int err = 0;
    for (unsigned int i = i0; i < i1; ++i) {
      if (ctrl_gain[i] != ctrl_gain_exp[i]) {
        if (err == 0)
          printf("Gain[%u][%u] = %d, expected %d\n", i / CTRL_N, i % CTRL_N,
                 ctrl_gain[i], ctrl_gain_exp[i]);
        ++err;
      }
    }
    errors[cid] = err;
    snrt_fence_snitch();
  }
  snrt_cluster_hw_barrier();

  int total = 0;
  if (cid == 0) {
    for (unsigned int c = 0; c < num_cores; ++c) {
      if (errors[c])
        printf("core %u: %d Gain mismatches\n", c, errors[c]);
      total += errors[c];
    }
    if (w != CTRL_W_EXP || k != CTRL_K_EXP || best != CTRL_GAIN_EXP) {
      printf("winner user %d subcarrier %d gain %d, expected %d %d %d\n", w,
             k, best, CTRL_W_EXP, CTRL_K_EXP, CTRL_GAIN_EXP);
      ++total;
    } else {
      printf("winner user %d subcarrier %d gain %d\n", w, k, best);
    }
    printf(total ? "Check Failed!\n" : "Check passed.\n");
  }
  snrt_cluster_hw_barrier();
  return total ? -1 : 0;
}
