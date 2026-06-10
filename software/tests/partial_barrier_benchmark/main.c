// Synthetic benchmark for partial barrier implementation.
// Tiles 0 and 2 perform multiple small reductions
// Tiles 1 and 3 perform one big reduction
// Author: Luca Caballero Cusin <lcaballero@student.ethz.ch>

#include <benchmark.h>
#include <snrt.h>
#include <stdio.h>
#include "spin_lock.h"

static uint32_t result __attribute__((section(".data")));
static uint32_t result_big __attribute__((section(".data")));
static uint32_t result_small[4] __attribute__((section(".data")));
static uint32_t printed __attribute__((section(".data")));
static uint32_t printed2 __attribute__((section(".data")));
static struct snrt_barrier sw_barrier __attribute__((section(".data")));
spinlock_t lock;


static uint32_t v_big[256] __attribute__((section(".data")));
static uint32_t v_small[64] __attribute__((section(".data")));

// Choose between partial or full barrier
#define PARTIAL


int main()
{
    volatile uint32_t *participation = (volatile uint32_t *)_snrt_barrier_participation_mask_reg_ptr();

    // whoever arrives first, writes the barrier
    // no race condition since they all write the same thing
    *participation = 0b1111; // all tiles participate

    result = 0;
    printed = 0;
    snrt_cluster_hw_barrier();



    // set participation mask
    #ifdef PARTIAL
        *participation = 0b0101; // tiles 0 and 2 only
    #endif
    

    // only tiles 1 and 3
    if (snrt_cluster_tile_idx() == 1 || snrt_cluster_tile_idx() == 3)
    {
        int local=0;
        // work
        for (int i=0;i<256;i++){
            v_big[i]=1;

        }
        #ifdef DEBUG
        spin_lock(&lock, 1);
        printf("core %u in tile %u reached work loop\n", snrt_cluster_core_idx(), snrt_cluster_tile_idx());
        spin_unlock(&lock, 1);
        #endif
        if (snrt_cluster_tile_idx()==1)
            for (int i=0; i< 32 ;i++){
            local+=v_big[(snrt_cluster_core_idx()%4)*32+i];

        }

        if (snrt_cluster_tile_idx()==3)
            for (int i=0; i<32  ;i++){
            local+=v_big[(snrt_cluster_core_idx()%4)*32+i+128];

        }

        spin_lock(&lock, 1);
        result_big += local;
        spin_unlock(&lock, 1);

        #ifdef PARTIAL
            
        #else
            // necessary for tiles 0 and 2 to continue
            snrt_cluster_hw_barrier();
            if (__atomic_fetch_add(&printed, 1, __ATOMIC_RELAXED) == 0) {
                spin_lock(&lock, 1);
                printf("1 and 3 reached barrier\n");
                spin_unlock(&lock, 1);
            }
            snrt_cluster_hw_barrier();
            snrt_cluster_hw_barrier();
            snrt_cluster_hw_barrier();
            
        #endif
        printed=0;
        snrt_barrier(&sw_barrier, snrt_cluster_core_num());

        if (__atomic_fetch_add(&printed, 1, __ATOMIC_RELAXED) == 0) {
            spin_lock(&lock, 1);
            printf("1 and 3 done with big red , result is : %d  , expected :256 \n",result_big);
            spin_unlock(&lock, 1);
        }

        
        
    }

    // only tiles 0 and 2
    if (snrt_cluster_tile_idx() == 0 || snrt_cluster_tile_idx() == 2)
    {
        for (int i=0;i<64;i++){
            v_small[i]=1;
        }
        for (int n=0;n<4;n++){
            int local=0;
            // work
            #ifdef DEBUG
            spin_lock(&lock, 1);
            printf("core %u in tile %u reached work loop\n", snrt_cluster_core_idx(), snrt_cluster_tile_idx());
            spin_unlock(&lock, 1);
            #endif
            if (snrt_cluster_tile_idx()==0)
                for (int i=0; i< 8 ;i++){
                local+=v_small[(snrt_cluster_core_idx()%4)*8+i];

            }

            if (snrt_cluster_tile_idx()==2)
                for (int i=0; i< 8 ;i++){
                local+=v_small[(snrt_cluster_core_idx()%4)*8+i+32];

            }

            spin_lock(&lock, 1);
            result_small[n] += local;
            spin_unlock(&lock, 1);

            printed2=0;

            // if full barrier, has to wait for big reduction to finish
            snrt_cluster_hw_barrier();

            if (__atomic_fetch_add(&printed2, 1, __ATOMIC_RELAXED) == 0) {
                spin_lock(&lock, 1);
                printf("0 and 2 done with small red %d , result is : %d, expected :64  \n",n,result_small[n]);
                spin_unlock(&lock, 1);
            }


            
        }

        
        snrt_barrier(&sw_barrier, snrt_cluster_core_num());

    }

    if (snrt_cluster_core_idx() == 0 || snrt_cluster_core_idx() == 4 || snrt_cluster_core_idx() == 8 || snrt_cluster_core_idx() == 12)
    {
        spin_lock(&lock, 1);
        printf("%u reached end\n", snrt_cluster_tile_idx());
        spin_unlock(&lock, 1);
    }
  

    // We use sw barrier for now, since crash happens if cores not synchronized at the end
    // when implementing multiple barriers, we can assign one to 1 & 3 and another for
    // all the cores at the very end

    snrt_barrier(&sw_barrier, snrt_cluster_core_num());

    return 0;
}
