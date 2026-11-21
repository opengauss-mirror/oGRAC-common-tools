#!/bin/bash
# Prepare TPC-C data on the two-node oGRAC cluster (default: 100 warehouses).
#
# Password handling:
#   - TPCC_PWD environment variable, or
#   - the password= line of an existing BenchmarkSQL props file (--props-source,
#     or the newest props_*load*.ograc / props_tpcc_*.ograc under $BENCH/run).
# The password is never printed. The generated props file is mode 600.
set -euo pipefail
umask 077

ROOT=${ROOT:-$HOME/ograc_cluster}
BENCH=${BENCH:-$HOME/benchmarksql}
DB_PORT=${DB_PORT:-29300}
if [[ -z "${CONN:-}" ]]; then
    : "${NODE0:?set NODE0 or CONN to the database connection}"
    CONN="jdbc:oGRAC://$NODE0:$DB_PORT"
fi
DB_USER=${DB_USER:-TPCC}
WAREHOUSES=${WAREHOUSES:-100}
WORKERS=${WORKERS:-50}
RECREATE=0
VERIFY=1
DRY_RUN=0
PROPS_SOURCE=${PROPS_SOURCE:-}

usage() {
    cat >&2 <<EOF
usage: load_tpcc.sh [options]
  --warehouses N     warehouse count (default 100)
  --workers N        loadWorkers (default 50)
  --conn URL         JDBC URL (default $CONN)
  --user NAME        database user/schema (default TPCC)
  --bench DIR        BenchmarkSQL directory (default $BENCH)
  --props-source F   reuse password= from this props file
  --recreate         drop existing bmsql_* tables before loading
  --no-verify        skip row-count verification
  --dry-run          print plan only
  -h, --help         this help
Environment: TPCC_PWD (required unless --props-source/auto-detected props has password)
EOF
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --warehouses) WAREHOUSES=${2:-}; shift 2 ;;
        --workers)    WORKERS=${2:-}; shift 2 ;;
        --conn)       CONN=${2:-}; shift 2 ;;
        --user)       DB_USER=${2:-}; shift 2 ;;
        --bench)      BENCH=${2:-}; shift 2 ;;
        --props-source) PROPS_SOURCE=${2:-}; shift 2 ;;
        --recreate)   RECREATE=1; shift ;;
        --no-verify)  VERIFY=0; shift ;;
        --dry-run)    DRY_RUN=1; shift ;;
        -h|--help)    usage ;;
        *) echo "unknown option: $1" >&2; usage ;;
    esac
done

[[ "$WAREHOUSES" =~ ^[1-9][0-9]*$ ]] || { echo "warehouses must be a positive integer" >&2; exit 2; }
[[ "$WORKERS" =~ ^[1-9][0-9]*$ ]] || { echo "workers must be a positive integer" >&2; exit 2; }
[[ "$DB_USER" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || { echo "invalid user name: $DB_USER" >&2; exit 2; }

SKILL_DIR=$(cd "$(dirname "$0")/.." && pwd)
TEMPLATE="$SKILL_DIR/assets/props.template.ograc"
RUN_DIR="$BENCH/run"
OGSQL="$ROOT/ograc/ograc/server/bin/ogsql"
DATA_DIR="$ROOT/dbdata/local/ograc/tmp/data"
UB_LIB=/usr/local/ubs_mem/lib
STAMP=$(date +%Y%m%d_%H%M%S)
LOG="$ROOT/logs/tpcc-load-${WAREHOUSES}w-${STAMP}.log"
PROPS_NAME="props_tpcc_${WAREHOUSES}w_${STAMP}.ograc"
PROPS_PATH="$RUN_DIR/$PROPS_NAME"
RESULT_DIR="result_tpcc_${WAREHOUSES}w_%tY-%tm-%td_%tH%tM%tS"

for f in "$TEMPLATE" "$RUN_DIR/runDatabaseBuild.sh" "$RUN_DIR/runSQL.sh" "$OGSQL"; do
    [[ -e "$f" ]] || { echo "missing required file: $f" >&2; exit 1; }
done
mkdir -p "$ROOT/logs"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

# ---- resolve TPCC password without echoing it -------------------------------
if [[ -z "${TPCC_PWD:-}" ]]; then
    if [[ -z "$PROPS_SOURCE" ]]; then
        PROPS_SOURCE=$(find "$RUN_DIR" -maxdepth 1 -type f \
            \( -name 'props_*load*.ograc' -o -name 'props_tpcc_*.ograc' \) \
            -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    fi
    if [[ -n "$PROPS_SOURCE" && -f "$PROPS_SOURCE" ]]; then
        TPCC_PWD=$(grep '^password=' "$PROPS_SOURCE" | head -1 | cut -d= -f2-)
    fi
fi
if [[ -z "${TPCC_PWD:-}" ]]; then
    echo "TPCC_PWD is not set and no props source with password= was found." >&2
    echo "Set TPCC_PWD or pass --props-source <file>." >&2
    exit 1
fi
case "$TPCC_PWD" in
    *$'\n'*) echo "TPCC_PWD must not contain a newline" >&2; exit 1 ;;
esac
export TPCC_PWD

# ---- helpers ---------------------------------------------------------------
sql_sys() {
    printf 'y\n' | env LD_LIBRARY_PATH="$ROOT/ograc/ograc/server/lib:$ROOT/ograc/ograc/server/add-ons:$UB_LIB" \
        "$OGSQL" "/ AS SYSDBA 127.0.0.1:$DB_PORT" -D "$DATA_DIR" -c "$1" 2>&1
}

table_exists() {
    local out rc
    set +e
    out=$(sql_sys "select count(*) from ${DB_USER}.bmsql_warehouse;")
    rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
        return 0
    fi
    if printf '%s\n' "$out" | grep -qiE 'does not exist|not exist'; then
        return 1
    fi
    printf '%s\n' "$out" | tail -10 >&2
    echo "failed to check table existence (not a simple 'table missing' error)" >&2
    exit 1
}

write_props() {
    CONN="$CONN" DB_USER="$DB_USER" TPCC_PWD="$TPCC_PWD" \
    WAREHOUSES="$WAREHOUSES" WORKERS="$WORKERS" RESULT_DIR="$RESULT_DIR" \
    python3 -I - "$TEMPLATE" "$PROPS_PATH" <<'PY'
import os
import re
import sys

template, out = sys.argv[1], sys.argv[2]
text = open(template, "r", encoding="utf-8").read()
repl = {
    "__CONN__": os.environ["CONN"],
    "__USER__": os.environ["DB_USER"],
    "__PASSWORD__": os.environ["TPCC_PWD"],
    "__WAREHOUSES__": os.environ["WAREHOUSES"],
    "__WORKERS__": os.environ["WORKERS"],
    "__RESULT_DIR__": os.environ["RESULT_DIR"],
}
text = re.sub(r"__[A-Z_]+__", lambda m: repl.get(m.group(0), m.group(0)), text)
with open(out, "w", encoding="utf-8") as fp:
    fp.write(text)
PY
    chmod 600 "$PROPS_PATH"
}

# ---- plan / preflight ------------------------------------------------------
log "=== TPC-C prepare plan ==="
log "bench       : $BENCH"
log "conn        : $CONN"
log "user        : $DB_USER"
log "warehouses  : $WAREHOUSES"
log "loadWorkers : $WORKERS"
log "recreate    : $RECREATE"
log "props       : $PROPS_PATH"
log "log         : $LOG"

if [[ $DRY_RUN -eq 1 ]]; then
    log "[dry-run] would ensure user $DB_USER, generate props, run runDatabaseBuild.sh, verify row counts"
    exit 0
fi

# ---- ensure TPCC user ------------------------------------------------------
users_out=$(sql_sys "select name from sys_users;") || {
    printf '%s\n' "$users_out" | tail -5 >&2
    echo "cannot connect to the cluster as sysdba (is it OPEN READ WRITE?)" >&2
    exit 1
}
if printf '%s\n' "$users_out" | awk '{print $1}' | grep -qx "$DB_USER"; then
    log "user $DB_USER already exists"
else
    pwd_sql=${TPCC_PWD//\'/\'\'}
    log "creating user $DB_USER and granting privileges"
    set +e
    create_out=$(sql_sys "create user $DB_USER identified by '$pwd_sql'; grant create session to $DB_USER; grant create table to $DB_USER; grant dba to $DB_USER; grant inherit privileges on user SYS to $DB_USER;")
    create_rc=$?
    set -e
    if [[ $create_rc -ne 0 ]]; then
        printf '%s\n' "$create_out" | tail -10 >&2
        echo "failed to create user $DB_USER" >&2
        exit 1
    fi
    log "user $DB_USER created"
fi

# ---- generate props and check JDBC login/tables ----------------------------
write_props

printf 'select count(*) from bmsql_warehouse;\n' > /tmp/tpcc_table_check_$$.sql
trap 'rm -f /tmp/tpcc_table_check_$$.sql' EXIT

cd "$RUN_DIR"
set +e
check_out=$(./runSQL.sh "$PROPS_NAME" /tmp/tpcc_table_check_$$.sql 2>&1)
check_rc=$?
set -e
if printf '%s\n' "$check_out" | grep -qiE 'password authentication|invalid username|login failed|authentication failed'; then
    printf '%s\n' "$check_out" | tail -8 >&2
    echo "JDBC login as $DB_USER failed; TPCC_PWD does not match the existing user" >&2
    exit 1
fi
if printf '%s\n' "$check_out" | grep -qiE 'connection refused|connect timed out|failed to connect|no route to host'; then
    printf '%s\n' "$check_out" | tail -8 >&2
    echo "JDBC connection to $CONN failed" >&2
    exit 1
fi

if table_exists; then
    if [[ $RECREATE -eq 0 ]]; then
        echo "TPCC tables already exist. Use --recreate to drop and reload them." >&2
        exit 1
    fi
    log "dropping existing bmsql_* tables (--recreate)"
    ./runSQL.sh "$PROPS_NAME" tableDrops >/dev/null 2>&1 || true
fi

# ---- build ----------------------------------------------------------------
log "=== runDatabaseBuild.sh start ==="
set +e
./runDatabaseBuild.sh "$PROPS_NAME" 2>&1 | tee -a "$LOG"
build_rc=${PIPESTATUS[0]}
set -e
log "=== runDatabaseBuild.sh end rc=$build_rc ==="

if [[ $build_rc -ne 0 ]]; then
    echo "TPC-C build failed; see $LOG" >&2
    exit "$build_rc"
fi
if grep -qiE '(^|[^a-z])(error|exception|fatal)([^a-z]|$)' "$LOG"; then
    log "WARN: error-like lines found in the build log; review before using the data"
fi

# ---- verify ---------------------------------------------------------------
if [[ $VERIFY -eq 1 ]]; then
    log "=== verify row counts ==="
    bash "$SKILL_DIR/scripts/verify_tpcc.sh" --warehouses "$WAREHOUSES" --user "$DB_USER" --root "$ROOT" 2>&1 | tee -a "$LOG"
    verify_rc=${PIPESTATUS[0]}
    if [[ $verify_rc -ne 0 ]]; then
        echo "row-count verification failed; see $LOG" >&2
        exit "$verify_rc"
    fi
fi

# ---- record ---------------------------------------------------------------
RECORD="$ROOT/logs/tpcc-load-${WAREHOUSES}w-${STAMP}.md"
{
    echo "# TPCC ${WAREHOUSES} 仓导入记录"
    echo
    echo "- 时间: $(date '+%F %T')"
    echo "- 连接: $CONN"
    echo "- 用户: $DB_USER"
    echo "- warehouses: $WAREHOUSES"
    echo "- loadWorkers: $WORKERS"
    echo "- props: $PROPS_PATH (mode 600)"
    echo "- 日志: $LOG"
    echo "- recreate: $RECREATE"
    echo "- 校验: $([[ $VERIFY -eq 1 ]] && echo yes || echo no)"
} > "$RECORD"

log "done; props=$PROPS_PATH record=$RECORD"
