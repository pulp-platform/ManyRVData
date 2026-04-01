# CachePool

> ⚠️ This repository is under active development. Interfaces and build flows may change.

## Overview

CachePool is a Snitch–Spatz–based many-core system with a shared L1 data cache ("CachePool") and DRAMSys-backed main memory. Configuration is centralized in `config/config.mk` and propagated automatically to:
- SystemVerilog (via `VLOG_DEFS` at compile time)
- The Spatz cluster generator (via an auto-generated `config/cachepool.hjson`)

## System Hierarchy

| Level | Module | Description |
|-------|--------|-------------|
| 1 | Core Complex (CC) | One 32-bit Snitch + one Spatz RVV accelerator |
| 2 | Tile | 4 CCs + 4 × 64 KiB 4-way InSitu-Cache banks |
| 3 | Group | 4 Tiles connected via crossbar |
| 4 | Cluster (WIP) | Multiple Groups connected via NoC (currently one Group) |

All tiles in a cluster share one unified L1 cache, interleaved across cache banks. The bank-selection offset is configurable at runtime via `l1d_xbar_config(...)`.

## Requirements

- Linux environment with: `make`, `git`, `python3`, `wget`, `curl`
- **CMake ≥ 3.28**, **GCC/G++ ≥ 11.2**
- **QuestaSim** (tested with `questa-2023.4`)
- Optional: SpyGlass for lint

## Quick Start

### Build Toolchains

This repository uses **Bender** to manage dependencies and generate simulation scripts. Ensure Bender is installed, or build it locally:

```bash
make bender
```

Build the RISC-V toolchains (LLVM + GCC). Spike (`riscv-isa-sim`) is also available through a dedicated target:

```bash
make toolchain
```

For ETH users, a **pre-built toolchain** is available for faster setup:

```bash
# ETH only: link a prebuilt toolchain
make quick-tool
```

### Initialize Submodules

Use Bender to initialize all required submodules:

```bash
make init
```

### Build DRAMSys

DRAMSys must be compiled before simulation. Tool versions can be overridden inline:

```bash
make dram-build CMAKE=/path/to/cmake-3.28.x CC=/path/to/gcc-11.2 CXX=/path/to/g++-11.2
```

### Generate Required RTL

Some RTL components (e.g., package headers) must be generated prior to simulation.
Generation requires specifying a **configuration**. If none is provided, the default is `cachepool_512`.

```bash
make generate config=cachepool_fpu_512
```

### Build the BootROM

The BootROM is built separately from the RTL generation step:

```bash
make bootrom config=cachepool_fpu_512
```

### Compilation and Simulation

#### Build Software Only

```bash
make sw config=cachepool_fpu_512
```

#### Build Hardware + Software (QuestaSim)

```bash
make vsim config=cachepool_fpu_512
```

#### Run the Simulation

The wrapper script launches the simulation (GUI or CLI) and expects a software ELF path as argument:

```bash
# GUI mode
./sim/bin/cachepool_cluster.vsim.gui  ./software/build/TESTNAME

# Headless mode
./sim/bin/cachepool_cluster.vsim      ./software/build/TESTNAME
```

## Benchmark

A lightweight benchmarking automation flow is provided under `util/auto-benchmark` to simplify batch testing of multiple configurations and kernels.

### Files

| File | Description |
|------|-------------|
| `configs.sh` | Defines configurations (`CONFIGS`) and kernel suffixes (`KERNELS`) to test, along with optional `PREFIX` and `ROOT_PATH`. |
| `run_all.sh` | Main automation script that builds each configuration, runs all kernels, saves logs, and generates summaries. |
| `write_results.py` | Extracts `[UART]` lines from simulator logs and appends them to per-configuration summary files. |
| `check_ci.py` | Scans a simulation log for failures and exits non-zero if any are found (see [CI Checking](#ci-checking)). |

### Usage

1. Edit `configs.sh` to list the desired configurations and kernels:

       CONFIGS="cachepool_fpu_512 cachepool_fpu_256 cachepool_fpu_128"
       KERNELS="fdotp-32b_M32768 ffft-64b_M16384 fmatmul-64b_M2048"
       PREFIX="test-cachepool-"
       ROOT_PATH=../..

2. Run all builds and simulations:

       ./run_all.sh

3. Results will appear in:

       logs/<timestamp>/

   and a symlink:

       logs/latest -> logs/<timestamp>/

### Output Structure

Example directory after a run:

    logs/20251028-1230/
    ├── cachepool_fpu_512_fdotp-32b_M32768.log
    ├── cachepool_fpu_512_fdotp-32b_M32768_pm/
    ├── cachepool_fpu_512_summary.txt
    ├── cachepool_fpu_256_summary.txt
    └── ...

Each run includes:
- `*.log` — Full simulation output
- `*_pm/` — Performance monitor logs automatically moved from `sim/bin/logs` and renamed to `<config>_<kernel>_pm/`
- `*_summary.txt` — `[UART]` summaries for each configuration, grouped by kernel with clear headers

This setup allows quick reproducible benchmarks with all results neatly organized per run.

### CI Checking

`check_ci.py` scans a simulation log and exits non-zero if any failure is detected, making it suitable for integration into CI pipelines. It flags the following patterns:

- Any line containing `FAIL` or `[FAIL]` (case-insensitive)
- Any line matching `error <N>` where N is non-zero (`error 0` is treated as pass)

Usage:

```bash
python3 check_ci.py logs/latest/cachepool_fpu_512_load-store.log
```

Exit code 0 means all tests passed; exit code 1 means at least one failure was detected. On failure the offending lines and their line numbers are printed for manual inspection.

## Configurations

All hardware knobs live in **`config/config.mk`** (and flavor files it includes). The default configuration is **4 tiles, 16 cores**.

| Flavor file | Description |
|-------------|-------------|
| `cachepool.mk` | No floating-point support |
| `cachepool_fpu.mk` | Enables single/half precision in the Spatz vector core |

Available named configurations (passed as `config=<name>`):

| Name | Cacheline | FPU |
|------|-----------|-----|
| `cachepool_512` | 512b | No |
| `cachepool_128` | 128b | No |
| `cachepool_fpu_512` | 512b | Yes |
| `cachepool_fpu_256` | 256b | Yes |
| `cachepool_fpu_128` | 128b | Yes |

The Spatz cluster consumes **`config/cachepool.hjson`**, which is **generated** from:
- `config/cachepool.hjson.tmpl` (skeleton with comments)
- `config/config.mk` (source of truth)

To switch flavors, set `config=<name>` (or export `CACHEPOOL_CONFIGURATION=<name>`), then rebuild:

```bash
make clean
make generate config=cachepool_fpu_512
```

> `make clean` is recommended when changing configurations.

### How configuration flows

1. **`config/config.mk`** defines all parameters (e.g., `num_tiles`, `num_cores`, `l1d_cacheline_width`, `axi_user_width`, addresses, etc.). Derived values (like `axi_user_width`) are pre-computed so tools receive integers, not expressions.
2. `make generate` calls the Python generator to produce **`config/cachepool.hjson`** from the template.
3. The Makefile passes the same values to **QuestaSim** via `VLOG_DEFS`, keeping RTL, sim, and HJSON in sync.

## Address Scrambling (overview)

- **DRAMSys**: multi-channel main memory with compile-time interleaving. The interleave granularity (bytes) is determined by the DRAM beat width and an `Interleave` factor in RTL. This is fixed at elaboration and not configurable at runtime.
- **L1D cache banking**: runtime-configurable crossbar bit selection allows distributing core traffic across banks for parallelism. Use `l1d_xbar_config(...)` at runtime to choose the offset.

## Cache Bank Partitioning

L1 cache banks can be partitioned at runtime between a **shared pool** (accessible cluster-wide via the interconnect) and a **private partition** (local to each tile). Five modes are supported:

| Mode | `l1d_part` value | Private banks | Shared banks |
|------|-----------------|---------------|--------------|
| All-shared | 0 | none | all |
| 1 private, 3 shared | 1 | 1 | 3 |
| Half-half | 2 | 2 | 2 |
| 3 private, 1 shared | 3 | 3 | 1 |
| All-private | 4 | all | none |

Private banks are local to each tile and not visible to remote tiles. Shared banks participate in the cluster-wide interleaved pool. For non-power-of-2 partition sizes (1 or 3 banks), bank selection uses modulo folding, which causes slightly uneven bank utilisation.

Partitioning is controlled via the `l1d_private` memory-mapped register in the cluster peripheral. The interconnect (`tcdm_cache_interco`) uses a runtime-configurable address rotation scheme to present a dense index space to each cache bank regardless of partition mode, preserving full SRAM utilization. The refill unit applies the inverse rotation before issuing misses to the NoC.

### Private/shared address classification

The boundary between private and shared address regions is configurable at runtime via `l1d_addr(...)`:

- Addresses **≥ boundary** are classified as **private**
- Addresses **<  boundary** are classified as **shared**

The default boundary is `0xA000_0000`. This means data in `.pdcp_src` (at `0xA000_0000+`) is private by default, and data in `.data` (at `0x8000_0000+`) is shared by default. The boundary can be raised or lowered at runtime to reclassify data regions without moving them in memory.

> Changing either the partition mode or the boundary address while the cache contains valid data requires a flush first.

## Cache Flushing

Flush instructions are issued through the cluster peripheral and dispatched to cache controllers via a two-level controller:

- **Cluster level** (`cachepool_peripheral`): holds the instruction and a per-tile one-hot tile-select mask. Issues the instruction to all tiles simultaneously and tracks completion at tile granularity.
- **Tile level** (`cachepool_tile`): receives the instruction, determines which of its local cache controllers to activate based on the partition field, and returns a single ready pulse to the cluster controller when all targeted controllers finish.

### Flush instruction encoding

| `insn` value | Operation | Banks targeted | Tile select |
|-------------|-----------|----------------|-------------|
| `2'b00` | Flush private | Private banks only | Per-tile one-hot mask |
| `2'b01` | Flush shared | Shared banks only | All tiles (forced) |
| `2'b10` | Flush all | All banks | All tiles (forced) |
| `2'b11` | Invalidate (init) | All banks | All tiles (forced) |

For `insn != 2'b00`, the peripheral sets the tile-select mask to all-ones for consistency.

### Software API

```c
// Flush all banks in all tiles (existing behaviour)
l1d_flush();

// Flush private banks in selected tiles (one-hot tile mask)
l1d_private_flush(uint32_t tile_mask);

// Flush shared banks in all tiles
l1d_shared_flush();

// Set the private/shared address boundary
l1d_addr(uint32_t addr);

// Poll until all pending flush operations complete
l1d_wait();
```

### Flush completion

Each tile tracks completion per cache controller using a `cache_flush_q` register (one bit per controller). The tile asserts a one-cycle ready pulse to the cluster controller when all targeted controllers have finished. The cluster controller uses a per-tile lock register to track in-flight flushes; a new instruction cannot be issued until all selected tiles report completion.

Cache accesses from cores and remote tiles are gated (`l1d_busy`) while a flush is in progress, preventing stale hits during the flush window.

## Snitch–Spatz Core Complex

The default system uses a 32-bit Snitch core with a Spatz RVV accelerator. Double-precision is disabled by default for scalability; enable the FPU flavor (`cachepool_fpu.mk`) for single/half precision support.

## Stack

Each core complex has a local **stack SPM**. Its depth is configured via parameters in `config/config.mk` (forwarded to RTL). If the stack exceeds the local SPM, it spills into the cache space (indexed with core ID bits).

## Peripherals

Cluster peripherals (including the BootROM and memory-mapped registers) are instantiated at the cluster level, outside of the Spatz cluster. The peripheral register block is defined in `hardware/cachepool_peripheral/` and generated from an HJSON register description.

## Address Map (example)

> Actual values come from `config/config.mk`. Example below reflects the defaults used by the generated HJSON/template.

| Start Address | Size         | Region        | Notes                                |
|---------------|--------------|---------------|--------------------------------------|
| `0x0000_0000` | `0x0000_1000`| Unused        | —                                    |
| `0x0000_1000` | `0x0000_1000`| Boot ROM      | Boot address typically `0x0000_1000` |
| `0x8000_0000` | `0x2000_0000`| DRAM          | 512 MiB (default in template)        |
| `0xA000_0000` | —            | Private boundary | Default `l1d_addr` value; addresses ≥ this are private |
| `0xBFFF_F800` | `0x0000_0200`| Stack (local) | Example stack window                 |
| `0xC000_0000` | `0x2000_0000`| Uncached      | MMIO/peripherals region              |
| `0xC001_0000` | `0x0000_1000`| UART          | UART base inside peripheral window   |

## Lint

SpyGlass lint (optional):

```bash
make lint config=cachepool_fpu_512
```

---

### Tips

- To see the exact macros passed to vlog, check `VLOG_DEFS` in the Makefile and `sim/work/compile.vsim.tcl`.
- If you change cacheline width, `AXI_USER_WIDTH` is derived (supported widths: 128→19, 256→18, 512→17). Unsupported widths error out at generation time.
- Use `make clean` when switching flavors/configs to prevent stale build artifacts.
- Runtime functions `snrt_tile_id()` and `snrt_num_tiles()` are available to query tile topology from software.
- Changing the partition mode or boundary address while the cache holds valid data requires a flush (`l1d_flush()` or the appropriate partition flush) before reconfiguring.
