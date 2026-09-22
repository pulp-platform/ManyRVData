/*
 * Copyright (C) 2026 ETH Zurich and University of Bologna
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * Kernel-side software performance probes. Copy this file (and perf_probe_events.h) into the
 * kernel tree, or add core/models/probe to the include path.
 *
 * One posted 32-bit store per event, to an address that encodes the hart and the event id
 * (perf_probe_events.h). The GVSoC collector decodes it; an RTL testbench snoops the same window,
 * so the instrumentation in the kernel is identical for both engines.
 *
 * EVERYTHING COMPILES AWAY unless the build defines RLC_PROBE=1, so the default binaries stay
 * byte-identical. Enable with -DRLC_PROBE=1.
 *
 * Usage:
 *
 *     #include "perf_probe.h"
 *     perf_probe_init();                        // once per core, before any other probe
 *     perf_probe_role(PERF_PROBE_ROLE_CONSUMER);
 *     perf_probe_entity(PROBE_EVT_SDU_RX, uid, node->data_size);
 *     perf_probe(PROBE_EVT_TTI_BEGIN, tti_index);
 *
 * The cost is one posted store plus the address arithmetic. In GVSoC the core's LSU hands the
 * store straight to the collector (no interconnect traffic, no wait for a response), matching a
 * posted store in hardware. Still: put probes at task boundaries (a packet, a PDU, a grant, a
 * phase), never inside an inner loop.
 */

#ifndef PERF_PROBE_H
#define PERF_PROBE_H

#include <stdint.h>
#include "perf_probe_events.h"

#ifndef RLC_PROBE
#define RLC_PROBE 0
#endif

#if RLC_PROBE

#include <snrt.h>

/* Per-core probe pointer, set ONCE by perf_probe_init() at kernel entry and kept in thread-local
   storage (the runtime keeps its own per-core pointers the same way).

   Not recomputed per event on purpose: reading mhartid is a csrr, which Snitch treats as
   non-sequenceable -- it waits for the offload sequencer to drain. Issued after a vector copy it
   stalls the core until the copy completes, destroying exactly the overlap the kernel relies on
   (measured: +8.7% kernel cycles on RLC TC1 with a csrr per event). The hart field is mhartid, the
   same id the GVSoC core probes and the hardware barrier use. */
static __thread volatile uint32_t *perf_probe_ptr;

static inline void perf_probe_init(void)
{
    perf_probe_ptr = (volatile uint32_t *)(PERF_PROBE_BASE +
                                           (snrt_hartid() << PERF_PROBE_HART_SHIFT));
}

/* One event with a plain 32-bit value. A no-op before perf_probe_init() on this core. */
static inline void perf_probe(uint32_t evt, uint32_t val)
{
    volatile uint32_t *p = perf_probe_ptr;
    if (p) p[evt] = val;
}

/* One event carrying an RLC entity id: value = (entity << 16) | (v & 0xffff). */
static inline void perf_probe_entity(uint32_t evt, uint32_t entity, uint32_t v)
{
    perf_probe(evt, (entity << PERF_PROBE_ENTITY_SHIFT) | (v & PERF_PROBE_VALUE_MASK));
}

static inline void perf_probe_role(uint32_t role)  { perf_probe(PROBE_EVT_ROLE, role); }
static inline void perf_probe_phase(uint32_t ph)   { perf_probe(PROBE_EVT_PHASE, ph); }

#else  /* !RLC_PROBE — every probe vanishes */

#define perf_probe_init()                     ((void)0)
#define perf_probe(evt, val)                  ((void)0)
#define perf_probe_entity(evt, entity, v)     ((void)0)
#define perf_probe_role(role)                 ((void)0)
#define perf_probe_phase(ph)                  ((void)0)

#endif /* RLC_PROBE */

#endif /* PERF_PROBE_H */
