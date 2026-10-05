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

#include <benchmark.h>
#include <snrt.h>
#include <stdint.h>
#include <stdio.h>

// -----------------------------------------------------------------------------
// Memory layout
// -----------------------------------------------------------------------------
// Default partition boundary: 0xA000_0000
//   >= boundary -> private   (gemm_A/B/C in .pdcp_src at 0xA000_0000+)
//   <  boundary -> shared    (gemm_D      in .data    at 0x8000_0000+)
//
// Values: A=1, B=2, C=3, D=4
//
// Address trick used in flush isolation tests:
//   Raise boundary (e.g. 0xC000_0000) -> gemm_A/B/C become shared
//   Lower boundary (e.g. 0x7000_0000) -> gemm_D becomes private

// Parts 2 and 3 move the partition boundary, which forces a full refetch
// through the other partition and a cluster-wide flush -- correct but slow in
// RTL. Set to 0 to skip them when iterating on Part 4.
#ifndef LS_FLUSH_ISOLATION
#define LS_FLUSH_ISOLATION 1
#endif

// Part 1 sweeps the five partition modes; unrelated to the fold path.
#ifndef LS_PART1
#define LS_PART1 1
#endif

// Part 2 (private flush isolation) and Part 3 share LS_FLUSH_ISOLATION, but
// Part 3 depends on the value Part 2 leaves in gemm_A, so this only skips
// Part 2 when you are deliberately iterating and expect Part 3's gemm_A check
// to fail.
#ifndef LS_PART2
#define LS_PART2 1
#endif

// 1 = run a single fold configuration (all-private, fold-group, offset 6) and
// skip the visibility sub-test, so a waveform covers one case end to end.
#ifndef LS_FOLD_MIN
#define LS_FOLD_MIN 0
#endif

#define BOUNDARY_DEFAULT  0xA0000000u
#define BOUNDARY_HIGH     0xC0000000u   // makes gemm_A/B/C shared
#define BOUNDARY_LOW      0x70000000u   // makes gemm_D private

// -----------------------------------------------------------------------------
// Test length control
// -----------------------------------------------------------------------------
// Keep small for RTL simulation speed.
#define CACHELINE_BYTES  64
#define ELEM_BYTES       sizeof(uint32_t)
#define ELEMS_PER_CL     (CACHELINE_BYTES / ELEM_BYTES)
#define TEST_CLS         4              // cachelines per core per test

// -----------------------------------------------------------------------------
// Static test arrays
// -----------------------------------------------------------------------------
// Sized so every core owns a large slice (dim_core = TOTAL/num_cores); only
// the first TEST_CLS cachelines of each slice are actually touched, to keep
// RTL simulation short.
// A/B/C are placed in the private region; D is placed in the shared region.
#define LOAD_STORE_TOTAL_ELEMS 262144

// Private region: default boundary puts these addresses in the private partition
static uint32_t gemm_A_dram[LOAD_STORE_TOTAL_ELEMS]
    __attribute__((section(".pdcp_src"))) = {[0 ... LOAD_STORE_TOTAL_ELEMS - 1] = 1};
static uint32_t gemm_B_dram[LOAD_STORE_TOTAL_ELEMS]
    __attribute__((section(".pdcp_src"))) = {[0 ... LOAD_STORE_TOTAL_ELEMS - 1] = 2};
static uint32_t gemm_C_dram[LOAD_STORE_TOTAL_ELEMS]
    __attribute__((section(".pdcp_src"))) = {[0 ... LOAD_STORE_TOTAL_ELEMS - 1] = 3};

// Shared region: default boundary puts this address in the shared partition
static uint32_t gemm_D_dram[LOAD_STORE_TOTAL_ELEMS]
    __attribute__((section(".data")))    = {[0 ... LOAD_STORE_TOTAL_ELEMS - 1] = 4};

// Per-core error counts, so the Part 4 checks run in parallel instead of
// being serialised on core 0.
static int error_cnt[256] __attribute__((section(".data")));

#define FOLD_BLOCK_ELEMS 16u   // one 64 B cacheline
#define FOLD_STRIDE      64u   // 256 B: steps addr[9:8]  (offset 6)
#define FOLD_BLOCKS      16u   // spans ~4 KiB: steps addr[11:10] (offset 8)

// Source pattern for the fold tests: FOLD_BLOCKS blocks of FOLD_BLOCK_ELEMS,
// contiguous, one set per core. Filled once with scalar stores, then every
// test case is a pure vle/vse copy into the strided target blocks.
#define SRC_ELEMS_PER_CORE (FOLD_BLOCKS * FOLD_BLOCK_ELEMS)
static uint32_t fold_src[64 * SRC_ELEMS_PER_CORE] __attribute__((section(".data")));

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

static inline uint32_t cls_to_elems(uint32_t cls) {
  return cls * ELEMS_PER_CL;
}

// Vector copy: all cores call this on their own slice.
static inline void stream_copy_vec(uint32_t *dst, uint32_t *src,
                                   uint32_t count) {
  uint32_t avl = count;
  uint32_t vlen;
  do {
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma"
                 : "=r"(vlen) : "r"(avl));
    asm volatile("vle32.v v0, (%0)" : : "r"(src));
    asm volatile("vse32.v v0, (%0)" : : "r"(dst));
    src += vlen;
    dst += vlen;
    avl -= vlen;
  } while (avl > 0);
}

// Vector load: all cores call this on their own slice.
static inline void stream_load(uint32_t *ptr, uint32_t count) {
  uint32_t avl = count;
  uint32_t vlen;
  do {
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma"
                 : "=r"(vlen) : "r"(avl));
    asm volatile("vle32.v v0, (%0)" : : "r"(ptr));
    ptr += vlen;
    avl -= vlen;
  } while (avl > 0);
}

// Fill this core's source pattern. Scalar, but run once for the whole test.
static void fold_src_init(uint32_t *src, uint32_t tag) {
  for (uint32_t i = 0; i < SRC_ELEMS_PER_CORE; i++) {
    src[i] = tag + i;
  }
}

// Count mismatches of count elements against src.
static int check_against(uint32_t *ptr, uint32_t *src, uint32_t count) {
  int err = 0;
  for (uint32_t i = 0; i < count; i++) {
    if (ptr[i] != src[i]) {
      err++;
    }
  }
  return err;
}

// Sparse blocks instead of one contiguous region. The home tile comes from
// addr[offset+2 +: LocalTileBits], so stepping a cacheline-sized block by
// FOLD_STRIDE walks that field through every value while touching a quarter of
// the data a contiguous region of the same span would -- fewer dirty lines to
// write back, and the flush is what dominates the runtime.

static inline void copy_blocks(uint32_t *base, uint32_t *src) {
  for (uint32_t b = 0; b < FOLD_BLOCKS; b++) {
    stream_copy_vec(base + b * FOLD_STRIDE, src + b * FOLD_BLOCK_ELEMS,
                    FOLD_BLOCK_ELEMS);
  }
}

static int check_blocks(uint32_t *base, uint32_t *src) {
  int err = 0;
  for (uint32_t b = 0; b < FOLD_BLOCKS; b++) {
    err += check_against(base + b * FOLD_STRIDE,
                         src + b * FOLD_BLOCK_ELEMS, FOLD_BLOCK_ELEMS);
  }
  return err;
}

// Write a per-core, per-element pattern. Unlike the constant fills above this
// detects a wrong home tile or a routing/rotation mismatch: an aliased or
// misrouted line shows up as the wrong tag or index, whereas a constant fill
// would read back correctly no matter where it landed.
static inline void write_pattern(uint32_t *dst, uint32_t count, uint32_t cid) {
  for (uint32_t i = 0; i < count; i++) {
    dst[i] = (cid << 16) | i;
  }
}

// Verify every core's slice. Returns 1 on pass.
static int check_pattern(uint32_t *base, uint32_t dim_core, uint32_t count,
                         uint32_t num_cores, uint32_t *fail_at,
                         uint32_t *fail_exp, uint32_t *fail_got) {
  for (uint32_t c = 0; c < num_cores; c++) {
    for (uint32_t i = 0; i < count; i++) {
      uint32_t exp = (c << 16) | i;
      uint32_t got = base[c * dim_core + i];
      if (got != exp) {
        *fail_at = c * dim_core + i;
        *fail_exp = exp;
        *fail_got = got;
        return 0;
      }
    }
  }
  return 1;
}

// Check count elements for expected value. Returns 1 on pass.
static int check_const(uint32_t *ptr, uint32_t count, uint32_t value,
                       uint32_t *fail_idx, uint32_t *fail_val) {
  for (uint32_t i = 0; i < count; i++) {
    if (ptr[i] != value) {
      *fail_idx = i;
      *fail_val = ptr[i];
      return 0;
    }
  }
  return 1;
}

// -----------------------------------------------------------------------------
// main
// -----------------------------------------------------------------------------
int main() {
  const uint32_t num_cores = snrt_cluster_core_num();
  const uint32_t num_tiles = snrt_cluster_tile_num();
  const uint32_t cid       = snrt_cluster_core_idx();
  const uint32_t num_cores_per_tile = num_cores / num_tiles;

  const uint32_t dim_core  = LOAD_STORE_TOTAL_ELEMS / num_cores;
  const uint32_t test_len  = cls_to_elems(TEST_CLS);  // per core, short

  // xbar offset: size of per-core region in address bits
  const uint32_t local_offset = 31 - __builtin_clz(dim_core * sizeof(uint32_t));

  // One-hot mask covering all tiles (uint64_t supports up to 64 tiles)
  const uint64_t all_tiles = (UINT64_C(1) << num_tiles) - 1;

  // Per-core pointers into each array
  uint32_t *a_ptr = gemm_A_dram + dim_core * cid;  // private, value 1
  uint32_t *b_ptr = gemm_B_dram + dim_core * cid;  // private, value 2
  uint32_t *c_ptr = gemm_C_dram + dim_core * cid;  // private, value 3
  uint32_t *d_ptr = gemm_D_dram + dim_core * cid;  // shared,  value 4

  if (cid == 0) {
    printf("*** CachePool partition + flush test ***\n");
    printf("Cores:%u  Tiles:%u  test_len:%u elems/core\n\n",
           num_cores, num_tiles, test_len);
  }

  // ===========================================================================
  // Part 1: Cache partitioning
  // ===========================================================================
  // For each partition mode, copy a known source into gemm_A (private) using
  // all cores in parallel, flush to DRAM, then verify the written value.
  // This exercises the routing logic for all 5 bank configurations.
  //
  // Source/expected value per mode (reuses pre-initialised arrays):
  //   part=0 (all-shared)    : B->A, expect 2
  //   part=1 (1priv 3shr)    : C->A, expect 3
  //   part=2 (half-half)     : B->A, expect 2
  //   part=3 (3priv 1shr)    : C->A, expect 3
  //   part=4 (all-private)   : B->A, expect 2

#if LS_PART1
  if (cid == 0) printf("=== Part 1: Partitioning ===\n");

  static const uint32_t part_modes_4[]  = {0, 1, 2, 3, 4};
  static const uint32_t part_expect_4[] = {2, 3, 2, 3, 2};
  static const char    *part_names_4[]  = {
    "all-shared", "1priv-3shr", "half-half", "3priv-1shr", "all-private"
  };

  static const uint32_t part_modes_2[]  = {0, 1, 2};
  static const uint32_t part_expect_2[] = {2, 3, 2};
  static const char    *part_names_2[]  = {
    "all-shared", "half-half", "all-private"
  };

  const uint32_t *part_modes;
  const uint32_t *part_expect;
  const char *const *part_names;
  uint32_t num_modes;

  if (num_cores_per_tile == 4) {
    part_modes  = part_modes_4;
    part_expect = part_expect_4;
    part_names  = part_names_4;
    num_modes   = 5;
  } else if (num_cores_per_tile == 2) {
    part_modes  = part_modes_2;
    part_expect = part_expect_2;
    part_names  = part_names_2;
    num_modes   = 3;
  } else {
    if (cid == 0) {
      printf("FATAL: CFG Error\n");
    }
    snrt_cluster_hw_barrier();
    return -1;
  }

  snrt_cluster_hw_barrier();

  for (uint32_t m = 0; m < num_modes; m++) {
    uint32_t part = part_modes[m];
    uint32_t exp  = part_expect[m];

    // Source: B (value 2) for even modes, C (value 3) for odd modes.
    uint32_t *src = (exp == 2) ? b_ptr : c_ptr;

    l1d_xbar_config(local_offset);
    l1d_part(part);

    // All cores copy in parallel into their slice of gemm_A.
    stream_copy_vec(a_ptr, src, test_len);
    snrt_cluster_hw_barrier();

    l1d_cluster_flush();

    if (cid == 0) {
      uint32_t fail_idx, fail_val;
      int pass = check_const(gemm_A_dram, test_len, exp, &fail_idx, &fail_val);
      if (!pass)
        printf("  FAIL idx %u exp 0x%x got 0x%x\n", fail_idx, exp, fail_val);
      printf("%s: %s\n", part_names[m], pass ? "PASS" : "FAIL");
    }
    snrt_cluster_hw_barrier();
  }

#endif  // LS_PART1

#if LS_FLUSH_ISOLATION
#if LS_PART2
  // ===========================================================================
  // Part 2: Private flush isolation
  // ===========================================================================
  // Verifies that l1d_cluster_private_flush evicts only the private partition,
  // leaving shared data intact.
  //
  // Steps:
  //   1. half-half, default boundary (0xA000_0000).
  //      gemm_A = private, gemm_D = shared.
  //   2. All cores load both regions into cache.
  //   3. Flush private only -> gemm_A evicted, gemm_D still cached.
  //   4. Raise boundary to 0xC000_0000 -> gemm_A becomes shared.
  //   5. All cores copy C->A (value 3) through shared banks -> flush all
  //      -> value 3 written to DRAM for gemm_A.
  //   6. Restore boundary -> reload gemm_A -> flush -> check value = 3.
  //      If private cache had stale data it would return value 2 (last written
  //      before step 3); seeing 3 confirms the private banks were cold.
  //   Waveform: gemm_D should show no refill traffic after step 3.

  if (cid == 0) printf("\n=== Part 2: Private flush isolation ===\n");

  l1d_xbar_config(local_offset);
  l1d_part(2);
  l1d_addr(BOUNDARY_DEFAULT);

  // Step 2: populate private (gemm_A, value 2 from previous test) and shared
  // (gemm_D, value 4) into cache.
  stream_load(a_ptr, test_len);
  snrt_cluster_hw_barrier();
  stream_load(d_ptr, test_len);
  snrt_cluster_hw_barrier();

  // Step 3: flush private only.
  l1d_cluster_private_flush(all_tiles);

  if (cid == 0) printf("Private flushed. Raising boundary...\n");

  // Step 4: raise boundary -> gemm_A now shared.
  l1d_addr(BOUNDARY_HIGH);

  // Step 5: write value 3 into gemm_A via shared banks, flush to DRAM.
  stream_copy_vec(a_ptr, c_ptr, test_len);
  snrt_cluster_hw_barrier();
  l1d_cluster_flush();

  // Step 6: restore boundary, reload gemm_A, flush, check.
  l1d_addr(BOUNDARY_DEFAULT);
  l1d_xbar_config(local_offset);
  l1d_part(2);

  stream_load(a_ptr, test_len);
  snrt_cluster_hw_barrier();
  l1d_cluster_flush();

  if (cid == 0) {
    uint32_t fail_idx, fail_val;
    // gemm_A must have been refetched from DRAM with the new value (3).
    int pass_a = check_const(gemm_A_dram, test_len, 3, &fail_idx, &fail_val);
    if (!pass_a)
      printf("  gemm_A FAIL idx %u exp 3 got 0x%x\n", fail_idx, fail_val);
    // gemm_D must still hold its original value (4): shared banks untouched.
    int pass_d = check_const(gemm_D_dram, test_len, 4, &fail_idx, &fail_val);
    if (!pass_d)
      printf("  gemm_D FAIL idx %u exp 4 got 0x%x\n", fail_idx, fail_val);
    printf("private-flush-isolation: %s\n", (pass_a && pass_d) ? "PASS" : "FAIL");
  }
  snrt_cluster_hw_barrier();

#endif  // LS_PART2

  // ===========================================================================
  // Part 3: Shared flush isolation
  // ===========================================================================
  // Verifies that l1d_cluster_shared_flush evicts only the shared partition,
  // leaving private data intact.
  //
  // Steps:
  //   1. half-half, default boundary.
  //      gemm_A = private (value 3 from Part 2), gemm_D = shared (value 4).
  //   2. All cores load both regions into cache.
  //   3. Flush shared only -> gemm_D evicted, gemm_A still cached.
  //   4. Lower boundary to 0x7000_0000 -> gemm_D becomes private.
  //   5. All cores copy B->D (value 2) through private banks -> flush private
  //      -> value 2 written to DRAM for gemm_D.
  //   6. Restore boundary -> reload gemm_D -> flush -> check value = 2.
  //      Seeing 2 confirms shared banks were cold (not stale value 4).
  //   Waveform: gemm_A should show no refill traffic after step 3.

  if (cid == 0) printf("\n=== Part 3: Shared flush isolation ===\n");

  l1d_xbar_config(local_offset);
  l1d_part(2);
  l1d_addr(BOUNDARY_DEFAULT);

  // Step 2: populate private (gemm_A) and shared (gemm_D) into cache.
  stream_load(a_ptr, test_len);
  snrt_cluster_hw_barrier();
  stream_load(d_ptr, test_len);
  snrt_cluster_hw_barrier();

  // Step 3: flush shared only.
  l1d_cluster_shared_flush();

  if (cid == 0) printf("Shared flushed. Lowering boundary...\n");

  // Step 4: lower boundary -> gemm_D now private.
  l1d_addr(BOUNDARY_LOW);

  // Step 5: write value 2 into gemm_D via private banks, flush to DRAM.
  stream_copy_vec(d_ptr, b_ptr, test_len);
  snrt_cluster_hw_barrier();
  l1d_cluster_private_flush(all_tiles);

  // Step 6: restore boundary, reload gemm_D, flush, check.
  l1d_addr(BOUNDARY_DEFAULT);
  l1d_xbar_config(local_offset);
  l1d_part(2);

  stream_load(d_ptr, test_len);
  snrt_cluster_hw_barrier();
  l1d_cluster_flush();

  if (cid == 0) {
    uint32_t fail_idx, fail_val;
    // gemm_D must have been refetched from DRAM with the new value (2).
    int pass_d = check_const(gemm_D_dram, test_len, 2, &fail_idx, &fail_val);
    if (!pass_d)
      printf("  gemm_D FAIL idx %u exp 2 got 0x%x\n", fail_idx, fail_val);
    // gemm_A must still hold its last written value (3): private banks untouched.
    int pass_a = check_const(gemm_A_dram, test_len, 3, &fail_idx, &fail_val);
    if (!pass_a)
      printf("  gemm_A FAIL idx %u exp 3 got 0x%x\n", fail_idx, fail_val);
    printf("shared-flush-isolation: %s\n", (pass_d && pass_a) ? "PASS" : "FAIL");
  }
  snrt_cluster_hw_barrier();

#endif  // LS_FLUSH_ISOLATION

  // ===========================================================================
  // Part 4: Group folding of the private partition
  // ===========================================================================
  // With GROUP_FOLD set, a private line lives in the tile its local address
  // bits select, so it is often a sibling tile reached over the intra-group
  // port. Two sub-tests, because they fail for different reasons:
  //
  //   4a: every core writes a unique pattern, flush, each core checks its own
  //       slice. Catches a wrong home tile, a lost write, or a writeback to
  //       the wrong DRAM address (routing and refill rotation disagreeing).
  //
  //   4b: one core writes, a core in a *different tile of the same group*
  //       reads with no flush in between. This is the only check that can tell
  //       a working fold from one that silently does nothing: 4a passes either
  //       way, because a write and read-back from the same core land in the
  //       same place whether or not the line was folded.
  //
  // Sizing is handled by the sparse block layout above: it walks the
  // local-tile field through all four values at both offsets, so no case here
  // degenerates into purely local accesses.

  if (cid == 0) printf("\n=== Part 4a: Group folding, write/flush/verify ===\n");

  // Each core prepares its own source pattern once; the cases then copy it.
  uint32_t *src = fold_src + cid * SRC_ELEMS_PER_CORE;
  fold_src_init(src, cid << 20);
  snrt_cluster_hw_barrier();

  l1d_addr(BOUNDARY_DEFAULT);

  static const uint32_t fold_modes[] = {L1D_FOLD_TILE, L1D_FOLD_GROUP};
  static const char    *fold_names[] = {"fold-tile ", "fold-group"};
  static const uint32_t offsets[]    = {6, 8};
  // Each core's blocks live inside its own 4 KiB window.
  const uint32_t region_elems = FOLD_BLOCKS * FOLD_STRIDE;

  // gemm_A is in .pdcp_src (>= boundary) so it is classified private and the
  // fold applies; gemm_D is in .data (< boundary) and stays shared, which
  // exercises the unchanged path alongside it in the mixed partition.
#if LS_FOLD_MIN
  const uint32_t n_part = 1, n_fold = 1, n_off = 1;
#else
  const uint32_t n_part = 2, n_fold = 2, n_off = 2;
#endif

  for (uint32_t pm = 0; pm < n_part; pm++) {
    const uint32_t part = (pm == 0) ? num_cores_per_tile      // all-private
                                    : (num_cores_per_tile / 2); // mixed
    for (uint32_t fi = 0; fi < n_fold; fi++) {
      // Minimal mode wants fold-group, which is index 1.
      const uint32_t f = (LS_FOLD_MIN != 0) ? 1u : fi;
      for (uint32_t o = 0; o < n_off; o++) {
        l1d_xbar_config(offsets[o]);
        l1d_part_folded(part, fold_modes[f]);

        copy_blocks(a_ptr, src);
        if (part != num_cores_per_tile) {
          copy_blocks(d_ptr, src);
        }
        snrt_cluster_hw_barrier();
        l1d_cluster_flush();

        int err = check_blocks(a_ptr, src);
        if (part != num_cores_per_tile) {
          err += check_blocks(d_ptr, src);
        }
        error_cnt[cid] = err;
        snrt_cluster_hw_barrier();

        if (cid == 0) {
          int total = 0;
          for (uint32_t c = 0; c < num_cores; c++) {
            total += error_cnt[c];
          }
          printf("%s part=%u offset=%u: %s (%d errors)\n", fold_names[f], part,
                 offsets[o], total ? "FAIL" : "PASS", total);
        }
        snrt_cluster_hw_barrier();
      }
    }
  }

#if !LS_FOLD_MIN
  // ---------------------------------------------------------------------------
  // Part 4b: intra-group visibility
  // ---------------------------------------------------------------------------
  // Writer is core 0 of each group, reader is core 0 of the group's second
  // tile. DRAM is first seeded with an OLD pattern, then the writer stores NEW
  // with no flush. Folded, the reader's request routes to the tile holding the
  // line and returns NEW; unfolded, it misses in its own tile and refills OLD.
  // So the expected result differs per mode, which is what makes this a real
  // discriminator rather than a check that passes regardless.

  if (cid == 0) printf("\n=== Part 4b: Intra-group visibility ===\n");

  const uint32_t cores_per_group = num_cores / snrt_cluster_group_num();
  const uint32_t grp             = cid / cores_per_group;
  const uint32_t cid_in_grp      = cid % cores_per_group;
  const int is_writer = (cid_in_grp == 0);
  const int is_reader = (cid_in_grp == num_cores_per_tile);  // first core, 2nd tile

  for (uint32_t f = 0; f < 2; f++) {
    // Two distinct patterns staged in this core's source area halves.
    uint32_t *old_src = src;
    uint32_t *new_src = fold_src + ((cid + 1) % num_cores) * SRC_ELEMS_PER_CORE;
    // Region owned by this group, addressed identically by writer and reader.
    uint32_t *region = gemm_A_dram + grp * region_elems;

    l1d_xbar_config(6);
    l1d_part_folded(num_cores_per_tile, fold_modes[f]);

    // Seed DRAM with OLD, from the writer only, and flush it out.
    if (is_writer) {
      copy_blocks(region, old_src);
    }
    snrt_cluster_hw_barrier();
    l1d_cluster_flush();

    // Writer stores NEW and does NOT flush.
    if (is_writer) {
      copy_blocks(region, new_src);
    }
    snrt_cluster_hw_barrier();

    // Reader looks for NEW. Folded it should see it; unfolded it should not.
    error_cnt[cid] = 0;
    if (is_reader) {
      error_cnt[cid] = check_blocks(region, new_src);
    }
    snrt_cluster_hw_barrier();

    if (cid == 0) {
      int seen = 0, missed = 0;
      for (uint32_t c = 0; c < num_cores; c++) {
        if ((c % cores_per_group) == num_cores_per_tile) {
          if (error_cnt[c] == 0) {
            seen++;
          } else {
            missed++;
          }
        }
      }
      const int want_visible = (fold_modes[f] == L1D_FOLD_GROUP);
      const int pass = want_visible ? (missed == 0) : (seen == 0);
      printf("%s: reader sees writer in %d groups, stale in %d -> %s\n",
             fold_names[f], seen, missed, pass ? "PASS" : "FAIL");
    }
    snrt_cluster_hw_barrier();
  }

#endif  // !LS_FOLD_MIN

  // Restore a sane configuration for anything that follows.
  l1d_xbar_config(local_offset);
  l1d_part(num_cores_per_tile);

  if (cid == 0) printf("\n*** All tests complete ***\n");

  return 0;
}
