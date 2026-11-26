#!/bin/bash
# Bounded, read-only evidence collector for a failed long-stability round.
# Creates $BASE/failures/<timestamp>-round-N with artifacts, gdb backtraces
# (only if the survivor is still alive), log tails, and a REPORT.md skeleton.
# It never stops/starts/modifies the cluster and never changes product code.
set -u

ROOT=${ROOT:-$HOME/ograc_cluster}
NODE1=${NODE1:?set NODE1 to the node1 address}
SSH_USER=${SSH_USER:-$USER}
RLOG=$ROOT/ograc/log/ograc/run/ogracd.rlog
DSS_LOG=$ROOT/ograc/log/dss/run/dssinstance.rlog
CMS_LOG=$ROOT/ograc/log/cms/run/cms_srv.rlog
CMS_HOME=$ROOT/ograc/cms
CMS_BIN=$CMS_HOME/service/bin/cms
CMS_ACTION=$ROOT/ograc/action/cms

OUT=${1:-}
KIND=${2:-unknown}
ROUND_START=${3:-}
TARGET=${4:-0}
if [[ -z "$OUT" ]]; then
    echo "usage: $0 <round_dir> [kind] [round_start] [target]" >&2
    exit 2
fi
[[ "$TARGET" == 0 || "$TARGET" == 1 ]] || TARGET=0
SURV=$((1 - TARGET))

BASE=$(dirname "$OUT")
TS=$(date +%Y%m%d-%H%M%S)
FAIL=$BASE/failures/$TS-$(basename "$OUT")
EV=$FAIL/evidence
mkdir -p "$EV"
SUDO_PWD_FILE=${SUDO_PWD_FILE:-$HOME/.spw}
PW=$(cat "$SUDO_PWD_FILE" 2>/dev/null || true)

log() { echo "[$(date '+%F %T')] $*"; }

# ---- round artifacts ----
for f in controller.log controller.out check.log check.out summary.txt markers.log restore.out monitor.log collect.out; do
    cp -f "$OUT/$f" "$EV/" 2>/dev/null || true
done

# ---- CMS db state ----
( cd "$CMS_ACTION" 2>/dev/null && \
  CMS_HOME="$CMS_HOME" \
  LD_LIBRARY_PATH="$CMS_HOME/service/lib:$CMS_HOME/service/add-ons" \
  timeout 10 "$CMS_BIN" stat -res db 2>&1 ) > "$EV/cms-db-stat.txt" 2>&1 || true

# ---- survivor process state ----
surv_pid=""
if (( SURV == 0 )); then
    surv_pid=$(ps -eo pid=,args= | awk -v d="$ROOT" '/ogracd/ && index($0, d) {print $1; exit}')
else
    surv_pid=$(ssh -o BatchMode=yes "$SSH_USER@$NODE1" \
        "ps -eo pid=,args= | awk -v d='$ROOT' '/ogracd/ && index(\$0, d) {print \$1; exit}'" 2>/dev/null)
fi
{
    echo "kind=$KIND round_start=$ROUND_START target=$TARGET survivor=$SURV"
    echo "collected_at=$(date '+%F %T')"
    echo "survivor_pid=${surv_pid:-none}"
    if [[ -n "$surv_pid" ]]; then
        if (( SURV == 0 )); then
            ps -o pid,lstart,stat,args -p "$surv_pid" 2>&1
            grep -E 'Max open files|Max processes' "/proc/$surv_pid/limits" 2>&1
        else
            ssh -o BatchMode=yes "$SSH_USER@$NODE1" \
                "ps -o pid,lstart,stat,args -p '$surv_pid'; grep -E 'Max open files|Max processes' /proc/$surv_pid/limits" 2>&1
        fi
    fi
} > "$EV/survivor-state.txt" 2>&1 || true

# ---- bounded log tails ----
rlog_tail() {
    local node=$1 dest=$2
    if (( node == 0 )); then
        tail -c 5000000 "$RLOG" > "$dest" 2>/dev/null || true
    else
        ssh -o BatchMode=yes "$SSH_USER@$NODE1" "tail -c 5000000 '$RLOG'" > "$dest" 2>/dev/null || true
    fi
}
rlog_tail "$SURV" "$EV/survivor-rlog-tail.txt"
rlog_tail "$TARGET" "$EV/target-rlog-tail.txt"
tail -c 2000000 "$DSS_LOG" > "$EV/dss-rlog-tail.txt" 2>/dev/null || true
tail -c 2000000 "$CMS_LOG" > "$EV/cms-rlog-tail.txt" 2>/dev/null || true

# ---- gdb (read-only), only if the survivor is alive and bounded ----
if [[ -n "$surv_pid" ]]; then
    if (( SURV == 0 )); then
        printf '%s\n' "$PW" | timeout 200 sudo -S -p '' gdb -q -batch -p "$surv_pid" \
            -ex 'set pagination off' -ex 'thread apply all bt 12' > "$EV/gdb-bt.txt" 2>&1 || true
        printf '%s\n' "$PW" | timeout 120 sudo -S -p '' gdb -q -batch -p "$surv_pid" \
            -ex 'set pagination off' -ex 'p g_gbp_rcy.phase' -ex 'p g_gbp_rcy.count' \
            -ex 'p g_gbp_rcy.abort_node' -ex 'p g_gbp_rcy.failed' > "$EV/gdb-rcy.txt" 2>&1 || true
    else
        printf '%s\n' "$PW" | timeout 240 ssh -o BatchMode=yes "$SSH_USER@$NODE1" \
            "sudo -S -p '' gdb -q -batch -p '$surv_pid' -ex 'set pagination off' -ex 'thread apply all bt 12'" \
            > "$EV/gdb-bt.txt" 2>&1 || true
        printf '%s\n' "$PW" | timeout 160 ssh -o BatchMode=yes "$SSH_USER@$NODE1" \
            "sudo -S -p '' gdb -q -batch -p '$surv_pid' -ex 'set pagination off' -ex 'p g_gbp_rcy.phase' -ex 'p g_gbp_rcy.count' -ex 'p g_gbp_rcy.abort_node' -ex 'p g_gbp_rcy.failed'" \
            > "$EV/gdb-rcy.txt" 2>&1 || true
    fi
fi

# ---- key lines for quick triage ----
{
    for f in "$EV/survivor-rlog-tail.txt" "$EV/target-rlog-tail.txt"; do
        [[ -f "$f" ]] || continue
        echo "===== $(basename "$f") ====="
        grep -aE 'ABORT|panic|failed to|ERROR|GBP-RCY|GBP-LOCK|DLS|reset to idle|Ordinary user login' "$f" | tail -120
    done
} > "$EV/key-lines.txt" 2>&1 || true

# ---- evidence index ----
{
    echo "# 证据清单：$(basename "$FAIL")"
    echo
    echo "- 采集时间：$(date '+%F %T')"
    echo "- 失败类型：$KIND"
    echo "- round 开始：$ROUND_START"
    echo "- target=$TARGET survivor=$SURV"
    echo "- survivor pid：${surv_pid:-none}"
    echo
    echo "| 文件 | 大小 |"
    echo "|---|---|"
    for f in "$EV"/*; do
        [[ -f "$f" ]] && echo "| $(basename "$f") | $(stat -c%s "$f" 2>/dev/null) |"
    done
} > "$FAIL/EVIDENCE.md"

# ---- report skeleton (analysis is filled in by the agent; never auto-fix) ----
{
    echo "# 失败记录：$(basename "$OUT") ($KIND)"
    echo
    echo "- 采集时间：$(date '+%F %T')"
    echo "- round 开始：$ROUND_START"
    echo "- target/survivor：$TARGET / $SURV"
    echo "- 证据目录：\`evidence/\`"
    echo
    echo "## 现象"
    echo
    echo "（待分析：从 controller.log / check.log / summary.txt 摘录）"
    echo
    echo "## 时间线"
    echo
    echo "（待分析：kill 时间、recovery reset、失败点）"
    echo
    echo "## 关键证据"
    echo
    echo "- gdb-bt.txt / gdb-rcy.txt（survivor 仍存活时）"
    echo "- survivor-rlog-tail.txt / target-rlog-tail.txt"
    echo "- markers.log / key-lines.txt"
    echo
    echo "## 根因分析"
    echo
    echo "（待分析；只记录，不修复）"
    echo
    echo "## 结论 / 后续"
    echo
    echo "（待分析；禁止在本长稳流程中修改代码或部署修复）"
} > "$FAIL/REPORT.md"

# ---- index ----
INDEX=$BASE/failures/index.md
[[ -f "$INDEX" ]] || { echo "# 长稳失败记录索引" > "$INDEX"; echo >> "$INDEX"; }
echo "- $(date '+%F %T') $(basename "$FAIL") kind=$KIND target=$TARGET survivor=$SURV dir=$FAIL" >> "$INDEX"

log "evidence collected: $FAIL"
echo "$FAIL"
