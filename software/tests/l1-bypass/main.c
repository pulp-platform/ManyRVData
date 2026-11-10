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

// Author: Diyou Shen     <dishen@iis.ee.ethz.ch>

// Directed test of the L1 bypass path. With L1D_BYPASS set, the private range
// [L1D_ADDR, stack) skips the L1 data cache and goes straight to DRAM; the test
// sets L1D_ADDR to 0xB000_0000.
//
// The buffer sits at the start of .l1_bypass and every word is preloaded with
// its own address, so a word returned from the wrong slot, part or line is
// caught by value. Each core works on its own slice:
//   0. switching the bypass keeps dirty cached data (no implicit invalidate)
//   1. scalar read of the preloaded pattern
//   2. vector unit-stride and strided read of the preloaded pattern
//   3. scalar word/halfword/byte writes, read-after-write
//   4. vector unit-stride and strided writes (strided: partial strobes per slot)
//   5. read of the neighbour core's slice (visibility through DRAM)
//   6. timing, core 0 only: a latency-bound pointer chase over a region, five
//      visits, one outlier dropped (DRAM refresh makes single visits noisy). With
//      the bypass off the region hits after its cold visit; with it on another
//      region never does and stays far above the hit time.
// In parts 0-5 half of each tile's banks are private: the private/bypass range is
// served by the local tile, everything below L1D_ADDR (counters, scratch) is
// shared and coherent across tiles. The cache xbar interleaves at cache-line
// granularity, so the shared data spreads over all controllers. Part 6 makes every
// bank private and tile-folded, so core 0 only reaches its own tile's banks and the
// timing is free of other cores and remote tiles.
//
// Strides of 12 B and unaligned e8 copies are left out: they hang on the cached
// path as well (pre-existing, independent of the bypass).

#include <benchmark.h>
#include <l1cache.h>
#include <snrt.h>
#include <stdint.h>
#include <stdio.h>
#include <spatz_lock.h>

#define BYP_BASE  0xB0000000u
// Words per half: 16 KiB, so each half spans every DRAM channel (1 KiB interleave).
#define BYP_WORDS 4096u

// Each word initialised to its own address (preprocessor expansion, no data file).
#define P1(b, i)    ((b) + 4u * (i))
#define P4(b, i)    P1(b, i), P1(b, (i) + 1), P1(b, (i) + 2), P1(b, (i) + 3)
#define P16(b, i)   P4(b, i), P4(b, (i) + 4), P4(b, (i) + 8), P4(b, (i) + 12)
#define P64(b, i)   P16(b, i), P16(b, (i) + 16), P16(b, (i) + 32), P16(b, (i) + 48)
#define P256(b, i)  P64(b, i), P64(b, (i) + 64), P64(b, (i) + 128), P64(b, (i) + 192)
#define P1024(b, i) P256(b, i), P256(b, (i) + 256), P256(b, (i) + 512), P256(b, (i) + 768)
#define P4096(b, i) P1024(b, i), P1024(b, (i) + 1024), P1024(b, (i) + 2048), P1024(b, (i) + 3072)
#define A1(i)       P1(BYP_BASE, i)

// Part 6 timing regions: 16 lines each, C (cached) then B (bypassed), after the two halves.
#define T_REG_WORDS  256u
#define T_BASE_WORD  (2u * BYP_WORDS)
#define T_VISITS     5u
#define T_LINE_BYTES 64u
#define T_LINES      (T_REG_WORDS * 4u / T_LINE_BYTES)

// Read-only half, read/write half, then the two timing regions.
static uint32_t byp_buf[T_BASE_WORD + 2 * T_REG_WORDS]
    __attribute__((section(".l1_bypass"), used)) = {
  P4096(BYP_BASE, 0), P4096(BYP_BASE, BYP_WORDS),
  P256(BYP_BASE, T_BASE_WORD), P256(BYP_BASE, T_BASE_WORD + T_REG_WORDS)
};

// Cached scratch, one slice per core.
#define MAX_CORES       64u
#define MAX_SLICE_WORDS (BYP_WORDS / 16u)
static uint32_t vbuf[MAX_CORES][MAX_SLICE_WORDS] __attribute__((section(".data")));
static int      error_cnt[MAX_CORES] __attribute__((section(".data")));

// Part 0: a cached value that is dirty when the bypass is switched
#define CANARY_INIT 0xDEADBEEFu
#define CANARY_NEW  0x1234ABCDu
static volatile uint32_t canary __attribute__((section(".data"))) = CANARY_INIT;

// Self-check of the reporting: 1 makes the last core report one error in part 1
#ifndef LBYP_INJECT_ERR
#define LBYP_INJECT_ERR 0
#endif

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

static inline void vec_copy(uint32_t *dst, const uint32_t *src, uint32_t count) {
  uint32_t avl = count;
  uint32_t vl;
  do {
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(avl));
    asm volatile("vle32.v v0, (%0)" : : "r"(src) : "memory");
    asm volatile("vse32.v v0, (%0)" : : "r"(dst) : "memory");
    src += vl;
    dst += vl;
    avl -= vl;
  } while (avl > 0);
}

// dst[i] = src[i * stride_words], unit-stride store.
static inline void vec_gather_strided(uint32_t *dst, const uint32_t *src,
                                      uint32_t stride_words, uint32_t count) {
  uint32_t avl = count;
  uint32_t vl;
  const uint32_t stride_b = stride_words * sizeof(uint32_t);
  do {
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(avl));
    asm volatile("vlse32.v v0, (%0), %1" : : "r"(src), "r"(stride_b) : "memory");
    asm volatile("vse32.v v0, (%0)" : : "r"(dst) : "memory");
    src += vl * stride_words;
    dst += vl;
    avl -= vl;
  } while (avl > 0);
}

// dst[i * stride_words] = src[i], strided store.
static inline void vec_scatter_strided(uint32_t *dst, const uint32_t *src,
                                       uint32_t stride_words, uint32_t count) {
  uint32_t avl = count;
  uint32_t vl;
  const uint32_t stride_b = stride_words * sizeof(uint32_t);
  do {
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(avl));
    asm volatile("vle32.v v0, (%0)" : : "r"(src) : "memory");
    asm volatile("vsse32.v v0, (%0), %1" : : "r"(dst), "r"(stride_b) : "memory");
    src += vl;
    dst += vl * stride_words;
    avl -= vl;
  } while (avl > 0);
}

// Scalar stores and vector loads use different ports and are not ordered with
// each other: drain the scalar stores before Spatz reads the same buffer.
static inline void scalar_to_vector_fence(void) { asm volatile("fence" ::: "memory"); }

// One timed visit of a part 6 region: a pointer chase over its lines. Every word holds its own
// address, so each load returns the address of its line and the next load depends on it; the
// visit is latency-bound, T_LINES times the load latency.
static uint32_t timed_visit(const uint32_t *ptr) {
  uint32_t a = (uint32_t)ptr;
  uint32_t t0 = benchmark_get_cycle();
  for (uint32_t l = 0; l < T_LINES; l++) {
    a = *(volatile uint32_t *)a + T_LINE_BYTES;
  }
  // Use the last loaded value before reading the cycle counter, so its latency is counted
  asm volatile("mv %0, %0" : "+r"(a));
  return benchmark_get_cycle() - t0;
}

// Words of a part 6 region that do not hold their own address
static uint32_t region_errors(const uint32_t *ptr, uint32_t base_word) {
  uint32_t err = 0;
  for (uint32_t i = 0; i < T_REG_WORDS; i++) {
    err += (ptr[i] != A1(base_word + i));
  }
  return err;
}

// Index of the visit farthest from the mean of t[0..n): the one outlier that is dropped
static uint32_t outlier_idx(const uint32_t *t, uint32_t n) {
  uint32_t sum = 0;
  for (uint32_t i = 0; i < n; i++) sum += t[i];
  const uint32_t mean = sum / n;
  uint32_t idx = 0, dmax = 0;
  for (uint32_t i = 0; i < n; i++) {
    const uint32_t d = (t[i] > mean) ? t[i] - mean : mean - t[i];
    if (d > dmax) {
      dmax = d;
      idx  = i;
    }
  }
  return idx;
}

// Mean of t[0..n) without t[skip]
static uint32_t mean_skip(const uint32_t *t, uint32_t n, uint32_t skip) {
  uint32_t sum = 0;
  for (uint32_t i = 0; i < n; i++) sum += (i == skip) ? 0 : t[i];
  return sum / (n - 1);
}

// 6. Timing on core 0 alone, T_VISITS visits per region, one outlier dropped (DRAM refresh
// and the like make single visits noisy). Every hart calls it, since the l1d_* helpers use
// the cluster barrier. Returns the number of failed checks (core 0 only).
static int bypass_timing(int is_core0) {
  int fails = 0;
  uint32_t tc[T_VISITS], tb[T_VISITS];
  uint32_t hot = 0;
  const uint32_t c_word = T_BASE_WORD;
  const uint32_t b_word = T_BASE_WORD + T_REG_WORDS;

  // Every bank private and tile-folded; this flushes, so both regions start cold
  l1d_part_folded(snrt_cluster_vpu_per_tile(), L1D_FOLD_TILE);

  // Bypass off: region C is cached in core 0's own tile and hits on the second visit
  l1d_bypass(0);
  if (is_core0) {
    for (uint32_t v = 0; v < T_VISITS; v++) tc[v] = timed_visit(&byp_buf[c_word]);
    const uint32_t err = region_errors(&byp_buf[c_word], c_word);
    // Hot: mean of the visits after the cold one, outlier dropped; < 0.7x the cold visit
    hot = mean_skip(&tc[1], T_VISITS - 1, outlier_idx(&tc[1], T_VISITS - 1));
    const int ok = (10 * hot < 7 * tc[0]);
    printf("6  cached, bypass off: %u %u %u %u %u, hot %u -> %s (%u data errors)\n",
           tc[0], tc[1], tc[2], tc[3], tc[4], hot, ok ? "PASS" : "FAIL", err);
    fails += !ok + (err != 0);
  }

  // Bypass on: region B was never cached and goes to DRAM on every visit
  l1d_bypass(1);
  if (is_core0) {
    for (uint32_t v = 0; v < T_VISITS; v++) tb[v] = timed_visit(&byp_buf[b_word]);
    const uint32_t err = region_errors(&byp_buf[b_word], b_word);
    // Never a hit: the repeated visits (outlier dropped) stay above 2x the cached hot visits
    const uint32_t warm = mean_skip(&tb[1], T_VISITS - 1, outlier_idx(&tb[1], T_VISITS - 1));
    const int ok = (warm > 2 * hot);
    printf("6  bypass on:          %u %u %u %u %u, warm %u -> %s (%u data errors)\n",
           tb[0], tb[1], tb[2], tb[3], tb[4], warm, ok ? "PASS" : "FAIL", err);
    fails += !ok + (err != 0);
  }
  l1d_bypass(0);
  return fails;
}

static inline uint32_t pat_a(uint32_t cid, uint32_t i) { return 0xA0000000u | (cid << 16) | i; }
static inline uint32_t pat_b(uint32_t cid, uint32_t i) { return 0x5B000000u | (cid << 16) | i; }
static inline uint32_t pat_c(uint32_t cid, uint32_t i) { return 0xC3000000u | (cid << 16) | i; }

static int report(const char *name, uint32_t cid, uint32_t num_cores) {
  snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);
  int fails = 0;
  if (cid == 0) {
    int total = 0;
    for (uint32_t c = 0; c < num_cores; c++) {
      total += error_cnt[c];
    }
    printf("%s: %s (%d errors)\n", name, total ? "FAIL" : "PASS", total);
    fails = (total != 0);
  }
  snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);
  return fails;
}

// -----------------------------------------------------------------------------
// main
// -----------------------------------------------------------------------------
int main() {
  // One hart per Spatz runs the test (dual-scalar CCs share a Spatz)
  const uint32_t num_cores  = snrt_cluster_vpu_num();
  const uint32_t cid        = snrt_cluster_vpu_idx();
  const int      is_primary = snrt_cluster_is_primary();
  int num_fails = 0;

  // Buffers are sized for MAX_CORES: reject larger clusters on every hart, before
  // any collective call, so nothing runs out of bounds or waits in a barrier.
  if (num_cores > MAX_CORES) {
    if (snrt_cluster_core_idx() == 0) {
      printf("FATAL: l1-bypass supports at most %u VPUs (got %u)\n", MAX_CORES, num_cores);
    }
    snrt_cluster_hw_barrier();
    return -1;
  }

  // Cache-line interleaving (log2(512/8)), so the shared data spreads over all controllers
  l1d_xbar_config(6);

  // 0. Dirty cached data survives switching the bypass on and off
  if (snrt_cluster_core_idx() == 0) {
    canary = CANARY_NEW;
  }
  l1d_bypass(1);
  l1d_bypass(0);
  const int canary_ok = (canary == CANARY_NEW);

  // Half the banks tile-private, private range from BYP_BASE up, bypass on. Every
  // hart calls the l1d_* helpers (they use the cluster barrier).
  l1d_part(snrt_cluster_vpu_per_tile() / 2);
  l1d_addr(BYP_BASE);
  l1d_bypass(1);

  if (!is_primary) {
    // Matches the primaries' part 6 (l1d_* calls) and final barrier
    bypass_timing(0);
    snrt_cluster_hw_barrier();
    return 0;
  }
  spatz_lock_acquire();

  uint32_t slice = BYP_WORDS / num_cores;
  if (slice > MAX_SLICE_WORDS) {
    slice = MAX_SLICE_WORDS;
  }

  if (cid == 0) {
    printf("*** L1 bypass test ***\n");
    printf("0  bypass switch keeps dirty data: %s\n", canary_ok ? "PASS" : "FAIL");
    num_fails += !canary_ok;
    printf("Cores:%u  buffer:0x%x  slice:%u words\n", num_cores, (uint32_t)byp_buf, slice);
    if ((uint32_t)byp_buf != BYP_BASE) {
      printf("FATAL: buffer not at 0x%x\n", BYP_BASE);
      num_fails++;
    }
  }
  snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);

  const uint32_t ro_base = cid * slice;
  const uint32_t rw_base = BYP_WORDS + cid * slice;
  volatile uint32_t *ro  = &byp_buf[ro_base];
  volatile uint32_t *rw  = &byp_buf[rw_base];
  uint32_t *vb           = vbuf[cid];
  int err;

  // 1. Scalar read of the preloaded pattern
  err = 0;
  for (uint32_t i = 0; i < slice; i++) {
    err += (ro[i] != A1(ro_base + i));
  }
  err += (LBYP_INJECT_ERR && cid == num_cores - 1);
  error_cnt[cid] = err;
  num_fails += report("1  scalar read", cid, num_cores);

  // 2a. Vector unit-stride read
  vec_copy(vb, (const uint32_t *)ro, slice);
  snrt_fence_spatz();
  err = 0;
  for (uint32_t i = 0; i < slice; i++) {
    err += (vb[i] != A1(ro_base + i));
  }
  error_cnt[cid] = err;
  num_fails += report("2a vector read", cid, num_cores);

  // 2b. Vector strided read (every second word, crosses parts and lines)
  const uint32_t n_str = slice / 2;
  vec_gather_strided(vb, (const uint32_t *)ro, 2, n_str);
  snrt_fence_spatz();
  err = 0;
  for (uint32_t i = 0; i < n_str; i++) {
    err += (vb[i] != A1(ro_base + 2 * i));
  }
  error_cnt[cid] = err;
  num_fails += report("2b vector strided read", cid, num_cores);

  // 3. Scalar writes: word, then halfword and byte overwrites, each read back
  // right away (read-after-write on the same address).
  err = 0;
  for (uint32_t i = 0; i < slice; i++) {
    uint32_t exp = pat_a(cid, i);
    rw[i] = exp;
    err += (rw[i] != exp);
    if (i % 2 == 0) {
      volatile uint16_t *h = (volatile uint16_t *)&rw[i] + 1;
      *h = (uint16_t)(0xBEEF ^ i);
      exp = (exp & 0x0000FFFFu) | ((uint32_t)(uint16_t)(0xBEEF ^ i) << 16);
      err += (rw[i] != exp);
    }
    if (i % 3 == 0) {
      volatile uint8_t *b = (volatile uint8_t *)&rw[i] + 1;
      *b = (uint8_t)(0x5A ^ i);
      exp = (exp & 0xFFFF00FFu) | ((uint32_t)(uint8_t)(0x5A ^ i) << 8);
      err += (rw[i] != exp);
    }
  }
  error_cnt[cid] = err;
  num_fails += report("3  scalar write/RAW", cid, num_cores);

  // 4a. Vector unit-stride write of pattern A, scalar read back
  for (uint32_t i = 0; i < slice; i++) {
    vb[i] = pat_a(cid, i);
  }
  scalar_to_vector_fence();
  vec_copy((uint32_t *)rw, vb, slice);
  snrt_fence_spatz();
  err = 0;
  for (uint32_t i = 0; i < slice; i++) {
    err += (rw[i] != pat_a(cid, i));
  }
  error_cnt[cid] = err;
  num_fails += report("4a vector write", cid, num_cores);

  // 4b. Vector strided write of pattern B into every second word
  const uint32_t n_half = slice / 2;
  for (uint32_t i = 0; i < n_half; i++) {
    vb[i] = pat_b(cid, i);
  }
  scalar_to_vector_fence();
  vec_scatter_strided((uint32_t *)rw, vb, 2, n_half);
  snrt_fence_spatz();
  err = 0;
  for (uint32_t i = 0; i < slice; i++) {
    uint32_t exp = (i % 2 == 0 && i / 2 < n_half) ? pat_b(cid, i / 2) : pat_a(cid, i);
    err += (rw[i] != exp);
  }
  error_cnt[cid] = err;
  num_fails += report("4b vector strided write", cid, num_cores);

  // 5. Every core writes pattern C, then checks its neighbour's slice
  for (uint32_t i = 0; i < slice; i++) {
    vb[i] = pat_c(cid, i);
  }
  scalar_to_vector_fence();
  vec_copy((uint32_t *)rw, vb, slice);
  snrt_fence_spatz();
  snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);
  const uint32_t nb = (cid + 1) % num_cores;
  volatile uint32_t *nrw = &byp_buf[BYP_WORDS + nb * slice];
  err = 0;
  for (uint32_t i = 0; i < slice; i++) {
    err += (nrw[i] != pat_c(nb, i));
  }
  error_cnt[cid] = err;
  num_fails += report("5  neighbour read", cid, num_cores);

  // 6. Timing on core 0 alone, with every bank private
  num_fails += bypass_timing(cid == 0);

  if (cid == 0) {
    printf("*** L1 bypass test %s ***\n", num_fails ? "FAILED" : "PASSED");
  }
  spatz_lock_release();
  snrt_cluster_hw_barrier();
  return num_fails ? -1 : 0;
}
