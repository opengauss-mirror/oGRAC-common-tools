#!/bin/bash
# Build the oGRAC two-node package with release optimization + DWARF.
# The build takes 40-60 minutes; run it as a background task.
set -euo pipefail

ROOT=${ROOT:-$HOME/ograc_cluster}
SRC=${SRC:-$HOME/code/oGRAC}
LOG_DIR=${LOG_DIR:-$ROOT/logs}
BUILD_TYPE=${BUILD_TYPE:-release}
# Process-crash/GBP fault recovery requires USE_ATOMIC_LOCK=ON.  A release
# built without it silently rejects recovery and can abort in page-read paths.
ATOMIC_LOCK=${ATOMIC_LOCK:-1}

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"

if [[ ! -x "$SRC/build/build_ograc.sh" && ! -f "$SRC/build/build_ograc.sh" ]]; then
    echo "build script not found: $SRC/build/build_ograc.sh" >&2
    exit 1
fi

echo "source : $SRC"
echo "log    : $LOG"
echo "atomic : $ATOMIC_LOCK (1/ON enables USE_ATOMIC_LOCK, required for process-crash recovery)"
echo "start  : $(date '+%F %T')"
cd "$SRC/build"

build_args=("$BUILD_TYPE" "--with-dss")
if [[ "$ATOMIC_LOCK" == "1" || "$ATOMIC_LOCK" == "ON" ]]; then
    build_args+=("atomic_lock=1")
fi

set +e
KEEP_DEBUG_INFO=1 sh build_ograc.sh "${build_args[@]}" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e

echo "finish : $(date '+%F %T')  rc=$rc"
[[ $rc -eq 0 ]] || { echo "build failed, see $LOG" >&2; exit "$rc"; }

pkg=$(ls -t "$SRC"/package/openGauss-oGRAC-*.tgz 2>/dev/null | head -1)
[[ -n "$pkg" && -f "$pkg" ]] || { echo "package not found under $SRC/package" >&2; exit 1; }

echo "package: $pkg"
sha256sum "$pkg"
for f in "$SRC/output/bin/ogracd" "$SRC/dss/bin/dssserver" "$SRC/output/bin/cms"; do
    [[ -f "$f" ]] && file "$f"
done
echo "done"
