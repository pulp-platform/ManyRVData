#ifndef RLC_H
#define RLC_H

#include "mm.h"
#include "llist.h"
#include "data_move_vec.h"
#define CACHE_LINE_SIZE 64 // Cache line size in bytes, typically 64 bytes (in current architeture is 16 bytes, but put 64 here for now)

/* rlc_context_t holds the RLC kernel state:
   - rlcId: RLC entity ID
   - cellId: Cell ID to which the RLC entity belongs
   - pollPdu: Number of PDUs polled
   - pollByte: Number of bytes polled
   - pduWithoutPoll: Total number of PDUs that are not polled
   - byteWithoutPoll: Total bytes of PDUs that are not polled
   - vtNextAck: First SN to be confirmed
   - vtNext: Next available RLCSN
   - sendPduNum: Number of PDUs to be confirmed
   - sendPduBytes: Number of bytes to be confirmed
   - waitAckLinkHdr/Tail: Linked list for SDUs to be confirmed
*/
typedef struct {
   unsigned int rlcId;
   unsigned int cellId; /* Indicates the cell to which the RLC entity belongs.*/
   unsigned int pollPdu;
   unsigned int pollByte;
   unsigned int pduWithoutPoll;  /* Indicates the total number of PDUs that are not polled. */
   unsigned int byteWithoutPoll; /* Indicates the total bytes of PDUs that are not polled. */

   // unsigned int sduNum; /* Number of sdus to be sent */
   // unsigned int sduBytes; /* Number of sdus bytes to be sent */
   // void *sduLinkHdr; /* First SDU to be sent */
   // void *sduLinkTail; /* Last SDU to be sent */
   LinkedList list;
   char Reserve1[CACHE_LINE_SIZE-6-sizeof(LinkedList)]; /* Reserved for future use, pieced into a cacheline */

   unsigned int vtNextAck; /* First SN to be confirmed */
   unsigned int vtNext; /* Next Available RLCSN */
   // unsigned int sendPduNum; /* Number of pdus to be confirmed */
   // unsigned int sendPduBytes; /* Number of pdus to be confirmed */
   // void *waitAckLinkHdr;  /* First SDU to be confirmed */
   // void *waitAckLinkTail; /* Last SDU to be confirmed */
   LinkedList sent_list;
   char Reserve2[CACHE_LINE_SIZE-2-sizeof(LinkedList)]; /* Reserved for future use, pieced into a cacheline */

   mm_context_t *mm_ctx;
} rlc_context_t;

volatile rlc_context_t rlc_ctx;

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
spinlock_t pdcp_pkd_ptr;
spinlock_t pdcp_pkd_ptr_lock;

#endif
