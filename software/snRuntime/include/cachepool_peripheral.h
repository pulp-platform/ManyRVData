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
// Number of 32-bit tile-select registers. Default 2 covers up to 64 tiles
// (16 groups x 4 tiles).
#define CACHEPOOL_PERIPHERAL_PARAM_NUM_TILE_SEL_REGS 2

// Number of per-core LP1 (private-L1) CMO register slots -- one per core /
#define CACHEPOOL_PERIPHERAL_PARAM_NUM_LP1_CMO_REGS 64

// Register width
#define CACHEPOOL_PERIPHERAL_PARAM_REG_WIDTH 32

// Hardware barrier register. Loads to this register will block until all
// cores have
#define CACHEPOOL_PERIPHERAL_HW_BARRIER_REG_OFFSET 0x0

// Controls prefetching of the instruction cache.
#define CACHEPOOL_PERIPHERAL_ICACHE_PREFETCH_ENABLE_REG_OFFSET 0x4
#define CACHEPOOL_PERIPHERAL_ICACHE_PREFETCH_ENABLE_ICACHE_PREFETCH_ENABLE_BIT 0

// Sets the status of the Spatz cluster.
#define CACHEPOOL_PERIPHERAL_SPATZ_STATUS_REG_OFFSET 0x8
#define CACHEPOOL_PERIPHERAL_SPATZ_STATUS_SPATZ_CLUSTER_PROBE_BIT 0

// Store cycle counts of kernels
#define CACHEPOOL_PERIPHERAL_SPATZ_CYCLE_REG_OFFSET 0xc

// Controls the cluster boot process.
#define CACHEPOOL_PERIPHERAL_CLUSTER_BOOT_CONTROL_REG_OFFSET 0x10

// End of computation and exit status register
#define CACHEPOOL_PERIPHERAL_CLUSTER_EOC_EXIT_REG_OFFSET 0x14
#define CACHEPOOL_PERIPHERAL_CLUSTER_EOC_EXIT_EOC_EXIT_MASK 0xf
#define CACHEPOOL_PERIPHERAL_CLUSTER_EOC_EXIT_EOC_EXIT_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CLUSTER_EOC_EXIT_EOC_EXIT_FIELD                   \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CLUSTER_EOC_EXIT_EOC_EXIT_MASK,             \
      .index = CACHEPOOL_PERIPHERAL_CLUSTER_EOC_EXIT_EOC_EXIT_OFFSET})

// Controls the configurations of L1 DCache SPM size.
#define CACHEPOOL_PERIPHERAL_CFG_L1D_SPM_REG_OFFSET 0x18
#define CACHEPOOL_PERIPHERAL_CFG_L1D_SPM_SPM_SIZE_MASK 0x3ff
#define CACHEPOOL_PERIPHERAL_CFG_L1D_SPM_SPM_SIZE_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_L1D_SPM_SPM_SIZE_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_L1D_SPM_SPM_SIZE_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_L1D_SPM_SPM_SIZE_OFFSET})

// Controls the L1 DCache flushing and invalidation.
#define CACHEPOOL_PERIPHERAL_CFG_L1D_INSN_REG_OFFSET 0x1c
#define CACHEPOOL_PERIPHERAL_CFG_L1D_INSN_INSN_MASK 0x3
#define CACHEPOOL_PERIPHERAL_CFG_L1D_INSN_INSN_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_L1D_INSN_INSN_FIELD                           \
  ((bitfield_field32_t){.mask = CACHEPOOL_PERIPHERAL_CFG_L1D_INSN_INSN_MASK,   \
                        .index =                                               \
                            CACHEPOOL_PERIPHERAL_CFG_L1D_INSN_INSN_OFFSET})

// One-hot tile selection mask for private-partition flush.
#define CACHEPOOL_PERIPHERAL_CFG_L1D_TILE_SEL_TILE_FIELD_WIDTH 32
#define CACHEPOOL_PERIPHERAL_CFG_L1D_TILE_SEL_TILE_FIELDS_PER_REG 1
#define CACHEPOOL_PERIPHERAL_CFG_L1D_TILE_SEL_MULTIREG_COUNT 2

// One-hot tile selection mask for private-partition flush.
#define CACHEPOOL_PERIPHERAL_CFG_L1D_TILE_SEL_0_REG_OFFSET 0x20

// One-hot tile selection mask for private-partition flush.
#define CACHEPOOL_PERIPHERAL_CFG_L1D_TILE_SEL_1_REG_OFFSET 0x24

// Controls the L1 DCache flushing and invalidation.
#define CACHEPOOL_PERIPHERAL_L1D_SPM_COMMIT_REG_OFFSET 0x28
#define CACHEPOOL_PERIPHERAL_L1D_SPM_COMMIT_COMMIT_BIT 0

// Controls the L1 DCache flushing and invalidation.
#define CACHEPOOL_PERIPHERAL_L1D_INSN_COMMIT_REG_OFFSET 0x2c
#define CACHEPOOL_PERIPHERAL_L1D_INSN_COMMIT_COMMIT_BIT 0

// Indicate the status of flushing
#define CACHEPOOL_PERIPHERAL_L1D_FLUSH_STATUS_REG_OFFSET 0x30
#define CACHEPOOL_PERIPHERAL_L1D_FLUSH_STATUS_STATUS_BIT 0

// Number of private banks configured per tile
#define CACHEPOOL_PERIPHERAL_L1D_PRIVATE_REG_OFFSET 0x34
#define CACHEPOOL_PERIPHERAL_L1D_PRIVATE_NUMBER_MASK 0xf
#define CACHEPOOL_PERIPHERAL_L1D_PRIVATE_NUMBER_OFFSET 0
#define CACHEPOOL_PERIPHERAL_L1D_PRIVATE_NUMBER_FIELD                          \
  ((bitfield_field32_t){.mask = CACHEPOOL_PERIPHERAL_L1D_PRIVATE_NUMBER_MASK,  \
                        .index =                                               \
                            CACHEPOOL_PERIPHERAL_L1D_PRIVATE_NUMBER_OFFSET})

// Starting address of private L1D partition
#define CACHEPOOL_PERIPHERAL_L1D_ADDR_REG_OFFSET 0x38

// Cache xbar offset setting
#define CACHEPOOL_PERIPHERAL_XBAR_OFFSET_REG_OFFSET 0x3c
#define CACHEPOOL_PERIPHERAL_XBAR_OFFSET_OFFSET_MASK 0x1f
#define CACHEPOOL_PERIPHERAL_XBAR_OFFSET_OFFSET_OFFSET 0
#define CACHEPOOL_PERIPHERAL_XBAR_OFFSET_OFFSET_FIELD                          \
  ((bitfield_field32_t){.mask = CACHEPOOL_PERIPHERAL_XBAR_OFFSET_OFFSET_MASK,  \
                        .index =                                               \
                            CACHEPOOL_PERIPHERAL_XBAR_OFFSET_OFFSET_OFFSET})

// Cache xbar offset setting
#define CACHEPOOL_PERIPHERAL_XBAR_OFFSET_COMMIT_REG_OFFSET 0x40
#define CACHEPOOL_PERIPHERAL_XBAR_OFFSET_COMMIT_COMMIT_BIT 0

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_OP_FIELD_WIDTH 3
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_OP_FIELDS_PER_REG 10
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_MULTIREG_COUNT 64

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_0_REG_OFFSET 0x44
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_0_OP_0_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_0_OP_0_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_0_OP_0_FIELD                          \
  ((bitfield_field32_t){.mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_0_OP_0_MASK,  \
                        .index =                                               \
                            CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_0_OP_0_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_1_REG_OFFSET 0x48
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_1_OP_1_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_1_OP_1_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_1_OP_1_FIELD                          \
  ((bitfield_field32_t){.mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_1_OP_1_MASK,  \
                        .index =                                               \
                            CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_1_OP_1_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_2_REG_OFFSET 0x4c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_2_OP_2_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_2_OP_2_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_2_OP_2_FIELD                          \
  ((bitfield_field32_t){.mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_2_OP_2_MASK,  \
                        .index =                                               \
                            CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_2_OP_2_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_3_REG_OFFSET 0x50
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_3_OP_3_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_3_OP_3_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_3_OP_3_FIELD                          \
  ((bitfield_field32_t){.mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_3_OP_3_MASK,  \
                        .index =                                               \
                            CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_3_OP_3_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_4_REG_OFFSET 0x54
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_4_OP_4_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_4_OP_4_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_4_OP_4_FIELD                          \
  ((bitfield_field32_t){.mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_4_OP_4_MASK,  \
                        .index =                                               \
                            CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_4_OP_4_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_5_REG_OFFSET 0x58
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_5_OP_5_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_5_OP_5_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_5_OP_5_FIELD                          \
  ((bitfield_field32_t){.mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_5_OP_5_MASK,  \
                        .index =                                               \
                            CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_5_OP_5_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_6_REG_OFFSET 0x5c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_6_OP_6_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_6_OP_6_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_6_OP_6_FIELD                          \
  ((bitfield_field32_t){.mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_6_OP_6_MASK,  \
                        .index =                                               \
                            CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_6_OP_6_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_7_REG_OFFSET 0x60
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_7_OP_7_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_7_OP_7_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_7_OP_7_FIELD                          \
  ((bitfield_field32_t){.mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_7_OP_7_MASK,  \
                        .index =                                               \
                            CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_7_OP_7_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_8_REG_OFFSET 0x64
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_8_OP_8_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_8_OP_8_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_8_OP_8_FIELD                          \
  ((bitfield_field32_t){.mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_8_OP_8_MASK,  \
                        .index =                                               \
                            CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_8_OP_8_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_9_REG_OFFSET 0x68
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_9_OP_9_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_9_OP_9_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_9_OP_9_FIELD                          \
  ((bitfield_field32_t){.mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_9_OP_9_MASK,  \
                        .index =                                               \
                            CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_9_OP_9_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_10_REG_OFFSET 0x6c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_10_OP_10_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_10_OP_10_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_10_OP_10_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_10_OP_10_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_10_OP_10_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_11_REG_OFFSET 0x70
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_11_OP_11_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_11_OP_11_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_11_OP_11_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_11_OP_11_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_11_OP_11_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_12_REG_OFFSET 0x74
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_12_OP_12_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_12_OP_12_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_12_OP_12_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_12_OP_12_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_12_OP_12_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_13_REG_OFFSET 0x78
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_13_OP_13_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_13_OP_13_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_13_OP_13_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_13_OP_13_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_13_OP_13_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_14_REG_OFFSET 0x7c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_14_OP_14_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_14_OP_14_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_14_OP_14_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_14_OP_14_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_14_OP_14_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_15_REG_OFFSET 0x80
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_15_OP_15_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_15_OP_15_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_15_OP_15_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_15_OP_15_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_15_OP_15_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_16_REG_OFFSET 0x84
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_16_OP_16_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_16_OP_16_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_16_OP_16_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_16_OP_16_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_16_OP_16_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_17_REG_OFFSET 0x88
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_17_OP_17_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_17_OP_17_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_17_OP_17_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_17_OP_17_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_17_OP_17_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_18_REG_OFFSET 0x8c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_18_OP_18_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_18_OP_18_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_18_OP_18_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_18_OP_18_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_18_OP_18_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_19_REG_OFFSET 0x90
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_19_OP_19_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_19_OP_19_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_19_OP_19_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_19_OP_19_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_19_OP_19_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_20_REG_OFFSET 0x94
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_20_OP_20_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_20_OP_20_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_20_OP_20_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_20_OP_20_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_20_OP_20_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_21_REG_OFFSET 0x98
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_21_OP_21_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_21_OP_21_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_21_OP_21_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_21_OP_21_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_21_OP_21_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_22_REG_OFFSET 0x9c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_22_OP_22_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_22_OP_22_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_22_OP_22_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_22_OP_22_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_22_OP_22_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_23_REG_OFFSET 0xa0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_23_OP_23_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_23_OP_23_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_23_OP_23_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_23_OP_23_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_23_OP_23_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_24_REG_OFFSET 0xa4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_24_OP_24_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_24_OP_24_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_24_OP_24_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_24_OP_24_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_24_OP_24_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_25_REG_OFFSET 0xa8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_25_OP_25_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_25_OP_25_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_25_OP_25_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_25_OP_25_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_25_OP_25_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_26_REG_OFFSET 0xac
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_26_OP_26_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_26_OP_26_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_26_OP_26_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_26_OP_26_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_26_OP_26_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_27_REG_OFFSET 0xb0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_27_OP_27_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_27_OP_27_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_27_OP_27_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_27_OP_27_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_27_OP_27_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_28_REG_OFFSET 0xb4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_28_OP_28_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_28_OP_28_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_28_OP_28_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_28_OP_28_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_28_OP_28_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_29_REG_OFFSET 0xb8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_29_OP_29_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_29_OP_29_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_29_OP_29_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_29_OP_29_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_29_OP_29_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_30_REG_OFFSET 0xbc
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_30_OP_30_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_30_OP_30_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_30_OP_30_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_30_OP_30_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_30_OP_30_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_31_REG_OFFSET 0xc0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_31_OP_31_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_31_OP_31_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_31_OP_31_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_31_OP_31_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_31_OP_31_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_32_REG_OFFSET 0xc4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_32_OP_32_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_32_OP_32_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_32_OP_32_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_32_OP_32_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_32_OP_32_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_33_REG_OFFSET 0xc8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_33_OP_33_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_33_OP_33_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_33_OP_33_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_33_OP_33_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_33_OP_33_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_34_REG_OFFSET 0xcc
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_34_OP_34_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_34_OP_34_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_34_OP_34_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_34_OP_34_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_34_OP_34_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_35_REG_OFFSET 0xd0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_35_OP_35_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_35_OP_35_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_35_OP_35_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_35_OP_35_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_35_OP_35_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_36_REG_OFFSET 0xd4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_36_OP_36_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_36_OP_36_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_36_OP_36_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_36_OP_36_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_36_OP_36_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_37_REG_OFFSET 0xd8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_37_OP_37_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_37_OP_37_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_37_OP_37_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_37_OP_37_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_37_OP_37_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_38_REG_OFFSET 0xdc
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_38_OP_38_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_38_OP_38_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_38_OP_38_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_38_OP_38_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_38_OP_38_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_39_REG_OFFSET 0xe0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_39_OP_39_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_39_OP_39_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_39_OP_39_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_39_OP_39_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_39_OP_39_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_40_REG_OFFSET 0xe4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_40_OP_40_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_40_OP_40_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_40_OP_40_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_40_OP_40_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_40_OP_40_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_41_REG_OFFSET 0xe8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_41_OP_41_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_41_OP_41_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_41_OP_41_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_41_OP_41_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_41_OP_41_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_42_REG_OFFSET 0xec
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_42_OP_42_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_42_OP_42_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_42_OP_42_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_42_OP_42_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_42_OP_42_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_43_REG_OFFSET 0xf0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_43_OP_43_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_43_OP_43_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_43_OP_43_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_43_OP_43_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_43_OP_43_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_44_REG_OFFSET 0xf4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_44_OP_44_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_44_OP_44_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_44_OP_44_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_44_OP_44_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_44_OP_44_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_45_REG_OFFSET 0xf8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_45_OP_45_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_45_OP_45_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_45_OP_45_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_45_OP_45_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_45_OP_45_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_46_REG_OFFSET 0xfc
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_46_OP_46_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_46_OP_46_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_46_OP_46_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_46_OP_46_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_46_OP_46_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_47_REG_OFFSET 0x100
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_47_OP_47_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_47_OP_47_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_47_OP_47_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_47_OP_47_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_47_OP_47_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_48_REG_OFFSET 0x104
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_48_OP_48_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_48_OP_48_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_48_OP_48_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_48_OP_48_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_48_OP_48_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_49_REG_OFFSET 0x108
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_49_OP_49_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_49_OP_49_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_49_OP_49_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_49_OP_49_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_49_OP_49_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_50_REG_OFFSET 0x10c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_50_OP_50_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_50_OP_50_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_50_OP_50_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_50_OP_50_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_50_OP_50_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_51_REG_OFFSET 0x110
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_51_OP_51_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_51_OP_51_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_51_OP_51_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_51_OP_51_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_51_OP_51_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_52_REG_OFFSET 0x114
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_52_OP_52_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_52_OP_52_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_52_OP_52_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_52_OP_52_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_52_OP_52_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_53_REG_OFFSET 0x118
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_53_OP_53_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_53_OP_53_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_53_OP_53_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_53_OP_53_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_53_OP_53_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_54_REG_OFFSET 0x11c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_54_OP_54_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_54_OP_54_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_54_OP_54_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_54_OP_54_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_54_OP_54_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_55_REG_OFFSET 0x120
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_55_OP_55_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_55_OP_55_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_55_OP_55_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_55_OP_55_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_55_OP_55_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_56_REG_OFFSET 0x124
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_56_OP_56_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_56_OP_56_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_56_OP_56_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_56_OP_56_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_56_OP_56_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_57_REG_OFFSET 0x128
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_57_OP_57_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_57_OP_57_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_57_OP_57_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_57_OP_57_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_57_OP_57_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_58_REG_OFFSET 0x12c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_58_OP_58_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_58_OP_58_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_58_OP_58_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_58_OP_58_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_58_OP_58_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_59_REG_OFFSET 0x130
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_59_OP_59_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_59_OP_59_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_59_OP_59_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_59_OP_59_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_59_OP_59_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_60_REG_OFFSET 0x134
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_60_OP_60_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_60_OP_60_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_60_OP_60_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_60_OP_60_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_60_OP_60_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_61_REG_OFFSET 0x138
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_61_OP_61_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_61_OP_61_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_61_OP_61_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_61_OP_61_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_61_OP_61_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_62_REG_OFFSET 0x13c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_62_OP_62_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_62_OP_62_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_62_OP_62_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_62_OP_62_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_62_OP_62_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_63_REG_OFFSET 0x140
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_63_OP_63_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_63_OP_63_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_63_OP_63_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_63_OP_63_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_63_OP_63_OFFSET})

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_ADDR_FIELD_WIDTH 32
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_ADDR_FIELDS_PER_REG 1
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_MULTIREG_COUNT 64

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_0_REG_OFFSET 0x144

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_1_REG_OFFSET 0x148

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_2_REG_OFFSET 0x14c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_3_REG_OFFSET 0x150

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_4_REG_OFFSET 0x154

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_5_REG_OFFSET 0x158

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_6_REG_OFFSET 0x15c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_7_REG_OFFSET 0x160

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_8_REG_OFFSET 0x164

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_9_REG_OFFSET 0x168

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_10_REG_OFFSET 0x16c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_11_REG_OFFSET 0x170

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_12_REG_OFFSET 0x174

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_13_REG_OFFSET 0x178

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_14_REG_OFFSET 0x17c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_15_REG_OFFSET 0x180

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_16_REG_OFFSET 0x184

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_17_REG_OFFSET 0x188

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_18_REG_OFFSET 0x18c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_19_REG_OFFSET 0x190

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_20_REG_OFFSET 0x194

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_21_REG_OFFSET 0x198

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_22_REG_OFFSET 0x19c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_23_REG_OFFSET 0x1a0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_24_REG_OFFSET 0x1a4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_25_REG_OFFSET 0x1a8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_26_REG_OFFSET 0x1ac

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_27_REG_OFFSET 0x1b0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_28_REG_OFFSET 0x1b4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_29_REG_OFFSET 0x1b8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_30_REG_OFFSET 0x1bc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_31_REG_OFFSET 0x1c0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_32_REG_OFFSET 0x1c4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_33_REG_OFFSET 0x1c8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_34_REG_OFFSET 0x1cc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_35_REG_OFFSET 0x1d0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_36_REG_OFFSET 0x1d4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_37_REG_OFFSET 0x1d8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_38_REG_OFFSET 0x1dc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_39_REG_OFFSET 0x1e0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_40_REG_OFFSET 0x1e4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_41_REG_OFFSET 0x1e8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_42_REG_OFFSET 0x1ec

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_43_REG_OFFSET 0x1f0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_44_REG_OFFSET 0x1f4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_45_REG_OFFSET 0x1f8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_46_REG_OFFSET 0x1fc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_47_REG_OFFSET 0x200

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_48_REG_OFFSET 0x204

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_49_REG_OFFSET 0x208

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_50_REG_OFFSET 0x20c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_51_REG_OFFSET 0x210

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_52_REG_OFFSET 0x214

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_53_REG_OFFSET 0x218

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_54_REG_OFFSET 0x21c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_55_REG_OFFSET 0x220

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_56_REG_OFFSET 0x224

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_57_REG_OFFSET 0x228

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_58_REG_OFFSET 0x22c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_59_REG_OFFSET 0x230

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_60_REG_OFFSET 0x234

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_61_REG_OFFSET 0x238

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_62_REG_OFFSET 0x23c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_63_REG_OFFSET 0x240

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_COMMIT_FIELD_WIDTH 1
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_COMMIT_FIELDS_PER_REG 32
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_MULTIREG_COUNT 64

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_0_REG_OFFSET 0x244
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_0_COMMIT_0_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_1_REG_OFFSET 0x248
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_1_COMMIT_1_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_2_REG_OFFSET 0x24c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_2_COMMIT_2_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_3_REG_OFFSET 0x250
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_3_COMMIT_3_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_4_REG_OFFSET 0x254
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_4_COMMIT_4_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_5_REG_OFFSET 0x258
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_5_COMMIT_5_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_6_REG_OFFSET 0x25c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_6_COMMIT_6_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_7_REG_OFFSET 0x260
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_7_COMMIT_7_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_8_REG_OFFSET 0x264
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_8_COMMIT_8_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_9_REG_OFFSET 0x268
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_9_COMMIT_9_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_10_REG_OFFSET 0x26c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_10_COMMIT_10_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_11_REG_OFFSET 0x270
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_11_COMMIT_11_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_12_REG_OFFSET 0x274
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_12_COMMIT_12_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_13_REG_OFFSET 0x278
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_13_COMMIT_13_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_14_REG_OFFSET 0x27c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_14_COMMIT_14_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_15_REG_OFFSET 0x280
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_15_COMMIT_15_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_16_REG_OFFSET 0x284
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_16_COMMIT_16_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_17_REG_OFFSET 0x288
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_17_COMMIT_17_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_18_REG_OFFSET 0x28c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_18_COMMIT_18_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_19_REG_OFFSET 0x290
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_19_COMMIT_19_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_20_REG_OFFSET 0x294
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_20_COMMIT_20_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_21_REG_OFFSET 0x298
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_21_COMMIT_21_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_22_REG_OFFSET 0x29c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_22_COMMIT_22_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_23_REG_OFFSET 0x2a0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_23_COMMIT_23_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_24_REG_OFFSET 0x2a4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_24_COMMIT_24_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_25_REG_OFFSET 0x2a8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_25_COMMIT_25_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_26_REG_OFFSET 0x2ac
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_26_COMMIT_26_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_27_REG_OFFSET 0x2b0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_27_COMMIT_27_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_28_REG_OFFSET 0x2b4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_28_COMMIT_28_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_29_REG_OFFSET 0x2b8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_29_COMMIT_29_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_30_REG_OFFSET 0x2bc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_30_COMMIT_30_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_31_REG_OFFSET 0x2c0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_31_COMMIT_31_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_32_REG_OFFSET 0x2c4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_32_COMMIT_32_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_33_REG_OFFSET 0x2c8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_33_COMMIT_33_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_34_REG_OFFSET 0x2cc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_34_COMMIT_34_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_35_REG_OFFSET 0x2d0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_35_COMMIT_35_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_36_REG_OFFSET 0x2d4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_36_COMMIT_36_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_37_REG_OFFSET 0x2d8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_37_COMMIT_37_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_38_REG_OFFSET 0x2dc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_38_COMMIT_38_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_39_REG_OFFSET 0x2e0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_39_COMMIT_39_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_40_REG_OFFSET 0x2e4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_40_COMMIT_40_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_41_REG_OFFSET 0x2e8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_41_COMMIT_41_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_42_REG_OFFSET 0x2ec
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_42_COMMIT_42_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_43_REG_OFFSET 0x2f0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_43_COMMIT_43_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_44_REG_OFFSET 0x2f4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_44_COMMIT_44_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_45_REG_OFFSET 0x2f8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_45_COMMIT_45_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_46_REG_OFFSET 0x2fc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_46_COMMIT_46_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_47_REG_OFFSET 0x300
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_47_COMMIT_47_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_48_REG_OFFSET 0x304
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_48_COMMIT_48_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_49_REG_OFFSET 0x308
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_49_COMMIT_49_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_50_REG_OFFSET 0x30c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_50_COMMIT_50_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_51_REG_OFFSET 0x310
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_51_COMMIT_51_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_52_REG_OFFSET 0x314
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_52_COMMIT_52_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_53_REG_OFFSET 0x318
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_53_COMMIT_53_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_54_REG_OFFSET 0x31c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_54_COMMIT_54_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_55_REG_OFFSET 0x320
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_55_COMMIT_55_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_56_REG_OFFSET 0x324
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_56_COMMIT_56_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_57_REG_OFFSET 0x328
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_57_COMMIT_57_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_58_REG_OFFSET 0x32c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_58_COMMIT_58_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_59_REG_OFFSET 0x330
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_59_COMMIT_59_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_60_REG_OFFSET 0x334
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_60_COMMIT_60_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_61_REG_OFFSET 0x338
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_61_COMMIT_61_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_62_REG_OFFSET 0x33c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_62_COMMIT_62_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_63_REG_OFFSET 0x340
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_63_COMMIT_63_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_STATUS_FIELD_WIDTH 1
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_STATUS_FIELDS_PER_REG 32
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_MULTIREG_COUNT 64

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_0_REG_OFFSET 0x344
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_0_STATUS_0_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_1_REG_OFFSET 0x348
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_1_STATUS_1_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_2_REG_OFFSET 0x34c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_2_STATUS_2_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_3_REG_OFFSET 0x350
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_3_STATUS_3_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_4_REG_OFFSET 0x354
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_4_STATUS_4_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_5_REG_OFFSET 0x358
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_5_STATUS_5_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_6_REG_OFFSET 0x35c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_6_STATUS_6_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_7_REG_OFFSET 0x360
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_7_STATUS_7_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_8_REG_OFFSET 0x364
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_8_STATUS_8_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_9_REG_OFFSET 0x368
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_9_STATUS_9_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_10_REG_OFFSET 0x36c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_10_STATUS_10_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_11_REG_OFFSET 0x370
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_11_STATUS_11_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_12_REG_OFFSET 0x374
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_12_STATUS_12_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_13_REG_OFFSET 0x378
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_13_STATUS_13_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_14_REG_OFFSET 0x37c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_14_STATUS_14_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_15_REG_OFFSET 0x380
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_15_STATUS_15_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_16_REG_OFFSET 0x384
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_16_STATUS_16_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_17_REG_OFFSET 0x388
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_17_STATUS_17_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_18_REG_OFFSET 0x38c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_18_STATUS_18_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_19_REG_OFFSET 0x390
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_19_STATUS_19_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_20_REG_OFFSET 0x394
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_20_STATUS_20_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_21_REG_OFFSET 0x398
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_21_STATUS_21_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_22_REG_OFFSET 0x39c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_22_STATUS_22_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_23_REG_OFFSET 0x3a0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_23_STATUS_23_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_24_REG_OFFSET 0x3a4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_24_STATUS_24_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_25_REG_OFFSET 0x3a8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_25_STATUS_25_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_26_REG_OFFSET 0x3ac
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_26_STATUS_26_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_27_REG_OFFSET 0x3b0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_27_STATUS_27_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_28_REG_OFFSET 0x3b4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_28_STATUS_28_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_29_REG_OFFSET 0x3b8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_29_STATUS_29_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_30_REG_OFFSET 0x3bc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_30_STATUS_30_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_31_REG_OFFSET 0x3c0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_31_STATUS_31_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_32_REG_OFFSET 0x3c4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_32_STATUS_32_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_33_REG_OFFSET 0x3c8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_33_STATUS_33_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_34_REG_OFFSET 0x3cc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_34_STATUS_34_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_35_REG_OFFSET 0x3d0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_35_STATUS_35_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_36_REG_OFFSET 0x3d4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_36_STATUS_36_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_37_REG_OFFSET 0x3d8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_37_STATUS_37_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_38_REG_OFFSET 0x3dc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_38_STATUS_38_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_39_REG_OFFSET 0x3e0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_39_STATUS_39_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_40_REG_OFFSET 0x3e4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_40_STATUS_40_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_41_REG_OFFSET 0x3e8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_41_STATUS_41_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_42_REG_OFFSET 0x3ec
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_42_STATUS_42_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_43_REG_OFFSET 0x3f0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_43_STATUS_43_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_44_REG_OFFSET 0x3f4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_44_STATUS_44_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_45_REG_OFFSET 0x3f8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_45_STATUS_45_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_46_REG_OFFSET 0x3fc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_46_STATUS_46_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_47_REG_OFFSET 0x400
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_47_STATUS_47_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_48_REG_OFFSET 0x404
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_48_STATUS_48_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_49_REG_OFFSET 0x408
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_49_STATUS_49_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_50_REG_OFFSET 0x40c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_50_STATUS_50_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_51_REG_OFFSET 0x410
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_51_STATUS_51_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_52_REG_OFFSET 0x414
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_52_STATUS_52_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_53_REG_OFFSET 0x418
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_53_STATUS_53_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_54_REG_OFFSET 0x41c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_54_STATUS_54_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_55_REG_OFFSET 0x420
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_55_STATUS_55_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_56_REG_OFFSET 0x424
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_56_STATUS_56_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_57_REG_OFFSET 0x428
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_57_STATUS_57_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_58_REG_OFFSET 0x42c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_58_STATUS_58_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_59_REG_OFFSET 0x430
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_59_STATUS_59_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_60_REG_OFFSET 0x434
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_60_STATUS_60_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_61_REG_OFFSET 0x438
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_61_STATUS_61_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_62_REG_OFFSET 0x43c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_62_STATUS_62_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_63_REG_OFFSET 0x440
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_63_STATUS_63_BIT 0

#ifdef __cplusplus
} // extern "C"
#endif
#endif // _CACHEPOOL_PERIPHERAL_REG_DEFS_
       // End generated register defines for cachepool_peripheral