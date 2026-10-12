# gemv-opt

FP32 `y = A * x`, with `A` of size `M x N`, laid out for CachePool's L1 and HBM.

Each active core owns `16 * lmul` consecutive rows of `A` over all `N`
columns, so no reduction is needed. Both modes run with tile-private L1
(`L1D_PART = cores per tile`, `L1D_FOLD_TILE`) and xbar offset 8. With that
offset the controller is `addr[8 +: log2(cores per tile)]`, so core `k` of a
tile only ever touches 256 B blocks of its own controller `k`. An m4 vector
load (64 floats) is exactly one block.

## Modes

| Mode | Goal | Layout of A | Timed iterations |
| --- | --- | --- | --- |
| `hot` | A resident in L1 | Each tile's blocks are `(tiles + 1)` KiB apart, spread over all HBM channels and all L1 sets | 3 (first cold, best of the rest hot) |
| `cold` | Refill bandwidth | Group `g` reads only HBM channel `chan_of_group[g]` | 1 (cold only) |

In cold mode, `A` is stored in stripes of `channels` KiB, with one 1 KiB slot
per channel (`addr[13:10]` with 16 channels). A slot holds 4 blocks, one per
controller. Column `j` of group `g` fills slot `chan_of_group[g]` of the
`cores per group / 4` consecutive stripes starting at stripe
`j * cores per group / 4`. Core `q = t * cores per tile + k` of the group owns
block `q % 4` of stripe `q / 4` of each column.

`chan_of_group` is indexed by the runtime group ID `gy * 4 + gx`. For 16
channels it is chosen against the refill-mesh routes of
`floonoc_cachepool_16g_16ch.yml`, so that no mesh link carries more than one
channel's traffic.

`x` is copied into every core's own controller in the same scheme, and `y` is
written at each core's column-0 position. `script/gen_data.py` describes both
layouts in detail.

## Configurations

| Test (`M N tag`) | Config | Mode |
| --- | --- | --- |
| `4096 64 hot` | `cachepool_fpu_4g` | hot |
| `4096 64 cold` | `cachepool_fpu_4g` | cold |
| `16384 64 hot` | `cachepool_fpu_16g` | hot |
| `16384 64 cold` | `cachepool_fpu_16g` | cold |
| `4096 64 hottiny` | `cachepool_fpu_16g_tiny` | hot |
| `4096 64 coldtiny` | `cachepool_fpu_16g_tiny` | cold |

A test only runs on the config it was generated for. `main.c` checks the
cluster shape and prints `FATAL` otherwise. For example:

```sh
source iis-env.sh
make clean all config=cachepool_fpu_16g DEBUG=0
./sim/bin/cachepool_cluster.vsim software/build/CachePoolTests/test-gemv-opt_M16384_N64_Kcold
```

## Data config fields (`script/data_*.json`)

| Field | Meaning |
| --- | --- |
| `M`, `N` | Matrix size. `M = groups * cores per group * 16 * lmul`, and `N` is a multiple of 64 |
| `groups` | Active groups, starting from group 0 |
| `lmul` | 1, 2 or 4. Cold mode needs 4 |
| `mode` | `hot` or `cold` |
| `channels` | Cold mode only: HBM channel count, must match the config's `l2_channel` |
| `chan_of_group` | Cold mode only: HBM channel of each group, all distinct |
| `cores_per_tile`, `tiles_per_group` | Cluster shape the data is generated for (default 4, 4) |

## Compile-time settings (`main.c`)

| Macro | Default | Meaning |
| --- | --- | --- |
| `XBAR_OFFSET` | 8 | L1 controller select offset |
| `L1D_PART` | cores per tile | Private L1 banks per tile |
| `L1D_FOLD` | `L1D_FOLD_TILE` | Private-bank folding |
| `MEASURE_ITER` | 3 | Hot-mode iterations |
| `COLD_MEASURE_ITER` | 1 | Cold-mode iterations |

The kernel prints cycles, utilization (in ‰ of 4 MACs per core per cycle) and
`A` bytes per cycle for the cold iteration, and for the hot one when there is
one. Every active core then checks its own rows.
