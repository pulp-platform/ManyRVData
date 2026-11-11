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

// Integer GEMV, ported from kernels/fp/gemv (gemv_v32b_m4): vfmul/vfmacc.vf become vmul/vmacc.vx.

#include "igemv.h"

// c[0..M_core) = A[0..M_core, 0..N) * b, with A column-major (column stride M)
void __attribute__((noinline)) igemv_v32b_m4(int32_t *a, int32_t *b, int32_t *c, int M,
                                             int M_core, int N) {
  unsigned int vl, avl = M_core;
  int32_t *a_ = a;
  int32_t *b_ = b;
  int32_t *c_ = c;

  do {
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(avl));
    for (int col = 0; col < N; col += 2) {
      // Load chunk a
      asm volatile("vle32.v v0, (%0)" ::"r"(a_));
      a_ += M;

      // Multiply and accumulate
      if (col == 0) {
        asm volatile("vmul.vx v4, v0, %0" ::"r"(*b_));
      } else {
        asm volatile("vmacc.vx v4, %0, v0" ::"r"(*b_));
      }
      b_++;

      // Load chunk a
      asm volatile("vle32.v v8, (%0)" ::"r"(a_));
      a_ += M;

      // Multiply and accumulate
      if (col == 0) {
        asm volatile("vmul.vx v12, v8, %0" ::"r"(*b_));
      } else {
        asm volatile("vmacc.vx v12, %0, v8" ::"r"(*b_));
      }
      b_++;
    }
    asm volatile("vadd.vv v12, v12, v4");
    asm volatile("vse32.v v12, (%0)" ::"r"(c_));
    avl -= vl;
    c_ += vl;
    b_ = b;
    // Next strip: the rows after the ones done (the fp version offsets by the rows left)
    a_ = a + (M_core - avl);
  } while (avl > 0);
}
