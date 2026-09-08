# Synchronisation is not visibility

**2026-09-08.** Four instances of one defect in a single day, across the RLC
kernel and the cache test suite, on two engines. The instances are cheap to fix
individually; the pattern is the thing worth keeping.

## The rule

**Both of this runtime's barriers are a single memory-mapped access. Neither
emits a fence. They make cores wait for one another and nothing more.**

```asm
_snrt_cluster_barrier:                 ; snRuntime/src/platforms/shared/start_snitch.S:35
    call _snrt_barrier_reg_ptr
    lw   a0, 0(a0)                     ; the entire barrier
    ret
```

```c
void snrt_cluster_partial_barrier(uint32_t local_mask) {   /* snRuntime/src/barrier.c */
    *(volatile uint32_t *)_snrt_barrier_reg_ptr() = local_mask;
}
```

So a store made before a barrier is **not** guaranteed visible to another core
after it. The names promise otherwise, which is the whole problem: "barrier" is
read as a memory barrier, and it is not one.

A second, independent case of the same confusion: **Snitch and Spatz have
separate load/store units.** A vector store and a scalar load of the same
address are unordered with respect to each other without an explicit `fence`.

And in both cases `volatile` does not help. It constrains the *compiler*. It
says nothing about a write buffer, an async cache, or a second LSU. An inline
asm `"memory"` clobber is likewise compiler-only.

## The instances

| # | Site | Handoff | Symptom |
|---|---|---|---|
| 1 | `rlc_ul_drv.c` armed flag | core 0 store → consumers load, across `snrt_cluster_hw_barrier()` | Flag read as 0 on every consumer. **Store and load both provably executed** (disassembly) and disagreed. |
| 2 | `rlc_am.c` / `rlc_ul_drv.c` TTI phase barriers | owner writes ~7 KB plan → helpers read it to copy payload | Suspected silent transport-block corruption; open. |
| 3 | `cache-mix-smoke/main.c` | Spatz `vse32.v` → Snitch scalar load, same address | **125 mismatches on RTL.** `fences: 0` in the file. |
| 4 | `cache-test-scalar/main.c` | core 0 writes 256 lines → all cores read, 14 bare barriers | Fails on GVSoC at 48-84 % density; `cache-basic` sub-test **passes on RTL**. |

## What #4 shows that the others don't

Instance 4 fails on the model and passes on hardware for the *same binary*.
That is not a model defect and not a hardware defect — it is a **latent
software defect whose exposure depends on how wide the store-visibility window
is**. The model's async cache has a wider window than the RTL's, so the model
exposes it and the hardware hides it.

The practical consequence: **passing on RTL is not evidence that this class of
bug is absent.** A test can rely on a guarantee it never had, and hardware
timing can conceal that indefinitely.

## What to do

1. Fence both sides of every phase boundary that hands memory between cores.
   `rlc_sync.h`'s `rlc_phase_barrier()` is the pattern: fence, barrier, fence.
2. Fence after a vector store before any scalar access to the same address.
   `rlc_copy.h`'s `rlc_memcpy8()` already does this.
3. For a flag one core publishes for others, use `_Atomic` with release/acquire
   **and** a fence — the atomic alone orders the compiler and the single core's
   accesses, not the fabric.
4. Do not read `volatile` as a synchronisation primitive anywhere.

## Cost

Two `fence` instructions per boundary. Against a phase of work this is
irrelevant, and it is unconditionally cheaper than a silently wrong transport
block or a test that passes for the wrong reason.

## Open

- Whether #2 explains the RLC multi-entity wedge (M16/24/48). Fixed because it
  is a defect regardless; **not** asserted as the wedge's cause.
- Whether fencing #4 collapses the GVSoC mismatch density. Experiment pending.
- #3 needs a pristine-RTL arm to separate "test was always racy" from "recent
  cache rewrites perturbed the race" — both hypotheses predict that adding a
  fence fixes it, so the fence experiment alone cannot separate them.
  (Correction owed to the L1-timing session, who caught that.)
