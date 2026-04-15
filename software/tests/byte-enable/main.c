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
#include <benchmark.h>
#include "printf.h"
#ifdef DATAHEADER
#include DATAHEADER
#endif

#define L1LineWidth (512 / 8) // 512 bits
#define BUF_LINES 2
#define BUF_BYTES (L1LineWidth * BUF_LINES)

#ifndef ENABLE_SCALAR_TESTS
#define ENABLE_SCALAR_TESTS 1
#endif

#ifndef ENABLE_VECTOR_TESTS
#define ENABLE_VECTOR_TESTS 1
#endif

#define VEC_E8_LEN 16U
#define VEC_E16_LEN 8U
#define VEC_BUF_BYTES 256U

static uint8_t test_buf[BUF_BYTES] __attribute__((aligned(L1LineWidth)))
    __attribute__((section(".data")));

static uint8_t vec_buf[VEC_BUF_BYTES] __attribute__((aligned(64)))
    __attribute__((section(".data")));
static uint8_t vec_data8[VEC_E8_LEN] __attribute__((aligned(4)))
    __attribute__((section(".data")));
static uint16_t vec_data16[VEC_E16_LEN] __attribute__((aligned(4)))
    __attribute__((section(".data")));
static uint8_t vec_idx8[VEC_E8_LEN] __attribute__((aligned(4)))
    __attribute__((section(".data")));
static uint16_t vec_idx16[VEC_E16_LEN] __attribute__((aligned(4)))
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

static uint8_t pattern_byte(size_t idx) {
  return (uint8_t)(0xA5U ^ (uint8_t)idx);
}

static void init_pattern(uint8_t *buf, size_t bytes) {
  size_t words = bytes / 4U;
  for (size_t w = 0; w < words; w++) {
    size_t base = w * 4U;
    uint32_t b0 = pattern_byte(base + 0U);
    uint32_t b1 = pattern_byte(base + 1U);
    uint32_t b2 = pattern_byte(base + 2U);
    uint32_t b3 = pattern_byte(base + 3U);
    uint32_t word = (b0) | (b1 << 8U) | (b2 << 16U) | (b3 << 24U);
    store_w(buf + base, word);
  }

  for (size_t i = words * 4U; i < bytes; i++) {
    buf[i] = pattern_byte(i);
  }
}

static void init_vec_data(void) {
  for (unsigned int i = 0; i < VEC_E8_LEN; i++) {
    vec_data8[i] = (uint8_t)(0x10U + (i * 3U));
    vec_idx8[i] = (uint8_t)(i * 3U);
  }
  for (unsigned int i = 0; i < VEC_E16_LEN; i++) {
    vec_data16[i] = (uint16_t)(0x2000U + (i * 5U));
    vec_idx16[i] = (uint16_t)(i * 4U);
  }
}

static unsigned long long cycle_to_ns(size_t cycle) {
  return (unsigned long long)cycle * 2ULL + 10ULL;
}

static void trace_inst(const char *name, const char *inst, const void *addr,
                        size_t cycle) {
  unsigned long long ns = cycle_to_ns(cycle);
  printf("[TRACE] %s: %s @ 0x%08x cycle %u ns %llu\n", name, inst,
         (unsigned int)(uintptr_t)addr, (unsigned int)cycle, ns);
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

  const uint8_t *addr = base + offset;
  const char *store_name = "s?";
  size_t store_cycle = 0;

  switch (size) {
    case 1:
      store_name = "sb";
      store_cycle = benchmark_get_cycle();
      store_b((void *)addr, (uint8_t)value);
      break;
    case 2:
      store_name = "sh";
      store_cycle = benchmark_get_cycle();
      store_h((void *)addr, (uint16_t)value);
      break;
    case 4:
      store_name = "sw";
      store_cycle = benchmark_get_cycle();
      store_w((void *)addr, (uint32_t)value);
      break;
    default:
      printf("[FAIL] %s: invalid size %u\n", name, size);
      return 1;
  }

  trace_inst(name, store_name, addr, store_cycle);

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
  size_t load_cycle = 0;
  int load_ok = 0;

  if (size == 1) {
    load_name = "lb";
    load_cycle = benchmark_get_cycle();
    load_got = load_b(addr);
    load_exp = (int8_t)value;
  } else if (size == 2) {
    load_name = "lh";
    load_cycle = benchmark_get_cycle();
    load_got = load_h(addr);
    load_exp = (int16_t)value;
  } else if (size == 4) {
    load_name = "lw";
    load_cycle = benchmark_get_cycle();
    load_got = load_w(addr);
    load_exp = (int32_t)value;
  }

  trace_inst(name, load_name, addr, load_cycle);

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

static int verify_vec_e8(const char *name, uint8_t *buf, size_t base_index,
                         const uint8_t *vals, const uint16_t *offsets,
                         size_t count, size_t region_bytes) {
  int errors = 0;

  for (size_t pos = 0; pos < region_bytes; pos++) {
    uint8_t exp = pattern_byte(base_index + pos);
    for (size_t i = 0; i < count; i++) {
      if (offsets[i] == pos) {
        exp = vals[i];
        break;
      }
    }
    uint8_t got = buf[base_index + pos];
    if (got != exp) {
      printf("[FAIL] %s: byte+%u expected 0x%02x got 0x%02x\n", name,
             (unsigned int)pos, (unsigned int)exp, (unsigned int)got);
      errors++;
    }
  }

  if (errors == 0) {
    printf("[PASS] %s: vector store verify\n", name);
  }

  return errors;
}

static int verify_vec_e16(const char *name, uint8_t *buf, size_t base_index,
                          const uint16_t *vals, const uint16_t *offsets,
                          size_t count, size_t region_bytes) {
  int errors = 0;

  for (size_t pos = 0; pos < region_bytes; pos++) {
    uint8_t exp = pattern_byte(base_index + pos);
    for (size_t i = 0; i < count; i++) {
      if (offsets[i] == pos) {
        exp = (uint8_t)(vals[i] & 0xFFU);
        break;
      } else if (offsets[i] + 1U == pos) {
        exp = (uint8_t)((vals[i] >> 8U) & 0xFFU);
        break;
      }
    }
    uint8_t got = buf[base_index + pos];
    if (got != exp) {
      printf("[FAIL] %s: byte+%u expected 0x%02x got 0x%02x\n", name,
             (unsigned int)pos, (unsigned int)exp, (unsigned int)got);
      errors++;
    }
  }

  if (errors == 0) {
    printf("[PASS] %s: vector store verify\n", name);
  }

  return errors;
}

static int run_vector_tests(void) {
  int errors = 0;
  uint32_t avl;
  uint32_t vlen;
  uint16_t offsets16[VEC_E16_LEN];
  uint16_t offsets8[VEC_E8_LEN];

  init_pattern(vec_buf, VEC_BUF_BYTES);
  init_vec_data();

  const uint32_t stride_b = 2U;
  const uint32_t stride_h = 4U;

  const size_t base_e8_unit = 0U;
  const size_t base_e8_stride = 64U;
  const size_t base_e8_index = 128U;
  const size_t base_e16_unit = 160U;
  const size_t base_e16_stride = 192U;
  const size_t base_e16_index = 224U;

  avl = VEC_E8_LEN;
  asm volatile("vsetvli %0, %1, e8, m1, ta, ma" : "=r"(vlen) : "r"(avl));
  asm volatile("vle8.v v0, (%0)" :: "r"(vec_data8) : "memory");
  size_t cyc = benchmark_get_cycle();
  asm volatile("vse8.v v0, (%0)" :: "r"(vec_buf + base_e8_unit) : "memory");
  trace_inst("vec e8 unit", "vse8.v", vec_buf + base_e8_unit, cyc);
  for (unsigned int i = 0; i < VEC_E8_LEN; i++)
    offsets8[i] = i;
  errors += verify_vec_e8("vec e8 unit", vec_buf, base_e8_unit, vec_data8,
                          offsets8, VEC_E8_LEN, VEC_E8_LEN);

  avl = VEC_E8_LEN;
  asm volatile("vsetvli %0, %1, e8, m1, ta, ma" : "=r"(vlen) : "r"(avl));
  asm volatile("vle8.v v0, (%0)" :: "r"(vec_data8) : "memory");
  cyc = benchmark_get_cycle();
  asm volatile("vsse8.v v0, (%0), %1" :: "r"(vec_buf + base_e8_stride),
               "r"(stride_b) : "memory");
  trace_inst("vec e8 strided", "vsse8.v", vec_buf + base_e8_stride, cyc);
  for (unsigned int i = 0; i < VEC_E8_LEN; i++)
    offsets8[i] = i * stride_b;
  errors += verify_vec_e8("vec e8 strided", vec_buf, base_e8_stride, vec_data8,
                          offsets8, VEC_E8_LEN,
                          (VEC_E8_LEN - 1U) * stride_b + 1U);

  avl = VEC_E8_LEN;
  asm volatile("vsetvli %0, %1, e8, m1, ta, ma" : "=r"(vlen) : "r"(avl));
  asm volatile("vle8.v v0, (%0)" :: "r"(vec_data8) : "memory");
  asm volatile("vle8.v v1, (%0)" :: "r"(vec_idx8) : "memory");
  cyc = benchmark_get_cycle();
  asm volatile("vsuxei8.v v0, (%0), v1" :: "r"(vec_buf + base_e8_index)
               : "memory");
  trace_inst("vec e8 indexed", "vsuxei8.v", vec_buf + base_e8_index, cyc);
  for (unsigned int i = 0; i < VEC_E8_LEN; i++)
    offsets8[i] = vec_idx8[i];
  errors += verify_vec_e8("vec e8 indexed", vec_buf, base_e8_index, vec_data8,
                          offsets8, VEC_E8_LEN,
                          offsets8[VEC_E8_LEN - 1U] + 1U);

  avl = VEC_E16_LEN;
  asm volatile("vsetvli %0, %1, e16, m1, ta, ma" : "=r"(vlen) : "r"(avl));
  asm volatile("vle16.v v0, (%0)" :: "r"(vec_data16) : "memory");
  cyc = benchmark_get_cycle();
  asm volatile("vse16.v v0, (%0)" :: "r"(vec_buf + base_e16_unit) : "memory");
  trace_inst("vec e16 unit", "vse16.v", vec_buf + base_e16_unit, cyc);
  for (unsigned int i = 0; i < VEC_E16_LEN; i++)
    offsets16[i] = i * 2U;
  errors += verify_vec_e16("vec e16 unit", vec_buf, base_e16_unit, vec_data16,
                           offsets16, VEC_E16_LEN, VEC_E16_LEN * 2U);

  avl = VEC_E16_LEN;
  asm volatile("vsetvli %0, %1, e16, m1, ta, ma" : "=r"(vlen) : "r"(avl));
  asm volatile("vle16.v v0, (%0)" :: "r"(vec_data16) : "memory");
  cyc = benchmark_get_cycle();
  asm volatile("vsse16.v v0, (%0), %1" :: "r"(vec_buf + base_e16_stride),
               "r"(stride_h) : "memory");
  trace_inst("vec e16 strided", "vsse16.v", vec_buf + base_e16_stride, cyc);
  for (unsigned int i = 0; i < VEC_E16_LEN; i++)
    offsets16[i] = i * stride_h;
  errors += verify_vec_e16("vec e16 strided", vec_buf, base_e16_stride,
                           vec_data16, offsets16, VEC_E16_LEN,
                           (VEC_E16_LEN - 1U) * stride_h + 2U);

  avl = VEC_E16_LEN;
  asm volatile("vsetvli %0, %1, e16, m1, ta, ma" : "=r"(vlen) : "r"(avl));
  asm volatile("vle16.v v0, (%0)" :: "r"(vec_data16) : "memory");
  asm volatile("vle16.v v1, (%0)" :: "r"(vec_idx16) : "memory");
  cyc = benchmark_get_cycle();
  asm volatile("vsuxei16.v v0, (%0), v1" :: "r"(vec_buf + base_e16_index)
               : "memory");
  trace_inst("vec e16 indexed", "vsuxei16.v", vec_buf + base_e16_index, cyc);
  for (unsigned int i = 0; i < VEC_E16_LEN; i++)
    offsets16[i] = vec_idx16[i];
  errors += verify_vec_e16("vec e16 indexed", vec_buf, base_e16_index,
                           vec_data16, offsets16, VEC_E16_LEN,
                           offsets16[VEC_E16_LEN - 1U] + 2U);

  (void)vlen;
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

#if ENABLE_SCALAR_TESTS
    errors += check_store_and_load("sb/lb line0+1", test_buf, 1, 1, 0x80U);

    errors += check_store_and_load("sh/lh line0+4+2", test_buf + 4, 2, 2,
                                   0x8001U);

    errors += check_store_and_load("sw/lw line0+16+0", test_buf + 16, 0, 4,
                                   0x80000005U);

    errors += check_store_and_load("sb/lb line1+3", test_buf + L1LineWidth, 3,
                                   1, 0x7FU);
#endif

#if ENABLE_VECTOR_TESTS
    errors += run_vector_tests();
#endif

    if (errors == 0) {
      printf("Byte-enable test PASSED\n");
    } else {
      printf("Byte-enable test FAILED: %d errors\n", errors);
    }
  }

  snrt_cluster_hw_barrier();

  return 0;
}
