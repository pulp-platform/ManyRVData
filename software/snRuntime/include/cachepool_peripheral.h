// Generated register defines for cachepool_peripheral

// Copyright information found in source file:
// Copyright 2020 ETH Zurich and University of Bologna.

// Licensing information found in source file:
// Licensed under Solderpad Hardware License, Version 0.51, see LICENSE for
// details. SPDX-License-Identifier: SHL-0.51

#ifndef _CACHEPOOL_PERIPHERAL_REG_DEFS_
#define _CACHEPOOL_PERIPHERAL_REG_DEFS_

#ifdef __cplusplus
extern "C" {
#endif
// Number of performance counters
#define CACHEPOOL_PERIPHERAL_PARAM_NUM_PERF_COUNTERS 2

// Register width
#define CACHEPOOL_PERIPHERAL_PARAM_REG_WIDTH 64

// Select from which hart in the cluster, starting from `0`,
#define CACHEPOOL_PERIPHERAL_HART_SELECT_HART_SELECT_FIELD_WIDTH 10
#define CACHEPOOL_PERIPHERAL_HART_SELECT_HART_SELECT_FIELDS_PER_REG 6
#define CACHEPOOL_PERIPHERAL_HART_SELECT_MULTIREG_COUNT 2

// Select from which hart in the cluster, starting from `0`,
#define CACHEPOOL_PERIPHERAL_HART_SELECT_0_REG_OFFSET 0x0
#define CACHEPOOL_PERIPHERAL_HART_SELECT_0_HART_SELECT_0_MASK 0x3ff
#define CACHEPOOL_PERIPHERAL_HART_SELECT_0_HART_SELECT_0_OFFSET 0
#define CACHEPOOL_PERIPHERAL_HART_SELECT_0_HART_SELECT_0_FIELD                 \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_HART_SELECT_0_HART_SELECT_0_MASK,           \
      .index = CACHEPOOL_PERIPHERAL_HART_SELECT_0_HART_SELECT_0_OFFSET})

// Select from which hart in the cluster, starting from `0`,
#define CACHEPOOL_PERIPHERAL_HART_SELECT_1_REG_OFFSET 0x8
#define CACHEPOOL_PERIPHERAL_HART_SELECT_1_HART_SELECT_1_MASK 0x3ff
#define CACHEPOOL_PERIPHERAL_HART_SELECT_1_HART_SELECT_1_OFFSET 0
#define CACHEPOOL_PERIPHERAL_HART_SELECT_1_HART_SELECT_1_FIELD                 \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_HART_SELECT_1_HART_SELECT_1_MASK,           \
      .index = CACHEPOOL_PERIPHERAL_HART_SELECT_1_HART_SELECT_1_OFFSET})

// Set bits in the cluster-local CLINT. Writing a 1 at location i sets the
// cluster-local interrupt
#define CACHEPOOL_PERIPHERAL_CL_CLINT_SET_REG_OFFSET 0x10
#define CACHEPOOL_PERIPHERAL_CL_CLINT_SET_CL_CLINT_SET_MASK 0xffffffff
#define CACHEPOOL_PERIPHERAL_CL_CLINT_SET_CL_CLINT_SET_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CL_CLINT_SET_CL_CLINT_SET_FIELD                   \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CL_CLINT_SET_CL_CLINT_SET_MASK,             \
      .index = CACHEPOOL_PERIPHERAL_CL_CLINT_SET_CL_CLINT_SET_OFFSET})

// Clear bits in the cluster-local CLINT. Writing a 1 at location i clears
// the cluster-local interrupt
#define CACHEPOOL_PERIPHERAL_CL_CLINT_CLEAR_REG_OFFSET 0x18
#define CACHEPOOL_PERIPHERAL_CL_CLINT_CLEAR_CL_CLINT_CLEAR_MASK 0xffffffff
#define CACHEPOOL_PERIPHERAL_CL_CLINT_CLEAR_CL_CLINT_CLEAR_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CL_CLINT_CLEAR_CL_CLINT_CLEAR_FIELD               \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CL_CLINT_CLEAR_CL_CLINT_CLEAR_MASK,         \
      .index = CACHEPOOL_PERIPHERAL_CL_CLINT_CLEAR_CL_CLINT_CLEAR_OFFSET})

// Hardware barrier register. Loads to this register will block until all
// cores have
#define CACHEPOOL_PERIPHERAL_HW_BARRIER_REG_OFFSET 0x20
#define CACHEPOOL_PERIPHERAL_HW_BARRIER_HW_BARRIER_MASK 0xffffffff
#define CACHEPOOL_PERIPHERAL_HW_BARRIER_HW_BARRIER_OFFSET 0
#define CACHEPOOL_PERIPHERAL_HW_BARRIER_HW_BARRIER_FIELD                       \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_HW_BARRIER_HW_BARRIER_MASK,                 \
      .index = CACHEPOOL_PERIPHERAL_HW_BARRIER_HW_BARRIER_OFFSET})

// Controls prefetching of the instruction cache.
#define CACHEPOOL_PERIPHERAL_ICACHE_PREFETCH_ENABLE_REG_OFFSET 0x28
#define CACHEPOOL_PERIPHERAL_ICACHE_PREFETCH_ENABLE_ICACHE_PREFETCH_ENABLE_BIT 0

// Sets the status of the Spatz cluster.
#define CACHEPOOL_PERIPHERAL_SPATZ_STATUS_REG_OFFSET 0x30
#define CACHEPOOL_PERIPHERAL_SPATZ_STATUS_SPATZ_CLUSTER_PROBE_BIT 0

// Store cycle counts of kernels
#define CACHEPOOL_PERIPHERAL_SPATZ_CYCLE_REG_OFFSET 0x38
#define CACHEPOOL_PERIPHERAL_SPATZ_CYCLE_SPATZ_CYC_MASK 0xffffffff
#define CACHEPOOL_PERIPHERAL_SPATZ_CYCLE_SPATZ_CYC_OFFSET 0
#define CACHEPOOL_PERIPHERAL_SPATZ_CYCLE_SPATZ_CYC_FIELD                       \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_SPATZ_CYCLE_SPATZ_CYC_MASK,                 \
      .index = CACHEPOOL_PERIPHERAL_SPATZ_CYCLE_SPATZ_CYC_OFFSET})

// Controls the cluster boot process.
#define CACHEPOOL_PERIPHERAL_CLUSTER_BOOT_CONTROL_REG_OFFSET 0x40
#define CACHEPOOL_PERIPHERAL_CLUSTER_BOOT_CONTROL_ENTRY_POINT_MASK 0xffffffff
#define CACHEPOOL_PERIPHERAL_CLUSTER_BOOT_CONTROL_ENTRY_POINT_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CLUSTER_BOOT_CONTROL_ENTRY_POINT_FIELD            \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CLUSTER_BOOT_CONTROL_ENTRY_POINT_MASK,      \
      .index = CACHEPOOL_PERIPHERAL_CLUSTER_BOOT_CONTROL_ENTRY_POINT_OFFSET})

// End of computation and exit status register
#define CACHEPOOL_PERIPHERAL_CLUSTER_EOC_EXIT_REG_OFFSET 0x48
#define CACHEPOOL_PERIPHERAL_CLUSTER_EOC_EXIT_EOC_EXIT_BIT 0

// Controls the configurations of L1 DCache SPM size.
#define CACHEPOOL_PERIPHERAL_CFG_L1D_SPM_REG_OFFSET 0x50
#define CACHEPOOL_PERIPHERAL_CFG_L1D_SPM_SPM_SIZE_MASK 0x3ff
#define CACHEPOOL_PERIPHERAL_CFG_L1D_SPM_SPM_SIZE_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_L1D_SPM_SPM_SIZE_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_L1D_SPM_SPM_SIZE_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_L1D_SPM_SPM_SIZE_OFFSET})

// Controls the L1 DCache flushing and invalidation.
#define CACHEPOOL_PERIPHERAL_CFG_L1D_INSN_REG_OFFSET 0x58
#define CACHEPOOL_PERIPHERAL_CFG_L1D_INSN_INSN_MASK 0x3
#define CACHEPOOL_PERIPHERAL_CFG_L1D_INSN_INSN_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_L1D_INSN_INSN_FIELD                           \
  ((bitfield_field32_t){.mask = CACHEPOOL_PERIPHERAL_CFG_L1D_INSN_INSN_MASK,   \
                        .index =                                               \
                            CACHEPOOL_PERIPHERAL_CFG_L1D_INSN_INSN_OFFSET})

// Controls the L1 DCache flushing and invalidation.
#define CACHEPOOL_PERIPHERAL_L1D_SPM_COMMIT_REG_OFFSET 0x60
#define CACHEPOOL_PERIPHERAL_L1D_SPM_COMMIT_COMMIT_BIT 0

// Controls the L1 DCache flushing and invalidation.
#define CACHEPOOL_PERIPHERAL_L1D_INSN_COMMIT_REG_OFFSET 0x68
#define CACHEPOOL_PERIPHERAL_L1D_INSN_COMMIT_COMMIT_BIT 0

// Indicate the status of flushing
#define CACHEPOOL_PERIPHERAL_L1D_FLUSH_STATUS_REG_OFFSET 0x70
#define CACHEPOOL_PERIPHERAL_L1D_FLUSH_STATUS_STATUS_BIT 0

// Cache xbar offset setting
#define CACHEPOOL_PERIPHERAL_XBAR_OFFSET_REG_OFFSET 0x78
#define CACHEPOOL_PERIPHERAL_XBAR_OFFSET_OFFSET_MASK 0x1f
#define CACHEPOOL_PERIPHERAL_XBAR_OFFSET_OFFSET_OFFSET 0
#define CACHEPOOL_PERIPHERAL_XBAR_OFFSET_OFFSET_FIELD                          \
  ((bitfield_field32_t){.mask = CACHEPOOL_PERIPHERAL_XBAR_OFFSET_OFFSET_MASK,  \
                        .index =                                               \
                            CACHEPOOL_PERIPHERAL_XBAR_OFFSET_OFFSET_OFFSET})

// Cache xbar offset setting
#define CACHEPOOL_PERIPHERAL_XBAR_OFFSET_COMMIT_REG_OFFSET 0x80
#define CACHEPOOL_PERIPHERAL_XBAR_OFFSET_COMMIT_COMMIT_BIT 0

#ifdef __cplusplus
} // extern "C"
#endif
#endif // _CACHEPOOL_PERIPHERAL_REG_DEFS_
       // End generated register defines for cachepool_peripheral