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

// LP1 eviction — capacity / replacement test for the private L1 (HPDcache).
//
// The earlier tiers (lp1_sanity, lp1_private) only ever touch a handful of
// cachelines per core, so the L1's replacement machinery NEVER fires: no line
// is ever evicted, no line is ever refilled-after-eviction. This test closes
// that gap. It is the difference between "behaves like a buffer" and "behaves
// like a cache".
//
// Every core works on a DISJOINT, cacheline-aligned private slice (no address
// is shared, so correctness must not depend on coherence -- exactly as in
// lp1_private). Within its own slice each core:
//
//   Phase A (capacity): scalar-write a region several times the size of the L1,
//     then read it back and verify. Because the working set far exceeds the
//     8 KB cache, the early lines are guaranteed to have been evicted by the
//     time the last ones are written; reading them back forces a refill from
//     L2. Correct read-back therefore proves the whole loop: write-through to
//     L2, capacity eviction, and refill-after-eviction return the right data.
//     This phase is geometry-INDEPENDENT: any working set > cache evicts.
//
//   Phase B (conflict): touch (ways+N) distinct lines that all map to the SAME
//     set, then read them all back. Since more lines than ways contend for one
//     set, at least (lines-ways) of them must be evicted and refilled; correct
//     read-back exercises per-set victim selection specifically. This phase
//     ASSUMES direct bit-field set indexing (no set hashing); if that
//     assumption is wrong it degrades to a strided access pattern that still
//     passes -- it can never false-FAIL.
//
// No fence is placed between a core's own stores and the later loads to the
// same addresses: single-core read-after-write through eviction (store ->
// write-through -> evict -> load -> refill, including the write-buffer-vs-refill
// ordering inside HPDcache) is a correctness guarantee the cache MUST provide.
// Fencing here would mask exactly the kind of ordering bug this test should
// catch.
//
// Reporting is serialized round-robin via the HARDWARE barrier (coherence-
// independent MMIO register), and each core reports from LOCAL counters, so the
// verdict introduces no cross-core sharing whatsoever. CI greps for "FAIL".

#include <benchmark.h>
#include <snrt.h>
#include <stdint.h>
#include <stdio.h>

// ---- L1 geometry: must track HPDcacheUserCfg in hardware/src/cachepool_tile.sv
#define CL_WORDS        16U                              // 64 B line = 16 x u32
#define L1_SETS         32U
#define L1_WAYS          4U
#define L1_LINE_WORDS   CL_WORDS
#define L1_WORDS        (L1_SETS * L1_WAYS * L1_LINE_WORDS)  // 2048 w = 8 KB

// ---- Phase A: sweep a region SWEEP_MULT times the L1 to force capacity evict.
#define SWEEP_MULT       4U
#define SWEEP_WORDS      (SWEEP_MULT * L1_WORDS)         // 8192 w = 32 KB / core

// ---- Phase B: lines spaced one whole cache (sets * line) apart share a set.
#define SET_STRIDE_WORDS (L1_SETS * L1_LINE_WORDS)       // 512 w = 2 KB
#define CONFLICT_LINES   (L1_WAYS + 4U)                  // 8 > ways -> evicts

// Upper bound on cores across the configs we build (fpu_2g=32, fpu_4g=64). Only
// the first `active` slices are touched; larger configs simply idle the rest so
// no core ever aliases another's slice.
#define LP1_MAX_CORES    64U

// Per-core private region, cacheline-aligned, in uninitialized cacheable DRAM
// scratch (.dram): reached through the L1 but not image-loaded or zeroed, so the
// 2 MB footprint costs nothing in the ELF. Every word is written before it is
// read, so the lack of zero-init is irrelevant.
static volatile uint32_t sweep_buf[LP1_MAX_CORES * SWEEP_WORDS]
    __attribute__((aligned(64))) __attribute__((section(".dram")));

// Distinct per (core, index): a wrong-line refill returns a wrong index field,
// and a cross-core leak returns a wrong core field -- both are caught.
static inline uint32_t patA(uint32_t cid, uint32_t i) {
  return ((cid & 0xFFu) << 24) | (i & 0x00FFFFFFu);
}
// Distinct per (core, conflict-line k).
static inline uint32_t patB(uint32_t cid, uint32_t k) {
  return 0xB0000000u | ((cid & 0xFFFFu) << 8) | (k & 0xFFu);
}

int main() {
  const uint32_t num_cores = snrt_cluster_core_num();
  const uint32_t cid       = snrt_cluster_core_idx();
  const uint32_t active    = (num_cores < LP1_MAX_CORES) ? num_cores : LP1_MAX_CORES;

  volatile uint32_t *my_buf = sweep_buf + cid * SWEEP_WORDS;

  // Local counters only -> no shared state, no false sharing.
  uint32_t cap_err  = 0;
  uint32_t conf_err = 0;
  uint32_t first_bad_idx = 0xFFFFFFFFu;  // for a single debug line on failure
  uint32_t first_bad_exp = 0, first_bad_got = 0;

  if (cid == 0) {
    printf("\n*** LP1 eviction (capacity + conflict replacement) ***\n");
    printf("Cores:%u  L1:%uKB(%uw)  sweep:%uKB(%uw, %ux L1)  conflict:%u lines/set\n",
           num_cores, (L1_WORDS * 4U) / 1024U, L1_WORDS,
           (SWEEP_WORDS * 4U) / 1024U, SWEEP_WORDS, SWEEP_MULT, CONFLICT_LINES);

    start_kernel();
  }
  snrt_cluster_hw_barrier();

  if (cid < active) {
    // ----- Phase A: capacity sweep -----
    // Write the whole oversized region; the front of it is evicted long before
    // we reach the end.
    for (uint32_t i = 0; i < SWEEP_WORDS; i++)
      my_buf[i] = patA(cid, i);
    // Read it all back; the evicted front must refill correctly from L2.
    for (uint32_t i = 0; i < SWEEP_WORDS; i++) {
      uint32_t got = my_buf[i];
      uint32_t exp = patA(cid, i);
      if (got != exp) {
        if (cap_err == 0) { first_bad_idx = i; first_bad_exp = exp; first_bad_got = got; }
        cap_err++;
      }
    }

    // ----- Phase B: single-set conflict sweep -----
    // CONFLICT_LINES addresses, each SET_STRIDE_WORDS apart, all map to one set
    // (assuming direct bit-field indexing). Writing more than `ways` of them
    // forces evictions within that one set; reading them all back forces the
    // evicted ones to refill. Touch one word (the line's first) per line.
    for (uint32_t k = 0; k < CONFLICT_LINES; k++)
      my_buf[k * SET_STRIDE_WORDS] = patB(cid, k);
    // Read in reverse so the line written last (still resident) is checked
    // first and the earliest (already evicted) is checked last.
    for (uint32_t k = CONFLICT_LINES; k-- > 0;) {
      uint32_t got = my_buf[k * SET_STRIDE_WORDS];
      uint32_t exp = patB(cid, k);
      if (got != exp) conf_err++;
    }
  }

  snrt_cluster_hw_barrier();

  if (cid == 0) {
    stop_kernel();
  }

  // Serialized per-core reporting, round-robin gated by the HW barrier.
  for (uint32_t k = 0; k < active; k++) {
    if (cid == k) {
      if (cap_err == 0 && conf_err == 0) {
        printf("  core %2u: PASS\n", cid);
      } else {
        printf("  core %2u: FAIL (capacity errors: %u, conflict errors: %u)\n",
               cid, cap_err, conf_err);
        if (first_bad_idx != 0xFFFFFFFFu)
          printf("           first cap miss @w%u exp 0x%08x got 0x%08x\n",
                 first_bad_idx, first_bad_exp, first_bad_got);
      }
    }
    snrt_cluster_hw_barrier();
  }

  if (cid == 0)
    printf("*** LP1 eviction complete ***\n");

  snrt_cluster_hw_barrier();
  return 0;
}
