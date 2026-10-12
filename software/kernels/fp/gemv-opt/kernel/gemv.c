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

// Author: Navaneeth Kunhi Purayil, ETH Zurich <nkunhi@iis.ee.ethz.ch>
// Author: Diyou Shen,              ETH Zurich <dishen@iis.ee.ethz.ch>

#include "gemv.h"

// One core's share of y = A * x: 16 * lmul rows over all N columns, so no
// reduction is needed. Every access stays in this core's own controller.
// a: this core's block of A in row 0; a block holds 4 / lmul columns and the
//    next block sits one row further on
// x: this core's block of x in row 0; 64 entries per block
// y: this core's block of y
// row: row size in floats
// N must be a multiple of 64.
void gemv_v32b(const float *a, const float *x, float *y,
               const uint32_t N, const uint32_t lmul,
               const uint32_t row) {
  // Offsets of the 4 columns handled per iteration, and the step to the next 4
  uint32_t o1, o2, o3, step;
  size_t vl;

  if (lmul == 4) {
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma"
                 : "=r"(vl)
                 : "r"(4 * GEMV_LINE_FLOATS));
    o1   = row;
    o2   = 2 * row;
    o3   = 3 * row;
    step = 4 * row;
  } else if (lmul == 2) {
    asm volatile("vsetvli %0, %1, e32, m2, ta, ma"
                 : "=r"(vl)
                 : "r"(2 * GEMV_LINE_FLOATS));
    o1   = 2 * GEMV_LINE_FLOATS;
    o2   = row;
    o3   = row + 2 * GEMV_LINE_FLOATS;
    step = 2 * row;
  } else {
    asm volatile("vsetvli %0, %1, e32, m1, ta, ma"
                 : "=r"(vl)
                 : "r"(GEMV_LINE_FLOATS));
    o1   = GEMV_LINE_FLOATS;
    o2   = 2 * GEMV_LINE_FLOATS;
    o3   = 3 * GEMV_LINE_FLOATS;
    step = row;
  }

  // Two accumulators break the vfmacc dependency chain
  asm volatile("vmv.v.i v16, 0");
  asm volatile("vmv.v.i v20, 0");

  // x is read through the integer LSU and moved over with fmv.w.x: an flw
  // is counted in Snitch's 3-bit acc_mem_cnt but not held back by its stall,
  // so flw behind 4 outstanding vle32 overflows the counter. The integer
  // loads run one iteration ahead so fmv.w.x never waits on them.
  const uint32_t *x_ = (const uint32_t *)x;
  uint32_t xi0, xi1, xi2, xi3;
  asm volatile("lw %0, 0(%1)" : "=r"(xi0) : "r"(x_));
  asm volatile("lw %0, 4(%1)" : "=r"(xi1) : "r"(x_));
  asm volatile("lw %0, 8(%1)" : "=r"(xi2) : "r"(x_));
  asm volatile("lw %0, 12(%1)" : "=r"(xi3) : "r"(x_));

  // Prologue: the first 4 columns
  asm volatile("vle32.v v0, (%0)" ::"r"(a));
  asm volatile("vle32.v v4, (%0)" ::"r"(a + o1));
  asm volatile("vle32.v v8, (%0)" ::"r"(a + o2));
  asm volatile("vle32.v v12, (%0)" ::"r"(a + o3));
  a += step;

  for (uint32_t j = 4; j <= N; j += 4) {
    float t0, t1, t2, t3;
    asm volatile("fmv.w.x %0, %1" : "=f"(t0) : "r"(xi0));
    asm volatile("fmv.w.x %0, %1" : "=f"(t1) : "r"(xi1));
    asm volatile("fmv.w.x %0, %1" : "=f"(t2) : "r"(xi2));
    asm volatile("fmv.w.x %0, %1" : "=f"(t3) : "r"(xi3));

    if (j == N) {
      asm volatile("vfmacc.vf v16, %0, v0" ::"f"(t0));
      asm volatile("vfmacc.vf v20, %0, v4" ::"f"(t1));
      asm volatile("vfmacc.vf v16, %0, v8" ::"f"(t2));
      asm volatile("vfmacc.vf v20, %0, v12" ::"f"(t3));
      break;
    }

    // Next x entries; a block of x covers 64 columns
    x_ += (j % GEMV_CTRL_FLOATS) ? 4 : row - GEMV_CTRL_FLOATS + 4;
    asm volatile("lw %0, 0(%1)" : "=r"(xi0) : "r"(x_));
    asm volatile("lw %0, 4(%1)" : "=r"(xi1) : "r"(x_));
    asm volatile("lw %0, 8(%1)" : "=r"(xi2) : "r"(x_));
    asm volatile("lw %0, 12(%1)" : "=r"(xi3) : "r"(x_));

    // Refill each register with the next column as soon as its FMA has it
    asm volatile("vfmacc.vf v16, %0, v0" ::"f"(t0));
    asm volatile("vle32.v v0, (%0)" ::"r"(a));
    asm volatile("vfmacc.vf v20, %0, v4" ::"f"(t1));
    asm volatile("vle32.v v4, (%0)" ::"r"(a + o1));
    asm volatile("vfmacc.vf v16, %0, v8" ::"f"(t2));
    asm volatile("vle32.v v8, (%0)" ::"r"(a + o2));
    asm volatile("vfmacc.vf v20, %0, v12" ::"f"(t3));
    asm volatile("vle32.v v12, (%0)" ::"r"(a + o3));
    a += step;
  }

  asm volatile("vfadd.vv v16, v16, v20");
  asm volatile("vse32.v v16, (%0)" ::"r"(y));
}

// LMUL 2 variant of gemv_v32b: 32-row vectors leave 16 register groups, so 8
// columns ride in a ring of v0 to v14 and each load gets 7 FMAs of lookahead.
// A block holds 2 columns; N must be a multiple of 64.
void gemv_v32b_m2(const float *a, const float *x, float *y,
                  const uint32_t N, const uint32_t row) {
  const uint32_t half = 2 * GEMV_LINE_FLOATS;
  size_t vl;

  asm volatile("vsetvli %0, %1, e32, m2, ta, ma" : "=r"(vl) : "r"(half));

  // Two accumulators break the vfmacc dependency chain
  asm volatile("vmv.v.i v24, 0");
  asm volatile("vmv.v.i v26, 0");

  // x through the integer LSU, one iteration ahead (see gemv_v32b)
  const uint32_t *x_ = (const uint32_t *)x;
  uint32_t xi0, xi1, xi2, xi3, xi4, xi5, xi6, xi7;
  asm volatile("lw %0, 0(%1)" : "=r"(xi0) : "r"(x_));
  asm volatile("lw %0, 4(%1)" : "=r"(xi1) : "r"(x_));
  asm volatile("lw %0, 8(%1)" : "=r"(xi2) : "r"(x_));
  asm volatile("lw %0, 12(%1)" : "=r"(xi3) : "r"(x_));
  asm volatile("lw %0, 16(%1)" : "=r"(xi4) : "r"(x_));
  asm volatile("lw %0, 20(%1)" : "=r"(xi5) : "r"(x_));
  asm volatile("lw %0, 24(%1)" : "=r"(xi6) : "r"(x_));
  asm volatile("lw %0, 28(%1)" : "=r"(xi7) : "r"(x_));

  // Prologue: the first 8 columns, 2 per block
  asm volatile("vle32.v v0, (%0)" ::"r"(a));
  asm volatile("vle32.v v2, (%0)" ::"r"(a + half));
  asm volatile("vle32.v v4, (%0)" ::"r"(a + row));
  asm volatile("vle32.v v6, (%0)" ::"r"(a + row + half));
  asm volatile("vle32.v v8, (%0)" ::"r"(a + 2 * row));
  asm volatile("vle32.v v10, (%0)" ::"r"(a + 2 * row + half));
  asm volatile("vle32.v v12, (%0)" ::"r"(a + 3 * row));
  asm volatile("vle32.v v14, (%0)" ::"r"(a + 3 * row + half));
  a += 4 * row;

  for (uint32_t j = 8; j <= N; j += 8) {
    float t0, t1, t2, t3, t4, t5, t6, t7;
    asm volatile("fmv.w.x %0, %1" : "=f"(t0) : "r"(xi0));
    asm volatile("fmv.w.x %0, %1" : "=f"(t1) : "r"(xi1));
    asm volatile("fmv.w.x %0, %1" : "=f"(t2) : "r"(xi2));
    asm volatile("fmv.w.x %0, %1" : "=f"(t3) : "r"(xi3));
    asm volatile("fmv.w.x %0, %1" : "=f"(t4) : "r"(xi4));
    asm volatile("fmv.w.x %0, %1" : "=f"(t5) : "r"(xi5));
    asm volatile("fmv.w.x %0, %1" : "=f"(t6) : "r"(xi6));
    asm volatile("fmv.w.x %0, %1" : "=f"(t7) : "r"(xi7));

    if (j == N) {
      asm volatile("vfmacc.vf v24, %0, v0" ::"f"(t0));
      asm volatile("vfmacc.vf v26, %0, v2" ::"f"(t1));
      asm volatile("vfmacc.vf v24, %0, v4" ::"f"(t2));
      asm volatile("vfmacc.vf v26, %0, v6" ::"f"(t3));
      asm volatile("vfmacc.vf v24, %0, v8" ::"f"(t4));
      asm volatile("vfmacc.vf v26, %0, v10" ::"f"(t5));
      asm volatile("vfmacc.vf v24, %0, v12" ::"f"(t6));
      asm volatile("vfmacc.vf v26, %0, v14" ::"f"(t7));
      break;
    }

    // Next x entries; a block of x covers 64 columns
    x_ += (j % GEMV_CTRL_FLOATS) ? 8 : row - GEMV_CTRL_FLOATS + 8;
    asm volatile("lw %0, 0(%1)" : "=r"(xi0) : "r"(x_));
    asm volatile("lw %0, 4(%1)" : "=r"(xi1) : "r"(x_));
    asm volatile("lw %0, 8(%1)" : "=r"(xi2) : "r"(x_));
    asm volatile("lw %0, 12(%1)" : "=r"(xi3) : "r"(x_));
    asm volatile("lw %0, 16(%1)" : "=r"(xi4) : "r"(x_));
    asm volatile("lw %0, 20(%1)" : "=r"(xi5) : "r"(x_));
    asm volatile("lw %0, 24(%1)" : "=r"(xi6) : "r"(x_));
    asm volatile("lw %0, 28(%1)" : "=r"(xi7) : "r"(x_));

    // Refill each register with the column 8 ahead as soon as its FMA has it
    asm volatile("vfmacc.vf v24, %0, v0" ::"f"(t0));
    asm volatile("vle32.v v0, (%0)" ::"r"(a));
    asm volatile("vfmacc.vf v26, %0, v2" ::"f"(t1));
    asm volatile("vle32.v v2, (%0)" ::"r"(a + half));
    asm volatile("vfmacc.vf v24, %0, v4" ::"f"(t2));
    asm volatile("vle32.v v4, (%0)" ::"r"(a + row));
    asm volatile("vfmacc.vf v26, %0, v6" ::"f"(t3));
    asm volatile("vle32.v v6, (%0)" ::"r"(a + row + half));
    asm volatile("vfmacc.vf v24, %0, v8" ::"f"(t4));
    asm volatile("vle32.v v8, (%0)" ::"r"(a + 2 * row));
    asm volatile("vfmacc.vf v26, %0, v10" ::"f"(t5));
    asm volatile("vle32.v v10, (%0)" ::"r"(a + 2 * row + half));
    asm volatile("vfmacc.vf v24, %0, v12" ::"f"(t6));
    asm volatile("vle32.v v12, (%0)" ::"r"(a + 3 * row));
    asm volatile("vfmacc.vf v26, %0, v14" ::"f"(t7));
    asm volatile("vle32.v v14, (%0)" ::"r"(a + 3 * row + half));
    a += 4 * row;
  }

  asm volatile("vfadd.vv v24, v24, v26");
  asm volatile("vse32.v v24, (%0)" ::"r"(y));
}
