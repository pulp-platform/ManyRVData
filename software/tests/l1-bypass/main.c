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
//   1. scalar read of the preloaded pattern
//   2. vector unit-stride and strided read of the preloaded pattern
//   3. scalar word/halfword/byte writes, read-after-write
//   4. vector unit-stride and strided writes (strided: partial strobes per slot)
//   5. read of the neighbour core's slice (visibility through DRAM)
//   6. timing, two visits each: a cached region gets faster after its cold
//      visit, the bypass region does not (DRAM refresh makes a third visit noisy)
//   7. bypass switched off: the same region now gets faster on its second visit
// All banks are tile-private, so every request is served by the local tile;
// private caches are not coherent across tiles, so part 5 needs the bypass.
//
// Strides of 12 B and unaligned e8 copies are left out: they hang on the cached
// path as well (pre-existing, independent of the bypass).

#include <benchmark.h>
#include <snrt.h>
#include <stdint.h>
#include <stdio.h>
#include <spatz_lock.h>

#define BYP_BASE  0xB0000000u
// Cached region (.pdcp_src), below the private/bypass boundary
#define PRV_BASE  0xA0000000u
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
#define P16384(b, i) P4096(b, i), P4096(b, (i) + 4096), P4096(b, (i) + 8192), P4096(b, (i) + 12288)
#define A1(i)       P1(BYP_BASE, i)

// Part 6 timing regions: 16 lines per core, small enough to never evict.
#define T_CORE_WORDS 256u
#define T_WORDS      (64u * T_CORE_WORDS)

// Read-only half, read/write half, then the bypass timing region.
static uint32_t byp_buf[2 * BYP_WORDS + T_WORDS] __attribute__((section(".l1_bypass"), used)) = {
  P4096(BYP_BASE, 0), P4096(BYP_BASE, BYP_WORDS), P16384(BYP_BASE, 2 * BYP_WORDS)
};

// Cached timing region (below the private/bypass boundary).
static uint32_t prv_buf[T_WORDS] __attribute__((section(".pdcp_src"), used)) = {
  P16384(PRV_BASE, 0)
};

// Cached scratch, one slice per core.
#define MAX_CORES       64u
#define MAX_SLICE_WORDS (BYP_WORDS / 16u)
static uint32_t vbuf[MAX_CORES][MAX_SLICE_WORDS] __attribute__((section(".data")));
static int      error_cnt[MAX_CORES] __attribute__((section(".data")));

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

// Stream count words through the vector unit (loads only).
static inline void vec_load(const uint32_t *src, uint32_t count) {
  uint32_t avl = count;
  uint32_t vl;
  do {
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(avl));
    asm volatile("vle32.v v0, (%0)" : : "r"(src) : "memory");
    src += vl;
    avl -= vl;
  } while (avl > 0);
}

// One timed visit of every core's slice; cycles measured on core 0.
static uint32_t timed_visit(const uint32_t *slice_ptr, uint32_t count, uint32_t cid) {
  snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);
  uint32_t t0 = benchmark_get_cycle();
  vec_load(slice_ptr, count);
  snrt_fence_spatz();
  snrt_cluster_host0_barrier(SNRT_HOST_BARRIER_SLOT);
  return (cid == 0) ? benchmark_get_cycle() - t0 : 0;
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

  // All banks tile-private, private range from BYP_BASE up, bypass on. Every hart
  // calls the l1d_* helpers (they use the cluster barrier). l1d_part() goes first:
  // a commit re-issues the last L1D instruction, which l1d_part() leaves at flush.
  l1d_part(snrt_cluster_vpu_per_tile());
  l1d_addr(BYP_BASE);
  l1d_bypass(1);

  if (!is_primary) {
    // Matches the primaries' l1d_bypass(0) before part 7
    l1d_bypass(0);
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
    printf("Cores:%u  buffer:0x%x  slice:%u words\n", num_cores, (uint32_t)byp_buf, slice);
    if ((uint32_t)byp_buf != BYP_BASE || (uint32_t)prv_buf != PRV_BASE || num_cores > MAX_CORES) {
      printf("FATAL: buffers not at 0x%x / 0x%x or too many cores\n", BYP_BASE, PRV_BASE);
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

  // 6. Timing: two visits of a cached region (B, cold first) and of the bypass
  // region (A). B must speed up after the cold visit, A must not.
  const uint32_t t_base = cid * T_CORE_WORDS;
  const uint32_t *b_ptr = &prv_buf[t_base];
  const uint32_t *a_ptr = &byp_buf[2 * BYP_WORDS + t_base];
  uint32_t tb[2], ta[2];
  for (uint32_t t = 0; t < 2; t++) tb[t] = timed_visit(b_ptr, T_CORE_WORDS, cid);
  for (uint32_t t = 0; t < 2; t++) ta[t] = timed_visit(a_ptr, T_CORE_WORDS, cid);
  err = 0;
  for (uint32_t i = 0; i < T_CORE_WORDS; i++) {
    err += (b_ptr[i] != P1(PRV_BASE, t_base + i));
  }
  error_cnt[cid] = err;
  num_fails += report("6  cached region data", cid, num_cores);
  if (cid == 0) {
    printf("6  cycles cached B: %u %u | bypass A: %u %u\n", tb[0], tb[1], ta[0], ta[1]);
    // cached: second visit < 0.7x cold; bypass: second visit within +-20% of the first
    const int b_ok = (10 * tb[1] < 7 * tb[0]);
    const int a_ok = (10 * ta[1] > 8 * ta[0]) && (10 * ta[1] < 12 * ta[0]);
    printf("6  timing: cached speeds up %s, bypass stays flat %s\n",
           b_ok ? "PASS" : "FAIL", a_ok ? "PASS" : "FAIL");
    num_fails += !(b_ok && a_ok);
  }

  // 7. Bypass off: the same bypass-range region is cacheable again (cold, then hit).
  // It was never cached, so no flush is needed.
  l1d_bypass(0);
  uint32_t tc[2];
  for (uint32_t t = 0; t < 2; t++) tc[t] = timed_visit(a_ptr, T_CORE_WORDS, cid);
  err = 0;
  for (uint32_t i = 0; i < T_CORE_WORDS; i++) {
    err += (a_ptr[i] != P1(BYP_BASE, 2 * BYP_WORDS + t_base + i));
  }
  error_cnt[cid] = err;
  num_fails += report("7  bypass off, data", cid, num_cores);
  if (cid == 0) {
    const int c_ok = (10 * tc[1] < 7 * tc[0]);
    printf("7  cycles same region, bypass off: %u %u -> %s\n", tc[0], tc[1],
           c_ok ? "PASS" : "FAIL");
    num_fails += !c_ok;
  }

  if (cid == 0) {
    printf("*** L1 bypass test %s ***\n", num_fails ? "FAILED" : "PASSED");
  }
  spatz_lock_release();
  snrt_cluster_hw_barrier();
  return num_fails ? -1 : 0;
}
