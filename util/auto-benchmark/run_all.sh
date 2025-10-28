#!/usr/bin/env bash
set -e

# Load user configs
source ./configs.sh

# Derived paths
SIM_CMD="${ROOT_PATH}/sim/bin/cachepool_cluster.vsim"
SW_PATH="${ROOT_PATH}/software/build/CachePoolTests"
SIM_LOG_DIR="./sim/bin/logs"   # where perf logs appear
LOG_DIR="logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"
ln -sfn "$(realpath "$LOG_DIR")" logs/latest

echo "== CachePool batch run =="
echo "ROOT_PATH : $ROOT_PATH"
echo "CONFIGS   : $CONFIGS"
echo "KERNELS   : $KERNELS"
echo "PREFIX    : $PREFIX"
echo "Logs      : $LOG_DIR (also at logs/latest)"
echo

for cfg in $CONFIGS; do
  echo "==== Building $cfg ===="
  make -C "$ROOT_PATH" -s clean generate vsim config=$cfg

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

    # Run simulation and capture output
    "$SIM_CMD" "$bin_path" 2>&1 | tee "$log_file"

    # Move generated perf logs if any
    if [[ -d "$SIM_LOG_DIR" && "$(ls -A "$SIM_LOG_DIR")" ]]; then
      new_pm_dir="${LOG_DIR}/${cfg}_${k}_pm"
      mv "$SIM_LOG_DIR" "$new_pm_dir"
      echo "  [INFO] Moved perf logs to $new_pm_dir"
    fi

    # Extract UART summary
    python3 write_results.py "$log_file" "$summary_file" "$cfg" "$k"
  done

  echo "---- Summary for $cfg written to $summary_file ----"
done

echo
echo "All runs complete. Logs stored in $LOG_DIR"
