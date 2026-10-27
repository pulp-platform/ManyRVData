// Copyright 2022 ETH Zurich and University of Bologna.
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

// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Author: Diyou Shen     <dishen@iis.ee.ethz.ch>

#ifndef _FDOTPROD_H_
#define _FDOTPROD_H_

#include <stdint.h>

// In-vector reduction of the accumulator (FDOTP_VRED):
// 0: one vfredusum over the whole accumulator
// 1: fold to LMUL 1 with vfadd, then vfredusum
// 2: fold to one element with vfadd and vslidedown
#define FDOTP_VRED_FULL  0
#define FDOTP_VRED_FOLD  1
#define FDOTP_VRED_SLIDE 2

float fdotp_v32b(const float *a, const float *b, const uint32_t vl,
                 const uint32_t offset, const uint32_t rounds,
                 const uint32_t lmul, const uint32_t unroll,
                 const uint32_t vred);

#endif
