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

#include <stdint.h>

/* Fast, tiny PRNG. State must never be 0. */
static inline uint32_t xorshift32(uint32_t *state) {
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x ? x : 0x9E3779B9u;  // avoid zero state
    return x;
}

/* Pick a small random delay to avoid slowing sim too much.
   Masking is cheaper than modulo on baremetal. */
#ifndef CS_DELAY_MASK
#define CS_DELAY_MASK 0x7Fu   // 0..127 cycles; tweak as you like
// #define CS_DELAY_MASK 0x7FFu   // 0..2047 cycles
#endif
