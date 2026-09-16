// Exercises three barrier scenarios at once, using two independent core
// wraps that never need to synchronize with each other:
//
//   - Core wrap 1: cores at odd local index, in every tile. Busy-waits,
//     then each tile's own odd cores run a purely internal partial barrier
//     among themselves (local_only, tile_mask = SNRT_BARRIER_TILE_MASK_SELF
//     -> skip-Global fast path, never leaves that tile). Every tile does
//     this independently and concurrently -- there is one hardware
//     instance per tile, so none of them interact. Slot 1.
//   - Core wrap 2: every other core in the cluster (the even-local-index
//     cores of every tile). Does a Spatz vector load, then a global
//     partial barrier -- cluster-reaching, every tile participates with
//     its even cores only. Slot 0.
//
// Because the two wraps run on different slots, wrap 1's fast internal
// rounds complete without waiting on wrap 2's much slower cluster-wide
// round, and vice versa -- that's the "parallel barriers without
// influence" property under test.
//
// Only 2 slots are needed (the universal minimum, every config has this
// many), not 3: wrap 1's and wrap 2's own barrier calls need distinct
// slots since both have members inside the same tile concurrently with
// different core_mask/tile_mask/local_only descriptors, but slot 0 can be
// shared with the automatic full-participation barrier every hart hits
// right after main() returns (start.S's post_barrier). If wrap 1 finishes
// and returns early while wrap 2's slot-0 round is still in flight, wrap
// 1's cores just get swept into that still-open round as unplanned extra
// arrivals -- the round still only waits on wrap 2's own core_mask, so
// this doesn't hang, it's just a semantically imprecise (not a clean
// full-cluster) release. Harmless here since neither wrap does anything
// after that point.
//
// No spin_lock or shared accumulator is used: each wrap has exactly one
// reporter core cluster-wide (no print contention), and there is no
// cross-tile read-modify-write of shared state.

#include <benchmark.h>
#include <snrt.h>
#include <stdio.h>

#define INTERNAL_BARRIER_SLOT 1
#define GLOBAL_BARRIER_SLOT   0

// Small read-only buffer for wrap 2's Spatz load -- never written after
// init, so plain reads need no flush regardless of cache partitioning.
#define LOAD_ELEMS 64
static uint32_t load_buf[LOAD_ELEMS] __attribute__((section(".data"))) = {
    [0 ... LOAD_ELEMS - 1] = 7};

static inline void spatz_load(uint32_t *ptr, uint32_t count) {
    uint32_t avl = count;
    uint32_t vlen;
    do {
        asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vlen) : "r"(avl));
        asm volatile("vle32.v v0, (%0)" : : "r"(ptr));
        ptr += vlen;
        avl -= vlen;
    } while (avl > 0);
}

int main() {
    uint32_t cpt = snrt_cluster_core_per_tile();
    uint32_t all_cores_mask = (1u << cpt) - 1;
    uint32_t odd_mask = 0;
    for (uint32_t i = 1; i < cpt; i += 2) odd_mask |= (1u << i);
    uint32_t even_mask = all_cores_mask & ~odd_mask;

    uint32_t core = snrt_cluster_core_idx();
    uint32_t local_id = core % cpt;

    snrt_cluster_hw_barrier();

    if (local_id % 2 == 1) {
        // Core wrap 1: busy-wait, then an internal (skip-Global) round
        // among this tile's own odd cores only.
        cachepool_wait(100);

        snrt_cluster_group_barrier(odd_mask, SNRT_BARRIER_TILE_MASK_SELF, 1,
                                    INTERNAL_BARRIER_SLOT);

        if (core == 1) {
            printf("core wrap 1 (odd cores, every tile): internal partial "
                   "barrier done\n");
        }
    } else {
        // Core wrap 2: real work (Spatz load), then a cluster-reaching
        // partial barrier that excludes every tile's odd cores.
        size_t t0 = benchmark_get_cycle();

        spatz_load(load_buf, LOAD_ELEMS);

        snrt_cluster_group_barrier(even_mask, SNRT_BARRIER_TILE_MASK_ALL, 0,
                                    GLOBAL_BARRIER_SLOT);

        if (core == 0) {
            size_t cyc = benchmark_get_cycle() - t0;
            printf("core wrap 2 (even cores, every tile): global partial "
                   "barrier done (%u cycles)\n",
                   (unsigned)cyc);
        }

        // Second round on the same slot/participants -- keeps every wrap-2
        // core from racing ahead and exiting before core 0's print above
        // is flushed.
        snrt_cluster_group_barrier(even_mask, SNRT_BARRIER_TILE_MASK_ALL, 0,
                                    GLOBAL_BARRIER_SLOT);
    }

    return 0;
}
