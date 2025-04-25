#ifndef DEBUG_H
#define DEBUG_H

#include <stdio.h>
#include "printf.h"

/* Enable or disable debug printing */
#define DEBUG_PRINT_ENABLED 1

/* Raw printf protected by global spinlock */
void debug_print_lock_init(void);
void debug_printf_locked(const char *fmt, ...);

/* Simple macro wrapper */
#if DEBUG_PRINT_ENABLED
    #define debug_printf(...) debug_printf_locked(__VA_ARGS__)
#else
    #define debug_printf(...) ((void)0)
#endif

#endif // DEBUG_H
