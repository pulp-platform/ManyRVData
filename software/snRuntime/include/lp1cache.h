// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

// SPDX-License-Identifier: Apache-2.0

// Author: Ho Tin Hung, ETH Zurich <hohung@ethz.ch>

// Private-L1 (LP1) cache control.
//
// LP1 is the per-core private HPDcache (write-through, no coherence), distinct
// from the shared distributed L1D controlled in l1cache.h.  These primitives
// issue a per-core CMO (Cache Management Operation) directly from the core via a
// custom CSR (CSR_LP1CMO); the write blocks in hardware until the CMO completes,
// so no status polling is needed.  Use them to bracket a critical section:
//
//   amoswap acquire (L2) -> lp1_inval() -> CS -> lp1_wt_flush() -> release (L2)
//
// Each core acts on its own private L1; call from the core that owns the
// critical section (the CSR is core-local, so no barrier is needed).

#include <stdint.h>

void lp1_wt_flush();                 // release: drain write-through write buffer
void lp1_inval();                    // acquire: invalidate the whole private L1
void lp1_inval_line(uint32_t addr);  // invalidate one cacheline covering addr
