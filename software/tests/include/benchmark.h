// Copyright 2020 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <snrt.h>
#include <stddef.h>
#include <l1cache.h>
#include "printf.h"

inline size_t benchmark_get_cycle() { return read_csr(mcycle); }

void start_kernel();
void stop_kernel();
size_t get_perf();
void write_cyc(uint32_t cyc);
static inline void cachepool_wait (uint32_t cycle) {
  if(cycle > 0) {
    size_t start = benchmark_get_cycle();
    while ((benchmark_get_cycle() - start) < cycle) {
      // busy wait
    }
  }
}