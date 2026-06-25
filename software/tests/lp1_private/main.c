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

// LP1 private — Tier 1 per-core private-slice test for the private L1 (HPDcache)
// bring-up.
//
// Goal: prove the private-L1 load/store/refill/writeback datapath works when
// ALL cores drive it in parallel, WITHOUT any coherence. Every core owns a
// disjoint, cacheline-aligned slice of two arrays; no address is ever touched
// by two cores, so correctness must not depend on coherence.
//
// Two phases, each on the core's own slice:
//   Phase A (scalar): write a known pattern, read it back, check.
//   Phase B (vector): vle32/vse32 copy src -> dst, then scalar-verify dst.
// Phase B exercises the Spatz coalescer scatter/gather through the L1.
//
// Why no false sharing: WORDS_PER_CORE is a multiple of the 16-word (64-byte)
// cacheline and the arrays are 64-byte aligned, so each core's slice occupies
// whole cachelines that no other core touches. With private L1s and no
// coherence this is exactly the case that MUST still pass.
//
// Reporting is serialized round-robin with the HARDWARE barrier (coherence-
// independent MMIO register) instead of a shared reduction, so the verdict
// itself introduces no cross-core sharing. Each core prints its own PASS/FAIL;
// CI greps for "FAIL".

#include <benchmark.h>
#include <snrt.h>
#include <stdint.h>
#include <stdio.h>

// 512-bit cacheline = 64 bytes = 16 x uint32. Keep the per-core slice a whole
// number of cachelines so adjacent cores never share a line.
#define CL_WORDS        16U
#define LINES_PER_CORE   4U
#define WORDS_PER_CORE  (CL_WORDS * LINES_PER_CORE)   // 64 words = 4 cachelines

// Upper bound on cores across the configs we build (fpu_2g=32, fpu_4g=64,
// tiny variants fewer). Sized generously; only the first num_cores slices are
// touched.
#define LP1_MAX_CORES   64U

// Two private arrays, cacheline-aligned, in cacheable .data (reached through
// the L1). Each core touches only [cid*WORDS_PER_CORE : +WORDS_PER_CORE).
static volatile uint32_t priv_src[LP1_MAX_CORES * WORDS_PER_CORE]
    __attribute__((aligned(64))) __attribute__((section(".data")));
static volatile uint32_t priv_dst[LP1_MAX_CORES * WORDS_PER_CORE]
    __attribute__((aligned(64))) __attribute__((section(".data")));

uint32_t s_errors [LP1_MAX_CORES] __attribute__((section(".data"))) = {0};
uint32_t v_errors [LP1_MAX_CORES] __attribute__((section(".data"))) = {0};

// Per-core expected pattern: distinct per core and per index.
static inline uint32_t pattern(uint32_t cid, uint32_t i) {
  return (cid << 24) | (0x00ABCD00u) | (i & 0xFFu);
}

// Vector copy count words from src to dst (both this core's private slice).
static void vec_copy(volatile uint32_t *dst, volatile uint32_t *src,
                     uint32_t count) {
  uint32_t avl = count;
  uint32_t vl;
  do {
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(avl));
    asm volatile("vle32.v v0, (%0)" ::"r"(src));
    asm volatile("vse32.v v0, (%0)" ::"r"(dst));
    src += vl;
    dst += vl;
    avl -= vl;
  } while (avl > 0);
}

int main() {
  const uint32_t num_cores = snrt_cluster_core_num();
  const uint32_t cid       = snrt_cluster_core_idx();

  // Cores beyond the static capacity must not run (would alias another slice).
  const uint32_t active = (num_cores < LP1_MAX_CORES) ? num_cores : LP1_MAX_CORES;

  volatile uint32_t *my_src = priv_src + cid * WORDS_PER_CORE;
  volatile uint32_t *my_dst = priv_dst + cid * WORDS_PER_CORE;

  // uint32_t s_errors = 0;
  // uint32_t v_errors = 0;

  if (cid == 0) {
    printf("\n*** LP1 private (Tier 1: per-core private slices) ***\n");
    printf("Cores:%u  words/core:%u (%u cachelines)\n",
           num_cores, WORDS_PER_CORE, LINES_PER_CORE);

    start_kernel();
  }

  snrt_cluster_hw_barrier();

  if (cid < active) {
    // ----- Phase A: scalar write then read-back on own slice -----
    for (uint32_t i = 0; i < WORDS_PER_CORE; i++)
      my_src[i] = pattern(cid, i);
    for (uint32_t i = 0; i < WORDS_PER_CORE; i++) {
      uint32_t got = my_src[i];
      uint32_t exp = pattern(cid, i);
      // if (got != exp) s_errors++;
      if (got != exp) s_errors[cid]++;
    }

    snrt_fence();

    // ----- Phase B: vector copy src -> dst, then scalar verify dst -----
    for (uint32_t i = 0; i < WORDS_PER_CORE; i++)
      my_dst[i] = 0u;  // clear so a no-op copy can't masquerade as success
    
    snrt_fence_spatz();      // order Snitch clear-stores BEFORE the Spatz vector stores

    vec_copy(my_dst, my_src, WORDS_PER_CORE);

    snrt_fence_spatz();      // drain Spatz vector stores BEFORE the Snitch scalar reads

    for (uint32_t i = 0; i < WORDS_PER_CORE; i++) {
      uint32_t got = my_dst[i];
      uint32_t exp = pattern(cid, i);
      // if (got != exp) v_errors++;
      if (got != exp) v_errors[cid]++;
    }

    // snrt_fence();
  }

  snrt_cluster_hw_barrier();

  if (cid == 0) {
    stop_kernel();
  }

  // Serialized per-core reporting: round-robin gated by the HW barrier, so no
  // shared memory and no coherence are involved in producing the verdict.
  for (uint32_t k = 0; k < active; k++) {
    if (cid == k) {
      // if (s_errors == 0 && v_errors == 0)
      if (s_errors[cid] == 0 && v_errors[cid] == 0)
        printf("  core %2u: PASS\n", cid);
      else
        printf("  core %2u: FAIL (scalar errors: %u, vector errors: %u)\n", cid, s_errors[cid], v_errors[cid]);
    }
    snrt_cluster_hw_barrier();
  }

  if (cid == 0)
    printf("*** LP1 private complete ***\n");

  snrt_cluster_hw_barrier();
  return 0;
}
