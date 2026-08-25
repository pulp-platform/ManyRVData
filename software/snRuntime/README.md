# snRuntime — CachePool Software Runtime

This library is the bare-metal software runtime for the CachePool manycore system. It is derived from the upstream Snitch runtime and extended with CachePool-specific cache management and peripheral APIs.

## Folder Structure

```
snRuntime/
├── include/          # Public headers — include these in application code
│   ├── snrt.h            # Master header: topology, barriers, DMA, allocation
│   ├── l1cache.h         # CachePool L1 data cache management API
│   ├── spatz_lock.h      # Dual-scalar Spatz ownership lock API
│   ├── cachepool_peripheral.h  # Register offsets for the cluster peripheral
│   ├── perf_cnt.h        # Performance counter API
│   ├── team.h            # Team/cluster descriptor structs
│   ├── interface.h       # Hardware interface definitions
│   ├── debug.h           # Debug printf helpers
│   ├── dm.h              # Data-mover (DMA) low-level interface
│   ├── eu.h              # Execution unit (work dispatch) interface
│   ├── kmp.h             # OpenMP KMP interface
│   └── omp.h             # OpenMP runtime interface
├── src/              # Runtime implementation
│   ├── start.S           # Entry point (hart 0 boots, others wait for IPI)
│   ├── team.c            # Team/topology initialisation
│   ├── barrier.c         # Hardware and software barrier implementations
│   ├── l1cache.c         # CachePool L1 cache management (flush, partition, xbar)
│   ├── spatz_lock.c      # Dual-scalar Spatz ownership lock (see spatz_lock.h)
│   ├── alloc.c           # L1 TCDM bump allocator + DRAM linked-list allocator
│   ├── memcpy.c          # Optimised memcpy
│   ├── perf_cnt.c        # Performance counter helpers
│   ├── printf.c          # Lightweight printf (wraps vendor/printf.c)
│   ├── dm.c / dma.c      # DMA engine helpers
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

### L1 Data Cache — CachePool-specific (`l1cache.h`)

All **cluster-wide** functions must be called by **every core** in the cluster. They
internally issue a `fence`, a hardware barrier, execute the operation on core 0 only,
and then issue a final barrier before returning. The low-level single-core variants
(without the `_cluster_` prefix) are for use inside the runtime or in single-core
contexts only.

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

Only meaningful on a `num_scalar_per_core=2` build (`cachepool_cc_dual`), where 2 Snitch
harts share 1 Spatz unit. On a single-scalar-per-CC build every call below is a harmless
no-op that always reports success.

```c
void spatz_lock_acquire();  // blocks (retries in software) until this hart owns Spatz
void spatz_lock_release();  // must be called by the current owner only
```

Both are plain, non-blocking-in-hardware retries under the hood — see `spatz_lock_outcome_t`
below — so a hart can never hang in hardware waiting on the other hart to release. After
`spatz_lock_acquire()` returns, it is always safe to issue vector/FP work immediately: if the
ownership switch is still draining, `acc_mux` (RTL) withholds Spatz access until it completes,
so the next vector/FP instruction just blocks there instead, exactly as if the acquire itself
had blocked.

For finer control (e.g. to do other work instead of retrying), use the non-blocking primitives
directly:

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
int  snrt_cluster_is_primary();       // true for the pair's default owner (even cid)
void snrt_cluster_host0_barrier();    // partial barrier over default owners only
void snrt_cluster_host1_barrier();    // partial barrier over their partners only
```

### Performance Counters (`perf_cnt.h`) *TODO: REMOVE*

```c
void     snrt_start_perf_counter(enum snrt_perf_cnt, enum snrt_perf_cnt_type, uint32_t hart_id);
void     snrt_stop_perf_counter(enum snrt_perf_cnt);
void     snrt_reset_perf_counter(enum snrt_perf_cnt);
uint32_t snrt_get_perf_counter(enum snrt_perf_cnt);
```

Counter types include cycles, TCDM accesses, TCDM congestion, FPU issues, retired
instructions, DMA bandwidth events, and ICache statistics.

### Memory Allocation (`snrt.h`)

Two allocators are provided for different memory regions.

**L1 TCDM — bump allocator** (no free support):

```c
void *snrt_l1alloc(size_t size);   // Bump-allocate from cluster TCDM scratchpad
void  snrt_l1alloc_reset();        // Reclaim all L1 allocations at once
```

**DRAM — linked-list allocator** (single-core, supports free + coalescing):

```c
void *snrt_malloc(size_t size);    // Allocate from DRAM; payload rounded up to 64 B
void  snrt_free(void *ptr);        // Free and coalesce with following free blocks
```

Both the block header and the payload are cacheline-aligned (64 bytes). A request for
any size — even 1 byte — allocates a minimum of 64 bytes of payload. The allocator
must be called by a **single core only**; it is not thread-safe by design since
allocation is expected to happen in single-core initialisation phases.

The heap begins at `_edram + l3off` (set in `snrt_alloc_init`) and grows upward.
Block headers (64 bytes each) are stored in DRAM immediately before their payloads
and are accessed through the L1 cache like any other data.

### DMA (`snrt.h`) *TODO: REMOVE*

```c
snrt_dma_txid_t snrt_dma_start_1d(void *dst, const void *src, size_t size);
snrt_dma_txid_t snrt_dma_start_2d(void *dst, const void *src, size_t size,
                                   size_t dst_stride, size_t src_stride, size_t repeat);
void snrt_dma_wait(snrt_dma_txid_t tid);
void snrt_dma_wait_all();
```

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

- `snrt_fence()` drains both Snitch's scalar LSU and Spatz's outstanding memory
  operations (`acc_mem_cnt_q`). Call it before a hardware barrier or before reading
  back results written by a vector kernel.
- Changing the partition mode (`l1d_part`) or the address boundary (`l1d_addr`) while
  valid data is cached requires a flush first.
- The `start_snitch.S` platform startup calls `l1d_flush` (single-core, invalidate)
  on the boot core before handing off to `main`. Application code does not need to
  call `l1d_init` manually.
