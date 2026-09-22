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

#ifndef LLIST_H
#define LLIST_H

#include <stddef.h>
#include <stdint.h>
#include "printf_lock.h"
#include "mcs_lock.h"
// #include "spin_lock.h"

/* --- Simple spinlock implementation --- */
/* We use a volatile int as a spinlock. Zero means unlocked. */
typedef volatile int spinlock_t __attribute__((aligned(4)));

/* RLC_PAD_SYNC=1 gives every lock and every cross-core flag a cache line of its own, and lets an
   idle consumer look at a queue before locking it. Default 0 keeps the historical layout.

   Why it matters: in the default layout one 64 B line holds the descriptor lock every producer
   takes per packet, `producer_done` which every core polls every iteration, and the per-user list
   locks, all 48 of TC2's in about three lines. At 256 cores every lock operation and every poll
   hits the same few lines; measured on GVSoC 4x4, TC1 ran 9x slower on 256 cores than on 4. */
#ifndef RLC_PAD_SYNC
#define RLC_PAD_SYNC 0
#endif
#define RLC_SYNC_LINE_BYTES 64

/* RLC_GROUP_STREAMS=1: per-group packet streams and node pools instead of one descriptor lock and
   one pool lock for the whole cluster (see rlc.h). Default 0. */
#ifndef RLC_GROUP_STREAMS
#define RLC_GROUP_STREAMS 0
#endif
#define RLC_MAX_STREAMS 64

/* RLC_TILE_AFFINITY=1: every UE is owned by one tile and handled entirely inside it, with its
   state in that tile's PRIVATE L1 partition (see rlc.h). RLC_PRIVATE_BANKS: L1 banks per tile
   given to the private partition (0 / 1 / N/2 / N-1 / N of N; the RTL's tcdm_cache_interco).
   Default 0 / the historical all-private setting. */
#ifndef RLC_TILE_AFFINITY
#define RLC_TILE_AFFINITY 0
#endif
/* Declares `name` in .data; with RLC_PAD_SYNC it is the only thing on its cache line (the name
   then refers to `name##_line.v` through a #define placed next to the declaration). */
#if RLC_PAD_SYNC
#define RLC_LINE_VAR(type, name) \
    struct { type v; char pad[RLC_SYNC_LINE_BYTES - sizeof(type)]; } name##_line \
        __attribute__((aligned(RLC_SYNC_LINE_BYTES))) __attribute__((section(".data")))
#else
#define RLC_LINE_VAR(type, name) type name __attribute__((section(".data")))
#endif

spinlock_t tosend_llist_lock __attribute__((section(".data")));
spinlock_t sent_llist_lock __attribute__((section(".data")));
/* Per-user mcs locks (tosend_llist_lock_2[NUM_USERS] / sent_llist_lock_2[NUM_USERS])
   are declared in rlc.h, where NUM_USERS is visible. */

static inline void spin_lock(spinlock_t *lock, int cycle) {
    while (__sync_lock_test_and_set(lock, 1)) { delay(cycle);}
}

static inline void spin_unlock(volatile int *lock, int cycle) {
   // Release fence: with commit-accurate write responses (cache Option A),
   // `fence` drains all prior stores to COMMIT (lsu_empty) before the unlock
   // store becomes visible, so a later core that acquires the lock sees the
   // critical-section data. (Snitch ignores the .rl AMO bit, hence an explicit
   // fence rather than amoswap.w.rl.)
   asm volatile ("fence rw, rw" ::: "memory");
   asm volatile (
       "amoswap.w zero, zero, %0"
       : "+A" (*lock)
   );
   delay(cycle);
}


/* Node structure representing a packet or data element.
   The node structure is stored at the beginning of a fixed‐size page;
   the remainder of the page may be used as payload.
*/
typedef struct Node {
    struct Node *prev;
    struct Node *next;
    void *data;         /* Pointer to the payload data */
    void *tgt;          /* Pointer to the address to move the payload data to */
    size_t data_size;   /* Size of the payload in bytes */
    spinlock_t lock;    /* Per‑node lock (0: unlocked, 1: locked) */
    uint32_t user_id;   /* Owning RLC entity / UE (instrumentation + multi-user routing) */
#if defined(RLC_TB_MODE) && (RLC_TB_MODE == 1)
    /* AM only: SN of this SDU's final segment, stamped when the SDU is fully
       transmitted. A STATUS PDU may only release the SDU once every segment
       it was split into has been acknowledged, and with segmentation the SDU
       count and the SN count diverge -- so the SN has to travel with the node.
       Guarded so the legacy build keeps its exact Node layout, which sets
       PAGE_SIZE and hence the whole memory-pool geometry. */
    uint32_t last_sn;
#endif
} Node;

/* Doubly‑linked list structure for storing Node pointers.
   All operations require a pointer to an instance of LinkedList.
*/
typedef struct {
    Node *head __attribute__((aligned(4)));
    Node *tail __attribute__((aligned(4)));
    int sduNum __attribute__((aligned(4)));   /* Number of SDUs to be sent */
    int sduBytes __attribute__((aligned(4)));/* Number of SUDs bytes to be sent */
    spinlock_t lock __attribute__((aligned(4)));  /* Global lock protecting the list structure */
} LinkedList;

/*
   list_init() initializes the given LinkedList instance.
   It sets the head and tail pointers to NULL and the lock to 0.
*/
void list_init(LinkedList *list);

/*
   list_push_back() appends a given Node to the end of the list.
   It is safe for concurrent use by multiple producers.
*/
void list_push_back(spinlock_t *llist_lock, LinkedList *list, volatile Node *node);

/*
   list_pop_front() removes and returns the node from the front of the list.
   This function should be used by a single consumer.
   If the list is empty, it returns NULL.
*/
Node *list_pop_front(spinlock_t *llist_lock, LinkedList *list);

/*
   list_peek_n() walks up to `max` nodes from the head without removing any,
   writing them into `out`. Returns how many were written.

   The AM grant planner needs to look ahead over several queued SDUs to decide
   where the grant boundary and the segment split fall, but it must not detach
   them: a partially transmitted SDU has to stay at the head of the list until
   its last segment is sent. Popping and re-inserting would need a push_front
   and would reorder against concurrent producers.
*/
/* `1` is RLC_TB_MODE_AM (rlc_am.h). Spelled numerically because llist.h is
   pulled in via mm.h before that header is seen, so the symbolic name is not
   yet defined here; RLC_TB_MODE itself always comes from the build (-D), so
   every translation unit agrees regardless of include order. */
#if defined(RLC_TB_MODE) && (RLC_TB_MODE == 1)
unsigned int list_peek_n(spinlock_t *llist_lock, LinkedList *list, Node **out,
                         unsigned int max);

/*
   list_peek_budget() is list_peek_n() that stops once the walked SDUs can no
   longer fit in `budget` bytes, counting `overhead` bytes of header per SDU.
   It includes the first node that overflows -- that one is the segmentation
   candidate -- and then stops.

   Walking the queue is a dependent pointer chase, one cache miss per node, and
   it is the dominant serial cost of a planning attempt (measured: it is where
   RTL spends essentially all of its time in rlc_am_try_plan). Gathering
   `max` nodes when the grant can only hold a handful wastes that cost
   proportionally -- at an 8 KiB grant and 1360-byte SDUs it is 128 nodes
   walked to plan 6.
*/
unsigned int list_peek_budget(spinlock_t *llist_lock, LinkedList *list,
                              Node **out, unsigned int max, unsigned int budget,
                              unsigned int overhead, unsigned int *reached_end);

#ifndef RLC_AM_BATCH
#define RLC_AM_BATCH 0
#endif
#if RLC_AM_BATCH
/* Batched queue operations for an AM owner (RLC_AM_BATCH=1). Only the owner removes nodes from
   its to-send queue; producers only append at the tail. That makes two things safe:

   list_peek_budget_nolock(): read head and length under the lock, then walk the nodes WITHOUT it.
     Every node in front of the snapshot length is fixed (nobody but the caller removes), and the
     walk never reads past that count, so it never races the producer writing tail->next. The
     locked walk held the lock for the whole pointer chase and stalled every producer behind it.

   list_detach_front_upto(): detach the chain head..last (the caller knows `last` and the chain's
     length and bytes, from its plan) in one O(1) locked step, instead of one lock per node.
   list_append_chain(): append a detached chain in one O(1) locked step. */
unsigned int list_peek_budget_nolock(spinlock_t *llist_lock, LinkedList *list, Node **out,
                                     unsigned int max, unsigned int budget, unsigned int overhead,
                                     unsigned int *reached_end);
void list_detach_front_upto(spinlock_t *llist_lock, LinkedList *list, Node *last,
                            unsigned int n, unsigned int bytes);
void list_append_chain(spinlock_t *llist_lock, LinkedList *list, Node *first, Node *last,
                       unsigned int n, unsigned int bytes);
#endif
#endif

/*
   list_remove() removes a specific Node from anywhere in the list.
   This function adjusts the pointers of neighboring nodes appropriately.
*/
void list_remove(spinlock_t *llist_lock, LinkedList *list, Node *node);

#endif /* LLIST_H */
