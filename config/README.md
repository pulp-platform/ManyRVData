# CachePool Configuration

This folder holds everything that parameterises a CachePool build: the Make
variables that become SystemVerilog defines, the per-flavour overrides, and the
FlooNoC topology descriptions. Nothing here is compiled directly — it is all
consumed by the root `Makefile`.

## Folder organisation

```
config/
├── config.mk                 master defaults, includes the selected flavour
├── <flavour>.mk              per-configuration overrides (7 of them)
├── floonoc/                  FlooNoC topology descriptions
├── cachepool.hjson.tmpl      template
├── cachepool.hjson           generated -- do not edit
└── cachepool_peripheral_reg.hjson   generated -- do not edit
```

### 1. Make configuration (`config.mk` + `<flavour>.mk`)

| File | Role |
| --- | --- |
| `config.mk` | Master file. Includes the selected flavour, then supplies a default for every remaining parameter. This is the authoritative list of knobs. |
| `cachepool_4g.mk` | 4 groups (2x2), no FPU |
| `cachepool_fpu_4g.mk` | 4 groups (2x2), Spatz FPU |
| `cachepool_dual_4g.mk` | 4 groups, dual scalar core per CC, no FPU |
| `cachepool_dual_fpu_4g.mk` | 4 groups, dual scalar core per CC, Spatz FPU |
| `cachepool_fpu_16g.mk` | 16 groups (4x4), Spatz FPU, 16 HBM channels |
| `cachepool_fpu_16g_tiny.mk` | 16 groups (4x4), reduced tiles/cores per group, 8 HBM channels |
| `cachepool_dual_fpu_16g.mk` | 16 groups (4x4), dual scalar core per CC, 8 HBM channels |

Flavour names follow `cachepool[_dual][_fpu]_<N>g[_tiny]`: `dual` selects two
Snitch scalar harts per Core Complex, `fpu` enables the Spatz FPU, `<N>g` is the
group count.

### 2. FlooNoC topologies (`floonoc/`)

Describe the L2 refill network: endpoints (group routers and HBM channels),
per-channel address windows, and the physical port each HBM chimney attaches to.
Consumed by `floogen` (`make update-floonoc`), which emits
`hardware/generated/floo_cachepool_noc_pkg.sv`.

Named `floonoc/floonoc_cachepool_<groups>g_<channels>ch[_<variant>].yml`.

| File | Topology |
| --- | --- |
| `floonoc_cachepool_4g_4ch.yml` | 2x2 mesh, 4 HBM channels on West/East |
| `floonoc_cachepool_16g_8ch.yml` | 4x4 mesh, 8 HBM channels on West/East |
| `floonoc_cachepool_16g_8ch_tiny.yml` | 4x4 mesh, 8 HBM channels, reduced widths |
| `floonoc_cachepool_16g_16ch.yml` | 4x4 mesh, 16 HBM channels on all four sides, same-ID placement |

The `Makefile` picks one automatically from `config` and `l2_channel` — see
[L2 channel placement](#l2-channel-placement) below. A topology file must always
agree with `cachepool_cluster.sv`'s chimney generation; the RTL has elaboration
assertions for the cases it can check.

### 3. Generated files — do not edit

`cachepool.hjson` and `cachepool_peripheral_reg.hjson` are produced by
`make generate` from the `.tmpl` files via `util/scripts/gen_spatz_cfg.py`.
Edits are overwritten on the next build.

### 4. Templates

`cachepool.hjson.tmpl` is the source for `cachepool.hjson`. (The peripheral
template lives with the peripheral RTL, in
`hardware/cachepool_peripheral/cachepool_peripheral_reg.hjson.tmpl`.)

## Selecting a configuration

```sh
make generate bootrom vsim sw config=cachepool_fpu_16g
```

The flavour is resolved in `config.mk` in this order: the `config` Make
variable, then the `CACHEPOOL_CONFIGURATION` environment variable. Always pass
one — the final fallback is `config := cachepool`, and there is no
`cachepool.mk`, so a build with neither set fails at the `include`.

**Override precedence** (highest first):

1. Command line — `make vsim config=cachepool_fpu_16g l2_channel=8`
2. The flavour `.mk` — included *before* `config.mk`'s own defaults, so its
   `?=` assignments win
3. `config.mk`'s `?=` defaults

## Parameters

Defaults below are the ones in `config.mk`. A flavour file usually overrides a
subset; the "Define" column gives the SystemVerilog macro the `Makefile` emits
(`—` means the parameter is consumed by a generator script instead of `vlog`).

### Cluster

| Parameter | Default | Define | Description |
| --- | --- | --- | --- |
| `num_groups` | `1` | `NUM_GROUPS` | Groups in the cluster |
| `num_groups_x` | `1` | `NUM_GROUPS_X` | X dimension of the group mesh; Y is `num_groups / num_groups_x` |
| `num_tiles_per_group` | `4` | — | Tiles per group (derives `num_tiles`) |
| `num_cores_per_tile` | `4` | — | Core Complex slots per tile (derives `num_cores`) |
| `num_lg_ports_per_core` | `1` | `LG_PORT_PER_CORE` | Intra-group remote ports per core (to other tiles in the same group) |
| `num_rg_ports_per_core` | `0` | `RG_PORT_PER_CORE` | Inter-group remote ports per core, via the L1 NoC. `0` disables inter-group L1 traffic |
| `num_noc_ports_per_tile` | `1` | `NOC_PORT_PER_TILE` | NoC router channels per tile; concentrates the tile's inter-group traffic |
| `data_width` | `32` | `DATA_WIDTH` | Core data width |
| `addr_width` | `32` | `ADDR_WIDTH` | Core address width |
| `bootrom_data_width` | `32` | — | Bootrom word width (used by `generate_bootrom.py`) |
| `num_barrier_slots` | `2` | `NUM_BARRIER_SLOTS` | Independent hardware barrier slots |
| `dram_type` | `HBM2` | `DRAM_TYPE` | DRAMSys model. One of `DDR3`, `DDR4`, `LPDDR4`, `HBM2`. Also sets the default `refill_data_width` |

### Tile and L1 data cache

| Parameter | Default | Define | Description |
| --- | --- | --- | --- |
| `refill_data_width` | auto from `dram_type` | `REFILL_DATA_WIDTH` | Refill interconnect data width. Default is 512 (HBM2), 256 (LPDDR4), 128 (otherwise) |
| `l1d_cacheline_width` | `512` | `L1D_CACHELINE_WIDTH` | Cache line width in bits |
| `l1d_bank_factor` | `1` | — | Banks per core (derives `l1d_num_banks`) |
| `l1d_coal_window` | `2` | `L1D_COAL_WINDOW` | Coalescing window of the request coalescer |
| `l1d_num_way` | `4` | `L1D_NUM_WAY` | Associativity per cache controller |
| `l1d_tile_size` | `256` | — | L1D size per tile in KiB (derives `l1d_depth`) |
| `l1d_tag_data_width` | `92` | `L1D_TAG_DATA_WIDTH` | Tag width. Not computed from the address map — widen by hand if the tag grows |
| `l1d_use_folded` | flavour-only (`1`) | `L1D_USE_FOLDED` | Folded (skewed) data banks |
| `l1d_fold_way_group` | flavour-only (`0`) | `L1D_FOLD_WAY_GROUP` | Fold-way group size; `0` = auto, `min(4, ways)` |
| `l1d_use_hash_way` | flavour-only (`1`) | `L1D_USE_HASH_WAY` | Hash-based way selection instead of associative/LRU search |
| `l1d_use_fwd_buf` | flavour-only (`1`) | `L1D_USE_FWD_BUF` | SRAM forwarding buffer |

The four `l1d_use_*` / `l1d_fold_way_group` knobs have **no default in
`config.mk`** — every flavour currently sets them (all to `1/0/1/1`). A new
flavour that omits them emits an empty define, which will not elaborate. Set
them explicitly.

### Core Complex

| Parameter | Default | Define | Description |
| --- | --- | --- | --- |
| `spatz_fpu_en` | `1` | — | Enable the Spatz FPU (reaches the RTL through `cachepool.hjson`) |
| `spatz_num_fpu` | `4` | `SPATZ_NUM_FPU` | FPUs per Spatz |
| `spatz_num_ipu` | `4` | `SPATZ_NUM_IPU` | IPUs per Spatz |
| `spatz_max_trans` | `32` | `SPATZ_MAX_TRANS` | Spatz outstanding transactions |
| `snitch_max_trans` | `16` | `SNITCH_MAX_TRANS` | Snitch/FPU outstanding transactions |
| `num_scalar_per_core` | `1` | `NUM_SCALAR_PER_CC` | Snitch scalar harts sharing one Spatz per CC. `1` or `2`; `2` also emits `CACHEPOOL_DUAL_CC` |

### AXI

| Parameter | Default | Define | Description |
| --- | --- | --- | --- |
| `axi_user_width` | derived from `l1d_cacheline_width` | `AXI_USER_WIDTH` | AXI `user` field width carrying `refill_user_t`. Auto-set to 18 / 19 / 22 for a 512 / 256 / 128-bit line |

### L2 and main memory

| Parameter | Default | Define | Description |
| --- | --- | --- | --- |
| `dram_addr` | `2147483648` (`0x8000_0000`) | — | DRAM base address |
| `dram_len` | `536870912` (`0x2000_0000`) | — | DRAM size |
| `uncached_addr` | `3221225472` (`0xC000_0000`) | — | Uncached region base |
| `uncached_len` | `536870912` (`0x2000_0000`) | — | Uncached region size |
| `l2_channel` | `4` | `L2_CHANNEL` | HBM/DRAM channels. Also sets the per-channel window `DramSize / l2_channel` and the address scramble width |
| `l2_bank_width` | `512` | `L2_BANK_WIDTH` | DRAM data width. Change with care |
| `l2_interleave` | `16` | `L2_INTERLEAVE` | Interleaving factor, in units of `l2_bank_width` bytes |

### Peripherals and stack

| Parameter | Default | Define | Description |
| --- | --- | --- | --- |
| `stack_addr` | `3221223424` (`0xBFFF_F800`) | — | Stack start address |
| `stack_hw_size` | `1024` | `STACK_HW_SIZE` | Hardware (SPM) stack size in bytes |
| `stack_tot_size` | `2048` | `STACK_TOT_SIZE` | Total stack size in bytes, shared plus private |
| `periph_start_addr` | `3221225472` (`0xC000_0000`) | — | Peripheral region base |
| `boot_addr` | `4096` (`0x1000`) | — | Boot address |
| `uart_addr` | `3221291008` (`0xC001_0000`) | — | UART base address |

### Derived — do not set

These are computed in `config.mk` and will be overwritten:

| Parameter | Formula |
| --- | --- |
| `num_tiles` | `num_groups * num_tiles_per_group` |
| `num_cores` | `num_tiles * num_cores_per_tile` |
| `l1d_num_banks` | `num_cores_per_tile * l1d_num_way * l1d_bank_factor` |
| `l1d_depth` | `l1d_tile_size * 8192 / l1d_cacheline_width` |
| `stack_hw_depth` | `stack_hw_size * 8 / data_width` |
| `stack_tot_depth` | `stack_tot_size * 8 / data_width` |
| `axi_user_width` | from `axi_user_base`, selected by `l1d_cacheline_width` |

## Constraints and special requirements

Items marked **(asserted)** fail at elaboration. Everything else is silent and
must be respected by hand — including the constraints written as `ASSERT_INIT`
in the RTL, which are inert because `INC_ASSERT` is never defined in any
CachePool build.

### Powers of two

- `l1d_num_way` must be a power of two. Hash way selection indexes ways with a
  truncating field, and the way index is reduced with `$clog2`.
- `l1d_cacheline_width`, `data_width`, `addr_width`, `l2_bank_width`,
  `l2_interleave`, `refill_data_width` are all width/index parameters reduced
  with `$clog2` — keep them powers of two.
- `l2_channel` must be a power of two: it is the width of the address
  scramble field, `ScrambleBits = $clog2(NumL2Channel)`.
- `num_groups`, `num_groups_x` — the mesh is rectangular, so `num_groups` must
  be exactly divisible by `num_groups_x`.

### Exact divisibility

- `l1d_tile_size * 8192` must be divisible by `l1d_cacheline_width`, otherwise
  `l1d_depth` truncates silently.
- `stack_hw_size * 8` and `stack_tot_size * 8` must be divisible by
  `data_width`.
- `L1AssoPerCtrl % EffectiveFoldWayGroup == 0` and
  `NumWordPerLine % PartSplit == 0`. `cachepool_tile.sv` has
  `CheckFoldWayGroup` / `CheckLineSplit` for these, but they are `ASSERT_INIT`
  and therefore never compiled — treat both as unchecked.

### L1 data cache micro-architecture

- `l1d_use_folded = 1` and `l1d_use_fwd_buf = 1` both require
  `l1d_use_hash_way = 1`. The production combination is `1/1/1`; the
  conventional unfolded combination is `0/0/0`. Mixed settings are untested.
- `l1d_tag_data_width` is not computed from the address map — it is a hand-set
  constant (the `TODO` in `config.mk` tracks this). All seven flavours set `92`
  explicitly and the default now matches, so a new flavour can inherit it.

### AXI user width

`axi_user_width >= $bits(refill_user_t)` is a hard requirement. Below that
floor, the MSB of `bank_id` is truncated on the AXI loopback and refill
responses route to the wrong subordinate port (e.g. `bank_id=4` aliases to
`bank_id=0`, hanging the affected controller). The auto-derivation from
`l1d_cacheline_width` satisfies it; only override `axi_user_width` with the
derivation in `config.mk` in front of you.

Note: `config.mk`'s comment states this is enforced by an
`ASSERT_INIT(CheckAxiUserFitsRefillUser)` in `cachepool_cluster.sv`. That
assertion is **not currently present** in the RTL, so treat the requirement as
unchecked.

### Address scrambling

`scrambleAddr()` in `cachepool_pkg.sv` only interleaves when
`l2_bank_width/8 * l2_interleave < DramSize / l2_channel`; otherwise it returns
the address unchanged and all traffic lands in one channel. With the defaults
(64 B x 16 = 1 KiB granularity) this holds comfortably.

The resulting mapping is **channel = `addr[ConstantBits + ScrambleBits - 1 :
ConstantBits]`**, where `ConstantBits = $clog2(l2_bank_width/8 * l2_interleave)`
and `ScrambleBits = $clog2(l2_channel)`. With the defaults that is a 1 KiB
granularity round-robin cycling through all channels every `l2_channel` KiB —
for `l2_channel = 16` the select field is `addr[13:10]`. Changing
`l2_interleave` or `l2_bank_width` moves which address bits select the
channel.

### Dual scalar cores

- `num_scalar_per_core` must be `1` or `2`. `cachepool_tile.sv`'s
  `NumScalarPerCCSupported` is an `ASSERT_INIT` and never compiled, so an
  unsupported value falls through to the dual branch silently.
- A tile is homogeneous: every CC in the build uses the same flavour.

### L2 channel placement

`cachepool_cluster.sv` supports two HBM chimney layouts, chosen by channel
count, and the `Makefile` picks the matching YAML automatically.

| `l2_channel` | Chimneys | Placement | YAML (16g) |
| --- | --- | --- | --- |
| `2 * num_groups_y` | West/East only | Linear | `floonoc_cachepool_16g_8ch.yml` |
| `2 * (num_groups_x + num_groups_y)` | All four sides | Same-ID | `floonoc_cachepool_16g_16ch.yml` |

- **(asserted)** `l2_channel` must equal one of those two counts, otherwise some
  channel has no chimney or some boundary port has no channel.
- **(asserted)** Same-ID placement requires a 4x4 group mesh. Only there does
  the boundary port count equal the group count, which is what lets every group
  own a distinct nearby channel. The 4g flavour also satisfies
  `l2_channel == num_groups`, but has only West/East chimneys, so it correctly
  stays linear.
- **Same-ID placement** assigns channel IDs so group *K* reaches channel *K* in
  one hop (groups in mesh columns 0 and 3) or two hops (interior columns):

  ```
   X  13  9 10 14  X
  12  12 13 14 15  15
   8   8  9 10 11  11
   4   4  5  6  7   7
   0   0  1  2  3   3
   X   1  5  6  2   X
  ```

  Outer ring is the HBM channel, inner 4x4 is the group (`g = gy*4 + gx`, with
  `gy=0` on the bottom row).

- The `HbmIdx` tables in `cachepool_cluster.sv` and the `dst_idx`/`dst_dir`
  entries in the YAML describe the same wiring from opposite ends. **Both must
  be edited together** — nothing cross-checks them at build time.
- Channel-to-address-window mapping is independent of placement. Moving a
  channel physically does not move its address range.

## Adding a new flavour

1. Copy the closest existing `.mk` and adjust. Set the four `l1d_use_*` /
   `l1d_fold_way_group` knobs explicitly (no `config.mk` default).
2. If the group count or HBM channel count changes, add or select a
   `floonoc_*.yml` and extend the `FLOO_CFG` selection in the `Makefile`. That
   block matches on the `config` name suffix, so a new group count needs a new
   branch.
3. Check the constraints above, in particular `l1d_tag_data_width` and
   `axi_user_width`, which do not auto-scale with the cluster size.
4. Build with `make generate bootrom vsim sw config=<name>`.
