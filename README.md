# CachePool

This reporistory is still under construction...

## Get Started

First, initialize and generated the needed hardware with:

```bash
make init
make generate
```

Then, DramSys needs to be built correctly with GCC version higher than 11.2.0, CMAKE higher than 3.28.0
```bash
make dram-build CMAKE=/path/to/cmake-3.28.3 CC=/path/to/gcc-11.2.0 CXX=/path/to/g++-11.2.0
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

## Address Scrambling

Multiple address scrambling are used in CachePool to fully utilize the available bandwidth

### DramSys
CachePool uses a multi-channel main memory built on DramSys. Address scrambling is made to better utilize the channels. The granularity of scrambling is controlled by the `Interleave` paramemter sets in the `cachepool_pkg.sv`, which `granularity = log2(512/8 * Interleave)`. This interleaving pattern is determined at elaboration time and cannot be modified during runtime.

### Cache Bank
The xbars to the cache banks can be configured during runtime to select the scrambling bits for parallism visits between cores. The function `l1d_xbar_config` can be used to set the offset.


## Snitch-Spatz Core Complex
Current CachePool system uses a 32b Spatz RVV accelerator and Snitch RISCV core. The double-precision is off by default in consideration of scalability.
