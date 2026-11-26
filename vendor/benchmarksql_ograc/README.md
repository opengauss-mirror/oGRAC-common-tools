# BenchmarkSQL（oGRAC 分支）

[BenchmarkSQL 5.0](https://sourceforge.net/projects/benchmarksql/) 的 oGRAC 适配分支，用于 TPC-C 压测。
本目录**只保留源码**，二进制依赖与构建产物不入库。

| 内容 | 说明 |
|---|---|
| [`BUILD.md`](BUILD.md) | 构建与运行指南（先读这个） |
| [`UPSTREAM.md`](UPSTREAM.md) | 上游基线、本分支改动、已删除文件清单 |
| [`src/`](src) | Java 源码（`client/`、`LoadData/`、`OSCollector/`、`jdbc/`） |
| [`run/`](run) | 运行脚本、SQL、props 模板 |
| [`lib/`](lib/README.md) | 第三方 jar 放置位置（jar 本身不入库） |
| `build.xml` | Ant 构建脚本，默认 target 产出 `dist/BenchmarkSQL-5.0.jar` |
| `doc/src/TimedDriver.odt` | 上游 TPC-C 驱动说明 |

相对上游的主要改动：新增 `nodeId` / `nodeCnt` 配置（多节点压测时各节点仓库不重叠）、新增
`tableCreates_par.sql` 与 `indexCreates_par.sql`、新增 `run/ograc_run.og` 配置示例。
详见 [`UPSTREAM.md`](UPSTREAM.md)。

使用本分支源码编译后，两节点各自压测的数据冲突率接近 0。

配套 skill：[`ograc-prepare-tpcc-data`](../../skills/ograc-prepare-tpcc-data/SKILL.md)（迁移到 `skills/` 后本链接同步更新）。
