#ifndef MM_C
#define MM_C

#include "mm.h"
#include <snrt.h>
#include <stdio.h>
#include <stddef.h>
#include <l1cache.h>
#include "printf.h"
#include "debug.h"

/* Simple spinlock functions using GCC built‑ins */
static inline void mm_lock_acquire(volatile int *lock) {
    while (__sync_lock_test_and_set(lock, 1)) { }
}

static inline void mm_lock_release(volatile int *lock) {
    asm volatile (
        "amoswap.w zero, zero, %0"
        : "+A" (*lock)
    );
}


/* mm_init: Only core 0 initializes the mm_context_t; others do nothing. */
void mm_init() {
    mm_ctx.buffer = (uint8_t *)snrt_l1alloc(BUFFER_SIZE);
    if (!mm_ctx.buffer) {
        fprintf(stderr, "mm_init: Failed to allocate %d bytes from L1\n", BUFFER_SIZE);
        /* In a baremetal system you might want to halt or trigger an error */
    }
    mm_ctx.alloc_offset = 0;
    mm_ctx.free_list = NULL;
    mm_ctx.lock = 0;
}

/* mm_alloc: Returns a fresh page from the pool if available; otherwise, recycles from free_list. */
void *mm_alloc() {
    void *page = NULL;
    // mm_lock_acquire(&ctx->lock);
    mm_lock_acquire(&mm_lock);
    debug_printf("[core_id %u][mm_alloc] mm_lock_acquire\n", snrt_cluster_core_idx());
    if (mm_ctx.alloc_offset + PAGE_SIZE <= BUFFER_SIZE) {
        page = mm_ctx.buffer + mm_ctx.alloc_offset;
        mm_ctx.alloc_offset += PAGE_SIZE;
    } else {
        if (mm_ctx.free_list != NULL) {
            page = (void *)mm_ctx.free_list;
            mm_ctx.free_list = mm_ctx.free_list->next;
        } else {
            page = NULL;  /* Out of memory */
        }
    }
    
    debug_printf("[core_id %u][mm_alloc] mm_lock_release\n", snrt_cluster_core_idx());
    // mm_lock_release(&ctx->lock);
    mm_lock_release(&mm_lock);
    return page;
}

/* mm_free: Recycles the page by pushing it onto the free list. */
void mm_free(void *p) {
    if (!p)
        return;
    
    // mm_lock_acquire(&ctx->lock);
    mm_lock_acquire(&mm_lock);
    debug_printf("[core_id %u][mm_free] mm_lock_release\n", snrt_cluster_core_idx());
    MM_FreePage *fp = (MM_FreePage *)p;
    fp->next = mm_ctx.free_list;
    mm_ctx.free_list = fp;
    debug_printf("[core_id %u][mm_free] mm_lock_release\n", snrt_cluster_core_idx());
    // mm_lock_release(&ctx->lock);
    mm_lock_release(&mm_lock);
}

/* mm_memset: Custom implementation that fills dest with the specified value. */
void *mm_memset(void *dest, int value, size_t count) {
    unsigned char *ptr = (unsigned char *)dest;
    while(count--) {
        *ptr++ = (unsigned char)value;
    }
    return dest;
}

/* mm_cleanup: Reset the memory management state. */
void mm_cleanup() {
    mm_ctx.alloc_offset = 0;
    mm_ctx.free_list = NULL;
}


#endif

