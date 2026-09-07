// Copyright 2020 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
#include "debug.h"
#include "snrt.h"
#include "team.h"

#define ALIGN_UP(addr, size) (((addr) + (size)-1) & ~((size)-1))

_Static_assert(sizeof(snrt_alloc_block_t) == SNRT_CACHELINE_SIZE,
               "snrt_alloc_block_t must be exactly one cacheline (64 bytes)");

// DRAM heap state. Modified by a single core only — no locking required.
static snrt_alloc_block_t *heap_head = NULL;
static uint32_t             heap_brk  = 0;

/**
 * @brief Allocate a cacheline-aligned block from DRAM.
 *
 * The requested size is rounded up to the next multiple of
 * SNRT_CACHELINE_SIZE by the runtime, so a request for 4 bytes
 * produces a 64-byte payload. The block header itself occupies exactly
 * one cacheline, so every header and every payload starts on a
 * cacheline boundary.
 *
 * Must be called by a single core only.
 *
 * @param size  Requested payload size in bytes.
 * @return Pointer to the payload, or NULL if size is 0.
 */
void *snrt_malloc(size_t size) {
    if (size == 0) return NULL;

    // Round payload up to cacheline boundary
    size = ALIGN_UP(size, SNRT_CACHELINE_SIZE);

    // First-fit: search for a free block of sufficient size
    snrt_alloc_block_t *block = heap_head;
    snrt_alloc_block_t *prev  = NULL;

    while (block != NULL) {
        if (block->free && block->size >= size) {
            // Split if the remainder fits a header + at least one payload cacheline
            if (block->size >= size + 2 * SNRT_CACHELINE_SIZE) {
                snrt_alloc_block_t *split =
                    (snrt_alloc_block_t *)((uint8_t *)block +
                                           SNRT_CACHELINE_SIZE + size);
                split->size = block->size - size - SNRT_CACHELINE_SIZE;
                split->free = 1;
                split->next = block->next;
                block->size = size;
                block->next = split;
            }
            block->free = 0;
            return (void *)((uint8_t *)block + SNRT_CACHELINE_SIZE);
        }
        prev  = block;
        block = block->next;
    }

    // No suitable free block — extend the heap
    snrt_alloc_block_t *new_block = (snrt_alloc_block_t *)heap_brk;
    new_block->size = size;
    new_block->free = 0;
    new_block->next = NULL;

    heap_brk = (uint32_t)((uint8_t *)new_block + SNRT_CACHELINE_SIZE + size);

    if (prev != NULL)
        prev->next = new_block;
    else
        heap_head = new_block;

    return (void *)((uint8_t *)new_block + SNRT_CACHELINE_SIZE);
}

/**
 * @brief Free a DRAM allocation and coalesce with following free blocks.
 *        Must be called by a single core only.
 *
 * @param ptr  Pointer returned by snrt_malloc. NULL is a no-op.
 */
void snrt_free(void *ptr) {
    if (ptr == NULL) return;

    snrt_alloc_block_t *block =
        (snrt_alloc_block_t *)((uint8_t *)ptr - SNRT_CACHELINE_SIZE);
    block->free = 1;

    // Coalesce with consecutive free blocks
    while (block->next != NULL && block->next->free) {
        block->size += SNRT_CACHELINE_SIZE + block->next->size;
        block->next  = block->next->next;
    }
}

/**
 * @brief Init the DRAM allocator
 *
 * @param l3off Number of bytes to skip on _edram before starting allocator
 */
void snrt_alloc_init(uint32_t l3off) {
    // DRAM linked-list allocator: starts cacheline-aligned after _edram + l3off
    extern uint32_t _edram;
    heap_brk  = ALIGN_UP((uint32_t)&_edram + l3off, SNRT_CACHELINE_SIZE);
    heap_head = NULL;
}
