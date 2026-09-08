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

/* RLC AM downlink execute stage. See rlc_am.h for the ownership model.
 
   Included from rlc.c after the core-role helpers, so rlc_ctx[], the per-user
   list locks and rlc_consumer_index() are all in scope. */

#ifndef RLC_AM_C
#define RLC_AM_C

#include "rlc_am.h"
#include "rlc_plan.c"

/* One plan buffer per consumer core rather than per entity: a core plans at
   most one grant at a time, and every entity has exactly one owner, so
   indexing by the owner's consumer index needs no allocator.
   (~5.6 KiB each at RLC_MAX_PDUS_PER_GRANT = 128.) */
#ifndef RLC_AM_MAX_CONSUMERS
#define RLC_AM_MAX_CONSUMERS RLC_ACTUAL_CONSUMERS
#endif

static rlc_plan_t rlc_am_plan_pool[RLC_AM_MAX_CONSUMERS]
    __attribute__((aligned(CACHE_LINE_SIZE))) __attribute__((section(".data")));

/* Written only by the owning consumer, read by the reporter after the barrier. */
/* The plan pool is indexed by consumer, not by entity, so a consumer that owns
   several entities shares ONE rlc_plan_t across all of them. Executors read
   e->plan for the whole life of a grant, so an owner that planned a second
   entity while the first grant was still open would overwrite a live plan
   underneath them. Rather than grow the pool to one buffer per entity (48 x
   ~7 KiB at TC2), an owner holds at most one open grant at a time and must
   commit it before planning another. Costs grant-level parallelism per owner;
   correctness is not negotiable and the buffer growth is.  */
#define RLC_AM_NO_ENTITY 0xFFFFFFFFu
static uint32_t rlc_am_open_entity[RLC_AM_MAX_TRACKED_CONSUMERS]
    __attribute__((section(".data")));

#if RLC_AM_TTI
/* Consensus state. Only consumer 0 writes rlc_am_stop; everyone reads it
   after a barrier, so all consumers leave the loop on the same TTI. A
   consumer that exited while others were still in a barrier would hang
   them, so the decision cannot be taken independently. */
static _Atomic uint32_t rlc_am_stop;
static uint32_t rlc_am_ttis;
/* Per-owner round-robin cursor over the entities it owns. */
static uint32_t rlc_am_rr[RLC_AM_MAX_TRACKED_CONSUMERS];

#endif

static uint32_t rlc_am_steps[RLC_AM_MAX_TRACKED_CONSUMERS]
    __attribute__((section(".data")));
static uint32_t rlc_am_last_u[RLC_AM_MAX_TRACKED_CONSUMERS]
    __attribute__((section(".data")));
static uint32_t rlc_am_sweeps[RLC_AM_MAX_TRACKED_CONSUMERS]
    __attribute__((section(".data")));

/* The pad lives INSIDE the same object as the entity array. A separate static
   does not work: the linker is free to place it after rlc_am_ent (it did), so
   the addresses would not move at all. Enclosing both in one struct makes the
   offset a language guarantee rather than a linker accident. */
#if RLC_LAYOUT_PAD
static struct {
  volatile char pad[RLC_LAYOUT_PAD];
  rlc_am_entity_t ent[NUM_USERS];
} rlc_am_blk __attribute__((aligned(CACHE_LINE_SIZE)))
    __attribute__((section(".data")));
#define rlc_am_ent (rlc_am_blk.ent)
#else
static rlc_am_entity_t rlc_am_ent[NUM_USERS]
    __attribute__((aligned(CACHE_LINE_SIZE))) __attribute__((section(".data")));
#endif

#if RLC_PLAN_VERIFY
static rlc_plan_t rlc_am_plan_ref[RLC_AM_MAX_CONSUMERS]
    __attribute__((aligned(CACHE_LINE_SIZE))) __attribute__((section(".data")));
static _Atomic uint32_t rlc_am_plan_bad;
#endif

#if RLC_AM_WORKQ
/* Two bitmaps, one bit per entity:
     ready  -- has queued data and no grant open (an owner should plan it)
     active -- a grant is open (any core can help execute it)
   A step walks set bits instead of all entities, so its cost tracks the work
   in flight rather than the entity count. Words that are zero are skipped
   whole, which is what makes 4800 mostly-idle entities affordable. */
#define RLC_AM_BM_WORDS (((NUM_USERS) + 31u) / 32u)
static _Atomic uint32_t rlc_am_bm_ready[RLC_AM_BM_WORDS];
static _Atomic uint32_t rlc_am_bm_active[RLC_AM_BM_WORDS];

static inline void rlc_am_bm_set(_Atomic uint32_t *bm, uint32_t u) {
  atomic_fetch_or_explicit(&bm[u >> 5], 1u << (u & 31u), memory_order_release);
}
static inline void rlc_am_bm_clr(_Atomic uint32_t *bm, uint32_t u) {
  atomic_fetch_and_explicit(&bm[u >> 5], ~(1u << (u & 31u)),
                            memory_order_release);
}
static inline int rlc_am_bm_empty(const _Atomic uint32_t *bm) {
  for (uint32_t w = 0u; w < RLC_AM_BM_WORDS; w++)
    if (atomic_load_explicit(&bm[w], memory_order_acquire)) return 0;
  return 1;
}

void rlc_am_mark_ready(uint32_t u) { rlc_am_bm_set(rlc_am_bm_ready, u); }
#endif /* RLC_AM_WORKQ */

/* Which consumer index owns entity u -- the same static partition the legacy
   consumer uses, so ownership and the existing round-robin agree. */
/* Every entity must map to a consumer that exists, so the partition is sized
   by RLC_ACTUAL_CONSUMERS rather than by the CONSUMER_CORE_NUM define. Using
   the define orphans every entity whose owner index exceeds the real consumer
   count -- those entities are never planned, never drain, and rlc_am_idle()
   never goes true, which hangs the run rather than corrupting it. */
static inline uint32_t rlc_am_owner_idx(uint32_t u) {
  const uint32_t ncons = RLC_ACTUAL_CONSUMERS;
  const uint32_t stride = (ncons < NUM_USERS) ? ncons : NUM_USERS;
  return u % stride;
}

#ifdef RLC_SELF_CHECK
/* Defined near the report at the end of this file; called from the plan and
   commit paths above it. */
static void rlc_am_poison(rlc_am_entity_t *e, uint32_t len);
static void rlc_am_verify_grant(uint32_t u);
#endif

/* ------------------------------------------------------------------------ */
/* Byte-granular payload copy                                               */
/* ------------------------------------------------------------------------ */

/* rlc_memcpy8() lives in rlc_copy.h: the uplink harness needs the same copy,
   and neither direction owns it. */
#include "rlc_copy.h"
#include "rlc_sync.h"

/* ------------------------------------------------------------------------ */

/* Set when the consumer set spans tiles while the transport-block arena is
   tile-private -- see the comment on RLC_AM_ALLOW_CROSS_TILE_TB. */
static uint32_t rlc_am_cross_tile_unsafe;

void rlc_am_init(uint32_t u) {
  if (u == 0u) {
    for (uint32_t k = 0u; k < RLC_AM_MAX_TRACKED_CONSUMERS; k++)
      rlc_am_open_entity[k] = RLC_AM_NO_ENTITY;

#if RLC_AM_TTI
    /* Programme which tiles take part in the consumer partial barrier. Must be
       done from exactly one core; main.c's startup snrt_cluster_hw_barrier()
       is the resync point the API requires before the mask is relied on. */
    {
      const uint32_t cpt0 = snrt_cluster_core_per_tile();
      uint32_t tm_lo = 0u, tm_hi = 0u;
      for (uint32_t i = 0u; i < RLC_ACTUAL_CONSUMERS; i++) {
        const uint32_t t = (uint32_t)consumer_core_ids[i] / cpt0;
        if (t < 32u) tm_lo |= 1u << t; else tm_hi |= 1u << (t - 32u);
      }
      snrt_barrier_set_tile_mask(tm_lo, tm_hi);
      for (uint32_t k = 0u; k < RLC_AM_MAX_TRACKED_CONSUMERS; k++) rlc_am_rr[k] = 0u;
      atomic_store_explicit(&rlc_am_stop, 0u, memory_order_relaxed);
      rlc_am_ttis = 0u;
    }
#endif

    /* Executors share one transport block, so they must share a tile while
       that arena is private. Checked once, loudly: getting this wrong loses
       payload writes with no other symptom. */
    rlc_am_cross_tile_unsafe = 0u;
#if !RLC_AM_ALLOW_CROSS_TILE_TB
    {
      const uint32_t cpt = snrt_cluster_core_per_tile();
      uint32_t tile0 = 0u, spans = 0u;
      for (uint32_t i = 0u; i < RLC_ACTUAL_CONSUMERS; i++) {
        const uint32_t t = (uint32_t)consumer_core_ids[i] / cpt;
        if (i == 0u) tile0 = t;
        else if (t != tile0) spans = 1u;
      }
      if (spans) {
        rlc_am_cross_tile_unsafe = 1u;
        printf_lock_acquire(&printf_lock);
        printf("[AM][FATAL] consumers span tiles but the transport-block arena "
               "at 0x%x is tile-private: executors on different tiles would "
               "write to different copies and payload writes would be lost. "
               "Move the arena below the l1d_addr boundary, or confine an "
               "entity's executors to the owner's tile.\n",
               (unsigned)RLC_TB_BASE);
        printf_lock_release(&printf_lock);
      }
    }
#endif
  }
  rlc_am_entity_t *e = &rlc_am_ent[u];
  e->so_next = 0u;
  e->plan = &rlc_am_plan_pool[rlc_am_owner_idx(u)];
  e->tb = (uint8_t *)(uintptr_t)(RLC_TB_BASE + u * RLC_TB_STRIDE);
  e->n = 0u;
  e->tb_used = 0u;
  atomic_store_explicit(&e->gen, 0u, memory_order_relaxed);
  atomic_store_explicit(&e->claim, 0u, memory_order_relaxed);
  atomic_store_explicit(&e->done, 0u, memory_order_relaxed);
  e->partial = 0u;
  e->plan_calls = 0u;
  e->peek_empty = 0u;
  e->plan_zero = 0u;
  e->plan_ok = 0u;
  e->peek_done = 0u;
  e->poison_done = 0u;
  e->published = 0u;
  e->peek_max = 0u;
  e->verify_sn = 0u;
  e->verify_so = 0u;
  e->verify_mask = 0u;
  e->verify_bad_idx = 0u;
  e->verify_have_bad = 0u;
  e->verify_align_bad = 0u;
  e->verify_align_ok = 0u;
  e->verify_pay_bad = 0u;
  e->verify_pay_checked = 0u;
  e->verify_first_byte = 0xFFFFFFFFu;
  e->grants = 0u;
  e->pdus = 0u;
  e->segments = 0u;
  e->polls = 0u;
}

/* --- owner: gather + plan + publish -------------------------------------- */

/* Returns 1 if a grant was opened. */
static int rlc_am_try_plan(uint32_t u) {
  rlc_am_entity_t *e = &rlc_am_ent[u];
  rlc_context_t *ctx = &rlc_ctx[u];
  rlc_plan_t *plan = e->plan;

  /* Look ahead over the queue without detaching anything: a partially sent
     SDU must stay at the head until its final segment goes out. */
  e->plan_calls++;
  /* Peek straight into the plan's own node array. A local Node*[128] would put
     512 B on the stack, and Snitch stacks are small -- this keeps the frame
     flat and saves a copy. */
  Node **peek = (Node **)plan->sdu_node;
  /* Walk only as far as the grant can reach. The queue walk is a dependent
     pointer chase and dominates the planning attempt, so gathering the full
     RLC_MAX_PDUS_PER_GRANT when the grant holds a handful of SDUs multiplies
     that cost for nothing. Charging the minimum header per SDU keeps the
     bound conservative -- a segmented lead SDU carries a larger header, so
     the walk can only ever stop later than strictly necessary, never early. */
  const uint32_t avail = list_peek_budget(
      (spinlock_t *)&tosend_llist_lock_2[u], &ctx->list, peek,
      RLC_MAX_PDUS_PER_GRANT, RLC_GRANT_BYTES + e->so_next, RLC_AMD_HDR_MIN);
  e->peek_done++; /* distinguishes "blocked in the peek" from "peek was empty" */
  if (avail > e->peek_max) e->peek_max = avail;
  if (avail == 0u) { e->peek_empty++; return 0; }

  for (uint32_t i = 0u; i < avail; i++) {
    plan->sdu_data[i] = peek[i]->data;
    plan->sdu_len[i] = (uint32_t)peek[i]->data_size;
  }
  plan->n_avail = avail;

  const rlc_plan_in_t in = {
      .grant_bytes = RLC_GRANT_BYTES,
      .sn_base = atomic_load_explicit(&ctx->vtNext, memory_order_relaxed),
      .so_first = e->so_next,
      .poll_pdu = atomic_load_explicit(&ctx->pollPdu, memory_order_relaxed),
      .poll_byte = atomic_load_explicit(&ctx->pollByte, memory_order_relaxed),
      .pdu_without_poll =
          atomic_load_explicit(&ctx->pduWithoutPoll, memory_order_relaxed),
      .byte_without_poll =
          atomic_load_explicit(&ctx->byteWithoutPoll, memory_order_relaxed),
      /* the peek saw the whole queue only if it did not hit the cap */
      .queue_drained = (avail < RLC_MAX_PDUS_PER_GRANT),
  };
  rlc_plan_out_t out;
#if RLC_PLAN_VERIFY
  uint32_t bad = 0u;
  const uint32_t n = rlc_plan_compute_checked(
      plan, &rlc_am_plan_ref[rlc_am_owner_idx(u)], &in, &out, &bad);
  if (bad) atomic_fetch_add_explicit(&rlc_am_plan_bad, bad, memory_order_relaxed);
#else
  const uint32_t n = rlc_plan_compute(plan, &in, &out);
#endif
  if (n == 0u) { e->plan_zero++; return 0; }
  e->plan_ok++;

  /* Stash what commit needs; it must not re-run the planner. */
  e->n = n;
  e->tb_used = plan->tb_used;
  e->partial = out.partial;
  e->so_next = out.so_next;
  atomic_store_explicit(&ctx->vtNext, out.sn_next, memory_order_relaxed);
  atomic_store_explicit(&ctx->pduWithoutPoll, out.pdu_without_poll,
                        memory_order_relaxed);
  atomic_store_explicit(&ctx->byteWithoutPoll, out.byte_without_poll,
                        memory_order_relaxed);

#ifdef RLC_SELF_CHECK
  rlc_am_poison(e, plan->tb_used);
#endif
  e->poison_done++;

  /* Publish: counters reset first, generation last (release). */
  atomic_store_explicit(&e->claim, 0u, memory_order_relaxed);
  atomic_store_explicit(&e->done, 0u, memory_order_relaxed);
  atomic_store_explicit(&e->gen,
                        atomic_load_explicit(&e->gen, memory_order_relaxed) + 1u,
                        memory_order_release);
  e->published++;
#if RLC_AM_WORKQ
  rlc_am_bm_set(rlc_am_bm_active, u);
#endif
  e->grants++;
  return 1;
}

/* --- any core: claim and execute ----------------------------------------- */

static void rlc_am_execute_range(rlc_am_entity_t *e, uint32_t lo, uint32_t hi) {
  const rlc_plan_t *p = e->plan;
  for (uint32_t i = lo; i < hi; i++) {
    uint8_t *dst = e->tb + p->tb_off[i];
    rlc_amd_hdr_write(dst, p->sn[i], p->si[i], p->poll[i], p->so[i]);
    const uint8_t *src = (const uint8_t *)p->sdu_data[i] + p->so[i];
#if RLC_DL_EXEC == RLC_DL_EXEC_COPY
    rlc_memcpy8(dst + p->hdr_len[i], src, p->seg_len[i]);
#else
    /* No payload movement: hand a descriptor to whatever drains the TB. */
    rlc_sgl_t *g = &e->sgl[i];
    g->hdr = dst;
    g->hdr_len = p->hdr_len[i];
    g->src = (void *)src;
    g->len = p->seg_len[i];
#endif
  }
}

/* Claim and run one chunk of entity u's open grant. Returns PDUs executed. */
static uint32_t rlc_am_help(uint32_t u) {
  rlc_am_entity_t *e = &rlc_am_ent[u];
  if ((atomic_load_explicit(&e->gen, memory_order_acquire) & 1u) == 0u) return 0;

  const uint32_t lo = atomic_fetch_add_explicit(&e->claim, RLC_AM_CLAIM_CHUNK,
                                                memory_order_relaxed);
  /* Read n *after* claiming: if the owner closed this grant and opened the
     next one in between, the claim landed on the new counter and n must be
     the new one too. plan/tb are written before the generation is bumped, so
     they are consistent with whichever grant the claim belongs to. */
  const uint32_t n = e->n;
  if (lo >= n) return 0;

  uint32_t hi = lo + RLC_AM_CLAIM_CHUNK;
  if (hi > n) hi = n;
  rlc_am_execute_range(e, lo, hi);
  atomic_fetch_add_explicit(&e->done, hi - lo, memory_order_release);
  return hi - lo;
}

/* --- owner: commit -------------------------------------------------------- */

/* Retire a finished grant: move fully-transmitted SDUs to the sent list and
   fold the grant into the entity counters. Only the owner runs this. */
static void rlc_am_commit(uint32_t u) {
  rlc_am_entity_t *e = &rlc_am_ent[u];
  rlc_context_t *ctx = &rlc_ctx[u];
  const rlc_plan_t *p = e->plan;
  const uint32_t n = e->n;
  const uint32_t partial = e->partial;

  /* Every SDU finished by this grant leaves the queue, in order, stamped with
     the SN of its final segment -- the STATUS path needs that to know when the
     SDU is fully acknowledged. The trailing segment's SDU stays at the head
     with e->so_next recording how much of it has gone out. */
  uint32_t retire = 0u;
  for (uint32_t i = 0u; i < n; i++) {
    if (!p->last_seg[i]) continue;
    Node *node = list_pop_front((spinlock_t *)&tosend_llist_lock_2[u],
                                &ctx->list);
    if (node == NULL) {
      DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
      DEBUG_PRINTF("[AM][u %u] commit: queue shorter than plan at %u\n", u, i);
      DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
      break;
    }
    node->last_sn = p->sn[i];
    list_push_back((spinlock_t *)&sent_llist_lock_2[u], &ctx->sent_list, node);
    retire++;
  }

  uint32_t bytes = 0u, polls = 0u, segs = 0u;
  for (uint32_t i = 0u; i < n; i++) {
    bytes += p->seg_len[i];
    polls += p->poll[i];
    segs += (p->si[i] != RLC_SI_FULL);
  }
  atomic_fetch_add_explicit(&ctx->dlPduNum, n, memory_order_relaxed);
  atomic_fetch_add_explicit(&ctx->rlcthrp, bytes, memory_order_relaxed);
  atomic_fetch_add_explicit(&ctx->tbsize, e->tb_used, memory_order_relaxed);
  atomic_fetch_add_explicit(&ctx->sduNum, -(int32_t)retire, memory_order_relaxed);
  atomic_fetch_add_explicit(&ctx->sduBytes, (uint32_t)(0u - bytes),
                            memory_order_relaxed);
  ctx->sendPduNum += n;
  ctx->sendPduBytes += bytes;
  e->pdus += n;
  e->polls += polls;
  e->segments += segs;

#ifdef RLC_SELF_CHECK
  rlc_am_verify_grant(u);
#endif

  e->n = 0u;
  /* Close the grant (generation back to even). */
  atomic_store_explicit(&e->gen,
                        atomic_load_explicit(&e->gen, memory_order_relaxed) + 1u,
                        memory_order_release);
#if RLC_AM_WORKQ
  rlc_am_bm_clr(rlc_am_bm_active, u);
  /* Anything left -- queued SDUs, or a segment mid-flight -- re-arms the
     entity so it is picked up again without a scan. */
  if (ctx->list.sduNum != 0 || e->so_next != 0u) {
    rlc_am_bm_set(rlc_am_bm_ready, u);
  }
#endif
}


/* ------------------------------------------------------------------------ */
/* TTI-structured consumer loop                                             */
/* ------------------------------------------------------------------------ */
#if RLC_AM_TTI

/* Entities owned by consumer index `me`, in order: me, me+stride, me+2*stride...
   (owner_idx(u) == u % stride, so the owned set is an arithmetic progression). */
static inline uint32_t rlc_am_owned_count(uint32_t me) {
  const uint32_t ncons = RLC_ACTUAL_CONSUMERS;
  const uint32_t stride = (ncons < NUM_USERS) ? ncons : NUM_USERS;
  if (me >= stride) return 0u; /* more consumers than entities: pure helper */
  return (NUM_USERS - me + stride - 1u) / stride;
}
static inline uint32_t rlc_am_owned_at(uint32_t me, uint32_t k) {
  const uint32_t ncons = RLC_ACTUAL_CONSUMERS;
  const uint32_t stride = (ncons < NUM_USERS) ? ncons : NUM_USERS;
  return me + k * stride;
}

/* Phase 1: each owner opens at most ONE grant.

   The plan pool is indexed by consumer, so an owner holds one plan buffer and
   therefore one open grant at a time. A TTI is consequently "one grant
   opportunity per OWNER", not per entity -- entities are served round-robin,
   so each gets a turn every ceil(owned/1) TTIs. The agreed cross-engine metric
   is bytes/cycle and does not depend on how a TTI is defined, so this changes
   the reporting granularity only. */
static void rlc_am_plan_phase(uint32_t me) {
  const uint32_t trk = (me < RLC_AM_MAX_TRACKED_CONSUMERS) ? me : 0u;
  const uint32_t n = rlc_am_owned_count(me);
  if (n == 0u) return;
  if (rlc_am_open_entity[trk] != RLC_AM_NO_ENTITY) return;

  for (uint32_t k = 0u; k < n; k++) {
    const uint32_t idx = (rlc_am_rr[trk] + k) % n;
    const uint32_t u = rlc_am_owned_at(me, idx);
    if (atomic_load_explicit(&rlc_am_ent[u].gen, memory_order_acquire) & 1u) continue;
    if (rlc_am_try_plan(u)) {
      rlc_am_open_entity[trk] = u;
      rlc_am_rr[trk] = (idx + 1u) % n; /* next TTI starts at the following one */
      return;
    }
  }
  rlc_am_rr[trk] = (rlc_am_rr[trk] + 1u) % n; /* nothing to plan; still advance */
}

/* Phase 2: everyone drains every open grant. Terminates when no chunk is left
   to claim -- a core may still be finishing a claimed chunk, which the barrier
   after this phase covers. */
static uint32_t rlc_am_execute_phase(void) {
  uint32_t total = 0u, worked;
  do {
    worked = 0u;
    for (uint32_t u = 0u; u < NUM_USERS; u++) worked += rlc_am_help(u);
    total += worked;
  } while (worked != 0u);
  return total;
}

/* Phase 3: owners retire. Safe without checking `done` because the barrier
   between execute and commit already guarantees every chunk has completed --
   the counter is kept as a cross-check rather than as the synchronisation. */
static void rlc_am_commit_phase(uint32_t me) {
  const uint32_t trk = (me < RLC_AM_MAX_TRACKED_CONSUMERS) ? me : 0u;
  const uint32_t u = rlc_am_open_entity[trk];
  if (u == RLC_AM_NO_ENTITY) return;
  if ((atomic_load_explicit(&rlc_am_ent[u].gen, memory_order_acquire) & 1u) == 0u) return;
  rlc_am_commit(u);
  rlc_am_open_entity[trk] = RLC_AM_NO_ENTITY;
}

void rlc_am_consumer_tti(uint32_t core_id) {
  const uint32_t me = rlc_consumer_index(core_id);
  /* Tile-local participant mask. O(n), computed once on entry, never in the
     loop. Every consumer in a tile derives the same value independently. */
  const uint32_t mask =
      snrt_cluster_partial_barrier_mask(consumer_core_ids, RLC_ACTUAL_CONSUMERS);

  while (1) {
#if RLC_TTI_CYCLES
    const uint32_t tti_start = benchmark_get_cycle();
#endif
    rlc_am_plan_phase(me);
    rlc_phase_barrier(mask);  /* helpers BLOCK here; fenced -- see rlc_sync.h */

    rlc_am_execute_phase();
    rlc_phase_barrier(mask);

    rlc_am_commit_phase(me);
    rlc_phase_barrier(mask);

    if (me == 0u) {
      rlc_am_ttis++;
      atomic_store_explicit(&rlc_am_stop,
          (atomic_load_explicit(&producer_done, memory_order_relaxed) >=
               PRODUCER_CORE_NUM && rlc_am_idle()) ? 1u : 0u,
          memory_order_release);
    }
    rlc_phase_barrier(mask);
    if (atomic_load_explicit(&rlc_am_stop, memory_order_acquire)) break;

#if RLC_TTI_CYCLES
    { /* pad to the scaled TTI so the run has a wallclock-flavoured cadence */
      const uint32_t used = benchmark_get_cycle() - tti_start;
      if (used < (uint32_t)RLC_TTI_CYCLES) delay((uint32_t)RLC_TTI_CYCLES - used);
    }
#endif
  }
}
#endif /* RLC_AM_TTI */

/* ------------------------------------------------------------------------ */
/* Transport-block self-check                                               */
/* ------------------------------------------------------------------------ */

#ifdef RLC_SELF_CHECK
static _Atomic uint32_t rlc_am_verify_errors;
static _Atomic uint32_t rlc_am_verify_grants;

/* Mark each planned PDU's header bytes before publishing, so a chunk that no
   core ever executed decodes as the fill pattern rather than as whatever the
   previous grant left behind.

   Only the header bytes, not the whole grant: filling all of tb_used meant
   8192 single-byte stores to DRAM per grant, which was slow enough to stall
   the owner for the rest of the run (observed on GVSoC as a second grant that
   planned but never published). The payload has its own byte-exact comparison
   in the verifier, so poisoning it added cost without adding coverage. */
#define RLC_TB_POISON 0xA5u
static void rlc_am_poison(rlc_am_entity_t *e, uint32_t len) {
  const rlc_plan_t *p = e->plan;
  (void)len;
  for (uint32_t i = 0u; i < e->n; i++) {
    uint8_t *h = e->tb + p->tb_off[i];
    for (uint32_t b = 0u; b < p->hdr_len[i]; b++) h[b] = RLC_TB_POISON;
  }
  asm volatile("fence" ::: "memory");
}

/* Decode the assembled block and check it against the plan that produced it.
   This validates the *execute* stage -- that every chunk actually ran, wrote
   its header at the offset the planner assigned, and copied the right payload
   bytes. The host test cannot see any of that: it never runs concurrently and
   never touches memory. */
/* Bit positions in rlc_am_entity_t::verify_mask. */
#define RLC_VB_TB_OFF     (1u << 0)
#define RLC_VB_SN         (1u << 1)
#define RLC_VB_SI         (1u << 2)
#define RLC_VB_POLL       (1u << 3)
#define RLC_VB_SO         (1u << 4)
#define RLC_VB_HDRLEN     (1u << 5)
#define RLC_VB_SN_SEQ     (1u << 6)
#define RLC_VB_PAYLOAD    (1u << 7)
#define RLC_VB_TB_USED    (1u << 8)
#define RLC_VB_SN_CONT    (1u << 9)
#define RLC_VB_SO_CONT    (1u << 10)
#define RLC_VB_POISON     (1u << 11) /* header still reads as the fill pattern */

static void rlc_am_verify_grant(uint32_t u) {
  rlc_am_entity_t *e = &rlc_am_ent[u];
  const rlc_plan_t *p = e->plan;
  uint32_t off = 0u, bad = 0u, mask = 0u;

#define RLC_VB(cond, bit)                                                     \
  do {                                                                        \
    if (cond) {                                                               \
      bad++;                                                                  \
      mask |= (bit);                                                          \
      if (!e->verify_have_bad) { e->verify_have_bad = 1u; e->verify_bad_idx = i; } \
    }                                                                         \
  } while (0)

  for (uint32_t i = 0u; i < e->n; i++) {
    rlc_amd_hdr_t hd;
    rlc_amd_hdr_read(e->tb + off, &hd);

    /* An untouched header still carries the pre-publish fill, which says the
       chunk was never executed rather than executed wrongly. */
    RLC_VB(e->tb[off] == RLC_TB_POISON && e->tb[off + 1u] == RLC_TB_POISON,
           RLC_VB_POISON);
    RLC_VB(off != p->tb_off[i], RLC_VB_TB_OFF);
    RLC_VB(hd.sn != p->sn[i], RLC_VB_SN);
    RLC_VB(hd.si != p->si[i], RLC_VB_SI);
    RLC_VB(hd.poll != p->poll[i], RLC_VB_POLL);
    RLC_VB(hd.so != p->so[i], RLC_VB_SO);
    RLC_VB(hd.hdr_len != p->hdr_len[i], RLC_VB_HDRLEN);
    /* Sequence numbers must be consecutive across the whole block. */
    RLC_VB(i > 0u && hd.sn != ((p->sn[i - 1u] + 1u) & RLC_SN_MASK),
           RLC_VB_SN_SEQ);

#if RLC_DL_EXEC == RLC_DL_EXEC_COPY
    {
      const uint8_t *src = (const uint8_t *)p->sdu_data[i] + p->so[i];
      const uint8_t *dst = e->tb + off + hd.hdr_len;
      const uint32_t algn = (uint32_t)((uintptr_t)dst & 3u);
      uint32_t mism = 0u, firstb = 0u;
      for (uint32_t b = 0u; b < p->seg_len[i]; b++) {
        if (dst[b] != src[b]) { mism = 1u; firstb = b; break; }
      }
      e->verify_pay_checked++;
      if (mism) {
        e->verify_pay_bad++;
        e->verify_align_bad |= (1u << algn);
        if (firstb < e->verify_first_byte) e->verify_first_byte = firstb;
      } else {
        e->verify_align_ok |= (1u << algn);
      }
      RLC_VB(mism != 0u, RLC_VB_PAYLOAD);
    }
#endif
    off += p->hdr_len[i] + p->seg_len[i];
  }
  {
    const uint32_t i = e->n;
    RLC_VB(off != e->tb_used, RLC_VB_TB_USED);
  }

  /* Continuity with the previous grant: the block must resume exactly where
     the last one stopped, both in SN and in segment offset. */
  if (e->n) {
    const uint32_t i = 0u;
    RLC_VB(p->sn[0] != e->verify_sn, RLC_VB_SN_CONT);
    RLC_VB(p->so[0] != e->verify_so, RLC_VB_SO_CONT);
    e->verify_sn = (p->sn[0] + e->n) & RLC_SN_MASK;
    e->verify_so = e->so_next;
  }
#undef RLC_VB
  e->verify_mask |= mask;

  atomic_fetch_add_explicit(&rlc_am_verify_grants, 1u, memory_order_relaxed);
  if (bad) {
    atomic_fetch_add_explicit(&rlc_am_verify_errors, bad, memory_order_relaxed);
    printf_lock_acquire(&printf_lock);
    printf("[AM-SB][u %u] grant %u: %u mismatches (n=%u tb_used=%u)\n", u,
           e->grants, bad, e->n, e->tb_used);
    printf_lock_release(&printf_lock);
  }
}
#endif /* RLC_SELF_CHECK */

/* ------------------------------------------------------------------------ */
/* STATUS PDU (TS 38.322 §6.2.2.5)                                          */
/* ------------------------------------------------------------------------ */

/* One STATUS PDU buffer per entity. Built and then parsed back on every
   status pass so the encode/decode cost is part of the measurement. */
static uint8_t rlc_am_status_buf[NUM_USERS][RLC_STATUS_HDR_LEN + 4u]
    __attribute__((aligned(4))) __attribute__((section(".data")));

void rlc_am_status(void) {
  for (uint32_t u = 0u; u < NUM_USERS; u++) {
    rlc_context_t *ctx = &rlc_ctx[u];

    /* The modelled UE acknowledges everything up to RLC_AM_ACK_LAG PDUs
       behind the transmitter. ACK_SN is the first *not* acknowledged SN. */
    const uint32_t vt_next =
        atomic_load_explicit(&ctx->vtNext, memory_order_relaxed);
    const uint32_t vt_ack =
        atomic_load_explicit(&ctx->vtNextAck, memory_order_relaxed);
    if (!rlc_sn_lt(vt_ack, vt_next)) continue;

    uint32_t ack_sn = (vt_next - RLC_AM_ACK_LAG) & RLC_SN_MASK;
    if (rlc_sn_lt(ack_sn, vt_ack)) continue; /* nothing new to acknowledge */

    /* Build it, then decode it -- the parse is the part a receiver pays for,
       and it is what the legacy model skipped entirely. */
    uint8_t *buf = rlc_am_status_buf[u];
    rlc_status_hdr_write(buf, ack_sn, /*e1=*/0u);
    uint32_t got_ack_sn, got_e1;
    rlc_status_hdr_read(buf, &got_ack_sn, &got_e1);
    if (got_ack_sn != ack_sn) {
      printf_lock_acquire(&printf_lock);
      printf("[AM-SB][u %u] STATUS round-trip: wrote %u read %u\n", u, ack_sn,
             got_ack_sn);
      printf_lock_release(&printf_lock);
#ifdef RLC_SELF_CHECK
      atomic_fetch_add_explicit(&rlc_am_verify_errors, 1u, memory_order_relaxed);
#endif
    }

    /* Release every SDU whose final segment is below ACK_SN. Because SDUs are
       retired in order, their last_sn values are monotonic, so the first node
       that is not acknowledged ends the scan. */
    uint32_t freed = 0u;
    while (1) {
      Node *head = NULL;
      if (list_peek_n((spinlock_t *)&sent_llist_lock_2[u], &ctx->sent_list,
                      &head, 1u) == 0u) {
        break;
      }
      if (!rlc_sn_lt(head->last_sn, got_ack_sn)) break;
      Node *node = list_pop_front((spinlock_t *)&sent_llist_lock_2[u],
                                  &ctx->sent_list);
      if (node == NULL) break;
      mm_free(node);
      freed++;
    }

    atomic_store_explicit(&ctx->vtNextAck, got_ack_sn, memory_order_relaxed);
    ctx->acksn = got_ack_sn;
    ctx->nackcount = 0u;
    if (freed) ctx->parseindex++;
  }
}

void rlc_am_report(void) {
  uint32_t grants = 0u, pdus = 0u, segs = 0u, polls = 0u;
  for (uint32_t u = 0u; u < NUM_USERS; u++) {
    grants += rlc_am_ent[u].grants;
    pdus += rlc_am_ent[u].pdus;
    segs += rlc_am_ent[u].segments;
    polls += rlc_am_ent[u].polls;
  }
  printf_lock_acquire(&printf_lock);
  printf("[AM] entities=%u grants=%u pdus=%u segments=%u polls=%u grant_bytes=%u\n",
         (unsigned)NUM_USERS, grants, pdus, segs, polls,
         (unsigned)RLC_GRANT_BYTES);
  /* Dispatch shape: the *_CORE_NUM macros come from the build, the NUM_*_CORES
     from the generated data header. They are allowed to disagree, but the
     lists are what actually decide who produces and who consumes. */
  for (uint32_t k = 0u; k < RLC_AM_MAX_TRACKED_CONSUMERS; k++) {
    if (!rlc_am_steps[k] && !rlc_am_last_u[k]) continue;
    printf("[AM] consumer %u: steps=%u completed_sweeps=%u last_entity=%u/%u\n",
           k, rlc_am_steps[k], rlc_am_sweeps[k], rlc_am_last_u[k],
           (unsigned)NUM_USERS);
  }
  if (rlc_am_cross_tile_unsafe) {
    printf("[AM] cross-tile transport block: UNSAFE -> results are not "
           "trustworthy\n");
  }
  printf("[AM] layout: sizeof(entity)=%u pad=%u ent@%p ctx@%p\n",
         (unsigned)sizeof(rlc_am_entity_t), (unsigned)RLC_LAYOUT_PAD,
         (void *)&rlc_am_ent[0], (void *)&rlc_ctx[0]);
  printf("[AM] zero-vl vsetvli events: %u\n",
         (unsigned)atomic_load_explicit(&rlc_vec_zero_vl, memory_order_relaxed));
#if RLC_AM_TTI
  {
    uint32_t bytes = 0u;
    for (uint32_t u = 0u; u < NUM_USERS; u++)
      bytes += atomic_load_explicit(&rlc_ctx[u].rlcthrp, memory_order_relaxed);
    printf("[AM] ttis=%u payload_bytes=%u tti_cycles=%u (one TTI = one grant "
           "opportunity per OWNER; bytes/cycle = payload_bytes / kernel_cycles)\n",
           rlc_am_ttis, bytes, (unsigned)RLC_TTI_CYCLES);
  }
#endif
  printf("[AM] dispatch: producers=%u(list %u) consumers=%u(list %u) workq=%u\n",
         (unsigned)PRODUCER_CORE_NUM, (unsigned)NUM_PRODUCER_CORES,
         (unsigned)CONSUMER_CORE_NUM, (unsigned)NUM_CONSUMER_CORES,
         (unsigned)RLC_AM_WORKQ);
  for (uint32_t u = 0u; u < NUM_USERS; u++) {
    const rlc_am_entity_t *e = &rlc_am_ent[u];
    printf("[AM] u%u: plan_calls=%u peek_empty=%u peek_max=%u plan_zero=%u "
           "peek_done=%u plan_ok=%u poison=%u published=%u grants=%u | tosend=%d sent=%d "
           "so_next=%u gen=%u\n",
           u, e->plan_calls, e->peek_empty, e->peek_max, e->plan_zero,
           e->peek_done, e->plan_ok, e->poison_done, e->published, e->grants,
           rlc_ctx[u].list.sduNum, rlc_ctx[u].sent_list.sduNum, e->so_next,
           (unsigned)atomic_load_explicit(&rlc_am_ent[u].gen,
                                          memory_order_relaxed));
    /* If rlc_am_init never ran, plan is NULL -- and sdu_node is the first
       member of rlc_plan_t, so the queue look-ahead would write to address 0
       and still return a plausible count. Print the pointers so that is
       visible rather than inferred. */
    printf("[AM] u%u: plan=%p tb=%p pool0=%p ent=%p n=%u tb_used=%u\n", u,
           (void *)e->plan, (void *)e->tb, (void *)&rlc_am_plan_pool[0],
           (void *)e, e->n, e->tb_used);
  }
#if RLC_PLAN_VERIFY
  {
    const uint32_t pb =
        atomic_load_explicit(&rlc_am_plan_bad, memory_order_relaxed);
    printf("[AM] plan vector-vs-reference mismatches: %u -> %s\n", pb,
           pb ? "FAIL" : "PASS");
  }
#endif
#ifdef RLC_SELF_CHECK
  {
    const uint32_t ve =
        atomic_load_explicit(&rlc_am_verify_errors, memory_order_relaxed);
    const uint32_t vg =
        atomic_load_explicit(&rlc_am_verify_grants, memory_order_relaxed);
    printf("[AM] transport-block check: %u grants, %u mismatches -> %s\n", vg,
           ve, ve ? "FAIL" : "PASS");
    for (uint32_t u = 0u; u < NUM_USERS; u++) {
      const rlc_am_entity_t *e = &rlc_am_ent[u];
      if (!e->verify_mask) continue;
      printf("[AM] u%u: payload %u/%u PDUs bad | align_bad=0x%x align_ok=0x%x "
             "first_diff_byte=%d | copy=%s\n",
             u, e->verify_pay_bad, e->verify_pay_checked, e->verify_align_bad,
             e->verify_align_ok,
             (e->verify_first_byte == 0xFFFFFFFFu) ? -1
                                                   : (int)e->verify_first_byte,
             RLC_DL_COPY_SCALAR ? "scalar" : "e8/m8-vector");
      printf("[AM] u%u: verify_mask=0x%x first_bad_pdu=%u  "
             "[bit0 tb_off,1 sn,2 si,3 poll,4 so,5 hdr_len,6 sn_seq,"
             "7 payload,8 tb_used,9 sn_cont,10 so_cont,11 poison]\n",
             u, e->verify_mask, e->verify_bad_idx);
    }
  }
#endif
  printf_lock_release(&printf_lock);
}

/* ------------------------------------------------------------------------ */

uint32_t rlc_am_step(uint32_t core_id) {
  const uint32_t me = rlc_consumer_index(core_id);
  uint32_t worked = 0u;
  const uint32_t trk = (me < RLC_AM_MAX_TRACKED_CONSUMERS) ? me : 0u;
  rlc_am_steps[trk]++;

#if RLC_AM_WORKQ
  /* Owner pass: plan the entities this core owns that have announced work. */
  for (uint32_t w = 0u; w < RLC_AM_BM_WORDS; w++) {
    uint32_t bits = atomic_load_explicit(&rlc_am_bm_ready[w],
                                         memory_order_acquire);
    while (bits) {
      const uint32_t b = (uint32_t)__builtin_ctz(bits);
      bits &= bits - 1u;
      const uint32_t u = (w << 5) + b;
      if (u >= NUM_USERS || rlc_am_owner_idx(u) != me) continue;
      rlc_am_last_u[trk] = u;
      if (rlc_am_open_entity[trk] != RLC_AM_NO_ENTITY) continue;
      if (atomic_load_explicit(&rlc_am_ent[u].gen, memory_order_acquire) & 1u)
        continue;
      /* Clear before looking: a producer that enqueues in between sets the bit
         again, so the notification cannot be lost -- only repeated. */
      rlc_am_bm_clr(rlc_am_bm_ready, u);
      if (rlc_am_try_plan(u)) {
        rlc_am_open_entity[trk] = u;
      } else {
        /* Nothing planned but work remains (e.g. the grant cannot hold even a
           header): re-arm, or the entity would stall unnoticed. */
        if (rlc_ctx[u].list.sduNum != 0 || rlc_am_ent[u].so_next != 0u) {
          rlc_am_bm_set(rlc_am_bm_ready, u);
        }
      }
    }
  }

  /* Helper pass: any core executes any open grant. */
  for (uint32_t w = 0u; w < RLC_AM_BM_WORDS; w++) {
    uint32_t bits = atomic_load_explicit(&rlc_am_bm_active[w],
                                         memory_order_acquire);
    while (bits) {
      const uint32_t b = (uint32_t)__builtin_ctz(bits);
      bits &= bits - 1u;
      const uint32_t u = (w << 5) + b;
      if (u >= NUM_USERS) continue;
      worked += rlc_am_help(u);
      rlc_am_entity_t *e = &rlc_am_ent[u];
      if (rlc_am_owner_idx(u) == me &&
          (atomic_load_explicit(&e->gen, memory_order_acquire) & 1u) &&
          atomic_load_explicit(&e->done, memory_order_acquire) >= e->n) {
        rlc_am_commit(u);
        if (rlc_am_open_entity[trk] == u) rlc_am_open_entity[trk] = RLC_AM_NO_ENTITY;
        worked++;
      }
    }
  }
  rlc_am_sweeps[trk]++;
  return worked;
#else
  for (uint32_t u = 0u; u < NUM_USERS; u++) {
    rlc_am_last_u[trk] = u;
    rlc_am_entity_t *e = &rlc_am_ent[u];
    /* Exactly one consumer index owns each entity. At NUM_USERS == 1 that is
       consumer 0; every other consumer is a helper, which is precisely what
       makes single-entity peak rate reachable. */
    const int owner = (rlc_am_owner_idx(u) == me);

    if (owner && rlc_am_open_entity[trk] == RLC_AM_NO_ENTITY &&
        (atomic_load_explicit(&e->gen, memory_order_acquire) & 1u) == 0u) {
      if (rlc_am_try_plan(u)) rlc_am_open_entity[trk] = u;
    }

    /* Any core helps any open grant, owned or not. */
    worked += rlc_am_help(u);

    if (owner && (atomic_load_explicit(&e->gen, memory_order_acquire) & 1u) &&
        atomic_load_explicit(&e->done, memory_order_acquire) >= e->n) {
      rlc_am_commit(u);
      if (rlc_am_open_entity[trk] == u) rlc_am_open_entity[trk] = RLC_AM_NO_ENTITY;
      worked++;
    }
  }
  rlc_am_sweeps[trk]++; /* only reached if the whole sweep completed */
  return worked;
#endif /* RLC_AM_WORKQ */
}

int rlc_am_idle(void) {
#if RLC_AM_WORKQ
  /* Both bitmaps clear means nothing is queued and nothing is in flight: a
     producer enqueueing would have set ready, a grant would have set active. */
  return rlc_am_bm_empty(rlc_am_bm_ready) && rlc_am_bm_empty(rlc_am_bm_active);
#else
  for (uint32_t u = 0u; u < NUM_USERS; u++) {
    if (atomic_load_explicit(&rlc_am_ent[u].gen, memory_order_acquire) & 1u)
      return 0;
    if (rlc_ctx[u].list.sduNum != 0) return 0;
    if (rlc_am_ent[u].so_next != 0u) return 0;
  }
  return 1;
#endif
}

#endif /* RLC_AM_C */
