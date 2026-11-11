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

// VRF layouts of a dual-thread Spatz, one thread at a time. The two harts of Core Complex 0 share
// one Spatz. While the Spatz lock is free (dual mode) each hart's vector registers live in its own
// half of the VRF and are half as long; while a hart holds the lock it has the full VRF.
//   1. dual mode, hart 0 (thread 0)
//   2. dual mode, hart 1 (thread 1)
//   3. isolation: both harts fill v8-v15, each must read back its own data
//   4. lock mode, hart 0
// Steps 1, 2 and 4 check vlenb and vsetvli's VLMAX, then run unit-stride (LMUL 1-8), strided and
// indexed accesses, slides and a reduction over full-length registers against scalar results.
// Without the dual-thread Spatz (SNRT_SPATZ_DUAL_THREAD=0) dual mode keeps the full VRF and step 3
// is skipped.

#include <snrt.h>
#include <stdint.h>
#include <printf.h>
#include <spatz_lock.h>

#ifndef SNRT_SPATZ_DUAL_THREAD
#define SNRT_SPATZ_DUAL_THREAD 0
#endif

// Largest group: LMUL 8 at the full VLEN of 512 bit is 128 words
#define BUF_WORDS 256u

static uint32_t src[BUF_WORDS] __attribute__((section(".data")));
static uint32_t src_b[BUF_WORDS] __attribute__((section(".data")));
static uint32_t dst[BUF_WORDS] __attribute__((section(".data")));
static uint32_t idx[BUF_WORDS] __attribute__((section(".data")));

// Results handed between the harts
static volatile int      fails_h1 __attribute__((section(".data")));
static volatile uint32_t vlenb_free_h0 __attribute__((section(".data")));
static volatile uint32_t vlenb_free_h1 __attribute__((section(".data")));

static inline uint32_t pat(uint32_t i) { return 0x1000u + 7u * i; }
static inline uint32_t pat_b(uint32_t i) { return 0x8000u + 13u * i; }

static void clear_dst(void) {
  for (uint32_t i = 0; i < BUF_WORDS; i++) dst[i] = 0xDEADBEEFu;
}

static int check(const char *what, uint32_t i, uint32_t got, uint32_t exp, int *reported) {
  if (got == exp) return 0;
  if (!*reported) {
    printf("    %s: element %u got 0x%x expected 0x%x\n", what, i, got, exp);
    *reported = 1;
  }
  return 1;
}

// dst = src + 3 over one full register group of LMUL m; returns the number of elements
#define UNIT_STRIDE(m)                                                               \
  static uint32_t unit_stride_m##m(void) {                                           \
    uint32_t vl;                                                                     \
    asm volatile("vsetvli %0, %1, e32, m" #m ", ta, ma" : "=r"(vl) : "r"(BUF_WORDS)); \
    asm volatile("vle32.v v8, (%0)" : : "r"(src) : "memory");                        \
    asm volatile("vadd.vi v16, v8, 3");                                              \
    asm volatile("vse32.v v16, (%0)" : : "r"(dst) : "memory");                       \
    return vl;                                                                       \
  }
UNIT_STRIDE(1)
UNIT_STRIDE(2)
UNIT_STRIDE(4)
UNIT_STRIDE(8)

// Runs every check on the calling hart and returns the number of failed ones; vlenb_out gets the
// vlenb seen (checked across the modes at the end).
static int run_checks(const char *tag, uint32_t *vlenb_out) {
  int fails = 0;
  uint32_t vl, vlenb, res;
  uint32_t (*const unit[4])(void) = {unit_stride_m1, unit_stride_m2, unit_stride_m4,
                                     unit_stride_m8};

  // VLEN: vlenb and the e32/m1 VLMAX
  asm volatile("csrr %0, vlenb" : "=r"(vlenb));
  asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(BUF_WORDS));
  *vlenb_out = vlenb;
  const uint32_t vlmax = vlenb / 4;
  int ok = (vl == vlmax);
  printf("  %s: vlenb %u, e32/m1 VLMAX %u -> %s\n", tag, vlenb, vl, ok ? "PASS" : "FAIL");
  fails += !ok;

  // Unit stride over full register groups, LMUL 1 to 8
  for (uint32_t l = 0; l < 4; l++) {
    int rep = 0, err = 0;
    clear_dst();
    vl = unit[l]();
    snrt_fence();
    err += (vl != vlmax << l);
    for (uint32_t i = 0; i < vl; i++) err += check("unit", i, dst[i], src[i] + 3, &rep);
    for (uint32_t i = vl; i < BUF_WORDS; i++) err += check("unit tail", i, dst[i], 0xDEADBEEFu, &rep);
    printf("    unit stride LMUL %u: vl %u -> %s\n", 1u << l, vl, err ? "FAIL" : "PASS");
    fails += (err != 0);
  }

  // Strided: every second word, LMUL 2
  {
    int rep = 0, err = 0;
    clear_dst();
    asm volatile("vsetvli %0, %1, e32, m2, ta, ma" : "=r"(vl) : "r"(BUF_WORDS));
    asm volatile("vlse32.v v8, (%0), %1" : : "r"(src), "r"(8) : "memory");
    asm volatile("vsse32.v v8, (%0), %1" : : "r"(dst), "r"(8) : "memory");
    snrt_fence();
    for (uint32_t i = 0; i < 2 * vl; i++) {
      err += check("strided", i, dst[i], (i % 2) ? 0xDEADBEEFu : src[i], &rep);
    }
    printf("    strided LMUL 2: vl %u -> %s\n", vl, err ? "FAIL" : "PASS");
    fails += (err != 0);
  }

  // Indexed: reversed gather, LMUL 2
  {
    int rep = 0, err = 0;
    clear_dst();
    asm volatile("vsetvli %0, %1, e32, m2, ta, ma" : "=r"(vl) : "r"(BUF_WORDS));
    for (uint32_t i = 0; i < vl; i++) idx[i] = 4 * (vl - 1 - i);
    snrt_fence();
    asm volatile("vle32.v v4, (%0)" : : "r"(idx) : "memory");
    asm volatile("vluxei32.v v8, (%0), v4" : : "r"(src) : "memory");
    asm volatile("vse32.v v8, (%0)" : : "r"(dst) : "memory");
    snrt_fence();
    for (uint32_t i = 0; i < vl; i++) err += check("indexed", i, dst[i], src[vl - 1 - i], &rep);
    printf("    indexed LMUL 2: vl %u -> %s\n", vl, err ? "FAIL" : "PASS");
    fails += (err != 0);
  }

  // Slides by one over a full LMUL 8 group: down (the last element comes from past the largest
  // group, so it is zero) and up (element 0 keeps vd's old value, zero)
  {
    int rep = 0, err = 0;
    clear_dst();
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(BUF_WORDS));
    asm volatile("vle32.v v8, (%0)" : : "r"(src) : "memory");
    asm volatile("vslidedown.vi v16, v8, 1");
    asm volatile("vse32.v v16, (%0)" : : "r"(dst) : "memory");
    snrt_fence();
    for (uint32_t i = 0; i < vl; i++) {
      err += check("slidedown", i, dst[i], (i + 1 < vl) ? src[i + 1] : 0, &rep);
    }
    clear_dst();
    asm volatile("vmv.v.i v16, 0");
    asm volatile("vslideup.vi v16, v8, 1");
    asm volatile("vse32.v v16, (%0)" : : "r"(dst) : "memory");
    snrt_fence();
    for (uint32_t i = 0; i < vl; i++) err += check("slideup", i, dst[i], i ? src[i - 1] : 0, &rep);
    printf("    slides LMUL 8: vl %u -> %s\n", vl, err ? "FAIL" : "PASS");
    fails += (err != 0);
  }

  // Reduction: sum over a full LMUL 4 group
  {
    uint32_t sum = 0;
    asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(1));
    asm volatile("vmv.v.i v1, 0");
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(BUF_WORDS));
    asm volatile("vle32.v v8, (%0)" : : "r"(src) : "memory");
    asm volatile("vredsum.vs v2, v8, v1");
    asm volatile("vmv.x.s %0, v2" : "=r"(res));
    for (uint32_t i = 0; i < vl; i++) sum += src[i];
    ok = (res == sum);
    printf("    reduction LMUL 4: vl %u sum 0x%x (expected 0x%x) -> %s\n", vl, res, sum,
           ok ? "PASS" : "FAIL");
    fails += !ok;
  }

  return fails;
}

// v8-v15 = buf, over the full LMUL 8 group of the current layout
static inline void fill_v8(const uint32_t *buf) {
  uint32_t vl;
  asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(BUF_WORDS));
  asm volatile("vle32.v v8, (%0)" : : "r"(buf) : "memory");
}

// buf = v8-v15; returns the number of elements
static inline uint32_t dump_v8(uint32_t *buf) {
  uint32_t vl;
  asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(BUF_WORDS));
  asm volatile("vse32.v v8, (%0)" : : "r"(buf) : "memory");
  return vl;
}

static int check_dump(const char *tag, const uint32_t *exp) {
  int rep = 0, err = 0;
  clear_dst();
  const uint32_t vl = dump_v8(dst);
  snrt_fence();
  for (uint32_t i = 0; i < vl; i++) err += check(tag, i, dst[i], exp[i], &rep);
  printf("  %s: v8-v15 hold the own data (%u elements) -> %s\n", tag, vl, err ? "FAIL" : "PASS");
  return err != 0;
}

int main() {
  const uint32_t hid = snrt_cluster_core_idx();
  int fails = 0;

#if SNRT_NUM_SCALAR_PER_CORE != 2
  if (hid == 0) printf("spatz-vrf-mode needs a dual-scalar CC config, skipped\n");
  snrt_cluster_hw_barrier();
  return 0;
#else
  if (hid == 0) {
    printf("*** Spatz VRF mode test (dual thread %s) ***\n",
           SNRT_SPATZ_DUAL_THREAD ? "on" : "off");
    for (uint32_t i = 0; i < BUF_WORDS; i++) {
      src[i]   = pat(i);
      src_b[i] = pat_b(i);
    }
    fails_h1 = 0;
    snrt_fence();
  }
  snrt_cluster_hw_barrier();

  // 1. Dual mode, thread 0 (the lock is free after boot)
  if (hid == 0) {
    printf("1  dual mode, hart 0\n");
    fails += run_checks("hart 0", (uint32_t *)&vlenb_free_h0);
    snrt_fence();
  }
  snrt_cluster_hw_barrier();

  // 2. Dual mode, thread 1
  if (hid == 1) {
    printf("2  dual mode, hart 1\n");
    fails_h1 = run_checks("hart 1", (uint32_t *)&vlenb_free_h1);
    snrt_fence();
  }
  snrt_cluster_hw_barrier();

  // 3. Isolation. Only fences and barriers run between filling and reading back v8-v15, so no
  // compiler-generated vector code touches them.
  if (SNRT_SPATZ_DUAL_THREAD) {
    if (hid == 0) {
      printf("3  isolation\n");
      fill_v8(src);
      snrt_fence();
    }
    snrt_cluster_hw_barrier();
    if (hid == 1) {
      fill_v8(src_b);
      snrt_fence();
    }
    snrt_cluster_hw_barrier();
    if (hid == 0) {
      fails += check_dump("hart 0", src);
      snrt_fence();
    }
    snrt_cluster_hw_barrier();
    if (hid == 1) {
      fails_h1 += check_dump("hart 1", src_b);
      snrt_fence();
    }
    snrt_cluster_hw_barrier();
  } else if (hid == 0) {
    printf("3  isolation: skipped, no dual-thread Spatz\n");
  }

  // 4. Lock mode: hart 0 owns Spatz and the full VRF
  if (hid == 0) {
    uint32_t vlenb_lock;
    printf("4  lock mode, hart 0\n");
    spatz_lock_acquire();
    fails += run_checks("hart 0", &vlenb_lock);
    spatz_lock_release();

    // Dual mode halves vlenb for both threads; without the dual-thread Spatz nothing changes
    const uint32_t vlenb_dual = SNRT_SPATZ_DUAL_THREAD ? vlenb_lock / 2 : vlenb_lock;
    const int ok = (vlenb_free_h0 == vlenb_dual) && (vlenb_free_h1 == vlenb_dual);
    printf("5  dual-mode vlenb: hart 0 %u, hart 1 %u, expected %u -> %s\n", vlenb_free_h0,
           vlenb_free_h1, vlenb_dual, ok ? "PASS" : "FAIL");
    fails += !ok + fails_h1;
    printf("*** Spatz VRF mode test %s ***\n", fails ? "FAILED" : "PASSED");
  }
  snrt_cluster_hw_barrier();
  return (hid == 0 && fails) ? -1 : 0;
#endif
}
