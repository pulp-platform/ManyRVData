// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0

#include <l1cache.h>
#include <snrt.h>
#include <stdint.h>
#include "printf.h"

#define MAX_CORES 8U
#define REGION_BYTES 1024U
#define TOTAL_BYTES (MAX_CORES * REGION_BYTES)
#define PART_BYTES 16U
#define VEC_LEN 4U
#define ITERS 256U
#define SCALAR_CORE 1U
#define VECTOR_CORE 0U

static uint8_t mix_buf[TOTAL_BYTES] __attribute__((section(".dram")))
    __attribute__((aligned(64)));
static uint32_t vec_vals[VEC_LEN] __attribute__((section(".data"))) = {
    0x11111131u, 0x22222242u, 0x33333353u, 0x44444464u};
static uint32_t core_errors[MAX_CORES] __attribute__((section(".data")));

static inline void vec_store_u32(uint32_t *base) {
  uint32_t vl = 0;
  asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(VEC_LEN));
  asm volatile("vle32.v v0, (%0)" : : "r"(vec_vals) : "memory");
  asm volatile("vse32.v v0, (%0)" : : "r"(base) : "memory");
}

int main() {
  const uint32_t cid = snrt_cluster_core_idx();
  const uint32_t cores = snrt_cluster_core_num();
  const uint32_t scalar_active = (cid == SCALAR_CORE);
  const uint32_t vector_active = (cid == VECTOR_CORE);

  if (cid == 0) {
    l1d_init(0);
    for (uint32_t i = 0; i < TOTAL_BYTES; i++) {
      mix_buf[i] = (uint8_t)(0xA0u ^ (uint8_t)i);
    }
    for (uint32_t i = 0; i < MAX_CORES; i++) {
      core_errors[i] = 0;
    }
  }
  snrt_cluster_hw_barrier();

  uint32_t errs = 0;
  if (scalar_active) {
    uint8_t *base = &mix_buf[SCALAR_CORE * REGION_BYTES];
    for (uint32_t it = 0; it < ITERS; it++) {
      const uint32_t part_ofst = (it * PART_BYTES) % (REGION_BYTES - PART_BYTES);
      volatile uint32_t *word_p = (volatile uint32_t *)(base + part_ofst + 12);
      const uint32_t scalar_exp = (cid << 24) ^ (it * 0x10201u);
      *word_p = scalar_exp;
      if (*word_p != scalar_exp) errs++;
    }
    core_errors[cid] = errs;
  } else if (vector_active) {
    uint8_t *base = &mix_buf[VECTOR_CORE * REGION_BYTES];
    for (uint32_t it = 0; it < ITERS; it++) {
      const uint32_t part_ofst = (it * PART_BYTES) % (REGION_BYTES - PART_BYTES);
      vec_store_u32((uint32_t *)(base + part_ofst));
      for (uint32_t j = 0; j < VEC_LEN; j++) {
        volatile uint32_t *wp = (volatile uint32_t *)(base + part_ofst + j * 4U);
        if (*wp != vec_vals[j]) errs++;
      }
    }
    core_errors[cid] = errs;
  }

  snrt_cluster_hw_barrier();
  if (cid == 0) {
    uint32_t total = 0;
    const uint32_t used = (cores > MAX_CORES) ? MAX_CORES : cores;
    for (uint32_t i = 0; i < used; i++) total += core_errors[i];
    if (total == 0) {
      printf("[PASS] cache-mix-smoke: mixed scalar/vector access OK\n");
    } else {
      printf("[FAIL] cache-mix-smoke: %u mismatches\n", total);
    }
    l1d_flush();
    return (int)total;
  }
  return 0;
}
