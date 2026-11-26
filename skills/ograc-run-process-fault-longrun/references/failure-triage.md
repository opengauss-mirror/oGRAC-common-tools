# 长稳失败定位与记录（只定位、记录，不修复）

## 输入

`collect_failure.sh` 已把现场保存到：

```
$BASE/failures/<timestamp>-round-N/
├── REPORT.md
├── EVIDENCE.md
└── evidence/
    ├── controller.log / controller.out / check.log / check.out / summary.txt / markers.log
    ├── gdb-bt.txt / gdb-rcy.txt        # survivor 仍存活时
    ├── survivor-rlog-tail.txt / target-rlog-tail.txt
    ├── dss-rlog-tail.txt / cms-rlog-tail.txt
    ├── cms-db-stat.txt / survivor-state.txt / key-lines.txt
```

## 步骤

### 1. 先分类

| controller/check 现象 | 类型 | 先看 |
|---|---|---|
| `FAIL: recovery reset not observed within 300s` | survivor 恢复卡住/超时 | `gdb-bt.txt`、`gdb-rcy.txt`、`markers.log`、`key-lines.txt` |
| `ABORT: a benchmark died during startup` | 压测启动失败 | DB 是否 `OPEN`、props、DB 启动日志、`survivor/target-rlog-tail.txt` |
| `[LOG] ABORT INFO: flush redo filed` / panic | DB 主动 abort | rlog 中第一个 `ABORT/panic/failed to ...` |
| `RESTORE FAILED` | 基础设施 | `restore.out`、DSS 日志、PR/空间/UB 残留 |
| `survivor result.csv not found` | harness | props `resultDirectory` 前缀、结果目录 |

### 2. survivor 卡住时的判读

- `gdb-rcy.txt`：
  - `g_gbp_rcy.phase`：`0=OFF,1=FREEZING,2=ANALYSIS,3=REPLAY,4=READY,5=RETIRING,6=RETIRED`；
  - `count`、`abort_node`、`failed`。
- `gdb-bt.txt` 重点线程：
  - `gbp_retire_proc` 是否在 `cm_sleep` 循环（RETIRING 未完成）；
  - 业务线程是否卡在 `ub_rw_lock_x_lock_local` / `gbp_lock_is_x_held_word`（GBP 锁/门闩）；
  - `buf_latch_x`（同一 ctrl latch 争用）；
  - `dtc_primary_load_partial_deposit_tx_area` 等 `DB_IN_BG_ROLLBACK`；
  - `dls_wait_txn`（DLS 事务等待）。
- 对照 `docs/gbp_store_fence_retire_deadlock_20261108.md` 的 lock word 解码（bit53 readonly、x_node、x_tid）与 ctrl 字段。如果**最新二进制**上仍出现同一签名，说明修复未覆盖该路径，明确记录；不要在现场改代码。
- 若 survivor 已死：看 `target/survivor-rlog-tail.txt` 的最后 `ABORT/panic`；`cms-db-stat.txt` 的最终状态。

### 3. DB abort 时

- 在 `survivor-rlog-tail.txt` 或 `target-rlog-tail.txt` 中找到**第一个** `ABORT|panic|failed to`，记录：
  - 页面 ID、page lsn/pcn、redo 文件名、错误码；
  - 之前是否有 `failed to write`、`CHECK_PAGE_PCN`、pcrb `knl_internal_delete`、DSS/DLS 错误。
- 对照已知问题文档：`docs/gbp_pcrb_delete_old_key_analysis_20261108.md` 等。

### 4. 压测启动失败

- 看 `perf-node0.log`/`perf-node1.log`（controller 目录或 `$PIPE/perf-*.log`）的 Java 异常；
- `Ordinary user login must in OPEN status`：DB 尚未 OPEN（controller 已有 `wait_db_open`，若仍出现说明等待被绕过/超时）；
- 连接失败：props `conn`、端口、监听地址、防火墙；
- `result.csv not found`：node1 props 的 `resultDirectory=result_tpcc_conflict_205_...`。

### 5. 写 REPORT.md

固定小节：

```markdown
## 现象
（一两句 + verdict）

## 时间线
- HH:MM:SS kill nodeX
- HH:MM:SS recovery reset（或超时）
- HH:MM:SS 失败判定

## 关键证据
- 引用的 evidence 文件名 + 关键行/栈帧

## 根因分析
- 直接原因：
- 根因/假设（置信度：高/中/低）：
- 与已知问题的关系：

## 结论 / 后续
- 是否已知问题：
- 未修复说明：
- 建议用户下一步（例如另起修复分支、补充复现条件）：
```

更新 `$BASE/failures/index.md`，追加一行摘要。

## 铁律

- 长稳流程中**不允许**修改产品源码、重新构建、热更新/部署二进制、改配置“绕过”。
- 不允许为了继续跑而隐藏失败；失败必须保留目录并记录。
- 需要修复时，先向用户报告，由用户决定是否另起修复流程。
