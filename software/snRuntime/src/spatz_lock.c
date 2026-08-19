// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

// SPDX-License-Identifier: Apache-2.0

#include <spatz_lock.h>
#include <snrt.h>

void spatz_lock_acquire(void) {
  volatile uint32_t *lock =
      (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                   CACHEPOOL_PERIPHERAL_SPATZ_LOCK_REG_OFFSET);
  *lock = 1;
}

void spatz_lock_release(void) {
  volatile uint32_t *lock =
      (uint32_t *)(_snrt_team_current->root->cluster_mem.end +
                   CACHEPOOL_PERIPHERAL_SPATZ_LOCK_REG_OFFSET);
  *lock = 0;
}
