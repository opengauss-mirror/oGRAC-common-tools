# oGRAC-common-tools

oGRAC 定制适配工具管理仓库。

## 工具清单

### ograc-docs-review

oGRAC 中文文档低级错误检视与修复 skill。

- 作用：自动扫描 `docs/zh/` 下 Markdown（含 `_toc.yaml`），按规则修复错别字、产品命名不一致、中英文混排空格、行内代码缺失、SQL 关键字大小写、Markdown 格式、口语化表述、Shell 代码块可复制性、弯引号等。
- 触发：在 OpenCode 中处理「检视/审校/修复/规范化 docs/zh 文档」「文档低级错误」「文档格式检查」「清理口语化」「PR 文档自检」「同步官方文档前批量检查」或任何涉及 oGRAC 中文文档质量批处理的任务时，agent 会自动加载本 skill。
- 使用：将 `ograc-docs-review/` 目录复制到 `.opencode/skills/ograc-docs-review/` 或 `.agents/skills/ograc-docs-review/` 下即可生效。
- 规则文件：`ograc-docs-review/references/ograc_rules.json`

### security-developing-skills

安全研发技能归档。

- 作用：存放可复用的安全研发技能。当前包含 `opengauss-secret-scan`，用于扫描 openGauss 公开主仓历史提交中的 AK/SK、GitCode/Gitee access_token、OBS 访问密钥和大模型 API Key，并只读核验是否仍有效。
- 使用：说明见 `security-developing-skills/README.md`。将 `security-developing-skills/opengauss-secret-scan/` 复制到 Cursor skills 目录后，按其中的 `SKILL.md` 运行。
- 注意：扫描报告含密钥原文，只留本地，不要提交进 git。

## 许可证

MulanPSL-2.0
