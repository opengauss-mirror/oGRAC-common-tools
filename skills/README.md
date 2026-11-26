# skills/

oGRAC 的 agent skill 集合。每个子目录一个 skill，入口固定为 `<skill>/SKILL.md`，**扁平放置、不分组**。

| skill | 作用 | 责任人 |
|---|---|---|
| [`ograc-deploy-two-node/`](ograc-deploy-two-node/SKILL.md) | 两节点集群的构建、安装、启动、验证 | zhangzq131 |
| [`ograc-restore-cold-backup/`](ograc-restore-cold-backup/SKILL.md) | `dsscmd cp` 停机一致冷备与整实例回拷 | zhangzq131 |
| [`ograc-prepare-tpcc-data/`](ograc-prepare-tpcc-data/SKILL.md) | TPC-C 数据准备（默认 100 仓） | zhangzq131 |
| [`ograc-run-process-fault-longrun/`](ograc-run-process-fault-longrun/SKILL.md) | 冷备恢复 + 全冲突 TPC-C + 随机 SIGKILL 的长稳流水线 | zhangzq131 |
| [`ograc-develop-from-design/`](ograc-develop-from-design/SKILL.md) | 按设计文档与约束型 Prompt 开发 GBP/UB 代码 | shirley_zhengx |
| [`ograc-review-pr/`](ograc-review-pr/SKILL.md) | GitCode PR 行级检视与评论 | shirley_zhengx |
| [`ograc-review-docs/`](ograc-review-docs/SKILL.md) | 中文文档低级错误检视与修复 | luodongxu |

## 通用约定

- **环境无关**：不含真实主机、用户名、LUN WWID、密码或本地路径；节点地址、部署目录、端口、LUN 全部由环境变量传入（`NODE0`/`NODE1`、`ROOT`、`SRC` 等，见各 `SKILL.md` 的「环境参数」）。
- **多人共用主机安全**：只操作当前用户 / 当前部署 `ROOT` 的进程与资源，禁止宽泛 `pkill`/`killall`；停止、删除、覆盖前先确认目标属于本实例。
- **密码**：只通过环境变量或权限 600 的口令文件传递，不写入日志与命令输出。

## 规范与校验

- 目录结构、字段约束、命名规则： [`../docs/skill-spec.md`](../docs/skill-spec.md)（agentskills 规范 + `ograc-<动词>-<对象>` 命名）。
- 校验：`python3 ci/check_skills.py`；只查上游规范用 `--spec-only`。
- 新增 skill 直接建 `skills/<name>/`，不要再加分类目录。
