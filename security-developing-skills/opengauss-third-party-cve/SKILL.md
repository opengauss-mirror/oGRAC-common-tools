---
name: opengauss-third-party-cve
description: "修复并验证 openGauss-third_party 的 CVE。给定本地仓库和 gitcode issue，确认组件与官方影响范围，排查 master、7.0.0、6.0.0；只给落在影响范围内且尚未合入补丁的分支打入 src-openeuler 已关闭问题单或上游对应版本线的 patch，用该组件自己的 build.sh 或 build.py 编译验证，在本地 bugfix 分支提交，不推送、不建 PR，并按固定模板输出影响性分析。Use when fixing, verifying, or backporting a CVE or security issue in openGauss-third_party, including openssl, libxml2, patch_list, build.sh, and src-openeuler."
---

# openGauss-third_party CVE 修复与验证

给定本地 `openGauss-third_party` 仓库和一个 gitcode issue。只修复真正落在影响范围内、且该分支还没有对应补丁的版本。验证通过后在本地 bugfix 分支提交。不要推送，不要创建 PR。

## 输入

- 本地仓库路径。
- issue 链接，例如 `https://gitcode.com/opengauss/openGauss-third_party/issues/420`。
- 默认排查分支：`master`、`7.0.0`、`6.0.0`。用户另点名分支时再增加，不要自行扩大到更老分支。

先 `git fetch` 这些分支，以远程最新提交为基线。工作区若有无关改动，不要混进 bugfix 提交。

## 1. 读 issue，分开三件事

从 issue 正文取出：

- CVE 编号
- 漏洞归属组件
- issue 里写的「漏洞归属的版本」
- 漏洞简述、CWE、补丁链接

「漏洞归属的版本」只是扫描器在某个分支上看到的包版本，不是完整影响范围。影响范围以组件官方安全公告为准，其次才是 NVD。公告里的 “not affected” 行要原样采信，例如 OpenSSL 写明 3.0、1.1.1、1.0.2 不受影响时，不要因为 issue 表格里出现这些版本就给它们打补丁。

多个修复提交通常是同一修复在不同上游版本线的 backport。打开每个 commit 或 PR，看目标分支（如 `openssl-3.5`、`4.0`、`master`），只采用与仓库里该组件版本同一条版本线的提交。

## 2. 排查三个分支

组件目录一般在 `dependency/<组件>/`，少数在 `gpl_dependency/` 或 `platform/`。对每个分支用 `git ls-tree` 看源码包名、`patch_list`、`build.sh` 或 `build.py`，不要把三个分支都 checkout 到同一个脏工作区。

版本从源码包文件名读取，例如 `openssl-3.5.8.tar.gz`、`openssl-3.0.9.tar.gz`、`openssl-1.1.1m.tar.gz`。

每个分支归入下面一种，并且写进最终报告：

- **受影响，需要修复**：仓库引入了该组件，版本落在公告的影响范围内，并且 `patch_list` 或 `build.sh` 里还没有这个 CVE 的补丁。
- **不受影响**：没有该组件；组件已日落并改为依赖操作系统自带库；或版本不在公告范围内。报告里写明对应版本和原因。
- **已有补丁，本次不改**：版本原本在范围内，但补丁已经登记。报告写明已合入，不要再叠一份。

同名但独立的包不要顺手改。例如 issue 指向 `openssl` 时，不要把 `tassl` 当成同一个组件；只有公告明确覆盖该包的版本线时才处理。

## 3. 取补丁

按这个顺序找补丁：

1. 在 `https://gitcode.com/org/src-openeuler/issues` 搜索该 CVE。GitCode API 可用：
   - `https://gitcode.com/api/v5/search/issues?q=CVE-编号`
   - `https://gitcode.com/api/v5/repos/src-openeuler/<组件>/issues/<号>/comments?per_page=100`
2. 问题单状态是 **closed**，说明该版本线已经有社区接受的结论。合入与仓库组件版本对应的那份 patch，不要拿另一条版本线的补丁硬套。
3. 问题单还是 **open** 时，先看评论里对各分支的结论。已经判定 `NOT_APPLICABLE` 的版本不要修。受影响版本若评论里还没有可下载的适配补丁，使用 issue 补丁表中、且 PR 标签对应该版本线的上游提交。补丁必须能在「现有补丁全部打上之后」干净应用。应用失败就按上下文改编 hunk，保持上游修复语义，不要另写一套修复。

把补丁保存为 `dependency/<组件>/CVE-<编号>.patch`。一个 CVE 有多段互不替代的补丁时，沿用仓库里已有的 `CVE-<编号>-1.patch` 命名。

## 4. 合入方式

对照该组件目录里已经合入的 CVE，以及 `https://gitcode.com/opengauss/openGauss-third_party/pull/515` 的做法：补丁文件进组件目录，并登记到构建脚本会真正执行的位置。

- 目录有 `patch_list`：在末尾追加下一号，例如 `Patch19: CVE-2026-35190.patch`。`build.py` 会按该清单 `patch -p1`。
- 目录有 `build.sh` 且在解包后手写 `patch -p1 < ../xxx.patch`：按现有 CVE 行的写法追加，不要只把文件放进目录。
- 不要改源码包，不要把补丁打进解包后的临时目录再提交。

登记前在临时目录演练：解包，按清单打完已有补丁，再 `patch -p1 --dry-run` 新补丁。已有补丁出现可接受的行号偏移可以继续；新补丁出现 reject 则先改编再登记。

## 5. 验证

编译成功才算通过。使用该组件自己的构建入口，让脚本自己打补丁再编译。

- 有 `build.sh`：在组件目录执行 `sh build.sh`，模式用脚本帮助信息和历史 PR 的写法。`libxml2` 一类参考 PR 515，使用 `sh build.sh -m all`。若 `all` 只是在 `build` 之后做打包和清理，至少要跑完会打补丁并编译的那个模式，退出码为 0。
- 只有 `build.py`：在组件目录执行 `python3 build.py -m build -f <目录中的源码包名> -t comm`。openssl 即此入口，没有 `build.sh`。通过标准是退出码 0，且日志出现 `[INFO] Build component finished`，补丁阶段没有 reject。

源码包经常是 Git LFS 指针，只有一百多字节，不能直接拿来编译。指针示例：

```text
version https://git-lfs.github.com/spec/v1
oid sha256:<oid>
size <size>
```

向 `https://gitcode.com/opengauss/openGauss-third_party.git/info/lfs/objects/batch` 发 LFS batch 下载请求，校验 sha256 与指针一致后再替换工作区文件供编译。编译结束后用 `git checkout -- <源码包>` 恢复指针。提交里不得包含源码包、解包目录、`install/`、`openssl_make/` 或 `output/`。

补丁上下文不对导致编译失败时，修补丁后重新完整跑构建。不要把失败的编译当成验证通过。

## 6. 提交

只对「需要修复」的分支各建一个本地分支，基于该分支最新提交：

```text
bugfix-cve-<cve小写>-<分支名>
```

例如 `bugfix-cve-2026-35190-master`。每个分支只提交该分支的补丁文件和构建清单改动。提交说明写明 CVE、组件、版本和分支。

不要 `git push`，不要开 PR，不要改远程跟踪到受保护分支之后再推送。不受影响的分支不建 bugfix 分支。

## 7. 输出

最终回复使用下面的结构。影响性说明写这个 CVE 的事实，不要套用别的组件的示例段落。评分优先用 issue 或 NVD 中已经给出的非 N/A 分数；两边都是 N/A 时，按官方严重级别和公告中的攻击条件、机密性、完整性、可用性写成 CVSS 3.1，并在说明里让向量和公告一致。不要抄另一个 CVE 的分数。

```text
影响性分析说明：
<该漏洞的英文影响说明，包含组件、缺陷类型、CWE、触发条件和机密性/完整性/可用性影响>

漏洞评分(openGauss评分):
 BaseScore： <分数> <Low|Medium|High|Critical>
 Vector：CVSS:3.1/...

受影响版本排查(受影响/不受影响)：
1.master: 受影响或不受影响，对应版本为<版本>，<必要原因>
2.7.0.0: ...
3.6.0.0: ...

本地修改：
- <openGauss 分支>: <本地分支名>，<提交说明>
- <未修改的分支>: 未修改
```

## CVE-2026-35190 的判定实例

issue 420 归属 openssl，扫描器看到的版本是 3.5.8。OpenSSL 公告 `https://openssl-library.org/news/secadv/20261117.txt` 写明 3.5、4.0、4.1 受影响，3.0、1.1.1、1.0.2 不受影响。三个上游提交里，`9491b0d9` 是 openssl-3.5 线，`9a812981` 是 4.0，`ade64619` 是 master/4.1。

- `master` 的 `openssl-3.5.8.tar.gz` 在范围内且没有该补丁，合入 `9491b0d9`，登记为 `patch_list` 的下一项，并用 `python3 build.py -m build -f openssl-3.5.8.tar.gz -t comm` 验证。
- `7.0.0` 是 openssl 3.0.9，不受影响。
- `6.0.0` 是 openssl 1.1.1m，不受影响。
- src-openeuler `openssl` issue 304 在公告当天仍是 open；其评论已经把 1.1.1 和 3.0.12 判为漏洞代码不存在。3.5 线还没有关闭后的适配补丁，因此 master 直接使用公告和 issue 补丁表中的 openssl-3.5 提交。
