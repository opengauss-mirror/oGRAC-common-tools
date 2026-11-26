#!/bin/bash
# Start the two-node oGRAC cluster in the order that works in this environment:
# DSS (both) -> CMS (both, wait SRV_READY) -> DB node0 -> DB node1 -> wait ONLINE.
#
# Usage:
#   bash start_cluster.sh [--with-om] [--allow-running]
# Optional env:
#   ROOT, NODE0, NODE1, SSH_USER, SUDO_PWD (only for --with-om)
set -euo pipefail

ROOT=${ROOT:-$HOME/ograc_cluster}
NODE0=${NODE0:?set NODE0 to the node0 address}
NODE1=${NODE1:?set NODE1 to the node1 address}
SSH_USER=${SSH_USER:-$USER}
WITH_OM=0
ALLOW_RUNNING=0
for arg in "$@"; do
    case "$arg" in
        --with-om) WITH_OM=1 ;;
        --allow-running) ALLOW_RUNNING=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

DATA_DIR="$ROOT/dbdata/local/ograc/tmp/data"
CMS_HOME="$ROOT/ograc/cms"
DSS_HOME="$ROOT/ograc/dss"
DB_BIN="$ROOT/ograc/ograc/server/bin"
CMS_ACTION="$ROOT/ograc/action/cms"
UB_LIB=/usr/local/ubs_mem/lib
STATUS_LOG="$ROOT/ograc/log/ograc/ogracstatus.log"
LOG="$ROOT/logs/start-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$ROOT/logs"
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

ssh1() { ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_USER@$NODE1" "$@"; }

our_procs() {
    ps -eo pid=,comm=,args= | awk -v r="$ROOT" \
        '($2=="ogracd" || $2=="cms" || $2=="dssserver") && index($0, r) {print}'
}
if [[ $ALLOW_RUNNING -eq 0 && -n "$(our_procs)" ]]; then
    echo "some processes of this deployment are already running; run stop_cluster.sh first or pass --allow-running" >&2
    printf '%s\n' "$(our_procs)" >&2
    exit 1
fi

wait_proc() { # wait_proc <pattern> <seconds>
    local pattern=$1 timeout=$2 i
    for ((i = 0; i < timeout; i += 3)); do
        pgrep -f "$pattern" >/dev/null 2>&1 && return 0
        sleep 3
    done
    return 1
}

cms_stat() {
    ( cd "$CMS_ACTION" && \
      CMS_HOME="$CMS_HOME" \
      LD_LIBRARY_PATH="$CMS_HOME/service/lib:$CMS_HOME/service/add-ons" \
      "$CMS_HOME/service/bin/cms" stat "$@" 2>/dev/null )
}

cms_server_ready() { # cms_server_ready <0|1>
    cms_stat -server "$1" | awk -v n="$1" '$1==n {print $2}' | head -1
}

start_dss() { # start_dss <0|1>
    local node=$1
    if [[ "$node" == "0" ]]; then
        ( export DSS_HOME="$DSS_HOME"
          export LD_LIBRARY_PATH="$DSS_HOME/lib:$ROOT/ograc/ograc/server/lib:$UB_LIB"
          export PATH="$DSS_HOME/bin:$PATH"
          timeout 120 bash "$DSS_HOME/dss_contrl.sh" -start 0 )
    else
        ssh1 "export DSS_HOME='$DSS_HOME'; export LD_LIBRARY_PATH='$DSS_HOME/lib:$ROOT/ograc/ograc/server/lib:$UB_LIB'; export PATH=\"$DSS_HOME/bin:\$PATH\"; timeout 120 bash '$DSS_HOME/dss_contrl.sh' -start 1"
    fi
}

start_cms() { # start_cms <0|1>
    local node=$1
    if [[ "$node" == "0" ]]; then
        ( cd "$CMS_ACTION" && python3 cms_ctl.py start )
    else
        ssh1 "cd '$CMS_ACTION' && python3 cms_ctl.py start"
    fi
}

start_db0() {
    sg ubsmd -c "source '$HOME/.bashrc' >/dev/null 2>&1 || true; export LD_LIBRARY_PATH='$UB_LIB':\$LD_LIBRARY_PATH; nohup '$DB_BIN/ogracd' open -D '$DATA_DIR' >> '$STATUS_LOG' 2>&1 & echo db0_pid=\$!"
}

start_db1() {
    ssh1 "source \$HOME/.bashrc >/dev/null 2>&1 || true; export LD_LIBRARY_PATH='$UB_LIB':\$LD_LIBRARY_PATH; nohup '$DB_BIN/ogracd' open -D '$DATA_DIR' >> '$STATUS_LOG' 2>&1 & echo db1_pid=\$!"
}

wait_cms_ready() {
    local timeout=${CMS_WAIT:-180} i s0 s1
    log "waiting for CMS SRV_READY on both nodes (timeout ${timeout}s)"
    for ((i = 0; i < timeout; i += 3)); do
        s0=$(cms_server_ready 0 || true)
        s1=$(cms_server_ready 1 || true)
        if [[ "$s0" == "TRUE" && "$s1" == "TRUE" ]]; then
            log "CMS ready: node0=TRUE node1=TRUE"
            return 0
        fi
        sleep 3
    done
    log "ERROR: CMS not ready (node0=${s0:-?}, node1=${s1:-?})"
    return 1
}

wait_db_online() {
    local timeout=${DB_WAIT:-300} i n
    log "waiting for cms stat -res db: both ONLINE/JOINED (timeout ${timeout}s)"
    for ((i = 0; i < timeout; i += 5)); do
        n=$(cms_stat -res db 2>/dev/null | awk '$2=="db" && $3=="ONLINE" && $6==1 {c++} END {print c+0}')
        if [[ "$n" -eq 2 ]]; then
            log "DB online/joined on both nodes"
            return 0
        fi
        sleep 5
    done
    log "ERROR: DB not ONLINE/JOINED on both nodes"
    return 1
}

wait_db_node_online() { # wait_db_node_online <0|1> [timeout]
    local node=$1 timeout=${2:-${DB_WAIT:-300}} i st
    log "waiting for node${node} DB ONLINE/JOINED (timeout ${timeout}s)"
    for ((i = 0; i < timeout; i += 3)); do
        st=$(cms_stat -res db 2>/dev/null | awk -v n="$node" '$2=="db" && $1==n && $3=="ONLINE" && $6==1 {print "JOINED"}' | head -1)
        if [[ "$st" == "JOINED" ]]; then
            log "node${node} DB ONLINE/JOINED"
            return 0
        fi
        sleep 3
    done
    log "ERROR: node${node} DB not ONLINE/JOINED"
    return 1
}

start_om() {
    : "${SUDO_PWD:?set SUDO_PWD for --with-om}"
    for module in og_om ograc_exporter; do
        log "starting $module on node0"
        ( cd "$ROOT/ograc/action/$module" && printf '%s\n' "$SUDO_PWD" | sudo -S -p '' sh appctl.sh start ) || log "WARN: $module node0 start failed"
        log "starting $module on node1"
        printf '%s\n' "$SUDO_PWD" | ssh1 "cd '$ROOT/ograc/action/$module' && sudo -S -p '' sh appctl.sh start" || log "WARN: $module node1 start failed"
    done
}

log "=== start DSS ==="
start_dss 0
start_dss 1
wait_proc "$DSS_HOME/bin/dssserver" 90 && log "DSS processes present on node0" || { log "ERROR: DSS not running on node0"; exit 1; }
ssh1 "pgrep -f '$DSS_HOME/bin/dssserver' >/dev/null" && log "DSS process present on node1" || { log "ERROR: DSS not running on node1"; exit 1; }

log "=== start CMS ==="
start_cms 0
start_cms 1
sleep 5
wait_proc "$CMS_HOME/service/bin/cms server" 60 && log "CMS process present on node0" || log "WARN: CMS process not seen on node0 yet"
wait_cms_ready

log "=== start DB node0 ==="
start_db0
wait_proc "$DB_BIN/ogracd" 120 && log "ogracd present on node0" || { log "ERROR: ogracd did not start on node0"; exit 1; }
# Let node0 finish its full-restart election/reform before node1 registers.
# A running cluster accepts node1 through the full_restart=false join path;
# starting both simultaneously races the CMS election.
wait_db_node_online 0 || exit 1

log "=== start DB node1 ==="
start_db1
sleep 5
ssh1 "pgrep -f '$DB_BIN/ogracd' >/dev/null" && log "ogracd present on node1" || log "WARN: ogracd not seen on node1 yet"

wait_db_online

if [[ $WITH_OM -eq 1 ]]; then
    log "=== start og_om / ograc_exporter ==="
    start_om
fi

log "=== final status ==="
cms_stat -res db | tee -a "$LOG"
log "start completed"
