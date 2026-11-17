# opengauss-third-party-cve

修复并验证 [openGauss-third_party](https://gitcode.com/opengauss/openGauss-third_party) 的 CVE。给定本地仓库和一个 gitcode issue，确认组件与官方影响范围，排查 `master`、`7.0.0`、`6.0.0`。只给落在影响范围内、且尚未合入补丁的分支打补丁，编译通过后在本地 bugfix 分支提交。不推送，不创建 PR。

技能名是 `opengauss-third-party-cve`。给代理执行的步骤在 `SKILL.md`。

## 安装

把本目录复制到代理的 skills 目录，目录名保持 `opengauss-third-party-cve`：

```bash
cp -a opengauss-third-party-cve ~/.codex/skills/opengauss-third-party-cve
```

Cursor 若使用自己的 skills 目录，同样整目录复制过去。OpenCode 可放到 `.opencode/skills/opengauss-third-party-cve/` 或 `.agents/skills/opengauss-third-party-cve/`。复制后新开一个对话再生效。

## 用法

新对话里写明技能名、本地仓库路径和 issue 链接：

```text
使用 skill opengauss-third-party-cve。
仓库：/path/to/openGauss-third_party
issue：https://gitcode.com/opengauss/openGauss-third_party/issues/420
```

默认只查 `master`、`7.0.0`、`6.0.0`。要多查分支时在同一句话里点名，例如「再查 5.0.0」。

代理会：

1. 从 issue 取出 CVE、组件和补丁链接。影响范围以组件官方公告为准，不把 issue 里的「漏洞归属的版本」当成全部受影响版本。
2. 在 src-openeuler 问题单中找已经关闭的对应修复。问题单仍开放时，采用与仓库组件版本同一条上游版本线的提交。
3. 按该组件已有的合入方式登记补丁。`patch_list` 追加一项；`build.sh` 在解包后追加 `patch -p1`。参考合入方式：<https://gitcode.com/opengauss/openGauss-third_party/pull/515>。
4. 用组件自己的构建入口编译。有 `build.sh` 时执行 `sh build.sh`；只有 `build.py` 时执行 `python3 build.py -m build -f <源码包> -t comm`。编译成功才算通过。
5. 从对应分支的最新提交建立 `bugfix-cve-<cve小写>-<分支名>`，只提交补丁和构建清单。

源码包经常是 Git LFS 指针。验证时要换成真实包，提交前恢复指针。不要把源码包、解包目录和编译产物提交进去。

## 输出

每个 issue 结束时给出影响性分析、openGauss 评分、三个分支的受影响结论，以及本地分支名。不受影响的分支不建 bugfix 分支。

```text
影响性分析说明：
<该 CVE 的英文影响说明>

漏洞评分(openGauss评分):
 BaseScore： <分数> <Low|Medium|High|Critical>
 Vector：CVSS:3.1/...

受影响版本排查(受影响/不受影响)：
1.master: ...
2.7.0.0: ...
3.6.0.0: ...

本地修改：
- master: bugfix-cve-<编号>-master，<提交说明>
- 7.0.0: 未修改
- 6.0.0: 未修改
```

issue 或 NVD 已有非 N/A 分数时沿用该分数。两边都是 N/A 时，按官方公告的严重级别、攻击条件和机密性、完整性、可用性影响写成 CVSS 3.1。

## 许可证

MulanPSL-2.0
