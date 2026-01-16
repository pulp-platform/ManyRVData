// Copyright 2020 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
#include "team.h"

#include "snrt.h"

// TLS copy of frequently used data that doesn't change at runtime
__thread struct snrt_team *_snrt_team_current;
__thread uint32_t _snrt_core_idx;

// Bootdata layout (append-only extension). Must match BootROM bootdata layout.
struct snrt_cluster_bootdata {
    uint32_t boot_addr;
    uint32_t core_count;
    uint32_t hartid_base;
    uint32_t tcdm_start;
    uint32_t tcdm_size;
    uint32_t tcdm_offset;
    uint64_t global_mem_start;
    uint64_t global_mem_end;
    uint32_t tile_count;   // appended field
};

static inline const struct snrt_cluster_bootdata *_snrt_bootdata(void) {
    return (const struct snrt_cluster_bootdata *)_snrt_team_current->root->bootdata;
}

const uint32_t _snrt_team_size __attribute__((section(".rodata"))) =
    sizeof(struct snrt_team_root);

struct snrt_team_root *snrt_current_team() {
    return _snrt_team_current->root;
}

struct snrt_peripherals *snrt_peripherals() {
    return &_snrt_team_current->root->peripherals;
}

uint32_t snrt_global_core_base_hartid() {
    return _snrt_team_current->root->global_core_base_hartid;
}

uint32_t snrt_cluster_core_base_hartid() {
    return _snrt_team_current->root->cluster_core_base_hartid;
}

uint32_t snrt_global_core_idx() {
    return snrt_hartid() - _snrt_team_current->root->global_core_base_hartid;
}

uint32_t snrt_global_core_num() {
    return _snrt_team_current->root->global_core_num;
}

uint32_t snrt_cluster_idx() { return _snrt_team_current->root->cluster_idx; }

uint32_t snrt_cluster_num() { return _snrt_team_current->root->cluster_num; }

uint32_t snrt_cluster_tile_num() {
    uint32_t n = _snrt_bootdata()->tile_count;
    return n ? n : 1;
}

uint32_t snrt_cluster_tile_idx() {
    uint32_t tiles = snrt_cluster_tile_num();
    uint32_t cpt   = snrt_cluster_core_num() / tiles;
    return snrt_cluster_core_idx() / cpt;
}

uint32_t snrt_cluster_core_idx() { return _snrt_core_idx; }

uint32_t snrt_cluster_core_num() {
    return _snrt_team_current->root->cluster_core_num;
}

uint32_t snrt_cluster_compute_core_idx() {
    // TODO: Actually derive this from the device tree!
    return snrt_cluster_core_idx();
}

uint32_t snrt_cluster_compute_core_num() {
    // TODO: Actually derive this from the device tree!
    return snrt_cluster_core_num() - 1;
}

uint32_t snrt_cluster_dm_core_idx() {
    // TODO: Actually derive this from the device tree!
    return snrt_cluster_core_num() - 1;
}

uint32_t snrt_cluster_dm_core_num() {
    // TODO: Actually derive this from the device tree!
    return 1;
}

int snrt_is_compute_core() {
    // TODO: Actually derive this from the device tree!
    return snrt_cluster_core_idx() < snrt_cluster_core_num() - 1;
}

int snrt_is_dm_core() {
    // TODO: Actually derive this from the device tree!
    return !snrt_is_compute_core();
}

uint32_t _snrt_barrier_reg_ptr() {
    return _snrt_team_current->root->barrier_reg_ptr;
}

snrt_slice_t snrt_global_memory() {
    return _snrt_team_current->root->global_mem;
}

snrt_slice_t snrt_cluster_memory() {
    return _snrt_team_current->root->cluster_mem;
}

void snrt_wakeup(uint32_t mask) { *snrt_peripherals()->wakeup = mask; }
