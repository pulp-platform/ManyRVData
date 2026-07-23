// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

// SPDX-License-Identifier: Apache-2.0

// Author: Ho Tin Hung, ETH Zurich <hohung@ethz.ch>

#include <lp1cache.h>

// Software critical-section support for the per-core private L1 (HPDcache).
// A CMO is issued directly from the core by writing the custom CSR CSR_LP1CMO;
// the write stalls the core until the CMO has completed at the HPDcache, so no
// commit/status handshake is needed (contrast the earlier peripheral path).
//
// CSR map (must match snitch_pkg.sv / cachepool_l1_ctrl.sv):
//   CSR_LP1CMOADDR (0xBC1) : cacheline address for INVAL_NLINE.
//   CSR_LP1CMO     (0xBC2) : write value = op; the write blocks until done.
//     op encoding: 0 = FENCE       (write-through WBUF drain -- "flush" under WT)
//                  1 = INVAL_ALL   (invalidate the whole private L1)
//                  2 = INVAL_NLINE (invalidate the cacheline covering addr)
#define LP1_CMO_OP_FENCE      0u
#define LP1_CMO_OP_INVAL_ALL  1u
#define LP1_CMO_OP_INVAL_LINE 2u

// Issue one CMO on this core's private L1 and block until it completes.  The
// "memory" clobber also keeps the compiler from reordering loads/stores across
// the CMO, preserving the acquire/release ordering the caller relies on.
static inline void lp1_cmo(uint32_t op) {
  asm volatile("csrw 0xBC2, %0" ::"r"(op) : "memory");
}

// Release side of a critical section: make all prior private-L1 writes visible
// downstream (drain the write-through write buffer) before the L2 release AMO.
void lp1_wt_flush() {
  lp1_cmo(LP1_CMO_OP_FENCE);
}

// Acquire side of a critical section: drop any stale lines so the first reads
// inside the section miss and refetch fresh data from L2.
void lp1_inval() {
  lp1_cmo(LP1_CMO_OP_INVAL_ALL);
}

// Invalidate a single cacheline covering addr (finer-grained than lp1_inval).
void lp1_inval_line(uint32_t addr) {
  asm volatile("csrw 0xBC1, %0" ::"r"(addr) : "memory");
  lp1_cmo(LP1_CMO_OP_INVAL_LINE);
}
