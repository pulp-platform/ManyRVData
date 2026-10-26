# Control algorithm: results

Cycle counts of the kernels in this directory (see `README.md` for the
algorithm and the kernel chain). This is the state of the work so far: the
full M = 64, N = 128 run on 16 cores and the 16-group numbers are still to
come. `RESULTS_SUMMARY.md` has only the best numbers.

## Setup

| Item | Value |
| --- | --- |
| Configuration | `cachepool_fpu_4g` (4 groups of 16 cores) |
| Spatz | 4 IPUs per core, ELEN 32, VLEN 512, 8 vector instructions in flight |
| VFU | with the reduction tree for the `vredmax` rows (see Hardware below); the other rows give the same cycles on both VFUs |
| L1 | private to the group (`L1D_FOLD_GROUP`), xbar offset 6 |
| Cores | 1 to 16 cores of one group; no data leaves the group, no flush |
| Clock | 1 GHz, so the 0.5 ms TTI is 500 000 cycles |
| Runs | run 0 is the first touch of the inputs, run 1 is hot; hot numbers below |

IPU utilization is the number of multiply-accumulates divided by
`cycles x cores x 4 lanes`. Every result below passes the bit-exact check
against `common/golden.py`: P, ResAllocMap, UserResAllocMap and the winner of
every iteration.

## Problem sizes

| Test | M | N | Iterations | Products (MAC) | Note |
| --- | --- | --- | --- | --- | --- |
| `64_128` | 64 | 128 | 128 | 2.10 M | benchmark size (above the N <= 100 range) |
| `64_128_i16` | 64 | 128 | 16 | 2.10 M | first 16 iterations of `64_128` |
| `64_128_i<n>w` | 64 | 128 | 8, 16, 32 | 2.10 M | first n iterations, run 0 only a warm-up (products and 2 iterations) |
| `63_37` | 63 | 37 | 37 | 0.27 M | odd sizes, vl not a multiple of 4 |
| `63_37_mix` | 63 | 37 | 37 | 0.27 M | inputs that hit the clamp often (slow path) |
| `9_21` | 9 | 21 | 21 | 0.01 M | small case |

The products are U = R1 * R2 (N x M x N), V = A * R (M x N x N) and
AR1 = A * R1 (M x N x M).

## Full algorithm

### M = 64, N = 128, all 128 iterations

| Version | Cores | Total | Products | IPU util | Finalization | Per iteration |
| --- | --- | --- | --- | --- | --- | --- |
| two barriers per iteration | 8 | 738 711 | 101 721 | 80.5 % | 7 883 | 4 251 after odd, 2 535 after even |
| fused update + selection | 8 | 703 271 | 100 132 | 81.8 % | 6 674 | 5 706 after odd, 1 595 after even |
| one barrier per iteration | 8 | 710 658 | 101 265 | 80.8 % | 7 994 | 5 561 with a pass, 3 867 without |
| late U update and helper core (optimization 13) | 8 | 586 236 | 100 325 | 81.6 % | 7 301 | 4 815 with a pass, 2 695 without |
| late U update and helper core (optimization 13) | 16 | 539 101 | 58 400 | 70.1 % | 7 012 | 5 065 with a pass, 2 377 without |
| optimizations 14 to 17, before the cleanup | 8 | 551 174 | 104 879 | 78.1 % | 7 118 | 4 167 with a pass, 2 716 without |
| optimizations 14 to 17, before the cleanup | 16 | 462 905 | 59 309 | 69.0 % | 5 073 | 3 505 with a pass, 2 733 without |
| current kernel | 8 | **547 283** | 104 071 | 78.7 % | 7 143 | 4 213 with a pass, 2 625 without |
| current kernel | 16 | **463 827** | 57 576 | 71.1 % | 4 926 | 3 537 with a pass, 2 745 without |

Hot runs. The first run of the current kernel, with the inputs not yet in the
L1, takes 477 719 cycles on 16 cores and 562 943 on 8. The cleanup (removal
of the stage kernels and probes the full kernel no longer needs, no change
to the algorithm) moves the code and data addresses; this alone changes the
totals by up to about 1.5 % (also the products, whose code is the same). The 32-iteration runs
projected 482 k and 565 k for the current kernel (550 k and 586 k for the
kernel of optimization 13, against 539 k and 586 k measured).

### M = 64, N = 128, first 16 iterations

| Version | Cores | Total | Products | IPU util | Finalization | Per iteration (pass / no pass) |
| --- | --- | --- | --- | --- | --- | --- |
| one barrier | 8 | 178 389 | 100 300 | 81 % | | |
| one barrier | 16 | 134 897 | | | | |
| top-2 selection | 16 | 127 749 | | | | |
| top-2 + clamp-free U + power update from V, rows-of-8 products | 8 | 175 227 | 104 254 | 78.5 % | 6 250 | 5 085 / 3 236 |
| top-2 + clamp-free U + power update from V, rows-of-8 products | 16 | 129 508 | 60 386 | 67.8 % | 5 887 | 5 397 / 2 827 |
| top-2 + clamp-free U + power update from V | 16 | **124 350** | 59 242 | 69.1 % | 5 843 | 4 851 / 2 811 |
| + overlapped power update | 16 | 126 189 | 59 543 | 68.7 % | 6 201 | 5 127 / 2 728 |
| + overlapped power update, per-core key slots | 8 | 170 877 | 101 241 | 80.9 % | 6 275 | 5 069 / 3 096 |
| + overlapped power update, per-core key slots | 16 | 125 259 | 56 538 | 72.4 % | 6 351 | 5 432 / 2 704 |
| + per-core tables | 8 | 169 914 | 101 134 | 81.0 % | 6 245 | 4 977 / 3 077 |
| + per-core tables | 16 | 124 602 | 59 417 | 68.9 % | 5 925 | 5 125 / 2 597 |
| + `vredmax`, result through memory | 8 | 168 778 | 100 159 | 81.7 % | 6 166 | 4 996 / 3 052 |
| + `vredmax`, result through memory | 16 | 123 585 | 58 934 | 69.5 % | 5 481 | 5 108 / 2 601 |
| + `vredmax`, result with `vmv.x.s` | 8 | **167 394** | 100 097 | 81.8 % | 6 176 | 4 909 / 2 972 |
| + `vredmax`, result with `vmv.x.s` | 16 | **121 496** | 56 235 | 72.8 % | 6 038 | 5 186 / 2 546 |
| same, warm-up run (`i16w`) | 16 | 123 929 | 58 930 | 69.5 % | 5 796 | 5 185 / 2 545 |
| + U rows of the pass shared evenly (`i16w`, with the profile timers) | 16 | 125 216 | 55 987 | 73.1 % | 5 717 | 5 340 / 2 903 |
| + U rows of the pass shared evenly (`i16w`, with the profile timers) | 8 | 175 227 | 101 671 | 80.5 % | 6 645 | 5 361 / 3 264 |
| + late U update and helper core (`i16w`, with the profile timers) | 16 | 125 889 | 60 138 | 68.1 % | 5 981 | 4 897 / 2 832 |
| + late U update and helper core (`i16w`, with the profile timers) | 8 | 170 889 | 102 126 | 80.2 % | 6 253 | 5 204 / 2 897 |
| + late U update and helper core (`i16w`) | 16 | 122 329 | 56 459 | 72.5 % | 6 755 | 5 184 / 2 535 |
| + late U update and helper core (`i16w`) | 8 | 165 489 | 100 920 | 81.1 % | 6 580 | 4 863 / 2 660 |
| + V and P apart in the L1, padded per-core buffers (`i16w`) | 16 | 118 983 | 56 374 | 72.6 % | 5 006 | 5 015 / 2 499 |
| + V and P apart in the L1, padded per-core buffers (`i16w`) | 8 | 166 563 | 102 300 | 80.0 % | 6 289 | 4 748 / 2 748 |
| + strip stagger of the odd cores (`i16w`) | 16 | 117 810 | 58 264 | 70.3 % | 5 266 | 4 451 / 2 568 |
| + strip stagger of the odd cores (`i16w`) | 8 | 165 268 | 101 131 | 81.0 % | 6 514 | 4 714 / 2 735 |
| + late U split into half rows (`i16w`) | 16 | 117 851 | 56 614 | 72.3 % | 5 464 | 4 595 / 2 622 |
| + late U split into half rows (`i16w`) | 8 | 169 502 | 104 061 | 78.7 % | 6 684 | 4 769 / 2 819 |
| + allocated columns marked in the column index table (`i16w`) | 16 | 116 871 | 58 171 | 70.4 % | 5 092 | 4 457 / 2 489 |
| + allocated columns marked in the column index table (`i16w`) | 8 | **165 221** | 103 088 | 79.4 % | 6 209 | 4 521 / 2 697 |
| + speculative power update, every idle core (`i16w`) | 16 | 114 510 | 57 353 | 71.4 % | 5 391 | 3 594 / 2 956 |
| + speculative power update, every idle core (`i16w`) | 8 | 166 258 | 104 306 | 78.5 % | 6 344 | 4 188 / 2 921 |
| + speculative power update, only cores without a larger published key (`i16w`) | 16 | 114 719 | 57 240 | 71.5 % | 5 439 | 3 677 / 2 922 |
| + speculative power update, only cores without a larger published key (`i16w`) | 8 | 166 313 | 104 141 | 78.6 % | 6 228 | 4 230 / 2 925 |
| current kernel (after the cleanup, `i16w`) | 16 | **116 545** | 58 034 | 70.5 % | 5 582 | 3 618 / 3 066 |
| current kernel (after the cleanup, `i16w`) | 8 | 166 313 | 104 141 | 78.6 % | 6 228 | 4 230 / 2 925 |

Blank cells: those runs had a timer race (all cores added to the same
counters), so only their totals are valid. The products do not use the
reductions; their spread (56 k to 59 k on 16 cores) is the run-to-run
variation of the L1 and the crossbar, and it accounts for most of the
difference between the last 16-core rows.

8 measured iterations (`i8w`, 16 cores): 92 037 cycles with the `vmv.x.s`
version (5 152 / 2 519 per iteration). Going from 8 to 16 iterations adds
31 147 cycles of iterations, 3.89 k per iteration, which agrees with the
average of the two per-iteration numbers of the 16-iteration runs.

The rows with the profile timers are slower than the same kernel without
them and are only compared with each other.

### M = 64, N = 128, first 32 iterations

| Version | Cores | Total | Products | IPU util | Finalization | Per iteration (pass / no pass) |
| --- | --- | --- | --- | --- | --- | --- |
| late U update and helper core (optimization 13) | 16 | 182 527 | 57 283 | 71.5 % | 6 184 | 5 118 / 2 487 |
| late U update and helper core (optimization 13) | 8 | 225 102 | 100 693 | 81.3 % | 6 984 | 4 824 / 2 650 |
| + L1 layout, strip stagger, late U in half rows (optimizations 14, 15) | 16 | 173 338 | 56 614 | 72.3 % | 5 111 | 4 524 / 2 572 |
| + L1 layout, strip stagger, late U in half rows (optimizations 14, 15) | 8 | 225 374 | 99 847 | 82.0 % | 7 022 | 4 681 / 2 840 |
| optimizations 14 to 17, before the cleanup | 16 | **166 954** | 58 245 | 70.3 % | 4 684 | 3 623 / 2 921 |
| optimizations 14 to 17, before the cleanup | 8 | **222 594** | 104 141 | 78.6 % | 6 164 | 4 271 / 2 835 |

For the kernel of optimization 13:

From 16 to 32 iterations the total grows by 60 198 cycles on 16 cores and
59 613 on 8, 3.76 k and 3.73 k per iteration, which agrees with the
per-iteration numbers (3.80 k and 3.74 k on average). The cost per iteration
stays constant, so the 32-iteration runs are used for the projection. 8
measured iterations (`i8w`, 16 cores) take 89 976 cycles (4 759 / 2 712).

### M = 63, N = 37, 4 cores

| Version | Total | Products | IPU util | Per iteration (pass / no pass) |
| --- | --- | --- | --- | --- |
| fused update + selection | 146 600 | | | |
| one barrier | 154 200 | | | |
| top-2 selection | 145 681 | 34 557 | 57.7 % | 3 347 / 2 498 |
| + clamp-free U, power update from V | 142 995 | 33 108 | 60.2 % | 3 324 / 2 454 |
| + overlapped power update | 140 234 | 33 197 | 60.1 % | 3 276 / 2 354 |
| + per-core key slots | **139 072** | 32 867 | 60.7 % | 3 246 / 2 340 |
| + per-core tables | 139 366 | 33 014 | 60.4 % | 3 253 / 2 340 |
| + `vredmax`, result through memory | 137 989 | | | |
| + `vredmax`, result with `vmv.x.s` | **135 705** | 33 023 | 60.4 % | 3 144 / 2 251 |
| + U rows of the pass shared evenly | 137 247 | 33 154 | 60.2 % | 3 225 / 2 245 |
| + late U update | 135 439 | | | 3 089 / 2 282 |
| + helper core | 134 295 | 33 578 | 59.4 % | 3 164 / 2 114 |
| + L1 layout, strip stagger, late U in half rows | 137 627 | | | 3 196 / 2 230 |
| + allocated columns in the column index table | **133 559** | 33 264 | 60.0 % | 3 104 / 2 145 |
| + speculative power update | 133 613 | 33 392 | 59.7 % | 3 071 / 2 175 |
| current kernel (after the cleanup) | 134 939 | 33 933 | 58.8 % | 3 102 / 2 179 |

### M = 9, N = 21

| Version | Cores | Total | Products | IPU util | Per iteration (pass / no pass) |
| --- | --- | --- | --- | --- | --- |
| one barrier | 1 | 59 700 | | | |
| top-2 selection | 1 | 56 692 | 11 010 | 21.8 % | 2 243 / 1 803 |
| + overlapped power update | 1 | **53 240** | 10 574 | 22.7 % | 2 114 / 1 679 |
| + per-core tables | 1 | 53 653 | 10 840 | 22.2 % | 2 116 / 1 680 |
| + `vredmax`, result through memory | 1 | 51 920 | | | |
| + `vredmax`, result with `vmv.x.s` | 1 | **50 523** | 10 662 | 22.6 % | 1 966 / 1 547 |
| + U rows shared evenly | 1 | 51 504 | 11 408 | 21.1 % | 1 968 / 1 569 |
| + late U update and helper core | 1 | 54 523 | 11 164 | 21.5 % | 2 035 / 1 772 |
| + allocated columns in the column index table | 1 | 53 225 | 10 849 | 22.0 % | 2 074 / 1 684 |
| + speculative power update | 1 | 53 802 | | | |
| current kernel (after the cleanup) | 1 | 54 035 | 11 132 | 21.6 % | 2 026 / 1 729 |
| one barrier | 4 | 46 500 | | | |
| top-2 selection | 4 | 42 539 | 6 121 | 9.8 % | 1 769 / 1 548 |
| + overlapped power update | 4 | 40 676 | 6 365 | 9.4 % | 1 670 / 1 452 |
| + per-core key slots | 4 | 40 315 | 6 536 | 9.2 % | 1 674 / 1 407 |
| + per-core tables | 4 | 39 405 | 5 386 | 11.1 % | 1 658 / 1 442 |
| + `vredmax`, result through memory | 4 | 38 249 | | | |
| + `vredmax`, result with `vmv.x.s` | 4 | **36 663** | 5 564 | 10.8 % | 1 558 / 1 266 |
| + U rows shared evenly | 4 | 37 501 | 6 364 | 9.4 % | 1 554 / 1 260 |
| + late U update | 4 | 38 894 | | | 1 607 / 1 346 |
| + helper core | 4 | 43 343 | 6 315 | 9.5 % | 1 727 / 1 615 |
| + L1 layout, strip stagger, late U in half rows | 4 | 43 844 | | | 1 750 / 1 601 |
| + allocated columns in the column index table | 4 | 41 934 | 6 525 | 9.2 % | 1 680 / 1 515 |
| + speculative power update | 4 | 43 576 | 6 420 | 9.3 % | 1 716 / 1 630 |
| current kernel (after the cleanup) | 4 | 43 576 | 6 420 | 9.3 % | 1 716 / 1 630 |

At this size the products are too small to fill the IPUs; the cost is the
21 iterations of selection and power update. The late U update and the
helper core cost more than they save at this size, so small sizes should
run without them.

### Slow path (`63_37_mix`, 4 cores)

| Version | Total | Per iteration (pass / no pass) |
| --- | --- | --- |
| two barriers | 421 600 | |
| one barrier | 438 800 | |
| top-2 selection | 423 609 | 18 830 / 2 499 |
| + clamp-free U, power update from V | 435 554 | 19 083 / 2 475 |
| + overlapped power update | 417 033 | 18 663 / 2 367 |
| + overlapped power update, per-core key slots | **416 281** | 18 646 / 2 342 |
| + per-core tables | 416 340 | 18 652 / 2 343 |
| + `vredmax`, result through memory | 417 736 | 18 760 / 2 313 |
| + `vredmax`, result with `vmv.x.s` | 412 066 | 18 485 / 2 254 |
| + U rows shared evenly | **410 957** | 18 443 / 2 244 |
| + late U update | 413 763 | 18 557 / 2 256 |
| + helper core | 414 272 | 18 704 / 2 115 |
| + L1 layout and strip stagger | 417 623 | 18 725 / 2 223 |
| + allocated columns in the column index table | 411 979 | 18 538 / 2 125 |
| + speculative power update | 413 416 | 18 556 / 2 175 |
| current kernel (after the cleanup) | 413 416 | 18 556 / 2 175 |

With these inputs most update passes cross the clamp margin, so the V
columns are recomputed (`it_fix_cols`) and the selection is redone. This is
the worst case and is not part of the benchmark inputs. It is also the test
of the late U update: before the initial margin check (optimization 12) it
gave a wrong winner in iteration 2.

All the `63_37_mix` runs, and some `63_37` and `9_21` runs of older kernels,
report an L1 scoreboard data mismatch about 68 k (22 k at 9 x 21) cycles
after reset, before the first iteration; the outputs still pass the check.

## Kernels alone (M = 64, N = 128, hot)

| Kernel | Cores | Cycles | IPU util |
| --- | --- | --- | --- |
| Products U+R and V+G (`uv-init`) | 8 | 73 383 | 89.3 % |
| Products U+R and V+G (`uv-init`) | 16 | 39 964 | 81.9 % |
| Gain + selection, one full pass (`gain-select`) | 1 | 46 303 | 95.1 % (gain) |
| Gain + selection, one full pass (`gain-select`) | 4 | 13 172 | 89.9 % (gain) |
| Gain + selection, one full pass (`gain-select`) | 8 | 7 552 | 86.7 % (gain) |
| Gain + selection, one full pass (`gain-select`) | 16 | 5 974 | 61.7 % (gain) |
| Update + gain after an odd iteration (`update-gain`, removed) | 4 | 22 692 | 74.4 % (pass) |
| Update + gain after an odd iteration (`update-gain`, removed) | 8 | 14 012 | 63.9 % (pass) |
| Power update of one winner (`power-update`) | 1 | 533 to 539 | |

`uv-init` computes U and V only; the products of the full kernel also
include AR1 = A * R1 and the first colS, hence the larger counts above. The
`update-gain` kernel (and the `uv-update` kernel it was built on) have been
removed: their update pass is part of `full` (`it_pass`), which no longer
evaluates the gain in the pass.

The full kernel does not run the full-width gain pass every iteration: it
keeps the gain lazily per column (colS), so most iterations only touch the
winner's row and the candidate columns.

## Optimizations, in order

1. **Restructured products.** U and V are computed once and updated with a
   rank-1 correction after each odd iteration (see `README.md`), instead of
   2.1 M multiply-accumulates per iteration.
2. **Group-private L1.** All the data stays in the L1 of one group (fold
   `GROUP`, xbar offset 6): with a tile-private L1, U and V on 16 cores took
   157 k cycles (20.8 % IPU util), with the group L1 40 k (81.9 %).
3. **Packed keys, no masks.** Gain and user are packed into one key and
   reduced with element-wise `vmax`, as Spatz has no masks.
4. **Lazy gain per column.** Each core keeps the best key of each of its
   columns (colS) and recomputes it only where P or V changed.
5. **One barrier per iteration.** Every core selects the winner from the
   per-core keys of the previous iteration and marks the subcarrier itself,
   so no second barrier is needed to publish the result.
6. **Top-2 selection.** One slide tree over the packed keys gives the best
   and the second-best column. If the second is below a conservative bound
   of the best's threshold, the best column is the only candidate and the
   exact candidate loop is skipped.
7. **Clamp-free U rows.** The U rows that cannot reach the R clamp are found
   once after the products; the update pass skips their clamp check.
8. **Power update from V.** The owner of row w recomputes G of the winner's
   row from V and overlaps the two strips of the power update, so it waits on
   one store fence instead of two.
9. **Per-core key slots and tables.** Each core writes its key to its own
   64 B slot and keeps its own copy of ResAllocMap and the index tables, so
   the 16 cores do not load the same line every iteration.
10. **`vredmax` instead of the slide trees.** With the reduction tree in the
    VFU, the maxima of the selection are one `vredmax` each, and the result
    is read with `vmv.x.s` instead of a store, fence and load. The top-2 is
    two reductions: the best key, then the best of the other lanes.
11. **U rows of the pass shared evenly.** The pass updates only the U rows
    that can reach the clamp, and their number differs between the blocks
    of the cores; each core now takes an equal share of all of them. Neutral
    (see the profile below).
12. **Late U update.** One pass changes U by at most 50 (|R1| <= 50), and the
    margin is `MaxR - 50`, so the V update of a pass is exact if U was inside
    the margin before it. The U update and its margin check therefore move
    from the pass iteration to the next iteration (without a pass), where
    the cores other than the owner and the helper run them. A margin check
    of U after the products makes sure U starts inside the margin; if it
    does not, the U update stays in the pass.
13. **Helper core.** In an iteration without a pass only row w of P changed
    and the next iteration rebuilds colS anyway, so the owner of w skips
    row w in its colS and candidates. The first core whose best column of
    the previous iteration is not k* (the helper) runs the power update and
    the exact key of row w; the cores whose best column is not k* reuse
    their key of the previous iteration.
14. **L1 layout and strip stagger.** The L1 of a group interleaves 64 B
    lines over its 16 cache controllers, so addresses 1 KiB apart share a
    controller. With rows of 512 B, every V and P row started at controller
    0 or 8, V and P at the same offset, and all cores streamed the same 8
    controllers in the pass. V and P now sit 256 B apart modulo 1 KiB, the
    per-core buffers have a pitch of N + 16 words, and the odd cores run the
    second strip of columns first. The pass time per core went from 2.5 k to
    3.7 k cycles (spread 1.2 k) to 2.3 k to 2.5 k, about -730 cycles per
    pass iteration on 16 cores.
15. **Late U update in half rows.** The late U rows were shared by whole
    rows, so with about 2.5 rows per core the shares alternated between 2
    and 3 rows; they are now shared in strips of half a row.
16. **Allocated columns in the column index table.** Each core sets the
    sign bit of `kidx[k*]` instead of reading its copy of ResAllocMap in the
    selection, so the packed key of a strip is one load, an AND, a load and
    an OR. The top-2 part of the selection went from about 580 to 405
    cycles per call.
17. **Speculative power update.** The owner of the winner of an iteration
    without a pass ran the power update (about 1 k cycles) before its pass
    in the next iteration, and was the slowest core there. Now, in the
    iteration without a pass, each core other than the owner and the helper
    computes the power update of its own best key into a buffer while it
    would wait at the barrier, unless a larger key of that iteration is
    already published (the winner always qualifies); the owner then only
    copies the row. Pass iterations went from about 4.5 k to 3.6 k cycles on
    16 cores, iterations without a pass from 2.5 k to 2.9 k.

Tried and dropped:
- rows-of-8 blocking of the products (no gain at 64 x 128, slower at
  63 x 37);
- software prefetch of the next U rows in the update pass (fills the
  8-instruction window and stalls compute, 5-14 % slower);
- moving the U rows of the winner's owner, which also runs the power update,
  to the next core (+600 cycles per pass iteration: that core became the
  slowest) or to all the other cores (+860 cycles over 8 iterations);
- a second-largest S per column kept in the pass, with the row of the
  largest packed into colS, so that the owner drops row w instead of
  rebuilding its colS after an iteration without a pass: the owner saved
  about 470 cycles there, but the 4 extra vector ops per row made the pass
  slower (+340 cycles per pass iteration on 16 cores, +950 on 8).

## Where the time goes (64 x 128, 16 cores, hot)

This profile is of the kernel before optimizations 12 and 13; the change
they make is below the table.

Products: about 56 k to 59 k cycles (69 to 73 % IPU util). Per-core profile
of the 16 hot iterations (`ctrl-full_64_128_i16w_C16_prof`, `vmv.x.s`
version), cycles per iteration:

| Phase | With a pass: other cores | With a pass: owner | Without a pass: other cores | Without a pass: owner |
| --- | --- | --- | --- | --- |
| Winner pick and power update | 250 to 600 | 1 328 | 270 to 420 | 1 115 |
| Update pass / colS of the owner's rows | 2 453 to 3 668 | 2 452 | 81 to 193 | 893 |
| Candidate selection (`it_cands`) | 843 to 1 035 | 1 012 | 983 to 1 076 | 861 |
| Barrier wait | 299 to 1 161 | 323 | 1 362 to 1 635 | 118 |

- **With a pass** (every other iteration), the slowest cores are the ones
  with the longest pass, not the owner of the winner. The pass time differs
  by up to 1.2 k cycles between cores although every core has the same work
  (4 V rows, and an equal share of the U rows since optimization 11), so the
  spread most likely comes from the memory system: bank conflicts between
  cores that access the same row offsets, or set conflicts of the arrays in
  the 4-way L1 (U, V, P and R2 are powers of two in size). The L1 has no
  hit or miss counters to confirm it.
- **Without a pass**, the owner is the critical path: power update, colS of
  its rows (only row w changed) and its selection, about 2.9 k cycles, while
  the other cores wait about 1.5 k at the barrier.

With the late U update and the helper core (same profile, kernel of optimization 13),
in an iteration without a pass the owner takes 583 (winner pick), 885
(colS), 1 028 (candidates) and 404 (barrier) cycles, the other cores
spend 500 to 1 400 cycles on their late U rows and 120 to 450 on their
candidates, and they wait 560 to 1 560 at the barrier. The owner's
candidates and the uneven late U rows are the next limits.

Current kernel (optimizations 14 to 17, `ctrl-full_64_128_i16w_C16_prof`,
whose timers add about 4 k cycles over the 16 iterations), cycles per
iteration:

| Phase | With a pass: other cores | With a pass: owner | Without a pass: other cores | Without a pass: owner |
| --- | --- | --- | --- | --- |
| Winner pick and power update (owner: copy of the speculative row) | 415 to 492 | 691 | 465 to 655 | 547 |
| Update pass / late U update / colS of the owner's rows | 2 122 to 2 219 | 2 012 | 938 to 1 505 | 1 218 |
| Candidate selection (and the speculative power update without a pass) | 757 to 923 | 908 | 671 to 913 | 906 |
| Barrier wait | 166 to 456 | 157 | 429 to 960 | 664 |

The pass now takes about the same time on every core, and the owner is no
longer behind in either kind of iteration. Without a pass, the helper core
takes 1 335 (winner pick and power update of w), 128, 1 240 (its key and
the exact key of row w) and 564 (barrier) cycles. Every core, the helper
included, waits at least 430 cycles at the barrier on average, so the
slowest core changes from one iteration to the next (the late U shares, the
speculative power updates and the helper move between cores).

The selection itself (`ctrl-full_64_128_i16w_C16_cprof`) takes, per call,
about 405 cycles for the top-2 of the column keys, 45 for the rest of the
candidate search and 280 for the exact keys; nearly every call (100 % on
15 of the 16 cores) has a single candidate column.

Within the power update (about 850 cycles in an earlier profile), about 500
are the two vector strips, about 270 the store fence and about 125 scalar
code and the divide.

## Hardware

Measured with a one-core probe (removed since; through memory unless noted):

| Operation | Old VFU | VFU with the reduction tree |
| --- | --- | --- |
| `vredmax` at vl 64 | 276 cycles | 75 cycles |
| `vredmax` at vl 37 | 103 cycles | 52 cycles |
| `vmv.x.s` right after a reduction | stale value (0 or older) | correct |
| `vslidedown` by 1 at vl 64 | 33 cycles | 33 cycles |
| one slide-by-half + `vmax` step | 27 cycles | 27 cycles |

Fixes in `hardware/deps/spatz` found while developing these kernels:
- `spatz_vfu.sv`: `scalar_result` was gated with the instruction at the head
  of the VFU, not the one whose result leaves the units, so `vmv.x.s`
  returned 0 when the next instruction had already arrived; now gated with
  `result_tag.last` as well.
- `spatz_vfu.sv`: `is_fpu_busy` also covers the FPU input register and the
  cycle a word enters the FPU, so a single-word FPU instruction is not cut
  off by an early switch back to the IPUs (hang at vl <= 4).
- `spatz_controller.sv`: `vslidedown` must not chain on its producer (it
  reads ahead of the element it writes).
- Open: `vloxei32` hangs when vl is not a multiple of 4 (the kernels keep
  vl a multiple of 4 for gathers).

## Against the TTI

| Cores | 128 iterations, measured (hot) | First run (inputs not in the L1) | TTI | Ratio (hot) |
| --- | --- | --- | --- | --- |
| 16 | **463 827** | 477 719 | 500 k | **0.93 x** |
| 8 | 547 283 | 562 943 | 500 k | 1.09 x |

On 16 cores the current kernel meets the TTI with about 36 k cycles to spare
(22 k for the first run). An update pass runs after every odd iteration, so
128 iterations are 64 with a pass and 64 without. On 8 cores it needs about
370 cycles less per iteration. The kernel of optimization 13 took 539 101
cycles on 16 cores (1.08 x) and 586 236 on 8 (1.17 x).

## Status

- Numbers on `cachepool_fpu_16g`: pending (all numbers here are on 4 groups,
  using one group).
