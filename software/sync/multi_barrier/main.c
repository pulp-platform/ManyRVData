// Tests two independent barrier rounds running concurrently on different
// slots: wrap 1 (odd-index cores, every tile) runs a tile-local internal
// barrier on slot 1; wrap 2 (even-index cores) runs a cluster-reaching
// partial barrier on slot 2 after a Spatz load. Slot 0 is reserved for
// full-participation rounds only, so wrap 2 (core_mask=even_mask, a
// subset) cannot share it -- needs 3 slots, skipped on smaller configs.

#include <benchmark.h>
#include <snrt.h>
#include <stdio.h>
#include "cachepool_peripheral.h"

#define INTERNAL_BARRIER_SLOT 1
#define GLOBAL_BARRIER_SLOT   2

#if CACHEPOOL_PERIPHERAL_HW_BARRIER_PARTICIPATION_MASK_MULTIREG_COUNT >= 3

// Read-only, never written, so plain reads need no cache flush.
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
        cachepool_wait(100);

        snrt_cluster_group_barrier(odd_mask, SNRT_BARRIER_TILE_MASK_SELF, 1,
                                    INTERNAL_BARRIER_SLOT);

        if (core == 1) {
            printf("core wrap 1 (odd cores, every tile): internal partial "
                   "barrier done\n");
        }
    } else {
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

        // Keeps wrap 2 from racing past core 0's print above.
        snrt_cluster_group_barrier(even_mask, SNRT_BARRIER_TILE_MASK_ALL, 0,
                                    GLOBAL_BARRIER_SLOT);
    }

    // Explicit closing barrier instead of relying on the implicit post-main() one.
    snrt_cluster_hw_barrier();

    return 0;
}

#else  // CACHEPOOL_PERIPHERAL_HW_BARRIER_PARTICIPATION_MASK_MULTIREG_COUNT < 3

int main() {
    if (snrt_cluster_core_idx() == 0) {
        printf("multi_barrier test skipped: needs >= 3 barrier slots (have %d); "
               "build with a config that sets num_barrier_slots >= 3\n",
               CACHEPOOL_PERIPHERAL_HW_BARRIER_PARTICIPATION_MASK_MULTIREG_COUNT);
    }
    return 0;
}

#endif
