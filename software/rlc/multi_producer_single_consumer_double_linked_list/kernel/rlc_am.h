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

/* RLC AM downlink: transport-block assembly on top of the grant planner.
 
   Ownership model ("owner-plans"): every RLC entity has one owner core, given
   by the same static partition the legacy consumer already uses. The owner
   gathers the queue, plans the grant, and publishes the plan; then *any*
   consumer core -- owner included -- claims chunks of that plan and executes
   them in parallel. The owner commits once all chunks report done.
 
   That split is what keeps single-entity peak rate reachable: at NUM_USERS==1
   there is one owner and C-1 helpers all filling the same transport block,
   into byte offsets the planner already fixed, with no lock and no ordering
   constraint between them. */

#ifndef RLC_AM_H
#define RLC_AM_H

#include <stdint.h>
#include <stdatomic.h>

#include "rlc_pdu.h"
#include "rlc_plan.h"

/* --- build-time selection ------------------------------------------------ */

/* Downlink model. LEGACY keeps the original "copy each SDU to a destination
   fixed at generation time" behaviour bit-for-bit, which is both the
   regression baseline and -- since CachePool instantiates no DMA -- the only
   thing in this kernel that generates payload DRAM traffic. */
#define RLC_TB_MODE_LEGACY 0
#define RLC_TB_MODE_AM     1
#ifndef RLC_TB_MODE
#define RLC_TB_MODE RLC_TB_MODE_LEGACY
#endif

/* Execute back-end. COPY moves the payload into the transport block. SGL only
   produces a scatter-gather descriptor per PDU, which is what a real
   accelerator would hand to a DMA. Same plan either way, so the two are
   directly comparable. */
#define RLC_DL_EXEC_COPY 0
#define RLC_DL_EXEC_SGL  1
#ifndef RLC_DL_EXEC
#define RLC_DL_EXEC RLC_DL_EXEC_COPY
#endif

/* Copy the payload with scalar byte stores instead of the e8/m8 vector copy.
   Isolation knob: a protocol-accurate AMD header is 3 or 5 bytes, so the
   payload destination inside the transport block is at an arbitrary byte
   offset, and whether a vector unit handles an unaligned base at LMUL=8 is
   exactly the thing in question. If the scalar copy is clean and the vector
   copy is not, the copy is at fault; if both fail, the offsets feeding them
   are. */
#ifndef RLC_DL_COPY_SCALAR
#define RLC_DL_COPY_SCALAR 0
#endif

/* Bytes granted per entity per scheduling opportunity. A real TTI scheduler
   replaces this (F6); until then it is a fixed knob. */
#ifndef RLC_GRANT_BYTES
#define RLC_GRANT_BYTES 8192u
#endif

/* The transport block is shared by every core that executes a grant. That is
   only sound while those cores can see each other's writes to it.

   RLC_TB_BASE is above the l1d_addr boundary (default 0xA000_0000), so the
   arena is classified PRIVATE -- and private banks are tile-local and not
   visible to remote tiles (see the README, "Cache Partitioning"). With
   main.c's l1d_part(num_cores_per_tile) every bank is private, so executors
   on different tiles would write into *different* copies of the transport
   block and the owner would only ever verify its own tile's half.

   Every configuration run so far is safe by accident: the data headers list
   consumers {2,3} or {1}, all inside tile 0. It breaks silently the moment a
   consumer list spans tiles, which is exactly what scaling executors means.
   rlc_am_init() therefore checks this at startup and fails loudly.

   Two ways out when we do scale: move the arena below the boundary so it is
   cluster-shared, or confine an entity's executors to the owner's tile (which
   is also the tile-local placement the GVSoC-side design argues for). Until
   one is chosen, set this to 1 only if you have made the arena visible
   cluster-wide by other means. */
#ifndef RLC_AM_ALLOW_CROSS_TILE_TB
#define RLC_AM_ALLOW_CROSS_TILE_TB 0
#endif

/* Transport-block arena. One TB per entity, carved from the target window
   that the legacy path used for per-descriptor destinations. */
#ifndef RLC_TB_BASE
#define RLC_TB_BASE 0xB0000000u
#endif
#ifndef RLC_TB_STRIDE
#define RLC_TB_STRIDE RLC_GRANT_BYTES
#endif

/* TTI-structured consumer loop.

   1 = plan / execute / commit run as three phases separated by a partial
   hardware barrier over the consumer set. Helpers **block in the barrier**
   instead of sweeping the entity list looking for work.

   That is the fix for the dominant cost measured on RTL: a helper was doing
   463 sweeps for a single grant, and enabling the bitmap work queue did not
   rescue it, because cheapening each sweep does not stop the polling. With
   this, a consumer that has nothing to do consumes nothing.

   It also gives the agreed cross-engine metric its unit of time:
     ONE TTI = ONE GRANT OPPORTUNITY PER ENTITY
     primary metric = bytes/cycle = (payload bytes) / (kernel cycles)
   0 keeps the original free-running loop for A/B comparison. */
#ifndef RLC_AM_TTI
#define RLC_AM_TTI 1
#endif

/* Optional wallclock-flavoured pacing: pad each TTI to this many cycles.
   0 = unpaced (run flat out). 5000 is the agreed scaled TTI -- a 1:100
   scaling of 500 us at 1 GHz -- chosen so neither engine has to simulate
   500,000 cycles per data point. */
#ifndef RLC_TTI_CYCLES
#define RLC_TTI_CYCLES 0
#endif

/* How far behind the transmitter the modelled UE acknowledges, in PDUs. The
   kernel receives ACKs only (no NACK, no retransmission), so a fixed lag is
   the whole feedback model -- but the STATUS PDU is really built and really
   parsed, so its cost is measured rather than assumed away. */
#ifndef RLC_AM_ACK_LAG
#define RLC_AM_ACK_LAG 4u
#endif

/* Pad rlc_am_entity_t out to a full cache line, removing false sharing between
   adjacent entities' atomics.

   Default ON: measured, and it removes a real defect. The struct is 124 B on
   rv32, so without this the array packs entities at 124 B and neighbours share
   cache lines -- and it holds gen/claim/done, the atomics every executing core
   hammers. Which entities collide depends on the index (entity u starts at
   124u). Costs 4 B per entity. */
#ifndef RLC_AM_ENT_PADDED
#define RLC_AM_ENT_PADDED 1
#endif

/* Dummy .data inserted ahead of the entity arrays, purely to shift every
   subsequent address without changing any structure. Separates "the layout
   moved" from "false sharing was removed" -- the two differ only in whether
   the padding is inside the struct or in front of it. */
#ifndef RLC_LAYOUT_PAD
#define RLC_LAYOUT_PAD 0
#endif

/* Work queue. 0 (default): every core visits every entity each step, which is
   fine at 1..48 entities but is O(NUM_USERS) per step and does not survive
   TC3's 4800. 1: entities announce themselves through two bitmaps, so a step
   costs O(entities that actually have work).

   Default ON. The base AM path is validated on hardware (RTL transport-block
   check passes end to end), and the scan-every-entity alternative was measured
   to be untenable: 8 entities x 8 packets could not finish an hour of RTL even
   with this enabled, because helpers poll. Without it, cost scales with the
   entity count on every step. */
#ifndef RLC_AM_WORKQ
#define RLC_AM_WORKQ 1
#endif

/* PDUs claimed per atomic operation by an executing core. Small enough to
   balance a lopsided grant, large enough that the claim is not the cost. */
#ifndef RLC_AM_CLAIM_CHUNK
#define RLC_AM_CLAIM_CHUNK 4u
#endif

/* --- scatter-gather output (RLC_DL_EXEC_SGL) ----------------------------- */

typedef struct {
  void    *hdr;     /* assembled RLC header inside the TB */
  uint32_t hdr_len;
  void    *src;     /* payload source, already offset by SO */
  uint32_t len;
} rlc_sgl_t;

/* --- per-entity assembly state ------------------------------------------- */

typedef struct {
  /* Segmentation cursor: bytes of the SDU at the head of the to-send list
     that have already been transmitted. Non-zero means that SDU stays queued
     and its remainder leads the next grant. */
  uint32_t so_next;

  /* Published grant. `gen` is odd while a grant is open; plan/tb/n are
     written before it is bumped and stay stable until the grant closes. */
  rlc_plan_t      *plan;
  uint8_t         *tb;
  uint32_t         n;
  uint32_t         tb_used;
  uint32_t         partial; /* last planned PDU is a segment, its SDU stays */
  _Atomic uint32_t gen;
  _Atomic uint32_t claim; /* next PDU index to hand out */
  _Atomic uint32_t done;  /* PDUs finished              */

#if RLC_DL_EXEC == RLC_DL_EXEC_SGL
  rlc_sgl_t sgl[RLC_MAX_PDUS_PER_GRANT];
#endif

  /* Cross-grant continuity expectations for the transport-block self-check:
     the SN and segment offset the next grant must start from. */
  uint32_t verify_sn;
  uint32_t verify_so;

  /* Which transport-block checks failed, as a bitmask, plus the first PDU
     index that failed. Carried in the entity and printed from the summary so
     the diagnosis does not depend on a per-grant printf surviving. */
  uint32_t verify_mask;
  uint32_t verify_bad_idx;
  uint32_t verify_have_bad;
  /* Payload-mismatch detail: which destination alignments failed (bit a set
     means a PDU whose payload started at addr%4 == a compared wrong), how many
     PDUs compared wrong vs were checked, and the first differing byte offset.
     If only the misaligned alignments appear, the copy is alignment-sensitive. */
  uint32_t verify_align_bad;
  uint32_t verify_align_ok;
  uint32_t verify_pay_bad;
  uint32_t verify_pay_checked;
  uint32_t verify_first_byte;

  /* instrumentation. Only the owner writes these, so no atomics needed. */
  uint32_t plan_calls;   /* owner reached the plan attempt            */
  uint32_t peek_empty;   /* ... and the queue look-ahead returned 0   */
  uint32_t plan_zero;    /* ... queue had SDUs but nothing was planned */
  uint32_t plan_ok;      /* planner returned n > 0                     */
  uint32_t peek_done;    /* the queue look-ahead returned (vs still in it) */
  uint32_t poison_done;  /* got past the pre-publish poison            */
  uint32_t published;    /* generation bumped, grant is live           */
  uint32_t peek_max;     /* largest look-ahead seen                   */
  uint32_t grants;
  uint32_t pdus;
  uint32_t segments;
  uint32_t polls;
}
#if RLC_AM_ENT_PADDED
/* Pad each entity to a whole cache line.

   rlc_am_entity_t is 124 B on rv32 -- not a multiple of 64 -- so despite the
   array being cache-line aligned, adjacent entities share lines. The struct
   holds gen/claim/done, the atomics that every executing core hammers, so two
   owners working on neighbouring entities ping-pong the same line. Which
   entities collide depends on the index (entity u starts at 124u), which makes
   the behaviour depend on entity count for a reason that has nothing to do
   with the protocol. */
__attribute__((aligned(CACHE_LINE_SIZE)))
#endif
rlc_am_entity_t;

/* Per-consumer progress, indexed by consumer index. Distinguishes "the step
   loop ran once" from "the step loop is stuck partway through the entity
   sweep": steps counts completed sweeps, last_u the highest entity reached. */
#ifndef RLC_AM_MAX_TRACKED_CONSUMERS
#define RLC_AM_MAX_TRACKED_CONSUMERS 16
#endif

/* Reset the AM state of one entity. Called from rlc_init(). */
void rlc_am_init(uint32_t u);

/* One step of the AM consumer for this core: plan an owned entity if it has
   no grant open, and help execute whatever grants are open. Returns the
   number of PDUs this core executed. */
uint32_t rlc_am_step(uint32_t core_id);

/* True once every entity is drained and no grant is open. */
int rlc_am_idle(void);

#if RLC_AM_WORKQ
/* Announce that entity u has data to send. Called by producers after they
   enqueue, and by commit when an entity still has work left over. */
void rlc_am_mark_ready(uint32_t u);
#endif

/* Build a STATUS PDU for every entity, parse it back, and release the SDUs it
   acknowledges. Runs on the status core, replacing the legacy fixed
   "acknowledge two nodes" model. */
void rlc_am_status(void);

/* TTI-structured consumer entry point. Returns when every producer has
   finished and every entity is drained. */
void rlc_am_consumer_tti(uint32_t core_id);

/* Print the AM summary (grants, PDUs, segments, polls) and, when the checks
   are compiled in, the verdict. Call on one core after the final barrier. */
void rlc_am_report(void);

#endif /* RLC_AM_H */
