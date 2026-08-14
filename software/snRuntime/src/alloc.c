// Copyright 2020 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
#include "debug.h"
#include "snrt.h"
#include "team.h"

#define ALIGN_UP(addr, size) (((addr) + (size)-1) & ~((size)-1))
#define ALIGN_DOWN(addr, size) ((addr) & ~((size)-1))

#define MIN_CHUNK_SIZE 8

/**
 * @brief Allocate a chunk of memory in the L1 memory
 * @details This currently does not support free-ing of memory
 *
 * @param size number of bytes to allocate
 * @return pointer to the allocated memory
 */
void *snrt_l1alloc(size_t size) {
    struct snrt_allocator_inst *alloc = &snrt_current_team()->allocator.l1;

    size = ALIGN_UP(size, MIN_CHUNK_SIZE);

    if (alloc->next + size > alloc->base + alloc->size) {
        snrt_trace(
            SNRT_TRACE_ALLOC,
            "Not enough memory to allocate: base %#x size %#x next %#x\n",
            alloc->base, alloc->size, alloc->next);
        return 0;
    }

    void *ret = (void *)alloc->next;
    alloc->next += size;
    return ret;
}

/**
 * @brief Free all allocated region in L1 memory
 * @details We'd better free all regions beore reconfiguring
 */
void snrt_l1alloc_reset() {
    struct snrt_allocator_inst *alloc = &snrt_current_team()->allocator.l1;
    // Reset next pointer to base
    alloc->next = alloc->base;
}

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
 * @brief Init the allocator
 * @details
 *
 * @param snrt_team_root pointer to the team structure
 * @param l3off Number of bytes to skip on _edram before starting allocator
 */
void snrt_alloc_init(struct snrt_team_root *team, uint32_t l3off) {
    // Allocator in L1 TCDM memory
    team->allocator.l1.base =
        ALIGN_UP((uint32_t)team->cluster_mem.start, MIN_CHUNK_SIZE);
    team->allocator.l1.size =
        (uint32_t)(team->cluster_mem.end - team->cluster_mem.start);
    team->allocator.l1.next = team->allocator.l1.base;
    // DRAM linked-list allocator: starts cacheline-aligned after _edram + l3off
    extern uint32_t _edram;
    heap_brk  = ALIGN_UP((uint32_t)&_edram + l3off, SNRT_CACHELINE_SIZE);
    heap_head = NULL;
}
