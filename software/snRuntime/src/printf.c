// Copyright 2020 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
#include "snrt.h"

#include <stdint.h>

extern char fake_uart;

void _putchar(char character) {
  // send char to console
  fake_uart = character;
}

void snrt_putchar(char character);

// Use snrt_putchar for printf
// #define _putchar snrt_putchar

/// vendor printf settings

#if defined(__TOOLCHAIN_GCC__)
// the gcc toolchain doesn't support this
#define PRINTF_DISABLE_SUPPORT_FLOAT
#endif

// Include the vendorized tiny printf implementation.
#include "../vendor/printf.c"

// Print a single-precision float as a decimal string without promoting to
// double. Passing a float through a variadic (...) argument promotes it to
// double per the C standard, generating fcvt.d.s / fsd which are illegal on
// rv32imaf. This wrapper takes the value as a named argument (no promotion)
// and keeps all arithmetic in single precision.
void snrt_printf_float(float val) {
    uint32_t bits;
    __builtin_memcpy(&bits, &val, sizeof(uint32_t));

    uint32_t exp  = (bits >> 23) & 0xFFU;
    uint32_t mant = bits & 0x7FFFFFU;

    if (exp == 0xFFU) {
        if (mant != 0U)
            printf("NaN");
        else
            printf("%sInf", (bits >> 31) ? "-" : "");
        return;
    }

    if (bits >> 31) {
        _putchar('-');
        val = -val;
    }

    uint32_t int_part  = (uint32_t)val;
    uint32_t frac_part = (uint32_t)((val - (float)int_part) * 1000000.0f);
    printf("%u.%06u", int_part, frac_part);
}
