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

/* RLC AM uplink -- receive, reassemble, deliver (TS 38.322 §5.2.2, §5.3.2).
 
   Structurally the mirror of the downlink, and for the same reason: the part
   that is unavoidably serial is isolated so the rest can run in parallel.
 
     DL:  gather (serial pointer chase) -> plan (serial arithmetic) -> execute (parallel)
     UL:  scan   (serial header walk)   -> reassemble (parallel)    -> deliver (serial, in-order)
 
   **The UL scan is serial for a structural reason, not an implementation one.**
   An AMD PDU header is 3 or 5 bytes depending on whether SO is present, and SO
   presence depends on SI, which is *inside* the header. So PDU i+1's offset
   cannot be computed without parsing PDU i. That is the UL's Amdahl fraction,
   and it is the quantity worth measuring -- the same role the gather plays on
   the downlink.
 
   MAC framing: each PDU is preceded by a 2-byte big-endian length giving
   header+payload bytes, modelling the MAC subheader that carries L. Without
   it the RLC layer cannot find PDU boundaries at all -- an AMD PDU has no
   length field of its own. Assuming MAC has already demultiplexed the TB to a
   single UE is the simplification agreed with the GVSoC-side design: the
   TB<->UE map is 1:1 and known from the protocol, so spending UL budget
   rediscovering it would model the wrong thing.
 
   Payload policy follows the same argument as the DL scatter-gather back-end:
   RLC does not need to touch payload bytes to reassemble, it needs to account
   for them. RLC_UL_EXEC selects whether we move the bytes (so the memory
   system sees representative traffic) or only account (what a real receiver
   with a DMA would do). */

#ifndef RLC_UL_H
#define RLC_UL_H

#include <stdint.h>
#include "rlc_pdu.h"

/* Uplink on/off. Independent of RLC_TB_MODE: the UL path can be exercised
   without the DL grant machinery. */
#ifndef RLC_UL_MODE
#define RLC_UL_MODE 0
#endif

/* COPY moves each segment into the reassembly buffer, so the memory system
   sees the traffic a real receiver's DMA would generate. COUNT only accounts
   for the bytes -- headers are still parsed, payload is never touched, which
   is what a receiver that hands payload to a DMA actually does. */
#define RLC_UL_EXEC_COPY  0
#define RLC_UL_EXEC_COUNT 1
#ifndef RLC_UL_EXEC
#define RLC_UL_EXEC RLC_UL_EXEC_COPY
#endif

/* Upper bound on PDUs scanned from one transport block. */
#ifndef RLC_UL_MAX_PDUS
#define RLC_UL_MAX_PDUS 128
#endif

/* Reassembly window, in SDUs. Must be a power of two -- SN maps to a slot by
   masking, so a non-power-of-two would need a modulo in the hot path. */
#ifndef RLC_UL_WINDOW
#define RLC_UL_WINDOW 64
#endif
#if (RLC_UL_WINDOW & (RLC_UL_WINDOW - 1)) != 0
#error "RLC_UL_WINDOW must be a power of two"
#endif

/* MAC subheader: 2-byte big-endian length of the RLC PDU that follows. */
#define RLC_UL_MAC_HDR 2u

/* One scanned PDU. Struct-of-arrays is not used here (unlike the DL plan)
   because the reassemble phase reads whole records rather than sweeping one
   field, and there is no vectorised arithmetic over them. */
typedef struct {
  const uint8_t *payload; /* into the transport block, not copied */
  uint32_t sn;
  uint32_t so;      /* segment offset within the SDU */
  uint32_t seg_len; /* payload bytes carried                */
  uint8_t si;       /* RLC_SI_*                             */
  uint8_t poll;     /* P bit -- a STATUS report is due       */
  uint8_t hdr_len;  /* 3 or 5                                */
  uint8_t _pad;
} rlc_ul_pdu_t;

typedef struct {
  rlc_ul_pdu_t pdu[RLC_UL_MAX_PDUS];
  uint32_t n;         /* PDUs scanned                              */
  uint32_t bytes;     /* payload bytes across them                 */
  uint32_t truncated; /* TB ended mid-PDU -- malformed             */
  uint32_t overflow;  /* more PDUs in the TB than RLC_UL_MAX_PDUS  */
  uint32_t polls;     /* PDUs with P set                           */
  uint32_t max_sn;    /* highest SN in this TB, for RX_Next_Highest */
  uint32_t have_sn;   /* 0 when the TB carried no PDU at all        */
} rlc_ul_scan_t;

/* Cache line, for separating state written in the parallel phase from state
   written in the serial phases. Matches CACHE_LINE_SIZE on the target; the
   host build only needs it to be a plausible line so the layout is the same
   shape being tested. */
#ifndef RLC_UL_LINE
#define RLC_UL_LINE 64
#endif

/* Per-entity receive state (TS 38.322 §5.2.2 state variables).
 
   **Every field written during the parallel reassemble phase is word-sized and
   word-aligned.** An earlier version used `uint8_t seen[64]` / `complete[64]`,
   which put the whole window in ONE cache line and had three consumers issuing
   concurrent *byte* stores into it. Sub-word stores from different cores into
   the same line are exactly the case a partial-strobe path can drop, so a lost
   `seen[slot]` silently costs an SDU -- and it costs more of them the more
   cores are running, which is indistinguishable from a coherence bug unless
   you know to look here. Word stores to distinct words have no such exposure.
 
   The three regions are line-separated because they have different writers:
   serial-phase state is written only by the delivering core, the parallel
   counters are hit by every core with an atomic RMW every segment, and mixing
   them means each RMW invalidates the line holding the serial state. */
typedef struct {
  /* --- serial phase only: written by the delivering core --- */
  uint32_t rx_next;         /* SN of the oldest SDU still awaited     */
  uint32_t rx_next_highest; /* highest SN received + 1                */
  uint32_t delivered;       /* SDUs delivered in order                */
  uint32_t delivered_bytes;
  uint8_t  _pad0[RLC_UL_LINE - 4u * sizeof(uint32_t)];

  /* --- parallel phase: accumulated by every core --- */
  uint32_t reassembled;  /* segments folded in                 */
  uint32_t dup;          /* segment for an already-complete SN */
  uint32_t out_of_window;
  uint32_t status_due;   /* poll seen since the last STATUS    */
  uint8_t  _pad1[RLC_UL_LINE - 4u * sizeof(uint32_t)];

  /* --- reassembly window, indexed by SN & (RLC_UL_WINDOW-1) --- */
  uint32_t recv[RLC_UL_WINDOW];  /* payload bytes accumulated for that SN */
  uint32_t total[RLC_UL_WINDOW]; /* full SDU length, known once the last
                                    segment arrives; 0 until then         */
  uint32_t seen[RLC_UL_WINDOW];  /* slot in use for the current window    */
  uint32_t complete[RLC_UL_WINDOW];
} rlc_ul_entity_t;

/* Walk a transport block and describe every PDU in it. Touches only the MAC
   length fields and the RLC headers -- never payload. Returns the PDU count
   (also left in s->n). */
uint32_t rlc_ul_scan(rlc_ul_scan_t *s, const uint8_t *tb, uint32_t tb_len);

/* Fold scanned PDUs [lo,hi) into the entity's reassembly state. Slices are
   disjoint and different cores may run different slices concurrently, so long
   as no two slices carry the same SN -- see rlc_ul_reassemble_range()'s
   comment on why the scan guarantees that in practice and what to do when it
   does not. */
void rlc_ul_reassemble_range(rlc_ul_entity_t *e, const rlc_ul_scan_t *s,
                             uint32_t lo, uint32_t hi);

/* Fold a scanned TB's highest SN into RX_Next_Highest (§5.2.2.2). Serial: the
   parallel phase used to do this with a read-modify-write on shared state,
   which is a genuine lost-update race -- two cores can both read the old value
   and both store, dropping the higher. It is bookkeeping no decision depends
   on, so the fix is to take it out of the parallel phase rather than to make
   it atomic. */
void rlc_ul_note_highest(rlc_ul_entity_t *e, const rlc_ul_scan_t *s);

/* Deliver every in-order complete SDU starting at rx_next, advancing it.
   Returns how many were delivered. */
uint32_t rlc_ul_deliver(rlc_ul_entity_t *e);

/* Build a STATUS PDU acknowledging everything below rx_next. Returns bytes
   written. */
uint32_t rlc_ul_build_status(const rlc_ul_entity_t *e, uint8_t *buf);

void rlc_ul_entity_init(rlc_ul_entity_t *e);

#endif /* RLC_UL_H */
