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

/* RLC AM grant planner -- see rlc_plan.h for the role of this stage.
 
   Two implementations live here:
     rlc_plan_compute_scalar()  the reference / specification
     rlc_plan_compute_vector()  the RVV version actually used
 
   The vector version exists because the plan stage, although logically
   serial, is almost entirely *data-parallel arithmetic* once the queue has
   been walked:
 
     - the transport-block offsets are an inclusive prefix sum of PDU lengths
     - the SN assignment is base + lane index
     - the segment boundary is "first lane whose running sum exceeds the grant"
     - the poll positions are threshold crossings of two running counters
 
   Prefix sums and first-crossing searches both map onto RVV. Spatz decodes no
   vid.v / viota.m / vcpop.m, so lane indices come from a static table and
   first-set-lane is done with a masked merge against a sentinel followed by
   an unsigned min-reduction. */

#ifndef RLC_PLAN_C
#define RLC_PLAN_C

#include <stdatomic.h>

#include "rlc_plan.h"

/* Counts vsetvli results of zero. Declared outside the vector guard so the
   scalar build can report it (always 0 there) without a second #if. */
_Atomic uint32_t rlc_vec_zero_vl;

/* The planner's primitives -- prefix sum, first-crossing search, and a few
   elementwise maps -- have two implementations with identical semantics: RVV
   under RLC_PLAN_VECTOR, plain C otherwise. The scan-based planner that uses
   them is built either way, so -DRLC_PLAN_VECTOR=0 yields a pure-C
   translation unit whose *algorithm* is the same one that runs on target.
   test/test_rlc_plan.c exploits that to diff the scan planner against the
   reference planner on the host, leaving only RVV codegen to be checked on
   hardware (RLC_PLAN_VERIFY). */
/* RVV forms. Compiled whenever any primitive is vectorised. */
#if RLC_PLAN_VECTOR

/* ------------------------------------------------------------------------ */
/* RVV helpers                                                              */
/* ------------------------------------------------------------------------ */

/* Lane indices. Spatz has no vid.v, so the iota comes from memory. Sized to
   RLC_MAX_PDUS_PER_GRANT, which bounds every vector length used here. */
static const uint32_t rlc_iota[RLC_MAX_PDUS_PER_GRANT] __attribute__((aligned(64))) = {
      0,   1,   2,   3,   4,   5,   6,   7,   8,   9,  10,  11,  12,  13,  14,  15,
     16,  17,  18,  19,  20,  21,  22,  23,  24,  25,  26,  27,  28,  29,  30,  31,
     32,  33,  34,  35,  36,  37,  38,  39,  40,  41,  42,  43,  44,  45,  46,  47,
     48,  49,  50,  51,  52,  53,  54,  55,  56,  57,  58,  59,  60,  61,  62,  63,
     64,  65,  66,  67,  68,  69,  70,  71,  72,  73,  74,  75,  76,  77,  78,  79,
     80,  81,  82,  83,  84,  85,  86,  87,  88,  89,  90,  91,  92,  93,  94,  95,
     96,  97,  98,  99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111,
    112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127,
};

#define RLC_VEC_NONE 0xFFFFFFFFu

/* Every vector loop below advances by the vl that vsetvli returns. A vl of 0
   would therefore spin forever -- the worst possible symptom, because it
   presents as a silent hang with no state to inspect. vsetvli must not return
   0 for a non-zero AVL with a legal vtype, so this can only fire on a broken
   decoder or an unsupported vtype, but the cost of the check is one branch
   per chunk and it converts a hang into an observable counter. */
/* Deliberately NOT wrapped in do{}while(0): the break must escape the caller's
   chunk loop, and inside a do-while wrapper it would escape only the wrapper
   and spin anyway. Only ever used as a statement directly inside those loops. */
#define RLC_VEC_GUARD(vl)                                                     \
  if ((vl) == 0u) {                                                           \
    atomic_fetch_add_explicit(&rlc_vec_zero_vl, 1u, memory_order_relaxed);    \
    break;                                                                    \
  }

/* Snitch's scalar LSU and Spatz's vector LSU are independent, so a scalar
   access can bypass an outstanding vector access to the same address. Every
   scalar<->vector handoff on the plan arrays is bracketed by a fence, which
   drains both (this is what snrt_fence() emits; spelled out here so the
   planner stays independent of snRuntime and can be exercised standalone). */
#define RLC_VEC_FENCE() asm volatile("fence" ::: "memory")

/* dst[0..n) = inclusive prefix sum of src[0..n).
   Hillis-Steele log-scan inside each vector chunk, scalar carry across chunks:
   ceil(log2(vl)) vector adds per chunk instead of vl scalar adds. */
static void __attribute__((unused)) rlc_vec_prefix_sum_u32_rvv(uint32_t *dst, const uint32_t *src,
                                   uint32_t n) {
  uint32_t carry = 0;
  uint32_t i = 0;
  RLC_VEC_FENCE();
  while (i < n) {
    uint32_t vl;
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(n - i));
    RLC_VEC_GUARD(vl);
    asm volatile("vle32.v v8, (%0)" ::"r"(src + i) : "memory");
    /* v8 <- inclusive scan of v8 */
    for (uint32_t ofs = 1; ofs < vl; ofs <<= 1) {
      /* vslideup leaves lanes [0,ofs) untouched, so zero the destination
         first -- those lanes must contribute nothing to the sum. */
      asm volatile("vmv.v.i v16, 0");
      asm volatile("vslideup.vx v16, v8, %0" ::"r"(ofs));
      asm volatile("vadd.vv v8, v8, v16");
    }
    asm volatile("vadd.vx v8, v8, %0" ::"r"(carry));
    asm volatile("vse32.v v8, (%0)" ::"r"(dst + i) : "memory");
    /* Carry into the next chunk is the last lane. Taken out of the vector
       register rather than re-read from dst[] -- a scalar load here would
       race the vector store that has just been issued. */
    asm volatile("vslidedown.vx v16, v8, %0" ::"r"(vl - 1));
    asm volatile("vmv.x.s %0, v16" : "=r"(carry));
    i += vl;
  }
  RLC_VEC_FENCE();
}

/* Smallest i in [start,n) with val[i] > thr, or n if there is none.
   Masked merge of the lane index against a sentinel, then an unsigned
   min-reduction -- Spatz decodes neither vfirst.m nor viota.m. */
static uint32_t __attribute__((unused)) rlc_vec_first_gt_u32_rvv(const uint32_t *val, uint32_t start,
                                     uint32_t n, uint32_t thr) {
  uint32_t i = start;
  RLC_VEC_FENCE();
  while (i < n) {
    uint32_t vl;
    uint32_t lane;
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(n - i));
    RLC_VEC_GUARD(vl);
    asm volatile("vle32.v v8,  (%0)" ::"r"(val + i) : "memory");
    asm volatile("vle32.v v12, (%0)" ::"r"(rlc_iota) : "memory");
    asm volatile("vmsgtu.vx v0, v8, %0" ::"r"(thr));
    asm volatile("vmv.v.x v16, %0" ::"r"(RLC_VEC_NONE));
    asm volatile("vmerge.vvm v16, v16, v12, v0");
    asm volatile("vmv.s.x v24, %0" ::"r"(RLC_VEC_NONE));
    asm volatile("vredminu.vs v24, v16, v24");
    asm volatile("vmv.x.s %0, v24" : "=r"(lane));
    if (lane != RLC_VEC_NONE) {
      RLC_VEC_FENCE();
      return i + lane;
    }
    i += vl;
  }
  RLC_VEC_FENCE();
  return n;
}

/* dst[0..n) = (base + i) & mask */
static void __attribute__((unused)) rlc_vec_iota_add_u32_rvv(uint32_t *dst, uint32_t base, uint32_t mask,
                                 uint32_t n) {
  uint32_t i = 0;
  RLC_VEC_FENCE();
  while (i < n) {
    uint32_t vl;
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(n - i));
    RLC_VEC_GUARD(vl);
    asm volatile("vle32.v v8, (%0)" ::"r"(rlc_iota) : "memory");
    asm volatile("vadd.vx v8, v8, %0" ::"r"(base + i));
    asm volatile("vand.vx v8, v8, %0" ::"r"(mask));
    asm volatile("vse32.v v8, (%0)" ::"r"(dst + i) : "memory");
    i += vl;
  }
  RLC_VEC_FENCE();
}

/* dst[0..n) = a[0..n) - b[0..n) */
static void __attribute__((unused)) rlc_vec_sub_u32_rvv(uint32_t *dst, const uint32_t *a, const uint32_t *b,
                            uint32_t n) {
  uint32_t i = 0;
  RLC_VEC_FENCE();
  while (i < n) {
    uint32_t vl;
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(n - i));
    RLC_VEC_GUARD(vl);
    asm volatile("vle32.v v8,  (%0)" ::"r"(a + i) : "memory");
    asm volatile("vle32.v v12, (%0)" ::"r"(b + i) : "memory");
    asm volatile("vsub.vv v8, v8, v12");
    asm volatile("vse32.v v8, (%0)" ::"r"(dst + i) : "memory");
    i += vl;
  }
  RLC_VEC_FENCE();
}

/* dst[0..n) = a[0..n) - imm */
static void __attribute__((unused)) rlc_vec_subx_u32_rvv(uint32_t *dst, const uint32_t *a, uint32_t imm,
                             uint32_t n) {
  uint32_t i = 0;
  RLC_VEC_FENCE();
  while (i < n) {
    uint32_t vl;
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(n - i));
    RLC_VEC_GUARD(vl);
    asm volatile("vle32.v v8, (%0)" ::"r"(a + i) : "memory");
    asm volatile("vsub.vx v8, v8, %0" ::"r"(imm));
    asm volatile("vse32.v v8, (%0)" ::"r"(dst + i) : "memory");
    i += vl;
  }
  RLC_VEC_FENCE();
}

/* dst[0..n) = a[0..n) + imm */
static void __attribute__((unused)) rlc_vec_addx_u32_rvv(uint32_t *dst, const uint32_t *a, uint32_t imm,
                             uint32_t n) {
  uint32_t i = 0;
  RLC_VEC_FENCE();
  while (i < n) {
    uint32_t vl;
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(n - i));
    RLC_VEC_GUARD(vl);
    asm volatile("vle32.v v8, (%0)" ::"r"(a + i) : "memory");
    asm volatile("vadd.vx v8, v8, %0" ::"r"(imm));
    asm volatile("vse32.v v8, (%0)" ::"r"(dst + i) : "memory");
    i += vl;
  }
  RLC_VEC_FENCE();
}

/* dst[0..n) = val */
static void __attribute__((unused)) rlc_vec_fill_u32_rvv(uint32_t *dst, uint32_t val, uint32_t n) {
  uint32_t i = 0;
  RLC_VEC_FENCE();
  while (i < n) {
    uint32_t vl;
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(n - i));
    RLC_VEC_GUARD(vl);
    asm volatile("vmv.v.x v8, %0" ::"r"(val));
    asm volatile("vse32.v v8, (%0)" ::"r"(dst + i) : "memory");
    i += vl;
  }
  RLC_VEC_FENCE();
}

#endif /* RLC_PLAN_VECTOR */

/* Plain-C twins. Always compiled: they are the host build's implementation
   and the fallback for every primitive whose bit is clear. */

#define RLC_VEC_NONE_C 0xFFFFFFFFu

static void __attribute__((unused)) rlc_vec_prefix_sum_u32_c(uint32_t *dst, const uint32_t *src,
                                   uint32_t n) {
  uint32_t acc = 0u;
  for (uint32_t i = 0u; i < n; i++) { acc += src[i]; dst[i] = acc; }
}

static uint32_t __attribute__((unused)) rlc_vec_first_gt_u32_c(const uint32_t *val, uint32_t start,
                                     uint32_t n, uint32_t thr) {
  for (uint32_t i = start; i < n; i++)
    if (val[i] > thr) return i;
  return n;
}

static void __attribute__((unused)) rlc_vec_iota_add_u32_c(uint32_t *dst, uint32_t base, uint32_t mask,
                                 uint32_t n) {
  for (uint32_t i = 0u; i < n; i++) dst[i] = (base + i) & mask;
}

static void __attribute__((unused)) rlc_vec_sub_u32_c(uint32_t *dst, const uint32_t *a, const uint32_t *b,
                            uint32_t n) {
  for (uint32_t i = 0u; i < n; i++) dst[i] = a[i] - b[i];
}

static void __attribute__((unused)) rlc_vec_subx_u32_c(uint32_t *dst, const uint32_t *a, uint32_t imm,
                             uint32_t n) {
  for (uint32_t i = 0u; i < n; i++) dst[i] = a[i] - imm;
}

static void __attribute__((unused)) rlc_vec_addx_u32_c(uint32_t *dst, const uint32_t *a, uint32_t imm,
                             uint32_t n) {
  for (uint32_t i = 0u; i < n; i++) dst[i] = a[i] + imm;
}

static void __attribute__((unused)) rlc_vec_fill_u32_c(uint32_t *dst, uint32_t val, uint32_t n) {
  for (uint32_t i = 0u; i < n; i++) dst[i] = val;
}


/* ---- per-primitive dispatch ------------------------------------------- */
/* Each selects its RVV form or its C twin independently, so RLC_PLAN_VECTOR
   can isolate one primitive at a time. */

static inline void rlc_vec_prefix_sum_u32(uint32_t *d, const uint32_t *s, uint32_t n) {
#if RLC_VEC_SCAN
  rlc_vec_prefix_sum_u32_rvv(d, s, n);
#else
  rlc_vec_prefix_sum_u32_c(d, s, n);
#endif
}
static inline uint32_t rlc_vec_first_gt_u32(const uint32_t *v, uint32_t st, uint32_t n, uint32_t t) {
#if RLC_VEC_SEARCH
  return rlc_vec_first_gt_u32_rvv(v, st, n, t);
#else
  return rlc_vec_first_gt_u32_c(v, st, n, t);
#endif
}
static inline void rlc_vec_iota_add_u32(uint32_t *d, uint32_t b, uint32_t m, uint32_t n) {
#if RLC_VEC_MAPS
  rlc_vec_iota_add_u32_rvv(d, b, m, n);
#else
  rlc_vec_iota_add_u32_c(d, b, m, n);
#endif
}
static inline void rlc_vec_sub_u32(uint32_t *d, const uint32_t *a, const uint32_t *b, uint32_t n) {
#if RLC_VEC_MAPS
  rlc_vec_sub_u32_rvv(d, a, b, n);
#else
  rlc_vec_sub_u32_c(d, a, b, n);
#endif
}
static inline void rlc_vec_subx_u32(uint32_t *d, const uint32_t *a, uint32_t i, uint32_t n) {
#if RLC_VEC_MAPS
  rlc_vec_subx_u32_rvv(d, a, i, n);
#else
  rlc_vec_subx_u32_c(d, a, i, n);
#endif
}
static inline void rlc_vec_addx_u32(uint32_t *d, const uint32_t *a, uint32_t i, uint32_t n) {
#if RLC_VEC_MAPS
  rlc_vec_addx_u32_rvv(d, a, i, n);
#else
  rlc_vec_addx_u32_c(d, a, i, n);
#endif
}
static inline void rlc_vec_fill_u32(uint32_t *d, uint32_t v, uint32_t n) {
#if RLC_VEC_MAPS
  rlc_vec_fill_u32_rvv(d, v, n);
#else
  rlc_vec_fill_u32_c(d, v, n);
#endif
}



/* ------------------------------------------------------------------------ */
/* Shared tail: the poll decision                                           */
/* ------------------------------------------------------------------------ */

/* TS 38.322 §5.3.3.2: on every AMD PDU carrying an SDU or SDU segment,
   PDU_WITHOUT_POLL and BYTE_WITHOUT_POLL advance; crossing pollPDU or
   pollByte sets the P bit and resets both counters. A poll is also sent when
   the transmission buffer runs empty.
 
   Two properties make this cheap to vectorise:
     - between two polls the PDU counter is a pure lane offset, so the next
       PDU-threshold crossing is closed-form, no search needed;
     - the byte counter is the prefix sum of seg_len, so the next
       byte-threshold crossing is one first-greater-than search.
   The loop therefore runs once per poll event, not once per PDU. */
static void rlc_plan_polls_vector(rlc_plan_t *plan, const rlc_plan_in_t *in,
                                  uint32_t n, uint32_t *pwp_io,
                                  uint32_t *bwp_io) {
  uint32_t pwp = *pwp_io;
  uint32_t bwp = *bwp_io;
  uint32_t start = 0;

  rlc_vec_fill_u32(plan->poll, 0u, n);
  rlc_vec_prefix_sum_u32(plan->bcum, plan->seg_len, n);

  while (start < n) {
    /* PDU-count crossing: pwp + (i - start + 1) >= poll_pdu */
    uint32_t i_pdu = n;
    if (in->poll_pdu != 0u) {
      uint32_t need = (in->poll_pdu > pwp) ? (in->poll_pdu - pwp) : 1u;
      i_pdu = start + need - 1u;
      if (i_pdu >= n) i_pdu = n;
    }
    /* Byte-count crossing: bwp + (bcum[i] - base) >= poll_byte, i.e. the
       first bcum[i] strictly greater than (poll_byte - bwp - 1 + base). */
    uint32_t i_byte = n;
    if (in->poll_byte != 0u) {
      uint32_t base = (start == 0u) ? 0u : plan->bcum[start - 1u];
      if (bwp >= in->poll_byte) {
        i_byte = start;
      } else {
        uint32_t thr = in->poll_byte - bwp - 1u + base;
        i_byte = rlc_vec_first_gt_u32(plan->bcum, start, n, thr);
      }
    }
    uint32_t k = (i_pdu < i_byte) ? i_pdu : i_byte;
    if (k >= n) break;
    plan->poll[k] = 1u;
    pwp = 0u;
    bwp = 0u;
    start = k + 1u;
  }

  /* Account for the PDUs after the last poll. */
  if (n > 0u) {
    uint32_t base = (start == 0u) ? 0u : plan->bcum[start - 1u];
    pwp += (n - start);
    bwp += plan->bcum[n - 1u] - base;
  }
  *pwp_io = pwp;
  *bwp_io = bwp;
}

/* ------------------------------------------------------------------------ */
/* Scalar reference                                                         */
/* ------------------------------------------------------------------------ */

uint32_t rlc_plan_compute_scalar(rlc_plan_t *plan, const rlc_plan_in_t *in,
                                 rlc_plan_out_t *out) {
  const uint32_t G = in->grant_bytes;
  uint32_t cum = 0u;
  uint32_t sn = in->sn_base;
  uint32_t pwp = in->pdu_without_poll;
  uint32_t bwp = in->byte_without_poll;
  uint32_t n = 0u;
  uint32_t partial = 0u;
  uint32_t so_next = 0u;

  for (uint32_t i = 0u; i < plan->n_avail && n < RLC_MAX_PDUS_PER_GRANT; i++) {
    /* Only the first entry can continue a partially transmitted SDU. */
    const uint32_t seg_so = (i == 0u) ? in->so_first : 0u;
    const uint32_t remaining = plan->sdu_len[i] - seg_so;
    /* Header length depends only on whether SO is present, and SO is present
       exactly when this PDU does not start at offset 0 -- independent of
       whether the PDU also ends up segmented. */
    const uint32_t hdr = (seg_so == 0u) ? RLC_AMD_HDR_MIN : RLC_AMD_HDR_MAX;

    if (cum + hdr >= G) break; /* no room for a header plus a payload byte */
    const uint32_t room = G - cum - hdr;

    uint32_t seg_len, si, last;
    if (remaining <= room) {
      seg_len = remaining;
      si = (seg_so == 0u) ? RLC_SI_FULL : RLC_SI_LAST;
      last = 1u;
    } else {
      seg_len = room;
      si = (seg_so == 0u) ? RLC_SI_FIRST : RLC_SI_MIDDLE;
      last = 0u;
    }

    plan->sn[n] = sn & RLC_SN_MASK;
    plan->so[n] = seg_so;
    plan->seg_len[n] = seg_len;
    plan->si[n] = si;
    plan->hdr_len[n] = hdr;
    plan->tb_off[n] = cum;
    plan->last_seg[n] = last;

    /* Poll counters (§5.3.3.2). */
    pwp += 1u;
    bwp += seg_len;
    uint32_t p = 0u;
    if (in->poll_pdu != 0u && pwp >= in->poll_pdu) {
      p = 1u;
    } else if (in->poll_byte != 0u && bwp >= in->poll_byte) {
      p = 1u;
    }
    if (p) {
      pwp = 0u;
      bwp = 0u;
    }
    plan->poll[n] = p;

    cum += hdr + seg_len;
    sn++;
    n++;

    if (!last) {
      /* The grant is exactly full by construction; the SDU remainder waits. */
      partial = 1u;
      so_next = seg_so + seg_len;
      break;
    }
  }

  /* A poll is also triggered when the buffer runs empty (§5.3.3.2). */
  if (n > 0u && in->queue_drained && !partial && !plan->poll[n - 1u]) {
    plan->poll[n - 1u] = 1u;
    pwp = 0u;
    bwp = 0u;
  }

  plan->n = n;
  plan->tb_used = cum;
  /* The SN identifies the SDU, not the PDU: every segment of one SDU carries
     the same SN, with SO distinguishing them (TS 38.322 6.2.2.4). So a grant
     whose last PDU is a segment leaves that SDU's SN still in use, and the
     next grant's leading segment must reuse it -- advancing here would open a
     hole the receiver can never fill, because the missing SN is never sent. */
  out->sn_next = (in->sn_base + n - partial) & RLC_SN_MASK;
  out->pdu_without_poll = pwp;
  out->byte_without_poll = bwp;
  out->so_next = so_next;
  out->partial = partial;
  return n;
}

/* ------------------------------------------------------------------------ */
/* Scan-based planner (RVV primitives when RLC_PLAN_VECTOR)                 */
/* ------------------------------------------------------------------------ */

uint32_t rlc_plan_compute_vector(rlc_plan_t *plan, const rlc_plan_in_t *in,
                                 rlc_plan_out_t *out) {
  const uint32_t G = in->grant_bytes;
  uint32_t n_avail = plan->n_avail;
  if (n_avail > RLC_MAX_PDUS_PER_GRANT) n_avail = RLC_MAX_PDUS_PER_GRANT;

  if (n_avail == 0u) {
    plan->n = 0u;
    plan->tb_used = 0u;
    out->sn_next = in->sn_base & RLC_SN_MASK;
    out->pdu_without_poll = in->pdu_without_poll;
    out->byte_without_poll = in->byte_without_poll;
    out->so_next = 0u;
    out->partial = 0u;
    return 0u;
  }

  /* 1. Provisional PDU lengths, assuming every SDU is sent whole. Only lane 0
        can carry an SO, so the vector pass uses the common header length and
        lane 0 is corrected afterwards. */
  rlc_vec_addx_u32(plan->pdu_len, plan->sdu_len, RLC_AMD_HDR_MIN, n_avail);
  const uint32_t hdr0 = (in->so_first == 0u) ? RLC_AMD_HDR_MIN : RLC_AMD_HDR_MAX;
  plan->pdu_len[0] = plan->sdu_len[0] - in->so_first + hdr0;

  /* 2. Running transport-block fill. */
  rlc_vec_prefix_sum_u32(plan->cum, plan->pdu_len, n_avail);

  /* 3. First PDU that overflows the grant -- the segmentation candidate. */
  const uint32_t k = rlc_vec_first_gt_u32(plan->cum, 0u, n_avail, G);

  uint32_t n, partial = 0u, so_next = 0u;
  if (k >= n_avail) {
    n = n_avail; /* the whole gathered queue fits */
  } else {
    const uint32_t base = (k == 0u) ? 0u : plan->cum[k - 1u];
    const uint32_t hdr_k = (k == 0u) ? hdr0 : RLC_AMD_HDR_MIN;
    if (base + hdr_k < G) {
      n = k + 1u; /* PDU k is carried as a segment */
      partial = 1u;
    } else {
      n = k; /* not even a header fits; PDU k waits for the next grant */
    }
  }

  if (n == 0u) {
    plan->n = 0u;
    plan->tb_used = 0u;
    out->sn_next = in->sn_base & RLC_SN_MASK;
    out->pdu_without_poll = in->pdu_without_poll;
    out->byte_without_poll = in->byte_without_poll;
    out->so_next = 0u;
    out->partial = 0u;
    return 0u;
  }

  /* 4. Fields that are uniform across the plan, then the lane-0 and
        segmented-tail corrections. */
  rlc_vec_subx_u32(plan->seg_len, plan->pdu_len, RLC_AMD_HDR_MIN, n);
  rlc_vec_fill_u32(plan->hdr_len, RLC_AMD_HDR_MIN, n);
  rlc_vec_fill_u32(plan->si, RLC_SI_FULL, n);
  rlc_vec_fill_u32(plan->so, 0u, n);
  rlc_vec_fill_u32(plan->last_seg, 1u, n);

  /* tb_off is the exclusive scan, i.e. cum - pdu_len. */
  rlc_vec_sub_u32(plan->tb_off, plan->cum, plan->pdu_len, n);

  /* SN is base + lane. */
  rlc_vec_iota_add_u32(plan->sn, in->sn_base, RLC_SN_MASK, n);

  /* Lane 0 continues a segmented SDU. */
  if (in->so_first != 0u) {
    plan->hdr_len[0] = hdr0;
    plan->so[0] = in->so_first;
    plan->seg_len[0] = plan->pdu_len[0] - hdr0;
    plan->si[0] = RLC_SI_LAST; /* refined below if it is segmented again */
  }

  /* The trailing PDU is truncated to fill the grant exactly. */
  if (partial) {
    const uint32_t j = n - 1u;
    const uint32_t base = (j == 0u) ? 0u : plan->cum[j - 1u];
    const uint32_t hdr_j = plan->hdr_len[j];
    plan->tb_off[j] = base;
    plan->seg_len[j] = G - base - hdr_j;
    plan->si[j] = (plan->so[j] == 0u) ? RLC_SI_FIRST : RLC_SI_MIDDLE;
    plan->last_seg[j] = 0u;
    so_next = plan->so[j] + plan->seg_len[j];
    plan->tb_used = G;
  } else {
    plan->tb_used = plan->cum[n - 1u];
  }

  /* 5. Poll bits over the final seg_len values. */
  uint32_t pwp = in->pdu_without_poll;
  uint32_t bwp = in->byte_without_poll;
  rlc_plan_polls_vector(plan, in, n, &pwp, &bwp);

  if (in->queue_drained && !partial && !plan->poll[n - 1u]) {
    plan->poll[n - 1u] = 1u;
    pwp = 0u;
    bwp = 0u;
  }

  plan->n = n;
  /* See the note in rlc_plan_compute_scalar(): SN is per SDU, so a trailing
     segment does not consume one. */
  out->sn_next = (in->sn_base + n - partial) & RLC_SN_MASK;
  out->pdu_without_poll = pwp;
  out->byte_without_poll = bwp;
  out->so_next = so_next;
  out->partial = partial;
  return n;
}

/* ------------------------------------------------------------------------ */

uint32_t rlc_plan_compute_checked(rlc_plan_t *plan, rlc_plan_t *ref,
                                  const rlc_plan_in_t *in, rlc_plan_out_t *out,
                                  uint32_t *nbad) {
  rlc_plan_out_t ref_out;
  uint32_t bad = 0u;

  /* The reference needs the same gathered inputs. */
  ref->n_avail = plan->n_avail;
  for (uint32_t i = 0u; i < plan->n_avail; i++) ref->sdu_len[i] = plan->sdu_len[i];

  const uint32_t n_ref = rlc_plan_compute_scalar(ref, in, &ref_out);
  const uint32_t n_vec = rlc_plan_compute_vector(plan, in, out);

  if (n_ref != n_vec) {
    bad++;
  } else {
    for (uint32_t i = 0u; i < n_vec; i++) {
      if (plan->sn[i]       != ref->sn[i])       bad++;
      if (plan->tb_off[i]   != ref->tb_off[i])   bad++;
      if (plan->seg_len[i]  != ref->seg_len[i])  bad++;
      if (plan->so[i]       != ref->so[i])       bad++;
      if (plan->si[i]       != ref->si[i])       bad++;
      if (plan->poll[i]     != ref->poll[i])     bad++;
      if (plan->hdr_len[i]  != ref->hdr_len[i])  bad++;
      if (plan->last_seg[i] != ref->last_seg[i]) bad++;
    }
  }
  if (plan->tb_used            != ref->tb_used)            bad++;
  if (out->sn_next             != ref_out.sn_next)          bad++;
  if (out->pdu_without_poll    != ref_out.pdu_without_poll) bad++;
  if (out->byte_without_poll   != ref_out.byte_without_poll) bad++;
  if (out->so_next             != ref_out.so_next)          bad++;
  if (out->partial             != ref_out.partial)          bad++;

  if (nbad) *nbad = bad;
  return n_vec;
}

uint32_t rlc_plan_compute(rlc_plan_t *plan, const rlc_plan_in_t *in,
                          rlc_plan_out_t *out) {
#if RLC_PLAN_IMPL
  return rlc_plan_compute_vector(plan, in, out);
#else
  return rlc_plan_compute_scalar(plan, in, out);
#endif
}

#endif /* RLC_PLAN_C */
