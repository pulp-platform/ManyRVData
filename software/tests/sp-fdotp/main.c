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

float *a;
float *b;
float *result;

uint32_t timer = (uint32_t)-1;

int main() {
  const unsigned int num_cores = snrt_cluster_core_num();
  const unsigned int cid = snrt_cluster_core_idx();

  const int measure_iter = 3;

  uint32_t spm_size = 0;

  const unsigned int dim = dotp_l.M / num_cores;

  uint32_t offset = 31 - __builtin_clz(dim * sizeof(float));

  // Allocate the matrices
  if (cid == 0) {
    // Set xbar policy
    l1d_xbar_config(offset);
    // Initialize the cache
    l1d_init(0);
  }

  // Wait for all cores to finish
  snrt_cluster_hw_barrier();

  // Reset timer
  unsigned int timer = (unsigned int)-1;
  unsigned int timer_tmp, timer_iter1;


  float *a_int = dotp_A_dram + dim * cid;
  float *b_int = dotp_B_dram + dim * cid;

  // Wait for all cores to finish
  snrt_cluster_hw_barrier();

  for (int iter = 0; iter < measure_iter; iter ++) {
    // Start dump
    if (cid == 0)
      start_kernel();

    // Start timer
    if (cid == 0)
      timer_tmp = benchmark_get_cycle();

    // Calculate dotp
    float acc;
    acc = fdotp_v32b(a_int, b_int, dim);
    result[cid] = acc;

    // Wait for all cores to finish
    snrt_cluster_hw_barrier();

    // End timer and check if new best runtime
    if (cid == 0) {
      timer_tmp = benchmark_get_cycle() - timer_tmp;
      timer = (timer < timer_tmp) ? timer : timer_tmp;
      if (iter == 0)
        timer_iter1 = timer;
    }

    // Final reduction
    if (cid == 0) {
      // timer_tmp = benchmark_get_cycle() - timer_tmp;
      for (unsigned int i = 1; i < num_cores; ++i)
        acc += result[i];
      result[0] = acc;
    }

    // Wait for all cores to finish
    snrt_cluster_hw_barrier();

    // End dump
    if (cid == 0)
      stop_kernel();

    snrt_cluster_hw_barrier();
  }

  // Check and display results
  if (cid == 0) {
    // The timer did not count the reduction time
    unsigned int performance = 1000 * 2 * dotp_l.M / timer;
    unsigned int perf_iter1  = 1000 * 2 * dotp_l.M / timer_iter1;
    unsigned int utilization = performance / (2 * num_cores * 4);
    unsigned int util_iter1  = perf_iter1  / (2 * num_cores * 4);
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
      // printf("Error: Result = %f, Golden = %f\n", result[0], dotp_result*measure_iter);
      return -1;
    }
  }

  // Wait for core 0 to display the results
  snrt_cluster_hw_barrier();

  return 0;
}