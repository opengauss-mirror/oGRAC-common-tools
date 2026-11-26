# 上游基线与本分支改动

## 上游

- 项目：BenchmarkSQL 5.0（<https://sourceforge.net/projects/benchmarksql/>）
- 上游说明：[`HOW-TO-RUN.txt`](HOW-TO-RUN.txt)（要求 JDK 7）
- 同步方式：本目录**不是** git subtree/submodule，与上游没有自动化同步。升级时按上游发布包人工比对
  `src/` 与 `run/`，再重新套用下面的改动。

## 本分支改动

| 文件 | 改动 |
|---|---|
| `src/client/jTPCC.java` | 读取新增配置 `nodeId`（默认 0）、`nodeCnt`（默认 1）；校验 `warehouses % nodeCnt == 0`；`terminalWarehouseID` 按节点编号分配，使多节点压测的仓库不重叠 |
| `src/client/jTPCCConfig.java` | 新增 `nodeId` / `nodeCnt` 默认值 |
| `run/sql.common/tableCreates_par.sql` | 适配 oGRAC 的分区建表 |
| `run/sql.common/indexCreates_par.sql` | 适配 oGRAC 的分区建索引 |
| `run/sql.postgres/buildFinish.sql` | oGRAC 装载收尾 |
| `run/runDatabaseBuild.sh` | 装载流程改用上述 `*_par` 脚本 |
| `run/ograc_run.og` | oGRAC 两节点压测配置示例 |
| `run/props.proxy`、`run/props.sharding` | 通用示例，非上游文件 |

## 已删除文件（2026-11-26，只保留源码）

| 文件 | 原因 |
|---|---|
| `build/*.class`（21 个）、`dist/BenchmarkSQL-5.0.jar` | 构建产物，由 `ant` 重新生成 |
| `src/client.zip` | `src/client/` 的过期快照，且内含 `.bak` |
| `src/client/jTPCC.java.bak` | 改造前备份 |
| `lib/` 下 9 个 jar/tar.gz | 第三方二进制依赖，改为按 [`BUILD.md`](BUILD.md) 本地获取 |
| `lib/postgres/opengauss-jdbc-7.0.0-RC7.jar_2uweiwue` | 误命名的 RC7 驱动，与 RC3 重复 |

## 敏感信息清理

`run/ograc_run.og`、`run/props.sharding`、`run/props.proxy` 中曾提交过真实内网地址与明文口令，2026-11-26 已替换为
`<node0_ip>`、`<password>` 等占位符。

`run/loop111test.sh` 是个人调试脚本，曾把节点 root 口令、数据库 sys 口令和节点 IP 写死在 expect 配置里，
现改为从 `OS_PWD`、`OGRAC_SYS_PWD`、`NODE0` 三个环境变量读取，未设置时直接报错退出。
该脚本还引用未入库的 `props_111.ograc`，使用前自行准备。

> **注意**：这些值仍存在于拆分前的 git 历史中。涉及的口令必须视为已泄露并轮换；如需彻底清除，
> 需重写历史，仓库管理员评估后再做。
