// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0
//
// cache-coverage: multi-core, multi-phase cache verification kernel.
//
// EVERY phase that doesn't intrinsically need a single core runs on
// ALL 4 cores in parallel.  Each core works on its own per-core slice
// (no cross-slice corruption is also a property we check), and the
// verification VIP (SB + Memory Model) checks correctness end-to-end.
//
// Phases:
//   00 setup           core 0 only (l1d_flush + xbar_config + l1d_init)
//   01 cold+hit        all cores  (each owns 1/4 of working set)
//   02 partial-bytes   all cores  (each owns its own 64-byte scratch line)
//   03 eviction        all cores  (each evicts its slice via reverse-walk)
//   04 multicore RAW   all cores  (each writes, all cores read)
//   05 vector          all cores  (each Spatz does vle+vse on its slice)
//   06 set-conflict    core 0     (8 same-set tags, 4 ways → forced evict)
//   07 random LFSR     all cores  (each core has own seed + own slice)
//   08 AMO atomicity   all cores  (4×AMO_ITER amoadds to shared counter)
//   09 ping-pong       all cores  (each ping-pongs on its own line)
//   10 cross-core RAW  all cores  (each writes, neighbor reads + verifies)
//   11 shared-set      all cores  (4 cores hit same set/depth)
//   12 producer chain  all cores  (c0 writes → c1 reads+writes → ... → c3 verifies)

#include <l1cache.h>
#include <snrt.h>
#include <stdint.h>
#include "printf.h"

#define MAX_CORES        4U
#define LINE_BYTES       64U
#define WORD_BYTES       4U
#define WORDS_PER_LINE   (LINE_BYTES / WORD_BYTES)

// 768 cache lines × 64 B = 48 KiB working set (= 3× per-way footprint).
#define NUM_LINES        768U
#define TOTAL_WORDS      (NUM_LINES * WORDS_PER_LINE)

// Phase 06: set-conflict (single core)
#define CONFLICT_STRIDE_LOG2 16U          // 64 KiB upstream stride → same set
#define CONFLICT_STRIDE      (1U << CONFLICT_STRIDE_LOG2)
#define CONFLICT_LINES       8U
#define CONFLICT_BYTES       (CONFLICT_LINES * CONFLICT_STRIDE)

// Phase 11: shared-set (multi-core).  Each core picks 4 stride-64KiB lines
// all hashing to the SAME set; 4 cores × 4 ways = 16 lines on one set,
// forces continuous eviction churn under multi-core contention.
#define SHARED_CONFLICT_LINES_PER_CORE  4U
#define SHARED_CONFLICT_TOTAL_LINES     (SHARED_CONFLICT_LINES_PER_CORE * MAX_CORES)
#define SHARED_CONFLICT_BYTES           (SHARED_CONFLICT_TOTAL_LINES * CONFLICT_STRIDE)

// Per-core / per-phase tunables
#define AMO_ITER         512U
#define PINGPONG_ITER    256U
#define LFSR_ITER        512U

static uint32_t buf [TOTAL_WORDS] __attribute__((section(".dram")))
                                  __attribute__((aligned(LINE_BYTES)));

static uint32_t core_errors [MAX_CORES] __attribute__((section(".dram")));

// One per-core 64-byte scratch line for phase 02.
static uint8_t  scratch [MAX_CORES][LINE_BYTES]
    __attribute__((section(".dram"))) __attribute__((aligned(LINE_BYTES)));

// Set-conflict (phase 06, single core).
static uint8_t  conflict_buf [CONFLICT_BYTES]
    __attribute__((section(".dram"))) __attribute__((aligned(CONFLICT_STRIDE)));

// Multi-core shared-set contention buffer (phase 11).
static uint8_t  shared_conflict_buf [SHARED_CONFLICT_BYTES]
    __attribute__((section(".dram"))) __attribute__((aligned(CONFLICT_STRIDE)));

// Shared counter for phase 08 (AMO multi-core).
static volatile uint32_t amo_counter
    __attribute__((section(".dram"))) __attribute__((aligned(LINE_BYTES))) = 0;

// Per-phase per-core error aggregation.  Each core stores its result;
// core 0 prints a summary line after the barrier.
#define N_PHASES 13
static volatile uint32_t phase_errs [N_PHASES][MAX_CORES]
    __attribute__((section(".dram"))) __attribute__((aligned(LINE_BYTES)));

static inline uint32_t pattern(uint32_t idx) {
  return (idx * 0x01010101u) ^ 0xA5A5A5A5u;
}

static inline uint32_t core_tag(uint32_t cid) {
  return cid * 0x11111111u;
}

// Forward decls.
static uint32_t phase_01_cold_then_hit(volatile uint32_t *p, uint32_t base, uint32_t chunk);
static uint32_t phase_02_partial_bytes(volatile uint8_t  *p);
static uint32_t phase_03_eviction     (volatile uint32_t *p, uint32_t base, uint32_t chunk);
static uint32_t phase_04_multicore    (volatile uint32_t *p, uint32_t n, uint32_t cid);
static uint32_t phase_05_vector_rw    (volatile uint32_t *p, uint32_t base, uint32_t chunk);
static uint32_t phase_06_set_conflict (volatile uint8_t  *base);
static uint32_t phase_07_random_lfsr  (volatile uint32_t *p, uint32_t base, uint32_t chunk, uint32_t cid);
static uint32_t phase_08_amo_multicore(uint32_t cid);
static uint32_t phase_09_pingpong     (volatile uint32_t *p, uint32_t addr);
static uint32_t phase_10_cross_core_raw(volatile uint32_t *p, uint32_t n, uint32_t cid);
static uint32_t phase_11_shared_set   (volatile uint8_t  *base, uint32_t cid);
static uint32_t phase_12_producer_chain(volatile uint32_t *p, uint32_t base, uint32_t chunk, uint32_t cid);

static inline void summary(uint32_t cid, uint32_t phase, const char *name) {
  // Called by core 0 after the barrier to print per-core counts.
  if (cid != 0) return;
  uint32_t total = 0;
  for (uint32_t c = 0; c < MAX_CORES; ++c) total += phase_errs[phase][c];
  printf("[cache-coverage] phase %02u %s: total=%u  (c0=%u c1=%u c2=%u c3=%u)\n",
         phase, name, total,
         phase_errs[phase][0], phase_errs[phase][1],
         phase_errs[phase][2], phase_errs[phase][3]);
}

int main() {
  const uint32_t cid    = snrt_cluster_core_idx();
  const uint32_t chunk  = TOTAL_WORDS / MAX_CORES;
  const uint32_t base   = chunk * cid;

  // ---------------- Phase 00: setup --------------------------------
  if (cid == 0) {
    l1d_flush();
    l1d_wait();
    l1d_xbar_config(31 - __builtin_clz(LINE_BYTES)); // line-interleaved
    l1d_init(0);
    l1d_wait();
    printf("[cache-coverage] phase 00: setup done\n");
    // zero the phase_errs table
    for (uint32_t i = 0; i < N_PHASES; ++i)
      for (uint32_t c = 0; c < MAX_CORES; ++c) phase_errs[i][c] = 0;
  }
  snrt_cluster_hw_barrier();

  // ---------------- Phase 01: cold + hit (all cores) ----------------
  phase_errs[1][cid] = phase_01_cold_then_hit(buf, base, chunk);
  snrt_cluster_hw_barrier();
  summary(cid, 1, "cold+hit");

  // ---------------- Phase 02: partial-bytes (all cores) -------------
  phase_errs[2][cid] = phase_02_partial_bytes(scratch[cid]);
  snrt_cluster_hw_barrier();
  summary(cid, 2, "partial-bytes");

  // ---------------- Phase 03: eviction (all cores) ------------------
  phase_errs[3][cid] = phase_03_eviction(buf, base, chunk);
  snrt_cluster_hw_barrier();
  summary(cid, 3, "eviction");

  // ---------------- Phase 04: multicore disjoint slices -------------
  phase_errs[4][cid] = phase_04_multicore(buf, TOTAL_WORDS, cid);
  snrt_cluster_hw_barrier();
  summary(cid, 4, "multicore-disjoint");

  // ---------------- Phase 05: vector (all cores) --------------------
  phase_errs[5][cid] = phase_05_vector_rw(buf, base, chunk);
  snrt_cluster_hw_barrier();
  summary(cid, 5, "vector");

  // ---------------- Phase 06: set-conflict (single core) ------------
  if (cid == 0)
    phase_errs[6][0] = phase_06_set_conflict(conflict_buf);
  snrt_cluster_hw_barrier();
  summary(cid, 6, "set-conflict");

  // ---------------- Phase 07: random LFSR (all cores) ---------------
  phase_errs[7][cid] = phase_07_random_lfsr(buf, base, chunk, cid);
  snrt_cluster_hw_barrier();
  summary(cid, 7, "random-lfsr");

  // ---------------- Phase 08: AMO multi-core ------------------------
  if (cid == 0) amo_counter = 0;
  snrt_cluster_hw_barrier();
  phase_errs[8][cid] = phase_08_amo_multicore(cid);
  snrt_cluster_hw_barrier();
  if (cid == 0) {
    uint32_t expected = MAX_CORES * AMO_ITER;
    uint32_t got      = amo_counter;
    phase_errs[8][0] += (got != expected);
    printf("[cache-coverage] phase 08 AMO: expected=%u got=%u %s\n",
           expected, got, (got != expected) ? "FAIL" : "OK");
  }
  snrt_cluster_hw_barrier();

  // ---------------- Phase 09: ping-pong (all cores) -----------------
  // Each core ping-pongs on a different line within its own slice.
  phase_errs[9][cid] = phase_09_pingpong(buf, base + (WORDS_PER_LINE * cid));
  snrt_cluster_hw_barrier();
  summary(cid, 9, "ping-pong");

  // ---------------- Phase 10: cross-core RAW (all cores) ------------
  phase_errs[10][cid] = phase_10_cross_core_raw(buf, TOTAL_WORDS, cid);
  snrt_cluster_hw_barrier();
  summary(cid, 10, "cross-core RAW");

  // ---------------- Phase 11: multi-core shared-set -----------------
  phase_errs[11][cid] = phase_11_shared_set(shared_conflict_buf, cid);
  snrt_cluster_hw_barrier();
  summary(cid, 11, "shared-set");

  // ---------------- Phase 12: producer-consumer chain ---------------
  phase_errs[12][cid] = phase_12_producer_chain(buf, base, chunk, cid);
  snrt_cluster_hw_barrier();
  summary(cid, 12, "producer-chain");

  // ---------------- Report ------------------------------------------
  if (cid < MAX_CORES) core_errors[cid] = phase_errs[0][cid];
  snrt_cluster_hw_barrier();

  if (cid == 0) {
    uint32_t total = 0;
    for (uint32_t p = 0; p < N_PHASES; ++p)
      for (uint32_t c = 0; c < MAX_CORES; ++c)
        total += phase_errs[p][c];
    if (total == 0) printf("[cache-coverage] ALL PHASES PASS\n");
    else            printf("[cache-coverage] FAIL: total errors = %u\n", total);
  }

  return 0;
}

// =====================================================================
// Phase 01: cold + hit on per-core slice.
// =====================================================================
static uint32_t phase_01_cold_then_hit(volatile uint32_t *p,
                                       uint32_t base, uint32_t chunk) {
  uint32_t errs = 0;
  for (uint32_t i = 0; i < chunk; ++i) p[base + i] = pattern(base + i);
  for (uint32_t i = 0; i < chunk; ++i) {
    uint32_t got = p[base + i];
    uint32_t exp = pattern(base + i);
    if (got != exp) ++errs;
  }
  return errs;
}

// =====================================================================
// Phase 02: partial-byte stores on a per-core scratch line.
// =====================================================================
static uint32_t phase_02_partial_bytes(volatile uint8_t *p) {
  uint32_t errs = 0;
  volatile uint32_t *w = (volatile uint32_t *)p;
  for (uint32_t i = 0; i < LINE_BYTES / 4; ++i) w[i] = 0xDEADBE00u | i;

  p[5] = 0x42;
  if (p[5] != 0x42) ++errs;
  if (p[4] != (uint8_t)(0xDEADBE01u >>  0)) ++errs;
  if (p[6] != (uint8_t)(0xDEADBE01u >> 16)) ++errs;
  if (p[7] != (uint8_t)(0xDEADBE01u >> 24)) ++errs;

  *((volatile uint16_t *)(p + 10)) = 0xCAFEu;
  if (*((volatile uint16_t *)(p + 10)) != 0xCAFEu) ++errs;
  if (p[8] != (uint8_t)(0xDEADBE02u >> 0)) ++errs;
  if (p[9] != (uint8_t)(0xDEADBE02u >> 8)) ++errs;

  return errs;
}

// =====================================================================
// Phase 03: write forward, reverse-walk read.  Per-core slice.
// =====================================================================
static uint32_t phase_03_eviction(volatile uint32_t *p,
                                  uint32_t base, uint32_t chunk) {
  uint32_t errs = 0;
  for (uint32_t i = 0; i < chunk; ++i) p[base + i] = pattern(base + i) ^ 0xFF00FF00u;
  for (int32_t i = (int32_t)chunk - 1; i >= 0; --i) {
    uint32_t got = p[base + (uint32_t)i];
    uint32_t exp = pattern(base + (uint32_t)i) ^ 0xFF00FF00u;
    if (got != exp) ++errs;
  }
  return errs;
}

// =====================================================================
// Phase 04: each core writes its slice, all cores read all slices
// (4-way cross-traffic on the cache).
// =====================================================================
static uint32_t phase_04_multicore(volatile uint32_t *p, uint32_t n, uint32_t cid) {
  if (cid >= MAX_CORES) return 0;
  uint32_t chunk = n / MAX_CORES;
  uint32_t base  = chunk * cid;
  uint32_t errs  = 0;
  for (uint32_t i = 0; i < chunk; ++i)
    p[base + i] = pattern(base + i) ^ core_tag(cid);
  snrt_cluster_hw_barrier();
  // Each core now reads ALL slices, not just its own.
  for (uint32_t c = 0; c < MAX_CORES; ++c) {
    uint32_t cbase = chunk * c;
    for (uint32_t i = 0; i < chunk; ++i) {
      uint32_t got = p[cbase + i];
      uint32_t exp = pattern(cbase + i) ^ core_tag(c);
      if (got != exp) ++errs;
    }
  }
  return errs;
}

// =====================================================================
// Phase 05: vector vle + vse on per-core slice.  Each core's Spatz
// pipeline runs independently, all four producing TCDM traffic in
// parallel on disjoint addresses.
// =====================================================================
static uint32_t phase_05_vector_rw(volatile uint32_t *p,
                                   uint32_t base, uint32_t chunk) {
  uint32_t errs = 0;
  uint32_t i = 0;
  while (i < chunk) {
    uint32_t avl = chunk - i;
    uint32_t vl;
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(avl));
    for (uint32_t j = 0; j < vl; ++j)
      p[base + i + j] = pattern(base + i + j) ^ 0xCC00CC00u;
    asm volatile("vle32.v v0, (%0)" : : "r"(&p[base + i]) : "memory");
    asm volatile("vse32.v v0, (%0)" : : "r"(&p[base + i]) : "memory");
    for (uint32_t j = 0; j < vl; ++j) {
      uint32_t got = p[base + i + j];
      uint32_t exp = pattern(base + i + j) ^ 0xCC00CC00u;
      if (got != exp) ++errs;
    }
    i += vl;
  }
  return errs;
}

// =====================================================================
// Phase 06: 8 stride-64KiB addresses → all same cache set → 4 evictions.
// Single core.
// =====================================================================
static uint32_t phase_06_set_conflict(volatile uint8_t *base) {
  uint32_t errs = 0;
  volatile uint32_t *p[CONFLICT_LINES];
  for (uint32_t k = 0; k < CONFLICT_LINES; ++k)
    p[k] = (volatile uint32_t *)(base + (k * CONFLICT_STRIDE));
  for (uint32_t k = 0; k < CONFLICT_LINES; ++k)
    *(p[k]) = 0xC0FFEE00u + k;
  for (uint32_t k = 0; k < CONFLICT_LINES; ++k) {
    uint32_t got = *(p[k]);
    uint32_t exp = 0xC0FFEE00u + k;
    if (got != exp) {
      if (errs < 8)
        printf("  [p06 round1] k=%u addr=0x%x exp=0x%x got=0x%x\n",
               k, (uint32_t)p[k], exp, got);
      ++errs;
    }
  }
  for (uint32_t k = 0; k < CONFLICT_LINES; ++k)
    *(p[k]) = 0xDEADC0DEu - k;
  for (uint32_t k = 0; k < CONFLICT_LINES; ++k) {
    uint32_t got = *(p[k]);
    uint32_t exp = 0xDEADC0DEu - k;
    if (got != exp) {
      if (errs < 16)
        printf("  [p06 round2] k=%u addr=0x%x exp=0x%x got=0x%x\n",
               k, (uint32_t)p[k], exp, got);
      ++errs;
    }
  }
  return errs;
}

// =====================================================================
// Phase 07: pseudo-random access pattern (per-core LFSR).
// =====================================================================
static uint32_t phase_07_random_lfsr(volatile uint32_t *p,
                                     uint32_t base, uint32_t chunk,
                                     uint32_t cid) {
  uint32_t errs = 0;
  uint32_t lfsr = 0xACE1u + cid * 0x1357u;   // distinct seed per core
  for (uint32_t iter = 0; iter < LFSR_ITER; ++iter) {
    uint32_t lsb = lfsr & 1u;
    lfsr >>= 1;
    if (lsb) lfsr ^= 0xB400u;
    if (lfsr == 0) lfsr = 0xACE1u;
    uint32_t idx = lfsr % chunk;
    uint32_t val = (iter << 16) | ((lfsr & 0xFFFu) << 4) | cid;
    p[base + idx] = val;
    uint32_t got = p[base + idx];
    if (got != val) ++errs;
  }
  return errs;
}

// =====================================================================
// Phase 08: AMO atomicity.  Every core does AMO_ITER amoadds.
// =====================================================================
static uint32_t phase_08_amo_multicore(uint32_t cid) {
  if (cid >= MAX_CORES) return 0;
  for (uint32_t i = 0; i < AMO_ITER; ++i) {
    uint32_t one = 1;
    asm volatile("amoadd.w zero, %1, %0"
                 : "+A"(amo_counter)
                 : "r"(one));
  }
  return 0;
}

// =====================================================================
// Phase 09: ping-pong on a per-core line.  Catches forwarding-buffer
// state divergence and WRITE_PEND → VALID merge bugs.
// =====================================================================
static uint32_t phase_09_pingpong(volatile uint32_t *p, uint32_t addr) {
  uint32_t errs = 0;
  for (uint32_t iter = 0; iter < PINGPONG_ITER; ++iter) {
    uint32_t v = (iter * 0xDEADBEEFu) ^ 0x12345678u;
    p[addr] = v;
    uint32_t got = p[addr];
    if (got != v) ++errs;
  }
  return errs;
}

// =====================================================================
// Phase 10: cross-core read-after-write — each core writes its slice,
// then reads its NEIGHBOUR'S slice and verifies.  Catches stale-data-
// from-wrong-core bugs.
// =====================================================================
static uint32_t phase_10_cross_core_raw(volatile uint32_t *p, uint32_t n, uint32_t cid) {
  if (cid >= MAX_CORES) return 0;
  uint32_t chunk = n / MAX_CORES;
  uint32_t errs  = 0;
  // Write own slice.
  for (uint32_t i = 0; i < chunk; ++i)
    p[chunk * cid + i] = pattern(chunk * cid + i) ^ 0xBEEFBEEFu;
  snrt_cluster_hw_barrier();
  // Read NEIGHBOUR's slice.  cid=0 reads cid=1's, 1 reads 2's, etc.
  uint32_t nb   = (cid + 1) % MAX_CORES;
  uint32_t nbase = chunk * nb;
  for (uint32_t i = 0; i < chunk; ++i) {
    uint32_t got = p[nbase + i];
    uint32_t exp = pattern(nbase + i) ^ 0xBEEFBEEFu;
    if (got != exp) ++errs;
  }
  return errs;
}

// =====================================================================
// Phase 11: SHARED-SET multi-core contention.  Every core owns 4 stride-
// 64KiB lines from the SAME big buffer (offsets cid*4..cid*4+3), all of
// which map to the SAME cache set under offset=6.  Total of 16 lines hit
// 1 set with 4 ways → 12 forced evictions, on top of the 4-way race for
// the resident slots between the 4 cores.
// =====================================================================
static uint32_t phase_11_shared_set(volatile uint8_t *base, uint32_t cid) {
  if (cid >= MAX_CORES) return 0;
  volatile uint32_t *p[SHARED_CONFLICT_LINES_PER_CORE];
  uint32_t core_off = cid * SHARED_CONFLICT_LINES_PER_CORE;
  for (uint32_t k = 0; k < SHARED_CONFLICT_LINES_PER_CORE; ++k)
    p[k] = (volatile uint32_t *)(base + ((core_off + k) * CONFLICT_STRIDE));

  // Each core writes a per-core marker on its lines.
  uint32_t errs = 0;
  for (uint32_t k = 0; k < SHARED_CONFLICT_LINES_PER_CORE; ++k)
    *(p[k]) = core_tag(cid) ^ (0xC0DE0000u + k);

  // Barrier ensures all cores have written before any starts reading.
  snrt_cluster_hw_barrier();

  // Each core reads back ITS OWN lines and verifies.  Even with massive
  // multi-core eviction churn on the SAME set, each core's tag must be
  // returned intact.
  for (uint32_t k = 0; k < SHARED_CONFLICT_LINES_PER_CORE; ++k) {
    uint32_t got = *(p[k]);
    uint32_t exp = core_tag(cid) ^ (0xC0DE0000u + k);
    if (got != exp) {
      if (errs < 4)
        printf("  [p11 cid=%u] k=%u addr=0x%x exp=0x%x got=0x%x\n",
               cid, k, (uint32_t)p[k], exp, got);
      ++errs;
    }
  }
  return errs;
}

// =====================================================================
// Phase 12: producer-consumer chain.
//   c0 writes its slice with value V.
//   c1 reads its slice (the part c0 wrote), verifies, then writes V+1.
//   c2 reads c1's output, verifies, writes V+2.
//   c3 reads c2's output, verifies, writes V+3.
// Each step uses a barrier — exercises the cross-core handoff
// (each core consumes data that lived in DRAM/cache from another core).
// =====================================================================
static uint32_t phase_12_producer_chain(volatile uint32_t *p,
                                        uint32_t base, uint32_t chunk,
                                        uint32_t cid) {
  if (cid >= MAX_CORES) return 0;
  uint32_t errs = 0;
  // Stage 0: c0 writes; others wait.
  if (cid == 0)
    for (uint32_t i = 0; i < chunk; ++i)
      p[base + i] = pattern(base + i) ^ 0x10000000u;
  snrt_cluster_hw_barrier();

  // Stages 1..3: cid C reads (C-1)'s slice, verifies, writes its own.
  for (uint32_t stage = 1; stage < MAX_CORES; ++stage) {
    if (cid == stage) {
      uint32_t prev_base = (stage - 1) * chunk;
      for (uint32_t i = 0; i < chunk; ++i) {
        uint32_t got = p[prev_base + i];
        uint32_t exp = pattern(prev_base + i) ^ ((uint32_t)stage << 28);
        if (got != exp) ++errs;
      }
      // Now write own slice with stage's tag.
      for (uint32_t i = 0; i < chunk; ++i)
        p[base + i] = pattern(base + i) ^ ((uint32_t)(stage + 1) << 28);
    }
    snrt_cluster_hw_barrier();
  }
  return errs;
}
