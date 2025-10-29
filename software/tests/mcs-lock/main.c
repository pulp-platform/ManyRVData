// Copyright 2025 ETH Zurich and University of Bologna.
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

// Author: Zexin Fu     <zexifu@iis.ee.ethz.ch>

#include "benchmark.h"
#include "kernel/printf_lock.c"
#include <snrt.h>
#include <stdio.h>
#include <stddef.h>
#include <l1cache.h>
#include "printf.h"
#include "kernel/printf_lock.h"
#include "random.h"

//  if you want to compare with spin lock, comment the following line
#define USE_MCS_LOCK

#ifdef USE_MCS_LOCK
    #include "mcs_lock.h"
#else
    #include "spin_lock.h"
#endif

#define L1LineWidth (512/8) // 512 bits

#ifdef USE_MCS_LOCK
    static _Atomic mcs_lock_t test_mcs_lock __attribute__((aligned(4))) __attribute__((section(".data")));
#else
    static volatile int test_spin_lock __attribute__((aligned(4))) __attribute__((section(".data")));
#endif

volatile size_t cycle_last_lock_rl; __attribute__((aligned(4))) __attribute__((section(".data")));
volatile size_t cycle_this_lock_ac; __attribute__((aligned(4))) __attribute__((section(".data")));

int main(void) {
    /* Retrieve the core index only once in main */
    const unsigned int core_id = snrt_cluster_core_idx();


    if (core_id == 0) {
        // Set xbar policy
        l1d_flush();
        uint32_t offset = 31 - __builtin_clz(L1LineWidth);
        l1d_xbar_config(offset); // cacheline interleaving

        // Initalize the thread saft printf
        debug_print_lock_init();

        // Initialize locks
        #ifdef USE_MCS_LOCK
            mcs_lock_init(&test_mcs_lock);
        #else
            test_spin_lock = 0;
        #endif

        // Initialize cycle counters
        cycle_this_lock_ac = 0;
        cycle_last_lock_rl = benchmark_get_cycle();
    } else {
        delay(100*(64/L1LineWidth)); // Ensure core 0 finishes initialization first
    }

    // debug_printf_locked("[core %u] pre  snrt_cluster_hw_barrier()\n", core_id);

    // Wait for all cores to finish
    snrt_cluster_hw_barrier();

    // debug_printf_locked("[core %u] post snrt_cluster_hw_barrier()\n", core_id);
    // DEBUG_PRINTF("[core %u] post snrt_cluster_hw_barrier() done\n", core_id);


    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u] post snrt_cluster_hw_barrier() done\n", core_id);
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

    int i = 9;
    int j = 0;
    int ac_start    = 0;
    int ac_end      = 0;
    int rl_start    = 0;
    int rl_end      = 0;
    int body_start  = 0;
    int body_end    = 0;
    int total_lock_interval_cycle = 0;
    int total_ac_cycle = 0;
    int total_rl_cycle = 0;
    while (j < i) {
        ac_start = benchmark_get_cycle();

#ifdef USE_MCS_LOCK
        mcs_lock_acquire(&test_mcs_lock, 0);
#else
        spin_lock(&test_spin_lock, 0);
#endif

        ac_end = benchmark_get_cycle();

        cycle_this_lock_ac = ac_end;

        start_kernel();

        // body_start = benchmark_get_cycle();
        uint32_t rand_delay_cycles = 0;
/*
        // Per-core RNG state: seed from cycle counter and core id
        uint32_t rng_state = (uint32_t)ac_end ^ ((core_id + 1u) * 0x9E3779B9u);
        if (!rng_state) rng_state = 0x1u;  // just in case

        // Random delay inside the critical section
        rand_delay_cycles = xorshift32(&rng_state) & CS_DELAY_MASK;
        cachepool_wait(rand_delay_cycles);
*/
#ifdef USE_MCS_LOCK
        // critical section with mcs lock
        printf("[core %u] in mcs critical section, j=%d, ac=%d, last_rl=%d, lock interval=%d, random_delay=%d\n",
            core_id, j, ac_end - ac_start, rl_end - rl_start, cycle_this_lock_ac - cycle_last_lock_rl, rand_delay_cycles);
#else
        // critical section with spin lock
        printf("[core %u] in spin critical section, j=%d, ac=%d, last_rl=%d, lock interval=%d, random_delay=%d\n",
            core_id, j, ac_end - ac_start, rl_end - rl_start, cycle_this_lock_ac - cycle_last_lock_rl, rand_delay_cycles);
#endif
        stop_kernel();

        // body_end = benchmark_get_cycle();


        rl_start = benchmark_get_cycle();

#ifdef USE_MCS_LOCK
        mcs_lock_release(&test_mcs_lock, 0);
#else
        spin_unlock(&test_spin_lock, 0);
#endif

        rl_end = benchmark_get_cycle();

        total_lock_interval_cycle += (cycle_this_lock_ac - cycle_last_lock_rl);
        total_ac_cycle += (ac_end - ac_start);
        total_rl_cycle += (rl_end - rl_start);

        cycle_last_lock_rl = rl_end;

        j++;
    }

    // // Wait for all cores to finish
    // snrt_cluster_hw_barrier(); // this can trigger Misaligned Load exception


#ifdef USE_MCS_LOCK
        mcs_lock_acquire(&test_mcs_lock, 0);
#else
        spin_lock(&test_spin_lock, 0);
#endif

#ifdef USE_MCS_LOCK
        printf("[core %u] use mcs lock", core_id);
#else
        printf("[core %u] use spin lock", core_id);
#endif

        printf("total_run_lock_number=%d, total_lock_interval_cycle=%d, avg_lock_interval_cycle=%d/1000pkg, total_ac_cycle=%d, avg_ac_cycle=%d/1000pkg, total_rl_cycle=%d, avg_rl_cycle=%d/1000pkg\n",
               i,
               total_lock_interval_cycle,
               (total_lock_interval_cycle * 1000)/i,
               total_ac_cycle,
               (total_ac_cycle * 1000)/i,
               total_rl_cycle,
               (total_rl_cycle * 1000)/i);

#ifdef USE_MCS_LOCK
        mcs_lock_release(&test_mcs_lock, 0);
#else
        spin_unlock(&test_spin_lock, 0);
#endif

    if(core_id != 0) {
        while(1){}
    }

    // Wait for all cores to finish
    snrt_cluster_hw_barrier(); // this can trigger Misaligned Load exception

    set_eoc();
    return 0;
}
