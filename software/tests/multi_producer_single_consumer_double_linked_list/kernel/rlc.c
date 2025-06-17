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
#include "printf_lock.h"

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
static void consumer(const unsigned int core_id) {
    while (1) {
        Node *node = list_pop_front();
        if (node != 0) {

            printf_lock_acquire(&printf_lock);
            printf("Consumer (core %u): processing node %p with data size %zu\n",
                   core_id, (void *)node, node->data_size);
            printf_lock_release(&printf_lock);

            delay(100);  /* Simulate processing delay */
            mm_free(node);
        } else {
            delay(10);   /* Wait briefly if list is empty */
        }
    }
}

/* Producer behavior (runs on cores other than 0) */
static void producer(const unsigned int core_id) {
    while (1) {
        Node *node = (Node *)mm_alloc();
        if (!node) {

            printf_lock_acquire(&printf_lock);
            printf("Producer (core %u): Out of memory\n", core_id);
            printf_lock_release(&printf_lock);

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
        list_push_back(node);

        printf_lock_acquire(&printf_lock);
        printf("Producer (core %u): added node %p\n", core_id, (void *)node);
        printf_lock_release(&printf_lock);

        delay(200);  /* Delay between node productions */
    }
}

/* cluster_entry() dispatches behavior based on core_id */
void cluster_entry(const unsigned int core_id) {
    if (core_id == 0) {
        consumer(core_id);
    } else if (core_id == 1) {
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
