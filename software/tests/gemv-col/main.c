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

// Author: Navaneeth Kunhi Purayil, ETH Zurich <nkunhi@iis.ee.ethz.ch>

#include <benchmark.h>
#include <snrt.h>
#include <stdio.h>
#include <l1cache.h>

#include "kernel/gemv.c"
#include DATAHEADER

#if (PREC == 64)
#define T double
#elif (PREC == 32)
#define T float
#elif (PREC == 16)
#define T __fp16
#else
#define T float
#endif

#define SNRT_NFPU_PER_CORE 4


static inline int fp_check(const T *a, const T *b) {
  const T threshold = 0.001;

  // Absolute value
  float comp = (float)*a - (float)*b;
  if (comp < 0)
    comp = -comp;

  return comp > threshold;
}

int main() {
  T *a;
  T *b;
  T *result;

  const unsigned int num_cores = snrt_cluster_core_num();
  const unsigned int cid = snrt_cluster_core_idx();

  unsigned int m_core = gemv_l.M / num_cores;

  uint32_t offset = 31 - __builtin_clz(m_core * sizeof(T));

  // Allocate the matrices
  if (cid == 0) {
    // Set xbar policy
    l1d_xbar_config(offset);
  }
  
  // Reset timer
  unsigned int timer = (unsigned int) - 1;

  // Unroll in M direction?
  int unroll_m = 0;

  a = gemv_A_dram;
  b = gemv_B_dram;
  result = gemv_result;

  // Calculate internal pointers
  T *a_core = a + m_core * cid;
  T *result_core = result + m_core * cid;

  // Wait for all cores to finish
  snrt_cluster_hw_barrier();


  for (int i = 0; i < 3; i++) {

    // Start dump
    if (cid == 0) {
      start_kernel();
    }

    // Start timer
    if (cid == 0) {
      timer = benchmark_get_cycle();
    }

    // Calculate gemv
    if (sizeof(T) == 8)
      // does not support 64b
      return -2;
    else if (sizeof(T) == 4)
      gemv_v32b_m4(a_core, b, result_core, gemv_l.M, m_core, gemv_l.N);
    else 
      gemv_v16b_m4(a_core, b, result_core, gemv_l.M, m_core, gemv_l.N);

    // Wait for all cores to finish
    snrt_cluster_hw_barrier();

    // End dump
    if (cid == 0) {
      stop_kernel();
      // printf("Core%d: 4\n", cid);
    }

    // End timer and check if new best runtime
    if (cid == 0)
      timer = benchmark_get_cycle() - timer;

  }

  // Check and display results
  if (cid == 0) {
    long unsigned int performance = 1000 * 2 * gemv_l.M * gemv_l.N / timer;
    long unsigned int utilization =
        performance / (2 * num_cores * SNRT_NFPU_PER_CORE * (4 / sizeof(T)));

    printf("\n----- (%d x %d) x (%d x 1) gemv -----\n", gemv_l.M, gemv_l.N, gemv_l.N);
    printf("The execution took %u cycles.\n", timer);
    printf("The performance is %ld OP/1000cycle (%ld%%o utilization).\n",
           performance, utilization);
  }

  if (cid == 0) {
    for (int i = 0; i < gemv_l.M; i++) {
      if (fp_check(&result[i], &gemv_result[i])) {
        printf("Error: ID: %i Result = %f, Golden = %f\n", i, result[i], gemv_result[i]);
        return -1;
      }
    }
  }

  // Wait for core 0 to finish displaying results
  snrt_cluster_hw_barrier();
  return 0;
}
