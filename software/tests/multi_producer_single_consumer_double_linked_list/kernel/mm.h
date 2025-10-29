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

#ifndef MM_H
#define MM_H

#include <stddef.h>
#include <stdint.h>
#include "llist.h"

// #define PAGE_SIZE (1024)                 /* Fixed size of each memory page in bytes */
#define PAGE_SIZE (sizeof(Node))          /* Fixed size of each memory page in bytes */
#define BUFFER_SIZE (PAGE_SIZE * 1024)      /* memory pool size in byte */

static uint32_t bulk_buffer[BUFFER_SIZE / sizeof(uint32_t)]
   __attribute__((section(".dram")))
   __attribute__((aligned(32)));

spinlock_t mm_lock __attribute__((section(".data")));

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

mm_context_t mm_ctx __attribute__((section(".data")));

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
