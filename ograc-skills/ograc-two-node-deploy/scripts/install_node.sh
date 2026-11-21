#!/bin/bash
# Install one oGRAC node from a package. Run on the target node itself.
#
# Required env:
#   SUDO_PWD       sudo password (never printed)
#   OGRAC_SYS_PWD  database sys password (never printed)
#   NODE0, NODE1   addresses of both nodes (rendered into the config)
#   DATA_DEV/REDO_DEV/ARCH_DEV/GCC_DEV
#                  absolute /dev/disk/by-id paths of the four LUNs
# Optional env (defaults shown):
#   OS_USER=$USER, OS_GROUP=$(id -gn), CMS_PORT=28520, DSS_PORT=28911,
#   DB_PORT=29300, INTERCONNECT_PORT=29410,29420, SHM_KEY=50
# Usage:
#   SUDO_PWD=... OGRAC_SYS_PWD=... bash install_node.sh \
#       --node 0 --package <tgz> --config <config-0.json> [--root <ROOT>] [--force]
#
# The config template may contain ${NAME} placeholders; they are rendered from
# the environment before the installer runs.
set -euo pipefail

ROOT=${ROOT:-$HOME/ograc_cluster}
NODE=""
PKG=""
CFG=""
FORCE=0

NODE0=${NODE0:?set NODE0 to the node0 address}
NODE1=${NODE1:?set NODE1 to the node1 address}
OS_USER=${OS_USER:-$USER}
OS_GROUP=${OS_GROUP:-$(id -gn)}
CMS_PORT=${CMS_PORT:-28520}
DSS_PORT=${DSS_PORT:-28911}
DB_PORT=${DB_PORT:-29300}
INTERCONNECT_PORT=${INTERCONNECT_PORT:-29410,29420}
SHM_KEY=${SHM_KEY:-50}
: "${DATA_DEV:?set DATA_DEV to the data LUN device}"
: "${REDO_DEV:?set REDO_DEV to the redo LUN device}"
: "${ARCH_DEV:?set ARCH_DEV to the archive LUN device}"
: "${GCC_DEV:?set GCC_DEV to the GCC LUN device}"

usage() {
    echo "usage: install_node.sh --node 0|1 --package <tgz> --config <json> [--root <ROOT>] [--force]" >&2
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --node)    NODE=${2:-}; shift 2 ;;
        --package) PKG=${2:-}; shift 2 ;;
        --config)  CFG=${2:-}; shift 2 ;;
        --root)    ROOT=${2:-}; shift 2 ;;
        --force)   FORCE=1; shift ;;
        *) usage ;;
    esac
done

[[ "$NODE" == "0" || "$NODE" == "1" ]] || usage
[[ -f "$PKG" ]] || { echo "missing package: $PKG" >&2; exit 1; }
[[ -f "$CFG" ]] || { echo "missing config: $CFG" >&2; exit 1; }
: "${SUDO_PWD:?set SUDO_PWD to the sudo password}"
: "${OGRAC_SYS_PWD:?set OGRAC_SYS_PWD to the database sys password}"

# Refuse dangerous roots.
case "$ROOT" in
    /|/home|"$HOME"|"") echo "unsafe ROOT: '$ROOT'" >&2; exit 1 ;;
esac
[[ "$ROOT" == /* ]] || { echo "ROOT must be absolute: $ROOT" >&2; exit 1; }

our_procs() {
    ps -eo pid=,comm=,args= | awk -v r="$ROOT" \
        '($2=="ogracd" || $2=="cms" || $2=="dssserver") && index($0, r) {print}'
}
if [[ -n "$(our_procs)" ]]; then
    if [[ $FORCE -eq 1 ]]; then
        echo "WARNING: this deployment's cluster processes are running; --force given." >&2
    else
        echo "cluster processes of this deployment are still running; stop the cluster first (or use --force)." >&2
        exit 1
    fi
fi

sudo_run() {
    printf '%s\n' "$SUDO_PWD" | sudo -S -p '' "$@"
}

# Render ${NAME} placeholders in the LUN config from the environment.  The
# template is intentionally not valid JSON until rendered (SHM_KEY is numeric).
# Python is used instead of bash pattern substitution so values containing
# "&", "/" or other pattern characters are substituted literally.
render_config() { # <src> <dst>
    local src=$1 dst=$2
    command -v python3 >/dev/null 2>&1 || {
        echo "python3 is required to render $src" >&2
        return 1
    }
    NODE0="$NODE0" NODE1="$NODE1" OS_USER="$OS_USER" OS_GROUP="$OS_GROUP" \
    ROOT="$ROOT" DATA_DEV="$DATA_DEV" REDO_DEV="$REDO_DEV" ARCH_DEV="$ARCH_DEV" \
    GCC_DEV="$GCC_DEV" CMS_PORT="$CMS_PORT" DSS_PORT="$DSS_PORT" DB_PORT="$DB_PORT" \
    INTERCONNECT_PORT="$INTERCONNECT_PORT" SHM_KEY="$SHM_KEY" \
    python3 - "$src" "$dst" <<'PY'
import os
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
with open(src, "r", encoding="utf-8") as fp:
    text = fp.read()

def substitute(match):
    key = match.group(1)
    value = os.environ.get(key, "")
    if not value:
        sys.exit("empty or missing value for config placeholder: %s" % key)
    return value

text = re.sub(r"\$\{([A-Z0-9_]+)\}", substitute, text)
if "${" in text:
    sys.exit("unrendered placeholders remain in %s" % src)
with open(dst, "w", encoding="utf-8") as fp:
    fp.write(text)
PY
}

mkdir -p "$ROOT/logs"
LOG="$ROOT/logs/install-node${NODE}-$(date +%Y%m%d-%H%M%S).log"

umask 077
PWD_FILE=$(mktemp /tmp/ograc_sys_pwd.XXXXXX)
CFG_RENDERED=$(mktemp /tmp/ograc_config.XXXXXX)
trap 'rm -f "$PWD_FILE" "$CFG_RENDERED"' EXIT
printf '%s' "$OGRAC_SYS_PWD" > "$PWD_FILE"
render_config "$CFG" "$CFG_RENDERED"

echo "=== node ${NODE} install ===" | tee "$LOG"
echo "package: $PKG" | tee -a "$LOG"
echo "config : $CFG (rendered from environment)" | tee -a "$LOG"
echo "root   : $ROOT" | tee -a "$LOG"

echo "=== extract package ===" | tee -a "$LOG"
sudo_run rm -rf "$ROOT/ograc_connector"
sudo_run tar -xzf "$PKG" -C "$ROOT"
sudo_run chown -R root:root "$ROOT/ograc_connector"
sudo_run chmod -R 777 "$ROOT/ograc_connector"
sudo_run cp "$CFG_RENDERED" "$ROOT/ograc_connector/action/config_params_lun.json"
sudo_run chmod 600 "$ROOT/ograc_connector/action/config_params_lun.json"

cd "$ROOT/ograc_connector/action"

echo "=== pre_install ===" | tee -a "$LOG"
sudo_run env OGRAC_SYS_PASSWORD_FILE="$PWD_FILE" \
    sh appctl.sh pre_install config_params_lun.json 2>&1 | tee -a "$LOG"

echo "=== install ===" | tee -a "$LOG"
sudo_run env OGRAC_SYS_PASSWORD_FILE="$PWD_FILE" \
    sh appctl.sh install config_params_lun.json 2>&1 | tee -a "$LOG"

echo "=== node ${NODE} install finished: $LOG ==="
