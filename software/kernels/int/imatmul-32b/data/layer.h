// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <stdint.h>

// C (M x N) = A (M x K) * B (K x N)
typedef struct imatmul_layer_struct {
  uint32_t M;
  uint32_t N;
  uint32_t K;
} imatmul_layer;
