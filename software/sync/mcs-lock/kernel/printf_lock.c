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

#include <stdarg.h>
#include <stdint.h>
#include <snrt.h>
#include "printf.h"
#include "printf_lock.h"

/* Spinlock acquire/release helpers */
static inline void printf_lock_acquire(volatile int *lock) {
    while (__sync_lock_test_and_set(lock, 1)) { delay(20); }
}

static inline void printf_lock_release(volatile int *lock) {
    asm volatile (
        "amoswap.w zero, zero, %0"
        : "+A" (*lock)
    );
    delay(20);
 }


void debug_print_lock_init(void) {
    printf_lock = 0; // Optional: usually zero by default
}

/* Thread-safe debug print using global spinlock */
#ifdef DEBUG_PRINTF
void debug_printf_locked(const char * __attribute__((aligned(8))) fmt, ...) {
    printf_lock_acquire(&printf_lock);

    printf(fmt);

    printf_lock_release(&printf_lock);
}
#else
void debug_printf_locked(const char *fmt, ...) {
    // No-op if DEBUG_PRINTF is not defined
    (void)fmt; // Avoid unused parameter warning
}
#endif

/* A simple busy-loop delay function. Adjust iterations as needed. */
static void delay(volatile int iterations) {
    for (; iterations > 0; iterations--);
}
