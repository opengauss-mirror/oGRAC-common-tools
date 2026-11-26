#!/bin/bash
# Verify TPC-C row counts in the two-node oGRAC cluster.
# Uses the local "/ AS SYSDBA" connection, so no database password is needed.
set -uo pipefail

ROOT=${ROOT:-$HOME/ograc_cluster}
DB_USER=${DB_USER:-TPCC}
WAREHOUSES=${WAREHOUSES:-100}
DB_PORT=${DB_PORT:-29300}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --warehouses) WAREHOUSES=${2:-}; shift 2 ;;
        --user)       DB_USER=${2:-}; shift 2 ;;
        --root)       ROOT=${2:-}; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

[[ "$WAREHOUSES" =~ ^[1-9][0-9]*$ ]] || { echo "invalid warehouses: $WAREHOUSES" >&2; exit 2; }

OGSQL="$ROOT/ograc/ograc/server/bin/ogsql"
DATA_DIR="$ROOT/dbdata/local/ograc/tmp/data"
UB_LIB=/usr/local/ubs_mem/lib
fails=0

sql_sys() {
    printf 'y\n' | env LD_LIBRARY_PATH="$ROOT/ograc/ograc/server/lib:$ROOT/ograc/ograc/server/add-ons:$UB_LIB" \
        "$OGSQL" "/ AS SYSDBA 127.0.0.1:$DB_PORT" -D "$DATA_DIR" -c "$1" 2>&1
}

count_table() { # count_table <table>
    local out rc val
    out=$(sql_sys "select count(*) from ${DB_USER}.$1;")
    rc=$?
    if [[ $rc -ne 0 ]]; then
        printf '%s\n' "$out" | tail -3 >&2
        echo ""
        return 1
    fi
    val=$(printf '%s\n' "$out" | awk '$1 ~ /^[0-9]+$/ && NF==1 {v=$1} END {print v}')
    [[ -n "$val" ]] || { echo "cannot parse count for $1" >&2; echo ""; return 1; }
    echo "$val"
}

check_exact() { # check_exact <table> <expected>
    local table=$1 expected=$2 actual
    actual=$(count_table "$table") || { fails=$((fails + 1)); printf '%-24s %12s %12s %s\n' "$table" "$expected" "ERROR" "FAIL"; return; }
    if [[ "$actual" == "$expected" ]]; then
        printf '%-24s %12s %12s %s\n' "$table" "$expected" "$actual" "PASS"
    else
        printf '%-24s %12s %12s %s\n' "$table" "$expected" "$actual" "FAIL"
        fails=$((fails + 1))
    fi
}

check_range() { # check_range <table> <expected> <percent>
    local table=$1 expected=$2 percent=$3 actual low high
    actual=$(count_table "$table") || { fails=$((fails + 1)); printf '%-24s %12s %12s %s\n' "$table" "~$expected" "ERROR" "FAIL"; return; }
    low=$((expected - expected * percent / 100))
    high=$((expected + expected * percent / 100))
    if (( actual >= low && actual <= high )); then
        printf '%-24s %12s %12s %s\n' "$table" "~$expected" "$actual" "PASS"
    else
        printf '%-24s %12s %12s %s\n' "$table" "~$expected" "$actual" "FAIL"
        fails=$((fails + 1))
    fi
}

echo "TPCC row-count verification: warehouses=$WAREHOUSES user=$DB_USER"
printf '%-24s %12s %12s %s\n' "table" "expected" "actual" "status"
printf '%-24s %12s %12s %s\n' "------------------------" "------------" "------------" "------"

check_exact bmsql_warehouse "$WAREHOUSES"
check_exact bmsql_district "$((WAREHOUSES * 10))"
check_exact bmsql_item 100000
check_exact bmsql_stock "$((WAREHOUSES * 100000))"
check_exact bmsql_customer "$((WAREHOUSES * 30000))"
check_exact bmsql_history "$((WAREHOUSES * 30000))"
check_exact bmsql_oorder "$((WAREHOUSES * 30000))"
check_exact bmsql_new_order "$((WAREHOUSES * 9000))"
check_range bmsql_order_line "$((WAREHOUSES * 300000))" 10

echo
if [[ $fails -eq 0 ]]; then
    echo "TPCC row-count verification passed"
    exit 0
fi
echo "TPCC row-count verification failed: $fails table(s)"
exit 1
