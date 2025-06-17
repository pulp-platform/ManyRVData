#ifndef LLIST_C
#define LLIST_C

#include "llist.h"
#include "rlc.h"
#include <snrt.h>
#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>
#include <l1cache.h>
#include "printf.h"
#include "printf_lock.h"

void list_init() {
    rlc_ctx.list.head = NULL;
    rlc_ctx.list.tail = NULL;
    rlc_ctx.list.sduNum = 0;
    rlc_ctx.list.sduBytes = 0;
    /* Set the list lock to 0 (unlocked) */
    rlc_ctx.list.lock = 0;
}

void list_push_back(volatile Node *node) {
    uint32_t timer_ac_lock_0, timer_ac_lock_1;
    uint32_t timer_rl_lock_0, timer_rl_lock_1;
    uint32_t timer_body_0, timer_body_1;

    /* Acquire the list lock to ensure exclusive access while modifying the list */
    // spin_lock(&list->lock);
    timer_ac_lock_0 = benchmark_get_cycle();
    spin_lock(&llist_lock);
    timer_ac_lock_1 = benchmark_get_cycle();

    printf_lock_acquire(&printf_lock);
    printf("[core %u][list_push_back] spin_lock\n", snrt_cluster_core_idx());
    printf_lock_release(&printf_lock);

    timer_body_0 = benchmark_get_cycle();
    node->next = NULL;
    node->prev = rlc_ctx.list.tail;

    printf_lock_acquire(&printf_lock);
    printf("[core %u][list_push_back] rlc_ctx.list.tail=0x%x\n", 
        snrt_cluster_core_idx(), rlc_ctx.list.tail);
    printf_lock_release(&printf_lock);
    if (rlc_ctx.list.tail != NULL) {
        rlc_ctx.list.tail->next = node;
    } else {
        /* If the list is empty, set the head to the new node */
        rlc_ctx.list.head = node;
    }
    rlc_ctx.list.tail = node;
    printf("[core %u][list_push_back] rlc_ctx.list.head=0x%x, rlc_ctx.list.tail=0x%x\n", 
        snrt_cluster_core_idx(), rlc_ctx.list.head, rlc_ctx.list.tail);
    rlc_ctx.list.sduNum++;
    rlc_ctx.list.sduBytes += node->data_size;
    timer_body_1 = benchmark_get_cycle();
    
    // spin_unlock(&list->lock);
    timer_rl_lock_0 = benchmark_get_cycle();
    spin_unlock(&llist_lock);
    timer_rl_lock_1 = benchmark_get_cycle();
    
    printf_lock_acquire(&printf_lock);
    printf("[core %u][list_push_back] spin_unlock, node=0x%x, \
        rlc_ctx.list.head=0x%x, rlc_ctx.list.tail=0x%x, ac=%d, bd=%d, rl=%d\n",
        snrt_cluster_core_idx(),
        node,
        rlc_ctx.list.head,
        rlc_ctx.list.tail,
        (timer_ac_lock_1 - timer_ac_lock_0),
        (timer_body_1 - timer_body_0),
        (timer_rl_lock_1 - timer_rl_lock_0)
    );
    printf_lock_release(&printf_lock);
}

Node *list_pop_front() {
    uint32_t timer_ac_lock_0, timer_ac_lock_1;
    uint32_t timer_rl_lock_0, timer_rl_lock_1;
    uint32_t timer_body_0, timer_body_1;

    Node *node = NULL;
    // spin_lock(&list->lock);
    timer_ac_lock_0 = benchmark_get_cycle();
    spin_lock(&llist_lock);
    timer_ac_lock_1 = benchmark_get_cycle();

    printf_lock_acquire(&printf_lock);
    printf("[core %u][list_pop_front] spin_lock\n", snrt_cluster_core_idx());
    printf_lock_release(&printf_lock);

    timer_body_0 = benchmark_get_cycle();
    if (rlc_ctx.list.head != NULL) {
        node = rlc_ctx.list.head;
        rlc_ctx.list.head = node->next;

        printf_lock_acquire(&printf_lock);
        printf("[core %u][list_pop_front] p1\n", snrt_cluster_core_idx());
        printf_lock_release(&printf_lock);

        if (rlc_ctx.list.head != NULL) {
            rlc_ctx.list.head->prev = NULL;

            printf_lock_acquire(&printf_lock);
            printf("[core %u][list_pop_front] p2\n", snrt_cluster_core_idx());
            printf_lock_release(&printf_lock);

        } else {
            /* List becomes empty, so tail is also NULL */
            rlc_ctx.list.tail = NULL;


            printf_lock_acquire(&printf_lock);
            printf("[core %u][list_pop_front] p3\n", snrt_cluster_core_idx());
            printf_lock_release(&printf_lock);
        }
        node->next = NULL;
        node->prev = NULL;
        rlc_ctx.list.sduNum--;
        rlc_ctx.list.sduBytes -= node->data_size;
    }
    timer_body_1 = benchmark_get_cycle();

    
    // spin_unlock(&list->lock);
    timer_rl_lock_0 = benchmark_get_cycle();
    spin_unlock(&llist_lock);
    timer_rl_lock_1 = benchmark_get_cycle();

    printf_lock_acquire(&printf_lock);
    printf("[core %u][list_pop_front] spin_unlock, node=0x%x, ac=%d, bd=%d, rl=%d\n", 
        snrt_cluster_core_idx(),
        node,
        (timer_ac_lock_1 - timer_ac_lock_0),
        (timer_body_1 - timer_body_0),
        (timer_rl_lock_1 - timer_rl_lock_0)
    );
    printf_lock_release(&printf_lock);

    return node;
}

void list_remove(LinkedList *list, Node *node) {
    // spin_lock(&list->lock);
    spin_lock(&llist_lock);

    printf_lock_acquire(&printf_lock);
    printf("[core %u][list_remove] spin_lock\n", snrt_cluster_core_idx());
    printf_lock_release(&printf_lock);

    if (node->prev != NULL) {
        node->prev->next = node->next;
    } else {
        /* If removing the head */
        rlc_ctx.list.head = node->next;
    }
    if (node->next != NULL) {
        node->next->prev = node->prev;
    } else {
        /* If removing the tail */
        rlc_ctx.list.tail = node->prev;
    }
    node->prev = NULL;
    node->next = NULL;

    printf_lock_acquire(&printf_lock);
    printf("[core %u][list_remove] spin_unlock\n", snrt_cluster_core_idx());
    printf_lock_release(&printf_lock);

    // spin_unlock(&list->lock);
    spin_unlock(&llist_lock);
}


#endif
