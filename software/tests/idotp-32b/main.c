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
#include "kernel/idotp.c"

int main() {
  const uint32_t num_cores = snrt_cluster_core_num();
  const uint32_t cid = snrt_cluster_core_idx();

  const int measure_iter = 3;

  // Byte-level interleaving for DRAM
  // Default setting is 1024b (128 Byte)
  // This is used to ensure we can utilze all four channels to DRAM
  const uint32_t Interleave   = 512;
  const uint32_t max_vlen     = 512;
  // Calculate the best lmul setting for current configuration
  const uint32_t lmul         = Interleave * 8 / max_vlen;


  // Each round we can calculate Interleave/4 32b-elements
  const uint32_t elem_per_round = Interleave * num_cores / 4;
  // how many rounds do we need to finish executing?
  const uint32_t rounds = (dotp_l.M > elem_per_round) ? ((dotp_l.M + elem_per_round - 1) / elem_per_round) : 1;

  const uint32_t dim = elem_per_round / num_cores;

  uint32_t offset = 31 - __builtin_clz(dim * sizeof(int));

  if (cid == 0) {
    // Set xbar policy
    l1d_init(0);
    l1d_xbar_config(offset);
    // Initialize the cache

    printf ("round:%u, lmul:%u, dim:%u\n", rounds, lmul, dim);
  }

  snrt_cluster_hw_barrier();

  // Reset timer
  uint32_t timer = (uint32_t)-1;
  uint32_t timer_tmp, timer_iter1;


  int *a_int = dotp_A_dram + dim * cid;
  int *b_int = dotp_B_dram + dim * cid;

  for (int iter = 0; iter < measure_iter; iter ++) {
    // Start dump
    if (cid == 0)
      start_kernel();

    snrt_cluster_hw_barrier();

    // Start timer
    timer_tmp = benchmark_get_cycle();

    // Calculate dotp
    int acc;

    if (lmul >= 8)
      acc = idotp_v32b_lmul8(a_int, b_int, elem_per_round, dim, rounds);
    else if (lmul >= 4)
      acc = idotp_v32b_lmul4(a_int, b_int, elem_per_round, dim, rounds);
    else if (lmul >= 2)
      acc = idotp_v32b_lmul2(a_int, b_int, elem_per_round, dim, rounds);
    else if (lmul >= 1)
      acc = idotp_v32b_lmul1(a_int, b_int, elem_per_round, dim, rounds);
    else
      return 0;

    result[cid] = acc;

    // Wait for all cores to finish
    snrt_cluster_hw_barrier();

    // End timer and check if new best runtime
    if (cid == 0) {
      timer_tmp = benchmark_get_cycle() - timer_tmp;
      timer = (timer < timer_tmp) ? timer : timer_tmp;
      if (iter == 0)
        timer_iter1 = timer;

      stop_kernel();
    }

    // Final reduction
    if (cid == 0) {
      // timer_tmp = benchmark_get_cycle() - timer_tmp;
      for (uint32_t i = 1; i < num_cores; ++i)
        acc += result[i];
      result[0] = acc;
    }

  }

  snrt_cluster_hw_barrier();

  // Check and display results
  if (cid == 0) {
    // The timer did not count the reduction time
    uint32_t performance = 1000 * 2 * dotp_l.M / timer;
    uint32_t perf_iter1  = 1000 * 2 * dotp_l.M / timer_iter1;
    uint32_t utilization = performance / (2 * num_cores * 4);
    uint32_t util_iter1  = perf_iter1  / (2 * num_cores * 4);
    write_cyc(timer);

    printf("\n----- (%d) 32b idotp -----\n", dotp_l.M);
    printf("The 1st execution took %u cycles.\n", timer_iter1);
    printf("The performance is %u OP/1000cycle (%u%%o utilization).\n",
           perf_iter1 , util_iter1);
    printf("The execution took %u cycles.\n", timer);
    printf("The performance is %u OP/1000cycle (%u%%o utilization).\n",
           performance, utilization);
  }

  if (cid == 0) {
    if (result[0] != dotp_result_golden*measure_iter) {
      printf("Check Failed!\n");
    }
  }

  // Wait for core 0 to display the results
  snrt_cluster_hw_barrier();

  return 0;
}