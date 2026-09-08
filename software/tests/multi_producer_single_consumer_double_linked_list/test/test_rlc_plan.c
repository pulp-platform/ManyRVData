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

/* Host-side unit test for the RLC AM grant planner.
 
   The scalar planner is the specification that the RVV implementation is
   checked against on target (RLC_PLAN_VERIFY), so it is worth validating on
   its own, away from any simulator. This drives a multi-grant stream over a
   queue of SDUs and checks the structural invariants plus an independent
   model of the poll counters and of SDU reassembly.
 
   Build and run:
     gcc -DRLC_PLAN_VECTOR=0 -O2 -I../kernel test_rlc_plan.c -o /tmp/t && /tmp/t
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../kernel/rlc_plan.c"

#define MAX_SDUS 4096

static uint32_t rng_state = 12345u;
static uint32_t rnd(uint32_t lo, uint32_t hi) { /* inclusive */
  rng_state = rng_state * 1103515245u + 12345u;
  return lo + (rng_state >> 8) % (hi - lo + 1u);
}

static int failures = 0;
static long checks = 0;

#define CHECK(cond, fmt, ...)                                                \
  do {                                                                       \
    checks++;                                                                \
    if (!(cond)) {                                                           \
      failures++;                                                            \
      if (failures <= 20)                                                    \
        printf("  FAIL %s:%d: " fmt "\n", __func__, __LINE__, ##__VA_ARGS__);\
    }                                                                        \
  } while (0)

/* One stream: a queue of SDUs drained by a sequence of grants. */
static void run_stream(const char *name, uint32_t n_sdus, uint32_t sdu_lo,
                       uint32_t sdu_hi, uint32_t grant_lo, uint32_t grant_hi,
                       uint32_t poll_pdu, uint32_t poll_byte) {
  static rlc_plan_t plan;
  static uint32_t sdu_len[MAX_SDUS];
  static uint32_t sent_off[MAX_SDUS]; /* independent reassembly model */

  for (uint32_t i = 0; i < n_sdus; i++) {
    sdu_len[i] = rnd(sdu_lo, sdu_hi);
    sent_off[i] = 0;
  }

  uint32_t head = 0;         /* first SDU still (partly) queued        */
  uint32_t so_first = 0;     /* bytes of SDU[head] already transmitted */
  uint32_t sn_base = rnd(0, RLC_SN_MASK);
  uint32_t pwp = 0, bwp = 0; /* planner-reported counters              */
  uint32_t m_pwp = 0, m_bwp = 0; /* independent poll model             */
  uint32_t grants = 0, pdus = 0;

  while (head < n_sdus && grants < 100000u) {
    const uint32_t grant = rnd(grant_lo, grant_hi);

    /* --- gather, exactly as the kernel will do it from the list --- */
    uint32_t avail = n_sdus - head;
    if (avail > RLC_MAX_PDUS_PER_GRANT) avail = RLC_MAX_PDUS_PER_GRANT;
    plan.n_avail = avail;
    for (uint32_t i = 0; i < avail; i++) plan.sdu_len[i] = sdu_len[head + i];

    rlc_plan_in_t in = {
        .grant_bytes = grant,
        .sn_base = sn_base,
        .so_first = so_first,
        .poll_pdu = poll_pdu,
        .poll_byte = poll_byte,
        .pdu_without_poll = pwp,
        .byte_without_poll = bwp,
        .queue_drained = (avail == n_sdus - head),
    };
    rlc_plan_out_t out;
    /* Runs the scan planner (the one that is vectorised on target) and diffs
       every output field against the reference planner. */
    static rlc_plan_t ref;
    uint32_t nbad = 0;
    const uint32_t n = rlc_plan_compute_checked(&plan, &ref, &in, &out, &nbad);
    CHECK(nbad == 0, "grant %u: scan planner diverges from reference in %u "
          "fields (n=%u grant=%u so_first=%u)", grants, nbad, n, grant,
          so_first);
    grants++;

    CHECK(n <= avail, "n=%u > avail=%u", n, avail);
    CHECK(plan.tb_used <= grant, "tb_used=%u > grant=%u", plan.tb_used, grant);

    if (n == 0) {
      /* Only legal if even a minimal header plus one byte cannot fit. */
      const uint32_t hdr = (so_first == 0) ? RLC_AMD_HDR_MIN : RLC_AMD_HDR_MAX;
      CHECK(grant <= hdr, "empty plan with grant=%u hdr=%u", grant, hdr);
      sn_base = out.sn_next;
      pwp = out.pdu_without_poll;
      bwp = out.byte_without_poll;
      continue;
    }

    /* SN is per SDU: it restarts from this grant's base each time, and a
       trailing segment does not consume one, so the next grant's leading
       segment reuses the same SN. */
    uint32_t sn_expect = sn_base;
    uint32_t off = 0;
    for (uint32_t i = 0; i < n; i++) {
      const uint32_t q = head + i;

      /* structure */
      CHECK(plan.tb_off[i] == off, "grant %u pdu %u: tb_off=%u want %u", grants,
            i, plan.tb_off[i], off);
      CHECK(plan.hdr_len[i] == rlc_amd_hdr_len(plan.si[i]),
            "pdu %u: hdr_len=%u si=%u", i, plan.hdr_len[i], plan.si[i]);
      CHECK(plan.seg_len[i] >= 1u, "pdu %u: empty payload", i);
      CHECK(plan.sn[i] == (sn_expect & RLC_SN_MASK), "pdu %u: sn=%u want %u", i,
            plan.sn[i], sn_expect & RLC_SN_MASK);
      sn_expect = (sn_expect + 1u) & RLC_SN_MASK;

      /* SI / SO / last_seg consistency */
      const int has_so = (plan.so[i] != 0);
      const int si_has_so = RLC_SI_HAS_SO(plan.si[i]);
      CHECK(has_so == si_has_so, "pdu %u: so=%u but si=%u", i, plan.so[i],
            plan.si[i]);
      const int is_last =
          (plan.si[i] == RLC_SI_FULL || plan.si[i] == RLC_SI_LAST);
      CHECK((uint32_t)is_last == plan.last_seg[i], "pdu %u: si=%u last_seg=%u",
            i, plan.si[i], plan.last_seg[i]);
      CHECK(plan.last_seg[i] || i == n - 1u,
            "pdu %u of %u is a non-final segment", i, n);

      /* reassembly: segments of one SDU must be contiguous and complete */
      CHECK(plan.so[i] == sent_off[q], "sdu %u: so=%u want %u", q, plan.so[i],
            sent_off[q]);
      sent_off[q] += plan.seg_len[i];
      CHECK(sent_off[q] <= sdu_len[q], "sdu %u: overrun %u > %u", q,
            sent_off[q], sdu_len[q]);
      if (plan.last_seg[i])
        CHECK(sent_off[q] == sdu_len[q], "sdu %u: short %u != %u", q,
              sent_off[q], sdu_len[q]);

      /* independent poll model (TS 38.322 5.3.3.2) */
      m_pwp += 1u;
      m_bwp += plan.seg_len[i];
      uint32_t want_poll = 0;
      if (poll_pdu && m_pwp >= poll_pdu) want_poll = 1;
      else if (poll_byte && m_bwp >= poll_byte) want_poll = 1;
      if (want_poll) { m_pwp = 0; m_bwp = 0; }
      /* the buffer-empty poll is applied by the planner to the final PDU */
      const int drained_here =
          in.queue_drained && !out.partial && (i == n - 1u);
      if (drained_here && !want_poll) {
        want_poll = 1;
        m_pwp = 0;
        m_bwp = 0;
      }
      CHECK(plan.poll[i] == want_poll, "pdu %u: poll=%u want %u", i,
            plan.poll[i], want_poll);

      off += plan.hdr_len[i] + plan.seg_len[i];
      pdus++;
    }
    CHECK(plan.tb_used == off, "tb_used=%u want %u", plan.tb_used, off);
    CHECK(out.pdu_without_poll == m_pwp, "pwp=%u want %u",
          out.pdu_without_poll, m_pwp);
    CHECK(out.byte_without_poll == m_bwp, "bwp=%u want %u",
          out.byte_without_poll, m_bwp);

    /* advance the queue exactly as the kernel will */
    head += n - out.partial;
    so_first = out.so_next;
    CHECK(out.partial == 0 || so_first == sent_off[head],
          "cursor %u != sent_off %u", so_first, sent_off[head]);
    sn_base = out.sn_next;
    pwp = out.pdu_without_poll;
    bwp = out.byte_without_poll;
  }

  for (uint32_t i = 0; i < n_sdus; i++)
    CHECK(sent_off[i] == sdu_len[i], "sdu %u not fully sent: %u/%u", i,
          sent_off[i], sdu_len[i]);

  printf("  %-28s %6u SDUs %6u grants %7u PDUs\n", name, n_sdus, grants, pdus);
}

int main(void) {
  printf("RLC AM plan reference tests\n");

  /* TC1-like: 1350 B SDUs, generous grants -> mostly unsegmented */
  run_stream("tc1-large-grant", 2000, 1350, 1350, 20000, 40000, 32, 25000);
  /* TC2-like: 800 B SDUs */
  run_stream("tc2-800B", 2000, 800, 800, 8000, 16000, 32, 25000);
  /* grants near the PDU size -> segmentation on almost every grant */
  run_stream("heavy-segmentation", 1500, 1350, 1350, 200, 900, 32, 25000);
  /* pathological: grants barely above the header */
  run_stream("tiny-grants", 300, 100, 400, 4, 12, 8, 64);
  /* variable SDU sizes */
  run_stream("mixed-sizes", 2000, 1, 2000, 100, 5000, 16, 4000);
  /* poll disabled */
  run_stream("no-poll", 1000, 800, 800, 4000, 9000, 0, 0);
  /* poll on every PDU */
  run_stream("poll-every-pdu", 800, 500, 500, 3000, 6000, 1, 0);
  /* byte-threshold poll only */
  run_stream("poll-bytes-only", 1200, 700, 700, 5000, 12000, 0, 3000);
  /* SN wraparound */
  rng_state = 999u;
  run_stream("sn-wrap", 3000, 900, 900, 2000, 4000, 32, 25000);

  printf("\n%ld checks, %d failures -> %s\n", checks, failures,
         failures ? "FAIL" : "PASS");
  return failures ? 1 : 0;
}
