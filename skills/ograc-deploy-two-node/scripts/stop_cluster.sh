#!/bin/bash
# Stop the two-node oGRAC cluster: DB (immediate) -> appctl stop on both nodes.
# Requires SUDO_PWD. Stops only this deployment; never touches other users' processes.
#
# Usage: SUDO_PWD='<sudo password>' bash stop_cluster.sh [--with-om-only]
set -uo pipefail

ROOT=${ROOT:-$HOME/ograc_cluster}
NODE0=${NODE0:?set NODE0 to the node0 address}
NODE1=${NODE1:?set NODE1 to the node1 address}
SSH_USER=${SSH_USER:-$USER}
DB_PORT=${DB_PORT:-29300}
: "${SUDO_PWD:?set SUDO_PWD to the sudo password}"

DATA_DIR="$ROOT/dbdata/local/ograc/tmp/data"
DB_BIN="$ROOT/ograc/ograc/server/bin"
ACTION="$ROOT/ograc_connector/action"
UB_LIB=/usr/local/ubs_mem/lib
LOG="$ROOT/logs/stop-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$ROOT/logs"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
ssh1() { ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_USER@$NODE1" "$@"; }
sudo_run() { printf '%s\n' "$SUDO_PWD" | sudo -S -p '' "$@"; }

log "=== stop DB (immediate) ==="
if pgrep -f "$DB_BIN/ogracd" >/dev/null 2>&1; then
    ( source "$HOME/.bashrc" >/dev/null 2>&1 || true
      export LD_LIBRARY_PATH="$ROOT/ograc/ograc/server/lib:$UB_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      timeout 180 "$DB_BIN/shutdowndb.sh" -h "$NODE0" -p "$DB_PORT" -m immediate -D "$DATA_DIR" -T 120 ) \
        2>&1 | tee -a "$LOG"
    log "shutdowndb returned ${PIPESTATUS[0]}"
else
    log "no local ogracd running"
fi

sleep 3

log "=== stop appctl services on node0 ==="
if [[ -d "$ACTION" ]]; then
    ( cd "$ACTION" && sudo_run timeout 240 sh appctl.sh stop ) 2>&1 | tee -a "$LOG" \
        || log "WARN: node0 appctl.sh stop returned non-zero"
else
    log "WARN: $ACTION not found"
fi

log "=== stop appctl services on node1 ==="
if ssh1 "test -d '$ACTION'"; then
    printf '%s\n' "$SUDO_PWD" | ssh1 "cd '$ACTION' && sudo -S -p '' timeout 240 sh appctl.sh stop" 2>&1 | tee -a "$LOG" \
        || log "WARN: node1 appctl.sh stop returned non-zero"
else
    log "WARN: $ACTION not found on node1"
fi

log "=== clean stale deploy locks ==="
for node in 0 1; do
    if [[ "$node" == "0" ]]; then
        if [[ -e "/tmp/ograc_deploy_lock_${USER}" ]]; then
            sudo_run rm -rf "/tmp/ograc_deploy_lock_${USER}" && log "removed local deploy lock"
        fi
    else
        ssh1 "if [ -e '/tmp/ograc_deploy_lock_${SSH_USER}' ]; then echo present; fi" | grep -q present && {
            printf '%s\n' "$SUDO_PWD" | ssh1 "sudo -S -p '' rm -rf '/tmp/ograc_deploy_lock_${SSH_USER}'"
            log "removed node1 deploy lock"
        }
    fi
done

sleep 3
log "=== remaining processes (only this ROOT) ==="
our_procs() {
    ps -eo pid=,comm=,args= | awk -v r="$ROOT" \
        '($2=="ogracd" || $2=="cms" || $2=="dssserver") && index($0, r) {print}'
}
local_procs=$(our_procs)
remote_procs=$(ssh1 "ps -eo pid=,comm=,args= | awk -v r='$ROOT' '\$2==\"ogracd\" || \$2==\"cms\" || \$2==\"dssserver\" { if (index(\$0, r)) print }'" 2>/dev/null || true)

if [[ -z "$local_procs" && -z "$remote_procs" ]]; then
    log "all target processes stopped"
    exit 0
fi

[[ -n "$local_procs" ]] && { log "remaining on node0:"; printf '%s\n' "$local_procs" | tee -a "$LOG"; }
[[ -n "$remote_procs" ]] && { log "remaining on node1:"; printf '%s\n' "$remote_procs" | tee -a "$LOG"; }
log "WARN: some processes remain; inspect the list above before killing anything"
exit 1
