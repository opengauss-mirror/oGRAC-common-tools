#!/bin/bash
# Restore a dss_cold_backup.sh image with dsscmd cp (no ogbackup).
#
# Preconditions:
#   - all oGRAC DB processes for this deployment are stopped
#   - CMS is stopped (recommended; no resource agent may restart the DB mid-copy)
#   - DSS is running on this node and points at the same DSS_HOME/LUNs
#
# Usage:
#   bash dss_cold_restore.sh <backup_dir>
# Env:
#   ROOT, DSS_HOME, PARALLEL (default 2)
set -uo pipefail

ROOT=${ROOT:-$HOME/ograc_cluster}
DATA=$ROOT/dbdata/local/ograc/tmp/data
DSS_HOME=${DSS_HOME:-$ROOT/ograc/dss}
UB_LIB=/usr/local/ubs_mem/lib
export DSS_HOME
export LD_LIBRARY_PATH="$DSS_HOME/lib:$ROOT/ograc/ograc/server/lib:$UB_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
DSScmd="$DSS_HOME/bin/dsscmd"
PARALLEL=${PARALLEL:-2}
BACKUP=${1:-}
STAMP=$(date +%Y%m%d-%H%M%S)
LOG=$ROOT/logs/dss-cold-restore-$STAMP.log

mkdir -p "$ROOT/logs"
log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
fail(){ log "ERROR: $*"; exit 1; }

[[ -n "$BACKUP" && -f "$BACKUP/MANIFEST.tsv" ]] || fail "usage: $0 <backup_dir with MANIFEST.tsv>"
db_pids(){ ps -eo pid=,args= | awk -v d="$DATA" '$0 ~ /(^|[\/ ])ogracd( |$)/ && index($0,d){print $1}'; }
[[ -z "$(db_pids)" ]] || fail "stop ogracd first: $(db_pids | tr '\n' ' ')"
[[ -S "$DSS_HOME/.dss_unix_d_socket" ]] || fail "DSS socket not found; start DSS first"
"$DSScmd" lsvg >/dev/null 2>&1 || fail "dsscmd lsvg failed"

# Data files first, control files last, so an interrupted restore never leaves
# a control image pointing at half-restored data.
awk -F'\t' '$2 ~ /^ctrl/ {print $1"\t"$2}' "$BACKUP/MANIFEST.tsv" > "$BACKUP/.ctrl.list"
awk -F'\t' '$2 !~ /^ctrl/ {print $1"\t"$2}' "$BACKUP/MANIFEST.tsv" > "$BACKUP/.data.list"

restore_one(){
    local vg=$1 name=$2
    local src="$BACKUP/${vg#+}/$name"
    [[ -f "$src" ]] || { echo "$vg/$name missing-local" >> "$BACKUP/FAILED"; return 1; }
    # Do NOT pad ctrl files to the DSS logical allocation (40MB).  The DB checks
    # the restored written size (ctrl1-3: 35,880,960 bytes); padding makes it
    # 41,943,040 and the DB refuses to open with "ctrl file size is abnormal".
    "$DSScmd" rm -p "$vg/$name" >> "$LOG" 2>&1 || true
    if ! "$DSScmd" cp -s "$src" -d "$vg/$name" >> "$LOG" 2>&1; then
        echo "$vg/$name copy-failed" >> "$BACKUP/FAILED"
        return 1
    fi
    return 0
}

run_list(){
    local list=$1
    : > "$BACKUP/FAILED"
    local running=0 vg name
    while IFS=$'\t' read -r vg name _; do
        [[ -n "${vg:-}" && -n "${name:-}" ]] || continue
        restore_one "$vg" "$name" &
        running=$((running+1))
        if (( running >= PARALLEL )); then wait -n 2>/dev/null || true; running=$((running-1)); fi
    done < "$list"
    wait
    [[ ! -s "$BACKUP/FAILED" ]] || fail "restore failed: $(tr '\n' ' ' < "$BACKUP/FAILED")"
}

log "restore from $BACKUP"
log "data files..."
run_list "$BACKUP/.data.list"
log "control files..."
run_list "$BACKUP/.ctrl.list"
log "restored $(wc -l < "$BACKUP/MANIFEST.tsv") files; verify sizes via dsscmd ls"
log "next: restart DSS both nodes, start CMS, then DB node0 (wait ONLINE/JOINED), then node1"
log "example: sh $ROOT/ograc/action/ograc/appctl.sh start  (node0, as root); then node1"
rm -f "$BACKUP/.data.list" "$BACKUP/.ctrl.list" "$BACKUP/FAILED"
