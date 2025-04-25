#ifndef LLIST_C
#define LLIST_C

#include "llist.h"
#include <snrt.h>
#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>
#include <l1cache.h>
#include "printf.h"
#include "debug.h"

void list_init(LinkedList *list) {
    list->head = NULL;
    list->tail = NULL;
    /* Set the list lock to 0 (unlocked) */
    list->lock = 0;
}

void list_push_back(LinkedList *list, Node *node) {
    /* Acquire the list lock to ensure exclusive access while modifying the list */
    // spin_lock(&list->lock);
    spin_lock(&llist_lock);
    debug_printf("[core_id %u][list_push_back] spin_lock\n", snrt_cluster_core_idx());
    node->next = NULL;
    node->prev = list->tail;
    if (list->tail != NULL) {
        list->tail->next = node;
    } else {
        /* If the list is empty, set the head to the new node */
        list->head = node;
    }
    list->tail = node;
    debug_printf("[core_id %u][list_push_back] spin_unlock\n", snrt_cluster_core_idx());
    // spin_unlock(&list->lock);
    spin_unlock(&llist_lock);
}

Node *list_pop_front(LinkedList *list) {
    Node *node = NULL;
    // spin_lock(&list->lock);
    spin_lock(&llist_lock);
    debug_printf("[core_id %u][list_pop_front] spin_lock\n", snrt_cluster_core_idx());
    if (list->head != NULL) {
        node = list->head;
        list->head = node->next;
        if (list->head != NULL) {
            list->head->prev = NULL;
        } else {
            /* List becomes empty, so tail is also NULL */
            list->tail = NULL;
        }
        node->next = NULL;
        node->prev = NULL;
    }
    debug_printf("[core_id %u][list_pop_front] spin_unlock\n", snrt_cluster_core_idx());
    // spin_unlock(&list->lock);
    spin_unlock(&llist_lock);
    return node;
}

void list_remove(LinkedList *list, Node *node) {
    // spin_lock(&list->lock);
    spin_lock(&llist_lock);
    debug_printf("[core_id %u][list_remove] spin_lock\n", snrt_cluster_core_idx());
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
    debug_printf("[core_id %u][list_remove] spin_unlock\n", snrt_cluster_core_idx());
    // spin_unlock(&list->lock);
    spin_unlock(&llist_lock);
}


#endif
