// Copyright 2020 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
#include "team.h"
#include "cachepool_peripheral.h"
#include "snrt.h"
#include "snrt_bootinfo.h"

extern const uint32_t _snrt_cluster_cluster_core_num;
extern const uint32_t _snrt_cluster_cluster_base_hartid;
extern const uint32_t _snrt_cluster_cluster_id;
void *const _snrt_cluster_global_offset = (void *)0x10000000;

const uint32_t snrt_stack_size __attribute__((weak, section(".rodata"))) = 10;

// Layout of the boot data still resident in bootrom. Only `boot_addr` is
// genuinely dynamic (per test binary); all other fields are chip-wide
// constants and are taken from snrt_bootinfo.h instead, to avoid every core
// reading them from the shared bootrom. See `ip/test/src/tb_lib.hh`.
struct snrt_cluster_bootdata {
    uint32_t boot_addr;
    uint32_t core_count;
    uint32_t hartid_base;
    uint32_t tcdm_start;
    uint32_t tcdm_size;
    uint32_t tcdm_offset;
    uint64_t global_mem_start;
    uint64_t global_mem_end;
    uint32_t tile_count;
};

// Rudimentary string buffer for putc calls.
extern uint32_t _edram;
#define PUTC_BUFFER_LEN (1024 - sizeof(size_t))
struct putc_buffer_header {
    size_t size;
    uint64_t syscall_mem[8];
};
static volatile struct putc_buffer {
    struct putc_buffer_header hdr;
    char data[PUTC_BUFFER_LEN];
} *const putc_buffer = (void *)&_edram;

void _snrt_init_team(uint32_t cluster_core_id, uint32_t cluster_core_num,
                     void *spm_start, void *spm_end,
                     const struct snrt_cluster_bootdata *bootdata,
                     struct snrt_team_root *team) {
    (void)cluster_core_id;
    (void)bootdata;
    team->base.root = team;
    team->global_core_base_hartid = SNRT_BOOT_HARTID_BASE;
    team->global_core_num = SNRT_BOOT_CORE_COUNT;
    team->cluster_idx =
        (snrt_hartid() - SNRT_BOOT_HARTID_BASE) / SNRT_BOOT_CORE_COUNT;
    team->cluster_num = 0;
    team->cluster_core_base_hartid = SNRT_BOOT_HARTID_BASE;
    team->cluster_core_num = cluster_core_num;
    team->global_mem.start =
        (uint64_t)(SNRT_BOOT_GLOBAL_MEM_START + (uint32_t)_snrt_cluster_global_offset);
    team->global_mem.end = (uint64_t)SNRT_BOOT_GLOBAL_MEM_END;
    team->cluster_mem.start = (uint64_t)spm_start;
    team->cluster_mem.end = (uint64_t)spm_start + SNRT_BOOT_TCDM_SIZE;
    team->barrier_reg_ptr = (uint32_t)spm_start + SNRT_BOOT_TCDM_SIZE +
                            CACHEPOOL_PERIPHERAL_HW_BARRIER_REG_OFFSET;

    // Initialize cluster barrier
    team->cluster_barrier.barrier = 0;
    team->cluster_barrier.barrier_iteration = 0;

    // TLS caches of frequently used data
    _snrt_team_current = &team->base;
    _snrt_core_idx =
        (snrt_hartid() - _snrt_team_current->root->cluster_core_base_hartid) %
        _snrt_team_current->root->cluster_core_num;

    // Initialize the string buffer. This technically doesn't belong here, but
    // the _snrt_init_team function is called once per thread before main, so
    // it's as good a point as any.
    putc_buffer[snrt_hartid()].hdr.size = 0;


    // Init allocator
    snrt_alloc_init(team, sizeof(struct putc_buffer));
    snrt_int_init(team);
}
