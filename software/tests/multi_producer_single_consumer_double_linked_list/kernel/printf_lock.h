#ifndef DEBUG_H
#define DEBUG_H

#include <stdio.h>
#include "printf.h"
#include "encoding.h"

// Enable debug printf
// #define DEBUG_PRINTF                printf
// #define DEBUG_PRINTF_LOCK_ACQUIRE   printf_lock_acquire
// #define DEBUG_PRINTF_LOCK_RELEASE   printf_lock_release
// Disable debug printf
#define DEBUG_PRINTF                printf_place_holder
#define DEBUG_PRINTF_LOCK_ACQUIRE   printf_lock_place_holder
#define DEBUG_PRINTF_LOCK_RELEASE   printf_lock_place_holder

// Dummy function when debug printf is disabled
void printf_place_holder(const char * __attribute__((aligned(8))) fmt, ...) {}
void printf_lock_place_holder(volatile int *lock) {}

/* Global spinlock aligned to 8 bytes to ensure correctness */
static volatile int printf_lock __attribute__((aligned(8))) __attribute__((section(".data"))) = 0;

/* Spinlock acquire/release helpers */
static inline void printf_lock_acquire(volatile int *lock);
static inline void printf_lock_release(volatile int *lock);

/* Initialize the printf lock */
void debug_print_lock_init(void);

/* Thread-safe debug print */
void debug_printf_locked(const char * __attribute__((aligned(8))) fmt, ...);

/* Read mcycle */
// size_t benchmark_get_cycle() { return read_csr(mcycle); }

/* A simple busy-loop delay function. Adjust iterations as needed. */
static void delay(volatile int iterations);

#endif // DEBUG_H
