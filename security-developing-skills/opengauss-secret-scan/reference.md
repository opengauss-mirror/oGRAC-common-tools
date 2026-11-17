# 扫描参考

## 范围

- 组织：`opengauss`，公开主仓。默认分支以台账 `repo.default_branch` 为准。
- ref：分支、Tag、`refs/pull`、`refs/merge-requests`、`refs/keep-around`、`refs/tmp`、`refs/notes`。
- 不扫：外部 fork、PR/Issue 评论、Wiki、Release 附件、LFS 对象。

水位写在报告里的 HTML 注释 `opengauss-scan-watermark`。增量只解析这段 JSON。每个仓库记录默认分支名、结束提交、本次新增提交数。

## 纳入与排除

纳入规则：`huawei-cloud-ak`、`huawei-cloud-sk`、`gitcode-gitee-token`、`gitcode-gitee-url-token`、`llm-sk-api-key`、`openai-api-key`。`generic-api-key` 只在片段含 `access_token` 或 `private_token`，且路径不是 `calender.js` / `calendar.js` 时纳入。

排除：未与 AK 出现在同一路径的 SK；`sk-migration-`、`sk-snapshot-`、`sk-pull-`、`sk-delete-`、`sk-spinner-`、`sk-toggleable`、`sk-your-`、`sk-proj-abcdefgh`、`sk-secret-after-redaction`；博客或示例数据里的 `aws-access-token`；`huawei-internal-host`、`huawei-confidential`、私钥、JWT。

AK 与 SK 按「同一路径里成对出现」合并。同一个 AK 在多个文件出现仍是一行。

## 只读核验

- OBS：对该区域 `ListBuckets`（签名版本 2）。文件里的主机是内网地址且 TCP 443 不通时，结果为无法确认。
- Gitee / GitCode：`GET /api/v5/user`。
- 大模型 Key：对 DeepSeek、百炼兼容接口、OpenAI 的 `/models` 发 `Authorization: Bearer`。任一 200 为有效；全部 401 为失效；没有明确拒绝为无法确认。

结果缓存在工作目录 `verify-cache.json`，键是提供者与密钥的 SHA-256，不写原文。增量默认读缓存。`--recheck` 才重新请求。

## 常见故障

- `self-signed certificate in certificate chain`：orgscan 把 git 的 SSL 后端固定成 openssl。只在扫描进程里设 `GIT_SSL_NO_VERIFY=1`。
- 旁路提交有密钥但 gitleaks 为 0：排除 pathspec 没写正例路径。全量和增量都要 `--no-exclude-binary`。
- `--seen-namespace` 不能单独迫使重扫。跳过条件是 `status=done` 且 ref 未变。
