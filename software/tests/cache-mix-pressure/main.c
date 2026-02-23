// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0

#include <l1cache.h>
#include <snrt.h>
#include <stdint.h>
#include "printf.h"

#define MAX_CORES 8U
#define REGION_BYTES 4096U
#define TOTAL_BYTES (MAX_CORES * REGION_BYTES)
#define VEC_LEN 16U
#define ITERS 4000U
#define SCALAR_CORE 0U
#define VECTOR_CORE 1U

static uint8_t pressure_buf[TOTAL_BYTES] __attribute__((section(".dram")))
    __attribute__((aligned(64)));
static uint32_t vec_vals[VEC_LEN] __attribute__((section(".data")));
static uint32_t core_sig[MAX_CORES] __attribute__((section(".data")));
static uint32_t core_err[MAX_CORES] __attribute__((section(".data")));

static inline void vec_store_u32(uint32_t *base) {
  uint32_t vl = 0;
  asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(VEC_LEN));
  asm volatile("vle32.v v0, (%0)" : : "r"(vec_vals) : "memory");
  asm volatile("vse32.v v0, (%0)" : : "r"(base) : "memory");
}

static inline uint32_t scalar_mix(uint32_t x) {
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  return x;
}

int main() {
  const uint32_t cid = snrt_cluster_core_idx();
  const uint32_t cores = snrt_cluster_core_num();
  const uint32_t scalar_active = (cid == SCALAR_CORE);
  const uint32_t vector_active = (cid == VECTOR_CORE);

  if (cid == 0) {
    l1d_init(0);
    for (uint32_t i = 0; i < VEC_LEN; i++) {
      vec_vals[i] = 0xABCD0000u + i;
    }
    for (uint32_t i = 0; i < TOTAL_BYTES; i++) {
      pressure_buf[i] = (uint8_t)(i ^ 0x5Au);
    }
    for (uint32_t i = 0; i < MAX_CORES; i++) {
      core_sig[i] = 0;
      core_err[i] = 0;
    }
  }
  snrt_cluster_hw_barrier();

  uint32_t sig = 0x13579BDFu ^ cid;
  uint32_t errs = 0;
  if (scalar_active) {
    uint8_t *base = &pressure_buf[SCALAR_CORE * REGION_BYTES];
    for (uint32_t it = 0; it < ITERS; it++) {
      const uint32_t win = (it * 64u + cid * 7u) % (REGION_BYTES - 64u);
      volatile uint32_t *sw = (volatile uint32_t *)(base + win + 32u);
      const uint32_t w = scalar_mix(sig ^ it);
      *sw = w;
      sig ^= *sw;
    }
    core_sig[cid] = sig;
    core_err[cid] = errs;
  } else if (vector_active) {
    uint8_t *base = &pressure_buf[VECTOR_CORE * REGION_BYTES];
    for (uint32_t it = 0; it < ITERS; it++) {
      const uint32_t win = (it * 64u + cid * 7u) % (REGION_BYTES - 64u);
      vec_store_u32((uint32_t *)(base + win));
      for (uint32_t j = 0; j < VEC_LEN; j++) {
        volatile uint32_t *wp = (volatile uint32_t *)(base + win + j * 4U);
        const uint32_t got = *wp;
        sig = scalar_mix(sig ^ got ^ (j << 8));
        if (got != vec_vals[j]) errs++;
      }
    }
    core_sig[cid] = sig;
    core_err[cid] = errs;
  }

  snrt_cluster_hw_barrier();
  if (cid == 0) {
    uint32_t total_err = 0;
    uint32_t fold_sig = 0;
    const uint32_t used = (cores > MAX_CORES) ? MAX_CORES : cores;
    for (uint32_t i = 0; i < used; i++) {
      total_err += core_err[i];
      fold_sig ^= core_sig[i];
    }
    if (total_err == 0) {
      printf("[PASS] cache-mix-pressure: done, signature=0x%08x\n", fold_sig);
    } else {
      printf("[FAIL] cache-mix-pressure: errors=%u signature=0x%08x\n", total_err, fold_sig);
    }
    l1d_flush();
    return (int)total_err;
  }

  return 0;
}
