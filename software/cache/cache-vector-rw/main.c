// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0
//
// Mimics the RLC consumer data-movement pattern: vector load from a source
// buffer and vector store to a destination buffer, packet by packet.
// By default only core 0 is active. Set NUM_ACTIVE_CORES to use more cores.

#include <l1cache.h>
#include <snrt.h>
#include <stdint.h>
#include "printf.h"
#include <benchmark.h>

#define MAX_CORES 4U

// Number of cores that participate in the data movement (default: 1 = core 0 only)
#ifndef NUM_ACTIVE_CORES
#define NUM_ACTIVE_CORES 1U
#endif

// Packet size matching the RLC consumer payload (1360 bytes = 340 words)
#define PKT_BYTES 1360U
#define WORD_BYTES 4U
#define PKT_WORDS (PKT_BYTES / WORD_BYTES)

// Number of packets to move per core
#ifndef NUM_PKTS
#define NUM_PKTS 16U
#endif

// Optional: flush the L1D before the vector kernel so cold-cache (miss-path)
// behavior is exercised instead of measuring buffer hits left over from the
// scalar buffer-fill warm-up.  Set to 1 to enable.  Default 0 preserves the
// historical measurement.
#ifndef FLUSH_BEFORE_KERNEL
#define FLUSH_BEFORE_KERNEL 0
#endif

// Each active core gets its own src/dst region
#define TOTAL_WORDS_PER_CORE (NUM_PKTS * PKT_WORDS)
#define TOTAL_WORDS (NUM_ACTIVE_CORES * TOTAL_WORDS_PER_CORE)
#define L1LineWidth (512 / 8)

static uint32_t src_buf[TOTAL_WORDS] __attribute__((section(".dram")))
    __attribute__((aligned(64)));
static uint32_t dst_buf[TOTAL_WORDS] __attribute__((section(".dram")))
    __attribute__((aligned(64)));
static uint32_t core_errors[MAX_CORES] __attribute__((section(".data")));
static uint32_t core_cycles[MAX_CORES] __attribute__((section(".data")));

// Vector memcpy using e32/m8: mimics vec_copy_u32 from cache-rlc-mimic
void vec_copy_u32(uint32_t *dst, const uint32_t *src,
                                uint32_t words) {
  uint32_t copied = 0;
  while (copied < words) {
    uint32_t avl = words - copied;
    uint32_t vl = 0;
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(avl));
    asm volatile("vle32.v v0, (%0)" : : "r"(src + copied) : "memory");
    asm volatile("vse32.v v0, (%0)" : : "r"(dst + copied) : "memory");
    copied += vl;
  }
}

int main() {
  const uint32_t cid = snrt_cluster_core_idx();

  if (cid == 0) {
    l1d_init(0);
    // Fill source with known pattern, clear destination
    for (uint32_t i = 0; i < TOTAL_WORDS; i++) {
      src_buf[i] = 0xCAFE0000u ^ i;
      dst_buf[i] = 0;
    }
    for (uint32_t i = 0; i < MAX_CORES; i++) {
      core_errors[i] = 0;
      core_cycles[i] = 0;
    }
  }
  snrt_cluster_hw_barrier();

#if FLUSH_BEFORE_KERNEL
  // Drop the lines warmed by the scalar buffer-init loop so the vector
  // kernel below starts with a cold L1D and actually runs the miss path.
  // NOTE: with the flush enabled, the verify currently reports mismatches
  // (cold-cache vector-store + scalar-verify path appears to have a
  // pre-existing bug, unrelated to the FLUSH macro itself).  Useful for
  // measuring miss-path cycles, not for data-integrity checks until that
  // bug is fixed.
  if (cid == 0) {
    l1d_flush();
    l1d_wait();
  }
  snrt_cluster_hw_barrier();
#endif

  uint32_t errs = 0;

  if (cid < NUM_ACTIVE_CORES) {
    // Each core works on its own region
    uint32_t *my_src = &src_buf[cid * TOTAL_WORDS_PER_CORE];
    uint32_t *my_dst = &dst_buf[cid * TOTAL_WORDS_PER_CORE];

    // Move packets one by one: vector load src -> vector store dst
    if (cid == 0) start_kernel();
    uint32_t cyc_start = benchmark_get_cycle();

    for (uint32_t pkt = 0; pkt < NUM_PKTS; pkt++) {
      uint32_t *s = &my_src[pkt * PKT_WORDS];
      uint32_t *d = &my_dst[pkt * PKT_WORDS];
      vec_copy_u32(d, s, PKT_WORDS);
    }

    uint32_t cyc_end = benchmark_get_cycle();
    if (cid == 0) stop_kernel();

    core_cycles[cid] = cyc_end - cyc_start;

    // Verify
    for (uint32_t i = 0; i < TOTAL_WORDS_PER_CORE; i++) {
      uint32_t got = my_dst[i];
      uint32_t exp = 0xCAFE0000u ^ (cid * TOTAL_WORDS_PER_CORE + i);
      if (got != exp) {
        errs++;
      }
    }
  }

  if (cid < MAX_CORES) {
    core_errors[cid] = errs;
  }
  snrt_cluster_hw_barrier();

  if (cid == 0) {
    uint32_t total_err = 0;
    uint32_t max_cyc = 0;
    for (uint32_t i = 0; i < NUM_ACTIVE_CORES; i++) {
      total_err += core_errors[i];
      if (core_cycles[i] > max_cyc) max_cyc = core_cycles[i];
    }

    const uint32_t total_words = NUM_ACTIVE_CORES * TOTAL_WORDS_PER_CORE;
    const uint32_t pass_words  = total_words - total_err;
    if (total_err == 0) {
      printf("[PASS] cache-vector-rw: cores=%u pkts=%u pkt_bytes=%u total_bytes=%u "
             "words_tested=%u pass=%u fail=0 cycles=%u\n",
             NUM_ACTIVE_CORES, NUM_PKTS, PKT_BYTES,
             NUM_ACTIVE_CORES * NUM_PKTS * PKT_BYTES,
             total_words, pass_words, max_cyc);
    } else {
      printf("[FAIL] cache-vector-rw: errors=%u cores=%u pkts=%u pkt_bytes=%u "
             "words_tested=%u pass=%u fail=%u cycles=%u\n",
             total_err, NUM_ACTIVE_CORES, NUM_PKTS, PKT_BYTES,
             total_words, pass_words, total_err, max_cyc);
      // -- Diagnostic dump --
      // Goal: distinguish (a) load-side bugs (vle returns wrong data) from
      // (b) store-side bugs (vse drops writes), and surface enough pattern
      // info to grep waveforms/RTL traces for the failing addresses.
      //
      // Classifies errors:
      //   got == 0           : likely "never written" (init value).
      //   got == exp ^ 0x...  : corrupted but probably store-derived.
      //   got == something_unrelated : foreign data, possibly aliasing.
      //
      // Cross-checks src_buf (the LOAD source) to see whether the LOAD
      // path itself is returning wrong data -- if src_errs > 0, the bug
      // is upstream of vec_copy's store path (probably cache refill /
      // flush writeback losing init data).
      const uint32_t MAX_LINES_REPORT = 32;
      for (uint32_t c = 0; c < NUM_ACTIVE_CORES; c++) {
        if (core_errors[c] == 0) continue;
        uint32_t *c_src = &src_buf[c * TOTAL_WORDS_PER_CORE];
        uint32_t *c_dst = &dst_buf[c * TOTAL_WORDS_PER_CORE];

        uint32_t first_err_idx = 0xFFFFFFFFu;
        uint32_t first_err_got = 0, first_err_exp = 0;
        uint32_t got_zero = 0, got_other = 0;
        uint32_t src_errs = 0, src_zero = 0;
        uint32_t first_src_err_idx = 0xFFFFFFFFu;
        uint32_t first_src_err_got = 0, first_src_err_exp = 0;
        for (uint32_t i = 0; i < TOTAL_WORDS_PER_CORE; i++) {
          uint32_t exp = 0xCAFE0000u ^ (c * TOTAL_WORDS_PER_CORE + i);
          uint32_t got_d = c_dst[i];
          if (got_d != exp) {
            if (first_err_idx == 0xFFFFFFFFu) {
              first_err_idx = i; first_err_got = got_d; first_err_exp = exp;
            }
            if (got_d == 0) got_zero++; else got_other++;
          }
          uint32_t got_s = c_src[i];
          if (got_s != exp) {
            if (first_src_err_idx == 0xFFFFFFFFu) {
              first_src_err_idx = i; first_src_err_got = got_s; first_src_err_exp = exp;
            }
            src_errs++;
            if (got_s == 0) src_zero++;
          }
        }
        uint32_t words_in_core = TOTAL_WORDS_PER_CORE;
        printf("  [CORE %u] words=%u pass=%u fail=%u (rate=%u%%)\n",
               c, words_in_core, words_in_core - core_errors[c], core_errors[c],
               (words_in_core - core_errors[c]) * 100U / words_in_core);
        printf("  [CORE %u] dst_errs=%u (got_zero=%u got_other=%u)  src_errs=%u (got_zero=%u)\n",
               c, core_errors[c], got_zero, got_other, src_errs, src_zero);
        if (first_err_idx != 0xFFFFFFFFu) {
          printf("  [CORE %u] first_dst_mismatch: idx=%u addr=0x%08x got=0x%08x exp=0x%08x\n",
                 c, first_err_idx,
                 (uint32_t)(uintptr_t)&c_dst[first_err_idx],
                 first_err_got, first_err_exp);
        }
        if (first_src_err_idx != 0xFFFFFFFFu) {
          printf("  [CORE %u] first_src_mismatch: idx=%u addr=0x%08x got=0x%08x exp=0x%08x\n",
                 c, first_src_err_idx,
                 (uint32_t)(uintptr_t)&c_src[first_src_err_idx],
                 first_src_err_got, first_src_err_exp);
        }
        // Interpretation hints
        if (src_errs == core_errors[c] && src_zero == src_errs && got_zero == core_errors[c]) {
          printf("  [CORE %u] PATTERN: src and dst both read all-zero for the same indices --\n", c);
          printf("             suggests dirty src_buf lines were NEVER written back to DRAM\n");
          printf("             (cache-flush writeback bug, not the vector store).\n");
        } else if (got_zero == core_errors[c] && src_errs == 0) {
          printf("  [CORE %u] PATTERN: dst is all-zero on mismatches, src reads correctly --\n", c);
          printf("             suggests vector store path dropped writes (store-side bug).\n");
        } else if (got_other > 0) {
          printf("  [CORE %u] PATTERN: %u mismatches have non-zero, non-expected got --\n",
                 c, got_other);
          printf("             possible data-corruption / aliasing / forwarding bug.\n");
        }
        // Per-cache-line totals: how many lines passed fully vs. partially
        // failed vs. failed completely.  Separate counts for src and dst.
        uint32_t lines_total = (TOTAL_WORDS_PER_CORE + 15) / 16;
        uint32_t s_full_ok = 0, s_partial = 0, s_all_wrong = 0;
        uint32_t d_full_ok = 0, d_partial = 0, d_all_wrong = 0;
        for (uint32_t line = 0; line < lines_total; line++) {
          uint32_t s_mask = 0, d_mask = 0;
          uint32_t in_line = 16;
          if (line * 16 + in_line > TOTAL_WORDS_PER_CORE)
            in_line = TOTAL_WORDS_PER_CORE - line * 16;
          uint32_t full = (in_line == 16) ? 0xFFFFu : ((1u << in_line) - 1);
          for (uint32_t w = 0; w < in_line; w++) {
            uint32_t i = line * 16 + w;
            uint32_t exp = 0xCAFE0000u ^ (c * TOTAL_WORDS_PER_CORE + i);
            if (c_src[i] == exp) s_mask |= (1u << w);
            if (c_dst[i] == exp) d_mask |= (1u << w);
          }
          if (s_mask == full)      s_full_ok++;
          else if (s_mask == 0)    s_all_wrong++;
          else                     s_partial++;
          if (d_mask == full)      d_full_ok++;
          else if (d_mask == 0)    d_all_wrong++;
          else                     d_partial++;
        }
        printf("  [CORE %u] lines_total=%u  src_lines: full_ok=%u partial=%u all_wrong=%u  "
               "dst_lines: full_ok=%u partial=%u all_wrong=%u\n",
               c, lines_total,
               s_full_ok, s_partial, s_all_wrong,
               d_full_ok, d_partial, d_all_wrong);

        // Per-cache-line summary: src_ok_mask + dst_ok_mask per 16-word line.
        // Lets the reviewer spot stride / periodic patterns at a glance.
        printf("  [CORE %u] per-line {src_ok_mask, dst_ok_mask} (first %u failing lines):\n",
               c, MAX_LINES_REPORT);
        uint32_t reported = 0;
        for (uint32_t line = 0; line < lines_total && reported < MAX_LINES_REPORT; line++) {
          uint32_t s_mask = 0, d_mask = 0;
          uint32_t in_line = 16;
          if (line * 16 + in_line > TOTAL_WORDS_PER_CORE)
            in_line = TOTAL_WORDS_PER_CORE - line * 16;
          for (uint32_t w = 0; w < in_line; w++) {
            uint32_t i = line * 16 + w;
            uint32_t exp = 0xCAFE0000u ^ (c * TOTAL_WORDS_PER_CORE + i);
            if (c_src[i] == exp) s_mask |= (1u << w);
            if (c_dst[i] == exp) d_mask |= (1u << w);
          }
          uint32_t full = (in_line == 16) ? 0xFFFFu : ((1u << in_line) - 1);
          if (s_mask != full || d_mask != full) {
            printf("    line %3u (base_idx=%u, dst_addr=0x%08x): src_ok=0x%04x dst_ok=0x%04x\n",
                   line, line * 16,
                   (uint32_t)(uintptr_t)&c_dst[line * 16],
                   s_mask, d_mask);
            reported++;
          }
        }
        if (reported == MAX_LINES_REPORT)
          printf("  [CORE %u] ... (more failing lines truncated)\n", c);
      }
    }

    l1d_flush();
    return (int)total_err;
  }

  return 0;
}
