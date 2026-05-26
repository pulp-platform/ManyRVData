// Copyright 2025 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Tests snrt_malloc / snrt_free. Must be called by a single core only.
//
// T1: Basic allocation — non-null, cacheline-aligned payload
// T2: No overlap    — runtime rounds small request up to 64 B; consecutive
//                     payloads do not share bytes
// T3: Free and reuse — freeing a block makes it available for the next malloc
//                      of the same size (same address returned)
// T4: Coalescing    — freeing two adjacent blocks and then allocating a size
//                     that spans both succeeds and returns the earlier address

#include <snrt.h>
#include <stdint.h>

#define CL 64  // cacheline size in bytes

int main() {
  uint32_t cid = snrt_cluster_core_idx();

  // Allocator is single-core; other cores do nothing.
  if (cid != 0) return 0;

  uint32_t nerrors = 0;

  // -----------------------------------------------------------------------
  // T1: Basic allocation — non-null and cacheline-aligned payload
  // -----------------------------------------------------------------------
  uint8_t *a = (uint8_t *)snrt_malloc(4);
  if (a == NULL)             nerrors++;
  if ((uint32_t)a % CL != 0) nerrors++;

  // -----------------------------------------------------------------------
  // T2: No overlap — payload of 'a' must not reach payload of 'b'
  //     (the runtime rounds the 4-byte request up to a full 64-byte payload)
  // -----------------------------------------------------------------------
  uint8_t *b = (uint8_t *)snrt_malloc(4);
  if (b == NULL)                      nerrors++;
  if ((uint32_t)b < (uint32_t)a + CL) nerrors++;

  // Write all 64 payload bytes of 'a' and verify 'b' is untouched
  for (int i = 0; i < CL; i++) a[i] = (uint8_t)i;
  b[0] = 0xBB;
  if (a[CL - 1] != (uint8_t)(CL - 1)) nerrors++;
  if (b[0] != 0xBB)                   nerrors++;

  // -----------------------------------------------------------------------
  // T3: Free and reuse — same address returned after free
  // -----------------------------------------------------------------------
  snrt_free(a);
  uint8_t *a2 = (uint8_t *)snrt_malloc(4);
  if (a2 != a) nerrors++;

  // -----------------------------------------------------------------------
  // T4: Coalescing — free e then d; freeing d triggers a forward coalesce
  //     with the already-free e, producing a block large enough for 2×CL
  // -----------------------------------------------------------------------
  // Allocate two fresh adjacent cacheline-sized blocks
  uint8_t *d = (uint8_t *)snrt_malloc(CL);
  uint8_t *e = (uint8_t *)snrt_malloc(CL);
  if (d == NULL || e == NULL) nerrors++;
  // e's payload must start exactly 2 cachelines past d's payload:
  // one cacheline for d's payload, one for e's header
  if ((uint32_t)e != (uint32_t)d + 2 * CL) nerrors++;

  // Free e first (marks e free, nothing to coalesce forward).
  // Free d next  (marks d free, d->next == e which is free → coalesce).
  snrt_free(e);
  snrt_free(d);

  // The coalesced block must satisfy a 2×CL request and must reuse d
  uint8_t *de = (uint8_t *)snrt_malloc(2 * CL);
  if (de != d) nerrors++;

  return (int)nerrors;
}
