#!/bin/bash
# Keep one coordinator alive on this host.
# Usage: coord_watch_n75.sh ROOT
set -u
ROOT=${1:?ROOT}
LOG="$ROOT/logs/coordinator.log"
mkdir -p "$ROOT/logs"
while :; do
  Rscript "$ROOT/simulation/scripts/coordinator_n75.R" "$ROOT" >> "$LOG" 2>&1
  echo "coordinator exited $(date -u +%FT%TZ), restart in 2s" >> "$LOG"
  sleep 2
done
