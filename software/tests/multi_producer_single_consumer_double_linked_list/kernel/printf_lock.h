#ifndef DEBUG_H
#define DEBUG_H

#include <stdio.h>
#include "printf.h"
#include "encoding.h"

/* Global spinlock aligned to 8 bytes to ensure correctness */
static volatile int printf_lock __attribute__((aligned(8))) = 0;

/* Raw printf protected by global spinlock */
void debug_print_lock_init(void);

size_t benchmark_get_cycle() { return read_csr(mcycle); }

#endif // DEBUG_H
