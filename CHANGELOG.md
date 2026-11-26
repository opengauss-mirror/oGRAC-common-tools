# 变更记录

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [Unreleased]

### Added

- 仓库治理框架：根 `README.md` 改为目录索引，新增 `CONTRIBUTING.md`、`CHANGELOG.md`、`.gitignore`。
- `ci/check_repo.sh`、`ci/check_links.py`：本地质量门禁（shell/Python 语法、README 索引、明文密钥与内网地址；`--strict` 额外检查 skill 目录规范、断链、LFS 指针、可执行位）。
- `docs/migration-map.md`：目录迁移与整改清单，含责任人与验收标准。
- 目录骨架：`skills/`、`tools/`、`vendor/`、`docs/`。
- `common-scripts/README.md`：补齐此前无文档的 `ograc_sim_single.sh` 与 `install-two-node.sh` 说明。
- `vendor/benchmarksql_ograc/BUILD.md`：构建与运行指南；`lib/README.md` 列出依赖 jar 的来源。
- `vendor/benchmarksql_ograc/UPSTREAM.md`：上游基线、本分支改动、已删除文件清单。
- `docs/ub-installation/firmware-manifest.md`：固件清单（111 个文件、sha256、真实大小）。
- `docs/ub-installation/firmware-README.md`：固件获取与校验说明。

### Changed

- `benchmarksql_ograc/` → `vendor/benchmarksql_ograc/`，只保留源码。
- `ub_installation_doc/` 的两份文档与截图 → `docs/ub-installation/`，改为 LF 换行。
- `.gitattributes` 精简为文本规范化规则；固件 LFS 规则随文件移出而失效，已删除。
- 根 README 增加「已迁出内容」小节，说明安全 skill 与固件包的新位置。

### Removed

- `benchmarksql_ograc/build/`、`dist/`、`src/client.zip`、`src/client/jTPCC.java.bak`。
- `lib/` 下 9 个 jar/tar.gz，含误命名的 `opengauss-jdbc-7.0.0-RC7.jar_2uweiwue`。
- `security-developing-skills/`：拆为独立仓库 `openGauss-security-skills`。
- `ub_installation_doc/images/包/`：111 个固件与软件包（约 231 MiB）拆为独立包 `oGRAC-firmware-packages`。

### Security

- `vendor/benchmarksql_ograc/run/ograc_run.og`、`run/props.sharding` 中的真实内网地址与明文口令替换为占位符。历史提交中仍可见，**口令需轮换**，见 `UPSTREAM.md`。
- `ci/check_repo.sh` 新增两类检查：`password=` 后接字面量、`jdbc://` 后接 IPv4 字面量。

## 2026-11-23

### Added

- `ograc-skills/ograc-dev-design`：设计文档驱动开发、Prompt 模式总结。
