# T3.1-T3.12 DUT, pinned 2026-09-08 — NO RUN YET

Pinned **before** any simulation, so drift between the peer's sync and an
approved run is detectable. Nothing has been run against this state.

The four files under test, verified against the L1-timing session's pins:

```
b23ed2027fa1dc75  insitu_cache_core.sv          unchanged from the T3.1-T3.15 batch
2bf77815139b3838  insitu_cache_encoder.sv       unchanged
c8ab3702c53efb65  insitu_cache_tcdm_wrapper.sv  CHANGED (was 5307c217)
f45f898632dd45ed  sram_forwarding_buffer.sv     CHANGED (was f0629785)
```

Both changed files were recovered from the git object store via
`git fsck --dangling`, not hand-edited — see the peer's note about a
hand-revert that had introduced a stray `begin`.

**Status: awaiting user approval to run `bandwidth` (+ `byte-enable`).**
Use `elf_under_test/` from `reports/rtl_reference_2026-09-08/` so the software
side is identical to the T3.1-T3.15 arm.
