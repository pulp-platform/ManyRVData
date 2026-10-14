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
 
   **A hardware barrier synchronises execution, not memory.** A partial
   barrier is one plain store to the barrier register:
 
     *(volatile uint32_t *)_snrt_barrier_reg_ptr() = payload;
 
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
#include "cachepool_peripheral.h"

/* ------------------------------------------------------------------------ */
/* Consumer-only barrier on its own hardware slot                            */
/* ------------------------------------------------------------------------ */

/* The phase barrier runs on a dedicated barrier slot. Slot 0 belongs to the
   full-cluster barrier (snrt_cluster_hw_barrier) and, on dual-scalar builds,
   slot 1 to the host barriers; every slot has its own tile/group/cluster
   round tracker and its own release, so the consumers' rounds never mix with
   the full barrier the other cores are waiting in. Non-participants therefore
   simply proceed to snrt_cluster_hw_barrier(). */
#if SNRT_HOST_BARRIER_SLOT == 1
#define RLC_BARRIER_SLOT 2u
#else
#define RLC_BARRIER_SLOT 1u
#endif

#if RLC_BARRIER_SLOT >= CACHEPOOL_PERIPHERAL_PARAM_NUM_BARRIER_SLOTS
#error "RLC phase barrier needs a free barrier slot: raise NumBarrierSlots"
#endif

/* Everything one barrier round needs; identical on every core of a tile, and
   the tile mask identical on every tile of a group, which is what the
   tile/group trackers latch and compare. */
typedef struct {
  uint32_t core_mask;   /* participants in my tile                         */
  uint32_t tile_mask;   /* participating tiles of my group (group-relative) */
  uint32_t local_only;  /* 1: the round resolves without the cluster level  */
  uint32_t group_mask;  /* participating groups (cluster-level, per slot)   */
} rlc_bar_t;

/* Derive the descriptor for the calling core from the participant list. */
static inline rlc_bar_t rlc_bar_describe(const unsigned int *cids, uint32_t n) {
  const uint32_t cpt = snrt_cluster_core_per_tile();
  const uint32_t ngrp = snrt_cluster_group_num();
  const uint32_t tpg = snrt_cluster_tile_num() / ngrp;
  const uint32_t my_tile = snrt_cluster_tile_idx();
  const uint32_t my_grp = my_tile / tpg;
  rlc_bar_t b = {0u, 0u, 1u, 0u};
  for (uint32_t i = 0u; i < n; i++) {
    const uint32_t t = cids[i] / cpt;
    const uint32_t g = t / tpg;
    b.group_mask |= 1u << g;
    if (g == my_grp) b.tile_mask |= 1u << (t % tpg);
    if (t == my_tile) b.core_mask |= 1u << (cids[i] % cpt);
  }
  if (b.group_mask & (b.group_mask - 1u)) {
    b.local_only = 0u;                     /* several groups: via the cluster */
  } else if (b.tile_mask == (1u << (my_tile % tpg))) {
    b.tile_mask = SNRT_BARRIER_TILE_MASK_SELF; /* one tile: never leaves it   */
  }
  return b;
}

/* Called once, by one core, before the startup snrt_cluster_hw_barrier(),
   which is the resync point the API asks for. Programming slot RLC_BARRIER_SLOT
   cannot disturb that barrier: it runs on slot 0. Only needed when the round
   crosses groups and not every group takes part (the register resets to all
   groups). */
static inline void rlc_bar_init(const unsigned int *cids, uint32_t n) {
  const rlc_bar_t b = rlc_bar_describe(cids, n);
  const uint32_t ngrp = snrt_cluster_group_num();
  const uint32_t all = (ngrp >= 32u) ? 0xffffffffu : ((1u << ngrp) - 1u);
  if (!b.local_only && b.group_mask != all)
    snrt_barrier_set_group_mask(RLC_BARRIER_SLOT, b.group_mask);
}

static inline void rlc_phase_barrier(const rlc_bar_t *b) {
  asm volatile("fence" ::: "memory"); /* publish this phase's writes */
  snrt_cluster_group_barrier(b->core_mask, b->tile_mask, (int)b->local_only,
                             RLC_BARRIER_SLOT);
  asm volatile("fence" ::: "memory"); /* observe the other cores' writes */
}

#endif /* RLC_SYNC_H */
