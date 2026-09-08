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

/* Grant planning for the RLC AM downlink.
 
   Everything in RLC that is genuinely serial -- SN order, the cumulative poll
   counters, and the segment boundary that depends on the running grant fill --
   is confined to this planning step, which touches no payload at all. It
   produces a fully-determined descriptor per output PDU, including the byte
   offset of that PDU inside the transport block.
 
   The execute step is then embarrassingly parallel: N cores take disjoint
   slices of the plan and write headers plus payload into offsets that are
   already decided. No shared cursor, no locks, no ordering constraint.
 
   Layout is struct-of-arrays: the planner's inner loops are vectorised (RVV,
   see rlc_plan.c) and the execute phase reads contiguous slices, so SoA wins
   on both sides. */

#ifndef RLC_PLAN_H
#define RLC_PLAN_H

#include <stdint.h>
#include "rlc_pdu.h"

/* Pad rlc_plan_t out to a whole cache line. Default OFF so the default build
   stays byte-comparable with the frozen sets the GVSoC side is running
   against; turning it on mid-investigation would confound every result with
   an uncontrolled change. Now default ON: pool entries are indexed by CONSUMER,
   so pool[0] and pool[1] are written by different cores, and without padding
   rlc_plan_t is 7180 B (7180 % 64 = 12) so adjacent entries straddle a shared
   line -- a write-write ping-pong on the hottest path in the planner. Costs
   52 B per entry. */
#ifndef RLC_PLAN_PADDED
#define RLC_PLAN_PADDED 1
#endif

/* Upper bound on PDUs produced from one grant. A grant that would yield more
   is truncated (the remainder stays queued for the next grant), so this is a
   memory/latency knob, not a correctness limit. */
#ifndef RLC_MAX_PDUS_PER_GRANT
#define RLC_MAX_PDUS_PER_GRANT 128
#endif

/* Which planner rlc_plan_compute() dispatches to:
     0 = the scalar reference (rlc_plan_compute_scalar)
     1 = the scan planner     (rlc_plan_compute_vector)  [default] */
#ifndef RLC_PLAN_IMPL
#define RLC_PLAN_IMPL 1
#endif

/* Which of the scan planner's primitives use RVV, as a bitmask. Each
   primitive has an RVV form and a plain-C twin with identical semantics, so
   this bisects a vector-execution problem down to a single primitive without
   needing a PC trace. 0 = every primitive in plain C (also what the host
   build uses, since it cannot assemble RVV at all). */
#define RLC_VEC_BIT_MAPS   1u /* iota_add, sub, subx, addx, fill */
#define RLC_VEC_BIT_SCAN   2u /* prefix_sum  -- Hillis-Steele log-scan       */
#define RLC_VEC_BIT_SEARCH 4u /* first_gt    -- masked merge + vredminu.vs   */

/* Default is MAPS|SCAN, deliberately NOT SEARCH.

   Spatz decodes the vector integer compares and vmerge but does not implement
   either in its datapath: VMSGTU appears in spatz_decoder.sv (mapped to
   spatz_req.op = VMSGTU) and in the op enum, and VMERGE appears in the enum
   only -- neither is handled in spatz_simd_lane.sv, spatz_ipu.sv or
   spatz_vfu.sv, whose integer ops are VADD, VSUB, VAND, VOR, VXOR, VMIN(U),
   VMAX(U), the VMUL, VDIV and VREM families, VSLL, VSRL, VSRA, VMACC,
   VMADD, VADC, VSBC, VMADC and VMSBC.

   That makes the first-crossing search unusable on this hardware, and in a
   nastier way than an illegal instruction: the RTL *decodes* it, so there is
   no trap -- it would simply produce a wrong mask silently. Every other
   primitive maps onto an op that is implemented (the vmv forms decode to
   VSLIDEUP, vmv.x.s to VADD, vredminu.vs to VMINU with the reduction FSM), so
   only the search is affected. It stays on its C twin, which costs little:
   the searches are short and the prefix sum is where the work is.

   Set to 7 to re-enable it on hardware that implements the compares. */
#ifndef RLC_PLAN_VECTOR
#define RLC_PLAN_VECTOR (RLC_VEC_BIT_MAPS | RLC_VEC_BIT_SCAN)
#endif

#define RLC_VEC_MAPS   (RLC_PLAN_VECTOR & RLC_VEC_BIT_MAPS)
#define RLC_VEC_SCAN   (RLC_PLAN_VECTOR & RLC_VEC_BIT_SCAN)
#define RLC_VEC_SEARCH (RLC_PLAN_VECTOR & RLC_VEC_BIT_SEARCH)

/* Run both planners on every grant and compare, reporting any divergence.
   Off by default -- it doubles the planning cost. */
#ifndef RLC_PLAN_VERIFY
#define RLC_PLAN_VERIFY 0
#endif

/* All fields are u32 even where a u16 would do: keeping one element width
   lets the whole planner run at e32 without SEW changes or widening ops. */
typedef struct {
  /* --- filled by the gather step (serial pointer chase over the queue) --- */
  void    *sdu_data[RLC_MAX_PDUS_PER_GRANT]; /* payload base of the source SDU */
  void    *sdu_node[RLC_MAX_PDUS_PER_GRANT]; /* owning list Node               */
  uint32_t sdu_len [RLC_MAX_PDUS_PER_GRANT]; /* full length of that SDU        */

  /* --- computed by rlc_plan_compute() ----------------------------------- */
  uint32_t sn      [RLC_MAX_PDUS_PER_GRANT]; /* RLC sequence number           */
  uint32_t tb_off  [RLC_MAX_PDUS_PER_GRANT]; /* byte offset of hdr inside TB  */
  uint32_t seg_len [RLC_MAX_PDUS_PER_GRANT]; /* payload bytes in this PDU     */
  uint32_t so      [RLC_MAX_PDUS_PER_GRANT]; /* segment offset into the SDU   */
  uint32_t si      [RLC_MAX_PDUS_PER_GRANT]; /* RLC_SI_*                      */
  uint32_t poll    [RLC_MAX_PDUS_PER_GRANT]; /* P bit                         */
  uint32_t hdr_len [RLC_MAX_PDUS_PER_GRANT]; /* 3 or 5 (18-bit SN)            */
  uint32_t last_seg[RLC_MAX_PDUS_PER_GRANT]; /* 1 = SDU fully sent by this PDU */

  /* --- planner scratch, held per-plan so concurrent planners never share -- */
  uint32_t pdu_len[RLC_MAX_PDUS_PER_GRANT]; /* hdr + payload of each PDU     */
  uint32_t cum    [RLC_MAX_PDUS_PER_GRANT]; /* inclusive scan of pdu_len     */
  uint32_t bcum   [RLC_MAX_PDUS_PER_GRANT]; /* inclusive scan of seg_len     */

  uint32_t n_avail; /* SDUs gathered                                         */
  uint32_t n;       /* PDUs planned (<= n_avail)                             */
  uint32_t tb_used; /* bytes of the grant consumed                           */
}
#if RLC_PLAN_PADDED
/* Pad to a whole cache line.

   Without this rlc_plan_t is 7180 B on rv32 -- 7180 % 64 = 12 -- so adjacent
   entries of rlc_am_plan_pool[] straddle a shared line. Pool entries are
   indexed by CONSUMER, so pool[0] and pool[1] are written by different cores,
   and the planner writes essentially the whole buffer per grant (three prefix
   sums plus every SoA field). That puts two cores in a write-write ping-pong
   on the boundary line on the hottest path in the planner.

   64 rather than CACHE_LINE_SIZE: this header is also compiled by the host
   unit test, which does not include rlc.h. */
__attribute__((aligned(64)))
#endif
rlc_plan_t;

/* Inputs to the planner. Passing these explicitly rather than an rlc_context_t
   keeps the arithmetic decoupled from the entity/list types, so the planner
   can be exercised standalone. */
typedef struct {
  uint32_t grant_bytes;       /* size of this grant / transport block        */
  uint32_t sn_base;           /* ctx->vtNext                                 */
  uint32_t so_first;          /* bytes of plan->sdu[0] already transmitted   */
  uint32_t poll_pdu;          /* ctx->pollPdu   (pollPDU,  §5.3.3.2)         */
  uint32_t poll_byte;         /* ctx->pollByte  (pollByte, §5.3.3.2)         */
  uint32_t pdu_without_poll;  /* running PDU_WITHOUT_POLL                    */
  uint32_t byte_without_poll; /* running BYTE_WITHOUT_POLL                   */
  uint32_t queue_drained;     /* 1 if the gather emptied the to-send queue   */
} rlc_plan_in_t;

/* Entity state the planner advances. The caller writes these back to the
   entity after the plan is committed. */
typedef struct {
  uint32_t sn_next;           /* new ctx->vtNext                             */
  uint32_t pdu_without_poll;
  uint32_t byte_without_poll;
  uint32_t so_next;           /* bytes of the trailing SDU already sent;
                                 0 when no SDU is left partially transmitted */
  uint32_t partial;           /* 1 if the last planned PDU is a segment      */
} rlc_plan_out_t;

/* Turn n_avail gathered SDUs into a PDU plan that fits grant_bytes.
   Returns the number of PDUs planned (also left in plan->n). */
uint32_t rlc_plan_compute(rlc_plan_t *plan, const rlc_plan_in_t *in,
                          rlc_plan_out_t *out);

/* Scalar reference implementation -- the specification of the above. Always
   built so RLC_PLAN_VERIFY can diff the two. */
uint32_t rlc_plan_compute_scalar(rlc_plan_t *plan, const rlc_plan_in_t *in,
                                 rlc_plan_out_t *out);

/* The scan-based planner -- prefix sums and threshold searches, vectorised
   when RLC_PLAN_VECTOR. This is what rlc_plan_compute() dispatches to. */
uint32_t rlc_plan_compute_vector(rlc_plan_t *plan, const rlc_plan_in_t *in,
                                 rlc_plan_out_t *out);

/* Run both planners on the same input and compare every output field.
   `ref` is caller-supplied scratch (no hidden statics, so concurrent planners
   stay independent). Returns the number of mismatching fields; the plan left
   in `plan` is the vector one. Only built when RLC_PLAN_VERIFY is set. */
uint32_t rlc_plan_compute_checked(rlc_plan_t *plan, rlc_plan_t *ref,
                                  const rlc_plan_in_t *in, rlc_plan_out_t *out,
                                  uint32_t *nbad);

#endif /* RLC_PLAN_H */
