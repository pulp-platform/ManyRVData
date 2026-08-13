#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load user configs
source "$SCRIPT_DIR/configs.sh"

# Derived paths (absolute, so they stay valid once we cd into ROOT_PATH)
ROOT_PATH="$(realpath "$ROOT_PATH")"
SIM_CMD="${ROOT_PATH}/sim/bin/cachepool_cluster.vsim"
SW_PATH="${ROOT_PATH}/software/build/CachePoolTests"
SIM_LOG_DIR="${ROOT_PATH}/sim/bin/logs"   # where perf logs appear
LOG_DIR="$(realpath -m "${SCRIPT_DIR}/logs/$(date +%Y%m%d-%H%M%S)")"
mkdir -p "$LOG_DIR"
ln -sfn "$LOG_DIR" "${SCRIPT_DIR}/logs/latest"

echo "== CachePool batch run =="
echo "ROOT_PATH : $ROOT_PATH"
echo "CONFIGS   : $CONFIGS"
echo "KERNELS   : $KERNELS"
echo "PREFIX    : $PREFIX"
echo "Logs      : $LOG_DIR (also at logs/latest)"
echo

for cfg in $CONFIGS; do
  echo "==== Building $cfg ===="
  make -C "$ROOT_PATH" -s clean generate update-floonoc bootrom vsim sw config=$cfg DEBUG=0 -B

  summary_file="${LOG_DIR}/${cfg}_summary.txt"
  rm -f "$summary_file"  # start fresh for each config

  for k in $KERNELS; do
    kernel_name="${PREFIX}${k}"
    bin_path="${SW_PATH}/${kernel_name}"
    log_file="${LOG_DIR}/${cfg}_${k}.log"

    echo "---- Running $cfg / $kernel_name ----"
    if [[ ! -f "$bin_path" ]]; then
      echo "  [WARN] Binary not found: $bin_path" | tee "$log_file"
      continue
    fi

    # Run from the repo root so relative sim artifacts (transcript, etc.) land there
    (cd "$ROOT_PATH" && "$SIM_CMD" "$bin_path") 2>&1 | tee "$log_file"

    # Move QuestaSim's own transcript/log artifact into the log folder
    for f in vsim.log sim/work/vsim.log; do
      if [[ -f "${ROOT_PATH}/${f}" ]]; then
        mv "${ROOT_PATH}/${f}" "${LOG_DIR}/${cfg}_${k}_$(basename "$f")"
      fi
    done

    # Copy generated perf logs if any, then clear files but keep the
    # subdir structure in place so the sim can write into it next kernel
    if [[ -d "$SIM_LOG_DIR" && "$(ls -A "$SIM_LOG_DIR")" ]]; then
      new_pm_dir="${LOG_DIR}/${cfg}_${k}_pm"
      cp -r "$SIM_LOG_DIR" "$new_pm_dir"
      find "$SIM_LOG_DIR" -type f -delete
      echo "  [INFO] Copied perf logs to $new_pm_dir"
    fi

    # Extract UART summary
    python3 "${SCRIPT_DIR}/write_results.py" "$log_file" "$summary_file" "$cfg" "$k"
  done

  echo "---- Summary for $cfg written to $summary_file ----"
done

echo
echo "All runs complete. Logs stored in $LOG_DIR"

python3 "${SCRIPT_DIR}/check-ci.py" $summary_file
