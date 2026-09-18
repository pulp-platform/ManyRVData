# snRuntime — CachePool Software Runtime

This library is the bare-metal software runtime for the CachePool manycore system.
It is derived from the upstream Snitch runtime and extended with CachePool-specific cache management and peripheral APIs.

## Folder Structure

```
snRuntime/
├── include/          # Public headers — include these in application code
│   ├── snrt.h            # Master header: topology, barriers, allocation
│   ├── l1cache.h         # CachePool L1 data cache management API
│   ├── spatz_lock.h      # Dual-scalar Spatz ownership lock API
│   ├── cachepool_peripheral.h  # Register offsets for the cluster peripheral
│   ├── team.h            # Team/cluster descriptor structs
│   └── debug.h           # Debug printf helpers
├── src/              # Runtime implementation
│   ├── start.S           # Entry point (hart 0 boots, others wait for IPI)
│   ├── team.c            # Team/topology initialisation
│   ├── barrier.c         # Hardware and software barrier implementations
│   ├── l1cache.c         # CachePool L1 cache management (flush, partition, xbar)
│   ├── spatz_lock.c      # Dual-scalar Spatz ownership lock (see spatz_lock.h)
│   ├── alloc.c           # DRAM linked-list allocator
│   ├── memcpy.c          # Optimised memcpy
│   ├── printf.c          # Lightweight printf (wraps vendor/printf.c)
│   ├── interrupt.c       # Interrupt initialisation
│   └── platforms/        # Platform-specific startup and putchar
├── tests/            # Self-contained runtime unit tests
├── vendor/           # Third-party sources (printf, riscv-opcodes)
└── link/             # Linker script template (common.ld.in)
```

## Key API

### Topology (`snrt.h`)

```c
uint32_t snrt_cluster_core_idx();    // Core index within the cluster (0-based)
uint32_t snrt_cluster_core_num();    // Total cores in the cluster
uint32_t snrt_cluster_tile_idx();    // Tile index within the cluster
uint32_t snrt_cluster_tile_num();    // Number of tiles in the cluster
int      snrt_is_compute_core();     // Non-zero if this is a compute (non-DMA) core
```

### Synchronisation (`snrt.h`)

```c
void snrt_cluster_hw_barrier();      // Hardware barrier: stalls until all cluster cores arrive
void snrt_cluster_sw_barrier();      // Software barrier (polling)
void snrt_global_barrier();          // Cluster-to-cluster barrier
```

#### Partial hardware barriers

The hardware barrier is three levels deep: core → tile → group → cluster.
A round only climbs as far up the hierarchy as it needs to.
A write to the barrier register carries a core mask, a tile mask, a `local_only` bit, and a barrier slot id, and each level stops forwarding once its own participants have arrived.
A plain load (no write), which is what `snrt_cluster_hw_barrier()` issues, is the legacy full-cluster barrier on slot 0 and always synchronizes everyone regardless of these masks.

Barrier slots are independent, concurrently-live round trackers (`NumBarrierSlots` of them, replicated at tile/group/cluster level, see `cachepool_pkg::NumBarrierSlots`), so rounds on different slots never serialize behind each other, even within the same tile or group.
The slot id is direct-mapped and software-chosen: every core participating in a given round must supply the identical id, exactly like they must already agree on the masks and `local_only`.
Slot 0 is reserved for the legacy `snrt_cluster_hw_barrier()`, which is always full-participation (`core_mask=ALL`); sharing it with any narrower-`core_mask` round risks corrupting that round's tile-level tracker if the two are ever concurrently in flight, so every other round — including `snrt_cluster_host0_barrier()`/`snrt_cluster_host1_barrier()` — must use its own distinct slot from `1..NumBarrierSlots-1`.
`NumBarrierSlots` is a per-config Makefile knob (`num_barrier_slots`, default 2, 4 on dual-scalar configs).

```c
void snrt_cluster_partial_barrier(uint32_t local_mask);
uint32_t snrt_cluster_partial_barrier_mask(const uint32_t *cids, uint32_t n);
void snrt_cluster_group_barrier(uint32_t core_mask, uint32_t tile_mask, int local_only, uint32_t barrier_id);
void snrt_barrier_set_group_mask(uint32_t barrier_id, uint32_t mask);
```

`snrt_cluster_partial_barrier(local_mask)` restricts participation to `local_mask` within the calling core's tile; every tile in the group and the cluster level still participate, matching `snrt_cluster_hw_barrier()`'s scope beyond the core mask.
It always uses slot 0.
`local_mask` is typically built with `snrt_cluster_partial_barrier_mask(cids, n)`, which derives this core's tile-local mask from a fixed list of global core ids (ids outside this core's own tile are ignored).
Every core in `cids` must call it with the identical `(cids, n)` for a given round, and the result is meant to be cached rather than recomputed in a hot loop.

`snrt_cluster_group_barrier(core_mask, tile_mask, local_only, barrier_id)` additionally restricts participation to `tile_mask` within the calling core's group, on the given barrier slot.
When `local_only` is set, the round resolves entirely at group level and never reaches the cluster — use this for work that only needs to synchronize within one group.
Every participating core must call it with identical arguments.
`tile_mask` is relative to the calling core's own group (bit *i* = tile *i* within that group); pass `SNRT_BARRIER_TILE_MASK_SELF` for a round confined to the calling core's own tile, which hardware resolves locally so it works in any group.
For any other tile subset there is still no group-relative tile index helper (only the cluster-wide `snrt_cluster_tile_idx()`), so an explicit `tile_mask` is only safe to use as-is in group 0, where the two coincide.

`snrt_barrier_set_group_mask(barrier_id, mask)` programs the given slot's cluster-level group-participation mask (one bit per group, one register per slot), consulted only by rounds on that slot that actually reach cluster level.
Call it from exactly one core, then use `snrt_cluster_hw_barrier()` as a resync point before relying on it, since the cluster barrier FSM samples this mask live when the first participating group arrives.

`snrt_cluster_host0_barrier(barrier_id)` / `snrt_cluster_host1_barrier(barrier_id)` (documented under the Spatz lock section below) are built on `snrt_cluster_group_barrier()` and so always reach cluster level, on the given slot.
`SNRT_HOST_BARRIER_SLOT` is the usual choice: slot 1 on dual-scalar builds (host 0's `core_mask` is a real subset there, so it needs isolation from slot 0), or slot 0 on single-scalar builds (every hart is host 0, so its `core_mask` is always `ALL` — provably identical in scope to `snrt_cluster_hw_barrier()`, so sharing slot 0 is safe and leaves every other slot free for application use).

### L1 Data Cache — CachePool-specific (`l1cache.h`)

All **cluster-wide** functions must be called by **every core** in the cluster.
They internally issue a `fence`, a hardware barrier, execute the operation on core 0 only, and then issue a final barrier before returning.
The low-level single-core variants (without the `_cluster_` prefix) are for use inside the runtime or in single-core contexts only.

#### Cluster-wide flush (recommended for application code)

```c
void l1d_cluster_flush();                      // Flush all banks in all tiles
void l1d_cluster_shared_flush();               // Flush shared banks only
void l1d_cluster_private_flush(uint32_t tile); // Flush private banks of selected tiles (one-hot mask)
```

#### Cache configuration (cluster-wide)

```c
// Set the crossbar interleaving offset (in bits).
// Granularity is clamped to >= log2(cacheline_bytes).
// Example: l1d_xbar_config(6) for 512-bit cachelines (6 = log2(64)).
void l1d_xbar_config(uint32_t offset);

// Set the number of private banks per tile (0=all-shared … 4=all-private).
void l1d_part(uint32_t size);
```

#### Address boundary and polling

```c
// Set the private/shared address boundary (default 0xA000_0000).
// Addresses >= boundary are private; addresses < boundary are shared.
// Requires a flush before changing while valid data is cached.
void l1d_addr(uint32_t addr);

// Poll the peripheral until the current flush instruction completes.
// Used by the low-level flush functions; not normally needed in application code.
void l1d_wait();
```

#### Cache initialisation (called once at boot, single-core)

```c
// Invalidate all cache banks (insn = 2'b11). Called from start_snitch.S.
void l1d_init(uint32_t size);
```

### Dual-Scalar Spatz Lock — CachePool-specific (`spatz_lock.h`)

Only meaningful on a `num_scalar_per_core=2` build (`cachepool_cc_dual`), where 2 Snitch harts share 1 Spatz unit.
On a single-scalar-per-CC build every call below is a harmless no-op that always reports success.

```c
void spatz_lock_acquire();  // blocks (retries in software) until this hart owns Spatz
void spatz_lock_release();  // must be called by the current owner only
```

Both are plain, non-blocking-in-hardware retries under the hood — see `spatz_lock_outcome_t` below — so a hart can never hang in hardware waiting on the other hart to release.
After `spatz_lock_acquire()` returns, it is always safe to issue vector/FP work immediately: if the ownership switch is still draining, `acc_mux` (RTL) withholds Spatz access until it completes, so the next vector/FP instruction just blocks there instead, exactly as if the acquire itself had blocked.

For finer control (e.g. to do other work instead of retrying), use the non-blocking primitives directly:

```c
typedef enum {
  SPATZ_LOCK_FAIL = 0,         // denied; hardware made no reservation, safe to retry
  SPATZ_LOCK_SUCCESS = 1,      // granted now
  SPATZ_LOCK_SUCCESS_WAIT = 2, // accepted, completes on its own once drained
} spatz_lock_outcome_t;

uint32_t spatz_lock_try_acquire();  // single, always-immediate attempt
uint32_t spatz_lock_try_release();
spatz_lock_outcome_t spatz_lock_outcome(uint32_t raw);  // decode the above
```

Related topology/sync helpers in `snrt.h`:

```c
int  snrt_cluster_is_primary();                       // true for the pair's default owner (even cid)
void snrt_cluster_host0_barrier(uint32_t barrier_id);  // partial barrier over default owners only
void snrt_cluster_host1_barrier(uint32_t barrier_id);  // partial barrier over their partners only
```

### Memory Allocation (`snrt.h`)

CachePool has no allocatable L1 scratchpad — L1 is a cache.
The only allocator is a DRAM linked-list allocator (single-core, supports free + coalescing):

```c
void *snrt_malloc(size_t size);    // Allocate from DRAM; payload rounded up to 64 B
void  snrt_free(void *ptr);        // Free and coalesce with following free blocks
```

Both the block header and the payload are cacheline-aligned (64 bytes).
A request for any size — even 1 byte — allocates a minimum of 64 bytes of payload.
The allocator must be called by a **single core only**; it is not thread-safe by design since allocation is expected to happen in single-core initialisation phases.

The heap begins at `_edram + l3off` (set in `snrt_alloc_init`) and grows upward.
Block headers (64 bytes each) are stored in DRAM immediately before their payloads and are accessed through the L1 cache like any other data.

## Typical Initialisation Pattern

```c
#include <snrt.h>
#include <l1cache.h>

int main() {
    const uint32_t cid = snrt_cluster_core_idx();

    // Configure cache xbar and partition — must be called by ALL cores.
    l1d_xbar_config(6);   // interleave at cacheline granularity
    l1d_part(0);          // all-shared

    // Single-core init: allocate buffers, set up data structures.
    if (cid == 0) {
        float *buf = (float *)snrt_malloc(N * sizeof(float));
        // ... populate buf, other setup ...
    }
    snrt_cluster_hw_barrier();

    // ... parallel computation ...

    // Flush before reading results back — must be called by ALL cores.
    l1d_cluster_flush();

    if (cid == 0) {
        // ... verify results ...
    }
    snrt_cluster_hw_barrier();

    return 0;
}
```

## Notes

- `snrt_fence()` drains both Snitch's scalar LSU and Spatz's outstanding memory operations (`acc_mem_cnt_q`). Call it before a hardware barrier or before reading back results written by a vector kernel.
- Changing the partition mode (`l1d_part`) or the address boundary (`l1d_addr`) while valid data is cached requires a flush first.
- The `start_snitch.S` platform startup calls `l1d_flush` (single-core, invalidate) on the boot core before handing off to `main`. Application code does not need to call `l1d_init` manually.
