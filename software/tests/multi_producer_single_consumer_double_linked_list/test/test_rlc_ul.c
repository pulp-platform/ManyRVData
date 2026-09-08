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

/* Host-side unit test for the RLC AM uplink.
 
   Builds transport blocks the way a conforming transmitter would -- SDUs
   segmented across grants, headers serialised with the real rlc_pdu.h writer
   -- then drives scan / reassemble / deliver and checks that every SDU comes
   out exactly once, in order, at its original length.
 
   The part worth having: each TB is reassembled TWICE, once as a single range
   and once split into N disjoint slices the way N cores would. Both must
   produce identical entity state. That is the claim rlc_ul_reassemble_range()
   makes about being safe to parallelise, tested rather than asserted.
 
   Build and run:
     gcc -O2 -I../kernel test_rlc_ul.c -o /tmp/t && /tmp/t
*/

#include <stdio.h>
#include <string.h>

#include "../kernel/rlc_ul.c"

#define MAX_SDUS 2048
#define TB_CAP   8192

static uint32_t rng_state = 2024u;
static uint32_t rnd(uint32_t lo, uint32_t hi) {
  rng_state = rng_state * 1103515245u + 12345u;
  return lo + (rng_state >> 9) % (hi - lo + 1u);
}

static int failures = 0;
static long checks = 0;
#define CHECK(cond, fmt, ...)                                                 \
  do {                                                                        \
    checks++;                                                                 \
    if (!(cond)) {                                                            \
      failures++;                                                             \
      if (failures <= 20)                                                     \
        printf("  FAIL %s:%d: " fmt "\n", __func__, __LINE__, ##__VA_ARGS__); \
    }                                                                         \
  } while (0)

/* --- transmitter: segment SDUs into transport blocks ------------------- */

typedef struct {
  uint8_t  tb[TB_CAP];
  uint32_t len;
  uint32_t npdu;
} tb_t;

/* Emit one PDU into the TB: MAC length + RLC header + payload. */
static int tb_put(tb_t *t, uint32_t sn, uint32_t si, uint32_t poll, uint32_t so,
                  const uint8_t *payload, uint32_t seg_len) {
  const uint32_t hdr = rlc_amd_hdr_len(si);
  const uint32_t need = RLC_UL_MAC_HDR + hdr + seg_len;
  if (t->len + need > TB_CAP) return 0;
  uint8_t *p = t->tb + t->len;
  p[0] = (uint8_t)(((hdr + seg_len) >> 8) & 0xFF);
  p[1] = (uint8_t)((hdr + seg_len) & 0xFF);
  rlc_amd_hdr_write(p + RLC_UL_MAC_HDR, sn, si, poll, so);
  memcpy(p + RLC_UL_MAC_HDR + hdr, payload, seg_len);
  t->len += need;
  t->npdu++;
  return 1;
}

/* --- one stream ------------------------------------------------------- */

static void run_stream(const char *name, uint32_t n_sdus, uint32_t lo,
                       uint32_t hi, uint32_t tb_budget, uint32_t poll_every,
                       uint32_t slices) {
  static uint8_t sdu[MAX_SDUS][2048];
  static uint32_t sdu_len[MAX_SDUS];
  static rlc_ul_scan_t scan;
  static rlc_ul_entity_t ent, ent_ref;

  for (uint32_t i = 0; i < n_sdus; i++) {
    sdu_len[i] = rnd(lo, hi);
    for (uint32_t b = 0; b < sdu_len[i]; b++) sdu[i][b] = (uint8_t)(i * 7u + b);
  }

  rlc_ul_entity_init(&ent);
  uint32_t sn = 0, cur = 0, so = 0, tbs = 0, total_pdus = 0;
  uint32_t delivered_total = 0;

  while (cur < n_sdus) {
    tb_t t;
    t.len = 0; t.npdu = 0;

    /* Fill one TB, segmenting the SDU that does not fit whole. */
    while (cur < n_sdus) {
      const uint32_t remaining = sdu_len[cur] - so;
      const uint32_t si_full = (so == 0) ? RLC_SI_FULL : RLC_SI_LAST;
      const uint32_t hdr = rlc_amd_hdr_len(si_full);
      if (t.len + RLC_UL_MAC_HDR + hdr + 1u > tb_budget) break;
      const uint32_t room = tb_budget - t.len - RLC_UL_MAC_HDR - hdr;
      const uint32_t poll = (poll_every && ((sn + 1u) % poll_every == 0)) ? 1u : 0u;

      if (remaining <= room) {
        if (!tb_put(&t, sn, si_full, poll, so, sdu[cur] + so, remaining)) break;
        sn = (sn + 1u) & RLC_SN_MASK; cur++; so = 0;
      } else {
        const uint32_t si = (so == 0) ? RLC_SI_FIRST : RLC_SI_MIDDLE;
        if (!tb_put(&t, sn, si, poll, so, sdu[cur] + so, room)) break;
        /* SN is per SDU: a segment does NOT consume one. The next segment of
           this same SDU reuses it, and SO tells the receiver where it goes. */
        so += room;
        break; /* TB is full by construction */
      }
    }
    if (t.npdu == 0) break;
    tbs++;

    /* --- scan --- */
    const uint32_t n = rlc_ul_scan(&scan, t.tb, t.len);
    CHECK(n == t.npdu, "TB %u: scanned %u PDUs, emitted %u", tbs, n, t.npdu);
    CHECK(scan.truncated == 0, "TB %u: reported truncated", tbs);
    CHECK(scan.overflow == 0, "TB %u: reported overflow", tbs);
    total_pdus += n;

    for (uint32_t i = 0; i < n; i++) {
      CHECK(scan.pdu[i].hdr_len == rlc_amd_hdr_len(scan.pdu[i].si),
            "pdu %u: hdr_len %u vs si %u", i, scan.pdu[i].hdr_len,
            scan.pdu[i].si);
      CHECK(scan.pdu[i].seg_len >= 1u, "pdu %u: empty payload", i);
    }

    /* --- reassemble twice: one range, then sliced like N cores --- */
    memcpy(&ent_ref, &ent, sizeof(ent));
    rlc_ul_reassemble_range(&ent_ref, &scan, 0, n);

    const uint32_t step = (n + slices - 1u) / (slices ? slices : 1u);
    for (uint32_t s = 0; s < n; s += (step ? step : 1u))
      rlc_ul_reassemble_range(&ent, &scan, s, s + (step ? step : 1u));

    CHECK(memcmp(&ent, &ent_ref, sizeof(ent)) == 0,
          "TB %u: %u-way sliced reassembly differs from single-range", tbs,
          slices);

    /* --- deliver --- */
    delivered_total += rlc_ul_deliver(&ent);
  }

  CHECK(delivered_total == n_sdus, "delivered %u of %u SDUs", delivered_total,
        n_sdus);
  CHECK(ent.delivered == n_sdus, "entity counter %u vs %u", ent.delivered,
        n_sdus);
  CHECK(ent.out_of_window == 0, "%u segments fell outside the window",
        ent.out_of_window);

  uint32_t want_bytes = 0;
  for (uint32_t i = 0; i < n_sdus; i++) want_bytes += sdu_len[i];
  CHECK(ent.delivered_bytes == want_bytes, "delivered %u bytes, want %u",
        ent.delivered_bytes, want_bytes);

  /* STATUS must acknowledge exactly what was delivered in order. */
  uint8_t st[8];
  const uint32_t stl = rlc_ul_build_status(&ent, st);
  uint32_t ack = 0, e1 = 0;
  rlc_status_hdr_read(st, &ack, &e1);
  CHECK(stl == RLC_STATUS_HDR_LEN, "status len %u", stl);
  CHECK(ack == ent.rx_next, "STATUS ACK_SN %u != rx_next %u", ack, ent.rx_next);
  CHECK(e1 == 0, "E1 set with no NACKs");

  printf("  %-26s %5u SDUs %5u TBs %6u PDUs  %u-way slices\n", name, n_sdus,
         tbs, total_pdus, slices);
}

int main(void) {
  printf("RLC AM uplink tests\n");

  run_stream("tc1-1350B-large-tb",   500, 1350, 1350, 8192, 32, 1);
  run_stream("tc1-sliced-4way",      500, 1350, 1350, 8192, 32, 4);
  run_stream("tc2-800B",             500,  800,  800, 8192, 32, 4);
  run_stream("heavy-segmentation",   400, 1350, 1350, 1024, 32, 4);
  run_stream("tiny-tb-every-sdu-cut",200,  600,  900,  300, 16, 4);
  run_stream("mixed-sizes",          600,    1, 2000, 4096, 16, 8);
  run_stream("poll-every-pdu",       200,  500,  500, 4096,  1, 4);
  run_stream("no-poll",              200,  500,  500, 4096,  0, 4);
  rng_state = 77u;
  run_stream("sliced-16way",         400,  900,  900, 8192, 32, 16);

  printf("\n%ld checks, %d failures -> %s\n", checks, failures,
         failures ? "FAIL" : "PASS");
  return failures ? 1 : 0;
}
