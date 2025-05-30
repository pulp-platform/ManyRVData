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

## Snitch-Spatz Core Complex
Current CachePool system uses a 32b Spatz RVV accelerator and Snitch RISCV core. The double-precision is off by default in consideration of scalability.
