# 子系统地图

更新日期：2026-07-18

每个子系统都有独立文档。文档先作为讨论草案，经逐段确认后才成为设计契约。

## 基线层

1. [产品契约与兼容性](subsystems/00-product-and-compatibility.md)
2. [平台兼容抽象](subsystems/01-platform-abstraction.md)
3. [进程执行与随包资源](subsystems/02-process-and-resources.md)
4. [网络传输](subsystems/03-network-transport.md)
5. [数据格式](subsystems/04-data-formats.md)
6. [配置与模型注册表](subsystems/05-configuration.md)

## Agent 核心层

7. [模型协议适配](subsystems/06-model-protocols.md)
8. [Agent 工具系统](subsystems/07-tool-system.md)
9. [权限与安全](subsystems/08-permission-and-safety.md)
10. [Agent 会话循环](subsystems/09-agent-session.md)

## 上下文层

11. [上下文存储](subsystems/10-context-storage.md)
12. [上下文索引与命名](subsystems/11-context-indexing.md)
13. [上下文压缩](subsystems/12-context-compaction.md)

## 交互与交付层

14. [CLI](subsystems/13-cli.md)
15. [兼容 TUI](subsystems/14-tui.md)
16. [诊断、自检与日志](subsystems/15-diagnostics-and-logging.md)
17. [打包、安装与发布](subsystems/16-packaging-and-release.md)
18. [Web 界面](subsystems/17-web.md)（暂缓）

## 依赖主线

`产品契约` → `平台/进程/网络/数据` → `配置/模型/工具/权限` → `会话` → `上下文/索引/压缩` → `CLI/TUI/诊断` → `发布`

Web 是稳定核心之上的可选适配器，不复制 Agent、权限或上下文逻辑。
