// Copyright 2025 ETH Zurich and University of Bologna.
//
// SPDX-License-Identifier: Apache-2.0
//
// SPDX-License-Identifier: Apache-2.0
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

/* Target-side driver for the RLC AM uplink.
 
   Kept separate from rlc_ul.c so that file stays free of snRuntime and can be
   compiled and exercised on the host (test/test_rlc_ul.c does exactly that).
   Everything here is harness: it manufactures the uplink transport blocks a
   MAC would hand up, then drives the real scan / reassemble / deliver path.
 
   Slot structure mirrors the downlink TTI, and for the same reason -- a
   helper with nothing to do must block, not poll:
 
     [ one core builds a TB and SCANS it        ]  serial by construction
     --------- partial barrier ---------
     [ every consumer REASSEMBLES a slice       ]  parallel
     --------- partial barrier ---------
     [ one core DELIVERS in order, emits STATUS ]  serial by definition
     --------- partial barrier ---------
 
   The scan is the uplink's Amdahl fraction: an AMD header is 3 or 5 bytes
   depending on SI, so PDU i+1's offset needs PDU i parsed. Measuring how fast
   one core can scan against how many cores can reassemble is the uplink
   analogue of the downlink's gather-versus-execute question. */

#ifndef RLC_UL_DRV_C
#define RLC_UL_DRV_C

#include "rlc_copy.h"
#include "rlc_sync.h"
#include "rlc_ul.h"
#include "rlc_ul_drv.h"
#include "rlc_ul.c"

/* Uplink transport blocks land here. Same arena reasoning as the downlink TB:
   above the l1d_addr boundary, so tile-private -- which is sound only while
   the consumers sharing it are co-tiled. rlc_am_init()'s cross-tile guard
   covers the same constraint and fires for both directions. */
#ifndef RLC_UL_TB_BASE
#define RLC_UL_TB_BASE 0xB0800000u
#endif
#ifndef RLC_UL_TB_BYTES
#define RLC_UL_TB_BYTES 8192u
#endif

/* Uplink SDU size.
 
   The DP Introduction doc specifies the uplink as **160 B** PDUs at 1 / 8 / 4
   Gbps for TC1 / TC2 / TC3 (see doc/KERNEL_REVIEW_NOTES.md "Huawei test
   cases"). The first version of this harness reused the 1360 B downlink
   dataset, which is not the documented uplink workload and happens to be a
   pathological choice: 1360 B SDUs in an 8192 B block pack as exactly six
   whole SDUs with two bytes spare, so nothing ever segmented and the serial
   header walk was measured on traffic containing none of what makes it
   serial. At 160 B a block carries ~49 PDUs and the boundary segments. */
#ifndef RLC_UL_SDU_BYTES
#define RLC_UL_SDU_BYTES 160u
#endif

/* Documented UL rate per test case, bits/s (doc: TC1 1 Gbps, TC2 8 Gbps,
   TC3 4 Gbps -- all at 160 B). RLC_UL_TC selects one. */
#ifndef RLC_UL_TC
#define RLC_UL_TC 1
#endif
#if RLC_UL_TC == 1
#define RLC_UL_RATE_BPS 1000000000ull
#elif RLC_UL_TC == 2
#define RLC_UL_RATE_BPS 8000000000ull
#elif RLC_UL_TC == 3
#define RLC_UL_RATE_BPS 4000000000ull
#else
#error "RLC_UL_TC must be 1, 2 or 3"
#endif

/* Slot cadence, from the doc's "pkts/slot (1600 slots/s)" row. One UL slot's
   aggregate byte budget is rate/8/1600; at 160 B that is the SDU count a
   conforming receiver must absorb per slot. */
#define RLC_UL_SLOTS_PER_SEC 1600u
#define RLC_UL_SLOT_BYTES ((uint32_t)(RLC_UL_RATE_BPS / 8ull / RLC_UL_SLOTS_PER_SEC))
#define RLC_UL_SLOT_SDUS (RLC_UL_SLOT_BYTES / RLC_UL_SDU_BYTES)

/* How many uplink SDUs the harness feeds in, per entity. Defaults to one
   slot's worth at the selected test case, so a run models a slot's arrival. */
#ifndef RLC_UL_SDUS
#define RLC_UL_SDUS RLC_UL_SLOT_SDUS
#endif

static rlc_ul_entity_t rlc_ul_ent[NUM_USERS]
    __attribute__((aligned(CACHE_LINE_SIZE))) __attribute__((section(".data")));
static rlc_ul_scan_t rlc_ul_scan_buf __attribute__((aligned(CACHE_LINE_SIZE)))
    __attribute__((section(".data")));
static uint8_t rlc_ul_status_buf[RLC_STATUS_HDR_LEN + 4u]
    __attribute__((aligned(4))) __attribute__((section(".data")));

/* Harness transmit cursor, shared: which SDU and which byte within it. */
static uint32_t rlc_ul_cur_sdu;
static uint32_t rlc_ul_cur_so;
static uint32_t rlc_ul_cur_sn;
static uint32_t rlc_ul_slots;
static uint32_t rlc_ul_tb_bytes;
static uint32_t rlc_ul_status_pdus;

/* Set by consumer 0 once the stream is exhausted; every consumer reads it
   after a barrier, so the loop exits on the same slot everywhere. */
static _Atomic uint32_t rlc_ul_stop __attribute__((aligned(CACHE_LINE_SIZE)))
    __attribute__((section(".data")));


/* Per-phase cycle accounting. build/scan/deliver run on consumer 0 only;
   reassemble is per-core, because the point of the measurement is how the
   parallel phase compares against the serial scan it cannot overlap with.
   Padded to a cache line so the per-core accumulators do not false-share. */
typedef struct {
  uint32_t cyc;
  uint8_t pad[CACHE_LINE_SIZE - sizeof(uint32_t)];
} rlc_ul_cyc_t;
static rlc_ul_cyc_t rlc_ul_cyc_reasm[RLC_ACTUAL_CONSUMERS]
    __attribute__((aligned(CACHE_LINE_SIZE))) __attribute__((section(".data")));
static uint32_t rlc_ul_cyc_build, rlc_ul_cyc_scan, rlc_ul_cyc_deliver;

/* Set once the cluster tile-participation mask has been programmed. The phase
   barriers are meaningless until it has been, and a barrier that returns
   immediately does not fail loudly -- it silently lets the phases overlap. So
   the consumer checks this and says so rather than producing quiet garbage.
 
   **Atomic, in .data, and fenced -- not a plain static.** The first version of
   this flag was a plain `static uint32_t`, which lands in .sbss and is written
   by core 0 in rlc_init() then read by the consumers after
   snrt_cluster_hw_barrier(). Nothing in that sequence makes the store visible:
   the hardware barrier is a synchronisation event, not a memory fence, and a
   non-atomic store carries no ordering of its own. The store executed and the
   load executed and they still disagreed -- consumers read 0 and every build
   tripped its own guard. Release/acquire plus an explicit fence is what
   actually publishes it. The same reasoning applies to any startup state one
   core computes for the others to read. */
static _Atomic uint32_t rlc_ul_barrier_armed
    __attribute__((aligned(CACHE_LINE_SIZE))) __attribute__((section(".data")));
static _Atomic uint32_t rlc_ul_tile_mask __attribute__((section(".data")));

void rlc_ul_init(void) {
  /* Step 1 of the partial-barrier API: programme which tiles take part. Must
     run from exactly one core BEFORE main.c's startup snrt_cluster_hw_barrier(),
     which is the resync point the API requires -- the cluster barrier FSM
     samples this mask live when the first participating tile arrives.
     rlc_am_init() does the same thing for the downlink; the uplink needs it
     for exactly the same reason and originally did not have it. */
  {
    const uint32_t cpt = snrt_cluster_core_per_tile();
    uint32_t tm_lo = 0u, tm_hi = 0u;
    for (uint32_t i = 0u; i < RLC_ACTUAL_CONSUMERS; i++) {
      const uint32_t t = (uint32_t)consumer_core_ids[i] / cpt;
      if (t < 32u) tm_lo |= 1u << t; else tm_hi |= 1u << (t - 32u);
    }
    snrt_barrier_set_tile_mask(tm_lo, tm_hi);
    atomic_store_explicit(&rlc_ul_tile_mask, tm_lo, memory_order_relaxed);
    /* Release, then fence: the consumers read this without holding any lock,
       and main.c's snrt_cluster_hw_barrier() right after rlc_init() does not
       order memory on its own. */
    atomic_store_explicit(&rlc_ul_barrier_armed, 1u, memory_order_release);
    asm volatile("fence" ::: "memory");
  }
  atomic_store_explicit(&rlc_ul_stop, 0u, memory_order_relaxed);
  for (uint32_t u = 0u; u < NUM_USERS; u++) rlc_ul_entity_init(&rlc_ul_ent[u]);
  rlc_ul_cur_sdu = 0u;
  rlc_ul_cur_so = 0u;
  rlc_ul_cur_sn = 0u;
  rlc_ul_slots = 0u;
  rlc_ul_tb_bytes = 0u;
  rlc_ul_status_pdus = 0u;
  rlc_ul_cyc_build = 0u;
  rlc_ul_cyc_scan = 0u;
  rlc_ul_cyc_deliver = 0u;
  for (uint32_t i = 0u; i < RLC_ACTUAL_CONSUMERS; i++) rlc_ul_cyc_reasm[i].cyc = 0u;
}

/* Every uplink SDU is one PDU_SIZE payload taken from the PDCP source region,
   so the harness generates realistic traffic without needing its own dataset.
   Returns TB length in bytes, 0 when the stream is exhausted. */
static uint32_t rlc_ul_build_tb(uint8_t *tb, uint32_t cap) {
  uint32_t len = 0u;
  while (rlc_ul_cur_sdu < RLC_UL_SDUS) {
    const uint32_t sdu_len = RLC_UL_SDU_BYTES;
    /* Payload comes from the PDCP source region so the harness needs no
       dataset of its own; UL SDUs are smaller than a DL packet, so take
       successive slices and wrap within the packet. */
    const uint32_t per_pkt = (uint32_t)PDU_SIZE / RLC_UL_SDU_BYTES;
    const uint8_t *base = (const uint8_t *)(uintptr_t)
        pdcp_pkgs[(rlc_ul_cur_sdu / (per_pkt ? per_pkt : 1u)) % NUM_PKGS].src_addr;
    const uint8_t *src =
        base + (per_pkt ? (rlc_ul_cur_sdu % per_pkt) : 0u) * RLC_UL_SDU_BYTES;
    const uint32_t remaining = sdu_len - rlc_ul_cur_so;
    const uint32_t si_full = (rlc_ul_cur_so == 0u) ? RLC_SI_FULL : RLC_SI_LAST;
    const uint32_t hdr = rlc_amd_hdr_len(si_full);

    if (len + RLC_UL_MAC_HDR + hdr + 1u > cap) break;
    const uint32_t room = cap - len - RLC_UL_MAC_HDR - hdr;

    uint32_t si, seg;
    if (remaining <= room) { seg = remaining; si = si_full; }
    else { seg = room; si = (rlc_ul_cur_so == 0u) ? RLC_SI_FIRST : RLC_SI_MIDDLE; }

    const uint32_t hl = rlc_amd_hdr_len(si);
    uint8_t *p = tb + len;
    p[0] = (uint8_t)(((hl + seg) >> 8) & 0xFFu);
    p[1] = (uint8_t)((hl + seg) & 0xFFu);
    /* Poll on the last segment of every 4th SDU, so the STATUS path runs. */
    const uint32_t poll = (si == RLC_SI_FULL || si == RLC_SI_LAST)
                              ? ((rlc_ul_cur_sdu % 4u) == 3u)
                              : 0u;
    rlc_amd_hdr_write(p + RLC_UL_MAC_HDR, rlc_ul_cur_sn, si, poll,
                      rlc_ul_cur_so);
    rlc_memcpy8(p + RLC_UL_MAC_HDR + hl, src + rlc_ul_cur_so, seg);
    len += RLC_UL_MAC_HDR + hl + seg;

    if (si == RLC_SI_FULL || si == RLC_SI_LAST) {
      /* SDU finished: only now does the SN advance. */
      rlc_ul_cur_sn = (rlc_ul_cur_sn + 1u) & RLC_SN_MASK;
      rlc_ul_cur_sdu++;
      rlc_ul_cur_so = 0u;
    } else {
      rlc_ul_cur_so += seg;
      break; /* TB full by construction */
    }
  }
  return len;
}

static int rlc_ul_done(void) { return rlc_ul_cur_sdu >= RLC_UL_SDUS; }

/* One uplink slot, run by every consumer. Entity 0 only: the harness feeds a
   single stream, which is what the scan-versus-reassemble split is measured
   on. Multi-entity uplink reuses these phases under the ownership map the
   downlink already has. */
static void rlc_ul_slot(uint32_t me, uint32_t bar_mask) {
  uint8_t *tb = (uint8_t *)(uintptr_t)RLC_UL_TB_BASE;

  /* --- phase 1: build + scan (serial by construction) --- */
  if (me == 0u) {
    const uint32_t t0 = benchmark_get_cycle();
    const uint32_t len = rlc_ul_build_tb(tb, RLC_UL_TB_BYTES);
    const uint32_t t1 = benchmark_get_cycle();
    rlc_ul_tb_bytes += len;
    if (len) rlc_ul_scan(&rlc_ul_scan_buf, tb, len);
    else rlc_ul_scan_buf.n = 0u;
    const uint32_t t2 = benchmark_get_cycle();
    rlc_ul_cyc_build += t1 - t0;
    rlc_ul_cyc_scan += t2 - t1;
    rlc_ul_slots++;
  }
  rlc_phase_barrier(bar_mask);

  /* --- phase 2: reassemble (parallel, disjoint slices) --- */
  {
    const uint32_t t0 = benchmark_get_cycle();
    const uint32_t n = rlc_ul_scan_buf.n;
    const uint32_t ncons = RLC_ACTUAL_CONSUMERS;
    const uint32_t step = (n + ncons - 1u) / (ncons ? ncons : 1u);
    const uint32_t lo = me * step;
    if (step && lo < n) {
      uint32_t hi = lo + step;
      if (hi > n) hi = n;
      rlc_ul_reassemble_range(&rlc_ul_ent[0], &rlc_ul_scan_buf, lo, hi);
    }
    rlc_ul_cyc_reasm[me].cyc += benchmark_get_cycle() - t0;
  }
  rlc_phase_barrier(bar_mask);

  /* --- phase 3: deliver in order + STATUS (serial by definition) --- */
  if (me == 0u) {
    const uint32_t t0 = benchmark_get_cycle();
    rlc_ul_note_highest(&rlc_ul_ent[0], &rlc_ul_scan_buf);
    rlc_ul_deliver(&rlc_ul_ent[0]);
    if (rlc_ul_ent[0].status_due) {
      rlc_ul_build_status(&rlc_ul_ent[0], rlc_ul_status_buf);
      rlc_ul_ent[0].status_due = 0u;
      rlc_ul_status_pdus++;
    }
    rlc_ul_cyc_deliver += benchmark_get_cycle() - t0;
    if (rlc_ul_done() && rlc_ul_scan_buf.n == 0u)
      atomic_store_explicit(&rlc_ul_stop, 1u, memory_order_relaxed);
  }
  rlc_phase_barrier(bar_mask);
}

static void rlc_ul_report(void) {
  const rlc_ul_entity_t *e = &rlc_ul_ent[0];
  const uint32_t want = (uint32_t)RLC_UL_SDUS * RLC_UL_SDU_BYTES;
  printf_lock_acquire(&printf_lock);
  printf("[UL] barrier tile_mask=0x%x local_mask=0x%x armed=%u\n",
         (uint32_t)atomic_load_explicit(&rlc_ul_tile_mask, memory_order_relaxed),
         snrt_cluster_partial_barrier_mask(consumer_core_ids,
                                           RLC_ACTUAL_CONSUMERS),
         (uint32_t)atomic_load_explicit(&rlc_ul_barrier_armed,
                                        memory_order_relaxed));
  printf("[UL] slots=%u tb_bytes=%u segments=%u polls_ack=%u exec=%s\n",
         rlc_ul_slots, rlc_ul_tb_bytes, e->reassembled, rlc_ul_status_pdus,
         (RLC_UL_EXEC == RLC_UL_EXEC_COPY) ? "copy" : "count");
  printf("[UL] tc=%u sdu=%uB slot_bytes=%u slot_sdus=%u\n", (unsigned)RLC_UL_TC,
         (unsigned)RLC_UL_SDU_BYTES, (unsigned)RLC_UL_SLOT_BYTES,
         (unsigned)RLC_UL_SLOT_SDUS);
  printf("[UL] delivered=%u/%u bytes=%u/%u rx_next=%u dup=%u oow=%u\n",
         e->delivered, (unsigned)RLC_UL_SDUS, e->delivered_bytes, want,
         e->rx_next, e->dup, e->out_of_window);
  {
    uint32_t rmax = 0u, rsum = 0u;
    for (uint32_t i = 0u; i < RLC_ACTUAL_CONSUMERS; i++) {
      rsum += rlc_ul_cyc_reasm[i].cyc;
      if (rlc_ul_cyc_reasm[i].cyc > rmax) rmax = rlc_ul_cyc_reasm[i].cyc;
    }
    /* The scan is the uplink's Amdahl fraction: it cannot overlap the
       reassemble that consumes its output, so serial/(serial+parallel) bounds
       what more cores can buy. build is harness cost, reported so it can be
       subtracted rather than silently counted as protocol work. */
    printf("[UL] cyc build=%u scan=%u reasm_max=%u reasm_sum=%u deliver=%u\n",
           rlc_ul_cyc_build, rlc_ul_cyc_scan, rmax, rsum, rlc_ul_cyc_deliver);
    printf("[UL] serial=%u parallel=%u cons=%u\n",
           rlc_ul_cyc_scan + rlc_ul_cyc_deliver, rmax,
           (unsigned)RLC_ACTUAL_CONSUMERS);
  }
  printf("[UL] check: %s\n",
         (e->delivered == RLC_UL_SDUS && e->out_of_window == 0u &&
          e->delivered_bytes == want)
             ? "PASS"
             : "FAIL");
  printf_lock_release(&printf_lock);
}

/* Uplink consumer entry point: replaces the downlink consumer body when
   RLC_UL_MODE is set. Lazily initialised by consumer 0 before the first
   barrier, so rlc_init() needs no uplink hook. */
void rlc_ul_consumer(uint32_t core_id) {
  const uint32_t me = rlc_consumer_index(core_id);
  const uint32_t mask =
      snrt_cluster_partial_barrier_mask(consumer_core_ids, RLC_ACTUAL_CONSUMERS);
  /* rlc_ul_init() ran in rlc_init(), before the startup hw barrier. If it did
     not, every phase barrier below is a no-op and the phases silently overlap:
     reassemble reads a scan buffer still being written, and deliver runs before
     the segments it needs have been folded in. That failure mode produces
     plausible-looking short delivery rather than an error, so say so. */
  if (!atomic_load_explicit(&rlc_ul_barrier_armed, memory_order_acquire)) {
    if (me == 0u) {
      printf_lock_acquire(&printf_lock);
      printf("[UL] FATAL: tile participation mask never programmed -- the "
             "phase barriers are no-ops. rlc_ul_init() must run in rlc_init().\n");
      printf_lock_release(&printf_lock);
    }
    return;
  }
  while (!atomic_load_explicit(&rlc_ul_stop, memory_order_relaxed))
    rlc_ul_slot(me, mask);
  if (me == 0u) rlc_ul_report();
}

#endif /* RLC_UL_DRV_C */
