#ifndef RLC_H
#define RLC_H

#include "mm.h"
#include "llist.h"
#include "data_move_vec.h"

/* rlc_context_t holds the RLC kernel state:
   - 'list': the linked list used to store packet nodes.
   - 'mm_ctx': a pointer to the memory management context.
*/
typedef struct {
    LinkedList list;
    mm_context_t *mm_ctx;
} rlc_context_t;

volatile rlc_context_t rlc_ctx;

/* 
   rlc_start() initializes shared RLC resources and starts the RLC kernel 
   for the current core. The core ID, obtained in main(), is passed here.
*/
void rlc_start(const unsigned int core_id);

/*
   cluster_entry() is the per-core entry function for the RLC kernel.
   Depending on the core ID (passed as a parameter), it calls consumer() if core_id is 0,
   or producer() otherwise.
*/
void cluster_entry(const unsigned int core_id);

/*
   pdcp_pkd_ptr is a pointer to the new PDCP packet data structure.
*/
spinlock_t pdcp_pkd_ptr;
spinlock_t pdcp_pkd_ptr_lock;

#endif
