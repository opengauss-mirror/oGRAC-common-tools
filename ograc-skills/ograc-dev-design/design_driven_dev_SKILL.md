---
name: ograc-design-driven-dev
description: >-
  按设计文档与约束型 Prompt 开发 oGRAC GBP/UB 相关代码。对照 ograc_master 基线、
  enable_ubsmem 门闩、最小改动、gbp 命名与错误号区分。在用户提到设计文档、
  GBP/UB 实现、淘汰 generation、txn-hot、对照基线改代码、或本举证目录时使用。
disable-model-invocation: true
---

# oGRAC 设计文档驱动开发

## 何时使用

- 按 `多写/灵渠/设计文档` 或 `gbp_eviction_generation.md` 落代码
- GBP / UB / txn-hot / 淘汰 / DRC barrier 相关改动
- 要求「对照 ograc_master」「UB 打开才走」「加 gbp 关键字」
- 先方案后实现、排障但不擅自碰活集群

Prompt 习惯总览见同目录：[`prompt开发模式总结.md`](prompt开发模式总结.md)

## 硬性规则

1. **先读规格再改代码**：用户给出设计/规格时，先提炼不变式与门闩，再动源码。
2. **`enable_ubsmem` 门闩**：GBP leftover、DRC barrier、淘汰 reload、store fence 等只在 UB 打开且集群场景生效；关闭时保持基线路径。
3. **最小改动**：在现有 recycle / check / grant / store / ckpt 上加门闩与比对；不重做热页迁移协议；不改无关模块。
4. **不影响热页命中**：`shmem_page_meta != NULL` 的热路径尽早返回；不在命中路径查 DRC / 淘汰分类。
5. **未刷盘不淘汰**：flush ready/recheck 不过就换槽，不 tombstone。
6. **对照基线**：用户点名 `ograc_master` 或某 commit 时，以该结构为主合入新逻辑，禁止顺手重构。
7. **命名**：GBP 专用函数/错误加 `gbp`（如 `dcs_gbp_*`、`buf_gbp_*`、`ERR_GBP_MSG_EAGAIN`）。
8. **未明确要求**：不 commit、不 push、不重启集群、不 DSS restore、不换二进制。
9. **用户要「方案」**：只出方案；用户说「修复/改一下」再改代码。
10. **回复中文**，简洁；代码注释保持仓库既有风格。

## 工作流

```text
进度:
- [ ] 1. 定位设计文档 / 规格段落 / 对照基线
- [ ] 2. 列出不变式、门闩、禁止事项
- [ ] 3. 标出将改的函数与调用链（尽量少）
- [ ] 4. 实现（UB 门闩 + 基线结构）
- [ ] 5. 自检：非 UB、热命中、普通页（analyze）不被拖慢
- [ ] 6. 命名/错误号是否可区分
- [ ] 7. 向用户说明改了什么、为何安全
```

### 1. 读设计

优先路径：

| 主题 | 位置 |
|------|------|
| 淘汰 + generation | `c:/zx_workhome/gbp_eviction_generation.md` |
| 锁 / fence | `c:/zx_workhome/多写/灵渠/设计文档/gbp_lock/` |
| 迁移 | `c:/zx_workhome/多写/灵渠/设计文档/gbp_migarate/` |
| 读写并发 | `c:/zx_workhome/多写/灵渠/设计文档/gbp_rw_并发/` |
| txn-hot | `c:/zx_workhome/多写/灵渠/设计文档/txn_hot/` |
| 代码树 | `c:/zx_workhome/zx_master_ub` |
| 基线树 | `c:/zx_workhome/ograc_master` |

规格中的「硬性约束」优先于叙述性文字。

### 2. 改代码时的检查清单

- [ ] `!enable_ubsmem` 或非集群：行为与改前一致
- [ ] 热页命中不增加 MES/DRC 往返
- [ ] 普通脏页 / analyze：无 GBP leftover 时不走 barrier
- [ ] 淘汰只在槽 X 下改 generation / tombstone
- [ ] DRC `buf_res->lsn` 作写盘下限时，普通 grant 的 `evict_flush_lsn==0` 不进 apply
- [ ] 新错误号在 `cm_error.h` + `g_error_desc` 成对出现
- [ ] GBP 重试点改用新错误号后，ckpt / read_page 识别逻辑同步更新

### 3. 热路径性能（可选优化回合）

当 perf 显示 `hot_header_valid` / 布局校验过重时：

- 布局字段只在 init 写入；热路径按 owner **本地缓存**校验结果
- 命中时只比 `remote_buf_addr` + `txn_hot_offset`，不再读远端 header
- region init / 映射变化时清缓存

当 perf 显示 GBP 锁族过重时：优先减少 lock 次数与持锁区间，再抠校验细节。

### 4. 排障约束

- Core / SIGSEGV：先解释根因（空指针从哪条协议路径来），再方案
- 活库：默认只读日志/core；不重启、不换包，除非用户明示
- SSH 双节点习惯：经 jump、注意 PowerShell CRLF；密码不回显

## Prompt 速查（可原样使用）

```text
# 实现
按规格实现；enable_ubsmem 关闭走原路径；最小改动；先方案后代码。

# 对照基线
以 ograc_master 的 <函数> 结构为主，合入 <特性>；开关关闭时 demotion/统计都不要走到。

# 门闩
相关逻辑仅 UB 打开执行；不要拖慢 analyze/普通页。

# 命名
GBP 相关函数加 gbp；GBP 重试用 ERR_GBP_MSG_EAGAIN 并注释场景。

# 修复
按照现在已选定的逻辑修复；不要改回另一套方案。
```

## 与检视 skill 的关系

合入前行级检视用同目录 [`代码检视SKILL.md`](代码检视SKILL.md)。  
本 skill 管「怎么按设计写出正确小改动」；检视 skill 管「怎么在 GitCode PR 上挂行评」。
