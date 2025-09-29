// mcs_lock.h — RISC-V bare-metal friendly MCS spinlock (C11)
// - No OS threads/TLS required (hart-local storage using mhartid)
// - Uses C11 <stdatomic.h> and RISC-V hints
// - Drop-in shim for existing spinlock_* API (see bottom)

#ifndef MCS_LOCK_H
#define MCS_LOCK_H

#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>
// #include "printf.h"
// #include "printf_lock.h"

#ifndef MCS_CACHELINE
#define MCS_CACHELINE 64        // adjust if your L1 line != 64B
#endif

#ifndef MCS_MAX_HARTS
#define MCS_MAX_HARTS 4        // set to your cluster max cores
#endif

#ifndef MCS_TLS_SLOTS
#define MCS_TLS_SLOTS 4         // max locks concurrently held per hart
#endif

// ---- RISC-V relax/yield hints ----
#if defined(__riscv_zihintpause)
  #define MCS_CPU_RELAX() __asm__ __volatile__("pause")
#else
  #define MCS_CPU_RELAX() __asm__ __volatile__("nop")
#endif
#ifdef MCS_USE_WFI
  #define MCS_CPU_PARK()  __asm__ __volatile__("wfi")
#else
  #define MCS_CPU_PARK()  MCS_CPU_RELAX()
#endif

// Opaque types
typedef struct mcs_node mcs_node_t;

typedef struct mcs_lock {
  _Atomic(mcs_node_t*) tail __attribute__((aligned(4)));
} mcs_lock_t;

// API
void mcs_lock_init(mcs_lock_t* L);
void __attribute__((noinline)) mcs_lock_acquire(mcs_lock_t* L);
uint32_t mcs_lock_try_acquire(mcs_lock_t* L);
void __attribute__((noinline)) mcs_lock_release(mcs_lock_t* L);

// // ---- Optional: shim to your existing TAS API names ----
// // Compile with -DMCS_SHIM_SPINLOCK to alias.
// #ifdef MCS_SHIM_SPINLOCK
//   #define spinlock_t       mcs_lock_t
//   #define spinlock_init    mcs_lock_init
//   #define spinlock_lock    mcs_lock_acquire
//   #define spinlock_trylock mcs_lock_try_acquire
//   #define spinlock_unlock  mcs_lock_release
// #endif


#endif // MCS_LOCK_H