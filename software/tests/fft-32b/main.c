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

// Author: Diyou Shen, ETH Zurich

#include <stdio.h>
#include <benchmark.h>
#include <snrt.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include DATAHEADER
#include "kernel/fft.c"

static inline int fp_check(const float a, const float b) {
  const float threshold = 0.01f;

  // Absolute value
  float comp = a - b;
  if (comp < 0)
    comp = -comp;

  return comp > threshold;
}

// max(#Core) = (NFFT/4)/(N_FU)
// Helper index in 16-bits, needs to fit in a vector word (1/2 * 1/(N_FU))
// We also need to one additional round for strided store into bitrev order (another 1/2)
// 256  -> 16
// 512  -> 32
// 1024 -> 64

int main() {
  const int measure_iter = 2;

  // twiddle layout: [re_p1, im_p1, re_p2, im_p2]
  const uint32_t num_cores = snrt_cluster_core_num();
  const uint32_t cid = snrt_cluster_core_idx();
  
  snrt_cluster_hw_barrier();
  const uint32_t NFFTpc = NFFT / active_cores;
  // 32-bit floating, 4 byte distance in memory
  const uint32_t element_size = 4;
  // elements distance between two stores
  const uint32_t stride_e = active_cores;
  // distance in bits
  const uint32_t stride = stride_e * element_size;

  const uint32_t CHECK = 1;

  // Reset timer
  uint32_t timer = (uint32_t)-1;
  uint32_t timer_tmp, timer_iter1;

  if (cid == 0) {
    // Set xbar policy
    // Currently set to fully interleave (log2(512/8))
    l1d_xbar_config(6);
  }

  // Wait for all cores to finish
  snrt_cluster_hw_barrier();

  // Calculate pointers for the second butterfly onwards
  float *src_p2 = samples_dram + cid * NFFTpc;
  float *buf_p2 = buffer_dram  + cid * NFFTpc;
  // Let each core has its own twiddle copy to reduce bank conflicts
  float *twi_p2 = twiddle_dram + (NTWI_P1<<1);
  float *out_p2 = out + coffset_dram[cid];

  uint32_t  p2_switch = 0;

  float *src_p1 = samples_dram;
  float *buf_p1 = buffer_dram;
  float *twi_p1 = twiddle_dram;
  const uint32_t len = (NFFTpc >> 1);

  // real and imagninary error
  uint32_t rerror = 0;
  uint32_t ierror = 0;

  for (int iter = 0; iter < measure_iter; iter++) {
    if (cid == 0) {
      start_kernel();
    }

    // Wait for all cores to finish
    snrt_cluster_hw_barrier();

    // Start timer
    if (cid == 0) {
      timer_tmp = benchmark_get_cycle();
    }

    for (uint32_t i = 0; i < log2_nfft1; i ++) {
      if (cid < active_cores) {
        fft_p1(src_p1, buf_p1, twi_p1, NFFT, NTWI_P1, cid, active_cores, i, len);
        // each round will use half the twiddle than previous round
        // the first round needs re/im NFFT/2 twiddles
        src_p1 = (i & 1) ? samples_dram : buffer_dram;
        buf_p1 = (i & 1) ? buffer_dram : samples_dram;
        twi_p1 += (NFFT >> (i+1));
        p2_switch = (i & 1);
      }

      // In first part of calculation, we need barrier after each round
      snrt_cluster_hw_barrier();
    }

    if (cid < active_cores) {
      // Fall back into the single-core case
      // Each core just do a FFT on (NFFT >> stage_in_P1) data
      if (p2_switch) {
        fft_p2(buf_p2, src_p2, twi_p2, out_p2, store_idx_dram, (NFFT>>log2_nfft1),
              NFFT, log2_nfft2, stride, log2_nfft1, NTWI_P2);
      } else {
        fft_p2(src_p2, buf_p2, twi_p2, out_p2, store_idx_dram, (NFFT>>log2_nfft1),
              NFFT, log2_nfft2, stride, log2_nfft1, NTWI_P2);
      }
    }
    // Wait for all cores to finish fft
    snrt_cluster_hw_barrier();

    // End timer and check if new best runtime
    if (cid == 0) {
      timer_tmp = benchmark_get_cycle() - timer_tmp;
      timer = (timer < timer_tmp) ? timer : timer_tmp;
      if (iter == 0)
        timer_iter1 = timer;

      stop_kernel();

      if ((iter == 0) && CHECK) {
        l1d_flush();
        l1d_wait();

        // Verify the real part
        for (unsigned int i = 0; i < NFFT; i++) {
          if (fp_check(out[i], gold_out_dram[2 * i])) {
            rerror ++;
          }
        }

        // Verify the imac part
        for (unsigned int i = 0; i < NFFT; i++) {
          if (fp_check(out[i + NFFT], gold_out_dram[2 * i + 1])) {
            ierror ++;
          }
        }

        printf ("r:%d,i:%d\n", rerror, ierror);
      }
    }

    snrt_cluster_hw_barrier();
  }
  
  // Display runtime
  if (cid == 0) {
    // Each stage requires:
    // 2 add, 2 sub, 2 mul, 2 macc/msac
    // in total 10 operations on NFFT/2 real and NFFT/2 im elements

    // Divide by two so that the utilization in macc isntead of op
    long unsigned int performance =
        1000 * NFFT * 10 * log2_nfft / timer;
    long unsigned int utilization = performance / (2 * active_cores * 4);

    printf("\n----- fft on %d samples -----\n", NFFT);
    printf("First execution took %u cycles.\n", timer_iter1);
    printf("The execution took %u cycles.\n", timer);
    printf("The performance is %ld OP/1000cycle (%ld%%o utilization).\n",
           performance, utilization);


  }

  // Wait for core 0 to finish displaying results
  snrt_cluster_hw_barrier();
  if ((rerror + ierror) > 0)
    return 1;
  else
    return 0;
}
