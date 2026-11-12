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

// Dual-thread Spatz with the FPU: the two harts of Core Complex 0 run floating-point vector code
// at the same time while the Spatz lock is free. Each hart has its own FPU sequencer (scalar FP
// registers, FP loads/stores), and Spatz runs both threads with separate CSRs and VRF halves.
// Both harts run the same code, so they use the same vector and FP register numbers:
//   hart 0: e32, LMUL 2, AVL 13
//   hart 1: e32, LMUL 4, AVL 50
// Each iteration loads FP scalars (flw), runs .vf operations, moves an element back to an FP
// register (vfmv.f.s), does scalar FP arithmetic on it and stores it (fsw). All values are small
// integers or halves, so every result is exact. Reductions, strided and indexed accesses are left
// out: their datapaths have known bugs.

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

static float src[BUF_ELEMS] __attribute__((section(".data")));
static float dst[2][ITERS][BUF_ELEMS] __attribute__((section(".data")));

// Per-hart scalar inputs and results
static float    scale[2][ITERS] __attribute__((section(".data")));
static float    offset[2] __attribute__((section(".data")));
static uint32_t vl_ret[2][ITERS] __attribute__((section(".data")));
static float    mvfs[2][ITERS] __attribute__((section(".data")));
static float    sadd[2][ITERS] __attribute__((section(".data")));

// dst = src * scale + offset over vl elements, vfmv.f.s of element 0, then a scalar FP add
static void run(uint32_t hid) {
  uint32_t vl;
  float    mv;
  for (uint32_t it = 0; it < ITERS; it++) {
    const float s = scale[hid][it];
    const float c = offset[hid];
    if (hid == 0) {
      asm volatile("vsetvli %0, %1, e32, m2, ta, ma" : "=r"(vl) : "r"(AVL_H0));
    } else {
      asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(AVL_H1));
    }
    asm volatile("vle32.v v8, (%0)" : : "r"(src) : "memory");
    asm volatile("vfmul.vf v16, v8, %0" : : "f"(s));
    asm volatile("vfadd.vf v16, v16, %0" : : "f"(c));
    asm volatile("vse32.v v16, (%0)" : : "r"(dst[hid][it]) : "memory");
    asm volatile("vfmv.f.s %0, v16" : "=f"(mv));
    vl_ret[hid][it] = vl;
    mvfs[hid][it]   = mv;
    sadd[hid][it]   = mv + s;
  }
}

static inline uint32_t bits(float f) {
  union {
    float    f;
    uint32_t u;
  } v = {.f = f};
  return v.u;
}

static int report(int *reported, const char *what, uint32_t it, uint32_t i, float got,
                  float exp) {
  if (bits(got) == bits(exp)) return 0;
  if (*reported < 4) {
    printf("    %s: iter %u element %u got 0x%x expected 0x%x\n", what, it, i, bits(got),
           bits(exp));
  }
  (*reported)++;
  return 1;
}

static int check_hart(uint32_t hid) {
  int err = 0, rep = 0;
  // VLEN 512 split in two in dual mode: e32/m1 VLMAX 8, else 16
  const uint32_t vlmax_m1 = SNRT_SPATZ_DUAL_THREAD ? 8u : 16u;
  const uint32_t vlmax    = vlmax_m1 * (hid ? 4u : 2u);
  const uint32_t avl      = hid ? AVL_H1 : AVL_H0;
  const uint32_t vl_exp   = avl < vlmax ? avl : vlmax;

  for (uint32_t it = 0; it < ITERS; it++) {
    const float s = scale[hid][it];
    const float c = offset[hid];
    if (vl_ret[hid][it] != vl_exp) {
      if (rep < 4) printf("    vsetvli: iter %u got %u expected %u\n", it, vl_ret[hid][it], vl_exp);
      rep++;
      err++;
    }
    for (uint32_t i = 0; i < vl_exp; i++) {
      err += report(&rep, "vfmul/vfadd", it, i, dst[hid][it][i], src[i] * s + c);
    }
    // Nothing is written past vl
    for (uint32_t i = vl_exp; i < BUF_ELEMS; i++) {
      err += report(&rep, "tail", it, i, dst[hid][it][i], 0.0f);
    }
    err += report(&rep, "vfmv.f.s", it, 0, mvfs[hid][it], src[0] * s + c);
    err += report(&rep, "fadd.s", it, 0, sadd[hid][it], src[0] * s + c + s);
  }
  printf("  hart %u: vl %u, %d errors -> %s\n", hid, vl_exp, err, err ? "FAIL" : "PASS");
  return err != 0;
}

int main() {
  const uint32_t hid = snrt_cluster_core_idx();
  int fails = 0;

#if SNRT_NUM_SCALAR_PER_CORE != 2
  if (hid == 0) printf("spatz-dual-thread-fp needs a dual-scalar CC config, skipped\n");
  snrt_cluster_hw_barrier();
  return 0;
#else
  if (hid == 0) {
    printf("*** Spatz dual-thread FP test (dual thread %s) ***\n",
           SNRT_SPATZ_DUAL_THREAD ? "on" : "off");
    for (uint32_t i = 0; i < BUF_ELEMS; i++) src[i] = (float)(i + 1);
    for (uint32_t h = 0; h < 2; h++) {
      offset[h] = 0.5f + (float)h;
      for (uint32_t it = 0; it < ITERS; it++) scale[h][it] = (float)(2 + it + 8 * h);
    }
    snrt_fence();
  }
  snrt_cluster_hw_barrier();

  // Both harts of CC0 run concurrently, the lock is free (dual mode)
  if (hid < 2) {
    run(hid);
    snrt_fence();
  }
  snrt_cluster_hw_barrier();

  if (hid == 0) {
    fails += check_hart(0);
    fails += check_hart(1);
    printf("*** Spatz dual-thread FP test %s ***\n", fails ? "FAILED" : "PASSED");
  }
  snrt_cluster_hw_barrier();
  return (hid == 0 && fails) ? -1 : 0;
#endif
}
