#!/bin/bash
# Periodic progress snapshots for a running grid (append-only log).
# Usage: monitor_n75.sh ROOT [INTERVAL_SECONDS]
set -u
R=${1:?ROOT}
INTERVAL=${2:-300}
cd "$R" || exit 1
mkdir -p logs
while [ ! -f "$R/STOP" ]; do
  ts=$(date "+%F %T")
  d=$(ls done 2>/dev/null | wc -l)
  q=$(ls queue 2>/dev/null | wc -l)
  a=$(ls assign 2>/dev/null | wc -l)
  f=$(cat results/worker_*.csv 2>/dev/null | grep -c '"failed"')
  echo "$ts done=$d queue=$q assign=$a failed=$f" >> logs/monitor.log
  sleep "$INTERVAL"
done
