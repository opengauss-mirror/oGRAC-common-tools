#!/bin/bash
# Restore the two-node oGRAC instance from a dsscmd cold backup.
#
# This is the validated workflow:
#   stop DB cleanly (bounded; force-kill if it is wedged) -> stop CMS -> stop DSS
#   -> clean stale SysV shm + UB pools -> start one restore DSS
#   -> dsscmd cp every file back (data first, ctrl last, NO ctrl padding)
#   -> restart DSS -> start CMS -> start node0, wait ONLINE/JOINED
#   -> start node1, wait ONLINE/JOINED -> verify TPCC.
#
# It intentionally does NOT use ogbackup and does NOT clear SCSI PR keys with
# sudo sg_persist.  Manual PR clears were the main cause of later open failures.
#
# Usage:
#   bash restore_instance_from_cold_backup.sh <backup_dir> [--yes] [--no-verify] [--no-sha]
# Env:
#   ROOT (default $HOME/ograc_cluster)
#   NODE0/NODE1  addresses of the two nodes (required)
#   SSH_USER (default current user)
#   DATA_DEV/REDO_DEV/ARCH_DEV/GCC_DEV  four LUN device paths (for SCSI PR clear)
#   DB_PORT (default 29300)
set -uo pipefail

ROOT=${ROOT:-$HOME/ograc_cluster}
NODE0=${NODE0:?set NODE0 to the node0 address}
NODE1=${NODE1:?set NODE1 to the node1 address}
SSH_USER=${SSH_USER:-$USER}
SRC=${SRC:-$HOME/code/oGRAC}
DB_PORT=${DB_PORT:-29300}
SKILL_DIR=$(cd "$(dirname "$0")/.." && pwd)
DATA=$ROOT/dbdata/local/ograc/tmp/data
DSS_HOME=$ROOT/ograc/dss
CMS_HOME=$ROOT/ograc/cms
CMS_ACTION=$ROOT/ograc/action/cms
DB_BIN=$ROOT/ograc/ograc/server/bin
UB_LIB=/usr/local/ubs_mem/lib
TPCC_SKILL=${TPCC_SKILL:-$(cd "$SKILL_DIR/../tpcc-prepare-data" 2>/dev/null && pwd)}
WAREHOUSES=${WAREHOUSES:-100}
SUDO_PWD_FILE=${SUDO_PWD_FILE:-$HOME/.spw}
# Bounded clean shutdown.  A GBP-quarantined DB loops in reform and never
# answers "shutdown immediate"; shutdowndb.sh -T 1800 would keep the restore
# stuck for 30 minutes, so an external timeout is mandatory.
DB_STOP_TIMEOUT=${DB_STOP_TIMEOUT:-120}
# Optional fault-injection hook: when set, each DB process gets
# OGRAC_UB_FAULT_CMD=<FAULT_CMD_DIR>/ub_fault_cmd_nodeN.txt.
FAULT_CMD_DIR=${FAULT_CMD_DIR:-}
# Four LUN devices.  Only these devices are touched by the PR clear.
PR_DEVICES=${PR_DEVICES:-"${DATA_DEV:-} ${REDO_DEV:-} ${ARCH_DEV:-} ${GCC_DEV:-}"}
# UB pool cleanup before restore.  The DB object prefix carries the namespace
# version compiled into ogracd; set UB_POOL_GENERATION to match your build.
OGRAC_REPO=${OGRAC_REPO:-$SRC}
UB_POOL_GENERATION=${UB_POOL_GENERATION:-v12}
export UB_POOL_GENERATION
UB_TOOL_SRC=${UB_TOOL_SRC:-$SKILL_DIR/scripts/ub_pool_tool.c}
UB_TOOL_LOCAL=${UB_TOOL_LOCAL:-/tmp/ograc_ub_pool_tool_$$}
UB_TOOL_REMOTE=${UB_TOOL_REMOTE:-/tmp/ograc_ub_pool_tool_$$}
BACKUP=
ASSUME_YES=0
VERIFY=1
VERIFY_SHA=1

usage(){
    cat >&2 <<EOF
usage: $0 <backup_dir> [--yes] [--no-verify] [--no-sha]
  <backup_dir>  output of dss_cold_backup.sh (contains MANIFEST.tsv)
  --yes         do not prompt (required when stdin is not a TTY)
  --no-verify   skip TPCC row-count verification
  --no-sha      skip SHA256SUMS verification
EOF
    exit 2
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes) ASSUME_YES=1; shift ;;
        --no-verify) VERIFY=0; shift ;;
        --no-sha) VERIFY_SHA=0; shift ;;
        -h|--help) usage ;;
        -*) echo "unknown option: $1" >&2; usage ;;
        *) [[ -z "$BACKUP" ]] || usage; BACKUP=$1; shift ;;
    esac
done
[[ -n "$BACKUP" ]] || usage

STAMP=$(date +%Y%m%d-%H%M%S)
LOG=$ROOT/logs/cold-restore-$STAMP.log
mkdir -p "$ROOT/logs"
log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
fail(){ log "ERROR: $*"; exit 1; }
ssh1(){ ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_USER@$NODE1" "$@"; }
cms_stat(){ ( cd "$CMS_ACTION" && CMS_HOME="$CMS_HOME" \
    LD_LIBRARY_PATH="$CMS_HOME/service/lib:$CMS_HOME/service/add-ons" \
    timeout 8 "$CMS_HOME/service/bin/cms" stat "$@" 2>/dev/null ); }
db_pid0(){ ps -eo pid=,args= | awk -v d="$DATA" '$0 ~ /(^|[\/ ])ogracd( |$)/ && index($0,d){print $1; exit}'; }
db_pid1(){ ssh1 "ps -eo pid=,args= | awk -v d='$DATA' '\$0 ~ /(^|[\\/ ])ogracd( |\$)/ && index(\$0,d){print \$1; exit}'"; }
# All matching PIDs, used by the force-stop path (a node normally has one
# ogracd, but never assume it: wait_no_db must also see duplicates).
db_pids0(){ ps -eo pid=,args= | awk -v d="$DATA" '$0 ~ /(^|[\/ ])ogracd( |$)/ && index($0,d){print $1}'; }
db_pids1(){ ssh1 "ps -eo pid=,args= | awk -v d='$DATA' '\$0 ~ /(^|[\\/ ])ogracd( |\$)/ && index(\$0,d){print \$1}'"; }
dss_pids0(){ ps -eo pid=,args= | awk -v d="$DSS_HOME" '$0 ~ /(^|[\/ ])dssserver( |$)/ && index($0,d){print $1}'; }
dss_pids1(){ ssh1 "ps -eo pid=,args= | awk -v d='$DSS_HOME' '\$0 ~ /(^|[\\/ ])dssserver( |\$)/ && index(\$0,d){print \$1}'"; }
dsscmd(){ env DSS_HOME="$DSS_HOME" LD_LIBRARY_PATH="$DSS_HOME/lib:$ROOT/ograc/ograc/server/lib:$UB_LIB" \
    timeout 30 "$DSS_HOME/bin/dsscmd" "$@"; }
dsscmd_t(){ env DSS_HOME="$DSS_HOME" LD_LIBRARY_PATH="$DSS_HOME/lib:$ROOT/ograc/ograc/server/lib:$UB_LIB" \
    timeout 5 "$DSS_HOME/bin/dsscmd" "$@"; }
dsscmd1(){ ssh1 "export DSS_HOME='$DSS_HOME'; export LD_LIBRARY_PATH='$DSS_HOME/lib:$ROOT/ograc/ograc/server/lib:$UB_LIB'; timeout 30 '$DSS_HOME/bin/dsscmd' $*"; }
dsscmd1_t(){ ssh1 "export DSS_HOME='$DSS_HOME'; export LD_LIBRARY_PATH='$DSS_HOME/lib:$ROOT/ograc/ograc/server/lib:$UB_LIB'; timeout 10 '$DSS_HOME/bin/dsscmd' $*"; }
node_joined(){ cms_stat -res db | awk -v n="$1" '$2=="db" && $1==n && $3=="ONLINE" && $6==1 {f=1} END{exit !f}'; }
wait_joined(){ local n=$1 t=${2:-300} i; for ((i=0;i<t;i+=3)); do node_joined "$n" && return 0; sleep 3; done; return 1; }
wait_no_db(){ local t=${1:-300} i; for ((i=0;i<t;i+=2)); do
    [[ -z "$(db_pids0)$(db_pids1)" ]] && return 0; sleep 2; done; return 1; }
start_dss0(){ ( export DSS_HOME LD_LIBRARY_PATH="$DSS_HOME/lib:$ROOT/ograc/ograc/server/lib:$UB_LIB"
    timeout 60 bash "$DSS_HOME/dss_contrl.sh" -start 0 ) >>"$LOG" 2>&1; }
start_dss1(){ ssh1 "export DSS_HOME='$DSS_HOME'; export LD_LIBRARY_PATH='$DSS_HOME/lib:$ROOT/ograc/ograc/server/lib:$UB_LIB'; timeout 60 bash '$DSS_HOME/dss_contrl.sh' -start 1" >>"$LOG" 2>&1; }
stop_dss_all(){
    ( export DSS_HOME LD_LIBRARY_PATH="$DSS_HOME/lib:$ROOT/ograc/ograc/server/lib:$UB_LIB"
      timeout 60 bash "$DSS_HOME/dss_contrl.sh" -stop 0 ) >>"$LOG" 2>&1 || true
    ssh1 "export DSS_HOME='$DSS_HOME'; export LD_LIBRARY_PATH='$DSS_HOME/lib:$ROOT/ograc/ograc/server/lib:$UB_LIB'; timeout 60 bash '$DSS_HOME/dss_contrl.sh' -stop 1" >>"$LOG" 2>&1 || true
    sleep 1
    local p
    for p in $(dss_pids0); do kill -9 "$p" 2>/dev/null || true; done
    for p in $(dss_pids1); do ssh1 "kill -9 $p" 2>/dev/null || true; done
    rm -f "$DSS_HOME/.dss_unix_d_socket" 2>/dev/null || true
    ssh1 "rm -f '$DSS_HOME/.dss_unix_d_socket'" 2>/dev/null || true
}
cms_pids0(){ ps -eo pid=,args= | awk -v b="$CMS_HOME/service/bin/cms" '$2==b && $3=="server"{print $1}'; }
cms_pids1(){ ssh1 "ps -eo pid=,args= | awk -v b='$CMS_HOME/service/bin/cms' '\$2==b && \$3==\"server\"{print \$1}'"; }
stop_cms_all(){
    # Must run before any force kill: a live CMS restarts ogracd immediately.
    # The process match is on our exact cms path, so other instances' CMS is never
    # signalled even though it runs on the same two hosts.
    ( cd "$CMS_ACTION" && timeout 120 python3 cms_ctl.py stop ) >>"$LOG" 2>&1 || true
    ssh1 "cd '$CMS_ACTION' && timeout 120 python3 cms_ctl.py stop" >>"$LOG" 2>&1 || true
    local i p
    for ((i=0;i<30;i++)); do
        [[ -z "$(cms_pids0)$(cms_pids1)" ]] && return 0
        sleep 2
    done
    log "WARN: CMS still running; SIGKILL our CMS processes only"
    for p in $(cms_pids0); do kill -9 "$p" 2>/dev/null || true; done
    for p in $(cms_pids1); do ssh1 "kill -9 $p" 2>/dev/null || true; done
    sleep 1
    [[ -z "$(cms_pids0)$(cms_pids1)" ]]
}
stop_client_pids(){
    # Our shutdowndb.sh/ogsql clients for this data dir.  A timed-out
    # shutdowndb.sh leaves ogsql attached; that session is what produced
    # "Shutdown current session (sid 52) is prohibited" and blocks shutdown.
    ps -eo pid=,args= | awk -v d="$DATA" '$2 ~ /(^|\/)(shutdowndb\.sh|ogsql)$/ && index($0,d){print $1}'
}
kill_stop_clients(){
    local p
    for p in $(stop_client_pids); do kill -TERM "$p" 2>/dev/null || true; done
}
force_kill_db(){
    # Last resort after the bounded clean shutdown failed.  CMS must already be
    # stopped, otherwise it restarts ogracd.  Every PID is validated by its
    # command line (ogracd + our data dir) before a signal is sent, so other users' oGRAC instances
    # and other users' processes can never match.
    local n pids p args
    for n in 0 1; do
        if [[ "$n" == 0 ]]; then pids=$(db_pids0); else pids=$(db_pids1); fi
        [[ -n "$pids" ]] || continue
        log "force-stop node$n pids=[$(echo $pids | tr '\n' ' ')] (SIGTERM)"
        for p in $pids; do
            if [[ "$n" == 0 ]]; then args=$(ps -o args= -p "$p" 2>/dev/null); else args=$(ssh1 "ps -o args= -p '$p' 2>/dev/null"); fi
            if [[ "$args" != *ogracd* || "$args" != *"$DATA"* ]]; then
                log "WARN: refusing to signal node$n pid $p (args: ${args:-gone})"
                continue
            fi
            if [[ "$n" == 0 ]]; then kill -TERM "$p" 2>/dev/null || true; else ssh1 "kill -TERM $p" 2>/dev/null || true; fi
        done
    done
    wait_no_db 30 && return 0
    for n in 0 1; do
        if [[ "$n" == 0 ]]; then pids=$(db_pids0); else pids=$(db_pids1); fi
        [[ -n "$pids" ]] || continue
        log "force-stop node$n pids=[$(echo $pids | tr '\n' ' ')] (SIGKILL)"
        for p in $pids; do
            if [[ "$n" == 0 ]]; then args=$(ps -o args= -p "$p" 2>/dev/null); else args=$(ssh1 "ps -o args= -p '$p' 2>/dev/null"); fi
            if [[ "$args" != *ogracd* || "$args" != *"$DATA"* ]]; then
                log "WARN: refusing to SIGKILL node$n pid $p (args: ${args:-gone})"
                continue
            fi
            if [[ "$n" == 0 ]]; then kill -KILL "$p" 2>/dev/null || true; else ssh1 "kill -KILL $p" 2>/dev/null || true; fi
        done
    done
    wait_no_db 60
}
sudo_local(){ # run sudo on node0, password from the protected file on stdin
    [[ -r "$SUDO_PWD_FILE" ]] || return 1
    local pw
    pw=$(cat "$SUDO_PWD_FILE")
    printf '%s\n' "$pw" | sudo -S -p '' "$@" >>"$LOG" 2>&1
}
sudo_remote(){ # run sudo on node1, password from the protected file on stdin
    [[ -r "$SUDO_PWD_FILE" ]] || return 1
    local pw
    pw=$(cat "$SUDO_PWD_FILE")
    printf '%s\n' "$pw" | ssh1 "sudo -S -p '' $*" >>"$LOG" 2>&1
}
stale_shm_lines(){ # <0|1>: current-user 0x32 segments with no attached process
    local out
    if [[ "$1" == 0 ]]; then out=$(LC_ALL=C ipcs -m); else out=$(ssh1 "LC_ALL=C ipcs -m"); fi
    printf '%s\n' "$out" | awk -v u="$(id -u)" -v n="$(id -un)" \
        '$1 ~ /^0x32/ && ($3==u || $3==n) && $6==0 {print $1, $2, $3, $6}'
}
cleanup_stale_sysv_shm(){
    # DSS uses fixed SysV keys 0x32xxxxxx.  A segment left by a killed DSS/DB
    # (or created before the uid migration) makes the next DSS die with
    # "Failed to attach shared memory key=0x32000001".  Remove only segments
    # owned by the current user, 0x32 keys, nattch=0.  Foreign segments --
    # including other instances' -- are reported and never touched.
    local node key shmid owner nattch removed out foreign
    for node in 0 1; do
        removed=0
        while read -r key shmid owner nattch; do
            [[ -n "$shmid" ]] || continue
            if [[ "$node" == 0 ]]; then
                ipcrm -m "$shmid" >/dev/null 2>&1 || sudo_local ipcrm -m "$shmid" \
                    || { log "WARN: node0 cannot remove shm key=$key shmid=$shmid"; continue; }
            else
                # </dev/null is required: ssh would otherwise consume the rest
                # of the "while read" list on stdin and stop the loop after
                # the first segment.
                ssh1 "ipcrm -m $shmid" </dev/null >/dev/null 2>&1 \
                    || { log "WARN: node1 cannot remove shm key=$key shmid=$shmid"; continue; }
            fi
            removed=$((removed+1)); log "removed stale shm node$node key=$key shmid=$shmid"
        done < <(stale_shm_lines "$node")
        log "SysV shm node$node: removed $removed stale 0x32 segment(s)"
        if [[ -n "$(stale_shm_lines "$node")" ]]; then
            fail "stale current-user 0x32 shm remains on node$node: $(stale_shm_lines "$node" | tr '\n' ' ')"
        fi
        if [[ "$node" == 0 ]]; then out=$(LC_ALL=C ipcs -m); else out=$(ssh1 "LC_ALL=C ipcs -m"); fi
        foreign=$(printf '%s\n' "$out" | awk -v u="$(id -u)" -v n="$(id -un)" \
            '$1 ~ /^0x32/ && $6==0 && $3!=u && $3!=n {print $1"/"$3}')
        [[ -z "$foreign" ]] || log "WARN: node$node foreign 0x32 shm left untouched: $(echo "$foreign" | tr '\n' ' ')"
    done
}
node_caps_ok(){ # <0|1>: cms has RAWIO and perctrl has SYS_ADMIN+RAWIO
    local c p
    if [[ "$1" == 0 ]]; then
        c=$(getcap "$CMS_HOME/service/bin/cms" 2>/dev/null)
        p=$(getcap "$DSS_HOME/bin/perctrl" 2>/dev/null)
    else
        c=$(ssh1 "getcap '$CMS_HOME/service/bin/cms' 2>/dev/null")
        p=$(ssh1 "getcap '$DSS_HOME/bin/perctrl' 2>/dev/null")
    fi
    [[ "$c" == *cap_sys_rawio* && "$p" == *cap_sys_admin* && "$p" == *cap_sys_rawio* ]]
}
ensure_runtime_privileges(){
    # chown of a binary or LUN device clears file capabilities; a uid migration
    # also leaves /dev nodes owned by the old uid.  CMS then fails dsscmd
    # reghl/inq_reg with EPERM and GCC reports "initialize gcc disk lock failed"
    # (the cb device is mode 600).  Repair only our own binaries and our four
    # LUN device nodes, on both nodes; other users' resources are never touched.
    command -v getcap >/dev/null 2>&1 || { log "WARN: getcap not found; skipping capability/device preflight"; return 0; }
    local cms_bin=$CMS_HOME/service/bin/cms perctrl=$DSS_HOME/bin/perctrl
    local uid dev real owner problems=0
    uid=$(id -u)
    node_caps_ok 0 || { log "capabilities missing on node0"; problems=1; }
    node_caps_ok 1 || { log "capabilities missing on node1"; problems=1; }
    for dev in $PR_DEVICES; do
        [[ -e "$dev" ]] || { log "WARN: missing device $dev"; continue; }
        real=$(readlink -f "$dev")
        owner=$(stat -L -c %u "$real" 2>/dev/null)
        [[ "$owner" == "$uid" ]] || { log "node0 device $real owner=$owner (want $uid)"; problems=1; }
        owner=$(ssh1 "stat -L -c %u '$real' 2>/dev/null")
        [[ "$owner" == "$uid" ]] || { log "node1 device $real owner=$owner (want $uid)"; problems=1; }
    done
    if [[ "$problems" == 0 ]]; then
        log "runtime preflight: cms/perctrl capabilities and LUN ownership OK on both nodes"
        return 0
    fi
    [[ -r "$SUDO_PWD_FILE" ]] || fail "capability/device problem detected and $SUDO_PWD_FILE is unreadable; fix setcap/chown manually (see SKILL.md)"
    if ! node_caps_ok 0; then
        log "restoring file capabilities on node0"
        sudo_local setcap CAP_SYS_RAWIO+ep "$cms_bin" || fail "setcap cms failed on node0"
        sudo_local setcap CAP_SYS_ADMIN,CAP_SYS_RAWIO+ep "$perctrl" || fail "setcap perctrl failed on node0"
        node_caps_ok 0 || fail "capabilities still missing on node0"
    fi
    if ! node_caps_ok 1; then
        log "restoring file capabilities on node1"
        sudo_remote "setcap CAP_SYS_RAWIO+ep '$cms_bin'" || fail "setcap cms failed on node1"
        sudo_remote "setcap CAP_SYS_ADMIN,CAP_SYS_RAWIO+ep '$perctrl'" || fail "setcap perctrl failed on node1"
        node_caps_ok 1 || fail "capabilities still missing on node1"
    fi
    for dev in $PR_DEVICES; do
        [[ -e "$dev" ]] || continue
        real=$(readlink -f "$dev")
        if [[ "$(stat -L -c %u "$real" 2>/dev/null)" != "$uid" ]]; then
            log "fixing node0 device owner: $real -> $(id -un):$(id -gn)"
            sudo_local chown "$(id -un):$(id -gn)" "$real" || fail "chown $real failed"
        fi
        if [[ "$(ssh1 "stat -L -c %u '$real' 2>/dev/null")" != "$uid" ]]; then
            log "fixing node1 device owner: $real"
            sudo_remote "chown $(id -un):$(id -gn) '$real'" || fail "remote chown $real failed"
        fi
    done
    log "runtime preflight: capabilities and LUN ownership repaired"
}
build_ub_pool_tool(){
    command -v cc >/dev/null 2>&1 || { log "ERROR: cc not found; cannot build UB pool tool"; return 1; }
    [[ -r "$UB_TOOL_SRC" ]] || { log "ERROR: missing UB pool source $UB_TOOL_SRC"; return 1; }
    # The tool is tiny; always rebuild so it matches the current namespace.
    cc -Wall -Wextra -Werror -I "$OGRAC_REPO/pkg/src/common" "$UB_TOOL_SRC" \
        -lubsm_sdk -lstdc++ -o "$UB_TOOL_LOCAL" >>"$LOG" 2>&1 \
        || { log "ERROR: failed to build UB pool tool"; return 1; }
    ssh1 "cat > '$UB_TOOL_REMOTE'" < "$UB_TOOL_LOCAL" >>"$LOG" 2>&1 \
        || { log "ERROR: failed to copy UB pool tool to node1"; return 1; }
    ssh1 "chmod +x '$UB_TOOL_REMOTE'" >>"$LOG" 2>&1 || return 1
    return 0
}
run_tool(){ # <local|remote> <sg|login> <tool args...>
    local host=$1 gid=$2
    shift 2
    if [[ "$host" == "local" ]]; then
        case "$gid" in
          sg)
            sg ubsmd -c "$UB_TOOL_LOCAL $*"
            ;;
          login)
            # sudo -u <self> gives the login primary gid while initgroups keeps
            # ubsmd as a supplementary group for socket access.
            [[ -r "$SUDO_PWD_FILE" ]] || return 1
            local pw
            pw=$(cat "$SUDO_PWD_FILE")
            printf '%s\n' "$pw" | sudo -S -p '' -u "$(id -un)" "$UB_TOOL_LOCAL" "$@"
            ;;
          *)
            "$UB_TOOL_LOCAL" "$@"
            ;;
        esac
    else
        if [[ "$gid" == "sg" ]]; then
            ssh1 "sg ubsmd -c '$UB_TOOL_REMOTE $*'"
        else
            # A fresh ssh login has the node's login primary gid plus ubsmd.
            ssh1 "$UB_TOOL_REMOTE $*"
        fi
    fi
}
cleanup_ub_pools(){
    # Must be called only after BOTH DB instances are stopped: deallocating a
    # buffer that the peer still maps can break the peer.  Nodes 0 and 1 are
    # cleaned separately because a remote node's buffer cannot be freed here.
    build_ub_pool_tool || return 1
    local n host out
    for n in 0 1; do
        if [[ "$n" == 0 ]]; then host=local; else host=remote; fi
        log "GBP buffers node $n: clean-all (sg ubsmd)"
        out=$(run_tool "$host" sg clean-all "$n" --both-databases-stopped 2>&1)
        log "GBP buffers node $n: $(echo "$out" | tr '\n' ' ' | cut -c1-320)"
        if echo "$out" | grep -q 'all-pools-empty'; then
            continue
        fi
        # Buffers created by a process whose primary gid was the login gid
        # need that gid; login mode keeps ubsmd supplementary.
        log "GBP buffers node $n: clean-all (login primary gid)"
        out=$(run_tool "$host" login clean-all "$n" --both-databases-stopped 2>&1)
        log "GBP buffers node $n: $(echo "$out" | tr '\n' ' ' | cut -c1-320)"
        if echo "$out" | grep -q 'all-pools-empty'; then
            continue
        fi
        # UBS may still hold references for a short time after a SIGKILL.
        log "GBP buffers node $n: retry after 5s (references draining)"
        sleep 5
        out=$(run_tool "$host" sg clean-all "$n" --both-databases-stopped 2>&1)
        log "GBP buffers node $n: $(echo "$out" | tr '\n' ' ' | cut -c1-320)"
        if echo "$out" | grep -q 'all-pools-empty'; then
            continue
        fi
        out=$(run_tool "$host" login clean-all "$n" --both-databases-stopped 2>&1)
        log "GBP buffers node $n: $(echo "$out" | tr '\n' ' ' | cut -c1-320)"
        if ! echo "$out" | grep -q 'all-pools-empty'; then
            log "ERROR: current-user GBP buffers remain on node $n"
            return 1
        fi
    done
    # The per-node clean-all prefix scan can miss an allocation whose desc name
    # arrives without the trailing NUL (observed on node0 after force-killed
    # DBs), while the final all-list still sees it.  Use the exact-prefix
    # release path in both gid modes as a belt-and-braces pass.
    for n in 0 1; do
        if [[ "$n" == 0 ]]; then host=local; else host=remote; fi
        out=$(run_tool "$host" sg "$n" release --both-databases-stopped 2>&1)
        log "GBP buffers node $n: release (sg) $(echo "$out" | tr '\n' ' ' | cut -c1-200)"
        out=$(run_tool "$host" login "$n" release --both-databases-stopped 2>&1)
        log "GBP buffers node $n: release (login) $(echo "$out" | tr '\n' ' ' | cut -c1-200)"
    done
    # Final cluster-wide check: any remaining current-user GBP allocation,
    # regardless of namespace generation or node index, fails the restore.
    out=$(run_tool local sg all-list 2>&1)
    if ! echo "$out" | grep -q 'matched=0'; then
        out=$(run_tool local login all-list 2>&1)
        if ! echo "$out" | grep -q 'matched=0'; then
            log "ERROR: current-user GBP allocations remain after cleanup: $(echo "$out" | tr '\n' ' ' | cut -c1-320)"
            return 1
        fi
    fi
    log "all current-user GBP buffers are gone"
    return 0
}
clear_stale_pr(){
    command -v sg_persist >/dev/null 2>&1 || { log "WARN: sg_persist not found; skip PR clear"; return 0; }
    [[ -r "$SUDO_PWD_FILE" ]] || {
        log "WARN: $SUDO_PWD_FILE not readable; skip PR clear (a stale reservation may hang DSS)"
        return 0
    }
    # Only safe now: every DB/CMS/DSS of this deployment has been stopped.
    local cms_found=0
    ps -eo args= | awk -v p="$ROOT/ograc/cms/service/bin/cms server" 'index($0,p)==1{f=1} END{exit !f}' && cms_found=1
    if [[ -n "$(db_pid0)$(db_pid1)" || "$cms_found" == 1 || -n "$(dss_pids0)$(dss_pids1)" ]]; then
        log "WARN: services still present; skip PR clear"
        return 0
    fi
    local pw dev out key
    pw=$(cat "$SUDO_PWD_FILE")
    for dev in $PR_DEVICES; do
        [[ -e "$dev" ]] || { log "WARN: PR device missing: $dev"; continue; }
        for key in 1 2; do
            printf '%s\n' "$pw" | sudo -S -p '' sg_persist --out --clear --param-rk=$key "$dev" >/dev/null 2>&1 || true
        done
        out=$(printf '%s\n' "$pw" | sudo -S -p '' sg_persist --in --read-reservation "$dev" 2>&1 \
            | grep -aE 'NO reservation|Key=' | head -1)
        # A registrants-only reservation belongs to one initiator port.  The
        # node0 port cannot clear a reservation registered through node1's HBA
        # ("Reservation conflict"); clear it from node1 as well.  Observed with
        # key=0x2 Write Exclusive/registrants-only, where data/redo/archive
        # blocked DSS with "Failed to lock share disk vg" until node1 cleared it.
        if echo "$out" | grep -q 'Key='; then
            log "PR $dev: reservation still held from node0; retrying clear on node1"
            for key in 1 2; do
                printf '%s\n' "$pw" | ssh1 "sudo -S -p '' sg_persist --out --clear --param-rk=$key '$dev'" >/dev/null 2>&1 || true
            done
            out=$(printf '%s\n' "$pw" | sudo -S -p '' sg_persist --in --read-reservation "$dev" 2>&1 \
                | grep -aE 'NO reservation|Key=' | head -1)
        fi
        log "PR $dev: ${out:-unknown}"
    done
}
ensure_restore_dss(){
    # IMPORTANT: use DSS maintenance mode (-M) for the restore copy.  A normal
    # "dss_contrl.sh -start" after a PR clear registers a reservation from a
    # path/port that may not be the one used for file I/O; the array then
    # returns reservation conflicts and the DSS hangs.  -M skips that
    # registration sequence and is the mode required by offline restores.
    local i p
    for p in $(dss_pids0); do kill -9 "$p" 2>/dev/null || true; done
    rm -f "$DSS_HOME/.dss_unix_d_socket"
    nohup env LD_LIBRARY_PATH="$DSS_HOME/lib:$ROOT/ograc/ograc/server/lib:$UB_LIB" \
        "$DSS_HOME/bin/dssserver" -D "$DSS_HOME" -M >>"$ROOT/ograc/log/dss/dss_manual_restore.out" 2>&1 &
    for ((i=0;i<20;i++)); do
        dsscmd_t lsvg >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}
wait_dss_both(){ # [total_seconds] [poll_seconds]
    # CMS restarts/registers DSS while it starts, so a short window can
    # misjudge "DSS unavailable": the 20x1s check failed at 21:52:02 while
    # node0 DSS was back and serving lsvg ~7 seconds later.  Bound the wait by
    # wall clock, not by iteration count (dsscmd timeouts make each iteration
    # up to ~15s long), and log the real per-node error on failure.
    local total=${1:-180} nap=${2:-2} start=$SECONDS e0 e1
    while (( SECONDS - start < total )); do
        if dsscmd_t lsvg >/dev/null 2>&1 && dsscmd1_t lsvg >/dev/null 2>&1; then
            return 0
        fi
        sleep "$nap"
    done
    e0=$(dsscmd_t lsvg 2>&1 | tail -1)
    e1=$(dsscmd1_t lsvg 2>&1 | tail -1)
    log "DSS lsvg failed after ${total}s: node0=[${e0:-no output}] node1=[${e1:-no output}]"
    return 1
}
start_cms_all(){
    : > "$ROOT/logs/ub_fault_cmd_node0.txt"
    # Export the fault-harness command file so the DB processes spawned by the
    # CMS inherit OGRAC_UB_FAULT_CMD (CMS-started ogracd has no "open" argv and
    # is the process that actually serves GBP pages in the tests).
    timeout 180 sg ubsmd -c "source $HOME/.bashrc >/dev/null 2>&1; export OGRAC_UB_FAULT_CMD='$ROOT/logs/ub_fault_cmd_node0.txt'; cd $CMS_ACTION && python3 cms_ctl.py start" >>"$LOG" 2>&1 || true
    # Same primary gid as node0 (ubsmd) so the DB's UB pool is owned by the
    # same gid on both nodes; otherwise the survivor/offline tool cannot delete
    # a crashed node's stale UB allocation (UBS checks the primary gid).
    ssh1 ": > $ROOT/logs/ub_fault_cmd_node1.txt; sg ubsmd -c 'source \$HOME/.bashrc >/dev/null 2>&1; export OGRAC_UB_FAULT_CMD=$ROOT/logs/ub_fault_cmd_node1.txt; cd $CMS_ACTION && timeout 180 python3 cms_ctl.py start'" >>"$LOG" 2>&1 || true
    local i s0 s1
    for ((i=0;i<60;i++)); do
        s0=$(cms_stat -server 0 | awk '$1==0{print $2}')
        s1=$(cms_stat -server 1 | awk '$1==1{print $2}')
        [[ "$s0" == TRUE && "$s1" == TRUE ]] && return 0
        sleep 3
    done
    return 1
}

# ---------------- preflight ----------------
[[ -d "$BACKUP" ]] || fail "backup dir not found: $BACKUP"
[[ -f "$BACKUP/MANIFEST.tsv" ]] || fail "missing MANIFEST.tsv"
[[ -s "$BACKUP/MANIFEST.tsv" ]] || fail "empty MANIFEST.tsv"
[[ -x "$DB_BIN/ogracd" ]] || fail "missing $DB_BIN/ogracd"
[[ -x "$DSS_HOME/bin/dsscmd" ]] || fail "missing dsscmd"
[[ -x "$DSS_HOME/bin/dssserver" ]] || fail "missing dssserver"
log "backup=$BACKUP log=$LOG"
missing=0
while IFS=$'\t' read -r vg name _l _w local_size; do
    f="$BACKUP/${vg#+}/$name"
    if [[ ! -f "$f" ]]; then log "missing file: $f"; missing=$((missing+1)); continue; fi
    sz=$(stat -c%s "$f")
    [[ "$sz" == "$local_size" ]] || { log "size mismatch: $f local=$sz manifest=$local_size"; missing=$((missing+1)); }
done < "$BACKUP/MANIFEST.tsv"
[[ "$missing" -eq 0 ]] || fail "$missing manifest/file-size problems"
if [[ "$VERIFY_SHA" == 1 ]]; then
    log "verifying SHA256SUMS (use --no-sha to skip)"
    ( cd "$BACKUP" && sha256sum -c SHA256SUMS ) >>"$LOG" 2>&1 || fail "SHA256 verification failed"
fi
if [[ "$ASSUME_YES" != 1 ]]; then
    if [[ ! -t 0 ]]; then fail "stdin is not a TTY; pass --yes to confirm the destructive restore"; fi
    read -r -p "Restore $BACKUP over the current DB? [y/N] " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || { log "aborted by user"; exit 1; }
fi

ensure_runtime_privileges

# ---------------- stop DB/CMS/DSS ----------------
if [[ -n "$(db_pid0)" || -n "$(db_pid1)" ]]; then
    # A client left behind by an earlier interrupted restore keeps a DB session
    # and can itself make "shutdown immediate" fail; clear it first.
    if [[ -n "$(stop_client_pids)" ]]; then
        log "cleaning leftover shutdown clients: [$(echo $(stop_client_pids) | tr '\n' ' ')]"
        kill_stop_clients
        sleep 1
    fi
    log "stopping DB cleanly (immediate, bounded to ${DB_STOP_TIMEOUT}s)"
    # shutdowndb.sh invokes ogsql from PATH; without this it fails with
    # "ogsql: command not found" and leaves the DB running.  -T is the tool's
    # internal wait; the external timeout bounds even a shutdown that ignores
    # -T (a GBP-quarantined DB loops in reform and never answers).
    ( export PATH="$DB_BIN:$PATH"
      export LD_LIBRARY_PATH="$ROOT/ograc/ograc/server/lib:$ROOT/ograc/ograc/server/add-ons:$UB_LIB"
      timeout --kill-after=10 "$DB_STOP_TIMEOUT" \
        "$DB_BIN/shutdowndb.sh" -h "$NODE0" -p "$DB_PORT" -w -m immediate -D "$DATA" -T "$DB_STOP_TIMEOUT" ) >>"$LOG" 2>&1 \
        || log "WARN: shutdowndb failed or timed out after ${DB_STOP_TIMEOUT}s"
    if wait_no_db 60; then
        log "DB stopped cleanly"
    else
        log "DB is still running; forcing the environment down"
        kill_stop_clients
        # CMS must stop first or it restarts ogracd right after the kill.
        stop_cms_all || log "WARN: CMS did not stop cleanly; continuing with force kill"
        force_kill_db || fail "could not force-stop the DB processes"
        wait_no_db 120 || fail "DB processes still present after SIGKILL"
        log "DB force-stopped"
    fi
fi
log "stopping CMS"
stop_cms_all || log "WARN: CMS processes remain (they must not run during restore)"
log "stopping DSS"
stop_dss_all

# A DSS killed hard (or one from before the uid migration) leaves SysV 0x32
# segments behind; the next DSS then fails to attach with EACCES.  Clean only
# our current-user, unattached segments.
log "cleaning stale SysV 0x32 shared-memory segments (current user, nattch=0)"
cleanup_stale_sysv_shm

# Both DB instances are stopped now.  Clean every GBP data-buffer allocation
# owned by this OS user on both nodes, across all namespace generations
# (current and legacy namespace generations).  A leftover allocation blocks
# the next DB start with
# "old allocation remains" / IpcCallCreateRegion 502.  Other users' objects are
# never matched (the tool filters on the current user's "<user>_" prefix).
log "cleaning all current-user GBP buffers on both nodes (both DBs stopped)"
cleanup_ub_pools || fail "current-user GBP buffer cleanup failed; a DB restart would fail with 'old allocation remains'"

# ---------------- restore files ----------------
log "clearing stale SCSI PR on our four LUNs (all services stopped)"
clear_stale_pr
log "starting restore DSS on node0"
ensure_restore_dss || fail "node0 DSS cannot serve dsscmd"
log "restoring files with dsscmd cp (data first, ctrl last, no ctrl padding)"
bash "$SKILL_DIR/scripts/dss_cold_restore.sh" "$BACKUP" >>"$LOG" 2>&1 \
    || fail "dss_cold_restore.sh failed; see $LOG"

# ---------------- restart stack ----------------
log "restarting DSS on both nodes"
stop_dss_all
start_dss0
start_dss1
# A node that was not registered with the SCSI PR key yet cannot serve dsscmd
# (dmesg: reservation conflict).  CMS registers the initiators, so do not treat
# a pre-CMS lsvg failure as fatal; retry after CMS is up.
if ! wait_dss_both; then
    log "WARN: DSS not serving before CMS (PR initiator not registered yet); starting CMS first"
fi

log "starting CMS"
start_cms_all || fail "CMS not SRV_READY on both nodes; see $LOG"
wait_dss_both || fail "DSS unavailable after restore (node0/node1 lsvg failed)"

log "starting node0, then node1 (node0 must be ONLINE/JOINED first)"
bash "$SKILL_DIR/scripts/start_db_pair.sh" >>"$LOG" 2>&1 \
    || fail "start_db_pair.sh failed; see $LOG"
wait_joined 0 300 || fail "node0 not ONLINE/JOINED"
wait_joined 1 300 || fail "node1 not ONLINE/JOINED"

# ---------------- verify ----------------
if [[ "$VERIFY" == 1 ]]; then
    # JOINED only means the RC master reform finished; the sys catalog may take
    # several seconds more to become visible.  Verifying immediately after
    # JOINED produced spurious "table does not exist" (OG-00843) failures.
    log "waiting 20s for catalog settlement before TPCC verification"
    sleep 20
    if [[ -x "$TPCC_SKILL/scripts/verify_tpcc.sh" ]]; then
        ok=0
        for attempt in 1 2 3; do
            log "verifying TPCC ($WAREHOUSES warehouses), attempt $attempt"
            if bash "$TPCC_SKILL/scripts/verify_tpcc.sh" --warehouses "$WAREHOUSES" >>"$LOG" 2>&1; then
                ok=1
                break
            fi
            log "TPCC verification attempt $attempt failed; retrying in 15s"
            sleep 15
        done
        [[ "$ok" == 1 ]] || fail "TPCC verification failed after 3 attempts; see $LOG"
    else
        log "WARN: $TPCC_SKILL/scripts/verify_tpcc.sh not found; skipping row-count check"
    fi
fi

log "restore completed successfully"
cms_stat -res db | tee -a "$LOG"
log "node0 pid=$(db_pid0) node1 pid=$(db_pid1)"
