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

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

#include <snrt.h>
#include <stdio.h>
#include <stddef.h>
#include <l1cache.h>
#include "printf.h"

static float result __attribute__((section(".data")));

typedef volatile int spinlock_t __attribute__((aligned(8)));
spinlock_t lock;

static inline void spin_lock (spinlock_t *lock) {
  while (__sync_lock_test_and_set(lock, 1)) { }
}

static inline void spin_unlock(spinlock_t *lock) {
  __sync_lock_release(lock);
}

void start_kernel() {
  uint32_t *bench =
      (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                   SPATZ_CLUSTER_PERIPHERAL_SPATZ_STATUS_REG_OFFSET);
  *bench = 1;
  // snrt_start_perf_counter(SNRT_PERF_CNT0, SNRT_PERF_CNT_CYCLES, 0);
}

void stop_kernel() {
  // snrt_stop_perf_counter(SNRT_PERF_CNT0);
  uint32_t *bench =
      (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                   SPATZ_CLUSTER_PERIPHERAL_SPATZ_STATUS_REG_OFFSET);
  *bench = 0;
}

int main() {
  const unsigned int num_cores = snrt_cluster_core_num();
  const unsigned int cid = snrt_cluster_core_idx();
  
  uint32_t spm_size = 0;

  if (cid == 0) {
    // Set xbar policy to default interleave (cacheline width)
    l1d_xbar_config(256, num_cores);
    // Init the cache
    l1d_init(spm_size);
  }

  // Wait for all cores to finish
  snrt_cluster_hw_barrier();

  if (cid == 0)
    start_kernel();


  // Fetch lock
  spin_lock (&lock);

  // Each core print its core id
  printf("Core%d:hello\n", cid);

  // Add cid to the result
  result += cid;

  // Release the lock
  spin_unlock(&lock);

  snrt_cluster_hw_barrier();

  if (cid == 0) {
    stop_kernel();
    printf("result: %f\n", result);
  }

  // Wait for core 0 to finish displaying results
  snrt_cluster_hw_barrier();
  set_eoc();

  return 0;
}
