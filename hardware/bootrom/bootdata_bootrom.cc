// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

#include <stdint.h>

// The boot data generated along with the system RTL.
struct BootData {
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

extern "C" const BootData BOOTDATA = {.boot_addr = 0x1000,
                           .core_count = 16,
                           .hartid_base = 0,
                           .tcdm_start = 0xbffff800,
                           .tcdm_size = 0x800,
                           .tcdm_offset = 0x0,
                           .global_mem_start = 0x80000000,
                           .global_mem_end = 0xa0000000,
                           .tile_count = 4};
