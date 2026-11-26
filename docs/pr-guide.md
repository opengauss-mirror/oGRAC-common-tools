# PR 指引

新增或改动任何文件前，先按第 1 节选目录。选错目录会被 `ci/check_layout.py` 拦下，规则与本文一一对应。

## 1. 按改动类型选目录

| 你要加/改的东西 | 放哪 | 示例 |
|---|---|---|
| 新的 agent skill | `skills/<ograc-动词-对象>/`，含 `SKILL.md` | `skills/ograc-review-pr/` |
| skill 的脚本 | `skills/<name>/scripts/` | `skills/ograc-deploy-two-node/scripts/preflight.sh` |
| skill 的细节文档、排障手册 | `skills/<name>/references/` | `skills/ograc-run-process-fault-longrun/references/failure-triage.md` |
| skill 的模板、配置、补丁 | `skills/<name>/assets/` | `skills/ograc-deploy-two-node/assets/config-node0.json` |
| 给人直接在终端跑的工具 | `tools/<tool-name>/` | `tools/ograc-sim-single/` |
| 第三方或上游源码分支 | `vendor/<project>/`，保留上游结构 | `vendor/benchmarksql_ograc/` |
| 整机 / OS / 固件安装文档 | `docs/ub-installation/` | `docs/ub-installation/安装UB流程.md` |
| 跨工具文档、规范、清单 | `docs/` | `docs/skill-spec.md` |
| 仓库自检脚本 | `ci/` | `ci/check_layout.py` |
| 根目录文档 | 只允许 `README.md`、`CONTRIBUTING.md`、`CHANGELOG.md` | — |

三条硬边界：

- **顶层目录只有五个**：`skills/`、`tools/`、`vendor/`、`docs/`、`ci/`。新增分类目录会被拒。
- **skill 扁平**：`skills/<name>/`，不允许 `skills/<分类>/<name>/`。
- **`vendor/` 豁免归位检查**（保留上游结构），但仍然禁止构建产物和二进制。

## 2. 不能入库的东西

| 内容 | 正确去处 |
|---|---|
| 构建产物与二进制（`.jar`、`.class`、`.rpm`、`.zip`、`.tar.gz`、`.so`、`.bin`、`.hpm`、`.odt` 等） | Release 附件、Git LFS、独立包（如 `oGRAC-firmware-packages`） |
| 真实主机地址、账号、口令 | 一律写 `<host>`、`<password>` 占位符；需要时用环境变量或权限 600 的口令文件 |
| 扫描报告（含密钥原文） | 本地保存，`.gitignore` 已覆盖 `*敏感信息扫描结果*.md` |

## 3. 提 PR 的流程

1. 从 `master` 开分支，命名 `type/短描述`（`fix/`、`refactor/`、`docs/`、`ci/`），不直接推 `master`。
2. **一个 PR 一件事**。迁移、修复、新功能分开；`skills/` 与 `vendor/` 的改动不要混在一个 PR 里。
3. 标题用中文动词开头，沿用仓库习惯（如 `新增 ograc-skills：冷备与实例恢复 skill`）。
4. 描述写三块：**改了什么**、**怎么验证**、**风险/行为变化**。
5. 本地跑门禁：

   ```bash
   ci/check_repo.sh                                  # 全部检查
   ci/check_repo.sh --quick                          # 只要语法/索引/密钥
   python3 ci/check_layout.py --base origin/master   # 只看本分支改了哪些文件放错位置
   python3 ci/check_skills.py                        # 改到 skill 时必跑
   ```

6. 改名或移动文件时，同时改所有引用，别留断链：

   ```bash
   grep -rl '<旧名字>' --include='*.md' --include='*.sh' --include='*.py' .
   ```

7. 推上去等 `CODEOWNERS` 自动拉对应责任人评审。

## 4. 常见驳回原因

| 现象 | 正确做法 |
|---|---|
| 在 `skills/` 下建分类目录，如 `skills/security/xxx/` | 拍平为 `skills/ograc-scan-xxx/` |
| 根目录新增 `NOTES.md`、`TODO.md` | 放 `docs/` |
| 脚本放在仓库根或 `docs/` 下 | `tools/<name>/` 或 `skills/<name>/scripts/` |
| 把 `*.tar.gz`、`*.rpm` 提交进来 | 放 Release 附件或独立包 |
| 一个 PR 同时改 skill 和 `vendor/` | 拆成两个 PR |
| 改了 skill 名但没改引用 | 按第 3 节第 6 条全仓替换 |
| props/连接串里写真实地址 | 用占位符，见第 2 节 |

## 5. 门禁与本文的对应关系

| 规则 | 检查位置 |
|---|---|
| 顶层目录白名单、根目录 md 白名单、`references/` 位置、脚本位置、二进制禁令 | `ci/check_layout.py` |
| skill 的命名、frontmatter 字段、扁平摆放 | `ci/check_skills.py`（规则见 [`skill-spec.md`](skill-spec.md)） |
| 明文口令、`jdbc://` 字面量 IP、expect 明文口令 | `ci/check_repo.sh` 的密钥扫描 |
| Markdown 断链 | `ci/check_links.py` |
| shell/Python 语法、可执行位 | `ci/check_repo.sh` |
