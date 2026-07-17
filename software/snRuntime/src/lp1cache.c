// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

// SPDX-License-Identifier: Apache-2.0

// Author: Ho Tin Hung, ETH Zurich <hohung@ethz.ch>

#include <lp1cache.h>
#include <snrt.h>

// Software critical-section support for the per-core private L1 (HPDcache).
// Each core owns one register slot [cid] (multireg, stride 4 bytes) so that
// independent cores running unrelated critical sections never contend on a
// shared trigger.  A CMO is issued by writing op+addr, pulsing commit, then
// polling status (busy while the injector has a request in flight).
//
// op encoding (must match cmo_decode() in cachepool_l1_ctrl.sv):
//   0 = FENCE       (write-through WBUF drain -- "flush" under WT policy)
//   1 = INVAL_ALL   (invalidate the whole private L1)
//   2 = INVAL_NLINE (invalidate the cacheline covering addr)
#define LP1_CMO_OP_FENCE      0u
#define LP1_CMO_OP_INVAL_ALL  1u
#define LP1_CMO_OP_INVAL_LINE 2u

// Issue one CMO on this core's slot and block until the injector completes.
static inline void lp1_cmo(uint32_t op, uint32_t addr) {
  uint32_t cid = snrt_cluster_core_idx();
  uint64_t base = _snrt_team_current->root->cluster_mem.end;

  volatile uint32_t *op_reg =
      (uint32_t *)(base + CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_0_REG_OFFSET +
                   cid * 4);
  volatile uint32_t *addr_reg =
      (uint32_t *)(base + CACHEPOOL_PERIPHERAL_CFG_LP1_CMO_ADDR_0_REG_OFFSET +
                   cid * 4);
  volatile uint32_t *commit_reg =
      (uint32_t *)(base + CACHEPOOL_PERIPHERAL_LP1_CMO_COMMIT_0_REG_OFFSET +
                   cid * 4);
  volatile uint32_t *status_reg =
      (uint32_t *)(base + CACHEPOOL_PERIPHERAL_LP1_CMO_STATUS_0_REG_OFFSET +
                   cid * 4);

  *op_reg   = op;
  *addr_reg = addr;
  // Trigger the injector.  The peripheral self-clears commit and raises status.
  *commit_reg = 1;
  // Wait until the CMO has been accepted and completed by the HPDcache.
  while (*status_reg) {
  }
}

// Release side of a critical section: make all prior private-L1 writes visible
// downstream (drain the write-through write buffer) before the L2 release AMO.
void lp1_wt_flush() {
  lp1_cmo(LP1_CMO_OP_FENCE, 0);
}

// Acquire side of a critical section: drop any stale lines so the first reads
// inside the section miss and refetch fresh data from L2.
void lp1_inval() {
  lp1_cmo(LP1_CMO_OP_INVAL_ALL, 0);
}

// Invalidate a single cacheline covering addr (finer-grained than lp1_inval).
void lp1_inval_line(uint32_t addr) {
  lp1_cmo(LP1_CMO_OP_INVAL_LINE, addr);
}
