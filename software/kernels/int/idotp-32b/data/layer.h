// Copyright 2020 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <stdint.h>

typedef enum { INT64 = 8, INT32 = 4, INT16 = 2, INT8 = 1 } precision_t;


/**
 * @struct dotp_layer_struct
 * @brief This structure contains all parameters necessary for DOTP
 * layers
 * @var dotp_layer_struct::M
 * Length of the vectors
 * @var gemm_layer_struct::dtype
 * Precision of Convolution layer
 */
typedef struct dotp_layer_struct {
  // DOTP
  uint32_t M;

  precision_t dtype;
} dotp_layer;
