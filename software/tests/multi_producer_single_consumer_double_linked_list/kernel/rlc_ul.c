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

/* RLC AM uplink. See rlc_ul.h for the phase structure and why the scan is
   the serial fraction. Written so it compiles standalone on the host, which
   is what test/test_rlc_ul.c exercises. */

#ifndef RLC_UL_C
#define RLC_UL_C

#include "rlc_ul.h"

/* Payload reads land here so they cannot be optimised away. Written once per
   reassembled range rather than per byte, so the sharing is negligible and the
   benign race between cores costs nothing -- it exists only to make the loads
   observable to the compiler. */
volatile uint32_t rlc_ul_payload_sink;

#ifndef RLC_UL_SLOT
#define RLC_UL_SLOT(sn) ((sn) & (RLC_UL_WINDOW - 1u))
#endif

void rlc_ul_entity_init(rlc_ul_entity_t *e) {
  e->rx_next = 0u;
  e->rx_next_highest = 0u;
  for (uint32_t i = 0u; i < RLC_UL_WINDOW; i++) {
    e->recv[i] = 0u;
    e->total[i] = 0u;
    e->seen[i] = 0u;
    e->complete[i] = 0u;
  }
  e->delivered = 0u;
  e->delivered_bytes = 0u;
  e->reassembled = 0u;
  e->dup = 0u;
  e->out_of_window = 0u;
  e->status_due = 0u;
}

/* ------------------------------------------------------------------------ */
/* Scan -- the serial phase                                                 */
/* ------------------------------------------------------------------------ */

uint32_t rlc_ul_scan(rlc_ul_scan_t *s, const uint8_t *tb, uint32_t tb_len) {
  uint32_t off = 0u;
  s->n = 0u;
  s->bytes = 0u;
  s->truncated = 0u;
  s->overflow = 0u;
  s->polls = 0u;
  s->max_sn = 0u;
  s->have_sn = 0u;

  while (off + RLC_UL_MAC_HDR <= tb_len) {
    /* MAC subheader: total length of the RLC PDU that follows. */
    const uint32_t plen =
        ((uint32_t)tb[off] << 8) | (uint32_t)tb[off + 1u];
    off += RLC_UL_MAC_HDR;

    if (plen == 0u) break; /* padding / end of the block */
    if (off + plen > tb_len) { s->truncated = 1u; break; }
    if (plen < RLC_AMD_HDR_MIN) { s->truncated = 1u; break; }

    /* The header must be parsed to know its own length: SO is present only
       for LAST/MIDDLE, and SI lives inside the first byte. This is what
       forces the walk to be sequential. */
    rlc_amd_hdr_t h;
    rlc_amd_hdr_read(tb + off, &h);
    if (h.hdr_len > plen) { s->truncated = 1u; break; }

    if (s->n >= RLC_UL_MAX_PDUS) { s->overflow = 1u; break; }

    rlc_ul_pdu_t *p = &s->pdu[s->n];
    p->payload = tb + off + h.hdr_len;
    p->sn = h.sn;
    p->so = h.so;
    p->seg_len = plen - h.hdr_len;
    p->si = (uint8_t)h.si;
    p->poll = (uint8_t)h.poll;
    p->hdr_len = (uint8_t)h.hdr_len;
    p->_pad = 0u;

    s->bytes += p->seg_len;
    s->polls += p->poll;
    /* Highest SN in this TB, kept here because the scan already walks every
       PDU in order -- the parallel phase must not maintain it (see
       rlc_ul_note_highest). */
    if (!s->have_sn || ((p->sn - s->max_sn) & RLC_SN_MASK) < RLC_UL_WINDOW) {
      s->max_sn = p->sn;
      s->have_sn = 1u;
    }
    s->n++;
    off += plen;
  }
  return s->n;
}

/* ------------------------------------------------------------------------ */
/* Reassemble -- the parallel phase                                         */
/* ------------------------------------------------------------------------ */

/* Fold [lo,hi) into the entity.
 
   Concurrency: two cores running different slices can legitimately hold
   segments of the SAME SDU -- a middle and a last segment can both appear in
   one transport block -- so `recv` is accumulated atomically. `total` is a
   plain store because exactly one PDU per SDU carries SI FULL or LAST and so
   there is exactly one writer, and it writes the same value either way.
 
   Completion is deliberately NOT decided here. Deciding "recv == total" in
   this phase races: one core can add the final bytes while another is still
   storing `total`, and neither observation sees the SDU as complete. It is
   computed in rlc_ul_deliver(), which is serial and runs after a barrier, so
   the check sees a settled state. That keeps this phase free of any
   read-modify-write on shared control state. */
void rlc_ul_reassemble_range(rlc_ul_entity_t *e, const rlc_ul_scan_t *s,
                             uint32_t lo, uint32_t hi) {
  if (hi > s->n) hi = s->n;
  for (uint32_t i = lo; i < hi; i++) {
    const rlc_ul_pdu_t *p = &s->pdu[i];

    /* Reception window: [rx_next, rx_next + RLC_UL_WINDOW). */
    const uint32_t ahead = (p->sn - e->rx_next) & RLC_SN_MASK;
    if (ahead >= RLC_UL_WINDOW) {
      __atomic_fetch_add(&e->out_of_window, 1u, __ATOMIC_RELAXED);
      continue;
    }

    const uint32_t slot = RLC_UL_SLOT(p->sn);
    if (e->complete[slot]) {
      __atomic_fetch_add(&e->dup, 1u, __ATOMIC_RELAXED);
      continue;
    }

    e->seen[slot] = 1u;

    /* A FULL or LAST segment is the one that reveals the SDU's total length:
       its offset plus its own payload is the whole SDU. */
    if (p->si == RLC_SI_FULL || p->si == RLC_SI_LAST) {
      e->total[slot] = p->so + p->seg_len;
    }

#if RLC_UL_EXEC == RLC_UL_EXEC_COPY
    /* Move the bytes so the memory system sees a receiver's traffic. There is
       no per-SDU landing buffer here: the accounting is what reassembly needs,
       and a real receiver would DMA payload elsewhere. Reading it is enough to
       generate the loads; the sum defeats dead-code elimination. */
    {
      uint32_t acc = 0u;
      for (uint32_t b = 0u; b < p->seg_len; b++) acc += p->payload[b];
      rlc_ul_payload_sink += acc;
    }
#endif

    __atomic_fetch_add(&e->recv[slot], p->seg_len, __ATOMIC_RELAXED);
    __atomic_fetch_add(&e->reassembled, 1u, __ATOMIC_RELAXED);

    if (p->poll) e->status_due = 1u;
  }
}

/* ------------------------------------------------------------------------ */
/* Deliver -- serial, in order                                              */
/* ------------------------------------------------------------------------ */

/* RX_Next_Highest = highest received SN + 1 (§5.2.2.2). Serial by design: the
   parallel phase used to do this as a read-modify-write on shared state, which
   loses updates when two cores read the same old value. No decision depends on
   it, so it moves here rather than becoming an atomic. */
void rlc_ul_note_highest(rlc_ul_entity_t *e, const rlc_ul_scan_t *s) {
  if (!s->have_sn) return;
  const uint32_t nh = (s->max_sn + 1u) & RLC_SN_MASK;
  if (((nh - e->rx_next_highest) & RLC_SN_MASK) < RLC_UL_WINDOW)
    e->rx_next_highest = nh;
}

uint32_t rlc_ul_deliver(rlc_ul_entity_t *e) {
  uint32_t n = 0u;
  while (1) {
    const uint32_t slot = RLC_UL_SLOT(e->rx_next);
    if (!e->seen[slot]) break;
    const uint32_t tot = e->total[slot];
    if (tot == 0u || e->recv[slot] < tot) break; /* still has holes */

    e->complete[slot] = 1u;
    e->delivered++;
    e->delivered_bytes += tot;
    n++;

    /* Retire the slot before rx_next passes it, so the window can wrap. */
    e->seen[slot] = 0u;
    e->complete[slot] = 0u;
    e->recv[slot] = 0u;
    e->total[slot] = 0u;
    e->rx_next = (e->rx_next + 1u) & RLC_SN_MASK;
  }
  return n;
}

/* ------------------------------------------------------------------------ */
/* STATUS                                                                   */
/* ------------------------------------------------------------------------ */

/* ACK_SN is the first SN not yet received in order, i.e. rx_next. Under the
   ACK-only assumption there are no NACK records, so E1 is 0. */
uint32_t rlc_ul_build_status(const rlc_ul_entity_t *e, uint8_t *buf) {
  return rlc_status_hdr_write(buf, e->rx_next, 0u);
}

#endif /* RLC_UL_C */
