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
#include <stdio.h>

#include DATAHEADER
#include "kernel/fdotp.c"

// Single-core baseline of fdotp-32b: the whole dot product is computed on
// core 0 only. The other cores fall straight through to `return 0`.
//
// NOTE: no cluster barriers and no l1d_xbar_config() are used here. Those
// helpers issue snrt_cluster_hw_barrier() internally and would deadlock,
// since the remaining cores never reach the barrier.
int main() {
  const uint32_t num_cores = 1;
  const uint32_t cid       = snrt_cluster_core_idx();

  if (cid == 0) {
    const int measure_iter = 3;

    // Byte-level interleaving for DRAM (default 512b), used to keep all DRAM
    // channels busy while a single core streams the whole vector.
    const uint32_t Interleave = 512;
    const uint32_t max_vlen   = 512;
    // Best LMUL setting for the current configuration
    const uint32_t lmul = Interleave * 8 / max_vlen;

    // Each round computes Interleave/4 32-bit elements
    const uint32_t elem_per_round = Interleave * num_cores / 4;
    // How many rounds are needed to cover the whole vector?
    const uint32_t rounds =
        (dotp_l.M > elem_per_round)
            ? ((dotp_l.M + elem_per_round - 1) / elem_per_round)
            : 1;
    const uint32_t dim = elem_per_round / num_cores;

    // Initialize the cache (barrier-free, safe to call from core 0 alone)
    l1d_init(0);

    printf("round:%u, lmul:%u, dim:%u\n", rounds, lmul, dim);

    // Reset timer
    uint32_t timer = (uint32_t)-1;
    uint32_t timer_tmp, timer_iter1 = 0;

    float *a_int = dotp_A_dram + dim * cid;
    float *b_int = dotp_B_dram + dim * cid;

    for (int iter = 0; iter < measure_iter; iter++) {
      // Start dump
      start_kernel();

      // Start timer
      timer_tmp = benchmark_get_cycle();

      // Calculate dotp over the whole vector
      float acc;
      if (lmul >= 8)
        acc = fdotp_v32b_lmul8(a_int, b_int, elem_per_round, dim, rounds);
      else if (lmul >= 4)
        acc = fdotp_v32b_lmul4(a_int, b_int, elem_per_round, dim, rounds);
      else if (lmul >= 2)
        acc = fdotp_v32b_lmul2(a_int, b_int, elem_per_round, dim, rounds);
      else if (lmul >= 1)
        acc = fdotp_v32b_lmul1(a_int, b_int, elem_per_round, dim, rounds);
      else
        return -3;

      // Make sure spatz has finished writing
      snrt_fence_spatz();

      result[cid] = acc;

      // End timer and keep the best runtime
      timer_tmp = benchmark_get_cycle() - timer_tmp;
      timer = (timer < timer_tmp) ? timer : timer_tmp;
      if (iter == 0)
        timer_iter1 = timer;

      stop_kernel();
    }

    // Check and display results
    uint32_t performance = 1000 * 2 * dotp_l.M / timer;
    uint32_t perf_iter1  = 1000 * 2 * dotp_l.M / timer_iter1;
    uint32_t utilization = performance / (2 * num_cores * 4);
    uint32_t util_iter1  = perf_iter1 / (2 * num_cores * 4);
    write_cyc(timer);

    printf("\n----- (%d) sp fdotp (single core) -----\n", dotp_l.M);
    printf("The 1st execution took %u cycles.\n", timer_iter1);
    printf("The performance is %u OP/1000cycle (%u%%o utilization).\n",
           perf_iter1, util_iter1);
    printf("The execution took %u cycles.\n", timer);
    printf("The performance is %u OP/1000cycle (%u%%o utilization).\n",
           performance, utilization);

    // Each iteration recomputes the same full dot product, so result[0]
    // holds a single dot product and must match the golden value directly.
    if (fp_check(result[0], dotp_result)) {
      printf("Check Failed!\n");
      printf("Calc:");
      snrt_printf_float(result[0]);
      printf(", Exp:");
      snrt_printf_float(dotp_result);
      printf("\n");
      return -1;
    }
  }

  return 0;
}
