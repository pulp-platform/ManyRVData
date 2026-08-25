// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

// SPDX-License-Identifier: Apache-2.0

#include <spatz_lock.h>
#include <snrt.h>

uint32_t spatz_lock_try_acquire(void) {
#if SNRT_NUM_SCALAR_PER_CORE == 2
  volatile uint32_t *lock =
      (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                   CACHEPOOL_PERIPHERAL_SPATZ_LOCK_ACQUIRE_REG_OFFSET);
  return *lock;
#else
  // No lock module exists to intercept this on a single-scalar-per-CC
  // build; report an unconditional grant rather than reading back the
  // register's uninitialized reset value (which would decode as FAIL).
  return SPATZ_LOCK_SUCCESS;
#endif
}

uint32_t spatz_lock_try_release(void) {
#if SNRT_NUM_SCALAR_PER_CORE == 2
  volatile uint32_t *lock =
      (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                   CACHEPOOL_PERIPHERAL_SPATZ_LOCK_RELEASE_REG_OFFSET);
  return *lock;
#else
  return SPATZ_LOCK_SUCCESS;
#endif
}

void spatz_lock_acquire(void) {
  spatz_lock_outcome_t outcome;
  do {
    outcome = spatz_lock_outcome(spatz_lock_try_acquire());
  } while (outcome == SPATZ_LOCK_FAIL);
}

void spatz_lock_release(void) {
  spatz_lock_outcome_t outcome;
  do {
    outcome = spatz_lock_outcome(spatz_lock_try_release());
  } while (outcome == SPATZ_LOCK_FAIL);
}
