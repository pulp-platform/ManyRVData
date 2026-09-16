// Copyright 2020 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
#include "snrt.h"
#include "team.h"

extern void _snrt_cluster_barrier();

/// Synchronize cores in a cluster with a hardware barrier
void snrt_cluster_hw_barrier() { _snrt_cluster_barrier(); }

/// Program the cluster-level group-participation mask for the given barrier
/// slot (HW_BARRIER_PARTICIPATION_MASK, one 32b register per slot).
void snrt_barrier_set_group_mask(uint32_t barrier_id, uint32_t mask) {
    volatile uint32_t *reg =
        (volatile uint32_t *)(_snrt_barrier_participation_mask_reg_ptr()
                               + barrier_id * sizeof(uint32_t));
    *reg = mask;
}

/// Compute the calling core's tile-local participant mask from a fixed
/// list of global core ids. cids that don't belong to this core's own tile
/// are ignored, since they participate in a different tile's barrier
/// instance. O(n); intended to be called once and the result cached.
uint32_t snrt_cluster_partial_barrier_mask(const uint32_t *cids, uint32_t n) {
    uint32_t cpt = snrt_cluster_core_per_tile();
    uint32_t my_tile = snrt_cluster_tile_idx();
    uint32_t mask = 0;
    for (uint32_t i = 0; i < n; i++) {
        if (cids[i] / cpt == my_tile) {
            mask |= 1u << (cids[i] % cpt);
        }
    }
    return mask;
}

/// Issue a partial hardware barrier restricted to local_mask. Tile mask and
/// local_only are left at their safe defaults (every tile in the group,
/// cluster-wide), matching snrt_cluster_hw_barrier()'s scope beyond the
/// core mask. Always uses slot 0 (reserved for the legacy/host0/host1
/// barriers, see snrt.h). A plain volatile store (unlike the read-based
/// full barrier, a write is never elided by the compiler regardless of
/// whether its result is used).
void snrt_cluster_partial_barrier(uint32_t local_mask) {
    uint32_t payload = local_mask
                        | (SNRT_BARRIER_TILE_MASK_ALL << SNRT_BARRIER_TILE_MASK_LSB);
    *(volatile uint32_t *)_snrt_barrier_reg_ptr() = payload;
}

/// Issue a barrier restricted to core_mask/tile_mask on the given barrier
/// slot, optionally staying local to the group (see snrt.h for the full
/// contract).
void snrt_cluster_group_barrier(uint32_t core_mask, uint32_t tile_mask,
                                 int local_only, uint32_t barrier_id) {
    uint32_t payload = core_mask
                        | (tile_mask << SNRT_BARRIER_TILE_MASK_LSB)
                        | ((local_only ? 1u : 0u) << SNRT_BARRIER_LOCAL_ONLY_BIT)
                        | (barrier_id << SNRT_BARRIER_ID_LSB);
    *(volatile uint32_t *)_snrt_barrier_reg_ptr() = payload;
}

/// Tile-local mask of every hart whose parity matches want_primary (host 0
/// positions if 1, host 1 positions if 0), given sequential host0/host1
/// pairing; with no pairing at all, every hart counts as host 0.
static uint32_t snrt_cc_role_mask(int want_primary) {
    uint32_t cpt = snrt_cluster_core_per_tile();
    uint32_t mask = 0;
#if SNRT_NUM_SCALAR_PER_CORE == 2
    for (uint32_t i = (want_primary ? 0 : 1); i < cpt; i += 2) mask |= (1u << i);
#else
    if (want_primary) for (uint32_t i = 0; i < cpt; i++) mask |= (1u << i);
#endif
    return mask;
}

void snrt_cluster_host0_barrier() {
    if (!snrt_cluster_is_primary()) return;
    snrt_cluster_partial_barrier(snrt_cc_role_mask(1));
}

void snrt_cluster_host1_barrier() {
    if (snrt_cluster_is_primary()) return;
    snrt_cluster_partial_barrier(snrt_cc_role_mask(0));
}

/// Synchronize cores in a cluster with a software barrier
void snrt_cluster_sw_barrier() {
    // Remember previous iteration
    volatile struct snrt_barrier *barrier_ptr =
        &_snrt_team_current->root->cluster_barrier;
    uint32_t prev_barrier_iteration = barrier_ptr->barrier_iteration;
    uint32_t barrier =
        __atomic_add_fetch(&barrier_ptr->barrier, 1, __ATOMIC_RELAXED);

    // Increment the barrier counter
    if (barrier == snrt_cluster_core_num()) {
        barrier_ptr->barrier = 0;
        __atomic_add_fetch(&barrier_ptr->barrier_iteration, 1,
                           __ATOMIC_RELAXED);
    } else {
        // Some threads have not reached the barrier --> Let's wait
        while (prev_barrier_iteration == barrier_ptr->barrier_iteration)
            ;
    }
}

static volatile struct snrt_barrier global_barrier
    __attribute__((section(".dram")));

/// Synchronize clusters globally with a global software barrier
void snrt_global_barrier() {
    // Remember previous iteration
    volatile struct snrt_barrier *barrier_ptr = &global_barrier;
    uint32_t prev_barrier_iteration = barrier_ptr->barrier_iteration;
    uint32_t barrier =
        __atomic_add_fetch(&barrier_ptr->barrier, 1, __ATOMIC_RELAXED);

    // Increment the barrier counter
    if (barrier == snrt_global_core_num()) {
        barrier_ptr->barrier = 0;
        __atomic_add_fetch(&barrier_ptr->barrier_iteration, 1,
                           __ATOMIC_RELAXED);
    } else {
        // Some threads have not reached the barrier --> Let's wait
        while (prev_barrier_iteration == barrier_ptr->barrier_iteration)
            ;
    }
}

/**
 * @brief Generic barrier
 *
 * @param barr pointer to a barrier
 * @param n number of harts that have to enter before released
 */
void snrt_barrier(struct snrt_barrier *barr, uint32_t n) {
    // Remember previous iteration
    uint32_t prev_it = barr->barrier_iteration;
    uint32_t barrier = __atomic_add_fetch(&barr->barrier, 1, __ATOMIC_RELAXED);

    // Increment the barrier counter
    if (barrier == n) {
        barr->barrier = 0;
        __atomic_add_fetch(&barr->barrier_iteration, 1, __ATOMIC_RELAXED);
    } else {
        // Some threads have not reached the barrier --> Let's wait
        while (prev_it == barr->barrier_iteration)
            ;
    }
}
