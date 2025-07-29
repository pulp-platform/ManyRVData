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

int main() {
  const unsigned int num_cores = snrt_cluster_core_num();
  const unsigned int cid = snrt_cluster_core_idx();

  const int measure_iter = 1;

  uint32_t spm_size = 0;

  const unsigned int dim = gemm_l.M * gemm_l.M;
  const unsigned int dim_core = dim / num_cores;

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


  uint32_t *a_int = gemm_A_dram + dim_core * cid;
  uint32_t *b_int = gemm_B_dram + dim_core * cid;
  uint32_t avl = dim_core;
  uint32_t vlen;

  if (cid == 0) {
    printf("dim per core:%d\n", avl);
    printf("a_ptr:%x, b_ptr:%x\n", a_int, b_int);
  }

  // Wait for all cores to finish
  snrt_cluster_hw_barrier();

  for (int iter = 0; iter < measure_iter; iter ++) {
    // Start dump
    if (cid == 0)
      start_kernel();

    // Start timer
    if (cid == 0)
      timer_tmp = benchmark_get_cycle();

      // Stripmine and accumulate a partial reduced vector
      do {
        asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vlen) : "r"(avl));
        // Move A to B
        asm volatile("vle32.v v8,  (%0)" ::"r"(a_int));
        asm volatile("vse32.v v8,  (%0)" ::"r"(b_int));
        a_int += vlen;
        b_int += vlen;
        avl -= vlen;
      } while (avl > 0);

    snrt_cluster_hw_barrier();

    // End timer and check if new best runtime
    if (cid == 0) {
      timer_tmp = benchmark_get_cycle() - timer_tmp;
      timer = (timer < timer_tmp) ? timer : timer_tmp;
      if (iter == 0)
        timer_iter1 = timer;

      stop_kernel();
    } else {
      cachepool_wait(100);
    }

    snrt_cluster_hw_barrier();

    if (cid == 0) {
      l1d_flush();
    } else {
      cachepool_wait(100);
    }

    snrt_cluster_hw_barrier();
  }



  if (cid == 0) {
    for (int i = 0; i < dim; i ++)
    if (gemm_A_dram[i] != gemm_B_dram[i]) {
      // printf("Error: Result = %f, Golden = %f\n", result[0], dotp_result*measure_iter);
      // return 0;
      printf("[%d]Check Failed!\n", i);
    }
  } else {
    cachepool_wait(100);
  }


  // Wait for core 0 to display the results
  snrt_cluster_hw_barrier();

  return 0;
}