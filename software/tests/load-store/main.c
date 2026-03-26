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
// Test length control
// -----------------------------------------------------------------------------
// Define SHORT_TEST for faster functional/interconnect testing.
// Test 1/2 use shortened accesses.
// Test 3 keeps capacity-style behavior.
#define SHORT_TEST 1

// Cache line assumptions for test sizing.
// Adjust if your cacheline size is different.
#define CACHELINE_BYTES 64
#define ELEM_BYTES      sizeof(uint32_t)
#define ELEMS_PER_CL    (CACHELINE_BYTES / ELEM_BYTES)

#if SHORT_TEST
#define LOCAL_TEST_CLS   16   // per core, functional local traffic
#define GLOBAL_TEST_CLS  32   // per core, functional shared traffic
#else
#define LOCAL_TEST_CLS   0    // 0 means use original full length
#define GLOBAL_TEST_CLS  0
#endif

typedef struct {
  uint32_t cold;
  uint32_t hot;
} test_result_t;

static inline void sync_all() { snrt_cluster_hw_barrier(); }

static inline uint32_t min_u32(uint32_t a, uint32_t b) { return (a < b) ? a : b; }

static inline uint32_t cls_to_elems(uint32_t cls) {
  return cls * ELEMS_PER_CL;
}

static inline void stream_copy_vec(uint32_t *dst, uint32_t *src, uint32_t count) {
  uint32_t avl = count;
  uint32_t vlen;

  do {
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma"
                 : "=r"(vlen)
                 : "r"(avl));
    asm volatile("vle32.v v0, (%0)" : : "r"(src));
    asm volatile("vse32.v v0, (%0)" : : "r"(dst));
    src += vlen;
    dst += vlen;
    avl -= vlen;
  } while (avl > 0);
}

static uint32_t timed_stream_copy_vec(uint32_t *dst, uint32_t *src,
                                      uint32_t count, uint32_t cid) {
  uint32_t cycles = 0;

  sync_all();

  if (cid == 0) {
    start_kernel();
    cycles = benchmark_get_cycle();
  }

  stream_copy_vec(dst, src, count);

  sync_all();

  if (cid == 0) {
    cycles = benchmark_get_cycle() - cycles;
    stop_kernel();
  } else {
    cachepool_wait(10);
  }

  return cycles;
}

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

static inline void stream_load(uint32_t *ptr, uint32_t count) {
  uint32_t avl = count;
  uint32_t vlen;
  do {
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vlen) : "r"(avl));
    asm volatile("vle32.v v0, (%0)" : : "r"(ptr));
    ptr += vlen;
    avl -= vlen;
  } while (avl > 0);
}

static uint32_t timed_stream_load(uint32_t *ptr, uint32_t count, uint32_t cid) {
  uint32_t cycles = 0;

  sync_all();

  if (cid == 0) {
    start_kernel();
    cycles = benchmark_get_cycle();
  }

  stream_load(ptr, count);

  sync_all();

  if (cid == 0) {
    cycles = benchmark_get_cycle() - cycles;
    stop_kernel();
  } else {
    cachepool_wait(10);
  }

  return cycles;
}

static test_result_t run_cold_hot_test(uint32_t *ptr, uint32_t count,
                                       uint32_t cid, uint32_t num_iters) {
  test_result_t res = {0, (uint32_t)-1};

  for (uint32_t i = 0; i < num_iters; i++) {
    sync_all();
    uint32_t cyc = timed_stream_load(ptr, count, cid);
    if (cid == 0) {
      if (i == 0) {
        res.cold = cyc;
      } else if (cyc < res.hot) {
        res.hot = cyc;
      }
    }
  }

  if (num_iters == 1) res.hot = res.cold;
  return res;
}

static uint32_t run_evict_test(uint32_t *evict_ptr, uint32_t *test_ptr,
                               uint32_t count, uint32_t cid) {
  sync_all();
  stream_load(evict_ptr, count);
  sync_all();
  return timed_stream_load(test_ptr, count, cid);
}

static void cache_cfg(uint32_t cid, uint32_t xbar_offset, uint32_t part) {
  if (cid == 0) {
    l1d_xbar_config(xbar_offset);
    l1d_init(0);
    l1d_part(part);
  }
  sync_all();
}

static void cache_flush_all(uint32_t cid) {
  if (cid == 0) {
    l1d_flush();
    l1d_wait();
  }
  sync_all();
}

int main() {
  const uint32_t num_cores = snrt_cluster_core_num();
  const uint32_t num_tiles = snrt_cluster_tile_num();
  const uint32_t cid       = snrt_cluster_core_idx();

  const uint32_t dim      = gemm_l.M;
  const uint32_t dim_core = dim / num_cores;
  const uint32_t dim_tile = dim / num_tiles;

  const uint32_t local_offset  = 31 - __builtin_clz(dim_core * sizeof(uint32_t));
  const uint32_t global_offset = 0;

  // Keep starting points unchanged.
  uint32_t *local_ptr  = gemm_A_dram + dim_core * cid;
  uint32_t *global_ptr = gemm_A_dram;
  uint32_t *next_ptr   = gemm_A_dram + dim_tile;

  // Shortened functional lengths.
  uint32_t local_len  = dim_core;
  uint32_t global_len = dim_tile;

#if SHORT_TEST
  local_len  = min_u32(dim_core, cls_to_elems(LOCAL_TEST_CLS));
  global_len = min_u32(dim_tile, cls_to_elems(GLOBAL_TEST_CLS));
#endif

  // Keep original capacity-style eviction length.
  uint32_t evict_len = dim_tile;

  test_result_t test1, test2;
  uint32_t test3;

  if (cid == 0) {
    printf("*** Cache/interconnect test ***\n");
#if SHORT_TEST
    printf("Mode: SHORT_TEST\n");
    printf("Local length : %u elems (%u cache lines)\n",
           local_len, local_len / ELEMS_PER_CL);
    printf("Global length: %u elems (%u cache lines)\n",
           global_len, global_len / ELEMS_PER_CL);
#else
    printf("Mode: FULL_TEST\n");
    printf("Local length : %u elems\n", local_len);
    printf("Global length: %u elems\n", global_len);
#endif
    printf("Evict length : %u elems\n\n", evict_len);
  }

  // ---------------------------------------------------------------------------
  // Shared cache
  // ---------------------------------------------------------------------------
  if (cid == 0) {
    printf("***Testing shared cache configuration***\n");
  }

  cache_cfg(cid, local_offset, 0);

  uint32_t *a_local_ptr = gemm_A_dram + dim_core * cid;
  uint32_t *b_local_ptr = gemm_B_dram + dim_core * cid;
  uint32_t test1_cyc;

  if (cid == 0) {
    printf("Test 1: Local Vector Copy + Flush + Check\n");
    printf("dim per core:%u\n", local_len);
    printf("a_ptr:%p\n", (void *)a_local_ptr);
    printf("b_ptr:%p\n", (void *)b_local_ptr);
  }

  test1_cyc = timed_stream_copy_vec(a_local_ptr, b_local_ptr, local_len, cid);

  if (cid == 0) {
    printf("Vector copy complete\n");
    printf("Cycles:%u cyc\n", test1_cyc);
    printf("Flushing cache...\n");
  }

  cache_flush_all(cid);

  if (cid == 0) {
    int pass = 1;
    for (uint32_t core = 0; core < num_cores; core++) {
      uint32_t fail_idx, fail_val;
      uint32_t *check_ptr = gemm_A_dram + dim_core * core;
      if (!check_const(check_ptr, local_len, 2, &fail_idx, &fail_val)) {
        printf("FAIL at core %u idx %u addr %p exp 0x%x got 0x%x\n",
               core, fail_idx, (void *)&check_ptr[fail_idx], 2, fail_val);
        pass = 0;
        break;
      }
    }

    printf("Test 1 Complete\n");
    printf("Result:%s\n", pass ? "PASS" : "FAIL");
  }

  sync_all();

  if (cid == 0) {
    printf("\nTest 2: Global Visit\n");
    printf("dim per core:%u\n", global_len);
    printf("a_ptr:%x\n", global_ptr);
  }

  cache_flush_all(cid);
  cache_cfg(cid, global_offset, 0);

  test2 = run_cold_hot_test(global_ptr, global_len, cid, 3);

  if (cid == 0) {
    printf("Test 2 Complete\n");
    printf("Cold:%u cyc; Hot:%u cyc\n", test2.cold, test2.hot);

    printf("\nTest 3: Eviction Test\n");
    printf("dim per core:%u\n", evict_len);
    printf("evict_ptr:%x\n", next_ptr);
    printf("test_ptr:%x\n", global_ptr);
  }

#if SHORT_TEST
  if (cid == 0) {
    printf("Skip Test 3 in Short Test Mode\n");
  }
#else
  test3 = run_evict_test(next_ptr, global_ptr, evict_len, cid);

  if (cid == 0) {
    printf("Test 3 Complete\n");
    printf("Result:%u cyc\n", test3);
  }
#endif

  // ---------------------------------------------------------------------------
  // Private cache
  // ---------------------------------------------------------------------------
  if (cid == 0) {
    printf("\n***Testing private cache configuration***\n");
  }

  cache_cfg(cid, local_offset, 4);
  cache_flush_all(cid);

  if (cid == 0) {
    printf("Configuration done!\n\n");
  }

  a_local_ptr = gemm_A_dram + dim_core * cid;
  b_local_ptr = gemm_C_dram + dim_core * cid;

  if (cid == 0) {
    printf("Test 1: Local Vector Copy + Flush + Check\n");
    printf("dim per core:%u\n", local_len);
    printf("a_ptr:%p\n", (void *)a_local_ptr);
    printf("b_ptr:%p\n", (void *)b_local_ptr);
  }

  test1_cyc = timed_stream_copy_vec(a_local_ptr, b_local_ptr, local_len, cid);

  if (cid == 0) {
    printf("Vector copy complete\n");
    printf("Cycles:%u cyc\n", test1_cyc);
    printf("Flushing cache...\n");
  }

  cache_flush_all(cid);

  if (cid == 0) {
    int pass = 1;
    for (uint32_t core = 0; core < num_cores; core++) {
      uint32_t fail_idx, fail_val;
      uint32_t *check_ptr = gemm_A_dram + dim_core * core;
      if (!check_const(check_ptr, local_len, 3, &fail_idx, &fail_val)) {
        printf("FAIL at core %u idx %u addr %p exp 0x%x got 0x%x\n",
               core, fail_idx, (void *)&check_ptr[fail_idx], 3, fail_val);
        pass = 0;
        break;
      }
    }

    printf("Test 1 Complete\n");
    printf("Result:%s\n", pass ? "PASS" : "FAIL");
  }

  sync_all();

  if (cid == 0) {
    printf("\nTest 2: Global Visit\n");
    printf("dim per core:%u\n", global_len);
    printf("a_ptr:%x\n", global_ptr);
  }

  cache_flush_all(cid);
  cache_cfg(cid, global_offset, 4);

  test2 = run_cold_hot_test(global_ptr, global_len, cid, 3);

  if (cid == 0) {
    printf("Test 2 Complete\n");
    printf("Cold:%u cyc; Hot:%u cyc\n", test2.cold, test2.hot);

    printf("\nTest 3: Eviction Test\n");
    printf("dim per core:%u\n", evict_len);
    printf("evict_ptr:%x\n", next_ptr);
    printf("test_ptr:%x\n", global_ptr);
  }

#if SHORT_TEST
  if (cid == 0) {
    printf("Skip Test 3 in Short Test Mode\n");
  }
#else
  test3 = run_evict_test(next_ptr, global_ptr, evict_len, cid);

  if (cid == 0) {
    printf("Test 3 Complete\n");
    printf("Result:%u cyc\n", test3);
  }
#endif

  // ---------------------------------------------------------------------------
  // Half-half
  // ---------------------------------------------------------------------------
  sync_all();

  if (cid == 0) {
    printf("\n***Testing half-half configuration***\n");
  }

  cache_cfg(cid, local_offset, 2);
  cache_flush_all(cid);

  if (cid == 0) {
    printf("Configuration done!\n\n");
  }

  // D is in the shared region, A in private region
  // Shuffle cid pointers to make sure remote/private access
  if (cid == num_cores - 1) {
    a_local_ptr = gemm_A_dram;
    b_local_ptr = gemm_D_dram;
  } else {
    a_local_ptr = gemm_A_dram + dim_core * (cid + 1);
    b_local_ptr = gemm_D_dram + dim_core * (cid + 1);
  }

  if (cid == 0) {
    printf("Test 1: Local + Share Vector Copy + Flush + Check\n");
    printf("dim per core:%u\n", local_len);
    printf("a_ptr:%p\n", (void *)a_local_ptr);
    printf("b_ptr:%p\n", (void *)b_local_ptr);
  }

  test1_cyc = timed_stream_copy_vec(a_local_ptr, b_local_ptr, local_len, cid);

  if (cid == 0) {
    printf("Vector copy complete\n");
    printf("Cycles:%u cyc\n", test1_cyc);
    printf("Flushing cache...\n");
  }

  cache_flush_all(cid);

  if (cid == 0) {
    int pass = 1;
    for (uint32_t core = 0; core < num_cores; core++) {
      uint32_t fail_idx, fail_val;
      uint32_t *check_ptr = gemm_A_dram + dim_core * core;
      if (!check_const(check_ptr, local_len, 4, &fail_idx, &fail_val)) {
        printf("FAIL at core %u idx %u addr %p exp 0x%x got 0x%x\n",
               core, fail_idx, (void *)&check_ptr[fail_idx], 4, fail_val);
        pass = 0;
        break;
      }
    }

    printf("Test 1 Complete\n");
    printf("Result:%s\n", pass ? "PASS" : "FAIL");
  }


  sync_all();

  return 0;
}

