# 部署记录模板

每次按本 skill 完成部署后，在 `$ROOT/logs/deploy-<YYYYMMDD-HHMMSS>.md` 记录一次。**不要记录任何密码。**

## 版本与产物

| 项 | 值 |
|---|---|
| 分支/标签 | `<branch>` |
| commit | `<git rev-parse HEAD>` |
| 构建命令 | `KEEP_DEBUG_INFO=1 sh build_ograc.sh release --with-dss atomic_lock=1` |
| 构建日志 | `$ROOT/logs/build-<timestamp>.log` |
| 包路径 | `$SRC/package/openGauss-oGRAC-<version>.tgz` |
| 包 sha256 | `<sha256>` |
| 包大小 | `<bytes>` |

安装后二进制（两节点应一致）：

| 文件 | BuildID | 调试信息 |
|---|---|---|
| `ogracd` | `<build-id>` | `with debug_info, not stripped` |
| `dssserver` | `<build-id>` | 同上 |
| `cms` | `<build-id>` | 同上 |

## 集群状态基线

`cms stat -res db`：

```
NODE_ID   RESOURCE_NAME   STAT     PRE_STAT   TARGET_STAT   WORK_STAT
0         db              ONLINE   OFFLINE    ONLINE        1
1         db              ONLINE   OFFLINE    ONLINE        1
```

`cms stat -server 0/1`：均为 `SRV_READY = TRUE`。

跨节点 SQL：node0 建表插入、node1 查询返回、删除成功。

redo：`+vg2` 下 redo 文件数量与大小（默认 10 × 10G）。

## 关键路径

| 项 | 值 |
|---|---|
| ROOT | `<ROOT>` |
| 安装目录 | `$ROOT/ograc` |
| 数据目录 | `$ROOT/dbdata/local/ograc/tmp/data` |
| 安装器 action | `$ROOT/ograc_connector/action` |
| 安装日志 | `$ROOT/logs/install-node{0,1}-*.log` |
| 运行日志 | `$ROOT/ograc/log/ograc/run/ogracd.rlog` |
| DB 启动输出 | `$ROOT/ograc/log/ograc/ogracstatus.log` |

## 端口与磁盘

- CMS `<CMS_PORT>`，DSS `<DSS_PORT>`，DB `<DB_PORT>`，interconnect `<INTERCONNECT_PORT>`
- data `<DATA_DEV>`
- redo `<REDO_DEV>`
- archive `<ARCH_DEV>`
- gcc `<GCC_DEV>`

## UB + 串行刷盘参数

见 `scripts/apply_ub_params.py`；落地文件：

```
$ROOT/dbdata/local/ograc/tmp/data/cfg/ogracd.ini
```

记录关键值（`DATA_BUFFER_SIZE`、`DTC_REMOTE_SGA_SIZE`、`DTC_REMOTE_DATA_BUF_SIZE`、`LOG_BUFFER_COUNT`、`LOG_BUFFER_SIZE`、`CHECKPOINT_IO_CAPACITY`、`DBWR_PROCESSES`、`MES_POOL_SIZE`、`ENABLE_DBSTOR_BATCH_FLUSH`）以及 `UBS_CLUSTER_HOSTS`。

## 已知环境差异

1. 两节点部署用户 UID/GID 是否一致；UB 段权限与命名空间代次。
2. 是否回退系统 gcc（第三方 gcc 工具链是否可用），CBB/DSS 是否加了 `-Wno-error`。
3. `appctl.sh start` 是否会在 CMS reform 阶段互等；本环境使用 `start_cluster.sh` 顺序启动。
4. `ogracd` 是否有 UB 轮询线程常驻约 100% CPU。
5. 人工干预项与原因。
