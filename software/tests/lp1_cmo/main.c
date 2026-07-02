// Copyright 2026 ETH Zurich and University of Bologna.
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

// Author: Ho Tin Hung, ETH Zurich

// LP1 CMO datapath liveness — single-core bring-up gate for the per-core
// private-L1 (HPDcache) CMO injector.
//
// Goal: prove the NEW control path is electrically alive end-to-end before it
// is relied upon in a real kernel (spin-lock). The path is:
//   runtime MMIO store -> peripheral reg -> per-core CMO FSM -> l1_ctrl
//   injector requester[2] -> HPDcache -> response -> done -> status clears.
// Every prior test kept lp1_cmo_valid at 0, so this is the first exercise of
// that datapath.
//
// This tier tests LIVENESS, not cross-core correctness: each lp1_* call is a
// blocking status poll, so if a CMO never completes (injector never sees
// l1_rsp[2].valid, or the arbiter never grants requester 2) the test HANGS.
// The print marker bracketing each call localizes such a hang to the exact op.
// The post-CMO reloads confirm the refill path still returns correct data.
// Cross-core staleness correctness is the spin-lock test's job.
//
// Only core 0 does work; every other core parks on the hardware barrier, which
// is coherence-independent (MMIO) and safe here.

#include <benchmark.h>
#include <lp1cache.h>
#include <snrt.h>
#include <stdint.h>
#include <stdio.h>

// Small cacheable footprint touched ONLY by core 0 — no sharing, no coherence.
#define CMO_WORDS 16

static volatile uint32_t cmo_buf[CMO_WORDS] __attribute__((section(".data")));

int main() {
  const uint32_t num_cores = snrt_cluster_core_num();
  const uint32_t cid       = snrt_cluster_core_idx();

  // Confirm every core booted and the HW barrier works before core 0 drives
  // the CMO datapath.
  snrt_cluster_hw_barrier();

  if (cid == 0) {
    printf("\n*** LP1 CMO datapath liveness (single-core) ***\n");
    printf("Cores:%u  (only core 0 active)\n", num_cores);

    start_kernel();

    uint32_t errors = 0;

    // Seed cacheable data. Write-through: values land in L2 and are also
    // resident in the private L1.
    for (uint32_t i = 0; i < CMO_WORDS; i++)
      cmo_buf[i] = 0xCA110000u + i;

    // [1] FENCE / write-through flush. Drains the WBUF; must complete & return.
    printf("  [1] lp1_wt_flush (CMO_FENCE) ... issuing\n");
    snrt_fence();
    lp1_wt_flush();
    printf("  [1] lp1_wt_flush DONE\n");

    // [2] INVAL_ALL. Drops every resident line; must complete & return.
    printf("  [2] lp1_inval (INVAL_ALL) ... issuing\n");
    lp1_inval();
    snrt_fence();
    printf("  [2] lp1_inval DONE\n");

    // After a full invalidate, these loads miss and refill from L2. On a single
    // core L2 still holds the seeded values, so the data must match — this
    // confirms the post-inval refill path is alive.
    for (uint32_t i = 0; i < CMO_WORDS; i++) {
      uint32_t got = cmo_buf[i];
      uint32_t exp = 0xCA110000u + i;
      if (got != exp) {
        printf("  FAIL refill idx %u exp 0x%08x got 0x%08x\n", i, exp, got);
        errors++;
      }
    }

    // [3] INVAL_NLINE on a single address; must complete & return.
    printf("  [3] lp1_inval_line ... issuing\n");
    lp1_inval_line((uint32_t)(uintptr_t)&cmo_buf[0]);
    snrt_fence();
    printf("  [3] lp1_inval_line DONE\n");

    // Reload the invalidated line: refills from L2, must match.
    {
      uint32_t got = cmo_buf[0];
      uint32_t exp = 0xCA110000u;
      if (got != exp) {
        printf("  FAIL line-refill exp 0x%08x got 0x%08x\n", exp, got);
        errors++;
      }
    }

    stop_kernel();

    if (errors == 0)
      printf("lp1_cmo: PASS\n");
    else
      printf("lp1_cmo: FAIL (%u errors)\n", errors);

    printf("*** LP1 CMO liveness complete ***\n");
  }

  // Final rendezvous so no core races ahead to EOC before core 0 is done.
  snrt_cluster_hw_barrier();

  return 0;
}
