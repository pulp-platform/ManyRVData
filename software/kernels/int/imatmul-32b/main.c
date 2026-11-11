// Copyright 2026 ETH Zurich and University of Bologna.
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

// Integer GEMM (32 bit), the integer counterpart of kernels/fp/fmatmul-32b: each VPU computes
// a block of rows, every element is checked exactly. KERNEL_LOCK=1 (default) runs with the Spatz
// lock held (full VRF); KERNEL_LOCK=0 runs without it, i.e. on the split VRF of a dual-thread
// Spatz.

#include <benchmark.h>
#include <l1cache.h>
#include <snrt.h>
#include <spatz_lock.h>

#include DATAHEADER
#include "kernel/imatmul.c"

#ifndef KERNEL_SIZE
#define KERNEL_SIZE 4
#endif

#ifndef XBAR_OFFSET
#define XBAR_OFFSET 6
#endif
#ifndef L1D_PART
#define L1D_PART num_cores_per_tile
#endif
#ifndef L1D_FOLD
#define L1D_FOLD L1D_FOLD_GROUP
#endif

#ifndef KERNEL_LOCK
#define KERNEL_LOCK 1
#endif

int *error_arr __attribute__((section(".data")));

// Wrong elements in rows [row_start, row_end) of C
static int verify_rows(const int32_t *c, const int32_t *gold, unsigned int row_start,
                       unsigned int row_end, unsigned int num_columns) {
  int error = 0;
  for (unsigned int i = row_start * num_columns; i < row_end * num_columns; ++i) {
    error += (c[i] != gold[i]);
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
  const unsigned int p_start = 0, p_end = imatmul_l.N;
  const unsigned int kernel_size = KERNEL_SIZE;
  const unsigned int active_cores = snrt_min(num_cores, imatmul_l.M / kernel_size);

  if (is_primary && cid == 0) {
    error_arr = (int *)snrt_malloc(active_cores * sizeof(int));
    for (unsigned int i = 0; i < active_cores; i++) error_arr[i] = 0;
  }

  snrt_cluster_hw_barrier();

  l1d_xbar_config(XBAR_OFFSET);
  l1d_part_folded(L1D_PART, L1D_FOLD);

  if (cid < active_cores) {
    m_start = (imatmul_l.M / active_cores) * cid;
    m_end   = (imatmul_l.M / active_cores) * (cid + 1);
  } else {
    m_start = 0;
    m_end   = 0;
  }

  if (is_primary) {
    unsigned int timer_start, timer_end, timer = (unsigned int)-1, timer_iter1 = 0;

    if (KERNEL_LOCK) spatz_lock_acquire();

    for (int i = 0; i < measure_iter; ++i) {
      if (cid == 0) start_kernel();

      timer_start = benchmark_get_cycle();

      if (kernel_size == 2) {
        imatmul_2xVL(imatmul_C_dram, imatmul_A_dram, imatmul_B_dram, m_start, m_end, imatmul_l.K,
                     imatmul_l.N, p_start, p_end);
      } else if (kernel_size == 4) {
        imatmul_4xVL(imatmul_C_dram, imatmul_A_dram, imatmul_B_dram, m_start, m_end, imatmul_l.K,
                     imatmul_l.N, p_start, p_end);
      } else {
        imatmul_8xVL(imatmul_C_dram, imatmul_A_dram, imatmul_B_dram, m_start, m_end, imatmul_l.K,
                     imatmul_l.N, p_start, p_end);
      }

      snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);

      timer_end = benchmark_get_cycle();
      const unsigned int timer_temp = timer_end - timer_start;
      if (cid == 0) {
        if (i == 0) timer_iter1 = timer_temp;
        if (timer_temp < timer) timer = timer_temp;
        stop_kernel();
      }

      if (i == 0) {
        if (cid < active_cores) {
          error_arr[cid] = verify_rows(imatmul_C_dram, imatmul_result, m_start, m_end, imatmul_l.N);
        }

        snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);

        if (cid == 0) {
          for (uint32_t j = 0; j < active_cores; j++) {
            if (error_arr[j] != 0) printf("Core %u: %d wrong elements\n", j, error_arr[j]);
            if (j) error_arr[0] += error_arr[j];
          }
        }

        snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);
      }
    }

    if (cid == 0) {
      const unsigned long long ops = 2ULL * imatmul_l.M * imatmul_l.N * imatmul_l.K;
      const uint32_t performance = (uint32_t)(1000ULL * ops / timer);
      const uint32_t utilization = performance / (2 * active_cores * 4);
      const uint32_t performance_iter1 = (uint32_t)(1000ULL * ops / timer_iter1);
      const uint32_t utilization_iter1 = performance_iter1 / (2 * active_cores * 4);

      write_cyc(timer);
      printf("\n----- (%ux%u) int32 imatmul, %s -----\n", imatmul_l.M, imatmul_l.N,
             KERNEL_LOCK ? "Spatz lock held" : "no Spatz lock");
      printf("Active cores %u, %d wrong elements\n", active_cores, error_arr[0]);
      printf("First iter took %u cycles.\n", timer_iter1);
      printf("The perf is %u OP/1000cycle (%u%%o utilization).\n", performance_iter1,
             utilization_iter1);
      printf("Best iter took %u cycles.\n", timer);
      printf("The perf is %u OP/1000cycle (%u%%o utilization).\n", performance, utilization);
    }

    snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);

    if (KERNEL_LOCK) spatz_lock_release();
  }

  snrt_cluster_hw_barrier();

  return (error_arr[0] > 0) ? -1 : 0;
}
