# oGRAC Skills

面向 oGRAC 测试与运维的可复用 agent skills。每个子目录都是一个独立 skill，入口为 `SKILL.md`，可按需复制到 agent 的 skills 目录中使用（例如 `.claude/skills/`、`.opencode/skills/`、`.agents/skills/`）。

## 特点

- **环境无关**：不包含任何真实主机、用户名、LUN WWID、密码或本地路径；节点地址、部署目录、端口、LUN 等全部通过环境变量传入。
- **可脚本化**：每个 skill 自带 `scripts/`、`references/`，按 SKILL.md 的步骤执行即可。
- **多人共用主机安全**：只操作当前用户/当前部署 ROOT 的进程和资源，禁止宽泛 `pkill`/`killall`；停止/覆盖前要求确认。

## Skill 列表

| Skill | 简介 |
|---|---|
| [`ograc-two-node-deploy`](ograc-two-node-deploy/SKILL.md) | 构建、安装、启动、验证 oGRAC 两节点测试集群；支持全量安装、停机增量刷新二进制、按验证过的顺序重启。 |
| [`ograc-cold-restore`](ograc-cold-restore/SKILL.md) | 用 `dsscmd cp` 做停机一致的冷备与整实例回拷；处理 ctrl 尺寸、DSS 假死、SCSI PR、UB pool 残留和启动顺序。 |
| [`tpcc-prepare-data`](tpcc-prepare-data/SKILL.md) | 为 oGRAC 集群准备 TPC-C 数据（默认 100 仓）：建用户、生成 props、并行装载、建索引并校验行数。 |
| [`ograc-process-fault-longrun`](ograc-process-fault-longrun/SKILL.md) | 进程故障长稳流水线：冷备恢复 + 全冲突 TPCC + 随机 SIGKILL + 恢复验证；默认无限轮次，失败只定位记录、不改代码。 |

## ograc-two-node-deploy

**作用**：在 self-owned 的两节点 oGRAC 测试集群上完成 release with debug info 构建、安装、启动和验证，并固化一组 UB + 串行刷盘参考参数。

**适用场景**：

- 把当前代码部署到两节点测试集群；
- 需要重新构建带调试符号的安装包；
- 不停数据、只刷新 `ogracd`/DSS/CMS 二进制；
- 集群启动失败，需要按 DSS → CMS → node0 → node1 的顺序重启。

**前置条件**：

- 两节点可 SSH 免密互访，且 `ubsmd` 服务在两节点均为 active；
- 已分配四个 LUN（data/redo/archive/gcc），并能提供 `/dev/disk/by-id/...` 路径；
- sudo 密码、数据库 sys 密码由使用者通过环境变量提供。

**主要内容**：

- `SKILL.md`：部署模式选择、7 步标准流程、故障速查；
- `scripts/preflight.sh`、`build_package.sh`、`install_node.sh`、`refresh_binaries.sh`、`start_cluster.sh`、`stop_cluster.sh`、`verify_cluster.sh`、`apply_ub_params.py`；
- `references/build-workarounds.md`、`troubleshooting.md`、`deployment-record-template.md`；
- `assets/`：两节点 LUN 配置模板（`${...}` 占位符，由 `install_node.sh` 渲染）和构建补丁。

**安全注意**：所有进程匹配都限定在 `$ROOT` 内；停止/卸载/覆盖安装/重启 `ubsmd` 前必须确认影响范围。

## ograc-cold-restore

**作用**：在 oGRAC 两节点集群上做停机一致的数据基线冷备，以及从冷备整实例回拷；不走 `ogbackup` 在线备份链。

**适用场景**：

- TPC-C 数据导入完成后保存基线；
- 测试后把实例回滚到某个冷备点；
- 排查 ctrl 文件尺寸、DSS 假死、SCSI PR 残留、UB pool 残留和启动顺序问题。

**前置条件**：

- 两节点 `NODE0`/`NODE1` 可 SSH 免密，DSS 安装目录可用；
- 清 PR 需要四个 LUN 设备路径和可选 sudo 密码文件（默认 `$HOME/.spw`）；
- 恢复会覆盖当前数据，必须确认可以丢弃。

**主要内容**：

- `SKILL.md`：冷备、配置另存、一键恢复流程，以及 8 类关键经验和故障速查；
- `scripts/dss_cold_backup.sh`、`dss_cold_restore.sh`、`restore_instance_from_cold_backup.sh`、`start_db_pair.sh`、`ub_pool_tool.c`；
- `ub_pool_tool.c` 清理本用户所有命名空间代次的 GBP buffer，不触碰其他用户。

**安全注意**：PR 清理只在全部服务停止后执行；所有 kill 都按 PID + 命令行 + 本实例 data dir 校验；其他用户的 SysV 段和 UB pool 只告警不删除。

## tpcc-prepare-data

**作用**：使用 oGRAC 分支的 BenchmarkSQL 准备 TPC-C 数据（默认 100 仓），包含建用户、生成 props、分区表 DDL、并行装载、索引和行数校验。

**适用场景**：

- 首次导入或重建 TPCC 数据；
- 为新代码测试准备压测基线；
- 校验现有 TPCC 数据是否完整。

**前置条件**：

- 集群 `OPEN READ WRITE`，CMS 两节点 `ONLINE`；
- 已安装 oGRAC 分支的 BenchmarkSQL（包含 `PCTFREE`、`CRMODE` 等扩展语法）；
- `TPCC_PWD` 或既有 props 中的密码由使用者提供。

**主要内容**：

- `SKILL.md`：参数、执行流程、行数校验公式、常见故障；
- `scripts/load_tpcc.sh`、`verify_tpcc.sh`；
- `assets/props.template.ograc`；
- `references/benchmarksql-notes.md`、`troubleshooting.md`。

**安全注意**：只操作 `TPCC` schema 下的 `bmsql_*`；`--recreate` 前必须确认；props 文件权限必须为 600，且不得提交或打印密码。

## ograc-process-fault-longrun

**作用**：驱动进程故障长稳测试流水线：每轮冷备恢复 → 启动两节点 DB → 全冲突 TPC-C → 随机 SIGKILL 目标节点 → 等待 survivor GBP recovery reset → 校验；默认无限轮次。

**适用场景**：

- 用最新代码构建的二进制持续验证进程 kill 后的 GBP/DRC/DLS 恢复；
- 长稳失败时保存现场、定位根因并记录（不修复）。

**前置条件**：

- 已按 `ograc-two-node-deploy` 部署二进制，并有可读的冷备基线（推荐来自 `ograc-cold-restore`）；
- `$PIPE` 下已有 controller、check、restore 三个外部脚本（契约见 `SKILL.md`）；
- 两节点 SSH 免密，运行用户 `nofile` ≥ 102400，`$SUDO_PWD_FILE`（默认 `$HOME/.spw`）可读。

**主要内容**：

- `SKILL.md`：环境参数、外部脚本契约、启动/监控/失败处理/停止流程；
- `scripts/run_long_stability.sh`：无限轮次驱动，失败自动取证并继续；
- `scripts/collect_failure.sh`：有界、只读取证（日志尾部、CMS 状态、gdb backtrace、证据索引）；
- `references/failure-triage.md`：失败分类、判读方法和 REPORT.md 模板。

**安全注意**：长稳期间禁止修改代码/重建/部署；所有 kill 按用户/路径/PID 限定；gdb 采集有界并立即 detach。

## 通用约定

- 密码只通过环境变量或受保护的密码文件传递，不写入日志、命令输出或提交内容。
- 节点地址使用 `NODE0`/`NODE1`，部署根目录使用 `ROOT`（默认 `$HOME/ograc_cluster`），源码目录使用 `SRC`。
- 任何“停止/删除/覆盖”动作都先确认目标属于当前部署。

## 许可证

与仓库一致：MulanPSL-2.0。
