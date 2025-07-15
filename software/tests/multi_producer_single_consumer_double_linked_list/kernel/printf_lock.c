#include <stdarg.h>
#include <stdint.h>
#include <snrt.h>
#include "printf.h"
#include "printf_lock.h"

#define DEBUG_PRINTF 1 // Enable debug printf

/* Spinlock acquire/release helpers */
static inline void printf_lock_acquire(volatile int *lock) {
    while (__sync_lock_test_and_set(lock, 1)) { delay((snrt_cluster_core_idx()+1)*20); }
}

static inline void printf_lock_release(volatile int *lock) {
    asm volatile (
        "amoswap.w zero, zero, %0"
        : "+A" (*lock)
    );
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
