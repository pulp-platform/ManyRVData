# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Configs and kernel suffixes (without prefix)
CONFIGS="cachepool_fpu_4g"
KERNELS="fdotp-32b_M65536 gemv_M1024_N128_K32 fmatmul-32b_M1024_N32_K32 fft-32b_M1024_N16 "
PREFIX="test-cachepool-"  # common prefix for all kernels
ROOT_PATH=../..           # adjust if needed (path to repo root)
