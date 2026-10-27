// Copyright 2025 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Iteration kernels of the full control algorithm (see ../../README.md),
// with the gain evaluated lazily.
//
// Gain = ilog(S), S = P * G, is only used by the selection, and ilog is
// non-decreasing in S (checked exhaustively for 0 <= S < 2^27, which holds S
// for every allowed input). Its widest step is below 1.6e-5 * S, so with
// Smax the largest S over the free subcarriers, every element whose Gain
// equals the largest Gain has S >= Smax - (Smax >> 14) - 2. The kernels
// therefore keep only the column maxima of S, and evaluate ilog exactly on
// the elements of the candidate columns (column maximum at or above that
// threshold). The winner is the same as with the gain of every element,
// ties included (largest Gain, then the lowest user, then the lowest
// subcarrier).
//
// Per core and column, colS[c][k] = max of S over the core's rows. The
// selection then runs on all cores:
//
//   it_cands     every core: Smax of its own colS over the free columns
//                (slide tree), then its candidate columns and the exact
//                keys Gain << 7 | (127 - i) of its rows in those columns;
//                best key and column per core. The winner is the best key
//                over the cores, so no merge of the cores' colS is needed.
//
// The maxima use vredmax (IT_REDMAX), or vslidedown + vmax trees on a VFU
// without the reduction tree.

#include <stdint.h>

#include "control.h"
#include "../../gain-select/kernel/gain_select.c"
#include "../../power-update/kernel/power_update.c"

static inline unsigned int it_vl(unsigned int n) {
  unsigned int avl = n < UV_VLMAX ? n : UV_VLMAX;
  unsigned int vl;
  asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(avl));
  return vl;
}

static inline unsigned int it_up4(unsigned int n) { return (n + 3) & ~3u; }

// Largest |U| that cannot make an R clamp bind across one update pass
// (|R1| <= 50)
#define IT_MARGIN (CTRL_MAX_R - 50)

// s = 1 - 2 * R2[w][p ..] into vs
#define IT_SIGN(vs, r2w)                                                       \
  do {                                                                         \
    asm volatile("vle32.v " vs ", (%0)" ::"r"(r2w));                           \
    asm volatile("vadd.vv " vs ", " vs ", " vs);                               \
    asm volatile("vrsub.vi " vs ", " vs ", 1");                                \
  } while (0)

// U row += c * s, then fold it into the max (v8) and min (v12) trackers
#define IT_U_ROW(vu, vs, row, c)                                               \
  do {                                                                         \
    asm volatile("vle32.v " vu ", (%0)" ::"r"(row));                           \
    asm volatile("vmacc.vx " vu ", %0, " vs ::"r"(c));                         \
    asm volatile("vse32.v " vu ", (%0)" ::"r"(row) : "memory");                \
    asm volatile("vmax.vv v8, v8, " vu);                                       \
    asm volatile("vmin.vv v12, v12, " vu);                                     \
  } while (0)

// 1 if one of the n words of trk is above the clamp margin. The loads are
// independent, so IT_SCAN of them are kept in flight.
#define IT_SCAN 8
static inline int it_flag_scan(const int32_t *trk, unsigned int n) {
  const volatile int32_t *t = trk;
  int flag = 0;
  unsigned int k = 0;
  for (; k + IT_SCAN <= n; k += IT_SCAN) {
    int32_t x[IT_SCAN];
#pragma clang loop unroll(full)
    for (unsigned int j = 0; j < IT_SCAN; ++j)
      x[j] = t[k + j];
#pragma clang loop unroll(full)
    for (unsigned int j = 0; j < IT_SCAN; ++j)
      flag |= x[j] > IT_MARGIN;
  }
  for (; k < n; ++k)
    flag |= t[k] > IT_MARGIN;
  return flag;
}

// R2[w] = 1 - R2[w]; one core, after every core has read the old row
void it_flip_r2(int32_t *R2, unsigned int w, unsigned int N) {
  int32_t *r2w = R2 + w * N;
  for (unsigned int p = 0; p < N;) {
    const unsigned int vl = it_vl(N - p);
    asm volatile("vle32.v v0, (%0)" ::"r"(r2w + p));
    asm volatile("vrsub.vi v0, v0, 1");
    asm volatile("vse32.v v0, (%0)" ::"r"(r2w + p) : "memory");
    p += vl;
  }
}

// Every vector op of the selection runs at a vl that is a multiple of 4 (the
// IPU lanes): with other lengths, the slide trees below gave wrong maxima on
// Spatz, and vloxei32 hangs (see power_update.c).

// Lanes [n, it_up4(n)) of vk set to -1 (neutral for the maxima here), at vl
// it_up4(n); lidx[i] = i, v4 scratch
#define IT_PAD(vk, n, lidx)                                                    \
  do {                                                                         \
    if ((n) & 3) {                                                             \
      asm volatile("vle32.v v4, (%0)" ::"r"(lidx));                            \
      asm volatile("vsub.vx v4, v4, %0" ::"r"(n));                             \
      asm volatile("vsra.vi v4, v4, 31");                                      \
      asm volatile("vxor.vi v4, v4, -1");                                      \
      asm volatile("vor.vv " vk ", " vk ", v4");                               \
    }                                                                          \
  } while (0)

// IT_REDMAX 1: the maxima use vredmax (the reduction tree of the VFU)
// instead of the slide trees below. IT_RED_VMV 1 reads the result with
// vmv.x.s, 0 through memory.
#ifndef IT_REDMAX
#define IT_REDMAX 1
#endif
#ifndef IT_RED_VMV
#define IT_RED_VMV 1
#endif

// Max of the first n elements of v0 with vredmax (v0 is its own start
// value); v4 is scratch, tmp one word
static inline int32_t it_red_max(unsigned int n, int32_t *tmp) {
  it_vl(n);
  asm volatile("vredmax.vs v4, v0, v0");
  if (IT_RED_VMV) {
    int32_t r;
    asm volatile("vmv.x.s %0, v4" : "=r"(r));
    return r;
  }
  it_vl(1);
  asm volatile("vse32.v v4, (%0)" ::"r"(tmp) : "memory");
  snrt_fence_spatz();
  return *(const volatile int32_t *)tmp;
}

// Max of the first n elements of v0 (n a multiple of 4, 4 <= n <= UV_VLMAX),
// through tmp (four words); v4 is scratch. Halving steps of multiples of 4
// down to four lanes, then a scalar max. The slide runs at vl = n, so its
// whole source is below vl; vslidedown reads ahead of the element it writes
// and must not chain on its producer (prevent_chaining in
// spatz_controller.sv).
static inline int32_t it_tree_max(unsigned int n, int32_t *tmp) {
  if (IT_REDMAX)
    return it_red_max(n, tmp);
  while (n > 4) {
    const unsigned int h = it_up4(n / 2);
    it_vl(n);
    asm volatile("vslidedown.vx v4, v0, %0" ::"r"(h));
    it_vl(n - h);
    asm volatile("vmax.vv v0, v0, v4");
    n = h;
  }
  it_vl(4);
  asm volatile("vse32.v v0, (%0)" ::"r"(tmp) : "memory");
  snrt_fence_spatz();
  const volatile int32_t *t = tmp;
  int32_t a = t[0], b = t[1], c = t[2], d = t[3];
  a = a > b ? a : b;
  c = c > d ? c : d;
  return a > c ? a : c;
}

// Largest and second largest of the first n lanes of v0 and v8 together,
// where every lane of v8 is at most the same lane of v0 and the lanes of v0
// are distinct or -1 (n as in it_tree_max). v4, v12 and v16 are scratch,
// tmp eight words.
static inline int32_t it_tree_top2(unsigned int n, int32_t *tmp,
                                   int32_t *second) {
  if (IT_REDMAX) {
    // top, then the max of v8 and of v0 without the top lane (the lanes of
    // v0 are distinct, so only the top lane is set, to 0: a second of 0
    // only makes it_cands take the general path)
    const int32_t m = it_red_max(n, tmp);
    it_vl(n);
    asm volatile("vsub.vx v4, v0, %0" ::"r"(m));
    asm volatile("vsra.vi v4, v4, 31");
    asm volatile("vand.vv v0, v0, v4");
    asm volatile("vmax.vv v0, v0, v8");
    *second = it_red_max(n, tmp);
    return m;
  }
  while (n > 4) {
    const unsigned int h = it_up4(n / 2);
    it_vl(n);
    asm volatile("vslidedown.vx v4, v0, %0" ::"r"(h));
    asm volatile("vslidedown.vx v12, v8, %0" ::"r"(h));
    it_vl(n - h);
    asm volatile("vmin.vv v16, v0, v4");
    asm volatile("vmax.vv v0, v0, v4");
    asm volatile("vmax.vv v12, v8, v12");
    asm volatile("vmax.vv v8, v16, v12");
    n = h;
  }
  it_vl(4);
  asm volatile("vse32.v v0, (%0)" ::"r"(tmp) : "memory");
  asm volatile("vse32.v v8, (%0)" ::"r"(tmp + 4) : "memory");
  snrt_fence_spatz();
  const volatile int32_t *t = tmp;
  int32_t a[4], b[4];
  for (int i = 0; i < 4; ++i) {
    a[i] = t[i];
    b[i] = t[4 + i];
  }
  int32_t m = a[0] > a[1] ? a[0] : a[1];
  const int32_t m23 = a[2] > a[3] ? a[2] : a[3];
  m = m > m23 ? m : m23;
  int32_t s = b[0] > b[1] ? b[0] : b[1];
  const int32_t s23 = b[2] > b[3] ? b[2] : b[3];
  s = s > s23 ? s : s23;
  for (int i = 0; i < 4; ++i)
    if (a[i] != m && a[i] > s)
      s = a[i];
  *second = s;
  return m;
}

// G = clamp(V >> G_SHIFT, MinG, MaxG) in place
#define IT_G_OF_V(vv)                                                          \
  do {                                                                         \
    asm volatile("vsra.vi " vv ", " vv ", %0" ::"i"(CTRL_G_SHIFT));            \
    asm volatile("vmax.vx " vv ", " vv ", %0" ::"r"(CTRL_MIN_G));              \
    asm volatile("vmin.vx " vv ", " vv ", %0" ::"r"(CTRL_MAX_G));              \
  } while (0)

// V row += a * s, then S = P * clamp(V >> G_SHIFT) folded into the column
// maxima acc. G is not stored: the pass is bound by the L1 bandwidth of the
// group, and G follows from V wherever it is needed (it_g_rows). (Loading
// the next row before this row's stores, with two buffers, was slower.)
#define IT_VS_ROW(acc, vs, vrow, prow, a)                                      \
  do {                                                                         \
    asm volatile("vle32.v v4, (%0)" ::"r"(vrow));                              \
    asm volatile("vle32.v v0, (%0)" ::"r"(prow));                              \
    asm volatile("vmacc.vx v4, %0, " vs ::"r"(a));                             \
    asm volatile("vse32.v v4, (%0)" ::"r"(vrow) : "memory");                   \
    IT_G_OF_V("v4");                                                           \
    asm volatile("vmul.vv v0, v0, v4");                                        \
    asm volatile("vmax.vv " acc ", " acc ", v0");                              \
  } while (0)

// G of one V element (scalar)
static inline int32_t it_g_of(int32_t v) {
  int32_t g = v >> CTRL_G_SHIFT;
  g = g < CTRL_MIN_G ? CTRL_MIN_G : g;
  return g > CTRL_MAX_G ? CTRL_MAX_G : g;
}

// The front of one strip of it_pu_update at vl n: inv(G) of V row strip vr
// into vinv (the gather at vl rounded up to 4, see pu_update), and the
// ResAllocMap and P strips into vra and vp
#define IT_PU_FRONT(vi, vinv, vra, vp, vr, ra, pr, n)                          \
  do {                                                                         \
    it_vl(it_up4(n));                                                          \
    asm volatile("vle32.v " vi ", (%0)" ::"r"(vr));                            \
    asm volatile("vsra.vi " vi ", " vi ", %0" ::"i"(CTRL_G_SHIFT));            \
    asm volatile("vmax.vx " vi ", " vi ", %0" ::"r"(CTRL_MIN_G));              \
    asm volatile("vminu.vx " vi ", " vi ", %0" ::"r"(PU_TAB_SIZE - 1));        \
    asm volatile("vsll.vi " vi ", " vi ", 2");                                 \
    asm volatile("vloxei32.v " vinv ", (%0), " vi ::"r"(pu_inv_tab));          \
    it_vl(n);                                                                  \
    asm volatile("vle32.v " vra ", (%0)" ::"r"(ra));                           \
    asm volatile("vle32.v " vp ", (%0)" ::"r"(pr));                            \
  } while (0)

// The back of one strip: P = max(0, (sum + inv) / (n + 1) - inv) where free,
// the old P where allocated (vres scratch)
#define IT_PU_BACK(vinv, vra, vp, vres, pr, sum, m, n)                         \
  do {                                                                         \
    it_vl(n);                                                                  \
    asm volatile("vadd.vx " vres ", " vinv ", %0" ::"r"(sum));                 \
    asm volatile("vmulhu.vx " vres ", " vres ", %0" ::"r"(m));                 \
    asm volatile("vsub.vv " vres ", " vres ", " vinv);                         \
    asm volatile("vmax.vx " vres ", " vres ", zero");                          \
    asm volatile("vsub.vv " vp ", " vp ", " vres);                             \
    asm volatile("vmacc.vv " vres ", " vra ", " vp);                           \
    asm volatile("vse32.v " vres ", (%0)" ::"r"(pr) : "memory");               \
  } while (0)

// pu_update (power_update.c) with G taken from the V row of w, so the owner
// does not first store a G row: the table index min(G, 101) is
// min(max(V >> G_SHIFT, MinG), 101). The two strips of the row (N <= 2 *
// UV_VLMAX) use separate registers, so their chains overlap, and the
// division for Delta waits in the shadow of the vector work.
// The vector part of it_pu_update: the new P row of a user with the n - 1
// allocated subcarriers klist[0 .. n - 2] and the new one k (res_alloc[k]
// already 1) into dst (the P row itself, or another buffer), from the old P
// row p_row. Returns Delta and the new P[k] in *pk; dst[k] is not set.
static inline int32_t it_pu_calc(int32_t *dst, const int32_t *p_row,
                                 const int32_t *v_row,
                                 const int32_t *res_alloc,
                                 const int32_t *klist, int32_t n,
                                 unsigned int k, unsigned int N,
                                 int32_t *pk) {
  const unsigned int n0 = N < UV_VLMAX ? N : UV_VLMAX, n1 = N - n0;
  IT_PU_FRONT("v0", "v4", "v8", "v12", v_row, res_alloc, p_row, n0);
  if (n1)
    IT_PU_FRONT("v16", "v20", "v24", "v28", v_row + n0, res_alloc + n0,
                p_row + n0, n1);

  int32_t sum = CTRL_P_SCALE + pu_inv(it_g_of(v_row[k]));
  for (int32_t j = 0; j < n - 1; ++j)
    sum += pu_inv(it_g_of(v_row[klist[j]]));
  const uint32_t m = 0xFFFFFFFFu / (uint32_t)(n + 1) + 1;
  IT_PU_BACK("v4", "v8", "v12", "v0", dst, sum, m, n0);
  if (n1)
    IT_PU_BACK("v20", "v24", "v28", "v16", dst + n0, sum, m, n1);

  const int32_t delta = sum / n;
  const int32_t p = delta - pu_inv(it_g_of(v_row[k]));
  *pk = p > 0 ? p : 0;
  return delta;
}

int32_t it_pu_update(int32_t *p_row, const int32_t *v_row, int32_t *res_alloc,
                     int32_t *ua_row, int32_t *klist, int32_t *nalloc,
                     unsigned int k, unsigned int N) {
  res_alloc[k] = 1;
  ua_row[k] = 1;
  const int32_t n = *nalloc + 1;
  klist[n - 1] = k;
  *nalloc = n;
  // the vector loads below must see ResAllocMap[k] = 1
  snrt_fence_snitch();
  int32_t pk;
  const int32_t delta =
      it_pu_calc(p_row, p_row, v_row, res_alloc, klist, n, k, N, &pk);
  // P[w][k] after the vector store of the same row
  snrt_fence_spatz();
  p_row[k] = pk;
  return delta;
}

// it_pu_update in two steps (IT_SPEC): it_pu_spec computes the new P row of
// a possible winner (user of p_row, subcarrier k) into spec, without
// changing any state (res_alloc[k] is set during the call only; it is this
// core's copy); it_pu_commit applies it once the user has won, if res_alloc
// and the P and V rows are still the same.
int32_t it_pu_spec(int32_t *spec, const int32_t *p_row, const int32_t *v_row,
                   int32_t *res_alloc, const int32_t *klist,
                   const int32_t *nalloc, unsigned int k, unsigned int N,
                   int32_t *pk) {
  res_alloc[k] = 1;
  snrt_fence_snitch();
  const int32_t delta =
      it_pu_calc(spec, p_row, v_row, res_alloc, klist, *nalloc + 1, k, N, pk);
  snrt_fence_spatz();
  res_alloc[k] = 0;
  return delta;
}

void it_pu_commit(int32_t *p_row, const int32_t *spec, int32_t *ua_row,
                  int32_t *klist, int32_t *nalloc, unsigned int k,
                  unsigned int N, int32_t pk) {
  ua_row[k] = 1;
  const int32_t n = *nalloc + 1;
  klist[n - 1] = k;
  *nalloc = n;
  for (unsigned int p = 0; p < N;) {
    const unsigned int vl = it_vl(N - p);
    asm volatile("vle32.v v0, (%0)" ::"r"(spec + p));
    asm volatile("vse32.v v0, (%0)" ::"r"(p_row + p) : "memory");
    p += vl;
  }
  snrt_fence_spatz();
  p_row[k] = pk;
}

// The U rows of [u0, u1) that can come near the clamp: U = R1 * R2 + C with
// R2 in {0, 1}, so U[l][k] stays within C[l][k] + [sum of the negative,
// sum of the positive R1[l][i]]. Rows whose bound stays within the margin
// never clamp nor raise the margin flag, so the pass skips them and their U
// goes stale (main.c recomputes it before the first column fix-up). The
// other rows go into rows[]. Returns the number of listed rows.
unsigned int it_u_rows(int32_t *rows, const int32_t *C,
                       const int32_t *R1, unsigned int u0, unsigned int u1,
                       unsigned int M, unsigned int ldr, unsigned int N,
                       int32_t *bnd) {
  // The bounds of up to UV_VLMAX rows at a time, one row per lane: strided
  // loads down the columns of R1 and C (vl padded to a multiple of 4; the
  // padded lanes read past row u1 and are not used). bnd: 2 * UV_VLMAX words.
  const unsigned int r1stride = ldr * sizeof(int32_t);
  const unsigned int cstride = N * sizeof(int32_t);
  unsigned int n = 0;
  for (unsigned int l0 = u0; l0 < u1; l0 += UV_VLMAX) {
    const unsigned int nr = u1 - l0 < UV_VLMAX ? u1 - l0 : UV_VLMAX;
    it_vl(it_up4(nr));
    asm volatile("vxor.vv v0, v0, v0");
    asm volatile("vxor.vv v4, v4, v4");
    for (unsigned int i = 0; i < M; ++i) {
      asm volatile("vlse32.v v16, (%0), %1" ::"r"(R1 + l0 * ldr + i),
                   "r"(r1stride));
      asm volatile("vmax.vx v20, v16, zero");
      asm volatile("vadd.vv v0, v0, v20");
      asm volatile("vmin.vx v20, v16, zero");
      asm volatile("vadd.vv v4, v4, v20");
    }
    asm volatile("vlse32.v v8, (%0), %1" ::"r"(C + l0 * N), "r"(cstride));
    asm volatile("vadd.vv v12, v8, v4");
    asm volatile("vadd.vv v8, v8, v0");
    for (unsigned int k = 1; k < N; ++k) {
      asm volatile("vlse32.v v16, (%0), %1" ::"r"(C + l0 * N + k),
                   "r"(cstride));
      asm volatile("vadd.vv v20, v16, v0");
      asm volatile("vmax.vv v8, v8, v20");
      asm volatile("vadd.vv v20, v16, v4");
      asm volatile("vmin.vv v12, v12, v20");
    }
    // v8 = largest, v12 = smallest reachable U of each row
    asm volatile("vse32.v v8, (%0)" ::"r"(bnd) : "memory");
    asm volatile("vse32.v v12, (%0)" ::"r"(bnd + UV_VLMAX) : "memory");
    snrt_fence_spatz();
    for (unsigned int r = 0; r < nr; ++r) {
      const int safe =
          bnd[r] <= IT_MARGIN && bnd[UV_VLMAX + r] >= -IT_MARGIN;
      if (!safe)
        rows[n++] = (int32_t)(l0 + r);
    }
  }
  snrt_fence_snitch();
  return n;
}

// U rows += R1[l][w] * s on the listed rows, with s of both strips in v24 /
// v28, and v8 = max(Umax, -Umin) of those rows
static inline void it_u_rows_add(int32_t *U, const int32_t *R1,
                                 unsigned int w, const int32_t *rows,
                                 unsigned int n, unsigned int ldr,
                                 unsigned int N) {
  it_vl(N);
  asm volatile("vxor.vv v8, v8, v8");
  asm volatile("vxor.vv v12, v12, v12");
  for (unsigned int p = 0, j = 0; p < N; ++j) {
    const unsigned int vl = it_vl(N - p);
    for (unsigned int r = 0; r < n; ++r) {
      const unsigned int l = (unsigned int)rows[r];
      if (j)
        IT_U_ROW("v0", "v28", U + l * N + p, R1[l * ldr + w]);
      else
        IT_U_ROW("v0", "v24", U + l * N + p, R1[l * ldr + w]);
    }
    p += vl;
  }
  it_vl(N);
  asm volatile("vrsub.vi v12, v12, 0");
  asm volatile("vmax.vv v8, v8, v12");
}

// U part of the pass on the listed rows only: s of both strips into v24 /
// v28, then it_u_rows_add
static inline void it_u_part(int32_t *U, const int32_t *R1,
                             const int32_t *r2w, unsigned int w,
                             const int32_t *rows, unsigned int n,
                             unsigned int ldr, unsigned int N) {
  const unsigned int vl0 = it_vl(N);
  IT_SIGN("v24", r2w);
  if (N > vl0) {
    it_vl(N - vl0);
    IT_SIGN("v28", r2w + vl0);
  }
  it_u_rows_add(U, R1, w, rows, n, ldr, N);
}

// 1 if an element of the n listed U rows is outside the clamp margin (v8,
// v12 and v16 scratch, trk as in it_pass)
int it_u_check(const int32_t *U, const int32_t *rows, unsigned int n,
               unsigned int N, int32_t *trk) {
  if (!n)
    return 0;
  it_vl(N);
  asm volatile("vxor.vv v8, v8, v8");
  asm volatile("vxor.vv v12, v12, v12");
  for (unsigned int p = 0; p < N;) {
    const unsigned int vl = it_vl(N - p);
    for (unsigned int r = 0; r < n; ++r) {
      const int32_t *u = U + (unsigned int)rows[r] * N + p;
      asm volatile("vle32.v v16, (%0)" ::"r"(u));
      asm volatile("vmax.vv v8, v8, v16");
      asm volatile("vmin.vv v12, v12, v16");
    }
    p += vl;
  }
  it_vl(N);
  asm volatile("vrsub.vi v12, v12, 0");
  asm volatile("vmax.vv v8, v8, v12");
  asm volatile("vse32.v v8, (%0)" ::"r"(trk) : "memory");
  snrt_fence_spatz();
  return it_flag_scan(trk, N < UV_VLMAX ? N : UV_VLMAX);
}

// s of both strips (v24 / v28, as left by it_pass) into sbuf
static inline void it_s_save(int32_t *sbuf, unsigned int N) {
  const unsigned int vl0 = it_vl(N);
  asm volatile("vse32.v v24, (%0)" ::"r"(sbuf) : "memory");
  if (N > vl0) {
    it_vl(N - vl0);
    asm volatile("vse32.v v28, (%0)" ::"r"(sbuf + vl0) : "memory");
  }
}

// Strips of columns per U row in it_u_late
#define IT_U_STRIPS(N) ((N) > UV_VLMAX ? 2u : 1u)

// The U part of a pass one iteration later (see main.c), with s from sbuf
// (it_s_save) as R2[w] may already be flipped; trk as in it_pass. The work
// is split in units of one strip of one row: unit u is strip
// u % IT_U_STRIPS(N) of row rows[u / IT_U_STRIPS(N)], and this core updates
// units [u0, u1), so the cores' shares differ by at most one strip instead
// of one row. Returns 1 if a U element crossed the clamp margin.
int it_u_late(int32_t *U, const int32_t *R1, const int32_t *sbuf,
              unsigned int w, const int32_t *rows, unsigned int u0,
              unsigned int u1, unsigned int ldr, unsigned int N,
              int32_t *trk) {
  if (u0 >= u1)
    return 0;
  const unsigned int ns = IT_U_STRIPS(N);
  const unsigned int vl0 = it_vl(N);
  asm volatile("vle32.v v24, (%0)" ::"r"(sbuf));
  if (N > vl0) {
    it_vl(N - vl0);
    asm volatile("vle32.v v28, (%0)" ::"r"(sbuf + vl0));
  }
  it_vl(N);
  asm volatile("vxor.vv v8, v8, v8");
  asm volatile("vxor.vv v12, v12, v12");
  for (unsigned int j = 0; j < ns; ++j) {
    it_vl(N - j * vl0);
    for (unsigned int u = u0 + (j + ns - u0 % ns) % ns; u < u1; u += ns) {
      const unsigned int l = (unsigned int)rows[u / ns];
      if (j)
        IT_U_ROW("v0", "v28", U + l * N + vl0, R1[l * ldr + w]);
      else
        IT_U_ROW("v0", "v24", U + l * N, R1[l * ldr + w]);
    }
  }
  it_vl(N);
  asm volatile("vrsub.vi v12, v12, 0");
  asm volatile("vmax.vv v8, v8, v12");
  asm volatile("vse32.v v8, (%0)" ::"r"(trk) : "memory");
  snrt_fence_spatz();
  return it_flag_scan(trk, N < UV_VLMAX ? N : UV_VLMAX);
}

// Update pass after an odd iteration won by user w: the nu U rows listed in
// urows (it_u_rows), V rows [v0, v1) and colS of those rows (G is left
// stale, see IT_VS_ROW). R1 and AR1
// have row pitch ldr. trk is a scratch of UV_VLMAX words. If sbuf is not
// NULL, s is stored there for it_u_late. Returns 1 if a U element crossed
// the clamp margin (then the caller fixes columns and calls it_s_rows).
// rev 1 runs the second strip of columns first, so that the cores do not all
// stream the same L1 lines (controllers) at the same time.
int it_pass(int32_t *U, int32_t *V, const int32_t *P,
            int32_t *colS, const int32_t *R1, const int32_t *AR1,
            const int32_t *R2, unsigned int w, const int32_t *urows,
            unsigned int nu, unsigned int v0, unsigned int v1,
            unsigned int ldr, unsigned int N, int32_t *trk,
            int32_t *sbuf, unsigned int rev) {
  const int32_t *r2w = R2 + w * N;
  if (nu) {
    it_u_part(U, R1, r2w, w, urows, nu, ldr, N);
    asm volatile("vse32.v v8, (%0)" ::"r"(trk) : "memory");
  } else {
    // s of both strips for the V part
    const unsigned int vl0 = it_vl(N);
    IT_SIGN("v24", r2w);
    if (N > vl0) {
      it_vl(N - vl0);
      IT_SIGN("v28", r2w + vl0);
    }
  }
  if (sbuf)
    it_s_save(sbuf, N);
  const unsigned int vl0 = N < UV_VLMAX ? N : UV_VLMAX;
  for (unsigned int jj = 0; jj < 2; ++jj) {
    const unsigned int j = jj ^ (rev & 1), p = j ? vl0 : 0;
    if (p >= N)
      continue;
    it_vl(N - p);
    if (j == 0) {
      asm volatile("vxor.vv v16, v16, v16");
      asm volatile("vadd.vi v16, v16, -1");
    } else {
      asm volatile("vxor.vv v20, v20, v20");
      asm volatile("vadd.vi v20, v20, -1");
    }
    for (unsigned int i = v0; i < v1; ++i) {
      const unsigned int o = i * N + p;
      const int32_t a = AR1[i * ldr + w];
      if (j == 0)
        IT_VS_ROW("v16", "v24", V + o, P + o, a);
      else
        IT_VS_ROW("v20", "v28", V + o, P + o, a);
    }
    if (j == 0)
      asm volatile("vse32.v v16, (%0)" ::"r"(colS + p) : "memory");
    else
      asm volatile("vse32.v v20, (%0)" ::"r"(colS + p) : "memory");
  }
  snrt_fence_spatz();
  return nu ? it_flag_scan(trk, N < UV_VLMAX ? N : UV_VLMAX) : 0;
}

// colS of rows [r0, r1) from P and V (no update), without row skip (none if
// skip is outside [r0, r1)); rev as in it_pass
void it_s_rows(int32_t *colS, const int32_t *P, const int32_t *V,
               unsigned int r0, unsigned int r1, unsigned int skip,
               unsigned int N, unsigned int rev) {
  const unsigned int vl0 = N < UV_VLMAX ? N : UV_VLMAX;
  for (unsigned int jj = 0; jj < 2; ++jj) {
    const unsigned int p = (jj ^ (rev & 1)) ? vl0 : 0;
    if (p >= N)
      continue;
    it_vl(N - p);
    asm volatile("vxor.vv v16, v16, v16");
    asm volatile("vadd.vi v16, v16, -1");
    for (unsigned int i = r0; i < r1; ++i) {
      if (i == skip)
        continue;
      asm volatile("vle32.v v0, (%0)" ::"r"(P + i * N + p));
      asm volatile("vle32.v v4, (%0)" ::"r"(V + i * N + p));
      IT_G_OF_V("v4");
      asm volatile("vmul.vv v0, v0, v4");
      asm volatile("vmax.vv v16, v16, v0");
    }
    asm volatile("vse32.v v16, (%0)" ::"r"(colS + p) : "memory");
  }
  snrt_fence_spatz();
}

// G rows [r0, r1) from V, for the scalar code that reads G (power update,
// finalization)
void it_g_rows(int32_t *G, const int32_t *V, unsigned int r0,
               unsigned int r1, unsigned int N) {
  for (unsigned int i = r0; i < r1; ++i)
    for (unsigned int p = 0; p < N;) {
      unsigned int vl = it_vl(N - p);
      asm volatile("vle32.v v4, (%0)" ::"r"(V + i * N + p));
      IT_G_OF_V("v4");
      asm volatile("vse32.v v4, (%0)" ::"r"(G + i * N + p) : "memory");
      p += vl;
    }
  snrt_fence_spatz();
}

// Recompute V[:, k] = A * clamp(U[:, k]) + D[k] for every column
// k in [k0, k1) with some |U| above the margin (A has row pitch lda). Slow
// path; every U row must be exact (see main.c).
void it_fix_cols(int32_t *V, const int32_t *U, const int32_t *A,
                 const int32_t *D, unsigned int k0, unsigned int k1,
                 unsigned int M, unsigned int N, unsigned int lda) {
  const unsigned int stride = N * sizeof(int32_t);
  const unsigned int astride = lda * sizeof(int32_t);
  for (unsigned int k = k0; k < k1; ++k) {
    int need = 0;
    for (unsigned int l = 0; l < N; ++l) {
      int32_t u = U[l * N + k];
      need |= (u > IT_MARGIN) | (u < -IT_MARGIN);
    }
    if (!need)
      continue;
    for (unsigned int i = 0; i < M;) {
      unsigned int vl = it_vl(M - i);
      asm volatile("vxor.vv v16, v16, v16");
      asm volatile("vadd.vx v16, v16, %0" ::"r"(D[k]));
      for (unsigned int l = 0; l < N; ++l) {
        int32_t r = U[l * N + k];
        r = r < CTRL_MIN_R ? CTRL_MIN_R : r;
        r = r > CTRL_MAX_R ? CTRL_MAX_R : r;
        asm volatile("vlse32.v v20, (%0), %1" ::"r"(A + i * lda + l),
                     "r"(astride));
        asm volatile("vmacc.vx v16, %0, v20" ::"r"(r));
      }
      asm volatile("vsse32.v v16, (%0), %1" ::"r"(V + i * N + k), "r"(stride)
                   : "memory");
      i += vl;
    }
  }
  snrt_fence_spatz();
}

// Scratch of it_cands: candidate keys, one word, the gains of a column
#define IT_SCR (3 * UV_VLMAX + 16)

// Columns take the low IT_COL_BITS bits of a packed key. The per-core table
// kidx holds 127 - k for a free column k and INT32_MIN | (127 - k) for an
// allocated one (it_take), so the key of an allocated column is negative.
#define IT_COL_BITS 7

// Packed key of one strip of columns into vk: colS[k] >> 7 << 7 | kidx[k]
// (v4 scratch)
#define IT_PACK_KEY(vk, cs, ki)                                                \
  do {                                                                         \
    asm volatile("vle32.v " vk ", (%0)" ::"r"(cs));                            \
    asm volatile("vle32.v v4, (%0)" ::"r"(ki));                                \
    asm volatile("vand.vx " vk ", " vk ", %0" ::"r"(-(1 << IT_COL_BITS)));     \
    asm volatile("vor.vv " vk ", " vk ", v4");                                 \
  } while (0)

// Candidate keys of one strip into vk: kidx[k] where colS[k] >= thr, else
// -1 (negative for the allocated columns either way; v4 scratch)
#define IT_CAND_KEY(vk, cs, ki, thr)                                           \
  do {                                                                         \
    asm volatile("vle32.v " vk ", (%0)" ::"r"(cs));                            \
    asm volatile("vle32.v v4, (%0)" ::"r"(ki));                                \
    asm volatile("vsub.vx " vk ", " vk ", %0" ::"r"(thr));                     \
    asm volatile("vsra.vi " vk ", " vk ", 31");                                \
    asm volatile("vor.vv " vk ", " vk ", v4");                                 \
  } while (0)

// Column k allocated in this core's table
static inline void it_take(int32_t *kidx, unsigned int k) {
  kidx[k] = INT32_MIN | (127 - (int32_t)k);
}

// Keys of vk below lim kept, the others set to -1 (v4 scratch)
#define IT_KEY_BELOW(vk, lim)                                                  \
  do {                                                                         \
    asm volatile("vsub.vx v4, " vk ", %0" ::"r"(lim));                         \
    asm volatile("vsra.vi v4, v4, 31");                                        \
    asm volatile("vand.vv " vk ", " vk ", v4");                                \
    asm volatile("vxor.vi v4, v4, -1");                                        \
    asm volatile("vor.vv " vk ", " vk ", v4");                                 \
  } while (0)

// IT_CPROF 1: cycles of the parts of it_cands per core, summed while
// it_cprof_on: top-2 of the column keys, the candidate keys (several
// candidate columns only), the exact keys; then the calls, the columns with
// exact keys and the calls with a single candidate column
#ifndef IT_CPROF
#define IT_CPROF 0
#endif
enum { CP_BEST, CP_CKEY, CP_EXACT, CP_CALLS, CP_COLS, CP_SINGLE, CP_NUM };
#if IT_CPROF
static unsigned int it_cprof[16][CP_NUM] __attribute__((section(".data")));
static volatile int it_cprof_on[16] __attribute__((section(".data")));
#define CP_LAP(ph)                                                             \
  do {                                                                         \
    if (it_cprof_on[cpc]) {                                                    \
      const unsigned int cpn = benchmark_get_cycle();                          \
      it_cprof[cpc][ph] += cpn - cpt;                                          \
      cpt = cpn;                                                               \
    }                                                                          \
  } while (0)
#define CP_ADD(ph, n)                                                          \
  do {                                                                         \
    if (it_cprof_on[cpc])                                                      \
      it_cprof[cpc][ph] += (n);                                                \
  } while (0)
#else
#define CP_LAP(ph)                                                             \
  do {                                                                         \
  } while (0)
#define CP_ADD(ph, n)                                                          \
  do {                                                                         \
  } while (0)
#endif

// Selection on one core over its rows [r0, r1) (1 <= r1 - r0 <= UV_VLMAX):
// Smax of its colS over the free columns, then its candidate columns and
// their exact keys. Smax of the core's own rows is at most the global one,
// so its threshold is too, and the core's best key is exact; the winner is
// the best key over the cores. kidx as in it_take, uidx[i] = 127 - i,
// lidx[i] = i. scr is a scratch of IT_SCR words. The padded lanes read up to
// 3 words past colS, kidx and uidx, and up to 3 rows past row r1
// of P and V. Row skip (none if outside [r0, r1)) is left out of the exact
// keys. Returns the best key (-1 if none) and its column in *kb.
// (Scalar passes over the S of the free columns instead of the trees were
// slower: the scalar loads wait for the L1 one by one.)
int32_t it_cands(const int32_t *colS, const int32_t *P, const int32_t *V,
                 const int32_t *kidx,
                 const int32_t *uidx, const int32_t *lidx, unsigned int r0,
                 unsigned int r1, unsigned int skip, unsigned int N,
                 int32_t *scr, int *kb) {
  const unsigned int vl0 = N < UV_VLMAX ? N : UV_VLMAX;
  const unsigned int vl1 = N - vl0;
  const unsigned int vl0p = it_up4(vl0), vl1p = it_up4(vl1);
  int32_t *ckey = scr, *tmp = scr + 2 * UV_VLMAX, *gscr = tmp + 16;
  const unsigned int gstride = N * sizeof(int32_t);
#if IT_CPROF
  const unsigned int cpc = snrt_cluster_vpu_idx();
  unsigned int cpt = benchmark_get_cycle();
  CP_ADD(CP_CALLS, 1);
#endif

  // The two largest packed keys of the free columns: the first gives a
  // candidate column and T = Smax >> 7 << 7, so thr = T - (T >> 14) - 2 is
  // at most the threshold of Smax. If the second key's column cannot reach
  // thr, that column is the only candidate.
  it_vl(vl0p);
  IT_PACK_KEY("v0", colS, kidx);
  IT_PAD("v0", vl0, lidx);
  if (!vl1) {
    asm volatile("vxor.vv v8, v8, v8");
    asm volatile("vadd.vi v8, v8, -1");
  } else {
    it_vl(vl1p);
    IT_PACK_KEY("v20", colS + vl0, kidx + vl0);
    IT_PAD("v20", vl1, lidx);
    asm volatile("vmin.vv v8, v0, v20");
    asm volatile("vmax.vv v0, v0, v20");
  }
  int32_t second;
  const int32_t top = it_tree_top2(vl0p, tmp, &second);
  *kb = -1;
  if (top < 0)
    return -1;
  const int32_t tb = top & ~((1 << IT_COL_BITS) - 1);
  const int32_t thr = tb - (tb >> 14) - 2;
  const int single = (second | ((1 << IT_COL_BITS) - 1)) < thr;
  CP_ADD(CP_SINGLE, single);
  CP_LAP(CP_BEST);

  // Otherwise the candidate keys of both strips, kept in ckey; strip 1
  // folded into v0
  if (!single) {
    it_vl(vl0p);
    IT_CAND_KEY("v0", colS, kidx, thr);
    IT_PAD("v0", vl0, lidx);
    asm volatile("vse32.v v0, (%0)" ::"r"(ckey) : "memory");
    if (vl1) {
      it_vl(vl1p);
      IT_CAND_KEY("v8", colS + vl0, kidx + vl0, thr);
      IT_PAD("v8", vl1, lidx);
      asm volatile("vse32.v v8, (%0)" ::"r"(ckey + UV_VLMAX) : "memory");
      asm volatile("vmax.vv v0, v0, v8");
    }
  }

  const unsigned int rows = r1 - r0, rowsp = it_up4(rows);
  int32_t best = -1;
  int32_t kc =
      single ? (top & ((1 << IT_COL_BITS) - 1)) : it_tree_max(vl0p, tmp);
  CP_LAP(CP_CKEY);
  while (kc >= 0) {
    CP_ADD(CP_COLS, 1);
    const unsigned int k = 127 - kc;
    // exact keys of rows [r0, r1) in column k, best one into tmp
    it_vl(rowsp);
    asm volatile("vlse32.v v0, (%0), %1" ::"r"(P + r0 * N + k), "r"(gstride));
    asm volatile("vlse32.v v4, (%0), %1" ::"r"(V + r0 * N + k), "r"(gstride));
    IT_G_OF_V("v4");
    GAIN_CORE_R("v0", "v4", "v12", gscr, 0);
    asm volatile("vle32.v v4, (%0)" ::"r"(uidx + r0));
    asm volatile("vadd.vv v0, v12, v4");
    IT_PAD("v0", rows, lidx);
    if (skip >= r0 && skip < r1) {
      // lane skip - r0 to -1: (d | -d) >> 31 is 0 there and -1 elsewhere
      asm volatile("vle32.v v4, (%0)" ::"r"(lidx));
      asm volatile("vsub.vx v4, v4, %0" ::"r"(skip - r0));
      asm volatile("vrsub.vi v12, v4, 0");
      asm volatile("vor.vv v4, v4, v12");
      asm volatile("vsra.vi v4, v4, 31");
      asm volatile("vand.vv v0, v0, v4");
      asm volatile("vxor.vi v4, v4, -1");
      asm volatile("vor.vv v0, v0, v4");
    }
    const int32_t key = it_tree_max(rowsp, tmp);
    // strict > in increasing k keeps the lowest column on ties
    if (key > best) {
      best = key;
      *kb = (int)k;
    }
    if (single)
      break;
    // next candidate: the keys below kc (higher columns)
    it_vl(vl0p);
    asm volatile("vle32.v v0, (%0)" ::"r"(ckey));
    IT_KEY_BELOW("v0", kc);
    if (vl1) {
      it_vl(vl1p);
      asm volatile("vle32.v v8, (%0)" ::"r"(ckey + UV_VLMAX));
      IT_KEY_BELOW("v8", kc);
      asm volatile("vmax.vv v0, v0, v8");
    }
    kc = it_tree_max(vl0p, tmp);
  }
  CP_LAP(CP_EXACT);
  return best;
}
