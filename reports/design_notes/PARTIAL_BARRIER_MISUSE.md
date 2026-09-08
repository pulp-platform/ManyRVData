# The RLC partial-barrier design is wrong at more than one tile

**2026-09-08.** Found by the GVSoC session after they implemented real
participation-mask semantics. Two independent defects, both mine, both
invisible in every configuration I have tested.

## Defect 1 — the cluster mask is programmed and never restored

`cachepool_cluster_barrier.sv`:

```systemverilog
Idle: if (|(tile_barrier_i & barrier_mask_i)) begin
        mask_d = barrier_mask_i;      // re-read from the REGISTER every round
assign all_arrived = (tile_barrier_i & mask_q) == mask_q;
```

**There is no full-versus-partial distinction at the cluster level.** The
read/write distinction exists only in the *tile* barrier, for the per-core
mask. The cluster mask is persistent and gates every round.

`rlc_ul_init()` and `rlc_am_init()` set it to "tile 0 only" from `rlc_init()`
and never restore it. From that point **every `snrt_cluster_hw_barrier()` in
the program waits only for tile 0** — including `main.c`'s startup resync and
the final barrier before the report. At 64 cores the other 60 sail through
unsynchronised.

## Defect 2 — participants and non-participants share a tile

`cachepool_tile_barrier.sv`:

```systemverilog
req_mask[i] = in_req_i[i].q.write ? in_req_i[i].q.data[NrPorts-1:0]
                                  : {NrPorts{1'b1}};   // a READ means "all"
MaskIdle: if (|barrier_hit) begin
            core_mask_d = req_mask[first_hit_idx];      // FIRST arrival owns the round
```

**Whichever request arrives first defines the round's participant set.** In
`cluster_entry()` the non-participating cores — idle ones, and producers once
they finish — go to `snrt_cluster_hw_barrier()`, a *read*, meaning "all cores
in this tile". Consumers in the same tile are meanwhile issuing partial-barrier
*writes*.

So a consumer's partial barrier can be absorbed into an all-cores round (and
then blocks until every core in the tile arrives), or an idle core's full
barrier can be absorbed into a consumers-only round (and released early).
**Mixing the two inside one tile is unsafe by construction.**

This one is not even multi-tile-specific: at 4 cores with P1/C1, cores 2 and 3
are idle and parked at the full barrier while core 1 runs partial barriers.

## Why nothing caught either

- **Defect 1 is a no-op at one tile.** Every RLC run puts producers and
  consumers in tile 0, where the mask is `0x1` — the only tile.
- **Defect 2 has never run on correct barrier hardware.** GVSoC's barrier was
  a global counter to `nb_cores` until today — no masks at all — so the model
  could not expose it, and the partial-barrier TTI path has not been run on
  RTL.

The pattern from the other notes repeats: **a test passing is not evidence the
mechanism works, when the platform never implemented the mechanism.**

## Defect 3 — the mask restricts who must ARRIVE, not who gets RELEASED

`cachepool_cluster_barrier.sv` has a single `barrier_done_o`, and every tile's
cores release on it unconditionally:

```systemverilog
// cachepool_tile_barrier.sv
Global: if (barrier_done_i) state_d[i] = Take;    // no mask check
```

**So any partial-barrier round's completion releases every core waiting at a
barrier anywhere in the cluster.** `barrier_mask_i` gates the *arrival*
condition (`all_arrived = (tile_barrier_i & mask_q) == mask_q`) and nothing
gates the broadcast.

The consequence is stronger than defects 1 and 2, and it constrains any fix:

> **A partial barrier is only safe when no core outside the participating set
> is waiting at a barrier at the same time — anywhere in the cluster, not just
> in the same tile.**

### Refuted: "move the non-participants to another tile"

This is the obvious fix for defect 2 and it does not work. Recorded here so the
next person does not spend the same hour on it.

The idea: if only consumers occupy the consumer tile, no read-barrier and
write-barrier ever share a tile, so defect 2 disappears — and non-participants
in other tiles are outside the cluster mask, so they cannot satisfy the arrival
condition either.

Why it fails: **they do not need to satisfy the arrival condition to be
released.** `barrier_done_o` is broadcast, and a core in `Global` takes it
whatever tile it is in. So the participants' first partial-barrier round frees
every non-participant that has reached its own tile barrier, cluster-wide.

It means the software spin in step 3 below is not a design preference, it is
the only construct the hardware leaves.

## The API contradiction underneath

`snrt.h` says to program the mask and then "use `snrt_cluster_hw_barrier()` as
a resync point before relying on it". But the narrowing is already in force by
then, so that resync barrier is itself masked and does not wait for everyone.
**The documented usage cannot work at more than one tile.** A fix has to
restructure the arm/resync sequence, not just add a restore.

## Proposed fix (not yet implemented)

1. **Do not program the mask in `rlc_init()`** — that precedes `main.c`'s
   startup full barrier, which the narrowing would break.
2. **Arm inside the consumer entry**: consumer 0 programs the mask; the other
   consumers wait on an `_Atomic` release/acquire flag plus a fence, *not* on a
   barrier — they cannot use the barrier they are about to narrow.
3. **Keep non-participants out of the barrier entirely** while partial barriers
   are in use: idle cores and finished producers spin on a "consumers done"
   flag instead of entering `snrt_cluster_hw_barrier()`. **Forced by defect 3**,
   not chosen — moving them to another tile does not help, because the done
   signal is broadcast cluster-wide. The flag needs `_Atomic` release/acquire
   plus a fence (same treatment as `rlc_ul_barrier_armed`), and a back-off
   between polls so it does not reintroduce the traffic the TTI loop exists to
   remove. Note the *participants* still block on a real barrier — only cores
   with no work spin, and they had nothing else to do.
4. **Restore the mask to all-ones** (its `RESVAL`) after the TTI loop, before
   setting that flag, so the final full barrier is a real full barrier.

Costs one flag and one spin per non-participant, and removes the mixed-mode
round entirely.

## Verification plan

GVSoC can run a candidate at 4 and 16 tiles in minutes — that is where the
difference appears, and their model now reproduces the contradiction faithfully
rather than hiding it. Cheaper than RTL for the first pass; RTL confirms after.

## Related

`SYNCHRONISATION_IS_NOT_VISIBILITY.md` — the barriers do not fence.
`PROVENANCE_THE_TOOL_NOT_THE_CONFIG.md` — measure the artefact, not the config.

## The fix requires masked barrier semantics — measured, and it is a feature

Verified on GVSoC, same binary and config, 1 tile:

```
masked barrier    -> retval=0, 1,137,580 cycles, MASK-OK, check: PASS  (<110 s wall)
counting barrier  -> no completion in 400 s (4x budget), no UL/MASK/EOC output
```

It is a **deadlock, not slowness**: the counting barrier is cheaper per
operation, and the masked arm finished the identical workload in under a
quarter of the budget.

**Mechanism — defect 3 read backwards.** The fix has non-participants spin
*outside* the barrier. A barrier that completes at `count == nb_cores` then
waits for arrivals that will never come: at 1 tile, one consumer waiting for
four. Deadlock by construction. The fix and a counting barrier are mutually
incompatible.

Three things follow, and the third is the one to be careful about:

1. **The 1/4/16-tile pass is a joint result.** The kernel change and correct
   masked semantics are each necessary and neither is sufficient.
2. **The failure character changed, deliberately and for the better.** Before
   the fix, a mask that was absent or misprogrammed produced *silent
   corruption* — phases overlapping, short delivery, plausible output. After
   it, the same condition produces a **hang**. A deadlock is detectable; quiet
   wrong answers are not. This is worth stating because it looks like a
   regression in robustness and is the opposite.
3. **It says nothing about whether the masked implementation is correct**, only
   that it differs and that the fix needs the difference. A deadlock on the old
   barrier would look identical if the new one were wrong in some *other* way.
   The RTL readings remain the only evidence for correctness.
   (Distinction drawn by the GVSoC session against their own result.)

**Portability consequence:** this kernel now requires a platform that implements
the participation mask. That is true of the RTL and was not true of the model
until today.

## Verification, 2026-09-08

Passed at 1, 4 and 16 tiles. The decisive evidence was read from the **barrier's
own state**, not from the kernel's self-report:

```
16 tiles:  6 x 0xffff  ->  33 x 0x1  ->  3 x 0xffff
 4 tiles:  6 x 0xf     ->  33 x 0x1  ->  3 x 0xf
 1 tile:   all 0x1                       (narrowing is a no-op -- why it hid here)
```

Startup barrier full, consumers progressing narrowed, mask restored before
release, and the shape independent of tile count.

**Independent cross-check on the 33.** Derived from the traffic profile:
488 SDUs per TC1 slot / 49 PDUs per 8192 B block = 11 slots, x 3 phase barriers
= **33**. Measured from barrier state on the model side. Two independent paths
to the same integer with no shared intermediate — so the narrowed region
contains exactly the barriers the kernel should issue and no others: nothing
leaked in from an absorbed full barrier, and none escaped.
