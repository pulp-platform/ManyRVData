#include "kernel/printf_lock.c"
#include "kernel/mm.c"
#include "kernel/rlc.c"
#include <snrt.h>
#include <stdio.h>
#include <stddef.h>
#include <l1cache.h>
#include "printf.h"
#include "kernel/printf_lock.h"
#include DATAHEADER

#define L1LineWidth (256/8) // 256 bits = 32 bytes

int main(void) {
    /* Retrieve the core index only once in main */
    const unsigned int core_id = snrt_cluster_core_idx();

    
    if (core_id == 0) {
        // Set xbar policy
        uint32_t offset = 31 - __builtin_clz(L1LineWidth);
        l1d_xbar_config(offset); // cacheline interleaving
        
        // Initalize the thread saft printf
        debug_print_lock_init();
        
        // Initialize memory management context
        mm_init();

        // Initialize the linked list for receiving queue
        list_init();
        
        // Initialize locks
        mm_lock = 0;
        llist_lock = 0;
    }

    // debug_printf_locked("[core %u] pre  snrt_cluster_hw_barrier()\n", core_id);

    // Wait for all cores to finish
    snrt_cluster_hw_barrier();

    // debug_printf_locked("[core %u] post snrt_cluster_hw_barrier()\n", core_id);
    // printf("[core %u] post snrt_cluster_hw_barrier() done\n", core_id);


    printf_lock_acquire(&printf_lock);
    printf("[core %u] post snrt_cluster_hw_barrier() done\n", core_id);
    printf_lock_release(&printf_lock);

    rlc_start(core_id);
    
    return 0;
}
