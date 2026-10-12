// Copyright 2025 ETH Zurich and University of Bologna.
//
// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Author: Navaneeth Kunhi Purayil, ETH Zurich <nkunhi@iis.ee.ethz.ch>
// Author: Diyou Shen,              ETH Zurich <dishen@iis.ee.ethz.ch>

#ifndef _GEMV_H
#define _GEMV_H

#include <stdint.h>

// Controller-major layouts, see script/gen_data.py: a 256 B block per cache
// controller, one chunk of blocks per tile, 1 KiB per HBM channel slot.
#define GEMV_LINE_FLOATS  16
#define GEMV_CTRL_FLOATS  64
#define GEMV_CHUNK_FLOATS 256

inline void gemv_v32b(const float *a, const float *x, float *y,
                      const uint32_t N, const uint32_t lmul,
                      const uint32_t row)
    __attribute__((always_inline));

inline void gemv_v32b_m2(const float *a, const float *x, float *y,
                         const uint32_t N, const uint32_t row)
    __attribute__((always_inline));

#endif
