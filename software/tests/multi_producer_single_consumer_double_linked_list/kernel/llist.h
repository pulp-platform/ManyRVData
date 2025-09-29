#ifndef LLIST_H
#define LLIST_H

#include <stddef.h>
#include "printf_lock.h"
#include "mcs_lock.h"
// #include "spin_lock.h"

/* --- Simple spinlock implementation --- */
/* We use a volatile int as a spinlock. Zero means unlocked. */
typedef volatile int spinlock_t __attribute__((aligned(4)));

spinlock_t tosend_llist_lock __attribute__((section(".data")));
spinlock_t sent_llist_lock __attribute__((section(".data")));
static _Atomic mcs_lock_t tosend_llist_lock_2 __attribute__((aligned(4))) __attribute__((section(".data")));
static _Atomic mcs_lock_t sent_llist_lock_2 __attribute__((aligned(4))) __attribute__((section(".data")));

static inline void spin_lock(spinlock_t *lock, int cycle) {
    while (__sync_lock_test_and_set(lock, 1)) { delay(cycle);}
}

static inline void spin_unlock(volatile int *lock, int cycle) {
   asm volatile (
       "amoswap.w zero, zero, %0"
       : "+A" (*lock)
   );
   delay(cycle);
}


/* Node structure representing a packet or data element.
   The node structure is stored at the beginning of a fixed‐size page;
   the remainder of the page may be used as payload.
*/
typedef struct Node {
    struct Node *prev;
    struct Node *next;
    void *data;         /* Pointer to the payload data */
    void *tgt;          /* Pointer to the address to move the payload data to */
    size_t data_size;   /* Size of the payload in bytes */
    spinlock_t lock;    /* Per‑node lock (0: unlocked, 1: locked) */
} Node;

/* Doubly‑linked list structure for storing Node pointers.
   All operations require a pointer to an instance of LinkedList.
*/
typedef struct {
    Node *head __attribute__((aligned(4)));
    Node *tail __attribute__((aligned(4)));
    int sduNum __attribute__((aligned(4)));   /* Number of SDUs to be sent */
    int sduBytes __attribute__((aligned(4)));/* Number of SUDs bytes to be sent */
    spinlock_t lock __attribute__((aligned(4)));  /* Global lock protecting the list structure */
} LinkedList;

/*
   list_init() initializes the given LinkedList instance.
   It sets the head and tail pointers to NULL and the lock to 0.
*/
void list_init(LinkedList *list);

/*
   list_push_back() appends a given Node to the end of the list.
   It is safe for concurrent use by multiple producers.
*/
void list_push_back(spinlock_t *llist_lock, LinkedList *list, volatile Node *node);

/*
   list_pop_front() removes and returns the node from the front of the list.
   This function should be used by a single consumer.
   If the list is empty, it returns NULL.
*/
Node *list_pop_front(spinlock_t *llist_lock, LinkedList *list);

/*
   list_remove() removes a specific Node from anywhere in the list.
   This function adjusts the pointers of neighboring nodes appropriately.
*/
void list_remove(spinlock_t *llist_lock, LinkedList *list, Node *node);

#endif /* LLIST_H */
