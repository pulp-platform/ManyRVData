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

#ifndef RLC_H
#define RLC_H

#include <stdint.h>
#include <stdatomic.h>
#include <stddef.h>
#include "mm.h"
#include "llist.h"
#include "data_move_vec.h"
#include <stdatomic.h>

#define CACHE_LINE_SIZE 64 // Cache line size in bytes, typically 64 bytes

/* ---- Multi-user / use-case configuration ----------------------------------
   NUM_USERS = number of RLC entities (one per UE). Comes from the generated
   data header (ACTIVE_USER_NUMBER); headers generated before the multi-user
   extension don't define it, so fall back to the TC1 single-user case. */
#ifndef ACTIVE_USER_NUMBER
#define ACTIVE_USER_NUMBER 1
#endif
#define NUM_USERS ACTIVE_USER_NUMBER

/* Rate pacing. 0 (default): legacy int32 expression, wraps and makes pacing
   inert — preserved verbatim so TC1 numbers are bit-identical to the
   pre-extension baseline. 1: 64-bit math, pacing actually engages at
   INPUT/OUTPUT_DATARATE. */
#ifndef RLC_ENABLE_PACING
#define RLC_ENABLE_PACING 0
#endif

/* Paced arrival. 0 (default): every descriptor is available at t=0 (a burst). N: descriptor i
   arrives at t0 + i * CPU_FREQ / N cycles, t0 = when the first descriptor is taken, so the
   offered load is N packets/s -- the DP test case's rate. A producer holding a descriptor that
   has not arrived yet waits for it. Latency is then measured from the arrival time, so a
   producer that falls behind shows up as latency, not as a lower offered rate. */
#ifndef RLC_ARRIVAL_PPS
#define RLC_ARRIVAL_PPS 0
#endif

/* Per-user list locks (indexed by RLC entity / user id). */
#if RLC_PAD_SYNC
typedef struct {
    _Atomic mcs_lock_t l;
    char pad[RLC_SYNC_LINE_BYTES - sizeof(mcs_lock_t)];
} rlc_lock_line_t;
static rlc_lock_line_t tosend_llist_lock_2_line[NUM_USERS] __attribute__((aligned(RLC_SYNC_LINE_BYTES))) __attribute__((section(".data")));
static rlc_lock_line_t sent_llist_lock_2_line[NUM_USERS]   __attribute__((aligned(RLC_SYNC_LINE_BYTES))) __attribute__((section(".data")));
#define RLC_TOSEND_LOCK(u) (&tosend_llist_lock_2_line[u].l)
#define RLC_SENT_LOCK(u)   (&sent_llist_lock_2_line[u].l)
#else
static _Atomic mcs_lock_t tosend_llist_lock_2[NUM_USERS] __attribute__((aligned(4))) __attribute__((section(".data")));
static _Atomic mcs_lock_t sent_llist_lock_2[NUM_USERS]   __attribute__((aligned(4))) __attribute__((section(".data")));
#define RLC_TOSEND_LOCK(u) (&tosend_llist_lock_2[u])
#define RLC_SENT_LOCK(u)   (&sent_llist_lock_2[u])
#endif


typedef struct {
   char data[CACHE_LINE_SIZE];
} RcvPktHeader;

typedef struct {
   char content[CACHE_LINE_SIZE / 2];
} DlschInd;

typedef struct {
   DlschInd dlschInd;
   char reserve[2 * CACHE_LINE_SIZE - sizeof(DlschInd) - 4 * sizeof(uint32_t)];
   uint32_t sduNum;
   uint32_t sudBytes;
   uint32_t totalPdlLen;
   uint32_t rlcDpbPduCnt;
} TestDataStru;

typedef struct {
   char stateRpt[2048];
} UeStateRpt;

/* rlc_context_t maintains the state of the RLC kernel, including:

   - rlcId: Unique identifier for the RLC entity.
   - cellId: Identifier for the cell to which this RLC entity belongs.
   - pollPdu: Number of PDUs for which polling is enabled.
   - pollByte: Number of bytes for which polling is enabled.
   - pduWithoutPoll: Total number of PDUs sent without polling.
   - byteWithoutPoll: Total bytes of PDUs sent without polling.
   - vtNextAck: Sequence number (SN) of the first unacknowledged PDU.
   - vtNext: Next available sequence number for a new PDU.
   - list: Linked list of SDUs pending transmission (to_send list).
   - sent_list: Linked list of SDUs that have been sent and are awaiting acknowledgment.

   State transitions:
   - When a producer adds a new node to the to_send list:
       list.sduNum++
       list.sduBytes++

   - When a consumer removes a node from the to_send list and transmits it:
       pduWithoutPoll++
       byteWithoutPoll++
       list.sduNum--
       list.sduBytes--
       vtNext++
       sent_list.sduNum++
       sent_list.sduBytes++

   - When an acknowledgment is received from the UE:
       vtNextAck++
       sent_list.sduNum--
       sent_list.sduBytes--
*/
typedef struct {
   unsigned int rlcId __attribute__((aligned(4)));
   unsigned int cellId __attribute__((aligned(4))); /* Indicates the cell to which the RLC entity belongs.*/
   _Atomic unsigned int pollPdu __attribute__((aligned(4)));
   _Atomic unsigned int pollByte __attribute__((aligned(4)));
   _Atomic unsigned int pduWithoutPoll __attribute__((aligned(4)));  /* Indicates the total number of PDUs that are not polled. */
   _Atomic unsigned int byteWithoutPoll __attribute__((aligned(4))); /* Indicates the total bytes of PDUs that are not polled. */
   _Atomic unsigned int pingFlag __attribute__((aligned(4)));
   _Atomic unsigned int recvMaxByte __attribute__((aligned(4)));
   _Atomic unsigned int sduNumCong __attribute__((aligned(4)));
   _Atomic unsigned int sudCongState __attribute__((aligned(4)));
   _Atomic unsigned int pktdelayEnqueFlag __attribute__((aligned(4)));
   unsigned int latestSduPktRxCycle __attribute__((aligned(4)));
   _Atomic unsigned int recvPdcpPduBytes __attribute__((aligned(4)));
   unsigned int lastRcvOrSubmitDataCyc __attribute__((aligned(4)));
   _Atomic unsigned int sduNum; /* Number of sdus to be sent */
   _Atomic unsigned int sduBytes; /* Number of sdus bytes to be sent */
   
   char Reserve0[CACHE_LINE_SIZE-16] __attribute__((aligned(4))); /* Reserved for future use, pieced into a cacheline */
   _Atomic unsigned int rcvPktNum __attribute__((aligned(4)));   
   _Atomic unsigned int rcvPktLength __attribute__((aligned(4)));
   _Atomic unsigned int enQuePktNum __attribute__((aligned(4)));
   _Atomic unsigned int enQuePktLength __attribute__((aligned(4)));   
   // void *sduLinkHdr; /* First SDU to be sent */
   // void *sduLinkTail; /* Last SDU to be sent */
   LinkedList list __attribute__((aligned(4)));
   char Reserve1[CACHE_LINE_SIZE-6-sizeof(LinkedList)] __attribute__((aligned(4))); /* Reserved for future use, pieced into a cacheline */

   _Atomic unsigned int vtNextAck __attribute__((aligned(4))); /* First SN to be confirmed */
   _Atomic unsigned int vtNext __attribute__((aligned(4))); /* Next Available RLCSN */
   _Atomic unsigned int tbsize;
   unsigned int pdcpcount;
   unsigned int sendPduNum; /* Number of pdus to be confirmed */
   unsigned int sendPduBytes; /* Number of pdus to be confirmed */
   unsigned int pktdelay;
   _Atomic unsigned int rlcthrp;
   _Atomic unsigned int dlPduNum;
   char Reserve3[CACHE_LINE_SIZE-36] __attribute__((aligned(4))); 
   unsigned int rlcOm[16];
   unsigned int dlDelayInfo[16];

   // void *waitAckLinkHdr;  /* First SDU to be confirmed */
   // void *waitAckLinkTail; /* Last SDU to be confirmed */
   LinkedList sent_list __attribute__((aligned(4)));
   unsigned int acksn;
   unsigned int nackcount;
   unsigned int parseindex;
   unsigned int rsv3;
   char Reserve2[CACHE_LINE_SIZE-16-sizeof(LinkedList)] __attribute__((aligned(4))); /* Reserved for future use, pieced into a cacheline */

   mm_context_t *mm_ctx __attribute__((aligned(4)));
} rlc_context_t;

/* One RLC entity per UE. 64-byte alignment gives every entity its own cache
   lines (no inter-entity false sharing); at NUM_USERS == 1 the layout is
   identical to the single-entity kernel. */
rlc_context_t rlc_ctx[NUM_USERS] __attribute__((aligned(CACHE_LINE_SIZE))) __attribute__((section(".data")));

/* rlc_init() initializes the RLC context for the given RLC ID and cell ID.
   It sets the initial values for pollPdu, pollByte, pduWithoutPoll, byteWithoutPoll,
   vtNextAck, vtNext, and initializes the linked lists.
   The mm_context_t pointer is also set to the provided memory management context.
*/
void rlc_init(const unsigned int rlcId, const unsigned int cellId, mm_context_t *mm_ctx);

/*
   rlc_start() initializes shared RLC resources and starts the RLC kernel
   for the current core. The core ID, obtained in main(), is passed here.
*/
void rlc_start(const unsigned int core_id);

/*
   cluster_entry() is the per-core entry function for the RLC kernel.
   Depending on the core ID (passed as a parameter), it calls consumer() if core_id is 0,
   or producer() otherwise.
*/
void cluster_entry(const unsigned int core_id);

/*
   pdcp_pkd_ptr is a pointer to the new PDCP packet data structure.
*/
RLC_LINE_VAR(spinlock_t, pdcp_pkd_ptr);
RLC_LINE_VAR(mcs_lock_t, pdcp_pkd_ptr_lock);

RLC_LINE_VAR(_Atomic(uint32_t), producer_done);
/* Per-group packet streams (RLC_GROUP_STREAMS=1).

   The default producer path takes one global descriptor lock and one global node-pool lock per
   packet. On the 4x4 mesh that caps the whole cluster at ~4 M pkt/s with 16 producers and ~0.9 M
   with 64 (the handoff crosses the mesh), whatever the entity count.

   With streams, every group that hosts producers owns one stream: stream s takes descriptors
   s, s+n, s+2n, ... (n = number of streams) with a single atomic fetch-add -- no lock -- and
   allocates nodes from its own slice of the pool under its own lock. A node goes back to the slice
   it came from (found from its address), so the STATUS core can free any node. Every stream sits
   on its own cache line. Needs the data header's producer list. */
#if RLC_GROUP_STREAMS
#ifndef RLC_TILES_PER_GROUP
#define RLC_TILES_PER_GROUP 4
#endif
typedef struct {
    _Atomic uint32_t next;       /* descriptors taken from this stream so far */
    spinlock_t pool_lock;
    uint32_t pool_used;          /* pages handed out from this stream's slice */
    MM_FreePage *free_list;
} __attribute__((aligned(RLC_SYNC_LINE_BYTES))) rlc_stream_t;
static rlc_stream_t rlc_stream[RLC_MAX_STREAMS] __attribute__((section(".data")));
RLC_LINE_VAR(uint32_t, rlc_nstreams);        /* set once by core 0 before the start barrier */
RLC_LINE_VAR(uint32_t, rlc_stream_pages);    /* pool pages per stream */
#if RLC_PAD_SYNC
#define rlc_nstreams     (rlc_nstreams_line.v)
#define rlc_stream_pages (rlc_stream_pages_line.v)
#endif
void rlc_streams_init(void);
#endif

#if RLC_ARRIVAL_PPS
RLC_LINE_VAR(uint32_t, rlc_arrival_t0);
#if RLC_PAD_SYNC
#define rlc_arrival_t0 (rlc_arrival_t0_line.v)
#endif
#endif
#if RLC_PAD_SYNC
#define pdcp_pkd_ptr      (pdcp_pkd_ptr_line.v)
#define pdcp_pkd_ptr_lock (pdcp_pkd_ptr_lock_line.v)
#define producer_done     (producer_done_line.v)
#endif
/* Number of producer cores that have finished; producer_done is only set
   once this reaches NUM_PRODUCER_CORES, so multiple producers don't cause
   the consumer(s) to exit early when just the first one finishes. */
/* producers_finished is not needed: `producer_done` below is itself the
   count of producers that have finished (see pkt_production_and_recycle). */

spinlock_t rlc_ctx_lock __attribute__((section(".data")));

#endif
