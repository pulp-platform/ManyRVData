// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0

#include <l1cache.h>
#include <snrt.h>
#include <stdint.h>
#include "printf.h"

#define MAX_CORES 8U
#define LINE_BYTES 64U
#define WORD_BYTES 4U
#define WORDS_PER_LINE (LINE_BYTES / WORD_BYTES)
#define NUM_LINES 16U
#define TOTAL_WORDS (NUM_LINES * WORDS_PER_LINE)
#define L1LineWidth (512/8) // 512 bits

static uint32_t line_buf[TOTAL_WORDS] __attribute__((section(".dram")))
    __attribute__((aligned(LINE_BYTES)));
static uint32_t core_errors[MAX_CORES] __attribute__((section(".dram")))
    __attribute__((aligned(64)));

int main() {
  const uint32_t cid = snrt_cluster_core_idx();
  volatile uint32_t *buf = line_buf;
  uint32_t errs = 0;

  if (cid == 0) {
    l1d_flush();
    uint32_t offset = 31 - __builtin_clz(L1LineWidth);
    l1d_xbar_config(offset); // cacheline interleaving
  }
  snrt_cluster_hw_barrier();

  if (cid == 0) {
    for (uint32_t word = 0; word < TOTAL_WORDS; word++) {
      buf[word] = word;
    }

    for (uint32_t word = 0; word < TOTAL_WORDS; word++) {
      const uint32_t got = buf[word];
      const uint32_t exp = word;
      if (got != exp) {
        errs++;
      }
    }
  }

  if (cid < MAX_CORES) {
    core_errors[cid] = errs;
  }
  snrt_cluster_hw_barrier();

  if (cid == 0) {
    uint32_t total_err = 0;
    for (uint32_t i = 0; i < MAX_CORES; i++) {
      total_err += core_errors[i];
    }

    if (total_err == 0) {
      printf("[PASS] cache-line-rw-smoke: lines=%u words=%u\n", NUM_LINES, TOTAL_WORDS);
    } else {
      printf("[FAIL] cache-line-rw-smoke: errors=%u lines=%u words=%u\n",
             total_err, NUM_LINES, TOTAL_WORDS);
    }

    l1d_flush();
    return (int)total_err;
  }

  return 0;
}
