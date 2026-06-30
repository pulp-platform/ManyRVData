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

// LR/SC sanity — single-core functional test for the phase-2 atomic path
// (Snitch LR/SC -> private L1 forwards uncacheable -> shared-L2 spatz_cache_amo
// reservation + conditional store).
//
// Reservation model in THIS design (spatz_cache_amo.sv):
//   - LR places a reservation {core, addr}                       (:171-175)
//   - SC succeeds iff a valid same-core reservation matches addr,
//     returns 0; it then CLEARS the reservation                  (:190-192)
//   - SC return code: 0 = success, 1 = fail                      (:155)
//   - Only a store from ANOTHER core breaks a reservation        (:183-187);
//     same-core ops never break it. So we cannot fail an SC with an
//     intervening same-core store -- failures are triggered STRUCTURALLY:
//       * SC with no preceding LR     -> fail (no valid reservation)
//       * second SC after a first SC  -> fail (first SC cleared it)
//
// CRITICAL verification rule (same as arith_amo / WI-5 deferred):
//   Never read back with a plain (cacheable) load -- after an uncacheable
//   atomic this core's L1 line is not refreshed. Memory state is checked only
//   through L2-authoritative paths: the SC return code, the LR return value,
//   and a no-op `amo_or(addr,0)` used as an atomic "read current value".
//   Initial values are established with `amo_swap` (AMOSwap, not AMOLR, so it
//   does not itself set a reservation).
//
// To keep the LR/SC pair tight, all return values of a scenario are captured
// BEFORE any CHECK/printf, so no spill or UART traffic lands between LR and SC.
//
// Only core 0 does work; all other cores park on the hardware barrier.

#include <benchmark.h>
#include <snrt.h>
#include <stdint.h>
#include <stdio.h>

// -----------------------------------------------------------------------------
// Atomic primitives (explicit inline asm so the exact instruction is tested)
// -----------------------------------------------------------------------------
static inline uint32_t load_reserved(volatile uint32_t *addr) {
  uint32_t val;
  asm volatile("lr.w %0, (%1)" : "=r"(val) : "r"(addr) : "memory");
  return val;
}

// sc.w rd, rs2, (rs1): rd <- 0 on success / 1 on failure; mem[rs1] <- rs2 on success
static inline uint32_t store_conditional(volatile uint32_t *addr, uint32_t val) {
  uint32_t status;
  asm volatile("sc.w %0, %2, (%1)" : "=r"(status) : "r"(addr), "r"(val) : "memory");
  return status;
}

static inline uint32_t amo_swap(volatile uint32_t *addr, uint32_t val) {
  uint32_t old;
  asm volatile("amoswap.w %0, %2, (%1)" : "=r"(old) : "r"(addr), "r"(val) : "memory");
  return old;
}

// Atomic "read current value" without modifying it (old | 0 == old).
static inline uint32_t amo_read(volatile uint32_t *addr) {
  uint32_t old;
  asm volatile("amoor.w %0, %2, (%1)" : "=r"(old) : "r"(addr), "r"(0u) : "memory");
  return old;
}

// -----------------------------------------------------------------------------
// Test buffer (cacheable .data; the atomics themselves are uncacheable in HW).
// -----------------------------------------------------------------------------
static volatile uint32_t buf_a __attribute__((section(".data")));

static uint32_t errors;

#define CHECK(label, got, exp)                                                  \
  do {                                                                          \
    uint32_t _g = (got), _e = (exp);                                           \
    if (_g != _e) {                                                            \
      printf("  FAIL %-14s exp 0x%08x got 0x%08x\n", (label), _e, _g);        \
      errors++;                                                                 \
    }                                                                           \
  } while (0)

int main() {
  const uint32_t num_cores = snrt_cluster_core_num();
  const uint32_t cid       = snrt_cluster_core_idx();

  // Rendezvous: confirm every core booted and the HW barrier works.
  snrt_cluster_hw_barrier();

  if (cid == 0) {
    printf("\n*** lrsc_amo (single-core LR/SC sanity) ***\n");
    printf("Cores:%u  (only core 0 active)\n", num_cores);

    start_kernel();

    errors = 0;
    volatile uint32_t *a = &buf_a;

    // --- Scenario 1: LR; SC(same addr) -> success, value written -----------
    {
      amo_swap(a, 0xAAAA0000u);                 // init (no reservation set)
      uint32_t lrval = load_reserved(a);        // reserve {core0, a}
      uint32_t sc    = store_conditional(a, 0xBBBB1111u); // matches -> success
      uint32_t mem   = amo_read(a);
      CHECK("s1.lr",  lrval, 0xAAAA0000u);      // LR returns current value
      CHECK("s1.sc",  sc,    0u);               // 0 = success
      CHECK("s1.mem", mem,   0xBBBB1111u);      // store took effect
    }

    // --- Scenario 2: SC with no preceding LR -> fail, memory unchanged -----
    // (Scenario 1's successful SC already cleared the reservation, so there is
    //  no valid reservation entering here.)
    {
      amo_swap(a, 0xCCCC2222u);                 // init
      uint32_t sc  = store_conditional(a, 0xDDDD3333u);  // no LR -> fail
      uint32_t mem = amo_read(a);
      CHECK("s2.sc",  sc,  1u);                 // 1 = fail
      CHECK("s2.mem", mem, 0xCCCC2222u);        // unchanged
    }

    // --- Scenario 3: LR; SC; SC -> first succeeds, second fails ------------
    {
      amo_swap(a, 0x11110000u);                 // init
      uint32_t lrval = load_reserved(a);        // reserve
      uint32_t sc1   = store_conditional(a, 0x22221111u); // success, clears resv
      uint32_t sc2   = store_conditional(a, 0x33332222u); // no resv -> fail
      uint32_t mem   = amo_read(a);
      CHECK("s3.lr",  lrval, 0x11110000u);
      CHECK("s3.sc1", sc1,   0u);               // first SC success
      CHECK("s3.sc2", sc2,   1u);               // second SC fail
      CHECK("s3.mem", mem,   0x22221111u);      // only the first store landed
    }

    stop_kernel();

    if (errors == 0)
      printf("lrsc_amo: PASS\n");
    else
      printf("lrsc_amo: FAIL (%u errors)\n", errors);
    printf("*** lrsc_amo complete ***\n");
  }

  // Final rendezvous so no core races to EOC before core 0 finishes.
  snrt_cluster_hw_barrier();

  return 0;
}
