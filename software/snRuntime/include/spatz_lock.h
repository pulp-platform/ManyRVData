// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

// SPDX-License-Identifier: Apache-2.0

#include <stdint.h>

#include "cachepool_peripheral.h"
#include "team.h"

extern __thread struct snrt_team *_snrt_team_current;

// Outcome of a single spatz_lock_try_acquire()/try_release() attempt --
// bits [1:0] of the raw register value, see cachepool_spatz_lock.sv.
typedef enum {
  SPATZ_LOCK_FAIL = 0,         // denied; hardware made no reservation
  SPATZ_LOCK_SUCCESS = 1,      // granted now
  SPATZ_LOCK_SUCCESS_WAIT = 2, // accepted, completes on its own once drained
} spatz_lock_outcome_t;

// Single, always-immediate attempt (never blocks in hardware). Decode with
// spatz_lock_outcome().
uint32_t spatz_lock_try_acquire(void);
uint32_t spatz_lock_try_release(void);

static inline spatz_lock_outcome_t spatz_lock_outcome(uint32_t raw) {
  return (spatz_lock_outcome_t)(raw & 0x3);
}

// Acquire/release Spatz ownership on a dual-Snitch Core Complex. Retries
// spatz_lock_try_acquire()/try_release() until it stops failing: FAIL means
// genuine contention (nothing reserved, must retry); SUCCESS/SUCCESS_WAIT
// both return right away -- on SUCCESS_WAIT, the switch is still draining,
// but acc_mux already refuses any new Spatz issue until it's done, so the
// next real vector/FP instruction naturally blocks in hardware until the
// switch completes, same as before. Only call release after a successful
// acquire on the same hart, and only from harts sharing a Spatz
// (cachepool_cc_dual) -- on a single-scalar-per-CC build these access a
// harmless, unused peripheral register (every attempt returns SUCCESS).
void spatz_lock_acquire(void);
void spatz_lock_release(void);
