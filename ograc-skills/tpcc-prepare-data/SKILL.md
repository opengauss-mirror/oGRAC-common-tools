---
name: tpcc-prepare-data
description: 为 oGRAC 测试集群准备 TPC-C 数据（默认 100 仓）：检查/创建 TPCC 用户、生成 BenchmarkSQL props、建表分区、并行装载、创建索引并校验行数。用于首次导入、重建 TPCC 数据或为新代码测试准备压测基线。
---

# TPC-C 测试数据准备（oGRAC）

## 何时使用本 skill

- 用户要求“导入/准备 TPC-C 数据”“建 100 仓”“重建 TPCC 数据”。
- 需要在 oGRAC 集群上为 `runBenchmark.sh` 准备数据基线。
- 数据导入不完整或表结构需要重建。

## 不可违反的约束

1. **只操作 `TPCC` schema 下的 `bmsql_*` 表和 `bmsql_hist_id_seq` 序列**。不要 drop 其他 schema/表。
2. **密码只通过环境变量 `TPCC_PWD` 传入，或从既有 BenchmarkSQL props 文件读取**；禁止把密码打印到终端、日志、报告或聊天回复。生成的 props 文件必须为 `600`。
3. `--recreate` 会删除现有 TPCC 数据，执行前必须向用户确认。
4. 集群必须处于 `OPEN READ WRITE` 且 CMS 两节点 `ONLINE`；不满足时先启动/修复集群，不要强行导入。
5. 多人共用机器：只使用分配的数据库用户和 `bmsql_*` 对象；不要改动其他用户的 schema、进程、端口。

## 环境参数

| 变量/参数 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `NODE0` | 是* | — | 数据库连接地址；*使用 `CONN`/`--conn` 时可不设 |
| `DB_PORT` | 否 | `29300` | 数据库端口 |
| `CONN` | 否 | `jdbc:oGRAC://$NODE0:$DB_PORT` | JDBC 连接串 |
| `DB_USER` | 否 | `TPCC` | 数据库用户/schema |
| `BENCH` | 否 | `$HOME/benchmarksql` | BenchmarkSQL（oGRAC 分支）目录 |
| `ROOT` | 否 | `$HOME/ograc_cluster` | oGRAC 部署根目录（本地 `ogsql`、日志） |
| `WAREHOUSES` | 否 | `100` | 仓库数 |
| `WORKERS` | 否 | `50` | `loadWorkers` 并行度 |

参考：100 仓在示例环境中约 3 分钟（NVMe + UB），实际取决于硬件和集群状态。

## 快速开始

默认导入 100 仓：

```bash
SKILL=<本 skill 目录>
export CONN='jdbc:oGRAC://<node>:<port>'   # 或设置 NODE0/DB_PORT
export TPCC_PWD='<TPCC 用户密码>'          # 由用户提供；不写入文件/日志
bash "$SKILL/scripts/load_tpcc.sh"
```

若本机已有可用的 BenchmarkSQL props（包含 `password=` 行），可以省略 `TPCC_PWD`，脚本会自动从最新的 `props_*load*.ograc` / `props_tpcc_*.ograc` 读取密码，不回显：

```bash
bash "$SKILL/scripts/load_tpcc.sh"
```

指定仓数/并行度：

```bash
bash "$SKILL/scripts/load_tpcc.sh" --warehouses 200 --workers 80
```

重建已有 TPCC 数据（**会 drop 现有 `bmsql_*`**，先确认）：

```bash
bash "$SKILL/scripts/load_tpcc.sh" --warehouses 100 --recreate
```

只做检查、不实际导入：

```bash
bash "$SKILL/scripts/load_tpcc.sh" --dry-run
```

## 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `--warehouses N` | 100 | 仓库数 |
| `--workers N` | 50 | `loadWorkers` 并行度 |
| `--conn URL` | `jdbc:oGRAC://$NODE0:$DB_PORT` | JDBC 连接串 |
| `--user NAME` | `TPCC` | 数据库用户/schema |
| `--bench DIR` | `$HOME/benchmarksql` | BenchmarkSQL 目录 |
| `--props-source FILE` | 自动选择 | 复用其中的 `password=`，不回显 |
| `--recreate` | 否 | 先 `tableDrops` 再导入 |
| `--no-verify` | 否 | 跳过导入后的行数校验 |
| `--dry-run` | 否 | 打印计划后退出 |

## 执行流程

`scripts/load_tpcc.sh` 会按顺序完成：

1. 检查 BenchmarkSQL、集群 `ogsql`、数据目录是否存在。
2. 解析 `TPCC_PWD`（环境变量优先，否则从 props 源读取）。
3. 检查 `TPCC` 用户；不存在则创建并授予 `create session`、`create table`、`dba`、`inherit privileges on user SYS`。
4. 生成 props：`$BENCH/run/props_tpcc_<N>w_<timestamp>.ograc`（`600`）。
5. 检查 `TPCC.bmsql_warehouse` 是否存在：
   - 不存在：直接导入。
   - 已存在且未指定 `--recreate`：停止并提示。
   - 已存在且指定 `--recreate`：先 `runSQL.sh tableDrops`（忽略不存在的表），再导入。
6. 执行 `runDatabaseBuild.sh <props>`，依次：
   - `sql.common/tableCreates_par.sql`（分区表 DDL）
   - `LoadData`（多 worker 并行装载）
   - `sql.common/indexCreates_par.sql`（主键/索引）
   - `sql.postgres/buildFinish.sql`（`analyze`）
7. 调用 `scripts/verify_tpcc.sh` 校验行数。
8. 在 `$ROOT/logs/` 写导入记录（不含密码）。

日志实时写入：

```
$ROOT/logs/tpcc-load-<N>w-<timestamp>.log
```

100 仓通常 3 分钟左右；200 仓以上建议作为后台任务运行并轮询日志。

## 行数校验公式

`scripts/verify_tpcc.sh --warehouses N` 期望值：

| 表 | 期望行数 |
|---|---:|
| `bmsql_warehouse` | `N` |
| `bmsql_district` | `N × 10` |
| `bmsql_item` | `100,000`（与仓数无关） |
| `bmsql_stock` | `N × 100,000` |
| `bmsql_customer` | `N × 30,000` |
| `bmsql_history` | `N × 30,000` |
| `bmsql_oorder` | `N × 30,000` |
| `bmsql_new_order` | `N × 9,000` |
| `bmsql_order_line` | 约 `N × 300,000`（每单 5–15 行随机） |

`bmsql_order_line` 允许 ±10% 偏差；其余表必须精确匹配。

## 导入后

生成的 props 是 **load-only**（`terminals=1`、`runMins=1`）。压测时复制一份并调整 `terminals`/`runMins`：

```bash
cd "$BENCH/run"
cp props_tpcc_100w_<timestamp>.ograc props_tpcc_100w_bench.ograc
# 编辑 props_tpcc_100w_bench.ograc：terminals=100，runMins=10
./runBenchmark.sh props_tpcc_100w_bench.ograc
```

需要多节点压测时，在各节点分别启动 `runBenchmark.sh`，并让 props 的 `resultDirectory` 按节点区分。

## 常见故障

| 现象 | 处理 |
|---|---|
| `Connection refused` / `SQLException` | 确认集群 `cms stat -res db` 两节点 ONLINE、`DB_PORT` 端口监听 |
| `password authentication failed` | `TPCC_PWD` 与已有用户密码不一致；提供正确密码，或确认后重建用户 |
| `table bmsql_* already exists` | 需要重建时加 `--recreate`；否则保留现有数据 |
| DDL 报 `PCTFREE` / `partition` 语法错误 | 确认使用的 BenchmarkSQL 是 oGRAC 分支（`sql.common` 内含 oGRAC 扩展语法） |
| 装载很慢 | 提高 `--workers`（如 80/100），检查 DSS/网络/CPU |
| 行数不符 | 重新执行 `verify_tpcc.sh`；若 `order_line` 偏差在 ±10% 内属正常 |
| 磁盘不足 | 100 仓约 10–30GB；检查 data VG 容量 |

完整排查见 `references/troubleshooting.md`，工具说明见 `references/benchmarksql-notes.md`。
