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
#include <team.h>   // SNRT_CACHELINE_SIZE

#include DATAHEADER
#include "kernel/fmatmul.c"

// ---------------------------------------------------------------------------
// Private-L1 (LP1): no coherency protection required.  Verified 2026-07-13.
//
// The matmul needs none by construction: A and B are read-only shared, and each
// core writes and verifies its OWN rows of C (producer == consumer).
//
// The only cross-core state is `error_arr` (verification bookkeeping): core 0
// publishes the pointer and every core reads it; each core writes its own slot
// and core 0 reads them all.  In principle that wants a release/acquire pair.  In
// practice it works unprotected, and we CONFIRMED it rather than assumed it --
// injecting a deliberate error into core 1's partition of C, with the CMOs
// compiled out, still reports "Core 1 error 1" on core 0.  The check is not blind.
//
// Why it works: the kernel streams tens of KB of matrices through each private L1,
// which evicts the small slot cachelines from core 0 long before it re-reads them,
// so its reads miss down to L2 where the peers' write-through values already sit.
// That is a CAPACITY ACCIDENT, not a guarantee.  If the bookkeeping ever grows a
// fast path, or the matrices shrink below the L1, core 0 could hit its own stale
// zeros and report a silent PASS.  The `#ifdef LP1` blocks below are the correct
// discipline, kept and working -- enable the define to turn them back on.
//
// NOTE the snrt_fence() before verify_matrix is deliberately NOT under LP1.  It is
// Snitch/Spatz ordering, not coherence: snrt_cluster_hw_barrier() does not drain
// Spatz, so the scalar verify can otherwise read C before this core's own async
// vse32.v stores have retired.  That hazard is real with or without a private L1.
//
// (The bug that actually broke this test was ALIGNMENT, not coherence -- see the
// error_ref comment below.)
// #define LP1

#ifdef LP1
#include <lp1cache.h>
#endif

#ifndef KERNEL_SIZE
#define KERNEL_SIZE 4
#endif

float *a;
float *b;
float *c;

// Pointer to per-core error slots; allocated in main by core 0 via snrt_l1alloc.
// Placed in .data so the pointer word lives at a fixed shared DRAM address.
//
// MUST occupy a whole cacheline.  This object sits at the head of .data, and
// gemm_A/B/C_dram follow it with only a float's natural 4-byte alignment.  A bare
// 4-byte pointer here therefore starts all three matrices at 4 mod 64:
//
//   80003940  4        error_arr
//   80003944  0x10000  gemm_A_dram   <-- 4 mod 64, and the skew propagates
//
// That breaks TWO alignment assumptions at once:
//   * 64B cacheline -- adjacent cores' row partitions of C false-share a line.
//   * 16B LP1 coalescing window (wordWidth=128b, 4 lanes x 4B) -- Spatz's 4 lanes
//     stop fitting in one window, so every vector access straddles two and the
//     coalescer splits it in half.  cachepool_l1_ctrl.sv's coal_be rebuilds the
//     byte-enable from the LANE INDEX, which is only valid when aligned.
//
// Note `aligned(64)` on the pointer alone would NOT fix this: it would start the
// symbol on a boundary but its size is still 4, so gemm_A_dram still lands at +4.
// The padding is what does the work -- it makes the whole slot a multiple of the
// cacheline, so whatever the linker places next starts on a 64B boundary.
// int *error_arr __attribute__((section(".data")));
// `ptr` is volatile and error_ref has external linkage on purpose: core 0 writes
// the pointer and every other core reads it.  If this were `static`, the compiler
// could see that the only store is under `if (cid == 0)` and constant-fold the
// pointer to its initial NULL on every other core.
typedef struct {
  int     *volatile ptr;
  uint8_t           _pad[SNRT_CACHELINE_SIZE - sizeof(int *)];
} error_ref_t;

error_ref_t error_ref
    __attribute__((section(".data"), aligned(SNRT_CACHELINE_SIZE)));

_Static_assert(sizeof(error_ref_t) == SNRT_CACHELINE_SIZE,
               "error_ref must occupy exactly one cacheline, or it will skew the "
               "alignment of gemm_A/B/C_dram in .data");

#define error_arr (error_ref.ptr)

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

  // Set matrix dimension
  kernel_size = KERNEL_SIZE;

  // Cap active cores to the number of row-tiles the matrix provides
  unsigned int active_cores = snrt_min(num_cores, gemm_l.M / kernel_size);

  // Allocate and zero the error array while the cache is still in shared mode,
  // so the pointer write and slot initialisation are visible to all cores.
  if (cid == 0) {
    error_arr = (int *)snrt_malloc(active_cores * sizeof(int));
    for (unsigned int i = 0; i < active_cores; i++)
      error_arr[i] = 0;
  }

  // Barrier here ensures all cores see error_arr before the cache mode changes.
  snrt_cluster_hw_barrier();

  // Set xbar policy and switch to private cache mode for the matmul.
  // All cores will access the same B; scramble based on cacheline.
  l1d_xbar_config(5);
  // l1d_part(4);

  a = gemm_A_dram;
  b = gemm_B_dram;
  c = gemm_C_dram;

  // Reset timer
  timer = (unsigned int)-1;

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

  // Initialize matrices
  #ifdef DEBUG
  if (cid == 0) {
    printf ("a:%x\n", a);
    printf ("b:%x\n", b);
    printf ("c:%x\n", c);

    printf ("active_cores:%u\n", active_cores);
    printf ("m_start:%x\n", m_start);
    printf ("m_end:%x\n",   m_end);

    printf ("p_start:%x\n", p_start);
    printf ("p_end:%x\n", p_end);
  }
  #endif

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
      return -1;
    }

    // NOT inside #ifdef LP1 -- this is not a coherency guard.  The kernel wrote C
    // with async Spatz vector stores (vse32.v), but verify_matrix reads C back with
    // SCALAR loads, and snrt_cluster_hw_barrier() does not drain Spatz.  Without
    // this fence the verify can read C before this core's own stores have retired.
    // The hazard is Snitch/Spatz ordering: it exists with or without a private L1
    // and with or without coherence.  No CMO needed -- producer and consumer of C
    // are the same core, so its private L1 is self-consistent once ordered.
    snrt_fence();

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
      if (cid < active_cores) {
        float *check_C    = gemm_C_dram + cid * (gemm_l.M / active_cores) * gemm_l.N;
        float *check_gold = (float *)gemm_checksum + cid * (gemm_l.M / active_cores);

        error_arr[cid] = verify_matrix(check_C, (const float *)check_gold,
                                       (gemm_l.M / active_cores), gemm_l.N);
      }

      snrt_cluster_hw_barrier();

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

      snrt_cluster_hw_barrier();
    }
  }

  // Check and display results
  if (cid == 0) {
    long unsigned int performance =
        1000 * 2 * gemm_l.M * gemm_l.N * gemm_l.K / timer;
    long unsigned int utilization = performance / (2 * active_cores * 4);

    long unsigned int performance_iter1 =
        1000 * 2 * gemm_l.M * gemm_l.N * gemm_l.K / timer_iter1;
    long unsigned int utilization_iter1 = performance_iter1 / (2 * active_cores * 4);

    write_cyc(timer);
    printf("\n----- (%dx%d) sp fmatmul -----\n", gemm_l.M, gemm_l.N);
    printf("Active cores %u \n", active_cores);
    printf("First iteration execution took %u cycles.\n", timer_iter1);
    printf("The performance is %ld OP/1000cycle (%ld%%o utilization).\n",
           performance_iter1, utilization_iter1);
    printf("The execution took %u cycles.\n", timer);
    printf("The performance is %ld OP/1000cycle (%ld%%o utilization).\n",
           performance, utilization);
  }

  // Wait for all cores to finish
  snrt_cluster_hw_barrier();
  if (error_arr[0] > 0)
    return -1;

  return 0;
}
