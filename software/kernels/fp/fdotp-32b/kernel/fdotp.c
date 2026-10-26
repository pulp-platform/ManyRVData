// Copyright 2022 ETH Zurich and University of Bologna.
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

// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Author: Diyou Shen     <dishen@iis.ee.ethz.ch>

#include "fdotp.h"

// Every round loads `vl` elements of a and b, `offset` floats after the
// previous one, and accumulates a * b into v24 (at LMUL L). vl is always set
// explicitly: Spatz maps `vsetvli rd, x0` to the LMUL 8 VLMAX whatever the
// requested LMUL.

// One register set: a in v8, b in v16
#define FDOTP_ACC_U1(L)                                                        \
  static inline void fdotp_acc_u1_m##L(const float *a, const float *b,       \
                                       const uint32_t vl,                     \
                                       const uint32_t offset,                 \
                                       uint32_t rounds) {                     \
    asm volatile("vsetvli zero, %0, e32, m" #L ", ta, ma" ::"r"(vl));          \
    asm volatile("vle32.v v8,  (%0)" ::"r"(a));                                \
    asm volatile("vle32.v v16, (%0)" ::"r"(b));                                \
    asm volatile("vfmul.vv v24, v8, v16");                                     \
    while (--rounds) {                                                         \
      a += offset;                                                             \
      asm volatile("vle32.v v8,  (%0)" ::"r"(a));                              \
      b += offset;                                                             \
      asm volatile("vle32.v v16, (%0)" ::"r"(b));                              \
      asm volatile("vfmacc.vv v24, v8, v16");                                  \
    }                                                                          \
  }

// Two register sets, (v0, v4) and (v8, v12): the next round is loaded into
// one set while the other one is multiplied. LMUL 4 at most.
#define FDOTP_ACC_U2(L)                                                        \
  static inline void fdotp_acc_u2_m##L(const float *a, const float *b,       \
                                       const uint32_t vl,                     \
                                       const uint32_t offset,                 \
                                       const uint32_t rounds) {               \
    asm volatile("vsetvli zero, %0, e32, m" #L ", ta, ma" ::"r"(vl));          \
    asm volatile("vle32.v v0, (%0)" ::"r"(a));                                 \
    asm volatile("vle32.v v4, (%0)" ::"r"(b));                                 \
    if (rounds == 1) {                                                         \
      asm volatile("vfmul.vv v24, v0, v4");                                    \
      return;                                                                  \
    }                                                                          \
    a += offset;                                                               \
    b += offset;                                                               \
    asm volatile("vle32.v v8,  (%0)" ::"r"(a));                                \
    asm volatile("vle32.v v12, (%0)" ::"r"(b));                                \
    asm volatile("vfmul.vv v24, v0, v4");                                      \
    uint32_t r = 2;                                                            \
    while (r < rounds) {                                                       \
      a += offset;                                                             \
      b += offset;                                                             \
      asm volatile("vle32.v v0, (%0)" ::"r"(a));                               \
      asm volatile("vle32.v v4, (%0)" ::"r"(b));                               \
      asm volatile("vfmacc.vv v24, v8, v12");                                  \
      if (++r == rounds) {                                                     \
        asm volatile("vfmacc.vv v24, v0, v4");                                 \
        return;                                                                \
      }                                                                        \
      a += offset;                                                             \
      b += offset;                                                             \
      asm volatile("vle32.v v8,  (%0)" ::"r"(a));                              \
      asm volatile("vle32.v v12, (%0)" ::"r"(b));                              \
      asm volatile("vfmacc.vv v24, v0, v4");                                   \
      ++r;                                                                     \
    }                                                                          \
    asm volatile("vfmacc.vv v24, v8, v12");                                    \
  }

FDOTP_ACC_U1(8)
FDOTP_ACC_U1(4)
FDOTP_ACC_U1(2)
FDOTP_ACC_U1(1)
FDOTP_ACC_U2(4)
FDOTP_ACC_U2(2)
FDOTP_ACC_U2(1)

// Spatz reduces one element per FPU latency, so the accumulator is first
// halved with full-width vfadd down to LMUL 1. vl is the accumulator length.
static inline void fdotp_fold_m1(const uint32_t lmul, uint32_t vl) {
  if (lmul >= 8) {
    vl >>= 1;
    asm volatile("vsetvli zero, %0, e32, m4, ta, ma" ::"r"(vl));
    asm volatile("vfadd.vv v24, v24, v28");
  }
  if (lmul >= 4) {
    vl >>= 1;
    asm volatile("vsetvli zero, %0, e32, m2, ta, ma" ::"r"(vl));
    asm volatile("vfadd.vv v24, v24, v26");
  }
  if (lmul >= 2) {
    vl >>= 1;
    asm volatile("vsetvli zero, %0, e32, m1, ta, ma" ::"r"(vl));
    asm volatile("vfadd.vv v24, v24, v25");
  }
}

// TMP-DOTP-SEED: 0 seeds v0 with vmv.s.x, 1 with vfmv.s.f, 2 not at all
#ifndef FDOTP_SEED
#define FDOTP_SEED 1
#endif
#if FDOTP_SEED == 0
#define FDOTP_SEED_V0() asm volatile("vmv.s.x v0, zero")
#elif FDOTP_SEED == 2
#define FDOTP_SEED_V0() do { } while (0)
#else
#define FDOTP_SEED_V0()                                                        \
  do {                                                                         \
    float zero_f;                                                              \
    asm volatile("fmv.w.x %0, zero" : "=f"(zero_f));                           \
    asm volatile("vfmv.s.f v0, %0" ::"f"(zero_f));                             \
  } while (0)
#endif

// Reduce the v24 accumulator (LMUL lmul, vl elements) to a scalar
static inline float fdotp_reduce(const uint32_t lmul, const uint32_t vl,
                                 const uint32_t vred) {
  float red;

  if (vred == FDOTP_VRED_FULL) {
    FDOTP_SEED_V0();
    asm volatile("vfredusum.vs v0, v24, v0");
    asm volatile("vfmv.f.s %0, v0" : "=f"(red));
    return red;
  }

  fdotp_fold_m1(lmul, vl);

  if (vred == FDOTP_VRED_FOLD) {
    FDOTP_SEED_V0();
    asm volatile("vfredusum.vs v0, v24, v0");
    asm volatile("vfmv.f.s %0, v0" : "=f"(red));
  } else {
    // Halve the remaining LMUL 1 vector until one element is left
    for (uint32_t n = vl / lmul / 2; n > 0; n >>= 1) {
      asm volatile("vsetvli zero, %0, e32, m1, ta, ma" ::"r"(n));
      asm volatile("vslidedown.vx v25, v24, %0" ::"r"(n));
      asm volatile("vfadd.vv v24, v24, v25");
    }
    asm volatile("vfmv.f.s %0, v24" : "=f"(red));
  }
  return red;
}

// 32-bit dot-product partial of one core: `rounds` chunks of vl elements at
// `lmul`, `offset` floats apart
float fdotp_v32b(const float *a, const float *b, const uint32_t vl,
                 const uint32_t offset, const uint32_t rounds,
                 const uint32_t lmul, const uint32_t unroll,
                 const uint32_t vred) {
  if (unroll == 2 && lmul <= 4) {
    if (lmul == 4)
      fdotp_acc_u2_m4(a, b, vl, offset, rounds);
    else if (lmul == 2)
      fdotp_acc_u2_m2(a, b, vl, offset, rounds);
    else
      fdotp_acc_u2_m1(a, b, vl, offset, rounds);
  } else {
    if (lmul == 8)
      fdotp_acc_u1_m8(a, b, vl, offset, rounds);
    else if (lmul == 4)
      fdotp_acc_u1_m4(a, b, vl, offset, rounds);
    else if (lmul == 2)
      fdotp_acc_u1_m2(a, b, vl, offset, rounds);
    else
      fdotp_acc_u1_m1(a, b, vl, offset, rounds);
  }
  return fdotp_reduce(lmul, vl, vred);
}
