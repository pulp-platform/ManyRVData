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

#include DATAHEADER

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
// Helpers
// -----------------------------------------------------------------------------

static inline void sync_all() { snrt_cluster_hw_barrier(); }

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

// Cache configuration: offset + invalidate + set partition.
static void cache_cfg(uint32_t cid, uint32_t xbar_offset, uint32_t part) {
  if (cid == 0) {
    l1d_xbar_config(xbar_offset);
    l1d_init(0);
    l1d_part(part);
  }
  sync_all();
}

// Flush all banks and wait for completion.
static void cache_flush_all(uint32_t cid) {
  if (cid == 0) {
    l1d_flush();
    l1d_wait();
  }
  sync_all();
}

// Flush private banks of selected tiles (one-hot mask) and wait.
static void cache_flush_private(uint32_t cid, uint32_t tile_mask) {
  if (cid == 0) {
    l1d_private_flush(tile_mask);
    l1d_wait();
  }
  sync_all();
}

// Flush shared banks of all tiles and wait.
static void cache_flush_shared(uint32_t cid) {
  if (cid == 0) {
    l1d_shared_flush();
    l1d_wait();
  }
  sync_all();
}

// Set partition boundary address.
static void cache_set_boundary(uint32_t cid, uint32_t addr) {
  if (cid == 0) {
    l1d_addr(addr);
  }
  sync_all();
}

// Print PASS/FAIL for a named test.
static void report(uint32_t cid, const char *name, int pass) {
  if (cid == 0) {
    printf("%s: %s\n", name, pass ? "PASS" : "FAIL");
  }
}

// -----------------------------------------------------------------------------
// main
// -----------------------------------------------------------------------------
int main() {
  const uint32_t num_cores = snrt_cluster_core_num();
  const uint32_t num_tiles = snrt_cluster_tile_num();
  const uint32_t cid       = snrt_cluster_core_idx();

  const uint32_t dim_core  = gemm_l.M / num_cores;
  const uint32_t test_len  = cls_to_elems(TEST_CLS);  // per core, short

  // xbar offset: size of per-core region in address bits
  const uint32_t local_offset = 31 - __builtin_clz(dim_core * sizeof(uint32_t));

  // One-hot mask covering all tiles
  const uint32_t all_tiles = (1u << num_tiles) - 1u;

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

  if (cid == 0) printf("=== Part 1: Partitioning ===\n");

  static const uint32_t part_modes[]  = {0, 1, 2, 3, 4};
  static const uint32_t part_expect[] = {2, 3, 2, 3, 2};
  static const char    *part_names[]  = {
    "all-shared", "1priv-3shr", "half-half", "3priv-1shr", "all-private"
  };

  for (int m = 0; m < 5; m++) {
    uint32_t part = part_modes[m];
    uint32_t exp  = part_expect[m];

    // Source: B (value 2) for even modes, C (value 3) for odd modes.
    uint32_t *src = (exp == 2) ? b_ptr : c_ptr;

    cache_cfg(cid, local_offset, part);

    // All cores copy in parallel into their slice of gemm_A.
    stream_copy_vec(a_ptr, src, test_len);
    sync_all();

    cache_flush_all(cid);

    if (cid == 0) {
      uint32_t fail_idx, fail_val;
      int pass = check_const(gemm_A_dram, test_len, exp, &fail_idx, &fail_val);
      if (!pass)
        printf("  FAIL idx %u exp 0x%x got 0x%x\n", fail_idx, exp, fail_val);
      report(cid, part_names[m], pass);
    }
    sync_all();
  }

  // ===========================================================================
  // Part 2: Private flush isolation
  // ===========================================================================
  // Verifies that cache_flush_private evicts only the private partition,
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

  cache_cfg(cid, local_offset, 2);
  cache_set_boundary(cid, BOUNDARY_DEFAULT);

  // Step 2: populate private (gemm_A, value 2 from previous test) and shared
  // (gemm_D, value 4) into cache.
  stream_load(a_ptr, test_len);
  sync_all();
  stream_load(d_ptr, test_len);
  sync_all();

  // Step 3: flush private only.
  cache_flush_private(cid, all_tiles);

  if (cid == 0) printf("Private flushed. Raising boundary...\n");

  // Step 4: raise boundary -> gemm_A now shared.
  cache_set_boundary(cid, BOUNDARY_HIGH);

  // Step 5: write value 3 into gemm_A via shared banks, flush to DRAM.
  stream_copy_vec(a_ptr, c_ptr, test_len);
  sync_all();
  cache_flush_all(cid);

  // Step 6: restore boundary, reload gemm_A, flush, check.
  cache_set_boundary(cid, BOUNDARY_DEFAULT);
  cache_cfg(cid, local_offset, 2);

  stream_load(a_ptr, test_len);
  sync_all();
  cache_flush_all(cid);

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
    report(cid, "private-flush-isolation", pass_a && pass_d);
  }
  sync_all();

  // ===========================================================================
  // Part 3: Shared flush isolation
  // ===========================================================================
  // Verifies that cache_flush_shared evicts only the shared partition,
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

  cache_cfg(cid, local_offset, 2);
  cache_set_boundary(cid, BOUNDARY_DEFAULT);

  // Step 2: populate private (gemm_A) and shared (gemm_D) into cache.
  stream_load(a_ptr, test_len);
  sync_all();
  stream_load(d_ptr, test_len);
  sync_all();

  // Step 3: flush shared only.
  cache_flush_shared(cid);

  if (cid == 0) printf("Shared flushed. Lowering boundary...\n");

  // Step 4: lower boundary -> gemm_D now private.
  cache_set_boundary(cid, BOUNDARY_LOW);

  // Step 5: write value 2 into gemm_D via private banks, flush to DRAM.
  stream_copy_vec(d_ptr, b_ptr, test_len);
  sync_all();
  cache_flush_private(cid, all_tiles);

  // Step 6: restore boundary, reload gemm_D, flush, check.
  cache_set_boundary(cid, BOUNDARY_DEFAULT);
  cache_cfg(cid, local_offset, 2);

  stream_load(d_ptr, test_len);
  sync_all();
  cache_flush_all(cid);

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
    report(cid, "shared-flush-isolation", pass_d && pass_a);
  }
  sync_all();

  if (cid == 0) printf("\n*** All tests complete ***\n");

  return 0;
}
