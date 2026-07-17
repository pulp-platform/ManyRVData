// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

// SPDX-License-Identifier: Apache-2.0

// Author: Ho Tin Hung, ETH Zurich <hohung@ethz.ch>

// Private-L1 (LP1) cache control.
//
// LP1 is the per-core private HPDcache (write-through, no coherence), distinct
// from the shared distributed L1D controlled in l1cache.h.  These primitives
// drive the per-core CMO (Cache Management Operation) injector so software can
// bracket a critical section:
//
//   amoswap acquire (L2) -> lp1_inval() -> CS -> lp1_wt_flush() -> release (L2)
//
// Each core acts on its own private L1; call from the core that owns the
// critical section (no barrier -- the register slot is per-core).

#include "encoding.h"
#include "cachepool_peripheral.h"
#include "team.h"

extern __thread struct snrt_team *_snrt_team_current;

void lp1_wt_flush();                 // release: drain write-through write buffer
void lp1_inval();                    // acquire: invalidate the whole private L1
void lp1_inval_line(uint32_t addr);  // invalidate one cacheline covering addr
