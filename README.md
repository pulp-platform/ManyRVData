# CachePool

> ⚠️ This repository is under active development. Interfaces and build flows may change.

## Overview

CachePool is a Snitch–Spatz–based many-core system with a shared L1 data cache (“CachePool”) and optional DRAMSys-backed main memory. Configuration is centralized in `config/config.mk` and propagated automatically to:
- SystemVerilog (via `VLOG_DEFS` at compile time)
- The Spatz cluster generator (via an auto-generated `config/cachepool.hjson`)

## Configurations

- All hardware knobs live in **`config/config.mk`** (and flavor files it includes, e.g., `cachepool.mk`, `cachepool_fpu.mk`).
  - `cachepool.mk`: no floating-point support
  - `cachepool_fpu.mk`: enables single/half precision in the Spatz vector core
- The Spatz cluster consumes **`config/cachepool.hjson`**, which is **generated** from:
  - `config/cachepool.hjson.tmpl` (skeleton with comments)
  - `config/config.mk` (source of truth)

To switch flavors, set `config=<flavor>` (or export `CACHEPOOL_CONFIGURATION=<flavor>`), then rebuild:

```bash
# Example: switch to FPU flavor
make clean
make generate config=cachepool_fpu
```

> `make clean` is recommended when changing configurations.

## Requirements

- Linux environment with: `make`, `git`, `python3`, `wget`, `curl`
- **CMake ≥ 3.28**, **GCC/G++ ≥ 11.2**
- **QuestaSim** (tested with `questa-2023.4-zr`)
- Optional: SpyGlass for lint

## Quick Start

Initialize submodules and generate the Spatz configuration + RTL packages:

```bash
make init
make generate
```

Build DRAMSys (if `USE_DRAMSYS=1`, default). You can override tool paths inline:

```bash
make dram-build CMAKE=/path/to/cmake-3.28.x CC=/path/to/gcc-11.2 CXX=/path/to/g++-11.2
```

Build RISC-V toolchains (LLVM + GCC). Spike (`riscv-isa-sim`) is available via a separate target if needed.

```bash
make toolchain
# or (ETH only) link a prebuilt toolchain
make quick-tool
```

Build software only:

```bash
make sw
```

Build software + hardware (QuestaSim):

```bash
make vsim
```

Run the simulation (GUI or CLI). The wrapper script expects the software ELF path as argument:

```bash
# GUI
./sim/bin/cachepool_cluster.vsim.gui ./software/build/TESTNAME
# Headless
./sim/bin/cachepool_cluster.vsim      ./software/build/TESTNAME
```

## How configuration flows

1. **`config/config.mk`** defines all parameters (e.g., `num_cores`, `l1d_cacheline_width`, `axi_user_width`, addresses, etc.).
   - Derived values (like `axi_user_width`) are pre-computed so tools receive integers, not expressions.
2. `make generate` calls the Python generator to produce **`config/cachepool.hjson`** from the template.
3. The Makefile passes the same values to **QuestaSim** via `VLOG_DEFS`, keeping RTL, sim, and HJSON in sync.

## Address Scrambling (overview)

- **DRAMSys**: multi-channel main memory with compile-time interleaving.
  The interleave granularity (bytes) is determined by the DRAM beat width and an `Interleave` factor in RTL. This is fixed at elaboration and not configurable at runtime.
- **L1D cache banking**: runtime-configurable crossbar bit selection allows distributing core traffic across banks for parallelism. Use `l1d_xbar_config(...)` at runtime to choose the offset.

## Snitch–Spatz Core Complex

The default system uses a 32-bit Snitch core with a Spatz RVV accelerator. Double-precision is disabled by default for scalability; enable the FPU flavor (`cachepool_fpu.mk`) for single/half precision support.

## Stack

Each core complex has a local **stack SPM**. Its depth is configured via parameters in `config/config.mk` (forwarded to RTL). If the stack exceeds the local SPM, it spills into the cache space (indexed with core ID bits).
**Known limitation:** the cache controller currently lacks byte-write support in the shared stack path. Prefer a larger local stack SPM (e.g., 512 B–1 KiB) to avoid issues.

## Address Map (example)

> Actual values come from `config/config.mk`. Example below reflects the defaults used by the generated HJSON/template.

| Start Address | Size         | Region       | Notes                                   |
|---------------|--------------|--------------|-----------------------------------------|
| `0x0000_0000` | `0x0000_1000`| Unused       | —                                       |
| `0x0000_1000` | `0x0000_1000`| Boot ROM     | Boot address typically `0x0000_1000`    |
| `0x8000_0000` | `0x2000_0000`| DRAM         | 512 MiB (default in template)           |
| `0xBFFF_F800` | `0x0000_0200`| Stack (local)| Example stack window                    |
| `0xC000_0000` | `0x2000_0000`| Uncached     | MMIO/peripherals region                 |
| `0xC001_0000` | `0x0000_1000`| UART         | UART base inside peripheral window      |

## Lint

SpyGlass lint (optional):

```bash
make lint
```

---

### Tips

- To see the exact macros passed to vlog, check `VLOG_DEFS` in the Makefile and `sim/work/compile.vsim.tcl`.
- If you change cacheline width, `AXI_USER_WIDTH` is derived (supported widths: 128→19, 256→18, 512→17). Unsupported widths error out at generation time.
- Use `make clean` when switching flavors/configs to prevent stale build artifacts.
