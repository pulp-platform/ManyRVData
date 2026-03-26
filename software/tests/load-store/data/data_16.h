// Copyright 2022 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "layer.h"

const gemm_layer gemm_l = {
	.M = 262144,
	.N = 16,
	.K = 16,
	.TA = 0,
	.TB = 0,
	.ALPHA = 0,
	.expand = 0
};


static uint32_t gemm_A_dram [262144]  __attribute__((section(".pdcp_src")))  = { [0 ... 262143] = 1 };
static uint32_t gemm_B_dram [262144]  __attribute__((section(".pdcp_src")))  = { [0 ... 262143] = 2 };
static uint32_t gemm_C_dram [262144]  __attribute__((section(".pdcp_src")))  = { [0 ... 262143] = 3 };
static uint32_t gemm_D_dram [262144]  __attribute__((section(".data")))  = { [0 ... 262143] = 4 };
