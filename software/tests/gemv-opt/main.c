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

// Author: Diyou Shen,              ETH Zurich <dishen@iis.ee.ethz.ch>

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

// static float result __attribute__((section(".data")));
// spinlock_t lock;


// Notice that A matrix might be transposed for easier access (not necessary)
// But the comments/algorithm will not assume it is transposed
// A matrix: N-by-M
// B vector: 1-by-N
// results:  M-by-1

int main() {
  T *a;
  T *b;
  T *result;

  const uint32_t num_cores = snrt_cluster_core_num();
  const uint32_t cid = snrt_cluster_core_idx();

  // How many column of data each core will work on
  // This will determine the vlen of the calculation
  const uint32_t m_core = gemv_l.M / num_cores;

  const uint32_t elem_width = sizeof(T) * 8;

  /*** Core Parameters for Optimization ***/
  const uint32_t lmul_m1       = 512;
  const uint32_t lmul_m1_elem  = lmul_m1 / elem_width;

  const uint32_t lmul_max      = m_core / lmul_m1_elem;
  uint32_t lmul;
  if (lmul_max >= 8) {
    // Use 4 for now due to implementation
    lmul = 4;
  } else if (lmul_max >= 4) {
    lmul = 4;
  } else if (lmul_max >= 2) {
    lmul = 2;
  } else if (lmul_max == 1) {
    lmul = 1;
  } else {
    if (cid == 0) {
      printf("FATAL: Problem size too small!\n");
    }
    snrt_cluster_hw_barrier();
    return -1;
  }

  // The elements each core will work on
  // This is used for scrambling
  const uint32_t block_elem_core = m_core * gemv_l.N;
  // offset bits in unit of byte (address)
  uint32_t offset = 31 - __builtin_clz(m_core * elem_width/8);

  // Allocate the matrices
  if (cid == 0) {
    // Set xbar policy
    l1d_xbar_config(offset);
  }

  /*** DRAM Parameters for Optimization ***/
  const uint32_t l2_interleave = 16;
  const uint32_t l2_channel    = 4;
  // in bits
  const uint32_t l2_lanewidth  = 512;
  // This is the continuous address block (bits) in DRAM
  const uint32_t l2_block_size = l2_lanewidth * l2_interleave;
  const uint32_t l2_block_elem = l2_block_size / elem_width;

  // In general, the data block should be much larger than DRAM block (1 KiB)
  // To fully utilize the BW, we will add offset of starting points
  // Warn if the data block is too small

  // Are we fully utilizing the off-chip bandwidth?
  // If our block size is a 4-times multiple of l2 block size
  // Then we will always visiting the same L2 channel
  if (block_elem_core < l2_block_elem) {
    if (cid == 0) {
      printf("FATAL: Current scheme cannot utilize all bandwidth!\n");
      printf("Core block size:%u, DRAM block size:%u\n", block_elem_core, l2_block_elem);
    }
    snrt_cluster_hw_barrier();
    return -1;
  }

  // Reset timer
  unsigned int timer_start, timer_end, timer, timer_iter1;

  // Calculate the starting points for each core
  // Notice it might be differnt if the matrix is transposed
  a = gemv_A_dram;
  b = gemv_B_dram;
  result = gemv_result;

  // Calculate internal pointers
  // This is the starting point without offset for BW utilization
  T *a_core       = a + m_core * cid;
  T *b_core       = b;
  T *r_core       = result + m_core * cid;

  uint32_t l2_block_bytes = l2_block_size / 8;
  uint32_t col_bytes      = gemv_l.M * sizeof(T);
  uint32_t l2_block_cols  = (l2_block_bytes + col_bytes - 1) / col_bytes;

  uint32_t col_shift = (cid * l2_block_cols) % gemv_l.N;

  T *a_offset = a_core + col_shift * gemv_l.M;
  T *b_offset = b_core + col_shift;

  uint32_t n_core   = gemv_l.N - col_shift;   // first segment length
  uint32_t comp_size = col_shift;             // second segment length

  if (cid == 0) {
    printf("lmul:%u, mcore:%u\n", lmul, m_core);
  }

  // Wait for all cores to finish
  snrt_cluster_hw_barrier();


  for (int i = 0; i < 3; i++) {

    // Start dump
    if (cid == 0) {
      start_kernel();
      // Start timer
      timer_start = benchmark_get_cycle();
    }

    // Calculate gemv
    if (lmul == 4) {
      gemv_v32b_m4(a_core, b_core, r_core, a_offset, b_offset, gemv_l.M, n_core, m_core, comp_size);
    } else if (lmul == 2) {
      gemv_v32b_m2(a_core, b_core, r_core, a_offset, b_offset, gemv_l.M, n_core, m_core, comp_size);
    } else if (lmul == 1) {
      gemv_v32b_m1(a_core, b_core, r_core, a_offset, b_offset, gemv_l.M, n_core, m_core, comp_size);
    }

    // Wait for all cores to finish
    snrt_cluster_hw_barrier();


    if (cid == 0) {
      // End timer and check if new best runtime
      timer_end = benchmark_get_cycle();
      unsigned int timer_temp = timer_end - timer_start;

      if (timer_temp < timer) {
        timer = timer_temp;
      }

      stop_kernel();

      if (i == 0) {
        timer = timer_temp;
        timer_iter1 = timer;

        for (uint32_t j = 0; j < gemv_l.M; j++) {
          if (fp_check(&result[j], &gemv_result[j])) {
            printf("Error: ID: %i Result = %f, Golden = %f\n", i, result[i], gemv_result[i]);
          }
        }
      }
    } else {
      cachepool_wait(10);
    }

    snrt_cluster_hw_barrier();

  }

  // Check and display results
  if (cid == 0) {
    long unsigned int performance =
        1000 * 2 * gemv_l.M * gemv_l.N / timer;
    long unsigned int utilization = performance / (2 * num_cores * 4 * (4 / sizeof(T)));

    long unsigned int performance_iter1 =
        1000 * 2 * gemv_l.M * gemv_l.N / timer_iter1;
    long unsigned int utilization_iter1 = performance_iter1 / (2 * num_cores * 4 * (4 / sizeof(T)));

    write_cyc(timer);
    printf("\n----- (%d x %d) x (%d x 1) gemv -----\n", gemv_l.M, gemv_l.N, gemv_l.N);
    printf("First iteration execution took %u cycles.\n", timer_iter1);
    printf("The performance is %ld OP/1000cycle (%ld%%o utilization).\n",
           performance_iter1, utilization_iter1);
    printf("The execution took %u cycles.\n", timer);
    printf("The performance is %ld OP/1000cycle (%ld%%o utilization).\n",
           performance, utilization);
  }

  // Wait for core 0 to finish displaying results
  snrt_cluster_hw_barrier();
  return 0;
}
