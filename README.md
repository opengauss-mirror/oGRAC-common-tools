# oGRAC-common-tools

oGRAC 定制适配的**公共工具与 agent skill** 仓库：可复用的测试 / 运维 / 开发 skill，配套脚本，以及 BenchmarkSQL 的 oGRAC 分支源码。

仓库不含二进制依赖与固件包：Java 依赖按 [`BUILD.md`](vendor/benchmarksql_ograc/BUILD.md) 本地获取，整机固件见 [`docs/ub-installation/firmware-README.md`](docs/ub-installation/firmware-README.md)。

## 快速开始

```bash
git clone https://gitcode.com/opengauss/oGRAC-common-tools.git
cd oGRAC-common-tools
ci/check_repo.sh          # 本地自检（全部检查）
```

### 使用某个 skill

skill 目录可以直接复制到 agent 的 skills 目录（`.claude/skills/`、`.opencode/skills/`、`.agents/skills/` 或 `~/.codex/skills/`），入口固定为 `<skill>/SKILL.md`：

```bash
cp -r skills/ograc-deploy-two-node ~/.codex/skills/
```

## 目录索引

| 路径 | 内容 | 责任人 |
|---|---|---|
| [`skills/ograc-deploy-two-node/`](skills/ograc-deploy-two-node/SKILL.md) | 两节点集群构建、安装、启动、验证 | zhangzq131 |
| [`skills/ograc-restore-cold-backup/`](skills/ograc-restore-cold-backup/SKILL.md) | `dsscmd cp` 冷备与整实例恢复 | zhangzq131 |
| [`skills/ograc-prepare-tpcc-data/`](skills/ograc-prepare-tpcc-data/SKILL.md) | TPC-C 数据准备（默认 100 仓） | zhangzq131 |
| [`skills/ograc-run-process-fault-longrun/`](skills/ograc-run-process-fault-longrun/SKILL.md) | 进程故障长稳流水线 | zhangzq131 |
| [`skills/ograc-develop-from-design/`](skills/ograc-develop-from-design/SKILL.md) | 设计文档驱动开发（GBP/UB） | shirley_zhengx |
| [`skills/ograc-review-pr/`](skills/ograc-review-pr/SKILL.md) | GitCode PR 行级检视 | shirley_zhengx |
| [`skills/ograc-review-docs/`](skills/ograc-review-docs/SKILL.md) | 中文文档低级错误检视与修复 | luodongxu |
| [`tools/`](tools/README.md) | 会话外工具（单机 LUN 模拟环境） | zhangzq131 |
| [`vendor/benchmarksql_ograc/`](vendor/benchmarksql_ograc/README.md) | BenchmarkSQL 5.0 的 oGRAC 分支，只保留源码 + [`BUILD.md`](vendor/benchmarksql_ograc/BUILD.md) | hwworkholic |
| [`docs/ub-installation/`](docs/ub-installation/安装UB流程.md) | 整机 OS 安装 + 固件升级手册；固件包已拆出 | huan |
| [`docs/`](docs/README.md) | 跨工具文档；skill 规范见 [`docs/skill-spec.md`](docs/skill-spec.md) | huan |
| [`ci/`](CONTRIBUTING.md) | 仓库自检脚本 | zhangzq131 |

skill 的命名、字段与摆放规则见 [`docs/skill-spec.md`](docs/skill-spec.md)，校验入口 `python3 ci/check_skills.py`。

### 已迁出的内容

| 内容 | 现在位置 | 原因 |
|---|---|---|
| 安全研发 skill（`opengauss-secret-scan`、`opengauss-third-party-cve`） | 独立仓库 `openGauss-security-skills` | 与 oGRAC 工具不同生命周期（2026-11-26 拆出） |
| 整机固件与 UB 软件包（111 个文件，约 231 MiB） | 独立包 `oGRAC-firmware-packages`，清单见 [`firmware-manifest.md`](docs/ub-installation/firmware-manifest.md) | 二进制不入代码仓（2026-11-26 拆出） |
| BenchmarkSQL 的 jar 与构建产物 | 不再入库，按 [`BUILD.md`](vendor/benchmarksql_ograc/BUILD.md) 本地构建 | 只保留源码 |
| 两节点部署旧脚本 `install-two-node.sh` | 已删除，内容仍在 git 历史 | 与 `skills/ograc-deploy-two-node` 重复且传明文口令 |

## 规范与门禁

- 新增或修改 skill、脚本、二进制前，先读 [`CONTRIBUTING.md`](CONTRIBUTING.md)；**新增文件放哪个目录**见 [`docs/pr-guide.md`](docs/pr-guide.md)；skill 的字段、命名与摆放规范见 [`docs/skill-spec.md`](docs/skill-spec.md)。
- 提交前跑 `ci/check_repo.sh`（9 项：语法、索引、密钥、skill 规范、文件归位、断链、LFS 指针、可执行位）；只要快速语法检查时用 `ci/check_repo.sh --quick`。
- 每项整改的负责人、验收标准和进度见 [`docs/migration-map.md`](docs/migration-map.md)。
- 变更记录见 [`CHANGELOG.md`](CHANGELOG.md)。

## 许可证

木兰宽松许可证，第 2 版（MulanPSL-2.0），见 [LICENSE](LICENSE)。
`vendor/benchmarksql_ograc/` 为第三方项目的分支，遵循其上游许可，见 [`NOTICE.md`](vendor/benchmarksql_ograc/NOTICE.md)。
