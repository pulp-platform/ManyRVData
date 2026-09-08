# RTL reference batch — 2026-09-08

Config `cachepool_fpu_4g` (4 groups x 4 tiles x 4 cores = 64), QuestaSim.
Requested by the L1-timing session to check whether 15 cache rewrites are
cycle-identical. Run on their working tree; provenance pinned (see below).

| kernel | status | EOC (cyc) | kernel cyc | 08-25 pristine | verdict |
|---|---|---|---|---|---|
| `bandwidth` | **PASS** | 33,876 | 2,058 (32/load) | 33,876 / 2,058 / 32 | **exact match** |
| `byte-enable` | **PASS** | 303,288 | n/a | 303,288 | **exact match** |
| `cache-mix-smoke` | **FAIL** | 69,378 | 125 mismatches | pristine: 69,378 / 125 | **exact match** — test bug |
| `cache-test-scalar` | `timeout_cap` | — | `cache-basic` **PASS** | no baseline | partial |
| `cache-test-vector` | `timeout_cap` | — | `vcache-basic` **PASS** | no baseline | partial |

128 scoreboards PASS / 0 FAIL on all three that reached EOC. Zero illegal
instructions anywhere — so no scalar-FP traps in this set.

## Cycle-identity: established

`bandwidth` and `byte-enable` both reproduce the 2026-08-25 pristine reference
**bit-identically**, against references taken two weeks before the rewrites
landed. Per-channel AR/R also match (CH0 159/182, CH1 8/9, CH2 4/4, CH3 164/227),
so refill traffic is identical in count *and* distribution.

**EOC is the stronger figure than kernel cycles** (the peer's point): kernel
cycles cover the hot loop, EOC covers boot, snRuntime init, barriers, teardown
and all 64 cores. Nothing anywhere in either run shifted by a cycle.

**Consequence:** if the RLC multi-entity wedge depends on write-visibility
*timing*, the L1D rewrites are excluded as a confound — the cache presents
writes on identical cycles before and after.

## Scope: this measured T3.1-T3.15, which may not be what ships

The DUT here is the timing session's **full** transform set, T3.1 through T3.15.
Their post-placement OOC ladder subsequently recommended shipping **T3.1-T3.12
only** (WNS -0.091 vs -0.106; T3.13 alone accounts for 13 of the 15 ps).

So this batch is evidence for a **superset** of the intended ship set. Whether
cycle-identity carries to the subset follows only if each transform is
independently cycle-neutral — which is plausible, is what they claim, and is
**not what this batch measured**. Reverting three transforms is also a code
change that can itself introduce error, which a re-verify would catch and an
inference would not.

**Re-verify `bandwidth` on the reduced set before anyone calls it verified.**
That is ~10 minutes of wallclock and it is the difference between a measurement
and an argument.

## `cache-mix-smoke` — a test bug, attributable without a pristine arm

```c
vec_store_u32(base + part_ofst);            // vse32.v -> Spatz's LSU
for (j...) if (*(volatile uint32_t*)(base + part_ofst + j*4) != vec_vals[j]) errs++;
                                             // scalar load -> Snitch's LSU
```

Independent LSUs, no `fence` between them; `fences: 0` in that file. `volatile`
constrains the compiler and says nothing about two hardware load/store units.
Predates the rewrites and is independent of the cache datapath.

**Settled by a pristine arm (2026-09-08).** Pristine `f1cbe54` fails
identically:

| arm | RTL | EOC | UART | scoreboards |
|---|---|---|---|---|
| this batch | T3.1-T3.15 | 69,378 | `[FAIL] 125 mismatches` | 128 PASS / 0 FAIL |
| pristine | f1cbe54 | 69,378 | `[FAIL] 125 mismatches` | 128 PASS / 0 FAIL |

Same count, same tally, **EOC identical to the cycle**. The race predates every
transform in the set. The caveat this row used to carry — that a fence would
fix it either way, so the fence experiment could not separate "always racy"
from "the rewrites changed the exposure" — is discharged by measurement rather
than by argument.

**And it upgrades the cycle-identity result.** `cache-mix-smoke` is now a
*third* matching kernel, and the most informative of the three: RTL simulation
is deterministic, so a program whose output depends on inter-core timing
detects a class of perturbation a passing kernel cannot. Two clean kernels show
the transforms do not change correct programs; this one shows they do not
change a program that is *already* sensitive to timing between cores.

**Qualification — the sensitivity argument rests on something neither arm
measured: the width of the race window.** If the losing core loses by a handful
of cycles, the count is a fine detector and "almost any perturbation would have
moved it" holds. If it loses by several hundred, the count is insensitive to
small shifts and the same 125 would return whether or not timing moved. Both
are consistent with everything observed, because neither arm instrumented the
window.

So: **the cycle-identical EOC is the hard result. The sensitivity argument is a
reason to weight it above a passing kernel, not an independent proof.**
(Qualification raised by the L1-timing session against my own framing; recorded
because "sensitive detector" reads as proof of non-perturbation to anyone who
has not reasoned about the window — the same way "identical failure" reads as
set-equality.)

**Limitation, recorded before either side leans on it:** the test prints only a
count, never the mismatching addresses. The comparison is over
(count, EOC, scoreboard tally) and does **not** establish that the same 125
locations mismatched on both arms. Two different races landing on the same
count *and* the same cycle would be remarkable, but the instrument cannot rule
it out. Closing that gap needs a test change (print addresses), not an RTL one.

## The two capped tests, and the part that is still informative

Both hit the 1 h per-test cap during their `*-stress` phase. Both had already
**passed their `*-basic` phase**, which is the interesting half:

> `cache-basic` and `vcache-basic` are unfenced cross-core write / barrier /
> read tests — `fences: 0, volatile: 0, atomics: 0, 14 bare hw barriers` — and
> **they pass on RTL**, while the same source fails on GVSoC at 48-84 % density.

Same binary, passes on hardware, fails on the model. The hazard is real and in
the source; hardware's store-visibility window is narrow enough to hide it.
**Passing on RTL is not evidence this class of bug is absent.**

Caveat added after the fact: the GVSoC arm ran under a global counting barrier
that has since been replaced, so that comparison needs re-measuring before it
is leaned on. Flagged by the GVSoC session, accepted here.

## Provenance

- DUT is `hardware/deps/insitu-cache` — **grepped from the generated
  `compile.vsim.tcl`**, not inferred from `Bender.local`, whose override never
  applied (see `design_notes/PROVENANCE_THE_TOOL_NOT_THE_CONFIG.md`).
- `dut_tripwire.sha256` pins the compile script + all 30 insitu sources.
  `dut_watch.sh` sampled it every 45 s: **130 samples, 0 changes.**
- `elf_under_test/` holds the exact test binaries used, frozen `chmod a-w` with
  a manifest, verified by the peer against live `software/build` *before* any
  rebuild — which is what makes the freeze evidence rather than a claim.
- The four modified cache sources under test:
  `b23ed202 / 2bf77815 / 5307c217 / f0629785`, independently confirmed by the
  peer from a marker written before this batch was pinned.

## Wallclock

| kernel | wall |
|---|---|
| `bandwidth` | 598 s |
| `byte-enable` | 889 s |
| `cache-mix-smoke` | 236 s (pristine arm: 211 s) |
| `cache-test-scalar` | capped at 3600 s |
| `cache-test-vector` | capped at 3600 s |

I predicted `byte-enable` would cap by extrapolating linearly from
`bandwidth`'s cycles-per-second. It took 15 minutes, not 90. **Wall time is not
linear in EOC cycles across kernels** — different core counts and DRAM traffic.
