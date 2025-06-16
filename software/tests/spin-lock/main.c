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

#include <benchmark.h>
#include <snrt.h>
#include <stdio.h>

static float result __attribute__((section(".data")));

typedef volatile int spinlock_t __attribute__((aligned(8)));
spinlock_t lock;

static inline void spin_lock (spinlock_t *lock) {
  while (__sync_lock_test_and_set(lock, 1)) { }
}

static inline void spin_unlock(spinlock_t *lock) {
  __sync_lock_release(lock);
}

int main() {
  const unsigned int num_cores = snrt_cluster_core_num();
  const unsigned int cid = snrt_cluster_core_idx();
  
  // Wait for all cores to finish
  snrt_cluster_hw_barrier();

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
    uint32_t res_hex = (uint32_t) result;
    printf("result: %x\n", res_hex);
  }

  // Wait for core 0 to finish displaying results
  snrt_cluster_hw_barrier();
  set_eoc();

  return 0;
}
