# 贡献规范

本仓库收录 oGRAC 相关的 agent skill、配套脚本与会话外工具。新增内容前请先对照本文；不符合规范的提交会在 `ci/check_repo.sh` 中被拦下。

## 1. 目录约定

目标结构（迁移进度见 [`docs/migration-map.md`](docs/migration-map.md)）：

```
skills/<skill-name>/      一个 skill 一个目录，入口固定 SKILL.md
  SKILL.md
  README.md               可选，最多 3 行，只做跳转，不重复 SKILL.md
  scripts/                可执行脚本
  references/             参考文档、排障手册、规则文件
  assets/                 配置模板、补丁
tools/<tool-name>/        会话外工具（脚本 + 简短 README）
vendor/<project>/         第三方分支源码（保留上游结构）
docs/                     跨工具的文档
ci/                       仓库自检
```

历史路径（`ograc-skills/`、`ograc-docs-review/`、`common-scripts/`）在迁移完成前保持可用，新增内容请直接落到目标路径。
`security-developing-skills/` 与 `ub_installation_doc/images/包/` 已于 2026-11-26 迁出本仓，不要在本仓重建。

## 2. Skill 规范

遵循 agentskills 规范，并叠加本仓的命名规则。完整的字段约束、命名规则、正反例与改名对照见 [`docs/skill-spec.md`](docs/skill-spec.md)，提交前跑：

```bash
python3 ci/check_skills.py                # 规范 + oGRAC 命名规则
python3 ci/check_skills.py --spec-only    # 只查上游规范
```

本仓在此之上的附加约定：

- **命名**：`ograc-<动词>-<对象>[-<限定语>]`，第二段必须出自动词词表，只用 `-` 连接，总长 ≤ 32 字符，不带版本号。见 [`docs/skill-spec.md`](docs/skill-spec.md) 第 4 节。

- **摆放**：skill 直接放在 `skills/<name>/`，**不允许二级分组**（没有 `skills/<分类>/<name>`）；迁移期 `ograc-skills/`、`ograc-docs-review/` 同样受规范约束。
- **文档不重复**：`SKILL.md` 是唯一真源；目录里的 `README.md` 最多 3 行、只做跳转。
- **扩展字段**：可以使用 `disable-model-invocation` 这类上游未定义的字段，但校验会报 `WARN`，需要在 PR 说明理由。

## 3. 脚本规范

- Shell：`#!/usr/bin/env bash` + `set -euo pipefail`，可执行位 755，`bash -n` 与 `shellcheck`（error 级）零告警。
- Python：仅支持 Python 3（`benchmarksql_ograc/` 下的上游 Python 2 脚本豁免，不得新增）。
- **禁止硬编码**主机名、IP、用户名、路径、口令、LUN WWID。全部通过环境变量或参数传入。
- 口令只允许两种传递方式：环境变量（如 `TPCC_PWD`），或权限 600 的口令文件（如 `SUDO_PWD_FILE`）。**不接受命令行明文口令**（会留在 shell history 与 `ps`）。
- 脚本不得内嵌默认口令；需要默认口令时，随机生成并写入 600 权限文件。
- 进程操作必须限定到 `$ROOT` / 本实例：禁止宽泛 `pkill`、`killall`、`pkill -u <user>`。
- 停止、删除、覆盖、重建前必须显式确认目标属于当前部署；清理类操作默认只告警不删除他人资源。
- 每个脚本顶部用注释写明：用途、必需环境变量、是否有破坏性副作用。

## 4. 二进制与 LFS

- 禁止提交构建产物：`build/`、`dist/`、`*.class`、`*.jar`（vendored 依赖除外）、`*.bak`、`*.zip` 源码快照。
- 单个二进制超过 **512 KB** 一律走 Git LFS 或外链（Release 附件、制品仓），不得直接入库。
- LFS 规则按**目录整段**声明，不要逐个后缀补；新增固件目录时同时更新 `.gitattributes` 与 `docs/migration-map.md`。
- 依赖 LFS 的文档必须在开头写明 `git lfs install` 前置，并给出一条自检命令（例如 `find <dir> -type f -size -1k` 输出为空）。
- 引入第三方驱动/工具包时，在目标目录 README 记录**来源 URL 与版本**，同一组件只保留一个版本。
- 示例配置（props、连接串、脚本默认值）**不得出现真实内网地址、真实账号或口令**，一律用 `<host>`、`<password>` 之类占位符。这类值一旦提交就等同于泄露，需要轮换并重写历史。

## 5. 文档规范

- Markdown；所有相对链接必须可解析（`ci/check_links.py`）。
- 中文文档使用全角标点，中英文之间留空格，命令与路径用行内代码。
- 新增或重命名目录后，同步更新根 `README.md` 的目录索引与 `docs/migration-map.md`。
- 不提交含真实密钥、账号、内网地址的截图与日志。

## 6. 提交与评审

- 一个 PR 只做一件事（迁移、修复、新增功能分开）。
- 提交信息沿用仓库习惯：**中文、动词开头、说清做了什么**，例如 `新增 ograc-skills：冷备与实例恢复 skill`、`修复示例配置中的真实地址`。跨模块改动在正文里列出受影响路径。
- 不直接 push `master`；至少一位模块责任人 review。
- 迁移类 PR 必须同时更新受影响的链接，保证 `ci/check_repo.sh` 通过。

## 7. 质量门禁

```bash
ci/check_repo.sh            # 当前应通过的检查：shell 语法、Python 3 语法、README 索引、明文密钥
ci/check_repo.sh --strict   # 整改目标：额外检查 skill 规范、Markdown 断链、LFS 指针、可执行位
python3 ci/check_skills.py  # 只跑 skill 规范校验（agentskills）
```

`--strict` 在 `docs/migration-map.md` 的整改项关闭后设为默认，并接入 GitCode 流水线。

## 8. 模块责任人

以 git 提交历史为依据，按模块分工。改动他人模块请先 @ 对应责任人。

| 模块 / 路径 | 责任人 | 联系方式 |
|---|---|---|
| 仓库整体、根 README、`ci/` | zhangzq131（提交历史中亦作 `zhangzq`） | zhangzq131@gmail.com |
| `ograc-skills/ograc-two-node-deploy`、`ograc-cold-restore`、`tpcc-prepare-data`、`ograc-process-fault-longrun` | zhangzq131 | zhangzq131@gmail.com |
| `common-scripts/ograc_sim_single.sh` | zhangzq131 | zhangzq131@gmail.com |
| `common-scripts/install-two-node.sh`（待废弃） | jyn88 | 954966764@qq.com |
| `ograc-skills/ograc-dev-design` | shirley_zhengx | zhengxue6@huawei.com |
| `ograc-docs-review` | luodongxu | luodongxu77@163.com |
| `vendor/benchmarksql_ograc/` | hwworkholic | arcoalien@qq.com |
| `docs/ub-installation/` | huan | hejiahuan11@h-partners.com |

已迁出模块（改动请到对应仓库）：

| 模块 | 现在位置 | 责任人 |
|---|---|---|
| `opengauss-secret-scan`、`opengauss-third-party-cve` | 独立仓库 `openGauss-security-skills` | congzhou2603（zhoucong42@huawei.com） |
| 整机固件与 UB 软件包 | 独立包 `oGRAC-firmware-packages` | huan |
