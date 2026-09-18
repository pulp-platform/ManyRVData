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
#include <snrt.h>
#include <spatz_lock.h>
#include <stdio.h>

#include DATAHEADER
#include "kernel/fdotp.c"

int main() {
  const uint32_t num_cores = snrt_cluster_vpu_num();
  const uint32_t cid = snrt_cluster_vpu_idx();
  const int is_primary = snrt_cluster_is_primary();

  const uint32_t measure_iter = 3;

  /*** DRAM Parameters for Optimization ***/
  const uint32_t l2_interleave = 16;
  const uint32_t l2_channel    = 4;
  const uint32_t l2_lanewidth  = 512;
  const uint32_t l2_block_size = l2_lanewidth * l2_interleave;
  const uint32_t l2_block_elem = l2_block_size / 32;

  /*** Core Parameters for Optimization ***/
  const uint32_t elem_per_core = dotp_l.M / num_cores;
  const uint32_t lmul_m1       = 512;
  const uint32_t lmul_m1_elem  = lmul_m1 / 32;

  const uint32_t lmul_max      = elem_per_core / lmul_m1_elem;
  uint32_t lmul;
  if (lmul_max >= 8) {
    lmul = 8;
  } else if (lmul_max >= 4) {
    lmul = 4;
  } else if (lmul_max >= 2) {
    lmul = 2;
  } else if (lmul_max == 1) {
    lmul = 1;
  } else {
    if (is_primary && cid == 0) {
      printf("FATAL: Problem size too small!\n");
      return -2;
    }
  }

  uint32_t elem_per_round = lmul * lmul_m1_elem;
  uint32_t rounds         = dotp_l.M / elem_per_round / num_cores;

  if ((elem_per_round * num_cores) < (l2_block_elem * l2_channel)) {
    if (is_primary && cid == 0) {
      printf("Warning: Current scheme cannot utilize all bandwidth!\n");
    }
  }

  const uint32_t l1_scramble_bits = 31 - __builtin_clz(elem_per_round*32/8);

  // Must be called by all cores, so it stays above the is_primary guard below.
  l1d_xbar_config(l1_scramble_bits);

  // Host 1 never touches Spatz or the shared result/timer state in this
  // kernel, so the rest of main() is gated by one check instead of many.
  if (is_primary) {
    uint32_t elem_jump_per_round = elem_per_round * num_cores;

    uint32_t timer = (uint32_t)-1;
    uint32_t timer_tmp, timer_iter1;

    float *a_int = dotp_A_dram + cid * elem_per_round;
    float *b_int = dotp_B_dram + cid * elem_per_round;

    if (cid == 0) {
      printf("lmul:%u, elem:%u, offs:%u, iter:%u\n", lmul, elem_per_round, elem_jump_per_round, rounds);
    }

    // LOCKED mode gives host 0 unarbitrated Spatz access; FREE mode would
    // round-robin-arbitrate with host 1 even though it never issues here.
    spatz_lock_acquire();

    for (int iter = 0; iter < measure_iter; iter ++) {
      if (cid == 0)
        start_kernel();

      snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);

      timer_tmp = benchmark_get_cycle();

      float acc;

      if (lmul >= 8)
        acc = fdotp_v32b_lmul8(a_int, b_int, elem_jump_per_round, elem_per_round, rounds);
      else if (lmul >= 4)
        acc = fdotp_v32b_lmul4(a_int, b_int, elem_jump_per_round, elem_per_round, rounds);
      else if (lmul >= 2)
        acc = fdotp_v32b_lmul2(a_int, b_int, elem_jump_per_round, elem_per_round, rounds);
      else if (lmul >= 1)
        acc = fdotp_v32b_lmul1(a_int, b_int, elem_jump_per_round, elem_per_round, rounds);
      else
        return -3;

      result[cid] = acc;

      snrt_fence_spatz();
      snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);

      if (cid == 0) {
        timer_tmp = benchmark_get_cycle() - timer_tmp;
        timer = (timer < timer_tmp) ? timer : timer_tmp;
        if (iter == 0)
          timer_iter1 = timer;

        stop_kernel();
      }

      // Two-level reduction tree, group size 4.
      const uint32_t red_group = 4;

      if (cid % red_group == 0) {
        for (uint32_t i = 1; i < red_group && (cid + i) < num_cores; ++i)
          acc += result[cid + i];
        result[cid] = acc;
      }

      snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);

      if (cid == 0) {
        for (uint32_t g = red_group; g < num_cores; g += red_group)
          acc += result[g];
        result[0] = acc;
      }
    }

    if (cid == 0) {
      // timer excludes the reduction above.
      uint32_t performance = 1000 * 2 * dotp_l.M / timer;
      uint32_t perf_iter1  = 1000 * 2 * dotp_l.M / timer_iter1;
      uint32_t utilization = performance / (2 * num_cores * 4);
      uint32_t util_iter1  = perf_iter1  / (2 * num_cores * 4);
      write_cyc(timer);

      printf("\n----- (%d) sp fdotp -----\n", dotp_l.M);
      printf("The 1st execution took %u cycles.\n", timer_iter1);
      printf("The performance is %u OP/1000cycle (%u%%o utilization).\n",
             perf_iter1 , util_iter1);
      printf("The execution took %u cycles.\n", timer);
      printf("The performance is %u OP/1000cycle (%u%%o utilization).\n",
             performance, utilization);
    }

    if (cid == 0) {
      if (fp_check(result[0], dotp_result*measure_iter)) {
        printf("Check Failed!\n");
        printf("Calc:");
        snrt_printf_float(result[0]);
        printf(", Exp:");
        snrt_printf_float((float)(dotp_result * measure_iter));
        printf("\n");
        return -1;
      }
    }

    snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);

    // main()'s epilogue restores fs0 unconditionally, even for host 1.
    spatz_lock_release();
  }

  // Explicit closing barrier instead of relying on the implicit post-main() one.
  snrt_cluster_hw_barrier();

  return 0;
}
