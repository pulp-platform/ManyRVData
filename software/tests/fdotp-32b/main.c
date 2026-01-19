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
#include <stdio.h>

#include DATAHEADER
#include "kernel/fdotp.c"

int main() {
  const uint32_t num_cores = snrt_cluster_core_num();
  const uint32_t num_tiles = snrt_cluster_tile_num();
  const uint32_t cid = snrt_cluster_core_idx();
  const uint32_t tid = snrt_cluster_tile_idx();
  // core id within a tile (0-3)
  const uint32_t cid_tile = cid - tid * num_tiles;

  const uint32_t num_cores_per_tile = num_cores / num_tiles;

  const int measure_iter = 3;

  // Here we target to reduce the remote access.
  // We want to keep the data fully interleaved on L1
  // Therefore, give a small value to it go with the default minimum
  // => interleave with cacheline width
  if (cid == 0) {
    // Set xbar policy
    l1d_xbar_config(1);
    // Initialize the cache
    l1d_init(0);
  }

  // hardcode for now the cacheline width and number of cache per tile
  // TODO: correctly pass in the info from hardware configuration
  const uint32_t cacheline          = 512;
  const uint32_t num_cache_per_tile = 4;

  // This is the max length each core can work contiunously without break (in bits)
  const uint32_t data_len_per_tile  = cacheline * num_cache_per_tile;
  // This is the max length each core can work contiunously without break (in elem)
  const uint32_t dim                = data_len_per_tile / 32;
  // This is the distance each core within a tile needs to jump after one iteration (in elem)
  // Also the dimension each core will work on in one large iteration
  const uint32_t tile_offset        = num_tiles * dim;
  // This is the distance each core needs to jump after one iteration (in elem)
  const uint32_t offset             = tile_offset * num_cores_per_tile;
  // Max hardware vlen the core support
  const uint32_t max_vlen           = 512;
  // Which lmul settins we can use for the kernel?
  const uint32_t lmul               = data_len_per_tile / max_vlen;
  // This is the number of large iterations need for execution
  const uint32_t rounds             = dotp_l.M / offset;

  if (cid == 0) {
    if (rounds < 1) {
      // Means we have way too less problem size, not fit for this algorithm
      printf ("FATAL: Number of elements too small!\n");
    } else {
      printf ("round:%u, lmul:%u, dim:%u\n", rounds, lmul, dim);
    }

    if (lmul > 8) {
      printf ("FATAL: Not yet support for long case!\n");
    }
  }

  snrt_cluster_hw_barrier();

  // Reset timer
  uint32_t timer = (uint32_t)-1;
  uint32_t timer_tmp, timer_iter1;

  // Calculate the starting points for each core
  float *a_int = dotp_A_dram + cid_tile * tile_offset + tid * dim;
  float *b_int = dotp_B_dram + cid_tile * tile_offset + tid * dim;


  for (int iter = 0; iter < measure_iter; iter ++) {
    // Start dump
    if (cid == 0)
      start_kernel();

    snrt_cluster_hw_barrier();

    // Start timer
    timer_tmp = benchmark_get_cycle();

    // Calculate dotp
    float acc;

    if (lmul >= 8)
      acc = fdotp_v32b_lmul8(a_int, b_int, offset, dim, rounds);
    else if (lmul >= 4)
      acc = fdotp_v32b_lmul4(a_int, b_int, offset, dim, rounds);
    else if (lmul >= 2)
      acc = fdotp_v32b_lmul2(a_int, b_int, offset, dim, rounds);
    else if (lmul >= 1)
      acc = fdotp_v32b_lmul1(a_int, b_int, offset, dim, rounds);
    else
      return 0;

    result[cid] = acc;

    // Wait for all cores to finish
    snrt_cluster_hw_barrier();

    // End timer and check if new best runtime
    if (cid == 0) {
      timer_tmp = benchmark_get_cycle() - timer_tmp;
      timer = (timer < timer_tmp) ? timer : timer_tmp;
      if (iter == 0)
        timer_iter1 = timer;

      stop_kernel();
    }

    // Final reduction
    if (cid == 0) {
      // timer_tmp = benchmark_get_cycle() - timer_tmp;
      for (uint32_t i = 1; i < num_cores; ++i)
        acc += result[i];
      result[0] = acc;
    }

  }

  snrt_cluster_hw_barrier();

  // Check and display results
  if (cid == 0) {
    // The timer did not count the reduction time
    uint32_t performance = 1000 * 2 * dotp_l.M / timer;
    uint32_t perf_iter1  = 1000 * 2 * dotp_l.M / timer_iter1;
    uint32_t utilization = performance / (2 * num_cores * 4);
    uint32_t util_iter1  = perf_iter1  / (2 * num_cores * 4);
    write_cyc(timer);

    printf("\n----- (%d) sp fdotp -----\n", dotp_l.M);
    printf("The 1st execution took %u cycles.\n", timer_iter1);
    printf("The performance is %u OP/1000cycle (%u%%o utilization).\n",
           perf_iter1 , util_iter1);
    printf("The execution took %u cycles.\n", timer);
    printf("The performance is %u OP/1000cycle (%u%%o utilization).\n",
           performance, utilization);
  }

  if (cid == 0) {
    if (fp_check(result[0], dotp_result*measure_iter)) {
      printf("Check Failed!\n");
    }
  }

  // Wait for core 0 to display the results
  snrt_cluster_hw_barrier();

  return 0;
}