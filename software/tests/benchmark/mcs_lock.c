// Copyright 2025 ETH Zurich and University of Bologna.
//
// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Author: Zexin Fu     <zexifu@iis.ee.ethz.ch>

// mcs_lock.c — RISC-V bare-metal MCS spinlock (hart-local nodes)
#include <snrt.h>
#include "mcs_lock.h"
#include <stdio.h>
#include "printf.h"
#include "benchmark.h"
// #include "printf_lock.h"

// Each waiter spins on its own node (aligned to keep it on a single line)
struct __attribute__((aligned(MCS_CACHELINE))) mcs_node {
  _Atomic(struct mcs_node*) next __attribute__((aligned(MCS_CACHELINE)));
  _Atomic(uint32_t)         locked __attribute__((aligned(MCS_CACHELINE)));
};


// Hart-local binding table: [hart][slot] -> (lock,node)
typedef struct {
  mcs_lock_t*         lock __attribute__((aligned(MCS_CACHELINE)));
  struct mcs_node     node __attribute__((aligned(MCS_CACHELINE)));
  uint32_t            in_use __attribute__((aligned(MCS_CACHELINE)));
} mcs_binding_core_t;

// Force starting alignment to a cache line, and size to *exactly* one line.
// If core > 64B in the future, the static assert will catch it.
typedef union __attribute__((aligned(MCS_CACHELINE))) {
  mcs_binding_core_t core;
  uint8_t            pad[(sizeof(mcs_binding_core_t)/MCS_CACHELINE + 1) * MCS_CACHELINE - sizeof(mcs_binding_core_t)];
} mcs_binding_t;

static mcs_binding_t mcs_bindings[MCS_MAX_HARTS][MCS_TLS_SLOTS] __attribute__((aligned(MCS_CACHELINE))) __attribute__((section(".data")));

// Acquire a free slot for this hart and lock
static inline mcs_binding_core_t* mcs_bind_acquire_slot(mcs_lock_t* L) {
  uint32_t h = snrt_cluster_core_idx();
  mcs_binding_t* row = mcs_bindings[h];
  for (int i = h; i < MCS_TLS_SLOTS; ++i) {
    if (!row[i].core.in_use) {
      row[i].core.in_use = true;
      row[i].core.lock   = L;
      atomic_store_explicit(&row[i].core.node.next, NULL, memory_order_relaxed);
      atomic_store_explicit(&row[i].core.node.locked, false, memory_order_relaxed);
      return &row[i].core;
    }
  }
  // If all slots busy, spin until one frees (or raise MCS_TLS_SLOTS)
  for (;;) {
    for (int i = h; i < MCS_TLS_SLOTS; ++i) {
      if (!row[i].core.in_use) {
        row[i].core.in_use = true;
        row[i].core.lock   = L;
        atomic_store_explicit(&row[i].core.node.next, NULL, memory_order_relaxed);
        atomic_store_explicit(&row[i].core.node.locked, false, memory_order_relaxed);
        return &row[i].core;
      }
    }
    MCS_CPU_PARK();
  }
}

static inline mcs_binding_core_t* mcs_bind_find(mcs_lock_t* L) {
  uint32_t h = snrt_cluster_core_idx();
  mcs_binding_t* row = mcs_bindings[h];
  for (int i = h; i < MCS_TLS_SLOTS; ++i) {
    if (row[i].core.in_use && row[i].core.lock == L) return &row[i].core;
  }
  return NULL; // unlocking a lock not held on this hart → no-op (or assert in debug)
}

static inline void mcs_bind_release_slot(mcs_binding_core_t* b) {
  b->lock   = NULL;
  b->in_use = false;
}

void mcs_lock_init(mcs_lock_t* L) {
  atomic_store_explicit(&L->tail, NULL, memory_order_relaxed);
}

uint32_t mcs_lock_try_acquire(mcs_lock_t* L) {
  mcs_binding_core_t* b = mcs_bind_acquire_slot(L);
  struct mcs_node* me = &b->node;

  atomic_store_explicit(&me->next, NULL, memory_order_relaxed);
  atomic_store_explicit(&me->locked, false, memory_order_relaxed);

  struct mcs_node* expected = NULL;
  uint32_t ok = atomic_compare_exchange_strong_explicit(
      &L->tail, &expected, me, memory_order_acq_rel, memory_order_acquire);

  if (!ok) mcs_bind_release_slot(b);

  // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
  // DEBUG_PRINTF("[core %u][mcs_lock_try_acquire] try result = %d, try add me = 0x%x to the tail if the list is empty.\n",
  //     snrt_cluster_core_idx(),
  //     ok,
  //     me
  // );
  // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

  return ok;
}

void __attribute__((noinline)) mcs_lock_acquire(mcs_lock_t* L, int delay) {
  mcs_binding_core_t* b = mcs_bind_acquire_slot(L);
  struct mcs_node* me = &b->node;

  atomic_store_explicit(&me->next, NULL, memory_order_relaxed);
  struct mcs_node* pred =
      atomic_exchange_explicit(&L->tail, me, memory_order_acq_rel);

  if (pred) {
    atomic_store_explicit(&me->locked, true, memory_order_relaxed);
    atomic_store_explicit(&pred->next, me, memory_order_relaxed);
    while (atomic_load_explicit(&me->locked, memory_order_relaxed)) {
      // cachepool_wait(delay); // prevent busy spinning
    }
  }

  // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
  // DEBUG_PRINTF("[core %u][mcs_lock_acquire] pred = 0x%x, added me = 0x%x to the pred->next.\n",
  //     snrt_cluster_core_idx(),
  //     pred,
  //     me
  // );
  // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
}

void __attribute__((noinline)) mcs_lock_release(mcs_lock_t* L, int delay) {
  mcs_binding_core_t* b = mcs_bind_find(L);
  if (!b) return; // or assert in debug

  struct mcs_node* me = &b->node;
  struct mcs_node* succ =
      // atomic_load_explicit(&me->next, memory_order_acquire);
      atomic_load_explicit(&me->next, memory_order_relaxed);

  if (!succ) {
    // No visible successor: try to swing tail back to NULL.
    struct mcs_node* expected = me;
    if (atomic_compare_exchange_strong_explicit(
            &L->tail, &expected, NULL, memory_order_acq_rel, memory_order_acquire)) {
      mcs_bind_release_slot(b);
      return;
    }
    // A successor is enqueuing; wait for linkage.
    do {
      // cachepool_wait(delay); // prevent busy spinning
      // succ = atomic_load_explicit(&me->next, memory_order_acquire);
      succ = atomic_load_explicit(&me->next, memory_order_relaxed);
    } while (!succ);
  }

  // Handoff: clear the successor's locked flag.
  atomic_store_explicit(&succ->locked, false, memory_order_release);
  mcs_bind_release_slot(b);

  // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
  // DEBUG_PRINTF("[core %u][mcs_lock_release] removed me = 0x%x from the list, next node is 0x%x.\n",
  //     snrt_cluster_core_idx(),
  //     me,
  //     succ
  // );
  // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
}
