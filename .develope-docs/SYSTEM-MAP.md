# 子系统地图

更新日期：2026-07-18

每个子系统都有独立文档。文档先作为讨论草案，经逐段确认后才成为设计契约。

完整待决策主题、优先级与建议讨论顺序见 [全产品设计决策清单](DESIGN-CHECKLIST.md)。子系统地图说明边界，清单负责避免遗漏用户体验、生命周期、失败恢复、安全、配置和验收问题。

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

## 上下文层

13. [上下文存储](subsystems/10-context-storage.md)
14. [上下文定位、实时索引与交互式浏览器](subsystems/11-context-indexing.md)
15. [上下文压缩](subsystems/12-context-compaction.md)

## 交互、验证与交付层

16. [CLI](subsystems/13-cli.md)
17. [兼容 TUI](subsystems/14-tui.md)
18. [诊断、自检与日志](subsystems/15-diagnostics-and-logging.md)
19. [测试、Agent 评估与平台验收](subsystems/20-testing-and-agent-evaluation.md)
20. [打包、安装与发布](subsystems/16-packaging-and-release.md)

## 横切与暂缓边界

21. [扩展边界与未来兼容](subsystems/21-extension-boundary.md)
22. [Web 界面](subsystems/17-web.md)（暂缓）

## 依赖主线

`产品契约` → `平台/进程/网络/数据` → `配置/模型/指令/工具/改动/权限` → `AgentLoop` → `上下文/索引/压缩` → `CLI/TUI/诊断` → `测试证据` → `发布`

扩展边界是所有核心系统的约束，不代表 v0.1 实现扩展运行时。Web 是稳定核心之上的可选适配器，不复制 Agent、权限或上下文逻辑。
