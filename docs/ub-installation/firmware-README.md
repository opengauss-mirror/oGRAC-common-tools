# 固件包获取与校验

本仓库只保留文档，**固件、BIOS、BMC、CPLD、UB 软件包等二进制不在仓库内**。

## 1. 需要哪些文件

完整清单（111 个文件，约 232 MiB）与每个文件的 SHA-256 见
[`firmware-manifest.md`](firmware-manifest.md)。固件升级顺序见
[`安装UB流程.md`](安装UB流程.md) 第二章。

## 2. 从哪里拿

| 文件类型 | 来源 |
|---|---|
| 整机固件（`.bin`、`.hpm`、`.zip.hwp7s`、`.fd`、`.der`、`.elf`） | 整机供应商（华为/鲲鹏）发布的固件包，按机型版本号索取，不要跨机型混用 |
| UB 软件包（`UBM-*.rpm`、`UBEngine-*.rpm`、`ubs-*.rpm`、`ubturbo-*.rpm`） | UB 软件发布件，或 `B006/UBE/repodata/` 对应的本地源 |

### 从原仓库取回（2026-11-26 已完成一次）

拆分前有 77 个固件以 Git LFS 指针提交，指针里保留了真实 sha256 与大小。这些对象现在已全部取回并通过校验；
需要重新取回时，用 Git LFS 批量接口按 `oid` + `size` 下载即可（随包附带的 `fetch_lfs.py` 就是干这个的，
只依赖 Python 3 标准库，公开仓库无需凭据）：

```bash
# 在固件包根目录执行，会把 77 个指针替换为实体并逐个校验 sha256
python3 fetch_lfs.py
```

或走 git-lfs 在拆分前的提交上取：

```bash
git log --oneline -1 -- 'ub_installation_doc/images/包'   # 找到拆分前的最后一个提交
git checkout <该提交> -- 'ub_installation_doc/images/包'
git lfs pull --include 'ub_installation_doc/images/包/**'
```

## 3. 校验

在固件包根目录执行：

```bash
sha256sum -c firmware.sha256
```

全部输出 `OK` 才算完整。2026-11-26 实测：111 个文件全部 OK。

## 4. 发布位置

固件包的最终存放位置（独立仓库 / Release 附件 / 制品库）尚未确定；确定后更新本节与
[`firmware-manifest.md`](firmware-manifest.md) 的说明。当前实物与 `firmware.sha256`、`fetch_lfs.py` 放在同一目录。
