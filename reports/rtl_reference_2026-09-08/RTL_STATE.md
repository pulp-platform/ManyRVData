# RTL state under test — batch 2026-09-08

**RESOLVED PATH, grepped from the compile script — not inferred from Bender.local.**

`Bender.local` does override insitu-cache to `working_dir/insitu-cache`, and I
originally wrote that the batch therefore compiles that working copy. **That was
wrong.** `sim/work/compile.vsim.tcl` (mtime 2026-08-24 23:18, NOT regenerated)
resolves to `hardware/deps/insitu-cache`, and that is what vlog reads:

```
"$ROOT/./hardware/deps/insitu-cache/src/insitu_cache/insitu_cache_core.sv"
```

`compile.vsim.tcl` is a make target whose prerequisites are rtl_lib.cc,
common_lib.cc, bootdata.cc and bootrom.bin — **RTL sources are not among them**,
so `make vsim` does not re-run bender and the Aug-24 script stands.

The results are still valid, verified rather than assumed: the two trees are
byte-identical (`cmp` on all four modified files) and produce the same
diff-vs-HEAD hash `f6657ec2ac4eda12`. Only the path was wrong, not the DUT.

**Hazard for future readers:** if anything touches a prerequisite of
compile.vsim.tcl mid-batch, make re-runs bender, the override takes effect, and
the source path switches trees silently — a no-op only while the trees match.
`dut_tripwire.sha256` pins the compile script and every insitu source it names;
`verify_dut.sh` re-checks it after the batch.

## IP git state
```
f1cbe54 [Verif] Waive check for store requsets since Spatz do not need order in this case

M  src/insitu_cache/insitu_cache_core.sv
M  src/insitu_cache/insitu_cache_encoder.sv
M  src/insitu_cache/insitu_cache_tcdm_wrapper.sv
M  src/utilities/sram_forwarding_buffer.sv

diff vs HEAD: 1275 lines, sha256 f6657ec2ac4eda12
```

## Modified file mtimes (all predate the vsim compile at ~03:44)
```
2026-09-07 23:25  src/insitu_cache/insitu_cache_encoder.sv
2026-09-08 00:24  src/insitu_cache/insitu_cache_core.sv
2026-09-08 01:56  src/insitu_cache/insitu_cache_tcdm_wrapper.sv
2026-09-08 02:04  src/utilities/sram_forwarding_buffer.sv
```

## Attribution
- HEAD `f1cbe54` is the pristine baseline; the 4 modified files are the timing rewrites.
- `bandwidth` has a known-good pristine reference from 2026-08-25 (2,058 kernel cyc / 32 cyc-per-load),
  so a deviation there is attributable to these rewrites.
- `cache-test-scalar` / `cache-test-vector` have NO pristine arm in this batch and may trap for an
  unrelated reason (scalar-FP offload defect). Single-arm results there are UNATTRIBUTABLE — informational only.
