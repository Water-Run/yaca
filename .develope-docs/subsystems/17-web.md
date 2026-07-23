# 17 Web 排除与重新进入记录

更新日期：2026-07-22

状态：v0.1 明确排除；`PJ-14 A` 已收到项目负责人回复

## 生效的产品结论

yaca v0.1 是 terminal-only 产品：

- 不发布、不启动 Web UI；
- 不监听为浏览器界面准备的 HTTP/WebSocket 端口；
- 不提供只读状态页、交互页面、浏览器审批或浏览器配置管理；
- 不把核心内部 application service、事件投影或测试 adapter 宣传为 Web/API；
- 不为未来 Web 冻结浏览器、HTTP、路由、静态资源或公共 action/event 兼容契约。

`PJ-17 A` 同时排除了公共 remote/headless IPC/RPC。用户通过 SSH 或其他方式获得普通终端后运行同一个 TUI，不构成 yaca 的 Web、远程控制服务或公共 headless API。

## v0.1 的零表面要求

以下对象不得出现在正式实现或发行物中：

- Web server、loader、router、template、静态页面和浏览器 bundle；
- HTTP/WebSocket/SSE 仅为 Web 使用的依赖、后台线程、端口探测和启动项；
- `WebEnabled`、listen address、port、browser、origin、CSRF、session cookie 等配置字段；
- Web CLI action、chat command、help 条目、self-test check、公开 Lua API 或未使用 schema namespace；
- 安装/升级迁移生成的 Web 默认值、示例配置和 README 启动说明；
- zip 中没有消费者的 Web 目录、占位文件、证书、图标或前端资源。

遇到历史配置、旧命令或外部脚本请求 Web 能力时，应返回稳定的 unsupported/deprecated 诊断；不能静默忽略后继续，让用户误以为能力已经启用。no-empty-shell 检查必须同时扫描配置 schema、parser、help、Runtime registry、self-test registry、依赖清单和最终 zip。

## 内部架构不构成未来承诺

TUI 可以消费窄的 ApplicationCoordinator、typed action 和领域事件，测试也可以直接注入事件；这些内部边界只服务当前 terminal 产品。它们：

- 不是 HTTP handler、公共 controller protocol 或浏览器兼容 API；
- 不承担认证、origin、CSRF、跨 tab、断线重连或网络 backpressure 语义；
- 不得为了“以后也许做 Web”扩大当前 Context writer、Permission、审批或存储契约；
- 可以随内部实现演进，不向第三方承诺 wire compatibility。

因此，当前架构只需保持领域核心不依赖某个特定终端绘制函数；这是一条可测试的内部依赖边界，不是 Web 预留功能。

## 显式重新进入条件

未来只有项目负责人提出具体 Web use case，并明确要求重新进入设计流时，才可以撤销本记录。重新进入不是把旧候选代码打开开关，而是建立新的产品决定和完整设计包，至少重新确认：

1. 只读还是交互，以及真实用户旅程；
2. loopback、本机 IPC、LAN 或 remote 的监听边界；
3. 浏览器与目标 OS 基线；
4. 身份、认证、origin/CSRF、缓存和秘密显示；
5. 输入、审批、取消和 Context writer 所有权；
6. 断线、重复提交、backpressure 和 unknown operation；
7. 配置/schema/XML 迁移、打包依赖和逐平台完整测试；
8. 与当时有效的 remote/headless 产品决定是否组合、隔离或冲突。

在这些决定和证据完成前，Web 始终是 unsupported，而不是“隐藏”“实验性”或“已预留”。
