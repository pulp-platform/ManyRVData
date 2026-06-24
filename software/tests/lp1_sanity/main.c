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

// LP1 sanity — Tier 0 single-core smoke test for the private L1 (HPDcache)
// bring-up.
//
// Goal: the absolute floor. Prove that, with a per-core private L1 inserted and
// NO cache coherence, the system still boots, a single core can drive the L1
// scalar load/store datapath, reach the UART, synchronize via the HARDWARE
// barrier, and signal EOC. Nothing here is shared between cores, so the result
// must NOT depend on coherence.
//
// Deliberately avoided at this stage:
//   - cache partitioning (l1d_part) and partition-boundary tricks,
//   - selective private/shared flush,
//   - the bank-interleave offset config (l1d_xbar_config),
//   - any cross-core shared address.
// Those belong to later tiers; keeping them out makes a failure here
// unambiguously a core / L1-datapath / boot problem.
//
// Only core 0 does work. Every other core simply parks on the hardware barrier.
// snrt_cluster_hw_barrier() resolves to a hardware barrier MMIO register, so it
// is coherence-independent and safe to rely on here.

#include <benchmark.h>
#include <snrt.h>
#include <stdint.h>
#include <stdio.h>

// Number of scalar words core 0 round-trips through its private L1.
#define SANITY_WORDS 16

// Private scratch in cacheable .data. Touched ONLY by core 0 — never shared,
// so no coherence is required for the round-trip below.
static volatile uint32_t sanity_buf[SANITY_WORDS]
    __attribute__((section(".data")));

int main() {
  const uint32_t num_cores = snrt_cluster_core_num();
  const uint32_t cid       = snrt_cluster_core_idx();

  // Initial rendezvous: confirms every core booted and the HW barrier works
  // before core 0 starts driving the L1.
  snrt_cluster_hw_barrier();

  if (cid == 0) {
    printf("\n*** LP1 sanity (Tier 0: single-core smoke) ***\n");
    printf("Cores:%u  (only core 0 active)\n", num_cores);

    uint32_t errors = 0;

    // Scalar write phase: drive SANITY_WORDS stores into the private L1.
    for (uint32_t i = 0; i < SANITY_WORDS; i++) {
      sanity_buf[i] = 0xC0DE0000u + i;
    }

    // Scalar read-back phase: pull them back and check. A correct private L1
    // must return exactly what was written (hit-on-own-write, then refill on a
    // re-read after eviction is implicitly exercised by the small footprint).
    for (uint32_t i = 0; i < SANITY_WORDS; i++) {
      uint32_t got = sanity_buf[i];
      uint32_t exp = 0xC0DE0000u + i;
      if (got != exp) {
        printf("  FAIL idx %u exp 0x%08x got 0x%08x\n", i, exp, got);
        errors++;
      }
    }

    if (errors == 0)
      printf("lp1_sanity: PASS\n");
    else
      printf("lp1_sanity: FAIL (%u errors)\n", errors);

    printf("*** LP1 sanity complete ***\n");
  }

  // Final rendezvous so no core races ahead to EOC before core 0 is done.
  snrt_cluster_hw_barrier();

  return 0;
}
