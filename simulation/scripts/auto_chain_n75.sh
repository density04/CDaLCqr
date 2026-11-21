#!/bin/bash
# Auto-continuation of the n=75 simulation (run on the coordinator host).
#
# After reps 1-20 are fully done it appends the next 20-rep block to the pull
# queue (unique task ids, offsets continue), then 41-60, ... up to MAXREP.
# Reproducibility is inherent: grid6_task_n75.R sets seed = 2026 + replication,
# and every task id embeds the replication, so no id/seed is ever reused.
#
# Also: restarts the coordinator if it dies, and keeps idle workers alive
# (grid6_worker_dyn2.sh), so a new block is picked up without relaunching.
#
# Hosts are read from $ROOT/hosts.txt (one "host|port|tag|workers" per line,
# use "local|0|tag|workers" for the coordinator host; see hosts.example.txt).
# Without that file the script runs workers on the local host only.
#
# Usage: auto_chain_n75.sh [ROOT] [MAXREP]
# Env:   SSH_OPTS (extra ssh options), SSH_USER (default root)
set -u
ROOT=${1:-$PWD}
MAXREP=${2:-100}
BLOCK=20
PER_BLOCK=8640            # 6 p * 4 setups * 3 taus * 20 reps * 6 methods
LOG="$ROOT/logs/auto_chain.log"
SSH_USER=${SSH_USER:-root}
SSH_OPTS=${SSH_OPTS:-"-o BatchMode=yes -o ConnectTimeout=10"}
mkdir -p "$ROOT/logs"
cd "$ROOT" || exit 1
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

HOSTS=()
if [ -f "$ROOT/hosts.txt" ]; then
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    HOSTS+=("$line")
  done < "$ROOT/hosts.txt"
else
  HOSTS=("local|0|$(hostname -s)|$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)")
fi
log "hosts: ${HOSTS[*]}"

count_done() { ls "$ROOT/done" 2>/dev/null | wc -l; }

host_workers() { # $1=host $2=port $3=pattern
  local c
  if [ "$1" = local ]; then
    c=$(pgrep -fc "$3" 2>/dev/null || true)
  else
    c=$(ssh $SSH_OPTS -p "$2" "$SSH_USER@$1" "pgrep -fc '$3'" 2>/dev/null || true)
  fi
  echo "${c:-0}"
}

total_workers() { # $1=pattern
  local t=0 c
  for spec in "${HOSTS[@]}"; do
    IFS='|' read -r host port tag n <<< "$spec"
    c=$(host_workers "$host" "$port" "$1")
    t=$((t + c))
  done
  echo "$t"
}

launch_host() { # $1=host $2=port $3=count $4=tag
  local h=$1 p=$2 n=$3 t=$4
  if [ "$h" = local ]; then
    bash "$ROOT/simulation/scripts/grid6_launch_dyn2.sh" "$ROOT" "$n" "$t" >> "$LOG" 2>&1
  else
    ssh $SSH_OPTS -p "$p" "$SSH_USER@$h" \
      "bash $ROOT/simulation/scripts/grid6_launch_dyn2.sh $ROOT $n $t" >> "$LOG" 2>&1
  fi
}

ensure_workers() { # $1=round; launch only the per-host deficit (never oversubscribe)
  local r=$1 c n want
  for spec in "${HOSTS[@]}"; do
    IFS='|' read -r host port tag n <<< "$spec"
    c=$(host_workers "$host" "$port" 'grid6_worker_dyn2\.sh')
    c=${c:-0}
    if [ "$c" -lt $(( n / 2 )) ]; then
      want=$(( n - c ))
      launch_host "$host" "$port" "$want" "${tag}f${r}"
      log "ensure_workers $tag: had=$c target=$n launch=$want tag=${tag}f${r}"
    fi
  done
}

make_block() { # $1=block index
  local k=$1 r0=$(( (k - 1) * BLOCK + 1 )) r1=$(( k * BLOCK )) idx0=$(( (k - 1) * PER_BLOCK ))
  Rscript "$ROOT/simulation/scripts/make_queue_n75b.R" "$ROOT" "$r0" "$r1" "$idx0" >> "$LOG" 2>&1
}

block_present() { # $1=first replication of the block
  [ -n "$(ls "$ROOT/queue" 2>/dev/null | grep "_r$(printf '%03d' "$1")_" | head -n 1)" ]
}

TOTAL_BLOCKS=$(( MAXREP / BLOCK ))
gen=0
round=0
log "AUTOCHAIN START maxrep=$MAXREP blocks=$TOTAL_BLOCKS root=$ROOT"
while :; do
  [ -f "$ROOT/STOP" ] && { log "STOP file present, exit"; break; }

  if ! pgrep -f 'coordinator_n75\.R' >/dev/null 2>&1; then
    nohup Rscript "$ROOT/simulation/scripts/coordinator_n75.R" "$ROOT" >> "$ROOT/logs/coordinator.log" 2>&1 &
    log "coordinator restarted pid=$!"
    sleep 3
  fi

  D=$(count_done)

  for k in $(seq 1 "$TOTAL_BLOCKS"); do
    [ "$gen" -ge "$k" ] && continue
    [ "$D" -lt $(( (k - 1) * PER_BLOCK )) ] && break
    r0=$(( (k - 1) * BLOCK + 1 ))
    if block_present "$r0"; then
      gen=$k
      continue
    fi
    make_block "$k"
    if block_present "$r0"; then
      gen=$k
      log "block $k (reps $r0-$(( k * BLOCK ))) generated, done=$D"
    else
      log "ERROR block $k generation failed"
    fi
    sleep 3
  done

  newc=$(total_workers 'grid6_worker_dyn2\.sh')
  if [ "$round" -eq 0 ]; then
    round=1
    for spec in "${HOSTS[@]}"; do
      IFS='|' read -r host port tag n <<< "$spec"
      c=$(host_workers "$host" "$port" 'grid6_worker_dyn2\.sh')
      c=${c:-0}
      [ "$c" -lt "$n" ] && launch_host "$host" "$port" $(( n - c )) "${tag}r1"
    done
    log "initial idle-worker launch round 1"
    sleep 30
  elif [ "$newc" -lt 100 ]; then
    round=$((round + 1))
    ensure_workers "$round"
    log "relaunch round $round (live idle workers=$newc)"
    sleep 30
  fi

  if [ "$D" -ge $(( MAXREP * PER_BLOCK )) ]; then
    touch "$ROOT/STOP"
    log "ALL DONE done=$D"
    break
  fi
  sleep 120
done
