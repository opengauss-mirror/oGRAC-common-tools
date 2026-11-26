# 目录迁移与整改清单

责任人按 git 提交历史归属确定（见 [`../CONTRIBUTING.md`](../CONTRIBUTING.md) 第 8 节）。同一项涉及多人时，第一位为牵头人。

优先级：**P0** 影响可用性或有安全风险；**P1** 结构重复、规范不符；**P2** 工程卫生。

## 一、已完成（2026-11-26）

| ID | 事项 | 结果 | 责任人 |
|---|---|---|---|
| R9 | 根 README 缺项 | README 改为目录索引，补上 UB 文档、孤儿脚本、dev-design | zhangzq131 |
| R1 | 固件 LFS 断链 | `images/包/` 111 个文件（约 231 MiB）移出本仓，生成 [`firmware-manifest.md`](ub-installation/firmware-manifest.md)（含 77 个 LFS 指针的真实 sha256 与大小）；`.gitattributes` 清掉失效规则 | huan |
| M11 | UB 文档去留 | 文档留在本仓，迁到 `docs/ub-installation/`；图片随迁；固件链接改为指向清单 | huan |
| — | 文档中的固件链接 | 目录链接改为升级顺序列表 + 清单引用；`ubsmtest` 改为随包说明 | huan |
| M7 | 安全 skill 归属 | 拆为独立仓库 `openGauss-security-skills`（10 个文件，已本地提交，未推送） | congzhou2603 |
| M8 | BenchmarkSQL 归位 | 迁到 `vendor/benchmarksql_ograc/` | hwworkholic |
| R4 | 构建产物入库 | 删除 `build/`（21 个 `.class`）、`dist/*.jar`、`src/client.zip`、`jTPCC.java.bak` | hwworkholic |
| R5 | 驱动版本混乱 | 删除 `lib/` 下 9 个 jar/tar.gz（含误命名文件），改为按 [`BUILD.md`](../vendor/benchmarksql_ograc/BUILD.md) 本地获取 | hwworkholic |
| R11 | 上游 Python 2 脚本 | 保留原样，`BUILD.md` 第 8 节标注，`ci` 对该路径豁免 | hwworkholic |
| R12 | 换行不统一 | 两份 UB 文档转 LF；固件目录名保持原样（随包移出） | huan |
| **新** | 示例配置泄露凭据 | `run/ograc_run.og`、`run/props.sharding`、`run/props.proxy` 中的真实内网地址与明文口令替换为占位符；`run/loop111test.sh` 的 expect 口令改为环境变量（`OS_PWD`、`OGRAC_SYS_PWD`、`NODE0`）；记录在 `vendor/benchmarksql_ograc/UPSTREAM.md` | hwworkholic |
| — | 凭据扫描补强 | `ci/check_repo.sh` 除 `password=` 与 `jdbc://IPv4` 外，新增 expect `send` 明文口令检测 | zhangzq131 |
| — | skill 规范文档与门禁 | 新增 `docs/skill-spec.md`（agentskills 规范落地版 + oGRAC 命名规则 + 扁平摆放规则）与 `ci/check_skills.py`（字段、命名、摆放、目录结构校验），接入 `--strict` | zhangzq131 |

## 二、待办

| ID | 事项 | 现状与证据 | 动作 | 责任人 | 验收 | 优先级 |
|---|---|---|---|---|---|---|
| S1 | 口令轮换 | 上述口令已进入 git 历史，等同泄露（涉 `ograc_run.og`、`props.sharding`、`loop111test.sh`） | 轮换数据库与节点口令；评估是否重写历史 | jyn88（原提交人）+ 仓库管理员 | 旧口令失效；决定记录在 `UPSTREAM.md` | P0 |
| R2 | 默认口令硬编码 | `common-scripts/ograc_sim_single.sh:276` 写入固定口令 | 改读 `OGRAC_SYS_PASSWORD`，未设则随机生成写 600 文件 | zhangzq131 | 脚本内无口令字面量 | P0 |
| R3 | 命令行明文口令 | `common-scripts/install-two-node.sh` 的 `--password`、`--node1-root-password` | 脚本已废弃，随 R6 删除 | jyn88 | 文件内无该参数 | P0 |
| S2 | 固件最终位置 | 当前仅暂存在 `oGRAC-firmware-packages`，77 个 LFS 实体仍未取回 | 取回实体、校验 `firmware.sha256`、确定发布位置并回写 `firmware-README.md` | huan | `sha256sum -c` 全 OK，文档指向最终位置 | P1 |
| S3 | 安全仓远端 | 独立仓只有本地初始提交 | 在 GitCode 建仓并推送，通知使用方改地址 | congzhou2603 | 远端可克隆，两个 SKILL.md 可加载 | P1 |
| R6 | 孤儿部署脚本 | `install-two-node.sh` 858 行、权限 644、无引用、与 `ograc-two-node-deploy` 重复 | 删除或移入 `tools/legacy/` | jyn88 | `--strict` 的「可执行位」项转绿 | P1 |
| R7 | skill 目录不合规 | `ograc-skills/ograc-dev-design/` 无 `SKILL.md`，4 个文件里 2 个声明同一 `name`，`代码检视SKILL.md` 与外部 `gitcode-pr-review` 重名，链接 `gitcode-api.md` 不存在 | 合并为 `SKILL.md` + `references/`，检视 skill 独立成目录，修断链 | shirley_zhengx | `--strict` 的 skill 规范与断链两项转绿 | P1 |
| R13 | skill 不符合 agentskills 规范 | `ci/check_skills.py --spec-only` 基线：6 个 skill，5 合规，1 违规（`ograc-dev-design` 无 `SKILL.md`，实际为三个 `*SKILL.md`）。规范见 [`skill-spec.md`](skill-spec.md) | 按规范拆分：`SKILL.md` 与目录同名、`code-review` 独立成目录 | shirley_zhengx | `python3 ci/check_skills.py --spec-only` 退出码 0 | P1 |
| R14 | skill 名不符合 oGRAC 命名规则 | 规则 2026-11-26 生效，6 个 skill 全部不满足：4 个第二段不是动词，`tpcc-prepare-data` 缺前缀，`ograc-dev-design` 另有无 `SKILL.md` 问题。改名对照见 [`skill-spec.md`](skill-spec.md) 4.4 | 按对照表改目录名 + `name` + 全仓引用 | zhangzq131（4 个）、luodongxu（1 个）、shirley_zhengx（1 个） | `python3 ci/check_skills.py` 退出码 0 | P1 |
| R10 | 门禁未进流水线 | `ci/check_repo.sh` 只在本地跑 | 整改项关闭后把 `--strict` 设为默认并接入 GitCode 流水线 | zhangzq131 | 断链、LFS 指针、不合规目录能报红 | P1 |
| M1 | `ograc-skills/ograc-two-node-deploy/` | 位置未变 | 迁 `skills/ograc-two-node-deploy/`（扁平，不建分组目录） | zhangzq131 | 引用全部更新，`ci` 通过 | P2 |
| M2 | `ograc-skills/ograc-cold-restore/` | 位置未变 | 迁 `skills/ograc-cold-restore/`（扁平） | zhangzq131 | 同上 | P2 |
| M3 | `ograc-skills/tpcc-prepare-data/` | 位置未变，依赖 `vendor/benchmarksql_ograc` | 迁 `skills/tpcc-prepare-data/`（扁平） | zhangzq131 | 同上 | P2 |
| M4 | `ograc-skills/ograc-process-fault-longrun/` | 位置未变 | 迁 `skills/ograc-process-fault-longrun/`（扁平） | zhangzq131 | 同上 | P2 |
| M5 | `ograc-skills/ograc-dev-design/` | 位置未变，不合规 | 先做 R7 再迁 `skills/ograc-dev-design/`（扁平） | shirley_zhengx | 同上 | P2 |
| M6 | `ograc-docs-review/` | 位置未变 | 迁 `skills/ograc-docs-review/`（扁平） | luodongxu | 同上 | P2 |
| M9 | `common-scripts/ograc_sim_single.sh` | 位置未变 | 迁 `tools/ograc-sim-single/` | zhangzq131 | 同上 | P2 |
| M10 | `common-scripts/install-two-node.sh` | 已废弃 | 随 R6 删除或迁 `tools/legacy/` | jyn88 | 同上 | P2 |
| R8 | 文档重复 | 根 README 已是索引；`ograc-skills/README.md` 仍有 127 行细节 | 各 skill README 保留 ≤3 行跳转，细节只在 `SKILL.md` | zhangzq131 | 同一段说明全仓只出现一次 | P2 |

## 三、执行顺序

1. **S1、R2、R3**：安全项，先止血再谈结构。
2. **S2、S3**：两个已拆出资产补齐远端与实体文件，别让拆分停在半路。
3. **R7、R13、R14 → M5、R6 → M10**：先合规再迁移，改名与迁移合并成一个 PR 完成。
4. **M1–M4、M6、M9**：四个 ograc skill 与 sim 脚本归位，一次一个 PR。
5. **R8、R10**：文档收敛后把 `--strict` 设为默认并接入流水线。
