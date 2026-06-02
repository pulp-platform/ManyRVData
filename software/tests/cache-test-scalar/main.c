// Copyright 2025 ETH Zurich and University of Bologna.
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
//
// Author: Zexin Fu <zexifu@iis.ee.ethz.ch>

#include <l1cache.h>
#include <snrt.h>
#include <stdint.h>
#include "printf.h"

#ifndef CACHE_TEST_ENABLE_BASIC
#define CACHE_TEST_ENABLE_BASIC 1
#endif

#ifndef CACHE_TEST_ENABLE_STRESS
#define CACHE_TEST_ENABLE_STRESS 1
#endif

#define CACHE_LINE_BYTES (512 / 8)
#define PART_BYTES 16U
#define WORDS_PER_LINE (CACHE_LINE_BYTES / sizeof(uint32_t))
#define PART_WORDS (PART_BYTES / sizeof(uint32_t))
#define MAX_CORES 32U

#define BASIC_LINES 256U
#define BASIC_WORDS (BASIC_LINES * WORDS_PER_LINE)
#define BASIC_PARTS_PER_LINE (WORDS_PER_LINE / PART_WORDS)
#define BASIC_SEED 0x13579BDu

#define STRESS_WORDS_PER_CORE 8192U
#define STRESS_BLOCKS_PER_CORE (STRESS_WORDS_PER_CORE / PART_WORDS)
#define STRESS_PASSES 4U

static uint32_t basic_buf[BASIC_WORDS]
    __attribute__((section(".dram")))
    __attribute__((aligned(CACHE_LINE_BYTES)));

static uint32_t stress_buf[MAX_CORES * STRESS_WORDS_PER_CORE]
    __attribute__((section(".dram")))
    __attribute__((aligned(CACHE_LINE_BYTES)));

static uint32_t basic_errors[MAX_CORES] __attribute__((section(".data")));
static uint32_t stress_errors[MAX_CORES] __attribute__((section(".data")));

static inline uint32_t basic_base_pattern(uint32_t line, uint32_t word) {
  return BASIC_SEED ^ (line * 0x9E3779B1u) ^ (word * 0x85EBCA6Bu);
}

static inline uint32_t basic_offset_pattern(uint32_t line, uint32_t word) {
  return 0xA5A50000u ^ (line * 0x27D4EB2Du) ^ word;
}

static inline uint32_t stress_pattern(uint32_t pass, uint32_t idx,
                                      uint32_t cid) {
  return 0xA5000000u ^ (cid << 16) ^ (pass << 8) ^ idx;
}

static uint32_t run_basic_test(void) {
  const uint32_t cid = snrt_cluster_core_idx();
  const uint32_t num_cores = snrt_cluster_core_num();

  snrt_cluster_hw_barrier();

  if (cid == 0) {
    for (uint32_t line = 0; line < BASIC_LINES; line++) {
      const uint32_t base = line * WORDS_PER_LINE;
      for (uint32_t part = 0; part < WORDS_PER_LINE; part += PART_WORDS) {
        for (uint32_t w = 0; w < PART_WORDS; w++) {
          basic_buf[base + part + w] =
              basic_base_pattern(line, part + w);
        }
      }
    }
  }
  snrt_cluster_hw_barrier();

  const uint32_t lines_per_core = (BASIC_LINES + num_cores - 1U) / num_cores;
  const uint32_t start_line = cid * lines_per_core;
  const uint32_t end_line =
      (start_line + lines_per_core > BASIC_LINES)
          ? BASIC_LINES
          : (start_line + lines_per_core);

  uint32_t errors = 0;
  for (uint32_t line = start_line; line < end_line; line++) {
    const uint32_t base = line * WORDS_PER_LINE;
    for (uint32_t part = 0; part < WORDS_PER_LINE; part += PART_WORDS) {
      for (uint32_t w = 0; w < PART_WORDS; w++) {
        const uint32_t idx = part + w;
        const uint32_t got = basic_buf[base + idx];
        const uint32_t exp = basic_base_pattern(line, idx);
        if (got != exp) {
          errors++;
        }
      }
    }
  }
  if (cid < MAX_CORES) {
    basic_errors[cid] = errors;
  }

  snrt_cluster_hw_barrier();

  if (cid == 0) {
    for (uint32_t line = 0; line < BASIC_LINES; line++) {
      const uint32_t base = line * WORDS_PER_LINE;
      const uint32_t part_idx = (line * 5u + 1u) % BASIC_PARTS_PER_LINE;
      const uint32_t offset = part_idx * PART_WORDS;
      for (uint32_t w = 0; w < PART_WORDS; w++) {
        basic_buf[base + offset + w] =
            basic_offset_pattern(line, offset + w);
      }
    }
  }
  snrt_cluster_hw_barrier();

  errors = 0;
  for (uint32_t line = start_line; line < end_line; line++) {
    const uint32_t base = line * WORDS_PER_LINE;
    const uint32_t part_idx = (line * 5u + 1u) % BASIC_PARTS_PER_LINE;
    const uint32_t offset = part_idx * PART_WORDS;
    for (uint32_t part = 0; part < WORDS_PER_LINE; part += PART_WORDS) {
      for (uint32_t w = 0; w < PART_WORDS; w++) {
        const uint32_t idx = part + w;
        const uint32_t exp =
            (idx >= offset && idx < offset + PART_WORDS)
                ? basic_offset_pattern(line, idx)
                : basic_base_pattern(line, idx);
        const uint32_t got = basic_buf[base + idx];
        if (got != exp) {
          errors++;
        }
      }
    }
  }
  if (cid < MAX_CORES) {
    basic_errors[cid] += errors;
  }

  snrt_cluster_hw_barrier();
  if (cid == 0) {
    l1d_flush();
  }
  snrt_cluster_hw_barrier();

  uint32_t result = 0;
  if (cid == 0) {
    uint32_t total_errors = 0;
    uint32_t used_cores = (num_cores > MAX_CORES) ? MAX_CORES : num_cores;
    for (uint32_t i = 0; i < used_cores; i++) {
      total_errors += basic_errors[i];
    }
    if (num_cores > MAX_CORES) {
      printf("[WARN] cache-basic: only first %u cores checked.\n", used_cores);
    }
    if (total_errors == 0) {
      printf("[PASS] cache-basic: data integrity OK.\n");
    } else {
      printf("[FAIL] cache-basic: %u mismatches.\n", total_errors);
    }
    result = total_errors;
  }

  snrt_cluster_hw_barrier();
  return (cid == 0) ? result : 0;
}

static uint32_t run_stress_test(void) {
  const uint32_t cid = snrt_cluster_core_idx();
  const uint32_t num_cores = snrt_cluster_core_num();

  snrt_cluster_hw_barrier();

  const uint32_t active = (cid < MAX_CORES);

  uint32_t *base = NULL;
  if (active) {
    base = &stress_buf[cid * STRESS_WORDS_PER_CORE];
    for (uint32_t block = 0; block < STRESS_BLOCKS_PER_CORE; block++) {
      const uint32_t base_idx = block * PART_WORDS;
      for (uint32_t w = 0; w < PART_WORDS; w++) {
        base[base_idx + w] =
            stress_pattern(0, base_idx + w, cid);
      }
    }

    for (uint32_t pass = 1; pass < STRESS_PASSES; pass++) {
      const uint32_t stride = (cid * 2U + 1U) + (pass * 4U);
      for (uint32_t iter = 0; iter < STRESS_BLOCKS_PER_CORE; iter++) {
        const uint32_t block = (iter * stride) % STRESS_BLOCKS_PER_CORE;
        const uint32_t base_idx = block * PART_WORDS;
        for (uint32_t w = 0; w < PART_WORDS; w++) {
          base[base_idx + w] =
              stress_pattern(pass, base_idx + w, cid);
        }
      }
    }
  }

  snrt_cluster_hw_barrier();

  uint32_t errors = 0;
  if (active) {
    for (uint32_t block = 0; block < STRESS_BLOCKS_PER_CORE; block++) {
      const uint32_t base_idx = block * PART_WORDS;
      for (uint32_t w = 0; w < PART_WORDS; w++) {
        const uint32_t idx = base_idx + w;
        const uint32_t got = base[idx];
        const uint32_t exp = stress_pattern(STRESS_PASSES - 1U, idx, cid);
        if (got != exp) {
          errors++;
        }
      }
    }
    stress_errors[cid] = errors;
  }

  snrt_cluster_hw_barrier();
  if (cid == 0) {
    l1d_flush();
  }
  snrt_cluster_hw_barrier();

  uint32_t result = 0;
  if (cid == 0) {
    uint32_t total_errors = 0;
    uint32_t used_cores = (num_cores > MAX_CORES) ? MAX_CORES : num_cores;
    for (uint32_t i = 0; i < used_cores; i++) {
      total_errors += stress_errors[i];
    }
    if (num_cores > MAX_CORES) {
      printf("[WARN] cache-stress: only first %u cores checked.\n", used_cores);
    }
    if (total_errors == 0) {
      printf("[PASS] cache-stress: data integrity OK.\n");
    } else {
      printf("[FAIL] cache-stress: %u mismatches.\n", total_errors);
    }
    result = total_errors;
  }

  snrt_cluster_hw_barrier();
  return (cid == 0) ? result : 0;
}

int main() {
  const uint32_t cid = snrt_cluster_core_idx();
  uint32_t failures = 0;

  if (cid == 0) {
    l1d_init(0);
  }
  snrt_cluster_hw_barrier();

#if CACHE_TEST_ENABLE_BASIC
  if (cid == 0) {
    printf("[RUN ] cache-basic\n");
  }
  uint32_t basic_errors = run_basic_test();
  if (cid == 0 && basic_errors != 0) {
    failures++;
  }
#endif

#if CACHE_TEST_ENABLE_STRESS
  if (cid == 0) {
    printf("[RUN ] cache-stress\n");
  }
  uint32_t stress_errors = run_stress_test();
  if (cid == 0 && stress_errors != 0) {
    failures++;
  }
#endif

  if (cid == 0) {
    if (failures == 0) {
      printf("[PASS] cache-tests: all enabled tests passed.\n");
    } else {
      printf("[FAIL] cache-tests: %u test group(s) failed.\n", failures);
    }
  }

  snrt_cluster_hw_barrier();
  return (cid == 0 && failures) ? 1 : 0;
}
