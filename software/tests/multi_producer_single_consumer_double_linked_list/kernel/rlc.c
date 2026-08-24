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

/* The core that runs the UE status task: the first producer, whichever it is. */
static inline unsigned int rlc_status_core(void) {
#if RLC_CORE_LISTS
    return producer_core_ids[0];
#else
    return 0;
#endif
}

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
                Node *sent_node = list_pop_front((spinlock_t *)&sent_llist_lock_2[u], &ctx->sent_list);
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
                mm_free(sent_node); // Free the sent node memory
            }
            ctx->acksn = ACK_SN;
            ctx->nackcount = 0;
            ctx->parseindex++;
            atomic_store_explicit(&ctx->vtNextAck, ACK_SN, memory_order_relaxed); // Update the next ACK sequence number
            for (uint32_t i = 0; i < 16; i++) {
                ctx->dlDelayInfo[i] = 300;
            }
        }
    }
}

/* Pop one node from entity ctx's to-send list and assemble/send its PDU.
   Returns 1 if a node was processed, 0 if the list was empty. */
static int rlc_send_pkt(const unsigned int core_id, rlc_context_t *ctx, TestDataStru *testData)
{
    const unsigned int u = (unsigned int)(ctx - rlc_ctx); // lock-free user index
    Node *node = list_pop_front((spinlock_t *)&tosend_llist_lock_2[u], &ctx->list);
    if (node == 0) {
        return 0;
    }
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

            // Add the node to the sent list
        list_push_back((spinlock_t *)&sent_llist_lock_2[u], &ctx->sent_list, node);
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
static void consumer(const unsigned int core_id) {
    const unsigned int c      = rlc_consumer_index(core_id);
    const unsigned int stride = (CONSUMER_CORE_NUM < NUM_USERS) ? CONSUMER_CORE_NUM : NUM_USERS;
    const unsigned int first  = c % stride;      /* first owned user */
    unsigned int cursor = first;
    uint32_t total_cycle = RLC_TOTAL_CYCLE(CONSUMER_CORE_NUM, OUTPUT_DATARATE);
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
    int new_pdcp_pkg_ptr = pdcp_receive_pkg(core_id, &pdcp_pkd_ptr_lock);
    if (new_pdcp_pkg_ptr < 0) {
        return -1;  // No more packages
    }

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


    Node *node = (Node *)mm_alloc();
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
    list_push_back((spinlock_t *)&tosend_llist_lock_2[uid], &ctx->list, node);
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
    while (1) {
        uint32_t start_timecycle = benchmark_get_cycle();
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
            ue_status_rpt(core_id);
        }
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
    timer_0 = benchmark_get_cycle();

    if(core_id == 0) {
        start_kernel();
    }

    const int is_consumer = rlc_is_consumer(core_id);
    const int is_producer = rlc_is_producer(core_id);

    if (is_producer) {
        pkt_production_and_recycle(core_id);
    } else if (is_consumer) {
        consumer(core_id);
    } /* else: idle core for this run, falls through to the barrier */

    snrt_cluster_hw_barrier(); // this can trigger Misaligned Load exception

#ifdef RLC_SELF_CHECK
    /* All sends are complete and tgt buffers are stable here. */
    if (core_id == 0) {
        self_check(pdcp_pkgs, NUM_PKGS);
    }
#endif

    if(core_id == 0) {
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
