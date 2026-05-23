// Minimal multi-tile bug repro -- absolutely no printf, no library.
//
// Only core 0 does anything: write 16 words to a single cache line in
// DRAM, then read them back, count mismatches.  Communicate the error
// count via the return value -- it gets shifted into the tohost EOC
// value by the runtime, so a non-zero retval == sim retval != 0.

#include <l1cache.h>
#include <snrt.h>
#include <stdint.h>

#define LINE_BYTES 64U
#define WORDS_PER_LINE (LINE_BYTES / 4)
#define L1LineWidth 64

static uint32_t line_buf[WORDS_PER_LINE] __attribute__((section(".dram")))
    __attribute__((aligned(LINE_BYTES))) = { 0 };

int main() {
  const uint32_t cid = snrt_cluster_core_idx();

  if (cid != 0) return 0;

  l1d_flush();
  uint32_t offset = 31 - __builtin_clz(L1LineWidth);
  l1d_xbar_config(offset);

  volatile uint32_t *buf = line_buf;

  for (uint32_t w = 0; w < WORDS_PER_LINE; ++w)
    buf[w] = 0xA5A50000u | w;

  uint32_t errs = 0;
  for (uint32_t w = 0; w < WORDS_PER_LINE; ++w) {
    if (buf[w] != (0xA5A50000u | w)) ++errs;
  }

  return (int)errs;
}
