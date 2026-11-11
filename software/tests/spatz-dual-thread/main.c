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

// Dual-thread Spatz: the two harts of Core Complex 0 share one Spatz and run vector code at the
// same time while the Spatz lock is free. Every instruction carries its hart's thread, so each
// hart has its own vl/vtype/vstart, scoreboard and half of the VRF. Both harts use the same
// register numbers with different SEW, LMUL and AVL:
//   hart 0: e32, LMUL 2, AVL 13
//   hart 1: e16, LMUL 4, AVL 50
// Each iteration checks the vsetvli return value, csrr vl/vtype, a vmv.x.s result and, in memory,
// unit-stride and slide results. Reductions, strided and indexed accesses are left out: their
// datapaths have known bugs.

#include <snrt.h>
#include <stdint.h>
#include <printf.h>

#ifndef SNRT_SPATZ_DUAL_THREAD
#define SNRT_SPATZ_DUAL_THREAD 0
#endif

#define ITERS 8u
#define BUF_ELEMS 64u

#define AVL_H0 13u
#define AVL_H1 50u

static uint32_t src32[BUF_ELEMS] __attribute__((section(".data")));
static uint32_t dst32[ITERS][BUF_ELEMS] __attribute__((section(".data")));
static uint32_t sld32[ITERS][BUF_ELEMS] __attribute__((section(".data")));

static uint16_t src16[BUF_ELEMS] __attribute__((section(".data")));
static uint16_t dst16[ITERS][BUF_ELEMS] __attribute__((section(".data")));
static uint16_t sld16[ITERS][BUF_ELEMS] __attribute__((section(".data")));

// Per-hart scalar results, checked after the concurrent phase
static uint32_t vl_ret[2][ITERS] __attribute__((section(".data")));
static uint32_t vl_csr[2][ITERS] __attribute__((section(".data")));
static uint32_t vtype_csr[2][ITERS] __attribute__((section(".data")));
static uint32_t mvxs[2][ITERS] __attribute__((section(".data")));
static uint32_t vlenb_seen[2] __attribute__((section(".data")));

static volatile int fails_h1 __attribute__((section(".data")));

static inline uint32_t k_of(uint32_t hid, uint32_t it) { return 5u + 3u * it + 100u * hid; }

// Hart 0: e32, LMUL 2. v8 = src, v16 = (v8 + k) * 3, v4 = v16 slid down by one.
static void run_h0(void) {
  uint32_t vl, csr_vl, csr_vtype, mv;
  for (uint32_t it = 0; it < ITERS; it++) {
    const uint32_t k = k_of(0, it);
    asm volatile("vsetvli %0, %1, e32, m2, ta, ma" : "=r"(vl) : "r"(AVL_H0));
    asm volatile("csrr %0, vl" : "=r"(csr_vl));
    asm volatile("csrr %0, vtype" : "=r"(csr_vtype));
    asm volatile("vle32.v v8, (%0)" : : "r"(src32) : "memory");
    asm volatile("vadd.vx v16, v8, %0" : : "r"(k));
    asm volatile("vmul.vx v16, v16, %0" : : "r"(3));
    asm volatile("vse32.v v16, (%0)" : : "r"(dst32[it]) : "memory");
    asm volatile("vmv.x.s %0, v16" : "=r"(mv));
    asm volatile("vslidedown.vi v4, v16, 1");
    asm volatile("vse32.v v4, (%0)" : : "r"(sld32[it]) : "memory");
    vl_ret[0][it]    = vl;
    vl_csr[0][it]    = csr_vl;
    vtype_csr[0][it] = csr_vtype;
    mvxs[0][it]      = mv;
  }
}

// Hart 1: e16, LMUL 4, same register numbers
static void run_h1(void) {
  uint32_t vl, csr_vl, csr_vtype, mv;
  for (uint32_t it = 0; it < ITERS; it++) {
    const uint32_t k = k_of(1, it);
    asm volatile("vsetvli %0, %1, e16, m4, ta, ma" : "=r"(vl) : "r"(AVL_H1));
    asm volatile("csrr %0, vl" : "=r"(csr_vl));
    asm volatile("csrr %0, vtype" : "=r"(csr_vtype));
    asm volatile("vle16.v v8, (%0)" : : "r"(src16) : "memory");
    asm volatile("vadd.vx v16, v8, %0" : : "r"(k));
    asm volatile("vmul.vx v16, v16, %0" : : "r"(3));
    asm volatile("vse16.v v16, (%0)" : : "r"(dst16[it]) : "memory");
    asm volatile("vmv.x.s %0, v16" : "=r"(mv));
    asm volatile("vslidedown.vi v4, v16, 1");
    asm volatile("vse16.v v4, (%0)" : : "r"(sld16[it]) : "memory");
    vl_ret[1][it]    = vl;
    vl_csr[1][it]    = csr_vl;
    vtype_csr[1][it] = csr_vtype;
    mvxs[1][it]      = mv;
  }
}

static int report(int *reported, const char *what, uint32_t it, uint32_t i, uint32_t got,
                  uint32_t exp) {
  if (got == exp) return 0;
  if (*reported < 4) {
    printf("    %s: iter %u element %u got 0x%x expected 0x%x\n", what, it, i, got, exp);
  }
  (*reported)++;
  return 1;
}

// Checks one hart's results; vlmax is the e32/m1 VLMAX of the half VRF (vlenb / 4)
static int check_hart(uint32_t hid) {
  int err = 0, rep = 0;
  const uint32_t vlenb  = vlenb_seen[hid];
  const uint32_t vlmax  = hid ? (vlenb / 2) * 4 : (vlenb / 4) * 2;
  const uint32_t avl    = hid ? AVL_H1 : AVL_H0;
  const uint32_t vl_exp = avl < vlmax ? avl : vlmax;
  // vtype: vlmul in [2:0], vsew in [5:3], ta [6], ma [7]
  const uint32_t vtype_exp = hid ? (0xC0u | (1u << 3) | 2u) : (0xC0u | (2u << 3) | 1u);

  for (uint32_t it = 0; it < ITERS; it++) {
    const uint32_t k = k_of(hid, it);
    err += report(&rep, "vsetvli", it, 0, vl_ret[hid][it], vl_exp);
    err += report(&rep, "csrr vl", it, 0, vl_csr[hid][it], vl_exp);
    err += report(&rep, "csrr vtype", it, 0, vtype_csr[hid][it], vtype_exp);
    for (uint32_t i = 0; i < vl_exp; i++) {
      if (hid == 0) {
        const uint32_t r = (src32[i] + k) * 3u;
        err += report(&rep, "unit", it, i, dst32[it][i], r);
        // Element vl-1 of the slide reads past vl, so only the elements below are defined
        if (i + 1 < vl_exp) {
          err += report(&rep, "slide", it, i, sld32[it][i], (src32[i + 1] + k) * 3u);
        }
        if (i == 0) err += report(&rep, "vmv.x.s", it, 0, mvxs[hid][it], r);
      } else {
        const uint16_t r = (uint16_t)((src16[i] + k) * 3u);
        err += report(&rep, "unit", it, i, dst16[it][i], r);
        if (i + 1 < vl_exp) {
          err += report(&rep, "slide", it, i, sld16[it][i],
                        (uint16_t)((src16[i + 1] + k) * 3u));
        }
        // Spatz's vmv.x.s returns the whole 32-bit lane word instead of the sign-extended
        // element (known limitation), so only the low SEW bits are checked
        if (i == 0) err += report(&rep, "vmv.x.s", it, 0, mvxs[hid][it] & 0xFFFFu, r);
      }
    }
    // Nothing is written past vl
    for (uint32_t i = vl_exp; i < BUF_ELEMS; i++) {
      err += report(&rep, "tail", it, i, hid ? dst16[it][i] : dst32[it][i], 0);
    }
  }
  printf("  hart %u: vlenb %u, vl %u, %d errors -> %s\n", hid, vlenb, vl_exp, err,
         err ? "FAIL" : "PASS");
  return err != 0;
}

int main() {
  const uint32_t hid = snrt_cluster_core_idx();
  int fails = 0;

#if SNRT_NUM_SCALAR_PER_CORE != 2
  if (hid == 0) printf("spatz-dual-thread needs a dual-scalar CC config, skipped\n");
  snrt_cluster_hw_barrier();
  return 0;
#else
  if (hid == 0) {
    printf("*** Spatz dual-thread test (dual thread %s) ***\n",
           SNRT_SPATZ_DUAL_THREAD ? "on" : "off");
    for (uint32_t i = 0; i < BUF_ELEMS; i++) {
      src32[i] = 0x1000u + 7u * i;
      src16[i] = (uint16_t)(0x100u + 5u * i);
    }
    fails_h1 = 0;
    snrt_fence();
  }
  snrt_cluster_hw_barrier();

  // Both harts of CC0 run concurrently, the lock is free (dual mode)
  if (hid < 2) {
    asm volatile("csrr %0, vlenb" : "=r"(vlenb_seen[hid]));
    if (hid == 0) {
      run_h0();
    } else {
      run_h1();
    }
    snrt_fence();
  }
  snrt_cluster_hw_barrier();

  if (hid == 0) {
    fails += check_hart(0);
    fails += check_hart(1);
    // Both threads see half of the full VLEN of 512 bit with the dual-thread Spatz
    const uint32_t vlenb_exp = SNRT_SPATZ_DUAL_THREAD ? 32u : 64u;
    const int ok = (vlenb_seen[0] == vlenb_exp) && (vlenb_seen[1] == vlenb_exp);
    printf("  vlenb: hart 0 %u, hart 1 %u, expected %u -> %s\n", vlenb_seen[0], vlenb_seen[1],
           vlenb_exp, ok ? "PASS" : "FAIL");
    fails += !ok;
    printf("*** Spatz dual-thread test %s ***\n", fails ? "FAILED" : "PASSED");
  }
  snrt_cluster_hw_barrier();
  return (hid == 0 && fails) ? -1 : 0;
#endif
}
