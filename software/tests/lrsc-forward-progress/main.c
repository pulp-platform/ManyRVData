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

// LR/SC forward-progress stress test.
//
// Every core runs a symmetric compare-and-swap retry loop (LR/SC on RV32A)
// against ONE shared word, so all reservations are served by the same AMO unit
// -- the case the RISC-V spec's forward-progress guarantee for constrained
// LR/SC sequences must cover.
//
// Before the reservation fix in spatz_cache_amo.sv, an LR from any core
// invalidated whatever reservation was held, so the cores could clobber each
// other's reservations in a ring and no SC would ever succeed: the test hangs.
// With the fix (incumbent reservation is kept, aged out after a grace period)
// one core always wins each round and the loop terminates.
//
// Author: Zexin Fu <zexifu@iis.ee.ethz.ch>

#include <benchmark.h>
#include <snrt.h>
#include <stdatomic.h>
#include <stdio.h>

#ifndef CAS_ITERATIONS
#define CAS_ITERATIONS 16
#endif

// Single contended word: one address => one AMO unit => one reservation.
static _Atomic uint32_t counter __attribute__((section(".data")));
// Per-core retry census, to show the contention actually happened.
static _Atomic uint32_t total_retries __attribute__((section(".data")));

int main() {
  const unsigned int num_cores = snrt_cluster_core_num();
  const unsigned int cid = snrt_cluster_core_idx();

  if (cid == 0) {
    atomic_store_explicit(&counter, 0, memory_order_relaxed);
    atomic_store_explicit(&total_retries, 0, memory_order_relaxed);
  }

  snrt_cluster_hw_barrier();

  uint32_t retries = 0;
  for (unsigned int i = 0; i < CAS_ITERATIONS; i++) {
    uint32_t expected = atomic_load_explicit(&counter, memory_order_relaxed);
    // Symmetric CAS retry loop: this is the constrained LR/SC sequence.
    while (!atomic_compare_exchange_strong_explicit(
               &counter, &expected, expected + 1,
               memory_order_relaxed, memory_order_relaxed)) {
      retries++;
    }
  }
  atomic_fetch_add_explicit(&total_retries, retries, memory_order_relaxed);

  snrt_cluster_hw_barrier();

  int ret = 0;
  if (cid == 0) {
    const uint32_t expect = (uint32_t)num_cores * CAS_ITERATIONS;
    const uint32_t got = atomic_load_explicit(&counter, memory_order_relaxed);
    const uint32_t rt = atomic_load_explicit(&total_retries, memory_order_relaxed);
    if (got == expect) {
      printf("[PASS] lrsc-forward-progress: %u cores x %u CAS = %u, retries=%u\n",
             num_cores, (unsigned)CAS_ITERATIONS, got, rt);
    } else {
      printf("[FAIL] lrsc-forward-progress: expected %u, got %u, retries=%u\n",
             expect, got, rt);
      ret = 1;
    }
  }

  snrt_cluster_hw_barrier();
  return ret;
}
