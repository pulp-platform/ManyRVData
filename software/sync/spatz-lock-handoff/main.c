// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0

// Lock handoff test: proves the Spatz lock actually serializes host0/host1,
// not just that Spatz produces correct data for independent requesters.
// v0 is physical Spatz register state shared across the lock handoff -- host0
// loads a pattern into v0, then both hosts (racing for the lock) add a fixed
// role constant (host0: 1, host1: 2) directly to v0, and host0 stores the
// final result. Fixed constants (not cid) keep the expected sum identical
// across every pair, so a failure is easy to spot and debug. A lost update
// (lock failed to serialize) yields a wrong final sum, which a
// per-hart-disjoint-slice test could never detect.

#include <benchmark.h>
#include <snrt.h>
#include <spatz_lock.h>
#include <stdint.h>
#include <stdio.h>

#define MAX_PAIRS 128U
#define TEST_LEN  64U  // vector elements per pair, fits one vsetvli group
#define PATTERN   1U

#if SNRT_NUM_SCALAR_PER_CORE == 2
#define PAIR_SIZE 2U
#define EXPECT    (PATTERN + 3U)  // host0 adds 1, host1 adds 2
#else
#define PAIR_SIZE 1U
#define EXPECT    (PATTERN + 1U)  // host0 only, adds 1
#endif

static uint32_t src_dram[TEST_LEN] __attribute__((section(".data")))
    = {[0 ... TEST_LEN - 1] = PATTERN};
static uint32_t dst_dram[MAX_PAIRS][TEST_LEN] __attribute__((section(".data")));
static uint32_t pair_errors[MAX_PAIRS] __attribute__((section(".data")));

int main() {
  const uint32_t cid = snrt_cluster_core_idx();
  const uint32_t pair = cid / PAIR_SIZE;
  const uint32_t add_val = snrt_cluster_is_primary() ? 1U : 2U;
  uint32_t vlen;

  if (cid == 0) {
    printf("*** spatz-lock-handoff test ***\n");
    printf("PATTERN=%u PAIR_SIZE=%u EXPECT=%u\n", PATTERN, PAIR_SIZE, EXPECT);
  }
  snrt_cluster_hw_barrier();

  // Phase 1 (host0 only): load the seed pattern into v0 and hold the lock
  // open just long enough to establish it -- no store, v0 carries the state.
  if (snrt_cluster_is_primary()) {
    spatz_lock_acquire();
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vlen) : "r"(TEST_LEN));
    asm volatile("vle32.v v0, (%0)" : : "r"(src_dram));
    spatz_lock_release();
  }
  snrt_cluster_hw_barrier();

  // Phase 2 (both hosts): racing add directly on v0, serialized by the lock
  // -- a lost update here means the lock failed to exclude concurrent access.
  spatz_lock_acquire();
  asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vlen) : "r"(TEST_LEN));
  asm volatile("vadd.vx v0, v0, %0" : : "r"(add_val));
  spatz_lock_release();
  snrt_cluster_hw_barrier();

  // Phase 3 (host0 only): store the final accumulated v0 for checking.
  if (snrt_cluster_is_primary()) {
    spatz_lock_acquire();
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vlen) : "r"(TEST_LEN));
    asm volatile("vse32.v v0, (%0)" : : "r"(dst_dram[pair]));
    spatz_lock_release();

    uint32_t errs = 0;
    for (uint32_t i = 0; i < TEST_LEN; i++) {
      if (dst_dram[pair][i] != EXPECT) {
        errs++;
      }
    }
    pair_errors[pair] = errs;
  }
  snrt_cluster_hw_barrier();

  if (cid == 0) {
    const uint32_t num_cores = snrt_cluster_core_num();
    const uint32_t num_pairs = num_cores / PAIR_SIZE;
    uint32_t total_err = 0;
    for (uint32_t p = 0; p < num_pairs; p++) {
      total_err += pair_errors[p];
    }

    if (total_err == 0) {
      printf("[PASS] spatz-lock-handoff: pairs=%u len=%u\n", num_pairs, TEST_LEN);
    } else {
      printf("[FAIL] spatz-lock-handoff: errors=%u pairs=%u len=%u\n",
             total_err, num_pairs, TEST_LEN);
      printf("  expect=%u\n", EXPECT);
      for (uint32_t p = 0; p < num_pairs; p++) {
        if (pair_errors[p] != 0) {
          printf("  pair %u: dst_dram[0]=%u errs=%u\n", p, dst_dram[p][0],
                 pair_errors[p]);
        }
      }
    }
  }
  snrt_cluster_hw_barrier();

  return 0;
}
