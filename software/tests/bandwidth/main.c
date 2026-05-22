// Copyright 2022 ETH Zurich and University of Bologna.
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

// Author: Diyou Shen     <dishen@iis.ee.ethz.ch>

#include <benchmark.h>
#include <snrt.h>
#include <stdint.h>
#include <stdio.h>

#include "data/data.h"

// #define DEBUG

// Random-load bandwidth benchmark — measures L1-to-core interconnect bandwidth.
//
// Phase 1 (warmup): all cores together stream through all of data_dram so that
// every cache line is resident in the L1 before measurement begins.
// Requires M * sizeof(int) <= total L1 cache capacity.
//
// Phase 2 (measurement): each core issues random vector loads drawn from a
// pre-generated offset table.  Because all data is already cached, this
// measures the L1 hit bandwidth (local + remote tile xbar), not DRAM refill
// latency.  No correctness check is performed — only the cycle count matters.

int main() {
  const uint32_t num_cores  = snrt_cluster_core_num();
  const uint32_t cid        = snrt_cluster_core_idx();
  const uint32_t c_per_tile = 4;
  const uint32_t cid_tile   = cid % c_per_tile;

  // Spatz vector config: lmul=4, element width 32 b, VLEN=512 b
  const uint32_t lmul       = 4;
  const uint32_t vlen_bits  = 512;
  const uint32_t elem_bits  = 32;
  // Elements transferred by one vle32.v with lmul=4
  const uint32_t v_len = lmul * vlen_bits / elem_bits;

  const uint32_t measure_iterations = R;

  // offset = 6 = log2(64 B cacheline) — the hardware minimum.
  //
  // With this offset and 256-byte-aligned accesses (step = v_len = 64 elems):
  //   addr[7:6] = bank within tile   (changes at +64, +128, +192 → banks 0..3)
  //   addr[9:8] = tile ID            (unchanged across the 256-byte span)
  //
  // Every vle32.v load (256 bytes, 4 cachelines) therefore maps entirely to
  // ONE tile while distributing its 4 cachelines across the 4 banks of that
  // tile.  The random offset in offset_dram picks which tile is targeted
  // (local or remote), so ~75 % of loads hit a remote tile and generate
  // traffic on the inter-tile xbar.
  const uint32_t scramble_bits = 6;

  if (cid == 0) {
    l1d_xbar_config(scramble_bits);
    // Fully shared
    l1d_part(4);
#ifdef DEBUG
    printf("scramble_bits=%u v_len=%u\n", scramble_bits, v_len);
#endif
  }

  snrt_cluster_hw_barrier();

  // -----------------------------------------------------------------------
  // Phase 1: warmup — fill L1 cache with all of data_dram.
  // Each core streams through its own slice (M / num_cores elements) using
  // the widest LMUL so that every tile's banks are populated in parallel.
  // -----------------------------------------------------------------------
  // const uint32_t elems_per_core = M / num_cores;
  const uint32_t elems_per_core = M;
  // const int *wp = data_dram + cid * elems_per_core;
  const int *wp = data_dram + cid_tile * elems_per_core;
  uint32_t avl  = elems_per_core;
  uint32_t wvl;
  do {
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(wvl) : "r"(avl));
    asm volatile("vle32.v v0, (%0)" :: "r"(wp));
    wp  += wvl;
    avl -= wvl;
  } while (avl > 0);

  // Barrier: every tile's banks must be populated before measurement starts.
  snrt_cluster_hw_barrier();

  // -----------------------------------------------------------------------
  // Phase 2: measurement — random loads from the now-hot cache.
  // -----------------------------------------------------------------------

  // Per-core pointer into the offset table.
  // Layout: interleaved by core —
  //   [core0_round0, core1_round0, ..., coreN_round0, core0_round1, ...]
  const uint32_t *offset_p = offset_dram + cid;

  const int *data = data_dram;
  const int *addr1, *addr2, *addr3, *addr4;

  uint32_t vl;
  asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(v_len));

  uint32_t timer = 0;

  if (cid == 0) {
    start_kernel();
    timer = benchmark_get_cycle();
  }

  // Four loads per inner iteration to overlap address computation with loads.
  for (uint32_t i = 0; i < measure_iterations / 4; i++) {
    addr1 = data + *offset_p; offset_p += num_cores;
    addr2 = data + *offset_p; offset_p += num_cores;
    asm volatile("vle32.v v0, (%0)" :: "r"(addr1));
    asm volatile("vle32.v v4, (%0)" :: "r"(addr2));
    addr3 = data + *offset_p; offset_p += num_cores;
    addr4 = data + *offset_p; offset_p += num_cores;
    asm volatile("vle32.v v8,  (%0)" :: "r"(addr3));
    asm volatile("vle32.v v12, (%0)" :: "r"(addr4));
  }

  snrt_cluster_hw_barrier();

  if (cid == 0) {
    timer = benchmark_get_cycle() - timer;
    stop_kernel();

    // elements loaded by one core / timer
    uint32_t performance = measure_iterations * v_len * 1000 / timer;
    // 1000‰ = one vector load per cycle (peak throughput)
    uint32_t utilization = performance / v_len;

    printf("\n----- random-load bw: %u iters x %u elems -----\n",
           measure_iterations, v_len);
    printf("Total cycles: %u, avg per load: %u\n",
           timer, timer / measure_iterations);
    printf("Performance: %u elems/1000cyc (%u%%o utilization)\n",
           performance, utilization);

    write_cyc(timer);
  }

  snrt_cluster_hw_barrier();

  return 0;
}
