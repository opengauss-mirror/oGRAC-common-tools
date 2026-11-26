#!/bin/bash
# Cold, file-level backup of the oGRAC DSS data using dsscmd cp.
#
# Preconditions:
#   - all oGRAC DB processes for this deployment are stopped (DSS stays running)
#   - DSS_HOME points at this deployment's DSS
#
# The copy is only consistent when ogracd is stopped.  This is deliberate:
# restore is a plain dsscmd cp back into +vg1/+vg2, not an online backup chain.
#
# Usage:
#   bash dss_cold_backup.sh [backup_dir]
# Env:
#   ROOT (default $HOME/ograc_cluster)
#   VGS  (default "+vg1 +vg2")
#   PARALLEL (default 4)
#   SHA256 (default 1; set 0 to skip hashing)
set -uo pipefail

ROOT=${ROOT:-$HOME/ograc_cluster}
DATA=$ROOT/dbdata/local/ograc/tmp/data
DSS_HOME=${DSS_HOME:-$ROOT/ograc/dss}
UB_LIB=/usr/local/ubs_mem/lib
export DSS_HOME
export LD_LIBRARY_PATH="$DSS_HOME/lib:$ROOT/ograc/ograc/server/lib:$UB_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
DSScmd="$DSS_HOME/bin/dsscmd"
VGS=${VGS:-"+vg1 +vg2"}
PARALLEL=${PARALLEL:-4}
SHA256=${SHA256:-1}
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP=${1:-$HOME/ograc_backups/tpcc_dss_$STAMP}
LOG=$ROOT/logs/dss-cold-backup-$STAMP.log

mkdir -p "$ROOT/logs"
log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
fail(){ log "ERROR: $*"; exit 1; }

# Refuse to copy while this deployment's DB is running.
db_pids(){ ps -eo pid=,args= | awk -v d="$DATA" '$0 ~ /(^|[\/ ])ogracd( |$)/ && index($0,d){print $1}'; }
[[ -z "$(db_pids)" ]] || fail "ogracd is still running: $(db_pids | tr '\n' ' ')"

[[ -x "$DSScmd" ]] || fail "missing $DSScmd"
[[ -S "$DSS_HOME/.dss_unix_d_socket" ]] || fail "DSS socket not found; start DSS first"
"$DSScmd" lsvg >/dev/null 2>&1 || fail "dsscmd lsvg failed; DSS is not usable"

mkdir -p "$BACKUP"
: > "$BACKUP/MANIFEST.tsv"
: > "$BACKUP/SHA256SUMS"
log "backup_dir=$BACKUP vgs=[$VGS] parallel=$PARALLEL"

copy_one(){
    local vg=$1 name=$2
    local dst="$BACKUP/${vg#+}/$name"
    mkdir -p "$(dirname "$dst")"
    rm -f "$dst"
    if ! "$DSScmd" cp -s "$vg/$name" -d "$dst" >> "$LOG" 2>&1; then
        echo "$vg/$name" >> "$BACKUP/FAILED"
        return 1
    fi
    return 0
}

for vg in $VGS; do
    list="$BACKUP/${vg#+}.list"
    "$DSScmd" ls -p "$vg" > "$list" 2>>"$LOG" || fail "dsscmd ls $vg failed"
    # columns: type time size written_size name fid node_id
    awk '$1=="-" {print $6}' "$list" | while read -r name; do
        [[ -n "$name" ]] || continue
        echo "$name"
    done > "$list.names"
    total=$(wc -l < "$list.names")
    log "$vg: $total files"
    mkdir -p "$BACKUP/${vg#+}"
    running=0
    while IFS= read -r name; do
        copy_one "$vg" "$name" &
        running=$((running+1))
        if (( running >= PARALLEL )); then
            wait -n 2>/dev/null || true
            running=$((running-1))
        fi
    done < "$list.names"
    wait
done

[[ ! -s "$BACKUP/FAILED" ]] || fail "some files failed: $(tr '\n' ' ' < "$BACKUP/FAILED")"

# Manifest and optional integrity hashes.
for vg in $VGS; do
    list="$BACKUP/${vg#+}.list"
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        dss_logical=$(awk -v n="$name" '$1=="-" && $6==n {print $4}' "$list")
        dss_written=$(awk -v n="$name" '$1=="-" && $6==n {print $5}' "$list")
        dst="$BACKUP/${vg#+}/$name"
        local_size=$(stat -c%s "$dst")
        echo -e "${vg}\t${name}\t${dss_logical}\t${dss_written}\t${local_size}" >> "$BACKUP/MANIFEST.tsv"
    done < "$list.names"
done

if [[ "$SHA256" == "1" ]]; then
    log "computing sha256 (set SHA256=0 to skip)"
    ( cd "$BACKUP" && find vg1 vg2 -type f -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum > SHA256SUMS )
fi

{
    echo "# oGRAC DSS cold backup"
    echo
    echo "- created: $(date '+%F %T')"
    echo "- root: $ROOT"
    echo "- vgs: $VGS"
    echo "- cluster must be stopped while copying; only DSS runs."
    echo "- restore: stop DB/CMS, keep DSS, then run dss_cold_restore.sh <this dir>"
    echo
    echo "## Files"
    echo 'See MANIFEST.tsv (vg, name, dss logical size, dss written size, local size) and SHA256SUMS.'
} > "$BACKUP/README.md"

log "backup complete: $BACKUP"
du -sh "$BACKUP" | tee -a "$LOG"
