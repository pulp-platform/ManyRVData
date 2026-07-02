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

// Author: Ho Tin Hung, ETH Zurich

// Multi-spin-lock — DISCRIMINATING cross-core staleness gate for the private-L1
// (LP1) critical-section CMOs.
//
// Unlike the single-shot spin-lock test (each core touches `result` exactly
// once, always a cold miss that refills fresh from L2 — so it passes even with
// the CMOs removed), this test has each core enter the critical section REPS
// times. On the 2nd+ entry a core would re-read its OWN previously-cached copy
// of `result` (LP1 is write-through, NO coherence), which is stale w.r.t. the
// updates other cores landed at L2 in between. That stale read clobbers those
// updates -> lost increments -> `result < gold`.
//
// The `lp1_inval()` after acquiring the lock drops that stale line so the read
// misses and refetches fresh; the `lp1_wt_flush()` before releasing drains the
// write-through buffer so this core's update reaches L2 before the next winner.
//
// Expected behavior (the discriminating property):
//   - WITH the lp1_inval/lp1_wt_flush pair : result == gold  (PASS)
//   - WITHOUT them (comment the CMO calls)  : result <  gold  (FAIL)
// That fails-without / passes-with contrast is the actual proof the CMOs fix
// staleness.
//
// Kept minimal to avoid hiding the hazard: no in-loop printf and a tiny
// footprint (just `result` + `lock`), so the `result` line stays resident in
// each core's LP1 across iterations rather than being evicted (an eviction
// would turn the re-read into a miss and mask the bug). `result` is volatile so
// every iteration performs a real load/store through the LP1 instead of the
// compiler keeping it in a register.

#include <benchmark.h>
#include <lp1cache.h>
#include <snrt.h>
#include <stdint.h>
#include <stdio.h>
#include "spin_lock.h"

// Critical-section entries per core. >1 is what exposes the staleness hazard.
#define REPS 16

#define LP1

static volatile uint32_t result __attribute__((section(".data")));

spinlock_t lock;

int main() {
  const unsigned int num_cores = snrt_cluster_core_num();
  const unsigned int cid       = snrt_cluster_core_idx();

  // Rendezvous so every core starts the contended loop together.
  snrt_cluster_hw_barrier();

  for (unsigned int r = 0; r < REPS; r++) {
    spin_lock(&lock, 20);

#ifdef LP1
    // Acquire side: drop stale cached copies so the read of `result` is fresh.
    lp1_inval();
    snrt_fence();
#endif

    result += cid;

#ifdef LP1
    // Release side: drain the write-through buffer so this update reaches L2
    // before the lock is handed to the next core. Fence must precede the flush.
    snrt_fence();
    lp1_wt_flush();
#endif

    spin_unlock(&lock, 20);
  }

  // Ensure all cores finished all iterations before core 0 checks the total.
  snrt_cluster_hw_barrier();

  if (cid == 0) {
    uint32_t res  = result;
    // Each core adds cid REPS times: REPS * (0+1+...+(N-1)) = REPS * N(N-1)/2.
    uint32_t gold = REPS * ((0 + num_cores - 1) * num_cores / 2);
    printf("result: %u; gold: %u\n", res, gold);
    if (res == gold)
      printf("multi-spin-lock: PASS\n");
    else
      printf("multi-spin-lock: FAIL\n");
  }

  // Wait for core 0 to finish displaying results.
  snrt_cluster_hw_barrier();

  return 0;
}
