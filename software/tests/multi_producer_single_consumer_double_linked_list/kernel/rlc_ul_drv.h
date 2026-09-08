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

// Author: Zexin Fu     <zexifu@iis.ee.ethz.ch>

/* Target-side uplink driver entry points. Declared separately from the
   implementation (rlc_ul_drv.c) because rlc_init() must call rlc_ul_init()
   and is defined earlier in the same translation unit. */

#ifndef RLC_UL_DRV_H
#define RLC_UL_DRV_H

#include <stdint.h>

/* MUST be called from exactly one core, from rlc_init(), i.e. BEFORE main.c's
   startup snrt_cluster_hw_barrier(). It programs the cluster tile
   participation mask, and that barrier is the resync point the partial-barrier
   API requires before the mask can be relied on. Doing it later -- lazily on
   entry to rlc_ul_consumer() -- leaves the phase barriers unprogrammed. */
void rlc_ul_init(void);

/* Uplink consumer entry point: receive/reassemble/deliver slots. */
void rlc_ul_consumer(uint32_t core_id);

#endif /* RLC_UL_DRV_H */
