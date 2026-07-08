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
#define CACHEPOOL_PERIPHERAL_PARAM_NUM_LP1_CMO_REGS 256

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
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_MULTIREG_COUNT 256

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

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_64_REG_OFFSET 0x144
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_64_OP_64_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_64_OP_64_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_64_OP_64_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_64_OP_64_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_64_OP_64_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_65_REG_OFFSET 0x148
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_65_OP_65_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_65_OP_65_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_65_OP_65_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_65_OP_65_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_65_OP_65_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_66_REG_OFFSET 0x14c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_66_OP_66_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_66_OP_66_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_66_OP_66_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_66_OP_66_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_66_OP_66_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_67_REG_OFFSET 0x150
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_67_OP_67_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_67_OP_67_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_67_OP_67_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_67_OP_67_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_67_OP_67_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_68_REG_OFFSET 0x154
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_68_OP_68_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_68_OP_68_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_68_OP_68_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_68_OP_68_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_68_OP_68_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_69_REG_OFFSET 0x158
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_69_OP_69_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_69_OP_69_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_69_OP_69_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_69_OP_69_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_69_OP_69_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_70_REG_OFFSET 0x15c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_70_OP_70_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_70_OP_70_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_70_OP_70_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_70_OP_70_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_70_OP_70_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_71_REG_OFFSET 0x160
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_71_OP_71_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_71_OP_71_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_71_OP_71_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_71_OP_71_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_71_OP_71_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_72_REG_OFFSET 0x164
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_72_OP_72_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_72_OP_72_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_72_OP_72_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_72_OP_72_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_72_OP_72_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_73_REG_OFFSET 0x168
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_73_OP_73_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_73_OP_73_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_73_OP_73_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_73_OP_73_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_73_OP_73_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_74_REG_OFFSET 0x16c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_74_OP_74_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_74_OP_74_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_74_OP_74_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_74_OP_74_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_74_OP_74_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_75_REG_OFFSET 0x170
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_75_OP_75_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_75_OP_75_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_75_OP_75_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_75_OP_75_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_75_OP_75_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_76_REG_OFFSET 0x174
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_76_OP_76_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_76_OP_76_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_76_OP_76_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_76_OP_76_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_76_OP_76_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_77_REG_OFFSET 0x178
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_77_OP_77_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_77_OP_77_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_77_OP_77_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_77_OP_77_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_77_OP_77_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_78_REG_OFFSET 0x17c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_78_OP_78_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_78_OP_78_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_78_OP_78_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_78_OP_78_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_78_OP_78_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_79_REG_OFFSET 0x180
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_79_OP_79_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_79_OP_79_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_79_OP_79_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_79_OP_79_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_79_OP_79_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_80_REG_OFFSET 0x184
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_80_OP_80_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_80_OP_80_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_80_OP_80_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_80_OP_80_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_80_OP_80_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_81_REG_OFFSET 0x188
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_81_OP_81_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_81_OP_81_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_81_OP_81_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_81_OP_81_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_81_OP_81_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_82_REG_OFFSET 0x18c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_82_OP_82_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_82_OP_82_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_82_OP_82_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_82_OP_82_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_82_OP_82_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_83_REG_OFFSET 0x190
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_83_OP_83_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_83_OP_83_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_83_OP_83_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_83_OP_83_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_83_OP_83_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_84_REG_OFFSET 0x194
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_84_OP_84_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_84_OP_84_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_84_OP_84_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_84_OP_84_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_84_OP_84_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_85_REG_OFFSET 0x198
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_85_OP_85_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_85_OP_85_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_85_OP_85_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_85_OP_85_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_85_OP_85_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_86_REG_OFFSET 0x19c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_86_OP_86_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_86_OP_86_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_86_OP_86_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_86_OP_86_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_86_OP_86_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_87_REG_OFFSET 0x1a0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_87_OP_87_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_87_OP_87_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_87_OP_87_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_87_OP_87_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_87_OP_87_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_88_REG_OFFSET 0x1a4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_88_OP_88_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_88_OP_88_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_88_OP_88_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_88_OP_88_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_88_OP_88_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_89_REG_OFFSET 0x1a8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_89_OP_89_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_89_OP_89_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_89_OP_89_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_89_OP_89_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_89_OP_89_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_90_REG_OFFSET 0x1ac
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_90_OP_90_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_90_OP_90_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_90_OP_90_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_90_OP_90_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_90_OP_90_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_91_REG_OFFSET 0x1b0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_91_OP_91_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_91_OP_91_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_91_OP_91_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_91_OP_91_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_91_OP_91_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_92_REG_OFFSET 0x1b4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_92_OP_92_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_92_OP_92_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_92_OP_92_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_92_OP_92_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_92_OP_92_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_93_REG_OFFSET 0x1b8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_93_OP_93_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_93_OP_93_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_93_OP_93_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_93_OP_93_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_93_OP_93_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_94_REG_OFFSET 0x1bc
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_94_OP_94_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_94_OP_94_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_94_OP_94_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_94_OP_94_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_94_OP_94_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_95_REG_OFFSET 0x1c0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_95_OP_95_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_95_OP_95_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_95_OP_95_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_95_OP_95_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_95_OP_95_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_96_REG_OFFSET 0x1c4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_96_OP_96_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_96_OP_96_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_96_OP_96_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_96_OP_96_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_96_OP_96_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_97_REG_OFFSET 0x1c8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_97_OP_97_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_97_OP_97_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_97_OP_97_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_97_OP_97_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_97_OP_97_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_98_REG_OFFSET 0x1cc
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_98_OP_98_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_98_OP_98_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_98_OP_98_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_98_OP_98_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_98_OP_98_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_99_REG_OFFSET 0x1d0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_99_OP_99_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_99_OP_99_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_99_OP_99_FIELD                        \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_99_OP_99_MASK,                  \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_99_OP_99_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_100_REG_OFFSET 0x1d4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_100_OP_100_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_100_OP_100_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_100_OP_100_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_100_OP_100_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_100_OP_100_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_101_REG_OFFSET 0x1d8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_101_OP_101_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_101_OP_101_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_101_OP_101_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_101_OP_101_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_101_OP_101_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_102_REG_OFFSET 0x1dc
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_102_OP_102_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_102_OP_102_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_102_OP_102_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_102_OP_102_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_102_OP_102_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_103_REG_OFFSET 0x1e0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_103_OP_103_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_103_OP_103_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_103_OP_103_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_103_OP_103_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_103_OP_103_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_104_REG_OFFSET 0x1e4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_104_OP_104_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_104_OP_104_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_104_OP_104_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_104_OP_104_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_104_OP_104_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_105_REG_OFFSET 0x1e8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_105_OP_105_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_105_OP_105_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_105_OP_105_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_105_OP_105_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_105_OP_105_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_106_REG_OFFSET 0x1ec
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_106_OP_106_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_106_OP_106_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_106_OP_106_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_106_OP_106_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_106_OP_106_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_107_REG_OFFSET 0x1f0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_107_OP_107_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_107_OP_107_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_107_OP_107_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_107_OP_107_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_107_OP_107_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_108_REG_OFFSET 0x1f4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_108_OP_108_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_108_OP_108_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_108_OP_108_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_108_OP_108_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_108_OP_108_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_109_REG_OFFSET 0x1f8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_109_OP_109_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_109_OP_109_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_109_OP_109_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_109_OP_109_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_109_OP_109_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_110_REG_OFFSET 0x1fc
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_110_OP_110_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_110_OP_110_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_110_OP_110_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_110_OP_110_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_110_OP_110_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_111_REG_OFFSET 0x200
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_111_OP_111_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_111_OP_111_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_111_OP_111_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_111_OP_111_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_111_OP_111_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_112_REG_OFFSET 0x204
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_112_OP_112_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_112_OP_112_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_112_OP_112_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_112_OP_112_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_112_OP_112_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_113_REG_OFFSET 0x208
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_113_OP_113_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_113_OP_113_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_113_OP_113_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_113_OP_113_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_113_OP_113_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_114_REG_OFFSET 0x20c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_114_OP_114_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_114_OP_114_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_114_OP_114_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_114_OP_114_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_114_OP_114_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_115_REG_OFFSET 0x210
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_115_OP_115_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_115_OP_115_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_115_OP_115_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_115_OP_115_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_115_OP_115_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_116_REG_OFFSET 0x214
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_116_OP_116_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_116_OP_116_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_116_OP_116_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_116_OP_116_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_116_OP_116_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_117_REG_OFFSET 0x218
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_117_OP_117_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_117_OP_117_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_117_OP_117_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_117_OP_117_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_117_OP_117_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_118_REG_OFFSET 0x21c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_118_OP_118_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_118_OP_118_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_118_OP_118_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_118_OP_118_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_118_OP_118_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_119_REG_OFFSET 0x220
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_119_OP_119_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_119_OP_119_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_119_OP_119_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_119_OP_119_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_119_OP_119_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_120_REG_OFFSET 0x224
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_120_OP_120_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_120_OP_120_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_120_OP_120_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_120_OP_120_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_120_OP_120_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_121_REG_OFFSET 0x228
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_121_OP_121_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_121_OP_121_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_121_OP_121_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_121_OP_121_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_121_OP_121_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_122_REG_OFFSET 0x22c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_122_OP_122_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_122_OP_122_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_122_OP_122_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_122_OP_122_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_122_OP_122_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_123_REG_OFFSET 0x230
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_123_OP_123_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_123_OP_123_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_123_OP_123_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_123_OP_123_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_123_OP_123_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_124_REG_OFFSET 0x234
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_124_OP_124_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_124_OP_124_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_124_OP_124_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_124_OP_124_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_124_OP_124_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_125_REG_OFFSET 0x238
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_125_OP_125_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_125_OP_125_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_125_OP_125_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_125_OP_125_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_125_OP_125_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_126_REG_OFFSET 0x23c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_126_OP_126_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_126_OP_126_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_126_OP_126_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_126_OP_126_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_126_OP_126_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_127_REG_OFFSET 0x240
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_127_OP_127_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_127_OP_127_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_127_OP_127_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_127_OP_127_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_127_OP_127_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_128_REG_OFFSET 0x244
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_128_OP_128_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_128_OP_128_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_128_OP_128_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_128_OP_128_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_128_OP_128_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_129_REG_OFFSET 0x248
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_129_OP_129_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_129_OP_129_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_129_OP_129_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_129_OP_129_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_129_OP_129_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_130_REG_OFFSET 0x24c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_130_OP_130_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_130_OP_130_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_130_OP_130_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_130_OP_130_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_130_OP_130_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_131_REG_OFFSET 0x250
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_131_OP_131_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_131_OP_131_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_131_OP_131_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_131_OP_131_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_131_OP_131_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_132_REG_OFFSET 0x254
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_132_OP_132_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_132_OP_132_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_132_OP_132_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_132_OP_132_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_132_OP_132_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_133_REG_OFFSET 0x258
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_133_OP_133_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_133_OP_133_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_133_OP_133_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_133_OP_133_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_133_OP_133_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_134_REG_OFFSET 0x25c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_134_OP_134_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_134_OP_134_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_134_OP_134_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_134_OP_134_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_134_OP_134_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_135_REG_OFFSET 0x260
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_135_OP_135_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_135_OP_135_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_135_OP_135_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_135_OP_135_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_135_OP_135_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_136_REG_OFFSET 0x264
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_136_OP_136_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_136_OP_136_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_136_OP_136_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_136_OP_136_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_136_OP_136_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_137_REG_OFFSET 0x268
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_137_OP_137_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_137_OP_137_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_137_OP_137_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_137_OP_137_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_137_OP_137_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_138_REG_OFFSET 0x26c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_138_OP_138_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_138_OP_138_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_138_OP_138_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_138_OP_138_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_138_OP_138_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_139_REG_OFFSET 0x270
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_139_OP_139_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_139_OP_139_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_139_OP_139_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_139_OP_139_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_139_OP_139_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_140_REG_OFFSET 0x274
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_140_OP_140_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_140_OP_140_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_140_OP_140_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_140_OP_140_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_140_OP_140_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_141_REG_OFFSET 0x278
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_141_OP_141_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_141_OP_141_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_141_OP_141_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_141_OP_141_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_141_OP_141_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_142_REG_OFFSET 0x27c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_142_OP_142_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_142_OP_142_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_142_OP_142_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_142_OP_142_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_142_OP_142_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_143_REG_OFFSET 0x280
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_143_OP_143_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_143_OP_143_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_143_OP_143_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_143_OP_143_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_143_OP_143_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_144_REG_OFFSET 0x284
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_144_OP_144_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_144_OP_144_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_144_OP_144_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_144_OP_144_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_144_OP_144_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_145_REG_OFFSET 0x288
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_145_OP_145_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_145_OP_145_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_145_OP_145_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_145_OP_145_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_145_OP_145_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_146_REG_OFFSET 0x28c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_146_OP_146_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_146_OP_146_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_146_OP_146_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_146_OP_146_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_146_OP_146_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_147_REG_OFFSET 0x290
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_147_OP_147_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_147_OP_147_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_147_OP_147_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_147_OP_147_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_147_OP_147_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_148_REG_OFFSET 0x294
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_148_OP_148_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_148_OP_148_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_148_OP_148_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_148_OP_148_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_148_OP_148_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_149_REG_OFFSET 0x298
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_149_OP_149_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_149_OP_149_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_149_OP_149_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_149_OP_149_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_149_OP_149_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_150_REG_OFFSET 0x29c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_150_OP_150_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_150_OP_150_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_150_OP_150_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_150_OP_150_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_150_OP_150_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_151_REG_OFFSET 0x2a0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_151_OP_151_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_151_OP_151_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_151_OP_151_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_151_OP_151_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_151_OP_151_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_152_REG_OFFSET 0x2a4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_152_OP_152_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_152_OP_152_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_152_OP_152_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_152_OP_152_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_152_OP_152_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_153_REG_OFFSET 0x2a8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_153_OP_153_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_153_OP_153_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_153_OP_153_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_153_OP_153_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_153_OP_153_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_154_REG_OFFSET 0x2ac
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_154_OP_154_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_154_OP_154_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_154_OP_154_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_154_OP_154_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_154_OP_154_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_155_REG_OFFSET 0x2b0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_155_OP_155_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_155_OP_155_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_155_OP_155_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_155_OP_155_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_155_OP_155_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_156_REG_OFFSET 0x2b4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_156_OP_156_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_156_OP_156_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_156_OP_156_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_156_OP_156_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_156_OP_156_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_157_REG_OFFSET 0x2b8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_157_OP_157_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_157_OP_157_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_157_OP_157_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_157_OP_157_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_157_OP_157_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_158_REG_OFFSET 0x2bc
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_158_OP_158_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_158_OP_158_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_158_OP_158_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_158_OP_158_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_158_OP_158_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_159_REG_OFFSET 0x2c0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_159_OP_159_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_159_OP_159_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_159_OP_159_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_159_OP_159_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_159_OP_159_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_160_REG_OFFSET 0x2c4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_160_OP_160_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_160_OP_160_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_160_OP_160_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_160_OP_160_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_160_OP_160_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_161_REG_OFFSET 0x2c8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_161_OP_161_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_161_OP_161_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_161_OP_161_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_161_OP_161_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_161_OP_161_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_162_REG_OFFSET 0x2cc
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_162_OP_162_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_162_OP_162_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_162_OP_162_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_162_OP_162_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_162_OP_162_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_163_REG_OFFSET 0x2d0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_163_OP_163_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_163_OP_163_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_163_OP_163_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_163_OP_163_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_163_OP_163_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_164_REG_OFFSET 0x2d4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_164_OP_164_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_164_OP_164_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_164_OP_164_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_164_OP_164_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_164_OP_164_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_165_REG_OFFSET 0x2d8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_165_OP_165_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_165_OP_165_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_165_OP_165_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_165_OP_165_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_165_OP_165_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_166_REG_OFFSET 0x2dc
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_166_OP_166_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_166_OP_166_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_166_OP_166_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_166_OP_166_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_166_OP_166_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_167_REG_OFFSET 0x2e0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_167_OP_167_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_167_OP_167_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_167_OP_167_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_167_OP_167_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_167_OP_167_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_168_REG_OFFSET 0x2e4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_168_OP_168_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_168_OP_168_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_168_OP_168_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_168_OP_168_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_168_OP_168_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_169_REG_OFFSET 0x2e8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_169_OP_169_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_169_OP_169_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_169_OP_169_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_169_OP_169_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_169_OP_169_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_170_REG_OFFSET 0x2ec
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_170_OP_170_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_170_OP_170_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_170_OP_170_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_170_OP_170_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_170_OP_170_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_171_REG_OFFSET 0x2f0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_171_OP_171_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_171_OP_171_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_171_OP_171_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_171_OP_171_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_171_OP_171_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_172_REG_OFFSET 0x2f4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_172_OP_172_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_172_OP_172_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_172_OP_172_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_172_OP_172_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_172_OP_172_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_173_REG_OFFSET 0x2f8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_173_OP_173_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_173_OP_173_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_173_OP_173_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_173_OP_173_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_173_OP_173_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_174_REG_OFFSET 0x2fc
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_174_OP_174_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_174_OP_174_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_174_OP_174_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_174_OP_174_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_174_OP_174_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_175_REG_OFFSET 0x300
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_175_OP_175_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_175_OP_175_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_175_OP_175_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_175_OP_175_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_175_OP_175_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_176_REG_OFFSET 0x304
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_176_OP_176_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_176_OP_176_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_176_OP_176_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_176_OP_176_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_176_OP_176_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_177_REG_OFFSET 0x308
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_177_OP_177_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_177_OP_177_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_177_OP_177_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_177_OP_177_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_177_OP_177_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_178_REG_OFFSET 0x30c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_178_OP_178_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_178_OP_178_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_178_OP_178_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_178_OP_178_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_178_OP_178_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_179_REG_OFFSET 0x310
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_179_OP_179_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_179_OP_179_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_179_OP_179_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_179_OP_179_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_179_OP_179_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_180_REG_OFFSET 0x314
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_180_OP_180_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_180_OP_180_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_180_OP_180_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_180_OP_180_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_180_OP_180_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_181_REG_OFFSET 0x318
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_181_OP_181_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_181_OP_181_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_181_OP_181_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_181_OP_181_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_181_OP_181_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_182_REG_OFFSET 0x31c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_182_OP_182_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_182_OP_182_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_182_OP_182_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_182_OP_182_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_182_OP_182_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_183_REG_OFFSET 0x320
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_183_OP_183_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_183_OP_183_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_183_OP_183_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_183_OP_183_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_183_OP_183_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_184_REG_OFFSET 0x324
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_184_OP_184_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_184_OP_184_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_184_OP_184_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_184_OP_184_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_184_OP_184_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_185_REG_OFFSET 0x328
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_185_OP_185_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_185_OP_185_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_185_OP_185_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_185_OP_185_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_185_OP_185_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_186_REG_OFFSET 0x32c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_186_OP_186_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_186_OP_186_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_186_OP_186_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_186_OP_186_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_186_OP_186_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_187_REG_OFFSET 0x330
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_187_OP_187_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_187_OP_187_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_187_OP_187_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_187_OP_187_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_187_OP_187_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_188_REG_OFFSET 0x334
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_188_OP_188_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_188_OP_188_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_188_OP_188_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_188_OP_188_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_188_OP_188_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_189_REG_OFFSET 0x338
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_189_OP_189_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_189_OP_189_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_189_OP_189_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_189_OP_189_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_189_OP_189_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_190_REG_OFFSET 0x33c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_190_OP_190_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_190_OP_190_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_190_OP_190_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_190_OP_190_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_190_OP_190_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_191_REG_OFFSET 0x340
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_191_OP_191_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_191_OP_191_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_191_OP_191_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_191_OP_191_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_191_OP_191_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_192_REG_OFFSET 0x344
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_192_OP_192_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_192_OP_192_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_192_OP_192_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_192_OP_192_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_192_OP_192_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_193_REG_OFFSET 0x348
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_193_OP_193_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_193_OP_193_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_193_OP_193_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_193_OP_193_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_193_OP_193_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_194_REG_OFFSET 0x34c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_194_OP_194_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_194_OP_194_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_194_OP_194_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_194_OP_194_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_194_OP_194_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_195_REG_OFFSET 0x350
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_195_OP_195_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_195_OP_195_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_195_OP_195_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_195_OP_195_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_195_OP_195_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_196_REG_OFFSET 0x354
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_196_OP_196_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_196_OP_196_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_196_OP_196_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_196_OP_196_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_196_OP_196_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_197_REG_OFFSET 0x358
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_197_OP_197_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_197_OP_197_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_197_OP_197_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_197_OP_197_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_197_OP_197_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_198_REG_OFFSET 0x35c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_198_OP_198_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_198_OP_198_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_198_OP_198_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_198_OP_198_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_198_OP_198_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_199_REG_OFFSET 0x360
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_199_OP_199_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_199_OP_199_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_199_OP_199_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_199_OP_199_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_199_OP_199_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_200_REG_OFFSET 0x364
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_200_OP_200_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_200_OP_200_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_200_OP_200_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_200_OP_200_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_200_OP_200_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_201_REG_OFFSET 0x368
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_201_OP_201_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_201_OP_201_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_201_OP_201_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_201_OP_201_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_201_OP_201_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_202_REG_OFFSET 0x36c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_202_OP_202_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_202_OP_202_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_202_OP_202_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_202_OP_202_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_202_OP_202_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_203_REG_OFFSET 0x370
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_203_OP_203_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_203_OP_203_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_203_OP_203_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_203_OP_203_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_203_OP_203_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_204_REG_OFFSET 0x374
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_204_OP_204_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_204_OP_204_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_204_OP_204_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_204_OP_204_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_204_OP_204_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_205_REG_OFFSET 0x378
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_205_OP_205_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_205_OP_205_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_205_OP_205_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_205_OP_205_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_205_OP_205_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_206_REG_OFFSET 0x37c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_206_OP_206_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_206_OP_206_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_206_OP_206_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_206_OP_206_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_206_OP_206_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_207_REG_OFFSET 0x380
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_207_OP_207_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_207_OP_207_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_207_OP_207_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_207_OP_207_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_207_OP_207_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_208_REG_OFFSET 0x384
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_208_OP_208_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_208_OP_208_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_208_OP_208_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_208_OP_208_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_208_OP_208_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_209_REG_OFFSET 0x388
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_209_OP_209_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_209_OP_209_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_209_OP_209_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_209_OP_209_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_209_OP_209_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_210_REG_OFFSET 0x38c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_210_OP_210_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_210_OP_210_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_210_OP_210_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_210_OP_210_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_210_OP_210_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_211_REG_OFFSET 0x390
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_211_OP_211_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_211_OP_211_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_211_OP_211_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_211_OP_211_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_211_OP_211_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_212_REG_OFFSET 0x394
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_212_OP_212_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_212_OP_212_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_212_OP_212_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_212_OP_212_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_212_OP_212_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_213_REG_OFFSET 0x398
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_213_OP_213_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_213_OP_213_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_213_OP_213_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_213_OP_213_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_213_OP_213_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_214_REG_OFFSET 0x39c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_214_OP_214_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_214_OP_214_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_214_OP_214_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_214_OP_214_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_214_OP_214_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_215_REG_OFFSET 0x3a0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_215_OP_215_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_215_OP_215_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_215_OP_215_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_215_OP_215_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_215_OP_215_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_216_REG_OFFSET 0x3a4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_216_OP_216_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_216_OP_216_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_216_OP_216_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_216_OP_216_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_216_OP_216_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_217_REG_OFFSET 0x3a8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_217_OP_217_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_217_OP_217_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_217_OP_217_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_217_OP_217_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_217_OP_217_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_218_REG_OFFSET 0x3ac
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_218_OP_218_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_218_OP_218_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_218_OP_218_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_218_OP_218_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_218_OP_218_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_219_REG_OFFSET 0x3b0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_219_OP_219_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_219_OP_219_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_219_OP_219_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_219_OP_219_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_219_OP_219_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_220_REG_OFFSET 0x3b4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_220_OP_220_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_220_OP_220_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_220_OP_220_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_220_OP_220_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_220_OP_220_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_221_REG_OFFSET 0x3b8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_221_OP_221_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_221_OP_221_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_221_OP_221_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_221_OP_221_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_221_OP_221_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_222_REG_OFFSET 0x3bc
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_222_OP_222_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_222_OP_222_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_222_OP_222_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_222_OP_222_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_222_OP_222_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_223_REG_OFFSET 0x3c0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_223_OP_223_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_223_OP_223_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_223_OP_223_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_223_OP_223_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_223_OP_223_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_224_REG_OFFSET 0x3c4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_224_OP_224_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_224_OP_224_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_224_OP_224_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_224_OP_224_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_224_OP_224_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_225_REG_OFFSET 0x3c8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_225_OP_225_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_225_OP_225_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_225_OP_225_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_225_OP_225_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_225_OP_225_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_226_REG_OFFSET 0x3cc
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_226_OP_226_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_226_OP_226_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_226_OP_226_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_226_OP_226_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_226_OP_226_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_227_REG_OFFSET 0x3d0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_227_OP_227_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_227_OP_227_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_227_OP_227_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_227_OP_227_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_227_OP_227_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_228_REG_OFFSET 0x3d4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_228_OP_228_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_228_OP_228_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_228_OP_228_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_228_OP_228_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_228_OP_228_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_229_REG_OFFSET 0x3d8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_229_OP_229_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_229_OP_229_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_229_OP_229_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_229_OP_229_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_229_OP_229_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_230_REG_OFFSET 0x3dc
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_230_OP_230_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_230_OP_230_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_230_OP_230_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_230_OP_230_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_230_OP_230_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_231_REG_OFFSET 0x3e0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_231_OP_231_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_231_OP_231_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_231_OP_231_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_231_OP_231_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_231_OP_231_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_232_REG_OFFSET 0x3e4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_232_OP_232_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_232_OP_232_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_232_OP_232_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_232_OP_232_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_232_OP_232_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_233_REG_OFFSET 0x3e8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_233_OP_233_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_233_OP_233_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_233_OP_233_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_233_OP_233_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_233_OP_233_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_234_REG_OFFSET 0x3ec
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_234_OP_234_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_234_OP_234_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_234_OP_234_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_234_OP_234_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_234_OP_234_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_235_REG_OFFSET 0x3f0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_235_OP_235_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_235_OP_235_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_235_OP_235_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_235_OP_235_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_235_OP_235_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_236_REG_OFFSET 0x3f4
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_236_OP_236_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_236_OP_236_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_236_OP_236_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_236_OP_236_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_236_OP_236_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_237_REG_OFFSET 0x3f8
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_237_OP_237_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_237_OP_237_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_237_OP_237_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_237_OP_237_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_237_OP_237_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_238_REG_OFFSET 0x3fc
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_238_OP_238_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_238_OP_238_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_238_OP_238_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_238_OP_238_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_238_OP_238_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_239_REG_OFFSET 0x400
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_239_OP_239_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_239_OP_239_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_239_OP_239_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_239_OP_239_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_239_OP_239_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_240_REG_OFFSET 0x404
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_240_OP_240_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_240_OP_240_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_240_OP_240_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_240_OP_240_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_240_OP_240_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_241_REG_OFFSET 0x408
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_241_OP_241_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_241_OP_241_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_241_OP_241_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_241_OP_241_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_241_OP_241_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_242_REG_OFFSET 0x40c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_242_OP_242_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_242_OP_242_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_242_OP_242_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_242_OP_242_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_242_OP_242_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_243_REG_OFFSET 0x410
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_243_OP_243_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_243_OP_243_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_243_OP_243_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_243_OP_243_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_243_OP_243_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_244_REG_OFFSET 0x414
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_244_OP_244_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_244_OP_244_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_244_OP_244_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_244_OP_244_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_244_OP_244_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_245_REG_OFFSET 0x418
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_245_OP_245_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_245_OP_245_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_245_OP_245_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_245_OP_245_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_245_OP_245_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_246_REG_OFFSET 0x41c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_246_OP_246_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_246_OP_246_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_246_OP_246_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_246_OP_246_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_246_OP_246_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_247_REG_OFFSET 0x420
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_247_OP_247_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_247_OP_247_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_247_OP_247_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_247_OP_247_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_247_OP_247_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_248_REG_OFFSET 0x424
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_248_OP_248_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_248_OP_248_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_248_OP_248_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_248_OP_248_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_248_OP_248_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_249_REG_OFFSET 0x428
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_249_OP_249_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_249_OP_249_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_249_OP_249_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_249_OP_249_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_249_OP_249_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_250_REG_OFFSET 0x42c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_250_OP_250_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_250_OP_250_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_250_OP_250_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_250_OP_250_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_250_OP_250_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_251_REG_OFFSET 0x430
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_251_OP_251_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_251_OP_251_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_251_OP_251_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_251_OP_251_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_251_OP_251_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_252_REG_OFFSET 0x434
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_252_OP_252_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_252_OP_252_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_252_OP_252_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_252_OP_252_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_252_OP_252_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_253_REG_OFFSET 0x438
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_253_OP_253_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_253_OP_253_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_253_OP_253_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_253_OP_253_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_253_OP_253_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_254_REG_OFFSET 0x43c
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_254_OP_254_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_254_OP_254_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_254_OP_254_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_254_OP_254_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_254_OP_254_OFFSET})

// Per-core LP1 CMO opcode.  0 = FENCE (write-through WBUF drain),
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_255_REG_OFFSET 0x440
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_255_OP_255_MASK 0x7
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_255_OP_255_OFFSET 0
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_255_OP_255_FIELD                      \
  ((bitfield_field32_t){                                                       \
      .mask = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_255_OP_255_MASK,                \
      .index = CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_255_OP_255_OFFSET})

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_ADDR_FIELD_WIDTH 32
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_ADDR_FIELDS_PER_REG 1
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_MULTIREG_COUNT 256

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_0_REG_OFFSET 0x444

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_1_REG_OFFSET 0x448

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_2_REG_OFFSET 0x44c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_3_REG_OFFSET 0x450

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_4_REG_OFFSET 0x454

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_5_REG_OFFSET 0x458

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_6_REG_OFFSET 0x45c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_7_REG_OFFSET 0x460

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_8_REG_OFFSET 0x464

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_9_REG_OFFSET 0x468

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_10_REG_OFFSET 0x46c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_11_REG_OFFSET 0x470

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_12_REG_OFFSET 0x474

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_13_REG_OFFSET 0x478

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_14_REG_OFFSET 0x47c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_15_REG_OFFSET 0x480

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_16_REG_OFFSET 0x484

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_17_REG_OFFSET 0x488

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_18_REG_OFFSET 0x48c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_19_REG_OFFSET 0x490

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_20_REG_OFFSET 0x494

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_21_REG_OFFSET 0x498

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_22_REG_OFFSET 0x49c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_23_REG_OFFSET 0x4a0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_24_REG_OFFSET 0x4a4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_25_REG_OFFSET 0x4a8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_26_REG_OFFSET 0x4ac

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_27_REG_OFFSET 0x4b0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_28_REG_OFFSET 0x4b4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_29_REG_OFFSET 0x4b8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_30_REG_OFFSET 0x4bc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_31_REG_OFFSET 0x4c0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_32_REG_OFFSET 0x4c4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_33_REG_OFFSET 0x4c8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_34_REG_OFFSET 0x4cc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_35_REG_OFFSET 0x4d0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_36_REG_OFFSET 0x4d4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_37_REG_OFFSET 0x4d8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_38_REG_OFFSET 0x4dc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_39_REG_OFFSET 0x4e0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_40_REG_OFFSET 0x4e4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_41_REG_OFFSET 0x4e8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_42_REG_OFFSET 0x4ec

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_43_REG_OFFSET 0x4f0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_44_REG_OFFSET 0x4f4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_45_REG_OFFSET 0x4f8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_46_REG_OFFSET 0x4fc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_47_REG_OFFSET 0x500

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_48_REG_OFFSET 0x504

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_49_REG_OFFSET 0x508

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_50_REG_OFFSET 0x50c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_51_REG_OFFSET 0x510

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_52_REG_OFFSET 0x514

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_53_REG_OFFSET 0x518

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_54_REG_OFFSET 0x51c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_55_REG_OFFSET 0x520

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_56_REG_OFFSET 0x524

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_57_REG_OFFSET 0x528

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_58_REG_OFFSET 0x52c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_59_REG_OFFSET 0x530

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_60_REG_OFFSET 0x534

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_61_REG_OFFSET 0x538

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_62_REG_OFFSET 0x53c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_63_REG_OFFSET 0x540

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_64_REG_OFFSET 0x544

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_65_REG_OFFSET 0x548

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_66_REG_OFFSET 0x54c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_67_REG_OFFSET 0x550

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_68_REG_OFFSET 0x554

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_69_REG_OFFSET 0x558

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_70_REG_OFFSET 0x55c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_71_REG_OFFSET 0x560

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_72_REG_OFFSET 0x564

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_73_REG_OFFSET 0x568

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_74_REG_OFFSET 0x56c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_75_REG_OFFSET 0x570

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_76_REG_OFFSET 0x574

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_77_REG_OFFSET 0x578

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_78_REG_OFFSET 0x57c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_79_REG_OFFSET 0x580

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_80_REG_OFFSET 0x584

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_81_REG_OFFSET 0x588

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_82_REG_OFFSET 0x58c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_83_REG_OFFSET 0x590

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_84_REG_OFFSET 0x594

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_85_REG_OFFSET 0x598

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_86_REG_OFFSET 0x59c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_87_REG_OFFSET 0x5a0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_88_REG_OFFSET 0x5a4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_89_REG_OFFSET 0x5a8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_90_REG_OFFSET 0x5ac

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_91_REG_OFFSET 0x5b0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_92_REG_OFFSET 0x5b4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_93_REG_OFFSET 0x5b8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_94_REG_OFFSET 0x5bc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_95_REG_OFFSET 0x5c0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_96_REG_OFFSET 0x5c4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_97_REG_OFFSET 0x5c8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_98_REG_OFFSET 0x5cc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_99_REG_OFFSET 0x5d0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_100_REG_OFFSET 0x5d4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_101_REG_OFFSET 0x5d8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_102_REG_OFFSET 0x5dc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_103_REG_OFFSET 0x5e0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_104_REG_OFFSET 0x5e4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_105_REG_OFFSET 0x5e8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_106_REG_OFFSET 0x5ec

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_107_REG_OFFSET 0x5f0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_108_REG_OFFSET 0x5f4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_109_REG_OFFSET 0x5f8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_110_REG_OFFSET 0x5fc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_111_REG_OFFSET 0x600

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_112_REG_OFFSET 0x604

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_113_REG_OFFSET 0x608

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_114_REG_OFFSET 0x60c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_115_REG_OFFSET 0x610

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_116_REG_OFFSET 0x614

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_117_REG_OFFSET 0x618

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_118_REG_OFFSET 0x61c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_119_REG_OFFSET 0x620

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_120_REG_OFFSET 0x624

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_121_REG_OFFSET 0x628

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_122_REG_OFFSET 0x62c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_123_REG_OFFSET 0x630

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_124_REG_OFFSET 0x634

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_125_REG_OFFSET 0x638

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_126_REG_OFFSET 0x63c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_127_REG_OFFSET 0x640

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_128_REG_OFFSET 0x644

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_129_REG_OFFSET 0x648

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_130_REG_OFFSET 0x64c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_131_REG_OFFSET 0x650

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_132_REG_OFFSET 0x654

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_133_REG_OFFSET 0x658

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_134_REG_OFFSET 0x65c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_135_REG_OFFSET 0x660

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_136_REG_OFFSET 0x664

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_137_REG_OFFSET 0x668

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_138_REG_OFFSET 0x66c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_139_REG_OFFSET 0x670

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_140_REG_OFFSET 0x674

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_141_REG_OFFSET 0x678

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_142_REG_OFFSET 0x67c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_143_REG_OFFSET 0x680

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_144_REG_OFFSET 0x684

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_145_REG_OFFSET 0x688

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_146_REG_OFFSET 0x68c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_147_REG_OFFSET 0x690

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_148_REG_OFFSET 0x694

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_149_REG_OFFSET 0x698

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_150_REG_OFFSET 0x69c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_151_REG_OFFSET 0x6a0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_152_REG_OFFSET 0x6a4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_153_REG_OFFSET 0x6a8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_154_REG_OFFSET 0x6ac

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_155_REG_OFFSET 0x6b0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_156_REG_OFFSET 0x6b4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_157_REG_OFFSET 0x6b8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_158_REG_OFFSET 0x6bc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_159_REG_OFFSET 0x6c0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_160_REG_OFFSET 0x6c4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_161_REG_OFFSET 0x6c8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_162_REG_OFFSET 0x6cc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_163_REG_OFFSET 0x6d0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_164_REG_OFFSET 0x6d4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_165_REG_OFFSET 0x6d8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_166_REG_OFFSET 0x6dc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_167_REG_OFFSET 0x6e0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_168_REG_OFFSET 0x6e4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_169_REG_OFFSET 0x6e8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_170_REG_OFFSET 0x6ec

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_171_REG_OFFSET 0x6f0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_172_REG_OFFSET 0x6f4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_173_REG_OFFSET 0x6f8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_174_REG_OFFSET 0x6fc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_175_REG_OFFSET 0x700

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_176_REG_OFFSET 0x704

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_177_REG_OFFSET 0x708

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_178_REG_OFFSET 0x70c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_179_REG_OFFSET 0x710

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_180_REG_OFFSET 0x714

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_181_REG_OFFSET 0x718

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_182_REG_OFFSET 0x71c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_183_REG_OFFSET 0x720

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_184_REG_OFFSET 0x724

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_185_REG_OFFSET 0x728

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_186_REG_OFFSET 0x72c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_187_REG_OFFSET 0x730

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_188_REG_OFFSET 0x734

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_189_REG_OFFSET 0x738

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_190_REG_OFFSET 0x73c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_191_REG_OFFSET 0x740

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_192_REG_OFFSET 0x744

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_193_REG_OFFSET 0x748

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_194_REG_OFFSET 0x74c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_195_REG_OFFSET 0x750

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_196_REG_OFFSET 0x754

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_197_REG_OFFSET 0x758

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_198_REG_OFFSET 0x75c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_199_REG_OFFSET 0x760

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_200_REG_OFFSET 0x764

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_201_REG_OFFSET 0x768

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_202_REG_OFFSET 0x76c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_203_REG_OFFSET 0x770

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_204_REG_OFFSET 0x774

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_205_REG_OFFSET 0x778

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_206_REG_OFFSET 0x77c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_207_REG_OFFSET 0x780

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_208_REG_OFFSET 0x784

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_209_REG_OFFSET 0x788

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_210_REG_OFFSET 0x78c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_211_REG_OFFSET 0x790

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_212_REG_OFFSET 0x794

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_213_REG_OFFSET 0x798

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_214_REG_OFFSET 0x79c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_215_REG_OFFSET 0x7a0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_216_REG_OFFSET 0x7a4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_217_REG_OFFSET 0x7a8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_218_REG_OFFSET 0x7ac

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_219_REG_OFFSET 0x7b0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_220_REG_OFFSET 0x7b4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_221_REG_OFFSET 0x7b8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_222_REG_OFFSET 0x7bc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_223_REG_OFFSET 0x7c0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_224_REG_OFFSET 0x7c4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_225_REG_OFFSET 0x7c8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_226_REG_OFFSET 0x7cc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_227_REG_OFFSET 0x7d0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_228_REG_OFFSET 0x7d4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_229_REG_OFFSET 0x7d8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_230_REG_OFFSET 0x7dc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_231_REG_OFFSET 0x7e0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_232_REG_OFFSET 0x7e4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_233_REG_OFFSET 0x7e8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_234_REG_OFFSET 0x7ec

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_235_REG_OFFSET 0x7f0

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_236_REG_OFFSET 0x7f4

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_237_REG_OFFSET 0x7f8

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_238_REG_OFFSET 0x7fc

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_239_REG_OFFSET 0x800

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_240_REG_OFFSET 0x804

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_241_REG_OFFSET 0x808

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_242_REG_OFFSET 0x80c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_243_REG_OFFSET 0x810

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_244_REG_OFFSET 0x814

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_245_REG_OFFSET 0x818

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_246_REG_OFFSET 0x81c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_247_REG_OFFSET 0x820

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_248_REG_OFFSET 0x824

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_249_REG_OFFSET 0x828

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_250_REG_OFFSET 0x82c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_251_REG_OFFSET 0x830

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_252_REG_OFFSET 0x834

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_253_REG_OFFSET 0x838

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_254_REG_OFFSET 0x83c

// Per-core cacheline address for LP1 INVAL_NLINE.  Ignored for
#define CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_255_REG_OFFSET 0x840

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_COMMIT_FIELD_WIDTH 1
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_COMMIT_FIELDS_PER_REG 32
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_MULTIREG_COUNT 256

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_0_REG_OFFSET 0x844
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_0_COMMIT_0_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_1_REG_OFFSET 0x848
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_1_COMMIT_1_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_2_REG_OFFSET 0x84c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_2_COMMIT_2_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_3_REG_OFFSET 0x850
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_3_COMMIT_3_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_4_REG_OFFSET 0x854
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_4_COMMIT_4_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_5_REG_OFFSET 0x858
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_5_COMMIT_5_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_6_REG_OFFSET 0x85c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_6_COMMIT_6_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_7_REG_OFFSET 0x860
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_7_COMMIT_7_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_8_REG_OFFSET 0x864
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_8_COMMIT_8_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_9_REG_OFFSET 0x868
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_9_COMMIT_9_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_10_REG_OFFSET 0x86c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_10_COMMIT_10_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_11_REG_OFFSET 0x870
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_11_COMMIT_11_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_12_REG_OFFSET 0x874
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_12_COMMIT_12_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_13_REG_OFFSET 0x878
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_13_COMMIT_13_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_14_REG_OFFSET 0x87c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_14_COMMIT_14_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_15_REG_OFFSET 0x880
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_15_COMMIT_15_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_16_REG_OFFSET 0x884
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_16_COMMIT_16_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_17_REG_OFFSET 0x888
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_17_COMMIT_17_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_18_REG_OFFSET 0x88c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_18_COMMIT_18_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_19_REG_OFFSET 0x890
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_19_COMMIT_19_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_20_REG_OFFSET 0x894
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_20_COMMIT_20_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_21_REG_OFFSET 0x898
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_21_COMMIT_21_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_22_REG_OFFSET 0x89c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_22_COMMIT_22_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_23_REG_OFFSET 0x8a0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_23_COMMIT_23_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_24_REG_OFFSET 0x8a4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_24_COMMIT_24_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_25_REG_OFFSET 0x8a8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_25_COMMIT_25_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_26_REG_OFFSET 0x8ac
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_26_COMMIT_26_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_27_REG_OFFSET 0x8b0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_27_COMMIT_27_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_28_REG_OFFSET 0x8b4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_28_COMMIT_28_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_29_REG_OFFSET 0x8b8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_29_COMMIT_29_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_30_REG_OFFSET 0x8bc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_30_COMMIT_30_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_31_REG_OFFSET 0x8c0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_31_COMMIT_31_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_32_REG_OFFSET 0x8c4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_32_COMMIT_32_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_33_REG_OFFSET 0x8c8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_33_COMMIT_33_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_34_REG_OFFSET 0x8cc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_34_COMMIT_34_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_35_REG_OFFSET 0x8d0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_35_COMMIT_35_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_36_REG_OFFSET 0x8d4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_36_COMMIT_36_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_37_REG_OFFSET 0x8d8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_37_COMMIT_37_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_38_REG_OFFSET 0x8dc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_38_COMMIT_38_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_39_REG_OFFSET 0x8e0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_39_COMMIT_39_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_40_REG_OFFSET 0x8e4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_40_COMMIT_40_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_41_REG_OFFSET 0x8e8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_41_COMMIT_41_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_42_REG_OFFSET 0x8ec
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_42_COMMIT_42_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_43_REG_OFFSET 0x8f0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_43_COMMIT_43_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_44_REG_OFFSET 0x8f4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_44_COMMIT_44_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_45_REG_OFFSET 0x8f8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_45_COMMIT_45_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_46_REG_OFFSET 0x8fc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_46_COMMIT_46_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_47_REG_OFFSET 0x900
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_47_COMMIT_47_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_48_REG_OFFSET 0x904
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_48_COMMIT_48_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_49_REG_OFFSET 0x908
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_49_COMMIT_49_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_50_REG_OFFSET 0x90c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_50_COMMIT_50_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_51_REG_OFFSET 0x910
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_51_COMMIT_51_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_52_REG_OFFSET 0x914
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_52_COMMIT_52_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_53_REG_OFFSET 0x918
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_53_COMMIT_53_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_54_REG_OFFSET 0x91c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_54_COMMIT_54_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_55_REG_OFFSET 0x920
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_55_COMMIT_55_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_56_REG_OFFSET 0x924
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_56_COMMIT_56_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_57_REG_OFFSET 0x928
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_57_COMMIT_57_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_58_REG_OFFSET 0x92c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_58_COMMIT_58_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_59_REG_OFFSET 0x930
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_59_COMMIT_59_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_60_REG_OFFSET 0x934
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_60_COMMIT_60_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_61_REG_OFFSET 0x938
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_61_COMMIT_61_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_62_REG_OFFSET 0x93c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_62_COMMIT_62_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_63_REG_OFFSET 0x940
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_63_COMMIT_63_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_64_REG_OFFSET 0x944
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_64_COMMIT_64_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_65_REG_OFFSET 0x948
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_65_COMMIT_65_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_66_REG_OFFSET 0x94c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_66_COMMIT_66_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_67_REG_OFFSET 0x950
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_67_COMMIT_67_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_68_REG_OFFSET 0x954
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_68_COMMIT_68_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_69_REG_OFFSET 0x958
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_69_COMMIT_69_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_70_REG_OFFSET 0x95c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_70_COMMIT_70_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_71_REG_OFFSET 0x960
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_71_COMMIT_71_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_72_REG_OFFSET 0x964
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_72_COMMIT_72_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_73_REG_OFFSET 0x968
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_73_COMMIT_73_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_74_REG_OFFSET 0x96c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_74_COMMIT_74_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_75_REG_OFFSET 0x970
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_75_COMMIT_75_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_76_REG_OFFSET 0x974
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_76_COMMIT_76_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_77_REG_OFFSET 0x978
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_77_COMMIT_77_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_78_REG_OFFSET 0x97c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_78_COMMIT_78_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_79_REG_OFFSET 0x980
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_79_COMMIT_79_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_80_REG_OFFSET 0x984
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_80_COMMIT_80_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_81_REG_OFFSET 0x988
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_81_COMMIT_81_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_82_REG_OFFSET 0x98c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_82_COMMIT_82_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_83_REG_OFFSET 0x990
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_83_COMMIT_83_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_84_REG_OFFSET 0x994
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_84_COMMIT_84_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_85_REG_OFFSET 0x998
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_85_COMMIT_85_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_86_REG_OFFSET 0x99c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_86_COMMIT_86_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_87_REG_OFFSET 0x9a0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_87_COMMIT_87_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_88_REG_OFFSET 0x9a4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_88_COMMIT_88_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_89_REG_OFFSET 0x9a8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_89_COMMIT_89_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_90_REG_OFFSET 0x9ac
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_90_COMMIT_90_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_91_REG_OFFSET 0x9b0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_91_COMMIT_91_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_92_REG_OFFSET 0x9b4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_92_COMMIT_92_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_93_REG_OFFSET 0x9b8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_93_COMMIT_93_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_94_REG_OFFSET 0x9bc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_94_COMMIT_94_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_95_REG_OFFSET 0x9c0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_95_COMMIT_95_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_96_REG_OFFSET 0x9c4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_96_COMMIT_96_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_97_REG_OFFSET 0x9c8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_97_COMMIT_97_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_98_REG_OFFSET 0x9cc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_98_COMMIT_98_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_99_REG_OFFSET 0x9d0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_99_COMMIT_99_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_100_REG_OFFSET 0x9d4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_100_COMMIT_100_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_101_REG_OFFSET 0x9d8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_101_COMMIT_101_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_102_REG_OFFSET 0x9dc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_102_COMMIT_102_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_103_REG_OFFSET 0x9e0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_103_COMMIT_103_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_104_REG_OFFSET 0x9e4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_104_COMMIT_104_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_105_REG_OFFSET 0x9e8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_105_COMMIT_105_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_106_REG_OFFSET 0x9ec
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_106_COMMIT_106_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_107_REG_OFFSET 0x9f0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_107_COMMIT_107_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_108_REG_OFFSET 0x9f4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_108_COMMIT_108_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_109_REG_OFFSET 0x9f8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_109_COMMIT_109_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_110_REG_OFFSET 0x9fc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_110_COMMIT_110_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_111_REG_OFFSET 0xa00
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_111_COMMIT_111_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_112_REG_OFFSET 0xa04
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_112_COMMIT_112_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_113_REG_OFFSET 0xa08
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_113_COMMIT_113_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_114_REG_OFFSET 0xa0c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_114_COMMIT_114_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_115_REG_OFFSET 0xa10
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_115_COMMIT_115_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_116_REG_OFFSET 0xa14
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_116_COMMIT_116_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_117_REG_OFFSET 0xa18
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_117_COMMIT_117_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_118_REG_OFFSET 0xa1c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_118_COMMIT_118_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_119_REG_OFFSET 0xa20
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_119_COMMIT_119_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_120_REG_OFFSET 0xa24
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_120_COMMIT_120_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_121_REG_OFFSET 0xa28
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_121_COMMIT_121_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_122_REG_OFFSET 0xa2c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_122_COMMIT_122_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_123_REG_OFFSET 0xa30
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_123_COMMIT_123_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_124_REG_OFFSET 0xa34
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_124_COMMIT_124_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_125_REG_OFFSET 0xa38
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_125_COMMIT_125_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_126_REG_OFFSET 0xa3c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_126_COMMIT_126_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_127_REG_OFFSET 0xa40
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_127_COMMIT_127_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_128_REG_OFFSET 0xa44
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_128_COMMIT_128_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_129_REG_OFFSET 0xa48
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_129_COMMIT_129_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_130_REG_OFFSET 0xa4c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_130_COMMIT_130_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_131_REG_OFFSET 0xa50
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_131_COMMIT_131_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_132_REG_OFFSET 0xa54
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_132_COMMIT_132_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_133_REG_OFFSET 0xa58
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_133_COMMIT_133_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_134_REG_OFFSET 0xa5c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_134_COMMIT_134_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_135_REG_OFFSET 0xa60
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_135_COMMIT_135_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_136_REG_OFFSET 0xa64
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_136_COMMIT_136_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_137_REG_OFFSET 0xa68
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_137_COMMIT_137_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_138_REG_OFFSET 0xa6c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_138_COMMIT_138_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_139_REG_OFFSET 0xa70
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_139_COMMIT_139_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_140_REG_OFFSET 0xa74
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_140_COMMIT_140_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_141_REG_OFFSET 0xa78
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_141_COMMIT_141_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_142_REG_OFFSET 0xa7c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_142_COMMIT_142_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_143_REG_OFFSET 0xa80
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_143_COMMIT_143_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_144_REG_OFFSET 0xa84
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_144_COMMIT_144_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_145_REG_OFFSET 0xa88
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_145_COMMIT_145_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_146_REG_OFFSET 0xa8c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_146_COMMIT_146_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_147_REG_OFFSET 0xa90
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_147_COMMIT_147_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_148_REG_OFFSET 0xa94
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_148_COMMIT_148_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_149_REG_OFFSET 0xa98
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_149_COMMIT_149_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_150_REG_OFFSET 0xa9c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_150_COMMIT_150_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_151_REG_OFFSET 0xaa0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_151_COMMIT_151_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_152_REG_OFFSET 0xaa4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_152_COMMIT_152_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_153_REG_OFFSET 0xaa8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_153_COMMIT_153_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_154_REG_OFFSET 0xaac
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_154_COMMIT_154_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_155_REG_OFFSET 0xab0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_155_COMMIT_155_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_156_REG_OFFSET 0xab4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_156_COMMIT_156_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_157_REG_OFFSET 0xab8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_157_COMMIT_157_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_158_REG_OFFSET 0xabc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_158_COMMIT_158_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_159_REG_OFFSET 0xac0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_159_COMMIT_159_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_160_REG_OFFSET 0xac4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_160_COMMIT_160_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_161_REG_OFFSET 0xac8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_161_COMMIT_161_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_162_REG_OFFSET 0xacc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_162_COMMIT_162_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_163_REG_OFFSET 0xad0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_163_COMMIT_163_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_164_REG_OFFSET 0xad4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_164_COMMIT_164_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_165_REG_OFFSET 0xad8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_165_COMMIT_165_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_166_REG_OFFSET 0xadc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_166_COMMIT_166_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_167_REG_OFFSET 0xae0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_167_COMMIT_167_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_168_REG_OFFSET 0xae4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_168_COMMIT_168_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_169_REG_OFFSET 0xae8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_169_COMMIT_169_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_170_REG_OFFSET 0xaec
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_170_COMMIT_170_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_171_REG_OFFSET 0xaf0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_171_COMMIT_171_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_172_REG_OFFSET 0xaf4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_172_COMMIT_172_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_173_REG_OFFSET 0xaf8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_173_COMMIT_173_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_174_REG_OFFSET 0xafc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_174_COMMIT_174_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_175_REG_OFFSET 0xb00
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_175_COMMIT_175_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_176_REG_OFFSET 0xb04
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_176_COMMIT_176_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_177_REG_OFFSET 0xb08
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_177_COMMIT_177_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_178_REG_OFFSET 0xb0c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_178_COMMIT_178_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_179_REG_OFFSET 0xb10
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_179_COMMIT_179_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_180_REG_OFFSET 0xb14
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_180_COMMIT_180_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_181_REG_OFFSET 0xb18
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_181_COMMIT_181_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_182_REG_OFFSET 0xb1c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_182_COMMIT_182_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_183_REG_OFFSET 0xb20
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_183_COMMIT_183_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_184_REG_OFFSET 0xb24
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_184_COMMIT_184_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_185_REG_OFFSET 0xb28
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_185_COMMIT_185_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_186_REG_OFFSET 0xb2c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_186_COMMIT_186_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_187_REG_OFFSET 0xb30
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_187_COMMIT_187_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_188_REG_OFFSET 0xb34
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_188_COMMIT_188_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_189_REG_OFFSET 0xb38
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_189_COMMIT_189_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_190_REG_OFFSET 0xb3c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_190_COMMIT_190_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_191_REG_OFFSET 0xb40
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_191_COMMIT_191_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_192_REG_OFFSET 0xb44
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_192_COMMIT_192_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_193_REG_OFFSET 0xb48
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_193_COMMIT_193_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_194_REG_OFFSET 0xb4c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_194_COMMIT_194_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_195_REG_OFFSET 0xb50
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_195_COMMIT_195_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_196_REG_OFFSET 0xb54
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_196_COMMIT_196_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_197_REG_OFFSET 0xb58
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_197_COMMIT_197_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_198_REG_OFFSET 0xb5c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_198_COMMIT_198_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_199_REG_OFFSET 0xb60
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_199_COMMIT_199_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_200_REG_OFFSET 0xb64
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_200_COMMIT_200_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_201_REG_OFFSET 0xb68
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_201_COMMIT_201_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_202_REG_OFFSET 0xb6c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_202_COMMIT_202_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_203_REG_OFFSET 0xb70
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_203_COMMIT_203_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_204_REG_OFFSET 0xb74
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_204_COMMIT_204_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_205_REG_OFFSET 0xb78
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_205_COMMIT_205_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_206_REG_OFFSET 0xb7c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_206_COMMIT_206_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_207_REG_OFFSET 0xb80
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_207_COMMIT_207_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_208_REG_OFFSET 0xb84
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_208_COMMIT_208_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_209_REG_OFFSET 0xb88
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_209_COMMIT_209_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_210_REG_OFFSET 0xb8c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_210_COMMIT_210_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_211_REG_OFFSET 0xb90
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_211_COMMIT_211_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_212_REG_OFFSET 0xb94
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_212_COMMIT_212_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_213_REG_OFFSET 0xb98
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_213_COMMIT_213_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_214_REG_OFFSET 0xb9c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_214_COMMIT_214_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_215_REG_OFFSET 0xba0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_215_COMMIT_215_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_216_REG_OFFSET 0xba4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_216_COMMIT_216_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_217_REG_OFFSET 0xba8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_217_COMMIT_217_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_218_REG_OFFSET 0xbac
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_218_COMMIT_218_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_219_REG_OFFSET 0xbb0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_219_COMMIT_219_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_220_REG_OFFSET 0xbb4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_220_COMMIT_220_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_221_REG_OFFSET 0xbb8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_221_COMMIT_221_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_222_REG_OFFSET 0xbbc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_222_COMMIT_222_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_223_REG_OFFSET 0xbc0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_223_COMMIT_223_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_224_REG_OFFSET 0xbc4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_224_COMMIT_224_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_225_REG_OFFSET 0xbc8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_225_COMMIT_225_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_226_REG_OFFSET 0xbcc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_226_COMMIT_226_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_227_REG_OFFSET 0xbd0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_227_COMMIT_227_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_228_REG_OFFSET 0xbd4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_228_COMMIT_228_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_229_REG_OFFSET 0xbd8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_229_COMMIT_229_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_230_REG_OFFSET 0xbdc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_230_COMMIT_230_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_231_REG_OFFSET 0xbe0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_231_COMMIT_231_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_232_REG_OFFSET 0xbe4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_232_COMMIT_232_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_233_REG_OFFSET 0xbe8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_233_COMMIT_233_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_234_REG_OFFSET 0xbec
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_234_COMMIT_234_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_235_REG_OFFSET 0xbf0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_235_COMMIT_235_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_236_REG_OFFSET 0xbf4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_236_COMMIT_236_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_237_REG_OFFSET 0xbf8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_237_COMMIT_237_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_238_REG_OFFSET 0xbfc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_238_COMMIT_238_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_239_REG_OFFSET 0xc00
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_239_COMMIT_239_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_240_REG_OFFSET 0xc04
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_240_COMMIT_240_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_241_REG_OFFSET 0xc08
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_241_COMMIT_241_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_242_REG_OFFSET 0xc0c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_242_COMMIT_242_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_243_REG_OFFSET 0xc10
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_243_COMMIT_243_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_244_REG_OFFSET 0xc14
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_244_COMMIT_244_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_245_REG_OFFSET 0xc18
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_245_COMMIT_245_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_246_REG_OFFSET 0xc1c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_246_COMMIT_246_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_247_REG_OFFSET 0xc20
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_247_COMMIT_247_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_248_REG_OFFSET 0xc24
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_248_COMMIT_248_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_249_REG_OFFSET 0xc28
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_249_COMMIT_249_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_250_REG_OFFSET 0xc2c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_250_COMMIT_250_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_251_REG_OFFSET 0xc30
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_251_COMMIT_251_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_252_REG_OFFSET 0xc34
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_252_COMMIT_252_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_253_REG_OFFSET 0xc38
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_253_COMMIT_253_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_254_REG_OFFSET 0xc3c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_254_COMMIT_254_BIT 0

// Per-core LP1 CMO trigger.  SW writes 1 to commit the opcode in
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_255_REG_OFFSET 0xc40
#define CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_255_COMMIT_255_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_STATUS_FIELD_WIDTH 1
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_STATUS_FIELDS_PER_REG 32
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_MULTIREG_COUNT 256

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_0_REG_OFFSET 0xc44
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_0_STATUS_0_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_1_REG_OFFSET 0xc48
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_1_STATUS_1_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_2_REG_OFFSET 0xc4c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_2_STATUS_2_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_3_REG_OFFSET 0xc50
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_3_STATUS_3_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_4_REG_OFFSET 0xc54
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_4_STATUS_4_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_5_REG_OFFSET 0xc58
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_5_STATUS_5_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_6_REG_OFFSET 0xc5c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_6_STATUS_6_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_7_REG_OFFSET 0xc60
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_7_STATUS_7_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_8_REG_OFFSET 0xc64
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_8_STATUS_8_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_9_REG_OFFSET 0xc68
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_9_STATUS_9_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_10_REG_OFFSET 0xc6c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_10_STATUS_10_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_11_REG_OFFSET 0xc70
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_11_STATUS_11_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_12_REG_OFFSET 0xc74
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_12_STATUS_12_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_13_REG_OFFSET 0xc78
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_13_STATUS_13_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_14_REG_OFFSET 0xc7c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_14_STATUS_14_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_15_REG_OFFSET 0xc80
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_15_STATUS_15_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_16_REG_OFFSET 0xc84
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_16_STATUS_16_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_17_REG_OFFSET 0xc88
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_17_STATUS_17_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_18_REG_OFFSET 0xc8c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_18_STATUS_18_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_19_REG_OFFSET 0xc90
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_19_STATUS_19_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_20_REG_OFFSET 0xc94
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_20_STATUS_20_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_21_REG_OFFSET 0xc98
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_21_STATUS_21_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_22_REG_OFFSET 0xc9c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_22_STATUS_22_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_23_REG_OFFSET 0xca0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_23_STATUS_23_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_24_REG_OFFSET 0xca4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_24_STATUS_24_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_25_REG_OFFSET 0xca8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_25_STATUS_25_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_26_REG_OFFSET 0xcac
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_26_STATUS_26_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_27_REG_OFFSET 0xcb0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_27_STATUS_27_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_28_REG_OFFSET 0xcb4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_28_STATUS_28_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_29_REG_OFFSET 0xcb8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_29_STATUS_29_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_30_REG_OFFSET 0xcbc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_30_STATUS_30_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_31_REG_OFFSET 0xcc0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_31_STATUS_31_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_32_REG_OFFSET 0xcc4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_32_STATUS_32_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_33_REG_OFFSET 0xcc8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_33_STATUS_33_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_34_REG_OFFSET 0xccc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_34_STATUS_34_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_35_REG_OFFSET 0xcd0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_35_STATUS_35_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_36_REG_OFFSET 0xcd4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_36_STATUS_36_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_37_REG_OFFSET 0xcd8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_37_STATUS_37_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_38_REG_OFFSET 0xcdc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_38_STATUS_38_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_39_REG_OFFSET 0xce0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_39_STATUS_39_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_40_REG_OFFSET 0xce4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_40_STATUS_40_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_41_REG_OFFSET 0xce8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_41_STATUS_41_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_42_REG_OFFSET 0xcec
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_42_STATUS_42_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_43_REG_OFFSET 0xcf0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_43_STATUS_43_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_44_REG_OFFSET 0xcf4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_44_STATUS_44_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_45_REG_OFFSET 0xcf8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_45_STATUS_45_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_46_REG_OFFSET 0xcfc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_46_STATUS_46_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_47_REG_OFFSET 0xd00
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_47_STATUS_47_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_48_REG_OFFSET 0xd04
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_48_STATUS_48_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_49_REG_OFFSET 0xd08
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_49_STATUS_49_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_50_REG_OFFSET 0xd0c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_50_STATUS_50_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_51_REG_OFFSET 0xd10
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_51_STATUS_51_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_52_REG_OFFSET 0xd14
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_52_STATUS_52_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_53_REG_OFFSET 0xd18
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_53_STATUS_53_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_54_REG_OFFSET 0xd1c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_54_STATUS_54_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_55_REG_OFFSET 0xd20
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_55_STATUS_55_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_56_REG_OFFSET 0xd24
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_56_STATUS_56_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_57_REG_OFFSET 0xd28
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_57_STATUS_57_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_58_REG_OFFSET 0xd2c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_58_STATUS_58_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_59_REG_OFFSET 0xd30
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_59_STATUS_59_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_60_REG_OFFSET 0xd34
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_60_STATUS_60_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_61_REG_OFFSET 0xd38
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_61_STATUS_61_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_62_REG_OFFSET 0xd3c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_62_STATUS_62_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_63_REG_OFFSET 0xd40
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_63_STATUS_63_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_64_REG_OFFSET 0xd44
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_64_STATUS_64_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_65_REG_OFFSET 0xd48
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_65_STATUS_65_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_66_REG_OFFSET 0xd4c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_66_STATUS_66_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_67_REG_OFFSET 0xd50
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_67_STATUS_67_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_68_REG_OFFSET 0xd54
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_68_STATUS_68_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_69_REG_OFFSET 0xd58
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_69_STATUS_69_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_70_REG_OFFSET 0xd5c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_70_STATUS_70_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_71_REG_OFFSET 0xd60
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_71_STATUS_71_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_72_REG_OFFSET 0xd64
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_72_STATUS_72_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_73_REG_OFFSET 0xd68
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_73_STATUS_73_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_74_REG_OFFSET 0xd6c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_74_STATUS_74_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_75_REG_OFFSET 0xd70
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_75_STATUS_75_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_76_REG_OFFSET 0xd74
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_76_STATUS_76_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_77_REG_OFFSET 0xd78
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_77_STATUS_77_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_78_REG_OFFSET 0xd7c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_78_STATUS_78_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_79_REG_OFFSET 0xd80
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_79_STATUS_79_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_80_REG_OFFSET 0xd84
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_80_STATUS_80_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_81_REG_OFFSET 0xd88
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_81_STATUS_81_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_82_REG_OFFSET 0xd8c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_82_STATUS_82_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_83_REG_OFFSET 0xd90
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_83_STATUS_83_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_84_REG_OFFSET 0xd94
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_84_STATUS_84_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_85_REG_OFFSET 0xd98
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_85_STATUS_85_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_86_REG_OFFSET 0xd9c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_86_STATUS_86_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_87_REG_OFFSET 0xda0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_87_STATUS_87_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_88_REG_OFFSET 0xda4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_88_STATUS_88_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_89_REG_OFFSET 0xda8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_89_STATUS_89_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_90_REG_OFFSET 0xdac
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_90_STATUS_90_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_91_REG_OFFSET 0xdb0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_91_STATUS_91_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_92_REG_OFFSET 0xdb4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_92_STATUS_92_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_93_REG_OFFSET 0xdb8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_93_STATUS_93_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_94_REG_OFFSET 0xdbc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_94_STATUS_94_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_95_REG_OFFSET 0xdc0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_95_STATUS_95_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_96_REG_OFFSET 0xdc4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_96_STATUS_96_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_97_REG_OFFSET 0xdc8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_97_STATUS_97_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_98_REG_OFFSET 0xdcc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_98_STATUS_98_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_99_REG_OFFSET 0xdd0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_99_STATUS_99_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_100_REG_OFFSET 0xdd4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_100_STATUS_100_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_101_REG_OFFSET 0xdd8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_101_STATUS_101_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_102_REG_OFFSET 0xddc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_102_STATUS_102_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_103_REG_OFFSET 0xde0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_103_STATUS_103_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_104_REG_OFFSET 0xde4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_104_STATUS_104_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_105_REG_OFFSET 0xde8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_105_STATUS_105_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_106_REG_OFFSET 0xdec
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_106_STATUS_106_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_107_REG_OFFSET 0xdf0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_107_STATUS_107_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_108_REG_OFFSET 0xdf4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_108_STATUS_108_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_109_REG_OFFSET 0xdf8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_109_STATUS_109_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_110_REG_OFFSET 0xdfc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_110_STATUS_110_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_111_REG_OFFSET 0xe00
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_111_STATUS_111_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_112_REG_OFFSET 0xe04
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_112_STATUS_112_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_113_REG_OFFSET 0xe08
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_113_STATUS_113_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_114_REG_OFFSET 0xe0c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_114_STATUS_114_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_115_REG_OFFSET 0xe10
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_115_STATUS_115_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_116_REG_OFFSET 0xe14
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_116_STATUS_116_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_117_REG_OFFSET 0xe18
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_117_STATUS_117_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_118_REG_OFFSET 0xe1c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_118_STATUS_118_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_119_REG_OFFSET 0xe20
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_119_STATUS_119_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_120_REG_OFFSET 0xe24
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_120_STATUS_120_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_121_REG_OFFSET 0xe28
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_121_STATUS_121_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_122_REG_OFFSET 0xe2c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_122_STATUS_122_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_123_REG_OFFSET 0xe30
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_123_STATUS_123_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_124_REG_OFFSET 0xe34
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_124_STATUS_124_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_125_REG_OFFSET 0xe38
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_125_STATUS_125_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_126_REG_OFFSET 0xe3c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_126_STATUS_126_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_127_REG_OFFSET 0xe40
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_127_STATUS_127_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_128_REG_OFFSET 0xe44
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_128_STATUS_128_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_129_REG_OFFSET 0xe48
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_129_STATUS_129_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_130_REG_OFFSET 0xe4c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_130_STATUS_130_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_131_REG_OFFSET 0xe50
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_131_STATUS_131_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_132_REG_OFFSET 0xe54
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_132_STATUS_132_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_133_REG_OFFSET 0xe58
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_133_STATUS_133_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_134_REG_OFFSET 0xe5c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_134_STATUS_134_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_135_REG_OFFSET 0xe60
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_135_STATUS_135_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_136_REG_OFFSET 0xe64
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_136_STATUS_136_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_137_REG_OFFSET 0xe68
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_137_STATUS_137_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_138_REG_OFFSET 0xe6c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_138_STATUS_138_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_139_REG_OFFSET 0xe70
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_139_STATUS_139_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_140_REG_OFFSET 0xe74
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_140_STATUS_140_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_141_REG_OFFSET 0xe78
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_141_STATUS_141_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_142_REG_OFFSET 0xe7c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_142_STATUS_142_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_143_REG_OFFSET 0xe80
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_143_STATUS_143_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_144_REG_OFFSET 0xe84
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_144_STATUS_144_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_145_REG_OFFSET 0xe88
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_145_STATUS_145_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_146_REG_OFFSET 0xe8c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_146_STATUS_146_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_147_REG_OFFSET 0xe90
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_147_STATUS_147_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_148_REG_OFFSET 0xe94
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_148_STATUS_148_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_149_REG_OFFSET 0xe98
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_149_STATUS_149_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_150_REG_OFFSET 0xe9c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_150_STATUS_150_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_151_REG_OFFSET 0xea0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_151_STATUS_151_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_152_REG_OFFSET 0xea4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_152_STATUS_152_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_153_REG_OFFSET 0xea8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_153_STATUS_153_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_154_REG_OFFSET 0xeac
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_154_STATUS_154_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_155_REG_OFFSET 0xeb0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_155_STATUS_155_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_156_REG_OFFSET 0xeb4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_156_STATUS_156_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_157_REG_OFFSET 0xeb8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_157_STATUS_157_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_158_REG_OFFSET 0xebc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_158_STATUS_158_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_159_REG_OFFSET 0xec0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_159_STATUS_159_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_160_REG_OFFSET 0xec4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_160_STATUS_160_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_161_REG_OFFSET 0xec8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_161_STATUS_161_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_162_REG_OFFSET 0xecc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_162_STATUS_162_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_163_REG_OFFSET 0xed0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_163_STATUS_163_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_164_REG_OFFSET 0xed4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_164_STATUS_164_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_165_REG_OFFSET 0xed8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_165_STATUS_165_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_166_REG_OFFSET 0xedc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_166_STATUS_166_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_167_REG_OFFSET 0xee0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_167_STATUS_167_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_168_REG_OFFSET 0xee4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_168_STATUS_168_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_169_REG_OFFSET 0xee8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_169_STATUS_169_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_170_REG_OFFSET 0xeec
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_170_STATUS_170_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_171_REG_OFFSET 0xef0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_171_STATUS_171_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_172_REG_OFFSET 0xef4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_172_STATUS_172_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_173_REG_OFFSET 0xef8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_173_STATUS_173_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_174_REG_OFFSET 0xefc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_174_STATUS_174_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_175_REG_OFFSET 0xf00
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_175_STATUS_175_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_176_REG_OFFSET 0xf04
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_176_STATUS_176_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_177_REG_OFFSET 0xf08
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_177_STATUS_177_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_178_REG_OFFSET 0xf0c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_178_STATUS_178_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_179_REG_OFFSET 0xf10
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_179_STATUS_179_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_180_REG_OFFSET 0xf14
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_180_STATUS_180_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_181_REG_OFFSET 0xf18
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_181_STATUS_181_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_182_REG_OFFSET 0xf1c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_182_STATUS_182_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_183_REG_OFFSET 0xf20
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_183_STATUS_183_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_184_REG_OFFSET 0xf24
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_184_STATUS_184_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_185_REG_OFFSET 0xf28
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_185_STATUS_185_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_186_REG_OFFSET 0xf2c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_186_STATUS_186_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_187_REG_OFFSET 0xf30
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_187_STATUS_187_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_188_REG_OFFSET 0xf34
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_188_STATUS_188_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_189_REG_OFFSET 0xf38
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_189_STATUS_189_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_190_REG_OFFSET 0xf3c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_190_STATUS_190_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_191_REG_OFFSET 0xf40
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_191_STATUS_191_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_192_REG_OFFSET 0xf44
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_192_STATUS_192_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_193_REG_OFFSET 0xf48
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_193_STATUS_193_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_194_REG_OFFSET 0xf4c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_194_STATUS_194_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_195_REG_OFFSET 0xf50
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_195_STATUS_195_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_196_REG_OFFSET 0xf54
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_196_STATUS_196_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_197_REG_OFFSET 0xf58
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_197_STATUS_197_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_198_REG_OFFSET 0xf5c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_198_STATUS_198_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_199_REG_OFFSET 0xf60
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_199_STATUS_199_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_200_REG_OFFSET 0xf64
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_200_STATUS_200_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_201_REG_OFFSET 0xf68
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_201_STATUS_201_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_202_REG_OFFSET 0xf6c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_202_STATUS_202_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_203_REG_OFFSET 0xf70
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_203_STATUS_203_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_204_REG_OFFSET 0xf74
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_204_STATUS_204_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_205_REG_OFFSET 0xf78
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_205_STATUS_205_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_206_REG_OFFSET 0xf7c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_206_STATUS_206_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_207_REG_OFFSET 0xf80
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_207_STATUS_207_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_208_REG_OFFSET 0xf84
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_208_STATUS_208_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_209_REG_OFFSET 0xf88
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_209_STATUS_209_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_210_REG_OFFSET 0xf8c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_210_STATUS_210_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_211_REG_OFFSET 0xf90
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_211_STATUS_211_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_212_REG_OFFSET 0xf94
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_212_STATUS_212_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_213_REG_OFFSET 0xf98
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_213_STATUS_213_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_214_REG_OFFSET 0xf9c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_214_STATUS_214_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_215_REG_OFFSET 0xfa0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_215_STATUS_215_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_216_REG_OFFSET 0xfa4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_216_STATUS_216_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_217_REG_OFFSET 0xfa8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_217_STATUS_217_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_218_REG_OFFSET 0xfac
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_218_STATUS_218_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_219_REG_OFFSET 0xfb0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_219_STATUS_219_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_220_REG_OFFSET 0xfb4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_220_STATUS_220_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_221_REG_OFFSET 0xfb8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_221_STATUS_221_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_222_REG_OFFSET 0xfbc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_222_STATUS_222_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_223_REG_OFFSET 0xfc0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_223_STATUS_223_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_224_REG_OFFSET 0xfc4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_224_STATUS_224_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_225_REG_OFFSET 0xfc8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_225_STATUS_225_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_226_REG_OFFSET 0xfcc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_226_STATUS_226_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_227_REG_OFFSET 0xfd0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_227_STATUS_227_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_228_REG_OFFSET 0xfd4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_228_STATUS_228_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_229_REG_OFFSET 0xfd8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_229_STATUS_229_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_230_REG_OFFSET 0xfdc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_230_STATUS_230_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_231_REG_OFFSET 0xfe0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_231_STATUS_231_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_232_REG_OFFSET 0xfe4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_232_STATUS_232_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_233_REG_OFFSET 0xfe8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_233_STATUS_233_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_234_REG_OFFSET 0xfec
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_234_STATUS_234_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_235_REG_OFFSET 0xff0
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_235_STATUS_235_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_236_REG_OFFSET 0xff4
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_236_STATUS_236_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_237_REG_OFFSET 0xff8
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_237_STATUS_237_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_238_REG_OFFSET 0xffc
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_238_STATUS_238_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_239_REG_OFFSET 0x1000
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_239_STATUS_239_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_240_REG_OFFSET 0x1004
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_240_STATUS_240_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_241_REG_OFFSET 0x1008
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_241_STATUS_241_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_242_REG_OFFSET 0x100c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_242_STATUS_242_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_243_REG_OFFSET 0x1010
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_243_STATUS_243_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_244_REG_OFFSET 0x1014
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_244_STATUS_244_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_245_REG_OFFSET 0x1018
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_245_STATUS_245_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_246_REG_OFFSET 0x101c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_246_STATUS_246_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_247_REG_OFFSET 0x1020
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_247_STATUS_247_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_248_REG_OFFSET 0x1024
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_248_STATUS_248_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_249_REG_OFFSET 0x1028
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_249_STATUS_249_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_250_REG_OFFSET 0x102c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_250_STATUS_250_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_251_REG_OFFSET 0x1030
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_251_STATUS_251_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_252_REG_OFFSET 0x1034
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_252_STATUS_252_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_253_REG_OFFSET 0x1038
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_253_STATUS_253_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_254_REG_OFFSET 0x103c
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_254_STATUS_254_BIT 0

// Per-core LP1 CMO status.  High while this core's CMO is in flight;
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_255_REG_OFFSET 0x1040
#define CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_255_STATUS_255_BIT 0

#ifdef __cplusplus
} // extern "C"
#endif
#endif // _CACHEPOOL_PERIPHERAL_REG_DEFS_
       // End generated register defines for cachepool_peripheral