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

int main() {
  const uint32_t num_cores = snrt_cluster_core_num();
  const uint32_t cid = snrt_cluster_core_idx();

  const uint32_t measure_iter = 3;

  /*** DRAM Parameters for Optimization ***/
  const uint32_t l2_interleave = 16;
  const uint32_t l2_channel    = 4;
  // in bits
  const uint32_t l2_lanewidth  = 512;
  // This is the continuous address block (bits) in DRAM
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
    if (cid == 0) {
      printf("FATAL: Problem size too small!\n");
      return 0;
    }
  }

  uint32_t elem_per_round = lmul * lmul_m1_elem;
  // We need to reduce scrambling size while keeping all channels busy
  // This is needed to reduce the loop control overhead
  uint32_t rounds         = dotp_l.M / elem_per_round / num_cores;


  if ((elem_per_round * num_cores) < (l2_block_elem * l2_channel)) {
    if (cid == 0) {
      printf("Warning: Current scheme cannot utilize all bandwidth!\n");
    }
  }
  
  // We want to map one block for one core to access
  // This will make the cores visiting different DRAM channel
  // Therefore, we need to scramble the L1 xbar at the same size
  // Notice scrambling here is in bytes
  const uint32_t l1_scramble_bits = 31 - __builtin_clz(elem_per_round*32/8);

  if (cid == 0) {
    // Set xbar policy
    l1d_xbar_config(l1_scramble_bits);
    // Initialize the cache
    l1d_init(0);
  }

  snrt_cluster_hw_barrier();

  // Now for all cores, it will execute #elem_per_round# data each round
  // And then jump #elem_per_round*num_cores# elements in address for next round
  uint32_t elem_jump_per_round = elem_per_round * num_cores;

  // Reset timer
  uint32_t timer = (uint32_t)-1;
  uint32_t timer_tmp, timer_iter1;

  // Calculate the starting points for each core
  float *a_int = dotp_A_dram + cid * elem_per_round;
  float *b_int = dotp_B_dram + cid * elem_per_round;

  if (cid == 0) {
    printf("lmul:%u, elem:%u, offs:%u, iter:%u\n", lmul, elem_per_round, elem_jump_per_round, rounds);
  }


  for (int iter = 0; iter < measure_iter; iter ++) {
    // Start dump
    if (cid == 0)
      start_kernel();

    snrt_cluster_hw_barrier();

    // Start timer
    timer_tmp = benchmark_get_cycle();

    // Calculate dotp
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
    }
  }

  // Wait for core 0 to display the results
  snrt_cluster_hw_barrier();

  return 0;
}