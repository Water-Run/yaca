# yaca 成套设计决策包

更新日期：2026-07-22

这里是项目负责人阅读每组完整选项正文（通常 A/B/C，二元题为 A/B）的入口。`QUESTIONS.md` 的 437 个 `AQ-*` 保留作原子追踪；本目录把它们组合成能看见完整产品行为的十个 owner packet、270 组负责人决定。02--10 是九个主包，11 是跨系统补缝包；后续审阅又把隐藏决定、捆绑选择、重复 owner、交叉传播缝隙、产品范围漏项和纯技术投票逐项清理。

现行 `decision-inventory-v9` 分布：`PJ 19 / PP 18 / TU 32 / M05 57 / AL06 49 / TS 35 / CX 16 / ED 14 / RF 14 / F4 16`；384 个 checklist ID、`AQ-001..AQ-437`、`CV-001..CV-076` 与 49 个回复批次使用同一现行投影。

本轮独立拆出的 composer 输入召回、配置秘密文件权限、raw shell 继承环境、完整 model-yield 后续接、direct 文件属性、ignore/隐藏项、`exec` cwd、输出解码与 canonical 保留、active XML 外改恢复仍全部处于待决状态。产品旅程包的单 workspace root 与自动命名标记优先级已经收口：root 来自 `CONTEXT` 镜像父目录，`AutoRenameDisabled` 是 Context XML metadata；后续增量回复又选择 `TU-32=A` 的平坦 `.model` picker/direct root 与 `F4-01 custom` 的逐顶层 turn 自动配置 generation，并确认无启动头 master、Context 列表排序、self-test 与活动锁不变量。这些都不替代其余包内选择；TU-33/TU-34、M05-56、AL06-49 仍分别拥有输入提示符、审批动作 grammar、SensitiveRead 字段存在性和 termination-review Model 来源，包内推荐不等于项目负责人选择。

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
- 默认按分批队列每次只讨论 3--6 个紧密相关组；当前批次只看实时登记表。负责人可以主动多答或整包回答。
- 可以回复“本包全部接受推荐，以下除外……”，仍会逐项归档；先应用同批显式上游/例外并重算条件，再作用于答复时锁定 inventory 中 active 的其余组。
- 条件不成立的组记 `not-applicable`，不生成空字段/页面/测试；模板中的条件组字母可以作为 pre-answer 保存，等上游激活后才生效。
- 没有明确回复的项目继续待决；推荐和示例文案不会自动写入 `DECISIONS.md`。
- 涉及 API、编译器、毫秒和字节常量的纯技术选择，先由原型/benchmark 提供证据；只在它改变产品保证时请负责人取舍。
- 每包确认后，结论要同步到 `DECISIONS.md`、对应子系统权威规格、原子题库和 readiness gate。

逐组当前状态、inventory digest、条件和原话/传播引用统一看 [设计决策实时登记表](../DECISION-REGISTER.md)，不在十个包里散写第二套状态。

实际逐批顺序见 [设计决策分批队列](../DECISION-BATCH-QUEUE.md)；packet 编号只是 owner 文档顺序，不是要求逐包答完的顺序。完整依赖、最高风险矛盾和实施前工件见 [设计决策路线图](../DESIGN-DECISION-ROADMAP.md)。
逐字段配置和跨请求/存储的数据边界分别见 [配置 schema 候选](../CONFIG-SCHEMA-CANDIDATE.md) 与 [数据分类候选](../DATA-CLASSIFICATION-CANDIDATE.md)；两者都只是供各包引用的审阅底稿。
