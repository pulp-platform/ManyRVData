# CachePool

This reporistory is still under construction...
It will be transferred to GitHub once we have a working demo.

## Get Started

First, initialize and generated the needed hardware with:

```bash
make init
make generate
```

LLVM and GCC toolchain are required to be built for the project. You can build the toolchain using

```bash
make toolchain
````

Or, you can link the pre-built toolchain within ETH domain

```bash
make quick-tool
````


You can build the software only with:

```bash
make sw
```

Or, build the software and hardware together with (only support QuestaSim for now):

```bash
make vsim
```

The QuestaSim simulation can be run with:

```bash
./sim/bin/spatz_cluster.vsim.gui ./software/build/TESTNAME
```

## Change configurations

Currently the Runtime support is still under construction. Changing configurations require manual modifications on multiple files.
The `cfg/cachepool.hjson` provides the configuration to generate the vector core package.
In case you change some system variables, e.g. cache size, you are required to change the `hardware/src/cachepool_pkg.sv` where defines the elaboration variables at system level.
In some rare cases, you may also need to change `hardware/tb/cachepool_cluster_wrapper.sv` for the cached_region size and support (will be moved into `cachepool_pkg.sv` in the future).

After modifying the files, you need to re-generate all the auto-generated files by:
```bash
make generate -B
```
