#!/bin/bash
# Verify the two-node oGRAC cluster: CMS status, cross-node SQL, redo layout.
# Safe to run against a live cluster; creates and drops a temporary table.
set -uo pipefail

ROOT=${ROOT:-$HOME/ograc_cluster}
NODE1=${NODE1:?set NODE1 to the node1 address}
SSH_USER=${SSH_USER:-$USER}
DB_PORT=${DB_PORT:-29300}
REDO_FILES=${REDO_FILES:-10}
REDO_SIZE=${REDO_SIZE:-10737418240.00000}
CHECK_VALUE=${CHECK_VALUE:-4242}

DATA_DIR="$ROOT/dbdata/local/ograc/tmp/data"
CMS_HOME="$ROOT/ograc/cms"
CMS_ACTION="$ROOT/ograc/action/cms"
DSS_HOME="$ROOT/ograc/dss"
DB_BIN="$ROOT/ograc/ograc/server/bin"
SERVER_LIB="$ROOT/ograc/ograc/server/lib:$ROOT/ograc/ograc/server/add-ons"
UB_LIB=/usr/local/ubs_mem/lib
TABLE="ograc_check_$(date +%s)"
fails=0

pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; fails=$((fails + 1)); }
section() { printf '\n== %s ==\n' "$*"; }

ssh1() { ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_USER@$NODE1" "$@"; }

cms_stat() {
    ( cd "$CMS_ACTION" && \
      CMS_HOME="$CMS_HOME" \
      LD_LIBRARY_PATH="$CMS_HOME/service/lib:$CMS_HOME/service/add-ons" \
      "$CMS_HOME/service/bin/cms" stat "$@" 2>/dev/null )
}

sql0() {
    printf 'y\n' | env LD_LIBRARY_PATH="$SERVER_LIB:$UB_LIB" \
        "$DB_BIN/ogsql" "/ AS SYSDBA 127.0.0.1:$DB_PORT" -D "$DATA_DIR" -c "$1"
}

sql1() {
    ssh1 "printf 'y\\n' | env LD_LIBRARY_PATH='$SERVER_LIB:$UB_LIB' '$DB_BIN/ogsql' '/ AS SYSDBA 127.0.0.1:$DB_PORT' -D '$DATA_DIR' -c \"$1\""
}

section "CMS 状态"
db_out=$(cms_stat -res db || true)
if [[ -z "$db_out" ]]; then
    fail "cms stat -res db 无输出（CMS 未运行或 cwd/CMS_HOME 不对）"
else
    printf '%s\n' "$db_out"
    online=$(printf '%s\n' "$db_out" | awk '$2=="db" && $3=="ONLINE" {c++} END {print c+0}')
    [[ "$online" -eq 2 ]] && pass "两节点 db ONLINE" || fail "db ONLINE 节点数=$online（期望 2）"
fi
for n in 0 1; do
    ready=$(cms_stat -server "$n" | awk -v n="$n" '$1==n {print $2}' | head -1)
    [[ "$ready" == "TRUE" ]] && pass "CMS node$n SRV_READY=TRUE" || fail "CMS node$n SRV_READY=${ready:-empty}"
done

section "跨节点 SQL"
create_out=$(sql0 "create table $TABLE(id int); insert into $TABLE values($CHECK_VALUE);" 2>&1)
create_rc=$?
if [[ $create_rc -eq 0 && "$create_out" == *"Succeed."* ]]; then
    pass "node0 建表/插入成功（$TABLE）"
    trap 'sql0 "drop table $TABLE;" >/dev/null 2>&1 || true' EXIT
else
    fail "node0 建表/插入失败 rc=$create_rc"
    printf '%s\n' "$create_out" | tail -5
fi

if [[ $create_rc -eq 0 ]]; then
    select_out=$(sql1 "select * from $TABLE;" 2>&1)
    select_rc=$?
    if [[ $select_rc -eq 0 && "$select_out" == *"$CHECK_VALUE"* ]]; then
        pass "node1 跨节点查询返回 $CHECK_VALUE"
    else
        fail "node1 跨节点查询失败 rc=$select_rc"
        printf '%s\n' "$select_out" | tail -8
    fi

    drop_out=$(sql0 "drop table $TABLE;" 2>&1)
    drop_rc=$?
    if [[ $drop_rc -eq 0 && "$drop_out" == *"Succeed."* ]]; then
        pass "node0 删除测试表成功"
        trap - EXIT
    else
        fail "node0 删除测试表失败 rc=$drop_rc"
        printf '%s\n' "$drop_out" | tail -5
    fi
fi

section "redo 布局"
dss_out=$(DSS_HOME="$DSS_HOME" LD_LIBRARY_PATH="$DSS_HOME/lib:$UB_LIB" \
    "$DSS_HOME/bin/dsscmd" ls -p +vg2 2>&1)
if [[ -z "$dss_out" ]]; then
    fail "dsscmd ls -p +vg2 无输出（DSS 未运行？）"
else
    redo_count=$(printf '%s\n' "$dss_out" | awk '$6 ~ /^redo/ {c++} END {print c+0}')
    redo_sizes=$(printf '%s\n' "$dss_out" | awk '$6 ~ /^redo/ {print $4}' | sort -u | tr '\n' ' ')
    [[ "$redo_count" -eq "$REDO_FILES" ]] && pass "redo 文件数=$REDO_FILES" || fail "redo 文件数=$redo_count（期望 $REDO_FILES）"
    [[ "$redo_sizes" == "$REDO_SIZE " ]] && pass "每个 redo 大小符合预期" || fail "redo 大小=$redo_sizes（期望 $REDO_SIZE）"
fi

section "汇总"
if [[ $fails -eq 0 ]]; then
    echo "集群验证通过"
    exit 0
fi
echo "集群验证失败项: $fails"
exit "$fails"
