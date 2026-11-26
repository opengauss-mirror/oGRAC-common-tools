---
name: ograc-restore-cold-backup
description: 用 dsscmd cp 冷备/恢复 oGRAC 实例（不走 ogbackup 在线备份链）。用于干净停机后的数据基线备份、整实例回拷、TPC-C 数据回滚，以及排查 ctrl 尺寸、DSS 假死、SCSI PR/启动顺序问题。
---

# oGRAC 冷备与实例恢复（dsscmd cp）

## 何时使用

- 需要在自有两节点 oGRAC 集群上保留一份**停机一致**的数据基线。
- 需要把实例快速回滚到某个冷备点（例如 TPC-C 导入完成后）。
- 不走 `ogbackup` 的在线全备/离线恢复链，直接用 `dsscmd cp` 拷贝/回拷 DSS 文件。

## 不可违反的约束

1. **只操作本实例的目录和进程**：`$ROOT`（部署根目录）、`$SRC`（源码目录）、备份目录；绝不碰同机其他用户或其他 oGRAC 实例的目录/进程/端口。
2. **冷备必须在 ogracd 干净停止后做**；恢复会覆盖当前 DB，执行前必须确认。
3. **不要在 CMS/DSS/DB 运行时手工清 SCSI PR**。运行中清 PR 会破坏注册状态，导致 `reservation conflict`、`failed to open ctrl1`。唯一安全的点是**所有本实例服务都已停止后**：恢复编排脚本会在此时用 `SUDO_PWD_FILE` 清理四个 LUN 的 stale PR，再启动恢复 DSS；不要在其他时刻手工执行。
4. 备份目录 700、配置 tar 600；禁止把明文密码文件复制进备份或在日志/回复中打印密码。
5. 除“全部服务停止后清 stale PR”这一处外，恢复脚本不需要 root；不要用 root 覆盖部署用户所有的安装文件。PR 清理只读 `SUDO_PWD_FILE`（默认 `$HOME/.spw`），不打印密码；文件不存在时脚本会跳过并提示风险。

## 环境参数

| 变量 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `NODE0` | 是 | — | node0 地址 |
| `NODE1` | 是 | — | node1 地址，SSH 免密 |
| `SSH_USER` | 否 | `$USER` | 节点间 SSH 用户 |
| `ROOT` | 否 | `$HOME/ograc_cluster` | 部署根目录 |
| `SRC` | 否 | `$HOME/code/oGRAC` | oGRAC 源码目录（UB pool 工具头文件） |
| `DB_PORT` | 否 | `29300` | 数据库端口 |
| `DATA_DEV`/`REDO_DEV`/`ARCH_DEV`/`GCC_DEV` | 清 PR 时必填 | — | 四个 LUN 的 `/dev/disk/by-id/...` 路径 |
| `SUDO_PWD_FILE` | 否 | `$HOME/.spw` | 仅用于停库/清 PR/setcap 的 sudo 密码文件（600） |
| `DSS_HOME` | 否 | `$ROOT/ograc/dss` | DSS 安装目录 |
| `TPCC_SKILL` | 否 | 同级的 `ograc-prepare-tpcc-data` skill | 恢复后行数校验 |

数据布局示例：`+vg1` 放 data/undo/temp/ctrl，`+vg2` 放 redo（每节点 5 × 10G，共 10 个文件）。VG 名称按你的安装配置填写。

## 参考量级（示例环境）

- 冷备：`+vg1` 约 24GB + `+vg2` 107GB（10 个 10GiB redo），共约 30 个文件、123GiB；无 FAILED，`SHA256SUMS` 完整。
- 备份速度：约 300–550MB/s（4 路并行 `dsscmd cp`）。
- 回拷：30 文件全部恢复，有效速度约 576MB/s。
- 实际数值取决于 LUN、文件系统和并发度。

## 快速开始

### 1. 做冷备（DB 干净停止后）

```bash
SKILL=<本 skill 目录>
bash "$SKILL/scripts/dss_cold_backup.sh" "$HOME/ograc_backups/tpcc_dss_$(date +%Y%m%d)"
```

`dss_cold_backup.sh` 的行为：

- 拒绝在 `ogracd` 仍运行时执行；
- 用 `dsscmd ls` 枚举 `+vg1`/`+vg2` 的普通文件（跳过 `.recycle`）；
- 4 路并行 `dsscmd cp` 到普通目录；
- 生成 `MANIFEST.tsv`（vg、name、DSS logical size、DSS written size、local size）和 `SHA256SUMS`；
- 不包含 archive VG、GCC LUN 和本地配置。

### 2. 另存本地配置（只存 1–3）

```bash
B=$HOME/ograc_backups/tpcc_dss_<时间>/local_files
mkdir -p "$B" && chmod 700 "$B"
R=$ROOT
tar -czf "$B/db_cfg.tar.gz"     -C $R/dbdata/local/ograc/tmp/data cfg
tar -czf "$B/cms_cfg.tar.gz"    -C $R/ograc/cms cfg
tar -czf "$B/dss_cfg.tar.gz"    -C $R/ograc/dss cfg
find $R/ograc/action -maxdepth 2 -type f -name '*.json' -printf '%P\n' | sort > /tmp/action_json.list
tar -czf "$B/action_cfg.tar.gz" -C $R/ograc/action -T /tmp/action_json.list
rm -f /tmp/action_json.list
chmod 600 "$B"/*.tar.gz
( cd "$B" && sha256sum *.tar.gz > SHA256SUMS )
```

### 3. 从冷备恢复实例

先停业务、确认当前数据可丢弃，然后执行：

```bash
SKILL=<本 skill 目录>
bash "$SKILL/scripts/restore_instance_from_cold_backup.sh" \
  "$HOME/ograc_backups/tpcc_dss_<时间>" --yes
```

脚本会按以下顺序执行：

1. 校验 `MANIFEST.tsv`、每个文件大小，以及 `SHA256SUMS`（`--no-sha` 可跳过）；随后做
   **运行前权限预检**：`cms` 的 `CAP_SYS_RAWIO`、`perctrl` 的 `CAP_SYS_ADMIN,CAP_SYS_RAWIO`
   和四个 LUN 设备节点属主（两节点都查）；缺失时用 `SUDO_PWD_FILE` 自动 `setcap`/`chown`，
   只修本实例自己的二进制和四个设备；
2. **有界干净停库**（`shutdowndb.sh -m immediate`，外部 `timeout $DB_STOP_TIMEOUT`，默认
   120s）；超时或 DB 仍在时自动强制停机：先清残留的 `shutdowndb.sh`/`ogsql` 客户端，
   停两节点 CMS，再对命令行匹配 `ogracd` + 本实例 data dir 的 PID 依次 `TERM`→`KILL`
   （绝不匹配其他实例或用户的进程）；
3. 停止两节点 CMS 和 DSS；清除本用户、`0x32` key、`nattch=0` 的 SysV 共享内存段
   （旧 uid 或强杀 DSS 留下的段会让新 DSS 报 `Failed to attach shared memory key=0x32000001`；
   其他用户的段只告警、不删除）；
4. **清理两节点本用户的所有 GBP buffer（所有命名空间代次）**（`ub_pool_tool.c` 现场编译并部署到 node1；按节点分别 `clean-all`，先 `sg ubsmd` 再登录主 gid、引用未释放时 5 秒后重试；最后 `all-list` 必须 `matched=0`，否则直接失败）；
5. 启动 node0 的恢复用 DSS，**必须用维护模式 `dssserver -D $DSS_HOME -M`**（不能用 `dss_contrl.sh -start`：PR 清理后普通启动会从错误的 path/port 注册 reservation，导致 DSS 卡死/`reservation conflict`）；
6. 调 `dss_cold_restore.sh` 用 `dsscmd cp` 回拷：**数据文件先、`ctrl*` 最后，绝不填充 ctrl**；
7. 重启 DSS 两节点、启动 CMS（两节点都用 `sg ubsmd`）；CMS 前 DSS lsvg 失败不算致命，先起 CMS 注册 PR，再复检；
8. 启动 node0 并等 `cms stat -res db` 为 `ONLINE` 且 `WORK_STAT=1`，再启动 node1，等两节点 `ONLINE/JOINED`；
9. 默认执行 TPC-C 行数校验（`--no-verify` 跳过）。

常用参数：

```bash
--yes        非 TTY/自动化场景必须携带（否则脚本拒绝破坏性恢复）
--no-verify  跳过 TPC-C 行数校验
--no-sha     跳过 SHA256 校验（不推荐）
```

## 关键经验（踩过的坑）

### 1. ctrl 文件不能填充

- `+vg1/ctrl1-3` 在 DSS 里 logical size 为 41,943,040，但 **DB 期望的 written size 是 35,880,960**。
- 把本地 ctrl 补到 41,943,040 再回拷，DB 会报：
  `the size of ctrl file +vg1/ctrl1 is abnormal, expected 35880960, actual 41943040`。
- 正确做法：`dsscmd cp` 原样回拷 35,880,960 字节的 ctrl，**不要 `truncate -s 41943040`**。

### 2. 不要运行中手工清 SCSI PR

- 在 CMS/DSS/DB **运行时**执行 `sg_persist --out --clear` 会破坏注册/保留状态；随后出现：
  - `dmesg: sd ... reservation conflict`
  - DB `failed to open +vg1/ctrl1`
  - node1 DSS 假死。
- 正确恢复顺序是：停 DB → 停 CMS → 停 DSS → 清 stale PR → 启动恢复 DSS → 回拷 → 重启 CMS/DSS/DB；让 `perctrl`/CMS 自己重新注册。
- `restore_instance_from_cold_backup.sh` 已实现这个安全点：它只在 `db_pid0/db_pid1`、CMS、DSS 全部不在后，读取 `SUDO_PWD_FILE` 清理四个 LUN 的 PR；如果没有密码文件则跳过并警告。
- 清理 PR 后，用于回拷的 DSS 必须是 **维护模式 `-M`**。普通 `dss_contrl.sh -start` 会重新注册 reservation，且注册 path 与实际 I/O path 可能不一致，导致 DSS 卡死（`Failed to get uds connection` + `dmesg reservation conflict`）。回拷完成后脚本会停掉维护 DSS，再按正常模式启动两节点 DSS。
- 注意：如果跳过 PR 清理、且数组上仍有上一次崩溃留下的 reservation，恢复 DSS 可能短暂假死，脚本会在约 1 分钟内报 `node0 DSS cannot serve dsscmd`，不会长时间空等。
- **registrants-only 保留只允许注册它的 initiator port 清除**。如果 reservation 是通过 node1 的 HBA 端口注册的（常见于崩溃/异常停 CMS 之后），在 node0 执行 `sg_persist --out --clear --param-rk=2` 会返回 `Reservation conflict`，四个 LUN 的 `read-reservation` 仍显示 `Key=`，随后 DSS 报 `Failed to lock share disk vg` / `node0 DSS cannot serve dsscmd`。恢复脚本会在 node0 清除后复检，仍有 `Key=` 时自动改从 node1 清除。

### 3. DSS 假死判定与重启

现象：

```bash
dsscmd lsvg
# Failed to get uds connection
```

但 `dssserver` 进程仍在、socket 时间很旧。处理：

```bash
# 只杀本实例 DSS（按路径匹配，绝不误杀其他实例）
ps -eo pid,args | grep "$ROOT/ograc/dss/bin/dssserver" | grep -v grep
kill -9 <pid>
rm -f $ROOT/ograc/dss/.dss_unix_d_socket
export DSS_HOME=$ROOT/ograc/dss
export LD_LIBRARY_PATH=$DSS_HOME/lib:$ROOT/ograc/ograc/server/lib:/usr/local/ubs_mem/lib
nohup $DSS_HOME/bin/dssserver -D $DSS_HOME >> $ROOT/ograc/log/dss/dss_manual.out 2>&1 &
```

`restore_instance_from_cold_backup.sh` 已内置这个检测/重启，不必手工处理。

### 4. 启动顺序：node0 必须 `WORK_STAT=1` 后再起 node1

- CMS 的 `stat -res db` 第 6 列是 `WORK_STAT`；只有 `ONLINE + WORK_STAT=1`（RC JOINED）才表示 node0 完成 master reform。
- 如果 node0 还停在 `WORK_STAT=0` 就启动 node1，会得到：
  `Multiple nodes cannot be added to the CMS at the same time without a master node`。
- `scripts/start_db_pair.sh` 已按 `ONLINE/JOINED` 等待 node0 后再起 node1。

### 5. CMS 必须以含 ubsmd 组的身份启动

- CMS 拉起的 `ogracd` 继承 CMS 的组；若 CMS 没有 `ubsmd` 补充组，DB 报：
  `Uds oob file path is invalid` / `Failed to initilize ubsm sdk`。
- node0 用 `sg ubsmd -c "… python3 cms_ctl.py start"`；node1 的登录会话本身应含 `ubsmd`。
- 检查：`ps -o pid,egid,supgrp,args -C cms`，supgrp 应包含 `ubsmd`。

### 6. JOINED 后不要立刻做行数校验

- `WORK_STAT=1` 只表示 RC master reform 完成，sys catalog 可能还要几秒才可见。
- 在 JOINED 后立刻跑 `verify_tpcc.sh` 可能对全部表报
  `OG-00843 The table or view TPCC.BMSQL_* does not exist`，但手工再查
  `select count(*) from TPCC.bmsql_warehouse` 已正常返回。
- `restore_instance_from_cold_backup.sh` 会先等 20 秒，失败后每 15 秒重试，最多 3 次；不要把这个误报当成数据损坏去重做恢复。

### 7. 备份只包含数据 VG

- `+vg1`：data/undo/temp/ctrl；`+vg2`：redo；这两部分足以在**干净停机**后恢复数据库。
- 不包含 archive VG（PITR 才需要）和 GCC LUN（CMS quorum）；如需整集群状态，另行单独备份 GCC/archive。
- 本地配置只备份 DB/CMS/DSS 配置和 action JSON；安装包/二进制/tools 单独保留，不放进冷备目录。

### 8. SIGKILL 后的 UB pool 残留会阻止重启

- 现象：`[UB-RECLAIM] old allocation remains for node N: <user>_vN_data_buf_part_N_g...`，
  随后 `IpcCallCreateRegion ... error=502`、`drc_init failed`、`Instance Startup Failed`。
- UBS 的 ShmDelete 按**主 gid** 校验属主。两节点必须用同一主 gid 启动 CMS/DB：统一用
  `sg ubsmd`。若 node1 走普通 ssh（主 gid 不同），它遗留的 pool 用
  `sg ubsmd` 清理会得到 `6011 NOPERM`。
- 清理前提：两端 ogracd 都已停止。`restore_instance_from_cold_backup.sh` 已在
  **停完 DB/CMS/DSS 后、清 PR/回拷前**自动执行清理：现场编译
  `scripts/ub_pool_tool.c`，复制到 node1，按节点分别清理**本用户创建的所有
  GBP buffer（当前及历史代次）**；先按 `sg ubsmd` 执行
  `clean-all`，失败再用登录主 gid 重试（node0 用 `sudo -u <self>` 得到
  登录主 gid + ubsmd 补充组；node1 用普通 ssh 登录得到登录主 gid + ubsmd），
  仍不干净则等 5 秒再重试，最后仍失败就中止恢复。
- 工具按当前用户名前缀 `<user>_` 过滤，只匹配 `data_buf_part_` 对象，**不会碰
  其他用户的共享内存**。
- **改过用户数字 uid 后**，旧 uid 创建的 pool 新 uid 删除会 6011。需以旧 uid 运行
  工具，并用 `UB_POOL_USER=<用户名>` 覆盖名字前缀（旧 passwd 名字可能已不存在）：
  `sudo env UB_POOL_USER=<旧用户名> setpriv --reuid=<旧uid> --regid=ubsmd --groups=ubsmd \
   ub_pool_tool clean-all NODE --both-databases-stopped`。
  否则恢复脚本会在 `cleanup_ub_pools` 阶段中止。
- 改 uid 后 DSS 的 **SysV 共享内存**也会残留：`ipcs -m` 中 owner=旧 uid、nattch=0 的
  `0x32xxxxxx` 段会让新 DSS 报 `Failed to attach shared memory key=0x32000001`，
  维护 DSS 起不来。确认 owner/nattch 后 `sudo ipcrm -m <shmid>` 清除；
  **绝不要删其他用户或其他实例的段**。
- **chown 会清掉 file capability**。改 uid 后必须恢复：
  `sudo setcap CAP_SYS_RAWIO+ep <cms_home>/service/bin/cms` 和
  `sudo setcap CAP_SYS_ADMIN,CAP_SYS_RAWIO+ep <dss_home>/bin/perctrl`。
  否则 `dsscmd reghl/inq_reg` 会报 EPERM/EEXIST，CMS 启动失败。
- 四个 LUN 的 `/dev/sdX` 节点属主也要从旧 uid 改成新 uid（保留组和权限）。
  GCC 盘通常是 `600`，漏改会让 CMS 报 `initialize gcc disk lock failed`；
  data/redo/archive 是 `660`，靠组权限可能掩盖问题，但应一并改。
- 手工清理（两端 DB 都停止后，在各自节点执行）：
  `UB_POOL_GENERATION=<vN> ub_pool_tool clean-all NODE --both-databases-stopped`；
  只查看不删除用 `ub_pool_tool all-list`，成功时 `matched=0`。脚本以
  `all-pools-empty` 判定成功。
- 清理后可正常重启；不要靠继续升命名空间代次绕过，否则旧 pool 会持续泄漏。
- SIGKILL 后立刻 deallocate 可能返回 `6024 IN_USING`；等 20–30 秒让 UBS 释放引用后重试。
- 集群 shutdown 后 node1 的 ogracd 可能残留（CMS 已显示 OFFLINE 但进程仍在）。按 PID
  确认 exe 和数据目录后 `TERM`/`KILL`，再清它的 pool；否则编排器会空等。
- 编排器日志里出现 `shutdowndb.sh: ... ogsql: command not found` 时，停库不会执行；
  脚本已补 `PATH=$DB_BIN:$PATH`。手工停库时也要先 export 该 PATH。

## 故障速查

| 现象 | 处理 |
|---|---|
| `ctrl file size is abnormal expected 35880960 actual 41943040` | 恢复时不要填充 ctrl；用原始 35,880,960 字节重拷 |
| `failed to open +vg1/ctrl1` | 先查 `dsscmd lsvg`；DSS 假死则按第 3 条重启 DSS |
| `Failed to get uds connection` | DSS 假死/未启动；杀本实例 dssserver，重启 |
| `reservation conflict` | 运行中不要清 PR；停全部服务后由恢复脚本安全清理（需 `$SUDO_PWD_FILE`） |
| 恢复脚本停在 `starting restore DSS` 很久 | 检查 `SUDO_PWD_FILE`、`sg_persist --in --read-reservation`，确认全部服务已停后重跑 |
| `Multiple nodes cannot be added ... without a master` | node0 未 `WORK_STAT=1`；等 JOINED 后再起 node1 |
| `Uds oob file path is invalid` | CMS 无 ubsmd 组；用 `sg ubsmd` 重启 CMS |
| `dsscmd cp` 报文件已存在 | 恢复脚本先 `dsscmd rm` 再 cp；手工时同样处理 |
| 恢复后 node1 打不开 ctrl | node1 DSS 假死；重启 node1 DSS 后再起 node1 |
| `[UB-RECLAIM] old allocation remains` / `IpcCallCreateRegion error=502` | 停两端 DB，在各自节点跑 `clean-all NODE --both-databases-stopped`，清理本用户所有代次 GBP buffer（见第 8 条） |
| pool 工具 `deallocate ret=6011` | 通常是把远端节点的对象拿到本节点删除；必须 node0 删 part_0、node1 删 part_1 |
| pool 工具 `deallocate ret=6024` | UBS 引用尚未释放；等 5–30 秒重试 |
| 回拷完成后 `ERROR: DSS unavailable after restore` | CMS 启动期间会重启/重新注册 DSS，旧的短窗口会误判；当前脚本按墙钟等待 `wait_dss_both` 180s，失败时打印两节点 `dsscmd lsvg` 的真实错误。若确已恢复，可直接跑 `start_db_pair.sh` 继续 |
| `shutdowndb.sh` 长时间无输出、DB 不退出 | DB 可能卡在 GBP quarantine reform 循环（日志反复 `[GBP-RCY] old pool epoch ... quarantined`）；恢复脚本默认 120s 后强制停机（`DB_STOP_TIMEOUT` 可调） |
| `OG-00676, Shutdown current session (sid 52) is prohibited` | 上一次被中断的 `shutdowndb.sh` 留下了 `ogsql` 会话；恢复脚本停库前会清理本实例 data dir 的残留客户端 |
| 强制停机后 DSS 报 `Failed to attach shared memory key=0x32000001` | 清本用户 `0x32`、`nattch=0` 的 SysV 段（脚本已自动执行）；旧 uid 段需按第 8 条用旧 uid 清理 |

## 脚本清单

| 脚本 | 用途 |
|---|---|
| `scripts/dss_cold_backup.sh` | 停机后用 `dsscmd cp` 备份 `+vg1/+vg2` 到普通目录 |
| `scripts/dss_cold_restore.sh` | 用 `dsscmd cp` 按 manifest 回拷，数据先、ctrl 最后，不填充 ctrl |
| `scripts/restore_instance_from_cold_backup.sh` | 一键编排：权限/设备预检 → 有界停库（卡死则强制停机）→ 停 CMS/DSS → 清 SysV shm 与两节点 UB pool → 清 PR → 回拷 → 重启 → JOINED → TPC-C 校验 |
| `scripts/start_db_pair.sh` | 先 node0 到 `ONLINE/JOINED`，再 node1，最后两节点 JOINED |
| `scripts/ub_pool_tool.c` | 清理本用户所有 GBP buffer（按节点 `clean-all`；`all-list` 只读）；由恢复脚本现场编译并部署到两节点 |
