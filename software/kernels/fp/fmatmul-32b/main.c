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
#include <spatz_lock.h>
#include <stdio.h>

#include DATAHEADER
#include "kernel/fmatmul.c"


#ifndef KERNEL_SIZE
#define KERNEL_SIZE 4
#endif

// L1 configuration. These defaults are the measured best general setting.
//
// XBAR_OFFSET picks the first L1 bank-select address bit, i.e. the interleave
// granularity across a tile's cache controllers. 6 is the finest the hardware
// allows (one cacheline; l1d_xbar_config clamps anything lower), which spreads
// a core's sequential vector stream over all four controllers.
//
// Offset 8 (256 B) trades cold for hot and is the better choice when the same
// matmul runs many times on 16g -- measured at M1024_N128_K128, all-private,
// group-folded:
//
//   offset 6: cold 31711 cyc (51.7% peak), hot 20692 cyc (79.2%)
//   offset 8: cold 50189 cyc (32.6% peak), hot 17819 cyc (91.9%)
//
// So prefer 6 for a one-shot matmul and 8 for a repeated one. On 4g, offset 6
// wins on both axes and there is no trade.
#ifndef XBAR_OFFSET
#define XBAR_OFFSET 6
#endif
// Number of private banks per tile (0 = all-shared). All-private is a large
// win here; all-shared costs ~2.7x on cold.
#ifndef L1D_PART
#define L1D_PART num_cores_per_tile
#endif
// L1D_FOLD_TILE keeps the private banks to their own tile; L1D_FOLD_GROUP
// spreads them across the group, so a line shared by the group -- B here -- is
// fetched once per group instead of once per tile. Group folding is the single
// biggest win for this kernel (2.30x cold / 2.48x hot at 4g), so it is the
// default; the sweep_*.c wrappers pin it explicitly either way.
#ifndef L1D_FOLD
#define L1D_FOLD L1D_FOLD_GROUP
#endif

float *a;
float *b;
float *c;

// Pointer to per-core error slots; allocated in main by core 0 via snrt_malloc.
// Placed in .data so the pointer word lives at a fixed shared DRAM address.
int *error_arr __attribute__((section(".data")));

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
    }
  }
  return error;
}

int main() {
  const unsigned int num_cores = snrt_cluster_vpu_num();
  const unsigned int num_cores_per_tile = snrt_cluster_vpu_per_tile();
  const unsigned int cid = snrt_cluster_vpu_idx();
  const int is_primary = snrt_cluster_is_primary();

  #if MEAS_1ITER == 1
  const int measure_iter = 1;
  #else
  const int measure_iter = 2;
  #endif

  unsigned int m_start, m_end;
  unsigned int p_start, p_end;
  unsigned int kernel_size;

  // Set matrix dimension
  kernel_size = KERNEL_SIZE;

  // Cap active cores to the number of row-tiles the matrix provides
  unsigned int active_cores = snrt_min(num_cores, gemm_l.M / kernel_size);

  // Allocate and zero the error array while the cache is still in shared mode,
  // so the pointer write and slot initialisation are visible to all cores.
  if (is_primary && cid == 0) {
    error_arr = (int *)snrt_malloc(active_cores * sizeof(int));
    for (unsigned int i = 0; i < active_cores; i++)
      error_arr[i] = 0;
  }

  // Barrier here ensures all cores see error_arr before the cache mode changes.
  snrt_cluster_hw_barrier();

  // Set xbar policy and switch to private cache mode for the matmul.
  // Bank is addr[offset +: 2], so an offset where (A row pitch >> offset) is
  // odd spreads a core's kernel_size rows over distinct banks. At cacheline
  // offset the row index drops out of the bank field entirely and the scalar
  // A stream sits on one bank for K/16 iterations, filling its MSHRs.
  l1d_xbar_config(XBAR_OFFSET);
  l1d_part_folded(L1D_PART, L1D_FOLD);

  a = gemm_A_dram;
  b = gemm_B_dram;
  c = gemm_C_dram;

  // Work over complete P dimension
  p_start = 0;
  p_end = gemm_l.N;
  if (cid < active_cores) {
    m_start = (gemm_l.M / active_cores) * cid;
    m_end   = (gemm_l.M / active_cores) * (cid + 1);
  } else {
    m_start = 0;
    m_end   = 0;
  }

  // Host 1 never touches Spatz or the shared result/timer state in this
  // kernel, so the rest of main() is gated by one check instead of many.
  if (is_primary) {
    unsigned int timer_start, timer_end, timer, timer_iter1;
    timer = (unsigned int)-1;

    // LOCKED mode gives host 0 unarbitrated Spatz access; FREE mode would
    // round-robin-arbitrate with host 1 even though it never issues here.
    spatz_lock_acquire();

    for (unsigned int i = 0; i < measure_iter; ++i) {
      if (cid == 0) {
        start_kernel();
      }

      timer_start = benchmark_get_cycle();

      if (kernel_size == 2) {
        matmul_2xVL(gemm_C_dram, gemm_A_dram, gemm_B_dram, m_start, m_end, gemm_l.K, gemm_l.N, p_start, p_end);
      } else if (kernel_size == 4) {
        matmul_4xVL(gemm_C_dram, gemm_A_dram, gemm_B_dram, m_start, m_end, gemm_l.K, gemm_l.N, p_start, p_end);
      } else if (kernel_size == 8) {
        matmul_8xVL(gemm_C_dram, gemm_A_dram, gemm_B_dram, m_start, m_end, gemm_l.K, gemm_l.N, p_start, p_end);
      } else {
        // Release before returning: this early-exit path leaves the loop
        // (and the is_primary block) without reaching the release below.
        spatz_lock_release();
        return -1;
      }

      snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);

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
        if (cid < active_cores) {
          float *check_C    = gemm_C_dram + cid * (gemm_l.M / active_cores) * gemm_l.N;
          float *check_gold = (float *)gemm_checksum + cid * (gemm_l.M / active_cores);

          error_arr[cid] = verify_matrix(check_C, (const float *)check_gold,
                                         (gemm_l.M / active_cores), gemm_l.N);
        }

        snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);

        if (cid == 0) {
          if (error_arr[0] != 0)
            printf("Core 0 error %d\n", error_arr[0]);

          for (uint32_t j = 1; j < active_cores; j++) {
            error_arr[0] += error_arr[j];
            if (error_arr[j] != 0)
              printf("Core %d error %d\n", j, error_arr[j]);
          }
        } else {
          cachepool_wait(10);
        }

        snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);
      }
    }

    // Check and display results
    if (cid == 0) {
      // 1000 * 2*M*N*K overflows 32 bits from ~128^3 upward, so the FLOP
      // count is formed in 64 bits and only the (small) results narrowed.
      const unsigned long long flops =
          2ULL * gemm_l.M * gemm_l.N * gemm_l.K;
      const uint32_t performance = (uint32_t)(1000ULL * flops / timer);
      const uint32_t utilization = performance / (2 * active_cores * 4);

      const uint32_t performance_iter1 =
          (uint32_t)(1000ULL * flops / timer_iter1);
      const uint32_t utilization_iter1 =
          performance_iter1 / (2 * active_cores * 4);

      write_cyc(timer);
      printf("\n----- (%dx%d) sp fmatmul -----\n", gemm_l.M, gemm_l.N);
      printf("Active cores %u \n", active_cores);
      printf("First iter took %u cycles.\n", timer_iter1);
      printf("The perf is %u OP/1000cycle (%u%%o utilization).\n",
             performance_iter1, utilization_iter1);
      printf("Best iter took %u cycles.\n", timer);
      printf("The perf is %u OP/1000cycle (%u%%o utilization).\n",
             performance, utilization);
    }

    snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);

    // main()'s epilogue restores callee-saved FP registers unconditionally, even for host 1.
    spatz_lock_release();
  }

  // Explicit closing barrier instead of relying on the implicit post-main() one.
  snrt_cluster_hw_barrier();

  if (error_arr[0] > 0)
    return -1;

  return 0;
}
