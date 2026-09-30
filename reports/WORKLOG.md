# CachePool Work Log

Running development log for assembling weekly reports. **Newest entries at top.**
Append an entry on every meaningful modification and on every git commit (see the
"Development log" section in `CLAUDE.md` for the convention). Each entry records the
time, commit, files, what + why, and verification.

---


## 2026-09-30

### History rewrite: tool attribution trailers removed from 2094188
- Commit `2094188` ([RTL] insitu_cache_ooc_wrapper) carried `Co-Authored-By: Claude...` and `Claude-Session:` trailers, against the no-tool-mention rule for commit messages. Reworded via `git rebase -i` on `dev/rlc-next` (unpushed); the 37 commits after it were re-created with **identical trees** (verified: new HEAD tree == old HEAD tree, 128 commits both).
- **All hashes from that commit onward changed.** References in this file were remapped; the full old->new map is `reports/history_rewrite_2026-09-30.map`. Hashes quoted to the GVSoC / timing sessions before today are the OLD ones -- translate with the map.
- Backup of the pre-rewrite branch: `backup/rlc-next-before-reword` (old HEAD `0b40899`). Delete once satisfied.
- Same trailers also on `007d31e` in `working_dir/insitu-cache` (branch `zexin/timing-metabank-loop-committed`, the tip; not checked out, unpushed). Reworded by us: new tip **`3c371bb`**, same tree, same parent `f1cbe54`, same author/dates. Backup: `backup/timing-metabank-loop-committed-before-reword`. The L1-timing session was notified that it is done.
- Verified: no commit on any non-backup branch of either repo mentions Claude/Anthropic.

## 2026-09-23 (noon)

### TC1 reaches its target: descriptor-ring to-send queue + owner plans in its private partition
- **Files:** `kernel/rlc_am.h` (RLC_AM_RING structures, RLC_AM_PRIV_PLAN), `kernel/rlc_am.c` (ring gather in
  plan, ring commit/STATUS, RLC_AM_QUEUED, private plan + vector publish), `kernel/rlc.c` (producer ring path,
  per-core receive-statistics shard), `software/tests/CMakeLists.txt` (`_am_xr`, `_am_xrp` targets).
- **Why:** TC1's single owner core was the serial bottleneck (plan 53% + commit 31%, IPC 0.15, 70% memory stall;
  48 helpers idle 87%). Causes: a linked to-send list in shared memory (a dependent remote load per node), 15
  producers on its lock, ~10 per-packet atomics on the entity's lines, and the ~7 KB plan buffer spread over ~28
  home tiles which the vector planner reads and writes.
- **RLC_AM_RING=1:** one array ring of SDU descriptors per entity (tail: producers, one atomic add; head: owner;
  ack: STATUS). No list, node pool or queue lock; commit advances head, STATUS advances ack. Per-packet entity
  statistics go to a per-core shard. Requires RLC_AM_WORKQ=0.
- **RLC_AM_PRIV_PLAN=1:** the owner plans in a buffer in its tile's private partition (0xB800_0000 + owner*size)
  and publishes the 8 executor fields to the shared plan with vector copies (scalar remote stores each wait for
  their response and made it slower: 1.40 M/s).
- **Results (GVSoC 4x4, 2P+2S banks, P16_C48_L64, 8 slots, all EOC 0):**

| TC1 | steady M pkt/s (burst / paced) | paced latency | <= 350 us |
|---|---|---|---|
| linked list (`am_x`) | 0.69 / 0.67 | backlog | 2% |
| + batched commit (`am_xb`) | 1.41 / 0.98 | backlog | 6% |
| + ring (`am_xr`) | 1.73 / 1.73 | p99 396 us, growing | 87% |
| + private plan (`am_xrp`) | **1.91 / 1.84 (target 1.852)** | **p50 49 us, p99 72 us, flat over 8 slots** | **100%** |

- **Open:** 64P+192C not rerun with `_am_xrp` (with `_am_xr` it was worse than 16P: 1.50); more headroom via
  vectorised ring gather and vector reductions in commit (owner PC profile: gather 29%, commit 25%, planner 24%).

---

## 2026-09-23 (morning)

### AM tile: STATUS only for entities that transmitted; up to G grants per owner per TTI
- **Files:** `kernel/rlc.h` (arena: dirty bitmap at +0x1C00, barrier/grant table at +0x1E00, plan/TB
  slots per (owner, grant)), `kernel/rlc.c` (setup), `kernel/rlc_am.c` (tile loop with
  `RLC_AM_TILE_GRANTS`; STATUS walks a dirty bitmap set at commit; no per-entity report lines in tile
  mode), `software/tests/CMakeLists.txt` (`_am_tile_g8` targets).
- **Why:** TC3 AM producers spent 67% sweeping all ~100 tile entities for STATUS after every packet.
- **Results (GVSoC 4x4):** TC3 AM tile 2.3 -> 10.6 M/s burst, paced at 3.125 sustained with p99
  24-32 us after slot 0; TC2 AM tile 11.4 -> 12.5 burst. 8 grants per TTI: no gain on TC3.
- The g8 runs exposed a second GVSoC Spatz deadlock (chained instruction counting its own writes),
  fixed in the GVSoC repo. Handover: GVSoC `prompt/HANDOVER_2026-09-23_rlc_scaling.md`.

---

## 2026-09-23 (night)

### Tile affinity on a half-private L1, AM in-tile and cross-tile, batched AM commit
- **Time:** 2026-09-23 ~02:00 +0200
- **Files:** `kernel/llist.{h,c}` (RLC_TILE_AFFINITY switch; batched queue ops under RLC_AM_BATCH),
  `kernel/mm.h`, `kernel/rlc.h` (private-region layout, tile arena, tile barrier line),
  `kernel/rlc.c` (tile setup, tile producer/consumer/STATUS/node pool), `kernel/rlc_am.{h,c}`
  (rlc_am_consumer_tile, per-core grant state, batched commit, lock-free peek, PKT_OUT at commit),
  `main.c` (RLC_PRIVATE_BANKS partition, per-tile setup between barriers),
  `script/generate_pdcp_pkg.py` (`slot_align`), new `_l64` JSONs, `software/tests/CMakeLists.txt`.
- **Why:** GVSoC now honours l1d_part() (it silently ignored it before), and the kernel's
  all-private `l1d_part(num_cores_per_tile)` is only correct when everything runs in one tile.
  User design: 2 private + 2 shared banks per tile; tile-private data above the 0xA000_0000
  boundary, globally shared data below it -- software-controlled coherence.
- **RLC_TILE_AFFINITY=1:** UE u owned by worker tile u % n_workers; rlc_ctx, list locks (one line
  each), AM entity, node pool, the tile's copy of its descriptors, plan buffers and transport
  blocks all in the private region, written only by the owner tile. Each tile's producer also runs
  STATUS for its UEs. Data slots aligned to 64 B so no line is shared by two tiles' packets.
- **AM in tile:** plan/execute/commit among the tile's 3 consumers, software sense-reversal barrier
  on a private line (the HW barrier is cluster-wide). **AM cross tile (TC1):** the existing TTI loop
  with the transport block moved below the boundary (0x9A00_0000, shared), 128 KB grants, producers
  on per-group streams. **Fix:** per-consumer AM grant state is now per core; the 16-slot table made
  consumers >= 16 share slot 0 and commit the owner's grant.
- **RLC_AM_BATCH=1:** commit moves the finished chain (the plan already holds its nodes) in two O(1)
  locked steps; plan walks the queue without holding its lock (only the owner removes).
- **Results (GVSoC 4x4, 2P+2S banks, all EOC 0, every packet delivered), steady M pkt/s:**

| | legacy tile | AM tile | AM cross-tile (+batch) | target |
|---|---|---|---|---|
| TC1 16P+48C | -- | -- | 0.69 (1.41 batched; 0.98 paced) | 1.85 |
| TC2 48 tiles | 10.7 burst / keeps up paced, p99 ~330 us | 11.4 burst / 9.1 paced, p99 460 us | -- | 7.81 |
| TC3 48 / 64 tiles | 5.3 / 4.3 burst, keeps up paced | 2.3 / 2.5 | -- | 3.13 |

- **Open:** AM TC3 (one grant per owner per TTI, few SDUs per UE); AM TC1 producers on one queue
  lock (64P worse than 16P); first-slot cold-start latency.
- AM-in-tile runs first hung in GVSoC: a Spatz model deadlock (chaining on a writer-less vreg),
  fixed in the GVSoC repo (core f3550501).

---

## 2026-09-23

### Per-group packet streams (RLC_GROUP_STREAMS): TC2 and TC3 sustained at their DP targets
- **Time:** 2026-09-23 ~00:30 +0200
- **Files:** `kernel/llist.h`, `kernel/mm.h` (pool sized for per-stream slices), `kernel/rlc.h`
  (`rlc_stream_t`), `kernel/rlc.c` (streams, stealing, node alloc/free per slice), `kernel/rlc_am.c`,
  `main.c` (`rlc_streams_init()` last before the start barrier), `software/tests/CMakeLists.txt`
  (`_pad_grp`, `_pad_grp_paced` targets on 16P+48C and 64P+192C).
- **What:** every group hosting producers owns a stream on its own cache line. Descriptors of stream
  s are s, s+n, s+2n... taken with one atomic fetch-add (no lock); nodes come from the stream's
  own pool slice under its own lock and return to it by address. Default 0 -> `M1_N1350_K100`
  loaded sections unchanged (md5).
- **Three follow-ups found by the runs, all fixed:**
  1. A producer steals from other streams once its own is empty -- otherwise the slowest stream
     sets the finish time (TC3 16P: 1/16 of packets ~170 ms late).
  2. Nodes are allocated from the slice of the packet's stream, not the producer's: a stealing
     producer ran its slice dry, and the kernel's out-of-memory path **drops the packet silently**
     (64P runs delivered 13.5k of 15.7k). That drop path is pre-existing and still there in the
     default build.
  3. The STATUS core takes no packets when other producers exist (it sweeps all entities between
     two packets), and under paced arrival a producer whose next packet is not due yet serves a
     stream that is > 2 us behind (groups have unequal producer counts).
- **GVSoC 4x4, 8 slots TC1/TC3, 4 slots TC2, all EOC 0, every packet delivered:**

| paced at the DP rate | delivered | target | p50 / p99 | within 350 us |
|---|---|---|---|---|
| TC2 64P+192C | **7.82 M/s** | 7.81 | 14 / 102 us | 100% |
| TC3 16P+48C | **3.13 M/s** | 3.13 | 11 / 33 us | 100% |
| TC3 64P+192C | **3.13 M/s** | 3.13 | 13 / 79 us | 100% |
| TC2 16P+48C | 4.12 M/s | 7.81 | backlog, p99 2.3 ms | 15% |
| TC1 16P+48C | 0.21 M/s | 1.85 | backlog | 1% |

  Burst capacity (steady): TC2 9.6 M/s and TC3 10.1 M/s on 64P+192C, 4.3 M/s on 16P+48C.
- **TC1 unchanged (0.21 at 16P, ~0.01-0.02 at 64P, 0.41 best at 2P+2C):** one entity, ~15-20
  atomics per packet on the same `rlc_ctx[0]` lines. Needs an owner-core design, not more cores.

---

## 2026-09-22 (late)

### Scaling fixes (RLC_PAD_SYNC), paced arrival, 8-slot sustained-load sweep on 4 / 64 / 256 cores
- **Time:** 2026-09-22 ~22:30 +0200
- **Files:** `kernel/llist.h` (RLC_PAD_SYNC, RLC_LINE_VAR), `kernel/mm.h`, `kernel/rlc.h`, `kernel/rlc.c`,
  `kernel/rlc_am.c`, `main.c` (lock accessors RLC_TOSEND_LOCK/RLC_SENT_LOCK), `kernel/perf_probe_events.h`
  (PKT_LATE), `script/generate_pdcp_pkg.py` (`"payload": false`), 9 `script/pdcp_pkg_*_{p2_c2,p16_c48,p64_c192}.json`,
  `software/tests/CMakeLists.txt` (sweep targets).
- **RLC_PAD_SYNC=1:** every lock and cross-core flag on its own 64 B line (per-user list locks, descriptor
  pointer + lock, `producer_done`, `mm_lock`, arrival t0) and an idle consumer reads `list.sduNum` before
  taking the lock. Default 0: loaded sections of `M1_N1350_K100` identical to before (md5 checked).
- **RLC_ARRIVAL_PPS=N:** descriptor i arrives at t0 + i/N; a producer waits for it; PKT_LATE tells the
  collector the arrival time, so latency is arrival -> PDU out and producer lag counts as latency.
- **Datasets:** 8 DL slots for TC1 (9256) and TC3 (15704), 4 for TC2 (19528, the 16 MiB source window
  holds 4.2); no payload bytes (headers ~100 KB). Layouts 2P+2C, 16P+48C (tile 0 of every group),
  64P+192C (every tile).
- **GVSoC 4x4, steady delivered rate (M pkt/s), all EOC 0:**

| | 2P+2C | 16P+48C | 64P+192C | target |
|---|---|---|---|---|
| TC1 (1 UE) | 0.41 | 0.22 | ~0.017 (partial) | 1.85 |
| TC2 (48 UE) | 0.32 | **4.01** | 0.92 | 7.81 |
| TC3 (4800 UE) | 0.27 | **4.03** | 0.92 | 3.13 |

- **TC3 at 16P+48C, paced at 3.125 M/s: sustained** -- delivered 3.126 M/s, p50 11 us / p99 32 us in
  every one of the 8 slots, 100% of packets within 350 us.
- **Ceiling is the global producer path:** TC2 and TC3 cap at the same rate for the same producer count
  (4.0 at 16P, 0.92 at 64P; producers 90-98% in receive). Every packet takes the one descriptor lock and
  the one pool lock; 64 producers spread over the mesh make each handoff slower, not faster.
- **TC1 is bound by its single entity:** all cores do ~15-20 atomic updates per packet on the same few
  lines of `rlc_ctx[0]`; at 16P+48C every core is 91% memory-stalled at ~1 memory op per 30 cycles.
- **Next:** per-group descriptor streams and node pools (TC2), entity-local accounting / owner-core
  design (TC1), STATUS sweep over 4800 entities makes the end-of-kernel drain ~8 ms (not in the rates).

---

## 2026-09-22 (evening)

### Perf-probe hooks and full-cluster (256-core) DP test cases
- **Time:** 2026-09-22 ~21:00 +0200
- **Commits:** perf-probe hooks (`kernel/perf_probe.h`, `perf_probe_events.h`, hooks in `rlc.c` /
  `rlc_am.c`); full-cluster test cases (`software/tests/CMakeLists.txt`, three
  `script/pdcp_pkg_*_p64_c192.json`, `data/.gitignore`).
- **Probes:** every hook is under `#if RLC_PROBE`; default targets' loaded sections and symbols are
  identical to a clean build. One posted store per event to 0xC002_0000 + hart<<8 + evt<<2, through
  a per-core pointer set once (a `csrr mhartid` per event cost +8.7%: Snitch's csrr waits for the
  vector sequencer). Events: role, phase, SDU in / PDU out (per-packet latency by node address),
  STATUS ACK, kernel/TTI markers. `_probe` targets for K100, M48_K300 and the AM K10 G8192 case.
  GVSoC decodes them (GVSoC repo `prompt/perf_probe_design.md`).
- **Full-cluster cases:** one DL slot of packets per DP test case -- TC1 M1_N1350_K1157, TC2
  M48_N800_K4882, TC3 M4800_N800_K1963 -- with 1 producer + 3 consumers in every tile (64 P /
  192 C). Headers are generated at build time from the JSONs (10-24 MB; too large for git).
  `MM_POOL_PAGES=K`: nodes are freed two per entity per ACK, so with many entities most stay live,
  and an exhausted pool silently drops the packet whose descriptor the producer already took.
- **GVSoC 4x4 (256 CC), all EOC 0, every packet timed:** TC1 0.044 M PDU/s (26.5 ms), TC2 0.132 M
  (37.0 ms, of which a 27 ms tail after the last PDU), TC3 0.745 M (2.6 ms). 256 cores are ~9x
  slower than 2P2C on TC1.
- **Cause (from the ELF):** one 64 B line at 0x8000ad40 holds the tail of `sent_llist_lock_2`,
  `pdcp_pkd_ptr_lock` (every producer, every packet), `producer_done` (polled by all 256 cores every
  iteration) and the head of `tosend_llist_lock_2`; all 48 users' locks fit in ~3 lines. Idle
  consumers poll by taking the lock (test-and-set). In the TC2 tail core 0 (STATUS) is 100%
  memory-stalled at ~2,500 cycles per access while the cache's mean latency is 15 cycles.
- **Next:** cache-line padding of locks/flags + lock-free empty check (define-guarded), paced
  arrival for sustained throughput/latency, multi-slot datasets.

---

## 2026-09-22

### Full kernel review against the DP Introduction and ETH RLC docs; four fixes
- **Time:** 2026-09-22
- **Read both source docs directly** (docx/pptx text extracted), not the KERNEL_REVIEW_NOTES summary. Then reviewed all 14 kernel files.
- **Verdict on completeness:** protocol layer complete (AMD/STATUS formats, SN-per-SDU, poll 32/25000, segmentation, RX reassembly + in-order delivery, ACK-only, no timers). Benchmark layer incomplete: no 4:1 DL:UL slot structure, UL is single-entity, TC2/TC3 not exercised (no 4800-user dataset), no control/scheduling task, no 128/256/512-thread linearity + PMU report, SDU 1353 vs our 1360.
- **Fix 1 -- TTI loop never terminated with RLC_AM_WORKQ=1 (the default).** `rlc_am_plan_phase` never cleared `rlc_am_bm_ready`; only the non-TTI `rlc_am_step` did. Producers set it, so `rlc_am_idle()` was never true and `rlc_am_stop` never set. **This is why no AM run ever reached `[EOC]` on GVSoC** -- every AM number they hold was from a truncated run of a non-terminating loop. Now clears on visit, re-arms if work remains.
- **Fix 2 -- spurious "buffer empty" polls.** `queue_drained = (avail < 128)`, but `list_peek_budget` stops on the byte budget so avail was ~6 always -> every non-segmenting grant set P on its last PDU. `list_peek_budget` now returns `reached_end`, decided under the lock.
- **Fix 3 -- UL slot rate 4x wrong.** I had used 1600 slots/s (the DL figure); the doc's tables say **UL slot numbers per second = 400** for all three test cases. TC1 UL is now 1953 SDUs/slot, matching the doc's own "disassembling packets per slot". **Invalidates the UL scaling numbers GVSoC measured** -- they were at a quarter of the specified load.
- **Fix 4 -- TTI phase cost.** Execute phase walked all NUM_USERS per pass even with the work queue; now walks the active bitmap. Plan phase took the list lock on idle entities; now pre-checks `sduNum`/`so_next`. Both matter for TC3's 4800 entities.
- **Reviewed and left alone (noted):** `rlc_am_help` n/claim ordering is only safe under TTI barriers (non-TTI mode has an ABA window; TTI is default); UL `complete[]` is effectively dead since deliver clears it immediately (dups of delivered SDUs land in `out_of_window`); `rlc_am_status` is O(NUM_USERS) per producer iteration.
- **Verification:** host `test_rlc_ul` 16,109/0 both EXEC modes, `test_rlc_plan` 589,728/0; **legacy loadable image bit-exact vs the previous commit** (rebuilt with HEAD's llist.{c,h}, md5 `e0e3ae62`); no unimplemented vector ops. Frozen 11 ELFs for the user's perf sim.

---

## 2026-09-08

### MULTI-ENTITY WEDGE: signature absent at 64 cores and M48 -- and the original observation was confounded
- **Time:** 2026-09-08 ~10:30 +0200
- **GVSoC ran the AM ladder serially on an idle machine, at both scales, with all three defects fixed.**

```
 4 tiles / 16 cores      GRANTS  MISMATCH  CYC/GRANT      16 tiles / 64 cores    GRANTS  MISMATCH  CYC/GRANT
 M8                          10      0.00     35,139      M16                        15      0.00     46,954
 M16                         14      0.00     29,611      M48                        20      0.00     31,054
 M24                         18      0.00     26,037      M48 (K=8 control)           7      0.00     44,960
 M32                         20      0.00     21,300
```
- **Zero payload mismatches at every rung, at both scales, across M8->M48** -- including M16 and M48 at 64 cores, the rungs and the machine size where the wedge was reported worst.
- **Entity-count scaling is monotonic in the GOOD direction at both scales.** 4 tiles: 35.1k -> 21.3k across M8->M32. 16 tiles: M48 (31.1k) beats M16 (47.0k). More entities = more available parallel work. **No non-monotonicity anywhere in either ladder** -- which is the wedge's actual signature.
- **The one cost found is on a different axis.** M16 at 4 tiles 29,611 -> at 16 tiles 46,954 = **1.59x worse**: same entity count spread over 4x the cores, so more NoC hops and more contention for the same entities. That is a machine-scale effect, expected, and orthogonal to "non-monotonic failure as entities increase". The K=8 control corroborates the channel is measuring something real (44,960 vs 31,054 at equal M with a third of the work to amortise).

#### The stronger conclusion: the original wedge observation was measuring an artefact stack
Every historical M16/24/48 failure was measured on a platform and a kernel that between them had **four** defects capable of producing exactly that signature:
| defect | effect | owner |
|---|---|---|
| barrier was a global counter to `nb_cores` | partial barriers released at semantically arbitrary times -> phases overlap | GVSoC |
| VLSU sized every access at lane width | manufactured line straddles -> **5-6 payload mismatches/grant** | GVSoC |
| tile mask armed at init, never restored | **every full barrier narrowed to tile 0** above 1 tile -- 60 of 64 cores unsynchronised | ours |
| verifier assumed SN advances per PDU | **1.00 spurious mismatch/grant**, deterministic | ours |
- Any one of those produces failure that worsens with core or entity count. **So "the wedge" as observed was never a measurement of the kernel.** Whether a real effect also existed underneath is unknowable from the old data -- the instrument and the subject were both broken.
- **Correct statement:** the wedge's signature is absent in both measurable channels at both scales with the defects fixed; the historical observation is retracted as confounded rather than explained.

#### What remains outside the instrument (GVSoC's framing, adopted)
- **Completion / hang** -- a bounded window cannot distinguish slow from wedged. If the wedge is a hang phenomenon, none of the above speaks to it. Probing it needs a **progress-stall detector, not a timeout**, and GVSoC would rather scope that deliberately than approximate it. Agreed.
- **Truncated runs** -- rates are the measurement, grant counts are not.

---

### Partial-barrier fix landed and validated; AM mismatch column resolved as THREE bugs, none payload corruption
- **Time:** 2026-09-08 ~09:00 +0200. Commits `dd5531e` (narrow fix), `46e1a33` (verifier SN), `3da7786` (progress line), `cbc45bf`/`9cd4457`/`4a9995a` (reports), `671462c`/`aaec01a`/`dab460d`/`3488749` (notes).

#### T3.1-T3.12 re-verify: both kernels exact
`bandwidth` 2,058 / 32 / EOC 33,876 / AR-R 335-422 and `byte-enable` EOC 303,288 -- **identical to both the 08-25 pristine reference and the T3.1-T3.15 arm.** Tripwire `DUT UNCHANGED` across both runs; ran the **frozen** `elf_under_test/` binaries so RTL was the only variable while I rebuilt `software/build` in parallel. **Designed the confound out rather than catching it** -- the earlier near-miss was the lesson. Deliverables in `reports/rtl_reference_t312_2026-09-08/`.

#### The partial-barrier fix -- validated at 1, 4 and 16 tiles
Arm on entry to the consumer loop (not `rlc_init`); consumers publish with an `_Atomic` flag, not the barrier they are narrowing; non-participants spin **outside** any barrier; restore to `RESVAL` before releasing them.
- **GVSoC measured the tile_mask trajectory from the barrier itself**, not from my kernel's prints: `6 x 0xffff -> 33 x 0x1 -> 3 x 0xffff` at 16 tiles, same shape at 4, all-`0x1` at 1. Startup barrier full, consumers progressing narrowed, mask restored before release, **shape independent of tile count**.
- **Independent cross-check on the 33:** derived from the traffic profile on my side (488 SDUs/slot / 49 PDUs per 8192 B = 11 slots x 3 phase barriers = 33), measured from barrier state on theirs. Two paths, no shared intermediate, neither party tuned toward it. So the narrowed region contains **exactly** the barriers the kernel should issue -- none absorbed in, none escaped.
- **The fix requires masked semantics: it deadlocks on a counting barrier**, by construction, because it withholds the arrivals such a barrier waits for. **The failure character changed deliberately for the better** -- a misprogrammed mask now *hangs* instead of corrupting silently. Recorded because it reads as fragility and is the opposite.

#### The AM payload mismatch column was THREE bugs and none was payload corruption
| cause | rate | owner | resolution |
|---|---|---|---|
| VLSU sizes every unit-stride access at lane width, manufacturing straddles | 5.1/grant | GVSoC | clamp, off the calibrated FSM |
| **verifier assumed SN advances per PDU** | 1.0/grant | **mine** | fixed |
| cross-core visibility | — | GVSoC | **no longer implicated** |
- **The VLSU bug came from my reading their log**: `addr=0x2c0023f size=4` is **not 4-byte aligned**, and my payload copy is `vse8.v` (byte elements) which cannot emit that. Their model was coalescing byte elements into 4-byte chunks and straddling lines no element crossed. Pointer, not diagnosis -- they found `size = std::min(width, pending_size)` with no line check.
- **The residue came from their number**: exactly **1.00 per grant across five cells, three binaries and two grant counts**. A race does not do that. `rlc_am_verify_grant()` set `verify_sn = sn[0] + n`, one too high on every grant ending on a partial -- **the same per-PDU SN assumption the uplink caught, which I fixed in both planners and the planner test and left in the verifier**, the one place that reports it as a payload failure.
- **Confirmed on `K4_G1024`** -- 1 KB grants against 1360 B SDUs segment in *every* grant, so the old verifier would have failed all six. Six clean, zero `[AM-SB]`.
- **And the `tb_used` sequence closes exactly:** 5477 total - 5440 payload = 37 header bytes over 9 PDUs, which forces 4 three-byte and 5 five-byte headers -- exactly one SDU-start per SDU and five SO-carrying continuations. Three independent quantities, one consistent assignment, and it is the protocol-correct one. **Segmentation is now validated on a target for the first time** -- my own worklog records it as "the path the passing RTL payload check never exercised".

#### Observability gap I created, then closed
Fixing the spurious mismatch removed the **only** per-grant output, so a correct AM run and a stuck one became indistinguishable -- and GVSoC then found that **no AM run has ever reached `[EOC]` on their engine**, so every AM cell in their table was a truncated run ("15 grants" meant "15 grants in 110 s"). Added an unconditional `[AM] grant N ok ... cyc=` line. Their rates were unaffected, which is why the conclusions hold, but the counts were not totals.

#### What the wedge ladder can still measure
Agreed with GVSoC and worth recording as a limit: **mismatch rate per grant** and **grants-per-cycle** are comparable from truncated runs; **completion/hang is not, and is out of reach on that engine.** If the wedge is purely a hang phenomenon it cannot be seen there, and we say so rather than infer it from timeouts.

#### Process
Three confounds caught before landing on the wrong side, and in every case the finding contradicted what the code's owner expected. The mechanism was not expertise: **each side held an artefact the other could not generate** -- I cannot produce their `[XLINE]` addresses, they cannot read my verifier source. See `design_notes/PROVENANCE_THE_TOOL_NOT_THE_CONFIG.md`.

---

### RTL reference batch COMPLETE; and the RLC partial-barrier design found broken at 3 levels
- **Time:** 2026-09-08 ~06:20 +0200
- **Commits:** `18ae20d` (mask read-back guard), `523b8e2` / `dab460d` / `aaec01a` (PARTIAL_BARRIER_MISUSE note), `c08c1fc` (provenance synthesis), `3b4b1a0` (batch results). All local, unpushed.

#### Batch result -- cycle-identity established
| kernel | status | EOC | kernel cyc | vs 08-25 pristine |
|---|---|---|---|---|
| `bandwidth` | PASS | 33,876 | 2,058 / 32 per load | **exact** |
| `byte-enable` | PASS | 303,288 | n/a | **exact** |
| `cache-mix-smoke` | FAIL | 69,378 | 125 mismatches | no baseline -- **test bug** |
| `cache-test-scalar` | timeout_cap | — | `cache-basic` **PASS** | partial |
| `cache-test-vector` | timeout_cap | — | `vcache-basic` **PASS** | partial |
- 128 SB PASS / 0 FAIL on all three reaching EOC; zero illegal instructions. Per-channel AR/R identical too, so refill traffic matches in count *and* distribution.
- **DUT tripwire: 130 samples over the whole batch, 0 changes.** Provenance held end to end.
- `cache-mix-smoke` is a Spatz-`vse32.v` -> Snitch-scalar-load handoff with no fence (`fences: 0` in that file). Attributable **without** a pristine arm. **Caveat recorded at the peer's insistence:** a fence fixes a race regardless of what exposed it, so the fence experiment alone cannot separate "always racy" from "rewrites perturbed the exposure" -- that row is not evidence about their RTL either way.
- **Wrong prediction of mine, recorded:** I said `byte-enable` would cap, extrapolating linearly from `bandwidth`'s cycles-per-second. It took 15 min, not 90. Wall time is not linear in EOC cycles across kernels.

#### THE BIG FINDING: the RLC partial-barrier design is wrong at three levels
Found by the GVSoC session after they implemented real participation-mask semantics. Written up in `reports/design_notes/PARTIAL_BARRIER_MISUSE.md`. **All three are mine.**
1. **The cluster mask is programmed and never restored.** `mask_d = barrier_mask_i` is re-read every round and there is **no full-vs-partial distinction at the cluster level**. `rlc_ul_init()`/`rlc_am_init()` narrow it to tile 0 from `rlc_init()` and never undo it, so **every later `snrt_cluster_hw_barrier()` -- including main.c's startup resync -- waits only for tile 0.** At 64 cores the other 60 sail through unsynchronised.
2. **Participants and non-participants share a tile.** `req_mask = write ? data : all-ones`, and **whichever request arrives first owns the round**. Idle cores and finished producers sit at the full barrier (a *read*) in the same tile where consumers issue partial-barrier *writes*. Two opposite symptoms from one mechanism -- absorbed into an all-cores round it **hangs**, absorbed into a consumers-only round it **releases early** -- which is how it reads as two bugs. **Not multi-tile-specific: bites at 4 cores with P1/C1.**
3. **`barrier_done_o` is a single unmasked broadcast.** Every tile's cores take it with no mask check, so **a partial-barrier completion releases every core waiting at a barrier anywhere in the cluster.** The mask gates *arrival*, not *release*. This refutes the obvious fix for (2) -- moving non-participants to another tile -- and makes the software spin the only construct the hardware leaves.
- **Why nothing caught it:** (1) is a no-op at one tile (mask 0x1 = the only tile); (2)+(3) have **never run on correct barrier hardware** -- GVSoC's barrier was a global counter to `nb_cores` until today, and the TTI path has not been on RTL. **Every green result for the TTI path came from a platform that did not implement the mechanism.**
- **API contradiction underneath:** `snrt.h` says to program the mask then use `snrt_cluster_hw_barrier()` as the resync point -- but the narrowing is already in force, so that barrier is itself masked. **The documented usage cannot work at more than one tile.**
- **Fix designed, NOT implemented -- awaiting the user.** Four parts: arm inside the consumer entry (not `rlc_init`); consumers sync on an `_Atomic` flag, not the barrier they are about to narrow; non-participants stay out of the barrier entirely (forced by defect 3) with back-off; restore the mask to `RESVAL` before the final full barrier. GVSoC will validate at 1/4/16 tiles in minutes with a `CACHEPOOL_BARRIER_COUNTING=1` arm alongside.

#### Two corrections to my own earlier claims
- **The `armed=1` guard was not a map check.** It printed a *software copy* of the intended mask, so it reported healthy on a run whose mask write went to the wrong address. I described it to GVSoC as a check, they retracted a correct objection on the strength of my description, and I had to give it back. **A check that cannot fail is not a check.** Now reads the register back, plus a pre-write `RESVAL 0xffffffff` probe (vs `CFG_L1D_TILE_SEL` resetting to 0 at the same address under the wrong map) -- GVSoC measured that it discriminates all three maps.
- **Retracted the `cache-basic` vs GVSoC 48-84% comparison**, at their prompting: their arm ran under the old global-counting barrier, which is not a neutral backdrop for a cross-core write/barrier/read test. Needs re-measuring on the new barrier before it is leaned on.

#### Process
`reports/design_notes/PROVENANCE_THE_TOOL_NOT_THE_CONFIG.md` closes with the synthesis: **the useful mechanism was not either party being right, it was each checking the other's claim against an artefact rather than a description** -- disassembly over header, generated script over `Bender.local`, `set_eoc`'s immediate over the header, `[EOC]` over plausible output, `RESVAL` over "the address accepts a write". Every real finding today came from that; both sides' errors came from the reverse.

---

### AM TTI loop fenced -- the same missing-fence defect the uplink proved, in the downlink
- **Time:** 2026-09-08 ~04:08 +0200
- **Files:** `kernel/rlc_sync.h` (new), `kernel/rlc_am.c`, `kernel/rlc_ul_drv.c`
- **User approved the recommendation.** The downlink TTI loop separated its phases with bare `snrt_cluster_partial_barrier(mask)` -- **four sites, zero fences**.
- **The defect:** `snrt_cluster_partial_barrier()` is one plain store to the barrier register. It synchronises *execution*, not *memory*. Every RLC phase boundary is a producer/consumer handoff of shared memory:
  - **DL plan -> execute:** the owner writes ~7 KB of plan (header lengths, segment lengths, source pointers, `n_avail`, `tb_used`); **every helper then reads it to copy payload**. Stale lengths or offsets corrupt the transport block *silently*.
  - **DL execute -> commit:** helpers write payload, the owner accounts it.
  - **UL scan -> reassemble:** already fixed earlier today.
- **This is not a theory -- the identical mechanism was proven on hardware hours earlier** in the uplink: a value core 0 stored and another core loaded, with a barrier between, disagreed, with both the store and the load provably executing in the disassembly. Same primitive, same absence of a fence.
- **Fix:** new `rlc_sync.h` with `rlc_phase_barrier()` -- fence, barrier, fence. Applied to all four DL sites; the UL's local duplicate was removed and now uses the shared one. **Verified in the object code:** fences emitted as `fence / jalr snrt_cluster_partial_barrier / fence` at each site. (Nine full fences in the function, not eight: the ninth is pre-existing, from `rlc_am_poison`. Checked rather than assumed.)
- **Still a hypothesis, stated as one:** this may or may not explain the multi-entity wedge (M16/24/48 failing non-monotonically). It is fixed because **a missing fence is a correctness defect regardless** -- keeping it to protect a performance baseline would mean protecting a measurement of a program that can silently corrupt. Two confident diagnoses of mine already died today; this one is not being asserted as the wedge's cause.
- **Verification:**
  - Fences present and correctly paired in `rlc_am_consumer_tti` disassembly.
  - Host `test_rlc_ul` **16,109 / 0 both EXEC modes**, `test_rlc_plan` **589,728 / 0**.
  - **Legacy loadable image bit-exact** (legacy does not use partial barriers).
  - **UL loadable images bit-identical to the pre-refactor freeze** -- so moving the UL barrier into the shared header changed no code. My first attempt at this check compared whole ELFs and reported "differs"; that was debug-info line numbers, not codegen. Corrected to compare loadable images.
  - No unimplemented vector ops. (AM ELFs use `vslideup/vslidedown/vadd/vsub/vand/vmv` from the vector planner -- all datapath-implemented; the known Spatz gap is integer *compares* and `vmerge`, neither present.)
  - Frozen at `reports/handover/elf_frozen_2026-09-08_0408_am_fenced/` -- the wedge ladder M8/12/16/24/32 tbchk plus M16 entpad. Note M16 entpad and M16 tbchk now share an md5, because `RLC_AM_ENT_PADDED=1` is the default and the variant is no longer distinct.
- **Rebuilt safely alongside the running RTL batch**, which is the hazard the timing peer identified: took a tripwire reading and `compile.vsim.tcl`'s mtime **before and after** `make sw`. Both unchanged, vsim still alive -- so `make sw` is empirically safe during a batch, which is now a known-good fact rather than an assumption.
- **Consequence for GVSoC: their AM performance baselines must be re-taken** -- fences shift cycle counts. Told them, with the reason.

---

### RTL reference batch for the timing peer: `bandwidth` reproduces pristine EXACTLY across 15 cache rewrites
- **Time:** 2026-09-08 ~04:05 +0200 (batch continues)
- **Report:** `reports/rtl_reference_2026-09-08/` -- `summary.tsv`, `RTL_STATE.md`, `dut_tripwire.sha256`, `verify_dut.sh`, `build_report.sh`, `insitu-cache_under_test.diff`, per-test logs.
- **Ran at the user's instruction** the batch the L1-timing session asked for, on `cachepool_fpu_4g`: `bandwidth`, `byte-enable`, `cache-mix-smoke`, `cache-test-scalar`, `cache-test-vector`.
- **RESULT -- `bandwidth` PASS, bit-identical to the 2026-08-25 pristine reference on every figure:**

  | | 08-25 pristine | 09-08 with 15 rewrites |
  |---|---|---|
  | kernel cycles | 2,058 | **2,058** |
  | avg per load | 32 | **32** |
  | performance | 1990 elems/1000cyc | **1990** |
  | **EOC (whole sim)** | **33,876** | **33,876** |
  | AR / R in kernel | 335 / 422 | **335 / 422** |
  | scoreboards | 128 PASS | **128 PASS / 0 FAIL** |

  Per-channel AR/R also match: CH0 159/182, CH1 8/9, CH2 4/4, CH3 164/227.
- **The peer's analytical point, adopted: EOC is the stronger figure, not kernel cycles.** Kernel cycles show the hot loop is unchanged; **EOC covers boot, snRuntime init, barriers, teardown, all 64 cores** -- nothing anywhere in the run shifted by a cycle. And matching per-channel AR/R means refill traffic reaching the NoC is identical in count *and distribution*, so the cache is not finishing on time by luck while generating different downstream traffic.
- **This passes the peer's own falsification test rather than merely not failing it** -- they had staked the cycle-identical claim on bandwidth returning exactly 2,058. **Consequence we can use: if the RLC multi-entity wedge depends on write-visibility *timing*, the L1D rewrites are excluded as a confound**, because the cache presents writes on identical cycles before and after. One variable removed from a problem where every hypothesis so far has died.
- **DUT provenance, because a reference number is worthless without it:**
  - **Corrected a real error of mine.** I wrote that `Bender.local`'s override meant the batch compiled `working_dir/insitu-cache`. **Wrong** -- `sim/work/compile.vsim.tcl` (mtime 08-24, never regenerated because RTL sources are *not* prerequisites of that make target) resolves to `hardware/deps/insitu-cache`. The peer caught it; I verified rather than accepted (`cmp` on all four files: identical; diff-vs-HEAD sha `f6657ec2ac4eda12` in both trees). DUT was right, my stated path was not. **Lesson: grep the compile script, never infer the DUT from the override file.**
  - **Tripwire added** (`dut_tripwire.sha256`): the compile script **plus all 30 insitu sources it names**, not just the 4 the peer edited -- a silent tree switch moves everything, so checking only the edited files would miss the exact case the tripwire exists for. `verify_dut.sh` re-checks; **DUT UNCHANGED** confirmed immediately after bandwidth.
  - The peer independently produced the same four file hashes from a marker file their own script wrote at 02:49, **before** I pinned anything -- two independent measurements agreeing, not one copied from the other.
- **`summary.tsv` was initially wrong and is now generated properly.** The batch script's inline grep looked for `Simulation ended at N`, but the real print is `[EOC] Simulation ended at <spaces> N (retval = 0)` in **picoseconds** -- so it recorded `n/a` for a run whose number was right there. Replaced with `build_report.sh`, which parses the logs for EOC/retval/kernel cycles/per-load/scoreboard tallies/illegal-instruction counts and classifies each row.
- **Machine-time safety:** checked `pgrep -a vsim` before touching anything -- **19 vsim processes running, none of them this repo** (the user's TeraNoC work and another user's jobs). A blanket `pkill vsim` would have destroyed all of them.
- **Known cap risk, flagged to the peer up front:** per-test cap is 1 h; `byte-enable` was 303,288 EOC cycles on 08-25 (~9x bandwidth, which took 598 s), so ~90 min -- it will likely cap. **A `timeout_cap` there is my cap, not a regression.** The peer has explicitly released it ("bandwidth has already done the job byte-enable was there to corroborate"). If re-run, it is for **our** GVSoC calibration (the 0.87x ratio), not for them.
- **Division of labour settled with the peer:** they run the pristine arm for `cache-test-scalar`/`cache-test-vector`, on their own tree, after my batch frees `sim/work`. Deciding reason: stashing their four files IS the freeze they committed to, and doing it mid-batch would cause exactly the DUT switch we spent three messages guarding against. They also noted they can reconstruct their changes from their own transcript and OOC runs; I cannot. **I signal when the last test exits; they do not touch the tree before that.**

---

### RLC UL: barrier flag was invisible cross-core; UL re-parameterised to the documented 160 B profile; committed
- **Time:** 2026-09-08 ~03:52 +0200
- **Commit:** `7cbc7a2` "rlc: AM transport-block assembly (DL) and reassembly (UL)" -- 40 files, 7419 insertions. Frozen ELF binaries deliberately NOT committed.
- **The v3 fix did not take, and GVSoC's guard caught its own build.** All five v3 ELFs printed `[UL] FATAL: tile participation mask never programmed`. **My static verification metric was worthless**: I had been grepping the objdump listing for the symbol name, which counts *interleaved source-comment lines and the definition label* -- for the v3 ELFs all three "hits" were a comment, a label and a source line, and **not one was a call**. GVSoC spotted the disagreement between my metric and their runtime guard and told me to re-derive it.
- **Second root cause, also mine:** `rlc_ul_barrier_armed` was a plain `static uint32_t` (in `.sbss`), written by core 0 in `rlc_init()` and read by the consumers after `main.c`'s `snrt_cluster_hw_barrier()`. Proven by disassembly that **the store executes** (inside main's `bnez s0` core-0 block, `sb s1, 1572(a0)`) and **the load executes** (`lbu`+`beqz`, not constant-folded) -- and they still disagreed. **The hardware barrier is a synchronisation event, not a memory fence, and a non-atomic store carries no ordering of its own.** Fixed: `_Atomic` with release/acquire, in `.data` cacheline-aligned, plus an explicit `fence`.
- **Same class, wider blast radius:** `snrt_cluster_partial_barrier()` is documented as "a plain volatile store" -- so **the phase barriers do not order memory either**. Consumer 0 writes the scan buffer in phase 1 and the others read it in phase 2. Added `rlc_ul_barrier()` which fences on both sides. **The AM TTI loop has the same unfenced pattern (plan writes -> execute reads across `snrt_cluster_partial_barrier`) and is a live suspect for the unresolved multi-entity wedge** -- NOT changed yet, because GVSoC holds AM baselines against the current loop. Flagged.
- **A sound static metric, replacing the bad one:** `scratchpad/callcheck.py` resolves `auipc`+`jalr` pairs (and direct `jal`) to their target address and compares against the symbol's `nm` address. Reports **exactly 1 resolved call site** for `snrt_barrier_set_tile_mask` in each UL ELF, with its address. The honest conclusion, though, is GVSoC's: **the runtime `armed=` print is the verification; a static grep is at best corroboration.**
- **UL re-parameterised to the documented profile (user: "align to the doc").** `doc/KERNEL_REVIEW_NOTES.md` (from `DP Introduction.docx`) specifies UL as **160 B** PDUs at **1 / 8 / 4 Gbps** for TC1/TC2/TC3, 1600 slots/s. I had reused the 1360 B *downlink* dataset -- not the documented workload, and a pathological pick: 1360 B in an 8192 B block packs as exactly six whole SDUs with two bytes spare, so **nothing ever segmented** and the serial header walk was measured on traffic containing none of what makes it serial. Now `RLC_UL_SDU_BYTES=160`, `RLC_UL_TC` selects the rate, and the slot budget is derived: TC1 -> 78,125 B and **488 SDUs per slot**, ~49 PDUs per 8 KB block, segmenting at every boundary. Targets renamed `*_ul_tc1_*` so the old 1360 B numbers cannot be confused with these.
- **Still not doc-aligned, flagged not silently skipped:** the **4:1 DL:UL slot split**. It needs the AM TTI loop refactored into a per-slot function so DL and UL slots interleave in one TTI; the doc lists it under P2 ("TTI structure ... our side, not the new kernel"). Deferred, not forgotten.
- **Verification:** host `test_rlc_ul` **16,109 / 0 both EXEC modes**, `test_rlc_plan` **589,728 / 0**, legacy loadable image **bit-exact**, no unimplemented vector ops in any of the five TC1 ELFs. Frozen at `reports/handover/elf_frozen_2026-09-08_0351_ul_tc1/`.
- **Also running:** the peer-requested RTL reference batch (`bandwidth`, `byte-enable`, `cache-mix-smoke`, `cache-test-scalar`, `cache-test-vector`) on `cachepool_fpu_4g` -> `reports/rtl_reference_2026-09-08/`. Checked `pgrep -a vsim` first: **19 vsim processes were running, none of them this repo** (TeraNoC and another user's jobs) -- a blanket `pkill vsim` would have destroyed all of them.

---

### RLC UL ROOT CAUSE: the phase barriers were never armed -- Step 1 of a two-step API was missing
- **Time:** 2026-09-08 ~03:31 +0200
- **Files:** `kernel/rlc_ul_drv.h` (new), `kernel/rlc_ul_drv.c`, `kernel/rlc.c`
- **My false-sharing prediction FAILED and GVSoC held me to it.** After the word-sizing fix: C2 went **62/64 -> 23/64 (worse)**, C3 unchanged at 3/64, `segments=164` survived. By my own stated criterion that was supposed to move the finding to their side. They were right to say "the layout change moved the number without removing the failure" -- but their inference (their visibility bug) was wrong too, and my prediction is what pointed them there. They were about to spend a shadow-bank check and a synchronous-cache-path run on it.
- **ACTUAL ROOT CAUSE, proven in object code, entirely mine:** `snrt_cluster_partial_barrier` is a **two-step API**. Step 1 programmes the cluster tile-participation mask (`snrt_barrier_set_tile_mask`) from exactly one core, before a full `snrt_cluster_hw_barrier()` resync. Step 2 is the per-phase call. **I only ever wrote Step 2.** `snrt_barrier_set_tile_mask()` lives in `rlc_am_init()`, gated on `RLC_TB_MODE == AM`; the UL builds set `RLC_UL_MODE=1` and leave `RLC_TB_MODE` at LEGACY, so **`rlc_am_init()` never runs and the mask is never programmed.**
  ```
  AM ELF        snrt_barrier_set_tile_mask references: 3
  all 5 UL ELFs snrt_barrier_set_tile_mask references: 0
  ```
- **Self-inflicted, and I can name the decision:** when wiring the UL in I chose *"lazy init inside `rlc_ul_consumer()` so `rlc.c` needs no extra hook"* -- which moved init to **after** `main.c`'s startup resync barrier, the one place it cannot go. I saved one `#if` block and lost the synchronisation contract.
- **Every observation follows, including the ones that defeated both hypotheses:**
  - Phase 2 runs while consumer 0 is still building/scanning -> cores read a scan buffer mid-write -> `segments` over/under-counts (66, 62, **164**) and `oow=662`. The surviving anomaly, with no double-counting bug needed.
  - Phase 3 runs before other cores have folded their segments in -> `recv[slot]` short -> **deliver halts at the first hole**. **`delivered == rx_next` in every single run** (64/64, 23/23, 3/3, 5/5) -- delivery was never corrupting, it was stopping. `dup=0` and `oow=0` on every copy run: nothing malformed, the data just wasn't there yet. That equality was in the first data set and I did not see it.
  - C1 passes trivially -- one consumer needs no phase separation.
  - Monotonic in core count; **layout-sensitive without being layout-caused**, which is exactly why the false-sharing fix moved 62->23 without fixing anything: it changed timing, not synchronisation.
  - `polls_ack` varying 11/11/9/11/13 on identical input -- poll bit read from a scan record being overwritten.
- **Fix:** `rlc_ul_init()` now programmes the tile mask and is called from `rlc_init()` before the startup hw barrier -- same placement and same reason as `rlc_am_init()`. New `rlc_ul_drv.h` so the prototype is visible at `rlc_init()`, which is defined earlier in the TU.
- **Guard added, because this failure mode is silent by construction:** an unarmed partial barrier does not error, it returns immediately and lets the phases overlap, yielding *plausible* short delivery. The consumer now checks an armed flag and prints `[UL] FATAL: tile participation mask never programmed` rather than producing quiet garbage, and every run prints `[UL] barrier tile_mask=0x.. local_mask=0x.. armed=..` so a regression is visible in the log. **Generalises: any future user of the partial-barrier API needs Step 1, and nothing in the API forces it.**
- **Verification:** all five ELFs now reference `snrt_barrier_set_tile_mask` 3x (matching AM), no unimplemented vector ops, host `test_rlc_ul` **16,109 / 0 in both EXEC modes**, `test_rlc_plan` **589,728 / 0**, legacy loadable image **still bit-exact**. Frozen at `reports/handover/elf_frozen_2026-09-08_0331_ul_v3/`.
- **Kept from the failed hypothesis:** the byte-granular `seen[]`/`complete[]` sharing and the `rx_next_highest` read-modify-write are real defects and stay fixed -- they would have surfaced later; they just were not this.
- **Process note worth keeping:** GVSoC refusing to accept "proven mine" on my say-so is what forced this find. Had they taken the false-sharing story, the barrier bug would still be there. Cheap cross-checking beat both engines' leading theories twice in one session.
- **Open:** awaiting the v3 re-run. `seg` Amdahl numbers (1.16 % -> 2.40 % with real segmentation, ~88 % parallel efficiency) are indicative only -- they come from a 5/64 run and need re-measuring on a passing one.

---

### RLC UL: GVSoC run found a real concurrency bug in my entity struct -- byte-granular sharing
- **Time:** 2026-09-08 ~03:25 +0200
- **Files:** `kernel/rlc_ul.h`, `kernel/rlc_ul.c`, `kernel/rlc_ul_drv.c`, `software/tests/CMakeLists.txt`
- **GVSoC ran the ladder.** Result: C1 copy PASS (64/64), C2 copy 62/64, C3 copy **3/64**, C3 count 64/64 but `oow=663`.
- **My predicted "truncation signature" was wrong and they disproved it properly.** I had told them `count` passing while `copy` failed would be their cross-line truncation bug. They checked the truncation profiles: **identical across all four runs, including the PASSING C1 run** (735 detail lines / 42 milestones / peak 16 / first addr 0x2c2003d). Truncation therefore cannot be what separates pass from fail, and `count` did not pass either. A signature that fires on a passing run distinguishes nothing. Their check, my error.
- **ROOT CAUSE, and it is mine, not the model's:**
  ```c
  uint8_t seen[RLC_UL_WINDOW];      /* WINDOW=64 -> 64 bytes = EXACTLY ONE CACHE LINE */
  uint8_t complete[RLC_UL_WINDOW];
  ```
  The parallel reassemble phase has every consumer doing `e->seen[slot] = 1u` -- **concurrent sub-word stores from different cores into the same cache line**. That is precisely the case a partial-strobe path can drop, and a lost `seen[slot]` silently costs an SDU. It gets worse with more writers, which is the observed **64 -> 62 -> 3** monotonic degradation, and C1 passes because with one core there is no concurrent writer. No coherence bug is needed to explain any of it.
  - Also explains copy-vs-count with no truncation involved: `count` does **12x less parallel work** (`reasm_max` 42,799 vs 513,673), so the window in which two cores are inside that line at once is ~12x narrower. Same defect, less exposure -- GVSoC's own framing, located in my code.
- **Fix:** every field written in the parallel phase is now word-sized and word-aligned (`seen`/`complete` -> `uint32_t[]`), and `rlc_ul_entity_t` is split into three **cache-line-separated** regions: serial-phase state (rx_next, delivered...), parallel-phase counters (reassembled, dup, oow, status_due), and the window arrays. Mixing them also meant every atomic RMW invalidated the line holding the serial state. Same lesson as `RLC_AM_ENT_PADDED=1` on the DL side.
- **Second, independent race found while in there:** `rx_next_highest` was maintained in the parallel phase as a **read-modify-write on shared state** -- two cores can both read the old value and both store, dropping the higher. It is §5.2.2.2 bookkeeping no decision depends on, so it moved out of the parallel phase into a serial helper (`rlc_ul_note_highest()`, fed by a new `max_sn`/`have_sn` in the scan, which already walks every PDU in order) rather than becoming an atomic.
- **COVERAGE HOLE found chasing their `segments=164` anomaly:** at `RLC_UL_TB_BYTES=8192` with 1360 B SDUs, a block holds **exactly 6 whole SDUs with 2 bytes to spare -- so the run never segmented a single SDU.** Every header was 3 bytes, SO never appeared, SI was always FULL. The ladder was measuring the serial scan on traffic that does not contain the thing that makes it serial, which makes the ~1.0 % Amdahl figure an optimistic bound. Added `RLC_UL_TB_BYTES` as a target parameter and a fifth ELF `..._P1_C3_ul_seg` at **TB=3000**, which forces a split in nearly every block (5-byte headers with SO, SI FIRST/MIDDLE/LAST, segments spanning blocks).
- **`segments=164` itself is unreproduced.** Host gives identical results in both `RLC_UL_EXEC` modes. With 12 slots x 6 PDUs there are at most 72 PDU visits, yet `segments + oow` = 827 for that run. Asked GVSoC for the raw `[UL]` lines -- their summary omitted `slots=` and `dup=`, which would narrow it. Open.
- **Their measurement stands and is worth keeping:** scan flat at 15,194-15,324 across all four (<1 % spread, serial by construction and it measures that way); reassemble **93-95 % parallel efficiency** (1.00 / 1.86 / 2.84 vs ideal 1/2/3) with `reasm_sum` conserved at 1.46-1.51 M, so the speedup is real division of labour. Payload movement is ~92 % of reassemble. **Scan Amdahl fraction: ~1.0 % with payload moved, ~14.7 % headers-only** -- the serial header walk is not what limits us while real payload is moving. They also caught a misreading I would have made: C3 copy's low `serial=17,201` is not a serial speedup, it is `deliver` being small because only 3 SDUs were delivered.
- **Falsifiable prediction given to them:** if the byte-sharing diagnosis is right, C2/C3 copy now deliver 64/64 unchanged. If they still degrade with consumer count, my explanation is wrong and it is on their side -- a stronger datapoint for them than the first run.
- **Verification:** host `test_rlc_ul` **16,109 / 0 in both EXEC modes**, `test_rlc_plan` **589,728 / 0**; build clean with no warnings from any new file; no unimplemented vector ops in any of the five ELFs (`vle32/vse32/vle8/vse8/vmv.v.i` only); **legacy loadable image still bit-exact**. ELFs frozen at `reports/handover/elf_frozen_2026-09-08_0321_ul_v2/`.

---

### RLC AM uplink: receive/reassemble/deliver implemented, host-tested, wired into the build
- **Time:** 2026-09-08 ~03:10 +0200
- **Files:** `kernel/rlc_ul.h` (new, 152), `kernel/rlc_ul.c` (new, ~210), `kernel/rlc_ul_drv.c` (new, 259), `kernel/rlc_copy.h` (new, extracted), `kernel/rlc_am.c`, `kernel/rlc.c`, `kernel/rlc_plan.c`, `test/test_rlc_ul.c` (new), `test/test_rlc_plan.c`, `data/data_1_1350_100_p1c3.h` (new), `software/tests/CMakeLists.txt`
- **What.** The RLC kernel now has an uplink -- the receive side of the same AM entity (TS 38.322 5.2.2 / 5.3.2), structured as the mirror of the downlink:
  ```
  DL:  gather (serial pointer chase) -> plan (serial arithmetic) -> execute (parallel)
  UL:  scan   (serial header walk)   -> reassemble (parallel)     -> deliver (serial, in-order)
  ```
- **Why the scan is serial is structural, not an implementation choice.** An AMD header is 3 or 5 bytes depending on whether SO is present, and SO presence depends on SI, which is *inside* the header. PDU i+1's offset cannot be computed without parsing PDU i. That is the uplink's Amdahl fraction and is the quantity worth measuring -- the same role the gather plays on the downlink.
- **Concurrency design.** `recv[]` accumulates with `__atomic_fetch_add`; `total[]` is a plain store (one writer -- only the FULL/LAST segment knows the SDU length). **Completion is computed in the serial `rlc_ul_deliver()`, not raced in reassemble**: two cores folding the last two segments could each see a partial sum and neither would observe completion. Keeping the check in a phase that runs after a barrier means it sees settled state, and reassemble stays free of read-modify-write on shared control state.
- **MAC framing.** Each PDU carries a 2-byte big-endian length prefix. An AMD PDU has no length field of its own, so without it RLC cannot find PDU boundaries at all. TB<->UE is 1:1 (MAC has already demultiplexed) -- agreed with the GVSoC side as the right simplification, since spending UL budget rediscovering a map the protocol already fixes would model the wrong thing.
- **PROTOCOL BUG FOUND AND FIXED (downlink).** The UL test caught it: **the SN identifies the SDU, not the PDU.** Every segment of one SDU carries the same SN, with SO distinguishing them (6.2.2.4). Both DL planners were advancing SN per PDU including segments, so a continuation segment got a fresh SN and a conforming receiver saw an unfillable hole (observed as "512 segments fell outside the window", 6 of 500 SDUs delivered). Fixed in `rlc_plan.c`, both the reference and the scan planner:
  ```c
  out->sn_next = (in->sn_base + n - partial) & RLC_SN_MASK;
  ```
  `test_rlc_plan.c`'s expectation had encoded the same wrong assumption and was corrected. **This is the payoff for building the receive side: it is an independent check on the transmit side, and it disagreed.** Any DL ELF frozen before today has non-conforming transport blocks -- it does not change the DL throughput numbers (SN never gated assembly) but they are unusable for anything protocol-level.
- **Build integration.** `RLC_UL_MODE=1` routes `consumer()` to `rlc_ul_consumer()`; the driver is `#include`d into `rlc.c` after the role helpers. Slot = build+scan (consumer 0) / reassemble (all, disjoint slices) / deliver+STATUS (consumer 0), three phases separated by `snrt_cluster_partial_barrier()`, so a helper with nothing to do blocks rather than polls -- same structure and same reason as the DL TTI loop. Per-phase cycle counters added (`build`/`scan`/`reasm_max`/`reasm_sum`/`deliver`), with `build` reported separately so harness cost can be subtracted rather than silently counted as protocol work.
- **`rlc_memcpy8()` extracted** from `rlc_am.c` into `rlc_copy.h`: the uplink harness needs the same unaligned e8/m8 copy and neither direction owns it.
- **Four CMake targets** (`add_rlc_ul` macro): C1/C2/C3 consumer ladder with payload moved, plus a C3 headers-only control (`RLC_UL_EXEC=1`). Consumers are kept inside one tile (cores 0-3) -- the TB arena at `0xB080_0000` is above `l1d_addr` and therefore tile-private, so a cross-tile consumer set could not see it. Needed a new data header (`data_1_1350_100_p1c3.h`, P1/C3) since no existing header had a 3-consumer list at NUM_USERS=1.
- **Verification:**
  - `test_rlc_ul` (new): **16,109 checks / 0 failures**. Each TB is reassembled **twice** -- once as a single range, once split into N slices -- and compared with `memcmp`, so the parallel-safety claim is tested rather than asserted. 9 streams covering heavy segmentation, tiny TBs and mixed sizes; sliced runs at 4-, 8- and 16-way.
  - `test_rlc_plan`: **589,728 checks / 0 failures** after the SN fix.
  - Build clean for `config=cachepool_fpu_4g`, **zero warnings from any of the new files**.
  - **Both refactors proven codegen-neutral rather than assumed so.** Reverted each in place, rebuilt, compared loadable images (`llvm-objcopy -O binary`): the `rlc_memcpy8` extraction leaves the AM image **bit-identical** (md5 `6bb6cc84...`), and the `rlc.c` UL hooks leave the legacy image **bit-identical**. Restores re-verified against the post-change images.
  - **Disassembly audited for unimplemented vector ops** -- the standing hazard after the `vmsgtu.vx` incident. The four UL ELFs contain only `vle32.v`/`vse32.v`/`vle8.v`/`vse8.v`/`vmv.v.i`: loads, stores and a splat, all proven on hardware. No compares, no merges, no reductions.
- **Handover:** ELFs frozen immutable at `reports/handover/elf_frozen_2026-09-08_0308_ul/` with `MANIFEST.md5`; brief at `reports/handover/PROMPT_gvsoc_rlc_ul.md`. Sent to the `cachepool_gvsoc` session with both of their known model bugs flagged up front *and their signatures given*: C1 passing while C2/C3 under-count = their cross-core visibility bug (counters are `__atomic_fetch_add` shared state); `count` passing while `copy` fails = their cross-line truncation bug (the builds differ in nothing but whether payload is read).
- **Open:** GVSoC results pending. Multi-entity UL still uses entity 0 only; the phases already take the DL ownership map when we want it.

---

### RLC AM: wrap-up -- three validated fixes flipped ON; TTI loop replaces helper polling
- **Time:** 2026-09-08 ~03:10 +0200
- **Flipped three knobs from default-off to default-on**, all previously measured and all off only because they were gated mid-investigation:
  - `RLC_AM_WORKQ=1` -- bitmap work queue (scan-every-entity does not survive multi-entity)
  - `RLC_AM_ENT_PADDED=1` -- `rlc_am_entity_t` 124 -> **128 B**, removing false sharing on the `gen`/`claim`/`done` atomics (+4 B/entity)
  - `RLC_PLAN_PADDED=1` -- `rlc_plan_t` 7180 -> **7232 B**, so consumer-indexed pool entries stop straddling a shared line on the planner's hottest path (+52 B/entry)
  - Verified in the built artifact, not assumed: per-entity 128 B (%64=0), pool per-entry 7232 B (%64=0), 4 `amoor.w` present. Legacy loadable image re-checked against a freshly regenerated pristine build: **bit-exact**. Host planner test 589,728 / 0.
- **Implemented the TTI-structured consumer loop (F6) -- the fix for the dominant measured cost.** Plan / execute / commit now run as three phases separated by `snrt_cluster_partial_barrier()` over the consumer set, so **a helper with nothing to do blocks instead of sweeping the entity list**. This is what the RTL data demanded: a helper was doing **463 sweeps for a single grant**, and enabling the work queue did *not* rescue multi-entity, because cheapening a sweep does not stop polling.
  - Exit is by consensus: only consumer 0 evaluates the condition and publishes `rlc_am_stop`; everyone reads it after a barrier. A consumer exiting independently would hang the others in the next barrier.
  - `snrt_barrier_set_tile_mask()` is programmed once from core 0 during init, with `main.c`'s startup `snrt_cluster_hw_barrier()` as the resync point the API requires. The participant mask is computed per-core via `snrt_cluster_partial_barrier_mask()` -- O(n) once on entry, never in the loop.
  - **Semantic deviation recorded:** the plan pool is indexed by *consumer*, so an owner holds one open grant, making a TTI "one grant opportunity per **owner**" rather than per entity; entities are served round-robin. The agreed cross-engine metric is bytes/cycle and does not depend on the TTI definition, so only reporting granularity changes.
  - `RLC_TTI_CYCLES` (default 0 = unpaced) pads each TTI to the agreed scaled 5,000-cycle cadence when wanted. `RLC_AM_TTI=0` keeps the free-running loop for A/B.
  - Report now emits `ttis`, `payload_bytes` and the metric definition.
- **Verification:** build clean, zero warnings from the new files, all four barrier symbols present in the AM binary, legacy bit-exact, host planner test 589,728 / 0.

### CORRECTION (2026-09-08, from the user): the scalar-FP conclusion below is WRONG
- **The intended design is that Snitch OFFLOADS scalar FP and vector instructions to Spatz, and Spatz's FPU sequencer executes the scalar FP instructions.** So `-march=...f...` is correct, `misa` not advertising F is expected (Snitch does not implement F itself, it forwards), and there is no "toolchain promises an extension the hardware lacks" mismatch.
- **Therefore the 64 illegal-instruction traps are a genuine defect, not expected behaviour.** Something in the offload path -- the accelerator interface, the FPU sequencer enable, or the config knobs reaching the tile -- is not routing scalar FP to Spatz on `cachepool_fpu_4g`. That is a real bug to find, and the CI suite failing on it is a symptom, not a configuration mistake.
- **What survives from the entry below:** the observation (64 traps, count tracks `active_cores` exactly, `mstatus.FS` ruled out) and the corrected scalar-FP instruction filter. **What does not:** the diagnosis and the "fpu means vector only" conclusion. Re-open as an offload-path bug.
- Told the timing/GVSoC peers the old version; **must correct that with them.**

### (SUPERSEDED -- see correction above) Root cause of the scalar-FP failures: toolchain promises an extension the hardware lacks
- **Time:** 2026-09-08 ~03:25 +0200
- **`misa` reports no F extension.** `snRuntime/src/start.S:71` guards boot FP-register init on `csrr t0, misa; andi t0, t0, (1<<3)|(1<<5); beqz t0, 3f` -- the block is skipped, which is why booting never traps despite containing 64 `fcvt.s.w`. **So the scalar FPU is genuinely not built in `cachepool_fpu_4g`**; "fpu" in the config name denotes Spatz's *vector* FPU only.
- **The bug is a flags/hardware mismatch:** `software/cmake/toolchain-llvm.cmake` compiles everything with `-march=rv32imafvzfh_xdma_xfquarter`, which **includes `f`**, so the compiler emits `flw`/`fsw` into a core that does not implement them. It only surfaces in kernels whose hot loop uses scalar floats -- which is every kernel in the CI list and no kernel we run ourselves.
- **Also caught a false negative of my own before it cost a peer anything.** My first scalar-FP filter returned exactly **77 for five unrelated kernels**, including `bandwidth` and `byte-enable`, which had already *passed* on RTL with zero illegal instructions. Identical counts across unrelated binaries is not a plausible measurement, and it contradicted a known result. It was matching `fcvt.*` -- 64 from the misa-guarded boot init plus 13 in printf's `_ftoa`. Correct filter (FP loads/stores and FP arithmetic only) gives **0 for all five**; they are all runnable. I had been about to tell the timing session to drop three tests for no reason.

---

## 2026-08-25

### CRITICAL: the entire CI performance suite cannot run on the config CI uses
- **Time:** 2026-08-25 ~18:40 +0200
- **Ran the scalar-FP audit GVSoC suggested across `util/auto-benchmark/configs.sh`. It is not 2 of 5 -- it is 4 of 4:**
  ```
  fdotp-32b_M65536            109 scalar-FP instructions   CANNOT RUN
  gemv_M1024_N128_K32         101                          CANNOT RUN
  fmatmul-32b_M1024_N32_K32   162                          CANNOT RUN
  fft-32b_M1024_N16            93                          CANNOT RUN
  ```
  And `configs.sh` sets **`CONFIGS="cachepool_fpu_4g"`** -- the exact config they trap on. **Every kernel in the CI performance suite is unrunnable on the config CI runs it against.**
- **Likely root cause now visible:** `cachepool_fpu_4g.mk` sets `spatz_fpu_en ?= 1` and `spatz_num_fpu ?= 4`, which enable **Spatz's vector FPU**. There is **no knob in that config enabling the scalar Snitch FPU**. So "fpu" in the config name means *vector* FP, and scalar-FP kernels have presumably never run on it since the config was created. That reframes this from "a coverage hole in the suite" to "the suite's headline kernels and its target config have never been compatible".
- **Cross-check result, and the sign flips -- stronger than the parity we hoped for.** `byte-enable` last in-kernel trace stamp (`vsuxei16.v`): **RTL 289,468 vs GVSoC 252,494 = 0.87x, i.e. their model is 13 % FASTER.** Against `bandwidth` at 14.2x slow. **A uniformly-slow model cannot be 14.2x slow on one kernel and 13 % fast on another**, so the 14.2x is confined to the refill path -- consistent with all three of their candidates and excluding any global constant. Their L1/cache-pipeline modelling is in good shape; the 13 % optimism is a separate and much smaller question.
- **`RESULTS.md` updated** with the CI finding and the two-kernel comparison table.
- **Accepted GVSoC's reframing of my 90-minute waste:** the failure was **ordering, not attention**. Running the gate and the thing it gates in one command means the gate cannot gate anything -- it becomes a log line instead of a decision. Same structural error as the linker pad: build a check, then arrange for it to be unable to fail. Fix: a gate runs in a separate step whose output is read before the gated step is launched.
- Not re-running `cache-line-rw-smoke` -- a second point on the same side of the split is not worth an RTL hour against the scalar-FP root cause.

---

### 64-core reference batch complete -- 2 of 5 usable; results in reports/rtl_reference_2026-08-25/RESULTS.md
- **Time:** 2026-08-25 ~18:15 +0200
  ```
  bandwidth                  PASS      EOC 33,876 cyc | 2,058 kernel | 32 cyc/load | AR 335 | 128 SB PASS
  byte-enable                PASS      EOC 303,288    | 128 SB PASS, every sub-test [PASS]
  fmatmul-32b_M1024_N64_K64  TRAP      64 illegal instr (scalar FP)
  fdotp-32b_M32768           TRAP      64 illegal instr (scalar FP)
  cache-line-rw-smoke        TIMEOUT   no EOC, no traps -- just slow
  ```
- **`fdotp` traps too**, so the joint `Calc ~= 209.38` prediction is **untestable on RTL**. The `measure_iter` source analysis stands, but neither engine can now confirm it by execution -- GVSoC's is the only one that runs the kernel at all, which is an odd position for a correctness question.
- **Process failure, mine, cost 90 minutes of RTL.** I ran the scalar-FP pre-check and launched the batch in the *same command*, so `fdotp-32b_M32768 flw=11 fsw=7 fadd/fmul=7 -> WILL TRAP` printed **as the run started**. I had the answer before it began and did not act on it; fdotp then burned the full cap reaching exactly the predicted outcome. **Computing a prediction and not using it to change what you run is worse than not computing it** -- the pre-check existed precisely to avoid this and I ignored it in the same breath as building it.
- **Deliverable written:** `reports/rtl_reference_2026-08-25/RESULTS.md` -- per-kernel results, the non-uniform `l1d_part` warning (all-private vs all-shared are separate calibrations, not poolable), the scalar-FP analysis, and the GVSoC comparison with the >= 7.5 concurrency target.
- **What GVSoC actually gets is thinner than planned:** `bandwidth` (the memory-bound headline, and the one that exposed their MLP-of-1) plus **one** all-shared L1-resident cross-check in `byte-enable`, rather than the pair. **No compute-bound kernel at all**, since both candidates use scalar FP.
- **The scalar-FP hole is a bigger outcome than any cycle number.** Two kernels referenced by our own CI list cannot execute on our hardware, and it took an external calibration request to notice -- because every workload we run ourselves happens to use vector FP or integer. That is a **coverage hole in the test suite**, not just a bug.

---

### MAJOR: scalar floating-point does not execute on CachePool RTL -- `fmatmul` unrunnable at any size
- **Time:** 2026-08-25 ~17:25 +0200
- **Confirmed by trap-count scaling, which rules out size, boundary and race explanations:**
  ```
  fmatmul M1024_N64_K64 -> 64 illegal instructions   (active_cores = min(64, 1024/4) = 64)
  fmatmul M32_N32_K32   ->  8 illegal instructions   (active_cores = min(64,   32/4) =  8)
  ```
  **The trap count tracks `active_cores` exactly.** Every core that executes the fmatmul kernel traps on the first scalar FP instruction it reaches (`flw ft3, 0(a7)` at `t0 = *a__;`), then sits in snRuntime's unhandled-exception `while(1)`.
- **Why it has never been seen:** the passing workloads contain **zero** scalar FP. `bandwidth`, the RLC payload check and the legacy TC1 baseline all report `flw=0 fsw=0 fadd/fmul=0`; they use *vector* FP (`vle32`/`vse32`) or integer only. `fmatmul` is the first workload run here that issues scalar FP, and it fails immediately.
- **`mstatus.FS` ruled out as the cause -- both sides' hypothesis, killed with the RTL source.** `snitch.sv:2829-2835` computes FS on *read* rather than storing it: `if (FP_EN) begin mstatus.fs = XDirty; mstatus.sd = 1'b1; end`. So FS is **always Dirty when FP_EN** and there is no state software could leave Off. My "nothing sets FS" observation was true (the bootrom sets only `mtvec` and `mie`) and **irrelevant**, because nothing needs to. GVSoC had independently confirmed their ISS *does* implement the FS trap and it is compiled in for this target, which is what made the hypothesis testable at all.
- **Remaining suspect: `FP_EN` is false in this build.** `cachepool_cc.sv:136` is `localparam bit FPEn = RVF | RVD | XF16 | XF8` with `RVF = 1` as a *default parameter*, but `cachepool_tile.sv:1484` passes `.RVF(RVF)` from above, and `RVF` is not defined in `cachepool_pkg.sv`, `cachepool_cluster.sv` or `cachepool_group.sv` -- so it comes from the generator or `VLOG_DEFS`. Unresolved; next thing to chase.
- **This is a real bug on our side, surfaced by GVSoC's calibration request** -- the same shape as `vmsgtu.vx`, in the same direction. **`fmatmul-32b_M1024_N32_K32` is in our CI kernel list** (`util/auto-benchmark/configs.sh`), so either CI runs a config where scalar FP works, or CI has been failing on it. Config name `cachepool_fpu_4g` implies FP support that the build does not deliver.
- **Consequence for GVSoC:** their `fmatmul_M1024_N64_K64` numbers (86,610 / 69,084) are **for a program that cannot run on this target** and should be deleted rather than caveated. They correctly redirected to `byte-enable` and `cache-line-rw-smoke` -- both all-shared and L1-resident -- as a cheaper substitute for the "does the non-refill path agree" cross-check. Their scalar-FP content was verified *before* running them rather than after.

---

### `fmatmul-32b_M1024_N64_K64` does not run on RTL -- all 64 cores trap on a scalar `flw`
- **Time:** 2026-08-25 ~17:05 +0200
- **Hard failure, not slowness.** 64 x `[Illegal Instruction Core N] PC: 80000778 Data: 0008a187` -- exactly one per core -- then core 0's sim time frozen at 37,164,000 ps for 45 s with the count static, zero UART, no EOC. Every core takes the trap once and sits in snRuntime's unhandled-exception `while(1)`. Killed rather than letting it burn the 90 min cap.
- **Decoded:** `0x0008a187` = **`flw ft3, 0(a7)`**, a scalar 32-bit float load, at source line `t0 = *a__;` in the fmatmul inner loop (`80000770 vle32.v` / `80000774 add` / `80000778 flw`).
- **Two things make it odd rather than a plain config mismatch:**
  1. The generated config says `isa: "rv32imafd"` -- **F is enabled**, so `flw` should be legal. First suspicion is `mstatus.FS` being Off, which makes every FP instruction illegal regardless of the ISA string.
  2. **No previously-passing run printed a single illegal instruction** -- `bandwidth`, the RLC payload check and the legacy TC1 baseline are all zero. Those use *vector* FP (`vle32`/`vse32`) and integer code; fmatmul is the first workload run here that issues **scalar** FP loads. Consistent with the scalar FPU being absent and the FPU sequencer offloading vector-but-not-scalar FP, but unconfirmed.
- **Another RTL-vs-model divergence, in the OPPOSITE direction to `vmsgtu.vx`.** GVSoC ran this same kernel and produced 86,610 / 69,084 cycles, so **their model executes `flw` where the RTL rejects it**. With `vmsgtu.vx` their simulator was stricter than hardware and caught a real kernel bug; here it is more permissive and would let through a kernel that cannot run. A model that accepts instructions the target rejects produces numbers for programs that do not exist.
- **`M1024_N64_K64` is not a CI-validated shape** -- `util/auto-benchmark/configs.sh` lists `fmatmul-32b_M1024_N32_K32`. Both variants contain `flw`, so the CI shape is not expected to fare better; probing rather than assuming.
- **Now running:** `fmatmul-32b_M32_N32_K32` as a cheap probe (smallest shape -- if it also traps, scalar FP is broken on this config generally and **no fmatmul number is available from RTL**), then `fdotp-32b_M32768` with the joint `Calc ~= 209.38` prediction, then `byte-enable` and `cache-line-rw-smoke`.
- **Consequence for the calibration:** `bandwidth` stands and was carrying most of the value, being the memory-bound one. But the L1-resident cross-check may be unavailable, which weakens the test of the MLP diagnosis -- GVSoC has been told to plan for that.

---

### The 14.2x is at least two mechanisms, not one -- and our 4-channel HBM2 is the second
- **Time:** 2026-08-25 ~16:50 +0200
- **GVSoC corrected their own "found it" claim.** Their backing store is `_MEM_LATENCY = 50`, so MLP=1 predicts ~65 cycles/load against 455 observed -- **MLP-of-1 accounts for roughly half the gap in log terms, leaving ~7x unexplained.** Their remaining candidates: the 17->1 group refill mux (1 request/cycle) and a **single shared `memory.Memory` behind all channels**.
- **Our config identifies the second candidate as the live one.** From `config/cachepool_fpu_4g.mk`: `dram_type = HBM2`, **`l2_channel = 4`**, `l2_bank_width = 512`, `l2_interleave = 16`. Confirmed in the transcript itself -- the bandwidth run instantiates **four distinct `DRAMSysRecordable0..3` controllers**, each reporting independent timing. Against their single shared memory that is a **4x serialisation on its own**, compounding with MLP=1.
- **Two further gaps, both understating their throughput:** (a) HBM2 is not a fixed-latency device -- DRAMSys models bank groups, row buffers and bank-level parallelism *inside* each channel, so a flat 50-cycle constant cannot reproduce it even with the channel count fixed; (b) `l2_interleave = 16` at 512-bit granularity spreads consecutive lines across all four channels by construction, which is exactly the pattern `bandwidth` generates -- close to the best case for channel parallelism and close to the worst case for a single-memory model. Recommended they check the channel count *before* the mux: it is a configuration fact rather than a mechanism to trace.
- **Owned my half of the error that misled them.** I offered "uniform ratio suggests a single constant" and they read it as confirmation of the MLP find. **That inference is simply wrong** -- independent multiplicative mechanisms also produce a clean ratio, so uniformity never discriminated between one cause and several. A plausible-sounding heuristic that does no work, offered as if it were evidence.
- **The AR-transaction bound is unaffected and stands:** 335 transactions in 2,241 cycles gives effective concurrency **>= 7.5 at L=50**, as a lower bound, independent of which mechanisms sum to the gap. If channels and MLP are both fixed and 32 cycles/load is still unreachable against 335 round trips, there is a third mechanism.
- **They recorded two of our points as requirements rather than notes:** re-running the correctness suite when the MLP gate is lifted (new interleavings have never executed), and that their mesh is **untested rather than validated** -- today's mesh A/B deltas (+4.4 %, +7.7 %) were measured through a path serialising to one miss at a time.

---

### Root cause of the 14.2x bandwidth gap: GVSoC's cache model has memory-level parallelism of ONE
- **Time:** 2026-08-25 ~16:35 +0200
- **GVSoC found it, from the RTL number we supplied.** `insitu_cache_core.cpp:1098` gates refill issue on `!refill_pending_`, so **each cache controller allows exactly one outstanding refill** -- a second miss cannot issue until the first returns and installs. The synchronous path does the same explicitly (`sync_refill_busy_until_`). That constant was calibrated against the standalone `insitu_cache_calib` testbench, whose responder is deliberately serialising by construction, and was carried into the full 64-core system unchanged.
- **They verified their own provenance before reporting** (two independent 64-core runs, byte-identical 29,122 / 455), which is what makes the 14.2x actionable rather than another retraction.
- **Confirmed the config values they cited, from our tree:** `config/cachepool_fpu_4g.mk:85` `spatz_max_trans ?= 32`, `:88` `snitch_max_trans ?= 16`. So 32 outstanding Spatz transactions per core against their **one** per controller.
- **Supplied a measured calibration target rather than an inferred one.** The RTL bandwidth run did **335 AR transactions in 2,241 kernel cycles**, so serialised refills at latency L would need 335*L:
  ```
  L= 50 -> 16,750 cyc vs 2,241 observed -> effective concurrency >=  7.5
  L= 80 -> 26,800                       ->                        >= 12.0
  L=100 -> 33,500                       ->                        >= 14.9
  ```
  Lower bounds (they assume zero hit time and no other overlap). Independently confirms the mechanism: **no MLP-of-1 model can produce 32 cycles/load when the workload takes 335 DRAM round trips**, however the mesh is tuned.
- **Second-order point worth recording:** with MLP capped at 1 there is at most one line in flight per controller, so **their mesh has never carried concurrent traffic** -- no contention, no arbitration pressure, no queueing. Their mesh work is therefore neither validated nor invalidated by anything either side has run; it is *untested*. "The mesh looked fine" and "nothing ever loaded the mesh" are easy to conflate and lead to opposite conclusions.
- **Pushed back on one framing:** they called it a calibration fix rather than a correctness one. True for cycle counts, but MLP=1 also **serialises refill ordering**, hiding reordering and MSHR-merge bugs that only appear with multiple lines in flight. Lifting the gate should be followed by the correctness suite, not just the timing ones -- the newly-possible interleavings have never executed on their model.
- **Consistency check on the diagnosis:** their RLC calibration landed at +14.8 % while this lands at +1320 %. RLC is L1-resident after warm-up and latency-bound; bandwidth is throughput-bound. The two differing by roughly that much is what the MLP explanation predicts.
- **This validates moving the batch ahead of our own queue.** The defect was invisible to every other workload we ran -- RLC is latency-bound, fmatmul is L1-resident, and the rest are too small to saturate.

---

### 64-core RTL reference: `bandwidth` -- 14.2x gap against GVSoC on their #1 calibration kernel
- **Time:** 2026-08-25 ~16:20 +0200
- **`bandwidth` on `cachepool_fpu_4g` (64 cores, `l1d_part(4)` = ALL PRIVATE): clean.**
  ```
  ----- random-load bw: 64 iters x 64 elems -----
  Total cycles: 2058, avg per load: 32
  Performance: 1990 elems/1000cyc (31%o utilization)
  Total Kernel Cycles 2241 | AR 335 | R 422
  [EOC] retval = 0 ; scoreboards 128 PASS / 0 FAIL
  ```
- **Against GVSoC's 29,122 total / 455 cycles-per-load: 14.2x on both metrics, identical to a tenth.** A uniform scaling rather than a shape difference, which points at a per-access latency or throughput **constant** being wrong rather than the mesh topology -- the easier kind to fix, and exactly what the batch existed to find.
- **Flagged a caveat before they calibrate on it:** `bandwidth/main.c:40` is `snrt_cluster_core_num()` and lines 121-126 stride the offset array by `num_cores`, so **`bandwidth` is in the same baked-count class they just retracted**. If their 29,122 was measured at fewer than 64 cores, part of the 14.2x is bookkeeping rather than their mesh. They confirmed 64 active cores for `fmatmul_M1024` but did **not** say so for `bandwidth`, so this is asked rather than assumed.
- Useful property of this particular target: being **all-private**, it exercises tile-local banks and largely sits outside the cross-core shared-data class their visibility bug corrupts -- a cleaner calibration anchor than most of what has been in dispute.
- `fmatmul-32b_M1024_N64_K64` started 09:38 (the other headline); fdotp follows, with the joint `Calc ~= 209.38` prediction on the line.

---

### GVSoC retracted its density figures (config mismatch) -- RLC results verified unaffected
- **Time:** 2026-08-25 ~16:05 +0200
- **Their retraction:** `snrt_cluster_core_num()` is **baked into the ELF** from the build config, and every CachePoolTests binary is built for `cachepool_fpu_4g` = 64 cores. Running those binaries at 4/8/16 cores left the *software* believing it had 64. `cache-basic` partitions by `lines_per_core = ceil(256/num_cores)`, so only 4N of 256 lines were ever checked while they divided errors by the full 8192. Corrected densities are **48 %, 69 %, 84 %, 47 %** -- not 3/8.6/21/47.5. **There was never a low-density corner**, so the "clean corner" technique, the standing rule they committed, and my probability model all rested on a curve that does not exist. (My model had already died on their M8-at-95 % evidence, but of the wrong cause.)
- **Checked what this does to the RLC results: nothing, and here is the mechanism.** The RLC kernel **never calls `snrt_cluster_core_num()`** -- grepped `main.c` and every kernel file; the only topology calls are `snrt_cluster_core_idx()` and `snrt_cluster_core_per_tile()`. **Dispatch is entirely by the data header's explicit core-id lists** (producers `{0,1}`, consumers `{2,3}`), which are literal constants in the binary rather than derived from a core count. So a 64-core RLC binary on a 4-core model misallocates nothing: cores 0-3 take their assigned roles and cores 4-63 were never assigned any. Structurally different from `cache-basic` and `fdotp`, both of which *partition* by the baked count and silently under-cover.
  - **Therefore still valid:** the entity ladder and its non-monotonicity, the M8-vs-M48 contrast, both layout arms, and the M48 density sweep.
  - Their runs completing also proves `snrt_cluster_hw_barrier()` does not consult the baked count -- a 64-core software expectation on a 4-core machine would have hung.
- **fdotp now has TWO stacked defects**, which is why it looked like "fails everywhere": (a) our `measure_iter` check bug, and (b) their config mismatch, since `elem_jump_per_round = elem_per_round * num_cores` makes a 64-core binary cover only N/64 on N cores. Their 16-core point (25 % predicted vs 26 % observed) settles (b). Only their 64-core residue (77 % of one iteration) remains unexplained.
- **Audited our own exposure to the same class: clean.** Every RTL run this session used `cachepool_fpu_4g` binaries on the `cachepool_fpu_4g` RTL build. Honestly recorded as luck rather than diligence -- we never varied core count, so never had the opportunity to make the same mistake.
- **Generalisation worth keeping:** *a value that should change with the configuration and doesn't is only visible if something checks it.* Their tell (`lmul:8, elem:128, offs:8192, iter:4`, identical at every core count) was printed on every run for hours. Our equivalent was building two binaries whose entire purpose was to differ and not verifying that they did.

---

### BUG in our test suite: `fdotp-32b`'s data check is unpassable by construction
- **Time:** 2026-08-25 ~15:50 +0200
- **`software/tests/fdotp-32b/main.c` can never pass its own check.** The GVSoC side predicted this from the source; I verified it independently, reading the whole loop rather than the two lines quoted, to rule out a hidden accumulation in the reduction:
  ```c
  for (iter = 0; iter < measure_iter; iter++) {   // measure_iter = 3
    float acc;                                    // fresh each iteration
    acc = fdotp_v32b_lmulN(...);                  // assigned, not +=
    result[cid] = acc;
    if (cid % 4 == 0) { for i: acc += result[cid+i]; result[cid] = acc; }  // level 1
    if (cid == 0)     { for g: acc += result[g];     result[0]   = acc; }  // level 2
  }                                                // loop closes here
  if (cid == 0) fp_check(result[0], dotp_result * measure_iter);           // line 185
  ```
  Both reduction levels use the **fresh per-iteration `acc`** and the loop closes immediately after, so `result[0]` holds **one** iteration's dot product while the check expects `209.38 x 3 = 628.15`. **A correct machine fails.**
- **The intent is unambiguous from `timer = (timer < timer_tmp) ? timer : timer_tmp`:** `measure_iter` exists to take the *best of three timings*, not to accumulate three results. The expectation should be `dotp_result`, unmultiplied -- a one-line fix.
- **Deliberately NOT fixed yet:** `fdotp-32b_M32768` is queued in the running reference batch, and changing its binary mid-flight is precisely the provenance mistake that destroyed the GVSoC TC2 run. Fix lands after the batch.
- **Consequence for the calibration:** fdotp's **cycle numbers remain valid** (the arithmetic performed is unaffected by a wrong final comparison); its **data check is worthless to both engines** until fixed.
- **Narrowed their residual failure for them.** Against the correct single-iteration 209.38 they see 19 % at 4 cores and 77 % at 64. At 4 cores `red_group == num_cores`, so **level 2 never executes** and core 0's answer is just its own partial plus three cross-core reads of `result[1..3]`; with 4 cores each partial is ~25 % of the total, and they measured 19 %. So the profile fits **cross-core reads of `result[]` failing** -- their known class -- with the *reduction tree shape* making the impact non-monotonic in core count rather than the corruption rate being non-monotonic. That is why it looked backwards to them. Suggested test: at 4 cores print `result[0..3]` immediately before level 1.

---

### RLC AM: work queue does NOT rescue multi-entity; helper polling is the real flaw. Reference batch running.
- **Time:** 2026-08-25 ~15:35 +0200
- **`M8_N1350_K8` timed out at 60 min WITH the work queue enabled** (`RLC_AM_WORKQ=1`, 8 entities, 8 packets). So the bitmap queue does **not** make multi-entity feasible on RTL. Reducing per-sweep cost is insufficient: **helpers still spin between grants**, and polling that scales with core count is the actual problem. The passing K4 run measured one helper doing **463 sweeps for a single grant**.
  - Consequence: **RTL cannot answer the multi-entity question at any size** with the current design. The `M16`-vs-`M32` ladder pair was never going to be runnable.
  - This is an architectural flaw found empirically, and it promotes "helpers must wait, not poll" **above** the TTI loop on the kernel list. Note the two are the same work: the TTI is what gives a helper something to wait *on*.
  - `M1_N1350_K4_G1024` (segmentation) also timed out -- G1024 turns 4 SDUs into 8 grants, ~8x the per-grant work of the passing G8192 run. **Segmentation remains untested on hardware**; it needs G2048 or 2 packets.
- **Reference batch escalated by the GVSoC side's user and now running**, ahead of everything: their model has no full-occupancy anchor at all, and the batch has been queued behind correctness work five times -- each decision defensible, the cumulative effect being that the number does not exist.
- **They caught a real error in my batch list.** `fmatmul-32b/main.c:82` is `active_cores = snrt_min(num_cores, gemm_l.M / kernel_size)`, so **M=64 caps at 16 active cores** and only **M=1024** reaches 64. My queued `fmatmul-32b_M64_N64_K64` would have handed them a 16-core number labelled 64-core, and they would have calibrated a full-occupancy mesh against it. Now running `fmatmul-32b_M1024_N64_K64`.
- **`l1d_part` modes sent with the batch, and they are NOT uniform** -- `bandwidth` and `fmatmul-32b` run **all-private** (`l1d_part(4)` / `l1d_part(num_cores_per_tile)`), while `fdotp-32b`, `byte-enable` and `cache-line-rw-smoke` set no partition and therefore run the reset default of **all-shared** (`L1D_PRIVATE=0`). Different interconnect paths; not poolable.
- **Also agreed to report a free diagnostic:** whether `fdotp-32b_M32768` passes its data check on RTL. It fails on their engine at every core count (calc 40.32 / 54.58 / 160.51 vs expected 628.15) with XLINE=0, and the trend runs *opposite* to their visibility bug's density curve -- so it is a third unexplained failure. RTL either exonerates the workload or hands them their cheapest lead.

---

### RLC AM: the O(N) sweep makes multi-entity RTL infeasible -- F5 is an enabler, not an optimisation
- **Time:** 2026-08-25 ~15:25 +0200
- **`M8_N1350_K8` also timed out** (rc=124, 60 min) despite my ~21 min extrapolation. **The extrapolation was wrong because RTL cost is not linear in packets -- it scales as packets x entities:**
  ```
  K4 / M1 :  4 pkts x  1 entity  =  4 units -> 10.3 min
  K8 / M8 :  8 pkts x  8 entities = 64 units -> >60 min (capped)
  ```
- **Cause, and it is a real design cost rather than a simulation artefact:** `rlc_am_step()` sweeps **every** entity per call and helpers spin between grants. The passing K4 run measured **consumer 1 doing 463 sweeps over 1 entity** -- at N entities that becomes 463 x N entity-visits of pure polling. At 48 entities the sweep is 48x longer, so multi-entity RTL is simply not reachable on the non-wq path.
- **This reframes F5.** The bitmap work queue was built as a scaling optimisation and defaulted OFF pending validation; it is in fact **the enabler for multi-entity operation at all**. A design whose idle-polling cost scales with the entity count cannot reach TC2's 48, let alone TC3's 4800, on any engine.
- **Built `_wqchk` variants** (`M8`/`M48` at K8 with `RLC_AM_WORKQ=1`, self-check on) -- bitmap atomics confirmed present in the artifact (4 `amoor.w`, 2 `amoand.w`). The wq path skips idle entities entirely, so cost should track *active* entities rather than total.
- **Queue reordered to put the cheap certain result first:** `M1_N1350_K4_G1024` (segmentation -- 1 entity, 4 packets, known-runnable size) -> `M8_K8_wq` -> `M48_K8_wq` -> reference batch. Segmentation is the one untested correctness path and it is affordable; the entity question is now gated on whether the work queue makes it affordable at all.
- Simulator hygiene after stopping the chain: 0 cachepool vsim, 8 TeraNoC vsim untouched.

---

### RLC AM: RTL multi-entity runs re-sized after M8 hit the wall
- **Time:** 2026-08-25 ~14:45 +0200
- **`M8_N1350_K24` timed out on RTL** (rc=124, 60 min cap, only the two consumer-entry lines). Not a bug -- a sizing error of mine. K4 (4 packets) took 10.3 min, so 24 packets extrapolates to **~62 min against a 60 min cap**. `M48_K24` was queued behind it and would have burned another hour answering nothing, so I stopped the chain.
- **Re-sized to 8 packets (~21 min extrapolated) and generated `data_8_1350_8.h` / `data_48_1350_8.h`.** Entity count stays the variable, matching the GVSoC ladder's axis, at a workload RTL can actually finish. The K24 rungs are simply not runnable here.
- **Gated the `rlc_plan_t` padding behind `RLC_PLAN_PADDED` (default 0) before rebuilding.** I had applied it unconditionally, which would have put an *uncontrolled* change into every RTL binary -- so a pass could not have been attributed between "hardware is coherent" and "the padding fixed it". Verified on the artifact that the default build still has the 7180 B / %64=12 plan entry, i.e. **byte-comparable code to GVSoC's ladder**. Host planner test after gating: 589,728 / 0.
  - Both padding fixes now sit behind knobs (`RLC_AM_ENT_PADDED`, `RLC_PLAN_PADDED`), both default off, both landing together with their own measurement once the entity question resolves.
- **Queue:** `M8_K8` -> `M48_K8` (the paired entity experiment: M8 passing and M48 failing on RTL would mean the wedge is real on hardware; both passing points at the GVSoC engine) -> `M1_N1350_K4_G1024` (segmentation, the path the passing payload check never exercised) -> the reference batch.
- **Simulator hygiene re-verified after stopping the chain:** 0 cachepool vsim, **8 TeraNoC vsim still running and untouched**.

---

### RLC AM: cache-line hygiene audit -- second, worse false-sharing defect found
- **Time:** 2026-08-25 ~14:20 +0200
- Audited every AM static for element/line alignment by reading symbol sizes out of a built ELF rather than trusting the `aligned()` attributes (which align the array *start*, not the element stride):
  ```
  rlc_am_ent        per-elem  124 B   % 64 = 60   <- elements share lines
  rlc_am_plan_pool  per-elem 7180 B   % 64 = 12   <- elements share lines
  rlc_ctx           per-elem  448 B   % 64 =  0   ok (7 x 64)
  ```
- **`rlc_am_plan_pool` is the worse of the two and was not previously known.** Pool entries are indexed by **consumer**, so `pool[0]` and `pool[1]` are written by *different cores*, and the planner writes essentially the whole 7 KB buffer per grant (three prefix sums plus every SoA field). A 12-byte overhang puts two cores in a write-write ping-pong on the boundary line, on the hottest path in the planner.
- **Fixed in source:** `rlc_plan_t` gets `__attribute__((aligned(64)))` -> 7180 -> 7232 B, +52 B per entry, **+104 B of `.data` total**. Spelled 64 rather than `CACHE_LINE_SIZE` because `rlc_plan.h` is also compiled by the host unit test, which does not include `rlc.h`. Host planner test re-run after the change: **589,728 checks / 0 failures**.
- **Both padding fixes (`rlc_am_entity_t` -> 128 B, `rlc_plan_t` -> 7232 B) are staged in source and deliberately NOT BUILT.** Building would change every AM binary and break comparability with the three frozen sets the GVSoC side is still running against -- the same provenance mistake that cost us their TC2 result. They land together, as one standalone change with its own before/after measurement, once the M32 mirror resolves.
- Generalisation worth keeping: **`__attribute__((aligned(N)))` on an array aligns the array, not the elements.** For any array whose elements are touched by different cores, the *struct type* needs the alignment so `sizeof` becomes a multiple of the line. Both defects here were exactly this mistake, and both were invisible in the source -- only the symbol sizes showed them.

---

### RLC AM: **RTL PAYLOAD CHECK PASSES** -- first non-vacuous PASS anywhere; copy is correct on hardware
- **Time:** 2026-08-25 ~14:00 +0200
- **`M1_N1350_K4_P2_C2_am_G8192_tbchk` on RTL, 64 cores, 10 min wall: PASS.**
  ```
  [AM] entities=1 grants=1 pdus=4 segments=0 polls=1
  [AM] u0: plan_calls=1 peek_max=4 plan_ok=1 poison=1 published=1 grants=1
           tosend=0 sent=4 so_next=0 gen=2
  [AM] consumer 0: steps=17  completed_sweeps=17
  [AM] consumer 1: steps=463 completed_sweeps=463
  [AM] zero-vl vsetvli events: 0
  [AM] transport-block check: 1 grants, 0 mismatches -> PASS
  [EOC] Simulation ended at 172384000 (retval = 0);  Total Kernel Cycles: 152301
  ```
- **What this establishes on hardware, end to end:** the transport-block check decoded a real 4-PDU grant and verified header fields, TB offsets, SN continuity, segment-offset continuity **and byte-exact payload** -- zero mismatches, `tosend=0`, `sent=4`, queue fully drained.
  - **`rlc_memcpy8` is correct.** The unaligned `e8/m8` base -- suspicion #1 from the original GVSoC handover, and the question their model could not adjudicate because its truncation masked a correct VLSU and a broken one identically -- **works on Spatz**. GVSoC's `verify_mask=0x80` payload failures were their cross-line truncation in full; they called that correctly before the evidence existed.
  - Also cleared on hardware: the vectorised planner (maps+scan, no compares), publish/claim/execute, commit and retirement, and the sweep loop -- `completed_sweeps` 17 and 463 means sweeps complete and `rlc_am_idle()` terminates properly.
- **Honest limitation I did not notice when sizing the test: `segments=0`.** Four 1360-byte SDUs fit inside one 8192-byte grant, so **the segmentation path was never exercised** -- SI=FIRST/MIDDLE/LAST, the SO field, the partial-SDU cursor and cross-grant `so_next` chaining are all still untested on hardware. Sizing the workload for speed also sized segmentation out of the experiment. Next RTL target: **K4 at G1024**, which forces every SDU to split and puts `so_next` chaining under test.
- **Queue:** M8 running (05:19), M48 behind it, both parked on GVSoC's M32 mirror result -- if it says layout, both get dropped in favour of the segmentation target, which is now the better use of the hour.
- **The division of labour is validated by two results neither side could reach alone:** GVSoC's engine found `vmsgtu.vx` (a silent-wrong-answer kernel bug on our hardware, invisible to the host test which compiles the C twins, and invisible to RTL which would have executed it to a wrong result without complaint); RTL answered the payload question their engine structurally could not.

---

### RLC AM: layout AND false-sharing hypotheses both dead; mirror arm built
- **Time:** 2026-08-25 ~13:55 +0200
- **Three-way M16 discriminator: ALL THREE FAIL.** `pad0`, `padshift` (rlc_am_ent moved 0x180, rlc_ctx moved 0x40) and `entpad` (stride 124 -> 128, start unchanged) all give `grants=0, XLINE=0`. The runtime `[AM] layout:` self-report confirms the variants genuinely differ. **So moving every address does not rescue M16, and eliminating the entity cache-line collision does not either** -- GVSoC's layout hypothesis and my false-sharing hypothesis die together. They proposed the test that went against them and said so plainly.
- **Also checked the last variable neither of us had examined -- the package distribution -- and it is not the answer.** `ACTIVE_USER_NUMBER` changes the generator's RNG stream, so each rung distributes its 24 packages differently. Extracted the descriptor histograms: even/odd (consumer 0 / consumer 1) splits are 11/13, 11/13, 14/10, 16/8, 14/10, 12/12 for N = 8..48, and distinct entities are 8, 12, 14, 16, 19, 20. **Both parities always have packages, so no rung starves an owner**, and nothing separates pass (8, 12, 32) from fail (16, 24, 48).
- **Mirror arm built and frozen** at `reports/handover/elf_frozen_2026-08-25_0540_m32mirror/`: M32 baseline (byte-identical to the ladder rung already run), `M32_padshift`, `M32_entpad`. GVSoC's point, which I should have seen when building the first arm: **"a failure that survives perturbation" and "a success that survives perturbation" are different claims**, and only the second tests what the layout hypothesis actually asserted -- that M32's *success* is a lucky layout. M32 passing under both -> layout inert and entity count is real; M32 failing under either -> success is layout-contingent and the whole ladder reverts to their bug.
- **RTL queue held** as they suggested: K4 payload check runs to completion (independent question); M48 and the `pad0`-vs-`entpad` pair stay parked until the mirror resolves, since if it says layout then RTL on any M16 variant is wasted.
- **The 124-byte entity fix is deliberately NOT landed yet.** It is a genuine false-sharing defect and `entpad` is the right fix on its own merits, but flipping the default mid-investigation would change every binary and break comparability with three frozen sets -- the same mistake that destroyed the TC2 run's provenance. It goes in as a standalone change with its own before/after measurement once the mirror resolves.
- **Habit worth naming from the linker catch:** not "check the symbol table" but **"verify the manipulated variable actually moved before trusting any result that depends on it"**. I built two binaries whose entire purpose was to differ and did not initially confirm that they did.

---

### RLC AM: ladder is non-monotonic -> layout, not entity count; found real false sharing on rlc_am_ent
- **Time:** 2026-08-25 ~13:30 +0200
- **Entity ladder result (GVSoC, frozen set, 4 cores):** grants = **4, 5, 0, 0, 3, 0** for M = 8, 12, 16, 24, 32, 48. **Non-monotonic** -- works at 8/12/32, fails at 16/24/48. Not a threshold, not accumulation, **not ordered in entity count at all**. `XLINE` tracks grants exactly (63, 63, 0, 0, 60, 0), so the pattern is corroborated through the independent channel.
- **My consumer-entry branch is retired:** the `[AM] core 2/3: consumer idx=` lines are present in every rung including all four M48 density configs. The consumers ran everywhere.
- **GVSoC withdrew "entity count is everything" (their phrase) and I accept the correction.** What actually varies across the ladder is `ACTIVE_USER_NUMBER` and therefore the **`.data` layout** -- every rung places `rlc_ctx[]`, `rlc_am_ent[]` and the list heads at different addresses. A deterministic *address-sensitive* corruption evaluated at six layouts yields exactly this: arbitrary pass/fail with no rule in the nominal parameter. It also retro-weakens the flat density line, which held layout fixed and varied cores.
- **Building their experiment turned up a real defect that is MINE: `rlc_am_entity_t` is 124 B on rv32, not a multiple of 64.** `aligned(CACHE_LINE_SIZE)` on the array only aligns the start, so adjacent entities are packed at 124 B and **share cache lines** -- and that struct holds `gen`/`claim`/`done`, the atomics every executing core hammers. Neighbouring owners ping-pong the same line, and which entities collide is a function of the index (entity u starts at 124u). Genuine defect, worth fixing regardless of this investigation. (Checked `rlc_context_t` expecting the same: it is exactly 448 B = 7x64, no sharing. That suspicion was wrong.)
- **Three-way discriminator frozen** at `reports/handover/elf_frozen_2026-08-25_0525_layout/`, all M16 (a failing rung), 4 cores: `pad0` (baseline), `padshift` (+320 B ahead of the array -- addresses move, structures identical), `entpad` (entity padded to 128 B -- same start address, no false sharing). padshift passes -> pure layout, not the kernel; entpad passes -> false sharing, my bug; both fail -> neither.
- **Caught a build error that would have produced a null experiment:** the first `padshift` used a separate `static volatile char pad[]` before the array and **the linker placed it after** `rlc_am_ent` -- both binaries came out with the array at the identical address. Without checking the symbol table I would have handed over two identical layouts labelled as different and drawn a conclusion from it. Fixed by enclosing pad and array in one struct, making the offset a language guarantee rather than a linker accident.
- **RTL plan revised:** K4 payload check runs regardless (different question). **RTL M48 will be dropped if `padshift` passes** -- at that point it tells us nothing; the pair worth running would be `pad0` vs `entpad` instead.
- **Methodological lesson, GVSoC's framing:** we labelled the axis by the parameter we varied rather than by what it physically changed. `ACTIVE_USER_NUMBER` moves entity count, `.data` layout, cache-line collision pattern and per-entity queue depth simultaneously, and we called it "entity count" because that is the macro's name. **Name the axis by the mechanism, not the knob.**

---

### NEAR-MISS: `pkill vsim` would have killed 8 unrelated simulations from another project
- **Time:** 2026-08-25 ~13:10 +0200
- **Do not use a bare process-name filter to free the simulator on this machine.** After the earlier `pkill -f 'vsim.*tb_cachepool'` self-match incident, the GVSoC-side agent suggested `pkill -x <exact-name>` as the safe form and I said I would use it. I checked before doing so: `pgrep -a vsim` shows **8 running vsim processes, all belonging to `/usr/scratch/fenga1/zexifu/TeraNoC_Spatz/TeraNoC`** -- the user's *other* project (mempool / TeraPool, `s8_fp16_*` workloads). **`pkill -x vsim` would have destroyed all eight**, hours of unrelated work, unrecoverably.
- **Correct procedure:** stop the owning background task (`TaskStop`), then *verify* with `pgrep -a vsim` filtered on the `-work` path or `+PRELOAD` argument. Never filter on the bare process name, and never on a pattern that can match the issuing shell's own command line. Confirmed after `TaskStop`: 0 cachepool vsim, 8 TeraNoC vsim still running and untouched.
- Recorded here because it generalises: this is a shared machine, the simulator binary is shared between projects, and both obvious `pkill` idioms are unsafe here for *different* reasons.

### RLC AM: entity-count ladder built; RTL payload target re-sized after measuring 39 cycles/s
- **Time:** 2026-08-25 ~13:05 +0200
- **GVSoC's density sweep is flat:** `M48_N1350_K24` gives `grants=0, completed_sweeps=0, XLINE=0` at **4, 8, 16 and 64 cores** -- density spanning ~3 % to ~95 % with nothing moving, while M8 works at both ends of the same axis. **Core count irrelevant, entity count everything.**
- **Built and froze the entity bracket** at `reports/handover/elf_frozen_2026-08-25_0505_ladder/`: M8/M12/M16/M24/M32/M48, identical but for `ACTIVE_USER_NUMBER`, all 24 packets / 2 producers / 2 consumers / grant 8192 / `RLC_SELF_CHECK=1`. M8 and M48 are the *same binaries* (same md5s) as the earlier frozen set, so the endpoints stay directly comparable rather than rebuilt.
- **Checked for a size threshold before handing it over and found none:** `.data` grows smoothly 21.5 -> 44.7 KB across the ladder with the 32 KiB mm pool trailing, and the linker gives DRAM 0x8000_0000 + 0x2000_0000 -- everything sits deep inside a 512 MB region. So a sharp flip would *not* be a linker-level size cliff, which removes the most obvious "structure crossing a boundary" candidate in advance.
- **Asked one cheap branch-killing question:** do the `[AM] core 2: consumer idx=0` lines appear in the M48 transcript? They print on entry to `consumer()` before any sweep, so their absence would mean the consumers never ran at all and everything else follows trivially. I expect them present -- `rlc_is_consumer()` cannot be entity-count-dependent -- but it retires the branch rather than leaving it assumed.
- **Re-sized the RTL payload target after measuring the real rate.** `tbchk` at K10 reached only 112 us of sim time in 48 minutes = **~39 cycles/s**, slower than the 52 measured earlier, so it could not reach EOC inside the cap. Killed it rather than waiting out the last 12 minutes and built `M1_N1350_K4_..._tbchk`: 4 packets fit one grant (4 x 1363 = 5452 < 8192), giving 4 PDUs and ~5.4 k byte-compares -- minutes rather than hours.
- **RTL queue now:** K4 payload check -> M8 -> M48 (the entity question, with trustworthy counters) -> GVSoC's reference batch.

---

### RLC AM: stale-read density model refuted; idle() shown sound on coherent hardware
- **Time:** 2026-08-25 ~12:50 +0200
- **My stale-read density model is dead, refuted by GVSoC's own existing data.** `M8_N1350_K24` at 64 cores (~95 % density) opened **3 grants and completed 2 sweeps**. If one stale zero among eight `sduNum` reads sufficed to satisfy `idle()`, that run should essentially never have completed a sweep. Across their three runs **density varies ~30x with no effect on outcome while entity count varies 6x and flips it** -- the same controlled-contrast argument that killed the gather hypothesis.
- **Own error worth recording:** I built the arithmetic on their 3 %/95 % figures after they had explicitly flagged them as `cache-basic` word-mismatch densities from a write-once-read-all pattern, not per-read error probabilities for a different access pattern. I transferred them anyway because the numbers produced a clean story (22 % vs 77 %), and the neatness should have increased suspicion rather than confidence.
- **Pushed back on one of their claims and I believe correctly: `rlc_am_idle()` is NOT unsound on coherent hardware.** They argued a legal interleaving could satisfy it transiently. Traced it: the gate is `producer_done >= N && rlc_am_idle()` (short-circuit); `producer_done` reaches N only after every producer has **returned from its final `list_push_back`** (it is incremented after `producer()` returns -1, on a later iteration than the last push); so once the gate reads N **no list can grow**, only `commit()` pops; `idle()` therefore scans a monotonically-draining set, and a scan returning 1 implies every list was empty at read time and still is. **Sound.** The O(N) cost and the fragility under unreliable reads are real; transient satisfaction by a legal interleaving is not.
  - Consequence: the monotone produced-vs-retired counter still gets built, but lands as a **cost-and-robustness** change (O(1) on the hot exit path, immune to bad reads) rather than a correctness fix -- claiming the latter would be unjustified.
- **Accepted their revised framing of my prediction:** RTL opening grants on M48 is consistent with their visibility bug *and* with any 48-entity-specific kernel issue coherent hardware tolerates. Evidence, not a discriminator. The sharper question is whether outcome tracks entity count rather than core count.
- **Requested runs (free on their side, higher value than anything on my RTL queue):** M48 at 8 and 16 cores to fill the density axis between their two points -- either extends the flat line or finds a knee. Offered to generate M16/M24 headers to bracket the entity axis between the working 8 and failing 48: a sharp flip suggests a structure crossing a size boundary, a gradual one suggests accumulation. Not built yet -- asked rather than assumed.
- RTL `tbchk` at 41 min and still running; letting it reach the cap since a completed payload check remains the only untainted answer on the copy question.

---

### RLC AM: premature exit diagnosed -- stale cross-core reads of `sduNum`, with a falsifiable RTL prediction
- **Time:** 2026-08-25 ~12:30 +0200
- **GVSoC's transcript gave a third branch neither of my two covered:** the M48 run **terminated normally** (core 0 printed the report *and* its final per-core line, both downstream of the full 64-core barrier) **and** left work undone. So `rlc_am_idle()` returned true -- not a halt, not slowness, a **premature exit**. (No literal `[EOC]` line: their wrapper swallows the tail. Core 0's final print is downstream of the same barrier, so it answers the question the split turned on.)
- **But their supporting `tosend` histogram is arithmetically impossible.** It sums to **33 queued SDUs** against **24 packages** in `data_48_1350_24.h`. Nodes enter a to-send list exactly once, in `producer()`, and `grants=0` means commit never popped any, so 24 is the hard maximum. Re-read `list_push_back` to rule out over-counting: head, tail, `sduNum` and `sduBytes` are all maintained together under the lock -- it is correct. So those values are not merely uncertain, they are provably wrong.
- **The diagnosis survives anyway, and the mechanism is theirs: `rlc_am_idle()` reads `rlc_ctx[u].list.sduNum` for every entity -- producer writes, consumer reads, i.e. their failing class. One stale zero on a non-empty list satisfies the predicate and the consumer exits.** At their measured ~3 % per-read density: 8 entities -> P(all reads correct) 0.78, so 22 % chance of a spurious exit per scan; **48 entities -> 0.23, so 77 %**. That reproduces the M8-vs-M48 contrast quantitatively with no kernel bug.
- **Ruled out their proposed producer-fill race:** the exit short-circuits on `producer_done >= PRODUCER_CORE_NUM` first, and `producer_done` is incremented only *after* a producer's final `list_push_back` returns -- so once it reads 2 the lists are stable and a correct scan cannot see them empty. The race they hypothesised cannot occur; stale reads can.
- **Falsifiable prediction committed before the run: `M48_N1350_K24` will open grants on RTL**, because the shared L1 has one home per line so `sduNum` reads are coherent and `idle()` cannot see a stale zero. If RTL wedges too, the bug is mine and their engine merely amplified it.
- **Design fix to make regardless of the outcome:** `rlc_am_idle()` is an O(NUM_USERS) non-atomic scan used as a **termination** condition. Even on coherent hardware it is not a consistent snapshot, and a termination predicate satisfiable transiently is fragile by construction. Replace with a monotone counter -- SDUs produced vs SDUs retired -- which is O(1), snapshot-free, and cannot be satisfied early. Their bug surfaced a genuine design weakness even if it turns out not to be the proximate cause here.

---

### RLC AM: entity count is the variable -- gather hypothesis dead, wedge localised to 8-vs-48 entities
- **Time:** 2026-08-25 ~12:10 +0200
- **Controlled experiment result (GVSoC, frozen ELFs, `md5sum -c` all OK):** `M48_N1350_K24` **wedges** (grants=0), `M8_N1350_K24` **works** (grants=4, completed_sweeps=3). Same packet count, producers, consumers, 4-core config and build. **Entity count is implicated independently; the budget fix is not sufficient; queue depth is not the variable.** My gather explanation for the wedge is dead.
- **Their corroboration is the strongest evidence in this whole thread, and it sidesteps their own bug entirely: `XLINE: 0` on M48 vs `63` on M8.** XLINE is internal to their cache model, per-instance, never read across cores by the kernel. M8 opens grants -> runs payload copies -> hits unaligned accesses -> truncates. M48 opens none -> no copy -> nothing to truncate. So `grants=0` is established through a mechanism with no dependence on the corrupted class -- arguably stronger than a kernel counter, being measured on the other side of the interface. Their argument that the *contrast* survives the 3 % density floor also holds: both runs sit at the same density, and a corruption firing at equal rates cannot explain one opening four grants and the other none.
- **One contradiction still open, and it needs a single fact I cannot get locally: did the M48 run reach EOC?** `cluster_entry` is work -> **full 64-core** `snrt_cluster_hw_barrier()` (verified: not the `snrt_cluster_partial_barrier` the runtime also offers) -> core 0 prints. So a printed report requires every consumer to have left its loop, which requires `rlc_am_idle()`, which requires every list empty. Clean split:
  - **EOC + retval** -> consumers exited normally -> `completed_sweeps=0`, `last_entity=12/48` are corrupted reads, and the wedge is a **throughput** story;
  - **killed, no EOC** -> counters truthful -> a real **halt** in my code at 48 entities.
  `XLINE=0` is consistent with both. Asked them for the `[EOC] Simulation ended` line from the existing transcript -- no new run needed. Also noted `tosend` is read by core 0, which is itself a producer, so for entities it wrote it is largely reading back its own stores: less exposed than the consumer-written counters, though not clean.
- **RTL `M48_N1350_K24` is queued behind `tbchk`** and settles halt-vs-throughput with counters neither side has to caveat.
- **They are staying in on interpretation** with the label-which-side convention. Worth recording why that matters: today's two best results each came from one side challenging the other -- they pushed me to check the RTL decoder and I found a real kernel bug (`vmsgtu.vx`), I questioned their contamination assumption and they found the density floor invalidated a standing rule they had written down. Neither happens with one engine or one reader.

---

### RLC AM: build churn destroyed a peer run's provenance -- frozen ELF snapshot as the fix
- **Time:** 2026-08-25 ~11:55 +0200
- **My fault, and worth recording as a process failure:** GVSoC ran a TC2 binary at mtime 04:27:33; by the time they grepped its listing I had rebuilt it to 04:37:21 (and twice more after). **What they tested is now unknowable**, and their "byte-identical to the pre-fix run" observation is about an unknown build. I had been disciplined about exactly this earlier -- deliberately refusing to rebuild while runs were queued, and md5-checking queued ELFs across builds -- and dropped it once I started adding targets quickly.
- **Fixed structurally, not by intending to be careful:** `reports/handover/elf_frozen_2026-08-25_0450/` with `MANIFEST.md5`, a README, and six immutable AM ELFs. Peer runs from there; `software/build/CachePoolTests/` is mine to churn. If a binary must change, a **new** `elf_frozen_<timestamp>/` is created rather than the existing one touched. Each ELF verified by grepping its interleaved-source `.s` for `list_peek_budget`, `rlc_am_open_entity`, the cross-tile guard and the sweep counters. The M48 control is md5 `16b63a29`.
- **GVSoC accepted all three points and struck a standing rule they had committed:** they had written down "any shared-data result is trustworthy if it comes from a low-core config with XLINE=0", and replaced it with the correct envelope -- **GVSoC cannot answer cross-core shared-data questions at any configuration** until the visibility bug is fixed; per-core-private data stays sound (`cache-stress` passes at every scale, `cache-basic` fails). They also recorded the determinism trap as general guidance.
- **They proposed stepping back from interpretation entirely (four retractions today, three theirs). I pushed back, because that tally is wrong.** Their engine found `vmsgtu.vx` -- a **real kernel bug of mine**, not a model artefact. Spatz decodes the vector integer compares and implements none of them, so on our hardware the first-crossing search would have produced a wrong mask **silently**, no trap, no symptom. Nothing in our flow catches that: the host test compiles the C twins, and RTL runs it to a wrong answer without complaint. That single find outweighs the retractions and came precisely from the property being discounted -- a different engine with different failure modes.
- **Also corrected the attribution:** the `tosend`/`peek_max` retraction was **mine** (my diagnostic pairs a running maximum with a value sampled at report time and invites the inference), and "stopped, not slow" was drawn from `steps`, a counter I built that structurally could not encode the distinction. They retracted things I handed them.
- **Standing arrangement going forward:** they keep interpreting and label which side of the shared-data line each result sits on; I weight accordingly. Their runs and RTL are a cross-check, not substitutes -- RTL runs `M48_N1350_K24` behind `tbchk` regardless of what they find.

---

### RLC AM: TC2 undiagnosable on GVSoC -- counters contradict the report having printed
- **Time:** 2026-08-25 ~11:40 +0200
- **My gather explanation for the TC2 wedge is dead, and GVSoC killed it correctly:** if the wedge happens during the **first** sweep while queues are still filling, `list_peek_budget` is a no-op **by construction** -- an empty-queue walk stops at the first node regardless of any budget. So the gather explains steady-state cost but cannot explain a wedge that occurs before the queues are deep enough for that cost to exist.
- **Answered their build question properly.** Every target emits a `.s` with source lines interleaved, so the fix's presence is a fact to grep (`if (acc >= budget)`), not a timestamp inference. My TC2 AM ELF (04:37:21) has it: `acc >= budget` 1, `acc += overhead` 1, `rlc_am_sweeps` 18, `rlc_am_open_entity` 5. Told them to grep their own rather than take my reconstruction.
- **The decisive point: their TC2 counters contradict the report having been printed at all.** `rlc_am_report()` runs on core 0 *after* `snrt_cluster_hw_barrier()`, which needs all 64 cores; consumers reach it only by leaving the loop; leaving requires `rlc_am_idle()`, which requires **every** entity to have `list.sduNum == 0`; and `rlc_am_sweeps[trk]++` sits at the end of the sweep before `return` (re-read to confirm). So a printed report implies `completed_sweeps >= 1`, `last_entity = 47`, `tosend = 0`. They observed `0`, `26`, `2..10`. **No value of any kernel variable makes those consistent** -- it requires the cross-core reads themselves to be unreliable, which is exactly their v1-and-later bug.
- **`XLINE=0` does not clear a run for this.** Truncation and cross-core visibility are two different defects; they measured the visibility one at **3 % density at 4 cores / 1 tile**, so the "clean corner" is clean only for truncation.
- **Flagged an unsound inference before either of us leaned on it:** their 4-core run being byte-identical to the pre-fix one was read as "unchanged code path", but **a deterministic simulator corrupts deterministically** -- identity is equally consistent with "the same corruption happened twice". Identity cannot discriminate here.
- **Conclusion: TC2 cannot be diagnosed on GVSoC until the visibility bug is fixed**, and I asked them to stop spending runs on it. The `M48_N1350_K24` control on RTL is now the only path -- built 04:37:28 with `data_48_1350_24.h`; they had pulled before it existed.
- **Instrument flaw acknowledged:** `steps` counts *entries*, so it was structurally incapable of distinguishing halted from slow, and I shipped it as if it could. GVSoC drew "stopped, not slow" from it and I accepted that; the fault is the instrument's. `completed_sweeps` (increments only on completion) is the counter that can answer it.

---

### RLC AM: retracted the "list corruption" reading -- the TC2 wedge is the un-fixed gather
- **Time:** 2026-08-25 ~11:15 +0200
- **GVSoC tested the contamination concern instead of arguing it:** re-ran TC2 at 4 cores / 1 tile (the 3 %-density corner) and got **XLINE 0**, with self-consistent counters -- a contiguous prefix u0..u5,u7 attempted, then the sweep stops at `last_entity=26/48`. Confirms the 64-core dump was contaminated (the `u0=1`/`u30=0` control-flow contradiction was the right tell) and that the wedge itself is real.
- **Retracted a reading I introduced and both of us built on: there is no head/sduNum disagreement.** `peek_max` is a running maximum recorded *during* the run; `tosend` is `rlc_ctx[u].list.sduNum` read **at report time**. So `peek_max=0` with `tosend=7` says only that the single peek happened *before* producers enqueued -- exactly what one sweep at the start of a run looks like. Their "seven for seven, uniform not sporadic" is the signature of all seven peeks being early, not of list corruption. **My diagnostic's fault**: it prints a running max next to a value sampled at a different time and invites the comparison.
- **Also retracted "stopped, not slow".** I accepted that from `steps=1` and should not have -- a single sweep 36x longer is indistinguishable from a stopped one when the run ends inside it.
- **Actual explanation, and their runs predate the fix.** Their TC2 runs are on the 04:17 tree; `list_peek_budget` landed at ~04:30. Uncapped, every `try_plan` walks up to 128 nodes: 8 entities / 2 consumers = 4 owned each = up to 512 dependent loads per sweep; **48 entities = 24 owned each = up to 3072**. The shape matches exactly -- early entities peek *empty* (O(1), fast), then as producers fill queues the later entities in the same sweep hit full 128-node walks, so the sweep starts fast and bogs down partway. That is `last_entity=26/48`, and it is why M8 completes sweeps and TC2 does not: ~6x the entities times ~6x the per-entity walk as the run warms up.
- **Their M8 runs (my target) localise it independently:** `grants=4 completed_sweeps=3` at 4 cores, `grants=3 completed_sweeps=2` at 64 cores -- **M8 works at both scales** with the same code, producers and consumers. So it is not the AM path, not ownership, not their simulator: it is something that changes between 8 and 48 entities. Their M8 payload verdict is contaminated (63 / 273 XLINE) but the grant-progress integers are written once per grant and far less exposed.
- **Built the controlled experiment:** `data_48_1350_24.h` + `..._M48_N1350_K24_P2_C2_am_G8192_tbchk` -- 48 entities at M8's 24-packet workload, isolating entity count from queue depth. If it passes while real TC2 does not, the cost is the gather; if it also wedges, entity count is implicated on its own. RTL can run this; it cannot run real TC2.
- **Cheapest next test is on their side:** re-run TC2 on the current tree. One run either kills the gather hypothesis or ends the TC2 investigation.
- **Verified again that the rebuild disturbed nothing queued** -- md5s of `M1_N1350_K100_P2_C4_am_G8192`, the M8 target and all five reference kernels are byte-identical across the build.

---

### RLC AM: GVSoC's shared-data bug invalidates its verdicts; RTL-sized targets built for both open questions
- **Time:** 2026-08-25 ~10:50 +0200
- **GVSoC retracted their cache-test diagnosis.** Not the truncation (XLINE=0), not per-bank corruption, and **not address->home routing** -- `BANKS_PER_TILE` = 1, 2 and 4 all give identical 247 mismatches, and with one bank there is no routing. **v1 fails too (1,266 mismatches at 16 cores)**, so it predates everything done this week: their model has apparently never been validated for cross-core shared-data correctness. Their own conclusion, stated plainly: **any payload verdict from their simulator is unsafe**, because the AM transport block is written by multiple cores and sits in the failing class.
- **Their `tbchk` run confirms it: 231 XLINE events**, `align_ok=0x0` (not one destination alignment passes). That is their truncation writing the answer, not a base-address bug. Verdict discarded; the target itself works as designed (3 grants, per-grant `[AM-SB]` detail coming through).
- **Their TC2 counters are also untrustworthy, and I could show it from the data rather than assume it.** `peek_done=1` does rule out the lock-hold hypothesis. But the surrounding numbers are **internally inconsistent with my control flow**: `last_entity=38` means consumer 0's sweep visited u=0..38, it owns the even entities, and the only gate between visiting `u` and `plan_calls++` is `open_entity == NO_ENTITY`. If that held, every even u<=38 must show `plan_calls>=1` (u30/u32 showing 0 contradicts); if it did not, the gate was shut all sweep and u0 would have been skipped too (u0 showing 1 contradicts). **No single value explains both.** All of `rlc_am_ent[]`, `rlc_ctx[]` and the list heads live in `.data` below the l1d_addr boundary -- classified **shared**, written by one core and read by another -- so every number in that dump is in the class their bug corrupts. The `head`-vs-`sduNum` disagreement is as likely theirs as mine.
- **Consequence: RTL is now the sole authority on both open questions.** Re-prioritised the RTL queue accordingly and built two targets sized to actually finish at ~52 cycles/s:
  - `..._M1_N1350_K10_P2_C2_am_G8192_tbchk` -- 10 packets, `RLC_SELF_CHECK` only (plan-verify dropped: the planner is cleared by 589,728 host checks and by their own vector-vs-reference PASS, and it was costing ~half the overhead to re-confirm). Answers the payload question. **Running.**
  - `..._M8_N1350_K24_P2_C2_am_G8192_tbchk` -- 8 entities, 24 packets, new `data_8_1350_24.h`. Exercises what TC2 does and TC1 cannot (several entities per owner, the one-open-grant rule, the ownership partition) at ~1/20th of TC2's work. Answers the head-vs-sduNum question.
- **Rebuild landed everything that had been source-only** -- budget-bounded gather, one-open-grant-per-owner, cross-tile TB guard, `peek_done` -- all four verified *present in the binary* by grepping the disassembly, not assumed. Host planner test still 589,728 / 0; legacy loadable image still `cmp`-identical to pristine.
- **Verified the rebuild disturbed nothing already queued:** snapshotted the md5 of `M1_N1350_K100_P2_C4_am_G8192` and all five reference kernels before the build and re-checked after -- all **byte-identical**.
- **Process:** `pkill -f 'vsim.*tb_cachepool'` matched the pattern against my own shell's command line and killed the shell mid-script before its edits applied. The simulator did stop and no damage resulted, but the edits had to be redone. Correct form is `pkill -x <exact-name>`.

---

### RLC AM: RTL trace shows the gather dominates -- 18x wasted pointer chase found and fixed
- **Time:** 2026-08-25 ~10:20 +0200
- **Both AM RTL runs timed out** (`_am_G8192` and `_am_G8192_scpy`, rc=124 at the 3600 s cap, no `[AM]` report from either). **But not wedged.** Salvaged `_scpy`'s per-hart trace before the next run overwrote it: core 2 has 93,791 entries reaching **187,138 ns of simulated time in 3600 s wall** = **~52 cycles/s**, against ~430 cycles/s for legacy TC1. The AM build is ~8x slower to *simulate*, which explains both timeouts with no hang. Confirms GVSoC's "honest slowness" reading, independently of their 6x check-overhead measurement.
- **The trace names where the time goes, and it is not where either of us guessed.** The hot PCs resolve to one loop -- `lw a5,8(a4)` / `sw` / `lw a4,16(a4)` / `sw` / `bnez` at `0x80001a70..8c` -- which is the **gather** in `rlc_am_try_plan`: `plan->sdu_data[i] = peek[i]->data`, two dependent loads per node chasing pointers through the to-send list. It accounts for essentially the whole trace tail. Not the copy, not the planner arithmetic, not the locks.
- **Found an 18x waste sitting next to it.** At an 8 KiB grant with 1363-byte PDUs only **6** SDUs can fit, but `list_peek_n` was called with `max = RLC_MAX_PDUS_PER_GRANT = 128` -- so up to 128 nodes were pointer-chased, one cache miss each, to plan 6, on **every** grant whenever the queue is deeper than the grant.
  - **Fixed with `list_peek_budget()`**: stops walking once accumulated `header + data_size` exceeds the grant, keeping the overflowing node because that is the segmentation candidate. Budget is `RLC_GRANT_BYTES + so_next` -- the peek charges full `data_size` for the lead SDU while only `data_size - so_next` is actually pending, so adding `so_next` compensates exactly; charging the minimum header keeps the bound conservative so the walk can only stop later than necessary, never early. Source only (checks-off RTL run in flight against the 02:20 binary).
- **Why this matters beyond the fix:** it is a good result for the plan/execute design -- the vectorised arithmetic is *not* the serial bottleneck, the dependent pointer chase is, which is exactly what the GVSoC side's list-prefetching argument targets. When the Amdahl fraction is finally measured, gather is what will be measured. It also means any AM-vs-legacy cycle comparison made before now would have been skewed by an 18x-inflated gather **on top of** the already-flagged missing SDU cacheline traffic; good that neither side produced one.
- **Process:** the earlier trace loss is fixed -- `run2.sh` and the reference batch both snapshot `sim/bin/logs/core/trace_hart_*.dasm` into `reports/.../trace/<test>/` before the next run starts. The `_scpy` traces were recovered manually only because I checked the directory before the next run had written to it.
- **Queue:** checks-off `_M1_N1350_K100_P2_C4_am_G8192` started 04:12:54 (decides hang-vs-slow definitively); reference batch behind it.

---

### RLC AM: cross-tile transport-block bug found in OUR design (prompted by a GVSoC cache bug)
- **Time:** 2026-08-25 ~09:50 +0200
- **GVSoC settled my RTL timeout confound cheaply:** same TC1 workload, checks ON = 3 grants / 17 PDUs / `tosend=86`; checks OFF = **16 grants / 97 PDUs / `tosend=0`**. ~6x the throughput, and checks-off **drains the queue completely** -- the first time the AM path has finished its work on either engine (`sent=14`, `gen=36`). So the RTL timeout is almost certainly verification cost, not a wedge; the checks-off RTL run will confirm.
- **Their cross-core visibility bug prompted me to check my own design, and found the same class of bug in the kernel -- mine, not a model artefact.** The transport block is written by every core executing a grant. `RLC_TB_BASE = 0xB000_0000` is **above** the `l1d_addr` boundary, so the arena is **private**, and per the README private banks are tile-local and invisible to remote tiles. `main.c` sets `l1d_part(num_cores_per_tile)` = all private. **Executors on different tiles would write into different copies of the transport block**, and the owner would verify only its own tile's half -- silent payload loss, no other symptom.
  - Every configuration run so far is safe **by accident**: consumer lists are {2,3} or {1}, all inside tile 0 at 4 cores/tile. C=8 spans tiles {0,1,2}; C=16 spans {0..4}. It breaks the moment executors scale, which is the entire point of the design.
  - **Added a startup guard** that detects a tile-spanning consumer set and fails loudly (plus `RLC_AM_ALLOW_CROSS_TILE_TB` for when the arena is genuinely made cluster-visible). Source only -- not built, because the checks-off RTL prediction is being tested against the 02:20 binary.
  - **Open design decision:** move the arena below the boundary so it is cluster-shared, or confine an entity's executors to the owner's tile. The second is the GVSoC side's tile-local placement argument arriving through the back door, and if a cluster-shared TB measures expensive it becomes a substantive argument rather than an aesthetic one. Note the first option is not free either: an all-private `l1d_part` leaves no shared banks at all.
- **Ruled on their cache-test failure, and it favours their theory over my suspicion.** I had suggested `cache-test-scalar`/`cache-test-vector` might be assuming coherence they were not entitled to. They are not: neither main.c calls `l1d_part`, `l1d_xbar_config` or `l1d_addr`, so both run the reset configuration -- and `cachepool_peripheral_reg.hjson` gives `L1D_PRIVATE resval = 0` (zero private banks, **everything shared**) and `L1D_ADDR resval = 0xA000_0000`. With a fully shared pool there is exactly one home bank per address, so cross-core visibility is architecturally guaranteed and **their 3 %->21 %->95 % escalation is a real model defect**.
- **The two bugs are exact opposites and were nearly conflated:** `cache-test-*` runs all-shared, where cross-tile visibility is guaranteed and their model breaks it (model bug, theirs); the RLC kernel runs all-private, where it is not guaranteed and my design assumed it (kernel bug, mine). Fixing either does not touch the other. Also suggested the RLC kernel as a private-path workload for them while they chase the routing bug, since it should be insensitive to cross-tile home routing entirely.

---

### RLC AM: first RTL run of the AM path timed out -- confound identified, requeued
- **Time:** 2026-08-25 ~09:20 +0200
- **`M1_N1350_K100_P2_C2_am_G8192` on RTL: rc=124 at the 3600 s cap**, no EOC, no `[AM]` report; only the two consumer-entry lines, so both consumers entered `rlc_am_step` and never returned. No trap, no error. Same shape as the GVSoC TC2 wedge.
- **Not read as a hang, because the target is confounded.** It is built with `RLC_PLAN_VERIFY=1` *and* `RLC_SELF_CHECK=1`: every grant runs **both** planners and the verifier byte-compares **every payload byte** scalar (~1360 per PDU) on top. At ~430 cycles/s the cap is ~1.5M cycles against legacy TC1's 182k, so a checked AM build could exceed it legitimately. The run cannot distinguish a wedge from honest slowness.
- **Requeued, correctness before calibration** (GVSoC's own prioritisation): `_scpy` (running; its XLINE count is useful regardless of whether it finishes) -> **`_M1_N1350_K100_P2_C4_am_G8192` with checks OFF** (`RLC_TB_MODE=1` only -- defines verified from the build flags; `rlc_am_report()` is not gated on the checks so grants/pdus still print) -> then the reference batch. If the checks-off build completes, the earlier timeout was verification cost; if it also times out, AM genuinely wedges on RTL and that is a real divergence from GVSoC, where the same path opened three grants.
- **Lost the vector run's per-hart traces** -- `_scpy` started immediately and overwrote `sim/bin/logs/core/`, which is the RTL equivalent of GVSoC's PC trace. Avoidable; all subsequent runs now snapshot traces to `reports/.../trace/<test>/` before the next run starts.
- **Process near-miss worth recording:** I began editing `run.sh` while bash was still executing it, which can make the shell resume at a stale byte offset and run garbage. Caught it, restored the in-flight file to its original bytes, and applied the change to the not-yet-started script instead.
- **Build/source skew, deliberate:** the ELFs on disk are the 02:20 build -- progress counters present, but **not** the one-open-grant-per-owner fix or `peek_done`. Rebuilding mid-wave would have made queued runs load different binaries than the ones they are being compared against. For TC1 the open-grant fix is a no-op (one entity per owner) so the queued runs are valid; TC2 must not be re-run against the current tree expecting the aliasing fix.

---

### RLC AM: TC2 wedge confirmed; plan-buffer aliasing found and fixed; RTL reference batch queued
- **Time:** 2026-08-25 ~08:50 +0200
- **TC2 wedge confirmed by the new counters:** `consumer 0: steps=1 completed_sweeps=0 last_entity=38/48`, `consumer 1: steps=1 ... last_entity=37/48`. Both entered `rlc_am_step` once and never returned, stopping on an entity they own (consumer 0 owns even, consumer 1 odd -- 38 and 37 fit). Stopped, not slow, which **rules out my sweep-cost hypothesis**; the `_wq` contrast cannot isolate cost when neither variant progresses.
- **One data point retracted -- my instrumentation gap.** `rlc_am_last_u` and `rlc_am_sweeps` were only written in the **non-wq** branch, so the wq run's `last_entity=0 completed_sweeps=0` was the initial value, not an observation, and its `plan_calls=0` on u0 is expected (the wq owner pass only visits entities whose ready bit is set). The only real wq signal was `steps=1`. Now instrumented in both branches.
- **Found a definite bug while reading the code for the wedge: plan-buffer aliasing.** `e->plan = &rlc_am_plan_pool[rlc_am_owner_idx(u)]` indexes the pool by **consumer**, not entity. TC1 is one entity per slot and fine; **TC2 with 2 consumers puts 24 entities on a single `rlc_plan_t`** (6 at C=8). Executors read `e->plan` for the whole life of a grant, so an owner planning its next entity would overwrite a live plan underneath them -- wrong offsets, wrong SNs, arbitrary corruption. Masked only because TC2 has opened zero grants; it would have bitten the instant the wedge cleared, and would then have looked like a fresh mystery.
  - **Fixed:** at most one open grant per owner, which must be committed before another entity is planned. Costs grant-level parallelism per owner (2 concurrent grants at TC2 instead of up to 48); the alternative is a per-entity pool at 48 x ~7 KiB, not worth spending before the path works. Applied to both wq and non-wq branches.
- **Added `peek_done`**, incremented immediately after `list_peek_n` returns, to close the last ambiguity in that region: `plan_calls=1, peek_done=0` means blocked *inside* the peek on `tosend_llist_lock_2[u]`; `peek_done=1` means it returned and the block is elsewhere.
- **Deliberately did NOT rebuild.** The `_scpy` RTL run is queued behind the vector one and had not started; rebuilding would have made it load a different ELF than the vector run, invalidating the very comparison those two runs exist to make. Tree has the fixes as source, build is still 02:12.
- **RTL reference batch agreed and queued** (GVSoC request, and their reasoning is sound: `M1_N1350_K100` lights up 4 of 64 cores and is latency-bound pointer-chasing, so +14.8 % agreement there says nothing about a memory-bound workload at full occupancy). Batch on `cachepool_fpu_4g`: `bandwidth`, `fmatmul-32b_M64_N64_K64`, `fdotp-32b_M32768`, `byte-enable`, `cache-line-rw-smoke`; scripts in `reports/rtl_reference_2026-08-25/`. Chained to start automatically when the AM pair releases the simulator -- concurrent vsim instances share `sim/bin/logs` and the `.rtlbinary` handoff and would corrupt each other.
- **Partition modes captured to send with the numbers** so they are not compared across different cache configurations: `bandwidth` `l1d_part(4)`, `fmatmul-32b` `l1d_part(num_cores_per_tile)`, `fdotp-32b` / `byte-enable` / `cache-line-rw-smoke` set only `l1d_xbar_config`.

---

### RLC AM: _scpy control is diagnostically useful but vacuous; TC2 sweep instrumented
- **Time:** 2026-08-25 ~08:20 +0200
- **`_scpy` result: `XLINE events: 0`, confirming the byte-granularity analysis** -- a 1-byte access cannot straddle a 64 B line, so GVSoC's truncation condition cannot fire and the payload-path events vanish. **But its PASS is vacuous**: `grants=1 pdus=2 tb_used=2726` against the vector build's `16`/`8192`, and the checker examined 0 grants. Byte-at-a-time over 1360-byte payloads is ~1360 dependent load/store pairs per PDU, so the owner spends the run inside the copy. The control is diagnostically useful and performance-useless -- I should have said so when building it, and would have banked the green if GVSoC had not checked the grant count. Third time their scepticism caught a false positive.
- **Both sides now read the payload diagnostic the same way, and it points at the truncation, not the copy:** `first_diff_byte=13` rather than 0 (truncation drops the tail at a line boundary; a wrong base would corrupt from byte 0), and `align_ok=0x3`/`align_bad=0xe` **overlap at bit 1** -- some offset-1 destinations pass and some fail, which is "depends where this payload happens to cross a line" rather than a base-address bug. Not calling it until RTL answers.
- **New TC2 failure: `u47 plan_calls=0`** on `M48_N800_K300_P2_C2_am_G8192` -- that entity was never *attempted*, distinct from "attempted and found nothing". The `RLC_ACTUAL_CONSUMERS` arithmetic is fine (stride=2, u0->consumer 0, u47->consumer 1, both exist, and the sweep visits every entity regardless of ownership). What does not add up is cost: a sweep is ~48 cheap atomic loads plus 24 lock-and-peek attempts, so 1.27M cycles should be hundreds of sweeps and `plan_calls` on u0 should be in the hundreds. **It is 1** -- so the consumer is stopped inside its first sweep, not making slow progress through it.
- **Added per-consumer progress counters** (`steps`, `completed_sweeps`, `last_entity`) to separate the two: `steps=1 completed_sweeps=0 last_entity=<small>` means wedged at that entity, and the only blocking thing in the sweep is the per-user to-send spin lock inside `list_peek_n`; `steps` large with `completed_sweeps=0` would mean the sweep restarts without finishing, a different bug. Audited the lock discipline while writing this -- no nesting anywhere (`rlc_am_commit` releases the to-send lock in `list_pop_front` before acquiring the sent lock in `list_push_back`; `rlc_am_status` takes only the sent lock; no path holds a list lock across `printf_lock`) -- so a classic deadlock is not the explanation and the counters are needed.
- **Suggested they also run the `_wq` TC2 target**, since the bitmap work queue skips idle entities instead of sweeping all 48, which is exactly the cost this result exposes.
- **Reproducibility note:** software was rebuilt at 02:20 to add the progress counters while the RTL AM run was already in flight. The RTL run loaded its ELF at t=0 from the 02:12 build, so its result is valid but predates the counters -- which do not touch the copy path. No further rebuilds until the RTL runs land.

---

### RLC AM: payload bug -- GVSoC cache-model truncation found; settling the copy on RTL
- **Time:** 2026-08-25 ~07:40 +0200
- **GVSoC found a data-corruption bug in their own L1 cache model** and took ownership: `insitu_cache_core.cpp::exchange_line_data()` truncates any access straddling a 64 B line (`n = cache_line_bytes_ - off`) and completes it "successfully", silently dropping the tail. It fires on our kernel -- `[XLINE] addr=0x2c0003f size=4 off=63 wr -> TRUNCATED`, i.e. 3 of every 4 bytes discarded -- and the warning is capped at 12 and goes to stderr, which the launcher swallows. Fits the payload-only signature exactly: write-side, offset-driven, independent of how bytes are moved, hence identical across reference/scanC/vector planners and at C=1.
- **Corrected their experiment before it misled them.** They predicted `_scpy` would *fail* and still emit XLINE warnings. It cannot: I checked the emitted code rather than trusting the source, and the scalar loop really is byte-granular (`lb`/`sb`, one byte per iteration -- -O2 did not widen it into word stores or a memcpy call, which would have silently invalidated the control). **A 1-byte access can never straddle a 64 B line**, so `off + n > line` cannot fire. If the truncation is the whole story, `_scpy` *passes* and the payload-path XLINE events disappear.
- **Named the likely source of their `size=4 off=63` events: my copy.** Nothing else in the AM path issues misaligned wide accesses -- the planner's `vse32.v` targets 4-aligned arrays (a 4-byte access at a 4-aligned address cannot straddle a 64 B line), `rlc_amd_hdr_write` is byte stores, and the producer's legacy `vector_memcpy32_m4_opt` is 4-aligned. The one generator is `rlc_memcpy8`'s unaligned `e8/m8` base, which a VLSU decomposes into misaligned word transactions. **Their bug being real does not exonerate my copy:** whether Spatz's actual VLSU handles an unaligned `e8/m8` base is still unvalidated, and their model cannot answer it while the truncation masks a correct and a broken VLSU identically.
- **Started the authoritative test on RTL** -- `..._am_G8192` and `..._am_G8192_scpy` under QuestaSim, into `reports/rlc_am_rtl_2026-08-25/`. This is the one question our side can answer and theirs currently cannot. Outcomes: both pass -> truncation was the whole story and the AM path is correct on hardware; vector fails / scalar passes -> Spatz's VLSU also mishandles the unaligned base and the copy must change regardless; both fail -> the offsets are wrong and neither explanation suffices. That third case is precisely what their `_scpy` run cannot separate from their own truncation.
- **Note for whoever reads the diagnostics next:** the `align_bad`/`align_ok` masks now read *through* their bug, so an "alignment-sensitive" verdict means "sensitive to something about the destination offset", not necessarily mine. `first_diff_byte` is the sharper field -- truncation drops the tail, so it should land at the distance to the next 64 B boundary and essentially never at 0, whereas a broken unaligned vector base would corrupt from byte 0.
- **Second time their loud failure stopped a wrong kernel edit** (after `vmsgtu.vx`): I was one step from rewriting `rlc_memcpy8` on an alignment story that was at best half right.

---

### RLC AM: vector path runs end to end; payload bug localised; owner-partition bug fixed
- **Time:** 2026-08-25 ~07:00 +0200
- **The vectorised planner now runs on GVSoC.** With the compare/merge removed from the default, GVSoC reports `grants=3 pdus=16 plan_ok=3 poison=3 published=3 gen=5 sent=3` and **`plan vector-vs-reference mismatches: 0 -> PASS` with three real grants behind it** -- the first non-vacuous pass of that check. Plan, publish, execute, commit and retirement all work.
- **Remaining failure is one bit: `verify_mask=0x80`, payload only, `first_bad_pdu=0`.** Bits 0-6 clear means every header field, offset and SN is right; bits 8-10 clear means continuity across grants holds; **bit 11 clear means every chunk was executed** -- so this is not un-executed work, which is exactly what that bit was added to answer. Identical on the reference, scan-C and vectorised planners, and identical at C=1, so neither the planner nor concurrency is involved. `rlc_memcpy8` is the only remaining common factor -- the unaligned `e8/m8` copy flagged as suspicion #1 in the original handover.
- **Added two things to settle it:** a `_scpy` control (`RLC_DL_COPY_SCALAR=1`, payload via scalar byte stores; verified 0 `vle8.v`/`vse8.v` against 1 each in the default) and an alignment diagnostic reporting `align_bad`/`align_ok` bitmasks over `(payload_dst & 3)`, bad/checked PDU counts and the first differing byte. If only 4-byte-aligned destinations compare equal, it is alignment-sensitivity conclusively.
- **Partial quantitative pre-confirmation, deliberately not overstated:** payload destinations advance by `pdu_len = 3 + 1360 = 1363` and `1363 mod 4 = 3`, so alignments cycle 3,2,1,0 and exactly one in four lands aligned -- which is precisely GVSoC's 16 PDUs / 12 mismatches / 4 passing. But modelling the grant boundaries properly gives 2 aligned, not 4, because the trailing PDU of a grant is a segment and the next grant's first PDU carries an SO (5-byte header), shifting the cycle. Consistent, not proof; the masks will settle it.
- **Owner-partition bug found while answering a question about core roles, and fixed.** `rlc_am_owner_idx` sized the entity->owner partition by the `CONSUMER_CORE_NUM` *build define* while dispatch follows the data header's consumer list. For `_P4_C8` on TC2 that meant stride=8 with only 2 consumers existing, so entities needing owner index 2..7 -- **36 of 48** -- had no owner: never planned, never drained, `rlc_am_idle()` never true, i.e. a **guaranteed hang**. Now sized by `RLC_ACTUAL_CONSUMERS` (the list length under core-list dispatch). Verified 0 orphaned entities across TC1 P2_C2/P2_C4 and TC2 P2_C2/P4_C8. Would have hit GVSoC as soon as they ran TC2 at C>2.
- **`vmerge.vvm` divergence recorded as the more dangerous of the two.** GVSoC implements it; Spatz decodes it and no lane executes it -- so a kernel using it **passes in simulation and silently corrupts on hardware**, the opposite failure mode to the compares' illegal-instruction trap. Warnings added next to the `_v4` CMake target and in the `rlc_plan.h` default comment; a `_v4` pass on any simulator must not be read as hardware evidence.
- **Modelling gap noted for later:** the AM execute path does not reproduce the legacy `rlc_send_pkt` "read one cacheline from the SDU, write 64 B back" traffic, so AM and legacy DRAM-traffic numbers are not directly comparable even once both are correct. To be added back deliberately rather than left to skew the first comparison.
- **Verification:** build clean, zero warnings from the new files, host planner test still 589,728 checks / 0 failures, legacy loadable image still `cmp`-identical to pristine.

---

### RLC AM: root cause -- Spatz implements no vector integer compare (RTL gap, not just GVSoC)
- **Time:** 2026-08-25 ~06:00 +0200
- **GVSoC found the trap.** Their PC trace plus decoder log: `pc 0x80000ba0, opcode 0x7a82c057, Unknown instruction, Raising exception (id: 2)` = illegal instruction on **`vmsgtu.vx`**, the first instruction of my first-crossing search. Their ISS (`isa_rvv_timed.py`, 238 vector instructions) is missing the entire vector integer compare family. So the core was never in an infinite loop -- it was wedged in snRuntime's default trap handler (`__snrt_isr` -> `jal 0,0`), which is why `plan_calls=1` with `tosend` climbing behind it, `plan_ok=0` *and* `plan_zero=0`, `zero-vl=0`, `_P1_C1` reproducing, and `_novec` passing.
- **They asked me to check whether our RTL had the same gap. It does, and worse.** The decoder accepts the family -- `VMSGTU_VX` is in the valid list (`spatz_decoder.sv:285`) and decoded to `spatz_req.op = VMSGTU` (`:593`) -- but the **datapath implements no integer compare at all**. `spatz_simd_lane.sv` covers VADC VADD VAND VDIV VDIVU VMACC VMADD VMADC VMAX VMAXU VMIN VMINU VMSBC VMUL VMULH VMULHSU VMULHU VNMSAC VNMSUB VOR VREM VREMU VRSUB VSBC VSLL VSRA VSRL VSUB VXOR; `spatz_ipu.sv` covers VDIV VMAX VMIN VMULH VMULHSU VREM. `grep -rn 'VMSEQ' hardware/deps/spatz/hw/` outside the decoder and the op enum returns **nothing**. Same for **VMERGE**, which exists only as an enum entry -- note this cuts the opposite way from GVSoC, which *has* vmerge and lacks the compares.
- **Consequence, and why this mattered:** on our hardware the sequence would **not** trap. The RTL decodes `vmsgtu.vx`, hands the VFU an op no lane implements, and the compare silently yields a wrong mask -- a wrong segment boundary in the planner with no error anywhere. GVSoC failing loudly with an illegal instruction is the better behaviour, and their question ("does your RTL accept it?") is what surfaced a genuine kernel bug that the host test cannot catch, since the host build compiles the C twins.
- **Fix:** `rlc_vec_first_gt_u32` is the only primitive using either instruction, so the default `RLC_PLAN_VECTOR` is now `MAPS|SCAN` and the first-crossing search runs on its C twin. Verified on the artifact: the default AM build emits **0 `vmsgtu`, 0 `vmerge`**, and keeps the prefix sum vectorised (2 `vslideup`, 6 `vadd`). The `_v4` target still emits them deliberately, so the search can be re-enabled on hardware that implements compares -- a knob, not a deletion. Cheap trade: the searches are short and monotonic, the prefix sum is where the work is.
- **Audited every remaining planner instruction against the Spatz datapath:** `vle32/vse32/vle8/vse8` -> VLSU; `vmv.v.i`/`vmv.v.x`/`vmv.s.x` -> VSLIDEUP; `vmv.x.s` -> VADD; `vslideup.vx`/`vslidedown.vx` -> VSLDU; `vadd`/`vsub`/`vand` -> lane; `vredminu.vs` -> VMINU with the reduction FSM. All implemented.
- **Also fixed:** a `*/` inside the new explanatory comment (`VMUL*/VDIV*`) silently terminated the block comment and broke the host build; reworded.
- **RTL gate result: `M48_N800_K300_P4_C8` TIMED OUT** -- rc=124 at the 5400 s cap, no EOC, no scoreboard output, against 59 min for the same data at 2P/2C. **The C>=8 problem is NOT fixed by upstream #27's AMO change.** Separate investigation; logs in `reports/rlc_64core_baseline_2026-08-24/logs/`.
- **Verification:** build clean, zero warnings from the new files, host planner test still 589,728 checks / 0 failures, legacy loadable image still `cmp`-identical to pristine.
- **Next:** GVSoC re-runs the default AM target, which is now free of instructions either simulator rejects; then the `verify_mask` readout on the outstanding 2-mismatch transport-block failure.

---

### RLC AM: third GVSoC round -- planner isolated to RVV, poison stall found
- **Time:** 2026-08-25 ~05:00 +0200
- **GVSoC round 3 gave a clean split.** `_novec` **opened a grant** (grants=1, 7 PDUs planned, tb_used=8192, gen=2, so_next=11) and produced the **first non-vacuous check result: transport-block check FAIL, 2 mismatches**. `_P1_C1` (one producer, one consumer, no helpers) reproduced `plan_ok=0, grants=0` exactly, and `zero-vl vsetvli events: 0` on all three. So: **the RVV planner is the fault, it is not concurrency, and it is not my `vl==0` hypothesis.** `plan_ok=0` with `plan_zero=0` and `plan_calls>0` proves by counter that `rlc_plan_compute` never returns. The pointer dump also confirmed `plan == pool0`, matching my disassembly reading.
- **Correction to what `_novec` proved.** `RLC_PLAN_VECTOR=0` was routing `rlc_plan_compute()` to `rlc_plan_compute_scalar` -- the *reference* planner -- not the scan planner with C twins. So it validated the AM plumbing and the reference planner, one step coarser than I had implied. Split the knob: `RLC_PLAN_IMPL` (0 reference / 1 scan) and `RLC_PLAN_VECTOR` as a bitmask over the scan planner's primitives. `_novec` is now explicitly `RLC_PLAN_IMPL=0`, preserving exactly what was run.
- **Diagnosed their second anomaly from the counters: `rlc_am_poison` was the stall.** `plan_ok=2` with `poison=1` and `published=1` means the second grant planned fine -- `n=7`, `tb_used=8192`, `so_next=11` are the stashes written right after `plan_ok++` -- and then never reached `poison`. The only thing between those counters is the poison call, which was filling the entire `tb_used` with **single-byte stores**: 8192 of them to DRAM per grant, slow enough to stall the owner for the rest of the run. That also explains `sent=0`/`tosend=99`. **Scoped the poison to each planned PDU's header bytes** (~35 bytes for a 7-PDU grant instead of 8192); the payload already has a byte-exact comparison in the verifier, so poisoning it was cost without coverage. Self-check-only code, so no effect on measured builds.
- **Transport-block check now names the failing field.** The per-grant `[AM-SB]` printf never appeared in their output, so the diagnosis no longer depends on it: each entity accumulates a `verify_mask` printed from the summary block, with a bit per check (tb_off, sn, si, poll, so, hdr_len, sn_seq, payload, tb_used, sn_cont, so_cont) plus **bit 11 = header still reads as the fill pattern**, which distinguishes "chunk never executed" from "chunk executed wrongly".
- **Bisect ladder built** so the RVV fault can be localised without a PC trace. Every planner primitive now independently selects its RVV form or its plain-C twin via the `RLC_PLAN_VECTOR` bitmask (1 maps / 2 prefix-sum / 4 first-crossing), verified on the artifacts -- each mask value emits exactly its own instructions and nothing else. New targets `_scanC` (all C), `_v1`, `_v2`, `_v4`.
- **Answered their `vredminu.vs` question from the RTL source:** Spatz's decoder does accept it (`spatz_decoder.sv:485`, sets `op_arith.is_reduction` with vs1/vs2 swapped) and `spatz_vfu.sv` implements a real reduction FSM (`Reduction_Init`/`Reduction_Reduce`) gated on `reduction_done` rather than the usual `vl_d >= vl`, so it is vl-driven and not a stub. Correctness at LMUL=4 with an LMUL=1 scalar operand cannot be established from source alone -- that is what the `_v4` target is for.
- **Also fixed:** `rlc_plan.c` was missing `#include <stdatomic.h>`; it only compiled because it is textually included after `rlc.c` pulls the header in. Standalone compilation of the file now works, which the bisect build needs.
- **Verification:** all five bisect/control targets build with zero warnings from the new files, host planner test still 589,728 checks / 0 failures, legacy loadable image still `cmp`-identical to pristine.

---

### RLC AM: second GVSoC round -- localising the zero-grant failure
- **Time:** 2026-08-25 ~04:10 +0200
- **GVSoC round 2 counters:** `plan_calls=1 peek_empty=0 peek_max=2 plan_zero=0 grants=0 | tosend=101 sent=0 so_next=0 gen=0` (C2_G8192 and C4_G1024; C4_G8192 showed `plan_calls=10 peek_empty=9 peek_max=1`). This **falls through all three branches** of my discriminator: not dispatch (owner ran), not producers (queue had SDUs), not the planner refusing. The break is between "planner returned n>0" and "grant opened". **The 640->128 B stack fix did not change the outcome** -- crossed off the suspect list, kept anyway.
- **`peek_max=2` vs `tosend=101` is not an under-read.** `plan_calls=1`, so the single peek happened early when only 2 SDUs were enqueued; 101 is the count at exit after production continued behind a stalled consumer. It is a timestamp, not a truncation. Worth recording because it looked like a `list_peek_n` bug at first glance.
- **NULL-plan hypothesis raised and then disproved from the disassembly.** `rlc_plan_t::sdu_node` is the *first* member, so an uninitialised `e->plan` would make `peek` exactly NULL, let `list_peek_n` write node pointers to address 0, and still return a plausible count -- reproducing the entire counter signature. Checked instead of assumed: `rlc_am_init` is inlined into `main` and does emit `lui a1,524294; addi a1,a1,-512; sw a1,-636(a0)`, i.e. `rlc_am_plan_pool` (0x80005E00) into `rlc_am_ent+4`. **`e->plan` is valid.**
- **New prime suspect: the planner never returns.** Past the `n == 0` check the path to `grants++` is straight-line with no conditions, so `grants=0` with `gen=0` most economically means `rlc_plan_compute` did not return. Every vector chunk loop has the shape `while (i < n) { vsetvli vl, n-i; ...; i += vl; }` -- **a `vl` of 0 spins forever**, which fits every observation including the C4_G8192 run dying before its check lines.
- **Added, this round:**
  - `vl == 0` guards on all 8 vector chunk loops plus `rlc_memcpy8`, counting the event and breaking out rather than hanging; new report line `[AM] zero-vl vsetvli events: N`. **My first cut of the guard was wrapped in `do{}while(0)`, where `break` escapes the wrapper rather than the caller's loop** -- it would have counted the event and spun anyway. Caught and fixed before building.
  - Bracket counters `plan_ok` / `poison_done` / `published`, plus a pointer dump (`plan`, `tb`, `pool0`, `ent`), spanning exactly the region the counters did not previously cover.
  - **`_novec` control target** (`RLC_PLAN_VECTOR=0`): same scan algorithm, RVV primitives swapped for their plain-C twins. Isolation verified on the artifact -- 0 `vslideup`/`vredminu`/`vmerge`/`vmsgtu` against 8 in the vector build. One run splits "my algorithm is wrong" from "my RVV is wrong".
  - **`_P1_C1` control target** with its own generated header (`data_1_1350_100_p1c1.h`, producers {0}, consumers {1}) -- dispatch follows the header lists and the `*_CORE_NUM` defines cannot shrink a list, so a genuine single-consumer run needed its own header. GVSoC correctly pointed out they had no C=1-vs-C>1 contrast and so could not separate concurrency from planner/copy bugs.
- **Independent confirmation of the legacy bit-exactness claim:** GVSoC re-ran their calibration anchor against the rebuilt legacy binary and got 149,248 / 149,678 / 195,098 / 195,370 -- bit-identical to before the rebuild. That validates behaviour, not just bytes, which is a stronger check than the `objcopy` comparison I had been relying on.
- **Verification:** all builds clean, zero warnings from the new files, host planner test still 589,728 checks / 0 failures, legacy loadable image still `cmp`-identical to pristine after every change above.

---

### RLC AM: first GVSoC bring-up -- zero grants opened; instrumentation + stack fix
- **Time:** 2026-08-25 ~03:20 +0200
- **GVSoC result (cachepool_gvsoc):** the AM path executes and terminates, but **opens zero grants**, so all three `[AM]` check lines pass *vacuously* -- with 0 grants the TB check has nothing to decode and the planner diff has nothing to plan. None of `rlc_memcpy8()`, the claim protocol, or the RVV planner ran, so my whole suspicion list is still untested. Their host-test run reproduced 589,728 checks / 0 failures, confirming the tree is intact. Credit to them for flagging the PASS lines as vacuous rather than reporting green.
- **Ruled out by inspection of the emitted code:** dispatch is correct -- the owner test folded to a literal `core_id == 2`, which is right given `consumer_core_ids = {2,3}` and `owner_idx(0) = 0` at `NUM_USERS == 1`. Both data headers define 2 producers {0,1} and 2 consumers {2,3}, so `PRODUCER_CORE_NUM=2` matches the list length and the consumer exit condition is satisfiable (consistent with runs terminating rather than hanging). All AM functions are present, fully inlined into an 858-line `rlc_am_step`.
- **Found and fixed a real hazard (possibly *the* bug):** `rlc_am_step` was allocating **640 bytes of stack**, because `rlc_am_try_plan` held a local `Node *peek[128]` = 512 B. snRuntime's `start.S` has its per-hart stack-offset code **commented out** and `snrt_stack_size` is 10, so headroom is not something I trust. Removed the local array entirely -- `rlc_plan_t` already owns `sdu_node[128]`, so the peek writes straight into it. **Frame 640 -> 128 bytes**, and one copy saved. A blown stack corrupting the list header or entity state would explain zero grants.
- **Instrumentation added** (owner-only writes, no atomics): per-entity `plan_calls` / `peek_empty` / `peek_max` / `plan_zero`, plus a dispatch line printing the `*_CORE_NUM` defines against the header's `NUM_*_CORES` lists, per-entity queue depths at exit, and a per-consumer "entered the loop" print. These discriminate the three candidates in a single run: owner never reached the plan attempt / queue always empty (producer-side) / planner refused SDUs it was given (my bug).
- **Noticed while checking:** the `_P2_C4` target sets `CONSUMER_CORE_NUM=4` but the data header's consumer list still has only 2 entries, and dispatch follows the **list** -- so that target actually runs 2 consumers, not 4. C2 and C4 are currently the same core count. Fix belongs in the data headers, not the defines; deferred until we know why grants=0.
- **TTI convention AGREED with the GVSoC side** (their proposal, accepted in full): primary metric is **bytes/cycle**, with **one TTI = one grant opportunity per entity**. This removes the ~1000x sim-speed gap from the comparison and neither side needs a TTI loop to produce a comparable number -- both divide `grant_bytes * grants` by kernel cycles. For a wallclock-flavoured figure, **TTI = 5,000 cycles** (1:100 scaling of 500 us at 1 GHz). Defining the TTI in microseconds was explicitly rejected: it forces one side to simulate 500k cycles per data point for no extra information. F6 will be built against this.
- **GVSoC calibration (their work, useful to us):** they anchored the model against our `reports/rlc_64core_baseline_2026-08-24` TC1 numbers and found the model was matching RTL's 10-cycle warm read-hit at the cache core's internal boundary instead of the core-observed end-to-end boundary, double-counting its own interconnect. After the fix, legacy path, same binary: fast pair 149,248 / 149,678 vs our 150,175 / 150,183 -- **0.6%**. Caveat to respect: their four cores split 2-2 (~149k vs ~195k) where ours agree within 40 cycles; that is an open model defect, so their AM cycle numbers are indicative and core-to-core spread must not be read as real. They also confirmed per-hop NoC latency = 2 cycles from our `noc_profiling/session_0` capture.
- **Verification:** build clean, zero warnings from the new files, legacy loadable image still `cmp`-identical to pristine after every change above.

---

### RLC AM: F5 -- bitmap work queue (behind a default-off knob)
- **Time:** 2026-08-25 ~02:50 +0200
- **Problem:** `rlc_am_step()` visited every entity on every step. At 1..48 entities that is tolerable, but it is O(NUM_USERS) per step per core and does not survive TC3's 4800 mostly-idle entities.
- **Fix:** two bitmaps, one bit per entity -- `ready` (has queued data, no grant open, an owner should plan it) and `active` (a grant is open, any core may help). A step walks set bits via `__builtin_ctz` and skips all-zero words whole, so its cost tracks work in flight rather than entity count. Producers call `rlc_am_mark_ready()` after enqueueing; publish sets `active`; commit clears `active` and re-arms `ready` if the entity still has queued SDUs or a segment mid-flight.
- **Lost-wakeup handling:** the owner clears the `ready` bit *before* peeking the queue, so a producer enqueueing in the window sets it again -- the notification can be repeated but never lost. And if planning yields nothing while work remains (e.g. the grant cannot hold even a header), the bit is re-armed explicitly, or the entity would stall unnoticed.
- **Deliberately defaults OFF (`RLC_AM_WORKQ=0`).** The GVSoC agent had already been handed a prompt naming specific targets; changing the code under them would have widened their debugging surface by adding a second untested lock-free structure to a path that has never executed. Separate `_wq` targets were registered instead, so the scan-free path can be *diffed* against the plain one rather than replacing it. Flip the default once the base AM path is validated.
- **Verification:** build clean, 8 AM targets (5 base + 3 wq), zero warnings from the new files. Legacy loadable image still `cmp`-identical to pristine. **Differential proof that the knob really isolates the change:** the non-wq AM binary contains **0** `amoor.w` and **0** `amoand.w` (the only instructions the bitmap set/clear emit) while the wq binary has 4 and 2, and both contain an identical 21 `amoadd.w` -- so the claim/done protocol is byte-for-byte the same and the F5 code cannot execute in the targets handed over.
- **Known limitation, recorded rather than fixed:** the `ready` bitmap is global, so an owner iterating set bits also steps over entities it does not own and skips them. Bounded by the number of *ready* entities, not by NUM_USERS, so it is a large improvement -- but at TC3 scale with many simultaneously-ready entities a per-owner structure (indexed by `u / stride`) would be exact. Deferred deliberately: building an MPSC ring on top of unexecuted code is the wrong order of work.
- **Next:** F6 TTI loop, blocked on agreeing the scaled-TTI convention with the GVSoC side (asked for a proposal in the handover); then UL.

---

### RLC AM: transport-block self-check, GVSoC handover, and F4 (real STATUS PDU)
- **Time:** 2026-08-25 ~02:15 +0200
- **Self-check (`rlc_am_verify_grant`, gated on `RLC_SELF_CHECK`).** Decodes each assembled transport block back with `rlc_amd_hdr_read()` and checks header fields against the plan that produced it, the offset each header actually landed at, SN continuity *across* grants, segment-offset continuity across grants, byte-exact payload, and that the block ends exactly at `tb_used`. The grant is poisoned with 0xA5 before publication so a chunk no core executed decodes as garbage rather than as the previous grant's leftovers. This validates the **execute** stage, which the host test structurally cannot reach -- it never runs concurrently and never touches memory. `rlc_am_report()` prints the AM summary plus the planner-diff and transport-block verdicts; wired into `cluster_entry()` in place of the legacy `self_check()`, which compares per-descriptor destinations the AM path never writes.
- **Handover to the GVSoC agent.** Prompt written to `reports/handover/PROMPT_gvsoc_rlc_am.md` and sent to session `cachepool_gvsoc [6b1de8]` (the id the user first quoted, `1dd2a36c-...`, was not in the reachable peer list). Covers build, run order, what the three `[AM]` lines mean, the three most likely failure modes (unaligned e8 copy on Spatz's VLSU is my top suspicion, then the claim-across-grant-boundary race, then an idle-spin hang), the ground rule that the legacy path must stay bit-exact, the 64-core legacy reference numbers, the missing-RVV-instruction caveat, and a request for a scaled-TTI convention proposal.
- **F4 -- real STATUS PDU (moved ahead of F5, deliberately).** In AM mode `ctx->vtNext` counts **PDUs** while `sent_list` gains one node per fully-sent **SDU**; with segmentation those diverge, so the legacy "acknowledge two nodes per pass, advance vtNextAck by two" model stops referring to sequence numbers at all. Not a crash (the pop is guarded and nodes only enter `sent_list` once every segment has gone out) but semantically meaningless in exactly the regime the new code exists to model. Replaced with: a real STATUS PDU built *and parsed back* per entity per pass (so the encode/decode cost is measured, not assumed away), ACK_SN derived from `vtNext - RLC_AM_ACK_LAG`, and SDU release by SN -- a node is freed only once its final segment is below ACK_SN.
  - `Node` gained an **AM-only** `last_sn`, stamped at commit from `plan->sn[i]` of the PDU whose `last_seg` is set. Guarded so the legacy `Node` layout -- and therefore `PAGE_SIZE` and the whole memory-pool geometry -- is untouched.
  - Added `rlc_sn_lt()` to `rlc_pdu.h`: SNs live modulo 2^18, so ordering is a half-window comparison, not `<`.
  - The commit retire loop now walks `last_seg[]` instead of counting `n - partial`, which yields the per-node SN for free.
- **Fixed a latent fragility I had introduced.** The `list_peek_n` guard read `RLC_TB_MODE == RLC_TB_MODE_AM`, but `llist.h` is pulled in via `mm.h` *before* `rlc_am.h` defines that symbolic constant -- so the guard evaluated `1 == 0` and the header declaration was silently skipped. It only linked because `llist.c` is included after `rlc_am.h`, where the constant does exist. Now spelled numerically (`RLC_TB_MODE == 1`) with a comment; `RLC_TB_MODE` itself always comes from `-D`, so every translation unit agrees regardless of include order. Same form used for the new `Node` field, where an inconsistent definition would have been far worse than a skipped declaration.
- **Verification:** `make sw config=cachepool_fpu_4g` clean, all 5 AM targets, **zero warnings from the new files** (the `llist.c:75-80` volatile-qualifier warnings are pre-existing in `list_push_back`). Host planner test still 589,728 checks / 0 failures. **Legacy loadable image still `cmp`-identical to the pristine build** after every change in this entry.
- **Still not simulated** -- that is now with the GVSoC side.
- **Next:** F5 entity work queue (replacing the O(NUM_USERS) triple scan in `rlc_am_step()`), then F6 TTI loop pending the convention agreement, then UL.

---

### RLC AM: execute stage -- owner-plans transport-block assembly
- **Time:** 2026-08-25 ~01:30 +0200
- **Model (user-approved "owner-plans"):** each entity has one owner core, given by the same static partition the legacy consumer already uses. The owner gathers, plans and publishes a grant; then *any* consumer core -- owner included -- claims chunks of that plan and executes them; the owner commits once all chunks report done. At `NUM_USERS == 1` the owner is consumer 0 and every other consumer is a helper filling the *same* transport block, which is what keeps single-entity peak rate reachable (the case Johannes' kernel cannot do, since he binds one entity to one core).
- **Files added:** `kernel/rlc_am.h`, `kernel/rlc_am.c` (305 lines).
- **Files modified:** `kernel/rlc.c` (3 gated hooks), `kernel/llist.{c,h}` (`list_peek_n`), `software/tests/CMakeLists.txt` (`add_spatz_test_rlc_am` + 5 targets).
- **Lock-free publish/claim protocol.** `gen` is odd while a grant is open; `plan`/`tb`/`n` are written before it is bumped (release) and stay stable until the grant closes. Executors claim with `atomic_fetch_add(&claim, CHUNK)`. **`n` is read *after* the claim, not before** -- if the owner closed one grant and opened the next in between, the claim landed on the new counter, so `n` must be the new one too; reading it before would let a core execute indices past the end of the new plan. Owner waits on `done >= n` (acquire) before committing.
- **`list_peek_n()` (new).** The planner must look ahead over several queued SDUs to place the grant boundary and the segment split, but must not detach them: a partially transmitted SDU has to stay at the head until its final segment goes out. Popping and re-inserting would need a `push_front` and would reorder against concurrent producers. Commit then pops exactly `n - partial` nodes to the sent list.
- **Byte-granular payload copy (`rlc_memcpy8`, e8/m8 RVV).** A protocol-accurate AMD header is **3 or 5 bytes**, so the payload inside the transport block starts at an arbitrary byte offset and the word-aligned vector copies the legacy path uses cannot be applied. The legacy path only got away with them because its placeholder header was a padded 10 bytes and every destination was slot-aligned. This is a real finding, not just an implementation detail: **protocol-accurate headers destroy the natural word alignment of the payload copy**, and it is worth measuring what that costs.
- **Dynamic claiming replaced the byte-balanced static split** I had originally proposed. The prefix sum makes a static byte-balanced partition free, but dynamic chunk claiming self-balances *and* copes with helper cores arriving late (they are also producing), which a static split cannot.
- **Two bugs caught during wiring:**
  1. First draft reused `ctx->parseindex` as the "trailing segment" flag -- it collides with `ue_status_rpt()`, which increments that field. Moved to `rlc_am_entity_t::partial`.
  2. First draft tested ownership as `me % stride`, so at `NUM_USERS == 1` **every** consumer would have believed it owned entity 0 and planned concurrently. Corrected to `rlc_am_owner_idx(u) == me`, which exactly one consumer index satisfies.
- **Verification:**
  - `make sw config=cachepool_fpu_4g` clean; all 5 AM targets build; **zero warnings from the new files**.
  - **Legacy path proven bit-exact.** The ELF md5 changes, but only `.debug_abbrev`/`.debug_info` differ -- every loadable section is identical in size, and `objcopy`-extracted loadable images of the pristine and modified builds `cmp` equal. (`list_peek_n` had to be `#if`-guarded to achieve this: emitting it unconditionally shifted every address in the legacy binary.)
  - Host planner test still 589,728 checks / 0 failures.
  - AM ELF confirmed to contain the `vle8.v`/`vse8.v` copy.
- **Not yet run in simulation.** Next: run the AM targets (starting with `RLC_PLAN_VERIFY=1` builds, which diff the vectorised planner against the scalar reference on target and count divergences) and add a TB decode self-check that reads the assembled block back with `rlc_amd_hdr_read()` to verify SN order, poll placement and byte-exact segment reassembly.
- **Open knobs:** `RLC_GRANT_BYTES` is a fixed 8192 until the TTI scheduler (F6) lands; TB arena is `0xB000_0000 + u * RLC_GRANT_BYTES`, which fits 48 entities in the 16 MiB window but **not 4800** (TC3 follow-up).

---

### 64-core baseline results (legacy path, cachepool_fpu_4g)
- **Time:** 2026-08-25 ~00:30 +0200
- `M1_N1350_K100` (TC1): EOC **182,534 cyc**, kernel **149,567 cyc**, retval=0, **128 SB PASS / 0 FAIL**, 4,884 AR/R DRAM transactions.
- `M48_N800_K300` (TC2, 2P/2C): EOC **630,820 cyc**, kernel **594,869 cyc**, retval=0, **128 SB PASS / 0 FAIL**, 11,677 AR.
- `M48_N800_K300_P4_C8` (the previously-corrupting C>=8 case) still running -- this is the gate on whether upstream #27's `amo_user_q.tile_id` fix already resolved it.
- Logs: `reports/rlc_64core_baseline_2026-08-24/logs/`.

---

### RLC AM: real PDU header, poll bit, and a vectorised grant planner (F1/F2 + plan stage)
- **Time:** 2026-08-25 ~00:40 +0200
- **Motivation:** Johannes Pfau's review of our kernel. Three criticisms conceded as correct: we build no transport block (each PDU goes to a `tgt_addr` fixed at generation time, so there is no grant, no output cursor and no in-order constraint), we never segment, and the poll counters are maintained but the P bit is never emitted. Our parallel speedup was partly obtained by assuming those problems away. His remaining point -- that payload copying is uninteresting because a real accelerator would hand a scatter-gather list to a DMA -- is right as protocol modelling but cannot be adopted wholesale on our side: **CachePool has no DMA** (`cachepool_cc.sv:192` hardwires `.Xdma(1'b0)`, `xdma: false` in the config, no `idma` instantiated in `hardware/src/`), so dropping the copy would leave the RTL model emitting essentially no payload DRAM traffic. Plan is to keep both as back-ends behind one switch.
- **Design:** confine everything genuinely serial in RLC -- SN order, cumulative poll counters, and the segment boundary that depends on the running grant fill -- to a **plan stage that touches no payload**, emitting a fully-determined descriptor per output PDU including its byte offset in the TB. The execute stage is then embarrassingly parallel: N cores take disjoint slices and write into offsets already decided. This keeps our intra-entity parallelism (which his kernel lacks -- he processes one entity on one core, so TC1 single-UE peak is unreachable for him) while adding his protocol depth.
- **Files added:**
  - `kernel/rlc_pdu.h` -- TS 38.322 §6.2.2.4 AMD PDU header (18- or 12-bit SN knob), D/C, P, SI, SO; write + read; §6.2.2.5 STATUS PDU build/parse as groundwork for replacing the hardcoded "ACK two PDUs" model. Replaces the old 10-byte placeholder header with a bare 32-bit SN at word 0.
  - `kernel/rlc_plan.h` -- struct-of-arrays plan descriptor (SoA because the planner vectorises over it and the execute phase reads contiguous slices), planner in/out state, config knobs `RLC_MAX_PDUS_PER_GRANT` (128), `RLC_PLAN_VECTOR`, `RLC_PLAN_VERIFY`.
  - `kernel/rlc_plan.c` -- two planners: `rlc_plan_compute_scalar()` (the reference/spec) and `rlc_plan_compute_vector()` (scan-based, the one used).
  - `test/test_rlc_plan.c` -- host unit test, no simulator needed.
- **Vectorisation (user request: use RVV via inline asm where it helps).** Once the queue has been walked, the plan stage is almost entirely data-parallel arithmetic: TB offsets are an inclusive prefix sum of PDU lengths; SN is base + lane; the segment boundary is the first lane whose running sum exceeds the grant; poll positions are threshold crossings of two running counters. Implemented primitives: Hillis-Steele log-scan prefix sum (`vslideup.vx` + `vadd.vv`, ceil(log2 vl) adds per chunk instead of vl scalar adds), first-crossing search, and elementwise maps. **Spatz decodes no `vid.v`, `viota.m`, `vcpop.m` or `vfirst.m`** (checked against `spatz_decoder.sv`), so lane indices come from a static iota table and first-set-lane is a masked merge against a sentinel followed by `vredminu.vs`. The poll loop runs **once per poll event, not per PDU**: the PDU-count crossing is closed-form and the byte-count crossing is one vector search.
- **Two hazards handled:** (1) Snitch's scalar LSU and Spatz's vector LSU are independent, so a scalar read can bypass an outstanding vector store -- every scalar<->vector handoff on the plan arrays is bracketed by a `fence` (what `snrt_fence()` emits; spelled out locally so the planner stays independent of snRuntime). (2) The prefix-sum carry is extracted from the vector register with `vslidedown.vx` + `vmv.x.s` rather than re-read from memory, which would have raced the store just issued.
- **Verification:**
  - Both builds clean under `-Wall -Wextra`: target (`clang --target=riscv32 -march=rv32imafvzfh_xdma_xfquarter`) and host (`gcc -DRLC_PLAN_VECTOR=0`).
  - The RVV primitives have plain-C twins with identical semantics, so the **scan algorithm itself** -- not just the reference -- runs and is tested on the host. `test/test_rlc_plan.c` drives 9 multi-grant streams (TC1-like, TC2-like, heavy segmentation, grants barely above the header, mixed sizes, poll disabled / every-PDU / bytes-only, SN wraparound), diffing the scan planner against the reference on every output field and checking structural invariants, SDU reassembly, and an independent poll model. **589,728 checks, 0 failures.**
  - Disassembly confirms only Spatz-decodable instructions are emitted: `vle32.v vse32.v vmv.v.x/v.i vmv.x.s vmv.s.x vadd.vx/vv vsub.vx/vv vand.vx vslideup.vx vslidedown.vx vredminu.vs vmsgtu.vx vmerge.vvm`.
- **Not yet wired into `rlc.c`** -- the planner is standalone until the execute stage lands, so the existing kernel and its numbers are untouched. Next: execute stage (header serialisation + `RLC_DL_EXEC={COPY,SGL}`), then `RLC_TB_MODE={LEGACY,AM}` integration, entity work queue, real STATUS PDU, TTI loop.
- **Note on TTI scaling:** a 500 us TTI at 1 GHz is 500,000 cycles and RTL sim runs ~1k cycles/s (~8 min wallclock per TTI), so the TTI must be a knob with proportionally scaled grants. Worth agreeing the convention with the GVSoC side so numbers stay comparable.
- **Follow-up:** `RLC_PLAN_VERIFY` runs both planners on target and diffs them; enable it on the first GVSoC/RTL run of the AM path to catch RVV codegen issues the host test cannot see.

---

## 2026-08-24

### Switched the work repo to the post-#27 upstream base; unblocked the 64-core build
- **Time:** 2026-08-24 ~23:15 +0200
- **Branch:** `dev/rlc-next` (5 commits on `origin/main`: `6aed315` bootrom, `fa9c66e` tile perf, `fbcafa6` rlc multiuser, `81d8139` amo fix, `2f51034` dispatch fallback fix). Upstream default config is now **`cachepool_fpu_4g` = 4 groups x 4 tiles x 4 cores = 64 cores** (was 16).
- **Also pushed:** `2f51034` cherry-picked as `c85412d` onto `feat/rlc-multiuser` (PR-2 branch).
- **Build blocker 1 (misdiagnosed at first, resolved):** `sim/work/compile.vsim.tcl` listed **two** `snitch_icache_pkg.sv` — `cluster_icache/src/` (has `icache_l1_events_t`) and `spatz/hw/ip/snitch_icache/src/` (older, compiled later, overwrote it), so upstream's `cachepool_tile.sv:19` `import snitch_icache_pkg::icache_l1_events_t;` failed. **Not an upstream bug:** spatz already gates its icache behind `target: not(cachepool)` and the Makefile already passes `-t cachepool`; the compile script was simply **stale**, generated while spatz was still at the pre-sync revision that lacked that guard. `make clean.vsim && make vsim` regenerates it correctly (verified: `bender script vsim -t cachepool ...` yields 0 spatz-icache files, 8 without). **No dependency or upstream change was needed** — the earlier hand-editing plan was dropped.
- **Build blocker 2 (real, fixed):** `hardware/tb/tb_cachepool.sv` carries our module-scope `bind cachepool_cache_ctrl cachepool_cache_ctrl_req_tracer` (trace-capture pipeline), but upstream's `Bender.yml` replaced ours and does not list the tracer source -> 64 elaboration errors, `Module 'cachepool_cache_ctrl_req_tracer' is not defined`. **Fix:** added `hardware/src/verif/cachepool_cache_ctrl_req_tracer.sv` to the existing `target: simulation` verif group in `Bender.yml`, next to `cachepool_tile_tcdm_checker.sv`.
- **Files touched:** `Bender.yml` (+1 line). Uncommitted local deltas also present: `Bender.local`, `Makefile` (`CC :=` / `CXX :=` — must stay `:=`, `?=` cannot override make's built-in `CC = cc` and breaks fesvr), `hardware/tb/tb_cachepool.sv`, `software/tests/CMakeLists.txt`.
- **Verification:** `make vsim config=cachepool_fpu_4g` exit 0; `make sw config=cachepool_fpu_4g` exit 0 (all RLC ELFs incl. TC2 `_M48_N800_K300` and the `_P*_C*` sweep variants). 64-core RLC re-baseline running -> `reports/rlc_64core_baseline_2026-08-24/`.
- **Follow-ups:** re-baseline TC1/TC2 numbers into the PR-2 description (currently says "not yet re-simulated on this base"); re-test whether the C>=8 RLC corruption is already fixed by upstream #27's `amo_user_q.tile_id` fix on the regular-AMO response path; consider upstreaming the `CC :=` Makefile fix.

---

## 2026-08-24 (earlier)

### LR/SC atomicity + forward-progress defects in spatz_cache_amo (partially fixed)
- **Time:** 2026-08-24 ~19:30 +0200
- **Trigger:** Johannes Pfau's `rlc_am/doc/RLC_HW.md` ask #6 reported that any core's LR steals the AMO unit's reservation (`spatz_cache_amo.sv:166`). **Verified true** — the guard is commented out in our RTL. The AMO unit is per L1 cache controller (`cachepool_tile.sv` `gen_cache_connect`), i.e. home-side and shared by all tiles.
- **New reproducer:** `software/tests/lrsc-forward-progress/` — 16 cores, symmetric CAS-increment retry loop on one word. Original RTL: 12/16 (1 iter), 22/32 (2 iter), **no completion in 900 s** at 8+ iterations.
- **Fixed (defect 1):** keep the incumbent reservation + **aging** (`ResvTimeoutCycles`, default 1024) so the LR-without-SC case that motivated disabling the guard stays bounded.
- **Fixed (defect 2), found while verifying:** `core_id` is only 2 bits and **per-tile** (`CoreIDWidth = idx_width(NumCoresTile)`), but the AMO unit serves every tile — so `{t0,c2}` and `{t1,c2}` aliased in three places (reservation ownership, foreign-write invalidation, SC response match). One tile's core could satisfy or take delivery of another tile's SC: an **atomicity** violation, not just fairness. Reservation now keys on `{tile_id, core_id}`; `TileIDWidth` plumbed from the tile.
- **Fixed (defect 3):** single-entry SC tracking (`sc_q`/`sc_user_q`/`sc_successful_q`). An SC response that did not match the tracked entry returned **raw memory data** to the core; `sc.w` reads rd=0 as success, so a zero word there = silent lost update. Trace evidence: **59 SCs accepted, only 35 responses matched, 4 unmatched with data=0**. Fix (user-approved): `tcdm_user_t` gained `is_sc`/`sc_fail`; the AMO unit stamps the outcome at issue and the response decodes its own status, so the single-entry registers and the SC-acceptance serialization are both gone (no throughput restriction). Works because the InSitu IP carries meta as a parameterized opaque type — no IP change needed.
- **Result:** test **PASSES** — 32/32 (2 iter) and **256/256 (16 iter, 1489 retries, 25,778 cyc)**; previously 8 iter would not finish in 900 s. Convoy gone: 8x work costs ~1.4x cycles.
- **Regression, all green:** RLC `M1_N1350_K100` = **241,339 cyc, retval=0, 32/32 SB PASS (identical to pre-fix baseline)**; spin-lock, byte-enable, cache-coverage-min, v12-race all PASS; mcs-lock progresses far better than before (54 critical sections in 600 s vs 4) — long-running by design, not a CI test.
- **Also noted:** on a CAS value-mismatch the core skips its `sc.w`, so reservations are released only by the aging timer (timeout is load-bearing; 1024 cyc causes convoying under contention). `req_id` is 0 on all AMO traffic. `InstructionInterfaceStable` asserts fire on this test (8x, not investigated).
- **Build gotcha re-confirmed:** `make vsim` does **not** recompile edited `hardware/src` — the first three runs silently used the old RTL. `make clean.vsim && make vsim` is required; check the build log greps for the edited file.
- **Artifacts:** `reports/amo_lrsc_fix_2026-08-24/` (FINDINGS.md, before/after/AMO_DEBUG logs, original file). Changed: `hardware/src/{spatz_cache_amo.sv,cachepool_tile.sv,cachepool_pkg.sv}` + new `software/tests/lrsc-forward-progress/` (registered). **Uncommitted, pending review.** An `AMO_DEBUG`-gated trace block remains in the AMO unit (off by default).

## 2026-08-10

### External PRs merged (validated), multi-group-first sequencing
- **Time:** 2026-08-10 ~17:55 +0200
- **PR pulp-platform/ManyRVData#25** ("Don't hardcode ETH toolchain for bootrom compilation", jpf-h): FF-merged into `fix/cache-refill-throughput` → HEAD `32ed552`. Verified: `install/riscv-gcc` provides `riscv32-unknown-elf-*` (gcc 7.1.1); bootrom rebuilds via the new rule (116 B vs 136 B with the old 9.5.0 module — gcc-version codegen delta, same function); vsim rebuilt + RLC K100 smoke run **clean (EOC 241,339, retval=0, 32/32 SB PASS)**. User's dirty Makefile preserved (stash/pop; their hunks at L16/L288 don't overlap).
- **PR Aquaticfuller/gvsoc#1** (https submodule URLs): merged into local GVSoC `main` (merge commit `f511d7d`). Trivial, safe for ssh users via the insteadOf note in the PR body.
- **Both are local until the user pushes** (pushing either marks the GitHub PRs merged).
- **Sequencing decision (user):** ~~multi-group first~~ → **final (2026-08-10): functional scope first** — UL processing + control/scheduling algorithm (Step 1, other side leads, we spec/review/integrate) BEFORE performance-side features (near-data, DMA stub, TTI placement), because functional content defines the benchmark and both kernels must share it for the A/B comparison. Multi-group GVSoC validation = parallel track (Step 2; gates scaling studies, not functional work). Handover doc §3 updated to this order.

### RLC kernel handover doc + email replies (Johannes Pfau thread)
- **Time:** 2026-08-10 ~17:30 +0200
- **What:** (1) Answered Huawei-side questions on what was spec'd vs. our choice in the RLC kernel (drafts in `reports/email/`, incl. trimmed inline reply + GVSoC `Couldn't find component ... remote_xbar` diagnosis: components are compiled per-topology at GVSoC build time; his single-tile install lacks the multi-tile component → rebuild with `CACHEPOOL_NB_TILE=4 ...` env set). (2) Wrote **handover doc for the GVSoC-side agent**: `software/tests/multi_producer_single_consumer_double_linked_list/doc/HANDOVER_GVSoC_AGENT.md` — repos/paths, verified state table, next-step plan with rationale (P0 C≥8 corruption root-cause, P1 baseline numbers, P2 near-data/TTI enablement + GVSoC DMA stub, P3 deferred TC3/UL), detailed kernel build instructions (make sw / incremental / variants / generator / defines), GVSoC build+run incl. the topology pitfall, and the C≥8 debug dossier.
- **Note:** earlier run logs + the captured waveform were under `/tmp/pr12_runs/` and are **lost** (/tmp cleaned); all key numbers are preserved in this worklog + `doc/MULTI_USER_EXTENSION_REPORT.md`. Waveform capture recipe is documented in the handover doc if regeneration is needed.

## 2026-07-27

### Rebase PR #12 ("adjust consumer and producer", RLC kernel) onto current main
- **Time:** 2026-07-27 ~17:45 +0200
- **Request:** check PR pulp-platform/ManyRVData#12 + all comments; rebase it onto the current RLC kernel (`software/tests/multi_producer_single_consumer_double_linked_list`).
- **PR state:** open, `mergeable=False`; head = fork `zouguoqi/ManyRVData@testbranch` `9760ae8fe4` (4 commits, touches only `kernel/rlc.c` +260/−131 and `kernel/rlc.h` +53/−6); base c8c7cd18 (Jan-26). `origin/pr-12` is stale (e9b832cf, missing the last commit; branch deleted upstream).
- **Review threads (Aquaticfuller → zouguoqi, translated):** (T1) make traffic-modeling globals `dlsch_ind`/`ue_status_rpt_content` `volatile` — author agreed; (T2) `dfx` write-only = intentional traffic modeling, no change; (T3) `firstSduPktRxCycle` naming inaccurate — author agreed; (T4) `pktdelay`/`pdcpcount`/`rlcOm[]` multi-writer → atomic for multi-consumer — author: "can change to atomic" (deferred, see below).
- **Rebase (in scratch worktree `/tmp/pr12_rebase`, branch `rebase/pr-12-rlc`):** 4 commits replayed onto `origin/main` (b63e969). Conflicts at 3 of 4 stops:
  - `rlc.h`: union — kept main-side `_Atomic` on `pduWithoutPoll`/`byteWithoutPoll`/`vtNext`, added all PR fields incl. PR's own `_Atomic` additions (sduNum/sduBytes/tbsize/rlcthrp/dlPduNum/…).
  - `rlc.c`: consumer body → PR's `rlc_send_pkt()` extraction; ported main-side relaxed atomics into it (`sn = atomic_fetch_add(&vtNext)` as memcpy header + relaxed `pduWithoutPoll`/`byteWithoutPoll`); dispatch resolved to PR's final configurable form (`core_id < PRODUCER_CORE_NUM` → `pkt_production_and_recycle`, next `CONSUMER_CORE_NUM` → `consumer`, spares fall through; defaults 2P+2C). **Semantics note:** this supersedes main's `core_id < 2 → consumer` inversion from f5c3ef4 (both give 2 consumers; PR adds rate-pacing + spare cores).
  - Mishap recovered: one `git add -A` staged unresolved markers into intermediate commits → aborted and redid the rebase cleanly (resolutions recovered from tagged partial branch `pr12_partial`).
- **Review-fix commits on top:** `82d5a91` volatile globals (T1), `698f68a` rename `firstSduPktRxCycle`→`latestSduPktRxCycle` (T3). T4 deferred (default 2P+2C already has 2 consumer writers — reported as follow-up decision for user).
- **Verification:** `git diff 9760ae8 rebase/pr-12-rlc` on the kernel dir = exactly the main-side delta (release fences, atomics, set_eoc removal) + review fixes; `rlc.c` and `main.c` compile with the production toolchain flags (`install/llvm clang -mcpu=snitch -march=rv32imafvzfh_xdma_xfquarter`, only pre-existing warnings). Intermediate commits 1–3 faithfully keep the PR's own compile bugs (fixed by its commit 4 — `end_timecycle` typo etc.). Adversarial 13-agent review (fidelity/accounting/review-coverage/concurrency + refute-pass): **fidelity clean (0 unattributable hunks); T1/T3 verified correct**; all race claims refuted as pre-existing + benign dead-stats (write-only fields: sendPduNum/sendPduBytes/pdcpcount/pktdelay/rlcOm/lastRcvOrSubmitDataCyc; acksn/nackcount/parseindex/dlDelayInfo single-writer on core 0). **One pre-existing PR bug surfaced (NOT rebase-introduced, not fixed):** rate-pacing `PRODUCER_CORE_NUM * PDU_SIZE * CPU_FREQENCY / {INPUT,OUTPUT}_DATARATE` = 2·1360·1e9 overflows signed 32-bit int → wraps to 1285701632 → `total_cycle` = 183 instead of 388571 ⇒ pacing effectively disabled (`delayCycle`≈0) at `rlc.c:361` and `rlc.c:490` (present identically in 9760ae8). Fixing (64-bit literal) would actually engage pacing and change benchmark behavior — user decision.
- **Branches (local only, NOT pushed):** `rebase/pr-12-rlc` (deliverable, 6 commits on b63e969), `pr-12-orig` (original PR head for reference), `pr12_partial` (scratch, deletable). Worktree `/tmp/pr12_rebase`.
- **Follow-ups:** T4 atomics decision (`pktdelay`/`pdcpcount`/`sendPduNum`/`sendPduBytes` racy with 2 consumers); run the rebased kernel in RTL sim; push branch + update PR.

### RTL verification of the rebased RLC kernel (cachepool_fpu_512, 16c/4t)
- **Time:** 2026-07-27 ~18:50 +0200
- **Setup:** main repo restored from single-tile state to `config=cachepool_fpu_512` (`make clean && generate && bootrom && vsim` — fresh 16c/4t build, rp1 per current local config). Rebased-kernel ELFs built from the worktree (`/tmp/pr12_rebase/software/build`) via cmake pointing at the main toolchain/deps; baseline (pre-PR, current-main) kernel ELF from the main repo's own `make vsim` sw build.
- **Rebased kernel (`rebase/pr-12-rlc`, K100):** EOC @ **241.344 µs**, **retval=0**, **32/32 scoreboards PASS** (16 cache SB + 16 coalescer SB), **0 MISMATCH**, 0 errors. Wall 3:49. → **PASS (eoc_clean)**.
- **Baseline (current main kernel, same vsim):** EOC @ 161.731 µs, retval=0, 32/0/0. Wall 2:52. → PASS. (Different shape: 2C+14P, no pacing/stats traffic; cycle delta expected, not a regression signal.)
- **K-variant quirk (pre-existing PR issue, NOT fixed):** `rlc.c` hard-includes `../data/data_1_1350_100.h`, so the K10/K100/K300 cmake variants are **byte-identical ELFs** (md5-verified) — the `DATAHEADER` define has no effect. Ran K10/K300 anyway (same 241.344 µs EOC, clean); variant parameterization is currently a no-op.
- **Logs:** `/tmp/pr12_runs/{rebased_K100,baseline_K100,rebased_K10,rebased_K300}.log`.
- **Note:** integrated sim build state is back to 16-core `cachepool_fpu_512`.

### Multi-user RLC kernel extension (TC2 48-UE) + commit d172ae5
- **Time:** 2026-07-27/28 (design + implementation + verification; commit 2026-07-28 ~01:00 +0200)
- **Commit `d172ae5` "rlc: multi-user RLC kernel with use-case switching"** — 11 files: kernel/{rlc.c,rlc.h,llist.h,mm.h}, main.c, generator + 2 JSONs + 2 TC2 data headers, tests/CMakeLists.txt.
- **Design (plan-approved):** `rlc_ctx[NUM_USERS]` (header-driven `ACTIVE_USER_NUMBER`, 64B-aligned), per-user locks/SN/ACK; producer routes by descriptor `user_id`; consumer static partition `{u : u % min(C,N) == c % min(C,N)}` (N=1 ⇒ exact TC1); ue_status_rpt per-entity loop (core 0); pacing overflow fixed behind `RLC_ENABLE_PACING=0` default (legacy expr verbatim ⇒ TC1 bit-parity); 810 B PDU alignment solved generator-side (`PDU_STRIDE`=812); use-case = compile-time data header via threeParam idiom + `_P/C` sweep macro.
- **Prerequisite fix:** `rlc.c`'s hard `#include "../data/data_1_1350_100.h"` shadowed `DATAHEADER` for every variant (K10/K100/K300 ELFs were byte-identical!); moved `DATAHEADER` before kernel includes, dropped 5 dead `add_library` targets.
- **Verification (cachepool_fpu_512):** Phase-0 gate EOC exactly 241,344 (code-identical). Post-refactor **TC1 regression 241,905 EOC / 130,828 region (+0.23% / +1.8%)**; K-variants now genuinely distinct. **TC2 clean at 2P2C (K300: 651,553; K1000: 1,872,345) and 4P4C (438,205)**. Single-user clean at ALL core counts (2P8C 524,537; 4P8C 328,572) ⇒ consumer-partition logic exonerated.
- **OPEN BUG (documented in commit msg):** TC2 with C≥8 corrupts memory — 2P4C/2P8C: 1 SB violation each (wild accesses 0xC80008f0 / 0x38000930); 4P8C: catastrophic (wild stores, text corruption → illegal instruction, deadlock). Node/descriptor guard fired 0× (node lifecycle exonerated); dup_push SB prints = pre-existing noise class (also in pre-PR kernel); probability ∝ consumer count; waveform of failing core captured (`/tmp/pr12_runs/capture_p4c8.fst`, first 60 µs) — root cause not yet found.
- **Also:** `v12-race` CMake line intentionally left unstaged (separate change); `doc/` left untracked (Huawei docx is internal-use-only — do not commit).

### Merge rebase/pr-12-rlc into fix/cache-refill-throughput
- **Time:** 2026-07-27 ~19:05 +0200 (user chose full merge over cherry-pick)
- **What:** `git merge rebase/pr-12-rlc --no-edit` on `fix/cache-refill-throughput` → merge commit **3a217de**. Brings the 6 RLC commits + b63e969 (partial-barrier PR #21 from main — branch was missing it; user OK'd).
- **Dirty-tree handling:** two overlaps with the user's dirty files — `config/cachepool.hjson` (generated; re-created via `make generate config=cachepool_fpu_512` post-merge) and `software/tests/CMakeLists.txt` (user's `v12-race` line vs incoming `partial_barrier` lines — disjoint hunks, stash-pop applied cleanly; both present now). All other dirty files untouched; nothing staged (restored pre-merge unstaged-dirty state). Temp stash dropped; user's older stashes untouched.
- **Verification:** kernel `rlc.c/rlc.h` byte-identical to `rebase/pr-12-rlc` (diff = 0); no unresolved conflicts.

### Post-merge RTL re-run of the merged RLC kernel (cachepool_fpu_512)
- **Time:** 2026-07-27 ~19:20 +0200
- **What:** rebuilt vsim + software on the merged branch (partial-barrier RTL now in), ran the merged RLC kernel (`software/tests/multi_producer_single_consumer_double_linked_list`, K100 = the only effective variant).
- **Correctness:** EOC @ **241344000 ps, retval=0, 32/32 SB PASS, 0 MISMATCH, 0 errors** — **cycle-identical** to the pre-merge rebased run (241.344 µs): partial-barrier merge is perf/function-neutral for this kernel (it uses the classic full barrier). Baseline old kernel for reference: 161.731 µs (different shape 2C+14P, no stats traffic).
- **Performance (241,344 cycles @ 1 GHz for 100 PDUs × 1360 B, pacing disabled by the int32-overflow bug ⇒ flat-out):** ≈2,413 cyc/PDU; payload copy throughput ≈0.56 GB/s (136 KB). L1 aggregate across 16 ctrls: **44,145 hits / 17,358 misses → 28.2% miss rate** (busiest ctrl 10,418 hits; idlest 877 — spares). **Forwarding buffer (64 data banks): RD hit-rate 72.0%** (67,091/93,190 served from flops, SRAM read suppressed), **WR absorb-rate 65.7%** (60,645/92,305 merged in flops), 40,284 lazy writebacks — direct evidence for the FB benefit questions (BW31/32). DRAMSys: 4 channels ≈ **30.6 Gb/s aggregate avg** (~3.8 GB/s refill+writeback traffic ≈ 6.8× payload amplification: list nodes, headers, status-rpt reads, stack, writebacks).
- **Log:** `/tmp/pr12_runs/merged_K100.log`.

## 2026-06-16

### RTL reference data for GVSoC closed-loop validation (single-tile + 16-core)
- **Time:** 2026-06-16 ~00:30 +0200
- **Request:** `ManyRVData_GVSoC/gvsoc/prompt/rtl_reference_request_2026-06-15.md` — single-tile (4-core) RTL reference cycle counts + cache stats for closed-loop GVSoC cache-model validation. **Data-collection only; no source modified** (used `config=cachepool_1t spatz_fpu_en=1 spatz_num_fpu=4` make overrides; the req-tracer bind was already present).
- **Config run:** NumTiles=1/NumCores=4/FPU/Burst=4 (cachepool_1t is non-FPU, so FPU overridden to run the FP kernels). Confirmed geometry: 512b line, 4-way, 1024 entries/ctrl, folded+hash+fwd, write-back, all-shared; dynamic_offset reset 14 but kernels reprogram (fmatmul/fft→6, fdotp/gemv→runtime). **No L2 cache — refills go to DRAMSys DDR4-1866** (the closed-loop cycle counts reflect DRAMSys, not the open-loop fixed MemLatency=50).
- **§D single-tile (retval=0, all replays SB PASS):** idotp_M8192, fmatmul_M32, fft_M1024_N4, fdotp_M8192, gemv_M512 — region/total/eoc cycles + cache hits/misses + rd/wr + refills/writebacks (3 granularities labeled: pre-coalescer ports, post-coalescer cache events, MSHR-merged refills). Also produced single-tile per-controller traces + per-access RTL CSVs (matching the GVSoC single-tile model). fmatmul M128 omitted (infeasible to EOC at RTL speed). vfadd not in suite → idotp smoke substitute.
- **§B 16-core totals** extracted from existing replay_batch_2026-06-12 capture logs (no new run): per-kernel region/total/eoc cycles + summed hits/misses.
- **Deliverables (for GVSoC handoff):** `reports/cache_calib/rtl_ref_1t_2026-06-16/` — `RTL_REFERENCE_2026-06-16.md` (full reply to §A–§E), `SINGLE_TILE_RESULTS.csv`, per-kernel `traces/` + `peraccess/` + logs. ELF md5s recorded (fmatmul/gemv/fdotp byte-identical to 16-core build; fft single-tile=N4). Scripts: `reports/cache_calib/rtl_ref_1t_2026-06-16/{build_1t,run_1t}.sh`.
- **NOTE:** the integrated sim build state is now SINGLE-TILE (was 16-core cachepool_fpu_512); to restore, `make generate/bootrom/sw/vsim config=<desired>`.

## 2026-06-12

### Trace dataset — 5 kernels × all-16-controller replay (GVSoC-alignment dataset)
- **Time:** 2026-06-13 ~15:10 +0200
- **What:** Captured per-controller cache traces for 5 real kernels and replayed EVERY controller through the single-controller perf TB; assembled a provenance-complete dataset for GVSoC alignment. Driver `util/cache_calib/trace_batch.sh` (capture → clean `t<T>c<C>` naming → replay all 16 → combined `replay_all.csv` + per-access CSVs); summary `util/cache_calib/dataset_summary.py`.
- **Kernels (config cachepool_fpu_512, 16c/4t, Burst=4; DUT IP 93d1c11):** fmatmul-32b_M32 (full), gemv-opt_M512_N128_K32 (full), fft-32b_M1024_N16 (full), fdotp-32b_M8192 (full), fmatmul-32b_M128 (**PARTIAL** — see below). MemLatency=50.
- **Result:** all **80 controller-replays SB PASS (0 fails)**. Cross-kernel: fdotp M8192 memory/latency-bound (mean 109 cy); gemv M512 cache-active (4194 refills, mean 35 cy); fft / fmatmul M32 mostly-hit (~10 cy). `data_err==unaligned_rd` on every controller (self-check artifact; cache correct).
- **fmatmul M128 PARTIAL:** full capture infeasible — RTL sim ~2.7 µs/min, EOC ~3.6 ms ⇒ ~22 h. Captured startup window (~46 µs, ~32k acc/ctrl). Valid for RTL↔GVSoC alignment (same trace both sides); not full-kernel-representative. Marked in `.../fmatmul-32b_M128.../PARTIAL_CAPTURE.txt` + replay_all.csv header. Full large-matmul = run M64 or overnight, or build without ENABLE_SPATZ_REQ_SCOREBOARD.
- **Provenance recorded** (DATASET.md): RTL/IP commits, ELF md5s, instrumented-file md5s, full config param set, trace format + delay semantics, replay knobs.
- **Deliverables:** `reports/cache_calib/replay_batch_2026-06-12/` — `DATASET.md` + per-kernel `traces/` (16), `peraccess/` (16 per-access RTL CSVs = GVSoC diff targets), `replay_all.csv`, logs. Tooling: `util/cache_calib/{trace_batch.sh,dataset_summary.py}`.

### Real-kernel trace capture → single-controller replay (GVSoC-alignment vehicle)
- **Time:** 2026-06-12 ~17:30 +0200
- **What:** Built a capture→replay pipeline so real-kernel cache traffic can drive the standalone perf TB (and later GVSoC) in the shared `port,rw,addr,size,delay` interchange format.
  - **New RTL/verif:** `hardware/src/verif/cachepool_cache_ctrl_req_tracer.sv` — taps `cachepool_cache_ctrl.core_req_*`, writes one trace file per controller (`+reqtrace=<base>`); `delay` = idle valid-low cycles since last accept (excludes backpressure). `bind` placed at **module scope in `hardware/tb/tb_cachepool.sv`** (a `$unit`-scope bind does NOT elaborate in Questa — vlog-2650; `-mfcu` alone insufficient). `Bender.yml`: tracer added to `simulation` target.
  - **New tooling:** `util/cache_calib/trace_select.py` (rank 16 controller traces, pick busiest/by-name); `reports/cache_calib/capture_2026-06-12/{build_integrated,capture_and_replay}.sh`.
- **Key fact (verified):** `core_req_addr_i` is the interco-ROTATED (controller-view) address; the standalone TB has no interco, so captured traces replay verbatim — no inverse rotation — provided capture config == replay config.
- **Run:** clean-built integrated `cachepool_fpu_512` (16c/4t, Burst=4) WITH the tracer; ran `fmatmul-32b_M32_N32_K32`; captured all **16 controllers** in one run. Replayed busiest (tile3/ctrl1, 3037 accesses) through the perf TB (separate work lib `work_capture` to avoid the user's open GUI calib sims). SB PASS + COAL-SB PASS.
- **Result:** MemLatency sweep 10→200 moves total cycles only +1.4% (52234→52960); 14 misses, controller idle ~98% ⇒ **fmatmul M32 is compute-bound / L1-latency-insensitive on one controller**. Reads avg 10.7 cyc, writes 4.2. `data_err=249` = exactly the 249 non-word-aligned reads (self-describing-check artifact; cache correct, SB PASS).
- **Deliverables:** `reports/cache_calib/capture_2026-06-12/CAPTURE_REPORT.md` (+ traces, replay CSVs, logs, scripts).
- **Next:** feed the trace to GVSoC, diff per-access latency; replay a cache-bound kernel (fft / fmatmul M128) for miss-heavy coverage; optional `+trace_no_datacheck` plusarg.
- **Build gotchas recorded:** `make vsim` skips recompiling edited TB/verif sources (force via `make clean.vsim`); a patched launcher copy must stay in `sim/bin/` so its `$0`-relative ROOT_DIR resolves.

### Cache calib TB re-run on latest RTL — perf results + report (GVSoC-alignment prep)
- **Time:** 2026-06-12 ~16:49 +0200
- **What:** Re-ran the standalone InsituCache performance-calibration TB (`tb_cachepool_cache_ctrl_perf`, DUT `cachepool_cache_ctrl`) on config `cachepool_512` against the **current** RTL (`working_dir/insitu-cache` @ `93d1c11` = committed L1 timing-opt batch + synth-compat). Regenerated Spatz sources for cachepool_512, clean recompile (0 errors), MemLatency sweep {10,50,100,200}.
- **Config:** Burst=1 regime (`refill_data_width=512`), NumPorts=5, 512b line, 4-way, BankFactor=2, folded+hash-way+fwd-buf, REMOTE_PORT_PER_CORE=1.
- **Correctness:** all 4 runs `[SB] PASS` + `[COAL-SB] PASS`, `data_err=0`, zero MISMATCH/Error.
- **Regression:** **cycle-identical to the Jun-3 `char_bl1/` baseline across all 20 phases × all 4 latencies (0 mismatches)** ⇒ the committed timing-opt batch is performance-neutral on the perf TB too (corroborates the CI-gate + full-sweep result).
- **Headline numbers:** warm hit 10 cyc isolated / 7 streaming (mem-indep); cold-miss latency = MemLatency+13; cold-miss throughput ≈0.247 acc/cyc bank-bound at low L (L10≡L50), latency/budget-bound at L≥100 (crossover ~115); hit BW 0.62/0.76/0.83/0.865 (1→4 ports, sub-linear); coal-warm 4-port 3.28 acc/cyc. New per-cycle profiler columns (`pb_*`) directly show the bank-bound→latency-bound shift (stall_other→idle) and `stall_refill=0` (Burst=1 bypasses the serialization gate).
- **Deliverables:** `reports/cache_calib/run_2026-06-12/REPORT.md` (full), `lat{10,50,100,200}.csv`, `run_lat*.log`, `compile.log`, `sweep.sh`.
- **Next:** GVSoC-side alignment — generate shared traces (`TRACE_OUT=`) and diff per-access latency vs the GVSoC model (`CALIB_IMPLEMENTATION.md` + `TRACE_SPEC.md`).

### CHECKPOINT — backend timing parked (CTS running, multi-day); pivot to GVSoC perf alignment
- **Time:** 2026-06-12 ~10:00 +0200
- Wrote `reports/CHECKPOINT_backend_timing_2026-06-12.md` — self-contained handoff: git versions (main `e0511fa`, IP `working_dir/insitu-cache` `93d1c11` clean + pushed to origin/zexin/sync-flush-fixes, hardware/deps files = 93d1c11 content), the full RTL timing-opt arc, verification (CI-gate + 4-config sweep all clean), placement result (WNS −0.245→−0.243 flat but TNS −48%/NVP −61%), the skew decomposition (−0.243 = −0.146 pre-CTS clock-skew artifact + −0.097 datapath excess), the CTS-first decision + post-CTS resume checklist, deferred levers (#2 sel_flush compute-ahead, SRAM width-split), reports index.
- **Next (per user):** CTS takes several days; meanwhile pivot to **GVSoC performance-model alignment** (separate topic). Resume backend timing from the CHECKPOINT file when post-CTS `timing_max.rpt` is ready.

## 2026-06-11

### Post-fix re-synth/placement measurement + worst-path analysis (report)
- **Time:** 2026-06-11 ~16:00 +0200
- **Input:** new placement run `cachepool_cluster_wrapper_1.00_4t16c-folded_20260609_171543/07d_placement/timing_max.rpt` (post Option X + decoder flatten + T1.1-T2.2 batch), vs pre-fix `reports/timing_max.rpt`.
- **Result (binding corner ssgnp 0.675V −40c):** WNS −0.245 → **−0.243** (+0.002). The RTL batch DID cut the targeted logic — on the identical genblk1_3 instance the old `dec_is_hit_pend → enc_mod_mask` route is no longer the worst route to the meta-write clock-gate — but the datapath win was offset by a tighter required time (clock-network) on the now-binding path. (125c: −0.208 → −0.194.)
- **Worst path now:** single-cycle meta read-modify-write (genblk1_3 meta-SRAM read → genblk1_6 meta-bank write clock-gate). Decomp: SRAM read 0.268 (33%), decode+encode+write-mask cloud 0.562 (69%, incl. the `bank_read_cache_addr`/`bank_read_sel_flush` region), data-we → skewed-fold grant (`any_other_write_in_col`) → meta-write back-third 0.226. **Endpoint has −0.146 ns negative clock skew (capture −0.388 vs launch −0.242, IDEAL clock / pre-CTS).**
- **Verdict:** logic depth no longer the lone limiter; path is now co-limited by the SRAM-read floor + the negative clock skew. **#1 lever = CTS useful-skew on the meta-write clock-gate (~0.10-0.15, physical, no RTL, likely closes most of −0.243); #2 = the deferred bank_read_sel_flush addr compute-ahead RTL lever (on-path, ~0.02-0.04).** Full analysis: `reports/worst_path_placement_2026-06-09_analysis.md`.
- **Skew probe (skew_probe.tcl → skew_probe_out/, report `reports/skew_analysis_2026-06-11.md`):** clock is IDEAL/pre-CTS (clk_i = 47845-fanout net, 0 propagated skew). The −0.146ns "skew" = per-pin ideal-clock OFFSETS (launch SRAM CLK −0.242, capture write-clock-gate CP −0.388), part of a −0.055…−0.388 spread across IDENTICAL meta-bank macros → an un-balanced estimate, not physical. **Decomposition: WNS −0.243 = −0.146 (pre-CTS clock-skew artifact, CTS balancing removes it for ALL 23/256 paths, free) + −0.097 (genuine datapath excess: 1.056ns logic+SRAM in 1.0ns period).** ⇒ Run CTS + re-measure (skew term should collapse); residual −0.097 closes with useful-skew + deferred-#2/SRAM-width RTL (~0.07) or pipeline. **RTL work essentially complete for this path; the dominant term is CTS's to fix.**

## 2026-06-09

### RTL timing-opt batch (7 fixes) — IMPLEMENTED, CI-gated, full-sweep-verified, COMMITTED
- **Time:** 2026-06-09 ~04:00 +0200
- **What:** Implemented the 7 vetted behaviour-preserving / zero-latency RTL timing restructurings from `reports/rtl_timing_opt_plan.md`, one at a time, each gated on the CI suite before commit. Report: `reports/rtl_timing_opt_impl_report.md`.
- **Per-fix gate:** `configs-ci.sh` (cachepool_fpu_512, 8 kernels); each fix must keep all 8 PASS with EOC + UART/cycles **byte-identical** to baseline (driver `/tmp/timingopt/gate.sh` + `compare.sh`). All 7 passed cycle-identical.
- **Commits — IP (`working_dir/insitu-cache`, zexin/sync-flush-fixes):** `0d6caba` selflush-flatten-cse (bank_read_sel_flush = sync_block_install|~proc_read_valid); `56cb49a` waymask-cascade-flatten (drop redundant refill_full_read_req arm); `126e0e1` metaskip per-way &mask precompute (mask_all_ones[dec_way]); `db854cc` decoder status raw-bit decode (s1/s0+XOR, all_pend=s1, +enum assert); `3e76dd2` wrfullhit drop redundant has_wr_data; `e5a16e0` wordwriteen drop redundant write_has_data. **main:** `5388e30` cachepool_tile bank_we/bank_req direct OR-reduce; `4b696b3` Bender.lock → e5a16e0 (Git source; worktree keeps Path override unstaged).
- **Full 4-config sweep (2t/4t × rp1/rp2, 37 tests each):** vs Option X baseline (sweep_optionX_2026-06-06) — **0 new sb_violations; every eoc_clean test cycle-byte-identical EOC on all 4 configs.** gemv-opt_M256 sb_violation on 4t_fpu_512 is pre-existing (identical EOC 46933000). cache-test-vector eoc_clean→timeout_cap on 2t was a cap artifact (4ms sim, baseline ~1284s wall, sweep cap 900s) — **extended re-run confirmed CYCLE-IDENTICAL** (EOC 4062352000 / 3678994000, SB-clean). 4t-rp2 baseline "stuck" entries were the baseline's own false-watcher artifacts (now correctly classified). Results: `reports/rtl_timing_opt_runs/`.
- **Net:** behaviour- and cycle-preserving across all configs, 0 corruption. Estimated ~0.13-0.18ns combined recovery (contingent; actual Fmax from the backend re-synth). Deferred: `flatten-write-output-mux-access-ctrl` (revisit only if re-synth shows it on-path).
- **Synthesis-compat fixes (during TSMC7 synth, IP commit `93d1c11`):** (1) dropped the `string` type keyword from 6 `parameter string` decls (SimInit/ModeleName/CtrlName) → untyped string-literal params like tc_sram_impl (synth tool rejects the `string` construct; behaviour-identical, sized-by-value); (2) added `import insitu_cache_pkg::*;` to `insitu_cache_top.sv` (was calling the package fn `cache_addr_hashing` without importing the pkg → VER-125; matches tcdm_wrapper). No `.svh` include added (user constraint). Synth area `hardware/deps/insitu-cache` shares inodes with the repo copy, so edits land directly. **Bender.lock bumped e5a16e0 → 93d1c11 + committed (main `e0511fa`)**; worktree keeps the Path override unstaged.
- **Follow-up:** push IP commits to github (lock pin resolves locally via Path override until then).

## 2026-06-08

### (no commit) RTL timing-opt candidate sweep → plan report (for review, NOT yet implemented)
- **Time:** 2026-06-08 ~21:00 +0200
- **File:** `reports/rtl_timing_opt_plan.md` — reviewable digest of behavior-preserving, zero-latency RTL timing restructurings to land BEFORE the multi-day backend run (user constraints: no pipeline/latency, prefer no logic change).
- **Method:** 45-agent discovery + adversarial-verification workflow over the cache datapath (7 area agents → 38 candidates → per-candidate equivalence/real-depth verifier). **15 actionable, 23 rejected** (synth-already-does-it / not-equivalent / off-config-512).
- **Vetted set (ranked, all verified bit-identical):** T1.1 `bank-we-direct-or` (tile.sv, path tail, ~0.03-0.05); T1.2 `selflush-flatten-cse` (tcdm_wrapper:1436, shared select root, ~0.02-0.05); T1.3 `metaskip-and-before-mux` Variant A (core:1591, meta-we endpoint, ~0.03-0.06); T1.4 `waymask-cascade-flatten` (core:997, ~0.03-0.05); T1.5 `hashway-status-bit-decompose` (decoder, +enum assert, ~0.00-0.03); T2.1 `wrfullhit-drop-redundant` (fwd buf, ~0.005); T2.2 `wordwriteen-drop-redundant` (tcdm_wrapper:2134, fan-in cut). Deferred: `flatten-write-output-mux-access-ctrl` (uncertain gain, invasive). Combined ~0.13-0.18ns across distinct segments (additive), magnitudes contingent on re-synth.
- **State:** started T1.1 (tile bank-we) then **reverted it on user request** — user wants to review the plan first, give feedback, then authorize. Tree clean except the already-committed Option X + decoder flatten. Each item, when done, needs vlog-check + one combined 4-config sweep + Bender.lock bump.

### (no commit) weekly report assembled
- **Time:** 2026-06-08 ~20:00 +0200
- **File:** `reports/weekly_report_2026-06-08.md` — covers 2026-06-01→06-08 (PR #20 merge + DiyouS fixes + config-selectable refactor; critical-path attribution → Option X → ungrouped analysis → lever evaluation incl. decoder flatten; calib TB + characterization + cold-miss regime). Assembled from WORKLOG + git log per the CLAUDE.md convention.

### (uncommitted RTL) Decoder priority-cascade FLATTEN (timing lever #1) — IMPLEMENTED, compiles clean
- **Time:** 2026-06-08 ~19:30 +0200
- **File:** `working_dir/insitu-cache/src/insitu_cache/insitu_cache_decoder.sv` (local override copy; needs Bender.lock rev bump at commit).
- **What:** Replaced the hash-way hit/pend/conflict **priority `if/else-if` cascade** (proc_hash_way_req) with a **flat sum-of-products**. Added 5 module-scope helpers (`_tag_hit`, `_is_valid_way/_is_rpend_way/_is_wpend_way/_is_inval_way`) via continuous assign: the wide ~18-bit tag compare computed ONCE + the 2-bit status decoded in parallel. Outputs: `dec_is_hit_o=_tag_hit&_is_valid_way`; `dec_is_hit_pend_o=_tag_hit&((rp&~w)|(wp&w))`; `dec_is_hit_conflit_o=_tag_hit&((rp&w)|(wp&~w))`; `dec_is_all_pend_o=~(valid|inval)`. MULTI_READ_PEND miss_meta append gated by `(_tag_hit&_is_rpend_way&~w)`.
- **Why:** `dec_is_hit_conflit_o` is the critical decoder output (§11, ungrouped report); the cascade stacked it behind the VALID/READ_PEND arms (else-if depth) on top of the shared tag compare. Flattening removes that priority depth. Est. **~0.03-0.05 ns** off the decoder segment (seg C). Only the hash-way branch touched (all 512 sweep configs use hash mode); the full-assoc branch (non-hash) is unchanged.
- **Behaviour-equivalence:** status is a 1-hot enum → cascade arms are mutually exclusive → priority==parallel; tag compare shared; all_pend/new_entry/prime/linkable reproduced exactly. Proven by case enumeration.
- **Verification:** `vlog -sv` compile of pkg+decoder clean (with and without `+define+ENABLE_MULTI_READ_PEND`); only benign vlog-13314 input-port-kind warnings. **Functional validation = pending 4-config scoreboard sweep** (any cache RTL edit re-opens it). **Timing gain = pending re-synth** (synthesis flow not runnable here).
- **COMMITTED 9d23305** (IP repo `working_dir/insitu-cache`, branch `zexin/sync-flush-fixes`, atop Option X bf0bdad) — `[RTL] insitu_cache_decoder: flatten hash-way hit/pend/conflict cascade to parallel SOP (cut decoder critical-path depth)`.
- **Bender.lock bumped + COMMITTED 10cc85a** (main repo `fix/cache-refill-throughput`, atop 84d72c6) — `[Bender] bump insitu-cache lock to decoder hash-way cascade flatten (9d23305)`. Staged rev-pin (bf0bdad→9d23305, github source) committed; worktree keeps the unstaged `Path: working_dir/insitu-cache` dev override.
- **Follow-ups still open:** push IP commits (bf0bdad, 9d23305) to github (else the lock pin resolves only locally via the Path override); functional 4-config sweep + re-synth before relying on it.
- Timing lever **#2** (access-controller addr comparator) deliberately NOT done — mislabeled by the analysis agent as a "rotation hoist"; it's actually the read-vs-write addr compare (tcdm_wrapper.sv:2191) gated by the late `bank_read_sel_flush` mux (:1464), entangled with the fwd-buffer hazard logic + Option-X-reshaped back half → re-evaluate post-Option-X re-synth (report §11.3 corrected).

### (uncommitted docs) Ungrouped timing analysis + post-Option-X estimate (report §10)
- **Time:** 2026-06-08 ~15:00 +0200
- **Input:** `reports/timing_max_2.rpt` — same pre-Option-X RTL as `timing_max.rpt` but synth'd with `set_ungroup false` on the cache modules (for readability). WNS −0.314 @125c / −0.365 @−40c (worse than flattened −0.208/−0.245 — hierarchy blocks cross-boundary opt + ~0.16ns un-optimizable tcdm_wrapper glue).
- **Module breakdown of the −0.365 path (≈1.13ns datapath):** SRAM 0.252 (fixed), **access_ctrl_for_data/fwd-buffer 0.222**, tcdm_wrapper glue 0.155, decoder 0.118, data_bank 0.099, meta_bank 0.076, core 0.071, encoder 0.053, tile_glue 0.047, access_ctrl_meta 0.041.
- **KEY finding:** the ungrouped critical path is the **write-ENABLE path** (dec_is_hit_pend → fwd-buffer write-enable → bank/meta clock-gate) — **0 `mshr_subarray_mask`/`enc_mod_mask` nodes on it.** The mask path (what Option X removes) and the enable path are **co-critical**; flattened `timing_max.rpt` exposed the mask path, ungrouped exposes the enable path.
- **Post-Option-X estimate (needs re-synth):** Option X touches only core+encoder (~0.12ns of the path); the two biggest blocks (SRAM 0.25 fixed, fwd-buffer access-ctrl 0.22) are untouched. So Option X likely improves flattened WNS to ~**−0.10…−0.18ns — probably still violating**; + CTS useful-skew for the ~0.13ns skew. **Tempers §7's optimistic ~0.19ns recovery.** Recommend re-synth post-Option-X (ungrouped) and diff vs timing_max_2.rpt.
- **`fwd_wr_hit` decomposition (report §10.5, RTL-verified):** `fwd_wr_hit = wr_req_i & PREDICATE`. PREDICATE inputs = buffer flops + registered wr_addr + wr_mask_i. The mask WAS the longer SRAM input (mshr_subarray_mask barrel shift); **Option X makes it constant → PREDICATE is now all-flop/constant → resolves in parallel with the SRAM read, OFF the critical path.** The only remaining late input is `wr_req_i = dec_is_hit_pend` (hit-pend tag compare — fundamental). **Decision: did NOT implement a `predicate_q` register** — it gives no timing benefit (predicate already early) AND is a correctness hazard (stale buffer state → wrong absorb → corruption, in the just-validated module; any fwd-buf edit re-opens the 4-config sweep). Residual lever = decoder hit-pend (Stage A) + SRAM floor. If re-synth shows the predicate still on-path, safe fix = COMBINATIONAL re-factor `wr_buf_can_absorb` (no flop), as a separately-validated follow-up.

### (uncommitted docs) Meta-SRAM shrink / byte-mask removal — analyzed (report §12)
- **Time:** 2026-06-08 ~18:30 +0200
- **Question (user):** the 64-bit byte write-mask stored in the meta SRAM is "no longer useful; a single dirty bit is enough" — can we drop it to shrink the meta SRAM and speed clk→Q? + any other dead bits?
- **Method:** 5-lens + 3-skeptic adversarial workflow vs RTL (write/refill/writeback policy; full mask use-map; MSHR-count overlap; dead-bit audit; full-line-writeback downstream cost).
- **Meta word (cfg-512, 92b/way):** status2 + dirty1(DEAD on read) + miss_meta5 + **mask64 (~70%)** + tag18 + lru2(DEAD on read). dirty/LRU real copies live in separate dirty_rf/lru_rf; the meta-word dirty/lru unpack to *_meta_unused (tcdm_wrapper.sv:1628/1632).
- **Verdict: hypothesis FALSE as-is** (naive removal = data corruption). The 64b mask is **multi-role & load-bearing**: VALID/WRITE_PEND → per-byte mask for (a) partial L2 writeback (core.sv:1201) + (b) refill-merge overlay (core.sv:2354); READ_PEND → low SubarrayCntWidth bits = **MSHR subarray count** (core.sv:1633/1713/2314). Cache is **write-VALIDATE** → partially-valid dirty lines genuinely exist. Skeptics confirmed 3 corruption/hang vectors: full-line WB of '0 placeholder bytes; WAR refill-merge byte loss; MSHR count collapse → cores hang (core.sv:242-251).
- **Removable ONLY with policy change**, and frees **~56-60 bits not 64**: (1) strict write-allocate / full-line-merge-before-VALID (no partial lines) → full-line WB safe, at **up to 4× L2 WB traffic** on sparse-dirty 128b-refill configs (loses the all-zero-beat skip, cachepool_cache_ctrl.sv:705); (2) relocate MSHR count to its own ~4-8b field → meta floor ~33-36b not ~28b; (3) update meta_skip + scoreboard. **Full-line WB is downstream-SAFE** (eviction guard VALID&&dirty + refill-merge invariant ⇒ evictable lines fully valid; DRAMSys honors-but-not-requires partial strobe; single shared L1). So mask-on-writeback is bandwidth-only, not correctness — user's intuition holds THERE; blockers are refill-merge + MSHR count.
- **Timing payoff modest:** SRAM access at fixed depth (128 rows, capacity-locked) scales weakly with width → 92→33b ≈ **~0.02-0.05 ns** off the 0.262 floor (needs SRAM datasheet/re-synth). Same league as §11.3 logic levers but via a correctness-critical policy overhaul. **REJECTED for timing.**
- **Cheaper alternatives:** (i) **free 3-bit cleanup** = drop dead dirty(1)+lru(2) meta fields, zero policy change, but ~3% width → negligible timing (only bundle into a bigger meta change; any meta edit re-opens the sweep). (ii) **tag/mask SPLIT** (no policy change, better ns-per-risk): narrow fast SRAM (tag+status+miss_meta+count ~33b) on the critical front + parallel 64b mask SRAM consumed only ~0.4ns later at the encoder (has slack). The lever to evaluate if SRAM-width timing is pursued; needs a 2nd-macro area + mask-SRAM-slack check.

### (uncommitted docs) read-one-way decoder fix — analyzed, REJECTED (report §11)
- **Time:** 2026-06-08 ~17:30 +0200
- **Question:** does the "read-one-way in the decoder" lever (eliminate the per-way tag select so SRAM→hit-decode is shorter) help close the −0.314ns cache critical path?
- **Method:** cell-by-cell read of the actual path in `timing_max_2.rpt` (lines 139-612) + **4-lens adversarial workflow** (cheap-removal / mux-size / reorg-cost / better-lever), each *trying to overturn* "don't do it". **All 4 returned `supports_dont_do`.**
- **Verdict: REJECT.** Three independent reasons: (1) **already done at the SRAM port** — read-enable is one-hot-gated by the hash way (`core.sv:997-1003` → `tcdm_wrapper.sv:1792`); only `_hash_way`'s SRAM reads. (2) **no removable mux** — 4 physically-separate per-way SRAMs, `_hash_way` is register-early, so the array-index collapses to **~0.006ns (one input inverter)** on the late tag-data edge; the 0.090ns decoder segment is the `==_tag` compare + status/priority (intrinsic). (3) **deleting it makes timing WORSE** — address-by-way SRAM = 128→512 deep = +0.04…0.09ns clk→Q landing on the violating startpoint, + serializes flush dirty-probe + mandatory 4-config re-sweep. **Net ~0.00 to negative ns.**
- **Path budget (measured, §11.1):** SRAM floor 0.262 + back-half logic/route (fwd-cov 0.103, XOR ~0.085, data-we ~0.06, tile route 0.149) + 0.297 clock-network dominate; segment B (read-one-way's target) is ~0.006ns of mux.
- **Real levers (§11.3):** logic levers combined (decoder-priority flatten 0.03-0.05, fwd-cov precompute 0.04-0.06, XOR hoist 0.026) ≈ 0.10-0.14ns — **still short of 0.314**. Highest-leverage closers are **architectural** (pipeline the hit-decision, `deferred_bank_write_t` infra exists) or **physical** (CTS useful-skew on the 0.297ns clock-network, floorplan the 0.149ns route, faster SRAM macro). **Next concrete step remains: re-synth post-Option-X to measure actual residual.**

## 2026-06-06

### (uncommitted) Option X sweep COMPLETE — all 4 configs, NO regression, 0 new corruption
- **Time:** 2026-06-07 ~01:10 +0200
- **Result (vs baseline sweep_2026-05-29_05-54):** 4 configs (4t/2t × rp2/rp1), 37 tests each. **0 regressions on every config; 0 new data corruption.** Every test matches-or-beats baseline; **7 tests improved** (baseline timeout_cap → eoc_clean). Per-config: 4t-rp2 32 match/2 better/0 reg; 4t-rp1 33 match/0 better/0 reg/1 sb_violation(pre-existing); 2t-rp2 31/4/0; 2t-rp1 34/1/0.
- **The lone sb_violation** (`gemv-opt_M256_N128_K32`, 4t-rp1) is **pre-existing** — sb_violation in baseline too, identical EOC time 46933000, resp-data mismatch; baseline had 2 violation types vs Option X's 1 (no worse). NOT Option X. Worth a separate look someday.
- **Report:** `reports/sweep_optionX_2026-06-06_19-47/SWEEP_REPORT.md` (full verdict + method/caveats). Orchestration finished clean (0 leaked sims; calib GUI preserved). v2 leak-proof driver used for configs 2-4.
- **Conclusion:** Option X functionally validated across all configs, perf-neutral-or-better.
- **COMMITTED 2026-06-08:** IP repo `working_dir/insitu-cache` (zexin/sync-flush-fixes) **bf0bdad** — `[RTL] insitu_cache_core: full-line write-back for folded MSHR append; drop barrel-shift mask off bank-write critical path`. Main repo (fix/cache-refill-throughput) **9cdf903** — `[Config] config.mk: default l1d folded/hash-way/fwd-buf knobs; fixes empty-define build break on fpu configs`. Only these two files committed; pre-existing/generated main-repo changes (Bender.*, Makefile, cachepool.hjson, cachepool_512.mk, bootrom/*) left untouched.
- **Bender.lock bumped + committed 2026-06-08:** main repo **84d72c6** — `[Bender] bump insitu-cache lock to Option X full-line MSHR-append write-back (bf0bdad)`. Committed Bender.lock pins insitu-cache → git rev bf0bdad; worktree keeps the local `Path: working_dir/insitu-cache` override (unstaged) for local dev.
- **Still TODO:** **push IP commit bf0bdad to github (pulp-platform/Insitu-Cache.git)** — the committed lock pin only resolves for non-override fetchers once bf0bdad is pushed (local build is fine via the path override). Re-synthesis for the actual Fmax gain. Pre-existing gemv-opt_M256 4t-rp1 sb_violation still open ([[project_optionx_and_gemvopt_bug]]).

### (uncommitted) Option X sweep — 4t-16c rp2 PASS (no regression); config build-bug fixed; remaining 3 configs pending
- **Time:** 2026-06-06 ~22:30 +0200
- **Files:** `config/config.mk` (added `l1d_use_folded/fold_way_group/hash_way/fwd_buf ?= 1/0/1/1` defaults); new `reports/sweep_optionX_2026-06-06_19-47/` (SWEEP_REPORT.md + per-config summary/logs); sweep driver `/tmp/optx/sweep_one.sh` (v2, leak-proof).
- **Config fix (root cause):** the 4t/2t fpu sweep configs never built — `config.mk` lacked defaults for the folded/hash/fwd knobs the config-selectable refactor made required, so the Makefile emitted empty `+define+L1D_USE_FOLDED=` → syntax error in `cachepool_cluster_wrapper.sv:24`. Added the production-combo defaults (`?=`, preserves explicit per-config values). This is the gap the earlier refactor missed.
- **4t_fpu_512_rp2 result (hardest config): NO REGRESSION, 0 corruption.** All 37 tests: 0 SB FAIL / 0 MISMATCH. 33 eoc_clean (vs 31 baseline — `cache-test-vector` + `fmatmul_M128` went timeout_cap→clean), 2 eoc_nz identical to baseline (cache-mix-pressure rv1, gemv-opt_M128 rv7 = pre-existing), 2 non-completing (cache-coverage/mcs-lock = pre-existing baseline stuck/timeout). Every test matches-or-beats baseline. Known `fft rp2` bug case (`fft-32b_M1024_N16`) clean; previously-stuck `fdotp-32b_M8192/M32768/M65536` clean.
- **Calib smoke:** all 20 phases data_err=0, throughput == baseline (perf-neutral).
- **Infra lessons (fixed):** (1) liveness watcher read the wrong dasm path (`sim/bin/logs` vs the real `util/auto-benchmark/logs/<run>/<test>/`) → false "stuck" at 240s; replaced with flat timeout. (2) `timeout`/`pkill -P` only killed the wrapper, not the `vsimk` kernel → orphaned-vsim resource leak (cleaned up; calib GUI preserved). v2 driver uses `setsid` process-group kill + `vsimk` sweep. (3) `make clean` removed the repo-root `vsim.wlf` (sweep step 1 per CLAUDE.md).
- **Pending:** build+sweep 4t-rp1, 2t-rp2, 2t-rp1 (~overnight). Awaiting user go-ahead given cost vs the strong 4t-rp2 result.

### (uncommitted) IMPLEMENTED Option X — full-line MSHR-append write-back (removes barrel shift from crit path)
- **Time:** 2026-06-06 ~19:45 +0200
- **Files:** `working_dir/insitu-cache/src/insitu_cache/insitu_cache_core.sv` — two sites: active no-MRP hit-pend append (~1725-1740) and the compiled-out MRP mirror (~1632-1648). Collapsed `if (PartSplit>1){masked write via mshr_subarray_mask} else {full-line write}` to **just the full-line write** (`subarrays[cnt]=info; enc_cache_data = req_hit_pend_cache_payload_tmp.data;` default all-ones mask). Left `mshr_subarray_mask()` defined but now uncalled (minimal/reversible diff; may draw an unused-function lint).
- **Why:** removes the data-dependent barrel-shift `mshr_subarray_mask` (Stage B, dominant 0.447 ns of the −0.245 critical path) from the bank-write path. Approved GO by 5-agent scenario workflow (scope/fwdbuf/data-correctness/adversarial all correct, low risk). Correctness rests on: `dec_cache_data` is the full fresh line (bank_read_all_parts_o tied high, core.sv:970) kept fresh by fwd-buffer assertion C3 (no stale-SRAM bypass of a dirty line). Only the two `mshr_subarray_mask` sites touched; the 6 real store/refill `enc_mod_mask=request.wmask/fsm_refill_stall_q.wmask/deferred` sites (1586/1773/1842/2256/2500/2554) KEPT.
- **Residual risks (from workflow):** (1) larger blast radius if C3 ever regresses (contingent, not introduced); (2) the **known open fft-rp2 partial-strb bug lives in this exact code region** — sweep must re-confirm it (could fix / not affect / change symptom); (3) write-column pressure only in the fwd-buffer-DISABLED `insitu_cache_top` integration, NOT the production `tcdm_wrapper` path.
- **Verification so far:** standalone calib smoke (`make cache-calib config=cachepool_512`, folded PartSplit=4, fwd-buf on) — recompiled clean (Errors:0), **all 20 phases data_err=0** incl. coal_cold_4port / mshr_depth (MSHR-append-heavy); throughput identical to baseline (cold-miss 0.2433, mshr 0.2466, coal 0.4672) ⇒ functionally correct + perf-neutral in the cache TB. **NEXT: 4-config integrated sweep** (4t-rp2 → 4t-rp1 → 2t-rp2 → 2t-rp1), functional (scoreboard/EOC) + performance (cycles), smoke on 4t-rp2 first (fdotp-32b_M8192/M32768/M65536, load-store_M16, fft M1024 N16) per CLAUDE.md.
- Uncommitted on `fix/cache-refill-throughput`; IP edit needs Bender.lock rev bump before any commit (user reviews first).

### (uncommitted) Critical-path: measured non-folded baseline comparison (corrects skew framing)
- **Time:** 2026-06-06 ~07:00 +0200
- **Files:** `reports/critical_path_timing_analysis.md` (§1 decomposition corrected; new §6 with full non-folded path + comparison).
- **What:** User extracted the SAME path (same meta-SRAM start, same meta clk-gate end, same ss −40c, 1 ns) from the **non-folded** (`PartSplit=1`) build, where the three §2 depth-adders are inactive. Compared to the folded WNS path.
- **Result:** non-folded MET at **+0.008**; folded VIOLATES at **−0.245** ⇒ regression **−0.253**. Normalizing each datapath to its launch clock: datapath **0.831 → 1.073 (+0.242)**, post-SRAM logic cloud **0.561 → 0.807 (+44%, ≈+72 cells)**; SRAM CLK→Q identical (0.270 vs 0.266); **skew essentially unchanged (−0.118 → −0.129)**.
- **Correction:** the regression is **≈96% added logic depth, ≈4% clock/skew**. My 2026-06-05 "~0.13 ns negative skew" was over-credited — the skew was already present in the MET baseline and is NOT the cause. Both launch and capture clock latencies moved ~0.1 ns more negative together (placement), so net clock impact is only −0.011. Confirms: fix = logic-depth reduction (pipeline the tag-read→hit-decode→bank-write boundary).
- **Per-cell decomposition (report §7):** parsed every cell on both paths. Folded post-SRAM 0.807 ns = LOGIC 0.682 (84.5%, 56 gates) + INV 0.055 + WIRE 0.046 + BUF 0.024; non-folded 0.558 = LOGIC 0.496 (25 gates) + BUF 0.037 + INV 0.025. **Regression split: true Boolean logic +0.186 ns (~75%, +31 gates 25→56), buf/inv/wire ~+0.06 (~25%), wire only ~6%.** Cell count 29→63 (+34). Corrects the earlier "buffering for larger folded layout" guess — it's overwhelmingly real logic depth, so pipelining recovers ~0.19 ns (clears −0.245 alone); floorplan is a minor lever.
- **Stage-B fix options in depth (report §9; feasibility workflow + direct RTL read):** evaluated the "drop the mask, write the full MSHR line back" idea. **Correctness: SAFE** — assertion C3 (`sram_forwarding_buffer.sv:752-759`) forbids an in-flight SRAM read to a different addr while the buffer is dirty, so a read of a buffer-dirty line always returns up-to-date data (`rd_buf_hit` or `rd_inflight_hit`); no stale-SRAM bypass ⇒ `dec_cache_data` always fresh ⇒ full-line write-back is correct (rests on existing C3 invariant). Corrected an earlier over-cautious "staleness race" call (it needs the C3-forbidden state). **Perf: ~free** — 1-cycle write either way; fwd-buffer `wr_full_hit` absorbs it (no column contention in production); only wider write-back mask + minor energy. **Option X (full-line write):** biggest win, smallest diff (mirror PartSplit==1 arm at core.sv:1638/1730), re-verify via sweep+scoreboard. **Option Y (keep masked write, cheaper):** Y1 constant-fold the shift (`case`/const-shift → NumSubarray-way mux of constants, ~3-4 levels vs 6-level barrel shifter, 0.04-0.08), Y2 hoist `mshr_subarray_mask` out of the FSM priority cascade to a standalone wire so it runs parallel to the condition logic (0.07-0.12). Either + Stage-C cheap wins + floorplan closes the path.
- **Per-stage delay + reduction analysis (report §8; 4-agent workflow, RTL-anchored):** segmented post-SRAM 0.807 ns → Stage A hash-way decode 0.156 (19%), **Stage B hit-pend→enc_mod_mask→write-mask 0.447 (55%, DOMINANT)**, Stage C fwd-buf write-enable+tail-wire 0.204 (25%). Stage B = FSM priority-mux ~0.19 + barrel-shift ~0.15 + encoder ~0.07. **Reduction plan:** minimal low-risk set = (1) hoist `hit_pend_mod_mask` out of the FSM priority cascade [B, 0.07-0.12], (2) constant-fold `mshr_subarray_mask` shift [B, 0.04-0.08], (4) register per-way meta-write enable + `&dec_cache_mask` skip [C, 0.03-0.06] — all pure combinational/registering, no latency cost, ~0.14-0.26 ns. Add (3) precompute `fwd_wr_hit` [C, 0.06-0.08, med] and (5) floorplan co-locate meta bank [C, 0.04-0.09, no-RTL] for margin; combinational set 1+2+3+4 ≈0.25-0.27 ns clears −0.245. Fallback (6): 1-cycle pipeline the DATA write via existing `deferred_bank_write_t` [B, 0.20-0.28, certain closer, needs refill-drain race proof]. Stage A deliberately left untouched (risk≫gain). RTL unmodified — change specs only.

## 2026-06-05

### (uncommitted) Critical-path timing attribution — which RTL changes deepened the cache hit-pend write path
- **Time:** 2026-06-05 ~16:50 +0200
- **Files:** new `reports/critical_path_timing_analysis.md`. Source: `reports/timing_max.rpt` (PrimeTime, post-place, ideal clock, 1 GHz, ss 0.675V).
- **What:** Analyzed the cluster's worst setup path (WNS −0.245 ns @ ss −40c; −0.208 @ 125c). Path = tag/meta SRAM read → `dec_is_hit_pend` (decoder) → `enc_mod_mask` (core) → data/meta bank write-enable → meta SRAM write clock-gate; functionally a store hitting a READ_PEND (MSHR) line in the folded cache. Same path replicated across all 16 controllers (systematic). Decomposed WNS into ≈0.116 ns real datapath depth + ≈0.129 ns estimated pre-CTS negative clock skew.
- **Why / attribution (4-agent adversarial workflow, all commits + diffs verified):** three genuinely-new depth additions, serially composed on the path:
  1. **`abfca84` (2026-03-25, hash-way folded lookup) — PRIMARY, ~4 mux levels.** Replaced the decoder's parallel all-ways compare (constant index) with a runtime `_hash_way` index into the 16-elem SRAM-output arrays ⇒ 16:1 mux on the SRAM-Q output at the path head; select is early address-XOR so SRAM data takes the slow mux side.
  2. **`cf00487` (2026-02-03) ~3-4 levels.** Introduced `mshr_subarray_mask()` (variable barrel-shift `slot_mask<<byte_base`) + routed the hit-pend WRITE through `enc_mod_data_with_mask=1; enc_mod_mask=mshr_subarray_mask(...)`; before, hit-pend writes used full-line/all-ones mask (no compute). (`55465aa`/`6851bdd` only refined/renamed — no added depth.)
  3. **`483b302` (2026-04-15, forwarding buffer origin) ~1 MUX2.** `downstream_write_req_o = upstream_write_req_i` → `fwd_wr_hit ? 1'b0 : upstream_write_req_i` on both data+meta access ctrls at the tail. (`fbabd6a` only parameterized; `2710920`/`4ec7b90` reduce depth.)
  All three are co-required by the folded+hashway+fwd-buf bundle (`tcdm_wrapper.sv:272` $fatal forces UseHashWaySelect=1). Cumulative ≈8-9 new gate levels ⇒ pushed a previously-comfortable path past 1 ns.
- **Recommendation:** pipeline the tag-read→hit-decode→bank-write-enable boundary (fixes all three stages at once and also relaxes the functional bank-contention throughput limiter). Secondary: restructure hash-way to compare-then-select; precompute the subarray mask; register `fwd_wr_hit`.
- **Caveats:** gate counts are structural estimates (no synth/PT re-run of the "before" state); stages are additive so no single revert guarantees closure; ~0.13 ns is pre-CTS skew that CTS/useful-skew may recover. Report has full before/after diffs.

## 2026-06-03

### (uncommitted) cold_miss_thrupt_1p waveform analysis — corrects "requester-bound" → bank-contention-bound
- **Time:** 2026-06-03 ~20:40 +0200 (analysis) · docs finalized 2026-06-04 ~06:50 +0200
- **Files:** new `reports/cache_calib/coldmiss_regime/` (`ANALYSIS.md` + artifacts `phase4_dump.txt`, `regime.wal`, `focused_log.do`, `calib.fst`, `calib.wlf`); edited `reports/cache_calib/REPORT_BL1.md` (§1 headline, §3 table + reading, §5).
- **What:** User asked why `cold_miss_thrupt_1p` shows three bandwidth regimes on the scope (6 full → ~26 at 2-on/2-off → rest 1-in-4). Re-ran the standalone calib TB (`cachepool_512`, BurstLength=1, MemLatency=50) with focused signal logging into a private WLF (`-wlf /tmp`, did NOT touch repo-root `vsim.wlf`), converted WLF→VCD→FST, and classified every cycle of phase 4 with WAL. Result reproduces the three regimes exactly: R1 c0–c5 (6 accepts, pipeline fill), R2 c8–c57 (26 accepts, perfect `11001100…`, bank `WR_CONFLICT`), R3 c60+ (1 acc/4cyc). 6+26=32=req-id budget. 263-cycle split: 64 accept / 29 cache-refuse / 170 driver-idle.
- **Why (the correction):** the steady-state ¼ rate is **cache data-bank read/write contention bound, not requester-budget bound** as `REPORT_BL1.md` originally claimed. Proof: MemLatency=10 and =50 give identical 0.243 throughput despite 5× latency ⇒ latency-independent ⇒ bank-bound (requester-bound would give ~0.5). Memory not limiting (`refill_rsp_valid` held high = backlog). Corrected model: `thr ≈ min(bank≈0.25, 32/(L+13))`, crossover ~L≈115; budget/latency only binds above that. Mechanism: `WR_CONFLICT` (`insitu_cache_tcdm_wrapper.sv:2258-2261`) + refill-arbiter priority (`insitu_cache_core.sv:884-893`); `NumPseudoDualBanks=1` (`l1d_bank_factor=1`); `bank_read_cache_ready` decoupled from `core_req_ready` by a 1-deep spill register.
- **Verification:** 4-agent adversarial check — regime counts confirmed (high), RTL mechanism confirmed (high), cache-vs-requester partially-confirmed/high (correct at low L, with the high-L nuance above), R1→R2 "why 6" partial/medium (forwarding-buffer spec-writeback collision, alternative not fully excluded). Phase `data_err=0`.
- **Follow-ups:** to raise this phase's BW the lever is bank contention (separate install/response port, or relax refill-arbiter priority), not the budget. All uncommitted on `fix/cache-refill-throughput` pending review.

## 2026-06-01

### (uncommitted) Cache latency/bandwidth characterization — expanded calib suite + expectation check
- **Time:** 2026-06-01
- **Files:** `hardware/tb/cache_calib/tb_cachepool_cache_ctrl_perf.sv` (4 new test phases + per-phase mem-traffic deltas in the CSV); new `reports/cache_calib/CHARACTERIZATION.md`; data `reports/cache_calib/char/char_memlat{10,50,100,200}.csv` + `char_memlat50_evfix.csv`.
- **What:** Used the standalone calib TB as a latency/BW characterization harness. Added phases beyond the original 4 metrics: **write latency/throughput**, **read-after-write (store→load) same-word**, **coalescer cold+warm (4 ports → same line, same cycle)**, **eviction/writeback**. Added per-phase `mem_rd`/`mem_wr` delta columns (line refills = misses, writeback beats = dirty evictions) so the CSV shows actual DRAM traffic per phase. Ran the full suite across MemLatency {10,50,100,200}.
- **Findings vs expectation (all data_err=0):** ✅ warm hit = **10 cyc** (mem-independent); ✅ cold miss = **MemLatency+17** (clean affine across 20× sweep); ✅ miss throughput serialized at ~1/(MemLat+17) (single outstanding refill, as designed); ✅ hit BW 0.86 acc/cyc 1-port, sub-linear port scaling to ~0.86; ✅ **coalescer**: 128 same-line accesses → exactly **32 mem reads** (1 miss/line merge), warm coalesced = **3.28 acc/cyc** (~4× single-port); ✅ RAW same-word forwarded (7 cyc, no mem); ✅ eviction (after resizing test to 2048 ln = 2× capacity) — writebacks fire (`mem_wr=1029`), dirty-victim miss = **567 cyc vs 513** clean (+~10%). **One follow-up (not a bug):** write throughput ≈ ½ read (0.49 vs 0.86 acc/cyc) — confirm intended write-path cost with architects.
- **Test fix:** first eviction phase was undersized (256+256 < 1024 capacity, contiguous → no set collision → `mem_wr=0`); bumped `EV_LINES` to 2048 to force evictions, re-ran (`char_memlat50_evfix.csv`).
- **Deliverable:** `reports/cache_calib/CHARACTERIZATION.md` — per-scenario tables, MemLatency-dependence table, ✅/⚠️ verdicts vs design intent.

### `3af9362` (main) + `fbabd6a` (IP) — make L1 folded/hash-way/fwd-buffer config-selectable
- **Time:** 2026-06-01 18:29 +0200 (main `3af9362`), 18:26 +0200 (IP `fbabd6a`)
- **Branches:** main `rebase/cache-refactoring-onto-main`; IP `working_dir/insitu-cache` `zexin/sync-flush-fixes`.
- **Files:** main — `config/cachepool_512.mk`, `config/cachepool_fpu_512.mk`, `Makefile` (VLOG_DEFS), `cachepool_cluster.sv`, `cachepool_group.sv`, `cachepool_tile.sv`, `cachepool_cluster_wrapper.sv`, `Bender.lock` (pin → `fbabd6a`). IP — `insitu_cache_tcdm_wrapper.sv`, `cachepool_cache_ctrl.sv`, `insitu_cache_core.sv`.
- **What:** Turned the L1 data-bank micro-architecture into config knobs (`l1d_use_folded` / `l1d_fold_way_group` / `l1d_use_hash_way` / `l1d_use_fwd_buf`, default = production folded+hash+fwd) emitted as `VLOG_DEFS` macros and macro-defaulted at `cachepool_cluster_wrapper`. Promoted the IP `UseForwardingBuffer` from a hardcoded `localparam` to a real parameter and threaded it cluster→group→tile→cache_ctrl→tcdm_wrapper. Made the IP `UseHashWaySelect` elaboration guard fold-aware (skewed-fold *or* fwd-buffer each require hash-select; so hash=0 is legal only for unfolded + fwd-off). Fixed two reversed part-selects (`[5:6]` when `PartSplit==1`) in `cachepool_cache_ctrl` (`coalescing_req_part_idx`) and `insitu_cache_core` (`preread_part_idx`) using the ascending `+:` form (bit-identical when folded).
- **Why:** answers DiyouS review comment #1 ("is the folded/unfolded `if` actually switchable?"). It wasn't: the param died at the `cluster→group` instantiation (silently fell back to module default) **and** the unfolded path failed elaboration. Now it's a real, config-driven switch. Also closed two dropped param paths of the same class: `UseFoldedDataBanks`/`FoldWayGroup` through `cluster→group`, and `UseHashWaySelect`/`UseForwardingBuffer` through `wrapper→cluster`.
- **Verification:** built + ran `load-store_M16` (config 512) both ways. **Folded default (4/1/1):** retval=0, 0 SB fail, EOC `68866000` — *bit-identical* to the pre-change folded run. **Unfolded conventional (0/0/0):** `PartSplit=1, CoalFactor=2`, no assertion fired, retval=0, 0 SB fail. Restored both flavor `.mk`s to production defaults after the unfolded test.
- **Cross-repo:** IP `fbabd6a` is committed + pushed to `origin/zexin/sync-flush-fixes`; main `Bender.lock` pins it (resolvable for CI/fresh checkout).
- **Open:** not run on `fpu_512` flavor or a vector kernel in unfolded mode (only `load-store` scalar path exercised). `Bender.lock` working-tree copy may re-mangle to a `Path:` override after a stray `bender update` — committed copy is the correct `Git:`+`fbabd6a` pin; `git checkout Bender.lock` restores it.

### `b704a70` (main) + `65940a3` (IP) — PR review fixes (DiyouS): coding style, verif relocation, W123 root-cause
- **Time:** 2026-06-01 17:16 +0200 (main `b704a70`), 16:43 +0200 (IP `65940a3`)
- **Files:** `hardware/src/cachepool_tile.sv` (verif blocks removed), `hardware/src/verif/cachepool_tile_tcdm_checker.sv` (new), `hardware/src/tcdm_cache_interco.sv` (rst_ni in sensitivity list), `working_dir/insitu-cache/src/cachepool/cachepool_cache_ctrl.sv` (IP: `'{}`→`{}` on xbar output ports), `util/lint/script/lint.tcl` (drop cachepool_cache_ctrl W123 waiver), `Bender.yml` (register verif file under `simulation` target).
- **What/why (per review comment):**
  - **always→always_ff + rst_ni (cc 2,3,5,6):** the tile tracer + per-port TCDM memory-model VIP and the interco Probe-D watcher were legacy `always @(posedge clk_i)`. Converted to `always_ff @(posedge clk_i or negedge rst_ni)`; the MM VIP (has registered counters/FIFOs) gets a real reset branch, the two stateless `$display` probes keep rst_ni in the sensitivity list + gate (no state to reset — flagged to reviewer).
  - **Relocate verif (cc 4):** moved the tracer + memory-model VIP out of the tile RTL body into `hardware/src/verif/cachepool_tile_tcdm_checker.sv`, `bind`-attached to `cachepool_tile`. Keeps the synthesizable body clean; behavior identical.
  - **W123 (cc 9) — reviewer is right, not a false positive:** the cache_ctrl `i_bypass_xbar` connected its **output** ports (`slv_rsp_o`, `slv_req_ready_o`, `slv_rsp_valid_o`) with an assignment pattern `'{...}` instead of concatenation `{...}`. `'{}` as a packed-array **lvalue** is the non-LRM-clean construct that made SpyGlass unable to see the driver. Fixed to `{...}` (inputs keep `'{}`, which is correct there) and **removed the W123 waiver**. MSB-first concat matches the by-position ordering (idx1=bypass/Snitch, idx0=coalescer).
- **Verification:** calib + integrated builds recompile clean (`cachepool_cache_ctrl`, `cachepool_tile`, bound `cachepool_tile_tcdm_checker`, TB all **Errors: 0**). Calib suite after the IP edit: **all data_err=0**, `'{}`→`{}` bit-identical. Integrated `clean.vsim`+`vsim` built and `load-store_M16` ran to **retval=0** with all 4 cache scoreboards reporting (proves the `bind cachepool_tile` attaches + the IP edit works in-system). SpyGlass `lint/lint_rtl` (run `…_164542`): the `cachepool_cache_ctrl` W123 is **gone**; the only W123 left is the third-party `spatz_decoder` (still waived).
- **cc 1 (folded `if`):** addressed in the follow-up commit `3af9362`/`fbabd6a` above — made genuinely switchable + config-driven, both modes verified. No longer an open item.
- **Note (cc 5):** memory-model VIP uses a plain clocked `always @(posedge clk_i)` (not `always_ff`) — it's a passive SV-queue scoreboard, not a flop; `always_ff` there only bought a lint waiver. Flagged for the PR reply.

### (uncommitted) Standalone InsituCache performance-calibration testbench — full suite + trace stimulus + GVSoC interchange spec
- **Time:** 2026-06-01
- **Files (new):** `hardware/tb/cache_calib/tb_cachepool_cache_ctrl_perf.sv`, `hardware/tb/cache_calib/refill_mem_model.sv`, `sim/cache_calib.mk`, `reports/cache_calib/{PLAN,REPORT,TRACE_SPEC}.md`, `reports/cache_calib/results_memlat{10,50,100,200}.csv`, `reports/cache_calib/traces/{sample.trace,sample_trace_out.rtl.csv}`; **edited:** `Bender.yml` (new `cachepool_calib` target), `Makefile` (include `sim/cache_calib.mk`).
- **What:** Standalone RTL TB around `cachepool_cache_ctrl` (DUT = coalescer + Snitch bypass + insitu wrapper — the per-controller cache as instantiated in `cachepool_tile`) for RTL↔GVSoC performance calibration. Lives in the main repo (DUT instantiates `reqrsp_xbar`/`reqrsp_pkg`, main-repo-only) and resolves the cache to `working_dir/insitu-cache` via the active `Bender.local` override. **Param fidelity:** TB `import cachepool_pkg::*` and mirrors the tile's per-controller localparams verbatim (PartSplit/fold/coalescer geometry), compiled with the **same `VLOG_DEFS`** as `make vsim` → DUT config is bit-identical to the integrated build. External tag/data SRAMs (`tc_sram_impl`, folded+unfolded + write-priority grant) replicated from the tile. Downstream memory = `refill_mem_model`: deterministic fixed-latency responder on the narrow burst refill port (knobs `MemLatency`/`BeatGap`/`AcceptEvery`, no `$random`) — the contract GVSoC must reproduce. Harness: cycle counter, per-(port,req_id) latency, hit/miss + outstanding depth, data-integrity scoreboard, CSV writer. Four built-in metric phases (warm-hit, cold-miss, MSHR depth, BW-vs-load) **plus** a `+trace=` stimulus mode that replays an external access stream and dumps a per-access result CSV.
- **Build/run:** `make cache-calib config=cachepool_512` (+ `cache-calib-compile`, `cache-calib-gui`; `MEM_LAT=` latency sweep; `TRACE=<f> TRACE_OUT=<f>` trace replay). The calib target deliberately does NOT depend on `make generate` (reuses the integrated build's generated sources).
- **Verification:** both TB files compile clean (Errors: 0); elaborates the full DUT with the exact integrated config (banner `NumPorts=5 Line=512 Ways=4 BankFactor=2 Word=32 Entries/ctrl=1024 PartSplit=4 Folded=1 Hash=1 RefillW=128 Burst=4`). **Full 4-metric suite + MemLatency sweep {10,50,100,200} + 13-access sample trace all PASS, data_err=0.** End-to-end `make … TRACE=` flow verified byte-identical to a hand-run. Verified reference numbers (config 512, one controller, unified `t_issue`=accept-cycle convention):
  - Warm read-hit latency = **10 cyc** isolated (**7 cyc** streaming steady-state), memory-independent across the sweep.
  - Cold read-miss first word = **MemLatency + 17 cyc** (constant +17: 27/67/117/217 at memlat 10/50/100/200).
  - Sustained 1-port hit throughput = **0.86 acc/cyc**; all-hit port scaling 1/2/3/4p = 0.62/0.76/0.83/0.86 acc/cyc (strongly sub-linear → ~0.86 ceiling, single shared controller).
  - **Refills serialized** (one outstanding line refill, `refill_read_outstanding_q`) ⇒ distinct-line miss throughput is memory-bound at ~1/(MemLatency+17); core accepts ahead (~6 hits / ~11 misses outstanding) but that hides hit latency, not miss latency. **Key invariant for GVSoC.**
- **TB bring-up fixes:** (1) responder `always_comb` temporaries hoisted to module scope + head-of-queue inlined (`job_t` unpacked queue elem → no `'0` aggregate assign); (2) calib vsim needs `-voptargs=+acc` (insitu wrapper drives module-scope packed struct `upstream_req_to_cache_payload` field-by-field in a generate block → vopt prunes it → vsim-3043 at load); (3) injection-rate gap sweep was a no-op (`automatic int unsigned gaps[4]='{...}` left zeroed by Questa in a procedural loop) → explicit unroll, now varies (gap 0/1/3/7 → 0.86/0.47/0.24/0.12 acc/cyc); (4) `$sscanf` `%[^,]` scanset unsupported by Questa → manual comma-split parser (`.atoi()`/`.atohex()`); (5) unified `issue_req` timestamp to the accept-cycle (`cyc`) convention used by the streaming driver + response monitor (previously `cyc+1`, off-by-one on single-access phases) → regenerated all reference CSVs.
- **Trace interchange:** `reports/cache_calib/TRACE_SPEC.md` is a self-contained spec for the GVSoC-side TB — DUT boundary + config-512 params, the memory-timing contract, the `port,rw,addr,size,delay` input grammar + ordering/concurrency semantics, the `idx,port,rw,addr,size,t_issue,t_resp,latency` per-access result schema, run instructions, the RTL reference numbers to match, and a CSV-diff calibration methodology.
- **GVSoC implementation reference (new):** `reports/cache_calib/CALIB_IMPLEMENTATION.md` — the "port me" doc for the GVSoC side. Gives the **cycle-accurate memory-model algorithm** (accept/queue/respond pseudocode, `ready_cycle`, beat/gap timing, deterministic self-describing data pattern) and the **exact measurement definitions** (t_issue/t_resp at the handshakes, req_id matching, throughput/outstanding/data_err), the ready/valid interface protocol, the trace-driver semantics, and — emphasized — the single-outstanding-refill serialization that dominates miss throughput (a GVSoC model that overlaps misses will over-predict and fail calibration). Cross-linked from TRACE_SPEC.
- **Deliverables:** `reports/cache_calib/{PLAN,REPORT,TRACE_SPEC,CALIB_IMPLEMENTATION}.md`, `results_memlat{10,50,100,200}.csv` (13 phases each), `traces/sample.trace` + `traces/sample_trace_out.rtl.csv`.
- **Next (optional):** DRAMSys memory mode (refill→AXI bridge) for a realism cross-check; larger generated traces for fuller calibration coverage.
- **Related:** `reports/cache_calib/PLAN.md`, `reports/cache_calib/REPORT.md`, `reports/cache_calib/TRACE_SPEC.md`.

---

## 2026-05-31

### `5a39d14` — [TEST] multi_producer: atomic rlc_ctx updates for multi-consumer
- **Time:** 2026-05-31 21:37 +0200 (commit)
- **Branch:** `rebase/cache-refactoring-onto-main`
- **Files:** `software/tests/multi_producer_single_consumer_double_linked_list/kernel/` → `rlc.c`, `rlc.h`, `llist.h`, `mm.c`, `printf_lock.c`
- **What:** Made the multi-consumer kernel safe under multiple consumers. `rlc.h`: marked `vtNext`, `pduWithoutPoll`, `byteWithoutPoll` `_Atomic`. `rlc.c`: consumer now allocates a unique per-PDU sequence number via `atomic_fetch_add_explicit(&rlc_ctx.vtNext,…)` (used as the memcpy header) and bumps the stats atomically, instead of plain `+=`. Kept the intended 2-consumer / 6-producer dispatch (`core_id < 2`). `llist.h`/`mm.c`/`printf_lock.c`: release `fence rw,rw` before each lock unlock.
- **Why:** The `_K100` test hung on `cachepool_2t_fpu_512_rp2` and threw scoreboard errors on `4t_fpu_512_rp2`. Two issues: (1) a SW data race on the non-atomic shared `rlc_ctx` counters under >1 consumer (this caused the 4t-rp2 scoreboard errors), and (2) a latent rp2 cache store read-after-write visibility bug (response-before-commit). The atomic fix removes (1); (2) stays latent for this access pattern. Note: I staged the full validated working-tree `rlc.c`+`rlc.h` before committing — the previously-staged snapshot was an incomplete subset (dispatch change without the atomics) that would have shipped the buggy non-atomic race.
- **Verification:** Rebuilt + ran `_K100` on all 4 configs (`make clean; make generate/bootrom/vsim`). All **eoc_clean, retval=0**, scoreboards **16/16 (2t) and 32/32 (4t) PASS, 0 mismatch**. Driver/logs: `/tmp/mp_4cfg/`.
- **Related:** root-cause note `reports/multi_producer_rp2_store_visibility_bug.md` (rp2 store-visibility RTL bug — SW workaround shipped, RTL "Option A" scoped & deferred to the cache IP author).

### (no commit) weekly report assembled
- **Time:** 2026-05-31
- **File:** `reports/weekly_report_2026-05-31.md`
- **What:** Wrote the weekly report (rebase summary + this week's debug/verification incl. SpyGlass lint sign-off + per-kernel triage). Established this `WORKLOG.md` and the dev-log convention in `CLAUDE.md`.

---

## 2026-05-29

### `9349510` — [Lint] cluster: fix W110 user_i width mismatch; waive W123 false-positives
- **Time:** 2026-05-29 17:51 +0200 (commit)
- **Files:** `hardware/src/cachepool_cluster.sv`, `config/config.mk`, `util/lint/script/lint.tcl`
- **What:** Zero-extend `refill_user_t` to the `AxiUserWidth` `user_i` port of `reqrsp_to_axi` + `ASSERT_INIT(AxiUserWidth >= $bits(refill_user_t))`. DU-scoped W123 waivers for `cachepool_cache_ctrl` (coalescer_resp/bypass_resp driven via the `i_bypass_xbar` aggregate port binding) and `spatz_decoder` (third-party dep). Fixed a stale `axi_user_width` comment.
- **Why:** SpyGlass W110 width mismatch on the AXI user port (behavior-preserving but flagged a refill-misroute hazard at elaboration); W123 "read but never set" were false positives SpyGlass can't trace through aggregate bindings.
- **Verification:** SpyGlass `lint/lint_rtl` — clean Design Read; no undriven/multi-driven nets; no comb loops (after the CombLoop restructure). Report: `reports/SPYGLASS_LINT_ANALYSIS.md`.

### `3f7f8d8` — [VERIF] cc/tile/interco: wrap long lines + verible waivers for debug probes
- **Time:** 2026-05-29 15:53 +0200 (commit)
- **Files:** `hardware/src/cachepool_cc.sv`, `cachepool_tile.sv`, `tcdm_cache_interco.sv`
- **What/Why:** Verible style cleanup (long-line wrapping) + waivers on the sim-only debug probes. Cosmetic; no behavior change.

### `824a6ea` — [Bender] bump insitu-cache lock to tcdm_wrapper comb-loop fix (2710920)
- **Time:** 2026-05-29 15:25 +0200 (commit)
- **Files:** `Bender.lock`
- **What/Why:** Bumped the InsituCache dep to rev `2710920`, which carries the combinational-loop restructure of the skewed-fold bank request/grant path (purely combinational, no added register/latency). The comb loops were pre-existing, unmasked once the cache wrapper was un-blackboxed during SpyGlass cleanup.
- **Verification:** CombLoop-fix validation sweep `reports/sweep_2026-05-29_05-54/` — 4 configs × 37 tests; exactly one sb_violation (gemv-opt 4t-rp1, later shown a scoreboard false positive); 4t-rp2 zero violations; proven bit-identical to prior behavior in A/B.

---

## 2026-05-28

### `b43f2b4` — [VERIF] cc/tile: guard debug probes with ifndef TARGET_SYNTHESIS
- **Time:** 2026-05-28 14:12 +0200 (commit)
- **Files:** `hardware/src/cachepool_cc.sv`, `cachepool_tile.sv`
- **What/Why:** Re-guarded debug/probe blocks that were under `` `ifndef VERILATOR `` so they no longer leak into the synthesizable scope (caused SYNTH_* warnings). No behavior change.

### `ce53511` — [VERIF] cc: demote benign EOC write-ack FIFO tail to info
- **Time:** 2026-05-28 12:08 +0200 (commit)
- **Files:** `hardware/src/cachepool_cc.sv`
- **What/Why:** Demoted a benign end-of-sim write-ack FIFO-tail message from warning to info (noise reduction).

---

## Earlier this week (context, pre-log)

- **`4f41fd4`** — MSHR drain-count overflow fix in the InsituCache IP: widened the refill sub-array drain counter (`clog2(N+1)`→`clog2(N+2)`) so it no longer wraps 8→0 and drops pending miss responses under MSHR-full pressure. Verified across the config sweep (`reports/sweep_2026-05-26_01-05/`). Memory: `project-mshr-drain-fix`.
- Multiple **4-config RTL sweeps** (`reports/sweep_2026-05-24_*`, `…_05-26_*`, `…_05-28_*`, `…_05-29_*`) as fixes landed, with per-config `summary.tsv` + `SWEEP_REPORT.md`.
