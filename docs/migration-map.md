# 目录迁移与整改清单

责任人按 git 提交历史归属确定，与 [`../CODEOWNERS`](../CODEOWNERS)、[`../CONTRIBUTING.md`](../CONTRIBUTING.md) 第 8 节保持一致。同一项涉及多人时，第一位为牵头人。

优先级：**P0** 影响可用性或有安全风险；**P1** 结构重复、规范不符；**P2** 工程卫生。

## 一、已完成（2026-11-26）

| ID | 事项 | 结果 | 责任人 |
|---|---|---|---|
| R9 | 根 README 缺项 | 改为目录索引，随迁移再次收敛为「每个 skill 一行」 | zhangzq131 |
| R1 | 固件 LFS 断链 | `images/包/` 111 个文件（约 231 MiB）移出本仓，生成 [`firmware-manifest.md`](ub-installation/firmware-manifest.md)（含 77 个 LFS 指针的真实 sha256 与大小）；`.gitattributes` 清掉失效规则 | huan |
| M11 | UB 文档去留 | 文档留在本仓，迁到 `docs/ub-installation/`；图片随迁；固件链接改为指向清单 | huan |
| M7 | 安全 skill 归属 | 拆为独立仓库 `openGauss-security-skills`（10 个文件，已本地提交） | congzhou2603 |
| M8 | BenchmarkSQL 归位 | 迁到 `vendor/benchmarksql_ograc/` | hwworkholic |
| R4 | 构建产物入库 | 删除 `build/`（21 个 `.class`）、`dist/*.jar`、`src/client.zip`、`jTPCC.java.bak` | hwworkholic |
| R5 | 驱动版本混乱 | 删除 `lib/` 下 9 个 jar/tar.gz（含误命名文件），改为按 [`BUILD.md`](../vendor/benchmarksql_ograc/BUILD.md) 本地获取 | hwworkholic |
| R11 | 上游 Python 2 脚本 | 保留原样，`BUILD.md` 第 8 节标注，`ci` 对该路径豁免 | hwworkholic |
| R12 | 换行不统一 | 两份 UB 文档转 LF | huan |
| — | 示例配置泄露凭据 | `run/ograc_run.og`、`run/props.sharding`、`run/props.proxy` 改占位符；`run/loop111test.sh` 的 expect 口令改为环境变量；记录在 [`UPSTREAM.md`](../vendor/benchmarksql_ograc/UPSTREAM.md) | hwworkholic |
| — | 凭据扫描补强 | `ci/check_repo.sh` 覆盖 `password=`、`jdbc://IPv4`、expect `send` 明文口令三类 | zhangzq131 |
| — | skill 规范与门禁 | `docs/skill-spec.md`（agentskills + oGRAC 命名 + 扁平摆放）+ `ci/check_skills.py`，接入门禁 | zhangzq131 |
| R7 / R13 | `ograc-dev-design` 结构不合规 | 拆为 `skills/ograc-develop-from-design/`（`SKILL.md` + `references/prompt-patterns.md`）与 `skills/ograc-review-pr/`；重名、断链、入口缺失同时解决 | shirley_zhengx |
| R14 / M1–M6 | 6 个 skill 改名并迁入 `skills/` | 全部完成，见 [`skill-spec.md`](skill-spec.md) 4.4；新增 `skills/ograc-review-pr/` | zhangzq131 / luodongxu / shirley_zhengx |
| R2 / M9 | sim 脚本口令与归位 | `tools/ograc-sim-single/ograc-sim-single.sh`：口令改读 `OGRAC_SYS_PASSWORD`，未设则随机生成 16 位写 600 文件 | zhangzq131 |
| R3 / R6 / M10 | 废弃部署脚本 | 删除 `common-scripts/install-two-node.sh`（858 行、带 `-p/--password`），内容留在 git 历史 | jyn88 |
| R8 | 文档重复 | 删除 `ograc-skills/README.md`（127 行重复）；`skills/README.md` 收敛为「表格 + 通用约定」 | zhangzq131 |
| R15 | 无 CODEOWNERS | 新增 [`CODEOWNERS`](../CODEOWNERS)，7 个 skill、`tools/`、`vendor/`、治理文件按路径映射 | zhangzq131 |
| R16 | vendored 许可缺失 | 新增 [`NOTICE.md`](../vendor/benchmarksql_ograc/NOTICE.md)：标明上游未随源码保留许可，禁止按 MulanPSL 再分发；许可证原文仍待补 | hwworkholic |
| R10 | 门禁未默认 | `ci/check_repo.sh` 默认跑全量检查，`--quick` 保留快速回路；`--strict` 仍兼容 | zhangzq131 |
| S2 | 固件实体取回 | 77 个 LFS 指针实体已用标准库脚本（LFS 批量接口）全部取回，`sha256sum -c firmware.sha256` → **111 个全部 OK**，包内已无指针 | huan |
| S3 | 安全仓远端 | 已在 GitCode 建仓 `luodongxu/openGauss-security-skills`（public）并推送，远端 master = `f1be01c` | congzhou2603 |

## 二、待办

| ID | 事项 | 现状与证据 | 动作 | 责任人 | 验收 | 优先级 |
|---|---|---|---|---|---|---|
| G1 | MR #18 待评审合并 | 分支 `refactor/repo-cleanup`，`mergeable: true`，`merge_by_self_passed: true`；未合并前所有整理只在分支上 | 评审后合并，删除分支 | luodongxu（作者）+ zhangzq131（评审） | `opengauss/master` 包含这批提交 | P0 |
| S1 | 口令轮换 | 旧口令仍在 git 历史（`ograc_run.og`、`props.sharding`、`loop111test.sh`），等同泄露 | 轮换数据库与节点口令；评估是否重写历史 | jyn88（原提交人）+ 仓库管理员 | 旧口令失效；决定记录在 `UPSTREAM.md` | P0 |
| S2 | 固件发布位置 | 实体已取回并校验（111/111 OK），但最终存放位置未定 | 定独立仓库 / Release 附件 / 制品库，并回写 `firmware-README.md` | huan | 文档指向最终位置，其他人可按文档拿到包 | P1 |
| S3 | 通知使用方改地址 | 仓已建并推送，但原来引用本仓路径的人还不知情 | 在团队渠道告知新地址，必要时改旧 README 引用 | congzhou2603 | 无人在旧路径上提改动 | P2 |
| R16 | 补上游许可证原文 | `vendor/benchmarksql_ograc/NOTICE.md` 已说明现状，仍缺许可证本体 | 从上游发布包取出 `LICENSE`/`COPYING` 放到位 | hwworkholic | 目录内有许可文件且 NOTICE 指向它 | P1 |
| R15 | CODEOWNERS 收尾 | `docs/ub-installation/` 的 owner `huan` 在 GitCode 无同名账号；仓级 `approval_required_reviewers_count=0`，路由不拦截 | 确认 huan 的登录名并补规则；把必需评审数设为 ≥1 | zhangzq131（需 huan 提供账号） | 改到该路径自动请求评审，且未获批不能合 | P1 |
| R10 | 门禁接入流水线 | 本地已默认全量，但未接 GitCode 流水线 | 按平台 CI 格式接入，PR 必跑 | zhangzq131 | PR 上可见检查结果，失败阻断合并 | P1 |
| S4 | 安全仓无规范与门禁 | 该仓只有 README、LICENSE 与两个 skill，无规范文档、无 `ci/`；技能名 `opengauss-*` 未定义命名规则 | 复用本仓规范与校验器，前缀改 `opengauss-` | congzhou2603 | 该仓有自己的规范文档与可跑的校验 | P2 |

## 三、执行顺序

1. **G1**：先合 MR，否则下面所有整改都堆在分支上。
2. **S1**：口令轮换，历史处置由管理员定。
3. **S2（发布位置）、S3、R16**：三个已拆出/第三方资产的收尾。
4. **R15、R10**：评审与流水线两道门配齐。
5. **S4**：安全仓自建规范。
