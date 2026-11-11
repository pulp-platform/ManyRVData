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

// Integer GEMV (32 bit), the integer counterpart of kernels/fp/gemv: each VPU computes a slice
// of the rows, the result is checked exactly. KERNEL_LOCK=1 (default) runs with the Spatz lock
// held (full VRF); KERNEL_LOCK=0 runs without it, i.e. on the split VRF of a dual-thread Spatz.

#include <benchmark.h>
#include <l1cache.h>
#include <snrt.h>
#include <spatz_lock.h>

#include "kernel/igemv.c"
#include DATAHEADER

#ifndef KERNEL_LOCK
#define KERNEL_LOCK 1
#endif

// Wrong results reported in detail before only counting
#define MAX_PRINTED_ERRORS 8

static int32_t *result_dram __attribute__((section(".data")));

int main() {
  const unsigned int num_cores = snrt_cluster_vpu_num();
  const unsigned int cid = snrt_cluster_vpu_idx();
  const int is_primary = snrt_cluster_is_primary();

  const unsigned int m_core = igemv_l.M / num_cores;
  const uint32_t offset = 31 - __builtin_clz(m_core * sizeof(int32_t));

  unsigned int timer_start, timer_end, timer = 0, timer_iter1 = 0;
  // Wrong results, counted on core 0 (its return value is the test result)
  unsigned int num_errors = 0;

  int32_t *a = igemv_A_dram;
  int32_t *b = igemv_B_dram;

  if (is_primary && cid == 0) {
    result_dram = (int32_t *)snrt_malloc(igemv_l.M * sizeof(int32_t));
  }

  // All cores see result_dram before the cache mode changes to all-private below
  snrt_cluster_hw_barrier();

  int32_t *result = result_dram;

  // All-private mode, as the fp version
  l1d_xbar_config(offset);
  l1d_part(4);

  int32_t *a_core = a + m_core * cid;
  int32_t *result_core = result + m_core * cid;

  snrt_cluster_hw_barrier();

  if (KERNEL_LOCK && is_primary) {
    spatz_lock_acquire();
  }

  // Unconditional loop so host 1 also reaches l1d_cluster_flush() (every core must call it)
  for (int i = 0; i < 3; i++) {
    if (is_primary) {
      if (cid == 0) {
        start_kernel();
        timer_start = benchmark_get_cycle();
      }

      igemv_v32b_m4(a_core, b, result_core, igemv_l.M, m_core, igemv_l.N);

      snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);

      if (cid == 0) {
        timer_end = benchmark_get_cycle();
        const unsigned int timer_temp = timer_end - timer_start;
        if (i == 0) {
          timer = timer_temp;
          timer_iter1 = timer_temp;
        } else if (timer_temp < timer) {
          timer = timer_temp;
        }
        stop_kernel();
      }
    }

    // All cores flush before the first-iteration check
    if (i == 0) {
      l1d_cluster_flush();
    }

    if (is_primary && cid == 0 && i == 0) {
      for (uint32_t j = 0; j < igemv_l.M; j++) {
        if (result[j] != igemv_result[j]) {
          if (num_errors < MAX_PRINTED_ERRORS) {
            printf("Error: row %u got %d expected %d\n", j, result[j], igemv_result[j]);
          }
          num_errors++;
        }
      }
    }

    snrt_cluster_hw_barrier();
  }

  if (is_primary && cid == 0) {
    const long unsigned int performance = 1000 * 2 * igemv_l.M * igemv_l.N / timer;
    const long unsigned int utilization = performance / (2 * num_cores * 4);
    const long unsigned int performance_iter1 = 1000 * 2 * igemv_l.M * igemv_l.N / timer_iter1;
    const long unsigned int utilization_iter1 = performance_iter1 / (2 * num_cores * 4);

    write_cyc(timer);
    printf("\n----- (%d x %d) x (%d x 1) igemv, %s -----\n", igemv_l.M, igemv_l.N, igemv_l.N,
           KERNEL_LOCK ? "Spatz lock held" : "no Spatz lock");
    printf("%u wrong results out of %u.\n", num_errors, igemv_l.M);
    printf("First iteration execution took %u cycles.\n", timer_iter1);
    printf("The performance is %ld OP/1000cycle (%ld%%o utilization).\n", performance_iter1,
           utilization_iter1);
    printf("The execution took %u cycles.\n", timer);
    printf("The performance is %ld OP/1000cycle (%ld%%o utilization).\n", performance,
           utilization);
  }

  if (KERNEL_LOCK && is_primary) {
    spatz_lock_release();
  }

  // Wait for core 0 to finish displaying results
  snrt_cluster_hw_barrier();
  return num_errors ? -1 : 0;
}
