// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0

// Flush of a private (folded) L1 partition. Core 0 writes FF_KIB KiB of a
// pattern with vector stores, all cores flush, then every core checks a
// slice from its own tile. With FF_KIB above the tile capacity, dirty lines
// are evicted during the writes as well as by the flush.
//
//   FF_FOLD: 0 tile, 1 group, 2 shared (no private partition)
//   FF_XBAR: l1d_xbar_config offset (0 keeps the default)

#include <l1cache.h>
#include <snrt.h>
#include <stdint.h>
#include "printf.h"

#ifndef FF_KIB
#define FF_KIB 512
#endif
#ifndef FF_FOLD
#define FF_FOLD 0
#endif
#ifndef FF_XBAR
#define FF_XBAR 6
#endif

#define FF_WORDS (FF_KIB * 1024 / 4)
#define FF_VL 64
#define FF_MAGIC 0x5a000000u
#define MAX_CORES 1024

static uint32_t buf[FF_WORDS] __attribute__((section(".dram"), aligned(64)));
static uint32_t ramp[FF_VL] __attribute__((section(".data"), aligned(64)));
static uint32_t errors[MAX_CORES] __attribute__((section(".data")));
static uint32_t first_bad[MAX_CORES] __attribute__((section(".data")));
static uint32_t first_val[MAX_CORES] __attribute__((section(".data")));

int main() {
  const uint32_t cid = snrt_cluster_vpu_idx();
  const uint32_t ncores = snrt_cluster_vpu_num();

  if (cid == 0)
    for (uint32_t i = 0; i < FF_VL; ++i)
      ramp[i] = i;
  snrt_cluster_hw_barrier();
  if (FF_XBAR)
    l1d_xbar_config(FF_XBAR);
  if (FF_FOLD != 2)
    l1d_part_folded(snrt_cluster_vpu_per_tile(),
                    FF_FOLD ? L1D_FOLD_GROUP : L1D_FOLD_TILE);

  if (cid == 0) {
    uint32_t vl;
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(FF_VL));
    asm volatile("vle32.v v0, (%0)" ::"r"(ramp));
    for (uint32_t p = 0; p < FF_WORDS; p += FF_VL) {
      asm volatile("vadd.vx v4, v0, %0" ::"r"(FF_MAGIC + p));
      asm volatile("vse32.v v4, (%0)" ::"r"(buf + p) : "memory");
    }
    snrt_fence_spatz();
    printf("cache-fold-flush: %u KiB, fold %d, xbar %d, written\n", FF_KIB,
           FF_FOLD, FF_XBAR);
  }

  l1d_cluster_flush();

  const uint32_t i0 = FF_WORDS / ncores * cid;
  const uint32_t i1 = FF_WORDS / ncores * (cid + 1);
  uint32_t err = 0, bad = 0, val = 0;
  for (uint32_t i = i0; i < i1; ++i) {
    uint32_t got = ((volatile uint32_t *)buf)[i];
    if (got != FF_MAGIC + i) {
      if (err == 0) {
        bad = i;
        val = got;
      }
      ++err;
    }
  }
  errors[cid] = err;
  first_bad[cid] = bad;
  first_val[cid] = val;
  // errors[] lives in each core's private partition until flushed
  l1d_cluster_flush();

  uint32_t total = 0;
  if (cid == 0) {
    for (uint32_t c = 0; c < ncores; ++c) {
      if (errors[c])
        printf("core %u: %u errors, first at 0x%08x = 0x%08x\n", c, errors[c],
               (uint32_t)(uintptr_t)(buf + first_bad[c]), first_val[c]);
      total += errors[c];
    }
    printf(total ? "[FAIL] %u errors\n" : "[PASS]\n", total);
  }
  snrt_cluster_hw_barrier();
  return total ? -1 : 0;
}
