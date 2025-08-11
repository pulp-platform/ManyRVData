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
  unsigned int timer_ldst, timer_flush;


  uint32_t *a_int = gemm_A_dram + dim_core * cid;
  uint32_t *b_int = gemm_B_dram + dim_core * cid;
  uint32_t *c_int = gemm_C_dram + dim_core * cid;
  uint32_t avl = dim_core;
  uint32_t vlen;

  if (cid == 0) {
    printf("dim per core:%d\n", avl);
    printf("a_ptr:%x, b_ptr:%x\n", a_int, b_int);
  }

  // Wait for all cores to finish
  snrt_cluster_hw_barrier();

  // Start dump
  if (cid == 0)
    start_kernel();

  // Start timer
  if (cid == 0)
    timer_ldst = benchmark_get_cycle();

  // Stripmine and accumulate a partial reduced vector
  do {
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vlen) : "r"(avl));
    asm volatile("vle32.v v0,  (%0)" ::"r"(a_int));
    asm volatile("vle32.v v8,  (%0)" ::"r"(b_int));
    asm volatile("vle32.v v12, (%0)" ::"r"(c_int));
    // Move A to C
    asm volatile("vse32.v v0,  (%0)" ::"r"(c_int));
    // Move B to A
    asm volatile("vse32.v v8,  (%0)" ::"r"(a_int));
    // Move C to B
    asm volatile("vse32.v v12, (%0)" ::"r"(b_int));

    a_int += vlen;
    b_int += vlen;
    c_int += vlen;
    avl -= vlen;
  } while (avl > 0);

  snrt_cluster_hw_barrier();

  // End timer and check if new best runtime
  if (cid == 0) {
    timer_ldst  = benchmark_get_cycle() - timer_ldst;
    stop_kernel();
  } else {
    cachepool_wait(10);
  }

  snrt_cluster_hw_barrier();

  if (cid == 0) {
    timer_flush = benchmark_get_cycle();
    l1d_flush();
  }

  snrt_cluster_hw_barrier();

  if (cid == 0) {
    timer_flush = benchmark_get_cycle() - timer_flush;
  } else {
    cachepool_wait(10);
  }

  if (cid == 0) {
    // uint32_t check_failed = 0;
    for (int i = 0; i < dim; i ++) {
      if (gemm_A_dram[i] != 2) {
        // check_failed = 1;
        printf("A[%d]Check Failed!, should be 2, read %u\n", i, gemm_A_dram[i]);
      }

      if (gemm_B_dram[i] != 3) {
        // check_failed = 1;
        printf("B[%d]Check Failed!, should be 3, read %u\n", i, gemm_A_dram[i]);
      }

      if (gemm_C_dram[i] != 1) {
        // check_failed = 1;
        printf("C[%d]Check Failed!, should be 1, read %u\n", i, gemm_A_dram[i]);
      }
    }

    // 4 cores, 4 ports
    const uint32_t elem_moved_per_cyc = num_cores * 4;
    // 3 rounds, each round is with size of dim, each round with 1 ld 1 st
    const uint32_t num_elem_moved = 3 * 2 * dim;

    // const uint32_t ideal_cyc = num_byte_moved / byte_moved_per_cyc;

    // Byte per cycle
    uint32_t perf_ldst = 1000 * num_elem_moved / timer_ldst;
    uint32_t perf_tot  = 1000 * num_elem_moved / (timer_ldst + timer_flush);

    uint32_t util_ldst = perf_ldst / elem_moved_per_cyc;
    uint32_t util_tot  = perf_tot  / elem_moved_per_cyc;

    printf("Load-Store 3x%u Testing Finished\n", dim);
    printf("Data movement takes %u cycles\n", timer_ldst);
    printf("Flush takes %u cycles\n", timer_flush);
    printf("LDST Only:\n");
    printf("Perf %u Elem/1K Cyc, Util %u %%o \n", perf_ldst, util_ldst);
    printf("Including Flush:\n");
    printf("Perf %u Elem/1K Cyc, Util %u %%o \n", perf_tot,  util_tot);
  } else {
    cachepool_wait(100);
  }


  // Wait for core 0 to display the results
  snrt_cluster_hw_barrier();

  return 0;
}