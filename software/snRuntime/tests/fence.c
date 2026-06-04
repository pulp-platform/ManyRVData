// Copyright 2025 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Tests snrt_fence(), snrt_fence_snitch(), and snrt_fence_spatz() as the
// release barrier in a spinlock critical section.
//
// With acc_mem_stall relaxed to the rollover guard only, an explicit fence is
// the sole mechanism that orders stores before the lock release.  Without it,
// the AMO unlock can fire while stores are still in flight, and the next lock
// holder reads stale data.
//
// Shared DRAM buffers are allocated by core 0 via snrt_malloc and broadcast
// through static globals.  Requires at least 2 cores and Spatz (RVV) support.
//
// T1: Scalar stores — full fence (snrt_fence).
//     Each core acquires the lock, increments a shared counter, calls
//     snrt_fence(), releases the lock.  After all cores finish, core 0
//     checks counter == num_cores.
//
// T2: Spatz vector stores — full fence (snrt_fence).
//     Each core acquires the lock, vector-loads the shared accumulator,
//     adds its own core id to every element (vadd.vx), vector-stores back,
//     calls snrt_fence(), releases the lock.  After all cores finish, core 0
//     checks every element equals num_cores*(num_cores-1)/2.
//
// T3: Scalar stores — Snitch-only fence (snrt_fence_snitch).
//     Same as T1 but uses snrt_fence_snitch(), which drains the Snitch LSU
//     only.  Sufficient to order scalar stores before the AMO unlock.
//
// T4: Spatz vector stores — Spatz-only fence (snrt_fence_spatz).
//     Same as T2 but uses snrt_fence_spatz(), which drains Spatz memory
//     operations only.  Sufficient to order vector stores before the AMO
//     unlock.

#include <snrt.h>
#include <stdint.h>

// Number of 32-bit elements in the vector accumulator (e32, m1)
#define N_VEC 16

// Shared DRAM pointers — allocated by core 0, read by all after barrier
static volatile uint32_t *g_lock;
static volatile uint32_t *g_counter;
static volatile uint32_t *g_vec_sum;

static inline void cs_lock(volatile uint32_t *lock) {
    while (__sync_lock_test_and_set((volatile int *)lock, 1)) { /* spin */ }
}

// snrt_fence() drains both Snitch LSU and Spatz (acc_mem_cnt_q) before the
// AMO unlock fires, guaranteeing stores are visible to the next lock holder.
static inline void cs_unlock(volatile uint32_t *lock) {
    snrt_fence();
    asm volatile("amoswap.w zero, zero, %0" : "+A"(*lock));
}

// snrt_fence_snitch() drains the Snitch LSU only — sufficient for scalar stores.
static inline void cs_unlock_snitch(volatile uint32_t *lock) {
    snrt_fence_snitch();
    asm volatile("amoswap.w zero, zero, %0" : "+A"(*lock));
}

// snrt_fence_spatz() drains Spatz operations only — sufficient for vector stores.
static inline void cs_unlock_spatz(volatile uint32_t *lock) {
    snrt_fence_spatz();
    asm volatile("amoswap.w zero, zero, %0" : "+A"(*lock));
}

int main() {
    uint32_t cid       = snrt_cluster_core_idx();
    uint32_t num_cores = snrt_cluster_core_num();
    uint32_t nerrors   = 0;

    if (num_cores < 2) return 0;

    // Core 0 allocates all shared state; other cores read after barrier
    if (cid == 0) {
        g_lock    = (volatile uint32_t *)snrt_malloc(sizeof(uint32_t));
        g_counter = (volatile uint32_t *)snrt_malloc(sizeof(uint32_t));
        g_vec_sum = (volatile uint32_t *)snrt_malloc(N_VEC * sizeof(uint32_t));
        *g_lock    = 0;
        *g_counter = 0;
        for (int i = 0; i < N_VEC; i++) g_vec_sum[i] = 0;
    }
    snrt_cluster_hw_barrier();

    // -----------------------------------------------------------------------
    // T1: Scalar counter increment in critical section
    // -----------------------------------------------------------------------
    cs_lock(g_lock);
    (*g_counter)++;
    cs_unlock(g_lock);

    snrt_cluster_hw_barrier();

    if (cid == 0) {
        if (*g_counter != num_cores) nerrors++;
        // Re-arm lock for T2
        *g_lock = 0;
    }
    snrt_cluster_hw_barrier();

    // -----------------------------------------------------------------------
    // T2: Vector accumulate in critical section
    // Each core adds its cid to every element; expected sum = n*(n-1)/2
    // -----------------------------------------------------------------------
    cs_lock(g_lock);
    {
        size_t vl;
        asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(N_VEC));
        asm volatile("vle32.v v0, (%0)" :: "r"(g_vec_sum) : "memory");
        asm volatile("vadd.vx v0, v0, %0" :: "r"(cid) : "memory");
        asm volatile("vse32.v v0, (%0)" :: "r"(g_vec_sum) : "memory");
    }
    cs_unlock(g_lock);

    snrt_cluster_hw_barrier();

    if (cid == 0) {
        uint32_t expected = (num_cores * (num_cores - 1)) / 2;
        for (int i = 0; i < N_VEC; i++) {
            if (g_vec_sum[i] != expected) nerrors++;
        }
        // Re-arm for T3
        *g_counter = 0;
        *g_lock    = 0;
    }
    snrt_cluster_hw_barrier();

    // -----------------------------------------------------------------------
    // T3: Scalar counter increment — Snitch-only fence
    // snrt_fence_snitch() is sufficient to order scalar (Snitch LSU) stores.
    // -----------------------------------------------------------------------
    cs_lock(g_lock);
    (*g_counter)++;
    cs_unlock_snitch(g_lock);

    snrt_cluster_hw_barrier();

    if (cid == 0) {
        if (*g_counter != num_cores) nerrors++;
        // Re-arm for T4
        for (int i = 0; i < N_VEC; i++) g_vec_sum[i] = 0;
        *g_lock = 0;
    }
    snrt_cluster_hw_barrier();

    // -----------------------------------------------------------------------
    // T4: Vector accumulate — Spatz-only fence
    // snrt_fence_spatz() is sufficient to order Spatz vector stores.
    // Each core adds its cid to every element; expected sum = n*(n-1)/2.
    // -----------------------------------------------------------------------
    cs_lock(g_lock);
    {
        size_t vl;
        asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(N_VEC));
        asm volatile("vle32.v v0, (%0)" :: "r"(g_vec_sum) : "memory");
        asm volatile("vadd.vx v0, v0, %0" :: "r"(cid) : "memory");
        asm volatile("vse32.v v0, (%0)" :: "r"(g_vec_sum) : "memory");
    }
    cs_unlock_spatz(g_lock);

    snrt_cluster_hw_barrier();

    if (cid == 0) {
        uint32_t expected = (num_cores * (num_cores - 1)) / 2;
        for (int i = 0; i < N_VEC; i++) {
            if (g_vec_sum[i] != expected) nerrors++;
        }
    }
    snrt_cluster_hw_barrier();

    return (cid == 0) ? (int)nerrors : 0;
}
