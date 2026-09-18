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

// Author: Diyou Shen, ETH Zurich

// Coalescer false sharing test for CachePool L1 cache
//
// Tests back-to-back vector store then vector load to the same cacheline
// from different cores, exercising the coalescer's partial-line merging.
//
// Build: same setup as FFT tests, needs benchmark.h and snrt.h

#include <stdio.h>
#include <benchmark.h>
#include <snrt.h>
#include <stdint.h>

#ifndef OFFSET_CFG
#define OFFSET_CFG 6
#endif

// 512-bit cacheline = 64 bytes = 16 x float32
#define CL_BYTES  64
#define CL_WORDS  16

// Number of cachelines to test
#define NUM_CL    4
#define NUM_WORDS (CL_WORDS * NUM_CL)

// Data arrays in DRAM — will be cached through L1
// Align to cacheline boundary
volatile float data_a[NUM_WORDS] __attribute__((section(".l1"))) __attribute__((aligned(64)));
volatile float data_b[NUM_WORDS] __attribute__((section(".l1"))) __attribute__((aligned(64)));

// ---------------------------------------------------------------------------
// Test 1: Scalar — two cores store to adjacent words, then cross-read
// ---------------------------------------------------------------------------
static uint32_t test_scalar_cross(uint32_t cid, uint32_t num_cores) {
  uint32_t errors = 0;
  if (num_cores < 2) return 0;

  // Init
  if (cid == 0) {
    for (uint32_t i = 0; i < CL_WORDS; i++)
      data_a[i] = 0.0f;
  }
  snrt_cluster_hw_barrier();

  // Core 0 writes word[0], Core 1 writes word[1]
  if (cid == 0) data_a[0] = 1.0f;
  if (cid == 1) data_a[1] = 2.0f;
  snrt_cluster_hw_barrier();

  // Cross-read
  if (cid == 0) {
    float val = data_a[1];
    if (val != 2.0f) {
      printf("T1 FAIL: c0 read [1]=%.1f exp 2.0\n", val);
      errors++;
    }
  }
  if (cid == 1) {
    float val = data_a[0];
    if (val != 1.0f) {
      printf("T1 FAIL: c1 read [0]=%.1f exp 1.0\n", val);
      errors++;
    }
  }
  snrt_cluster_hw_barrier();
  return errors;
}

// ---------------------------------------------------------------------------
// Test 2: Scalar — 4 cores write to words [0..3], then all verify
// ---------------------------------------------------------------------------
static uint32_t test_scalar_four_core(uint32_t cid, uint32_t num_cores) {
  uint32_t errors = 0;
  uint32_t active = (num_cores < 4) ? num_cores : 4;

  if (cid == 0) {
    for (uint32_t i = 0; i < CL_WORDS; i++)
      data_a[i] = 0.0f;
  }
  snrt_cluster_hw_barrier();

  if (cid < active) {
    data_a[cid] = (float)(cid + 10);
  }
  snrt_cluster_hw_barrier();

  if (cid == 0) {
    for (uint32_t i = 0; i < active; i++) {
      float expected = (float)(i + 10);
      float actual   = data_a[i];
      if (actual != expected) {
        printf("T2 FAIL: [%d]=%.1f exp %.1f\n", i, actual, expected);
        errors++;
      }
    }
  }
  snrt_cluster_hw_barrier();
  return errors;
}

// ---------------------------------------------------------------------------
// Test 3: Vector store — two cores do vector stores to same cacheline
//
// Core 0: vse32 to words [0..3]  (4 floats = 16 bytes)
// Core 1: vse32 to words [4..7]  (4 floats = 16 bytes)
// Both within the same 64-byte cacheline.
//
// Uses e32, m1 with avl=4 to store 4 elements per vector instruction.
// This fires 4 memory requests from Spatz back-to-back.
// ---------------------------------------------------------------------------
static uint32_t test_vector_store_same_cl(uint32_t cid, uint32_t num_cores) {
  uint32_t errors = 0;
  if (num_cores < 2) return 0;

  // Init with scalar from core 0
  if (cid == 0) {
    for (uint32_t i = 0; i < CL_WORDS; i++)
      data_a[i] = 0.0f;
    // Prepare source data for vector stores
    for (uint32_t i = 0; i < CL_WORDS; i++)
      data_b[i] = (float)(100 + i);
  }
  snrt_cluster_hw_barrier();

  // Core 0: vector store 4 floats to data_a[0..3]
  // Core 1: vector store 4 floats to data_a[4..7]
  if (cid == 0) {
    volatile float *src = &data_b[0];
    volatile float *dst = &data_a[0];
    size_t vl;
    asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(4));
    asm volatile("vle32.v v0, (%0)" ::"r"(src));
    asm volatile("vse32.v v0, (%0)" ::"r"(dst));
  }
  if (cid == 1) {
    volatile float *src = &data_b[4];
    volatile float *dst = &data_a[4];
    size_t vl;
    asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(4));
    asm volatile("vle32.v v0, (%0)" ::"r"(src));
    asm volatile("vse32.v v0, (%0)" ::"r"(dst));
  }
  snrt_cluster_hw_barrier();

  // Verify all 8 words
  if (cid == 0) {
    for (uint32_t i = 0; i < 8; i++) {
      float expected = (float)(100 + i);
      float actual   = data_a[i];
      if (actual != expected) {
        printf("T3 FAIL: [%d]=%.1f exp %.1f\n", i, actual, expected);
        errors++;
      }
    }
  }
  snrt_cluster_hw_barrier();
  return errors;
}

// ---------------------------------------------------------------------------
// Test 4: Vector butterfly pattern — store then cross-load
//
// Mimics the FFT butterfly: core 0 stores upper wing (4 floats),
// core 1 stores lower wing (4 floats), both in the same cacheline.
// Then each core loads the other's result using vector load.
//
// This creates the exact coalescer scenario: back-to-back vector
// stores from two cores to the same cacheline, followed by vector
// loads to the same cacheline.
// ---------------------------------------------------------------------------
static uint32_t test_vector_butterfly(uint32_t cid, uint32_t num_cores) {
  uint32_t errors = 0;
  if (num_cores < 2) return 0;

  // Init
  if (cid == 0) {
    for (uint32_t i = 0; i < CL_WORDS; i++) {
      data_a[i] = 0.0f;
      data_b[i] = 0.0f;
    }
    // Core 0 source: words 0..3
    data_b[0]  = 10.0f;
    data_b[1]  = 11.0f;
    data_b[2]  = 12.0f;
    data_b[3]  = 13.0f;
    // Core 1 source: words 4..7
    data_b[4]  = 20.0f;
    data_b[5]  = 21.0f;
    data_b[6]  = 22.0f;
    data_b[7]  = 23.0f;
  }
  snrt_cluster_hw_barrier();

  // Phase 1: Both cores vector-store to same cacheline (data_a)
  if (cid == 0) {
    volatile float *src = &data_b[0];
    volatile float *dst = &data_a[0];
    size_t vl;
    asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(4));
    asm volatile("vle32.v v0, (%0)" ::"r"(src));
    asm volatile("vse32.v v0, (%0)" ::"r"(dst));
  }
  if (cid == 1) {
    volatile float *src = &data_b[4];
    volatile float *dst = &data_a[4];
    size_t vl;
    asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(4));
    asm volatile("vle32.v v0, (%0)" ::"r"(src));
    asm volatile("vse32.v v0, (%0)" ::"r"(dst));
  }
  snrt_cluster_hw_barrier();

  // Phase 2: Cross-load with vector load
  // Core 0 reads core 1's words [4..7], stores to data_b[8..11]
  if (cid == 0) {
    volatile float *src = &data_a[4];
    volatile float *dst = &data_b[8];
    size_t vl;
    asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(4));
    asm volatile("vle32.v v0, (%0)" ::"r"(src));
    asm volatile("vse32.v v0, (%0)" ::"r"(dst));
  }
  // Core 1 reads core 0's words [0..3], stores to data_b[12..15]
  if (cid == 1) {
    volatile float *src = &data_a[0];
    volatile float *dst = &data_b[12];
    size_t vl;
    asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(4));
    asm volatile("vle32.v v0, (%0)" ::"r"(src));
    asm volatile("vse32.v v0, (%0)" ::"r"(dst));
  }
  snrt_cluster_hw_barrier();

  // Scalar verify
  if (cid == 0) {
    // Core 0 cross-loaded core 1's data into data_b[8..11]
    float exp_cross[4] = {20.0f, 21.0f, 22.0f, 23.0f};
    for (uint32_t i = 0; i < 4; i++) {
      if (data_b[8 + i] != exp_cross[i]) {
        printf("T4 FAIL: c0 cross[%d]=%.1f exp %.1f\n", i, data_b[8+i], exp_cross[i]);
        errors++;
      }
    }
    // Verify core 0's own words survived in data_a[0..3]
    float exp_own[4] = {10.0f, 11.0f, 12.0f, 13.0f};
    for (uint32_t i = 0; i < 4; i++) {
      if (data_a[i] != exp_own[i]) {
        printf("T4 FAIL: c0 own[%d]=%.1f exp %.1f\n", i, data_a[i], exp_own[i]);
        errors++;
      }
    }
  }
  snrt_cluster_hw_barrier();
  return errors;
}

// ---------------------------------------------------------------------------
// Test 5: Wider vector (m4) — mimics actual FFT memory pattern
//
// Uses e32, m4 like the real FFT kernel. With VLEN=128 and m4,
// each vector instruction handles 16 floats = 64 bytes = one full
// cacheline. Two cores each store a full cacheline to adjacent
// lines, then cross-read.
//
// This creates maximum Spatz memory port pressure — all 4 FUs fire
// simultaneously, producing 4 back-to-back requests to the same
// cache bank.
// ---------------------------------------------------------------------------
static uint32_t test_vector_m4_pressure(uint32_t cid, uint32_t num_cores) {
  uint32_t errors = 0;
  if (num_cores < 2) return 0;

  // Init both cachelines
  if (cid == 0) {
    for (uint32_t i = 0; i < NUM_WORDS; i++) {
      data_a[i] = 0.0f;
      data_b[i] = (float)(200 + i);
    }
  }
  snrt_cluster_hw_barrier();

  // Core 0: m4 vector store to data_a[0..15]  (cacheline 0)
  // Core 1: m4 vector store to data_a[16..31] (cacheline 1)
  // With dynamic_offset=6, consecutive cachelines go to different
  // banks, so these hit different controllers — no false sharing.
  // But with smaller offsets or different alignment, they could
  // alias to the same bank.
  if (cid == 0) {
    volatile float *src = &data_b[0];
    volatile float *dst = &data_a[0];
    size_t vl;
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(16));
    asm volatile("vle32.v v0, (%0)" ::"r"(src));
    asm volatile("vse32.v v0, (%0)" ::"r"(dst));
  }
  if (cid == 1) {
    volatile float *src = &data_b[16];
    volatile float *dst = &data_a[16];
    size_t vl;
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(16));
    asm volatile("vle32.v v0, (%0)" ::"r"(src));
    asm volatile("vse32.v v0, (%0)" ::"r"(dst));
  }
  snrt_cluster_hw_barrier();

  // Cross-read with m4 vector load
  if (cid == 0) {
    volatile float *src = &data_a[16]; // core 1's cacheline
    volatile float *dst = &data_b[32]; // temp
    size_t vl;
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(16));
    asm volatile("vle32.v v0, (%0)" ::"r"(src));
    asm volatile("vse32.v v0, (%0)" ::"r"(dst));
  }
  snrt_cluster_hw_barrier();

  if (cid == 0) {
    for (uint32_t i = 0; i < 16; i++) {
      float expected = (float)(200 + 16 + i);
      float actual   = data_b[32 + i];
      if (actual != expected) {
        printf("T5 FAIL: [%d]=%.1f exp %.1f\n", i, actual, expected);
        errors++;
      }
    }
  }
  snrt_cluster_hw_barrier();
  return errors;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
int main() {
  const uint32_t num_cores = snrt_cluster_core_num();
  const uint32_t cid       = snrt_cluster_core_idx();
  uint32_t total_errors = 0;

  l1d_xbar_config(OFFSET_CFG);

  // T1: Scalar two-core cross
  if (cid == 0) printf("\n--- T1: Scalar cross ---\n");
  snrt_cluster_hw_barrier();
  if (cid == 0) start_kernel();
  snrt_cluster_hw_barrier();
  total_errors += test_scalar_cross(cid, num_cores);
  snrt_cluster_hw_barrier();
  if (cid == 0) stop_kernel();
  snrt_cluster_hw_barrier();

  // T2: Scalar four-core
  if (cid == 0) printf("--- T2: Scalar 4-core ---\n");
  snrt_cluster_hw_barrier();
  if (cid == 0) start_kernel();
  snrt_cluster_hw_barrier();
  total_errors += test_scalar_four_core(cid, num_cores);
  snrt_cluster_hw_barrier();
  if (cid == 0) stop_kernel();
  snrt_cluster_hw_barrier();

  // T3: Vector store same cacheline
  if (cid == 0) printf("--- T3: Vec store same CL ---\n");
  snrt_cluster_hw_barrier();
  if (cid == 0) start_kernel();
  snrt_cluster_hw_barrier();
  total_errors += test_vector_store_same_cl(cid, num_cores);
  snrt_cluster_hw_barrier();
  if (cid == 0) stop_kernel();
  snrt_cluster_hw_barrier();

  // T4: Vector butterfly pattern
  if (cid == 0) printf("--- T4: Vec butterfly ---\n");
  snrt_cluster_hw_barrier();
  if (cid == 0) start_kernel();
  snrt_cluster_hw_barrier();
  total_errors += test_vector_butterfly(cid, num_cores);
  snrt_cluster_hw_barrier();
  if (cid == 0) stop_kernel();
  snrt_cluster_hw_barrier();

  // T5: m4 pressure test
  if (cid == 0) printf("--- T5: Vec m4 pressure ---\n");
  snrt_cluster_hw_barrier();
  if (cid == 0) start_kernel();
  snrt_cluster_hw_barrier();
  total_errors += test_vector_m4_pressure(cid, num_cores);
  snrt_cluster_hw_barrier();
  if (cid == 0) stop_kernel();
  snrt_cluster_hw_barrier();

  if (cid == 0) {
    if (total_errors == 0)
      printf("\nALL TESTS PASSED (offset=%d)\n", OFFSET_CFG);
    else
      printf("\nFAILED: %d errors (offset=%d)\n", total_errors, OFFSET_CFG);
  }

  snrt_cluster_hw_barrier();
  return (total_errors > 0) ? 1 : 0;
}
