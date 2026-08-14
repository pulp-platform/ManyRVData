# Copyright 2020 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

#include "../../start.S"
#include "snrt_bootinfo.h"

# Function to determine the initial cluster layout to setup the initial stack.
# The fields below are chip-wide constants fixed by the hardware config (see
# snrt_bootinfo.h), so they are compiled in as immediates instead of being
# read from BOOTDATA in the shared bootrom: every core in every group would
# otherwise serialize on those reads through the single shared bootrom port.
#
# Expecting:
# - a0: mhartid
# - a1: device tree ptr ("bootdata" in `tb_lib.hh`), preserved into a4 for
#       the caller, no longer dereferenced here
_snrt_init_core_info:
    .globl _snrt_init_core_info
    mv        a4, a1
    li        a1, SNRT_BOOT_CORE_COUNT   # number of cores per cluster
    li        t0, SNRT_BOOT_HARTID_BASE  # cluster's hartid offset
    li        a2, SNRT_BOOT_TCDM_START   # start address of the TCDM
    li        t1, SNRT_BOOT_TCDM_SIZE    # size of TCDM address space
    li        t2, SNRT_BOOT_TCDM_OFFSET  # offset between cluster TCDMs
    sub       a0, a0, t0
    div       t3, a0, a1 # calculate cluster index
    mul       t4, t3, t2 # calculate cluster TCDM offset
    add       a2, a2, t4 # start address of current cluster TCDM
    add       a3, a2, t1 # end address of current cluster TCDM
    remu      a0, a0, a1 # calculate cluster-local core id
    ret

# Must leave a0 untouched.
_snrt_cluster_barrier:
    .globl _snrt_cluster_barrier
    addi      sp, sp, -4
    sw        ra, 0(sp)
    call      _snrt_barrier_reg_ptr
    lw        a0, 0(a0)
    mv        zero, a0
    lw        ra, 0(sp)
    addi      sp, sp, 4
    ret

# Mustn't use any non-temporary registers
# Expecting:
# - a0: device tree ptr ("bootdata" in `tb_lib.hh`), unused -- hartid_base is
#       a chip-wide constant, see snrt_bootinfo.h
# a0 = hartid_base
_snrt_get_base_hartid:
    .globl _snrt_get_base_hartid
    li        a0, SNRT_BOOT_HARTID_BASE
    ret
