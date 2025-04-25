#include "kernel/debug.c"
#include "kernel/mm.c"
#include "kernel/rlc.c"
#include <snrt.h>
#include <stdio.h>
#include <stddef.h>
#include <l1cache.h>
#include "printf.h"

int main(void) {
    /* Retrieve the core index only once in main */
    const unsigned int core_id = snrt_cluster_core_idx();

    mm_context_t mm_ctx;
    rlc_context_t rlc_ctx;
    
    if (core_id == 0) {
        /* Initalize the thread saft printf */
        debug_print_lock_init();
        /* Initialize memory management context */
        mm_init(&mm_ctx);
        /* Set up the RLC context to use the memory management context */
        rlc_ctx.mm_ctx = &mm_ctx;

        /* Initialize the linked list */
        list_init(&rlc_ctx.list);
    } 

    // Wait for all cores to finish
    snrt_cluster_hw_barrier();

    rlc_start(&rlc_ctx, core_id);
    
    return 0;
}
