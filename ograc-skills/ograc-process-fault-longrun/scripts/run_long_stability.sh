#!/bin/bash
# Long-stability process-failure test for an oGRAC two-node pipeline.
#
# Default: unlimited rounds (MAX_ROUNDS=0).  Each round:
#   cold restore -> start both DBs -> full-conflict TPCC -> SIGKILL a random
#   target at T0+120..180s -> wait for survivor GBP recovery reset -> check.
# A failed round records evidence via collect_failure.sh and the loop continues.
# This script never modifies product code, never rebuilds or deploys anything.
#
# Run as the deployment/pipeline user.  Environment:
#   BASE_DIR   output base (default $PIPE/longrun)
#   MAX_ROUNDS 0 = unlimited (default)
set -u

PIPE=${PIPE:-$HOME/ograc-pipeline}
ROOT=${ROOT:-$HOME/ograc_cluster}
SCRIPTS=${SCRIPTS:-$PIPE/scripts}
BASE_BACKUP=${BASE_BACKUP:-$HOME/ograc_backups/tpcc_dss_clean}
RESTORE=${RESTORE:-$SCRIPTS/restore_instance_from_cold_backup.sh}
CONTROLLER=${CONTROLLER:-$SCRIPTS/controller_perf_randomkill.sh}
CHECK=${CHECK:-$SCRIPTS/check_random_round.sh}
COLLECT=${COLLECT:-$SCRIPTS/collect_failure.sh}
BASE=${BASE_DIR:-$PIPE/longrun}
MAX_ROUNDS=${MAX_ROUNDS:-0}
STOP_FILE=$BASE/STOP

mkdir -p "$BASE" "$BASE/failures"
PROGRESS=$BASE/progress.log
log() { echo "[$(date '+%F %T')] $*" | tee -a "$PROGRESS"; }

# Continue numbering if this base already has round dirs.
r=$(ls -d "$BASE"/round-[0-9]* 2>/dev/null | sed 's#.*/round-##' | sort -n | tail -1)
r=${r:-0}
log "long-stability start base=$BASE max_rounds=$MAX_ROUNDS (0=unlimited) next_round=$((r + 1)) baseline=$BASE_BACKUP"
log "installed ogracd=$(sha256sum "$ROOT/ograc/ograc/server/bin/ogracd" 2>/dev/null | awk '{print $1}') libograc=$(sha256sum "$ROOT/ograc/ograc/server/lib/libograc.so" 2>/dev/null | awk '{print $1}')"

consecutive_setup_fail=0
while :; do
    [[ -f "$STOP_FILE" ]] && { log "STOP file found; exiting"; break; }
    if (( MAX_ROUNDS > 0 && r >= MAX_ROUNDS )); then
        log "reached max_rounds=$MAX_ROUNDS; exiting"
        break
    fi

    r=$((r + 1))
    target=$((RANDOM % 2))
    out=$BASE/round-$r
    mkdir -p "$out"
    round_start=$(date '+%F %T')
    echo "round=$r target=$target start=$round_start" >> "$BASE/targets.txt"
    log "round $r: target=$target survivor=$((1 - target)) start"

    timeout 3600 bash "$RESTORE" "$BASE_BACKUP" --yes --no-sha --no-verify > "$out/restore.out" 2>&1
    if ! grep -q 'restore completed successfully' "$out/restore.out"; then
        consecutive_setup_fail=$((consecutive_setup_fail + 1))
        log "round $r: RESTORE FAILED (consecutive=$consecutive_setup_fail); artifacts $out"
        timeout 300 bash "$COLLECT" "$out" "restore-fail" "$round_start" "$target" > "$out/collect.out" 2>&1 || true
        if (( consecutive_setup_fail >= 3 )); then
            log "round $r: 3 consecutive restore failures; stopping long run for inspection"
            break
        fi
        sleep 60
        continue
    fi
    consecutive_setup_fail=0
    log "round $r: restore ok, run controller"

    KILL_NODE=$target OUT_DIR=$out timeout 1800 bash "$CONTROLLER" > "$out/controller.out" 2>&1
    ctl=$?
    bash "$CHECK" "$out" "$round_start" "$target" "$((1 - target))" > "$out/check.log" 2>&1
    chk=$?
    verdict=$(grep '^ROUND_VERDICT=' "$out/check.out" 2>/dev/null | tail -1)
    log "round $r: target=$target controller_rc=$ctl check_rc=$chk $verdict"

    if [[ "$ctl" != 0 || "$chk" != 0 ]]; then
        log "round $r: FAILED; collecting evidence, continuing (no code changes)"
        timeout 300 bash "$COLLECT" "$out" "round-fail" "$round_start" "$target" > "$out/collect.out" 2>&1 || true
    fi
done
log "long-stability driver exited at round $r"
