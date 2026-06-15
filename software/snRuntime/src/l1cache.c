// Copyright 2020 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

// SPDX-License-Identifier: Apache-2.0

#include <l1cache.h>
#include <snrt.h>

void l1d_xbar_config(uint32_t offset) {
  // The input will give the starting bit to select the cache bank
  // e.g., offset = 5 with 4 cache bank will use bit [6:5] to
  // choose the cache bank
  // These selected bits will be removed from the address in
  // cache controller and added back when leaving the controller

  // 6 is the cacheline width (log2(512b/8))
  // granularity cannot be less than cacheline width
  offset = (offset > 6) ? offset : 6;

  // All cores fence and sync before reconfiguration
  asm volatile("fence" ::: "memory");
  snrt_cluster_hw_barrier();
  if (snrt_cluster_core_idx() == 0) {
    uint32_t *cfg =
        (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                     CACHEPOOL_PERIPHERAL_XBAR_OFFSET_REG_OFFSET);
    *cfg = offset;
    // Flush cache before committing xbar changes
    l1d_flush();
    l1d_wait();
    l1d_xbar_commit();
  }
  snrt_cluster_hw_barrier();
}


void l1d_xbar_commit() {
  uint32_t *commit =
      (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                   CACHEPOOL_PERIPHERAL_XBAR_OFFSET_COMMIT_REG_OFFSET);
  *commit = 1;
}

void l1d_commit() {
  uint32_t *commit =
      (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                   CACHEPOOL_PERIPHERAL_L1D_INSN_COMMIT_REG_OFFSET);
  *commit = 1;
}

void l1d_init(uint32_t size) {
  uint32_t *insn =
      (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                   CACHEPOOL_PERIPHERAL_CFG_L1D_INSN_REG_OFFSET);
  *insn = 3;
  l1d_commit();
  l1d_wait();
  // Write in the default config immediately after initialization
  // No need to call outside unless need a different config
  // l1d_spm_config(size);
}

// Flush all partition in all tiles
void l1d_flush() {
  uint32_t *insn =
      (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                   CACHEPOOL_PERIPHERAL_CFG_L1D_INSN_REG_OFFSET);
  // 2'b10 stands for flush all
  *insn = 2;
  l1d_commit();
}

// Flush private partitions in selected tiles.
// tile is a one-hot bitmask: bit i selects tile i.
// Bits 0-31 go to register 0, bits 32-63 to register 1.
void l1d_private_flush(uint64_t tile) {
  uint32_t *insn =
      (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                   CACHEPOOL_PERIPHERAL_CFG_L1D_INSN_REG_OFFSET);
  *insn = 0;

  uint32_t *tile_lo =
      (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                   CACHEPOOL_PERIPHERAL_CFG_L1D_TILE_SEL_0_REG_OFFSET);
  uint32_t *tile_hi =
      (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                   CACHEPOOL_PERIPHERAL_CFG_L1D_TILE_SEL_1_REG_OFFSET);
  *tile_lo = (uint32_t)(tile);
  *tile_hi = (uint32_t)(tile >> 32);
  l1d_commit();
}

// Flush shared partitions in all tiles
void l1d_shared_flush() {
  uint32_t *insn =
      (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                   CACHEPOOL_PERIPHERAL_CFG_L1D_INSN_REG_OFFSET);
  // 2'b01 stands for flush all
  *insn = 1;
  l1d_commit();
}

// Cluster-wide flush: all cores fence and sync, core 0 issues the flush instruction.
// Must be called by all cores in the cluster.
void l1d_cluster_flush() {
  asm volatile("fence" ::: "memory");
  snrt_cluster_hw_barrier();
  if (snrt_cluster_core_idx() == 0) {
    l1d_flush();
    l1d_wait();
  }
  snrt_cluster_hw_barrier();
}

// Cluster-wide private flush: all cores fence and sync, core 0 issues the flush instruction.
// Must be called by all cores in the cluster.
void l1d_cluster_private_flush(uint64_t tile) {
  asm volatile("fence" ::: "memory");
  snrt_cluster_hw_barrier();
  if (snrt_cluster_core_idx() == 0) {
    l1d_private_flush(tile);
    l1d_wait();
  }
  snrt_cluster_hw_barrier();
}

// Cluster-wide shared flush: all cores fence and sync, core 0 issues the flush instruction.
// Must be called by all cores in the cluster.
void l1d_cluster_shared_flush() {
  asm volatile("fence" ::: "memory");
  snrt_cluster_hw_barrier();
  if (snrt_cluster_core_idx() == 0) {
    l1d_shared_flush();
    l1d_wait();
  }
  snrt_cluster_hw_barrier();
}

void l1d_wait() {
  volatile uint32_t *busy =
      (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                   CACHEPOOL_PERIPHERAL_L1D_FLUSH_STATUS_REG_OFFSET);
  // wait until flush finished
  while (*busy) {

  }
}

// Used for hybrid SPM/cache, unused in CachePool now
// void l1d_spm_config (uint32_t size) {
//   // flush the cache before reconfiguration
//   l1d_flush();
//   l1d_wait();
//   // free all allocated region
//   snrt_l1alloc_reset();
//   // set the pointers
//   volatile uint32_t *cfg_size =
//       (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
//                    CACHEPOOL_PERIPHERAL_CFG_L1D_SPM_REG_OFFSET);
//   volatile uint32_t *commit =
//       (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
//                    CACHEPOOL_PERIPHERAL_L1D_SPM_COMMIT_REG_OFFSET);
//   // Make sure dummy region will not be optimized away
//   volatile double *dummy;
//   // Should be (L1_size - size) * 128
//   int cache_region = (128 - size) * 128;
//   dummy = (volatile double *)snrt_l1alloc(cache_region * sizeof(double));
//   // change size and commit the change
//   *cfg_size = size;
//   *commit   = 1;
// }

// Used to configure the number of private cache banks per tile
void l1d_part (uint32_t size) {
  // All cores fence and sync before reconfiguration
  asm volatile("fence" ::: "memory");
  snrt_cluster_hw_barrier();
  if (snrt_cluster_core_idx() == 0) {
    l1d_flush();
    l1d_wait();
    volatile uint32_t *cfg_private =
        (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                     CACHEPOOL_PERIPHERAL_L1D_PRIVATE_REG_OFFSET);
    *cfg_private = size;
    l1d_commit();
  }
  snrt_cluster_hw_barrier();
}

// Configure the starting address mapping to the private partition
void l1d_addr (uint32_t addr) {
  // set the pointers
  volatile uint32_t *cfg_private =
      (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                   CACHEPOOL_PERIPHERAL_L1D_ADDR_REG_OFFSET);
  *cfg_private = addr;
  l1d_commit();
}

void set_eoc (uint32_t eoc_value) {
    volatile uint32_t *eoc_reg =
        (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                    CACHEPOOL_PERIPHERAL_CLUSTER_EOC_EXIT_REG_OFFSET);
    // Value is already encoded by caller, write directly
    *eoc_reg = eoc_value;
}