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
  const unsigned int num_tiles = snrt_cluster_tile_num();
  const unsigned int cid = snrt_cluster_core_idx();

  const int measure_iter = 1;

  uint32_t spm_size = 0;

  const unsigned int dim = gemm_l.M;
  const unsigned int dim_core = dim / num_cores;

  uint32_t offset = 31 - __builtin_clz(dim_core * sizeof(float));

  if (cid == 0) {
    // Set xbar policy
    l1d_xbar_config(offset);
    // Initialize the cache
    l1d_init(0);
  }

  // Wait for all cores to finish
  snrt_cluster_hw_barrier();

  // Reset timer
  unsigned int timer_test1, timer_test1_cold, timer_test1_hot;
  unsigned int timer_test2, timer_test2_cold, timer_test2_hot;
  unsigned int timer_test3;


  uint32_t *a_int = gemm_A_dram + dim_core * cid;
  uint32_t *b_int = gemm_B_dram + dim_core * cid;
  uint32_t *c_int = gemm_C_dram + dim_core * cid;
  uint32_t avl = dim_core;
  uint32_t vlen;

  /***** Share Test 1 *****/
  if (cid == 0) {
    // All cores will visit 1 MiB Data
    printf("***Testing shared cache configuration***\n");
    l1d_part(0);
    printf("Configuration done!\n\n");
    printf("Test 1: Local Visit\n");
    printf("dim per core:%d\n", avl);
    printf("a_ptr:%x\n", a_int);
  }

  uint32_t iter = 2;

  // Wait for all cores to finish
  snrt_cluster_hw_barrier();

  while (iter > 0) {
    iter --;
    // Start dump
    if (cid == 0)
      start_kernel();

    // Start timer
    if (cid == 0)
      timer_test1 = benchmark_get_cycle();

    // Stripmine and accumulate a partial reduced vector
    do {
      asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vlen) : "r"(avl));
      asm volatile("vle32.v v0,  (%0)" ::"r"(a_int));
      a_int += vlen;
      // b_int += vlen;
      // c_int += vlen;
      avl -= vlen;
    } while (avl > 0);

    snrt_cluster_hw_barrier();

    // End timer and check if new best runtime
    if (cid == 0) {
      timer_test1  = benchmark_get_cycle() - timer_test1;
      stop_kernel();
      if (iter == 1)
        timer_test1_cold = timer_test1;
      else
        timer_test1_hot  = timer_test1;
    } else {
      cachepool_wait(10);
    }

    a_int = gemm_A_dram + dim_core * cid;
    avl   = dim_core;
  }

  snrt_cluster_hw_barrier();

  // Second test is mainly for private v.s. shared
  // No need to visit entire 1 MiB
  avl   = dim / num_tiles;
  a_int = gemm_A_dram;
  iter  = 3;

  if (cid == 0) {
    printf("Test 1 Complete\n");
    printf("Cold:%u cyc; Hot:%u cyc\n", timer_test1_cold, timer_test1_hot);

    // Each core will visit 1 MiB data
    printf("\nTest 2: Global Visit\n");
    printf("dim per core:%d\n", avl);
    printf("a_ptr:%x\n", a_int);
    // Flush the cache
    l1d_flush();
    l1d_wait();
  }

  // offset = 31 - __builtin_clz(dim_core / num_tiles * sizeof(float));

  if (cid == 0) {
    // Set xbar policy
    l1d_xbar_config(0);
    // Initialize the cache
    l1d_init(0);
  }

  timer_test2_hot = (uint32_t) -1;

  /***** Share Test 2 *****/
  snrt_cluster_hw_barrier();

  while (iter > 0) {
    iter --;

    a_int = gemm_A_dram;
    avl   = dim / num_tiles;

    // Start dump
    if (cid == 0)
      start_kernel();

    // Start timer
    if (cid == 0)
      timer_test2 = benchmark_get_cycle();

    // Stripmine and accumulate a partial reduced vector
    do {
      asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vlen) : "r"(avl));
      asm volatile("vle32.v v0,  (%0)" ::"r"(a_int));
      a_int += vlen;
      // b_int += vlen;
      // c_int += vlen;
      avl -= vlen;
    } while (avl > 0);

    snrt_cluster_hw_barrier();

    // End timer and check if new best runtime
    if (cid == 0) {
      timer_test2  = benchmark_get_cycle() - timer_test2;
      stop_kernel();
      if (iter == 1)
        timer_test2_cold = timer_test2;
      else
        timer_test2_hot  = timer_test2_hot > timer_test2 ? timer_test2 : timer_test2_hot;
    } else {
      cachepool_wait(10);
    }
  }

  snrt_cluster_hw_barrier();

  /***** Share Test 3 *****/
  avl = dim / num_tiles;

  if (cid == 0) {
    printf("Test 2 Complete\n");
    printf("Cold:%u cyc; Hot:%u cyc\n", timer_test2_cold, timer_test2_hot);

    // Each core will visit the next 256 KiB data and revisit the previous 128 KiB
    // In shared cache, the revisit would be cache hit
    printf("\nTest 3: Eviction Test\n");
    printf("dim per core:%d\n", avl);
    printf("a_ptr:%x\n", a_int);
  }

  // Visit the next 256 KiB Block first
  do {
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vlen) : "r"(avl));
    asm volatile("vle32.v v0,  (%0)" ::"r"(a_int));
    a_int += vlen;
    avl -= vlen;
  } while (avl > 0);

  avl = dim / num_tiles;
  a_int = gemm_A_dram;

  // Start dump
  if (cid == 0)
    start_kernel();

  // Start timer
  if (cid == 0)
    timer_test3 = benchmark_get_cycle();

  // Stripmine and accumulate a partial reduced vector
  do {
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vlen) : "r"(avl));
    asm volatile("vle32.v v0,  (%0)" ::"r"(a_int));
    a_int += vlen;
    avl -= vlen;
  } while (avl > 0);

  snrt_cluster_hw_barrier();

  // End timer and check if new best runtime
  if (cid == 0) {
    timer_test3  = benchmark_get_cycle() - timer_test3;
    stop_kernel();
  } else {
    cachepool_wait(10);
  }

  if (cid == 0) {
    printf("Test 3 Complete\n");
    printf("Result:%u cyc\n", timer_test3);
  }

  snrt_cluster_hw_barrier();

  offset = 31 - __builtin_clz(dim_core * sizeof(float));

  if (cid == 0) {
    // Set xbar policy
    l1d_xbar_config(offset);
    // Initialize the cache
    l1d_init(0);
  }

  a_int = gemm_A_dram + dim_core * cid;
  b_int = gemm_B_dram + dim_core * cid;
  c_int = gemm_C_dram + dim_core * cid;
  avl = dim_core;
  iter = 2;

  if (cid == 0) {
    // All cores will visit 1 MiB Data
    printf("\n***Testing private cache configuration***\n");
    l1d_part(4);
    printf("Configuration done!\n\n");
    printf("Test 1: Local Visit\n");
    printf("dim per core:%d\n", avl);
    printf("a_ptr:%x\n", a_int);
    // Flush the cache
    l1d_flush();
    l1d_wait();
  }

  /***** Private Test 1 *****/

  // Wait for all cores to finish
  snrt_cluster_hw_barrier();

  while (iter > 0) {
    iter --;
    // Start dump
    if (cid == 0)
      start_kernel();

    // Start timer
    if (cid == 0)
      timer_test1 = benchmark_get_cycle();

    // Stripmine and accumulate a partial reduced vector
    do {
      asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vlen) : "r"(avl));
      asm volatile("vle32.v v0,  (%0)" ::"r"(a_int));
      a_int += vlen;
      // b_int += vlen;
      // c_int += vlen;
      avl -= vlen;
    } while (avl > 0);

    snrt_cluster_hw_barrier();

    // End timer and check if new best runtime
    if (cid == 0) {
      timer_test1  = benchmark_get_cycle() - timer_test1;
      stop_kernel();
      if (iter == 1)
        timer_test1_cold = timer_test1;
      else
        timer_test1_hot  = timer_test1;
    } else {
      cachepool_wait(10);
    }

    a_int = gemm_A_dram + dim_core * cid;
    avl   = dim_core;
  }

  snrt_cluster_hw_barrier();

  avl   = dim / num_tiles;
  a_int = gemm_A_dram;
  iter  = 3;

  if (cid == 0) {
    printf("Test 1 Complete\n");
    printf("Cold:%u cyc; Hot:%u cyc\n", timer_test1_cold, timer_test1_hot);

    // Each core will visit 1 MiB data
    printf("\nTest 2: Global Visit\n");
    printf("dim per core:%d\n", avl);
    printf("a_ptr:%x\n", a_int);
    // Flush the cache
    l1d_flush();
    l1d_wait();
  }

  // offset = 31 - __builtin_clz(dim_core / num_tiles * sizeof(float));

  if (cid == 0) {
    // Set xbar policy
    l1d_xbar_config(0);
    // Initialize the cache
    l1d_init(0);
  }

  timer_test2_hot = (uint32_t) -1;

  /***** Private Test 2 *****/

  snrt_cluster_hw_barrier();

  while (iter > 0) {
    iter --;
    a_int = gemm_A_dram;

    // Start dump
    if (cid == 0)
      start_kernel();

    // Start timer
    if (cid == 0)
      timer_test2 = benchmark_get_cycle();

    // Stripmine and accumulate a partial reduced vector
    do {
      asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vlen) : "r"(avl));
      asm volatile("vle32.v v0,  (%0)" ::"r"(a_int));
      a_int += vlen;
      avl -= vlen;
    } while (avl > 0);

    snrt_cluster_hw_barrier();

    // End timer and check if new best runtime
    if (cid == 0) {
      timer_test2  = benchmark_get_cycle() - timer_test2;
      stop_kernel();
      if (iter == 1)
        timer_test2_cold = timer_test2;
      else
        timer_test2_hot  = timer_test2_hot > timer_test2 ? timer_test2 : timer_test2_hot;
    } else {
      cachepool_wait(10);
    }

    avl   = dim / num_tiles;
  }

  /***** Private Test 3 *****/

  snrt_cluster_hw_barrier();

  avl = dim / num_tiles;

  if (cid == 0) {
    printf("Test 2 Complete\n");
    printf("Cold:%u cyc; Hot:%u cyc\n", timer_test2_cold, timer_test2_hot);

    // Each core will visit the next 256 KiB data and revisit the previous 128 KiB
    // In private cache, the revisit would still the miss due to eviction
    printf("\nTest 3: Eviction Test\n");
    printf("dim per core:%d\n", avl);
    printf("a_ptr:%x\n", a_int);
  }

  // Visit the next 256 KiB Block first
  do {
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vlen) : "r"(avl));
    asm volatile("vle32.v v0,  (%0)" ::"r"(a_int));
    a_int += vlen;
    avl -= vlen;
  } while (avl > 0);

  avl = dim / num_tiles;
  a_int = gemm_A_dram;

  // Start dump
  if (cid == 0)
    start_kernel();

  // Start timer
  if (cid == 0)
    timer_test3 = benchmark_get_cycle();

  // Stripmine and accumulate a partial reduced vector
  do {
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vlen) : "r"(avl));
    asm volatile("vle32.v v0,  (%0)" ::"r"(a_int));
    a_int += vlen;
    avl -= vlen;
  } while (avl > 0);

  snrt_cluster_hw_barrier();

  // End timer and check if new best runtime
  if (cid == 0) {
    timer_test3  = benchmark_get_cycle() - timer_test3;
    stop_kernel();
  } else {
    cachepool_wait(10);
  }

  if (cid == 0) {
    printf("Test 3 Complete\n");
    printf("Result:%u cyc\n", timer_test3);
  }


  snrt_cluster_hw_barrier();

  return 0;
}