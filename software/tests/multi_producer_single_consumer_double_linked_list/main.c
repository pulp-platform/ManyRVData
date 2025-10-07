#include "kernel/printf_lock.c"
#include "kernel/mm.c"
#include "kernel/rlc.c"
#include <snrt.h>
#include <stdio.h>
#include <stddef.h>
#include <l1cache.h>
#include "printf.h"
#include "kernel/printf_lock.h"
#include "kernel/mcs_lock.h"
#include DATAHEADER

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

        // Initialize the RLC context
        rlc_init(0, 0, &mm_ctx);

        // // Initialize the linked list for receiving queue
        // list_init(&rlc_ctx.list);

        // Initialize locks
        mm_lock = 0;
        tosend_llist_lock = 0;
        sent_llist_lock = 0;
        mcs_lock_init(&tosend_llist_lock_2);
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

    // // Wait for all cores to finish
    // snrt_cluster_hw_barrier(); // this can trigger Misaligned Load exception

    return 0;
}
