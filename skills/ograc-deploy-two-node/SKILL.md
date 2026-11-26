---
name: ograc-deploy-two-node
description: 构建、安装、启动、验证 oGRAC 两节点测试集群（release with debug info + UB 串行刷盘参数）。用于部署新代码、全量重装、停机增量刷新已安装二进制，或按验证过的顺序重启与排查启动问题。
---

# oGRAC 两节点测试集群部署

## 何时使用本 skill

- 用户要求把当前代码部署到一台两节点 oGRAC 测试集群。
- 需要重新构建 release with debug info 安装包并安装。
- 需要在不重建数据的情况下刷新 `ogracd`/DSS/CMS 二进制。
- 集群启动失败，需要按已验证的顺序重启或排查。

## 不可违反的约束

1. **只操作分配给自己的目录和进程**：源码树 `$SRC`、部署根目录 `$ROOT`（默认 `$HOME/ograc_cluster`），以及当前用户的进程。
2. **绝不修改、停止、覆盖同机其他用户的 oGRAC 实例、目录、进程、端口、服务**。发现端口/磁盘/进程冲突时停止并报告，不要抢占。
3. **密码只允许通过环境变量传入**：`SUDO_PWD`（sudo）和 `OGRAC_SYS_PWD`（数据库 sys 用户）。禁止把密码写入任何文件、日志、命令输出或回复；脚本内部不得 `echo` 密码。
4. 执行停止集群、`uninstall`、覆盖安装、重启 `ubsmd` 等动作前，先向用户确认影响范围。
5. **不要使用宽泛的 `pkill -f`/`killall`**。先用 `ps -eo pid,args` / `pgrep -af` 查明确切 PID 和命令行，再按 PID 处理，避免误杀同机其他用户进程。
6. 只使用本文记录或用户明确提供的路径、端口、LUN。需要改动时先与用户确认。

## 环境参数

本 skill 不内置任何主机、用户、LUN 或路径。运行前由使用者提供：

| 变量 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `NODE0` | 是 | — | node0 地址（执行部署的本机，也用于 SQL 连接） |
| `NODE1` | 是 | — | node1 地址，要求 `SSH_USER@NODE1` 免密可达 |
| `SSH_USER` | 否 | `$USER` | 节点间 SSH 用户 |
| `ROOT` | 否 | `$HOME/ograc_cluster` | 部署根目录；安装目录 `$ROOT/ograc`，数据目录 `$ROOT/dbdata/local/ograc/tmp/data` |
| `SRC` | 否 | `$HOME/code/oGRAC` | oGRAC 源码目录 |
| `DATA_DEV` | 安装时必填 | — | data LUN 的 `/dev/disk/by-id/...` 路径 |
| `REDO_DEV` | 安装时必填 | — | redo LUN 路径 |
| `ARCH_DEV` | 安装时必填 | — | archive LUN 路径 |
| `GCC_DEV` | 安装时必填 | — | GCC/quorum LUN 路径 |
| `CMS_PORT` | 否 | `28520` | CMS 端口 |
| `DSS_PORT` | 否 | `28911` | DSS 端口 |
| `DB_PORT` | 否 | `29300` | 数据库端口 |
| `INTERCONNECT_PORT` | 否 | `29410,29420` | interconnect 端口 |
| `SHM_KEY` | 否 | `50` | DSS `_SHM_KEY` |

- redo 规划示例：每节点 5 × 10G，两节点共 10 个 redo 文件。
- 机器可能由多人共用：以上目录、端口和 LUN 是分配给你这一套实例的资源；不要占用或改动他人的资源。
- node1 必须提前配置免密 SSH；`sg ubsmd` 需要在两节点都可用。

## 部署模式选择

| 模式 | 适用场景 | 数据 | 风险 |
|---|---|---|---|
| **A. 全量安装** | 空机器首次部署，或安装目录/配置需完全重建 | 新建数据 | 中 |
| **B. 二进制刷新**（推荐迭代新代码） | 只更新 `ogracd`/DSS/CMS 二进制和库，保留数据和配置 | 保留 | 低 |
| **C. 官方重装** | 配置、磁盘布局变化，或安装树损坏 | 可能删除安装目录/用户，数据需确认 | 高 |

> 日常“部署新代码测试”优先用模式 B；只有安装配置变化或环境损坏时才用模式 C。模式 C 会执行官方 `appctl.sh uninstall override`，务必先向用户确认。

## 标准流程

所有脚本位于本 skill 的 `scripts/` 目录。下文用 `SKILL` 表示该目录的绝对路径：

```bash
SKILL=<本 skill 目录>
```

先准备环境参数和凭据（凭据只在当前 shell 环境变量中使用，不要写入文件或日志）：

```bash
export NODE0=<node0 地址>
export NODE1=<node1 地址>
export ROOT=$HOME/ograc_cluster
export SRC=$HOME/code/oGRAC
export DATA_DEV=/dev/disk/by-id/<data-lun>
export REDO_DEV=/dev/disk/by-id/<redo-lun>
export ARCH_DEV=/dev/disk/by-id/<archive-lun>
export GCC_DEV=/dev/disk/by-id/<gcc-lun>

export SUDO_PWD='<sudo 密码>'
export OGRAC_SYS_PWD='<数据库 sys 密码>'   # 仅模式 A/C 需要
```

### 第 0 步：预检（只读）

```bash
bash "$SKILL/scripts/preflight.sh"
```

检查项：SSH、`ubsmd` 服务与用户组、四个 LUN、端口占用、源码树中的可选构建适配、本实例进程。出现 `[FAIL]` 必须先解决；`[WARN]` 需判断是否影响本次操作。对多人共用机器，预检只统计 `$ROOT` 下的本实例进程。

### 第 1 步：构建安装包

```bash
bash "$SKILL/scripts/build_package.sh"
```

- 构建命令：`KEEP_DEBUG_INFO=1 sh build_ograc.sh release --with-dss atomic_lock=1`
- **进程故障恢复测试必须使用 `atomic_lock=1`（`USE_ATOMIC_LOCK=ON`）**；否则 GBP 恢复会被拒绝，页读取错误还可能直接 ABORT。`build_package.sh` 默认已带上该参数，可用 `ATOMIC_LOCK=0` 关闭。
- **耗时约 40–60 分钟，必须作为后台任务运行**（使用 agent 的后台任务机制，如 `run_in_background`），轮询日志，不要用前台 10 分钟超时。
- 产物：`$SRC/package/openGauss-oGRAC-*.tgz`
- 构建完成后脚本会打印包路径、sha256，以及 `ogracd`/`dssserver`/`cms` 的 `file` 结果；三者应为 `with debug_info, not stripped`。

构建树若依赖本地兼容修改（保留 DWARF、系统 gcc 回退、UB 命名空间隔离等），见 `references/build-workarounds.md`。如果换了分支或重新 clone 导致这些修改丢失，构建可能失败或符号被剥离；先按该文档恢复。

### 第 2 步：停止现有集群（模式 B/C 必做）

```bash
SUDO_PWD='<用户提供的 sudo 密码>' bash "$SKILL/scripts/stop_cluster.sh"
```

脚本会：停止 DB → 两节点 `appctl.sh stop` → 清理残留部署锁 → 确认本实例无 `ogracd`/`dssserver`/`cms server` 进程。

**停止前必须确认**：当前集群没有用户正在跑的测试；停止会中断所有会话。

### 第 3 步：部署

#### 模式 B：增量刷新二进制（推荐）

集群已停止后执行：

```bash
SUDO_PWD='<用户提供的 sudo 密码>' bash "$SKILL/scripts/refresh_binaries.sh"
```

脚本从 `output/` 和 `dss/` 拷贝新二进制/库到两节点安装目录，并记录拷贝前后的 sha256。默认刷新：

- `$ROOT/ograc/ograc/server/bin/ogracd` 与 `server/lib/*.so`
- `$ROOT/ograc/dss/bin/*` 与 `dss/lib/*`
- `$ROOT/ograc/cms/service/bin/cms`

**必须在集群停止状态下执行**；运行中覆盖 `.so` 会导致 `SIGSEGV`/`SIGBUS`。

#### 模式 A：全量安装

在 **node0 本机**执行节点 0 安装：

```bash
SUDO_PWD='<sudo 密码>' OGRAC_SYS_PWD='<数据库 sys 密码>' \
  bash "$SKILL/scripts/install_node.sh" \
  --node 0 \
  --package "$SRC/package/openGauss-oGRAC-<版本>.tgz" \
  --config "$SKILL/assets/config-node0.json"
```

节点 0 成功后再安装节点 1：把脚本、配置和安装包放到 node1，在 node1 上本地执行：

```bash
ssh "$SSH_USER@$NODE1" "mkdir -p $ROOT/tools"
scp "$SKILL/scripts/install_node.sh" "$SSH_USER@$NODE1:$ROOT/tools/"
scp "$SKILL/assets/config-node1.json" "$SSH_USER@$NODE1:$ROOT/tools/"
scp "$SRC/package/openGauss-oGRAC-<版本>.tgz" "$SSH_USER@$NODE1:$ROOT/package.tgz"
ssh "$SSH_USER@$NODE1"
# 在 node1 上执行；密码通过环境变量传入，不要写进命令日志
SUDO_PWD='...' OGRAC_SYS_PWD='...' bash $ROOT/tools/install_node.sh \
  --node 1 --package $ROOT/package.tgz --config $ROOT/tools/config-node1.json
```

`config-node*.json` 中的 `${NODE0}`、`${DATA_DEV}`、`${ROOT}` 等占位符由 `install_node.sh` 在安装前用环境变量渲染，未设置时会直接报错退出。`install_node.sh` 会做：解压安装包 → `chown root:root` → `chmod 777 ograc_connector` → 渲染并放置 `config_params_lun.json` → `appctl.sh pre_install` → `appctl.sh install`。数据库密码通过临时文件 + `OGRAC_SYS_PASSWORD_FILE` 传给安装器，退出时删除。

#### 模式 C：官方重装（谨慎）

```bash
# 1. 停止（脚本会处理两节点）
bash "$SKILL/scripts/stop_cluster.sh"

# 2. 在 node0 和 node1 上分别卸载（会删除安装目录/服务用户，数据是否保留需先确认）
cd $ROOT/ograc_connector/action
printf '%s\n' "$SUDO_PWD" | sudo -S -p '' sh appctl.sh uninstall override
# node1 上执行相同的 uninstall 命令

# 3. 按模式 A 重新安装
```

> `uninstall override` 会执行 `userdel -rf` 并删除安装目录。仅在对数据无保留需求、且用户明确同意时使用。

### 第 4 步：应用 UB + 串行刷盘参数（仅模式 A/C 需要）

安装会重新生成 `ogracd.ini`，必须对 **两个节点** 分别执行。先在 node0 本机执行：

```bash
UBS_CLUSTER_HOSTS='<UBS 集群主机列表>' \
  python3 "$SKILL/scripts/apply_ub_params.py" "$ROOT/dbdata/local/ograc/tmp/data/cfg/ogracd.ini"
```

再把脚本放到 node1 并在 node1 上对同一路径执行：

```bash
scp "$SKILL/scripts/apply_ub_params.py" "$SSH_USER@$NODE1:$ROOT/tools/"
ssh "$SSH_USER@$NODE1" "UBS_CLUSTER_HOSTS='<UBS 集群主机列表>' python3 $ROOT/tools/apply_ub_params.py $ROOT/dbdata/local/ograc/tmp/data/cfg/ogracd.ini"
```

参数清单见 `scripts/apply_ub_params.py` 顶部（参考 Gitee wiki “4.2 UB+串行刷盘”）。默认内存值按约 1.5TB 节点缩放，**换硬件时要按比例调整**。`UBS_CLUSTER_HOSTS` 与站点相关，必须由使用者提供；不设置时脚本不会修改该键。模式 B 不重建配置，无需重复执行。

### 第 5 步：启动

```bash
bash "$SKILL/scripts/start_cluster.sh"
```

脚本严格按以下顺序执行（与 `appctl.sh start` 不同，后者在部分环境会在 CMS reform 阶段互等）：

1. 两节点启动 DSS：`dss_contrl.sh -start 0/1`
2. 两节点启动 CMS：`cms_ctl.py start`，等待 `cms stat -server 0/1` 均为 `TRUE`
3. node0 启动 DB：`sg ubsmd -c "... ogracd open -D $DATA_DIR"`
4. 等待 node0 在 `cms stat -res db` 中变为 `ONLINE`（完成 master 选举/full-restart reform）
5. node1 启动 DB；RC 会走 `full_restart=false` 的加入路径，与运行中的 node0 组成两节点集群
6. 等待 `cms stat -res db` 两节点均为 `ONLINE`

> DB 启动/停止由 CMS 的 `db` 资源管理：`cms res -start db -node 0/1` 可设置目标状态。CMS 拉起的进程命令是 `ogracd -D <data>`（没有 `open` 参数），手工拉起的是 `ogracd open -D <data>`；脚本必须同时匹配两种形式。

可选启动 `og_om`/`ograc_exporter`：`bash "$SKILL/scripts/start_cluster.sh" --with-om`（需要 `SUDO_PWD`）。

### 第 6 步：验证

```bash
bash "$SKILL/scripts/verify_cluster.sh"
```

验证内容：

- CMS 两节点 `ONLINE`，`SRV_READY=TRUE`
- node0 建表/插入，node1 跨节点查询，node0 删除
- `dsscmd ls -p +vg2` 中 redo 文件数量与大小（默认期望 10 × 10G，可用 `REDO_FILES`/`REDO_SIZE` 覆盖）

任何一项失败，脚本以非 0 退出并打印原因。排查见 `references/troubleshooting.md`。

### 第 7 步：记录

在 `$ROOT/logs/` 下创建部署记录文件（**不含密码**），文件名示例：

```
$ROOT/logs/deploy-<YYYYMMDD-HHMMSS>.md
```

至少包含：git commit、构建时间、包路径与 sha256、部署模式、节点/端口/LUN、UB 参数、`verify_cluster.sh` 结果、人工干预项。可参考 `references/deployment-record-template.md`。

## 常见故障速查

| 现象 | 处理 |
|---|---|
| `cms load param failed` | 必须在 `$ROOT/ograc/action/cms` 目录下执行 `cms` |
| `appctl.sh start` 卡在 CMS reform / 节点互等 | 不要重试；用 `start_cluster.sh` 的顺序启动 |
| `Multiple nodes cannot be added to CMS at same time without master` | 不要并行启动；先起 node0，等 `cms stat -res db` 显示 node0 `ONLINE` 后再起 node1 |
| CMS 拉起的 `ogracd` 报 `Uds oob file path is invalid` / `Failed to initilize ubsm sdk` | CMS 进程没有 `ubsmd` 补充组；从含 `ubsmd` 组的登录会话重启 CMS（`id -nG` 应包含 `ubsmd`），或手工用 `sg ubsmd` 启动 DB |
| UB 错误 602 权限不足 | 确认 `ubsmem_shmem_allocate` 权限与两节点区域名一致；跨 UID 部署时通常需要放宽权限或统一 UID |
| `IpcCallCreateRegion` 502 / `LookupRegion` 503 | 区域名不一致或 `libogprotocol.so` 未更新；全量刷新 `output/lib/*.so` 后重启 |
| `failed to open +vg1/ctrl1` | DSS 已退出；先启动 DSS，检查 `dssinstance.rlog` |
| `appctl.sh` 报部署锁残留 | `sudo rm -rf /tmp/ograc_deploy_lock_<用户名>` 后重试 |
| `cms_daemon.py: Permission denied` | `chmod 755 $ROOT/ograc/action/cms/cms_daemon.py` |
| `og_om` 无法遍历部署用户的 home | `setfacl -m u:<服务用户>:x <部署用户 home>`，并保证目录 755/文件 644 |
| 运行中覆盖 `.so` 后 SIGSEGV/SIGBUS | 停止全部服务后再拷贝库，重新启动 |

完整故障处理（含 UB 残留对象清理、gdb 附加方法）见 `references/troubleshooting.md`。

## 关键注意点

1. **构建保留调试符号**依赖 `KEEP_DEBUG_INFO=1`；不要省略。官方 release 默认会剥离符号。
2. **二进制刷新必须停机**；CMS/DSS/DB 运行中覆盖库会导致崩溃。
3. **UB 共享内存区域名与对象前缀必须与当前源码一致**（通常形如 `shm_pool_vN_0/1`、`<user>_vN_data_buf_part_<node>`）；如果启动报 “old allocation remains”，说明存在上一次异常退出的 UB 对象。SDK 可能拒绝删除该对象（6011/602），此时只能换一个新的命名空间重新分配；不要把旧对象强行映射后复用。
4. **100% CPU 线程**：`ogracd` 启动后有一个线程常驻约 100% CPU，gdb 栈为 `ub_comm_queue::UBShmTransport::run_dispatcher_loop()`，是 UB 用户态轮询线程，不是挂死。
5. **不要在两节点同时启动 DB**；`start_cluster.sh` 先起 node0，等 node0 `ONLINE` 后再起 node1。不要改成并行启动。

## 参考

- 官方两节点编译部署：<https://docs.opengauss.org/zh/docs/latest/ograc/installation_guide/two_nodes_guide/compiling_the_version_two_node.html>
- Gitee 超节点性能测试（4.2 UB+串行刷盘）：<https://gitee.com/shirley_zhengx/openGauss-server/wikis/ograc/ograc%E8%B6%85%E8%8A%82%E7%82%B9%E6%80%A7%E8%83%BD%E6%B5%8B%E8%AF%95?sort_id=18099189#42-ub%E4%B8%B2%E8%A1%8C%E5%88%B7%E7%9B%98>
- 构建兼容修改：`references/build-workarounds.md`
- 故障处理：`references/troubleshooting.md`
- 部署记录模板：`references/deployment-record-template.md`
