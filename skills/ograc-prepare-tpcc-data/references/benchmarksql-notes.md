# BenchmarkSQL / oGRAC 说明

## 工具位置

- 目录：`$BENCH`（默认 `$HOME/benchmarksql`），必须是包含 oGRAC 扩展语法的分支。
- 入口：
  - `run/runDatabaseBuild.sh`：建表 + 装载 + 索引 + analyze
  - `run/runBenchmark.sh`：压测
  - `run/runSQL.sh`：执行单个 SQL 文件

## 方言

props 中使用：

```
db=postgres
driver=org.postgresql.Driver
conn=jdbc:oGRAC://<host>:<port>
```

`db=postgres` 会使用 `run/sql.postgres/` 与 `run/sql.common/` 下的 SQL；这些 SQL 包含 oGRAC 扩展语法：

- `PCTFREE 50`
- `partition by RANGE(...) INTERVAL(1)`
- `partition by hash(...) partitions 2000`
- `using index(create ... CRMODE PAGE LOCAL)`
- `analyze table ... compute statistics`

因此必须使用 oGRAC 分支的 BenchmarkSQL，原生 BenchmarkSQL 的 PostgreSQL 脚本不兼容。

## 装载流程

`runDatabaseBuild.sh` 默认步骤：

1. `sql.common/tableCreates_par.sql`
2. `runLoader.sh`（Java `LoadData`，`loadWorkers` 个并行连接）
3. `sql.common/indexCreates_par.sql`
4. `sql.postgres/buildFinish.sql`

`tableDrops` 不包含在 build 中；本 skill 在 `--recreate` 时先单独执行。

## 行数公式（N 仓）

| 表 | 行数 |
|---|---:|
| `bmsql_warehouse` | N |
| `bmsql_district` | N × 10 |
| `bmsql_item` | 100,000 |
| `bmsql_stock` | N × 100,000 |
| `bmsql_customer` | N × 30,000 |
| `bmsql_history` | N × 30,000 |
| `bmsql_oorder` | N × 30,000 |
| `bmsql_new_order` | N × 9,000 |
| `bmsql_order_line` | ≈ N × 300,000（每单 5–15 行） |

## 参考基线

| 仓数 | workers | 耗时 | 环境 |
|---:|---:|---|---|
| 100 | 50 | 约 3 分钟 | 两节点、release with debug info、NVMe + UB |

实际耗时随 CPU、内存、DSS 和网络变化。

## 压测

生成 props 后：

```bash
cd "$BENCH/run"
./runBenchmark.sh props_tpcc_100w_<timestamp>.ograc
```

需要多终端/多节点时，可在 props 中调整 `terminals`；多节点运行时让各节点的 `resultDirectory` 不同。

## 数据与配置保护

- props 文件包含密码，权限必须为 `600`。
- 装载数据位于 `TPCC` schema；压测账号也是 `TPCC`。
- 不要用 `runSQL.sh tableDrops` 清理其他 schema；它只包含 `bmsql_*` 和 `bmsql_hist_id_seq`。
