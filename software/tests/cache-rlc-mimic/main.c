// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0

#include <l1cache.h>
#include <snrt.h>
#include <stdint.h>
#include "printf.h"

#define MAX_CORES 8U
#define CONSUMER_CORE 0U
#define PRODUCER_CORE 1U
#ifndef RLCM_PKT_BYTES
#define RLCM_PKT_BYTES 1360U
#endif
#define WORD_BYTES 4U
#define PKT_BYTES RLCM_PKT_BYTES
#define PKT_WORDS (PKT_BYTES / WORD_BYTES)
#ifndef RLCM_JOBS_PER_PRODUCER
#define RLCM_JOBS_PER_PRODUCER 24U
#endif
#define JOBS_PER_PRODUCER RLCM_JOBS_PER_PRODUCER
#define ACTIVE_PRODUCERS 1U
#define MAX_JOBS (ACTIVE_PRODUCERS * JOBS_PER_PRODUCER)

typedef struct {
  uint32_t src_word_ofst;
  uint32_t dst_word_ofst;
  uint32_t words;
  uint32_t valid;
} job_t;

static uint32_t src_buf[MAX_JOBS * PKT_WORDS] __attribute__((section(".dram")))
    __attribute__((aligned(64)));
static uint32_t dst_buf[MAX_JOBS * PKT_WORDS] __attribute__((section(".dram")))
    __attribute__((aligned(64)));
static job_t job_table[MAX_JOBS] __attribute__((section(".dram")))
    __attribute__((aligned(64)));

static uint32_t prod_done[MAX_CORES] __attribute__((section(".data")));
static uint32_t core_err[MAX_CORES] __attribute__((section(".data")));
static uint32_t core_sig[MAX_CORES] __attribute__((section(".data")));

static inline uint32_t mix32(uint32_t x) {
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  return x;
}

static inline void vec_copy_u32(uint32_t *dst, const uint32_t *src, uint32_t words) {
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
  const uint32_t producers = ACTIVE_PRODUCERS;
  const uint32_t total_jobs = producers * JOBS_PER_PRODUCER;

  if (cid == 0) {
    l1d_init(0);
    for (uint32_t i = 0; i < MAX_JOBS * PKT_WORDS; i++) {
      src_buf[i] = 0;
      dst_buf[i] = 0;
    }
    for (uint32_t i = 0; i < MAX_JOBS; i++) {
      job_table[i].src_word_ofst = 0;
      job_table[i].dst_word_ofst = 0;
      job_table[i].words = 0;
      job_table[i].valid = 0;
    }
    for (uint32_t i = 0; i < MAX_CORES; i++) {
      prod_done[i] = 0;
      core_err[i] = 0;
      core_sig[i] = 0;
    }
  }
  snrt_cluster_hw_barrier();

  uint32_t errs = 0;
  uint32_t sig = 0x12345678u ^ (cid * 0x1020304u);

  if (cid == PRODUCER_CORE) {
    const uint32_t pidx = 0;
    for (uint32_t j = 0; j < JOBS_PER_PRODUCER; j++) {
      const uint32_t job_id = pidx * JOBS_PER_PRODUCER + j;
      const uint32_t src_base = (((j * producers) + pidx) * PKT_WORDS) %
                                (MAX_JOBS * PKT_WORDS - PKT_WORDS);
      const uint32_t dst_base = (((j * producers) + ((pidx + 3U) %
                                (producers ? producers : 1U))) * PKT_WORDS) %
                                (MAX_JOBS * PKT_WORDS - PKT_WORDS);

      for (uint32_t w = 0; w < PKT_WORDS; w++) {
        uint32_t v = mix32(((pidx + 1U) << 24) ^ (job_id << 12) ^ w);
        src_buf[src_base + w] = v;
        dst_buf[dst_base + w] = v ^ 0x5a5a5a5au;
      }

      job_table[job_id].src_word_ofst = src_base;
      job_table[job_id].dst_word_ofst = dst_base;
      job_table[job_id].words = PKT_WORDS;
      __atomic_store_n(&job_table[job_id].valid, 1U, __ATOMIC_RELEASE);
      sig ^= mix32(src_base ^ (dst_base << 1) ^ job_id);
    }
    __atomic_store_n(&prod_done[PRODUCER_CORE], 1U, __ATOMIC_RELEASE);
  }

  if (cid == CONSUMER_CORE) {
    uint32_t consumed = 0;
    uint32_t scan = 0;
    uint32_t progress_epoch = 0;

    while (consumed < total_jobs) {
      uint32_t job_id = scan % (total_jobs ? total_jobs : 1U);
      if (__atomic_load_n(&job_table[job_id].valid, __ATOMIC_ACQUIRE) == 1U) {
        uint32_t src_base = job_table[job_id].src_word_ofst;
        uint32_t dst_base = job_table[job_id].dst_word_ofst;
        uint32_t words = job_table[job_id].words;

        vec_copy_u32(&dst_buf[dst_base], &src_buf[src_base], words);

        // Spot-check a few words, then full checksum accumulate to catch corruption.
        for (uint32_t k = 0; k < words; k += 17U) {
          uint32_t got = dst_buf[dst_base + k];
          uint32_t exp = src_buf[src_base + k];
          if (got != exp) errs++;
          sig ^= mix32(got ^ (k << 8) ^ job_id);
        }

        __atomic_store_n(&job_table[job_id].valid, 0U, __ATOMIC_RELEASE);
        consumed++;
      }
      scan++;

      if ((scan & 0x7ffffU) == 0U) {
        uint32_t done_mask = 0;
        if (__atomic_load_n(&prod_done[PRODUCER_CORE], __ATOMIC_ACQUIRE) != 0U)
          done_mask |= (1U << PRODUCER_CORE);
        printf("[PROGRESS] cache-rlc-mimic: epoch=%u consumed=%u/%u scan=%u done_mask=0x%08x\n",
               progress_epoch, consumed, total_jobs, scan, done_mask);
        progress_epoch++;
      }
    }

    // End-to-end verify full destination buffers for all jobs.
    for (uint32_t job_id = 0; job_id < total_jobs; job_id++) {
      uint32_t src_base = job_table[job_id].src_word_ofst;
      uint32_t dst_base = job_table[job_id].dst_word_ofst;
      for (uint32_t w = 0; w < PKT_WORDS; w++) {
        uint32_t got = dst_buf[dst_base + w];
        uint32_t exp = src_buf[src_base + w];
        if (got != exp) errs++;
      }
    }
  }

  if (cid < MAX_CORES) {
    core_err[cid] = errs;
    core_sig[cid] = sig;
  }
  snrt_cluster_hw_barrier();

  if (cid == 0) {
    uint32_t total_err = 0;
    uint32_t fold_sig = 0;
    for (uint32_t i = 0; i <= PRODUCER_CORE; i++) {
      total_err += core_err[i];
      fold_sig ^= core_sig[i];
    }

    if (total_err == 0) {
      printf("[PASS] cache-rlc-mimic: jobs=%u pkt=%uB signature=0x%08x\n",
             total_jobs, PKT_BYTES, fold_sig);
    } else {
      printf("[FAIL] cache-rlc-mimic: errors=%u jobs=%u pkt=%uB signature=0x%08x\n",
             total_err, total_jobs, PKT_BYTES, fold_sig);
    }

    l1d_flush();
    return (int)total_err;
  }

  return 0;
}
