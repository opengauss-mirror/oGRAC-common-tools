#!/bin/bash
################################################################################
# oGRAC 单集群 LUN 开发环境
#
# 宿主机用 LIO(fileio + tcm_loop) 创建 4 个 LUN；每个 LUN 有 node0/node1 两条
# loopback 路径，共享同一个 backstore，支持真实 SCSI-3 PR。容器内运行双节点主集群。
# 脚本为单文件版本，可拷贝到 oGRAC 源码树任意位置执行，不依赖同目录 Dockerfile/cluster.sh。
#
#   sudo bash ograc_sim_single.sh create
#   sudo bash ograc_sim_single.sh init
#   sudo bash ograc_sim_single.sh make debug
#   sudo bash ograc_sim_single.sh install debug
#   sudo bash ograc_sim_single.sh start
#   sudo bash ograc_sim_single.sh verify
################################################################################
if [ -z "${BASH_VERSION:-}" ]; then echo "[ERROR] 请用 bash 执行" >&2; exit 1; fi
if shopt -qo posix 2>/dev/null; then exec /bin/bash "$0" "$@"; fi
set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
is_ograc_src() { [ -f "${1}/build/build_ograc.sh" ] && [ -d "${1}/docker" ]; }
find_ograc_src() {
    local cand start parent
    if [ -n "${OGRAC_SRC:-}" ]; then
        cand="$(cd "${OGRAC_SRC}" 2>/dev/null && pwd)" || return 1
        is_ograc_src "${cand}" || return 1
        printf '%s\n' "${cand}"; return 0
    fi
    for start in "${SCRIPT_DIR}" "${PWD}"; do
        cand="$(cd "${start}" 2>/dev/null && pwd)" || continue
        while :; do
            if is_ograc_src "${cand}"; then printf '%s\n' "${cand}"; return 0; fi
            [ "${cand}" = "/" ] && break
            parent="$(dirname "${cand}")"; [ "${parent}" = "${cand}" ] && break
            cand="${parent}"
        done
    done
    return 1
}
OGRAC_SRC="$(find_ograc_src)" || {
    echo "[ERROR] 未找到 oGRAC 源码根目录；请将脚本放到源码树内，或设置 OGRAC_SRC=/path/to/oGRAC" >&2
    exit 1
}
export OGRAC_SRC
IN_CONTAINER="${OGRAC_IN_CONTAINER:-0}"
SIM_USER="${SIM_USER:-${SUDO_USER:-$(logname 2>/dev/null || whoami)}}"; SIM_USER="${SIM_USER:-root}"
SIM_ROOT="${SIM_ROOT:-/home/${SIM_USER}/ogracsim_single}"
SIM_BASE="${OGRAC_DEV_BASE:-${SIM_BASE:-${SIM_ROOT}/cluster}}"
DEPLOY_USER="${DEPLOY_USER:-${SIM_USER}_ograc}"
CONTAINER_NAME="${CONTAINER_NAME:-ograc-dev-${SIM_USER}}"
IMAGE_NAME="${IMAGE_NAME:-ograc:dev}"
INSTANCE_ID="${INSTANCE_ID:-${SIM_USER}_single}"
DEV_SLOT="${DEV_SLOT:-0}"
LUN_COUNT="${LUN_COUNT:-4}"
LUN_SIZE="${LUN_SIZE:-200G}"
LUN_PREFIX="${LUN_PREFIX:-sim}"
DTC_TASK_NUM="${DTC_TASK_NUM:-16}"
RCY_PROC_NUM="${RCY_PROC_NUM:-8}"
REDO_NUM="${REDO_NUM:-50}"
MEM_DATA_BUFFER="${MEM_DATA_BUFFER:-8G}"
MEM_TEMP_BUFFER="${MEM_TEMP_BUFFER:-256M}"
MEM_SHARED_POOL="${MEM_SHARED_POOL:-512M}"
MEM_INDEX_BUFFER="${MEM_INDEX_BUFFER:-128M}"
MEM_VARIANT_AREA="${MEM_VARIANT_AREA:-32M}"
MEM_LARGE_POOL="${MEM_LARGE_POOL:-16M}"
MEM_SESSIONS="${MEM_SESSIONS:-512}"
MEM_OPT_WORKERS="${MEM_OPT_WORKERS:-128}"
MEM_MAX_WORKERS="${MEM_MAX_WORKERS:-256}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
apply_layout() {
    local off=$((DEV_SLOT * 100))
    LUN_IMG_DIR="${SIM_BASE}/lundisks"; DBDATA0_HOST_DIR="${SIM_BASE}/dbdata"
    DBDATA1_HOST_DIR="${SIM_BASE}/dbdata1"; INSTALL_HOST_DIR="${SIM_BASE}/install"
    DEV_ENV_FILE="${SIM_BASE}/dev.env"
    WWN_BASE="${WWN_BASE:-naa.60014056$(printf '%04x' "${DEV_SLOT}")00}"
    FILEIO_START="${FILEIO_START:-$((5 + DEV_SLOT * 4))}"
    NODE0_CMS_PORT="${NODE0_CMS_PORT:-$((18520 + off))}"; NODE1_CMS_PORT="${NODE1_CMS_PORT:-$((18521 + off))}"
    NODE0_DSS_PORT="${NODE0_DSS_PORT:-$((19100 + off))}"; NODE1_DSS_PORT="${NODE1_DSS_PORT:-$((19101 + off))}"
    NODE0_OGRAC_PORT="${NODE0_OGRAC_PORT:-$((19300 + off))}"; NODE1_OGRAC_PORT="${NODE1_OGRAC_PORT:-$((19301 + off))}"
    NODE0_INTERCONNECT_PORT="${NODE0_INTERCONNECT_PORT:-$((19410 + off))}"
    NODE1_INTERCONNECT_PORT="${NODE1_INTERCONNECT_PORT:-$((19420 + off))}"
    SHM_KEY="${SHM_KEY:-$((17 + DEV_SLOT * 2))}"; SHM_KEY1="${SHM_KEY1:-$((18 + DEV_SLOT * 2))}"
}
apply_layout
if [ -f "${SIM_BASE}/dev.env" ]; then
    # shellcheck disable=SC1090
    set -a; source "${SIM_BASE}/dev.env"; set +a; apply_layout
fi
log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { echo "[$(date '+%H:%M:%S')] [ERROR] $*" >&2; exit 1; }
err() { echo "[$(date '+%H:%M:%S')] [ERROR] $*" >&2; }
container_running() { docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "${CONTAINER_NAME}"; }
require_host_root() {
    [ "${IN_CONTAINER}" = "1" ] && die "请在宿主机执行，不要在容器内执行"
    [ "$(id -u)" -eq 0 ] || die "请使用 sudo 执行: sudo bash $0 $*"
}
write_dev_env() {
    local v
    mkdir -p "${SIM_BASE}"; : > "${DEV_ENV_FILE}"
    for v in SIM_USER SIM_ROOT SIM_BASE DEPLOY_USER CONTAINER_NAME IMAGE_NAME INSTANCE_ID DEV_SLOT \
             LUN_COUNT LUN_SIZE LUN_PREFIX WWN_BASE FILEIO_START NODE0_CMS_PORT NODE1_CMS_PORT \
             NODE0_DSS_PORT NODE1_DSS_PORT NODE0_OGRAC_PORT NODE1_OGRAC_PORT \
             NODE0_INTERCONNECT_PORT NODE1_INTERCONNECT_PORT SHM_KEY SHM_KEY1 DTC_TASK_NUM RCY_PROC_NUM REDO_NUM \
             MEM_DATA_BUFFER MEM_TEMP_BUFFER MEM_SHARED_POOL MEM_INDEX_BUFFER MEM_VARIANT_AREA MEM_LARGE_POOL \
             MEM_SESSIONS MEM_OPT_WORKERS MEM_MAX_WORKERS; do
        printf '%s=%q\n' "${v}" "${!v}" >> "${DEV_ENV_FILE}"
    done
    chmod 644 "${DEV_ENV_FILE}"
}
# ============================== 宿主机：LUN ==================================
ensure_pr_metadata_dir() { mkdir -p /var/target/pr || die "无法创建 /var/target/pr"; chmod 755 /var/target /var/target/pr 2>/dev/null || true; }
clean_luns() {
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    local loopback_base="/sys/kernel/config/target/loopback" core_base="/sys/kernel/config/target/core"
    local i wwn_dir tpg lun bs_idx bs_dir lun_dir sub
    for i in $(seq 1 $((LUN_COUNT * 2))); do
        wwn_dir="${loopback_base}/${WWN_BASE}$(printf '%02d' "${i}")"; [ -d "${wwn_dir}" ] || continue
        for tpg in "${wwn_dir}"/tpgt_*; do
            [ -d "${tpg}" ] || continue
            for lun in "${tpg}"/lun/lun_*; do
                [ -d "${lun}" ] || continue
                find "${lun}" -maxdepth 1 -type l -delete 2>/dev/null || true; rmdir "${lun}" 2>/dev/null || true
            done
            echo "NULL" > "${tpg}/nexus" 2>/dev/null || true; rmdir "${tpg}" 2>/dev/null || true
        done
        rmdir "${wwn_dir}" 2>/dev/null || true
    done
    for bs_idx in $(seq "${FILEIO_START}" $((FILEIO_START + LUN_COUNT - 1))); do
        bs_dir="${core_base}/fileio_${bs_idx}"; [ -d "${bs_dir}" ] || continue
        for lun_dir in "${bs_dir}"/sim*; do
            [ -d "${lun_dir}" ] || continue
            case "$(basename "${lun_dir}")" in *"${INSTANCE_ID}"*) ;; *) continue ;; esac
            echo 0 > "${lun_dir}/enable" 2>/dev/null || true
            find "${lun_dir}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | while read -r sub; do rmdir "${sub}" 2>/dev/null || true; done
            rmdir "${lun_dir}" 2>/dev/null || true
        done
        rmdir "${bs_dir}" 2>/dev/null || true
    done
}
create_luns() {
    log "创建 ${LUN_COUNT} 个 ${LUN_SIZE} LUN（每 LUN node0/node1 双路径）"
    mkdir -p "${LUN_IMG_DIR}"; modprobe target_core_mod 2>/dev/null || true
    modprobe target_core_file 2>/dev/null || true; modprobe tcm_loop 2>/dev/null || true
    ensure_pr_metadata_dir; mkdir -p /sys/kernel/config/target/loopback
    pgrep -x multipathd >/dev/null 2>&1 && log "[WARN] multipathd 正在运行，双路径可能被聚合；请停用或 blacklist"
    local i node wwn wwn_idx tpg_dir found_dev try after_devs before_devs
    local lun_name img_file bs_idx bs_dir lun_dir size_bytes
    local -a new_devs=()
    before_devs="$(ls -d /sys/block/sd* 2>/dev/null | xargs -n1 basename 2>/dev/null | sort || true)"
    for i in $(seq 1 "${LUN_COUNT}"); do
        lun_name="${LUN_PREFIX}${i}_${INSTANCE_ID}"; img_file="${LUN_IMG_DIR}/${lun_name}.img"
        bs_idx=$((FILEIO_START + i - 1)); bs_dir="/sys/kernel/config/target/core/fileio_${bs_idx}"
        lun_dir="${bs_dir}/${lun_name}"; truncate -s "${LUN_SIZE}" "${img_file}"; size_bytes="$(stat -c%s "${img_file}")"
        [ -d "${lun_dir}" ] && { echo 0 > "${lun_dir}/enable" 2>/dev/null || true; rmdir "${lun_dir}" 2>/dev/null || true; }
        mkdir -p "${bs_dir}" "${lun_dir}"
        echo "fd_dev_name=${img_file}" > "${lun_dir}/control"; echo "fd_dev_size=${size_bytes}" > "${lun_dir}/control"
        echo 512 > "${lun_dir}/attrib/block_size"; echo 1 > "${lun_dir}/enable"
        [ "$(cat "${lun_dir}/enable")" = "1" ] || die "backstore enable 失败: ${lun_dir}"
    done
    # 必须“先全部 node0、再全部 node1”，保证 dev_list 前 4/后 4 可直接切分。
    for node in 0 1; do for i in $(seq 1 "${LUN_COUNT}"); do
        lun_name="${LUN_PREFIX}${i}_${INSTANCE_ID}"; bs_idx=$((FILEIO_START + i - 1))
        lun_dir="/sys/kernel/config/target/core/fileio_${bs_idx}/${lun_name}"
        wwn_idx=$((i + node * LUN_COUNT)); wwn="${WWN_BASE}$(printf '%02d' "${wwn_idx}")"
        tpg_dir="/sys/kernel/config/target/loopback/${wwn}/tpgt_1"; mkdir -p "${tpg_dir}"
        printf '%s' "${wwn}" > "${tpg_dir}/nexus"; mkdir -p "${tpg_dir}/lun/lun_0"; ln -sf "${lun_dir}" "${tpg_dir}/lun/lun_0/${lun_name}"
        found_dev=""
        for try in $(seq 1 15); do
            sleep 0.3; after_devs="$(ls -d /sys/block/sd* 2>/dev/null | xargs -n1 basename 2>/dev/null | sort || true)"
            found_dev="$(comm -13 <(echo "${before_devs}") <(echo "${after_devs}") | head -1 || true)"
            [ -n "${found_dev}" ] && [ -b "/dev/${found_dev}" ] && break; found_dev=""
        done
        [ -n "${found_dev}" ] || die "创建 ${lun_name}(node${node}) 后未出现新 SCSI 设备"
        new_devs+=("/dev/${found_dev}"); before_devs="${after_devs}"; log "  ${lun_name} node${node}: /dev/${found_dev}"
    done; done
    printf '%s\n' "${new_devs[@]}" > "${LUN_IMG_DIR}/dev_list.txt"
    log "LUN 创建完成: ${LUN_IMG_DIR}/dev_list.txt"
}
get_lun_devs() { grep -E '^/dev/' "${LUN_IMG_DIR}/dev_list.txt" 2>/dev/null || true; }
# ============================ 宿主机：Docker =================================
build_image() {
    if [ "${FORCE_REBUILD}" != "1" ] && docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
        log "镜像 ${IMAGE_NAME} 已存在，跳过构建"; return
    fi
    local dockerfile="${SCRIPT_DIR}/Dockerfile"
    if [ ! -f "${dockerfile}" ] || [ ! -f "${SCRIPT_DIR}/cluster.sh" ]; then
        mkdir -p "${SIM_BASE}"; dockerfile="${SIM_BASE}/.ograc_sim_Dockerfile"
        log "使用脚本内嵌 Dockerfile"
        if ! printf '%s' "${DOCKERFILE_B64}" | base64 -d | gzip -dc > "${dockerfile}"; then
            die "内嵌 Dockerfile 解码失败"
        fi
    fi
    log "构建镜像 ${IMAGE_NAME}"
    docker build -t "${IMAGE_NAME}" -f "${dockerfile}" "${OGRAC_SRC}" | tail -20
}
start_container() {
    local -a devs=() args=(); local dev sg_dev i
    mapfile -t devs < <(get_lun_devs); [ "${#devs[@]}" -ge 8 ] || die "未找到 8 个 LUN 路径"
    mkdir -p "${DBDATA0_HOST_DIR}" "${DBDATA1_HOST_DIR}" "${INSTALL_HOST_DIR}" "${LUN_IMG_DIR}" \
             "${SIM_BASE}/userhomes/${DEPLOY_USER}" "${SIM_BASE}/userhomes/ograc"
    chmod 711 "/home/${SIM_USER}" 2>/dev/null || true
    chmod 755 "${SIM_ROOT}" "${SIM_BASE}" "${INSTALL_HOST_DIR}" "${DBDATA0_HOST_DIR}" "${DBDATA1_HOST_DIR}" 2>/dev/null || true
    args=(run -d --name "${CONTAINER_NAME}" --privileged --network=host --hostname "${CONTAINER_NAME}" --stop-timeout 30
          -v /home:/home -v "${SIM_BASE}/userhomes/ograc:/home/ograc"
          -v "${SIM_BASE}/userhomes/${DEPLOY_USER}:/home/${DEPLOY_USER}" -v "${OGRAC_SRC}:${OGRAC_SRC}"
          -e OGRAC_IN_CONTAINER=1 -e "OGRAC_DEV_BASE=${SIM_BASE}" -e "SIM_USER=${SIM_USER}" -e "OGRAC_SRC=${OGRAC_SRC}")
    for dev in "${devs[@]}"; do
        args+=(--device "${dev}"); sg_dev="$(sg_map 2>/dev/null | awk -v b="$(basename "${dev}")" 'index($2,b) {print $1; exit}')"
        [ -n "${sg_dev}" ] && args+=(--device "/dev/${sg_dev#/dev/}")
    done
    log "启动容器 ${CONTAINER_NAME}（8 个 LUN 路径）"
    docker "${args[@]}" "${IMAGE_NAME}" bash "${SCRIPT_PATH}" _container_init
    for i in $(seq 1 20); do container_running && break; sleep 1; done
    container_running || die "容器启动失败: ${CONTAINER_NAME}"
    docker exec -e OGRAC_IN_CONTAINER=1 -e "OGRAC_DEV_BASE=${SIM_BASE}" -e "SIM_USER=${SIM_USER}" -e "OGRAC_SRC=${OGRAC_SRC}" \
        "${CONTAINER_NAME}" bash "${SCRIPT_PATH}" _container_prepare
    log "容器已启动；进入: sudo bash $0 enter"
}
ct_start() {
    require_host_root ct-start
    docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}" || die "容器不存在，请先 create"
    docker start "${CONTAINER_NAME}" >/dev/null; log "容器已启动: ${CONTAINER_NAME}"
}
ct_stop() { require_host_root ct-stop; docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true; log "容器已停止"; }
destroy_env() {
    require_host_root destroy
    [ -n "${SIM_ROOT}" ] && [[ "${SIM_ROOT}" == /home/* ]] || die "拒绝清理异常路径: ${SIM_ROOT}"
    if [ "${SIM_BASE}" != "${SIM_ROOT}" ]; then [[ "${SIM_BASE}" == /home/* ]] || die "拒绝清理异常路径: ${SIM_BASE}"; fi
    clean_luns; rm -rf "${SIM_ROOT}"
    [ "${SIM_BASE}" = "${SIM_ROOT}" ] || rm -rf "${SIM_BASE}"
    log "环境已清理: ${SIM_ROOT}"
}
show_env() {
    echo "===== oGRAC 单集群 LUN 环境 ====="; echo "用户: ${SIM_USER}  目录: ${SIM_BASE}"
    echo "容器: ${CONTAINER_NAME}"; echo "端口: CMS ${NODE0_CMS_PORT}/${NODE1_CMS_PORT}, OGRAC ${NODE0_OGRAC_PORT}/${NODE1_OGRAC_PORT}"
    echo "WWN: ${WWN_BASE}01..08  fileio: ${FILEIO_START}..$((FILEIO_START + 3))"
    echo "设备: $(get_lun_devs | tr '\n' ' ')"
    docker ps -a --filter "name=^/${CONTAINER_NAME}$" --format '状态: {{.Status}}' 2>/dev/null || echo "状态: 不存在"
}
create_env() {
    require_host_root create
    if [ -f "${DEV_ENV_FILE}" ] || docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then die "环境已存在，请先 destroy"; fi
    [ "${LUN_COUNT}" = "4" ] || die "精简版固定使用 4 个 LUN"
    mkdir -p "${SIM_ROOT}" "${SIM_BASE}"; clean_luns; write_dev_env
    create_luns; build_image; start_container; log "create 完成"
}
# ============================ 容器：公共辅助 =================================
as_root() { bash -c "$*" 2>&1; }
as_ograc() {
    setpriv --reuid=ograc --regid=ograc --init-groups --inh-caps=+sys_rawio,+sys_admin \
        --ambient-caps=+sys_rawio,+sys_admin -- env HOME=/home/ograc USER=ograc LOGNAME=ograc bash -c "$*" 2>&1
}
as_ograc_bg() {
    setpriv --reuid=ograc --regid=ograc --init-groups --inh-caps=+sys_rawio,+sys_admin \
        --ambient-caps=+sys_rawio,+sys_admin -- env HOME=/home/ograc USER=ograc LOGNAME=ograc \
        setsid bash -c "$*" </dev/null >/dev/null 2>&1 & disown 2>/dev/null || true
}
as_ograc_bg_pid() {
    setpriv --reuid=ograc --regid=ograc --init-groups --inh-caps=+sys_rawio,+sys_admin \
        --ambient-caps=+sys_rawio,+sys_admin -- env HOME=/home/ograc USER=ograc LOGNAME=ograc \
        setsid bash -c "$*" </dev/null >/dev/null 2>&1 & local pid=$!; disown 2>/dev/null || true; echo "${pid}"
}
ensure_deploy_user() {
    groupadd -g 9015 "${DEPLOY_USER}" 2>/dev/null || true
    id -u "${DEPLOY_USER}" >/dev/null 2>&1 || useradd -u 9015 -g 9015 -m -s /bin/bash -d "/home/${DEPLOY_USER}" "${DEPLOY_USER}" 2>/dev/null || true
    mkdir -p "/home/${DEPLOY_USER}" /data; echo -n 'Ograc@12345' > "/home/${DEPLOY_USER}/.sys_pw"
    chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "/home/${DEPLOY_USER}" /data 2>/dev/null || true; chmod 600 "/home/${DEPLOY_USER}/.sys_pw"
}
ensure_ograc_user() {
    groupadd -g 9017 ogracgroup 2>/dev/null || true; groupadd -g 9016 ograc 2>/dev/null || true
    id -u ograc >/dev/null 2>&1 || useradd -u 9016 -g ograc -G ogracgroup,disk -s /bin/bash -d /home/ograc ograc 2>/dev/null || true
    usermod -aG disk ograc 2>/dev/null || true; mkdir -p /home/ograc
    [ -f /home/ograc/.bashrc ] || cp /etc/skel/.bashrc /home/ograc/ 2>/dev/null || touch /home/ograc/.bashrc
    sed -i -E '/DSS_HOME|CMS_HOME|GCC_HOME|OGDB_HOME|OGDB_DATA|ograc1|export (PATH|LD_LIBRARY_PATH)=.*(ogracsim|install\/ograc)/d' \
        /home/ograc/.bashrc "/home/${DEPLOY_USER}/.bashrc" 2>/dev/null || true
    echo -n 'Ograc@12345' > /home/ograc/.sys_pw; chown -R ograc:ograc /home/ograc 2>/dev/null || true; chmod 600 /home/ograc/.sys_pw
    chown -R ograc:ograc "${OGRAC_HOME}/ograc" "${OGRAC_HOME}/cms" "${OGRAC_HOME}/dss" \
        "${OGRAC_HOME1}/ograc" "${OGRAC_HOME1}/cms" "${OGRAC_HOME1}/dss" "${DATA_ROOT}" "${DATA_ROOT1}" 2>/dev/null || true
    chmod 755 "${SIM_BASE}" "${OGRAC_HOME}" "${OGRAC_HOME1}" "${DATA_ROOT}" "${DATA_ROOT1}" 2>/dev/null || true
}
setup_paths() {
    OGRAC_HOME="${SIM_BASE}/install/ograc"; OGRAC_HOME1="${OGRAC_HOME}1"
    DATA_ROOT="${SIM_BASE}/dbdata"; DATA_ROOT1="${SIM_BASE}/dbdata1"; LUN_IMG_DIR="${SIM_BASE}/lundisks"
    DEV_LIST="${LUN_IMG_DIR}/dev_list.txt"; ACTION_DIR="/data/ograc_connector/action"; CONFIG_FILE="config_params_lun.json"
    SYS_PW_FILE="/home/ograc/.sys_pw"; BUILD_DIR="${OGRAC_SRC}/build"; OUTPUT_DIR="${OGRAC_SRC}/output"
    BUILD_TYPE_FILE="${BUILD_DIR}/.ograc_build_type"; LUN_DEVICES=()
}
setup_paths
discover_luns() {
    local -a found=(); local dev
    mapfile -t found < <(grep -E '^/dev/' "${DEV_LIST}" 2>/dev/null || true)
    [ "${#found[@]}" -ge 8 ] || die "LUN 设备不足（需要 8 个）: ${DEV_LIST}"
    LUN_DEVICES=("${found[@]:0:8}"); for dev in "${LUN_DEVICES[@]}"; do [ -b "${dev}" ] || die "LUN 不存在: ${dev}"; done
    log "LUN 设备: ${LUN_DEVICES[*]}"
}
node_lun_devices() { if [ "${1:-0}" = "1" ]; then NODE_LUN_DEVS=("${LUN_DEVICES[@]:4:4}"); else NODE_LUN_DEVS=("${LUN_DEVICES[@]:0:4}"); fi; }
_node_home() { [ "$1" = "0" ] && echo "${OGRAC_HOME}" || echo "${OGRAC_HOME}1"; }
_node_data() { [ "$1" = "0" ] && echo "${DATA_ROOT}" || echo "${DATA_ROOT1}"; }
db_create_done() { grep -qE '"db_create_status"[[:space:]]*:[[:space:]]*"done"' "${1:-}" 2>/dev/null; }
_node_env() {
    local node_id="$1" home data; home="$(_node_home "${node_id}")"; data="$(_node_data "${node_id}")/local/ograc/tmp/data"
    node_lun_devices "${node_id}"
    cat <<EOF
export HOME=/home/ograc USER=ograc LOGNAME=ograc
export DSS_HOME=${home}/dss CMS_HOME=${home}/cms GCC_HOME=${NODE_LUN_DEVS[3]}
export OGDB_HOME=${home}/ograc/server OGDB_DATA=${data}
export PATH=${home}/dss/bin:${home}/cms/service/bin:${home}/ograc/server/bin:\$PATH
export LD_LIBRARY_PATH=${home}/ograc/server/lib:${home}/ograc/server/add-ons:${home}/cms/service/lib:${home}/cms/service/add-ons:${home}/dss/lib:${home}/dss/add-ons:\${LD_LIBRARY_PATH:-}
EOF
}
chmod_luns() {
    local dev base sg_name
    for dev in "${LUN_DEVICES[@]}"; do
        chmod 666 "${dev}" 2>/dev/null || true; base="$(basename "${dev}")"
        sg_name="$(ls "/sys/block/${base}/device/scsi_generic/" 2>/dev/null | head -1)"
        [ -n "${sg_name}" ] && chmod 666 "/dev/${sg_name}" 2>/dev/null || true
    done; chmod 1777 /tmp 2>/dev/null || true
}
clean_shm() {
    as_root "ipcs -m | grep ' ograc ' | awk '{print \$2}' | xargs -r ipcrm -m 2>/dev/null" || true
    as_root "ipcs -s | grep ' ograc ' | awk '{print \$2}' | xargs -r ipcrm -s 2>/dev/null" || true
}
find_third_party() {
    local cand search="${THIRD_PARTY_PATH:-${OGRAC_SRC}}"
    for cand in "${search}" "${search}"/openGauss-third_party_binarylibs* \
                "${search}"/third_party "${search}"/third_party/openGauss-third_party_binarylibs*; do
        [ -x "${cand}/buildtools/gcc10.3/gcc/bin/gcc" ] || continue
        _TP="${cand}"; THIRD_PARTY_PATH="${_TP}"
        GCC_BIN="${_TP}/buildtools/gcc10.3/gcc/bin/gcc"; CMAKE_BIN="${_TP}/buildtools/cmake-3.31.7/bin/cmake"
        return 0
    done
    die "未找到三方库（查找 ${search}）；请放到 ${OGRAC_SRC} 或设置 THIRD_PARTY_PATH"
}
as_deploy() { ensure_deploy_user; runuser -u "${DEPLOY_USER}" -- bash -lc "$*" 2>&1; }
read_build_type() { [ -f "${BUILD_TYPE_FILE}" ] && tr -d '[:space:]' < "${BUILD_TYPE_FILE}" || return 1; }
# ============================ 容器：初始化/编译 ==============================
do_init() {
    ensure_deploy_user; log "安装编译依赖"
    as_root "yum install -y gcc gcc-c++ make cmake git automake autoconf libtool openssl-devel bzip2-devel \
        ncurses-devel python3-devel libaio-devel zlib-devel lz4-devel numactl-devel unixODBC-devel flex bison patch iputils 2>&1 | tail -8"
    find_third_party; mkdir -p "${OGRAC_HOME}/log/deploy" "${OGRAC_HOME}/log/ograc" "${OGRAC_HOME}/log/cms" "${OGRAC_HOME}/log/dss" /data
    chmod 755 /data; chmod 1777 /tmp; log "初始化完成: ${GCC_BIN}"
}
do_make() {
    local build_type="${1:-debug}" mode="full" rc=0
    [ $# -le 2 ] || die "用法: make [debug|release] [inc]"
    case "${2:-}" in ""|inc) ;; *) die "用法: make [debug|release] [inc]" ;; esac
    if [ "${build_type}" = "inc" ]; then build_type="$(read_build_type 2>/dev/null || echo debug)"; mode="inc"; fi
    case "${build_type}" in debug|release) ;; *) die "用法: make [debug|release] [inc]" ;; esac
    [ "${2:-}" = "inc" ] && mode="inc"; [ "${mode}" = "inc" ] && [ ! -f "${BUILD_DIR}/Makefile" ] && mode="full"
    [ "${mode}" = "inc" ] && [ "${build_type}" = "release" ] && die "Release 不支持增量编译，请执行: make release"
    ensure_deploy_user; find_third_party; export THIRD_PARTY_PATH
    export PATH="${_TP}/buildtools/gcc10.3/gcc/bin:${_TP}/buildtools/cmake-3.31.7/bin:${PATH}"
    export LD_LIBRARY_PATH="${_TP}/buildtools/gcc10.3/gcc/lib64:${_TP}/buildtools/gcc10.3/isl/lib:${_TP}/buildtools/gcc10.3/mpc/lib:${_TP}/buildtools/gcc10.3/mpfr/lib:${_TP}/buildtools/gcc10.3/gmp/lib:${LD_LIBRARY_PATH:-}"
    as_root "mkdir -p ${BUILD_DIR} ${OUTPUT_DIR}"; as_root "chown -R ${DEPLOY_USER}:${DEPLOY_USER} ${BUILD_DIR} ${OUTPUT_DIR} 2>/dev/null || true"
    as_root "chmod -R a+rX ${OGRAC_SRC} 2>/dev/null || true"
    command -v setfacl >/dev/null 2>&1 && as_root "setfacl -R -m u:9015:rwX -m d:u:9015:rwX ${OGRAC_SRC} 2>/dev/null || true"
    set +e
    if [ "${mode}" = "inc" ]; then as_deploy "cd ${BUILD_DIR} && make oGRAC ogracd ogsql -j$(nproc)" > /tmp/ograc_make.log 2>&1; else
        as_deploy "cd ${BUILD_DIR} && sh build_ograc.sh ${build_type} --with-dss --third-party-path=${THIRD_PARTY_PATH}" > /tmp/ograc_make.log 2>&1
    fi
    rc=$?; set -e; tail -20 /tmp/ograc_make.log
    [ "${rc}" -eq 0 ] || die "编译失败（rc=${rc}），详见 /tmp/ograc_make.log"
    [ -f "${OUTPUT_DIR}/bin/ogracd" ] || die "编译后未找到 ${OUTPUT_DIR}/bin/ogracd"
    printf '%s\n' "${build_type}" > "${BUILD_TYPE_FILE}"; chown "${DEPLOY_USER}:${DEPLOY_USER}" "${BUILD_TYPE_FILE}" 2>/dev/null || true
    log "编译成功: ${OUTPUT_DIR}/bin/ogracd (${build_type}, ${mode})"
}
# ============================ 容器：配置生成 =================================
gen_config() {
    local node_id="$1" cms dss ograc home data shm
    if [ "${node_id}" = "0" ]; then cms="${NODE0_CMS_PORT}"; dss="${NODE0_DSS_PORT}"; ograc="${NODE0_OGRAC_PORT}"; home="${OGRAC_HOME}"; data="${DATA_ROOT}"; shm="${SHM_KEY}"; else
        cms="${NODE1_CMS_PORT}"; dss="${NODE1_DSS_PORT}"; ograc="${NODE1_OGRAC_PORT}"; home="${OGRAC_HOME1}"; data="${DATA_ROOT1}"; shm="${SHM_KEY1}"; fi
    node_lun_devices "${node_id}"
    cat <<EOF
{"deploy_mode":"dss","node_id":"${node_id}","cms_ip":"127.0.0.1;127.0.0.1","db_type":"1","mes_ssl_switch":false,
 "MAX_ARCH_FILES_SIZE":"300G","redo_num":"$((REDO_NUM / 2))","redo_size":"300M","auto_tune":"0",
 "kernel_parameters":{"DATA_BUFFER_SIZE":"${MEM_DATA_BUFFER}","TEMP_BUFFER_SIZE":"${MEM_TEMP_BUFFER}","SHARED_POOL_SIZE":"${MEM_SHARED_POOL}",
 "_INDEX_BUFFER_SIZE":"${MEM_INDEX_BUFFER}","VARIANT_MEMORY_AREA_SIZE":"${MEM_VARIANT_AREA}","LARGE_POOL_SIZE":"${MEM_LARGE_POOL}",
 "CR_POOL_SIZE":"32M","CR_POOL_COUNT":"2","BUF_POOL_NUM":"1","TEMP_POOL_NUM":"1","SESSIONS":"${MEM_SESSIONS}",
 "OPTIMIZED_WORKER_THREADS":"${MEM_OPT_WORKERS}","MAX_WORKER_THREADS":"${MEM_MAX_WORKERS}"},
 "dss_vg_list":{"vg1":"${NODE_LUN_DEVS[0]}","vg2":"${NODE_LUN_DEVS[1]}","vg3":"${NODE_LUN_DEVS[2]}"},
 "gcc_home":"${NODE_LUN_DEVS[3]}","_SHM_KEY":${shm},"cms_port":"${cms}","dss_port":"${dss}","ograc_port":"${ograc}",
 "interconnect_port":"${NODE0_INTERCONNECT_PORT},${NODE1_INTERCONNECT_PORT}",
 "module_config":{"ograc_home":"${home}","data_root":"${data}","user":"ograc"}}
EOF
}
write_config() {
    local node_id="$1"; mkdir -p "${ACTION_DIR}"; gen_config "${node_id}" > "${ACTION_DIR}/${CONFIG_FILE}"
    chown "${DEPLOY_USER}:${DEPLOY_USER}" "${ACTION_DIR}/${CONFIG_FILE}"; log "已生成 node${node_id} 配置"
}
fix_config() {
    local n home cms dss ograc shm ci di data ini port
    for n in 0 1; do
        home="$(_node_home "${n}")"; data="$(_node_data "${n}")"
        if [ "${n}" = "0" ]; then cms="${NODE0_CMS_PORT}"; dss="${NODE0_DSS_PORT}"; ograc="${NODE0_OGRAC_PORT}"; shm="${SHM_KEY}"; else
            cms="${NODE1_CMS_PORT}"; dss="${NODE1_DSS_PORT}"; ograc="${NODE1_OGRAC_PORT}"; shm="${SHM_KEY1}"; fi
        ci="${home}/cms/cfg/cluster.ini"; [ -f "${ci}" ] && sed -i -e "s/^CMS_PORT\[0\].*/CMS_PORT[0] = ${NODE0_CMS_PORT}/" -e "s/^CMS_PORT\[1\].*/CMS_PORT[1] = ${NODE1_CMS_PORT}/" "${ci}"
        ci="${home}/cms/cfg/cms.ini"; if [ -f "${ci}" ]; then sed -i -e "s/^_PORT.*/_PORT = ${cms}/" -e "s/^_DISK_USAGE_THRESHOLD.*/_DISK_USAGE_THRESHOLD = ${CMS_DISK_THRESHOLD:-95}/" "${ci}"
            grep -q '^_DISK_USAGE_THRESHOLD' "${ci}" || echo "_DISK_USAGE_THRESHOLD = ${CMS_DISK_THRESHOLD:-95}" >> "${ci}"; fi
        di="${home}/dss/cfg/dss_inst.ini"; [ -f "${di}" ] && sed -i -e "s|^DSS_NODES_LIST=.*|DSS_NODES_LIST=0:127.0.0.1:${NODE0_DSS_PORT},1:127.0.0.1:${NODE1_DSS_PORT}|" -e "s|^_SHM_KEY=.*|_SHM_KEY=${shm}|" "${di}"
        ci="${data}/local/ograc/tmp/data/cfg/cluster.ini"; [ -f "${ci}" ] && sed -i -e "s/^CMS_PORT\[0\].*/CMS_PORT[0] = ${NODE0_CMS_PORT}/" -e "s/^CMS_PORT\[1\].*/CMS_PORT[1] = ${NODE1_CMS_PORT}/" -e "s/^LSNR_PORT\[0\].*/LSNR_PORT[0] = ${NODE0_OGRAC_PORT}/" -e "s/^LSNR_PORT\[1\].*/LSNR_PORT[1] = ${NODE1_OGRAC_PORT}/" "${ci}"
        ini="${data}/local/ograc/tmp/data/cfg/ogracd.ini"; [ -f "${ini}" ] || continue
        sed -i -e "s/^INSTANCE_ID.*/INSTANCE_ID = ${n}/" -e "s|^LSNR_ADDR.*|LSNR_ADDR = 0.0.0.0|" -e "s|^LSNR_PORT.*|LSNR_PORT = ${ograc}|" -e "s|^_SHM_KEY.*|_SHM_KEY = ${shm}|" "${ini}"
        sed -i -e "s/^DATA_BUFFER_SIZE.*/DATA_BUFFER_SIZE = ${MEM_DATA_BUFFER}/" \
               -e "s/^TEMP_BUFFER_SIZE.*/TEMP_BUFFER_SIZE = ${MEM_TEMP_BUFFER}/" \
               -e "s/^SHARED_POOL_SIZE.*/SHARED_POOL_SIZE = ${MEM_SHARED_POOL}/" \
               -e "s/^_INDEX_BUFFER_SIZE.*/_INDEX_BUFFER_SIZE = ${MEM_INDEX_BUFFER}/" \
               -e "s/^VARIANT_MEMORY_AREA_SIZE.*/VARIANT_MEMORY_AREA_SIZE = ${MEM_VARIANT_AREA}/" \
               -e "s/^LARGE_POOL_SIZE.*/LARGE_POOL_SIZE = ${MEM_LARGE_POOL}/" \
               -e "s/^SESSIONS.*/SESSIONS = ${MEM_SESSIONS}/" \
               -e "s/^OPTIMIZED_WORKER_THREADS.*/OPTIMIZED_WORKER_THREADS = ${MEM_OPT_WORKERS}/" \
               -e "s/^MAX_WORKER_THREADS.*/MAX_WORKER_THREADS = ${MEM_MAX_WORKERS}/" "${ini}"
        grep -q '^OGRAC_TASK_NUM' "${ini}" && sed -i "s/^OGRAC_TASK_NUM.*/OGRAC_TASK_NUM = ${DTC_TASK_NUM}/" "${ini}" || echo "OGRAC_TASK_NUM = ${DTC_TASK_NUM}" >> "${ini}"
        grep -q '^LOG_REPLAY_PROCESSES' "${ini}" && sed -i "s/^LOG_REPLAY_PROCESSES.*/LOG_REPLAY_PROCESSES = ${RCY_PROC_NUM}/" "${ini}" || echo "LOG_REPLAY_PROCESSES = ${RCY_PROC_NUM}" >> "${ini}"
    done
    python3 - "${OGRAC_HOME}/ograc/cfg/ograc_config.json" "${OGRAC_HOME1}/ograc/cfg/ograc_config.json" \
        "${NODE0_CMS_PORT}" "${NODE1_CMS_PORT}" "${NODE0_OGRAC_PORT}" "${NODE1_OGRAC_PORT}" <<'PY' 2>/dev/null || true
import json, os, sys
for p in sys.argv[1:3]:
    if not os.path.isfile(p): continue
    d = json.load(open(p)); d.update({"CMS_PORT[0]": sys.argv[3], "CMS_PORT[1]": sys.argv[4], "LSNR_PORT[0]": sys.argv[5], "LSNR_PORT[1]": sys.argv[6]}); json.dump(d, open(p, "w"))
PY
    log "双节点端口配置已校正"
}
# ============================ 容器：安装/修复 ================================
disable_dss_check() {
    python3 - "$1" <<'PY'
import re, sys
p=sys.argv[1]; t=open(p).read(); t2,n=re.subn(r'function check_dss\(\)\s*\{.*?\n\}', 'function check_dss()\n{\n    # SIM_DSS_CHECK_DISABLED\n    return 0\n}', t, count=1, flags=re.S)
if n != 1: raise SystemExit(1)
open(p,'w').write(t2)
PY
}
patch_dss_iofence() {
    local src="" f
    for f in "${OGRAC_HOME}/action/dss/dss_contrl.sh" "${ACTION_DIR}/dss/dss_contrl.sh"; do [ -f "${f}" ] && { src="${f}"; break; }; done
    for f in "${OGRAC_HOME}/dss/dss_contrl.sh" "${OGRAC_HOME1}/dss/dss_contrl.sh"; do
        [ -f "${f}" ] || continue; [ -n "${src}" ] && cp -f "${src}" "${f}"
        sed -i 's@^source ~/.bashrc@[ -r "${HOME}/.bashrc" ] \&\& source "${HOME}/.bashrc" || true  # SIM_BASHRC@' "${f}" 2>/dev/null || true
        chown ograc:ograc "${f}" 2>/dev/null || true; chmod 700 "${f}" 2>/dev/null || true; disable_dss_check "${f}" || return 1
    done
}
patch_connector() {
    python3 - <<'PY'
from pathlib import Path
import ast, re
A=Path("/data/ograc_connector/action")
def rd(p): return (A/p).read_text()
def wr(p,t): (A/p).write_text(t)
t=rd("cms/cms_ctl.py")
if 'OGRAC_RUNNING_MODE' not in t:
    t=t.replace('self.running_mode = "ogracd_in_cluster"', 'self.running_mode = os.environ.get("OGRAC_RUNNING_MODE", "ogracd_in_cluster")', 1)
    t=t.replace('"CMS_PORT[1]": self.port,', '"CMS_PORT[1]": str(int(self.port) + 1),', 1); wr("cms/cms_ctl.py",t)
t=rd("dss/dss_ctl.py")
if 'VG_CONFIG.clear()' not in t:
    t=t.replace('        if dss_vg_list:\n            for vg_name, vg_path in dss_vg_list.items():', '        VG_CONFIG.clear()\n        if dss_vg_list:\n            for vg_name, vg_path in dss_vg_list.items():', 1); wr("dss/dss_ctl.py",t)
t=rd("cms/cms_deploy.py")
if 'SIM_SKIP_SETCAP' not in t:
    t=t.replace('    def _patch_cms_rpath(self):\n', '    def _patch_cms_rpath(self):\n        return  # SIM_SKIP_SETCAP\n', 1)
    t=re.sub(r'^(\s*)run_cmd\(f\'setcap CAP_SYS_RAWIO\+ep .*?\n', r'\1# SIM_SKIP_SETCAP: setpriv ambient caps\n\1pass\n', t, flags=re.M); wr("cms/cms_deploy.py",t)
t=rd("ograc/ograc_ctl.py")
if 'SIM_FIX_OGENCRYPT' not in t:
    new='''    # SIM_FIX_OGENCRYPT: feed password directly to ogencrypt
    env = os.environ.copy(); lib = os.path.join(install_path, "lib")
    env["LD_LIBRARY_PATH"] = lib + ((":" + env["LD_LIBRARY_PATH"]) if env.get("LD_LIBRARY_PATH") else "")
    proc = subprocess.Popen([ogencrypt_bin, "-e", "PBKDF2"], shell=False, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    pw = plain_password.encode(); sep = os.linesep.encode()
    try:
        out_b, err_b = proc.communicate(pw + sep + pw + sep, timeout=60)'''
    t,n=re.subn(r'(?s)    cmd = f"source ~/.bashrc && \{ogencrypt_bin\} -e PBKDF2".*?out_b, err_b = proc\.communicate\(timeout=60\)', new, t, count=1)
    if n != 1: raise SystemExit("ogencrypt patch failed")
    wr("ograc/ograc_ctl.py",t)
t=rd("ograc_deploy.py")
if 'SIM_REUSE_SYSPW' not in t:
    old=r'(?s)        sys_password_file = None\n        if "ograc" in INSTALL_ORDER and sys\.stdin\.isatty\(\):.*?os\.environ\["OGRAC_SYS_PASSWORD_FILE"\] = sys_password_file'
    new='''        sys_password_file = None  # SIM_REUSE_SYSPW
        _env_pw = os.environ.get("OGRAC_SYS_PASSWORD_FILE")
        if "ograc" in INSTALL_ORDER:
            if _env_pw and os.path.isfile(_env_pw): pass
            elif sys.stdin.isatty(): sys_password_file = self._prompt_sys_password_and_write_file()
            else: raise RuntimeError("OGRAC_SYS_PASSWORD_FILE not set and stdin is not a tty")
            if sys_password_file: os.environ["OGRAC_SYS_PASSWORD_FILE"] = sys_password_file'''
    t,n=re.subn(old,new,t,count=1)
    if n != 1: raise SystemExit("syspw patch failed")
    wr("ograc_deploy.py",t)
t=rd("pre_install.py")
if 'SIM_SKIP_CHECKDISK' not in t:
    t=t.replace('return self.get_disk_available() >= NEEDED_SIZE', 'return True  # SIM_SKIP_CHECKDISK', 1)
if 'SIM_REDO_SIZE_M' not in t:
    t=t.replace('''        if not value.endswith("G"):
            return False
        try:
            return int(value.strip("G")) > 0''','''        try:  # SIM_REDO_SIZE_M
            if value.endswith("G"): return int(value.strip("G")) > 0
            if value.endswith("M"): return int(value.strip("M")) > 0
            return False''',1)
if 'SIM_SKIP_CHECKDISK' not in t or 'SIM_REDO_SIZE_M' not in t: raise SystemExit("pre_install patch failed")
wr("pre_install.py",t); print("connector patches applied")
for p in ("cms/cms_ctl.py","dss/dss_ctl.py","cms/cms_deploy.py","ograc/ograc_ctl.py","ograc_deploy.py","pre_install.py"):
    ast.parse(rd(p))
for p,m in (("cms/cms_ctl.py","OGRAC_RUNNING_MODE"),("dss/dss_ctl.py","VG_CONFIG.clear()"),("cms/cms_deploy.py","SIM_SKIP_SETCAP")):
    if m not in rd(p): raise SystemExit(f"patch missing: {p}")
PY
}
select_package() {
    local build_type="${1:-}" candidates=()
    [ -n "${build_type}" ] || build_type="$(read_build_type 2>/dev/null || true)"
    if [ -n "${build_type}" ]; then
        case "${build_type}" in
            debug) mapfile -d '' candidates < <(find "${OGRAC_SRC}/package" -maxdepth 1 -type f -name 'oGRAC-*-debug-*.tgz' ! -name '*symbols*' -print0 2>/dev/null | sort -z) ;;
            release) mapfile -d '' candidates < <(find "${OGRAC_SRC}/package" -maxdepth 1 -type f -name 'oGRAC-*.tgz' ! -name '*-debug-*' ! -name '*symbols*' -print0 2>/dev/null | sort -z) ;;
            *) die "install 类型必须是 debug 或 release: ${build_type}" ;;
        esac
        [ "${#candidates[@]}" -gt 0 ] || die "未找到 ${build_type} 部署包，请先 make ${build_type}"
    else
        mapfile -d '' candidates < <(find "${OGRAC_SRC}/package" -maxdepth 1 -type f -name 'oGRAC-*.tgz' ! -name '*symbols*' -print0 2>/dev/null | sort -z)
        [ "${#candidates[@]}" -eq 1 ] || die "package/ 中存在 0 个或多个包，请执行 install debug|release"
        build_type=release; [[ "$(basename "${candidates[0]}")" == *-debug-* ]] && build_type=debug
    fi
    [ "${#candidates[@]}" -eq 1 ] || die "${build_type} 部署包不唯一，请清理旧包"
    SELECTED_PACKAGE="${candidates[0]}"; SELECTED_BUILD_TYPE="${build_type}"
}
run_appctl() {
    local action="$1" log_file="$2"
    bash -c "export OGRAC_SYS_PASSWORD_FILE=${SYS_PW_FILE} OGRAC_RUNNING_MODE=ogracd_in_cluster; cd ${ACTION_DIR} && sh appctl.sh ${action} ${CONFIG_FILE}" >"${log_file}" 2>&1 || { tail -30 "${log_file}" | sed 's/^/    /'; return 1; }
    tail -12 "${log_file}" | sed 's/^/    /'; ! grep -qE "${action} failed|=== ${action} failed" "${log_file}"
}
cluster_script_source() {
    local src="${SCRIPT_DIR}/cluster.sh" out="${SIM_BASE}/.ograc_sim_cluster.sh" tmp="${SIM_BASE}/.ograc_sim_cluster.sh.tmp.$$"
    if [ -f "${src}" ]; then printf '%s\n' "${src}"; return 0; fi
    mkdir -p "${SIM_BASE}"
    if ! printf '%s' "${CLUSTER_SH_B64}" | base64 -d | gzip -dc > "${tmp}"; then
        rm -f "${tmp}"; err "内嵌 cluster.sh 解码失败"; return 1
    fi
    chmod 600 "${tmp}"; mv -f "${tmp}" "${out}" || { rm -f "${tmp}"; return 1; }
    printf '%s\n' "${out}"
}
sync_cluster_script() {
    local dest src; dest="$(_node_home "$1")/cms/service/bin/cluster.sh"; [ -d "$(dirname "${dest}")" ] || return 0
    src="$(cluster_script_source)" || return 1
    install -o ograc -g ograc -m 500 "${src}" "${dest}"
}
ensure_pr_keys() {
    local i dev; [ "${#LUN_DEVICES[@]}" -ge 8 ] || return 0
    for i in 0 1 2; do sg_persist -d "${LUN_DEVICES[$i]}" --out --register --param-sark=0x1 >/dev/null 2>&1 || true; done
    for i in 4 5 6; do sg_persist -d "${LUN_DEVICES[$i]}" --out --register --param-sark=0x2 >/dev/null 2>&1 || true; done
}
clear_pr_keys() {
    local i dev
    for i in 0 1 2 3; do dev="${LUN_DEVICES[$i]}"; sg_persist -d "${dev}" --out --release --param-rk=0x1 >/dev/null 2>&1 || true; sg_persist -d "${dev}" --out --register --param-rk=0x1 --param-sark=0 >/dev/null 2>&1 || true; done
    for i in 4 5 6 7; do dev="${LUN_DEVICES[$i]}"; sg_persist -d "${dev}" --out --register --param-rk=0x2 --param-sark=0 >/dev/null 2>&1 || true; done
}
reset_gcc() {
    local cms="${OGRAC_HOME}/cms/service/bin/cms" env0; [ -f "${cms}" ] || return 0; chmod 666 "${LUN_DEVICES[3]}" 2>/dev/null || true
    dd if=/dev/zero of="${LUN_DEVICES[3]}" bs=1M count=200 status=none 2>/dev/null || true; env0="$(_node_env 0)"
    as_ograc "${env0}; ${cms} gcc -reset -f" >/dev/null 2>&1 || true
    as_ograc "${env0}; ${cms} node -add 0 node0 127.0.0.1 ${NODE0_CMS_PORT}" >/dev/null 2>&1 || true
    as_ograc "${env0}; ${cms} node -add 1 node1 127.0.0.1 ${NODE1_CMS_PORT}" >/dev/null 2>&1 || true
    as_ograc "${env0}; ${cms} res -add db -type db -attr \"script=${OGRAC_HOME}/cms/service/bin/cluster.sh\"" >/dev/null 2>&1 || true
    as_ograc "${env0}; ${cms} res -add dss -type dss -attr \"script=${OGRAC_HOME}/dss/dss_contrl.sh\"" >/dev/null 2>&1 || true
}
post_install_fixup() {
    local cms="${OGRAC_HOME}/cms/service/bin/cms" env0; [ -f "${cms}" ] || return 0; patch_dss_iofence || return 1
    chmod 666 "${LUN_DEVICES[3]}" 2>/dev/null || true; env0="$(_node_env 0)"
    as_ograc "${env0}; ${cms} gcc -reset -f" >/dev/null 2>&1 || true
    as_ograc "${env0}; ${cms} node -add 0 node0 127.0.0.1 ${NODE0_CMS_PORT}" >/dev/null 2>&1 || true
    as_ograc "${env0}; ${cms} node -add 1 node1 127.0.0.1 ${NODE1_CMS_PORT}" >/dev/null 2>&1 || true
    as_ograc "${env0}; ${cms} res -add db -type db -attr \"script=${OGRAC_HOME}/cms/service/bin/cluster.sh\"" >/dev/null 2>&1 || true
    as_ograc "${env0}; ${cms} res -add dss -type dss -attr \"script=${OGRAC_HOME}/dss/dss_contrl.sh\"" >/dev/null 2>&1 || true; log "GCC/DSS 修复完成"
}
do_install() {
    [ $# -le 1 ] || die "用法: install [debug|release]"; select_package "${1:-}"
    local pkg="${SELECTED_PACKAGE}" n home; log "选择 ${SELECTED_BUILD_TYPE} 包: ${pkg}"
    do_stop silent || true; pkill -KILL -u ograc 2>/dev/null || true; clean_shm; rm -rf /tmp/ograc_deploy_lock_ograc
    clear_pr_keys; for dev in "${LUN_DEVICES[@]}"; do dd if=/dev/zero of="${dev}" bs=1M count=10 conv=notrunc 2>/dev/null || true; done
    rm -rf /data/ograc_connector; mkdir -p /data; tar -xf "${pkg}" -C /data; chown -R "${DEPLOY_USER}:${DEPLOY_USER}" /data/ograc_connector; chmod -R a+rX /data/ograc_connector
    [ -f "${ACTION_DIR}/appctl.sh" ] || die "部署包缺少 ${ACTION_DIR}/appctl.sh"; patch_connector || die "connector patch 失败"
    ensure_ograc_user; ensure_pr_keys
    rm -rf "${OGRAC_HOME}/ograc"/* "${OGRAC_HOME}/cms"/* "${OGRAC_HOME}/dss"/* "${OGRAC_HOME1}/ograc"/* \
        "${OGRAC_HOME1}/cms"/* "${OGRAC_HOME1}/dss"/* "${DATA_ROOT}"/* "${DATA_ROOT1}"/* 2>/dev/null || true
    sed -i '/CMS_HOME\|DSS_HOME\|GCC_HOME\|ograc.*server.*PATH\|ograc.*server.*LD_LIBRARY/d' /home/ograc/.bashrc 2>/dev/null || true
    mkdir -p "${DATA_ROOT}/local" "${DATA_ROOT1}/local" "${OGRAC_HOME}/log" "${OGRAC_HOME1}/log"; chown -R ograc:ograc "${DATA_ROOT}" "${DATA_ROOT1}" 2>/dev/null || true; chmod 1777 /tmp
    for n in 0 1; do
        home="$(_node_home "${n}")"; mkdir -p "${home}/log/deploy" "${home}/log/ograc" "${home}/log/cms" "${home}/log/dss"
        if [ "${n}" = "1" ]; then [ -d "${OGRAC_HOME}/image" ] && cp -al "${OGRAC_HOME}/image" "${OGRAC_HOME1}/image" 2>/dev/null || true
            [ -d "${OGRAC_HOME}/repo" ] && cp -al "${OGRAC_HOME}/repo" "${OGRAC_HOME1}/repo" 2>/dev/null || true
            sed -i '/CMS_HOME\|DSS_HOME\|GCC_HOME\|ograc.*server.*PATH\|ograc.*server.*LD_LIBRARY/d' /home/ograc/.bashrc 2>/dev/null || true; fi
        write_config "${n}"; log "部署 node${n}"
        run_appctl pre_install "/tmp/ograc_${n}.pre.log" || die "node${n} pre_install 失败"
        run_appctl install "/tmp/ograc_${n}.install.log" || die "node${n} install 失败"; sync_cluster_script "${n}"
    done
    fix_config; post_install_fixup; ensure_ograc_user; chmod_luns; log "安装完成，下一步: start"
}
# ============================ 容器：启停 =====================================
_dss_running() { pgrep -u ograc -f "dssserver -D $1" >/dev/null 2>&1; }
_dss_ready() {
    timeout 8 setpriv --reuid=ograc --regid=ograc --init-groups --inh-caps=+sys_rawio,+sys_admin \
        --ambient-caps=+sys_rawio,+sys_admin -- env HOME=/home/ograc USER=ograc LOGNAME=ograc \
        bash -c "$1; exec $2/bin/dsscmd lsvg" 2>/dev/null | grep -qi 'vg_name'
}
_dss_clean_stale() { as_ograc "$1; rm -f $2/dss.lck $2/dss_vg.lck $2/process/dss.process $2/.dss_unix_d_socket" 2>/dev/null || true; }
_start_dss() {
    local node_id="$1" defer="${2:-0}" home dss_home dss_bin env_setup attempt pid i ok reghl_ok rtry
    home="$(_node_home "${node_id}")"; dss_home="${home}/dss"; dss_bin="${dss_home}/bin/dssserver"; env_setup="$(_node_env "${node_id}")"
    [ -f "${dss_bin}" ] || { err "node${node_id} DSS 未安装"; return 1; }; chmod_luns
    _dss_running "${dss_home}" && _dss_ready "${env_setup}" "${dss_home}" && { log "node${node_id} DSS 已在运行"; return 0; }
    _dss_running "${dss_home}" && { pkill -TERM -u ograc -f "dssserver -D ${dss_home}" 2>/dev/null || true; sleep 2; }
    _dss_clean_stale "${env_setup}" "${dss_home}"
    for attempt in 1 2 3; do
        reghl_ok=false
        for rtry in 1 2 3; do
            as_ograc "${env_setup}; ${dss_home}/bin/dsscmd unreghl -D ${dss_home} >/dev/null 2>&1; ${dss_home}/bin/dsscmd reghl -D ${dss_home} >/dev/null 2>&1" && { reghl_ok=true; break; }; sleep 2
        done
        [ "${reghl_ok}" = "true" ] || { err "node${node_id} DSS reghl 失败"; return 1; }
        pid="$(as_ograc_bg_pid "${env_setup}; exec ${dss_bin} -D ${dss_home} >> ${home}/log/dss/dss.log 2>&1")"; ok=0
        for i in $(seq 1 15); do
            sleep 1; kill -0 "${pid}" 2>/dev/null || break
            if [ "${defer}" = "defer" ]; then ok=1; break; fi
            _dss_ready "${env_setup}" "${dss_home}" && { ok=1; break; }
        done
        [ "${ok}" = "1" ] && { log "node${node_id} DSS 启动成功"; return 0; }; kill -9 "${pid}" 2>/dev/null || true; clean_shm; _dss_clean_stale "${env_setup}" "${dss_home}"
    done
    err "node${node_id} DSS 启动失败"; return 1
}
_start_cms() {
    local node_id="$1" home cms port env_setup i; home="$(_node_home "${node_id}")"; cms="${home}/cms/service/bin/cms"; env_setup="$(_node_env "${node_id}")"
    port="$([ "${node_id}" = "0" ] && echo "${NODE0_CMS_PORT}" || echo "${NODE1_CMS_PORT}")"
    pgrep -u ograc -f "${cms} server -start" >/dev/null 2>&1 && { log "node${node_id} CMS 已在运行"; return 0; }
    [ -f "${cms}" ] || { err "node${node_id} CMS 未安装"; return 1; }; mkdir -p "${home}/log/cms"; touch "${home}/log/cms/CmsStatus.log"
    chown -R ograc:ograc "${home}/log/cms" 2>/dev/null || true; chmod +x "${home}/action/cms/cms_daemon.py" 2>/dev/null || true
    as_ograc_bg "${env_setup}; exec ${cms} server -start >> ${home}/log/cms/CmsStatus.log 2>&1"
    for i in $(seq 1 10); do ss -tln 2>/dev/null | grep -q ":${port} " && { log "node${node_id} CMS 启动成功 (${port})"; return 0; }; sleep 1; done
    err "node${node_id} CMS 未监听 ${port}"; return 1
}
_start_ogracd() {
    local node_id="$1" mode="${2:-open}" home data env_setup ogracd port status_file
    home="$(_node_home "${node_id}")"; data="$(_node_data "${node_id}")/local/ograc/tmp/data"; env_setup="$(_node_env "${node_id}")"
    ogracd="${home}/ograc/server/bin/ogracd"; port="$([ "${node_id}" = "0" ] && echo "${NODE0_OGRAC_PORT}" || echo "${NODE1_OGRAC_PORT}")"
    [ -f "${ogracd}" ] || { err "node${node_id} ogracd 未安装"; return 1; }
    ss -tln 2>/dev/null | grep -q ":${port} " && { log "node${node_id} ogracd 已在监听"; return 0; }
    mkdir -p "${home}/log/ograc/run" "${data}"; chown -R ograc:ograc "${home}/log/ograc" "${data}" 2>/dev/null || true
    status_file="${home}/ograc/cfg/start_status.json"; mkdir -p "$(dirname "${status_file}")"
    if [ "${mode}" = "create" ]; then echo '{"start_status": "default", "db_create_status": "default", "ever_started": false}' > "${status_file}"; else
        echo '{"start_status": "started", "db_create_status": "done", "ever_started": true}' > "${status_file}"; fi; chown ograc:ograc "${status_file}"
    log "node${node_id} 启动 ogracd (${mode})"
    if [ "${mode}" = "create" ]; then
        chmod u+w "${home}/ograc/server/admin/scripts/"*.sql 2>/dev/null || true
        as_ograc_bg "${env_setup}; export OGRAC_SYS_PASSWORD_FILE=${SYS_PW_FILE} OGRAC_RUNNING_MODE=ogracd_in_cluster; cd ${home}/action/ograc && exec python3 ograc_ctl.py start >> ${home}/log/ograc/run/ogracd.rlog 2>&1"; else
        as_ograc_bg "${env_setup}; exec ${ogracd} open -D ${data} >> ${home}/log/ograc/run/ogracd.rlog 2>&1"
        for i in $(seq 1 30); do
            ss -tln 2>/dev/null | grep -q ":${port} " && { log "node${node_id} ogracd 已监听 ${port}"; return 0; }
            pgrep -u ograc -f "ogracd.*-D ${data}" >/dev/null 2>&1 || { err "node${node_id} ogracd 启动后退出了"; tail -5 "${home}/log/ograc/run/ogracd.rlog" 2>/dev/null | sed 's/^/    /'; return 1; }
            sleep 1
        done
        err "node${node_id} ogracd 未监听 ${port}"; return 1
    fi
}
wait_cms_ready() {
    local env0 i; env0="$(_node_env 0)"
    for i in $(seq 1 30); do as_ograc "${env0}; cms stat -server $1 2>/dev/null" 2>/dev/null | grep -q TRUE && return 0; sleep 2; done; return 1
}
wait_node0_open() {
    local first="$1" env0 status_file rlog dbst i res created=false; env0="$(_node_env 0)"; status_file="${OGRAC_HOME}/ograc/cfg/start_status.json"; rlog="${OGRAC_HOME}/log/ograc/run/ogracd.rlog"
    if [ "${first}" = "1" ]; then
        log "等待首次建库完成（最长 30 分钟，DATA_BUFFER=${MEM_DATA_BUFFER}）"
        for i in $(seq 1 900); do
            if db_create_done "${status_file}" && grep -q 'successfully alter database OPEN' "${rlog}" 2>/dev/null; then
                dbst="$(as_ograc "${env0}; printf 'SELECT OPEN_STATUS FROM DV_DATABASE;\\n' | ogsql / as sysdba -q -D ${DATA_ROOT}/local/ograc/tmp/data" 2>/dev/null || true)"
                echo "${dbst}" | grep -q 'READ WRITE' && { created=true; break; }
            fi
            if ! pgrep -u ograc -f "ogracd.*-D ${DATA_ROOT}|ograc_ctl.py start|installdb.sh" >/dev/null 2>&1; then
                if db_create_done "${status_file}" && grep -q 'successfully alter database OPEN' "${rlog}" 2>/dev/null; then
                    created=true; break
                fi
                err "node0 建库进程异常退出"; tail -30 "${rlog}" | sed 's/^/    /'; return 1
            fi
            [ $((i % 30)) -eq 0 ] && log "  建库中... $((i / 2))s（$(tail -1 "${rlog}" 2>/dev/null | cut -c1-110)）"
            sleep 2
        done
        [ "${created}" = "true" ] || { err "node0 建库超时"; return 1; }
    fi
    log "等待 node0 OPEN 并加入集群 (WORK_STAT=1)"
    for i in $(seq 1 120); do
        res="$(as_ograc "${env0}; cms stat -res db 2>/dev/null" || true)"
        echo "${res}" | awk '$1==0 && $2=="db" && $3=="ONLINE" && $6==1 {f=1} END{exit !f}' && { log "node0 已 OPEN 并加入集群"; return 0; }
        if ! pgrep -u ograc -f "ogracd.*-D ${DATA_ROOT}" >/dev/null 2>&1; then
            err "node0 ogracd 在等待入盟时退出"; tail -20 "${rlog}" | sed 's/^/    /'; return 1
        fi
        sleep 2
    done
    err "node0 未在 240s 内完成 OPEN/入盟"; return 1
}
ensure_gcc_nodes() {
    local cms="${OGRAC_HOME}/cms/service/bin/cms" env0 nodes add_out; [ -f "${cms}" ] || return 0; chmod 666 "${LUN_DEVICES[3]}" 2>/dev/null || true; env0="$(_node_env 0)"
    nodes="$(as_ograc "${env0}; ${cms} node -list 2>/dev/null" || true)"
    echo "${nodes}" | grep -qE '^[[:space:]]*0[[:space:]]' || add_out="$(as_ograc "${env0}; ${cms} node -add 0 node0 127.0.0.1 ${NODE0_CMS_PORT} 2>&1" || true)"
    echo "${nodes}" | grep -qE '^[[:space:]]*1[[:space:]]' || add_out="$(as_ograc "${env0}; ${cms} node -add 1 node1 127.0.0.1 ${NODE1_CMS_PORT} 2>&1" || true)"
    case "${add_out:-}" in *disk_lock*|*"lock gcc"*|*"add node failed"*) reset_gcc; return 0 ;; esac
    as_ograc "${env0}; ${cms} res -add db -type db -attr \"script=${OGRAC_HOME}/cms/service/bin/cluster.sh\"" >/dev/null 2>&1 || true
    as_ograc "${env0}; ${cms} res -add dss -type dss -attr \"script=${OGRAC_HOME}/dss/dss_contrl.sh\"" >/dev/null 2>&1 || true
}
_ensure_dss1_ready() {
    local env1="${OGRAC_HOME1}" i round; env1="$(_node_env 1)"
    for round in 1 2; do
        _dss_ready "${env1}" "${OGRAC_HOME1}/dss" && { log "node1 DSS 已就绪"; return 0; }
        log "node1 DSS 第 ${round} 轮未就绪，重启 node1 CMS/DSS"; _ograc_signal_node 1 TERM || true; sleep 3
        _dss_clean_stale "${env1}" "${OGRAC_HOME1}/dss"; _start_cms 1 || true; sleep 3
        wait_cms_ready 1 || log "[WARN] node1 CMS 重启后未 READY"
        as_ograc "${env1}; ${OGRAC_HOME1}/dss/bin/dsscmd unreghl -D ${OGRAC_HOME1}/dss >/dev/null 2>&1 || true; ${OGRAC_HOME1}/dss/bin/dsscmd reghl -D ${OGRAC_HOME1}/dss >/dev/null 2>&1 || true"
        _start_dss 1 || return 1
        for i in $(seq 1 12); do _dss_ready "${env1}" "${OGRAC_HOME1}/dss" && { log "node1 DSS 已就绪"; return 0; }; sleep 5; done
    done; err "node1 DSS 未完成 join"; return 1
}
do_start() {
    local first=1; ensure_ograc_user; chmod_luns; rm -rf /tmp/ograc_deploy_lock_ograc
    mkdir -p "${DATA_ROOT}/local" "${DATA_ROOT1}/local"; chown -R ograc:ograc "${DATA_ROOT}" "${DATA_ROOT1}" 2>/dev/null || true
    fix_config
    if [ -f "${OUTPUT_DIR}/bin/ogracd" ]; then do_deploy; else log "未发现 output 产物，使用 package 内二进制"; fi
    patch_dss_iofence
    db_create_done "${OGRAC_HOME}/ograc/cfg/start_status.json" && first=0
    if [ -f "${OGRAC_HOME}/cms/service/bin/cms" ]; then
        if [ "${first}" = "0" ] && ! ograc_procs_alive; then
            log "清理上次运行残留的 CMS/GCC 状态"
            reset_gcc
        fi
        ensure_gcc_nodes
    fi
    log "启动 node0"; _start_dss 0 || return 1; _start_cms 0 || return 1; wait_cms_ready 0 || log "[WARN] CMS node0 未 READY"
    if [ "${first}" = "1" ]; then _start_ogracd 0 create || return 1; else _start_ogracd 0 open || return 1; fi
    wait_node0_open "${first}" || return 1; log "启动 node1"; _start_dss 1 defer || log "[WARN] node1 DSS 暂未就绪"
    _start_cms 1 || return 1; sleep 3; wait_cms_ready 1 || log "[WARN] CMS node1 未 READY"
    _ensure_dss1_ready || return 1; sleep 2; wait_cms_ready 1 || log "[WARN] CMS node1 未 READY"
    _start_ogracd 1 open || { log "[WARN] node1 ogracd 首次启动失败，整轮重试"; _ensure_dss1_ready || return 1; sleep 2; _start_ogracd 1 open || return 1; }
    log "启动完成；执行 status 或 verify"
}
ograc_procs_alive() {
    local p state; for p in $(pgrep -u ograc -f "ogracd|ograc_ctl|installdb|cms server|dssserver" 2>/dev/null || true); do
        state=$(awk '{print $3}' "/proc/${p}/stat" 2>/dev/null || echo Z); [ "${state}" = "Z" ] || return 0; done; return 1
}
_ograc_signal() {
    local sig="$1" p pgid; for p in $(pgrep -u ograc -f "ogracd|ograc_ctl|installdb|cms server|dssserver" 2>/dev/null || true); do
        pgid=$(awk '{print $5}' "/proc/${p}/stat" 2>/dev/null || true); [ -n "${pgid}" ] && kill "-${sig}" -- "-${pgid}" 2>/dev/null || true; kill "-${sig}" "${p}" 2>/dev/null || true; done
}
_ograc_signal_node() {
    local home p exe cwd pgid; home="$(_node_home "$1")"
    for p in $(pgrep -u ograc -f "ogracd|ograc_ctl|installdb|cms server|dssserver" 2>/dev/null || true); do
        exe=$(readlink -f "/proc/${p}/exe" 2>/dev/null || true); cwd=$(readlink -f "/proc/${p}/cwd" 2>/dev/null || true)
        case "${exe}${cwd}" in *"${home}"*) pgid=$(awk '{print $5}' "/proc/${p}/stat" 2>/dev/null || true); [ -n "${pgid}" ] && kill "-$2" -- "-${pgid}" 2>/dev/null || true; kill "-$2" "${p}" 2>/dev/null || true ;; esac
    done
}
do_stop() {
    local silent="${1:-}" i; [ "${silent}" = "silent" ] && exec 3>&1 >/dev/null 2>&1; log "停止 oGRAC 双节点"; _ograc_signal TERM
    for i in $(seq 1 15); do ograc_procs_alive || break; sleep 1; done; ograc_procs_alive && { _ograc_signal KILL; sleep 2; }
    clean_shm; rm -rf /tmp/ograc_deploy_lock_ograc 2>/dev/null || true; log "停止完成"; [ "${silent}" = "silent" ] && exec 1>&3 2>&1 3>&- 2>/dev/null || true
}
# ============================ 容器：部署/验证 ===============================
sync_ogsql() {
    local src="${OUTPUT_DIR}/bin/ogsql" bin_dir tmp; [ -f "${src}" ] || return 0; bin_dir="$(_node_home "$1")/ograc/server/bin"; [ -d "${bin_dir}" ] || return 0
    tmp="${bin_dir}/.ogsql.tmp.$$"; cp -f -p "${src}" "${tmp}"; chown ograc:ograc "${tmp}"; chmod 750 "${tmp}"; mv -f "${tmp}" "${bin_dir}/ogsql"
}
do_deploy() {
    local src="${OUTPUT_DIR}/bin/ogracd" n home bin_dir lib_dir tmp so base cms_src
    [ -f "${src}" ] || die "未找到 ${src}，请先 make"; cms_src="${OUTPUT_DIR}/bin/cms"
    for n in 0 1; do home="$(_node_home "${n}")"; bin_dir="${home}/ograc/server/bin"; lib_dir="${home}/ograc/server/lib"; [ -d "${bin_dir}" ] || continue
        tmp="${bin_dir}/.ogracd.tmp.$$"; cp -f -p "${src}" "${tmp}"; chown ograc:ograc "${tmp}"; chmod 750 "${tmp}"; mv -f "${tmp}" "${bin_dir}/ogracd"; sync_ogsql "${n}"
        for so in "${OUTPUT_DIR}"/lib/*.so; do [ -f "${so}" ] || continue; base="$(basename "${so}")"; [ -f "${lib_dir}/${base}" ] || continue
            tmp="${lib_dir}/.${base}.tmp.$$"; cp -f -p "${so}" "${tmp}"; chown ograc:ograc "${tmp}"; chmod 750 "${tmp}"; mv -f "${tmp}" "${lib_dir}/${base}"; done
        if [ -f "${cms_src}" ] && [ -d "${home}/cms/service/bin" ]; then
            tmp="${home}/cms/service/bin/.cms.tmp.$$"; cp -f -p "${cms_src}" "${tmp}"; chown ograc:ograc "${tmp}"; chmod 750 "${tmp}"; mv -f "${tmp}" "${home}/cms/service/bin/cms"
            for so in libogprotocol.so libogcommon.so; do [ -f "${OUTPUT_DIR}/lib/${so}" ] && [ -f "${home}/cms/service/lib/${so}" ] || continue
                tmp="${home}/cms/service/lib/.${so}.tmp.$$"; cp -f -p "${OUTPUT_DIR}/lib/${so}" "${tmp}"; chown ograc:ograc "${tmp}"; chmod 750 "${tmp}"; mv -f "${tmp}" "${home}/cms/service/lib/${so}"; done
        fi
    done; log "ogracd/ogsql/cms 已更新"
}
do_sql() {
    local node_id="${1:-0}" sql home data env_setup out; shift || true; sql="${*:-SELECT STATUS, OPEN_STATUS FROM DV_DATABASE;}"
    home="$(_node_home "${node_id}")"; data="$(_node_data "${node_id}")/local/ograc/tmp/data"; env_setup="$(_node_env "${node_id}")"
    [ -x "${home}/ograc/server/bin/ogsql" ] || die "ogsql 不存在，请先 install"; log "node${node_id} SQL: ${sql}"
    out="$(as_ograc "${env_setup}; printf '%s\\n' \"${sql}\" | ogsql / as sysdba -q -D ${data}" 2>&1)" || true; echo "${out}"
    ! echo "${out}" | grep -qiE 'OG-[0-9]+|PLC-[0-9]+|does not exist|Execute failed|Instance Startup Failed'
}
do_login() {
    local node_id="${1:-0}" home data env_setup; home="$(_node_home "${node_id}")"; data="$(_node_data "${node_id}")/local/ograc/tmp/data"; env_setup="$(_node_env "${node_id}")"
    [ -x "${home}/ograc/server/bin/ogsql" ] || die "ogsql 不存在，请先 install"
    setpriv --reuid=ograc --regid=ograc --init-groups --inh-caps=+sys_rawio,+sys_admin --ambient-caps=+sys_rawio,+sys_admin \
        -- env HOME=/home/ograc USER=ograc LOGNAME=ograc bash -c "${env_setup}; exec ogsql / as sysdba -D ${data}"
}
do_verify() {
    local ts id0 id1 env0 data0 data1 s0 s1 ready=false i port cms_stat q0 q1 q id ports_ready last_port
    for i in $(seq 1 30); do
        ports_ready=true
        for port in "${NODE0_CMS_PORT}" "${NODE1_CMS_PORT}" "${NODE0_DSS_PORT}" "${NODE1_DSS_PORT}" "${NODE0_OGRAC_PORT}" "${NODE1_OGRAC_PORT}"; do
            ss -tln 2>/dev/null | grep -q ":${port} " || { ports_ready=false; last_port="${port}"; break; }
        done
        [ "${ports_ready}" = "true" ] && break
        sleep 2
    done
    [ "${ports_ready}" = "true" ] || { err "端口 ${last_port} 未监听"; return 1; }
    env0="$(_node_env 0)"; data0="${DATA_ROOT}/local/ograc/tmp/data"; data1="${DATA_ROOT1}/local/ograc/tmp/data"
    cms_stat="$(as_ograc "${env0}; cms stat -server 2>/dev/null" || true)"; echo "${cms_stat}" | sed 's/^/    /'
    echo "${cms_stat}" | grep -q TRUE || { err "CMS 未 READY"; return 1; }
    ts=$(date +%s); id0=$((ts % 100000000)); id1=$((id0 + 1))
    for i in $(seq 1 30); do
        s0=$(as_ograc "${env0}; printf 'SELECT OPEN_STATUS FROM DV_DATABASE;\\n' | ogsql / as sysdba -q -D ${data0}" 2>/dev/null || true)
        s1=$(as_ograc "$(_node_env 1); printf 'SELECT OPEN_STATUS FROM DV_DATABASE;\\n' | ogsql / as sysdba -q -D ${data1}" 2>/dev/null || true)
        echo "${s0}" | grep -q 'READ WRITE' && echo "${s1}" | grep -q 'READ WRITE' && { ready=true; break; }; sleep 2
    done; [ "${ready}" = "true" ] || { err "双节点未 OPEN/READ WRITE"; return 1; }
    do_sql 0 "CREATE TABLE IF NOT EXISTS t_sim_verify(id INT PRIMARY KEY, name VARCHAR(64), ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP);" || return 1
    do_sql 0 "INSERT INTO t_sim_verify(id,name) VALUES(${id0},'node0'); COMMIT;" || return 1
    do_sql 1 "INSERT INTO t_sim_verify(id,name) VALUES(${id1},'node1'); COMMIT;" || return 1
    do_sql 0 "SELECT id,name FROM t_sim_verify WHERE id IN (${id0},${id1}) ORDER BY id;" || return 1
    do_sql 1 "SELECT id,name FROM t_sim_verify WHERE id IN (${id0},${id1}) ORDER BY id;" || return 1
    q0="$(as_ograc "${env0}; printf 'SELECT id FROM t_sim_verify WHERE id IN (${id0},${id1});\\n' | ogsql / as sysdba -q -D ${data0}" 2>&1 || true)"
    q1="$(as_ograc "$(_node_env 1); printf 'SELECT id FROM t_sim_verify WHERE id IN (${id0},${id1});\\n' | ogsql / as sysdba -q -D ${data1}" 2>&1 || true)"
    for q in "${q0}" "${q1}"; do for id in "${id0}" "${id1}"; do
        printf '%s\n' "${q}" | grep -q "${id}" || { err "双节点未交叉看到 id=${id}"; return 1; }
    done; done
    log "verify 通过"
}
do_status() {
    echo "===== oGRAC 单集群状态 =====  目录: ${SIM_BASE}"
    echo "端口: CMS ${NODE0_CMS_PORT}/${NODE1_CMS_PORT}, DSS ${NODE0_DSS_PORT}/${NODE1_DSS_PORT}, OGRAC ${NODE0_OGRAC_PORT}/${NODE1_OGRAC_PORT}"
    echo "LUN: ${LUN_DEVICES[*]}"; echo "[进程]"; ps -u ograc -o pid,etime,stat,args= 2>/dev/null | grep -E 'PID|ogracd|cms server|dssserver' || echo "  ？"
    echo "[端口]"; ss -tlnp 2>/dev/null | grep -E ":(${NODE0_CMS_PORT}|${NODE1_CMS_PORT}|${NODE0_DSS_PORT}|${NODE1_DSS_PORT}|${NODE0_OGRAC_PORT}|${NODE1_OGRAC_PORT}) " || echo "  无"
    for n in 0 1; do sf="$(_node_home "${n}")/ograc/cfg/start_status.json"; echo -n "node${n}: "; [ -f "${sf}" ] && cat "${sf}" || echo "不存在"; done
}
do_clean() {
    do_stop silent; discover_luns; for dev in "${LUN_DEVICES[@]}"; do dd if=/dev/zero of="${dev}" bs=1M count=10 conv=notrunc 2>/dev/null || true; done; clear_pr_keys
    rm -rf "${OGRAC_HOME}/ograc"/* "${OGRAC_HOME}/cms"/* "${OGRAC_HOME}/dss"/* "${OGRAC_HOME1}/ograc"/* \
        "${OGRAC_HOME1}/cms"/* "${OGRAC_HOME1}/dss"/* "${DATA_ROOT}"/* "${DATA_ROOT1}"/* /data/ograc_connector 2>/dev/null || true; clean_shm; log "集群数据已清理"
}
do_log() { tail -n "${1:-50}" "${OGRAC_HOME}/log/ograc/run/ogracd.rlog" 2>/dev/null || echo "日志不存在"; }
container_prepare() { SIM_BASE="${OGRAC_DEV_BASE:-${SIM_BASE}}"; setup_paths; ensure_deploy_user; ensure_ograc_user; chmod 755 /data /tmp; chmod 1777 /tmp; }
container_init() { trap 'timeout 25 bash "${SCRIPT_PATH}" stop silent >/dev/null 2>&1 || true; exit 0' TERM INT; container_prepare 2>/dev/null || true; log "容器 PID1 就绪"; while :; do sleep 3600 & wait $!; done; }
# ============================ 内嵌资源 ======================================
# 由 docker/lun-sim/{Dockerfile,cluster.sh} 压缩生成，保证脚本可独立拷贝。
DOCKERFILE_B64='H4sICMd0yGoCA0RvY2tlcmZpbGUAVZC/SgQxEMb7fYqPE2w0nnqdrSKInMKBWKhILsntDmaTsMl6rpWNoJUK9mIh2NgJih74NMvZ3SsYPf+caTIzzG/mm2+1s9mGdcqoUqui+RstLc7PzbeYDp55t5AkU6hvXoa3J+9vl8PXR8ygHpzUF1f18/Pw+r5+uqtPn0aDs0PKmykFDB/OR4PzpLO1garMQcYHrjVYhd0E38+nrf0ykPYgV9gyKMRPOM9MCleFzJoWjAosWBt7umQkG7f/jSA3roiscDxk+MyYJlMeQVOXk4Upcy6CnmCiRKZMxo1QEp9atfIe/YxEBl9Ki8ALpMfk0E9VgCiLSboXZYx3Sur1xlFcHdnCV0ZAe9tDKJRCKrsTXJf7jAmbO60CWRMZ7/sSPuPS9v/dNT39ZZnQihtE05IvF/MDSQWYQ1PywJNke7OzvrLW+UmX2yvYaXitlGvMokEm6qRQNfaSD61vezPgAQAA'
CLUSTER_SH_B64='H4sICGrH+moCA2NsdXN0ZXIuc2gA7VjbbttGEH0mv2LCqLZUh5bkNClqQw4USXYE1FLgC/rQBDRNriTW1JLlJY5iM9/e2V1elhQluzVQoEANJBC5cz17dmaWL1+0bxzavjHDhRp6cWAR+N7eZ4+BpaoXg/Pxx0tjOD7vNZq2E1BzSaDRDIhpuw69BX0GjU6rpU5Pz/sD48P0bFSSq/l1X5hMWqjZH1yOpxPuQWvcF3aStmlFjkc19XR0aQymk5PxKZMo5JO2Nw9My7C85dKj7TmJ8CedOXPDoTNv319p6vvxZGgMPl4ZwulWfcuPDUTC5opMR/g0Tsa/jqqhccW2NZtzLeF1/4+QRcs0hdvHQ85cli2o9k0ckqB3fbfwzKVzrbrevPzCmcHvgIaFYKJBD7TA8yINPqvRglBVSU00mv4qWnj0NeJewJiAZhPf9VYGE9Ja6sxRg5hSh86NpWeTzWpnxvnVZDw5Nc6mwxEqkq9OZNB4acwcl1RBspYhhygT2o++RlqhgozYoKGpIYbiEhGMtozdyPFdoql+4FkkDI3IM6wFsW57GofTLlZ8M1oIq8P3xrB/2T/UE0R0FlNOJiA0jANiFLvWbMG9qnBAkcuoWdl5BPfzEQhQlYBEcYA/EC+h8iJVqvCspESshQfab2bA8D0Esd8Fa/wVUC+CmRdT+xDqTB3vHJR9q4rrWaYLCBVHsThddfG3ilhtJpBqlWJc3uIb0P3y+sFx2yZf2jR2XXh4gCiISeq/lHyF8TXJj6kTOabrfEMEAMU5CJACsL+fpZiRrhZQB22kmGFgO10WUQVaWWRmIiNtaAZWr/GulXpg+yZ0TgklgRmxeConuIgnO2Xp8SsdszzBMAY9hLyEgl46l7oFWnGU1pPakEiFI/XJEDckj4H2HPv1G73paFQ8VECFOzOEyfQS5gJ3dGZGUGcxc51IhzYOzTlpttT7bPeu2ItDLXtUAP8aHdyIyAwiPE42MRy7vMyXYh9YYWBbXKPr+fWqtw7yv6oHICsaM481zqq6EMr14WYFXLA2AF7R6iMQS9wE5hHFYX0knP+8vrJyvCEaIWgZWR0uxGTIES3WT7Oy6jphJDYAyyRlXJALLiMCY5koUdBVFT9EysSlo/AA84D4oJ+ArssGslq+RST1kS1/GcFuk/18sAkPuLW7LXYLK2safE1WaPXOAt3dZsF37HCbAfPuFnYxWocipw+ScjQ8uUzj72AYkDR2rO91KbXyCpVLYsEhf4LWWe9ZzCBxN8h3a+Q7eYER5CmiwWObP2BvzQTORxfGqH/aH0+0ktfKWebn0OBtW7TetY6sKshKnP1cI4xwQgA0F5II9ki+gPRYmIF9ZwYEjqHoUazapaA03vHUOlJi0wujfz74gGjGvFfqDiKopIPQ9rFHEmLtlLtAH/epyQR630EzzcBavP0JsfwMOztM4Cvjf6GKW/yihy/tMGRCaWCiBDL0JldnvWsL62Kb7TMbDtkcCw+c9Rqz7kTEQlwJngVO2uuKdqPZLL3AbtTFEbuEZ47hADp699Vbvdt91X2r5+U9VU048KIJPJpvjjEjLU5r3NNGNMXEhz76vFmNJydTjmo6hX0TDE3NyNTMqDYKAi84hBo74IRAln60YuWRyWORYyTkieD/m5DglE49Jmne/B9jnk6ePAvYHoA+QmqBHkNe/IDNBTgJUG+BHUiMrKAP4ZM0pyZwfAzycxtdidtCWvLxWfTzHS3dEs5ySkosl07jSR9b6pADkePAJyBxrqvR/MNgnhfLWnXAXioVh22V8h7WzB+BMH4ECfYgqXqvl1D2tlUusryAz2D3h/AT3S15RVnef3ihn5yga66ztwcJjCZDfBbFn7+FPQQh2W2p1coJa6XzKfW7DsMMwqdVdD5/6L9AJaGS7YurwWB0cZEb31j+2Ql7SgPgVl5v2WDjZiWmpv93em2na3fjv7bV8pAp37JtNCp/BEik+IvrhiTDhllZSIm82FqsSeQdpKb3K4q1wBYMP795U6sn8urC8ZZVzQoI3lygtA5hbDGcNUmuAnIBs5IBvdWiuIxVDUoFtNrVMqN4moAN9A4FPkZUU7lmQrbHTbCXlNyxiaFxjw/JHhsUcpf8HRNINkBie5SU24kIFRsg+5qxML8UaQFusly11ngi31r+LaZsocpjXBGpdjaRZRMLJBoUPHgqETYwQaJCmQvbQnzGpr3c/gdLE8n3iJAqPl82XipsXjgooOfXfDXzyCZP3wyWvUZXTa+ovcaBapkh/8zFlvhXIVUR137GXulygU9HR3zN88VS1njkFdGByut5Y8oE+Q2OyZSucs+be4RluUTye4X0XMjIx0NIyW9SuR9bG2aFFNXCPUqTEGFQa3iaUvQvLB2VVBQYAAA='
show_help() {
    cat <<EOF
oGRAC 单集群 LUN 开发环境（4 LUN x 2 路径，容器内双节点主集群）
用法: sudo bash $0 <command> [args]
说明: 可独立拷贝到 oGRAC 源码树内执行；源码根自动探测，也可用 OGRAC_SRC 指定。
宿主机: create | destroy | enter | ct-start | ct-stop | env
容器/转发: init | make [debug|release|inc] | install [debug|release] |
           start | stop | restart | status | sql [0|1] [SQL] | login [0|1] |
           verify | clean | log [行数]
示例:
  sudo bash $0 create && sudo bash $0 init && sudo bash $0 make debug
  sudo bash $0 install debug && sudo bash $0 start && sudo bash $0 verify
  sudo bash $0 destroy
EOF
}
forward_cluster() {
    require_host_root "$*"; container_running || die "容器 ${CONTAINER_NAME} 未运行"; docker exec -e OGRAC_IN_CONTAINER=1 \
        -e "OGRAC_DEV_BASE=${SIM_BASE}" -e "SIM_USER=${SIM_USER}" -e "OGRAC_SRC=${OGRAC_SRC}" \
        "${CONTAINER_NAME}" bash "${SCRIPT_PATH}" "$@"
}
main() {
    [ $# -gt 0 ] || { show_help; exit 0; }; local cmd="$1"; shift || true
    case "${cmd}" in
        -h|--help|help) show_help ;; _container_init) container_init ;; _container_prepare) container_prepare ;;
        create) create_env ;; destroy) destroy_env ;; ct-start) ct_start ;; ct-stop) ct_stop ;;
        env|ct-status) show_env ;; enter) require_host_root enter; container_running || die "容器未运行"; exec docker exec -it -w "${OGRAC_SRC}" "${CONTAINER_NAME}" bash ;;
        init|make|install|start|stop|restart|clean|status|sql|login|verify|log)
            if [ "${IN_CONTAINER}" = "1" ]; then
                discover_luns; case "${cmd}" in
                    init) do_init ;; make) do_make "$@" ;; install) do_install "$@" ;; start) do_start ;;
                    stop) do_stop "${1:-}" ;; restart) do_stop silent; sleep 2; do_start ;; clean) do_clean ;;
                    status) do_status ;; sql) do_sql "$@" ;; login) do_login "$@" ;; verify) do_verify ;; log) do_log "${1:-50}" ;;
                esac
            else
                if [ "${cmd}" = "login" ]; then require_host_root login; container_running || die "容器未运行"
                    docker exec -it -e OGRAC_IN_CONTAINER=1 -e "OGRAC_DEV_BASE=${SIM_BASE}" -e "SIM_USER=${SIM_USER}" -e "OGRAC_SRC=${OGRAC_SRC}" \
                        "${CONTAINER_NAME}" bash "${SCRIPT_PATH}" login "$@"
                else forward_cluster "${cmd}" "$@"; fi
            fi ;;
        *) err "未知命令: ${cmd}"; show_help; exit 1 ;;
    esac
}
main "$@"
