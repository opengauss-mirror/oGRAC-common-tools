# 两节点 oGRAC 集群故障处理

本文记录两节点部署/启动过程中常见的问题与处理方式。所有命令均假定：

```bash
ROOT=$HOME/ograc_cluster
NODE0=<node0 地址>
NODE1=<node1 地址>
SSH_USER=$USER
```

## 1. 启动/停止

### 1.1 `appctl.sh start` 卡住或两节点互等

现象：node0 执行 `appctl.sh start` 后长时间停在 CMS reform / `cms res -start db`；node1 报：

```
Multiple nodes cannot be added to CMS at same time without master
```

处理：不要反复重试。`appctl.sh stop` 两节点后，用 `start_cluster.sh` 的顺序启动：

1. DSS 两节点
2. CMS 两节点，等 `cms stat -server 0/1` 都为 `TRUE`
3. DB node0，再 node1

### 1.2 `cms load param failed`

`cms` 必须在 action 目录下执行（它按当前目录加载配置）：

```bash
cd $ROOT/ograc/action/cms
CMS_HOME=$ROOT/ograc/cms \
LD_LIBRARY_PATH=$ROOT/ograc/cms/service/lib:$ROOT/ograc/cms/service/add-ons \
$ROOT/ograc/cms/service/bin/cms stat -res db
```

### 1.3 部署锁残留

`appctl.sh` 报锁冲突时：

```bash
printf '%s\n' "$SUDO_PWD" | sudo -S -p '' rm -rf /tmp/ograc_deploy_lock_$USER
```

node1 上同样处理。确认没有其他部署进程正在运行时才删除。

### 1.4 `cms_daemon.py: Permission denied`

安装包解压后文件模式可能是 644：

```bash
sudo chmod 755 $ROOT/ograc/action/cms/cms_daemon.py
sudo chmod 755 $ROOT/ograc/action/cms
```

### 1.5 `og_om` 无法遍历部署用户的 home

监控服务用户需要能进入部署用户的 home 目录：

```bash
sudo setfacl -m u:<服务用户>:x <部署用户 home>
# 必要时保证部署目录 755、文件 644
```

## 2. UB 共享内存

### 2.1 错误 602：权限不足

常见原因：两节点部署用户 UID 不一致，node0 以 `0600` 创建的段 node1 无法打开。

可选做法：

- 让两节点部署用户 UID/GID 一致（推荐）；
- 或在源码中把 `ubsmem_shmem_allocate(..., 0600, ...)` 调整为 `0666`，并使用同一代次的区域/对象名隔离：
  - `shm_pool_vN_<node_id>`
  - `<user>_vN_data_buf_part_<node>`

修改后必须重新编译并刷新 `ogracd` 与 `output/lib/*.so`，只换 `ogracd` 不够。

### 2.2 `IpcCallCreateRegion` 502 / `LookupRegion` 503

原因：`ogracd` 里的区域名与 `libogprotocol.so` 中的区域名不一致（只更新了 `ogracd`，没更新库）。

处理：

1. 停止全部服务。
2. 确认 `output/bin/ogracd` 和 `output/lib/*.so` 都来自同一次构建。
3. 刷新 `$ROOT/ograc/ograc/server/bin/ogracd` 与 `$ROOT/ograc/ograc/server/lib/*.so`。
4. 两节点都执行，再按顺序启动。

### 2.3 region / object 已存在或残留

反复失败的启动会在 UB 侧留下对象。先查日志确认名称：

```bash
grep -E 'data_buf|shm_pool|region' $ROOT/ograc/log/ograc/run/ogracd.rlog | tail -50
```

可用 UBS SDK 写一个只删除本人对象的小工具（编译时链接 `-lubsm_sdk`），以 `ubsmd` 组执行。若仍无法清理，`systemctl restart ubsmd`（会影响同机所有用户，必须先确认）后再启动。

### 2.4 `ubsmem_shmem_deallocate` 报对象不存在

如果该节点使用新的隔离代次名称，旧的 `v1/v2/...` 对象可以忽略；不要为了清理旧对象去改回旧名称。

## 3. DSS / CMS 崩溃

### 3.1 运行中覆盖 `.so` 导致 SIGSEGV / SIGBUS

现象：`dssserver` 崩溃、`cms` 报 `SIGBUS`，或后续 `failed to open +vg1/ctrl1`。

原因：在服务运行时覆盖了 `$ROOT/ograc/ograc/server/lib/*.so` 或安装目录中的库。

处理：停止全部服务 → 重新拷贝库 → 启动 DSS → CMS → DB。**任何二进制/库刷新都必须在停机状态执行**。

### 3.2 `failed to open +vg1/ctrl1`

DSS 已退出或未启动。检查：

```bash
pgrep -af "$ROOT/ograc/dss/bin/dssserver"
tail -50 $ROOT/ograc/log/dss/run/dssinstance.rlog
```

先启动 DSS，再启动 CMS/DB。

### 3.3 DSS 命令报 `DSS_HOME not found`

```bash
export DSS_HOME=$ROOT/ograc/dss
export LD_LIBRARY_PATH=$DSS_HOME/lib:/usr/local/ubs_mem/lib
$DSS_HOME/bin/dsscmd ls -p +vg2
```

## 4. 调试与观察

### 4.1 gdb 附加报 `Operation not permitted`

`ogracd` 可能设置不可 dump（`/proc/<pid>/exe` 也不可读），同用户 gdb 无法附加。需要 root：

```bash
printf '%s\n' "$SUDO_PWD" | sudo -S -p '' gdb -batch -p <tid> -ex 'bt'
```

gdb 采集必须有界（`timeout`），采完立即 detach；不要长时间 attach。

### 4.2 一个线程常驻约 100% CPU

栈示例：

```
ub_comm_queue::UBShmTransport::poll_and_dispatch_once(...)
ub_comm_queue::UBShmTransport::run_dispatcher_loop()
```

这是 UB 用户态轮询线程，不是死循环。只要 DB 可正常连接和查询即可忽略。

### 4.3 日志位置

| 组件 | 日志 |
|---|---|
| DB | `$ROOT/ograc/log/ograc/run/ogracd.rlog` |
| DB 启动输出 | `$ROOT/ograc/log/ograc/ogracstatus.log` |
| DSS | `$ROOT/ograc/log/dss/run/dssinstance.rlog` |
| CMS | `$ROOT/ograc/log/cms/*.log` |
| 安装/部署 | `$ROOT/log/ograc/ograc_deploy.log` |
| 本 skill 操作 | `$ROOT/logs/{build,install,start,stop}-*.log` |

## 5. 进程处理原则

- 先 `ps -eo pid=,comm=,args=` 或 `pgrep -af` 看明确 PID 和完整命令行。
- 只对确认属于 `$ROOT` 的 PID 操作。
- 禁止 `pkill -f ogracd` 这类宽泛匹配：同机可能有他人的 oGRAC 进程，也可能误杀当前 shell。
- 需要强制终止时，逐 PID `kill <pid>`，必要时 `kill -9 <pid>`，并记录原因。
