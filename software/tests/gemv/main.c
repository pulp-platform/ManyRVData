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
#include <lp1cache.h>
#include <team.h>   // SNRT_CACHELINE_SIZE

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

// The kernel output MUST NOT alias the golden reference.
//
// The original code did `result = gemv_result`, so the kernel overwrote the
// reference and fp_check(&result[j], &gemv_result[j]) then compared the array
// with ITSELF: x - x == 0, always below threshold.  The test could not fail --
// it would have reported success with the cache off and garbage in memory.
//
// Sized from the golden array so it tracks M with no extra macro.  Explicitly
// cacheline-aligned, and a whole number of cachelines (M is always a multiple of
// 16 floats here), so it cannot skew the alignment of whatever the linker places
// next -- see fmatmul-32b/main.c for the hang that alignment skew caused.
static T gemv_out[sizeof(gemv_result) / sizeof(T)]
    __attribute__((section(".pdcp_src"), aligned(SNRT_CACHELINE_SIZE)));

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

  // We use all-private mode for this kernel
  l1d_xbar_config(offset);
  // l1d_part(4);

  // Reset timer.  `timer` is read by the `timer_temp < timer` test on the very
  // first iteration, so it must start at max, not at whatever was on the stack.
  unsigned int timer_start, timer_end, timer_iter1;
  unsigned int timer = (unsigned int)-1;

  // Unroll in M direction?
  int unroll_m = 0;

  a = gemv_A_dram;
  b = gemv_B_dram;
  // Output buffer, distinct from the golden gemv_result -- see gemv_out above.
  result = gemv_out;

  // Calculate internal pointers
  T *a_core = a + m_core * cid;
  T *result_core = result + m_core * cid;

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
    if (sizeof(T) == 8)
      // does not support 64b
      return -2;
    else if (sizeof(T) == 4)
      gemv_v32b_m4(a_core, b, result_core, gemv_l.M, m_core, gemv_l.N);
    else
      gemv_v16b_m4(a_core, b, result_core, gemv_l.M, m_core, gemv_l.N);

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
      }
    }

    // All cores flush before first-iteration verification
    if (i == 0) {
      // Producer / release.
      snrt_fence();
      lp1_wt_flush();

      l1d_cluster_flush();

      // Consumer / acquire.  Core 0 drop the copies in its own private L1
      lp1_inval();
      snrt_fence();
    }

    if (cid == 0) {
      if (i == 0) {
        for (uint32_t j = 0; j < gemv_l.M; j++) {
          if (fp_check(&result[j], &gemv_result[j])) {
            printf("Error: idx %u Calc:", j);
            snrt_printf_float(result[j]);
            printf(",Exp:");
            snrt_printf_float(gemv_result[j]);
            printf("\n");
          }
        }
      }
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
