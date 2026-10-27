// Copyright 2022 ETH Zurich and University of Bologna.
//
// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Author: Diyou Shen     <dishen@iis.ee.ethz.ch>

#include <benchmark.h>
#include <l1cache.h>
#include <snrt.h>
#include <spatz_lock.h>
#include <stdio.h>

#include DATAHEADER
#include "kernel/fdotp.c"

// sum(a * b) over M floats. Core c owns chunks c, c + cores, c + 2 * cores, ...
// of LMUL * VLEN / 32 elements each, reduces its partial inside the vector register and
// then across cores.

// LMUL of the accumulation (1, 2, 4 or 8)
#ifndef DOTP_LMUL
#define DOTP_LMUL 8
#endif
// 1: one register set; 2: two register sets, LMUL 4 at most
#ifndef DOTP_UNROLL
#define DOTP_UNROLL 1
#endif
// In-vector reduction, see kernel/fdotp.h
#ifndef DOTP_VRED
#define DOTP_VRED FDOTP_VRED_FOLD
#endif
// Cross-core reduction. 0: groups of 4, then core 0 adds the group sums;
// 1: binary tree over per-core slots, neighbours first. 1 polls slots that
// other cores write in the same L1 line and gives wrong sums on the current
// L1, so 0 is the default.
#ifndef DOTP_XRED
#define DOTP_XRED 0
#endif
// Number of private banks per tile (0 = all-shared) and how they are folded
#ifndef L1D_PART
#define L1D_PART 0
#endif
#ifndef L1D_FOLD
#define L1D_FOLD L1D_FOLD_TILE
#endif

#define MEASURE_ITER 3

// Upper bound on cores, for the per-core slots
#define MAX_CORES 256

// Empty slot marker: a NaN no partial sum of valid data produces
#define SLOT_EMPTY 0xFFFFFFFFu

// Tree reduction mailboxes: core c publishes its subtree sum in slot c, and
// its parent empties it again after reading.
static volatile uint32_t dotp_slot[MAX_CORES]
    __attribute__((section(".data"))) = {[0 ... MAX_CORES - 1] = SLOT_EMPTY};
// Partials of the two-level reduction
static float dotp_part[MAX_CORES] __attribute__((section(".data")));

static int num_errors __attribute__((section(".data")));

static inline int fp_check(const float a, const float b) {
  const float threshold = 0.01f;

  float comp = a - b;
  if (comp < 0)
    comp = -comp;

  return comp > threshold;
}

static inline uint32_t f2u(const float f) {
  union { float f; uint32_t u; } v = {.f = f};
  return v.u;
}

static inline float u2f(const uint32_t u) {
  union { float f; uint32_t u; } v = {.u = u};
  return v.f;
}

// Binary tree: at level s, core c with bit s set hands its sum to core c - s.
// Returns the full sum on core 0.
static inline float reduce_tree(float acc, const uint32_t cid,
                                const uint32_t num_cores) {
  for (uint32_t s = 1; s < num_cores; s <<= 1) {
    if (cid & s) {
      dotp_slot[cid] = f2u(acc);
      break;
    }
    if (cid + s < num_cores) {
      uint32_t v;
      while ((v = dotp_slot[cid + s]) == SLOT_EMPTY)
        ;
      dotp_slot[cid + s] = SLOT_EMPTY;
      acc += u2f(v);
    }
  }
  return acc;
}

// Groups of 4 under a barrier, then core 0 adds the group sums. Every
// partial is already in dotp_part, behind a barrier.
static inline float reduce_two_level(float acc, const uint32_t cid,
                                     const uint32_t num_cores) {
  const uint32_t red_group = 4;

  if (cid % red_group == 0) {
    for (uint32_t i = 1; i < red_group && (cid + i) < num_cores; ++i)
      acc += dotp_part[cid + i];
    dotp_part[cid] = acc;
    snrt_fence_snitch();
  }

  snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);

  if (cid == 0)
    for (uint32_t g = red_group; g < num_cores; g += red_group)
      acc += dotp_part[g];
  return acc;
}

// 2 * M operations against 4 FPUs per core, 2 operations each
static void print_perf(const char *name, const uint32_t cycles,
                       const uint32_t m, const uint32_t num_cores) {
  const uint32_t perf = 1000 * 2 * m / cycles;
  printf("%s: %u cycles, %u OP/1000cycle (%u%%o utilization).\n", name,
         cycles, perf, perf / (2 * num_cores * 4));
}

int main() {
  const uint32_t num_cores      = snrt_cluster_vpu_num();
  const uint32_t cores_per_tile = snrt_cluster_vpu_per_tile();
  const uint32_t cid            = snrt_cluster_vpu_idx();
  const int      is_primary     = snrt_cluster_is_primary();

  // VLEN in floats
  uint32_t vlenb;
  asm volatile("csrr %0, vlenb" : "=r"(vlenb));
  const uint32_t vlen_elem = vlenb / sizeof(float);

  const uint32_t elem_per_core = dotp_l.M / num_cores;

  const uint32_t lmul           = DOTP_LMUL;
  const uint32_t unroll         = (DOTP_UNROLL == 2 && lmul <= 4) ? 2 : 1;
  const uint32_t elem_per_round = lmul * vlen_elem;
  const uint32_t rounds         = elem_per_core / elem_per_round;
  const uint32_t offset         = elem_per_round * num_cores;

  if (num_cores > MAX_CORES || rounds == 0 ||
      rounds * elem_per_round != elem_per_core) {
    if (is_primary && cid == 0)
      printf("FATAL: M %u does not split into %u cores x %u elements\n",
             dotp_l.M, num_cores, elem_per_round);
    return -2;
  }

  // One stripe of all cores' chunks should cover every HBM channel
  const uint32_t l2_stripe = SNRT_L2_CHANNEL * SNRT_L2_INTERLEAVE *
                             SNRT_L2_BANK_WIDTH / 8;
  if (is_primary && cid == 0 && offset * sizeof(float) < l2_stripe)
    printf("Warning: a stripe of %u B is below the %u B HBM stripe\n",
           offset * (uint32_t)sizeof(float), l2_stripe);

  // A core's chunk is one L1 controller block, so core k of a tile streams
  // through controller k.
  const uint32_t xbar_offset = 31 - __builtin_clz(elem_per_round * sizeof(float));

  // Must be called by all cores, so it stays above the is_primary guard below.
  l1d_xbar_config(xbar_offset);
#ifndef ISO_NO_PART
  l1d_part_folded(L1D_PART, L1D_FOLD);
#endif

  // Host 1 never touches Spatz or the shared result/timer state in this
  // kernel, so the rest of main() is gated by one check instead of many.
  if (is_primary) {
    const float *a = (const float *)dotp_A_dram + cid * elem_per_round;
    const float *b = (const float *)dotp_B_dram + cid * elem_per_round;

    // Cycles up to the per-core partials, and in total with the cross-core
    // reduction
    uint32_t part_cold  = 0;
    uint32_t part_hot   = (uint32_t)-1;
    uint32_t timer_cold = 0;
    uint32_t timer_hot  = (uint32_t)-1;
    int errors = 0;

    if (cid == 0)
      printf("lmul %u, unroll %u, vred %u, xred %u, L1 part %u fold %u, "
             "xbar %u, elem %u, offs %u, rounds %u\n",
             lmul, unroll, DOTP_VRED, DOTP_XRED, L1D_PART, L1D_FOLD,
             xbar_offset, elem_per_round, offset, rounds);

    // LOCKED mode gives host 0 unarbitrated Spatz access; FREE mode would
    // round-robin-arbitrate with host 1 even though it never issues here.
    spatz_lock_acquire();

    for (uint32_t iter = 0; iter < MEASURE_ITER; iter++) {
      if (cid == 0)
        start_kernel();

      // The fence publishes the slots emptied in the previous iteration
      asm volatile("fence" ::: "memory");
      snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);

      uint32_t timer = benchmark_get_cycle();

      float acc = fdotp_v32b(a, b, elem_per_round, offset, rounds, lmul,
                             unroll, DOTP_VRED);

      // Every core has its partial: the end of the part that scales with M
      dotp_part[cid] = acc;
      snrt_fence_snitch();
      snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);
      const uint32_t part = benchmark_get_cycle() - timer;

      if (DOTP_XRED)
        acc = reduce_tree(acc, cid, num_cores);
      else
        acc = reduce_two_level(acc, cid, num_cores);

      // Core 0 holds the full sum, so every core has finished its part
      if (cid == 0) {
        timer = benchmark_get_cycle() - timer;
        stop_kernel();

        if (iter == 0) {
          part_cold  = part;
          timer_cold = timer;
        } else {
          if (part < part_hot)
            part_hot = part;
          if (timer < timer_hot)
            timer_hot = timer;
        }

        if (fp_check(acc, dotp_result)) {
          errors++;
          printf("Iteration %u: check failed. Calc:", iter);
          snrt_printf_float(acc);
          printf(", Exp:");
          snrt_printf_float(dotp_result);
          printf("\n");
        }
      }
    }

    if (cid == 0) {
      write_cyc(timer_hot);

      printf("\n----- (%u) sp fdotp -----\n", dotp_l.M);
      // Up to the per-core partials: the measure for a long vector, where
      // the cross-core reduction is negligible
      print_perf("Partials, 1st execution", part_cold, dotp_l.M, num_cores);
      print_perf("Partials", part_hot, dotp_l.M, num_cores);
      // With the cross-core reduction: the cost of one dot product
      print_perf("Total, 1st execution", timer_cold, dotp_l.M, num_cores);
      print_perf("Total", timer_hot, dotp_l.M, num_cores);
      if (errors)
        printf("Check Failed!\n");
      num_errors = errors;
    }

    // main()'s epilogue restores fs0 unconditionally, even for host 1.
    spatz_lock_release();
  }

  // Explicit closing barrier instead of relying on the implicit post-main() one.
  snrt_cluster_hw_barrier();

  return (num_errors > 0) ? -1 : 0;
}
