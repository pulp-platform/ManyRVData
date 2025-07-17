#ifndef RLC_C
#define RLC_C

#include "rlc.h"
#include "mm.h"
#include "llist.c"
#include "data_move_vec.c"
#include <snrt.h>
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <l1cache.h>
#include "printf.h"
#include "printf_lock.h"
#include "../data/data_1_1350_10.h"

/* Simple spinlock functions using GCC built‑ins */
static inline void pdcp_pkg_lock_acquire(volatile int *lock) {
    while (__sync_lock_test_and_set(lock, 1)) { delay(100); }
}

static inline void pdcp_pkg_lock_release(volatile int *lock) {
    asm volatile (
        "amoswap.w zero, zero, %0"
        : "+A" (*lock)
    );
}

void rlc_init(const unsigned int rlcId, const unsigned int cellId, mm_context_t *mm_ctx) {
    rlc_ctx.rlcId = rlcId;
    rlc_ctx.cellId = cellId;
    rlc_ctx.pollPdu = 32;
    rlc_ctx.pollByte = 25000;
    rlc_ctx.pduWithoutPoll = 0;
    rlc_ctx.byteWithoutPoll = 0;
    rlc_ctx.vtNextAck = 0;
    rlc_ctx.vtNext = 0;

    // Initialize the linked lists
    list_init(&rlc_ctx.list);
    list_init(&rlc_ctx.sent_list);

    // Set the memory management context
    rlc_ctx.mm_ctx = mm_ctx;

    // Initialize PDCP package pointer and lock
    pdcp_pkd_ptr = 0;
    pdcp_pkd_ptr_lock = 0;

    // printf_lock_acquire(&printf_lock);
    // printf("[core %u][rlc_init] RLC context initialized for RLC ID %u, Cell ID %u\n",
    //        snrt_cluster_core_idx(), rlcId, cellId);
    // printf_lock_release(&printf_lock);
}

int pdcp_receive_pkg(const unsigned int core_id, volatile int *lock) {
    uint32_t timer_ac_lock_0, timer_ac_lock_1;
    uint32_t timer_rl_lock_0, timer_rl_lock_1;
    uint32_t timer_body_0, timer_body_1;

    timer_ac_lock_0 = benchmark_get_cycle();
    pdcp_pkg_lock_acquire(lock); // Acquire the lock to ensure exclusive access
    timer_ac_lock_1 = benchmark_get_cycle();

    timer_body_0 = benchmark_get_cycle();
    int pkg_ptr = -1; // Initialize package pointer to -1 (indicating no package)
    if (pdcp_pkd_ptr < NUM_PKGS) {
        // If the pointer is within bounds, return the package pointer
        pkg_ptr = pdcp_pkd_ptr;
        pdcp_pkd_ptr++; // Increment the pointer for the next package
    } else {
        printf_lock_acquire(&printf_lock);
        printf("Producer (core %u): out of PDCP pkg, pdcp_pkd_ptr = %d\n", core_id, pdcp_pkd_ptr);
        printf_lock_release(&printf_lock);
    }
    timer_body_1 = benchmark_get_cycle();

    timer_rl_lock_0 = benchmark_get_cycle();
    pdcp_pkg_lock_release(lock); // Release the lock
    timer_rl_lock_1 = benchmark_get_cycle();

    printf_lock_acquire(&printf_lock);
    printf("[core %u][pdcp_receive_pkg] spin_unlock, ac=%d, bd=%d, rl=%d\n",
        snrt_cluster_core_idx(),
        (timer_ac_lock_1 - timer_ac_lock_0),
        (timer_body_1 - timer_body_0),
        (timer_rl_lock_1 - timer_rl_lock_0)
    );
    printf_lock_release(&printf_lock);
    return pkg_ptr; // Return the package pointer
}

/*
   Each allocation is a fixed-size page (PAGE_SIZE bytes).
   The Node structure is placed at the beginning of the page and the remaining
   space is used for payload. Thus, available payload size is:
*/
#define PACKET_SIZE (PAGE_SIZE - sizeof(Node))

/* Consumer behavior (runs on core 0) */
static void consumer(const unsigned int core_id) {
    while (1) {
        Node *node = list_pop_front(&tosend_llist_lock);
        if (node != 0) {

            printf_lock_acquire(&printf_lock);
            printf("Consumer (core %u): processing node %p, data_size = %zu, data_src = 0x%x, data_tgt = 0x%x\n",
                   core_id, (void *)node, node->data_size, node->data, node->tgt);
            printf_lock_release(&printf_lock);

            // delay(100);  /* Simulate processing delay */

            uint32_t timer_mv_0, timer_mv_1;
            timer_mv_0 = benchmark_get_cycle();
            // vector_memcpy32_m4_opt(node->tgt, node->data, node->data_size);
            // vector_memcpy32_m8_opt(node->tgt, node->data, node->data_size);
            // scalar_memcpy32_32bit_unrolled(node->tgt, node->data, node->data_size);
            // vector_memcpy32_m8_m4_general_opt(node->tgt, node->data, node->data_size);
            // vector_memcpy32_1360B_opt(node->tgt, node->data);
            vector_memcpy32_1360B_opt_with_header(node->tgt, node->data, rlc_ctx.vtNext);
            timer_mv_1 = benchmark_get_cycle();

            // Increment the next available RLC sequence number
            rlc_ctx.vtNext++;

            printf_lock_acquire(&printf_lock);
            printf("Consumer (core %u): move node %p from data_src = 0x%x to data_tgt = 0x%x, data_size = %zu, cyc = %d, bw = %dB/1000cyc\n",
                   core_id, (void *)node, node->data, node->tgt, node->data_size,
                   (timer_mv_1 - timer_mv_0),
                   (node->data_size * 1000 / (timer_mv_1 - timer_mv_0)));
            printf_lock_release(&printf_lock);

            mm_free(node);
        } else {
            // delay(10);   /* Wait briefly if list is empty */
        }
    }
}

/* Producer behavior (runs on cores other than 0) */
static void producer(const unsigned int core_id) {
    printf_lock_acquire(&printf_lock);
    printf("Producer (core %u): pdcp_src_data[0][0] = %d, pdcp_src_data[6][500] = %d, pdcp_src_data[%d-1][%d-1] = %d\n",
        core_id,
        pdcp_src_data[0][0],
        pdcp_src_data[6][500],
        NUM_SRC_SLOTS,
        PDU_SIZE,
        pdcp_src_data[NUM_SRC_SLOTS-1][PDU_SIZE-1]);
    printf_lock_release(&printf_lock);
    int new_pdcp_pkg_ptr = pdcp_receive_pkg(core_id, &pdcp_pkd_ptr_lock);
    while (new_pdcp_pkg_ptr >= 0) {
        printf_lock_acquire(&printf_lock);
        printf("Producer (core %u): pdcp_receive_pkg id = %d, user_id = %d, pkg_length = %d, src_addr = 0x%x, tgt_addr = 0x%x\n",
            core_id,
            new_pdcp_pkg_ptr,
            pdcp_pkgs[new_pdcp_pkg_ptr].user_id,
            pdcp_pkgs[new_pdcp_pkg_ptr].pkg_length,
            pdcp_pkgs[new_pdcp_pkg_ptr].src_addr,
            pdcp_pkgs[new_pdcp_pkg_ptr].tgt_addr);
        printf_lock_release(&printf_lock);


        Node *node = (Node *)mm_alloc();
        if (!node) {

            printf_lock_acquire(&printf_lock);
            printf("Producer (core %u): Out of memory\n", core_id);
            printf_lock_release(&printf_lock);

            delay(200);  /* Delay before retrying */
            continue;
        }

        uint32_t timer_body_0, timer_body_1;

        timer_body_0 = benchmark_get_cycle();
        /* Initialize the node header */
        node->lock = 0;
        node->prev = 0;
        node->next = 0;
        /* Set the payload pointer immediately after the Node structure */
        node->data = (void *)((uint8_t *)(pdcp_pkgs[new_pdcp_pkg_ptr].src_addr));
        node->tgt = (void *)((uint8_t *)(pdcp_pkgs[new_pdcp_pkg_ptr].tgt_addr));
        node->data_size = pdcp_pkgs[new_pdcp_pkg_ptr].pkg_length;
        timer_body_1 = benchmark_get_cycle();

        printf_lock_acquire(&printf_lock);
        printf("[core %u][bd fill_node] mm_alloc: node = %p, data = 0x%x, tgt = 0x%x, data_size = %zu, bd=%d\n",
            core_id,
            (void *)node,
            node->data,
            node->tgt,
            node->data_size,
            (timer_body_1 - timer_body_0)
        );
        printf_lock_release(&printf_lock);


        // /* Zero-initialize the payload using our custom mm_memset */
        // mm_memset(node->data, 0, PACKET_SIZE);
        /* Append the node to the shared linked list */
        list_push_back(&tosend_llist_lock, node);

        printf_lock_acquire(&printf_lock);
        printf("Producer (core %u): added node %p, size = %d, src_addr = 0x%x, tgt_addr = 0x%x\n", 
            core_id,
            (void *)node,
            node->data_size,
            node->data,
            node->tgt);
        printf_lock_release(&printf_lock);

        // Get the pointer to the next PDCP package
        new_pdcp_pkg_ptr = pdcp_receive_pkg(core_id, &pdcp_pkd_ptr_lock);
        // delay(200);  /* Delay between node productions */
    }
}

/* cluster_entry() dispatches behavior based on core_id */
void cluster_entry(const unsigned int core_id) {
    if (core_id == 1) {
        consumer(core_id);
    } else if (core_id == 0) {
        producer(core_id);
    } else {
        while (1) {}
    }
}


void rlc_start(const unsigned int core_id) {
    /* Enter per-core processing based on core_id */
    cluster_entry(core_id);
}


#endif
