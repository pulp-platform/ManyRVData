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

// Arithmetic AMO sanity — single-core functional test for the phase-2 AMO path
// (Snitch AMO -> private L1 forwards uncacheable -> shared-L2 spatz_cache_amo RMW).
//
// Scope: ONE core (core 0) exercising every RV32 `amo*.w` arithmetic op plus the
// in-cacheline word selection. Cross-core atomicity and LR/SC are separate tests.
//
// CRITICAL verification rule (WI-5 / self-staleness is intentionally deferred):
//   We must NOT check results with a plain (cacheable) load. After an uncacheable
//   AMO, this core's L1 line for the address is NOT refreshed, so a cacheable load
//   could read a stale pre-AMO value and make a correct DUT look broken (or hide a
//   bug). Everything here is verified through L2-authoritative paths only:
//     - the AMO's own returned OLD value, and
//     - a no-op `amoor(addr, 0)` used as an atomic "read current value".
//   Initial values are likewise established with `amoswap` (not a normal store),
//   which also sidesteps any write-buffer-vs-uncached-AMO ordering hazard.
//
// Only core 0 does work; all other cores park on the hardware barrier (MMIO,
// coherence-independent), exactly as in lp1_sanity.

#include <benchmark.h>
#include <snrt.h>
#include <stdint.h>
#include <stdio.h>

// -----------------------------------------------------------------------------
// AMO primitives (explicit inline asm so the exact amo*.w instruction is tested)
//   amo<op>.w rd, rs2, (rs1):  rd <- mem[rs1] (old);  mem[rs1] <- old <op> rs2
// -----------------------------------------------------------------------------
#define DEF_AMO(suffix, mnem)                                                   \
  static inline uint32_t amo_##suffix(volatile uint32_t *addr, uint32_t val) {  \
    uint32_t old;                                                               \
    asm volatile(mnem " %0, %2, (%1)"                                           \
                 : "=r"(old)                                                    \
                 : "r"(addr), "r"(val)                                          \
                 : "memory");                                                   \
    return old;                                                                 \
  }

DEF_AMO(add,  "amoadd.w")
DEF_AMO(and,  "amoand.w")   // exercises the ATOP-CLR operand re-invert in L1-ctrl
DEF_AMO(or,   "amoor.w")
DEF_AMO(xor,  "amoxor.w")
DEF_AMO(swap, "amoswap.w")
DEF_AMO(max,  "amomax.w")   // signed
DEF_AMO(min,  "amomin.w")   // signed
DEF_AMO(maxu, "amomaxu.w")  // unsigned
DEF_AMO(minu, "amominu.w")  // unsigned

// Atomic "read current value" without modifying it (old | 0 == old).
static inline uint32_t amo_read(volatile uint32_t *addr) {
  return amo_or(addr, 0u);
}

// -----------------------------------------------------------------------------
// Test buffers (cacheable .data; the AMO op itself is marked uncacheable in HW).
// buf2 is cacheline-aligned (64B = 16 words) so word index == addr[5:2].
// -----------------------------------------------------------------------------
static volatile uint32_t buf_a __attribute__((section(".data")));

#define WS_WORDS 32  // two 64-byte cachelines worth of 32-bit words
static volatile uint32_t buf2[WS_WORDS]
    __attribute__((section(".data"), aligned(64)));

// -----------------------------------------------------------------------------
// Check helper
// -----------------------------------------------------------------------------
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
    printf("\n*** arith_amo (single-core arithmetic AMO sanity) ***\n");
    printf("Cores:%u  (only core 0 active)\n", num_cores);

    start_kernel();

    errors = 0;

    volatile uint32_t *a = &buf_a;
    uint32_t r;

    // --- Part 1: logical/arith chain on a single word -----------------------
    // Each step asserts the returned OLD value; the running memory value is
    // re-checked by the following step (and by amo_read at the end).
    amo_swap(a, 0);                          // init a=0 (ignore return)
    r = amo_add (a, 5);          CHECK("add#1",  r, 0x00000000);  // a=5
    r = amo_add (a, 3);          CHECK("add#2",  r, 0x00000005);  // a=8
    r = amo_swap(a, 0xFFFFFFFF); CHECK("swap",   r, 0x00000008);  // a=0xFFFFFFFF
    r = amo_and (a, 0x0F0F0F0F); CHECK("and",    r, 0xFFFFFFFF);  // a=0x0F0F0F0F
    r = amo_or  (a, 0x00F000F0); CHECK("or",     r, 0x0F0F0F0F);  // a=0x0FFF0FFF
    r = amo_xor (a, 0xFFFFFFFF); CHECK("xor",    r, 0x0FFF0FFF);  // a=0xF000F000
    r = amo_read(a);             CHECK("read#1", r, 0xF000F000);  // unchanged

    // --- Part 2: signed max/min --------------------------------------------
    amo_swap(a, 10);
    r = amo_max (a, 5);          CHECK("smax#1", r, 10);          // a=max(10,5)=10
    r = amo_max (a, 20);         CHECK("smax#2", r, 10);          // a=20
    r = amo_min (a, 7);          CHECK("smin#1", r, 20);          // a=7
    r = amo_min (a, 100);        CHECK("smin#2", r, 7);           // a=7
    r = amo_read(a);             CHECK("read#2", r, 7);
    // signed semantics: 0xFFFFFFFF == -1 < 1
    amo_swap(a, 0xFFFFFFFF);
    r = amo_max (a, 1);          CHECK("smax-neg", r, 0xFFFFFFFF);// a=max(-1,1)=1
    r = amo_read(a);             CHECK("read#3", r, 1);
    amo_swap(a, 0xFFFFFFFF);
    r = amo_min (a, 1);          CHECK("smin-neg", r, 0xFFFFFFFF);// a=min(-1,1)=-1
    r = amo_read(a);             CHECK("read#4", r, 0xFFFFFFFF);

    // --- Part 3: unsigned max/min ------------------------------------------
    // unsigned: 0xFFFFFFFF is the largest, not -1.
    amo_swap(a, 0xFFFFFFFF);
    r = amo_maxu(a, 1);          CHECK("umax",   r, 0xFFFFFFFF);  // a=0xFFFFFFFF
    r = amo_minu(a, 1);          CHECK("umin#1", r, 0xFFFFFFFF);  // a=min_u(...,1)=1
    r = amo_minu(a, 100);        CHECK("umin#2", r, 1);           // a=1
    r = amo_maxu(a, 0);          CHECK("umax0",  r, 1);           // a=1
    r = amo_read(a);             CHECK("read#5", r, 1);

    // --- Part 4: in-cacheline word selection -------------------------------
    // Independently RMW all 32 words across two lines; verify per-word old
    // values AND that no AMO clobbers a neighbouring word (write-back strb).
    for (uint32_t i = 0; i < WS_WORDS; i++)
      amo_swap(&buf2[i], 0x1000u + i);             // unique init per word
    for (uint32_t i = 0; i < WS_WORDS; i++) {
      uint32_t old = amo_add(&buf2[i], i);         // a[i] -> 0x1000+i+i
      if (old != (0x1000u + i)) {
        printf("  FAIL ws-old   word %2u exp 0x%08x got 0x%08x\n",
               i, 0x1000u + i, old);
        errors++;
      }
    }
    for (uint32_t i = 0; i < WS_WORDS; i++) {
      uint32_t cur = amo_read(&buf2[i]);           // expect 0x1000 + 2*i
      if (cur != (0x1000u + 2u * i)) {
        printf("  FAIL ws-final word %2u exp 0x%08x got 0x%08x\n",
               i, 0x1000u + 2u * i, cur);
        errors++;
      }
    }

    stop_kernel();

    if (errors == 0)
      printf("arith_amo: PASS\n");
    else
      printf("arith_amo: FAIL (%u errors)\n", errors);
    printf("*** arith_amo complete ***\n");
  }

  // Final rendezvous so no core races to EOC before core 0 finishes.
  snrt_cluster_hw_barrier();

  return 0;
}
