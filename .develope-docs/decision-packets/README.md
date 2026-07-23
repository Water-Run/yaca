# yaca 成套设计决策包

更新日期：2026-07-22

这里是项目负责人阅读每组完整选项正文（通常 A/B/C，二元题为 A/B）的入口。`QUESTIONS.md` 的 437 个 `AQ-*` 保留作原子追踪；本目录把它们组合成能看见完整产品行为的十个 owner packet、270 组负责人决定。02--10 是九个主包，11 是跨系统补缝包；后续审阅又把隐藏决定、捆绑选择、重复 owner、交叉传播缝隙、产品范围漏项和纯技术投票逐项清理。

现行 `decision-inventory-v9` 分布：`PJ 19 / PP 18 / TU 32 / M05 57 / AL06 49 / TS 35 / CX 16 / ED 14 / RF 14 / F4 16`；384 个 checklist ID、`AQ-001..AQ-437`、`CV-001..CV-076` 与 49 个历史回复批次使用同一现行投影。270 组已经全部收到负责人答复；本目录保留为问题语义、条件和覆盖审计证据，不再是待答问卷。

勘误：冻结包 10 把 luainstaller 当前的 Windows x86 guard 写成了“luainstaller 不支持 x86/XP”。现行证据只能证明默认发布路径会拒绝 x86，且随包 MSVC 配方只覆盖 x64；底层 launcher/bundler 是否能够支持 x86 尚未验证。该问题现在按 `AS-005-01` 作为资格验证和发布证据门处理，不把冻结包中的旧候选措辞当成能力结论。

后续拆出的 composer 输入召回、配置秘密文件权限、raw shell 继承环境、完整 model-yield 后续接、direct 文件属性、ignore/隐藏项、`exec` cwd、输出解码、canonical 保留与 active XML 外改恢复均已由 Batch 06 集中回复并投影到 D-049..D-057。包内旧推荐仍只是提问时的候选证据；现行行为只以 `DECISION-REGISTER.md`、`DECISIONS.md` 和 owner 规格为准。

## 顺序

1. [02 产品旅程与表面地图](02-product-journey-and-surfaces.md)
2. [03 Prompt、人格与工作区指令](03-prompt-personality-and-instructions.md)
3. [04 TUI 视觉、输入与 CLI 体验](04-tui-visual-input-cli-experience.md)
4. [05 Model、配置、网络与 Self-Test](05-model-configuration-network-selftest.md)
5. [06 AgentLoop、忙时动作、DoubleCheck 与压缩](06-agentloop-busy-doublecheck-compaction.md)
6. [07 Tool Calling、安全、进程与运行时](07-tools-safety-process-runtime.md)
7. [08 Context XML、索引与恢复](08-context-xml-index-recovery.md)
8. [09 错误、诊断、关闭与兼容体验](09-errors-diagnostics-compatibility.md)
9. [10 发布、完整测试与架构就绪冻结](10-release-testing-and-readiness-freeze.md)
10. [11 跨系统运行接缝与遗漏收口](11-cross-system-operational-seams.md)

## 回复规则

- 每包按自己的短编号回复，例如 `PJ-01 A`、`PP-03 接受推荐，但……`。
- 以下规则只在负责人明确重开决定或新增产品轴时使用；现行问卷已经关闭。
- 可以回复“本包全部接受推荐，以下除外……”，仍会逐项归档；先应用同批显式上游/例外并重算条件，再作用于答复时锁定 inventory 中 active 的其余组。
- 条件不成立的组记 `not-applicable`，不生成空字段/页面/测试；模板中的条件组字母可以作为 pre-answer 保存，等上游激活后才生效。
- 新增或重开的项目在没有明确回复时保持待决；推荐和示例文案不会自动写入 `DECISIONS.md`。
- 涉及 API、编译器、毫秒和字节常量的纯技术选择，先由原型/benchmark 提供证据；只在它改变产品保证时请负责人取舍。
- 每包确认后，结论要同步到 `DECISIONS.md`、对应子系统权威规格、原子题库和 readiness gate。

逐组当前状态、inventory digest、条件和原话/传播引用统一看 [设计决策实时登记表](../DECISION-REGISTER.md)，不在十个包里散写第二套状态。

实际逐批顺序见 [设计决策分批队列](../DECISION-BATCH-QUEUE.md)；packet 编号只是 owner 文档顺序，不是要求逐包答完的顺序。完整依赖、最高风险矛盾和实施前工件见 [设计决策路线图](../DESIGN-DECISION-ROADMAP.md)。
逐字段配置和跨请求/存储的数据边界分别见 [配置 schema 候选](../CONFIG-SCHEMA-CANDIDATE.md) 与 [数据分类候选](../DATA-CLASSIFICATION-CANDIDATE.md)；两者都只是供各包引用的审阅底稿。
