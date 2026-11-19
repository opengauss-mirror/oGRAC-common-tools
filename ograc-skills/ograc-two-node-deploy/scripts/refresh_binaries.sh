#!/bin/bash
# Refresh installed oGRAC/DSS/CMS binaries from the local build output.
# The cluster MUST be stopped first. Preserves data and configuration.
#
# Usage: SUDO_PWD='<sudo password>' bash refresh_binaries.sh [--src "$HOME/code/oGRAC"]
set -euo pipefail

ROOT=${ROOT:-$HOME/ograc_cluster}
SRC=${SRC:-$HOME/code/oGRAC}
NODE1=${NODE1:?set NODE1 to the node1 address}
SSH_USER=${SSH_USER:-$USER}
: "${SUDO_PWD:?set SUDO_PWD to restore perctrl file capabilities after the copy}"

sudo_run() { printf '%s\n' "$SUDO_PWD" | sudo -S -p '' "$@"; }
sudo_run1() { printf '%s\n' "$SUDO_PWD" | ssh1 "sudo -S -p '' $*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --src) SRC=${2:-}; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

# Only our own deployment matters: the hosts may also run other users' oGRAC
# instances, whose ogracd/dssserver/cms must not block (or be touched by) this
# refresh.  Match the command line on our ROOT path.
# Match on comm (not the raw argv) so this script's own awk invocation, whose
# argument list contains the same strings, is never mistaken for a daemon.
running=$(ps -eo pid=,comm=,args= | awk -v r="$ROOT" \
    '($2=="ogracd" || $2=="cms" || $2=="dssserver") && index($0, r) {print}')
if [[ -n "$running" ]]; then
    echo "cluster processes are running; stop the cluster before refreshing binaries." >&2
    echo "$running" >&2
    exit 1
fi

for f in "$SRC/output/bin/ogracd" "$SRC/dss/bin/dssserver" "$SRC/output/bin/cms"; do
    [[ -f "$f" ]] || { echo "missing build output: $f" >&2; exit 1; }
done

# CMS runs with CAP_SYS_RAWIO (file capability), so the loader is in secure
# mode: LD_LIBRARY_PATH and $ORIGIN runpaths are ignored, and the lookup falls
# back to ld.so.cache.  On these hosts the cache resolves libogprotocol.so /
# libogcommon.so to /usr/lib64 copies owned by another user and mode 750,
# which gives "cannot open shared object file: Permission denied".  Bake an
# absolute RUNPATH (same $ROOT on both nodes) and ship the matching protocol
# libraries into cms/service/lib.
CMS_RPATH="$ROOT/ograc/cms/service/lib:$ROOT/ograc/cms/service/add-ons"
command -v patchelf >/dev/null 2>&1 || { echo "patchelf not found; cms needs an absolute RUNPATH" >&2; exit 1; }
chmod u+w "$SRC/output/bin/cms" 2>/dev/null || true
patchelf --set-rpath "$CMS_RPATH" "$SRC/output/bin/cms"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
ssh1() { ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_USER@$NODE1" "$@"; }

sha() { sha256sum "$1" | awk '{print $1}'; }

log "=== node0: copy binaries ==="
install -m 700 "$SRC/output/bin/ogracd" "$ROOT/ograc/ograc/server/bin/ogracd"
cp -f "$SRC"/output/lib/*.so "$ROOT/ograc/ograc/server/lib/"
chmod 700 "$ROOT"/ograc/ograc/server/lib/*.so
cp -f "$SRC"/dss/bin/* "$ROOT/ograc/dss/bin/"
chmod 700 "$ROOT"/ograc/dss/bin/*
cp -f "$SRC"/dss/lib/* "$ROOT/ograc/dss/lib/" 2>/dev/null || true
install -m 500 "$SRC/output/bin/cms" "$ROOT/ograc/cms/service/bin/cms"
# RUNPATH resolves these two from cms/service/lib; keep them on the same build.
for f in libogprotocol.so libogcommon.so; do
    chmod u+w "$ROOT/ograc/cms/service/lib/$f" 2>/dev/null || true
    cp -f "$SRC/output/lib/$f" "$ROOT/ograc/cms/service/lib/$f"
    chmod 500 "$ROOT/ograc/cms/service/lib/$f"
done
# cp clears file capabilities. perctrl needs them for SCSI PR (dsscmd reghl/inq_reg),
# otherwise the next DSS start fails with EPERM/EEXIST.
sudo_run setcap cap_sys_admin,cap_sys_rawio+ep "$ROOT/ograc/dss/bin/perctrl"
log "node0 ogracd sha256: $(sha "$ROOT/ograc/ograc/server/bin/ogracd")"
log "node0 perctrl caps: $(getcap "$ROOT/ograc/dss/bin/perctrl")"

log "=== node1: copy binaries ==="
# Installed binaries/libraries are often mode 500/600.  scp opens the existing
# destination for writing instead of replacing it, so make the remote targets
# writable for their owner first (the post-copy step restores the final modes).
ssh1 "chmod -R u+w '$ROOT/ograc/ograc/server/bin' '$ROOT/ograc/ograc/server/lib' \
    '$ROOT/ograc/dss/bin' '$ROOT/ograc/dss/lib' '$ROOT/ograc/cms/service/bin' \
    '$ROOT/ograc/cms/service/lib' 2>/dev/null || true"
scp -q "$SRC/output/bin/ogracd" "$SSH_USER@$NODE1:$ROOT/ograc/ograc/server/bin/ogracd"
scp -q "$SRC"/output/lib/*.so "$SSH_USER@$NODE1:$ROOT/ograc/ograc/server/lib/"
scp -q "$SRC"/dss/bin/* "$SSH_USER@$NODE1:$ROOT/ograc/dss/bin/"
scp -q "$SRC"/dss/lib/* "$SSH_USER@$NODE1:$ROOT/ograc/dss/lib/" 2>/dev/null || true
scp -q "$SRC/output/bin/cms" "$SSH_USER@$NODE1:$ROOT/ograc/cms/service/bin/cms"
scp -q "$SRC"/output/lib/libogprotocol.so "$SRC"/output/lib/libogcommon.so "$SSH_USER@$NODE1:$ROOT/ograc/cms/service/lib/"
ssh1 "chmod 700 '$ROOT/ograc/ograc/server/bin/ogracd' '$ROOT'/ograc/ograc/server/lib/*.so '$ROOT'/ograc/dss/bin/*; chmod 500 '$ROOT/ograc/cms/service/bin/cms' '$ROOT/ograc/cms/service/lib/libogprotocol.so' '$ROOT/ograc/cms/service/lib/libogcommon.so'"
sudo_run1 setcap cap_sys_admin,cap_sys_rawio+ep "$ROOT/ograc/dss/bin/perctrl"
log "node1 ogracd sha256: $(ssh1 "sha256sum '$ROOT/ograc/ograc/server/bin/ogracd'" | awk '{print $1}')"
log "node1 perctrl caps: $(ssh1 "getcap '$ROOT/ograc/dss/bin/perctrl'")"

log "=== verify debug info ==="
file "$ROOT/ograc/ograc/server/bin/ogracd" "$ROOT/ograc/dss/bin/dssserver" "$ROOT/ograc/cms/service/bin/cms"
ssh1 "file '$ROOT/ograc/ograc/server/bin/ogracd' '$ROOT/ograc/dss/bin/dssserver' '$ROOT/ograc/cms/service/bin/cms'"

log "done; start the cluster with start_cluster.sh"
