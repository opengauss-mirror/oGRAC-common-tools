# 变更记录

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [Unreleased]

### Added

- 仓库治理框架：根 `README.md` 改为目录索引，新增 `CONTRIBUTING.md`、`CHANGELOG.md`、`.gitignore`。
- `ci/check_repo.sh`、`ci/check_links.py`：本地质量门禁（shell/Python 语法、README 索引、明文密钥与内网地址；`--strict` 额外检查 skill 规范、断链、LFS 指针、可执行位）。
- `docs/skill-spec.md`：skill 目录规范。第 1–3 节为 agentskills 原规范，第 4 节为 oGRAC 命名规则（`ograc-<动词>-<对象>`、动词词表、只用 `-`、≤ 32 字符、禁版本号与 `helper` 类词），第 5 节规定**扁平摆放**：`skills/<name>/`，不允许 `skills/<分类>/<name>`。含正反例与改名对照。
- `docs/pr-guide.md`：PR 指引。按改动类型给出目录对照（skill / 脚本 / 参考文档 / 工具 / 第三方 / 安装文档 / 治理文档），列出不能入库的内容、提交流程、常见驳回原因。
- `ci/check_layout.py`：按 PR 指引检查文件归位——顶层目录白名单、根目录 md 白名单、`references/` 位置、脚本位置、二进制禁令；`vendor/` 保留上游结构豁免归位但仍禁构建产物；支持 `--base <ref>` 只查本分支改动，已用 5 类违规夹具验证。
- `.gitcode/workflows/gate.yml`：GitCode Actions 流水线，push 到 master / PR open·update·reopen / 手动触发时安装 Python 3.12 并跑 `ci/check_repo.sh`；`gc actions yaml validate` 校验通过。README 索引与门禁说明同步；`ci/check_repo.sh` 的目录索引检查跳过 `.` 开头的目录。
- `ci/check_skills.py`：按 agentskills 规范加 oGRAC 命名规则校验 skill 目录（`name` 与目录同名、命名字符、`description` 长度、`metadata` 值类型、入口文件名、500 行建议、引用层级、前缀/动词/连接符/长度/禁用词），并按第 5 节检查摆放（必须在 `skills/<name>/`，且禁止二级分组）；支持 `--spec-only` 只查上游规范；已用 21 个夹具验证每条规则能触发。
- `docs/migration-map.md`：目录迁移与整改清单，含责任人与验收标准。
- 目录骨架：`skills/`、`tools/`、`vendor/`、`docs/`。
- `common-scripts/README.md`：补齐此前无文档的 `ograc_sim_single.sh` 与 `install-two-node.sh` 说明。
- `vendor/benchmarksql_ograc/BUILD.md`：构建与运行指南；`lib/README.md` 列出依赖 jar 的来源。
- `vendor/benchmarksql_ograc/UPSTREAM.md`：上游基线、本分支改动、已删除文件清单。
- `docs/ub-installation/firmware-manifest.md`：固件清单（111 个文件、sha256、真实大小）。
- `docs/ub-installation/firmware-README.md`：固件获取与校验说明。
- 固件包 `oGRAC-firmware-packages/`：77 个 Git LFS 实体已全部取回（`fetch_lfs.py`，标准库 + LFS 批量接口），`sha256sum -c` 111/111 OK。
- `CODEOWNERS`：按路径声明 7 个 skill、`tools/`、`vendor/` 与治理文件的评审人；`docs/ub-installation/` 待 huan 的 GitCode 账号确认后补。
- `vendor/benchmarksql_ograc/NOTICE.md`：标明上游许可未随源码保留，禁止按 MulanPSL 再分发。
- `skills/ograc-review-pr/`：从 `ograc-dev-design` 拆出的 GitCode PR 行级检视 skill，自带 `.gitignore` 隔离凭据文件。
- `tools/ograc-sim-single/README.md`：补上原 `common-scripts/README.md` 的内容并说明 `OGRAC_SYS_PASSWORD`。

### Changed

- **6 个 skill 改名并迁入 `skills/`**（扁平、不分组）：`ograc-two-node-deploy`→`ograc-deploy-two-node`、`ograc-cold-restore`→`ograc-restore-cold-backup`、`tpcc-prepare-data`→`ograc-prepare-tpcc-data`、`ograc-process-fault-longrun`→`ograc-run-process-fault-longrun`、`ograc-docs-review`→`ograc-review-docs`、`ograc-dev-design`→`ograc-develop-from-design` + `ograc-review-pr`。
- `common-scripts/ograc_sim_single.sh` → `tools/ograc-sim-single/ograc-sim-single.sh`；数据库 sys 口令改为读 `OGRAC_SYS_PASSWORD`，未设置时随机生成 16 位并写 600 文件。
- `ci/check_repo.sh` 默认跑全量检查（含断链、skill 规范、LFS 指针、可执行位），`--quick` 保留快速回路。
- `benchmarksql_ograc/` → `vendor/benchmarksql_ograc/`，只保留源码。
- `ub_installation_doc/` 的两份文档与截图 → `docs/ub-installation/`，改为 LF 换行。
- `.gitattributes` 精简为文本规范化规则；固件 LFS 规则随文件移出而失效，已删除。
- 根 README 增加「已迁出内容」小节，说明安全 skill 与固件包的新位置。

### Removed

- `common-scripts/install-two-node.sh`：858 行的废弃部署脚本，与 `skills/ograc-deploy-two-node` 重复且以命令行传明文口令；内容保留在 git 历史。
- `common-scripts/` 目录：最后一个脚本迁入 `tools/ograc-sim-single/`。
- `ograc-skills/README.md`：127 行与各 `SKILL.md` 重复的说明，内容并入 `skills/README.md`。
- `ograc-skills/ograc-dev-design/` 的三个非规范入口（`design_driven_dev_SKILL.md`、`设计文档驱动开发SKILL.md`、`代码检视SKILL.md`）：改为标准 `SKILL.md` 结构。
- `benchmarksql_ograc/build/`、`dist/`、`src/client.zip`、`src/client/jTPCC.java.bak`。
- `lib/` 下 9 个 jar/tar.gz，含误命名的 `opengauss-jdbc-7.0.0-RC7.jar_2uweiwue`。
- `security-developing-skills/`：拆为独立仓库 `openGauss-security-skills`。
- `ub_installation_doc/images/包/`：111 个固件与软件包（约 231 MiB）拆为独立包 `oGRAC-firmware-packages`。

### Security

- `vendor/benchmarksql_ograc/run/ograc_run.og`、`run/props.sharding` 中的真实内网地址与明文口令替换为占位符。历史提交中仍可见，**口令需轮换**，见 `UPSTREAM.md`。
- `vendor/benchmarksql_ograc/run/loop111test.sh` 的 expect 口令改为 `OS_PWD` / `OGRAC_SYS_PWD` / `NODE0` 环境变量，移除写死的节点 IP。
- `ci/check_repo.sh` 新增三类检查：`password=` 后接字面量、`jdbc://` 后接 IPv4 字面量、expect `send` 明文口令。

## 2026-11-23

### Added

- `ograc-skills/ograc-dev-design`：设计文档驱动开发、Prompt 模式总结。
