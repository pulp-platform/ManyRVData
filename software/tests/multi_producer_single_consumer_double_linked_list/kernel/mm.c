#ifndef MM_C
#define MM_C

#include "mm.h"
#include <snrt.h>
#include <stdio.h>
#include <stddef.h>
#include <l1cache.h>
#include "printf.h"
#include "printf_lock.h"

/* Simple spinlock functions using GCC built‑ins */
static inline void mm_lock_acquire(volatile int *lock) {
    while (__sync_lock_test_and_set(lock, 1)) { delay(20); }
}

static inline void mm_lock_release(volatile int *lock) {
    asm volatile (
        "amoswap.w zero, zero, %0"
        : "+A" (*lock)
    );
    delay(20);
}


/* mm_init: Only core 0 initializes the mm_context_t; others do nothing. */
void mm_init() {
    // mm_ctx.buffer = (uint8_t *)snrt_l1alloc(BUFFER_SIZE);
    mm_ctx.buffer = bulk_buffer;
    if (!bulk_buffer) {

        DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
        DEBUG_PRINTF("mm_init: Failed to allocate %d bytes from L1\n", BUFFER_SIZE);
        DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

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

    uint32_t timer_ac_lock_0, timer_ac_lock_1;
    uint32_t timer_rl_lock_0, timer_rl_lock_1;
    uint32_t timer_mm_alloc_0, timer_mm_alloc_1;

    timer_ac_lock_0 = benchmark_get_cycle();
    mm_lock_acquire(&mm_lock);
    timer_ac_lock_1 = benchmark_get_cycle();

    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u][mm_alloc] mm_lock_acquire\n", snrt_cluster_core_idx());
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

    timer_mm_alloc_0 = benchmark_get_cycle();


    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u][mm_alloc] mm_ctx.alloc_offset=%d, PAGE_SIZE=%d, BUFFER_SIZE=%d\n", 
    //     snrt_cluster_core_idx(), mm_ctx.alloc_offset, PAGE_SIZE, BUFFER_SIZE);
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

    if (mm_ctx.alloc_offset + PAGE_SIZE <= BUFFER_SIZE) {
        page = bulk_buffer + (mm_ctx.alloc_offset / sizeof(uint32_t));
        mm_ctx.alloc_offset += PAGE_SIZE;

        // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
        // DEBUG_PRINTF("[core %u][mm_alloc] stage 1, bulk_buffer=0x%x, mm_ctx.alloc_offset=0x%x, page=0x%x\n", 
        //     snrt_cluster_core_idx(), bulk_buffer, mm_ctx.alloc_offset, page);
        // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
    } else {
        if (mm_ctx.free_list != NULL) {
            page = (void *)mm_ctx.free_list;
            mm_ctx.free_list = mm_ctx.free_list->next;

            // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
            // DEBUG_PRINTF("[core %u][mm_alloc] stage 2, page=0x%x\n", snrt_cluster_core_idx(), page);
            // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
        } else {
            page = NULL;  /* Out of memory */

            DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
            DEBUG_PRINTF("[core %u][mm_alloc] Out of memory\n", snrt_cluster_core_idx());
            DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
        }
    }
    timer_mm_alloc_1 = benchmark_get_cycle();

    // mm_lock_release(&ctx->lock);
    timer_rl_lock_0 = benchmark_get_cycle();
    mm_lock_release(&mm_lock);
    timer_rl_lock_1 = benchmark_get_cycle();

    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u][mm_alloc] mm_lock_release, page=0x%x, ac=%d, mm=%d, rl=%d cycles\n", 
    //     snrt_cluster_core_idx(),
    //     page,
    //     (timer_ac_lock_1 - timer_ac_lock_0),
    //     (timer_mm_alloc_1 - timer_mm_alloc_0),
    //     (timer_rl_lock_1 - timer_rl_lock_0));
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
    return page;
}

/* mm_free: Recycles the page by pushing it onto the free list. */
void mm_free(void *p) {
    if (!p)
        return;

    uint32_t timer_ac_lock_0, timer_ac_lock_1;
    uint32_t timer_rl_lock_0, timer_rl_lock_1;
    uint32_t timer_mm_free_0, timer_mm_free_1;
    // mm_lock_acquire(&ctx->lock);
    timer_ac_lock_0 = benchmark_get_cycle();
    mm_lock_acquire(&mm_lock);
    timer_ac_lock_1 = benchmark_get_cycle();

    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u][mm_free] mm_lock_acquire\n", snrt_cluster_core_idx());
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

    timer_mm_free_0 = benchmark_get_cycle();
    MM_FreePage *fp = (MM_FreePage *)p;
    fp->next = mm_ctx.free_list;
    mm_ctx.free_list = fp;
    timer_mm_free_1 = benchmark_get_cycle();

    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u][mm_free] mm_lock_release\n", snrt_cluster_core_idx());
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);

    // mm_lock_release(&ctx->lock);
    timer_rl_lock_0 = benchmark_get_cycle();
    mm_lock_release(&mm_lock);
    timer_rl_lock_1 = benchmark_get_cycle();

    // DEBUG_PRINTF_LOCK_ACQUIRE(&printf_lock);
    // DEBUG_PRINTF("[core %u][mm_free] ac = %d, bd = %d, rl = %d\n",
    //     snrt_cluster_core_idx(),
    //     (timer_ac_lock_1 - timer_ac_lock_0),
    //     (timer_mm_free_1 - timer_mm_free_0),
    //     (timer_rl_lock_1 - timer_rl_lock_0));
    // DEBUG_PRINTF_LOCK_RELEASE(&printf_lock);
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

