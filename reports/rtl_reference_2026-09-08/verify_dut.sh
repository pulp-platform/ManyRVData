#!/bin/bash
# Re-check that the DUT did not change during the batch.
# The hazard: compile.vsim.tcl is a make target whose prerequisites do NOT
# include RTL sources. If anything touches a prerequisite mid-batch, make
# re-runs bender, Bender.local's override takes effect, and the resolved
# source path silently switches from hardware/deps to working_dir. Nothing in
# the vsim logs would show it.
cd /usr/scratch/fenga1/zexifu/manyRVData/ManyRVData_rebase
if sha256sum -c reports/rtl_reference_2026-09-08/dut_tripwire.sha256 --quiet 2>/dev/null; then
  echo "DUT UNCHANGED across the batch — every result is from one RTL state."
else
  echo "*** DUT CHANGED MID-BATCH — results are not attributable to one RTL state ***"
  sha256sum -c reports/rtl_reference_2026-09-08/dut_tripwire.sha256 2>&1 | grep -v ': OK$'
fi
