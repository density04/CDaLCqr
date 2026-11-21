#!/bin/bash
# Idle-capable pull worker.  Unlike grid6_worker_dyn.sh it does NOT exit when the
# coordinator reports DONE: it sleeps and polls again, so a later task block
# (reps 21-40, 41-60, ...) is picked up automatically without relaunching hosts.
# Usage: grid6_worker_dyn2.sh ROOT WORKER_ID
set -u
ROOT=${1:?ROOT}; WID=${2:?WORKER_ID}
LIB=${CDA_LIB_DIR:-$ROOT/lib}
Q="$ROOT/queue"; RQ="$ROOT/req"; FD="$ROOT/feed"; DN="$ROOT/done"; ST="$ROOT/start"; RS="$ROOT/results"
FEED="$FD/$WID"; FIN="$FD/$WID.DONE"; LOG="$ROOT/logs/worker_${WID}.log"
mkdir -p "$Q" "$RQ" "$FD" "$DN" "$ST" "$RS" "$ROOT/logs"
touch "$FEED"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export CDA_PILOT_SCALE=${CDA_PILOT_SCALE:-0.5}
export R_LIBS="$LIB${CDA_R_LIBS:+:$CDA_R_LIBS}"
cd "$ROOT" || exit 1
echo "WORKER $WID START $(date -u +%FT%TZ)" >> "$LOG"
pos=0
while :; do
  [ -f "$ROOT/STOP" ] && break
  total=$(wc -l < "$FEED" 2>/dev/null || echo 0)
  while [ "$pos" -lt "$total" ]; do
    pos=$((pos + 1))
    id=$(sed -n "${pos}p" "$FEED" | sed 's/[[:space:]]*$//')
    [ -z "$id" ] && continue
    [ -f "$DN/$id" ] && continue
    f="$Q/$id.task"
    [ -f "$f" ] || { echo "MISSING $id" >> "$LOG"; continue; }
    : > "$ST/$id"
    IFS=',' read -r setup tau p rep method < "$f"
    before=$([ -f "$RS/worker_${WID}.csv" ] && wc -l < "$RS/worker_${WID}.csv" || echo 0)
    tmo=3600
    case "$method" in MA_*) tmo=10800 ;; esac
    timeout -s TERM "$tmo" Rscript "$ROOT/simulation/scripts/grid6_task_n75.R" \
      "$ROOT" "$setup" "$tau" "$p" "$rep" "$method" "$LIB" "$WID" >> "$LOG" 2>&1
    rc=$?
    after=$([ -f "$RS/worker_${WID}.csv" ] && wc -l < "$RS/worker_${WID}.csv" || echo 0)
    if [ "$rc" -ne 0 ] && [ "$after" -eq "$before" ]; then
      Rscript "$ROOT/simulation/scripts/grid6_fail.R" "$ROOT" "$setup" "$tau" "$p" "$rep" \
        "$method" "$WID" "$rc" >> "$LOG" 2>&1
    fi
    echo "$(date -u +%FT%TZ) rc=$rc" > "$DN/$id"
  done
  [ -f "$ROOT/STOP" ] && break
  if [ -f "$FIN" ]; then
    rm -f "$FIN"
    sleep 20
    continue
  fi
  tok="$(date +%s)_${RANDOM}_${pos}"
  : > "$RQ/${WID}__${tok}"
  waited=0
  while [ "$waited" -lt 600 ]; do
    nt=$(wc -l < "$FEED" 2>/dev/null || echo 0)
    [ "$nt" -gt "$total" ] && break
    [ -f "$FIN" ] && break
    [ -f "$ROOT/STOP" ] && break
    sleep 2
    waited=$((waited + 2))
  done
done
echo "WORKER $WID EXIT $(date -u +%FT%TZ)" >> "$LOG"
