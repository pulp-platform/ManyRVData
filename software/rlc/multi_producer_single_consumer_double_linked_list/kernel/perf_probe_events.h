/*
 * Copyright (C) 2026 ETH Zurich and University of Bologna
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * Software performance-probe port: the contract between the kernel, the GVSoC collector and
 * (later) the RTL testbench. Plain C so the same file compiles into the RISC-V kernel.
 *
 *   address = PERF_PROBE_BASE + (hart << PERF_PROBE_HART_SHIFT) + (event << 2)
 *   data    = 32-bit value; for per-entity events value = (entity << 16) | v16
 *
 * A store is self-describing (hart and event come from the address), so it needs no hart-id
 * sideband and the layout survives into hardware unchanged. The window sits after the UART in the
 * SoC peripheral space: peripheral 0xC000_0000, UART 0xC001_0000, probes 0xC002_0000..0xC005_FFFF.
 *
 * Keep this file identical in core/models/probe/ and in the kernel tree
 * (software/tests/multi_producer_single_consumer_double_linked_list/kernel/).
 */

#ifndef PERF_PROBE_EVENTS_H
#define PERF_PROBE_EVENTS_H

#define PERF_PROBE_BASE         0xC0020000u
#define PERF_PROBE_WINDOW_SIZE  0x40000u        /* 1024 harts x 64 events x 4 B */
#define PERF_PROBE_HART_SHIFT   8
#define PERF_PROBE_NB_EVENTS    64
#define PERF_PROBE_ENTITY_SHIFT 16
#define PERF_PROBE_VALUE_MASK   0xFFFFu

enum perf_probe_evt {
    PROBE_EVT_KERNEL_START = 0,  /* --                         core 0, kernel work phase begins   */
    PROBE_EVT_KERNEL_END   = 1,  /* --                         core 0, kernel work phase ends     */
    PROBE_EVT_ROLE         = 2,  /* gauge: 0 idle 1 producer 2 consumer 3 status 4 helper        */
    PROBE_EVT_SDU_RX       = 3,  /* entity | bytes             producer enqueued one SDU          */
    PROBE_EVT_PDU_TX       = 4,  /* entity | bytes             one PDU assembled / sent            */
    PROBE_EVT_GRANT        = 5,  /* entity | n_pdus            AM: one grant committed             */
    PROBE_EVT_SEGMENT      = 6,  /* entity | 1                 AM: a PDU carried an SDU segment    */
    PROBE_EVT_POLL         = 7,  /* entity | 1                 P bit set on a PDU                  */
    PROBE_EVT_STATUS_ACK   = 8,  /* entity | sdus_released     STATUS PDU processed                */
    PROBE_EVT_QDEPTH       = 9,  /* gauge: entity | sduNum     to-send list depth                  */
    PROBE_EVT_ACKDEPTH     = 10, /* gauge: entity | sduNum     wait-ack list depth                 */
    PROBE_EVT_TTI_BEGIN    = 11, /* tti index                  consumer 0                          */
    PROBE_EVT_TTI_END      = 12, /* tti index                  consumer 0                          */
    PROBE_EVT_PHASE        = 13, /* gauge: 0 plan 1 execute 2 commit 3 barrier 4 idle             */
    PROBE_EVT_LOCK_SPIN    = 14, /* cycles                     spent spinning on a list lock       */
    PROBE_EVT_MM_LIVE      = 15, /* gauge: live nodes          after mm_alloc / mm_free            */
    PROBE_EVT_UL_TB        = 16, /* entity | pdus              UL: one transport block scanned     */
    PROBE_EVT_UL_DELIVER   = 17, /* entity | sdus              UL: SDUs delivered in order         */
    PROBE_EVT_UL_STATUS    = 18, /* entity | bytes             UL: STATUS PDU built                */
    PROBE_EVT_MARK         = 19, /* free-form                                                     */
    PROBE_EVT_PKT_IN       = 20, /* tag (e.g. node address)   SDU entered the entity; opens latency */
    PROBE_EVT_PKT_OUT      = 21, /* same tag                  SDU fully sent; closes latency        */
    PROBE_EVT_NB_DEFINED   = 22,
};

/* Events whose value packs an entity id in the upper 16 bits. */
#define PERF_PROBE_ENTITY_EVENTS \
    ((1u << PROBE_EVT_SDU_RX) | (1u << PROBE_EVT_PDU_TX) | (1u << PROBE_EVT_GRANT) | \
     (1u << PROBE_EVT_SEGMENT) | (1u << PROBE_EVT_POLL) | (1u << PROBE_EVT_STATUS_ACK) | \
     (1u << PROBE_EVT_QDEPTH) | (1u << PROBE_EVT_ACKDEPTH) | (1u << PROBE_EVT_UL_TB) | \
     (1u << PROBE_EVT_UL_DELIVER) | (1u << PROBE_EVT_UL_STATUS))

/* Events that are levels (the last value in a slice is the state), not increments. */
#define PERF_PROBE_GAUGE_EVENTS \
    ((1u << PROBE_EVT_ROLE) | (1u << PROBE_EVT_QDEPTH) | (1u << PROBE_EVT_ACKDEPTH) | \
     (1u << PROBE_EVT_PHASE) | (1u << PROBE_EVT_MM_LIVE))

#define PERF_PROBE_EVENT_NAMES { \
    "kernel_start", "kernel_end", "role", "sdu_rx", "pdu_tx", "grant", "segment", "poll", \
    "status_ack", "qdepth", "ackdepth", "tti_begin", "tti_end", "phase", "lock_spin", "mm_live", \
    "ul_tb", "ul_deliver", "ul_status", "mark", "pkt_in", "pkt_out" }

#define PERF_PROBE_ROLE_IDLE      0
#define PERF_PROBE_ROLE_PRODUCER  1
#define PERF_PROBE_ROLE_CONSUMER  2
#define PERF_PROBE_ROLE_STATUS    3
#define PERF_PROBE_ROLE_HELPER    4

/* PHASE values. The collector integrates time spent in each (sw_state.csv), so a hart's phase is
   a state: emit on transitions only, never once per loop iteration. */
#define PERF_PROBE_PHASE_PLAN     0   /* AM: grant planning                               */
#define PERF_PROBE_PHASE_EXECUTE  1   /* assembling / copying a PDU                       */
#define PERF_PROBE_PHASE_COMMIT   2   /* AM: grant commit                                 */
#define PERF_PROBE_PHASE_BARRIER  3   /* waiting at a (partial) barrier                   */
#define PERF_PROBE_PHASE_IDLE     4   /* polling, nothing to do                           */
#define PERF_PROBE_PHASE_RECEIVE  5   /* producer: taking a PDCP packet, enqueueing an SDU */
#define PERF_PROBE_PHASE_STATUS   6   /* STATUS PDU processing (ACK release)              */
#define PERF_PROBE_PHASE_DONE     7   /* role finished, waiting for the others            */

#endif /* PERF_PROBE_EVENTS_H */
