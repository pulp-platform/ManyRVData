// Copyright 2025 ETH Zurich and University of Bologna.
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

// Author: Diyou Shen,              ETH Zurich <dishen@iis.ee.ethz.ch>

#include <benchmark.h>
#include <snrt.h>
#include <spatz_lock.h>
#include <stdio.h>
#include <l1cache.h>

#include "kernel/gemv.c"
#include DATAHEADER

// y = A * x with A: M x N, x: N, y: M, all fp32.
//
// Each active core owns 16 * lmul rows over all N columns, so there is no
// reduction. Both modes run with tile-private L1 and xbar offset 8, where the
// controller is addr[8 +: log2(cores per tile)]: core k of a tile only touches
// 256 B blocks of its own controller k, so the cores of a tile never contend
// for a controller and an m4 vector load hits a single one. The data header
// picks the layout (script/gen_data.py):
//
// hot: consecutive blocks of a tile are (tiles + 1) chunks apart, which spreads
//   the tiles over all HBM channels and every set of the controller, so A
//   stays resident in L1. Best when A is already in L1.
//
// cold: each group reads only its own HBM channel, chan_of_group[g], chosen
//   against the refill-mesh routes so that no mesh link carries more than one
//   channel's traffic. A tile then reaches only a few controller sets, so the
//   mode runs a single (cold) iteration.

// addr[8 +: log2(cores per tile)] selects the controller: 256 B (one m4
// vector) per controller.
#ifndef XBAR_OFFSET
#define XBAR_OFFSET 8
#endif
// Number of private banks per tile (0 = all-shared) and how they are folded.
// Both layouts are built for every bank private to its own tile.
#ifndef L1D_PART
#define L1D_PART cores_per_tile
#endif
#ifndef L1D_FOLD
#define L1D_FOLD L1D_FOLD_TILE
#endif

// Timed iterations: the first runs on a cold L1, the rest on a hot one. Cold
// mode only needs the first, and its hot iterations are slow to simulate.
#ifndef MEASURE_ITER
#define MEASURE_ITER 3
#endif
#ifndef COLD_MEASURE_ITER
#define COLD_MEASURE_ITER 1
#endif

// Upper bound on cores, for the per-core error slots
#define MAX_CORES 256

// Per-core error counts of the result check; every core fills its own slot.
static int core_errors[MAX_CORES] __attribute__((section(".data")));
static int num_errors __attribute__((section(".data")));

static inline int fp_check(const float a, const float b) {
  const float threshold = 0.001f;

  float comp = a - b;
  if (comp < 0)
    comp = -comp;

  return comp > threshold;
}

// Float offset of a core's block in row 0 of the hot A, x and y layouts:
// tile t's chunk of cores_per_tile blocks, then core k's block.
static inline uint32_t core_offset_hot(const uint32_t cid) {
  return cid * GEMV_CTRL_FLOATS;
}

// Float offset of a core's block in the first stripes of the cold A, x and y
// layouts: core q of group g sits in stripe q / 4, in the 1 KiB slot of the
// group's channel, at block q % 4.
static inline uint32_t core_offset_cold(const uint32_t cid, const uint32_t cpg,
                                        const uint32_t stripe) {
  const uint32_t q = cid % cpg;
  return (q / 4) * stripe + gemv_chan_of_group[cid / cpg] * GEMV_CHUNK_FLOATS +
         (q % 4) * GEMV_CTRL_FLOATS;
}

int main() {
  const uint32_t num_cores      = snrt_cluster_vpu_num();
  const uint32_t cores_per_tile = snrt_cluster_vpu_per_tile();
  const uint32_t num_groups     = snrt_cluster_group_num();
  const uint32_t cores_per_grp  = num_cores / num_groups;
  const uint32_t cid            = snrt_cluster_vpu_idx();
  const int      is_primary     = snrt_cluster_is_primary();

  const uint32_t lmul         = gemv_l.lmul;
  const uint32_t rows         = GEMV_LINE_FLOATS * lmul;
  const uint32_t active_cores = gemv_l.groups * cores_per_grp;
  const int      cold         = (gemv_l.mode == GEMV_MODE_COLD);
  // Cold: one 1 KiB slot per HBM channel in a stripe
  const uint32_t stripe       = gemv_l.channels * GEMV_CHUNK_FLOATS;
  // Distance between a core's consecutive blocks.
  // Hot: one chunk per active tile plus one empty chunk.
  // Cold: a group's column spans cores_per_grp / 4 stripes.
  const uint32_t row          = cold ? (cores_per_grp / 4) * stripe
                                     : (active_cores / cores_per_tile + 1) *
                                       cores_per_tile * GEMV_CTRL_FLOATS;

  // Reject anything the data was not generated for.
  if (gemv_l.cores_per_tile != cores_per_tile ||
      gemv_l.tiles_per_group != cores_per_grp / cores_per_tile ||
      num_cores > MAX_CORES || gemv_l.groups > num_groups ||
      gemv_l.M != active_cores * rows || (gemv_l.N % GEMV_CTRL_FLOATS) != 0 ||
      (cold && (lmul != 4 || (cores_per_grp % 4) != 0))) {
    if (is_primary && cid == 0)
      printf("FATAL: data (mode %u, groups %u, lmul %u, channels %u) does not fit this config\n",
             gemv_l.mode, gemv_l.groups, lmul, gemv_l.channels);
    return -1;
  }

  const uint32_t xbar_offset = XBAR_OFFSET;
  const uint32_t l1_part     = L1D_PART;
  const uint32_t l1_fold     = L1D_FOLD;
  l1d_xbar_config(xbar_offset);
  l1d_part_folded(l1_part, l1_fold);

  const uint32_t offset = cold ? core_offset_cold(cid, cores_per_grp, stripe)
                               : core_offset_hot(cid);
  const float *a_core = (const float *)gemv_A_dram + offset;
  const float *x_core = (const float *)gemv_B_dram + offset;
  float       *y_core = (float *)gemv_Y_dram + offset;

  // Host 1 never touches Spatz or the shared timer state in this kernel, so
  // the timed region is gated by one check instead of many.
  if (is_primary) {
    const uint32_t iters = cold ? COLD_MEASURE_ITER : MEASURE_ITER;
    uint32_t timer_cold = 0;
    uint32_t timer_hot  = (uint32_t)-1;

    // LOCKED mode gives host 0 unarbitrated Spatz access; FREE mode would
    // round-robin-arbitrate with host 1 even though it never issues here.
    spatz_lock_acquire();

    for (uint32_t i = 0; i < iters; ++i) {
      if (cid == 0)
        start_kernel();

      snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);

      uint32_t timer = benchmark_get_cycle();

      if (cid < active_cores) {
        if (lmul == 2)
          gemv_v32b_m2(a_core, x_core, y_core, gemv_l.N, row);
        else
          gemv_v32b(a_core, x_core, y_core, gemv_l.N, lmul, row);
      }

      snrt_fence_spatz();
      snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);

      timer = benchmark_get_cycle() - timer;

      if (cid == 0) {
        stop_kernel();
        if (i == 0)
          timer_cold = timer;
        else if (timer < timer_hot)
          timer_hot = timer;
      }
    }

    if (cid == 0) {
      // 64-bit FLOP and byte counts: 1000 * 2 * M * N overflows 32 bits.
      const uint64_t flops = 2ULL * gemv_l.M * gemv_l.N;
      const uint64_t bytes = 4ULL * gemv_l.M * gemv_l.N;

      const uint32_t perf_cold = (uint32_t)(1000ULL * flops / timer_cold);
      const uint32_t util_cold = perf_cold / (2 * active_cores * 4);
      // A bytes moved per 10 cycles, printed with one decimal
      const uint32_t bw_cold   = (uint32_t)(10ULL * bytes / timer_cold);

      write_cyc(iters > 1 ? timer_hot : timer_cold);
      printf("\n----- (%u x %u) x (%u x 1) gemv-opt -----\n", gemv_l.M,
             gemv_l.N, gemv_l.N);
      printf("Mode %s: active cores %u (groups %u), lmul %u, L1 part %u fold %u xbar %u\n",
             cold ? "cold" : "hot", active_cores, gemv_l.groups, lmul,
             l1_part, l1_fold, xbar_offset);
      printf("Cold: %u cycles, %u OP/1000cycle (%u%%o utilization), %u.%u B/cycle\n",
             timer_cold, perf_cold, util_cold, bw_cold / 10, bw_cold % 10);
      if (iters > 1) {
        const uint32_t perf_hot = (uint32_t)(1000ULL * flops / timer_hot);
        const uint32_t util_hot = perf_hot / (2 * active_cores * 4);
        const uint32_t bw_hot   = (uint32_t)(10ULL * bytes / timer_hot);
        printf("Hot:  %u cycles, %u OP/1000cycle (%u%%o utilization), %u.%u B/cycle\n",
               timer_hot, perf_hot, util_hot, bw_hot / 10, bw_hot % 10);
      }
    }

    // main()'s epilogue restores callee-saved FP registers unconditionally, even for host 1.
    spatz_lock_release();
  }

  // Back to all-shared: this writes the private y lines back to DRAM and
  // makes them, and num_errors, visible to every core. Called by all cores;
  // in cold mode it only flushes.
  l1d_part(0);

  // Every active core checks its own rows; core 0 then adds up the counts.
  if (is_primary && cid < active_cores) {
    int errors = 0;
    for (uint32_t i = cid * rows; i < (cid + 1) * rows; ++i) {
      const uint32_t r = i % rows;
      const uint32_t idx = (cold ? core_offset_cold(cid, cores_per_grp, stripe)
                                 : core_offset_hot(cid)) + r;
      if (fp_check(((const float *)gemv_Y_dram)[idx], gemv_result[i]))
        errors++;
    }
    core_errors[cid] = errors;
  }

  snrt_cluster_hw_barrier();

  if (is_primary && cid == 0) {
    int errors = 0;
    for (uint32_t c = 0; c < active_cores; ++c) {
      if (core_errors[c])
        printf("Core %u: %d wrong rows\n", c, core_errors[c]);
      errors += core_errors[c];
    }
    if (errors)
      printf("%d errors\n", errors);
    num_errors = errors;
  }

  // Explicit closing barrier instead of relying on the implicit post-main() one.
  snrt_cluster_hw_barrier();

  return (num_errors > 0) ? -1 : 0;
}
