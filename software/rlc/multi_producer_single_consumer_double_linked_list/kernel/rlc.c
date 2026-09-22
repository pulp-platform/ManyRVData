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

#ifndef RLC_C
#define RLC_C

#undef  USE_MCS_LOCK
// #define USE_MCS_LOCK

#undef  USE_MCS_LOCK_2
// #define USE_MCS_LOCK_2

#include "rlc.h"
#include "rlc_am.h"   /* RLC_TB_MODE and the AM entity API (impl included below) */
#include "rlc_ul.h"   /* RLC_UL_MODE and the uplink API (impl included below)  */
#if RLC_UL_MODE
#include "rlc_ul_drv.h" /* rlc_ul_init() must be reachable from rlc_init() below  */
#endif

/* Set when this build narrows the cluster barrier mask for a consumer-only
   partial-barrier region, which requires non-participants to stay out of any
   barrier for the duration. */
#if (RLC_UL_MODE) || ((RLC_TB_MODE == RLC_TB_MODE_AM) && RLC_AM_TTI)
#define RLC_NARROWED_BARRIER 1
#else
#define RLC_NARROWED_BARRIER 0
#endif
#include "mm.h"
#include "llist.c"
#include "data_move_vec.c"
#include <snrt.h>
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <l1cache.h>
#include "printf.h"
#include "printf_lock.h"
/* Data header comes from the build (-DDATAHEADER, see CMakeLists). main.c
   includes it before this file; the guard below is a self-sufficiency
   fallback for standalone compilation of rlc.c. Never hard-code a specific
   header here: it would shadow DATAHEADER for every variant (include guard
   PDCP_PKG_H is shared by all generated headers). */
#ifndef PDCP_PKG_H
#include DATAHEADER
#endif

#include <stdatomic.h>
#include "benchmark.h"
/* Software performance probes (gvsoc prompt/perf_probe_design.md). Every call below compiles to
   nothing unless the build defines RLC_PROBE=1, so default ELFs are unchanged. */
#include "perf_probe.h"
#if RLC_PROBE
/* PHASE is a state: store only on transitions, never once per loop iteration. */
static inline void rlc_probe_phase_to(uint32_t *cur, uint32_t ph) {
    if (*cur != ph) { *cur = ph; perf_probe_phase(ph); }
}
#define RLC_PROBE_PHASE_TO(cur, ph) rlc_probe_phase_to(&(cur), (ph))
#else
#define RLC_PROBE_PHASE_TO(cur, ph) ((void)0)
#endif

// volatile: these structs model memory traffic (status indications/reports);
// their loaded values are intentionally unused, so without volatile the
// compiler would optimize the loads away (PR #12 review).
volatile DlschInd dlsch_ind __attribute__((section(".data")));
volatile UeStateRpt ue_status_rpt_content __attribute__((section(".data")));

static inline size_t memdiff32(const void *a, const void *b, size_t len_bytes) {
    const uint8_t *p = (const uint8_t *)a;
    const uint8_t *q = (const uint8_t *)b;
    const uint32_t *p_32 = (const uint8_t *)a;
    const uint32_t *q_32 = (const uint8_t *)b;

    size_t i = 0;

    // 1) Bytewise until both pointers are 4B-aligned or we run out
    while (i < len_bytes && (((uintptr_t)(p + i) | (uintptr_t)(q + i)) & 3)) {
        if (p[i] != q[i]) return i;
        i++;
    }

    // 2) 32-bit chunks
    size_t n_words = (len_bytes - i) / 4;
    const uint32_t *wp = (const uint32_t *)(p + i);
    const uint32_t *wq = (const uint32_t *)(q + i);
    for (size_t k = 0; k < n_words; ++k) {
        uint32_t x = wp[k] ^ wq[k];
        if (x) {
            // Find the first differing byte within this 32-bit word
            size_t base = i + (k * 4);
            // if ((x & 0x000000FFu) && p[base + 0] != q[base + 0]) return base + 0;
            // if ((x & 0x0000FF00u) && p[base + 1] != q[base + 1]) return base + 1;
            // if ((x & 0x00FF0000u) && p[base + 2] != q[base + 2]) return base + 2;
            // if ((x & 0xFF000000u) && p[base + 3] != q[base + 3]) return base + 3;
            if(p_32[base] != q_32[base]) return base;
        }
    }
    i += n_words * 4;

    // 3) Trailing bytes
    while (i < len_bytes) {
        if (p[i] != q[i]) return i;
        i++;
    }

    return len_bytes; // equal
}

static inline void memprint32(const void *a, const void *b, size_t len_bytes) {
    const uint8_t *p = (const uint8_t *)a;
    const uint8_t *q = (const uint8_t *)b;
    DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    DEBUG_PRINTF("a: ");
    for (int i = 0; i < len_bytes; i++) {
        DEBUG_PRINTF("%02X ", (uint8_t)(p[i]));
    }
    DEBUG_PRINTF("\n");
    DEBUG_PRINTF("b: ");
    for (int i = 0; i < len_bytes; i++) {
        DEBUG_PRINTF("%02X ", (uint8_t)(q[i]));
    }
    DEBUG_PRINTF("\n");
    DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
}


/* self_check compares src vs tgt payloads after the run. Two byte ranges are
   excluded: [0,4) holds the RLC SN written over the tgt header word, and
   [64,128) is rewritten on the SRC side by rlc_send_pkt AFTER the payload copy
   (traffic modeling), so tgt legitimately has the pre-rewrite content there. */
#ifdef RLC_SELF_CHECK
void self_check(const pdcp_pkg_t *meta, int size) {
    uint32_t core_id = snrt_cluster_core_idx();
    int npass = 0, nfail = 0;
    for (int i = 0; i < size; i++) {
        const uint8_t *src = (const uint8_t *)(uintptr_t)meta[i].src_addr;
        const uint8_t *tgt = (const uint8_t *)(uintptr_t)meta[i].tgt_addr;
        size_t len = meta[i].pkg_length;
        size_t first_bad = len; /* len == match */
        for (size_t off = 4; off < len && first_bad == len; off++) {
            if (off >= 64 && off < 128) continue; /* post-copy src rewrite, see above */
            if (src[off] != tgt[off]) first_bad = off;
        }
        if (first_bad == len) {
            npass++;
        } else {
            nfail++;
            DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
            DEBUG_PRINTF("[core %u][self test] FAIL pkg_num = %d user = %d, first mismatch @%d\n",
                core_id, i, meta[i].user_id, (int)first_bad);
            DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
        }
    }
    DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    DEBUG_PRINTF("[core %u][self test] SUMMARY: %d/%d pass, %d fail\n", core_id, npass, size, nfail);
    DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
}
#endif

/* Initialize RLC entity `rlcId` (one entity per UE). Global/shared resources
   (pdcp_pkd_ptr, its lock, producer_done, rlc_ctx_lock) are initialized once
   in main(), not here. */
void rlc_init(const unsigned int rlcId, const unsigned int cellId, mm_context_t *mm_ctx) {
    rlc_context_t *ctx = &rlc_ctx[rlcId];
    ctx->rlcId = rlcId;
    ctx->cellId = cellId;
    ctx->pollPdu = 32;
    ctx->pollByte = 25000;
    ctx->pduWithoutPoll = 0;
    ctx->byteWithoutPoll = 0;
    ctx->vtNextAck = 0;
    ctx->vtNext = 0;

    // Initialize the linked lists
    list_init(&ctx->list);
    list_init(&ctx->sent_list);

    // Set the memory management context
    ctx->mm_ctx = mm_ctx;

#if RLC_TB_MODE == RLC_TB_MODE_AM
    rlc_am_init(rlcId);
#endif
#if RLC_UL_MODE
    /* Uplink init must happen HERE, not lazily on entry to the consumer: it
       programmes the cluster tile participation mask, and main.c's startup
       snrt_cluster_hw_barrier() right after this is the resync point the
       partial-barrier API requires before that mask can be relied on. */
    if (rlcId == 0u) rlc_ul_init();
#endif
}

int __attribute__((noinline)) pdcp_receive_pkg(const unsigned int core_id, volatile int *lock) {
    uint32_t timer_ac_lock_0, timer_ac_lock_1;
    uint32_t timer_rl_lock_0, timer_rl_lock_1;
    uint32_t timer_body_0, timer_body_1;

    // timer_ac_lock_0 = benchmark_get_cycle();
#ifdef USE_MCS_LOCK_2
    mcs_lock_acquire(lock, 10);
#else
    spin_lock(lock, 10);
#endif
    // timer_ac_lock_1 = benchmark_get_cycle();

    // timer_body_0 = benchmark_get_cycle();
    int pkg_ptr = -1; // Initialize package pointer to -1 (indicating no package)
    if (pdcp_pkd_ptr < NUM_PKGS) {
        // If the pointer is within bounds, return the package pointer
        pkg_ptr = pdcp_pkd_ptr;
        pdcp_pkd_ptr++; // Increment the pointer for the next package
#if RLC_ARRIVAL_PPS
        /* The arrival clock starts with the first descriptor. Set under the lock, so every later
           taker (who acquires the lock after this release) sees it. */
        if (pkg_ptr == 0) rlc_arrival_t0 = benchmark_get_cycle();
#endif
    } else {
        DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
        DEBUG_PRINTF("Producer (core %u): out of PDCP pkg, pdcp_pkd_ptr = %d\n", core_id, pdcp_pkd_ptr);
        DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
    }
    // timer_body_1 = benchmark_get_cycle();

    // timer_rl_lock_0 = benchmark_get_cycle();
#ifdef USE_MCS_LOCK_2
    mcs_lock_release(lock, 10);
#else
    spin_unlock(lock, 10);
#endif
    // timer_rl_lock_1 = benchmark_get_cycle();

    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u][pdcp_receive_pkg] spin_unlock, ac=%d, bd=%d, rl=%d\n",
    //     core_id,
    //     (timer_ac_lock_1 - timer_ac_lock_0),
    //     (timer_body_1 - timer_body_0),
    //     (timer_rl_lock_1 - timer_rl_lock_0)
    // );
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
    return pkg_ptr; // Return the package pointer
}

/*
   Each allocation is a fixed-size page (PAGE_SIZE bytes).
   The Node structure is placed at the beginning of the page and the remaining
   space is used for payload. Thus, available payload size is:
*/
#define PACKET_SIZE (PAGE_SIZE - sizeof(Node))

// -- Producer / consumer core sets --
// The generated data header is authoritative: producer_core_ids[] and
// consumer_core_ids[] name the cores that run the kernel, so the roles can be
// spread over specific tiles/groups rather than being forced into contiguous
// ranges.  PRODUCER_CORE_NUM / CONSUMER_CORE_NUM remain as build-time knobs
// for headers generated before the lists existed, and as the pacing divisor.
#if defined(NUM_PRODUCER_CORES) && defined(NUM_CONSUMER_CORES)
/* The data header names the cores explicitly. */
#define RLC_CORE_LISTS 1
#ifndef PRODUCER_CORE_NUM
#define PRODUCER_CORE_NUM NUM_PRODUCER_CORES
#endif
#ifndef CONSUMER_CORE_NUM
#define CONSUMER_CORE_NUM NUM_CONSUMER_CORES
#endif
#else
/* Header predates the core lists: fall back to contiguous ranges -- cores
   [0, PRODUCER_CORE_NUM) produce and the next CONSUMER_CORE_NUM consume.
   Deriving the ranges instead of declaring a fixed id array matters: the array
   form would need a literal initializer per core count, and a short one (say
   {0,1}) paired with a large PRODUCER_CORE_NUM would read past its
   initializers and dispatch silently wrong. */
#define NUM_PRODUCER_CORES PRODUCER_CORE_NUM
#define NUM_CONSUMER_CORES CONSUMER_CORE_NUM
#endif

#if RLC_CORE_LISTS
/* Returns 1 if core_id appears in the given id list. */
static int core_in_list(const unsigned int core_id, const unsigned int *ids, unsigned int n) {
    for (unsigned int i = 0; i < n; i++) {
        if (ids[i] == core_id) return 1;
    }
    return 0;
}

/* Position of core_id within a list, or the list length if absent. */
static unsigned int core_index_in_list(const unsigned int core_id, const unsigned int *ids,
                                       unsigned int n) {
    for (unsigned int i = 0; i < n; i++) {
        if (ids[i] == core_id) return i;
    }
    return n;
}
#endif

/* Role of a core, and a consumer's position among the consumers. The position
   is what selects that consumer's share of the RLC entities, so it must follow
   the core list when there is one and the contiguous range otherwise. */
static inline int rlc_is_consumer(const unsigned int core_id) {
#if RLC_CORE_LISTS
    return core_in_list(core_id, consumer_core_ids, NUM_CONSUMER_CORES);
#else
    return (core_id >= PRODUCER_CORE_NUM) &&
           (core_id <  PRODUCER_CORE_NUM + CONSUMER_CORE_NUM);
#endif
}

static inline int rlc_is_producer(const unsigned int core_id) {
#if RLC_CORE_LISTS
    return !rlc_is_consumer(core_id) &&
           core_in_list(core_id, producer_core_ids, NUM_PRODUCER_CORES);
#else
    return core_id < PRODUCER_CORE_NUM;
#endif
}

static inline unsigned int rlc_consumer_index(const unsigned int core_id) {
#if RLC_CORE_LISTS
    return core_index_in_list(core_id, consumer_core_ids, NUM_CONSUMER_CORES);
#else
    return core_id - PRODUCER_CORE_NUM;
#endif
}

/* The number of consumers that actually exist.

   CONSUMER_CORE_NUM is a build define and may exceed the length of the data
   header's consumer_core_ids list, which is what dispatch really follows. Any
   arithmetic that partitions work *across consumers* must use this, not the
   define: sizing a partition by the define while only the listed cores exist
   leaves the surplus shares with no core to claim them. */
#if RLC_CORE_LISTS
#define RLC_ACTUAL_CONSUMERS NUM_CONSUMER_CORES
#else
#define RLC_ACTUAL_CONSUMERS CONSUMER_CORE_NUM
#endif

/* Cluster tile-participation mask for the consumer set: one bit per tile.
   Used to arm the narrowed-barrier region -- see rlc_sync.h for why this is
   done on entry to the consumer loop rather than at init. Needs the explicit
   core lists, which is also where the barrier participant set comes from. */
#if RLC_NARROWED_BARRIER
#if !RLC_CORE_LISTS
#error "a narrowed barrier needs RLC_CORE_LISTS: the participant set comes from consumer_core_ids"
#endif
static inline void rlc_consumer_tile_mask(uint32_t *lo, uint32_t *hi) {
    const uint32_t cpt = snrt_cluster_core_per_tile();
    uint32_t l = 0u, h = 0u;
    for (uint32_t i = 0u; i < RLC_ACTUAL_CONSUMERS; i++) {
        const uint32_t t = (uint32_t)consumer_core_ids[i] / cpt;
        if (t < 32u) l |= 1u << t; else h |= 1u << (t - 32u);
    }
    *lo = l; *hi = h;
}
#endif /* RLC_NARROWED_BARRIER */

/* The core that runs the UE status task: the first producer, whichever it is. */
static inline unsigned int rlc_status_core(void) {
#if RLC_CORE_LISTS
    return producer_core_ids[0];
#else
    return 0;
#endif
}

#if RLC_GROUP_STREAMS
#if !RLC_CORE_LISTS
#error "RLC_GROUP_STREAMS needs the data header's producer_core_ids"
#endif
/* Lead between stream setup and the first paced arrival: covers the start barrier and dispatch. */
#define RLC_ARRIVAL_LEAD 5000u

static inline uint32_t rlc_group_of(uint32_t core) {
    return core / (snrt_cluster_core_per_tile() * RLC_TILES_PER_GROUP);
}

/* The STATUS core (first producer) takes no packets in stream mode when there are other producers:
   it sweeps every entity between two packets, so a stream it owned would lag the others by that
   much, and with paced arrival nobody steals from a stream that is late but not empty (TC3 16P:
   1/16 of the packets up to 5 ms late). */
#define RLC_STATUS_PRODUCES (NUM_PRODUCER_CORES == 1)

/* Stream of a core = position of its group among the distinct groups of the packet-taking
   producers, in list order. Also returns the number of streams. */
static uint32_t rlc_stream_index(uint32_t core, uint32_t *nstreams) {
    uint32_t groups[RLC_MAX_STREAMS];
    uint32_t n = 0u, mine = 0u;
    const uint32_t g_me = rlc_group_of(core);
    for (uint32_t i = RLC_STATUS_PRODUCES ? 0u : 1u; i < NUM_PRODUCER_CORES; i++) {
        const uint32_t g = rlc_group_of(producer_core_ids[i]);
        uint32_t j = 0u;
        while (j < n && groups[j] != g) j++;
        if (j == n && n < RLC_MAX_STREAMS) groups[n++] = g;
        if (g == g_me) mine = j;
    }
    *nstreams = n;
    return mine;
}

void rlc_streams_init(void) {
    uint32_t n;
    (void)rlc_stream_index(producer_core_ids[NUM_PRODUCER_CORES - 1], &n);
    rlc_nstreams = n;
    rlc_stream_pages = (MM_POOL_PAGES + n - 1u) / n;
    for (uint32_t s = 0u; s < RLC_MAX_STREAMS; s++) {
        rlc_stream[s].next = 0u;
        rlc_stream[s].pool_lock = 0;
        rlc_stream[s].pool_used = 0u;
        rlc_stream[s].free_list = NULL;
    }
#if RLC_ARRIVAL_PPS
    rlc_arrival_t0 = benchmark_get_cycle() + RLC_ARRIVAL_LEAD;
#endif
}

/* This core's stream, set once on entry to the producer loop, and the stream it currently takes
   from (its own until that runs dry, then the others in turn). */
static __thread uint32_t rlc_my_stream;
static __thread uint32_t rlc_take_stream;

/* Next descriptor, or -1 when every stream is exhausted.

   A producer drains its own stream first and then steals from the others. Without stealing a
   stream is only as fast as its own producers: the STATUS core is also a producer and sweeps
   every entity between two packets, so on TC3 (4800 entities) its stream trickled out for
   ~170 ms after all the others were done. */
#if RLC_ARRIVAL_PPS
#define CPU_FREQENCY 1000000000 /* same definition as below, needed earlier here */
#define RLC_PERIOD_Q8 (((uint64_t)CPU_FREQENCY << 8) / RLC_ARRIVAL_PPS)
static inline uint32_t rlc_due(uint32_t idx) {
    return rlc_arrival_t0 + (uint32_t)(((uint64_t)idx * RLC_PERIOD_Q8) >> 8);
}
/* Streams are fed by different numbers of producers (the STATUS core's group has one fewer), so
   under paced arrival one stream can fall behind while the others are merely early -- and
   stealing on exhaustion never triggers. A producer whose own next packet has not arrived yet
   serves the first stream that is more than RLC_STEAL_SLACK cycles behind instead of waiting. */
#define RLC_STEAL_SLACK 2000u
static int rlc_stream_take_late(void) {
    const uint32_t now = benchmark_get_cycle();
    const uint32_t own = rlc_take_stream;
    const uint32_t k_own = atomic_load_explicit(&rlc_stream[own].next, memory_order_relaxed);
    const uint32_t i_own = k_own * rlc_nstreams + own;
    if (i_own >= NUM_PKGS || (int32_t)(rlc_due(i_own) - now) <= 0) return -1;
    for (uint32_t d = 1u; d < rlc_nstreams; d++) {
        const uint32_t s = (own + d) % rlc_nstreams;
        const uint32_t k = atomic_load_explicit(&rlc_stream[s].next, memory_order_relaxed);
        const uint32_t i = k * rlc_nstreams + s;
        if (i < NUM_PKGS && (int32_t)(now - rlc_due(i)) > (int32_t)RLC_STEAL_SLACK) {
            const uint32_t k2 = atomic_fetch_add_explicit(&rlc_stream[s].next, 1u, memory_order_relaxed);
            const uint32_t i2 = k2 * rlc_nstreams + s;
            if (i2 < NUM_PKGS) return (int)i2;
        }
    }
    return -1;
}
#endif

static int rlc_stream_take(void) {
#if RLC_ARRIVAL_PPS
    const int late = rlc_stream_take_late();
    if (late >= 0) return late;
#endif
    for (uint32_t tries = 0u; tries < rlc_nstreams; tries++) {
        const uint32_t s = rlc_take_stream;
        const uint32_t k = atomic_fetch_add_explicit(&rlc_stream[s].next, 1u, memory_order_relaxed);
        const uint32_t idx = k * rlc_nstreams + s;
        if (idx < NUM_PKGS) return (int)idx;
        rlc_take_stream = (s + 1u == rlc_nstreams) ? 0u : s + 1u;
    }
    return -1;
}

/* Nodes come from the slice of the stream the packet belongs to, not the producer's: a stealing
   producer would otherwise run its own slice dry, and an allocation failure drops the packet. */
static void *rlc_node_alloc(uint32_t s) {
    rlc_stream_t *st = &rlc_stream[s];
    void *page = NULL;
    mm_lock_acquire(&st->pool_lock);
    if (st->pool_used < rlc_stream_pages) {
        page = (uint8_t *)bulk_buffer + (s * rlc_stream_pages + st->pool_used) * PAGE_SIZE;
        st->pool_used++;
    } else if (st->free_list != NULL) {
        page = (void *)st->free_list;
        st->free_list = st->free_list->next;
    }
    mm_lock_release(&st->pool_lock);
    return page;
}

static void rlc_node_free(void *p) {
    if (!p) return;
    const uint32_t s = (uint32_t)(((uint8_t *)p - (uint8_t *)bulk_buffer) / PAGE_SIZE) / rlc_stream_pages;
    rlc_stream_t *st = &rlc_stream[s];
    mm_lock_acquire(&st->pool_lock);
    ((MM_FreePage *)p)->next = st->free_list;
    st->free_list = (MM_FreePage *)p;
    mm_lock_release(&st->pool_lock);
}
#define RLC_NODE_ALLOC(idx) rlc_node_alloc((uint32_t)(idx) % rlc_nstreams)
#define RLC_NODE_FREE(p) rlc_node_free(p)
#else
#define RLC_NODE_ALLOC(idx) mm_alloc()
#define RLC_NODE_FREE(p) mm_free(p)
#endif

/* AM transport-block assembly. Included here, after the core-role helpers, so
   rlc_ctx[], the per-user list locks and rlc_consumer_index() are in scope. */
#if RLC_TB_MODE == RLC_TB_MODE_AM
#include "rlc_am.c"
#endif

/* Uplink. Needs the same helpers, plus consumer_core_ids for the partial
   barrier -- hence the core-list requirement. */
#if RLC_UL_MODE
#if !RLC_CORE_LISTS
#error "RLC_UL_MODE needs RLC_CORE_LISTS: the UL barrier set comes from consumer_core_ids"
#endif
#include "rlc_ul_drv.c"
#endif

#define CPU_FREQENCY 1000000000 // 1GHz
#define OUTPUT_DATARATE 7000000
#define INPUT_DATARATE 7000000

/* Per-iteration pacing budget. RLC_ENABLE_PACING=1: correct 64-bit math
   (intended INPUT/OUTPUT_DATARATE pacing). =0 (default): the legacy int32
   expression — it overflows (e.g. 2*1360*1e9 wraps to 1285701632 -> 183 cyc),
   which makes pacing nearly inert, but tiny delays still fire on iterations
   shorter than the wrapped value, so keep it verbatim for TC1 parity. */
#if RLC_ENABLE_PACING
#define RLC_TOTAL_CYCLE(ncore, rate) ((uint32_t)(((uint64_t)(ncore) * PDU_SIZE * CPU_FREQENCY) / (rate)))
#else
#define RLC_TOTAL_CYCLE(ncore, rate) ((uint32_t)((ncore) * PDU_SIZE * CPU_FREQENCY / (rate)))
#endif

void ue_status_rpt(const unsigned int core_id)
{
#if RLC_TB_MODE == RLC_TB_MODE_AM
    /* AM builds and parses a real STATUS PDU and releases SDUs by SN. The
       legacy model below acknowledges a fixed two *nodes* per pass and
       advances vtNextAck by two, which stops meaning anything once
       segmentation makes the SDU count and the SN count diverge. */
    (void)core_id;
    rlc_am_status();
    return;
#else
    // Simulate receiving ACK from UE after certain sent pkgs, per RLC entity.
    // ACK_SN is ctx->vtNextAck+2. Core 0 scans all users each call (single
    // writer per entity; striping across producer cores is a future option).
    for (unsigned int u = 0; u < NUM_USERS; u++) {
        rlc_context_t *ctx = &rlc_ctx[u];
        if (ctx->sent_list.sduNum >= 2) {
            char head = ue_status_rpt_content.stateRpt[0];
            char head1 = ue_status_rpt_content.stateRpt[1];
            char head2 = ue_status_rpt_content.stateRpt[2];
            uint32_t vtNextAck = atomic_load_explicit(&ctx->vtNextAck, memory_order_relaxed);
            int ACK_SN = vtNextAck + 2; // Assume each time ack 2 sent pkgs

            for (int i = vtNextAck; i < ACK_SN; i++) {
                char ack = ue_status_rpt_content.stateRpt[16 + ACK_SN - i];
                Node *sent_node = list_pop_front((spinlock_t *)RLC_SENT_LOCK(u), &ctx->sent_list);
                if (sent_node != NULL) {
                    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
                    // DEBUG_PRINTF("[core %u][consumer] pop sent_list, ACK_SN=%d, SN=%d, sent node %p, data_size=%zu\n",
                    //        core_id, ACK_SN, i, (void *)sent_node, sent_node->data_size);
                    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
                } else {
                    DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
                    DEBUG_PRINTF("[core %u][consumer] ERROR: pop sent_list, ACK_SN=%d, SN=%d, but sent_node is NULL\n",
                            core_id, ACK_SN, i);
                    DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
                }
                RLC_NODE_FREE(sent_node); // Free the sent node memory
            }
            ctx->acksn = ACK_SN;
            ctx->nackcount = 0;
            ctx->parseindex++;
            atomic_store_explicit(&ctx->vtNextAck, ACK_SN, memory_order_relaxed); // Update the next ACK sequence number
            perf_probe_entity(PROBE_EVT_STATUS_ACK, u, 2u);
            for (uint32_t i = 0; i < 16; i++) {
                ctx->dlDelayInfo[i] = 300;
            }
        }
    }
#endif /* RLC_TB_MODE */
}

/* Pop one node from entity ctx's to-send list and assemble/send its PDU.
   Returns 1 if a node was processed, 0 if the list was empty. */
static int rlc_send_pkt(const unsigned int core_id, rlc_context_t *ctx, TestDataStru *testData)
{
    const unsigned int u = (unsigned int)(ctx - rlc_ctx); // lock-free user index
#if RLC_PAD_SYNC
    /* Look before locking: an idle consumer otherwise takes the lock (an atomic swap) on every
       poll of an empty queue. A plain load; a push that lands just after is seen next pass. */
    if (ctx->list.sduNum == 0) return 0;
#endif
    Node *node = list_pop_front((spinlock_t *)RLC_TOSEND_LOCK(u), &ctx->list);
    if (node == 0) {
        return 0;
    }
    /* No queue-depth gauges here: reading list.sduNum means a load on the line every core
       contends for, and it measurably slowed the kernel it was measuring. Depth is rebuilt from
       the SDU_RX / PDU_TX / STATUS_ACK counts instead. */
    perf_probe_phase(PERF_PROBE_PHASE_EXECUTE);
#ifdef RLC_NODE_GUARD
    if (((uintptr_t)node->data & 0xFF000000) != 0xA0000000 ||
        ((uintptr_t)node->tgt  & 0xFF000000) != 0xB0000000 ||
        node->data_size != PDU_SIZE || node->user_id != u) {
        printf_lock_acquire(&printf_lock);
        printf("[GUARD][core %u] BAD NODE u=%u node=%p user=%u data=0x%x tgt=0x%x size=%u cyc=%d\n",
               core_id, u, (void *)node, node->user_id,
               (unsigned int)(uintptr_t)node->data, (unsigned int)(uintptr_t)node->tgt,
               (unsigned int)node->data_size, benchmark_get_cycle());
        printf_lock_release(&printf_lock);
    }
#endif
        // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
        // DEBUG_PRINTF("Consumer (core %u): processing node %p, data_size = %zu, data_src = 0x%x, data_tgt = 0x%x, @mcycle = %d\n",
        //        core_id, (void *)node, node->data_size, node->data, node->tgt, benchmark_get_cycle());
        // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

        // delay(100);  /* Simulate processing delay */

        uint32_t timer_mv_0, timer_mv_1;
        // timer_mv_0 = benchmark_get_cycle();
        // vector_memcpy32_m4_opt(node->tgt, node->data, node->data_size);
        // vector_memcpy32_m8_opt(node->tgt, node->data, node->data_size);
        // scalar_memcpy32_32bit_unrolled(node->tgt, node->data, node->data_size);
        // vector_memcpy32_m8_m4_general_opt(node->tgt, node->data, node->data_size);
        // vector_memcpy32_1360B_opt(node->tgt, node->data);
        // Atomically allocate a unique RLC sequence number for this PDU from
        // the OWNING entity (SNs are per-RLC-entity) and use it as the header.
        uint32_t sn = atomic_fetch_add_explicit(&ctx->vtNext, 1, memory_order_relaxed);
#if (PDU_SIZE == 1360)
        vector_memcpy32_1360B_opt_with_header(node->tgt, node->data, sn);
#else
        // Generic path (e.g. 810-byte PDUs): word-vector copy (bases are
        // 4-aligned by PDU_STRIDE; the tail switch handles the odd bytes),
        // then the SN overwrites the first header word of the target.
        vector_memcpy32_m8_m4_general_opt(node->tgt, node->data, node->data_size);
        *(volatile uint32_t *)node->tgt = sn;
#endif
        // timer_mv_1 = benchmark_get_cycle();

        // Update the RLC stats atomically (shared across multiple consumers).
        atomic_fetch_add_explicit(&ctx->pduWithoutPoll,  1,               memory_order_relaxed);
        atomic_fetch_add_explicit(&ctx->byteWithoutPoll, node->data_size, memory_order_relaxed);
        ctx->sendPduNum +=1;
        ctx->sendPduBytes += node->data_size;
        atomic_fetch_add_explicit(&ctx->tbsize, (node->data_size + 10), memory_order_relaxed);
        /* read one cacheline from node mem */
        RcvPktHeader tmp = *(RcvPktHeader *)node->data;
        /* write 64B to node mem */
        vector_memcpy32_m4_opt(((RcvPktHeader *)node->data + 1), &tmp, sizeof(RcvPktHeader));
        ctx->pdcpcount++;
        atomic_fetch_add_explicit(&ctx->rlcthrp, node->data_size, memory_order_relaxed);
        atomic_fetch_add_explicit(&ctx->dlPduNum, 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&ctx->sduBytes, (0 - node->data_size), memory_order_relaxed);
        atomic_fetch_add_explicit(&ctx->sduNum, (-1), memory_order_relaxed);
        testData->sduNum = ctx->sduNum;
        testData->rlcDpbPduCnt = ctx->pdcpcount;
        testData->sudBytes = ctx->sduBytes;
        testData->totalPdlLen = ctx->tbsize;
        /* write one cacheline data to rlc_entity */
        for (uint32_t i = 0; i < 16; i++) {
            ctx->rlcOm[i] = 20;
        }
        // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
        // DEBUG_PRINTF("Consumer (core %u): move node %p from data_src = 0x%x to data_tgt = 0x%x, data_size = %zu, cyc = %d, bw = %dB/1000cyc\n",
        //        core_id, (void *)node, node->data, node->tgt, node->data_size,
        //        (timer_mv_1 - timer_mv_0),
        //        (node->data_size * 1000 / (timer_mv_1 - timer_mv_0)));
        // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

        perf_probe_entity(PROBE_EVT_PDU_TX, u, (uint32_t)node->data_size);
        perf_probe(PROBE_EVT_PKT_OUT, (uint32_t)(uintptr_t)node);
            // Add the node to the sent list
        list_push_back((spinlock_t *)RLC_SENT_LOCK(u), &ctx->sent_list, node);
        return 1;
}

/* Consumer behavior: static user partition + round-robin scan, one node per
   (paced) iteration. Consumer c (index within the consumer group) owns users
   {u : u % stride == c % stride} with stride = min(CONSUMER_CORE_NUM,
   NUM_USERS); at NUM_USERS == 1 stride is 1, so all consumers share user 0 —
   exactly the single-user behavior. The scan always issues the pop attempt
   (no sduNum pre-check) to keep the idle lock traffic of the baseline.
   Rate-limited so the aggregate consumer throughput equals OUTPUT_DATARATE
   when pacing is enabled. */
#if RLC_UL_MODE
/* Uplink mode: the consumer set runs receive/reassemble/deliver slots instead
   of downlink assembly. Producers still run their normal path -- they are the
   source of the payload the uplink harness retransmits. */
static void consumer(const unsigned int core_id) { rlc_ul_consumer(core_id); }
#elif RLC_TB_MODE == RLC_TB_MODE_AM
static void consumer(const unsigned int core_id) {
    /* Grant-based assembly: plan (owner) + execute (all cores) + commit. */
#if RLC_AM_TTI && RLC_CORE_LISTS
    /* TTI-structured: the three phases are separated by a partial barrier over
       the consumer set, so a helper with nothing to do blocks rather than
       sweeping the entity list. Requires explicit core lists, which is where
       the barrier participant set comes from. */
#ifdef RLC_SELF_CHECK
    printf_lock_acquire(&printf_lock);
    printf("[AM] core %u: consumer idx=%u (TTI mode)\n", core_id,
           rlc_consumer_index(core_id));
    printf_lock_release(&printf_lock);
#endif
    rlc_am_consumer_tti(core_id);
    return;
#endif
#ifdef RLC_SELF_CHECK
    printf_lock_acquire(&printf_lock);
    printf("[AM] core %u: consumer idx=%u\n", core_id,
           rlc_consumer_index(core_id));
    printf_lock_release(&printf_lock);
#endif
    while (1) {
        rlc_am_step(core_id);
        if (atomic_load_explicit(&producer_done, memory_order_relaxed) >=
                PRODUCER_CORE_NUM &&
            rlc_am_idle()) {
            break;
        }
    }
}
#else
static void consumer(const unsigned int core_id) {
    const unsigned int c      = rlc_consumer_index(core_id);
    const unsigned int stride = (CONSUMER_CORE_NUM < NUM_USERS) ? CONSUMER_CORE_NUM : NUM_USERS;
    const unsigned int first  = c % stride;      /* first owned user */
    unsigned int cursor = first;
    uint32_t total_cycle = RLC_TOTAL_CYCLE(CONSUMER_CORE_NUM, OUTPUT_DATARATE);
#if RLC_PROBE
    uint32_t probe_ph = 0xffffffffu;
#endif
    while (1) {
        uint32_t start_timecycle = benchmark_get_cycle();
        TestDataStru dfx = {0};
        dfx.dlschInd = dlsch_ind;
        /* round-robin over owned users; send at most one PDU per iteration */
        unsigned int u = cursor;
        int sent = 0;
        do {
            sent = rlc_send_pkt(core_id, &rlc_ctx[u], &dfx);
            if (!sent) { u += stride; if (u >= NUM_USERS) u = first; }
        } while (!sent && u != cursor);
        if (sent) { u += stride; if (u >= NUM_USERS) u = first; cursor = u; }
#if RLC_PROBE
        if (sent) probe_ph = PERF_PROBE_PHASE_EXECUTE;   /* rlc_send_pkt stored it */
        else RLC_PROBE_PHASE_TO(probe_ph, PERF_PROBE_PHASE_IDLE);
#endif
        uint32_t end_timecycle = benchmark_get_cycle();
        /* calculate delay interval */
        uint32_t interval = end_timecycle - start_timecycle;
        rlc_ctx[first].pktdelay = interval;
        uint32_t delayCycle = (total_cycle >= interval) ? (total_cycle - interval) : 0;
        delay(delayCycle);

        /* Exit when all producers are done and every owned list is drained */
        if (atomic_load_explicit(&producer_done, memory_order_relaxed) >= PRODUCER_CORE_NUM) {
            int drained = 1;
            for (unsigned int v = first; v < NUM_USERS; v += stride) {
                if (rlc_ctx[v].list.sduNum != 0) { drained = 0; break; }
            }
            if (drained) break;
        }
    }
}
#endif /* RLC_TB_MODE */

/* Producer behavior (runs on cores other than 0) */
/* Returns 0 on success, -1 when no more packages available. */
static int producer(const unsigned int core_id) {
    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("Producer (core %u): pdcp_src_data[0][0] = %d, pdcp_src_data[3657][500] = %d, pdcp_src_data[%d-1][%d-1] = %d, @mcycle = %d\n",
    //     core_id,
    //     pdcp_src_data[0][0],
    //     pdcp_src_data[3657][500],
    //     NUM_SRC_SLOTS,
    //     PDU_SIZE,
    //     pdcp_src_data[NUM_SRC_SLOTS-1][PDU_SIZE-1],
    //     benchmark_get_cycle());
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
#if RLC_GROUP_STREAMS
    int new_pdcp_pkg_ptr = rlc_stream_take();
#else
    int new_pdcp_pkg_ptr = pdcp_receive_pkg(core_id, &pdcp_pkd_ptr_lock);
#endif
    if (new_pdcp_pkg_ptr < 0) {
        return -1;  // No more packages
    }
#if RLC_ARRIVAL_PPS
    /* Wait for this packet's arrival time. Q8 fixed-point period keeps the math in 64-bit
       multiplies (no 64-bit divide on rv32). */
    const uint64_t rlc_period_q8 = ((uint64_t)CPU_FREQENCY << 8) / RLC_ARRIVAL_PPS;
    const uint32_t due = rlc_arrival_t0 + (uint32_t)(((uint64_t)new_pdcp_pkg_ptr * rlc_period_q8) >> 8);
    uint32_t now_cyc;
    while ((int32_t)((now_cyc = benchmark_get_cycle()) - due) < 0) { }
    /* How long ago it arrived; the collector back-dates this packet's PKT_IN by it. Sent here,
       from the cycle already read, not later: a csrr after the vector header copy would wait for
       the vector unit to drain. */
    perf_probe(PROBE_EVT_PKT_LATE, now_cyc - due);
#endif

    /* Route the package to its owning RLC entity (one per UE). */
    const unsigned int uid = (unsigned int)pdcp_pkgs[new_pdcp_pkg_ptr].user_id;
    rlc_context_t *ctx = &rlc_ctx[uid];
    ctx->latestSduPktRxCycle = benchmark_get_cycle();
#ifdef RLC_NODE_GUARD
    if (uid >= NUM_USERS ||
        (pdcp_pkgs[new_pdcp_pkg_ptr].src_addr & 0xFF000000) != 0xA0000000 ||
        (pdcp_pkgs[new_pdcp_pkg_ptr].tgt_addr & 0xFF000000) != 0xB0000000) {
        printf_lock_acquire(&printf_lock);
        printf("[GUARD][core %u] BAD DESCRIPTOR idx=%d uid=%u src=0x%x tgt=0x%x cyc=%d\n",
               core_id, new_pdcp_pkg_ptr, uid,
               pdcp_pkgs[new_pdcp_pkg_ptr].src_addr, pdcp_pkgs[new_pdcp_pkg_ptr].tgt_addr,
               benchmark_get_cycle());
        printf_lock_release(&printf_lock);
    }
#endif

    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("Producer (core %u): pdcp_receive_pkg id = %d, user_id = %d, pkg_length = %d, src_addr = 0x%x, tgt_addr = 0x%x\n",
    //     core_id,
    //     new_pdcp_pkg_ptr,
    //     pdcp_pkgs[new_pdcp_pkg_ptr].user_id,
    //     pdcp_pkgs[new_pdcp_pkg_ptr].pkg_length,
    //     pdcp_pkgs[new_pdcp_pkg_ptr].src_addr,
    //     pdcp_pkgs[new_pdcp_pkg_ptr].tgt_addr);
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);


    Node *node = (Node *)RLC_NODE_ALLOC(new_pdcp_pkg_ptr);
    if (!node) {

        DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
        DEBUG_PRINTF("Producer (core %u): Out of memory\n", core_id);
        DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

        delay(200);  /* Delay before retrying */
        return 0;  /* Not done, just out of memory temporarily */
    }

    uint32_t timer_body_0, timer_body_1;

    // timer_body_0 = benchmark_get_cycle();
    /* Initialize the node header */
    node->lock = 0;
    node->prev = 0;
    node->next = 0;
    node->user_id = uid;
    /* Set the payload pointer immediately after the Node structure */
    if (new_pdcp_pkg_ptr >= 0) {
        node->data = (void *)((uint8_t *)(pdcp_pkgs[new_pdcp_pkg_ptr].src_addr));
        node->tgt = (void *)((uint8_t *)(pdcp_pkgs[new_pdcp_pkg_ptr].tgt_addr));
        node->data_size = pdcp_pkgs[new_pdcp_pkg_ptr].pkg_length;
        /* read one cacheline from node mem */
        RcvPktHeader tmp = *(RcvPktHeader *)node->data;
        unsigned int pingflag = ctx->pingFlag;
        atomic_store_explicit(&ctx->pingFlag, pingflag, memory_order_relaxed);
        atomic_store_explicit(&ctx->recvMaxByte, node->data_size, memory_order_relaxed);
        RcvPktHeader *pt = (RcvPktHeader *)((char *)node->data + sizeof(RcvPktHeader));
        /* write 64B data to Node */
        vector_memcpy32_m4_opt((pt + 1), &tmp, sizeof(RcvPktHeader));
        atomic_fetch_add_explicit(&ctx->sduNumCong, 1, memory_order_relaxed);
        atomic_store_explicit(&ctx->sudCongState, 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&ctx->pktdelayEnqueFlag, 1, memory_order_relaxed);
    }
    // timer_body_1 = benchmark_get_cycle();

    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u][bd fill_node] mm_alloc: node = %p, data = 0x%x, tgt = 0x%x, data_size = %zu, bd=%d\n",
    //     core_id,
    //     (void *)node,
    //     node->data,
    //     node->tgt,
    //     node->data_size,
    //     (timer_body_1 - timer_body_0)
    // );
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);


    // /* Zero-initialize the payload using our custom mm_memset */
    // mm_memset(node->data, 0, PACKET_SIZE);
    /* Append the node to the owning entity's to-send list */
#if RLC_TB_MODE != RLC_TB_MODE_AM
    perf_probe(PROBE_EVT_PKT_IN, (uint32_t)(uintptr_t)node);
#endif
    perf_probe_entity(PROBE_EVT_SDU_RX, uid, (uint32_t)node->data_size);
    list_push_back((spinlock_t *)RLC_TOSEND_LOCK(uid), &ctx->list, node);
#if (RLC_TB_MODE == RLC_TB_MODE_AM) && RLC_AM_WORKQ
    /* Announce the entity so an owner picks it up without scanning. */
    rlc_am_mark_ready(uid);
#endif
    atomic_fetch_add_explicit(&ctx->sduBytes, node->data_size, memory_order_relaxed);
    atomic_fetch_add_explicit(&ctx->sduNum, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&ctx->recvPdcpPduBytes, node->data_size, memory_order_relaxed);
    ctx->lastRcvOrSubmitDataCyc = benchmark_get_cycle() - ctx->latestSduPktRxCycle;

    atomic_fetch_add_explicit(&ctx->rcvPktNum, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&ctx->rcvPktLength, node->data_size, memory_order_relaxed);
    atomic_fetch_add_explicit(&ctx->enQuePktNum, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&ctx->enQuePktLength, node->data_size, memory_order_relaxed);

    DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    DEBUG_PRINTF("Producer (core %u): added node %p, size = %d, src_addr = 0x%x, tgt_addr = 0x%x\n", 
        core_id,
        (void *)node,
        node->data_size,
        node->data,
        node->tgt);
    DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

    // delay(200);  /* Delay between node productions */
    return 0;
}

static void pkt_production_and_recycle(const unsigned int core_id)
{
    uint32_t total_cycle = RLC_TOTAL_CYCLE(PRODUCER_CORE_NUM, INPUT_DATARATE);
    int this_core_done = 0;
#if RLC_GROUP_STREAMS
    uint32_t nstreams_unused;
    rlc_my_stream = rlc_stream_index(core_id, &nstreams_unused);
    rlc_take_stream = rlc_my_stream;
    (void)nstreams_unused;
    if (!RLC_STATUS_PRODUCES && core_id == rlc_status_core()) {
        /* STATUS only: counts as a finished producer from the start. */
        this_core_done = 1;
        atomic_fetch_add_explicit(&producer_done, 1, memory_order_relaxed);
    }
#endif
#if RLC_PROBE
    uint32_t probe_ph = 0xffffffffu;
#endif
    while (1) {
        uint32_t start_timecycle = benchmark_get_cycle();
#if RLC_PROBE
        RLC_PROBE_PHASE_TO(probe_ph, this_core_done ? PERF_PROBE_PHASE_DONE : PERF_PROBE_PHASE_RECEIVE);
#endif
        if (!this_core_done) {
            if (producer(core_id) < 0) {
                this_core_done = 1;
                atomic_fetch_add_explicit(&producer_done, 1, memory_order_relaxed);
            }
        }
        /* UE status report runs on exactly one core -- the first producer in
           the list, not core 0: with explicit core lists core 0 need not be a
           producer at all, and gating on it would drop the ACK task entirely. */
        if (core_id == rlc_status_core()) {
#if RLC_PROBE
            if (!this_core_done) RLC_PROBE_PHASE_TO(probe_ph, PERF_PROBE_PHASE_STATUS);
#endif
            ue_status_rpt(core_id);
        }
#if RLC_PROBE
        RLC_PROBE_PHASE_TO(probe_ph, this_core_done ? PERF_PROBE_PHASE_DONE : PERF_PROBE_PHASE_IDLE);
#endif
        uint32_t end_timecycle = benchmark_get_cycle();
        /* calculate delay interval */
        uint32_t interval = end_timecycle - start_timecycle;
        uint32_t delayCycle = (total_cycle >= interval) ? (total_cycle - interval) : 0;
        delay(delayCycle);

        /* Exit only when THIS core has finished producing AND all other
           producers are also done.  Without the `this_core_done` guard a
           slow core would abandon its in-flight work the moment enough
           OTHER cores happened to finish first. */
        if (this_core_done &&
            atomic_load_explicit(&producer_done, memory_order_relaxed) >= PRODUCER_CORE_NUM) {
            break;
        }
    }
}

/* cluster_entry() dispatches behavior based on core_id: cores listed in
   producer_core_ids/consumer_core_ids (see the generated data header) run
   the RLC kernel; any other core stays idle for this run and just reaches
   the shared barrier below. */
void cluster_entry(const unsigned int core_id) {
    uint32_t timer_0, timer_1;
    perf_probe_init();
    timer_0 = benchmark_get_cycle();

    if(core_id == 0) {
        start_kernel();
        perf_probe(PROBE_EVT_KERNEL_START, 0u);
    }

    const int is_consumer = rlc_is_consumer(core_id);
    const int is_producer = rlc_is_producer(core_id);
#if RLC_PROBE
    perf_probe_role(is_producer ? PERF_PROBE_ROLE_PRODUCER :
                    is_consumer ? PERF_PROBE_ROLE_CONSUMER : PERF_PROBE_ROLE_IDLE);
    if (!is_producer && !is_consumer) perf_probe_phase(PERF_PROBE_PHASE_BARRIER);
#endif

    if (is_producer) {
        pkt_production_and_recycle(core_id);
    } else if (is_consumer) {
        consumer(core_id);
    } /* else: idle core for this run, falls through to the barrier */

#if RLC_NARROWED_BARRIER
    /* Cores that are not consumers must NOT be sitting at a barrier while the
       consumers hold the mask narrowed. Two hardware properties force this:
       whichever request arrives first owns a tile's round, and barrier_done is
       an unmasked cluster-wide broadcast. So they wait here, outside any
       barrier, until the mask has been restored. See rlc_sync.h. */
#if RLC_PROBE
    if (!is_consumer) perf_probe_phase(PERF_PROBE_PHASE_DONE);
#endif
    if (!is_consumer) rlc_narrow_wait_outside();
#endif

#if RLC_PROBE
    if (is_producer || is_consumer) perf_probe_phase(PERF_PROBE_PHASE_BARRIER);
#endif
    snrt_cluster_hw_barrier(); // this can trigger Misaligned Load exception

#if RLC_TB_MODE == RLC_TB_MODE_AM
    /* The legacy self_check compares the per-descriptor destinations, which
       the AM path never writes -- it assembles transport blocks instead, and
       those are checked at commit time by rlc_am_verify_grant(). */
    if (core_id == 0) {
        rlc_am_report();
    }
#elif defined(RLC_SELF_CHECK)
    /* All sends are complete and tgt buffers are stable here. */
    if (core_id == 0) {
        self_check(pdcp_pkgs, NUM_PKGS);
    }
#endif

    if(core_id == 0) {
        perf_probe(PROBE_EVT_KERNEL_END, 0u);
        stop_kernel();
    }

    timer_1 = benchmark_get_cycle();

    // printf is slow -- only cores that actually ran the kernel print
    // their timing; idle cores skip it entirely.
    if (!is_consumer && !is_producer) {
        return;
    }

    int use_mcs_lock;
#ifdef USE_MCS_LOCK
    use_mcs_lock = 1;
#else
    use_mcs_lock = 0;
#endif
    printf_lock_acquire(&printf_lock);
    printf("[core %u]: start cycle = %d, end cycle = %d, total cycles = %d, use_mcs_lock=%d\n",
        core_id,
        timer_0,
        timer_1,
        (timer_1 - timer_0),
        use_mcs_lock);
    printf_lock_release(&printf_lock);
}


void rlc_start(const unsigned int core_id) {
    /* Enter per-core processing based on core_id */
    cluster_entry(core_id);
}


#endif
