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

/* ------------------------------------------------------------------------ */
/* Narrowed-barrier region                                                   */
/* ------------------------------------------------------------------------ */

/* Using a partial barrier safely takes more than programming the mask. Three
   properties of the hardware constrain it -- see
   reports/design_notes/PARTIAL_BARRIER_MISUSE.md:
 
   1. The cluster tile mask is PERSISTENT and gates every round, full barriers
      included: `mask_d = barrier_mask_i` is re-read at each round start and
      there is no full-vs-partial distinction at the cluster level. So a mask
      left narrowed breaks every later snrt_cluster_hw_barrier().
 
   2. At tile level, WHICHEVER REQUEST ARRIVES FIRST owns the round --
      `core_mask_d = req_mask[first_hit_idx]`, where a read means "all cores"
      and a write means "this mask". Mixing the two inside one tile races, and
      the two directions give opposite symptoms: a partial barrier absorbed
      into an all-cores round hangs, a full barrier absorbed into a
      participants-only round releases early.
 
   3. `barrier_done_o` is a SINGLE UNMASKED BROADCAST. The mask gates who must
      arrive, not who is released, so any partial-barrier completion frees
      every core waiting at a barrier anywhere in the cluster. This is why
      non-participants cannot simply be moved to another tile, and why they
      have to stay out of the barrier entirely rather than wait in one.
 
   Hence: arm here rather than at init (arming before main's startup barrier
   would break that barrier), publish it with a flag rather than a barrier
   (the participants cannot resync on the barrier they are narrowing), keep
   non-participants spinning outside, and restore the mask before anyone
   reaches a full barrier again. */

#define RLC_MASK_RESVAL 0xFFFFFFFFu

static _Atomic uint32_t rlc_narrow_armed;   /* mask programmed; partials legal */
static _Atomic uint32_t rlc_narrow_done;    /* region over; mask restored      */
static uint32_t rlc_narrow_probe;           /* pre-write read of the register  */
static uint32_t rlc_narrow_readback;        /* post-write read               */

/* Bounded pause between polls. Only cores with no work spin -- participants
   still block on a real barrier -- but idle cores polling a shared line at
   full rate is pointless memory traffic. */
static inline void rlc_narrow_pause(void) {
  for (volatile int i = 0; i < 64; i++) { }
}

/* Enter the narrowed region. `first` must be true on exactly one participant.
   Returns nothing; rlc_narrow_ok() reports whether the register agreed. */
static inline void rlc_narrow_enter(uint32_t tm_lo, uint32_t tm_hi, int first) {
  if (first) {
    volatile uint32_t *reg =
        (volatile uint32_t *)_snrt_barrier_participation_mask_reg_ptr();
    /* Pre-write probe: the mask register resets to RESVAL 0xFFFFFFFF, while
       everything else that could sit at this offset under a wrong peripheral
       map resets to 0. Read-back alone cannot tell them apart -- any RW
       scratch accepts a write and returns it. */
    rlc_narrow_probe = reg[0];
    snrt_barrier_set_tile_mask(tm_lo, tm_hi);
    asm volatile("fence" ::: "memory");
    rlc_narrow_readback = reg[0];
    atomic_store_explicit(&rlc_narrow_armed, 1u, memory_order_release);
    asm volatile("fence" ::: "memory");
  } else {
    while (!atomic_load_explicit(&rlc_narrow_armed, memory_order_acquire))
      rlc_narrow_pause();
    asm volatile("fence" ::: "memory");
  }
}

/* Leave the narrowed region: restore the mask, then release the cores waiting
   outside. Order matters -- a non-participant released before the restore
   would enter a still-narrowed barrier. */
static inline void rlc_narrow_exit(int first) {
  if (first) {
    snrt_barrier_set_tile_mask(RLC_MASK_RESVAL, RLC_MASK_RESVAL);
    asm volatile("fence" ::: "memory");
    atomic_store_explicit(&rlc_narrow_done, 1u, memory_order_release);
    asm volatile("fence" ::: "memory");
  }
}

/* Non-participants: wait OUTSIDE any barrier until the region is over. */
static inline void rlc_narrow_wait_outside(void) {
  while (!atomic_load_explicit(&rlc_narrow_done, memory_order_acquire))
    rlc_narrow_pause();
  asm volatile("fence" ::: "memory");
}

/* True when the participation-mask register behaved like the mask register:
   reset signature seen before the write, and the write read back. */
static inline int rlc_narrow_ok(uint32_t tm_lo) {
  return (rlc_narrow_probe == RLC_MASK_RESVAL) && (rlc_narrow_readback == tm_lo);
}

#endif /* RLC_SYNC_H */
