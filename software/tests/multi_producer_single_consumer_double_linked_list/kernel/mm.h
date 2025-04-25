#ifndef MM_H
#define MM_H

#include <stddef.h>
#include <stdint.h>
#include "llist.h"

#define PAGE_SIZE (1024)             /* Fixed size of each memory page in bytes */
#define BUFFER_SIZE (1024 * 1024)      /* 1MB memory pool size */

spinlock_t mm_lock;

/* Type for free list entries */
typedef struct MM_FreePage {
    struct MM_FreePage *next;
} MM_FreePage;

/* Memory management context. All state is stored here. */
typedef struct {
    uint8_t *buffer;      /* Pointer to the memory pool allocated from L1 */
    size_t alloc_offset;  /* Current allocation offset */
    MM_FreePage *free_list;  /* Free list of recycled pages */
    spinlock_t lock;    /* Spinlock for mutual exclusion */
} mm_context_t __attribute__((aligned(8)));

mm_context_t mm_ctx;

/* 
   mm_init() initializes the memory management context.
*/
void mm_init();

/* Allocate one page (PAGE_SIZE bytes) from the memory pool.
   Returns a pointer to the allocated page or NULL if out-of-memory.
*/
void *mm_alloc();

/* Free a previously allocated page.
   The page is added to the free list for later reuse.
*/
void mm_free(void *p);

/* 
   A simple custom memset implementation that fills count bytes in dest
   with the given value.
*/
void *mm_memset(void *dest, int value, size_t count);

/* Reset the mm_context_t state.
   In a baremetal system, this might simply reset the allocation pointer and free list.
*/
void mm_cleanup();

#endif
