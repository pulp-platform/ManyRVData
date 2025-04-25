#include <stdarg.h>
#include <stdint.h>
#include "printf.h"
#include "debug.h"

/* Global spinlock aligned to 8 bytes to ensure correctness */
static volatile int debug_lock __attribute__((aligned(8))) = 0;

/* Spinlock acquire/release helpers */
static inline void debug_lock_acquire(volatile int *lock) {
    while (__sync_lock_test_and_set(lock, 1)) { }
}

static inline void debug_lock_release(volatile int *lock) {
    asm volatile (
        "amoswap.w zero, zero, %0"
        : "+A" (*lock)
    );
 }


void debug_print_lock_init(void) {
    debug_lock = 0; // Optional: usually zero by default
}

/* Thread-safe debug print using global spinlock */
void debug_printf_locked(const char *fmt, ...) {
    debug_lock_acquire(&debug_lock);

    printf(fmt);

    debug_lock_release(&debug_lock);
}
