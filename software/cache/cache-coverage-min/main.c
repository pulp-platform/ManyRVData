// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0
//
// cache-coverage-min: minimal repro for the phase-06 writeback-loss bug.
// Single core, no warm-up.  Just hammers the same cache set with 8
// stride-64KiB addresses (all hashing to depth=0, ctrl=0) so the VIP
// trace can capture the exact COMMIT / UPREQ sequence without burying
// it in 10s of µs of unrelated traffic.

#include <l1cache.h>
#include <snrt.h>
#include <stdint.h>
#include "printf.h"

#define CONFLICT_STRIDE_LOG2  16U
#define CONFLICT_STRIDE       (1U << CONFLICT_STRIDE_LOG2)
#define CONFLICT_LINES        8U
#define CONFLICT_BYTES        (CONFLICT_LINES * CONFLICT_STRIDE)

static uint8_t conflict_buf[CONFLICT_BYTES]
    __attribute__((section(".dram"))) __attribute__((aligned(CONFLICT_STRIDE)));

int main() {
  const uint32_t cid = snrt_cluster_core_idx();
  if (cid == 0) {

    // Minimal cache setup: line-interleave (offset=6).
    l1d_flush();
    l1d_wait();
    l1d_xbar_config(31 - __builtin_clz(64));  // offset = 6
    l1d_init(0);
    l1d_wait();
    printf("[cache-coverage-min] setup done.  conflict_buf@0x%x\n",
          (uint32_t)conflict_buf);

    volatile uint32_t *p[CONFLICT_LINES];
    for (uint32_t k = 0; k < CONFLICT_LINES; ++k)
      p[k] = (volatile uint32_t *)(conflict_buf + (k * CONFLICT_STRIDE));

    // -- Round 1: write k=0..7, then read all back.
    printf("[cache-coverage-min] WRITE round 1\n");
    for (uint32_t k = 0; k < CONFLICT_LINES; ++k) {
      start_kernel();
      *(p[k]) = 0xC0FFEE00u + k;
      stop_kernel();
    }

    printf("[cache-coverage-min] READ round 1\n");
    uint32_t errs = 0;
    for (uint32_t k = 0; k < CONFLICT_LINES; ++k) {
      start_kernel();
      uint32_t got = *(p[k]);
      uint32_t exp = 0xC0FFEE00u + k;
      stop_kernel();
      if (got != exp) {
        printf("  [ERR] k=%u addr=0x%x exp=0x%x got=0x%x\n",
              k, (uint32_t)p[k], exp, got);
        ++errs;
      } else {
        printf("  [OK ] k=%u addr=0x%x got=0x%x\n", k, (uint32_t)p[k], got);
      }
    }
    printf("[cache-coverage-min] round1 errors=%u\n", errs);
    printf("[cache-coverage-min] %s\n", errs ? "FAIL" : "PASS");
  }
  snrt_cluster_hw_barrier();
  return 0;
}
