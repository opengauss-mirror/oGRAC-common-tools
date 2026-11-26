# TPC-C 数据准备故障处理

以下命令假定：

```bash
ROOT=$HOME/ograc_cluster
BENCH=$HOME/benchmarksql
DB_PORT=29300
```

## 1. 连接失败

### `Connection refused` / `connect timed out`

先确认集群和端口：

```bash
cd $ROOT/ograc/action/cms
CMS_HOME=$ROOT/ograc/cms \
LD_LIBRARY_PATH=$ROOT/ograc/cms/service/lib:$ROOT/ograc/cms/service/add-ons \
$ROOT/ograc/cms/service/bin/cms stat -res db

ss -lnt | grep "$DB_PORT"
```

两节点必须 `ONLINE`，且 `$DB_PORT` 在监听。集群未启动时先按部署 skill 的 `start_cluster.sh` 启动。

### `password authentication failed` / `invalid username`

`TPCC_PWD` 与数据库中已有 `TPCC` 用户的密码不一致。处理方式：

1. 找到创建该用户时使用的 props 文件，通过 `--props-source` 指向它；或
2. 由用户确认后重置密码（**不要在回复/日志中打印新密码**）：

```bash
export LD_LIBRARY_PATH=$ROOT/ograc/ograc/server/lib:$ROOT/ograc/ograc/server/add-ons:/usr/local/ubs_mem/lib
printf 'y\n' | $ROOT/ograc/ograc/server/bin/ogsql "/ AS SYSDBA 127.0.0.1:$DB_PORT" \
  -D $ROOT/dbdata/local/ograc/tmp/data \
  -c "alter user TPCC identified by '<new-password>';"
```

### `TPCC_PWD is not set and no props source ...`

设置环境变量，或指定一个包含 `password=` 的既有 props：

```bash
export TPCC_PWD='...'
bash scripts/load_tpcc.sh --props-source /path/to/props.ograc
```

## 2. 表已存在

```
TPCC tables already exist. Use --recreate to drop and reload them.
```

这是保护行为。确认可以删除现有 TPCC 数据后加 `--recreate`：

```bash
bash scripts/load_tpcc.sh --warehouses 100 --recreate
```

只影响以下对象：

- `bmsql_config`
- `bmsql_warehouse`
- `bmsql_district`
- `bmsql_customer`
- `bmsql_history`
- `bmsql_oorder`
- `bmsql_order_line`
- `bmsql_new_order`
- `bmsql_stock`
- `bmsql_item`
- `bmsql_hist_id_seq`

不会删除其他 schema 或其他用户的表。

## 3. 建表失败

### `PCTFREE` / `partition by` / `CRMODE` 语法错误

说明使用的不是 oGRAC 分支的 BenchmarkSQL，而是原生 PostgreSQL 版本。确认：

```bash
grep -n 'PCTFREE\|CRMODE PAGE LOCAL' "$BENCH/run/sql.common/tableCreates_par.sql"
```

必须使用 oGRAC 分支的 BenchmarkSQL。

### `permission denied` / `insufficient privilege`

`TPCC` 用户缺少 DBA 或建表权限。由用户确认后补授权：

```bash
printf 'y\n' | $ROOT/ograc/ograc/server/bin/ogsql "/ AS SYSDBA 127.0.0.1:$DB_PORT" \
  -D $ROOT/dbdata/local/ograc/tmp/data \
  -c "grant create session to TPCC; grant create table to TPCC; grant dba to TPCC; grant inherit privileges on user SYS to TPCC;"
```

## 4. 装载慢或卡住

| 检查项 | 命令/说明 |
|---|---|
| 集群状态 | `cms stat -res db` 两节点 ONLINE |
| loader 进程 | `pgrep -af 'LoadData'` |
| CPU/内存 | `top`、`free -g` |
| DSS | `ps -eo pid,args | grep "$ROOT/ograc/dss/bin/dssserver"`；DSS 退出会导致装载失败 |
| 日志 | `$ROOT/logs/tpcc-load-*.log`、`$ROOT/ograc/log/ograc/run/ogracd.rlog` |

100 仓基线约 3 分钟（50 workers）。如果明显更慢：

- 提高 `--workers`（如 80、100），但不要超过数据库连接/CPU 承受能力；
- 检查是否有其他压测/恢复任务同时运行；
- 检查 DSS/网络是否异常。

装载中的正常进度行：

```
Worker 007: Loading Warehouse     42
Worker 007: Loading Warehouse     42 done
```

## 5. 行数不符

先单独运行校验：

```bash
bash scripts/verify_tpcc.sh --warehouses 100
```

- `bmsql_order_line` 在 `N × 300,000` 的 ±10% 内属正常（每单 5–15 行随机）。
- 其他表必须精确匹配；不匹配通常说明装载中途失败或被中断。
- 重新导入：加 `--recreate`。

## 6. 磁盘空间

100 仓数据量约 10–30GB（含索引）。检查数据 VG：

```bash
export DSS_HOME=$ROOT/ograc/dss
export LD_LIBRARY_PATH=$DSS_HOME/lib:/usr/local/ubs_mem/lib
$DSS_HOME/bin/dsscmd ls -p +vg1
```

空间不足时先清理旧测试数据或换更大 LUN，不要删除他人文件。

## 7. 生成的 props 文件

- 路径：`$BENCH/run/props_tpcc_<N>w_<timestamp>.ograc`
- 权限：`600`
- 内容包含数据库密码，**不要复制到共享目录、不要提交到 git、不要在回复中打印**。
- 压测时可直接复用；不需要每次重新生成。
