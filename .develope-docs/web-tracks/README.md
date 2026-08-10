# Web 产品线设计预留区

更新日期：2026-08-10

状态：**设计预留 / 未开题**；不进入 yaca v0.1 实现与发行

## 为什么单独放这里

D-044 要求 v0.1 核心 zip **零 Web 表面**。  
D-058 允许在文档中为未来 **本机本地 Web** 产品线预留独立设计轨道，但：

- 不得因此向 v0.1 的配置、CLI/TUI、Runtime、self-test、依赖或 zip 注入 listener/页面/字段空壳；
- 不得把仓库根 `web/` 的历史占位当成已支持功能；
- 不得在核心 AgentLoop / Permission / Context 契约上为“以后也许做 Web”提前扩大公共 wire。

本目录只承载 **Web 产品线自己的设计**；核心领域仍以 `subsystems/` 为准。Web 只能 **消费** 核心已确认的 narrow application service / typed action / 领域事件，不得复制第二套 AgentLoop。

## 两条产品线（兼容级别 + 服务端栈）

| 产品线 | 意图 | 浏览器兼容基线 | 服务端技术栈（D-058 已确认） | 当前文档 |
| --- | --- | --- | --- | --- |
| `yaca-web` | 本机本地 Web 主线；在仍保守的前提下允许比 IE6 更现代的浏览器假设 | 待开题：拟面向仍可用的桌面浏览器集合，**不等于**现代 SPA 栈 | **Java 8** | [yaca-web.md](yaca-web.md) |
| `yaca-ie6` | 与 `yaca-web` 同产品族、同本机边界，但 **有意** 兼容到 **Internet Explorer 6** | IE6 + 同级老引擎；严格遵循仓库 `coding-style.txt` 的 HTM 规则 | **PHP 5.4** | [yaca-ie6.md](yaca-ie6.md) |

### 服务端栈规则

- **分栈实现**：Java 8 只服务 `yaca-web`；PHP 5.4 只服务 `yaca-ie6`。不把两条线合并成“同一后端换皮”。
- **不污染核心 zip**：JRE / PHP 运行时都不是 v0.1 terminal 三目标包的组成部分。
- **版本是硬基线**：设计、依赖与验收不得默认依赖更高语言版本（Java 9+ 或 PHP 7+ 专属能力），除非负责人日后修订 D-058。
- **语义对齐靠协议，不靠同构代码**：共享的是领域动作/事件与安全不变量的设计契约；允许两套后端各自实现。

两条线共享：

- 同一领域核心语义（不 fork AgentLoop 用户可见结果）；
- 同一本机/本地信任模型（默认 loopback，不自动变成 LAN/remote 控制面）；
- 同一 Permission / DoubleCheck / Context writer 不变量；
- 同一“显式重开设计流后才能编码”的门禁。

两条线 **不共享**：

- 服务端语言、运行时、打包与宿主假设（Java 8 vs PHP 5.4）；
- 页面实现、CSS/JS 能力集合、打包资源集；
- 浏览器验收矩阵；
- 可能的渲染降级与交互替代路径（例如 IE6 上的审批/流式展示）。

## 与仓库根 `web/` 的关系

仓库根 `web/` 现为 **空预留目录说明**，只指向本设计区与 D-058。  
任何 server、路由、静态页、配置字段的实现，都必须等 Web 决策包完成且核心 v0.1 门禁允许后再开独立实现批次。

## 开题前禁止事项

- 引入前端框架、构建链、现代 ES 模块工具链（尤其 `yaca-ie6`）；
- 在 `yaca-ie6` 中使用仅 PHP 7+ 可用的语法/标准库作为默认路径；
- 在 `yaca-web` 中使用仅 Java 9+ 可用的语言特性或默认要求更高 JRE；
- 在核心 `main.lua` / 配置 schema 中增加 `WebEnabled`、port、origin 等字段；
- 把 Web 审批当成可绕过 TUI 安全路径的后门；
- 将 public remote API 与“本机本地 Web”混为一谈（remote/headless 仍受 D-044 排除，除非另行重开）。

## 建议开题顺序（未来）

1. 先冻结本机边界、身份/CSRF、审批与 Context writer 所有权（两条线共用协议层）。
2. 再冻结 `yaca-ie6`：PHP 5.4 宿主/SAPI、IE6 页面子集与验收矩阵（更严，反向约束共享协议）。
3. 再冻结 `yaca-web`：Java 8 宿主（嵌入式容器 / 外置 servlet 等——待决）与在 IE6 子集之上的可选增强面。
4. 最后才考虑与核心发行物的打包关系（独立 zip / 可选组件 / 旁路进程等——全部待决）。
