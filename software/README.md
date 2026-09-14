# CachePool Software

```
software/
├── snRuntime/ # bare-metal C runtime (barriers, l1 cache control, printf,
│              # allocator, Spatz lock, ...), linked into every test
├── cache/     # L1D cache correctness/stress tests
├── sync/      # locks, barriers, and other concurrency primitives
├── kernels/
│   ├── fp/    # floating-point vector kernels (fdotp, fmatmul, gemv, fft, ...)
│   └── int/   # integer vector kernels (idotp, ...)
├── rlc/       # RLC (multi-producer/single-consumer) application test(s)
├── tests/     # smoke tests / one-off repros that don't fit another group,
│              # plus the shared benchmark/spin_lock/mcs_lock helper libraries
│              # and headers (tests/benchmark, tests/include) used by all groups
└── cmake/     # shared CMake macros and toolchain files
```

Each test lives in its own directory (e.g. `kernels/fp/fdotp-32b/`):
`main.c`, plus, for data-driven kernels, `kernel/` (kernel source), `data/`
(generated headers, gitignored), and `script/` (`gen_data.py` +
`data_<params>.json` golden-value definitions).

## Building

From the repository root:

```
make sw config=<config-name>          # build all registered tests
```

Binaries land in `software/build/CachePoolTests/`, named
`test-<test-name>`. Run one against the RTL simulator with:

```
./sim/bin/cachepool_cluster.vsim software/build/CachePoolTests/test-<test-name>
```

## Adding a test

1. Create the test's directory under the group it belongs to (`cache/`,
   `sync/`, `kernels/fp/`, `kernels/int/`, `rlc/`, or `tests/` for
   ungrouped smoke tests/repros).
2. Register it in that group's `CMakeLists.txt` with one of the
   `add_spatz_test_{zeroParam,oneParam,twoParam,threeParam}` macros
   (`zeroParam` for a fixed test, `oneParam`/`twoParam`/`threeParam` for
   tests swept over 1-3 named parameters via `DATAHEADER`) — mirror an
   existing entry in that file.
3. For a data-driven kernel, add `script/gen_data.py` and one
   `script/data_<params>.json` per parameter combination; golden headers
   under `data/` are generated automatically by `make gen-data` (also run
   as part of `make sw`).

## Adding a new group

Add a directory under `software/`, give it a `CMakeLists.txt` with its own
`add_spatz_test_*` calls, and add an `add_subdirectory(...)` line for it in
`software/CMakeLists.txt`, inside the `ENABLE_CACHEPOOL_TESTS` block.

## Removing a test

Delete its directory and the corresponding `add_spatz_test_*` line(s) from
the group's `CMakeLists.txt`.
