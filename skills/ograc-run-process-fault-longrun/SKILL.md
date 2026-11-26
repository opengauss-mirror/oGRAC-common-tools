---
name: ograc-run-process-fault-longrun
description: 进程故障长稳测试流水线：持续执行冷备恢复 + 全冲突 TPC-C + 随机进程 SIGKILL + 故障恢复验证，测试最新代码的二进制；默认无限轮次一直跑，失败时只定位原因并记录现场，不修改代码、不部署修复。
---

# 进程故障长稳测试流水线

## 何时使用本 skill

- 用户要求跑进程故障**长稳**测试（默认无限轮次，一直跑）。
- 需要用**最新代码构建的二进制**持续验证进程 kill 后的 GBP/DRC/DLS 恢复。
- 长稳过程中出现失败，需要保存现场、定位原因、写记录（**但不修复**）。

## 不可违反的约束

1. **只操作本流水线分配的集群和用户目录**：`$PIPE`（流水线目录）、`$ROOT`（部署根目录）、`$BASE_DIR`（本轮输出），以及这些目录对应的进程。
2. **绝不修改/停止/覆盖同机其他用户的 oGRAC 实例或他人的目录/进程/端口**。禁止全局 `pkill/killall`；所有 kill 必须按用户/路径/PID 限定。
3. **长稳运行期间只做定位和记录**：
   - 禁止修改产品源码、重新构建、热更新二进制、部署“修复版”；
   - 失败证据要保存到失败目录，写分析报告并告知用户；
   - 是否修复、何时修复由用户另行决定。
4. 密码只通过文件/环境传递（默认 `$SUDO_PWD_FILE=$HOME/.spw`）；不得写入日志、命令输出或回复，脚本不得 echo 密码。
5. 停止正在运行的测试/集群前先向用户确认影响（用户明确要求时除外）。
6. gdb 等现场采集必须有界（`timeout`），采完立即 detach；不要长时间 attach。

## 环境参数

| 变量 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `NODE0` | 是 | — | node0 地址 |
| `NODE1` | 是 | — | node1 地址，SSH 免密 |
| `SSH_USER` | 否 | `$USER` | 节点间 SSH 用户 |
| `ROOT` | 否 | `$HOME/ograc_cluster` | oGRAC 部署根目录 |
| `SRC` | 否 | `$HOME/code/oGRAC` | oGRAC 源码目录（记录 commit） |
| `PIPE` | 否 | `$HOME/ograc-pipeline` | 流水线工作目录（driver/控制台/脚本/日志） |
| `BASE_BACKUP` | 否 | `$HOME/ograc_backups/tpcc_dss_clean` | 每轮冷备恢复的基线 |
| `BASE_DIR` | 否 | `$PIPE/longrun` | 本轮输出目录（控制台可传带时间戳的目录） |
| `MAX_ROUNDS` | 否 | `0` | 0 = 无限轮次 |
| `DB_PORT` | 否 | `29300` | 数据库端口 |
| `SUDO_PWD_FILE` | 否 | `$HOME/.spw` | 停库/gdb 用的 sudo 密码文件（600） |
| `WAREHOUSES` | 否 | `100` | TPC-C 仓数 |

### 流水线目录需要的外部脚本

本 skill 自带长稳驱动 `run_long_stability.sh` 和取证 `collect_failure.sh`；下列脚本属于测试流水线，需要由使用者提供并放到 `$PIPE/scripts/`：

| 文件 | 契约 |
|---|---|
| `controller_perf_randomkill.sh` | 启动 100 仓全冲突 TPC-C，warmup 后在 T0+120..180s 随机 SIGKILL 目标节点，等待 survivor GBP recovery reset，继续观察吞吐；写 `controller.out/log`、`summary.txt`、`markers.log`，成功返回 0 |
| `check_random_round.sh` | 读取本轮目录与目标节点，校验恢复是否完成；写 `check.out/log`，最后一行 `ROUND_VERDICT=...`，成功返回 0 |
| `restore_instance_from_cold_backup.sh` | 来自 `ograc-restore-cold-backup` skill，负责每轮冷备恢复 |

控制台（driver 管理）可选：任何能 `start --long`、`status`、`watch`、`stop` 的包装脚本；本文以 `$PIPE/pipelinectl` 为例。

## 标准流程

### 0. 预检

- 确认长稳 driver 是否在跑：`$PIPE/pipelinectl status`。
- 若在跑：向用户确认是否停止当前测试（长稳启动/更新二进制会停掉它）。
- 确认两节点无异常、基线可读、磁盘有空间、运行用户的 `nofile` 足够大（建议 ≥ 102400）。
- 记录当前 `git -C $SRC rev-parse HEAD` 和构建日志路径。

### 1. 构建并部署最新二进制

按 `ograc-deploy-two-node` skill 的模式 B（停机刷新 `ogracd` + `server/lib/*.so`）部署，并记录：

- git commit、build 日志、安装后 `ogracd`/`libograc.so` 的 sha256；
- 若 DSS/CMS 源码也变了，一并刷新。

若用户明确“用当前已部署二进制、不重新构建”，记录现有 sha 后继续。

### 2. 安装长稳脚本

```bash
SKILL=<本 skill 目录>
mkdir -p "$PIPE/scripts"
install -m 755 "$SKILL/scripts/run_long_stability.sh" "$PIPE/scripts/"
install -m 755 "$SKILL/scripts/collect_failure.sh"     "$PIPE/scripts/"
# 再放入 controller_perf_randomkill.sh、check_random_round.sh、
# restore_instance_from_cold_backup.sh（来自 cold-restore skill）
```

### 3. 启动长稳（默认无限轮次）

```bash
$PIPE/pipelinectl start --long
# 可选：--base DIR  指定/续跑 base；--max-rounds N  限定轮次；--force 追加到已有 base
```

- 默认 `MAX_ROUNDS=0`：**无限轮次，一直跑**。
- 默认 base：`$PIPE/longrun`（控制台通常传入带时间戳的目录）；`CURRENT_BASE` 会指向它。
- 底层驱动：`$PIPE/scripts/run_long_stability.sh`。
- 每轮失败（controller 或 check 非 0）不会退出，会调用 `collect_failure.sh` 保存现场后继续下一轮。
- 连续 3 次 restore 失败视为基础设施问题，driver 停止并记录（不当作产品失败）。

### 4. 监控

```bash
$PIPE/pipelinectl status   # 一次性
$PIPE/pipelinectl watch    # 每 10s
```

`status` 应显示 driver、当前 round、每轮 PASS/FAIL、当前 controller 尾部（kill/reset）、失败计数、CMS db 状态。

### 5. 失败处理（只定位、记录，不修复）

driver 在失败时会自动调用 `collect_failure.sh` 把现场保存到：

```
$BASE/failures/<timestamp>-round-N/
├── REPORT.md              # 模板 + 现场摘要（待 agent 补全分析）
├── EVIDENCE.md            # 证据清单
└── evidence/
    ├── controller.log / check.log / check.out / summary.txt / markers.log
    ├── gdb-bt.txt / gdb-rcy.txt        # survivor 仍活着时采集
    ├── survivor-rlog-tail.txt
    ├── target-rlog-tail.txt
    ├── dss-rlog-tail.txt / cms-rlog-tail.txt
    ├── cms-db-stat.txt / survivor-limits.txt / key-lines.txt
```

agent 的处理步骤：

1. 打开失败目录，先读 `REPORT.md`、`EVIDENCE.md`、`controller.log`、`check.log`；必要时看 `summary.txt`、`markers.log`。
2. 按 `references/failure-triage.md` 分类失败并定位第一时间因果错误：
   - recovery reset 超时 / survivor 卡住 → 看 `gdb-bt.txt`、`gdb-rcy.txt`、`markers.log` 的 `[GBP-RCY]/[DLS]`；
   - 压测启动即死 → OPEN 状态、props、DB 启动日志；
   - DB abort → target/survivor rlog 的第一个 `ABORT/panic/failed to ...`；
   - restore 失败 → 基础设施（DSS/PR/空间/UB 残留）。
3. 在 `REPORT.md` 写：现象、时间线、证据、根因（或假设 + 置信度）、影响、未修复说明；更新 `$BASE/failures/index.md`。
4. **不修改代码、不重新构建/部署、不“顺手修复”**。把结论报告给用户，由用户决定是否另起修复流程。
5. 长稳继续（除非用户要求暂停/停止）。

### 6. 停止

```bash
$PIPE/pipelinectl stop                # 停 driver/bench，保留集群
$PIPE/pipelinectl stop --with-cluster # 同时停 DB/CMS/DSS
```

也可以 `touch $BASE/STOP`，driver 会在下一轮边界优雅退出。

## 失败判定与记录

- `controller_rc=0 && check_rc=0` → PASS；否则 FAIL。
- FAIL 不停止长稳；restore 连续失败 3 次才停止（infra）。
- 每次失败必须有 `REPORT.md` + 证据目录；`failures/index.md` 汇总：时间、round、target、失败类型、结论摘要、目录。

## 安全

- 只操作分配给本流水线的集群和目录；节点可能多人共用。
- 任何停止/覆盖前确认 scope；不要触碰其他用户的实例和目录。
- gdb 采集用 `timeout`，采完 detach；不要修改寄存器/内存。

## 参考

- 失败分类与记录模板：`references/failure-triage.md`
- 冷备恢复：`ograc-restore-cold-backup` skill
- 部署/二进制刷新：`ograc-deploy-two-node` skill
- TPC-C 数据：`ograc-prepare-tpcc-data` skill
