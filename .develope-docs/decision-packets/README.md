# yaca 成套设计决策包

更新日期：2026-07-18

这里是项目负责人主要阅读和回复的设计入口。`QUESTIONS.md` 的 373 个 `AQ-*` 保留作原子追踪；本目录把它们组合成能看见完整产品行为的十个包、187 组负责人决定。02--10 是九个主包，11 是第四轮反向审阅后形成的跨系统补缝包；第五轮又把隐藏决定、捆绑选择、重复 owner 和纯技术投票逐项清理。

现行分布：`PJ 12 / PP 12 / TU 19 / M05 40 / AL06 36 / TS 17 / CX 13 / ED 12 / RF 13 / F4 13`。

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
- 可以回复“本包全部接受推荐，以下除外……”，仍会逐项归档。
- 没有明确回复的项目继续待决；推荐和示例文案不会自动写入 `DECISIONS.md`。
- 涉及 API、编译器、毫秒和字节常量的纯技术选择，先由原型/benchmark 提供证据；只在它改变产品保证时请负责人取舍。
- 每包确认后，结论要同步到 `DECISIONS.md`、对应子系统权威规格、原子题库和 readiness gate。

完整依赖、最高风险矛盾和实施前工件见 [设计决策路线图](../DESIGN-DECISION-ROADMAP.md)。
逐字段配置和跨请求/存储的数据边界分别见 [配置 schema 候选](../CONFIG-SCHEMA-CANDIDATE.md) 与 [数据分类候选](../DATA-CLASSIFICATION-CANDIDATE.md)；两者都只是供各包引用的审阅底稿。
