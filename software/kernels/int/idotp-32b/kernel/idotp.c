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

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

#include "idotp.h"

// 32-bit dot-product: a * b
int idotp_v32b_lmul8(const int *a, const int *b, const unsigned int offset, const unsigned int avl, const unsigned int rounds) {
  unsigned int vl;
  unsigned int iter = rounds;

  int red;

  // Set the vl
  asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(avl));

  asm volatile("vle32.v v8,  (%0)" ::"r"(a));
  iter --;
  asm volatile("vle32.v v16, (%0)" ::"r"(b));
  asm volatile("vmul.vv v24, v8, v16");

  // Stripmine and accumulate a partial reduced vector
  do {
    // Load chunk a and b
    a += offset;
    asm volatile("vle32.v v8,  (%0)" ::"r"(a));
    b += offset;
    asm volatile("vle32.v v16, (%0)" ::"r"(b));
    iter --;

    // Multiply and accumulate
    asm volatile("vmacc.vv v24, v8, v16");
  } while (iter > 0);

  // Reduce and return
  asm volatile("vredsum.vs v0, v24, v0");
  asm volatile("vmv.x.s %0, v0" : "=r"(red));
  return red;
}

// 32-bit dot-product: a * b
int idotp_v32b_lmul4(const int *a, const int *b, const unsigned int offset, const unsigned int avl, const unsigned int rounds) {
  unsigned int vl;
  unsigned int iter = rounds;

  int red;

  // Set the vl
  asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(avl));

  asm volatile("vle32.v v8,  (%0)" ::"r"(a));
  iter --;
  asm volatile("vle32.v v16, (%0)" ::"r"(b));
  asm volatile("vmul.vv v24, v8, v16");

  // Stripmine and accumulate a partial reduced vector
  do {
    // Load chunk a and b
    a += offset;
    asm volatile("vle32.v v8,  (%0)" ::"r"(a));
    b += offset;
    asm volatile("vle32.v v16, (%0)" ::"r"(b));
    iter --;

    // Multiply and accumulate
    asm volatile("vmacc.vv v24, v8, v16");
  } while (iter > 0);

  // Reduce and return
  asm volatile("vredsum.vs v0, v24, v0");
  asm volatile("vmv.x.s %0, v0" : "=r"(red));
  return red;
}

// 32-bit dot-product: a * b
int idotp_v32b_lmul2(const int *a, const int *b, const unsigned int offset, const unsigned int avl, const unsigned int rounds) {
  unsigned int vl;
  unsigned int iter = rounds;

  int red;

  // Set the vl
  asm volatile("vsetvli %0, %1, e32, m2, ta, ma" : "=r"(vl) : "r"(avl));

  asm volatile("vle32.v v8,  (%0)" ::"r"(a));
  iter --;
  asm volatile("vle32.v v16, (%0)" ::"r"(b));
  asm volatile("vmul.vv v24, v8, v16");

  // Stripmine and accumulate a partial reduced vector
  do {
    // Load chunk a and b
    a += offset;
    asm volatile("vle32.v v8,  (%0)" ::"r"(a));
    b += offset;
    asm volatile("vle32.v v16, (%0)" ::"r"(b));
    iter --;

    // Multiply and accumulate
    asm volatile("vmacc.vv v24, v8, v16");
  } while (iter > 0);

  // Reduce and return
  asm volatile("vredsum.vs v0, v24, v0");
  asm volatile("vmv.x.s %0, v0" : "=r"(red));
  return red;
}

// 32-bit dot-product: a * b
int idotp_v32b_lmul1(const int *a, const int *b, const unsigned int offset, const unsigned int avl, const unsigned int rounds) {
  unsigned int vl;
  unsigned int iter = rounds;

  int red;

  // Set the vl
  asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(avl));

  asm volatile("vle32.v v8,  (%0)" ::"r"(a));
  iter --;
  asm volatile("vle32.v v16, (%0)" ::"r"(b));
  asm volatile("vfmul.vv v24, v8, v16");

  // Stripmine and accumulate a partial reduced vector
  do {
    // Load chunk a and b
    a += offset;
    asm volatile("vle32.v v8,  (%0)" ::"r"(a));
    b += offset;
    asm volatile("vle32.v v16, (%0)" ::"r"(b));
    iter --;

    // Multiply and accumulate
    asm volatile("vmacc.vv v24, v8, v16");
  } while (iter > 0);

  // Reduce and return
  asm volatile("vredsum.vs v0, v24, v0");
  asm volatile("vmv.x.s %0, v0" : "=r"(red));
  return red;
}
