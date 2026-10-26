// Copyright 2025 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// The full control algorithm on ACTIVE_CORES cores of one group, from the
// inputs to P, ResAllocMap and UserResAllocMap (see ../README.md):
//
//   products     U/R, V and AR1 = A * R1 (uv_matmul), colS of every core,
//                and the U rows that can come near the clamp (it_u_rows; the
//                update pass skips the others)
//   iteration j  every core picks the winner w of iteration j - 1 from the
//                per-core keys and marks its subcarrier; the owner of row w
//                updates its power (it_pu_update). After an odd iteration,
//                the update pass (it_pass), which the owner runs after its
//                pu_update; after an even one, the owner recomputes its
//                colS (P changed in row w only). Then every core: Smax of
//                its own colS, its candidate columns and their exact keys
//                (it_cands), and one barrier. If a pass crossed the clamp
//                margin (rare), the slow path fixes the V columns
//                (it_fix_cols) and redoes colS and the selection. Core 0
//                flips R2[w] one iteration after the pass.
//   finalization the update for the last winner, then the users split over
//                the cores (pu_finalize)
//
// One barrier of the active cores per iteration: the selection of a core
// only reads its own colS, P and V rows and its copy of ResAllocMap. The L1 is
// private to the group (L1D_FOLD_GROUP), so no data leaves the group and
// nothing is flushed. The state is restored before every run, outside the
// timed region; run 0 is the first touch of the inputs, the later runs are
// hot. Each active core checks its rows of P and UserResAllocMap, core 0
// ResAllocMap and the winner of every iteration.

#include <benchmark.h>
#include <snrt.h>
#include <stdio.h>

#include DATAHEADER
#include "kernel/iter.c"
#include "../uv-init/kernel/uv_init.c"

#ifndef ACTIVE_CORES
#define ACTIVE_CORES 1
#endif
#ifndef L1D_FOLD
#define L1D_FOLD L1D_FOLD_GROUP
#endif
#ifndef XBAR_OFFSET
#define XBAR_OFFSET 6
#endif

#define NUM_RUNS 2
// IT_HELPER 1: in an iteration without a pass (only row w of the winner w
// changed, and column k* was taken), a helper core runs the power update of
// row w and the exact key of row w, while the owner of row w selects over
// its other rows only. Its colS then leaves out row w, which is fine as
// the next iteration has a pass and rebuilds every colS. The helper is the
// first core after the owner whose best key of the previous iteration is
// not in column k*, so that key is still exact; every such core reuses its
// key instead of selecting again.
#ifndef IT_HELPER
#define IT_HELPER 1
#endif
// IT_U_LATE 1: the U part of a pass runs in the next iteration (without a
// pass), on the cores other than the owner of its winner, which otherwise
// wait at the barrier. The rank-1 update of V in a pass is exact as long as
// U was within the clamp margin before it (one pass moves U by at most
// max |R1| = 50 = MaxR - margin), so the U update and its margin check are
// only needed before the next pass. Once a late check crosses the margin,
// or if U is already outside it after the products, the passes update U
// first again (and fix the V columns, as before).
#ifndef IT_U_LATE
#define IT_U_LATE 1
#endif
// IT_SPEC 1: in an iteration without a pass, the cores other than the owner
// and the helper, which wait at the barrier, compute the power update of
// their own best key into pspec (it_pu_spec). The next iteration has a pass,
// and if one of those keys wins, its owner only copies the row
// (it_pu_commit) before its pass instead of running the power update.
#ifndef IT_SPEC
#define IT_SPEC 1
#endif
// Iterations of run 0. Fewer than CTRL_ITERS make run 0 a short warm-up of
// the caches (the products and a few iterations); run 1 is measured in full.
#ifndef CTRL_WARM_ITERS
#define CTRL_WARM_ITERS CTRL_ITERS
#endif
#define IPU_LANES 4
// barrier slot of the active cores (slot 0 is the cluster barrier)
#define ACT_BARRIER_SLOT 1
// U = R1 * R2, V = A * R and AR1 = A * R1
#define MAC_PROD                                                               \
  (CTRL_N * CTRL_M * CTRL_N + CTRL_M * CTRL_N * CTRL_N +                       \
   CTRL_M * CTRL_N * CTRL_M)

#define ARR(name, n)                                                           \
  static int32_t name[n] __attribute__((section(".data"), aligned(64)))

ARR(ctrl_U, CTRL_N *CTRL_N);
ARR(ctrl_R, CTRL_N *CTRL_N);
// IT_LAYOUT 1: the L1 interleaves 64 B lines over the 16 cache controllers
// of the group (xbar offset 6), so addresses 1 KiB apart share a controller.
// A row of N = 128 words is 512 B: every row then starts at controller 0 or
// 8 and, with V and P at the same offset, the strips of all cores queue at
// the same 8 controllers. V and P go into one block with P 256 B further
// modulo 1 KiB, and the per-core buffers get a pitch of 16 words more than
// N, so they start at different controllers.
#ifndef IT_LAYOUT
#define IT_LAYOUT 1
#endif
// IT_STAGGER 1: the odd cores run the second strip of columns first in the
// pass and in the colS rebuilds, so that half the cores stream the other
// half of the controllers (see IT_LAYOUT)
#ifndef IT_STAGGER
#define IT_STAGGER 1
#endif
#if IT_LAYOUT
static struct {
  int32_t v[CTRL_M * CTRL_N];
  int32_t pad[(1024 - (CTRL_M * CTRL_N * 4) % 1024 + 256) % 1024 / 4];
  int32_t p[CTRL_M * CTRL_N];
} vp __attribute__((section(".data"), aligned(1024)));
#define ctrl_V vp.v
#define ctrl_P vp.p
#define IT_CP (CTRL_N + 16)
#define IT_TP (UV_VLMAX + 16)
#else
ARR(ctrl_V, CTRL_M *CTRL_N);
ARR(ctrl_P, CTRL_M *CTRL_N);
#define IT_CP CTRL_N
#define IT_TP UV_VLMAX
#endif
ARR(ctrl_G, CTRL_M *CTRL_N);
ARR(ctrl_R2, CTRL_M *CTRL_N);
ARR(ctrl_AR1, CTRL_M *CTRL_LDA_R1);
ARR(zero_row, CTRL_LDA_R1);
ARR(ctrl_ua, CTRL_M *CTRL_N);
ARR(klist, CTRL_M *CTRL_N);
ARR(nalloc, CTRL_M);
ARR(delta, CTRL_M);
// Per-core copies of ResAllocMap and of the index tables of it_cands, so
// that the cores do not all load the same lines every iteration (each core
// marks k* in its own copy; core 0's copy is checked). IT_TBL words each,
// for N <= 128 and the 3 words read past the end.
#define IT_TBL 144
ARR(res_alloc, ACTIVE_CORES *IT_TBL);
ARR(colS, ACTIVE_CORES *IT_CP);
ARR(urows, CTRL_N);
// number of listed U rows of each core
ARR(unum, ACTIVE_CORES);
// the listed U rows of all cores, in order: the pass shares them out evenly
ARR(brows, CTRL_N);
ARR(ubnd, ACTIVE_CORES * 2 * UV_VLMAX);
ARR(kidx, ACTIVE_CORES *IT_TBL);
ARR(uidx, ACTIVE_CORES *IT_TBL);
ARR(lidx, ACTIVE_CORES *IT_TBL);
ARR(scr, ACTIVE_CORES *IT_SCR);
ARR(trk, ACTIVE_CORES *IT_TP);
ARR(winners, CTRL_N * 3);

// One word per core, on its own cache line
typedef struct {
  volatile int32_t v;
  int32_t pad[15];
} it_word_t;

// Set by a core whose pass crossed the clamp margin, read after the barrier
// of that iteration. Passes alternate between the two words; core 0 clears
// the other word at the start of a pass (its last reads were before the
// previous barrier, its next set is a pass later).
static it_word_t uflag[2] __attribute__((section(".data")));
// Set by a core whose late U update (IT_U_LATE) crossed the clamp margin;
// read at the next pass, never cleared within a run
static it_word_t ulate __attribute__((section(".data")));
// s of the last pass of each core, for its late U update
ARR(sbuf, ACTIVE_CORES *IT_CP);
// speculative P row of each core (IT_SPEC)
ARR(pspec, ACTIVE_CORES *IT_CP);
// colS of row w alone, for the helper (IT_HELPER)
ARR(wcolS, ACTIVE_CORES *IT_CP);
// Best key and its column of every core, one cache line per core: every
// core reads all keys after the barrier, and with the keys on one line all
// those loads queued at one L1 bank. Iteration j writes buffer j & 1, which
// is read after its barrier and written again only after the next one.
typedef struct {
  volatile int32_t key, k;
  // iteration of key and k + 1 (IT_SPEC: which keys are already published)
  volatile int32_t it;
  int32_t pad[13];
} it_slot_t;
static it_slot_t slot[2][ACTIVE_CORES]
    __attribute__((section(".data"), aligned(64)));
static int errors[ACTIVE_CORES] __attribute__((section(".data")));
// first mismatch of each core: matrix, offset, got, expected
static int32_t bad[ACTIVE_CORES][4] __attribute__((section(".data")));

// cycles of each run: products, iterations with / without an update pass,
// the last update with the finalization, total
enum { T_PROD, T_A_ODD, T_A_EVEN, T_FIN, T_TOTAL, T_NUM };
// IT_PROF 1: cycles of each phase of the hot iterations, per core, split
// by iterations with and without an update pass, and summed separately over
// the iterations where the core owns the winner
#ifndef IT_PROF
#define IT_PROF 0
#endif
enum { PH_PU, PH_PASS, PH_CANDS, PH_BAR, PH_NUM };
static unsigned int prof[2][ACTIVE_CORES][PH_NUM]
    __attribute__((section(".data")));
static unsigned int prof_own[2][ACTIVE_CORES][PH_NUM + 1]
    __attribute__((section(".data")));
// the same for the iterations where the core is the helper (IT_HELPER)
static unsigned int prof_hlp[ACTIVE_CORES][PH_NUM + 1]
    __attribute__((section(".data")));
static unsigned int cycles[NUM_RUNS][T_NUM] __attribute__((section(".data")));

static void split(unsigned int n, unsigned int cid, unsigned int cores,
                  unsigned int *x0, unsigned int *x1) {
  *x0 = n * cid / cores;
  *x1 = n * (cid + 1) / cores;
}

// the core whose rows of split(n, ., cores) hold row i
static unsigned int split_owner(unsigned int n, unsigned int i,
                                unsigned int cores) {
  unsigned int c = 0;
  while (c + 1 < cores && n * (c + 1) / cores <= i)
    ++c;
  return c;
}

typedef struct {
  uint32_t core_mask, tile_mask;
} active_mask_t;

// Masks of the barrier of harts 0 .. ACTIVE_CORES - 1 (all in group 0)
static active_mask_t active_mask(void) {
  const unsigned int cpt = snrt_cluster_core_per_tile();
  active_mask_t m = {0, 0};
  for (unsigned int h = 0; h < ACTIVE_CORES && h < cpt; ++h)
    m.core_mask |= 1u << h;
  const unsigned int tiles = (ACTIVE_CORES + cpt - 1) / cpt;
  m.tile_mask = tiles > 1 ? (1u << tiles) - 1 : SNRT_BARRIER_TILE_MASK_SELF;
  return m;
}

static inline void abar(active_mask_t m) {
  snrt_cluster_group_barrier(m.core_mask, m.tile_mask, 1, ACT_BARRIER_SLOT);
}

static int check(int32_t *first, int32_t name, const int32_t *got,
                 const int32_t *exp, unsigned int i0, unsigned int i1) {
  int err = 0;
  for (unsigned int i = i0; i < i1; ++i) {
    if (got[i] != exp[i]) {
      if (err == 0 && first[0] == 0) {
        first[0] = name;
        first[1] = (int32_t)i;
        first[2] = got[i];
        first[3] = exp[i];
      }
      ++err;
    }
  }
  return err;
}

int main() {
  const unsigned int cid = snrt_cluster_vpu_idx();
  const int active = snrt_cluster_is_primary() && cid < ACTIVE_CORES;
  const active_mask_t amask = active_mask();
  unsigned int u0, u1, v0, v1, k0, k1;
  split(CTRL_N, cid, ACTIVE_CORES, &u0, &u1);
  split(CTRL_M, cid, ACTIVE_CORES, &v0, &v1);
  split(CTRL_N, cid, ACTIVE_CORES, &k0, &k1);
  int32_t *my_colS = colS + cid * IT_CP;
  const unsigned int stag = IT_STAGGER ? (cid & 1) : 0;

  snrt_cluster_hw_barrier();
  if (cid == 0 &&
      ACTIVE_CORES > snrt_cluster_vpu_num() / snrt_cluster_group_num())
    printf("warning: %u cores span more than one group\n", ACTIVE_CORES);
  if (XBAR_OFFSET)
    l1d_xbar_config(XBAR_OFFSET);
  l1d_part_folded(snrt_cluster_vpu_per_tile(), L1D_FOLD);
  int32_t *my_ra = res_alloc + cid * IT_TBL, *my_kidx = kidx + cid * IT_TBL;
  int32_t *my_uidx = uidx + cid * IT_TBL, *my_lidx = lidx + cid * IT_TBL;
  if (cid == 0)
    pu_init_tab();
  if (active) {
    for (unsigned int i = 0; i < IT_TBL; ++i) {
      my_kidx[i] = 127 - (int32_t)i;
      my_uidx[i] = 127 - (int32_t)i;
      my_lidx[i] = (int32_t)i;
    }
    snrt_fence_snitch();
  }
  snrt_cluster_hw_barrier();

#pragma clang loop unroll(disable)
  for (int run = 0; run < NUM_RUNS; ++run) {
    // Restore the input state of this core's rows
    if (active) {
      for (unsigned int i = v0 * CTRL_N; i < v1 * CTRL_N; ++i) {
        ctrl_R2[i] = ctrl_R2_in[i];
        ctrl_P[i] = CTRL_P_SCALE;
        ctrl_ua[i] = 0;
      }
      for (unsigned int i = v0; i < v1; ++i) {
        nalloc[i] = 0;
        delta[i] = CTRL_P_SCALE;
      }
      for (unsigned int k = 0; k < IT_TBL; ++k) {
        my_ra[k] = 0;
        my_kidx[k] = 127 - (int32_t)k;
      }
      if (cid == 0) {
        uflag[0].v = 0;
        uflag[1].v = 0;
        for (unsigned int c = 0; c < ACTIVE_CORES; ++c) {
          slot[0][c].it = 0;
          slot[1][c].it = 0;
        }
        ulate.v = 0;
      }
      snrt_fence_snitch();
    }
    snrt_cluster_hw_barrier();

    if (active) {
      // per core, so the laps of the cores do not race; core 0 reports
      unsigned int cyc[T_NUM] = {0};
      unsigned int t = benchmark_get_cycle(), t0 = t, tn;
#define LAP(slot)                                                              \
  do {                                                                         \
    tn = benchmark_get_cycle();                                                \
    cyc[slot] += tn - t;                                                       \
    t = tn;                                                                    \
  } while (0)

      // Products and the column maxima of S
      uv_matmul(ctrl_U, ctrl_R, ctrl_R1, ctrl_R2, ctrl_C, CTRL_N, u0, u1, 0,
                CTRL_N, CTRL_M, CTRL_LDA_R1, CTRL_N, UV_MODE_U);
      // this core's U rows that can come near the clamp
      unsigned int nu = it_u_rows(urows + u0, ctrl_C, ctrl_R1, u0, u1,
                                  CTRL_M, CTRL_LDA_R1, CTRL_N,
                                  ubnd + cid * 2 * UV_VLMAX);
      unum[cid] = (int32_t)nu;
      // the late U updates assume U within the margin before the first pass
      if (IT_U_LATE && it_u_check(ctrl_U, urows + u0, nu, CTRL_N,
                                  trk + cid * IT_TP))
        ulate.v = 1;
      int u_exact = 0;
      snrt_fence();
      abar(amask);
      // V and AR1 without their clamped copies (G is recomputed from V
      // where it is used, see it_g_rows)
      uv_matmul(ctrl_V, ctrl_V, ctrl_A, ctrl_R, ctrl_D, 0, v0, v1, 0, CTRL_N,
                CTRL_N, CTRL_LDA_A, CTRL_N, UV_MODE_RAW);
      uv_matmul(ctrl_AR1, ctrl_AR1, ctrl_A, ctrl_R1, zero_row, 0, v0, v1, 0,
                CTRL_M, CTRL_N, CTRL_LDA_A, CTRL_LDA_R1, UV_MODE_RAW);
      it_s_rows(my_colS, ctrl_P, ctrl_V, v0, v1, CTRL_M, CTRL_N, stag);
      // this core's share [b0, b1) of all the listed U rows: their number
      // differs between the blocks, so the pass would be unbalanced with
      // the own rows only (each core fills its own part of brows)
      unsigned int nall = 0;
      for (unsigned int c = 0; c < ACTIVE_CORES; ++c)
        nall += (unsigned int)unum[c];
      unsigned int b0, b1;
      split(nall, cid, ACTIVE_CORES, &b0, &b1);
      for (unsigned int c = 0, base = 0; c < ACTIVE_CORES; ++c) {
        const unsigned int n = (unsigned int)unum[c];
        unsigned int c0, c1;
        split(CTRL_N, c, ACTIVE_CORES, &c0, &c1);
        for (unsigned int i = 0; i < n; ++i)
          if (base + i >= b0 && base + i < b1)
            brows[base + i] = urows[c0 + i];
        base += n;
      }
      const int32_t *prows = brows + b0;
      unsigned int pn = b1 - b0;
      // U updated in the pass itself (else one iteration later), and a late
      // U update pending for the pass won by user late_w
      int u_eager = !IT_U_LATE;
      int late = 0;
      unsigned int late_w = 0;
      // the late U updates read the shares of the other cores
      snrt_fence_snitch();
      abar(amask);
      LAP(T_PROD);

      // The winner w of iteration j - 1 is applied in iteration j: its power,
      // and after an odd iteration the update pass, whose R2[w] flip waits
      // for the next iteration (every core has read R2[w] by then).
      unsigned int q = 0, flip_w = 0;
      int flip = 0;
      // the speculative power update of this core (IT_SPEC): user, column
      // (-1 if none), Delta and P[w][k]
      int spec_k = -1;
      unsigned int spec_w = 0;
      int32_t spec_d = 0, spec_pk = 0;
      int32_t *my_spec = pspec + cid * IT_CP;
      const unsigned int iters = run ? CTRL_ITERS : CTRL_WARM_ITERS;
#pragma clang loop unroll(disable)
      for (unsigned int j = 0; j <= iters; ++j) {
        const int pass = j > 0 && ((j - 1) & 1);
        int was_owner = 0;
        unsigned int pt = benchmark_get_cycle();
#if IT_CPROF
        it_cprof_on[cid] = run == NUM_RUNS - 1 && j > 0 && j < iters;
#endif
#define PROF(ph)                                                               \
  do {                                                                         \
    if (IT_PROF && run == NUM_RUNS - 1 && j > 0 && j < iters) {               \
      const unsigned int pn = benchmark_get_cycle();                           \
      prof[pass][cid][ph] += pn - pt;                                          \
      if (was_owner)                                                           \
        prof_own[pass][cid][ph] += pn - pt;                                    \
      if (helper)                                                              \
        prof_hlp[cid][ph] += pn - pt;                                          \
      pt = pn;                                                                 \
    }                                                                          \
  } while (0)
        if (flip && cid == 0)
          it_flip_r2(ctrl_R2, flip_w, CTRL_N);
        flip = 0;
        // roles in an iteration without a pass (IT_HELPER): this core's key
        // of the previous iteration is reused, the owner leaves out row
        // skip_w, the helper adds the key of row w
        int reuse = 0, helper = 0, owner_now = 0;
        int32_t reuse_key = -1;
        int reuse_k = -1;
        unsigned int skip_w = CTRL_M, row_w = 0;
        if (j > 0) {
          // the cores hold different users, so their keys never tie
          const it_slot_t *ks = slot[(j - 1) & 1];
          int32_t kv[ACTIVE_CORES];
#pragma clang loop unroll(full)
          for (unsigned int c = 0; c < ACTIVE_CORES; ++c)
            kv[c] = ks[c].key;
          int32_t best = kv[0];
          unsigned int bc = 0;
#pragma clang loop unroll(full)
          for (unsigned int c = 1; c < ACTIVE_CORES; ++c)
            if (kv[c] > best) {
              best = kv[c];
              bc = c;
            }
          const int bk = ks[bc].k;
          const unsigned int w = 127 - (best & 127);
          if (cid == 0) {
            winners[3 * (j - 1)] = (int32_t)w;
            winners[3 * (j - 1) + 1] = bk;
            winners[3 * (j - 1) + 2] = best >> KEY_USER_BITS;
          }
          // every core marks k* itself (the owner's pu_update stores the
          // same 1), so the selection below needs no barrier
          my_ra[bk] = 1;
          it_take(my_kidx, (unsigned int)bk);
          const int owner = w >= v0 && w < v1;
          owner_now = owner;
          const unsigned int oc = split_owner(CTRL_M, w, ACTIVE_CORES);
          int hc = -1;
          if (IT_HELPER && !pass && ACTIVE_CORES > 1) {
            for (unsigned int d = 1; d < ACTIVE_CORES; ++d) {
              const unsigned int c = (oc + d) % ACTIVE_CORES;
              if (ks[c].k != bk) {
                hc = (int)c;
                break;
              }
            }
            reuse = !owner && ks[cid].k != bk;
            reuse_key = ks[cid].key;
            reuse_k = ks[cid].k;
            helper = hc == (int)cid;
            if (owner && hc >= 0)
              skip_w = w;
            row_w = w;
          }
          if (owner && pass && spec_k == bk && spec_w == w) {
            it_pu_commit(ctrl_P + w * CTRL_N, my_spec, ctrl_ua + w * CTRL_N,
                         klist + w * CTRL_N, &nalloc[w], bk, CTRL_N, spec_pk);
            delta[w] = spec_d;
          } else if (hc >= 0 ? helper : owner) {
            delta[w] = it_pu_update(ctrl_P + w * CTRL_N, ctrl_V + w * CTRL_N,
                                    my_ra, ctrl_ua + w * CTRL_N,
                                    klist + w * CTRL_N, &nalloc[w], bk,
                                    CTRL_N);
          }
          // P[w][k] and res_alloc[k*] are scalar stores; vector loads follow
          snrt_fence_snitch();
          was_owner = owner;
          if (IT_PROF && owner && run == NUM_RUNS - 1 && j < iters)
            prof_own[pass][cid][PH_NUM] += 1;
          if (IT_PROF && helper && run == NUM_RUNS - 1 && j < iters)
            prof_hlp[cid][PH_NUM] += 1;
          PROF(PH_PU);
          if (pass) {
            // flag word q & 1; the other one was last read before the
            // previous barrier
            if (cid == 0)
              uflag[(q & 1) ^ 1].v = 0;
            // a late check crossed the margin: from now on as before
            if (!u_eager && ulate.v)
              u_eager = 1;
            // the owner's pass reads the new P row after its pu_update
            if (it_pass(ctrl_U, ctrl_V, ctrl_P, my_colS, ctrl_R1, ctrl_AR1,
                        ctrl_R2, w, prows, u_eager ? pn : 0, v0, v1,
                        CTRL_LDA_R1, CTRL_N, trk + cid * IT_TP,
                        u_eager ? 0 : sbuf + cid * IT_CP, stag))
              uflag[q & 1].v = 1;
            late = !u_eager;
            late_w = w;
            flip = 1;
            flip_w = w;
          } else {
            if (owner && j < iters)
              it_s_rows(my_colS, ctrl_P, ctrl_V, v0, v1, skip_w, CTRL_N, stag);
            // the late U update of the last pass, all listed rows shared
            // over the cores other than the owner (U is not used after the
            // last iteration)
            if (late && j < iters &&
                ((!owner && !helper) || ACTIVE_CORES == 1)) {
              // ranks of the cores other than the owner and the helper
              unsigned int parts = 0, rank = 0;
              for (unsigned int c = 0; c < ACTIVE_CORES; ++c)
                if (c != oc && (int)c != hc) {
                  rank += c < cid;
                  ++parts;
                }
              if (!parts) {
                parts = 1;
                rank = 0;
              }
              unsigned int r0, r1;
              split(nall * IT_U_STRIPS(CTRL_N), rank, parts, &r0, &r1);
              if (it_u_late(ctrl_U, ctrl_R1, sbuf + cid * IT_CP, late_w,
                            brows, r0, r1, CTRL_LDA_R1, CTRL_N,
                            trk + cid * IT_TP))
                ulate.v = 1;
            }
            late = 0;
          }
          PROF(PH_PASS);
        }

        // Candidates and exact keys of this core's rows: they only read
        // this core's colS, P and V rows and res_alloc
        int kb = -1;
        int32_t key = -1;
        if (j < iters && v1 > v0) {
          if (reuse) {
            key = reuse_key;
            kb = reuse_k;
          } else {
            key = it_cands(my_colS, ctrl_P, ctrl_V, my_kidx, my_uidx,
                           my_lidx, v0, v1, skip_w, CTRL_N,
                           scr + cid * IT_SCR, &kb);
          }
        }
        if (helper && j < iters) {
          // the exact key of row w, from its new P
          int32_t *wc = wcolS + cid * IT_CP;
          int kw = -1;
          it_s_rows(wc, ctrl_P, ctrl_V, row_w, row_w + 1, CTRL_M, CTRL_N, stag);
          const int32_t keyw =
              it_cands(wc, ctrl_P, ctrl_V, my_kidx, my_uidx, my_lidx,
                       row_w, row_w + 1, CTRL_M, CTRL_N, scr + cid * IT_SCR,
                       &kw);
          if (keyw > key) {
            key = keyw;
            kb = kw;
          }
        }
        slot[j & 1][cid].key = key;
        slot[j & 1][cid].k = kb;
        slot[j & 1][cid].it = (int32_t)(j + 1);
        snrt_fence();
        spec_k = -1;
        // only for an odd j: the next iteration has a pass. Only if no key
        // published so far in this iteration is larger: the winner always
        // passes, and most other cores skip the work.
        int spec = IT_SPEC && (j & 1) && j < iters && key >= 0 && !owner_now &&
                   !helper;
        if (spec) {
          const it_slot_t *ks = slot[j & 1];
          for (unsigned int c = 0; c < ACTIVE_CORES; ++c)
            if (ks[c].it == (int32_t)(j + 1) && ks[c].key > key)
              spec = 0;
        }
        if (spec) {
          spec_w = 127 - (unsigned int)(key & 127);
          spec_k = kb;
          spec_d = it_pu_spec(my_spec, ctrl_P + spec_w * CTRL_N,
                              ctrl_V + spec_w * CTRL_N, my_ra,
                              klist + spec_w * CTRL_N, &nalloc[spec_w],
                              (unsigned int)kb, CTRL_N, &spec_pk);
        }
        PROF(PH_CANDS);
        abar(amask);
        PROF(PH_BAR);

        // Slow path (rare): a U element crossed the clamp margin in this
        // pass, so fix the V columns and redo colS and the selection
        if (pass && uflag[q & 1].v) {
          if (!u_exact) {
            // first fix-up: the skipped U rows are stale, so recompute this
            // core's rows (R2 before the flip of row w, then the update of
            // this pass) and update all of them from now on
            uv_matmul(ctrl_U, ctrl_R, ctrl_R1, ctrl_R2, ctrl_C, CTRL_N, u0,
                      u1, 0, CTRL_N, CTRL_M, CTRL_LDA_R1, CTRL_N, UV_MODE_U);
            nu = 0;
            for (unsigned int l = u0; l < u1; ++l)
              urows[u0 + nu++] = (int32_t)l;
            it_u_part(ctrl_U, ctrl_R1, ctrl_R2 + flip_w * CTRL_N, flip_w,
                      urows + u0, nu, CTRL_LDA_R1, CTRL_N);
            prows = urows + u0;
            pn = nu;
            snrt_fence();
            u_exact = 1;
            abar(amask);
          }
          it_fix_cols(ctrl_V, ctrl_U, ctrl_A, ctrl_D, k0, k1, CTRL_M, CTRL_N,
                      CTRL_LDA_A);
          abar(amask);
          if (j < iters) {
            it_s_rows(my_colS, ctrl_P, ctrl_V, v0, v1, CTRL_M, CTRL_N, stag);
            if (v1 > v0)
              key = it_cands(my_colS, ctrl_P, ctrl_V, my_kidx,
                             my_uidx, my_lidx, v0, v1, CTRL_M, CTRL_N,
                             scr + cid * IT_SCR, &kb);
            slot[j & 1][cid].key = key;
            slot[j & 1][cid].k = kb;
            snrt_fence();
            abar(amask);
          }
        }
        if (pass)
          ++q;
        if (j == iters)
          break;
        if (pass)
          LAP(T_A_ODD);
        else
          LAP(T_A_EVEN);
      }

      // Finalization of this core's users (with the last update above)
      it_g_rows(ctrl_G, ctrl_V, v0, v1, CTRL_N);
      pu_finalize(ctrl_P, ctrl_G, klist, nalloc, delta, v0, v1, CTRL_N);
      snrt_fence_snitch();
      abar(amask);
      LAP(T_FIN);
      cyc[T_TOTAL] = t - t0;
      if (cid == 0)
        for (int i = 0; i < T_NUM; ++i)
          cycles[run][i] = cyc[i];
#undef LAP
    }
    snrt_cluster_hw_barrier();
  }

  if (cid == 0) {
    // iteration j applies the winner of j - 1: an update pass for j - 1 odd
    const unsigned int odd = (CTRL_ITERS - 1) / 2;
    const unsigned int even = CTRL_ITERS - odd;
    printf("control algorithm, M %u N %u, %u iterations, %u cores, L1 %s "
           "xbar %d\n",
           CTRL_M, CTRL_N, CTRL_ITERS, ACTIVE_CORES,
           L1D_FOLD == L1D_FOLD_TILE ? "tile" : "group", XBAR_OFFSET);
    for (int run = 0; run < NUM_RUNS; ++run) {
      unsigned int *c = cycles[run];
      if (!run && CTRL_WARM_ITERS != CTRL_ITERS) {
        printf("run 0 (warm-up, %u iterations): products %u cycles\n",
               CTRL_WARM_ITERS, c[T_PROD]);
        continue;
      }
      printf("run %d (%s): total %u cycles (TTI 500000)\n", run,
             run ? "hot" : "first touch", c[T_TOTAL]);
      printf("  products %u (IPU util %u permille), finalization %u\n",
             c[T_PROD],
             (unsigned int)(1000ULL * MAC_PROD /
                            ((unsigned long long)c[T_PROD] * IPU_LANES *
                             ACTIVE_CORES)),
             c[T_FIN]);
      printf("  per iteration: %u with an update pass, %u without\n",
             odd ? c[T_A_ODD] / odd : 0, even ? c[T_A_EVEN] / even : 0);
    }
    if (IT_PROF) {
      // hot iterations 1 .. CTRL_ITERS - 1 (iteration 0 has no winner)
      const unsigned int np = (CTRL_ITERS - 1) / 2, nn = CTRL_ITERS / 2;
      for (int ps = 1; ps >= 0; --ps) {
        const unsigned int ni = ps ? np : nn;
        printf("%s pass, cycles per iteration: core pu pass cands barrier\n",
               ps ? "with" : "without");
        for (unsigned int c = 0; c < ACTIVE_CORES; ++c)
          printf("  %2u %5u %5u %5u %5u\n", c, prof[ps][c][PH_PU] / ni,
                 prof[ps][c][PH_PASS] / ni, prof[ps][c][PH_CANDS] / ni,
                 prof[ps][c][PH_BAR] / ni);
        unsigned int own[PH_NUM + 1] = {0};
        for (unsigned int c = 0; c < ACTIVE_CORES; ++c)
          for (int h = 0; h <= PH_NUM; ++h)
            own[h] += prof_own[ps][c][h];
        if (own[PH_NUM])
          printf("  owner %5u %5u %5u %5u (%u iterations)\n",
                 own[PH_PU] / own[PH_NUM], own[PH_PASS] / own[PH_NUM],
                 own[PH_CANDS] / own[PH_NUM], own[PH_BAR] / own[PH_NUM],
                 own[PH_NUM]);
      }
      unsigned int hlp[PH_NUM + 1] = {0};
      for (unsigned int c = 0; c < ACTIVE_CORES; ++c)
        for (int h = 0; h <= PH_NUM; ++h)
          hlp[h] += prof_hlp[c][h];
      if (hlp[PH_NUM])
        printf("  helper %5u %5u %5u %5u (%u iterations)\n",
               hlp[PH_PU] / hlp[PH_NUM], hlp[PH_PASS] / hlp[PH_NUM],
               hlp[PH_CANDS] / hlp[PH_NUM], hlp[PH_BAR] / hlp[PH_NUM],
               hlp[PH_NUM]);
    }
#if IT_CPROF
    printf("it_cands per call: core calls top2 ckeys exact cols%% single%%\n");
    for (unsigned int c = 0; c < ACTIVE_CORES; ++c) {
      const unsigned int *cp = it_cprof[c], n = cp[CP_CALLS] ? cp[CP_CALLS] : 1;
      printf("  %2u %4u %5u %5u %5u %4u %4u\n", c, cp[CP_CALLS],
             cp[CP_BEST] / n, cp[CP_CKEY] / n, cp[CP_EXACT] / n,
             100 * cp[CP_COLS] / n, 100 * cp[CP_SINGLE] / n);
    }
#endif
  }

  // Each active core checks its rows; core 0 also the global results
  if (active) {
    int32_t *b = bad[cid];
    int err = check(b, 'P', ctrl_P, ctrl_P_exp, v0 * CTRL_N, v1 * CTRL_N);
    err += check(b, 'U', ctrl_ua, ctrl_ua_exp, v0 * CTRL_N, v1 * CTRL_N);
    if (cid == 0) {
      err += check(b, 'A', res_alloc, ctrl_res_exp, 0, CTRL_N);
      err += check(b, 'W', winners, ctrl_win_exp, 0, 3 * CTRL_ITERS);
    }
    errors[cid] = err;
    snrt_fence_snitch();
  }
  snrt_cluster_hw_barrier();

  int total = 0;
  if (cid == 0) {
    for (unsigned int c = 0; c < ACTIVE_CORES; ++c) {
      if (errors[c]) {
        const int32_t o = bad[c][1];
        if (bad[c][0] == 'W')
          printf("core %u: %d mismatches, first winner of iteration %d "
                 "(field %d) = %d, expected %d\n",
                 c, errors[c], o / 3, o % 3, bad[c][2], bad[c][3]);
        else
          printf("core %u: %d mismatches, first %c[%d] = %d, expected %d "
                 "(U = UserResAllocMap, A = ResAllocMap)\n",
                 c, errors[c], (char)bad[c][0], o, bad[c][2], bad[c][3]);
      }
      total += errors[c];
    }
    printf(total ? "Check Failed!\n" : "Check passed.\n");
  }
  snrt_cluster_hw_barrier();
  return total ? -1 : 0;
}
