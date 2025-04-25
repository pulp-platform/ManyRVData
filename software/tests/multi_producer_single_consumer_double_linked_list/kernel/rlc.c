#ifndef RLC_C
#define RLC_C

#include "rlc.h"
#include "mm.h"
#include "llist.c"
#include <snrt.h>
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <l1cache.h>
#include "printf.h"
#include "debug.h"

/* 
   Each allocation is a fixed-size page (PAGE_SIZE bytes).
   The Node structure is placed at the beginning of the page and the remaining
   space is used for payload. Thus, available payload size is:
*/
#define PACKET_SIZE (PAGE_SIZE - sizeof(Node))

/* A simple busy-loop delay function. Adjust iterations as needed. */
static void delay(volatile int iterations) {
    for (; iterations > 0; iterations--);
}

/* Consumer behavior (runs on core 0) */
static void consumer(rlc_context_t *ctx, const unsigned int core_id) {
    while (1) {
        Node *node = list_pop_front(&ctx->list);
        if (node != 0) {
            printf("Consumer (core %u): processing node %p with data size %zu\n",
                   core_id, (void *)node, node->data_size);
            delay(100);  /* Simulate processing delay */
            mm_free(ctx->mm_ctx, node);
        } else {
            delay(10);   /* Wait briefly if list is empty */
        }
    }
}

/* Producer behavior (runs on cores other than 0) */
static void producer(rlc_context_t *ctx, const unsigned int core_id) {
    ctx->mm_ctx->lock = 0;
    while (1) {
        Node *node = (Node *)mm_alloc(ctx->mm_ctx);
        if (!node) {
            printf("Producer (core %u): Out of memory\n", core_id);
            delay(200);  /* Delay before retrying */
            continue;
        }
        /* Initialize the node header */
        node->lock = 0;
        node->prev = 0;
        node->next = 0;
        /* Set the payload pointer immediately after the Node structure */
        node->data = (void *)((uint8_t *)node + sizeof(Node));
        node->data_size = PACKET_SIZE;
        /* Zero-initialize the payload using our custom mm_memset */
        mm_memset(node->data, 0, PACKET_SIZE);
        /* Append the node to the shared linked list */
        list_push_back(&ctx->list, node);
        printf("Producer (core %u): added node %p\n", core_id, (void *)node);
        delay(200);  /* Delay between node productions */
    }
}

/* cluster_entry() dispatches behavior based on core_id */
void cluster_entry(rlc_context_t *ctx, const unsigned int core_id) {
    if (core_id == 0) {
        consumer(ctx, core_id);
    } else {
        producer(ctx, core_id);
    }
}


void rlc_start(rlc_context_t *ctx, const unsigned int core_id) {
    /* Enter per-core processing based on core_id */
    cluster_entry(ctx, core_id);
}


#endif
