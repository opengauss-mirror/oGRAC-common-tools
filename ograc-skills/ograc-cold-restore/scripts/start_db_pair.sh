#!/bin/bash
# Start the two DB instances in the order the RC code supports reliably:
#   1. start node0 and wait until CMS reports node0 ONLINE (it becomes the master)
#   2. start node1; it joins the running cluster (full_restart=false path)
#   3. wait until both are ONLINE
#
# The old simultaneous start races the CMS full-restart election and can fail
# with "Multiple nodes cannot be added to the CMS at the same time without a
# master node."  A running cluster accepts a later joiner.
#
# ogracd may appear as "ogracd open -D <data>" (manual) or "ogracd -D <data>"
# (CMS resource script), so process checks match both forms.
set -u
ROOT=${ROOT:-$HOME/ograc_cluster}
NODE1=${NODE1:?set NODE1 to the node1 address}
SSH_USER=${SSH_USER:-$USER}
DATA=$ROOT/dbdata/local/ograc/tmp/data
BIN=$ROOT/ograc/ograc/server/bin/ogracd
CMS_HOME=$ROOT/ograc/cms
CMS_ACTION=$ROOT/ograc/action/cms
UB_LIB=/usr/local/ubs_mem/lib
LOG=$ROOT/logs/start-db-pair-$(date +%Y%m%d-%H%M%S).log
log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
cms_stat(){ ( cd "$CMS_ACTION" && CMS_HOME="$CMS_HOME" LD_LIBRARY_PATH="$CMS_HOME/service/lib:$CMS_HOME/service/add-ons" timeout 8 "$CMS_HOME/service/bin/cms" stat "$@" 2>/dev/null ); }
db_state(){ cms_stat -res db | awk '$2=="db"{printf "%s:%s ",$1,$3}'; }
db_pid0(){ ps -eo pid=,args= | awk -v d="$DATA" '$0 ~ /(^|[\/ ])ogracd( |$)/ && index($0,d) {print $1; exit}'; }
db_pid1(){ ssh -o BatchMode=yes "$SSH_USER@$NODE1" "ps -eo pid=,args= | awk -v d='$DATA' '\$0 ~ /(^|[\\/ ])ogracd( |\$)/ && index(\$0,d) {print \$1; exit}'"; }
start_node0(){
    : > "$ROOT/logs/ub_fault_cmd_node0.txt"
    sg ubsmd -c "ulimit -n 524288; source '$HOME/.bashrc' >/dev/null 2>&1 || true; export LD_LIBRARY_PATH='$UB_LIB':\$LD_LIBRARY_PATH; export OGRAC_UB_FAULT_CMD='$ROOT/logs/ub_fault_cmd_node0.txt'; nohup '$BIN' open -D '$DATA' >> '$ROOT/ograc/log/ograc/ogracstatus.log' 2>&1 & echo node0_pid=\$!"
}
start_node1(){
    # Use sg ubsmd on node1 too: UBS shared-memory ownership is checked by the
    # process's primary gid.  Starting node0 under ubsmd but node1 under the
    # login gid leaves node1's pool undeletable by the survivor/offline tool.
    # nofile: a node reinstalled from scratch may have soft nofile 1024; the
    # first TPCC redo flush then aborts with EMFILE ("failed to write +vg2/redoXX").
    ssh -o BatchMode=yes "$SSH_USER@$NODE1" ": > $ROOT/logs/ub_fault_cmd_node1.txt; sg ubsmd -c 'ulimit -n 524288; source \$HOME/.bashrc >/dev/null 2>&1 || true; export LD_LIBRARY_PATH=$UB_LIB:\$LD_LIBRARY_PATH; export OGRAC_UB_FAULT_CMD=$ROOT/logs/ub_fault_cmd_node1.txt; nohup $BIN open -D $DATA >> $ROOT/ograc/log/ograc/ogracstatus.log 2>&1 & echo node1_pid=\$!'"
}
node_joined(){ # node_joined <node>: ONLINE and RC work_stat=JOINED(1)
    cms_stat -res db | awk -v n="$1" '$2=="db" && $1==n && $3=="ONLINE" && $6==1 {f=1} END{exit !f}'
}
both_joined(){ node_joined 0 && node_joined 1; }
wait_online(){ # wait_online <node> <seconds>
    local node=$1 timeout=$2 i
    for ((i=0; i<timeout; i+=2)); do
        node_joined "$node" && return 0
        sleep 2
    done
    return 1
}

# CMS may auto-start node1 while we are about to start node0.  Starting both
# together races the election and fails with "Multiple nodes cannot be added to
# the CMS at the same time without a master node".  If node1 is already
# starting, let it become the master first; node0 then joins a running cluster.
if [[ -n "$(db_pid1)" && -z "$(db_pid0)" ]]; then
    log "node1 already starting/running (pid=$(db_pid1)); waiting for it to become master"
    if wait_online 1 180; then
        log "node1 ONLINE/JOINED (master): [$(db_state)]"
    else
        log "ERROR: node1 did not become ONLINE/JOINED: [$(db_state)]"
        exit 1
    fi
fi

if [[ -z "$(db_pid0)" ]]; then log "start node0"; start_node0; else log "node0 already running pid=$(db_pid0)"; fi
if wait_online 0 180; then log "node0 ONLINE/JOINED: [$(db_state)]"; else log "ERROR: node0 did not become ONLINE/JOINED: [$(db_state)]"; exit 1; fi

if [[ -z "$(db_pid1)" ]]; then log "start node1"; start_node1; else log "node1 already running pid=$(db_pid1)"; fi
for i in $(seq 1 90); do
    st=$(db_state)
    log "db=[$st]"
    if both_joined; then log "both ONLINE/JOINED"; exit 0; fi
    sleep 2
done
log "timeout waiting both ONLINE/JOINED"
exit 1
