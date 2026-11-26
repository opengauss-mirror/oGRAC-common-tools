# Skill 目录规范（agentskills）

本仓所有 skill 遵循 [Agent Skills 规范](https://github.com/agentskills/agentskills)。本文是仓库内的落地版本，字段约束以 [specification.mdx](https://github.com/agentskills/agentskills/blob/main/docs/specification.mdx) 为准（2026-11-26 核对）。与上游有出入时以上游为准，并回来修正本文。

## 1. 目录结构

一个 skill 就是一个目录，**至少**包含 `SKILL.md`：

```
<skill-name>/
├── SKILL.md          # 必需：frontmatter + 指令正文
├── scripts/          # 可选：可执行脚本
├── references/       # 可选：详细参考文档
├── assets/           # 可选：模板、图片、数据
└── ...               # 其他文件/目录
```

其余文件与目录不受限制，`scripts/`、`references/`、`assets/` 只是约定。

## 2. frontmatter

`SKILL.md` 必须以 YAML frontmatter 开头（首行 `---`，以 `---` 闭合），后接 Markdown 正文。

| 字段 | 必填 | 约束 |
|---|---|---|
| `name` | 是 | 1–64 字符；只允许小写字母、数字、连字符；不得以 `-` 开头或结尾；不得出现 `--`；**必须与所在目录名一致** |
| `description` | 是 | 1–1024 字符；非空；写清「做什么」和「何时使用」，含可检索的关键词 |
| `license` | 否 | 许可证名，或指向仓库内许可文件 |
| `compatibility` | 否 | 1–500 字符；仅在确有环境要求时写（依赖的软件、网络、系统包等） |
| `metadata` | 否 | 字符串键值对；**值必须是字符串**，版本号要加引号（`version: "1.0"`），不加引号会被 YAML 解析成浮点数 |
| `allowed-tools` | 否 | 空格分隔的预授权工具列表，实验性字段 |

最小示例：

```yaml
---
name: ograc-two-node-deploy
description: 构建、安装、启动、验证 oGRAC 两节点测试集群。用于部署新代码、全量重装、停机刷新二进制，或按顺序重启与排查启动问题。
---
```

## 3. 正文与渐进披露

agent 分三阶段加载 skill：启动时只读 `name` + `description`（约 100 token），命中任务后读整个 `SKILL.md`，需要时才读 `scripts/`、`references/`、`assets/`。

因此：

- `description` 决定 skill 会不会被触发，触发词写全，别写成「帮助处理文档」。
- `SKILL.md` 建议不超过 **500 行**、约 5000 token；细节移到 `references/`。
- 引用其他文件用**相对 skill 根目录**的路径，且保持**一层**深度，例如 `references/REFERENCE.md`，不要 `references/a/b/c.md`。
- 正文没有格式限制，但建议给出步骤、输入输出示例和边界情况。

## 4. 校验

仓库自带的校验器按上述规则检查（仅 Python 3 标准库，可离线跑）：

```bash
python3 ci/check_skills.py                 # 单个仓库
python3 ci/check_skills.py --root <dir>    # 指定目录，便于自测
```

`ci/check_repo.sh --strict` 会把它作为一项门禁。输出中 `FAIL` 计入退出码 1，`WARN` 只提示。

上游的参考实现是 [`skills-ref`](https://github.com/agentskills/agentskills/tree/main/skills-ref)：

```bash
skills-ref validate ./my-skill
```

两者规则一致；本仓用自实现是为了在无网络、无额外依赖的 CI 环境里也能跑。

## 5. 本仓附加约定（规范之外）

以下三条是仓库自己的约定，不属于 agentskills 规范：

1. **归位**：skill 目录最终放在 `skills/<name>/`。迁移完成前 `ograc-skills/`、`ograc-docs-review/` 同样受本规范约束。
2. **文档不重复**：`SKILL.md` 是唯一真源；目录里的 `README.md` 最多 3 行、只做跳转。
3. **扩展字段**：可以用 `disable-model-invocation` 这类上游未定义的字段（部分客户端支持），但校验会给出 `WARN`，需要在 PR 说明理由。

脚本与安全要求见 [`../CONTRIBUTING.md`](../CONTRIBUTING.md) 第 3 节。

## 6. 常见违规与修法

| 现象 | 修法 |
|---|---|
| 入口叫 `xxx_SKILL.md` 或 `xxx-skill.md` | 改名为 `SKILL.md`，否则标准加载器扫不到 |
| 一个目录里多个 `*SKILL.md` | 一个 skill 一个目录；其余拆到同级目录或 `references/` |
| `name` 与目录名不一致 | 改 `name` 或改目录名，二者必须相同 |
| `name` 含大写、下划线、中文、空格 | 改为小写 kebab-case，如 `ograc-docs-review` |
| `description` 只写「帮助处理 xx」 | 补「做什么 + 何时使用 + 关键词」 |
| `metadata.version: 1.0` | 加引号：`version: "1.0"` |
| `SKILL.md` 超过 500 行 | 把细节移入 `references/`，正文留流程 |
| 引用写成 `references/a/b/c.md` | 压平到一层 |

## 7. 存量状态

截至 2026-11-26：6 个 skill，5 个合规，1 个违规。

| skill | 状态 |
|---|---|
| `ograc-skills/ograc-two-node-deploy` | 合规 |
| `ograc-skills/ograc-cold-restore` | 合规 |
| `ograc-skills/tpcc-prepare-data` | 合规 |
| `ograc-skills/ograc-process-fault-longrun` | 合规 |
| `ograc-docs-review` | 合规 |
| `ograc-skills/ograc-dev-design` | **违规**：无 `SKILL.md`，实际为 `design_driven_dev_SKILL.md`、`代码检视SKILL.md`、`设计文档驱动开发SKILL.md` |

违规项的整改责任人与验收标准见 [`migration-map.md`](migration-map.md) 的 R13。
