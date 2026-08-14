#!/bin/bash

set -euo pipefail

SCRIPT_VERSION="2026-08-07-install-only-v1"

show_usage() {
    cat <<EOF
Usage:
  $0 --cms-ip <node0_ip> --cms-ip <node1_ip> \\
     --vg1 <disk> --vg2 <disk> --vg3 <disk> --gcc-home <disk> \\
     --package-path <path> --password <password>

Options:
  --cms-ip                  CMS IP. Pass twice: first node0, second node1.
  --cms-ips                 CMS IPs as comma or semicolon-separated value: node0_ip,node1_ip.
  --vg1                     Disk path for dss_vg_list.vg1.
  --vg2                     Disk path for dss_vg_list.vg2.
  --vg3                     Disk path for dss_vg_list.vg3.
  --gcc-home                Disk path for gcc_home.
  --package-path            oGRAC package file path, or a directory containing one oGRAC*.tgz.
  --node1-package-dir        Directory where the package is copied on node1. Default: node0 package directory.
  --node1-root-password      Root SSH password for node1 when SSH trust is not configured.
  -p, --password            OGRAC database password for automatic install input.

Optional config overrides:
  --deploy-mode             Default: dss
  --db-type                 Default: 1
  --mes-ssl-switch          Default: false
  --max-arch-files-size     Default: 300G
  --redo-num                Default: 6
  --redo-size               Default: 5G
  --auto-tune               Default: 1
  --cms-port                Default: 14587
  --dss-port                Default: 1811
  --ograc-port              Default: 1611
  --interconnect-port       Default: 1601,1602
  --shm-key                 Default: 17
  --ograc-home              Default: /opt/ograc
  --data-root               Default: /mnt/dbdata
  --ograc-user              Default: ograc
  --ask-extra               Ask whether to override optional parameters.
  --no-ask-extra            Do not ask optional parameter questions.
  -h, --help                Show this help.

Environment fallbacks:
  CMS_IPS, VG1_DISK, VG2_DISK, VG3_DISK, GCC_HOME_DISK, OGRAC_PACKAGE_PATH,
  NODE1_PACKAGE_DIR, NODE1_ROOT_PASSWORD, OGRAC_AUTO_PASSWORD_VALUE
EOF
}

DEPLOY_MODE="${DEPLOY_MODE:-dss}"
DB_TYPE="${DB_TYPE:-1}"
MES_SSL_SWITCH="${MES_SSL_SWITCH:-false}"
MAX_ARCH_FILES_SIZE="${MAX_ARCH_FILES_SIZE:-300G}"
REDO_NUM="${REDO_NUM:-6}"
REDO_SIZE="${REDO_SIZE:-5G}"
AUTO_TUNE="${AUTO_TUNE:-1}"
CMS_PORT="${CMS_PORT:-14587}"
DSS_PORT="${DSS_PORT:-1811}"
OGRAC_PORT="${OGRAC_PORT:-1611}"
INTERCONNECT_PORT="${INTERCONNECT_PORT:-1601,1602}"
SHM_KEY="${SHM_KEY:-17}"
OGRAC_HOME="${OGRAC_HOME:-/opt/ograc}"
DATA_ROOT="${DATA_ROOT:-/mnt/dbdata}"
OGRAC_USER="${OGRAC_USER:-ograc}"
ASK_EXTRA="${ASK_EXTRA:-auto}"
OGRAC_PACKAGE_FILE=""
OGRAC_PACKAGE_FILE_NAME=""
OGRAC_PACKAGE_DIR=""

CMS_IP_LIST=()
SG_PERSIST_DISK_LIST=()

add_cms_ips() {
    local ip
    local ips

    IFS=',;' read -r -a ips <<< "$1"
    for ip in "${ips[@]}"; do
        ip="${ip#"${ip%%[![:space:]]*}"}"
        ip="${ip%"${ip##*[![:space:]]}"}"
        if [ -n "${ip}" ]; then
            CMS_IP_LIST+=("${ip}")
        fi
    done
}

require_option_value() {
    if [ "$#" -lt 2 ]; then
        echo "Missing value for $1" >&2
        exit 1
    fi
}

read_optional_value() {
    local prompt="$1"
    local current_value="$2"
    local new_value

    read -r -p "${prompt} [${current_value}]: " new_value
    if [ -n "${new_value}" ]; then
        printf '%s' "${new_value}"
    else
        printf '%s' "${current_value}"
    fi
}

prompt_extra_params() {
    local answer

    if [ "${ASK_EXTRA}" = "no" ]; then
        return
    fi

    if [ "${ASK_EXTRA}" = "auto" ] && [ ! -t 0 ]; then
        return
    fi

    read -r -p "是否指定其它配置参数? [y/N]: " answer
    case "${answer}" in
        y|Y|yes|YES)
            DEPLOY_MODE="$(read_optional_value "deploy_mode" "${DEPLOY_MODE}")"
            DB_TYPE="$(read_optional_value "db_type" "${DB_TYPE}")"
            MES_SSL_SWITCH="$(read_optional_value "mes_ssl_switch(true/false)" "${MES_SSL_SWITCH}")"
            MAX_ARCH_FILES_SIZE="$(read_optional_value "MAX_ARCH_FILES_SIZE" "${MAX_ARCH_FILES_SIZE}")"
            REDO_NUM="$(read_optional_value "redo_num" "${REDO_NUM}")"
            REDO_SIZE="$(read_optional_value "redo_size" "${REDO_SIZE}")"
            AUTO_TUNE="$(read_optional_value "auto_tune" "${AUTO_TUNE}")"
            CMS_PORT="$(read_optional_value "cms_port" "${CMS_PORT}")"
            DSS_PORT="$(read_optional_value "dss_port" "${DSS_PORT}")"
            OGRAC_PORT="$(read_optional_value "ograc_port" "${OGRAC_PORT}")"
            INTERCONNECT_PORT="$(read_optional_value "interconnect_port" "${INTERCONNECT_PORT}")"
            SHM_KEY="$(read_optional_value "_SHM_KEY" "${SHM_KEY}")"
            OGRAC_HOME="$(read_optional_value "module_config.ograc_home" "${OGRAC_HOME}")"
            DATA_ROOT="$(read_optional_value "module_config.data_root" "${DATA_ROOT}")"
            OGRAC_USER="$(read_optional_value "module_config.user/ograc user" "${OGRAC_USER}")"
            ;;
    esac
}

resolve_ograc_package_path() {
    local package_dir
    local package_file_name
    local packages

    if [ -z "${OGRAC_PACKAGE_PATH}" ]; then
        return 1
    fi

    if [ -d "${OGRAC_PACKAGE_PATH}" ]; then
        package_dir="$(cd "${OGRAC_PACKAGE_PATH}" && pwd)"
        packages=("${package_dir}"/oGRAC*.tgz)
        if [ ! -e "${packages[0]}" ]; then
            echo "No oGRAC*.tgz package found in ${package_dir}" >&2
            return 1
        fi
        if [ "${#packages[@]}" -ne 1 ]; then
            echo "Multiple oGRAC*.tgz packages found in ${package_dir}; pass an exact --package-path file" >&2
            return 1
        fi
        OGRAC_PACKAGE_FILE="${packages[0]}"
    elif [ -f "${OGRAC_PACKAGE_PATH}" ]; then
        package_dir="$(cd "$(dirname "${OGRAC_PACKAGE_PATH}")" && pwd)"
        package_file_name="$(basename "${OGRAC_PACKAGE_PATH}")"
        OGRAC_PACKAGE_FILE="${package_dir}/${package_file_name}"
    else
        echo "Package path does not exist: ${OGRAC_PACKAGE_PATH}" >&2
        return 1
    fi

    OGRAC_PACKAGE_DIR="$(dirname "${OGRAC_PACKAGE_FILE}")"
    OGRAC_PACKAGE_FILE_NAME="$(basename "${OGRAC_PACKAGE_FILE}")"

    if [ -z "${NODE1_PACKAGE_DIR}" ]; then
        NODE1_PACKAGE_DIR="${OGRAC_PACKAGE_DIR}"
    fi
}

parse_args() {
    VG1_DISK="${VG1_DISK:-}"
    VG2_DISK="${VG2_DISK:-}"
    VG3_DISK="${VG3_DISK:-}"
    GCC_HOME_DISK="${GCC_HOME_DISK:-}"
    OGRAC_PACKAGE_PATH="${OGRAC_PACKAGE_PATH:-}"
    NODE1_PACKAGE_DIR="${NODE1_PACKAGE_DIR:-}"
    NODE1_ROOT_PASSWORD="${NODE1_ROOT_PASSWORD:-}"
    OGRAC_AUTO_PASSWORD_VALUE="${OGRAC_AUTO_PASSWORD_VALUE:-}"

    if [ -n "${CMS_IPS:-}" ]; then
        add_cms_ips "${CMS_IPS}"
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --cms-ip|--cms-ips)
                if [ "$#" -lt 2 ]; then
                    echo "Missing value for $1" >&2
                    exit 1
                fi
                add_cms_ips "$2"
                shift 2
                ;;
            --vg1)
                if [ "$#" -lt 2 ]; then
                    echo "Missing value for $1" >&2
                    exit 1
                fi
                VG1_DISK="$2"
                shift 2
                ;;
            --vg2)
                if [ "$#" -lt 2 ]; then
                    echo "Missing value for $1" >&2
                    exit 1
                fi
                VG2_DISK="$2"
                shift 2
                ;;
            --vg3)
                if [ "$#" -lt 2 ]; then
                    echo "Missing value for $1" >&2
                    exit 1
                fi
                VG3_DISK="$2"
                shift 2
                ;;
            --gcc-home)
                if [ "$#" -lt 2 ]; then
                    echo "Missing value for $1" >&2
                    exit 1
                fi
                GCC_HOME_DISK="$2"
                shift 2
                ;;
            --package-path|--package)
                if [ "$#" -lt 2 ]; then
                    echo "Missing value for $1" >&2
                    exit 1
                fi
                OGRAC_PACKAGE_PATH="$2"
                shift 2
                ;;
            --node1-package-dir)
                if [ "$#" -lt 2 ]; then
                    echo "Missing value for $1" >&2
                    exit 1
                fi
                NODE1_PACKAGE_DIR="$2"
                shift 2
                ;;
            --node1-root-password)
                if [ "$#" -lt 2 ]; then
                    echo "Missing value for $1" >&2
                    exit 1
                fi
                NODE1_ROOT_PASSWORD="$2"
                shift 2
                ;;
            -p|--password)
                if [ "$#" -lt 2 ]; then
                    echo "Missing value for $1" >&2
                    exit 1
                fi
                OGRAC_AUTO_PASSWORD_VALUE="$2"
                shift 2
                ;;
            --deploy-mode)
                require_option_value "$@"
                DEPLOY_MODE="$2"
                shift 2
                ;;
            --db-type)
                require_option_value "$@"
                DB_TYPE="$2"
                shift 2
                ;;
            --mes-ssl-switch)
                require_option_value "$@"
                MES_SSL_SWITCH="$2"
                shift 2
                ;;
            --max-arch-files-size)
                require_option_value "$@"
                MAX_ARCH_FILES_SIZE="$2"
                shift 2
                ;;
            --redo-num)
                require_option_value "$@"
                REDO_NUM="$2"
                shift 2
                ;;
            --redo-size)
                require_option_value "$@"
                REDO_SIZE="$2"
                shift 2
                ;;
            --auto-tune)
                require_option_value "$@"
                AUTO_TUNE="$2"
                shift 2
                ;;
            --cms-port)
                require_option_value "$@"
                CMS_PORT="$2"
                shift 2
                ;;
            --dss-port)
                require_option_value "$@"
                DSS_PORT="$2"
                shift 2
                ;;
            --ograc-port)
                require_option_value "$@"
                OGRAC_PORT="$2"
                shift 2
                ;;
            --interconnect-port)
                require_option_value "$@"
                INTERCONNECT_PORT="$2"
                shift 2
                ;;
            --shm-key)
                require_option_value "$@"
                SHM_KEY="$2"
                shift 2
                ;;
            --ograc-home)
                require_option_value "$@"
                OGRAC_HOME="$2"
                shift 2
                ;;
            --data-root)
                require_option_value "$@"
                DATA_ROOT="$2"
                shift 2
                ;;
            --ograc-user)
                require_option_value "$@"
                OGRAC_USER="$2"
                shift 2
                ;;
            --ask-extra)
                ASK_EXTRA="yes"
                shift
                ;;
            --no-ask-extra)
                ASK_EXTRA="no"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_usage >&2
                exit 1
                ;;
        esac
    done
}

validate_args() {
    local missing=0

    if [ "${#CMS_IP_LIST[@]}" -ne 2 ]; then
        echo "Missing required parameter: pass exactly two --cms-ip values, or --cms-ips node0_ip,node1_ip" >&2
        missing=1
    fi

    if [ -z "${VG1_DISK}" ]; then
        echo "Missing required parameter: --vg1" >&2
        missing=1
    fi

    if [ -z "${VG2_DISK}" ]; then
        echo "Missing required parameter: --vg2" >&2
        missing=1
    fi

    if [ -z "${VG3_DISK}" ]; then
        echo "Missing required parameter: --vg3" >&2
        missing=1
    fi

    if [ -z "${GCC_HOME_DISK}" ]; then
        echo "Missing required parameter: --gcc-home" >&2
        missing=1
    fi

    if [ -z "${OGRAC_PACKAGE_PATH}" ]; then
        echo "Missing required parameter: --package-path" >&2
        missing=1
    elif ! resolve_ograc_package_path; then
        missing=1
    fi

    if [ -z "${OGRAC_AUTO_PASSWORD_VALUE}" ]; then
        echo "Missing required parameter: --password" >&2
        missing=1
    fi

    case "${MES_SSL_SWITCH}" in
        true|false) ;;
        *)
            echo "Invalid value for --mes-ssl-switch: use true or false" >&2
            missing=1
            ;;
    esac

    case "${SHM_KEY}" in
        ''|*[!0-9]*)
            echo "Invalid value for --shm-key: use a number" >&2
            missing=1
            ;;
    esac

    if [ "${missing}" -ne 0 ]; then
        show_usage >&2
        exit 1
    fi

    node0_ip="${CMS_IP_LIST[0]}"
    node1_ip="${CMS_IP_LIST[1]}"
    cms_ip="${node0_ip};${node1_ip}"
    SG_PERSIST_DISK_LIST=("${VG1_DISK}" "${VG2_DISK}" "${VG3_DISK}" "${GCC_HOME_DISK}")
}

run_sg_persist_cleanup() {
    local disk

    for disk in "${SG_PERSIST_DISK_LIST[@]}"; do
        sg_persist -n -o -I -S 2 -d "${disk}"
        sg_persist -n -o -C -K 2 -d "${disk}"
    done
}

join_shell_command() {
    local arg
    local quoted_arg
    local command_line=""

    for arg in "$@"; do
        printf -v quoted_arg '%q' "${arg}"
        command_line+="${quoted_arg} "
    done

    printf '%s' "${command_line}"
}

write_set_args_line() {
    local output_file="$1"
    local arg
    local quoted_arg

    shift
    printf 'set --' > "${output_file}"
    for arg in "$@"; do
        printf -v quoted_arg '%q' "${arg}"
        printf ' %s' "${quoted_arg}" >> "${output_file}"
    done
    printf '\n' >> "${output_file}"
}

run_expect_command() {
    local command_line="$1"

    EXPECT_COMMAND="${command_line}" NODE1_ROOT_PASSWORD="${NODE1_ROOT_PASSWORD}" expect <<'EOF'
set timeout -1
set password $env(NODE1_ROOT_PASSWORD)
spawn sh -c $env(EXPECT_COMMAND)
expect {
    -nocase -re "are you sure you want to continue connecting" { send "yes\r"; exp_continue }
    -nocase -re "password:" { send "$password\r"; exp_continue }
    timeout { exit 1 }
    eof
}
catch wait result
exit [lindex $result 3]
EOF
}

run_node1_ssh_command() {
    local command_line

    if [ -z "${NODE1_ROOT_PASSWORD}" ]; then
        ssh "${node1_ssh}" "$@"
        return
    fi

    command_line="$(join_shell_command ssh "${node1_ssh}" "$@")"
    run_expect_command "${command_line}"
}

run_node1_scp_to_dir() {
    local source_path="$1"
    local target_dir="$2"
    local command_line

    if [ -z "${NODE1_ROOT_PASSWORD}" ]; then
        scp "${source_path}" "${node1_ssh}:${target_dir}/"
        return
    fi

    command_line="$(join_shell_command scp "${source_path}" "${node1_ssh}:${target_dir}/")"
    run_expect_command "${command_line}"
}

run_node1_bash() {
    local script_body_file
    local payload_file
    local quoted_payload_file
    local command_line
    local status

    script_body_file="$(mktemp)"
    payload_file="$(mktemp)"
    cat > "${script_body_file}"
    write_set_args_line "${payload_file}" "$@"
    cat "${script_body_file}" >> "${payload_file}"

    if [ -z "${NODE1_ROOT_PASSWORD}" ]; then
        ssh "${node1_ssh}" "bash -s" < "${payload_file}"
        status=$?
    else
        command_line="$(join_shell_command ssh "${node1_ssh}" "bash -s")"
        printf -v quoted_payload_file '%q' "${payload_file}"
        run_expect_command "${command_line} < ${quoted_payload_file}"
        status=$?
    fi

    rm -f "${script_body_file}" "${payload_file}"
    return "${status}"
}

json_escape() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "${value}"
}

write_config_params_lun() {
    local output_file="$1"
    local node_id="$2"
    local output_dir

    output_dir="$(dirname "${output_file}")"
    mkdir -p "${output_dir}"

    cat > "${output_file}" <<EOF
{
    "deploy_mode": "$(json_escape "${DEPLOY_MODE}")",
    "node_id": "$(json_escape "${node_id}")",
    "cms_ip": "$(json_escape "${cms_ip}")",
    "db_type": "$(json_escape "${DB_TYPE}")",
    "mes_ssl_switch": ${MES_SSL_SWITCH},
    "MAX_ARCH_FILES_SIZE": "$(json_escape "${MAX_ARCH_FILES_SIZE}")",
    "redo_num": "$(json_escape "${REDO_NUM}")",
    "redo_size": "$(json_escape "${REDO_SIZE}")",
    "auto_tune": "$(json_escape "${AUTO_TUNE}")",
    "dss_vg_list": {
        "vg1": "$(json_escape "${VG1_DISK}")",
        "vg2": "$(json_escape "${VG2_DISK}")",
        "vg3": "$(json_escape "${VG3_DISK}")"
    },
    "gcc_home": "$(json_escape "${GCC_HOME_DISK}")",
    "cms_port": "$(json_escape "${CMS_PORT}")",
    "dss_port": "$(json_escape "${DSS_PORT}")",
    "ograc_port": "$(json_escape "${OGRAC_PORT}")",
    "interconnect_port": "$(json_escape "${INTERCONNECT_PORT}")",
    "_SHM_KEY": ${SHM_KEY},
    "module_config": {
        "ograc_home": "$(json_escape "${OGRAC_HOME}")",
        "data_root": "$(json_escape "${DATA_ROOT}")",
        "user": "$(json_escape "${OGRAC_USER}")"
    }
}
EOF
}

parse_args "$@"
prompt_extra_params
validate_args

################### 需要修改的参数 #######################
# 数据库安装用户，按环境改
OGRAC_USER="${OGRAC_USER:-ograc}"

# 节点0安装包存放目录
base_path1=${OGRAC_PACKAGE_DIR}
# 节点0安装脚本目录
script_path1=${base_path1}/ograc_connector/action

# 节点1连接信息和安装包存放目录
node1_ssh="${node1_ssh:-root@${node1_ip}}"
base_path2=${NODE1_PACKAGE_DIR}
# 节点1安装脚本目录
script_path2=${base_path2}/ograc_connector/action

# 数据库安装目录
ograc_install=/data/ograc_install

# 自动输入安装密码


#lun1= /dev/disk/by-id/scsi-36382028100ed96ac4404967600000144
#lun2= /dev/disk/by-id/scsi-36382028100ed96ac4404967600000143
#lun3= /dev/disk/by-id/scsi-36382028100ed96ac4404967600000145
#lun4= /dev/disk/by-id/scsi-36382028100ed96ac4404967600000146

################### 需要修改的参数结束 #######################

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "请使用 root 执行此脚本"
        exit 1
    fi
}

run_expect_install_local() {
    export OGRAC_AUTO_PASSWORD="${OGRAC_AUTO_PASSWORD_VALUE}"
    expect <<'EOF'
set timeout 600
set password $env(OGRAC_AUTO_PASSWORD)
spawn sh appctl.sh install config_params_lun.json
expect {
    -re "please input ograc password:" { send "$password\r"; exp_continue }
    -re "please confirm the password:" { send "$password\r"; exp_continue }
    -re "completed successfully|=== install success ===" { expect eof }
    timeout { exit 1 }
    eof
}
catch wait result
exit [lindex $result 3]
EOF
}

run_node1_install() {
    run_node1_bash \
        "${OGRAC_USER}" \
        "${base_path2}" \
        "${script_path2}" \
        "${ograc_install}" \
        "${OGRAC_AUTO_PASSWORD_VALUE}" \
        "${OGRAC_PACKAGE_FILE_NAME}" \
        "${DEPLOY_MODE}" \
        "${cms_ip}" \
        "${DB_TYPE}" \
        "${MES_SSL_SWITCH}" \
        "${MAX_ARCH_FILES_SIZE}" \
        "${REDO_NUM}" \
        "${REDO_SIZE}" \
        "${AUTO_TUNE}" \
        "${VG1_DISK}" \
        "${VG2_DISK}" \
        "${VG3_DISK}" \
        "${GCC_HOME_DISK}" \
        "${CMS_PORT}" \
        "${DSS_PORT}" \
        "${OGRAC_PORT}" \
        "${INTERCONNECT_PORT}" \
        "${SHM_KEY}" \
        "${OGRAC_HOME}" \
        "${DATA_ROOT}" <<'REMOTE_NODE1'
set -euo pipefail

OGRAC_USER="$1"
base_path2="$2"
script_path2="$3"
ograc_install="$4"
OGRAC_AUTO_PASSWORD_VALUE="$5"
OGRAC_PACKAGE_FILE_NAME="$6"
DEPLOY_MODE="$7"
cms_ip="$8"
DB_TYPE="$9"
MES_SSL_SWITCH="${10}"
MAX_ARCH_FILES_SIZE="${11}"
REDO_NUM="${12}"
REDO_SIZE="${13}"
AUTO_TUNE="${14}"
VG1_DISK="${15}"
VG2_DISK="${16}"
VG3_DISK="${17}"
GCC_HOME_DISK="${18}"
CMS_PORT="${19}"
DSS_PORT="${20}"
OGRAC_PORT="${21}"
INTERCONNECT_PORT="${22}"
SHM_KEY="${23}"
OGRAC_HOME="${24}"
DATA_ROOT="${25}"

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 执行节点1远程脚本"
    exit 1
fi

json_escape() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "${value}"
}

write_config_params_lun_remote() {
    local output_file="${script_path2}/config_params_lun.json"

    mkdir -p "${script_path2}"
    cat > "${output_file}" <<EOF
{
    "deploy_mode": "$(json_escape "${DEPLOY_MODE}")",
    "node_id": "1",
    "cms_ip": "$(json_escape "${cms_ip}")",
    "db_type": "$(json_escape "${DB_TYPE}")",
    "mes_ssl_switch": ${MES_SSL_SWITCH},
    "MAX_ARCH_FILES_SIZE": "$(json_escape "${MAX_ARCH_FILES_SIZE}")",
    "redo_num": "$(json_escape "${REDO_NUM}")",
    "redo_size": "$(json_escape "${REDO_SIZE}")",
    "auto_tune": "$(json_escape "${AUTO_TUNE}")",
    "dss_vg_list": {
        "vg1": "$(json_escape "${VG1_DISK}")",
        "vg2": "$(json_escape "${VG2_DISK}")",
        "vg3": "$(json_escape "${VG3_DISK}")"
    },
    "gcc_home": "$(json_escape "${GCC_HOME_DISK}")",
    "cms_port": "$(json_escape "${CMS_PORT}")",
    "dss_port": "$(json_escape "${DSS_PORT}")",
    "ograc_port": "$(json_escape "${OGRAC_PORT}")",
    "interconnect_port": "$(json_escape "${INTERCONNECT_PORT}")",
    "_SHM_KEY": ${SHM_KEY},
    "module_config": {
        "ograc_home": "$(json_escape "${OGRAC_HOME}")",
        "data_root": "$(json_escape "${DATA_ROOT}")",
        "user": "$(json_escape "${OGRAC_USER}")"
    }
}
EOF
}

run_expect_install_remote() {
    export OGRAC_AUTO_PASSWORD="${OGRAC_AUTO_PASSWORD_VALUE}"
    expect <<'EOF'
set timeout 600
set password $env(OGRAC_AUTO_PASSWORD)
spawn sh appctl.sh install config_params_lun.json
expect {
    -re "please input ograc password:" { send "$password\r"; exp_continue }
    -re "please confirm the password:" { send "$password\r"; exp_continue }
    -re "completed successfully|=== install success ===" { expect eof }
    timeout { exit 1 }
    eof
}
catch wait result
exit [lindex $result 3]
EOF
}

echo "=========================================="
echo "开始在 node1 执行安装流程"
echo "=========================================="

echo "步骤1.1: node1 解压安装包并生成配置文件"
echo "=========================================="
tar -xvf "${base_path2}/${OGRAC_PACKAGE_FILE_NAME}" -C "${base_path2}"
write_config_params_lun_remote
chmod -R 777 "${base_path2}"
chmod -R 777 /dev/sd*
echo "步骤1.1完成: node1 配置文件生成成功"
echo ""

echo "步骤2.1: node1 pre_install服务"
echo "=========================================="
cd "${script_path2}"
sh appctl.sh pre_install config_params_lun.json
echo "步骤2.1完成: node1 服务启动成功"
echo ""

echo "步骤3.1: node1 安装服务"
echo "=========================================="
cd "${script_path2}"
run_expect_install_remote
echo "步骤3.1完成: node1 服务启动成功"
echo ""

echo "步骤4.1: node1 start服务"
echo "=========================================="
cd "${script_path2}"
sh appctl.sh start config_params_lun.json
echo "步骤4.1完成: node1 服务启动成功"
echo ""

REMOTE_NODE1
}

require_root

echo "install script version: ${SCRIPT_VERSION}"

echo "=========================================="
echo "开始执行 node0 + node1 合并安装流程"
echo "只需要在 node0 执行当前脚本"
echo "=========================================="

echo "步骤1: 清理磁盘"
echo "=========================================="
run_sg_persist_cleanup
echo "步骤1完成"

echo "步骤2: node0 解压安装包并生成配置文件"
echo "=========================================="
tar -xvf "${OGRAC_PACKAGE_FILE}" -C "${base_path1}"
write_config_params_lun "${script_path1}/config_params_lun.json" "0"
chmod -R 777 "${base_path1}"
chmod -R 777 /dev/sd*
echo "步骤2完成: node0 配置文件生成成功"
echo ""

echo "步骤3: node0 pre_install服务"
echo "=========================================="
cd "${script_path1}"
sh appctl.sh pre_install config_params_lun.json
echo "步骤3完成: node0 服务启动成功"
echo ""

echo "步骤4: node0 install服务"
echo "=========================================="
cd "${script_path1}"
run_expect_install_local
echo "步骤4完成: node0 服务启动成功"
echo ""

echo "步骤5: node0 start服务"
echo "=========================================="
cd "${script_path1}"
sh appctl.sh start config_params_lun.json
echo "步骤5完成: node0 服务启动成功"
echo ""

echo "步骤6: scp 安装包到 node1"
echo "=========================================="
run_node1_ssh_command "mkdir -p '${base_path2}'"
run_node1_scp_to_dir "${OGRAC_PACKAGE_FILE}" "${base_path2}"
echo "步骤6完成: scp安装包成功"
echo ""

echo "步骤7: 通过 SSH 在 node1 执行原节点1安装流程"
echo "=========================================="
run_node1_install
echo "步骤7完成: node1 安装流程执行成功"
echo ""

echo "=========================================="
echo "node0 和 node1 所有步骤执行完成！"
echo "=========================================="
