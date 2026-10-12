// Copyright 2025 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0 

#pragma once

#include <stdint.h>

typedef enum { FP64 = 8, FP32 = 4, FP16 = 2, FP8 = 1 } precision_t;

// hot: controller-major layout over all HBM channels, A stays in L1
// cold: controller-major layout, each group on its own HBM channel
typedef enum { GEMV_MODE_HOT = 0, GEMV_MODE_COLD = 1 } gemv_mode_t;

typedef struct gemv_layer_struct {
    uint32_t M;
    uint32_t N;
  
    precision_t dtype;

    // Active groups and LMUL
    uint32_t groups;
    uint32_t lmul;

    // Layout mode, and the HBM channels the cold layout was generated for
    gemv_mode_t mode;
    uint32_t channels;

    // Cluster shape the layout was generated for
    uint32_t cores_per_tile;
    uint32_t tiles_per_group;
  } gemv_layer;