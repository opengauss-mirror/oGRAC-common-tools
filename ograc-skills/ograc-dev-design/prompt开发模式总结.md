# oGRAC / GBP·UB 开发：Prompt 模式总结

本文整理「设计文档 + 提示词 → 代码」的实际工作方式，材料来自：

对应开发 skill：[`design_driven_dev_SKILL.md`](design_driven_dev_SKILL.md)

---

## 1. 总体流程

```text
设计文档 / 流程图 / 规格 md
        ↓
约束型 Prompt（范围、对照基线、硬性门闩）
        ↓
小步改代码（只动相关路径）
        ↓
对照 ograc_master / 指定 commit 验收
        ↓
命名与错误号对齐（gbp 关键字等）
        ↓
perf / core / 日志验证，再迭代
```

原则：**先定不变式，再写代码；先门闩，再功能；改动尽量小。**

---

## 2. Prompt 分层（常用）

| 层级 | 作用 | 典型说法 |
|------|------|----------|
| 规格层 | 把设计写成可执行约束 | 见 `gbp_eviction_generation.md` 硬性约束 1–4 |
| 对照层 | 以旧树/旧 commit 为基准 | 「参考 ograc_master 的 `dtc_read_page`，结构不变为主」 |
| 门闩层 | UB/GBP 逻辑不得污染普通路径 | 「这些逻辑都要在 UB 打开下才进行」 |
| 修复层 | 先对齐逻辑再改 | 「按照现在逻辑修复一下」 |
| 命名层 | GBP 专用符号可检索 | 「与 gbp 相关的函数全部加上 gbp 关键字」 |
| 排障层 | 先根因/方案，再实现 | 「根因到底是啥」「有什么修改方案」 |
| 性能层 | 热路径少读共享头/少拿锁 | 「热路径优化」「优秀修改，提升性能」 |
| 运维层 | 不擅自碰活集群 | 不重启、不恢复 DSS、不换二进制（除非明确要求） |

---

## 3. 高价值 Prompt 模板

### 3.1 按设计文档实现

```text
按下面设计/规格实现，硬性约束必须遵守：
1) 不影响热页迁移和热页访问正常路径
2) 未刷盘不淘汰，换下一个槽
3) 尽可能小的改动；enable_ubsmem 关闭时走原路径
4) 对照基线：<ograc_master 路径或 commit>
先给方案/关键改动点，确认后再改代码。不要 commit。
```

### 3.2 对照基线合入逻辑

```text
以 /c/zx_workhome/ograc_master 的 <函数> 结构为基准，不要过分修改原函数逻辑；
把当前 cherry-pick / 设计里的 <特性> 加进去。
当 <开关>=false 时，相关代码和统计都不要走到。
```

### 3.3 门闩与回归

```text
刚才改的逻辑都要在 enable_ubsmem（UB）打开下才进行。
普通页（如 analyze table）不要走 GBP/DRC 额外探测。
对照 commit <正常基线> 检查是否引入慢路径。
```

### 3.4 命名与错误号

```text
GBP 淘汰/水位/校验相关函数名加上 gbp 关键字，便于和基线 DCS 路径区分。
复用 ERR_DCS_MSG_EAGAIN 的 GBP 场景改成独立 ERR_GBP_MSG_EAGAIN，并注明场景。
```

### 3.5 排障

```text
先解释根因（为什么指针/状态为空），再给修改方案；
未明确说「改代码」时只出方案。
不要重启集群 / 恢复 DSS / 换二进制。
```

### 3.6 性能

```text
perf 热点在 <符号>。分析是否每次都读远端布局/反复加锁；
给出可落地的小改动（例如按 owner 缓存校验结果），保持语义不变。
```

---

## 4. 设计文档地图（开发时优先读）

| 主题 | 路径 |
|------|------|
| GBP 初始化 / 全局内存 | `多写\灵渠\设计文档\gbp_init\` |
| GBP 锁模式 / fence | `多写\灵渠\设计文档\gbp_lock\` |
| 热冷迁移 | `多写\灵渠\设计文档\gbp_migarate\` |
| 读写并发 / reload | `多写\灵渠\设计文档\gbp_rw_并发\` |
| txn-hot 共享内存 | `多写\灵渠\设计文档\txn_hot\` |
| 淘汰 generation 规格 | `c:\zx_workhome\gbp_eviction_generation.md` |
| 业界对比 | `多写\灵渠\设计文档\业界类比\` |

规格文档里「硬性约束」优先级高于实现细节叙述。

---

## 5. 对话中沉淀的工程约定

1. **UB 门闩**：GBP leftover / DRC barrier / 淘汰 reload 仅在 `enable_ubsmem && cluster`。
2. **基线优先**：普通路径对齐 `ograc_master` 或指定正常 commit（如 analyze 回归对照）。
3. **热页命中**：`shmem_page_meta != NULL` 时尽早返回，不查 DRC。
4. **错误可区分**：DCS ask-master 重试用 `ERR_DCS_MSG_EAGAIN`；GBP 淘汰复用另用 `ERR_GBP_MSG_EAGAIN`。
5. **命名**：GBP 专用 API 带 `gbp`（如 `dcs_gbp_apply_evict_flush_lsn`）。
6. **热路径**：布局校验结果可本地缓存；不要每次读远端 header。
7. **region 已存在**：可复用并打 WAR；**data buffer 已存在** 则拒绝启动。
8. **未要求不 commit / 不碰活库**。

---

## 6. 举证材料索引

| 文件 | 说明 |
|------|------|
| `代码pr连接.txt` | 相关 PR 链接 |
| `代码检视SKILL.md` | GitCode 行级检视 skill |
| `prompt开发模式总结.md` | 本文 |
| `design_driven_dev_SKILL.md` | 设计文档驱动开发 skill |
| `设计文档驱动开发SKILL.md` | 开发 skill 入口索引 |

PR 示例：

- https://gitcode.com/opengauss/oGRAC/pull/485
- https://gitcode.com/opengauss/oGRAC/pull/477
- https://gitcode.com/opengauss/oGRAC/pull/474
- https://gitcode.com/opengauss/oGRAC/pull/460
- https://gitcode.com/opengauss/oGRAC/pull/511
