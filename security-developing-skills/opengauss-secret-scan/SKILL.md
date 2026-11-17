---
name: opengauss-secret-scan
description: >-
  使用 https://gitcode.com/CCCHHHMMM/repo_secret_scan 扫描 https://gitcode.com/opengauss
  全部公开仓库的历史提交，归一化 AK/SK、GitCode/Gitee access_token、OBS 访问密钥和大模型 API Key，
  只读核验是否仍有效，并写出 opengauss-敏感信息扫描结果.md。支持按报告中的结束提交做增量扫描。
  Use when the user asks to scan openGauss secrets, orgscan, repo_secret_scan, AK/SK,
  access_token, OBS keys, LLM API keys, or to incrementally rescan opengauss.
---

# openGauss 仓库敏感信息扫描

工具：<https://gitcode.com/CCCHHHMMM/repo_secret_scan>。只扫 `opengauss` 组织的公开主仓，不扫外部 fork，不读桶内对象，不对密钥做写操作。报告含原文，只留本地，不要外发、不要提交进 git。

脚本：`scripts/run_scan.py`。规则：`rules/opengauss.toml`。细节见 [reference.md](reference.md)。

## 功能 1：全量

扫描 openGauss 所有仓库的历史全量 commit，主要针对 aksk / gitcode gitee 的 access_key，obs 桶的访问密钥，大模型的 api key 等。基于工具完成扫描，对同一泄漏资源归一化，并验证泄漏的敏感信息是否还有效。

输出 `opengauss-敏感信息扫描结果.md`，记录：

1. 所有仓库的扫描 commit 范围。
2. 敏感信息表格，分成四张：「确认仍然有效，属于官方社区资源」「确认仍然有效、不属于官方社区资源」「确认已失效」「无法确认」。列：敏感信息名称，敏感信息类型，commit 链接，敏感信息原文，敏感信息文件链接，合入者 id，是否有效，最近代码分支是否已整改。

```bash
python scripts/run_scan.py full --out opengauss-敏感信息扫描结果.md
```

已有完整台账、只重建报告时加 `--from-ledger`。全量重扫会把仓库状态改回 pending，耗时长，不要和增量搞混。

## 功能 2：增量

从功能 1 写出的 `opengauss-敏感信息扫描结果.md` 提取每个仓库的 commit 结束位置，只扫描新增 commit。后续要求与功能 1 相同：同一资源归一化、只读核验、四张表，并更新扫描范围。

```bash
python scripts/run_scan.py incremental --out opengauss-敏感信息扫描结果.md
```

没有水位注释时停止，先跑全量。不要为了增量去重置 `status` 或删除 `refs/ss/seen`。

## 必须遵守的跑法

- 工作目录默认 `D:/orgscan/opengauss`（可用 `--workdir`）。
- 进程环境设置 `GIT_SSL_NO_VERIFY=1`。不要改全局 git config。
- orgscan 命令带上 `--org opengauss --no-forks --no-exclude-binary --all-refs --engines gitleaks`，以及本技能的 `--rules`。
- 不带 `--no-exclude-binary` 时，gitleaks 的排除 pathspec 会漏掉旁路提交里的密钥。
- `status=done` 且远端 ref 未变时，orgscan 会跳过。全量重扫才把 `repo.status` 改回 `pending`。

## 判定

- 同一 AK/SK、同一 token、同一 API Key 跨提交、跨仓库只留一行。代表提交取最早的一条。
- 官方社区资源：infra 构建配置、回归测试 OBS、仓库内官方文档中的默认值、用于 `opengaussorg` 的令牌。个人仓库或贡献者自己的密钥不算。
- 有效：只读身份或 ListBuckets 成功。失效：目标接口明确拒绝（401 或 `InvalidAccessKeyId`）。内网地址不可达，或签名/网络失败：无法确认。
- 最近代码分支是否已整改：当前默认分支文件里已经没有原文为「是」，否则为「否」，并写上仍在的路径。

## 用法

在技能目录或任意目录执行（把脚本路径换成实际路径）：

```bash
python scripts/run_scan.py full --from-ledger --out opengauss-敏感信息扫描结果.md
python scripts/run_scan.py incremental --no-fetch --out opengauss-敏感信息扫描结果.md
python scripts/run_scan.py incremental --only opengauss/playground-course --since-parent 1 --no-fetch
```

`--since-parent 1` 只用于验证增量：把该仓库的起点临时当成默认分支的父提交，扫完仍把水位写回真实尖端。
