#!/bin/bash
# Read-only preflight checks for a two-node oGRAC test cluster.
# Usage: bash preflight.sh [--running-ok]
# Exit code: number of FAIL items (0 = ready).
#
# Required environment:
#   NODE0, NODE1      addresses of the two nodes (node1 must be reachable by SSH)
#   ROOT              deployment root (default $HOME/ograc_cluster)
#   SRC               oGRAC source tree (default $HOME/code/oGRAC)
# Optional environment:
#   SSH_USER          SSH user for node1 (default current user)
#   DATA_DEV/REDO_DEV/ARCH_DEV/GCC_DEV
#                     absolute /dev/disk/by-id paths of the four LUNs
#   CMS_PORT/DSS_PORT/DB_PORT (default 28520/28911/29300)
#   STRICT_LOCAL_PATCHES=1  treat missing local build adaptations as FAIL
set -uo pipefail

ROOT=${ROOT:-$HOME/ograc_cluster}
SRC=${SRC:-$HOME/code/oGRAC}
NODE0=${NODE0:?set NODE0 to the node0 address}
NODE1=${NODE1:?set NODE1 to the node1 address}
SSH_USER=${SSH_USER:-$USER}
CMS_PORT=${CMS_PORT:-28520}
DSS_PORT=${DSS_PORT:-28911}
DB_PORT=${DB_PORT:-29300}
STRICT_LOCAL_PATCHES=${STRICT_LOCAL_PATCHES:-0}
RUNNING_OK=0
[[ ${1:-} == "--running-ok" ]] && RUNNING_OK=1

LUNS=()
for dev in "${DATA_DEV:-}" "${REDO_DEV:-}" "${ARCH_DEV:-}" "${GCC_DEV:-}"; do
    [[ -n "$dev" ]] && LUNS+=("$dev")
done

fails=0
warns=0
ok()   { printf '[OK]   %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; warns=$((warns + 1)); }
bad()  { printf '[FAIL] %s\n' "$*"; fails=$((fails + 1)); }
section() { printf '\n== %s ==\n' "$*"; }

ssh1() { ssh -o BatchMode=yes -o ConnectTimeout=8 "$SSH_USER@$NODE1" "$@"; }
our_procs_local() {
    ps -eo pid=,comm=,args= | awk -v r="$ROOT" \
        '($2=="ogracd" || $2=="cms" || $2=="dssserver") && index($0, r) {print}'
}
our_procs_remote() {
    ssh1 "ps -eo pid=,comm=,args= | awk -v r='$ROOT' '\$2==\"ogracd\" || \$2==\"cms\" || \$2==\"dssserver\" { if (index(\$0, r)) print }'" 2>/dev/null
}

section "节点与 SSH"
if [[ "$(hostname -I 2>/dev/null)" == *"$NODE0"* ]]; then
    ok "当前节点包含 $NODE0"
else
    warn "当前节点 IP 未匹配 $NODE0，请确认在 node0 上执行（NODE0 也可以是本机主机名）"
fi
if ssh1 true >/dev/null 2>&1; then
    ok "SSH 免密到 $NODE1"
else
    bad "SSH 免密到 $NODE1 失败"
fi

section "目录"
for d in "$ROOT" "$ROOT/ograc" "$ROOT/dbdata"; do
    if [[ -d "$d" ]]; then ok "存在 $d"; else warn "不存在 $d（首次安装可忽略）"; fi
done
if [[ -d "$ROOT/ograc_connector/action" ]]; then
    ok "存在 $ROOT/ograc_connector/action"
else
    warn "不存在 $ROOT/ograc_connector/action（首次安装可忽略）"
fi
if [[ -d "$SRC" ]]; then ok "存在源码树 $SRC"; else bad "缺少源码树 $SRC"; fi

section "ubsmd 服务与用户组"
for node in "$NODE0" "$NODE1"; do
    if [[ "$node" == "$NODE0" ]]; then
        st=$(systemctl is-active ubsmd 2>/dev/null || true)
    else
        st=$(ssh1 systemctl is-active ubsmd 2>/dev/null || true)
    fi
    [[ "$st" == "active" ]] && ok "$node ubsmd active" || bad "$node ubsmd 状态: ${st:-unknown}"
done
if id -nG | tr ' ' '\n' | grep -qx ubsmd; then
    ok "当前会话包含 ubsmd 组"
else
    warn "当前会话不含 ubsmd 组；启动脚本会用 sg ubsmd 提权到该组"
fi
if ssh1 'id -nG | grep -qw ubsmd' >/dev/null 2>&1; then
    ok "node1 会话包含 ubsmd 组"
else
    warn "node1 的 $SSH_USER 会话不含 ubsmd 组"
fi

section "LUN 设备"
if [[ ${#LUNS[@]} -eq 0 ]]; then
    warn "未设置 DATA_DEV/REDO_DEV/ARCH_DEV/GCC_DEV，跳过 LUN 检查（仅刷新二进制时可忽略）"
else
    for dev in "${LUNS[@]}"; do
        if [[ -e "$dev" ]]; then ok "$dev"; else bad "缺少设备 $dev"; fi
    done
    for dev in "${LUNS[@]}"; do
        real=$(readlink -f "$dev" 2>/dev/null || true)
        [[ -z "$real" ]] && continue
        mnt=$(lsblk -no MOUNTPOINT "$real" 2>/dev/null | head -1)
        [[ -n "$mnt" ]] && warn "$dev 已挂载到 $mnt" || true
    done
fi

section "源码树构建适配（本地补丁，可选）"
# These checks describe optional adaptations of a working tree (keeping DWARF in
# release builds, falling back to the system compiler, isolating UB namespaces).
# They are not required by upstream oGRAC; set STRICT_LOCAL_PATCHES=1 if your
# deployment depends on them.
check_grep() {
    local file=$1 pattern=$2 label=$3
    if [[ -f "$file" ]] && grep -q "$pattern" "$file"; then
        ok "$label"
    elif [[ $STRICT_LOCAL_PATCHES -eq 1 ]]; then
        bad "$label（$file 缺少 '$pattern'）"
    else
        warn "$label 未检测到（若本次部署依赖该适配，请恢复后再构建）"
    fi
}
check_grep "$SRC/build/Makefile.sh" "KEEP_DEBUG_INFO" "Makefile.sh 保留调试符号开关"
check_grep "$SRC/build/build_ograc.sh" "KEEP_DEBUG_INFO" "build_ograc.sh 符号包开关"
check_grep "$SRC/build/build_dss.sh" "KEEP_DEBUG_INFO" "build_dss.sh 保留调试符号"
check_grep "$SRC/build/build_dss.sh" "using system gcc" "build_dss.sh 系统 gcc 回退"
check_grep "$SRC/CBB/build/linux/opengauss/build.sh" "using system gcc" "CBB build.sh 系统 gcc 回退"
check_grep "$SRC/CBB/CMakeLists.txt" "Wno-error" "CBB -Wno-error"
check_grep "$SRC/DSS/CMakeLists.txt" "Wno-error" "DSS -Wno-error"
check_grep "$SRC/pkg/src/cluster/dtc_remote_buffer.c" "shm_pool_v" "UB 区域名版本隔离"
check_grep "$SRC/pkg/src/protocol/cs_ub.c" "shm_pool_v" "UB 区域名版本隔离（protocol）"
check_grep "$SRC/pkg/src/cluster/dtc_ub_reclaim.c" "_v[0-9]*_data_buf_part_" "UB 对象名版本隔离（reclaim）"

section "端口"
for port in "$CMS_PORT" "$DSS_PORT" "$DB_PORT"; do
    if ss -lntH "sport = :$port" 2>/dev/null | grep -q .; then
        if [[ $RUNNING_OK -eq 1 ]]; then
            ok "端口 $port 已被占用（允许集群运行）"
        else
            warn "端口 $port 已被占用；如为当前集群请先 stop_cluster.sh"
        fi
    else
        ok "端口 $port 空闲"
    fi
done

section "集群进程（仅当前 ROOT）"
procs="$(our_procs_local)"
remote_procs="$(our_procs_remote || true)"
if [[ -z "$procs" && -z "$remote_procs" ]]; then
    ok "两节点均无本实例的 oGRAC 进程"
else
    if [[ $RUNNING_OK -eq 1 ]]; then
        ok "本实例 oGRAC 进程（允许运行）"
    else
        warn "本实例存在 oGRAC 进程；全量安装/刷新二进制前需要停止"
    fi
    [[ -n "$procs" ]] && printf '%s\n' "$procs" | sed 's/^/       node0: /'
    [[ -n "$remote_procs" ]] && printf '%s\n' "$remote_procs" | sed 's/^/       node1: /'
fi

section "汇总"
printf 'FAIL=%d WARN=%d\n' "$fails" "$warns"
[[ $fails -eq 0 ]] && echo "预检通过" || echo "预检未通过，请先处理 FAIL 项"
exit "$fails"
