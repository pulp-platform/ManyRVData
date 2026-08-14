// Copyright 2020 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "snrt.h"

extern __thread struct snrt_team *_snrt_team_current;
extern __thread uint32_t _snrt_core_idx;
extern const uint32_t _snrt_team_size;

struct snrt_team {
    /// Pointer to the root team description of this cluster.
    struct snrt_team_root *root;
};

struct snrt_allocator_inst {
    // Base address from where allocation starts
    uint32_t base;
    // Number of bytes alloctable
    uint32_t size;
    // Address of the next allocated block
    uint32_t next;
};
struct snrt_allocator {
    struct snrt_allocator_inst l1;
};

// DRAM heap block header — padded to exactly one cacheline (64 bytes) so that
// every header and every payload starts on a cacheline boundary.
#define SNRT_CACHELINE_SIZE 64
typedef struct snrt_alloc_block {
    uint32_t size;                  // payload size in bytes (multiple of SNRT_CACHELINE_SIZE)
    uint32_t free;                  // 1 = free, 0 = allocated
    struct snrt_alloc_block *next;  // next block in list (NULL = end of heap)
    uint8_t  _pad[52];              // pad to SNRT_CACHELINE_SIZE (64 - 12 = 52 bytes)
} snrt_alloc_block_t;

// This struct is placed at the end of each clusters TCDM
struct snrt_team_root {
    struct snrt_team base;
    uint32_t global_core_base_hartid;
    uint32_t global_core_num;
    uint32_t cluster_idx;
    uint32_t cluster_num;
    uint32_t cluster_core_base_hartid;
    uint32_t cluster_core_num;
    snrt_slice_t global_mem;
    snrt_slice_t cluster_mem;
    struct snrt_allocator allocator;
    struct snrt_barrier cluster_barrier;
    uint32_t barrier_reg_ptr;
    uint32_t barrier_participation_mask_reg_ptr;
    struct snrt_peripherals peripherals;
};
