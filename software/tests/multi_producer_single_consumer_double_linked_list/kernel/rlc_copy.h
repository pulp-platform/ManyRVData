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

/* Byte-granular payload copy, shared by the downlink TB assembler and the
   uplink harness. Kept in its own header because both directions need it and
   neither owns it. */

#ifndef RLC_COPY_H
#define RLC_COPY_H

#include <stdint.h>

#ifndef RLC_DL_COPY_SCALAR
#define RLC_DL_COPY_SCALAR 0
#endif

/* A protocol-accurate AMD header is 3 or 5 bytes, so the payload inside the
   transport block starts at an arbitrary byte offset -- the word-aligned
   vector copies the legacy path uses cannot be applied here. (The legacy path
   only got away with them because its placeholder header was a padded 10
   bytes and every destination was slot-aligned.) e8 elements need no more
   than byte alignment, so this copies at m8: VLEN/8 * 8 = 512 B per pass at
   VLEN=512. */
static void rlc_memcpy8(uint8_t *dst, const uint8_t *src, uint32_t n) {
#if RLC_DL_COPY_SCALAR
  for (uint32_t b = 0u; b < n; b++) dst[b] = src[b];
  asm volatile("fence" ::: "memory");
#else
  uint32_t i = 0;
  while (i < n) {
    uint32_t vl;
    asm volatile("vsetvli %0, %1, e8, m8, ta, ma" : "=r"(vl) : "r"(n - i));
    if (vl == 0u) break; /* see RLC_VEC_GUARD in rlc_plan.c */
    asm volatile("vle8.v v8, (%0)" ::"r"(src + i) : "memory");
    asm volatile("vse8.v v8, (%0)" ::"r"(dst + i) : "memory");
    i += vl;
  }
  asm volatile("fence" ::: "memory");
#endif
}

#endif /* RLC_COPY_H */
