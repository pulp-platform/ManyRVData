# Ask the tool what it did, not the config what it should have done

**2026-09-08.** Two provenance failures in one night, on two sides of the same
comparison, both of which would have produced a clean-looking wrong answer.

## The rule

**A configuration file states an intention. Only the generated artefact records
what actually happened.** Read the artefact.

## Case 1 — `Bender.local` overrides do not apply until the lock is regenerated

`Bender.local` says:

```yaml
overrides:
  insitu-cache: { path: "working_dir/insitu-cache" }
```

`Bender.lock` says:

```yaml
insitu-cache:
  revision: f1cbe54dca0989f025b0450e85c42faf2bf5cbf1
  source:
    Git: https://github.com/pulp-platform/Insitu-Cache.git
```

**The lock wins.** It resolves to a Git checkout under `hardware/deps/`, not to
the overridden path, until `bender update` regenerates it. So reading
`Bender.local` and concluding "we are compiling `working_dir`" is wrong twice
over:

1. the lock still resolves to `hardware/deps`, and
2. `sim/work/compile.vsim.tcl` is a make target whose prerequisites are
   `rtl_lib.cc`, `common_lib.cc`, `bootdata.cc`, `bootrom.bin` — **RTL sources
   are not among them**, so `make vsim` does not re-run bender at all and a
   months-old script stays authoritative.

Either alone is enough to defeat the override. A peer independently hit the
same thing from the other direction: repointed `Bender.local` at a private
copy, launched a run, and the tool analysed the original tree anyway.

**Do:** `grep` the resolved path out of the generated `compile.vsim.tcl`.
**Don't:** infer it from `Bender.local`, `Bender.yml`, or a `bender` command
you ran earlier.

## Case 2 — a rebuild silently changes what a peer's comparison arm reads

Two sessions compared RTL arms using ELFs from a shared `software/build/`.
One session was about to rebuild one of those ELFs (adding a fence to a test)
while the other planned to run it. The arms would then have differed in two
variables — cache RTL *and* test binary — and nothing in either log would have
shown it.

**Do:** freeze the exact binaries a measurement used, `chmod a-w`, with a
manifest, *before* touching the build directory. Point collaborators at the
frozen copy, not at `software/build/`.

## What made both catchable

Not reasoning — checking:

| check | caught |
|---|---|
| `grep` the resolved path from the generated script | the `Bender.local` inference |
| hash the compile script + **all 30** sources it names | a mid-batch tree switch (tripwire) |
| verify a frozen ELF still matches the live one | that the freeze predated the rebuild |
| `pgrep -a vsim` before any process action | 19 unrelated simulations, none this repo |

Each is seconds of work and each caught something the reasoning missed. Write
the comparability conditions down **before** running, while there is no result
yet to be tempted by.

## Related

See `SYNCHRONISATION_IS_NOT_VISIBILITY.md` for the other pattern from the same
night: a primitive whose name promises more than it delivers.
