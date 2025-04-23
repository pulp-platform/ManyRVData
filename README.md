# CachePool

This reporistory is still under construction...
It will be transferred to GitHub once we have a working demo.

## Get Started

Make sure you clone this repository recursively to get all the necessary submodules:

```bash
git submodule update --init --recursive
```

Then, initialize and generated the needed hardware with:

```bash
make init
make generate
```

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
./bin/spatz_cluster.vsim.gui ./software/build/TESTNAME
```
