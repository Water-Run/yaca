# 主线就绪差距：从“决定已收口”到“可开发”

更新日期：2026-08-29

状态：运营清单（编码启动断点）；**当前判定：Gate A/B 已通过，可从 C01 开始编码；Release Gate R 关闭**

进度注记：SQ/D-070/D-071 收口。**编码就绪边界已机器化**：16 份 contract、12 组 synthetic fixtures、7,000+ 跨规格断言、28 项 gate audit 与 `M0..M10`/`C01..C34` 实施图已落盘。TP-003/006/008/010 在 2026-08-29 取得范围明确的 `proven-modern` 证据；Gate A/B 已通过。`../luainstaller` 为 1.3.0，旧 x86 guard 阻塞已消失；yaca-specific 三包与真实 XP/Win7/CentOS 证据仍缺，因此 Release Gate R 保持关闭。权威判定见 [`ARCHITECTURE-READINESS.md`](ARCHITECTURE-READINESS.md) 和 [`GATE-AUDIT-2026-08-29.md`](GATE-AUDIT-2026-08-29.md)。本文回答三个实操问题：

1. 现在站在哪一层？
2. 离“可写实施计划 / 可开始编码”还缺什么？
3. 建议按什么顺序补齐（主线，不含 Web 实现）？

Web 双线（D-058：`yaca-web`/Java 8、`yaca-ie6`/PHP 5.4）**不计入** v0.1 主线就绪；见 [`web-tracks/`](web-tracks/README.md)。

---

## 1. “可开发就绪”在本项目的正式含义

项目把“能写代码”拆成两道门，不能混谈：

| 门 | 含义 | 当前 |
| --- | --- | --- |
| **A. 实施计划就绪** | 每个相关子系统已有唯一权威规格；只能实现后/目标机验证的事实已绑定 task、proof plan、失败退路和 hard gate | **通过** |
| **B. 编码就绪** | A 已通过；已有全程序实施计划（文件、依赖、测试、退出、提交边界）；首任务唯一 | **通过** |
| **R. 资格与发布** | 实现完成；Win32/Win64/Linux 独立 target proof、最终 zip 与供应链/旅程证据全部通过 | **关闭** |

流水线（不可跳步）：

```text
负责人选择 ──已完成──► DECISIONS / REGISTER
        │
        ▼
 owner 规格硬化（schema / 状态表 / 矩阵） ──已完成──► 16 contracts / 12 fixtures
        │
        ▼
 技术证明 plan + 关键路径证据 ──已路由──► modern-proven 或 qualification-bound
        │
        ▼
 实施计划就绪 (A) ──PASS──►
        │
        ▼
 全程序实施计划 M0..M10 / C01..C34 ──PASS──►
        │
        ▼
 编码就绪 (B) → C01 串行实现 → target qualification → Release Gate R
```

**D-001 / D-057 明确：问卷答完 ≠ 可编码。**

---

## 2. 进度总览（四层）

| 层 | 完成度（粗估） | 证据 |
| --- | ---: | --- |
| 题库 / 审计覆盖 | ~95% | AQ-001..437、384 checklist、CV-001..076、10 决策包 |
| 负责人产品选择 | **100%** | register `unanswered=0` / `conflict=0`；D-001..D-058 |
| Owner **可编码规格** | **100%（当前计划输入）** | 16 contracts / 12 fixtures；formats/path/wire/Prompt/transport/TUI 边角已闭合 |
| 技术证明 | **关键 modern 候选已过；target 0%** | luainstaller 1.3.0 upstream modern；TP-003/006/008/010 proven-modern；无 proven-target |
| 实施计划 / 源码 | **计划 100% / 源码 0%** | M0..M10、C01..C34 已冻结；`src/*.lua` 仍全空 |
| 发布证据 | **0%** | 无三目标合格 zip |

一句话：**施工图和排程已闭环；下一步从 C01 建测试地基，目标机与发布证据沿 hard gate 补齐。**

---

## 3. P0 计划状态与 qualification hard gate

图例：

- **语义**：产品选择是否够用（大多已够）
- **规格**：是否已有唯一、可执行的权威工件
- **证明**：`proven-modern` 只支持实现候选；`target pending` 仍绑定 milestone/Release hard gate
- **计划状态**：`plan-ready` 可直接实现；`qualification-bound` 可开始实现，但对应目标证据通过前不能完成指定 milestone/发布

| Gate | 主题 | 规格/fixture | 证据阶段 | 计划状态 | Task / hard gate |
| --- | --- | --- | --- | --- | --- |
| AR-P0-01 | 产品闭环 / 零表面 / 发行形态 | machine frozen | 本地 scan；target pending | qualification-bound | C33 / release |
| AR-P0-02 | AgentLoop typed outcome | machine frozen | synthetic pass | plan-ready | C26 / M8 |
| AR-P0-03 | Model 协议 canonical | exact synthetic wire | TP-015 recorded pending | qualification-bound | C21 / M6 |
| AR-P0-04 | 事件泵 / 可取消 I/O | machine frozen | TP-003 modern；target pending | qualification-bound | C04 / target adapters |
| AR-P0-05 | TUI full-duplex / draft | fd+40-column transcripts | target terminal pending | qualification-bound | C14 / M4 |
| AR-P0-06 | 工具 × Permission | machine frozen | fold pass；target pending | qualification-bound | C25 / M7 |
| AR-P0-07 | 改动事务 / 无 undo | unique fault semantics | TP-008 modern；target pending | qualification-bound | C25 / M7 |
| AR-P0-08 | 数据 / secret / import | matrix+carrier frozen | TP-006 modern；target pending | qualification-bound | C19 / M6 |
| AR-P0-09 | typed config | catalog+grammar frozen | synthetic pass；target pending | qualification-bound | C10 / M3 |
| AR-P0-10 | Context durability | RNG+semantic+format frozen | TP-008/010 modern；target pending | qualification-bound | C17 / M5 |
| AR-P0-11 | path/index/lifecycle | SHA-256/path vectors frozen | local oracle pass；target pending | qualification-bound | C16 / M5 |
| AR-P0-12 | compact model view | unique design | implementation benchmark scheduled | plan-ready | C28 / M8 |
| AR-P0-13 | CLI/action state | parser+machine+fd frozen | synthetic pass；target pending | qualification-bound | C12/C14 / M4 |
| AR-P0-14 | safe load / ambient | current/planned/native allowlists | TP-029 target pending | qualification-bound | C04/C31 / M10 |
| AR-P0-15 | local ID / locks / crash | machine frozen | TP-008 modern；target pending | qualification-bound | C17 / M5 |
| AR-P0-16 | release feasibility | pins+package plan frozen | upstream modern；three targets pending | qualification-bound | C32 / release |

P1 门（AR-P1-01..12）也已逐项路由为 `plan-ready` / `qualification-bound`；完整表见 Gate Audit，machine truth 在 `contracts/readiness.lua`。

---

## 4. 技术证明债务（主线关键路径）

完整列表见 [`TECHNICAL-PROOF-BACKLOG.md`](TECHNICAL-PROOF-BACKLOG.md)。进入编码前，至少要把下列 TP 提升到 **`specified`（可复现步骤 + 通过条件 + 失败退路）**；标 ★ 的最好在写主路径实现前有 modern 或目标机结果。

| ID | 主题 | 与 P0 关系 | 最低就绪要求 |
| --- | --- | --- | --- |
| TP-003 ★ | 统一事件泵 | P0-04 | `proven-modern` fake core；XP/CentOS 计划保留 |
| TP-004 ★ | XP console / QuickEdit | P0-05 | 按键矩阵 + 后备策略证据 |
| TP-005 | 子进程取消 / unknown | P0-06、P1-03 | kill-tree / 管道计划 |
| TP-006 ★ | curl 流式 / 密钥 | P0-03、P1-02 | `proven-modern` carrier/cancel/scanner；目标计划保留 |
| TP-007 | TLS / CA / HTTP | P0-03 | 旧平台 TLS 基线 |
| TP-008 ★ | 单 XML 正确性 | P0-10 | `proven-modern` POSIX 崩溃矩阵；目标计划保留 |
| TP-009 ★ | 单 XML 写放大 | P0-10 | hard limit 数字来源 |
| TP-010 ★ | LuaExpat + Lua 5.5 | P0-10、P1-01 | `proven-modern` Linux build/corpus；三架构计划保留 |
| TP-001 | luainstaller Win32 | P0-16 | 1.3.0 upstream modern 已有；执行 yaca-specific qualification |
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
| 00 | 产品契约 | 高 | 机读旅程/零表面已齐；公开文档与最终包同步 |
| 01 | 平台抽象 | 高 | 机读窄端口/加载/identity 已齐；能力探测 proof |
| 02 | 进程资源 | 高 | transport contract 已齐；C04/C25 target cancel/pipe hard gate |
| 03 | 网络 | 高 | carrier/retry/redirect/ambient 已机读；C19 target qualification |
| 04 | 数据格式 | 高 | strict UTF-8/JSON/SSE/XML/INI 与 pins/fixtures 已齐 |
| 05 | 配置 | 高 | 机读正式 catalog/grammar/migration 已齐；数字/原子写 proof |
| 06 | 模型协议 | 高 | canonical + exact synthetic wire 已齐；C21/TP-015 recorded fixture |
| 07 | 工具 | 中 | tool registry 全表 |
| 08 | 权限 | 中 | 矩阵机械求值表 |
| 09 | AgentLoop | 高 | 机读状态/outcome/trace 已齐；fault/hard-cap proof |
| 10 | Context 存储 | 高 | RNG + semantic schema 已齐；提交原语/性能 proof |
| 11 | 索引 | 高 | path/hash/selector vectors 已齐；target filesystem/cap 待校准 |
| 12 | 压缩 | 中 | view schema |
| 13 | CLI | 高 | 39 action 机读 registry 已齐；parser/help/output 实现 |
| 14 | TUI | 高 | fd、draft、ASCII chrome/transcript 已齐；target terminal proof 待做 |
| 15 | 诊断 | 高 | error/exit/check registry 已齐；脱敏/output fixture |
| 16 | 发布 | 高（计划） | pins/allowlist/M10 已齐；三目标 qualification 未执行 |
| 17 | Web | 排除+预留 | **不阻塞主线** |
| 18 | Prompt | 高 | 七 purpose 原文/层序/native control schemas 已齐 |
| 19 | 改动事务 | 中 | fault 矩阵 |
| 20 | 测试 | 高（计划） | test tree、C01 harness、每 task test boundary 已冻结 |
| 21 | 扩展 | 关闭 | 零表面扫描清单 |
| 22 | 运行时 | 中 | 与 01/02/03/09 的组合契约 |

**全程序已处于「计划已确认」，产品实现仍为 0%；每个子系统只有完成对应 C task 和 hard gate 后才进入「已验证」。**

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

目标已完成：Wave 0–5 已使 **Gate A/B 通过**；后续按实施计划推进 C01--C34，并在 milestone hard gate 收集 target evidence。

### Wave 0 — 基线对齐（1 个短迭代）

1. 冻结「规格完成定义」检查表（对照本文 §8）。
2. 将 `_CONFIG_.ini` 标为 **historical draft / non-normative**（或改名/加头注释），避免被当成契约。
3. 维护本文件与 `TRACKING.md` 的进度勾选。

### Wave 1 — 三条脊柱规格（最高杠杆，先做）

不做这三条，其它规格会反复返工：

| 工作包 | 产出 | 关闭的门 |
| --- | --- | --- |
| **W1-A AgentLoop** | 状态枚举、转换表、terminal outcome、turn/request/attempt、busy 意图、DoubleCheck 插入点、golden trace | P0-02 规格侧 — **2026-08-29 机读冻结** |
| **W1-B Config schema** | 逐字段 catalog、grammar、默认/未知字段、secret、ConfigGeneration、XML 白名单/migration | P0-09 规格侧 — **2026-08-29 机读冻结** |
| **W1-C Context XML** | RNG + event payload schema、提交状态机、崩溃表、metadata、导入边界 | P0-10 规格侧 — **2026-08-29 机读冻结** |

### Wave 2 — 交互与工具脊柱

| 工作包 | 产出 | 门 |
| --- | --- | --- |
| **W2-A Action registry** | 39 action + args/state/confirm/result + argv fixtures | P0-13 — **机读冻结** |
| **W2-B Tool×Permission** | 8 工具 + 5 capability + fold fixtures | P0-06 — **机读冻结** |
| **W2-C Model events** | canonical request/event/response/control + synthetic fixtures | P0-03 — **机读冻结；recorded wire 待 proof** |

### Wave 3 — 平台与安全规格 + proof plan

| 工作包 | 产出 | 门 / TP |
| --- | --- | --- |
| **W3-A Runtime ports** | **规格侧冻结** → 01/02/03/22 + platform machine contract | P0-04/P0-14/P0-15 规格侧；证明仍缺 |
| **W3-B Path/Index** | **首版完成** → 11 + D-070 display≠hash | P0-11 规格侧 |
| **W3-C Data/secret matrix** | **首版完成** → `DATA-CLASSIFICATION.md` | P0-08 规格侧 |
| **W3-D Change/compaction** | **首版完成** → 19 + 12 | P0-07、P0-12 规格侧 |

### Wave 4 — 产品闭环与文档诚实

| 工作包 | 产出 | 门 |
| --- | --- | --- |
| **W4-A Journey + zero-surface** | 用户旅程矩阵；排除能力负向清单（配置/CLI/XML/zip） | P0-01 — **机读冻结；最终 zip 待 proof** |
| **W4-B Error/self-test registry** | 稳定 error ID、self-test check ID | P1-07 — **机读冻结** |
| **W4-C README sync** | 中英文 README 仅声明设计/未实现边界并与 registry 对齐 | P1-12 — **2026-08-29 完成** |

### Wave 5 — 实施计划就绪判定（2026-08-29 完成）

Wave 1–4 规格工件已齐；TP-003/006/008/010 已 `proven-modern`，P0-05 的 exact synthetic transcript 与 TP-004 target plan 已绑定 C14：

1. `ARCHITECTURE-READINESS.md` 已把计划门与 qualification/release 门分开。
2. `IMPLEMENTATION-PLAN.md` 已冻结文件树、C01--C34、测试、退出和提交边界。
3. Gate A/B 已通过；按 D-002 从 C01 串行编码。Gate R 仍需三目标证据。

### 已确认实现顺序（由 C01--C34 展开）

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
| 现在能不能写产品代码？ | **能**；Gate A/B 已过，从 C01 开始 |
| 缺的是负责人选择题吗？ | **不是** |
| 接下来缺什么？ | **产品实现 C01--C34；各 milestone target proof；最终三包 qualification** |
| 最短路径？ | **C01 harness/manifest → C02 platform identity → C03 event pump → 按 M0..M10 串行推进** |

**下一批编码执行单：**

1. C01：测试 harness、release manifest、loader negative tests；独立提交并推送 M0。
2. C02：pure platform identity + fake-native dependency；不提前做真实 I/O。
3. C03：先把 TP-003 oracle 转为产品单测，再实现 deterministic event pump。

核心里程碑按 D-071 提交并推送 `main`；目标平台 release qualification 仍作为不可绕过的 Gate R。
