#ifndef LLIST_H
#define LLIST_H

#include <stddef.h>

/* --- Simple spinlock implementation --- */
/* We use a volatile int as a spinlock. Zero means unlocked. */
typedef volatile int spinlock_t __attribute__((aligned(8)));

static inline void spin_lock(spinlock_t *lock) {
    while (__sync_lock_test_and_set(lock, 1)) { }
}

static inline void spin_unlock(volatile int *lock) {
   asm volatile (
       "amoswap.w zero, zero, %0"
       : "+A" (*lock)
   );
}


/* Node structure representing a packet or data element.
   The node structure is stored at the beginning of a fixed‐size page;
   the remainder of the page may be used as payload.
*/
typedef struct Node {
    struct Node *prev;
    struct Node *next;
    void *data;         /* Pointer to the payload data */
    size_t data_size;   /* Size of the payload in bytes */
    spinlock_t lock;    /* Per‑node lock (0: unlocked, 1: locked) */
} Node;

/* Doubly‑linked list structure for storing Node pointers.
   All operations require a pointer to an instance of LinkedList.
*/
typedef struct {
    Node *head;
    Node *tail;
    spinlock_t lock;    /* Global lock protecting the list structure */
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
void list_push_back(LinkedList *list, Node *node);

/* 
   list_pop_front() removes and returns the node from the front of the list.
   This function should be used by a single consumer.
   If the list is empty, it returns NULL.
*/
Node *list_pop_front(LinkedList *list);

/* 
   list_remove() removes a specific Node from anywhere in the list.
   This function adjusts the pointers of neighboring nodes appropriately.
*/
void list_remove(LinkedList *list, Node *node);

#endif /* LLIST_H */
