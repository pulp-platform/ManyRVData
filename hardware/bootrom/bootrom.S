# Copyright 2020 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

#include <cachepool_peripheral.h>
#include <snrt_bootinfo.h>

  .global _start
  .global BOOTDATA

_start:
  la      t1, exception
  csrw    mtvec, t1
  csrr    a0, mhartid
  la      a1, BOOTDATA

  // Enable MSI interrupt
  csrw mie, 0xF

  // Wait for the wakeup interrupt
  wfi

  // Peripheral base = TCDM start + TCDM size. These are chip-wide constants
  // fixed by the hardware config (see snrt_bootinfo.h), so we use immediates
  // here instead of reading BOOTDATA: every core in every group would
  // otherwise serialize on this read through the single shared bootrom.
  li      t2, (SNRT_BOOT_TCDM_START + SNRT_BOOT_TCDM_SIZE)

  // Find the entry point address
  addi    t2, t2, CACHEPOOL_PERIPHERAL_CLUSTER_BOOT_CONTROL_REG_OFFSET

  // Load the entry point. This one is genuinely dynamic (written once by
  // the testbench/host per test binary), so it cannot be a constant.
  lw      t2, 0(t2)

  // Jump to the entry point
  jr      t2

exception:
  wfi
  j     exception

.pushsection .boot_section,"aw",@progbits;
entry_addr:
  .word exception
