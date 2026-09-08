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

/* Phase barrier for the RLC TTI loops, downlink and uplink.
 
   **snrt_cluster_partial_barrier() synchronises execution, not memory.** Its
   whole implementation is one plain store to the barrier register:
 
     void snrt_cluster_partial_barrier(uint32_t local_mask) {
         *(volatile uint32_t *)_snrt_barrier_reg_ptr() = local_mask;
     }
 
   It makes the participating cores wait for one another, and that is all. It
   issues no fence, so a write made before it is not guaranteed visible to
   another core after it. The name invites exactly the wrong assumption, and
   the uplink proved the consequence on real hardware: a value one core stored
   and another core loaded, with a barrier in between, disagreed -- both the
   store and the load provably executed.
 
   Every RLC phase boundary is a producer/consumer handoff of shared memory:
 
     DL  plan  -> execute :  the owner writes ~7 KB of plan (header lengths,
                             segment lengths, source pointers, n_avail,
                             tb_used) and every helper then reads it to copy
                             payload. Stale lengths or offsets here corrupt
                             the transport block silently.
     DL  execute -> commit:  helpers write payload, the owner then accounts it.
     UL  scan  -> reassemble: consumer 0 writes the scan buffer, the others
                             read it.
 
   So fence on both sides: release what this phase wrote, then acquire what
   the others wrote. Cost is two fences per boundary against a whole phase of
   work -- irrelevant next to a silently wrong transport block. */

#ifndef RLC_SYNC_H
#define RLC_SYNC_H

#include <stdint.h>
#include <snrt.h>

static inline void rlc_phase_barrier(uint32_t local_mask) {
  asm volatile("fence" ::: "memory"); /* publish this phase's writes */
  snrt_cluster_partial_barrier(local_mask);
  asm volatile("fence" ::: "memory"); /* observe the other cores' writes */
}

#endif /* RLC_SYNC_H */
