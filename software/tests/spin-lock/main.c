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

// This tiny test let each core add its core_id into a same memory location
// Can be used to verify the spin-lock and global shared memory access
// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

#include <benchmark.h>
#include <lp1cache.h>
#include <snrt.h>
#include <stdio.h>
#include "spin_lock.h"

static float result __attribute__((section(".data")));

spinlock_t lock;

int main() {
  const unsigned int num_cores = snrt_cluster_core_num();
  const unsigned int cid = snrt_cluster_core_idx();
  const unsigned int tid = snrt_cluster_tile_idx();

  // Wait for all cores to finish
  snrt_cluster_hw_barrier();

  // Fetch lock
  spin_lock (&lock, 20);

  // Acquire side of the critical section: drop any stale cached copies so the
  // read of `result` below misses and refetches the fresh value from L2.
  lp1_inval();
  snrt_fence();

  // Each core print its core id
  printf("T%d,C%d: Hello\n", tid, cid);

  // Add cid to the result
  result += cid;

  // Release side of the critical section: drain the write-through write buffer
  // (incl. any Spatz stores) so this core's update lands at L2 before the lock
  // is released.  The fence must precede the flush (WBUF-ordering).
  snrt_fence();
  lp1_wt_flush();

  // Release the lock
  spin_unlock(&lock, 20);

  snrt_cluster_hw_barrier();

  if (cid == 0) {
    uint32_t res_hex = (uint32_t) result;
    uint32_t res_gold = (0 + num_cores - 1) * num_cores / 2;
    printf("result: %u; gold: %u\n", res_hex, res_gold);
  }

  // Wait for core 0 to finish displaying results
  snrt_cluster_hw_barrier();

  return 0;
}
