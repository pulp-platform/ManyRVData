# RLC Kernel — Build & Run Guide

Multi-user RLC (5G L2 data-plane) benchmark kernel for CachePool. From a fresh clone to a
running simulation in ~6 steps. See `doc/KERNEL_REVIEW_NOTES.md` for how the kernel works and
`doc/MULTI_USER_EXTENSION_REPORT.md` for the multi-user design.

## 0. Prerequisites (once per clone)

```bash
make bender              # install the Bender dependency tool
make quick-tool          # ETH only: link the prebuilt RISC-V toolchain
                         # (else: make toolchain  — builds LLVM+GCC from source, hours)
make init                # checkout RTL deps via Bender into hardware/deps
```

Python 3 with `jinja2` and `hjson` is needed for config generation.

## 1. Build the software (produces the kernel ELF)

```bash
make sw config=cachepool_fpu_512     # builds ALL tests into software/build/
```

`make sw` implies `generate` (config headers) and `bootrom`, and it **wipes `software/build`
first** — so use it for the initial build or after changing `config=`.

Once the build tree exists, rebuild just this kernel's variants (much faster, no wipe):

```bash
cd software/build
make test-cachepool-multi_producer_single_consumer_double_linked_list_M1_N1350_K100   # TC1 single-user
make test-cachepool-multi_producer_single_consumer_double_linked_list_M48_N800_K300   # TC2 multi-user (48 UEs)
```

After editing `CMakeLists.txt` (e.g. adding a variant), run `cmake .` in `software/build` first.

## 2. Where the binaries land

```
software/build/CachePoolTests/test-cachepool-multi_producer_single_consumer_double_linked_list_<VARIANT>
```

`<VARIANT>` naming (maps directly to the generated data header `data_<M>_<N>_<K>.h`):

| Variant | Use case | Packets |
|---|---|---|
| `M1_N1350_K{10,100,300}` | TC1 single-user peak (1 UE, 1350 B) | 10 / 100 / 300 |
| `M48_N800_K{300,1000}` | TC2 multi-user peak (48 UEs, 800 B) | 300 / 1000 |
| `M48_N800_K300_P<p>_C<c>` | TC2 with explicit producer/consumer core counts — registered: `P2_C4`, `P4_C4`, `P2_C8`, `P4_C8` | 300 |
| `M48_N800_K300_sc` | TC2 with payload self-check enabled | 300 |

Default core mapping: 2 producers (cores 0–1), 2 consumers (cores 2–3), rest idle.
`M1_N1350_K100` is the CI standard.

## 3. Run in RTL simulation

```bash
make vsim config=cachepool_fpu_512        # builds the QuestaSim model + software (once; ~20 min)
./sim/bin/cachepool_cluster.vsim      software/build/CachePoolTests/test-cachepool-multi_producer_single_consumer_double_linked_list_M1_N1350_K100
./sim/bin/cachepool_cluster.vsim.gui  <same ELF>   # with waveform GUI
```

A good run ends with:
`[EOC] Simulation ended at <time> (retval = 0)` and `[SB ...] STATUS: PASS` per cache controller.

Reference cycle counts (cachepool_fpu_512, 16 cores): TC1 K100 = **241,905** cycles
(kernel work phase 130,828); TC2 K300 2P2C = **651,553** (region 530,059);
TC2 K1000 = **1,872,345**. Known issue: TC2 with `CONSUMER_CORE_NUM >= 8` currently fails
(under debug — see `doc/MULTI_USER_EXTENSION_REPORT.md` §5).

## 4. Changing the use case / data

Data headers are generated, not hand-written:

```bash
cd software/tests/multi_producer_single_consumer_double_linked_list/script
python3 generate_pdcp_pkg.py pdcp_pkg_48_800_300.json   # -> ../data/data_48_800_300.h
```

JSON knobs: `active_user_number` (UEs), `pkg_length`, `pdcp_header_length`, `total_pkg_number`,
src/tgt windows. Then register the variant in `software/tests/CMakeLists.txt` with
`add_spatz_test_threeParam(... <users> <len> <pkgs>)` (or `add_spatz_test_rlc` for custom
core counts) and rebuild.

Optional compile defines: `RLC_ENABLE_PACING=1` (enable the 7 MB/s rate pacing; default off),
`RLC_SELF_CHECK=1` (payload compare at end), `MM_POOL_PAGES=<n>` (node pool size).
