#ifndef RLC_H
#define RLC_H

#include <stdint.h>
#include <stdatomic.h>
#include <stddef.h>
#include "mm.h"
#include "llist.h"
#include "data_move_vec.h"

#define CACHE_LINE_SIZE 64 // Cache line size in bytes, typically 64 bytes

/* rlc_context_t maintains the state of the RLC kernel, including:

   - rlcId: Unique identifier for the RLC entity.
   - cellId: Identifier for the cell to which this RLC entity belongs.
   - pollPdu: Number of PDUs for which polling is enabled.
   - pollByte: Number of bytes for which polling is enabled.
   - pduWithoutPoll: Total number of PDUs sent without polling.
   - byteWithoutPoll: Total bytes of PDUs sent without polling.
   - vtNextAck: Sequence number (SN) of the first unacknowledged PDU.
   - vtNext: Next available sequence number for a new PDU.
   - list: Linked list of SDUs pending transmission (to_send list).
   - sent_list: Linked list of SDUs that have been sent and are awaiting acknowledgment.

   State transitions:
   - When a producer adds a new node to the to_send list:
       list.sduNum++
       list.sduBytes++

   - When a consumer removes a node from the to_send list and transmits it:
       pduWithoutPoll++
       byteWithoutPoll++
       list.sduNum--
       list.sduBytes--
       vtNext++
       sent_list.sduNum++
       sent_list.sduBytes++

   - When an acknowledgment is received from the UE:
       vtNextAck++
       sent_list.sduNum--
       sent_list.sduBytes--
*/
typedef struct {
   unsigned int rlcId __attribute__((aligned(4)));
   unsigned int cellId __attribute__((aligned(4))); /* Indicates the cell to which the RLC entity belongs.*/
   _Atomic unsigned int pollPdu __attribute__((aligned(4)));
   _Atomic unsigned int pollByte __attribute__((aligned(4)));
   _Atomic unsigned int pduWithoutPoll __attribute__((aligned(4)));  /* Indicates the total number of PDUs that are not polled. */
   _Atomic unsigned int byteWithoutPoll __attribute__((aligned(4))); /* Indicates the total bytes of PDUs that are not polled. */

   // unsigned int sduNum; /* Number of sdus to be sent */
   // unsigned int sduBytes; /* Number of sdus bytes to be sent */
   // void *sduLinkHdr; /* First SDU to be sent */
   // void *sduLinkTail; /* Last SDU to be sent */
   LinkedList list __attribute__((aligned(4)));
   char Reserve1[CACHE_LINE_SIZE-6-sizeof(LinkedList)] __attribute__((aligned(4))); /* Reserved for future use, pieced into a cacheline */

   _Atomic unsigned int vtNextAck __attribute__((aligned(4))); /* First SN to be confirmed */
   _Atomic unsigned int vtNext __attribute__((aligned(4))); /* Next Available RLCSN */
   // unsigned int sendPduNum; /* Number of pdus to be confirmed */
   // unsigned int sendPduBytes; /* Number of pdus to be confirmed */
   // void *waitAckLinkHdr;  /* First SDU to be confirmed */
   // void *waitAckLinkTail; /* Last SDU to be confirmed */
   LinkedList sent_list __attribute__((aligned(4)));
   char Reserve2[CACHE_LINE_SIZE-2-sizeof(LinkedList)] __attribute__((aligned(4))); /* Reserved for future use, pieced into a cacheline */

   mm_context_t *mm_ctx __attribute__((aligned(4)));
} rlc_context_t;

rlc_context_t rlc_ctx __attribute__((section(".data")));

/* rlc_init() initializes the RLC context for the given RLC ID and cell ID.
   It sets the initial values for pollPdu, pollByte, pduWithoutPoll, byteWithoutPoll,
   vtNextAck, vtNext, and initializes the linked lists.
   The mm_context_t pointer is also set to the provided memory management context.
*/
void rlc_init(const unsigned int rlcId, const unsigned int cellId, mm_context_t *mm_ctx);

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
spinlock_t pdcp_pkd_ptr __attribute__((section(".data")));
mcs_lock_t pdcp_pkd_ptr_lock __attribute__((section(".data")));

_Atomic(uint32_t) producer_done __attribute__((section(".data")));

spinlock_t rlc_ctx_lock __attribute__((section(".data")));

#endif
