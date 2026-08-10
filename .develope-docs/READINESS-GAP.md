# 主线就绪差距：从“决定已收口”到“可开发”

更新日期：2026-08-10

状态：运营清单（设计阶段）；**当前判定：未达实施计划就绪，未达编码就绪**

进度注记：SQ 完成；D-070 收口。**W1–W2 首版 + Wave 3 四包首版齐**（见 HANDOFF）。Owner 规格粗估升至 ~35–40%；P0 门仍未 passed；**未** 达门 A/B；不写产品代码。权威门禁仍以 [`ARCHITECTURE-READINESS.md`](ARCHITECTURE-READINESS.md) 为准。本文回答三个实操问题：

1. 现在站在哪一层？
2. 离“可写实施计划 / 可开始编码”还缺什么？
3. 建议按什么顺序补齐（主线，不含 Web 实现）？

Web 双线（D-058：`yaca-web`/Java 8、`yaca-ie6`/PHP 5.4）**不计入** v0.1 主线就绪；见 [`web-tracks/`](web-tracks/README.md)。

---

## 1. “可开发就绪”在本项目的正式含义

项目把“能写代码”拆成两道门，不能混谈：

| 门 | 含义 | 当前 |
| --- | --- | --- |
| **A. 实施计划就绪** | 每个相关子系统已有**唯一权威规格**（无 A/B 任选）；P0 规格工件齐全；P0 技术证明至少有 **可执行 proof plan**（关键路径最好已有目标机或可复现原型结果） | **未通过** |
| **B. 编码就绪** | A 已通过；已有**全程序实施计划**（文件、顺序、测试、提交边界）；计划项不再写“视情况选择” | **未通过** |

流水线（不可跳步）：

```text
负责人选择 ──已完成──► DECISIONS / REGISTER
        │
        ▼
 owner 规格硬化（schema / 状态表 / 矩阵） ──缺口──► 尚未完成
        │
        ▼
 技术证明 plan + 关键路径证据 ──缺口──► 大多 unplanned
        │
        ▼
 实施计划就绪 (A)
        │
        ▼
 全程序实施计划 ──不存在──►
        │
        ▼
 编码就绪 (B) → 按子系统串行实现
```

**D-001 / D-057 明确：问卷答完 ≠ 可编码。**

---

## 2. 进度总览（四层）

| 层 | 完成度（粗估） | 证据 |
| --- | ---: | --- |
| 题库 / 审计覆盖 | ~95% | AQ-001..437、384 checklist、CV-001..076、10 决策包 |
| 负责人产品选择 | **100%** | register `unanswered=0` / `conflict=0`；D-001..D-058 |
| Owner **可编码规格** | **~35–40%** | W1–W3 首版合同表已落；多数子系统仍非「设计已确认→计划已确认」 |
| 技术证明 | **~0–5%** | 关键 TP 仅 `specified`；无 proven-target |
| 实施计划 / 源码 | **0%** | 无实施计划；`src/*.lua` 全空 |
| 发布证据 | **0%** | 无三目标合格 zip |

一句话：**方向和边界已经画死；施工图和试桩还没齐。**

---

## 3. P0 门禁差距表（进入实施计划前必须处理）

图例：

- **语义**：产品选择是否够用（大多已够）
- **规格**：是否已有唯一、可执行的权威工件
- **证明**：是否有 proof plan / 目标证据
- **阻塞度**：H = 不做则几乎无法安全开写任何主路径；M = 阻塞完整计划；L = 可与邻近项并行收口

| Gate | 主题 | 语义 | 规格 | 证明 | 阻塞度 | 缺失的权威工件（摘要） |
| --- | --- | --- | --- | --- | --- | --- |
| AR-P0-01 | 产品闭环 / 零表面 / 发行形态 | 有 | 缺 | 缺 | M | 旅程矩阵、zero-surface manifest、安装→升级→卸载状态表；README 与模板对齐 |
| AR-P0-02 | AgentLoop typed outcome | 有 | **首版**（W1-A） | 缺 | **H** | golden trace / 完整因果仍待加深 |
| AR-P0-03 | Model 协议 canonical | 有 | **首版**（W2-C） | 缺 | **H** | 双 adapter 录制 fixture 仍缺 |
| AR-P0-04 | 事件泵 / 可取消 I/O | 有 | **首版**（W3-A 22/02/03） | **缺** | **H** | XP/CentOS 证明未做 |
| AR-P0-05 | TUI full-duplex / draft | 有 | 缺 | **缺** | H | 输入状态机、fd 能力矩阵、快捷键→文本后备、ASCII golden transcript |
| AR-P0-06 | 工具 × Permission 矩阵 | 有 | **首版**（W2-B） | 缺 | **H** | 机读求值/fixture 仍待 |
| AR-P0-07 | 改动事务 / 无 undo | 有 | **首版**（W3-D 19） | 缺 | M | 目标机 fault 注入证据 |
| AR-P0-08 | 数据分类 / 秘密 / 导入 | 有 | **首版**（W3-C） | 缺 | H | canary/exact-scan TP |
| AR-P0-09 | 配置 typed schema | 有 | **首版**（W1-B） | 缺 | **H** | INI grammar/原子写；替换过时 `_CONFIG_.ini` |
| AR-P0-10 | Context XML durability | 有 | **首版**（W1-C） | **缺** | **H** | 崩溃真值表目标机证据 |
| AR-P0-11 | 路径 / 索引 / 生命周期 | 有 | **首版**（W3-B） | 缺 | H | golden path vectors / 密码学原语锁定 |
| AR-P0-12 | 压缩 model view | 有 | **首版**（W3-D 12） | 缺 | M | token 估算阈值 TP |
| AR-P0-13 | CLI/点命令 × 状态 | 有 | **首版**（W2-A） | 缺 | **H** | golden argv / 机读 schema |
| AR-P0-14 | 安全加载 / ambient | 方向 | 缺 | 缺 | H | module allowlist、DLL 搜索、curl/shell ambient isolation |
| AR-P0-15 | 本地 ID / 锁 / 崩溃 | 有 | 缺 | 缺 | H | identity 表、lease、stale lock 协议 |
| AR-P0-16 | 发布可行性 | 有 | 缺 | **阻塞** | **H*** | luainstaller x86/x64 qualification；三 zip 证据（*编码前可后置到发布阶段，但实施计划必须写清 qualification 任务与失败退路） |

P1 门（AR-P1-01..12）在写**全程序**计划前也应关闭；若只做**局部子系统**垂直切片，至少关闭该子系统及其上游 P1。

---

## 4. 技术证明债务（主线关键路径）

完整列表见 [`TECHNICAL-PROOF-BACKLOG.md`](TECHNICAL-PROOF-BACKLOG.md)。进入编码前，至少要把下列 TP 提升到 **`specified`（可复现步骤 + 通过条件 + 失败退路）**；标 ★ 的最好在写主路径实现前有 modern 或目标机结果。

| ID | 主题 | 与 P0 关系 | 最低就绪要求 |
| --- | --- | --- | --- |
| TP-003 ★ | 统一事件泵 | P0-04 | ABI + XP/CentOS 计划 |
| TP-004 ★ | XP console / QuickEdit | P0-05 | 按键矩阵 + 后备策略证据 |
| TP-005 | 子进程取消 / unknown | P0-06、P1-03 | kill-tree / 管道计划 |
| TP-006 ★ | curl 流式 / 密钥 | P0-03、P1-02 | carrier + 取消 + 无 argv 泄漏 |
| TP-007 | TLS / CA / HTTP | P0-03 | 旧平台 TLS 基线 |
| TP-008 ★ | 单 XML 正确性 | P0-10 | 崩溃切点真值表 |
| TP-009 ★ | 单 XML 写放大 | P0-10 | hard limit 数字来源 |
| TP-010 ★ | LuaExpat + Lua 5.5 | P0-10、P1-01 | 三架构构建计划 |
| TP-001 | luainstaller Win32 | P0-16 | qualification 计划（可后置实施，不可忽略） |
| TP-015/016/017 | 协议 / control / outcome | P0-02、P0-03 | fixture 语料 |
| TP-019 | INI 往返 | P0-09 | parser contract |
| TP-024 | CLI grammar | P0-13 | golden argv |
| TP-029/030 | 加载路径 / 干净机 zip | P0-14、P0-16 | 发布阶段硬门 |

**原则：** 原型是“可丢弃验证”，不是产品半成品；失败且会改用户保证时，只重开最小产品差异（D-057）。

---

## 5. 子系统规格状态（主线）

相对 [`TRACKING.md`](TRACKING.md) 与各文件“状态：”行：

| 编号 | 子系统 | 产品语义 | 精确规格缺口（典型） |
| ---: | --- | --- | --- |
| 00 | 产品契约 | 高 | 旅程矩阵、零表面 manifest、文档同步 |
| 01 | 平台抽象 | 中高 | 窄端口 ABI、能力探测表 |
| 02 | 进程资源 | 中 | 取消/管道/unknown 契约数值 |
| 03 | 网络 | 中 | curl carrier、retry 展开、ambient isolation |
| 04 | 数据格式 | 中 | 选定 parser 版本证据、安全子集 |
| 05 | 配置 | 中 | **逐字段正式 catalog**（替代草案 ini） |
| 06 | 模型协议 | 中 | wire schema + fixture |
| 07 | 工具 | 中 | tool registry 全表 |
| 08 | 权限 | 中 | 矩阵机械求值表 |
| 09 | AgentLoop | 中高 | **完整状态/outcome 表** |
| 10 | Context 存储 | 中 | **XML schema + 提交状态机** |
| 11 | 索引 | 中高 | path codec、碰撞展示、性能 cap |
| 12 | 压缩 | 中 | view schema |
| 13 | CLI | 中 | action×state、短参无冲突表 |
| 14 | TUI | 中 | 页面 chrome、输入状态机 |
| 15 | 诊断 | 中 | error/check ID registry |
| 16 | 发布 | 中 | 装配 recipe、qualification |
| 17 | Web | 排除+预留 | **不阻塞主线** |
| 18 | Prompt | 中 | 内置英文 Prompt 原文、大小上限 |
| 19 | 改动事务 | 中 | fault 矩阵 |
| 20 | 测试 | 方向 | 测试金字塔与 golden 目录约定 |
| 21 | 扩展 | 关闭 | 零表面扫描清单 |
| 22 | 运行时 | 中 | 与 01/02/03/09 的组合契约 |

**没有任何子系统处于「计划已确认」；也几乎没有「设计已确认」可单独开工。**

---

## 6. 与仓库草稿的漂移（实现时陷阱）

必须在规格硬化时主动消解，避免编码抄错：

| 草稿 | 问题 | 应以何为准 |
| --- | --- | --- |
| `src/_CONFIG_.ini` | Cautious Permission、旧 Allow* 字段、TrustMeBro、旧 Style 名 | D-049..052、CONFIG-SCHEMA-CANDIDATE → **新正式 schema** |
| `src/*.lua` 空模块名 | 未体现 platform 窄端口、process/network 分模块 | D-013/014；实施计划再定文件表 |
| 旧 README 命令 | 曾含冲突短参 | D-054 action registry |
| `bin/` | 32-bit/x32 候选，不可整包发布 | D-056 最小 allowlist + 目标机构建 |
| `web/` | 仅预留 | D-044/D-058；核心零表面 |

---

## 7. 建议补齐顺序（主线工作包）

目标：用最少路径达到 **门 A（实施计划就绪）**，再写实施计划进入门 B。

### Wave 0 — 基线对齐（1 个短迭代）

1. 冻结「规格完成定义」检查表（对照本文 §8）。
2. 将 `_CONFIG_.ini` 标为 **historical draft / non-normative**（或改名/加头注释），避免被当成契约。
3. 维护本文件与 `TRACKING.md` 的进度勾选。

### Wave 1 — 三条脊柱规格（最高杠杆，先做）

不做这三条，其它规格会反复返工：

| 工作包 | 产出 | 关闭的门 |
| --- | --- | --- |
| **W1-A AgentLoop** | 状态枚举、转换表、terminal outcome、turn/request/attempt、busy 意图、DoubleCheck 插入点、golden trace 目录约定 | P0-02 规格侧 — **首版已写入 09-agent-session（2026-08-10）** |
| **W1-B Config schema** | 逐字段 catalog、类型/默认/未知字段、secret 规则、ConfigGeneration、与 XML 覆盖白名单；从 CONFIG-SCHEMA-CANDIDATE **收口** 而非继续分叉 | P0-09 规格侧 — **首版已写入 05-configuration（2026-08-10）** |
| **W1-C Context XML** | 元素/事件 schema、提交状态机、崩溃真值表、AutoRenameDisabled、导入信任边界 | P0-10 规格侧 — **首版已写入 10-context-storage（2026-08-10）** |

### Wave 2 — 交互与工具脊柱

| 工作包 | 产出 | 门 |
| --- | --- | --- |
| **W2-A Action registry** | ACTION-REGISTRY.md | P0-13 — **首版** |
| **W2-B Tool×Permission** | TOOL-PERMISSION-MATRIX.md | P0-06 — **首版** |
| **W2-C Model events** | MODEL-EVENT-SCHEMA.md | P0-03 — **首版** |
| **W2-B Tool×Permission** | 8 工具 registry + capability 矩阵 + approval 快照 + raw shell 宽边界声明 | P0-06 |
| **W2-C Model adapters** | 双协议 ModelEvent schema + 录制 fixture 清单 | P0-03 |

### Wave 3 — 平台与安全规格 + proof plan

| 工作包 | 产出 | 门 / TP |
| --- | --- | --- |
| **W3-A Runtime ports** | **首版完成** → 01/02/03/22 | P0-04 规格侧；证明仍缺 |
| **W3-B Path/Index** | **首版完成** → 11 + D-070 display≠hash | P0-11 规格侧 |
| **W3-C Data/secret matrix** | **首版完成** → `DATA-CLASSIFICATION.md` | P0-08 规格侧 |
| **W3-D Change/compaction** | **首版完成** → 19 + 12 | P0-07、P0-12 规格侧 |

### Wave 4 — 产品闭环与文档诚实

| 工作包 | 产出 | 门 |
| --- | --- | --- |
| **W4-A Journey + zero-surface** | 用户旅程矩阵；排除能力负向清单（配置/CLI/XML/zip） | P0-01 |
| **W4-B Error/self-test registry** | 稳定 error ID、self-test check ID | P1-07 |
| **W4-C README sync** | 中英文 README 仅声明设计/未实现边界（已部分完成，需与 registry 再对齐） | P1-12 |

### Wave 5 — 实施计划就绪判定

当 Wave 1–4 的规格工件齐备，且 **TP-003/006/008/010（及 P0-05 相关的 TP-004）至少 `specified`** 时：

1. 更新 `ARCHITECTURE-READINESS.md` 各门状态（规格侧 / 证明侧分开勾）。
2. 写 **全程序实施计划**（文件树、子系统顺序、测试目录、提交边界、发布 qualification 并行轨）。
3. 通过门 A → 门 B → 才允许按 D-002 串行编码。

### 编码启动后的推荐实现顺序（仅供计划引用，现在不执行）

```text
平台窄端口 + 事件泵骨架
  → ini/json/xml 安全子集
  → 配置 schema + bootstrap REPL
  → CLI/TUI action registry 空转
  → Context 存储 + Resolver
  → curl + Model adapter
  → 工具 + Permission
  → AgentLoop 接满
  → 压缩 / 诊断 / self-test
  → 打包 qualification
```

---

## 8. 规格“完成”检查表（每个子系统）

一项规格只有在下列项为 **是** 时，才可从「讨论中」标为「设计已确认」：

- [ ] 无“方案 A/B 任选”残留（被否决分支已删除或标明历史）
- [ ] 输入/输出/不变量/durable 点写清
- [ ] 正常 / 取消 / 失败 / 恢复四类路径都有唯一结果
- [ ] 配置字段、CLI/TUI action、XML 元素、error ID 可追溯到本规格
- [ ] 资源上限与旧平台降级有写明（数字可标 provisional，但必须有来源 TP）
- [ ] 验收 fixture 目录与命名约定已写
- [ ] 与上下游规格的交叉引用无冲突
- [ ] 对应 AR-P0/P1 与 TP 的链接已更新

---

## 9. 刻意不纳入主线就绪的内容

| 项 | 原因 |
| --- | --- |
| `yaca-web` / `yaca-ie6` 实现 | D-058 预留；不阻塞 v0.1 |
| MCP / 插件 / 子 Agent | D-038 关闭 |
| 通用 undo / WAL | D-052/D-053 否决或仅允许证明失败后最小重开 |
| 最终三平台完整测试证据 | 属发布硬门；实施计划必须排期，但 **Wave 1–3 规格** 可先完成 |
| 金额/计费 | D-051 明确 v0.1 不算钱 |

---

## 10. 当前结论与下一步建议

| 问题 | 答案 |
| --- | --- |
| 现在能不能写产品代码？ | **不能**（门 A/B 均未过） |
| 缺的是负责人选择题吗？ | **不是** |
| 缺的是什么？ | **(1) 可执行 owner 规格 (2) proof plan/关键证据 (3) 实施计划** |
| 最短路径？ | **Wave 1：AgentLoop + Config schema + Context XML** 三件套并行硬化 |

**建议的下一次具体工作（请负责人选一条开刀）：**

1. **W1-A** 起草 `09-agent-session` 的完整状态/outcome 表（从 D-051 机械展开）  
2. **W1-B** 把 `CONFIG-SCHEMA-CANDIDATE` 收成「现行唯一 schema」并废弃草案 ini  
3. **W1-C** 起草 Context XML 元素与提交/崩溃真值表  

选中后，把对应子系统文档从“候选叙述”改成“唯一权威规格”，并回写本文件与 `ARCHITECTURE-READINESS` 的勾选状态。
