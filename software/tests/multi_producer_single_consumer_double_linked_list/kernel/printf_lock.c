#include <stdarg.h>
#include <stdint.h>
#include "printf.h"
#include "printf_lock.h"

/* Spinlock acquire/release helpers */
static inline void printf_lock_acquire(volatile int *lock) {
    while (__sync_lock_test_and_set(lock, 1)) { }
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

// /* Thread-safe debug print using global spinlock */
// void debug_printf_locked(const char *fmt, ...) {
//     printf_lock_acquire(&printf_lock);

//     printf(fmt);

//     printf_lock_release(&printf_lock);
// }
