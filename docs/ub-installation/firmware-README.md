# 固件包获取与校验

本仓库只保留文档，**固件、BIOS、BMC、CPLD、UB 软件包等二进制不在仓库内**。

## 1. 需要哪些文件

完整清单（111 个文件，解包后约 231 MiB）与每个文件的 SHA-256 见
[`firmware-manifest.md`](firmware-manifest.md)。固件升级顺序见
[`安装UB流程.md`](安装UB流程.md) 第二章。

## 2. 从哪里拿

按用途分两类：

| 文件类型 | 来源 |
|---|---|
| 整机固件（`.bin`、`.hpm`、`.zip.hwp7s`、`.fd`、`.der`、`.elf`） | 整机供应商（华为/鲲鹏）发布的固件包，按机型版本号索取，不要跨机型混用 |
| UB 软件包（`UBM-*.rpm`、`UBEngine-*.rpm`、`ubs-*.rpm`、`ubturbo-*.rpm`） | UB 软件发布件，或 `B006/UBE/repodata/` 对应的本地源 |

原仓库曾把 77 个固件以 Git LFS 指针提交，指针里保留了真实 sha256 与大小；如果仍能访问原仓库，
这些对象仍可从其 LFS 端点取回：

```bash
git lfs install
GIT_LFS_SKIP_SMUDGE=1 git clone https://gitcode.com/opengauss/oGRAC-common-tools.git
cd oGRAC-common-tools
git lfs pull --include 'ub_installation_doc/images/包/**'
```

> 该路径在 2026-11-26 的拆分后已从仓库删除，需要在拆分前的提交上取：
>
> ```bash
> git log --oneline -1 -- 'ub_installation_doc/images/包'   # 找到拆分前的最后一个提交
> git checkout <该提交> -- 'ub_installation_doc/images/包'
> ```

## 3. 校验

拿到固件包后，在包根目录执行：

```bash
sha256sum -c firmware.sha256
```

全部输出 `OK` 才算完整。LFS 指针文件的 sha256 取的是指针里记录的 `oid`，即实体文件的真实摘要。

## 4. 已知缺口

- 拆分前 `.gitattributes` 只覆盖了 `*.rpm`、`*.zip` 与 BIOS 目录，`*.swbom`、`*.hpm`、`repodata/*.gz`
  是普通二进制直接入库；拆分后这些文件已不在本仓库，无需再处理。
- 固件包最终发布位置（独立 GitCode 仓库 / Release 附件 / 制品库）尚未确定，确定后请更新本节与
  [`firmware-manifest.md`](firmware-manifest.md) 的说明。
