# Skill 目录规范（agentskills + oGRAC 命名）

本仓所有 skill 遵循 [Agent Skills 规范](https://github.com/agentskills/agentskills)，并在此之上叠加一套 oGRAC 命名规则。字段约束以 [specification.mdx](https://github.com/agentskills/agentskills/blob/main/docs/specification.mdx) 为准（2026-11-26 核对）；与上游有出入时以上游为准，并回来修正本文。

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

## 2. frontmatter（上游规范）

`SKILL.md` 必须以 YAML frontmatter 开头（首行 `---`，以 `---` 闭合），后接 Markdown 正文。

| 字段 | 必填 | 约束 |
|---|---|---|
| `name` | 是 | 1–64 字符；只允许小写字母、数字、连字符；不得以 `-` 开头或结尾；不得出现 `--`；**必须与所在目录名一致** |
| `description` | 是 | 1–1024 字符；非空；写清「做什么」和「何时使用」，含可检索的关键词 |
| `license` | 否 | 许可证名，或指向仓库内许可文件 |
| `compatibility` | 否 | 1–500 字符；仅在确有环境要求时写 |
| `metadata` | 否 | 字符串键值对；**值必须是字符串**，版本号要加引号（`version: "1.0"`） |
| `allowed-tools` | 否 | 空格分隔的预授权工具列表，实验性字段 |

## 3. 正文与渐进披露

agent 分三阶段加载：启动只读 `name` + `description`（约 100 token），命中任务后读整个 `SKILL.md`，需要时才读 `scripts/`、`references/`、`assets/`。

- `description` 决定 skill 会不会被触发，触发词要写全。
- `SKILL.md` 建议不超过 **500 行**（约 5000 token），细节移到 `references/`。
- 引用他用**相对 skill 根目录**的路径，保持**一层**深度：`references/REFERENCE.md`，不要 `references/a/b/c.md`。

## 4. oGRAC 命名规则（本仓自定，比规范更严）

规范只要求 `name` 由 `[a-z0-9-]` 组成且等于目录名。本仓再收紧一条主线：**名字要一眼看出「对什么、做什么」**。

### 4.1 规则

| # | 规则 | 取值 | 理由 |
|---|---|---|---|
| N1 | 前缀 | 必须 `ograc-` 开头 | 任何客户端、任何目录下都能按前缀筛出本仓 skill |
| N2 | 结构 | `ograc-<动词>-<对象>[-<限定语>]`，至少三段 | 第二段固定动词，机器可判定「是动作」而不是名词堆叠 |
| N3 | 动词 | 必须出自 4.2 词表 | 防止 `deploy/install/setup` 各自为政，也避免 `dev`、`docs` 这种名词占位 |
| N4 | 连接符 | 只用 `-`，禁止 `_` | 上游 `name` 正则为 `[a-z0-9-]`，`_` 直接违规；同时避免 shell/URL 转义差异 |
| N5 | 长度 | **≤ 32 字符**（含 `ograc-`） | 上游上限 64；32 能让 `skills/<name>/SKILL.md` 保持短路径，超过说明一个 skill 干了多件事，应拆分 |
| N6 | 禁用词 | `helper`、`assistant`、`util`、`utils`、`tool`、`tools`、`misc`、`skill`、`skills` | 这些词不说明任何动作，写进名字就是噪音 |
| N7 | 版本 | 名字不带 `v2`、`new`、`old`、`2` 等版本/代次标记 | 版本放 `metadata.version`，否则改名即破坏引用 |
| N8 | 字符 | 纯 ASCII 小写 | 中文只出现在 `description`；目录名带中文会在跨平台与链接编码上出问题 |

### 4.2 动词词表

```
backup  build   check     clean    collect   deploy    design    develop
diagnose install load      migrate  prepare   publish   restore   review
run      scan    sync      test     uninstall upgrade   verify
```

新增动词必须同时改本文与 `ci/check_skills.py` 的 `OGRAC_VERBS`，否则门禁会拒绝该名字。

### 4.3 正反例

| 名字 | 判定 | 说明 |
|---|---|---|
| `ograc-deploy-two-node` | ✅ | 动词 `deploy` + 对象 `two-node`，21 字符 |
| `ograc-restore-cold-backup` | ✅ | 25 字符 |
| `ograc-run-process-fault-longrun` | ✅ | 31 字符，贴近上限 |
| `ograc-two-node-deploy` | ❌ | 动词在末尾，第二段 `two` 不是动词 |
| `ograc-docs-review` | ❌ | 第二段 `docs` 是名词；应为 `ograc-review-docs` |
| `tpcc-prepare-data` | ❌ | 缺 `ograc-` 前缀 |
| `ograc_dev_single` | ❌ | 用了 `_`，违反 N4 与上游规范 |
| `ograc-deploy-two-node-cluster-check` | ❌ | 35 字符，超 N5，应拆成两个 skill |
| `ograc-install-helper` | ❌ | `helper` 命中 N6 |

### 4.4 存量改名对照

规则自 2026-11-26 起生效。存量 6 个 skill 全部不满足新规则（原规则只要求「看起来像 skill」），按下表改名；改名需同步目录名、`name` 字段和所有引用，落项见 [`migration-map.md`](migration-map.md) R14。

| 现名 | 建议名 | 长度 | 责任人 |
|---|---|---|---|
| `ograc-two-node-deploy` | `ograc-deploy-two-node` | 21 | zhangzq131 |
| `ograc-cold-restore` | `ograc-restore-cold-backup` | 25 | zhangzq131 |
| `tpcc-prepare-data` | `ograc-prepare-tpcc-data` | 23 | zhangzq131 |
| `ograc-process-fault-longrun` | `ograc-run-process-fault-longrun` | 31 | zhangzq131 |
| `ograc-docs-review` | `ograc-review-docs` | 17 | luodongxu |
| `ograc-dev-design` | `ograc-develop-from-design` | 25 | shirley_zhengx |

改名命令（以「迁入 `skills/` 的同时改名」为例，其余同理）：

```bash
git mv ograc-skills/ograc-two-node-deploy skills/ograc-deploy-two-node
sed -i 's/^name: ograc-two-node-deploy$/name: ograc-deploy-two-node/' skills/ograc-deploy-two-node/SKILL.md
grep -rl 'ograc-two-node-deploy' --include='*.md' . | xargs sed -i 's/ograc-two-node-deploy/ograc-deploy-two-node/g'
python3 ci/check_skills.py
```

### 5. 摆放与仓库约定

1. **摆放**：所有 skill **直接**放在 `skills/<name>/`，**不允许再加一级分组**——没有 `skills/security/<name>`、`skills/test/<name>`、`skills/ograc/<name>`。`scripts/`、`references/`、`assets/` 是 skill 内部资源目录，不算分组层。理由：skill 名已经是全局唯一的入口标识，再分组会让同名字在不同路径下出现，也让「复制到 agent 的 skills 目录」变成了两步。
2. **迁移期**：`ograc-skills/`、`ograc-docs-review/` 属于存量，按 [`migration-map.md`](migration-map.md) M1–M6 迁入 `skills/<name>/`，不另建中间目录。
3. **文档不重复**：`SKILL.md` 是唯一真源；目录里的 `README.md` 最多 3 行、只做跳转。
4. **扩展字段**：可以用 `disable-model-invocation` 这类上游未定义的字段（部分客户端支持），但校验会给出 `WARN`，需在 PR 说明理由。

## 6. 校验

```bash
python3 ci/check_skills.py                # 规范 + oGRAC 命名规则
python3 ci/check_skills.py --spec-only    # 只查上游规范，跳过 4.x 命名规则
python3 ci/check_skills.py --root <dir>   # 指定目录（用于自测）
```

`ci/check_repo.sh --strict` 会把它作为一项门禁。`FAIL` 计入退出码 1，`WARN` 只提示。

上游参考实现是 [`skills-ref`](https://github.com/agentskills/agentskills/tree/main/skills-ref)（`skills-ref validate ./my-skill`），只覆盖第 1–3 节；第 4 节是本仓自定，`skills-ref` 不检查。本仓用标准库自实现，是为了在无网络、无额外依赖的 CI 里也能跑。

## 7. 常见违规与修法

| 现象 | 修法 |
|---|---|
| 入口叫 `xxx_SKILL.md` | 改名 `SKILL.md`，否则标准加载器扫不到 |
| 一个目录多个 `*SKILL.md` | 一个 skill 一个目录，其余拆到同级或 `references/` |
| `name` 与目录名不一致 | 改 `name` 或改目录名，二者必须相同 |
| `name` 缺 `ograc-` 前缀 | 按 4.1 N1 补前缀 |
| 第二段不是动词 | 按 4.2 改写，动词前置 |
| 用 `_` 连接 | 全部换 `-` |
| 超过 32 字符 | 拆分 skill 或去掉冗余限定语 |
| 名字带 `v2` / `new` | 去掉，版本写 `metadata.version` |
| skill 放在 `ograc-skills/` 或 `skills/<分组>/<name>/` | 直接拍平到 `skills/<name>/` |
| `description` 只写「帮助处理 xx」 | 补「做什么 + 何时使用 + 关键词」 |
| `metadata.version: 1.0` | 加引号：`version: "1.0"` |
| `SKILL.md` 超过 500 行 | 细节移入 `references/` |
| 引用写成 `references/a/b/c.md` | 压平到一层 |

## 8. 存量状态

截至 2026-11-26：

| 检查 | 结果 |
|---|---|
| 上游规范（第 1–3 节） | 6 个 skill，5 合规，1 违规（`ograc-dev-design` 无 `SKILL.md`） |
| oGRAC 命名规则（第 4 节） | 6 个 skill，**0 合规**，全部待改名 |
| 摆放（第 5 节，`skills/<name>/`） | 6 个 skill **全部不在** `skills/` 下，待 M1–M6 迁移 |

两件事分开推进：`ograc-dev-design` 的结构问题记在 R13，六个 skill 的改名记在 R14，责任人与验收见迁移清单。改名完成前 `--strict` 的该项会持续报红，这是预期状态。
