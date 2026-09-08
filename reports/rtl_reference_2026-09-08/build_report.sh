#!/bin/bash
# Rebuild summary.tsv from the logs. The batch script's inline grep looked for
# "Simulation ended at N" but the actual print is "[EOC] Simulation ended at
# <spaces> N (retval = 0)" in picoseconds -- so it recorded n/a for a run that
# had the number. Parse the logs instead of trusting that grep.
cd /usr/scratch/fenga1/zexifu/manyRVData/ManyRVData_rebase
OUT=reports/rtl_reference_2026-09-08
printf "kernel\tstatus\teoc_cyc\tretval\tkernel_cyc\tper_load\tsb_pass\tsb_fail\tillegal\n" > $OUT/summary.tsv
for t in bandwidth byte-enable cache-mix-smoke cache-test-scalar cache-test-vector; do
  L=$OUT/logs/$t.log
  [ -f "$L" ] || { printf "%s\tnot_run\t-\t-\t-\t-\t-\t-\t-\n" "$t" >> $OUT/summary.tsv; continue; }
  eocps=$(grep -oE "Simulation ended at +[0-9]+" "$L" | grep -oE "[0-9]+$" | tail -1)
  eoc=$([ -n "$eocps" ] && echo $((eocps/1000)) || echo "-")
  ret=$(grep -oE "retval = [0-9-]+" "$L" | grep -oE "[0-9-]+$" | tail -1)
  kc=$(grep -oE "Total cycles: [0-9]+" "$L" | grep -oE "[0-9]+$" | tail -1)
  pl=$(grep -oE "avg per load: [0-9]+" "$L" | grep -oE "[0-9]+$" | tail -1)
  sp=$(grep -c "STATUS: PASS" "$L"); sf=$(grep -c "STATUS: FAIL" "$L")
  ill=$(grep -ciE "illegal instruction" "$L")
  if   [ -n "$eocps" ] && [ "$ret" = "0" ] && [ "$sf" = "0" ]; then st=PASS
  elif [ -n "$eocps" ] && [ "$sf" != "0" ];                     then st=sb_violation
  elif [ -n "$eocps" ];                                         then st=eoc_nonzero_retval
  elif [ "$ill" != "0" ];                                       then st=TRAP
  else
    # No EOC yet. Three different things, and calling them all timeout_cap is
    # the kind of misleading row this script exists to avoid:
    #   running     -- vsim alive and this is the newest log
    #   crash       -- stopped early with an error
    #   timeout_cap -- neither; it was killed by the wallclock cap
    newest=$(ls -t $OUT/logs/*.log 2>/dev/null | head -1)
    if pgrep -f "vsimk.*ManyRVData_rebase" >/dev/null 2>&1 && [ "$newest" = "$L" ]; then
      st=running
    elif grep -qiE "fatal|error:|\\*\\* Error" "$L"; then st=crash
    else st=timeout_cap; fi
  fi
  # Keep the last kernel-printed line: a capped run still carries real results
  # (sub-tests that completed), and losing them to a bare timeout_cap row throws
  # away the informative half of the run.
  lu=$(grep "\[UART\]" "$L" | tail -1 | sed 's/.*\[UART\] *//' | cut -c1-46)
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$t" "$st" "$eoc" "${ret:--}" "${kc:--}" "${pl:--}" "$sp" "$sf" "$ill" "${lu:--}" >> $OUT/summary.tsv
done
column -t -s$'\t' $OUT/summary.tsv
