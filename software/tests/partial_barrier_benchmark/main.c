// This tiny test tests the partial barrier implementation by
// setting the participation mask only for tiles 1 & 3.
// Tiles 0 & 2 should be able to reach end of programs
// before 1 & 3 finish the work and pass the partial barrier.
// Author: Luca Caballero Cusin <lcaballero@student.ethz.ch>

#include <benchmark.h>
#include <snrt.h>
#include <stdio.h>
#include "spin_lock.h"

static uint32_t result __attribute__((section(".data")));
static uint32_t printed __attribute__((section(".data")));
static struct snrt_barrier sw_barrier __attribute__((section(".data")));
spinlock_t lock;

int main()
{
    volatile uint32_t *participation = (volatile uint32_t *)_snrt_barrier_participation_mask_reg_ptr();

    // whoever arrives first, writes the barrier
    // no race condition since they all write the same thing
    *participation = 0b1111; // all tiles participate

    result = 0;
    snrt_cluster_hw_barrier();

    // atomic test-and-set: returns old value
    if (__atomic_fetch_add(&printed, 1, __ATOMIC_RELAXED) == 0) {
        spin_lock(&lock, 1);
        printf("setting participation for tiles 1 and 3\n");
        spin_unlock(&lock, 1);
    }

    // set participation mask
    *participation = 0b1010; // tiles 1 and 3 only

    // only tiles 1 and 3
    if (snrt_cluster_tile_idx() == 1 || snrt_cluster_tile_idx() == 3)
    {
        // work
        spin_lock(&lock, 1);
        printf("core %u in tile %u reached work loop\n", snrt_cluster_core_idx(), snrt_cluster_tile_idx());
        spin_unlock(&lock, 1);

        spin_lock(&lock, 1);
        result += snrt_cluster_core_idx();
        spin_unlock(&lock, 1);

        snrt_cluster_hw_barrier();
        
        if (snrt_cluster_core_idx() == 4)
        {
            spin_lock(&lock, 1);
            printf("tiles done working, result (expected = 76) = %u\n", result);
            spin_unlock(&lock, 1);
        }
    }

    if (snrt_cluster_core_idx() == 0 || snrt_cluster_core_idx() == 4 || snrt_cluster_core_idx() == 8 || snrt_cluster_core_idx() == 12)
    {
        spin_lock(&lock, 1);
        printf("%u reached end of first stage\n", snrt_cluster_tile_idx());
        spin_unlock(&lock, 1);
    }
    printed=0;

    snrt_barrier(&sw_barrier, snrt_cluster_core_num());

    if (__atomic_fetch_add(&printed, 1, __ATOMIC_RELAXED) == 0) {
        spin_lock(&lock, 1);
        printf("setting participation for tiles 0 and 2\n");
        spin_unlock(&lock, 1);
    }

    // set participation mask
    *participation = 0b0101; // tiles 0 and 2 only

    // only tiles 0 and 2
    if (snrt_cluster_tile_idx() == 0 || snrt_cluster_tile_idx() == 2)
    {
        // work
        spin_lock(&lock, 1);
        printf("core %u in tile %u reached work loop\n", snrt_cluster_core_idx(), snrt_cluster_tile_idx());
        spin_unlock(&lock, 1);

        spin_lock(&lock, 1);
        result += snrt_cluster_core_idx();
        spin_unlock(&lock, 1);

        snrt_cluster_hw_barrier();
        
        if (snrt_cluster_core_idx() == 4)
        {
            spin_lock(&lock, 1);
            printf("tiles done working, result (expected = 76) = %u\n", result);
            spin_unlock(&lock, 1);
        }
    }



    if (snrt_cluster_core_idx() == 0 || snrt_cluster_core_idx() == 4 || snrt_cluster_core_idx() == 8 || snrt_cluster_core_idx() == 12)
    {
        spin_lock(&lock, 1);
        printf("%u reached end of second stage\n", snrt_cluster_tile_idx());
        spin_unlock(&lock, 1);
    }

    // We use sw barrier for now, since crash happens if cores not synchronized at the end
    // when implementing multiple barriers, we can assign one to 1 & 3 and another for
    // all the cores at the very end

    snrt_barrier(&sw_barrier, snrt_cluster_core_num());

    return 0;
}
