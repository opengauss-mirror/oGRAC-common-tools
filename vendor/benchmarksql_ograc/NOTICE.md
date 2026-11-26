# 第三方来源与许可

本目录是 [BenchmarkSQL 5.0](https://sourceforge.net/projects/benchmarksql/) 的 oGRAC 适配分支。

| 项 | 内容 |
|---|---|
| 上游项目 | BenchmarkSQL 5.0（SourceForge） |
| 引入方式 | 直接复制源码，非 submodule / 非 subtree |
| 相对上游改动 | 见 [`UPSTREAM.md`](UPSTREAM.md) |
| 上游许可 | **未随源码保留**：本目录不含上游 `LICENSE`/`COPYING`，`HOW-TO-RUN.txt` 也没有许可声明 |

## 当前处理

在补齐上游许可证之前，本目录按「许可待确认」对待：**不要**用本仓库的 MulanPSL-2.0 去覆盖或再分发本目录的代码。

## 待办

1. 从上游发布包取出许可证原文，放到本目录（`LICENSE` 或 `COPYING`）。
2. 在本文件记录上游版本号与获取日期。
3. 若上游许可与 MulanPSL 不兼容，评估是否需要把本目录拆为独立仓库。

责任人：hwworkholic（见 [`../../docs/migration-map.md`](../../docs/migration-map.md) R16）。
