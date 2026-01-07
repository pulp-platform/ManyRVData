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

// Author: Zexin Fu     <zexifu@iis.ee.ethz.ch>

#include <snrt.h>
#include <stdio.h>
#include <stddef.h>
#include <stdint.h>
#include <l1cache.h>
#include "printf.h"
#ifdef DATAHEADER
#include DATAHEADER
#endif

#define L1LineWidth (512 / 8) // 512 bits
#define BUF_LINES 2
#define BUF_BYTES (L1LineWidth * BUF_LINES)

static uint8_t test_buf[BUF_BYTES] __attribute__((aligned(L1LineWidth)))
    __attribute__((section(".data")));

static inline void store_b(void *addr, uint8_t value) {
  asm volatile("sb %0, 0(%1)" :: "r"(value), "r"(addr) : "memory");
}

static inline void store_h(void *addr, uint16_t value) {
  asm volatile("sh %0, 0(%1)" :: "r"(value), "r"(addr) : "memory");
}

static inline void store_w(void *addr, uint32_t value) {
  asm volatile("sw %0, 0(%1)" :: "r"(value), "r"(addr) : "memory");
}


static inline int32_t load_b(const void *addr) {
  int32_t out;
  asm volatile("lb %0, 0(%1)" : "=r"(out) : "r"(addr) : "memory");
  return out;
}

static inline int32_t load_h(const void *addr) {
  int32_t out;
  asm volatile("lh %0, 0(%1)" : "=r"(out) : "r"(addr) : "memory");
  return out;
}

static inline int32_t load_w(const void *addr) {
  int32_t out;
  asm volatile("lw %0, 0(%1)" : "=r"(out) : "r"(addr) : "memory");
  return out;
}

static void init_pattern(uint8_t *buf, size_t bytes) {
  size_t words = bytes / 4U;
  for (size_t w = 0; w < words; w++) {
    size_t base = w * 4U;
    uint32_t b0 = (uint8_t)(0xA5U ^ (uint8_t)(base + 0U));
    uint32_t b1 = (uint8_t)(0xA5U ^ (uint8_t)(base + 1U));
    uint32_t b2 = (uint8_t)(0xA5U ^ (uint8_t)(base + 2U));
    uint32_t b3 = (uint8_t)(0xA5U ^ (uint8_t)(base + 3U));
    uint32_t word = (b0) | (b1 << 8U) | (b2 << 16U) | (b3 << 24U);
    store_w(buf + base, word);
  }

  for (size_t i = words * 4U; i < bytes; i++) {
    buf[i] = (uint8_t)(0xA5U ^ (uint8_t)i);
  }
}

static int check_store_and_load(const char *name, uint8_t *base,
                                uint32_t offset, uint32_t size,
                                uint32_t value) {
  int errors = 0;

  if (((uintptr_t)base & 0x3U) != 0U) {
    printf("[FAIL] %s: base misaligned 0x%llx\n", name,
           (unsigned long long)(uintptr_t)base);
    return 1;
  }

  if ((offset + size) > 4U) {
    printf("[FAIL] %s: offset+size out of range\n", name);
    return 1;
  }

  uint32_t orig = (uint32_t)load_w(base);

  switch (size) {
    case 1:
      store_b(base + offset, (uint8_t)value);
      break;
    case 2:
      store_h(base + offset, (uint16_t)value);
      break;
    case 4:
      store_w(base + offset, (uint32_t)value);
      break;
    default:
      printf("[FAIL] %s: invalid size %u\n", name, size);
      return 1;
  }

  uint32_t after = (uint32_t)load_w(base);
  uint32_t expected = orig;

  uint32_t mask = (size == 1) ? 0xFFU
                   : (size == 2) ? 0xFFFFU
                                 : 0xFFFFFFFFU;
  uint32_t shift = offset * 8U;
  expected = (orig & ~(mask << shift)) | ((value & mask) << shift);

  int store_ok = (after == expected);
  if (!store_ok) {
    printf("[FAIL] %s: store before 0x%08x expected 0x%08x got 0x%08x\n", name,
           (unsigned int)orig, (unsigned int)expected, (unsigned int)after);
    errors++;
  }

  int32_t load_got = 0;
  int32_t load_exp = 0;
  const char *load_name = "l?";
  int load_ok = 0;

  if (size == 1) {
    load_name = "lb";
    load_got = load_b(base + offset);
    load_exp = (int8_t)value;
  } else if (size == 2) {
    load_name = "lh";
    load_got = load_h(base + offset);
    load_exp = (int16_t)value;
  } else if (size == 4) {
    load_name = "lw";
    load_got = load_w(base + offset);
    load_exp = (int32_t)value;
  }

  load_ok = (load_got == load_exp);
  if (!load_ok) {
    printf("[FAIL] %s: %s before 0x%08x expected 0x%08x got 0x%08x\n", name,
           load_name, (unsigned int)orig, (unsigned int)load_exp,
           (unsigned int)load_got);
    errors++;
  }

  if (store_ok) {
    printf("[PASS] %s: store before 0x%08x expected 0x%08x got 0x%08x\n", name,
           (unsigned int)orig, (unsigned int)expected, (unsigned int)after);
  }
  if (load_ok) {
    printf("[PASS] %s: %s before 0x%08x expected 0x%08x got 0x%08x\n", name,
           load_name, (unsigned int)orig, (unsigned int)load_exp,
           (unsigned int)load_got);
  }
  return errors;
}

int main(void) {
  const unsigned int core_id = snrt_cluster_core_idx();

  if (core_id == 0) {
    l1d_init(0);
    uint32_t offset = 31U - __builtin_clz((unsigned int)L1LineWidth);
    l1d_xbar_config(offset);
  }

  snrt_cluster_hw_barrier();

  int errors = 0;

  if (core_id == 0) {
    init_pattern(test_buf, BUF_BYTES);
    printf("original data (line order, high->low addr):\n");
    for (unsigned int line = 0; line < BUF_LINES; line++) {
      printf("line %u: ", line);
      for (unsigned int byte = 0; byte < L1LineWidth; byte++) {
        unsigned int idx = line * L1LineWidth + (L1LineWidth - 1U - byte);
        printf("%02x ", (unsigned int)test_buf[idx]);
      }
      printf("\n");
    }

    errors += check_store_and_load("sb/lb line0+1", test_buf, 1, 1, 0x80U);

    errors += check_store_and_load("sh/lh line0+4+2", test_buf + 4, 2, 2,
                                   0x8001U);

    errors += check_store_and_load("sw/lw line0+16+0", test_buf + 16, 0, 4,
                                   0x80000005U);

    errors += check_store_and_load("sb/lb line1+3", test_buf + L1LineWidth, 3,
                                   1, 0x7FU);

    if (errors == 0) {
      printf("Byte-enable test PASSED\n");
    } else {
      printf("Byte-enable test FAILED: %d errors\n", errors);
    }
  }

  snrt_cluster_hw_barrier();

  if (core_id == 0) {
    set_eoc();
  }

  return 0;
}
