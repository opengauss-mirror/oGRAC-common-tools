# skills/

oGRAC 相关 agent skill 的归集目录。每个子目录一个 skill，入口固定为 `<skill>/SKILL.md`。

当前状态：**骨架，迁移中**。现有内容仍在 `ograc-skills/`、`ograc-docs-review/`、`security-developing-skills/`，迁移顺序、责任人与验收标准见 [`../docs/migration-map.md`](../docs/migration-map.md)。

新增 skill 请直接建在这里，并遵守 [`../docs/skill-spec.md`](../docs/skill-spec.md)（agentskills 规范 + oGRAC 命名规则）。

**扁平摆放**：一个 skill 就是 `skills/<name>/`，不要再加分组目录（没有 `skills/<分类>/<name>`）。

校验：`python3 ci/check_skills.py`。
