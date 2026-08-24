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

#ifndef LLIST_C
#define LLIST_C

#undef  USE_MCS_LOCK
// #define USE_MCS_LOCK

#include "mcs_lock.h"
#include "llist.h"
#include "rlc.h"
#include <snrt.h>
#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>
#include <l1cache.h>
#include "printf.h"
#include "printf_lock.h"
#include "benchmark.h"

void list_init(LinkedList *list) {
    list->head = NULL;
    list->tail = NULL;
    list->sduNum = 0;
    list->sduBytes = 0;
    /* Set the list lock to 0 (unlocked) */
    list->lock = 0;
}

void list_push_back(spinlock_t *llist_lock, LinkedList *list, volatile Node *node) {
    uint32_t core_id = snrt_cluster_core_idx();
    uint32_t timer_ac_lock_0, timer_ac_lock_1;
    uint32_t timer_rl_lock_0, timer_rl_lock_1;
    uint32_t timer_body_0, timer_body_1;

    /* Acquire the list lock to ensure exclusive access while modifying the list */
    // spin_lock(&list->lock);
    // timer_ac_lock_0 = benchmark_get_cycle();
#ifdef USE_MCS_LOCK
    mcs_lock_acquire(llist_lock, 10);
#else
    spin_lock(llist_lock, 10);
#endif
    // timer_ac_lock_1 = benchmark_get_cycle();

    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u][list_push_back] spin_lock\n", core_id);
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

    // timer_body_0 = benchmark_get_cycle();
    node->next = NULL;
    node->prev = list->tail;

    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u][list_push_back] list->tail=0x%x\n",
    //     core_id, list->tail);
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
    if (list->tail != NULL) {
        list->tail->next = node;
    } else {
        /* If the list is empty, set the head to the new node */
        list->head = node;
    }
    list->tail = node;
    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u][list_push_back] list->head=0x%x, list->tail=0x%x\n",
    //     core_id, list->head, list->tail);
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
    list->sduNum++;
    list->sduBytes += node->data_size;
    // timer_body_1 = benchmark_get_cycle();

    // spin_unlock(&list->lock);
    // timer_rl_lock_0 = benchmark_get_cycle();
#ifdef USE_MCS_LOCK
    mcs_lock_release(llist_lock, 10);
#else
    spin_unlock(llist_lock, 10);
#endif
    // timer_rl_lock_1 = benchmark_get_cycle();

    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u][list_push_back] spin_unlock, node=%p, \
    //     list->head=0x%x, list->tail=0x%x, ac=%d, bd=%d, rl=%d\n",
    //     core_id,
    //     (void *)node,
    //     list->head,
    //     list->tail,
    //     (timer_ac_lock_1 - timer_ac_lock_0),
    //     (timer_body_1 - timer_body_0),
    //     (timer_rl_lock_1 - timer_rl_lock_0)
    // );
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
}

Node *list_pop_front(spinlock_t *llist_lock, LinkedList *list) {
    uint32_t core_id = snrt_cluster_core_idx();
    uint32_t timer_ac_lock_0, timer_ac_lock_1;
    uint32_t timer_rl_lock_0, timer_rl_lock_1;
    uint32_t timer_body_0, timer_body_1;

    Node *node = NULL;
    // spin_lock(&list->lock);
    // timer_ac_lock_0 = benchmark_get_cycle();
#ifdef USE_MCS_LOCK
    mcs_lock_acquire(llist_lock, 10);
#else
    spin_lock(llist_lock, 10);
#endif
    // timer_ac_lock_1 = benchmark_get_cycle();

    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u][list_pop_front] spin_lock\n", core_id);
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

    // timer_body_0 = benchmark_get_cycle();
    if (list->head != NULL) {
        node = list->head;
        list->head = node->next;

        // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
        // DEBUG_PRINTF("[core %u][list_pop_front] p1\n", core_id);
        // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

        if (list->head != NULL) {
            list->head->prev = NULL;

            // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
            // DEBUG_PRINTF("[core %u][list_pop_front] p2\n", core_id);
            // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

        } else {
            /* List becomes empty, so tail is also NULL */
            list->tail = NULL;


            // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
            // DEBUG_PRINTF("[core %u][list_pop_front] p3\n", core_id);
            // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
        }
        node->next = NULL;
        node->prev = NULL;
        list->sduNum--;
        list->sduBytes -= node->data_size;
    }
    // timer_body_1 = benchmark_get_cycle();


    // spin_unlock(&list->lock);
    // timer_rl_lock_0 = benchmark_get_cycle();
#ifdef USE_MCS_LOCK
    mcs_lock_release(llist_lock, 10);
#else
    spin_unlock(llist_lock, 10);
#endif
    // timer_rl_lock_1 = benchmark_get_cycle();

    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u][list_pop_front] spin_unlock, node=%p, ac=%d, bd=%d, rl=%d\n", 
    //     core_id,
    //     (void *)node,
    //     (timer_ac_lock_1 - timer_ac_lock_0),
    //     (timer_body_1 - timer_body_0),
    //     (timer_rl_lock_1 - timer_rl_lock_0)
    // );
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

    return node;
}

void list_remove(spinlock_t *llist_lock, LinkedList *list, Node *node) {
    // spin_lock(&list->lock);
    spin_lock(llist_lock, 20);

    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u][list_remove] spin_lock\n", snrt_cluster_core_idx());
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

    if (node->prev != NULL) {
        node->prev->next = node->next;
    } else {
        /* If removing the head */
        list->head = node->next;
    }
    if (node->next != NULL) {
        node->next->prev = node->prev;
    } else {
        /* If removing the tail */
        list->tail = node->prev;
    }
    node->prev = NULL;
    node->next = NULL;

    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u][list_remove] spin_unlock\n", snrt_cluster_core_idx());
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

    // spin_unlock(&list->lock);
    spin_unlock(llist_lock, 20);
}


#endif
