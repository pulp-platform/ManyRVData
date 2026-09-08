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

/* RLC AM PDU formats -- 3GPP TS 38.322 §6.2.2.4 (AMD PDU) and §6.2.2.5
   (STATUS PDU).
 
   The legacy kernel wrote a bare 32-bit sequence number into a 10-byte
   placeholder header.  That is enough to make the payload copy measurable but
   it models none of the constraints that make RLC hard to parallelise: the
   header carries the poll bit (a cumulative, order-dependent decision) and the
   segmentation info + segment offset (which depend on the running grant fill).
   This header emits the real thing.
 
   All fields are packed big-endian / network bit order, so serialisation is
   byte-by-byte rather than a word store. */

#ifndef RLC_PDU_H
#define RLC_PDU_H

#include <stdint.h>

/* SN length. TS 38.322 allows 12 or 18 bits for AM; the kernel has always
   assumed 18 (matching the Huawei DP test cases). */
#ifndef RLC_SN_BITS
#define RLC_SN_BITS 18
#endif

#if (RLC_SN_BITS != 12) && (RLC_SN_BITS != 18)
#error "RLC AM supports only a 12- or 18-bit SN"
#endif

#define RLC_SN_MASK ((1u << RLC_SN_BITS) - 1u)

/* Sequence numbers live in a modulo-2^RLC_SN_BITS space, so ordering is
   comparison against half the window rather than plain <. */
static inline int rlc_sn_lt(uint32_t a, uint32_t b) {
  return (int)(((b - a) & RLC_SN_MASK) != 0u) &&
         (((b - a) & RLC_SN_MASK) < ((RLC_SN_MASK + 1u) >> 1));
}

/* D/C field (§6.2.3.1) */
#define RLC_DC_CONTROL 0u
#define RLC_DC_DATA    1u

/* SI field (§6.2.3.4) */
#define RLC_SI_FULL   0u /* complete SDU, no segmentation      */
#define RLC_SI_FIRST  1u /* first segment of an SDU            */
#define RLC_SI_LAST   2u /* last segment of an SDU             */
#define RLC_SI_MIDDLE 3u /* neither the first nor the last     */

/* SO is present only when the segment does not start at offset 0, i.e. for
   the LAST and MIDDLE segments (§6.2.2.4). */
#define RLC_SI_HAS_SO(si) (((si) == RLC_SI_LAST) || ((si) == RLC_SI_MIDDLE))

#if RLC_SN_BITS == 18
/* Oct1: D/C | P | SI(2) | R | R | SN[17:16]
   Oct2: SN[15:8]
   Oct3: SN[7:0] */
#define RLC_AMD_HDR_MIN 3u
#else
/* Oct1: D/C | P | SI(2) | SN[11:8]
   Oct2: SN[7:0] */
#define RLC_AMD_HDR_MIN 2u
#endif
#define RLC_AMD_HDR_SO  2u /* SO(16) */
#define RLC_AMD_HDR_MAX (RLC_AMD_HDR_MIN + RLC_AMD_HDR_SO)

/* Header length implied by an SI value. Kept branch-free: the planner
   evaluates this for every PDU in a grant. */
static inline uint32_t rlc_amd_hdr_len(uint32_t si) {
  return RLC_AMD_HDR_MIN + (RLC_SI_HAS_SO(si) ? RLC_AMD_HDR_SO : 0u);
}

/* Serialise one AMD PDU header at p. Returns the number of bytes written. */
static inline uint32_t rlc_amd_hdr_write(uint8_t *p, uint32_t sn, uint32_t si,
                                         uint32_t poll, uint32_t so) {
  sn &= RLC_SN_MASK;
#if RLC_SN_BITS == 18
  p[0] = (uint8_t)((RLC_DC_DATA << 7) | ((poll & 1u) << 6) |
                   ((si & 3u) << 4) | ((sn >> 16) & 0x3u));
  p[1] = (uint8_t)((sn >> 8) & 0xFFu);
  p[2] = (uint8_t)(sn & 0xFFu);
#else
  p[0] = (uint8_t)((RLC_DC_DATA << 7) | ((poll & 1u) << 6) |
                   ((si & 3u) << 4) | ((sn >> 8) & 0xFu));
  p[1] = (uint8_t)(sn & 0xFFu);
#endif
  if (RLC_SI_HAS_SO(si)) {
    p[RLC_AMD_HDR_MIN + 0] = (uint8_t)((so >> 8) & 0xFFu);
    p[RLC_AMD_HDR_MIN + 1] = (uint8_t)(so & 0xFFu);
    return RLC_AMD_HDR_MIN + RLC_AMD_HDR_SO;
  }
  return RLC_AMD_HDR_MIN;
}

/* Parse an AMD PDU header. Mirrors rlc_amd_hdr_write; used by the self-check
   to decode an assembled transport block back into a PDU sequence. */
typedef struct {
  uint32_t sn;
  uint32_t si;
  uint32_t poll;
  uint32_t so;
  uint32_t hdr_len;
} rlc_amd_hdr_t;

static inline void rlc_amd_hdr_read(const uint8_t *p, rlc_amd_hdr_t *h) {
  h->poll = (p[0] >> 6) & 1u;
  h->si   = (p[0] >> 4) & 3u;
#if RLC_SN_BITS == 18
  h->sn = (((uint32_t)p[0] & 0x3u) << 16) | ((uint32_t)p[1] << 8) | p[2];
#else
  h->sn = (((uint32_t)p[0] & 0xFu) << 8) | p[1];
#endif
  if (RLC_SI_HAS_SO(h->si)) {
    h->so      = ((uint32_t)p[RLC_AMD_HDR_MIN] << 8) | p[RLC_AMD_HDR_MIN + 1];
    h->hdr_len = RLC_AMD_HDR_MIN + RLC_AMD_HDR_SO;
  } else {
    h->so      = 0u;
    h->hdr_len = RLC_AMD_HDR_MIN;
  }
}

/* ---- STATUS PDU (§6.2.2.5) --------------------------------------------
   Groundwork for replacing the hardcoded "ACK two PDUs" model with a real
   status report. Under the ACK-only assumption the NACK list stays empty, but
   the build/parse cost is then modelled rather than assumed away. */

#define RLC_CPT_STATUS 0u

#if RLC_SN_BITS == 18
#define RLC_STATUS_HDR_LEN 3u /* D/C|CPT(3)|ACK_SN[17:14] | [13:6] | [5:0]|E1|R */
#else
#define RLC_STATUS_HDR_LEN 2u /* D/C|CPT(3)|ACK_SN[11:8] | [7:0] ... + E1|R    */
#endif

/* Serialise a STATUS PDU header with the given ACK_SN. e1 = 1 when at least
   one NACK_SN record follows. Returns bytes written. */
static inline uint32_t rlc_status_hdr_write(uint8_t *p, uint32_t ack_sn,
                                            uint32_t e1) {
  ack_sn &= RLC_SN_MASK;
#if RLC_SN_BITS == 18
  p[0] = (uint8_t)((RLC_DC_CONTROL << 7) | ((RLC_CPT_STATUS & 7u) << 4) |
                   ((ack_sn >> 14) & 0xFu));
  p[1] = (uint8_t)((ack_sn >> 6) & 0xFFu);
  p[2] = (uint8_t)(((ack_sn & 0x3Fu) << 2) | ((e1 & 1u) << 1));
  return 3u;
#else
  p[0] = (uint8_t)((RLC_DC_CONTROL << 7) | ((RLC_CPT_STATUS & 7u) << 4) |
                   ((ack_sn >> 8) & 0xFu));
  p[1] = (uint8_t)(ack_sn & 0xFFu);
  p[2] = (uint8_t)((e1 & 1u) << 7);
  return 3u;
#endif
}

static inline uint32_t rlc_status_hdr_read(const uint8_t *p, uint32_t *ack_sn,
                                           uint32_t *e1) {
#if RLC_SN_BITS == 18
  *ack_sn = (((uint32_t)p[0] & 0xFu) << 14) | ((uint32_t)p[1] << 6) |
            ((uint32_t)p[2] >> 2);
  *e1 = (p[2] >> 1) & 1u;
#else
  *ack_sn = (((uint32_t)p[0] & 0xFu) << 8) | p[1];
  *e1     = (p[2] >> 7) & 1u;
#endif
  return 3u;
}

#endif /* RLC_PDU_H */
