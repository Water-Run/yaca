# 17 Web：v0.1 排除、重开条件与双产品线预留

更新日期：2026-08-10

状态：

- **v0.1 核心产品**：仍按 D-044 **明确排除**（零表面）
- **未来本机 Web 产品族**：D-058 已登记负责人重开意图与双线预留（`yaca-web` / `yaca-ie6`）
- **实现**：两条 Web 线均 **未开题、禁止编码**；仅设计文档可演进

## 1. v0.1 仍然生效的排除结论

yaca **v0.1** 是 terminal-only 产品：

- 不发布、不启动 Web UI；
- 不监听为浏览器界面准备的 HTTP/WebSocket 端口；
- 不提供只读状态页、交互页面、浏览器审批或浏览器配置管理；
- 不把核心内部 application service、事件投影或测试 adapter 宣传为 Web/API；
- 不为 v0.1 发行物冻结浏览器、HTTP、路由、静态资源或公共 action/event 兼容契约。

`PJ-17 A` 同时排除了公共 remote/headless IPC/RPC。用户通过 SSH 或其他方式获得普通终端后运行同一个 TUI，不构成 yaca 的 Web、远程控制服务或公共 headless API。

D-058 **不撤销** 上述 v0.1 零表面义务；它只打开“核心之后 / 并行产品线”的 **设计预留权**。

## 2. v0.1 的零表面要求

以下对象不得出现在 **v0.1 正式实现或三个核心 zip** 中：

- Web server、loader、router、template、静态页面和浏览器 bundle；
- HTTP/WebSocket/SSE 仅为 Web 使用的依赖、后台线程、端口探测和启动项；
- `WebEnabled`、listen address、port、browser、origin、CSRF、session cookie 等配置字段；
- Web CLI action、chat command、help 条目、self-test check、公开 Lua API 或未使用 schema namespace；
- 安装/升级迁移生成的 Web 默认值、示例配置和 README 启动说明；
- zip 中没有消费者的 Web 目录、占位文件、证书、图标或前端资源。

遇到历史配置、旧命令或外部脚本请求 Web 能力时，应返回稳定的 unsupported/deprecated 诊断；不能静默忽略后继续，让用户误以为能力已经启用。no-empty-shell 检查必须同时扫描配置 schema、parser、help、Runtime registry、self-test registry、依赖清单和最终 zip。

仓库中允许存在：

- `.develope-docs/web-tracks/` 下的 **设计预留文档**；
- 仓库根 `web/README.md` 指向设计预留的 **说明文件**。

二者都 **不是** 产品表面，不得被 loader 扫描为可启动组件。

## 3. 内部架构不构成未来承诺

TUI 可以消费窄的 ApplicationCoordinator、typed action 和领域事件，测试也可以直接注入事件；这些内部边界只服务当前 terminal 产品。它们：

- 不是 HTTP handler、公共 controller protocol 或浏览器兼容 API；
- 不承担认证、origin、CSRF、跨 tab、断线重连或网络 backpressure 语义；
- 不得为了“以后也许做 Web”扩大当前 Context writer、Permission、审批或存储契约；
- 可以随内部实现演进，不向第三方承诺 wire compatibility。

因此，当前架构只需保持领域核心不依赖某个特定终端绘制函数；这是一条可测试的内部依赖边界，不是 Web 预留功能。未来 Web 线若复用该边界，必须在 Web 决策包中 **重新证明** 审批、取消、writer 与秘密规则，而不是默认“内部接口已经够用”。

## 4. D-058：本机 Web 产品族预留（负责人重开）

更新日期：2026-08-10

项目负责人要求在设计阶段 **留空** 本地 Web 版本，并按 **兼容级别** 分为两条产品线；服务端技术栈同日确认：

| 产品线 ID | 含义 | 兼容意图 | 服务端技术栈 |
| --- | --- | --- | --- |
| `yaca-web` | 本机本地 Web 主线 | 保守浏览器集合；可宽于 IE6，但不是现代 SPA 默认 | **Java 8** |
| `yaca-ie6` | 同产品族的 IE6 线 | **有意** 兼容到 Internet Explorer 6 | **PHP 5.4** |

共同前提（已确认方向，细节未冻）：

1. **本地**：默认本机使用；不是公网多租户服务；不等于已批准的 LAN/remote controller。
2. **后置于 / 平行于核心 TUI**：不阻塞 v0.1 terminal 闭环的规格、证明与实现顺序。
3. **双线分文档、分栈实现**：能力协议尽量共享；**服务端不共享运行时**（Java 8 vs PHP 5.4）；前端资源与验收矩阵按兼容级别分轨。
4. **版本即基线**：不得默认依赖 Java 9+ 或 PHP 7+ 专属能力。
5. **零实现直至 Web 决策包完成**：现在只允许空预留文档，不允许 server/page 伪实现；JRE/PHP 不得进入 v0.1 核心 zip。

权威预留正文：

- [web-tracks 总览](../web-tracks/README.md)
- [yaca-web 预留](../web-tracks/yaca-web.md)
- [yaca-ie6 预留](../web-tracks/yaca-ie6.md)

## 5. 显式重新进入条件（实现级）

D-058 只批准 **设计预留**。进入 Web **实现** 前，仍须由项目负责人确认具体 use case，并完成独立设计包，至少重新确认：

1. 只读还是交互，以及真实用户旅程；
2. loopback、本机 IPC、LAN 或 remote 的监听边界（默认应保持最窄）；
3. `yaca-web` 与 `yaca-ie6` 各自的浏览器/OS 基线与验收矩阵；
4. 各线服务端宿主：`yaca-web` 的 Java 8 运行/打包证据；`yaca-ie6` 的 PHP 5.4 SAPI/打包证据；
5. 身份、认证、origin/CSRF、缓存和秘密显示；
6. 输入、审批、取消和 Context writer 所有权（与 TUI 并存时的单 writer）；
7. 断线、重复提交、backpressure 和 unknown operation；
8. IE6 线的传输降级（不得唯一依赖现代流式 API）；
9. 配置/schema/XML 迁移、打包依赖和逐平台完整测试；
10. 与当时有效的 remote/headless 产品决定是否组合、隔离或冲突；
11. 与 v0.1 核心 zip 的关系：独立产物还是可选组件（默认倾向独立，待决；**不得**把 JRE/PHP 混入 terminal 三目标包）。

在这些决定和证据完成前，Web **实现** 始终是 unsupported，而不是“隐藏”“实验性”或“半预留代码”。

## 6. 历史占位清理策略

仓库根 `web/` 曾含空 `page.htm`、`server.lua`（pegasus）等占位。按 D-044/D-058：

- 不得把它们当作可运行功能；
- 实现前清理项：仅保留指向 `.develope-docs/web-tracks/` 的说明，避免假完成度；
- 不得重新引入未审计的 Web 框架依赖。

## 7. 与子系统地图的关系

- v0.1 主线：17 号文档继续是 **排除 + 预留入口**，不参与核心依赖主线编码顺序。
- Web 产品族：有自己的未来决策包与测试门，不占用 AR-P0 核心门的“必须先做 Web”位置。
- 核心 P0 仍优先：AgentLoop、配置 schema、Context XML、事件泵、工具矩阵、三目标发布证明。
