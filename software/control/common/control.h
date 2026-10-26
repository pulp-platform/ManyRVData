// Copyright 2025 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Constants shared by the control-algorithm kernels; they must match
// common/golden.py (see ../README.md for why these values).

#ifndef CONTROL_H
#define CONTROL_H

#define CTRL_MIN_R (-4096)
#define CTRL_MAX_R 4096
#define CTRL_MIN_G 1
#define CTRL_MAX_G (1 << 20)
#define CTRL_G_SHIFT 7
#define CTRL_P_SCALE 100

// uv_matmul output modes
#define UV_MODE_U 0
#define UV_MODE_V 1
// out only, no clamped aux (the full kernel recomputes G where it is used)
#define UV_MODE_RAW 2

// e32 elements in one LMUL-4 register group (VLEN = 512)
#define UV_VLMAX 64

#endif
