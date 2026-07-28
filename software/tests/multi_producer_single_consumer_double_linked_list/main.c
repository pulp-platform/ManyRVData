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

#include <stdint.h>
/* DATAHEADER must be included before the kernel sources so that rlc.c/rlc.h
   see NUM_PKGS / PDU_SIZE / ACTIVE_USER_NUMBER (rlc.c has a guarded fallback). */
#include DATAHEADER
#include "kernel/printf_lock.c"
#include "kernel/mm.c"
#include "kernel/rlc.c"
#include <snrt.h>
#include <stdio.h>
#include <stddef.h>
#include <l1cache.h>
#include "printf.h"
#include "kernel/printf_lock.h"
#include "mcs_lock.h"

#define L1LineWidth (512/8) // 512 bits

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

        // Initialize memory management context
        mm_init();

        // Initialize all RLC entities (one per UE)
        for (unsigned int u = 0; u < NUM_USERS; u++) {
            rlc_init(u, 0, &mm_ctx);
        }

        // Initialize shared/global resources (single producer-descriptor stream)
        pdcp_pkd_ptr = 0;
        mcs_lock_init(&pdcp_pkd_ptr_lock);
        producer_done = 0;
        rlc_ctx_lock = 0;

        // Initialize locks
        mm_lock = 0;
        tosend_llist_lock = 0;
        sent_llist_lock = 0;
        for (unsigned int u = 0; u < NUM_USERS; u++) {
            mcs_lock_init(&tosend_llist_lock_2[u]);
            mcs_lock_init(&sent_llist_lock_2[u]);
        }
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

    rlc_start(core_id);

    // Wait for all cores to finish
    snrt_cluster_hw_barrier(); // this can trigger Misaligned Load exception

    return 0;
}
