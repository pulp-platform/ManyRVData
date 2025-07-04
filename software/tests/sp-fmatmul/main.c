// Copyright 2023 ETH Zurich and University of Bologna.
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

// Author: Matheus Cavalcante, ETH Zurich

#include <benchmark.h>
#include <snrt.h>
#include <stdio.h>

#include DATAHEADER
#include "kernel/sp-fmatmul.c"


#ifndef KERNEL_SIZE
#define KERNEL_SIZE 4
#endif

float *a;
float *b;
float *c;

int error[4] = {0};

// Verify the matrices
int verify_matrix(float *matrix, const float *checksum,
                  const unsigned int num_rows, const unsigned int num_columns) {
  int error = 0;

  for (unsigned int i = 0; i < num_rows; ++i) {
    float sum = 0;
    for (unsigned int j = 0; j < num_columns; ++j) {
      sum += (float)matrix[i * num_columns + j];
    }

    float diff = sum - (float)checksum[i];
    if (diff < 0)
      diff = -diff;
    if (diff > 0.01f) {
      error ++;
      // printf("Row: %d, Result: %x, Golden reselt: %x\n", i, print_sum, print_gold);
    }
  }
  return error;
}

int main() {
  const unsigned int num_cores = snrt_cluster_core_num();
  const unsigned int cid = snrt_cluster_core_idx();

  #if MEAS_1ITER == 1
  const int measure_iter = 1;
  #else
  const int measure_iter = 2;
  #endif

  unsigned int timer_start, timer_end, timer, timer_iter1;

  unsigned int m_start, m_end;
  unsigned int p_start, p_end;
  unsigned int kernel_size;


  if (cid == 0) {
    // Set xbar policy
    // All cores will access the same B
    // Scramble based on cacheline
    // l1d_xbar_config(5);
    l1d_xbar_config(5);
    // Init the cache
    l1d_init(0);
  }

  // Wait for all cores to finish
  snrt_cluster_hw_barrier();

  a = gemm_A_dram;
  b = gemm_B_dram;
  c = gemm_C_dram;

  // Reset timer
  timer = (unsigned int)-1;

  // Set matrix dimension
  kernel_size = KERNEL_SIZE;

  // Work over complete P dimension
  p_start = 0;
  p_end = gemm_l.N;
  m_start = (gemm_l.M / num_cores) * cid;
  m_end = (gemm_l.M / num_cores) * (cid + 1);

  // Initialize matrices
  #ifdef DEBUG
  if (cid == 0) {
    printf ("a:%x\n", a);
    printf ("b:%x\n", b);
    printf ("c:%x\n", c);

    printf ("m_start:%x\n", m_start);
    printf ("m_end:%x\n",   m_end);

    printf ("p_start:%x\n", p_start);
    printf ("p_end:%x\n", p_end);
  }
  #endif

  // Wait for all cores to finish
  snrt_cluster_hw_barrier();

  // Calculate matmul
  for (unsigned int i = 0; i < measure_iter; ++i) {
    // Start dump
    if (cid == 0) {
      start_kernel();
    }

    // Start timer
    timer_start = benchmark_get_cycle();

    if (kernel_size == 2) {
      matmul_2xVL(gemm_C_dram, gemm_A_dram, gemm_B_dram, m_start, m_end, gemm_l.K, gemm_l.N, p_start, p_end);
    } else if (kernel_size == 4) {
      matmul_4xVL(gemm_C_dram, gemm_A_dram, gemm_B_dram, m_start, m_end, gemm_l.K, gemm_l.N, p_start, p_end);
    } else if (kernel_size == 8) {
      matmul_8xVL(gemm_C_dram, gemm_A_dram, gemm_B_dram, m_start, m_end, gemm_l.K, gemm_l.N, p_start, p_end);
    } else {
      return -2;
    }

    // Wait for all cores to finish
    snrt_cluster_hw_barrier();

    // End timer and check if new best runtime
    timer_end = benchmark_get_cycle();
    unsigned int timer_temp = timer_end - timer_start;
    if (cid == 0) {
      if (timer_temp < timer) {
        timer = timer_temp;
        if (i == 0)
          timer_iter1 = timer;
      }
      stop_kernel();
    }

    if (i == 0) {
      float * check_C    = gemm_C_dram   + cid*(gemm_l.M/num_cores)*gemm_l.N;
      float * check_gold = (float *) gemm_checksum + cid*(gemm_l.M/num_cores);

      error[cid] = verify_matrix(check_C, (const float *)check_gold, (gemm_l.M/num_cores), gemm_l.N);

      snrt_cluster_hw_barrier();

      if (cid == 0) {
        for (uint32_t j = 0; j < num_cores; j++) {
          printf("Core %d error %d\n", j, error[j]);
          // error[0] += error[j];
        }

      } else {
        cachepool_wait(10);
      }

      snrt_cluster_hw_barrier();

      // if (error[0] != 0) {
      //   if (cid == 0) {
      //     printf("Check failed, error count:%d\n", error[0]);
      //     // printf("First iter took %u cycles\n", timer_iter1);
      //   }
      //   // return -1;
      // }
    }
  }

  // Check and display results
  if (cid == 0) {
    long unsigned int performance =
        1000 * 2 * gemm_l.M * gemm_l.N * gemm_l.K / timer;
    long unsigned int utilization = performance / (2 * num_cores * 4);

    long unsigned int performance_iter1 =
        1000 * 2 * gemm_l.M * gemm_l.N * gemm_l.K / timer_iter1;
    long unsigned int utilization_iter1 = performance_iter1 / (2 * num_cores * 4);

    write_cyc(timer);
    printf("\n----- (%dx%d) sp fmatmul -----\n", gemm_l.M, gemm_l.N);
    printf("First iteration execution took %u cycles.\n", timer_iter1);
    printf("The performance is %ld OP/1000cycle (%ld%%o utilization).\n",
           performance_iter1, utilization_iter1);
    printf("The execution took %u cycles.\n", timer);
    printf("The performance is %ld OP/1000cycle (%ld%%o utilization).\n",
           performance, utilization);
  }

  // Wait for all cores to finish
  snrt_cluster_hw_barrier();
  set_eoc();

  return 0;
}
