# Control algorithm: best results

Best cycle counts of the full algorithm so far. The full history, the kernels
alone, the per-core profile and the hardware notes are in `RESULTS.md`; the
algorithm and the kernels are described in `README.md`.

Setup: `cachepool_fpu_4g`, one group of 16 cores, L1 private to the group
(xbar offset 6), Spatz with 4 IPUs per core and the VFU with the reduction
tree. Hot runs (inputs already in the L1), 1 GHz, so the 0.5 ms TTI is
500 000 cycles. IPU utilization is the multiply-accumulates of the products
divided by `cycles x cores x 4 lanes`. Every result passes the bit-exact
check against the reference model.

## Full algorithm

| M | N | Iterations | Cores | Total cycles | Products (cycles) | Products IPU util | Finalization | Per iteration, with / without update pass |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 64 | 128 | 16 of 128 | 16 | 114 719 | 57 240 | 71.5 % | 5 439 | 3 677 / 2 922 |
| 64 | 128 | 16 of 128 | 8 | 165 221 | 103 088 | 79.4 % | 6 209 | 4 521 / 2 697 |
| 64 | 128 | 32 of 128 | 16 | 166 954 | 58 245 | 70.3 % | 4 684 | 3 623 / 2 921 |
| 64 | 128 | 32 of 128 | 8 | 222 594 | 104 141 | 78.6 % | 6 164 | 4 271 / 2 835 |
| 64 | 128 | 128 | 16 | **463 827** | 57 576 | 71.1 % | 4 926 | 3 537 / 2 745 |
| 64 | 128 | 128 | 8 | 547 283 | 104 071 | 78.7 % | 7 143 | 4 213 / 2 625 |
| 63 | 37 | 37 | 4 | 133 559 | 33 264 | 60.0 % | 3 645 | 3 104 / 2 145 |
| 63 | 37 | 37, slow path | 4 | 410 957 | 32 987 | 60.5 % | 3 351 | 18 443 / 2 244 |
| 9 | 21 | 21 | 4 | 36 663 | 5 564 | 10.8 % | 1 593 | 1 558 / 1 266 |
| 9 | 21 | 21 | 1 | 50 523 | 10 662 | 22.6 % | 3 168 | 1 966 / 1 547 |

The products are U = R1 * R2, V = A * R and AR1 = A * R1: 2.10 M
multiply-accumulates at 64 x 128, 0.27 M at 63 x 37 and 0.01 M at 9 x 21. An
update pass (the rank-1 update of U and V and the new column maxima of S,
needed because R2 changes) runs after every odd iteration. The slow-path
inputs make most passes cross the R clamp margin, so the affected V columns
are recomputed; they are a stress test, not a benchmark input.

The 16-core rows at 64 x 128 (16 and 32 iterations) are the kernel before
the cleanup (current kernel at 16 iterations: 116 545). The 8-core row at 16
iterations is the kernel without the speculative power update (the current
kernel takes 166 313 there, and is faster at 32 iterations). The
128-iteration rows are the current kernel (before the cleanup: 462 905 on 16
cores, 551 174 on 8). The cleanup changes no algorithm step, but it moves the
code and data addresses, which alone changes the totals by up to about
1.5 %. The 63 x 37 row is the kernel without the speculative power update
(current kernel: 134 939). The 9 x 21 rows and the slow path are older
kernels: the helper core and the late U update do not pay off at 9 x 21
(current kernel: 43 576 on 4 cores, 54 035 on 1).

## Against the TTI (M = 64, N = 128, all 128 iterations)

| Cores | Measured (hot) | First run (inputs not in the L1) | TTI | Ratio (hot) |
| --- | --- | --- | --- | --- |
| 16 | **463 827** | 477 719 | 500 k | **0.93 x** |
| 8 | 547 283 | 562 943 | 500 k | 1.09 x |
| 16, previous kernel | 539 101 | | 500 k | 1.08 x |
| 8, previous kernel | 586 236 | | 500 k | 1.17 x |

On 16 cores (one group) the full algorithm meets the 0.5 ms TTI with about
36 k cycles to spare, and also on the first run. The steps since the
previous kernel, all bit-exact: V and P placed on different L1 cache
controllers with a staggered column order per core (pass -730 cycles on 16
cores), the late U update shared in half rows, allocated columns marked in
the per-core column index table (selection -175 per call), and a
speculative power update computed by the idle cores before each pass
iteration (pass iterations -800). The numbers on `cachepool_fpu_16g` are
still to come.

## Kernels alone (M = 64, N = 128, hot)

| Kernel | Cores | Cycles | IPU util |
| --- | --- | --- | --- |
| Products U and V (`uv-init`) | 16 | 39 964 | 81.9 % |
| Products U and V (`uv-init`) | 8 | 73 383 | 89.3 % |
| Gain over all of M x N (`gain-select`) | 1 | 45 181 | 95.1 % |
| Power update of one winner (`power-update`) | 1 | about 535 | |
| `vredmax` at vl 64 (one-core probe) | 1 | 75 (276 on the old VFU) | |
