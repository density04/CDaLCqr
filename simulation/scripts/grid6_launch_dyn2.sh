#!/bin/bash
# Launch N idle-capable pull-workers on this host.
# Usage: grid6_launch_dyn2.sh ROOT NWORKERS HOSTTAG
set -u
ROOT=${1:?ROOT}; N=${2:-1}; TAG=${3:-$(hostname -s)}
for i in $(seq 1 "$N"); do
  WID="${TAG}_${i}"
  nohup setsid bash "$ROOT/simulation/scripts/grid6_worker_dyn2.sh" "$ROOT" "$WID" \
    >/dev/null 2>&1 </dev/null &
done
echo "launched ${TAG}_1..${TAG}_${N}"
