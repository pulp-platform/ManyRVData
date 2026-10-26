# Control algorithm

Greedy subcarrier and power allocation for an uplink OFDMA system, based on
K. Kim et al., "Iterative and greedy resource allocation in an uplink OFDMA
system", PIMRC 2004. The benchmark extends the paper's algorithm with
synthetic matrix stages (R and G below) that make the gains of every user
change with each allocation. The algorithm runs once per 0.5 ms TTI, which is
500 000 cycles at 1 GHz; the target is to fit that budget with as few cores as
possible.

## Inputs and outputs

| Name | Shape | Range |
| --- | --- | --- |
| M | scalar | [1, 80] users |
| N | scalar | [1, 100] subcarriers |
| R1 | N x M | [-50, 50] |
| R2 | M x N | 0 or 1 |
| A | M x N | [-3000, 3000] |
| C | N x N | [-3000, 3000] |
| D | N | [-3000, 3000] |

All values are integers. The outputs are the subcarrier allocation
`ResAllocMap[N]` and `UserResAllocMap[M][N]` (0 or 1) and the power allocation
`P[M][N]`.

## Algorithm

Everything is 32-bit integer arithmetic. Power values (P and the per-user
water level Delta) are fixed point, scaled by 100, and every division
truncates.

```
P = 100, Delta = 100, ResAllocMap = 0, UserResAllocMap = 0
for j in 0 .. N-1, while some subcarrier is free:
  R = clamp(R1 * R2 + C, MinR, MaxR)                    N x N
  G = clamp((A * R + D) >> 7, MinG, MaxG)                M x N
  S = P .* G,  Gain = ln(1 + S)
  (w, k*) = the user and free subcarrier with the largest Gain
  allocate k* to w and update P[w][:]                   (power update)
  R2[w][:] = (R2[w][:] + j) % 2
finalize: recompute P of every allocated (user, subcarrier)
```

| Parameter | Value |
| --- | --- |
| MinR, MaxR | -4096, 4096 |
| MinG, MaxG | 1, 2^20 |

Ties go to the lowest subcarrier within a user, then to the lowest user.

### Gain

Gain is `ln(1 + S)` in Q16, computed with 32-bit integer operations:

```
1 + S = 2^e * m, m in [1, 2)      exponent and mantissa bits of float(1 + S)
u     = (m - 1.5) * 2/3           |u| <= 1/3
ln m  = ln 1.5 + u - u^2/2 + u^3/3   (degree-3 Taylor series, Horner in Q30)
Gain  = e * ln 2 + ln m           (summed in Q24, rounded to Q16)
```

The int-to-float conversion is the only floating-point operation; it finds
the exponent, as Spatz has no count-leading-zeros instruction. The error is
below 4.3e-3 against the exact ln(1 + S).

With these ranges and N <= 128, every intermediate fits in int32:
`|R1 * R2 + C| <= 7000`, `|A * R + D| <= 1.58e9` and `S <= 1.05e8`. The shift
by 7 keeps G well inside [MinG, MaxG].

## Benchmark size

The kernels are benchmarked at M = 64 users and N = 128 subcarriers. N is
above the range's 100, so this is more work than any allowed input (the
initial products are 2.1 M multiply-accumulates against 1.6 M at M = 80,
N = 100). The power-of-two sizes split into whole four-row blocks over 1, 2,
4, 8 and 16 cores, so every core gets the same work.

### Power update

Each user has a total power of 1 (100 scaled). With `inv(g) = 100 / g`, `n`
the number of subcarriers of user w after the allocation and `g` its row of
G:

```
sum      = 100 + sum of inv(g[k]) over the subcarriers k of w
Delta[w] = sum / n
P[w][k*] = max(0, Delta[w] - inv(g[k*]))
for every free subcarrier k:
  P[w][k] = max(0, (sum + inv(g[k])) / (n + 1) - inv(g[k]))
```

Finalization applies the first two lines to every user with at least one
subcarrier, using the final G. Users with no subcarriers keep their P row.

On the paper's example (two users, three subcarriers, gains 8 4 2 and 4 2 1)
this gives P = 69, 31 and 100 and Delta = 81 and 150, against the exact
68.75, 31.25, 100, 81.25 and 150.

## Restructured algorithm

R and G do not depend on the user. `(x + j) % 2` keeps R2 for even j and
flips row w for odd j, so R2 changes in one row only after odd iterations, by
`s = +1` or `-1` per column. The kernels therefore keep the unclamped products
and update them instead of recomputing:

```
U = R1 * R2 + C          R = clamp(U)
V = A * R + D            G = clamp(V >> 7)
after an odd iteration with winner w:
  U += R1[:, w] * s^T
  V += (A * R1[:, w]) * s^T, in the columns where no R clamp is involved
  V[:, k] = A * R[:, k] + D[k], in the other columns
```

For M = 64 and N = 128 this is 2.1 M multiply-accumulates once, then about
33 k operations per odd iteration, instead of 2.1 M per iteration.

## Kernels

| Kernel | Directory | Work |
| --- | --- | --- |
| Full algorithm | `full` | the whole algorithm on up to 16 cores of one group, one barrier per iteration (the benchmark) |
| Products | `uv-init` | U, R, V and G from the inputs (two int32 GEMMs with clamps), alone |
| Gain and selection | `gain-select` | Gain = ln(1 + P .* G) over all of M x N and the argmax over free subcarriers, alone |
| Power | `power-update` | power update of one winner and finalization, alone |

`full` uses the products of `uv-init`, the integer log of `gain-select` and
the power update tables of `power-update`; the stage kernels measure those
parts on their own. Cycle counts and utilization are in `RESULTS.md`, the
best results in `RESULTS_SUMMARY.md`.

In `gain-select`, the selection uses neither masks nor reductions: each Gain
is packed with its user into `key = Gain << 7 | (127 - i)`, an element-wise
`vmax` over the rows keeps the best key of every column, and a scalar scan
over the columns skips the allocated subcarriers. `full` evaluates the log
only where needed (lazy gain, below).

## Full kernel

`full` runs the whole algorithm on up to 16 cores of one group. Core c owns a
block of U rows (subcarriers, `[u0, u1)`) and a block of V, P and G rows
(users, `[v0, v1)`). All the data stays in the L1 of the group, so nothing is
flushed.

### Lazy gain

Only the selection uses Gain, and `ln(1 + S)` as computed above is
non-decreasing in S (checked for every S below 2^27, which covers all allowed
inputs). Its widest step is below 1.6e-5 * S, so every element whose Gain
equals the largest Gain has

```
S >= Smax - (Smax >> 14) - 2,     Smax = largest S over the free subcarriers
```

Each core therefore keeps only `colS[k]`, the maximum of S over its rows in
column k, and evaluates the log exactly only in the candidate columns, whose
colS reaches that threshold. The winner is the same as with the Gain of every
element, ties included.

### One iteration

```
every core:  read the per-core keys of iteration j - 1, pick the winner
             (w, k*), mark k* in its own tables
if j - 1 was odd (pass iteration):
  owner of w: power update of row w (or copy of its speculative row)
  every core: update pass on its rows: V += AR1[:, w] * s^T and colS of its
              rows (U is updated one iteration later, see below)
else:
  helper:     power update of row w and the exact key of row w
  owner of w: colS of its rows without row w
  the others: late U update of the last pass
every core:  candidates and exact keys of its rows (or its key of iteration
             j - 1 if its best column was not k*), stored in its own slot;
             before a pass iteration, the speculative power update
one barrier
if a U element crossed the margin (rare): recompute the affected V columns,
             colS and the selection
```

`AR1 = A * R1` is computed with the products, so the V update is a rank-1
update too. The margin is `MaxR - 50`: as long as no U element passes it, no
R element can clamp, and the rank-1 update of V is exact. The U rows whose
bound `C[l][k] + [sum of the negative, sum of the positive R1[l][i]]` stays
inside the margin can never clamp; they are found once after the products and
skipped by the pass.

Three changes move work off the critical path, without changing the result:

- **Late U update.** One pass changes U by at most 50, so the V update of a
  pass is exact as long as U was inside the margin before it. The U update
  of a pass and its margin check are therefore done in the next iteration
  (which has no pass), by the cores other than the owner and the helper,
  split into strips of half a row so that the shares differ by at most one
  strip. This needs U inside the margin from the start, which is checked
  once after the products; if it is not, the U update stays in the pass.
- **Helper core.** After an iteration without a pass only row w of P has
  changed, and the next iteration rebuilds colS anyway. The owner of w
  skips row w; a helper core (the first one whose best column was not k*)
  runs the power update and the exact key of row w. The other cores whose
  best column was not k* keep their key from the previous iteration.
- **Speculative power update.** An iteration without a pass is followed by
  one with a pass, whose owner would run the power update before its pass.
  Instead, in the iteration without a pass, each core other than the owner
  and the helper computes the power update of its own best key into a
  buffer while the others finish, unless a larger key of that iteration is
  already published. The winner always qualifies, so its owner only copies
  the buffer into its P row in the pass iteration.

### Memory layout

The L1 of a group interleaves 64 B lines over its 16 cache controllers, so
addresses 1 KiB apart share a controller. A row of N = 128 words is 512 B,
so every V and P row starts at controller 0 or 8. V and P are therefore
placed 256 B apart modulo 1 KiB, the per-core buffers (colS and the others)
get a pitch of N + 16 words, and the odd cores process the second strip of
columns of the pass first. The cores then spread their loads over all the
controllers instead of queueing at the same ones.

### Selection

The packed key is `key = S >> 7 << 7 | kidx[k]` for the columns and
`Gain << 7 | (127 - i)` for the exact keys of the candidate users. Each core
keeps its own table `kidx[k] = 127 - k`, and sets its sign bit when k is
allocated, so allocated columns get negative keys without a separate load
of ResAllocMap. Two `vredmax` reductions give the best and second-best column key of a core (the
second over the other lanes, with the best one masked out); the results are
read with `vmv.x.s`. If the second is below the threshold of the best, the
best column is the only candidate and the exact keys are computed in that
column only. The winner is the best key over the cores. With `IT_REDMAX 0`
the maxima use `vslidedown` + `vmax` trees instead, for a VFU without the
reduction tree (where `vredmax` is serial and slower).

### Build options

The steps above can be switched off for comparison with compile
definitions of `full`: `IT_U_LATE`, `IT_HELPER`, `IT_SPEC`, `IT_LAYOUT`,
`IT_STAGGER` and `IT_REDMAX` (all 1 by default). `IT_PROF=1` prints the
cycles of each phase per core, the owner of the winner and the helper, and
`IT_CPROF=1` the cycles of the parts of the selection.

## Files

- `common/golden.py`: reference model, written directly from the algorithm.
- `common/fast_model.py`: the restructured algorithm, checked bit-exactly
  against `golden.py`.
- `common/control.h`: constants shared by the kernels.
- `full/main.c`: the full kernel (data layout, roles of the cores, iteration
  loop, checks and printout).
- `full/kernel/iter.c`: its iteration kernels (update pass, late U update,
  colS, selection, power update and its speculative version, column fix-up).
- `uv-init`, `gain-select`, `power-update`: the stage kernels.
- `<kernel>/script/gen_data.py`: generates `data/data_<cfg>.h` (inputs and
  expected outputs) from `script/data_<cfg>.json` with `make gen-data`.
- `RESULTS.md`: cycle counts and utilization of all versions;
  `RESULTS_SUMMARY.md`: the best results only.

Tests are named `ctrl-<kernel>_<cfg>_C<cores>[_<variant>]`, where `<cores>`
is the number of cores the kernel uses. The `full` configurations are
`64_128` (all 128 iterations, run twice: first with the inputs not yet in
the L1, then hot), `64_128_i<n>w` (a warm-up run of 2 iterations, then
`<n>` = 8, 16 or 32 iterations hot, for shorter simulations), `63_37`,
`63_37_mix` (inputs that make most passes cross the clamp margin, a stress
test of the slow path) and `9_21`. The variants are `prof` and `cprof`.
