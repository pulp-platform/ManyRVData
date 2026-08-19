// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

// SPDX-License-Identifier: Apache-2.0

#include "cachepool_peripheral.h"
#include "team.h"

extern __thread struct snrt_team *_snrt_team_current;

// Acquire/release Spatz ownership on a dual-Snitch Core Complex. Each store
// blocks in hardware until granted, so no software polling is needed. Only
// call release after a successful acquire on the same hart, and only from
// harts sharing a Spatz (cachepool_cc_dual) -- on a single-scalar-per-CC
// build these write a harmless, unused peripheral register.
void spatz_lock_acquire(void);
void spatz_lock_release(void);
