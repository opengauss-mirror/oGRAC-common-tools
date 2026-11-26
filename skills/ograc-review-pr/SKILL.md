---
name: ograc-review-pr
description: >-
  登录 GitCode 对 Pull Request 做行级代码检视并发布评论。要求挂到 Files 对比的右侧改动行，
  评论统一为「[问题描述]/[修改建议]」格式。在用户要求检视 PR、GitCode review、行内评论、
  或给出 gitcode.com/.../pull/N 链接时使用。
---

# GitCode PR 行级检视

## 何时使用

用户要检视 GitCode PR，并以本人账号在 **diff 改动行** 上评论（不是只发一条总评）。

## 硬性要求

1. **行级评论优先**：在 Files 对比里对具体改动行挂评论；总评可选、不可替代行评。
2. **锚在右侧新文件行**：`position` = 新文件行号（RIGHT / `start_new_line`）。禁止用 GitHub 风格的 diff 相对 offset。
3. **评论正文格式**（必须严格两段，中文）：

```text
[问题描述]<一句话说明问题与影响>
[修改建议]<可执行的改法>
```

示例：

```text
[问题描述]历史上限 20→500。
[修改建议]请确认默认硬上限是否过大；文档中说明可用 `OGSQL_HISTSIZE` 裁剪。
```

4. **不要**在正文里写 `**[Critical]**` / `**[High]**` 等严重度标题（严重度只放在回复用户的摘要表里）。
5. **UTF-8**：Windows 上用 `curl.exe` + 无 BOM 的 UTF-8 JSON 文件发帖；避免 PowerShell `ConvertTo-Json` 直接传中文导致乱码。
6. **勿提交密钥**：本 skill 目录下的 `gitcode_auth.json`、`gitcode_account.txt` 及 token 不得 git add/commit（已列入本目录 `.gitignore`）。

## 账号与认证

按优先级读取（路径相对本 skill 目录 `skills/ograc-review-pr/`）：

1. `gitcode_auth.json` → `token`、`username`、`api_base`（默认 `https://api.gitcode.com/api/v5`）
2. 若无 auth JSON：从同目录 `gitcode_account.txt`（或仓库 `docs/gitcode_account.txt`）解析 username/token，并写回本目录 `gitcode_auth.json`（仅本地）

请求头：`Authorization: Bearer <token>`

发帖前可 `GET {api_base}/user` 确认登录身份与用户期望一致。

## 工作流

复制并跟踪：

```text
检视进度:
- [ ] 1. 解析 PR URL → owner/repo/number
- [ ] 2. 登录并拉 meta / files / compare patch
- [ ] 3. 精读改动（用户指定文件则聚焦该文件）
- [ ] 4. 列出候选行评（问题+建议+新文件行号）
- [ ] 5. POST 行评（UTF-8 JSON）
- [ ] 6. 校验锚点（仅 start_new_line；误锚则删改）
- [ ] 7. 向用户汇总（含 PR 链接与关键结论）
```

### 1. 拉取变更

```text
GET {api_base}/repos/{owner}/{repo}/pulls/{number}
GET {api_base}/repos/{owner}/{repo}/pulls/{number}/files
GET {api_base}/repos/{owner}/{repo}/compare/{base}...{head}
```

大文件以 compare 返回的 `patch` / 本地保存的 `.diff` 为准；必要时再拉 head 源文件核对上下文。

### 2. 检视关注点（按严重度筛）

优先找可合入阻断项：

| 优先 | 关注 |
|------|------|
| 必改 | 注入/命令拼接、缓冲区越界、半更新状态、敏感信息入历史/日志 |
| 高 | API/选项兼容性破坏、长度上限不一致、错误路径污染会话 |
| 中 | 边界判断、行为与常见工具不一致、无谓的性能热点 |
| 低/建议 | 命名风格、固定大数组、可拆文件、文档缺失 |

只对**有依据的问题**发评论；不堆砌风格吹毛求疵。用户指定「只看某文件」时，行评只挂该文件。

### 3. 发布行评

```text
POST {api_base}/repos/{owner}/{repo}/pulls/{number}/comments
Content-Type: application/json; charset=utf-8

{
  "body": "[问题描述]...\n[修改建议]...",
  "path": "path/to/file.c",
  "position": <新文件行号>,
  "need_to_resolve": true|false
}
```

- `need_to_resolve`：合入前必改 → `true`；建议项 → `false`
- 选行：优先纯新增行（`+`）；避免 hunk 边界两侧都有的上下文行（易同时出现 `start_old_line`）

更新 / 删除：

```text
PATCH  {api_base}/repos/{owner}/{repo}/pulls/comments/{id}   body: {"body":"..."}
DELETE {api_base}/repos/{owner}/{repo}/pulls/comments/{id}
```

探测评论发完必须删除。

### 4. 锚点校验（必做）

发帖后 `GET .../pulls/{number}/comments`，确认本人 `diff_comment`：

- 有 `diff_position.start_new_line`（等于目标行）
- **没有**意外的 `start_old_line`（除非故意评删除行）

若落在左侧/双端：`DELETE` 后换纯 `+` 行重发。

### 5. 回复用户

中文、简洁。给出：

- PR 链接
- 行评条数 / 聚焦文件
- 按严重度的摘要表（Critical/High 写清「合入前必改」）
- 提醒在 Files 页核对锚点

## Windows 发帖注意

- 用 `curl.exe`，不要用 PowerShell 的 `curl` 别名
- JSON 先写入文件（UTF-8 无 BOM），再 `--data-binary "@file.json"`
- 手动转义 `body` 中的 `"`、`\`、换行；或用可靠 UTF-8 JSON 序列化后再写文件

## 更多

- API 细节与踩坑：用 `gc api <endpoint>` 调 GitCode REST 接口，端点见 GitCode 帮助中心（`docs.gitcode.com`）；本 skill 只依赖上列四个端点。
