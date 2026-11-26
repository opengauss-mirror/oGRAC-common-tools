# oGRAC-common-tools

oGRAC 定制适配的**公共工具与 agent skill** 仓库：可复用的测试 / 运维 / 文档 skill，配套脚本，以及 BenchmarkSQL 的 oGRAC 分支源码。

仓库不含二进制依赖与固件包：Java 依赖按 [`BUILD.md`](vendor/benchmarksql_ograc/BUILD.md) 本地获取，整机固件见 [`docs/ub-installation/firmware-README.md`](docs/ub-installation/firmware-README.md)。

## 快速开始

```bash
git clone https://gitcode.com/opengauss/oGRAC-common-tools.git
cd oGRAC-common-tools
ci/check_repo.sh          # 本地自检
```

### 使用某个 skill

skill 目录可以直接复制到 agent 的 skills 目录（`.claude/skills/`、`.opencode/skills/`、`.agents/skills/` 或 `~/.codex/skills/`），入口固定为 `<skill>/SKILL.md`：

```bash
cp -r ograc-skills/ograc-two-node-deploy ~/.codex/skills/
```

## 目录索引

| 路径 | 内容 | 状态 | 责任人 |
|---|---|---|---|
| [`ograc-skills/`](ograc-skills/README.md) | 两节点部署、冷备恢复、TPC-C 数据准备、进程故障长稳 | 稳定，计划迁往 `skills/` | zhangzq131 |
| [`ograc-skills/ograc-dev-design/`](ograc-skills/ograc-dev-design/design_driven_dev_SKILL.md) | 设计文档驱动开发、Prompt 模式总结、PR 行级检视 | 待规范：无 `SKILL.md` | shirley_zhengx |
| [`ograc-docs-review/`](ograc-docs-review/SKILL.md) | 中文文档低级错误检视与修复 | 稳定，计划迁往 `skills/` | luodongxu |
| [`common-scripts/`](common-scripts/README.md) | 单机 LUN 模拟开发环境；两节点部署脚本（已废弃） | 计划迁往 `tools/` | zhangzq131 / jyn88 |
| [`docs/ub-installation/`](docs/ub-installation/安装UB流程.md) | 整机 OS 安装 + 固件升级手册；固件包已拆出 | 已迁移 | huan |
| [`vendor/benchmarksql_ograc/`](vendor/benchmarksql_ograc/README.md) | BenchmarkSQL 5.0 的 oGRAC 分支，只保留源码 + [`BUILD.md`](vendor/benchmarksql_ograc/BUILD.md) | 已迁移 | hwworkholic |
| [`skills/`](skills/README.md) | 目标 skill 归集目录 | 骨架，迁移中 | 各 skill 责任人 |
| [`tools/`](tools/README.md) | 目标工具目录 | 骨架，迁移中 | zhangzq131 |
| [`vendor/`](vendor/README.md) | 第三方分支目录 | 已启用 | hwworkholic |
| [`docs/`](docs/README.md) | 跨工具文档目录 | 已启用 | huan |
| [`ci/`](CONTRIBUTING.md) | 仓库自检脚本 | 已可用 | zhangzq131 |

### 已迁出的内容

| 内容 | 现在位置 | 原因 |
|---|---|---|
| 安全研发 skill（`opengauss-secret-scan`、`opengauss-third-party-cve`） | 独立仓库 `openGauss-security-skills` | 与 oGRAC 工具不同生命周期（2026-11-26 拆出） |
| 整机固件与 UB 软件包（111 个文件，约 231 MiB） | 独立包 `oGRAC-firmware-packages`，清单见 [`firmware-manifest.md`](docs/ub-installation/firmware-manifest.md) | 二进制不入代码仓（2026-11-26 拆出） |
| BenchmarkSQL 的 jar 与构建产物 | 不再入库，按 [`BUILD.md`](vendor/benchmarksql_ograc/BUILD.md) 本地构建 | 只保留源码 |

## 规范与门禁

- 新增或修改 skill、脚本、二进制前，先读 [`CONTRIBUTING.md`](CONTRIBUTING.md)。
- 提交前跑 `ci/check_repo.sh`；整改收尾后加 `--strict` 并接入流水线。
- 每项整改的负责人、验收标准和进度见 [`docs/migration-map.md`](docs/migration-map.md)。
- 变更记录见 [`CHANGELOG.md`](CHANGELOG.md)。

## 许可证

木兰宽松许可证，第 2 版（MulanPSL-2.0），见 [LICENSE](LICENSE)。
`vendor/benchmarksql_ograc/` 为第三方项目的分支，遵循其上游许可。
