# security-developing-skills

安全研发相关技能的归档目录。将对应技能目录复制到 Cursor 或 OpenCode 的 skills 目录后即可使用。

## opengauss-secret-scan

扫描 [openGauss 组织](https://gitcode.com/opengauss) 的全部公开主仓历史提交，归一化 AK/SK、GitCode/Gitee access_token、OBS 访问密钥和大模型 API Key，只读核验是否仍有效，并写出 `opengauss-敏感信息扫描结果.md`。支持按报告中的结束提交做增量扫描。

依赖工具：[repo_secret_scan](https://gitcode.com/CCCHHHMMM/repo_secret_scan)。

| 路径 | 作用 |
|---|---|
| `opengauss-secret-scan/SKILL.md` | 技能说明，以及全量、增量用法 |
| `opengauss-secret-scan/reference.md` | 纳入规则、只读核验和常见故障 |
| `opengauss-secret-scan/scripts/run_scan.py` | 扫描、归一化、核验和写报告 |
| `opengauss-secret-scan/rules/opengauss.toml` | 在 gitleaks 默认规则上追加的检测规则 |

本地台账目录默认是 `D:/orgscan/opengauss`。可用环境变量覆盖：

- `OPENGAUSS_SCAN_WORKDIR`：台账与镜像目录
- `OPENGAUSS_SCAN_REPORT`：报告输出路径
- `REPO_SECRET_SCAN`：`repo_secret_scan` 所在目录

在技能目录执行：

```bash
python scripts/run_scan.py full --out opengauss-敏感信息扫描结果.md
python scripts/run_scan.py incremental --out opengauss-敏感信息扫描结果.md
```

扫描子进程会设置 `GIT_SSL_NO_VERIFY=1`。不要修改全局 git config。

报告含密钥原文，只留本地，不要外发，不要提交进 git。

## 许可证

MulanPSL-2.0
