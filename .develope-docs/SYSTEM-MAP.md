# 子系统地图

更新日期：2026-07-22

每个子系统都有独立文档。文档先作为讨论草案，经逐段确认后才成为设计契约。

负责人讨论入口见 [设计决策路线图](DESIGN-DECISION-ROADMAP.md) 与 `decision-packets/`；原子完整性见 [设计问题题库](QUESTIONS.md) 和 [全产品设计决策清单](DESIGN-CHECKLIST.md)；[配置 schema 候选](CONFIG-SCHEMA-CANDIDATE.md) 与 [数据分类候选](DATA-CLASSIFICATION-CANDIDATE.md) 提供横切字段/数据流底稿；能否进入实施计划由 [架构实施就绪门](ARCHITECTURE-READINESS.md) 判断。子系统地图说明最终权威规格归属，决策包负责通俗问答，题库负责防遗漏。

## 基线层

1. [产品契约与兼容性](subsystems/00-product-and-compatibility.md)
2. [平台兼容抽象](subsystems/01-platform-abstraction.md)
3. [进程执行与随包资源](subsystems/02-process-and-resources.md)
4. [网络传输](subsystems/03-network-transport.md)
5. [数据格式](subsystems/04-data-formats.md)
6. [配置与模型注册表](subsystems/05-configuration.md)

## Agent 核心层

7. [模型协议适配](subsystems/06-model-protocols.md)
8. [Prompt、指令与工作区发现](subsystems/18-prompt-and-workspace-instructions.md)
9. [Agent 工具系统](subsystems/07-tool-system.md)
10. [改动事务、审阅与撤销](subsystems/19-change-transactions-and-undo.md)
11. [权限与安全](subsystems/08-permission-and-safety.md)
12. [AgentLoop 与会话状态机](subsystems/09-agent-session.md)

AgentLoop 的开源实现源码核对单独保存在 [参考研究](references/agent-loop-reference-study.md)，它只提供机制证据，不属于已确认设计。

## 应用运行时横切层

13. [应用运行时、生命周期与并发](subsystems/22-application-runtime-and-concurrency.md)

22 号系统定义组合、生命周期、事件泵和背压，横跨端口与领域服务。把它列在这里是责任分组，不代表它能在 02/03、09/10、13/14 的契约或实现之前独立完成；其上游选择应提前讨论，最终装配在被组合服务可用后完成。

## 上下文层

14. [上下文存储](subsystems/10-context-storage.md)
15. [上下文定位、实时索引与交互式浏览器](subsystems/11-context-indexing.md)
16. [上下文压缩](subsystems/12-context-compaction.md)

## 交互、验证与交付层

17. [CLI](subsystems/13-cli.md)
18. [兼容 TUI](subsystems/14-tui.md)
19. [诊断、自检与日志](subsystems/15-diagnostics-and-logging.md)
20. [测试、Agent 评估与平台验收](subsystems/20-testing-and-agent-evaluation.md)
21. [打包、安装与发布](subsystems/16-packaging-and-release.md)

## 横切与排除边界

22. [扩展边界与未来兼容](subsystems/21-extension-boundary.md)
23. [Web 排除与重开记录](subsystems/17-web.md)（D-044 已明确排除）

## 依赖主线

领域与端口的主线是：`产品契约` → `平台/进程/网络/数据` → `配置/模型/指令/工具/改动/权限` → `AgentLoop` → `上下文/索引/压缩` → `CLI/TUI/诊断`。22 号运行时负责组合并协调这些已定义契约，不反向取得它们的业务所有权；20 号消费所有核心契约形成测试证据，16 号依据证据发布。

扩展边界是所有核心系统的约束，不代表 v0.1 实现扩展运行时。Web 在 v0.1 没有配置、CLI、listener、asset、依赖或发行空壳；17 号只保存未来必须由项目负责人显式重开设计流的条件。
