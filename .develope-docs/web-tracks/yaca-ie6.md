# yaca-ie6 设计预留

更新日期：2026-08-10

状态：**空预留**；未开始决策包；禁止实现

## 产品意图

`yaca-ie6` 是 yaca 产品族中 **有意兼容到 Internet Explorer 6** 的本机本地 Web 表面。

负责人明确要求：这条线不是“尽量兼容”，而是 **兼容级别设计的一等公民**。  
它与 `yaca-web` 同属本地 Web 产品族，但浏览器与前端技术选择以 IE6 为硬门槛。

## 已确认技术栈（D-058）

| 层 | 选择 | 说明 |
| --- | --- | --- |
| 服务端语言 / 平台 | **PHP 5.4** | 语言级别与运行基线；不得默认依赖 PHP 7+ 专属语法或行为 |
| 浏览器 | **Internet Explorer 6** | 最低验收目标；有意保留 |
| 与 `yaca-web` | **分栈** | 主线使用 Java 8；本线不实现为 Java |

约束：

- 不得把 PHP 运行时打进 v0.1 核心 `yaca` terminal zip。
- 未批准前不默认绑定仅现代 PHP 生态可用的框架/Composer 强制栈。
- SAPI/宿主（内置 server、Apache/mod_php、CGI 等）待决；须能在目标旧环境上证明。
- 与核心 yaca 的联接待决，但必须遵守单 writer / Permission / DoubleCheck。

## 兼容基线（预留声明，待正式冻结）

在正式决策包完成前，设计与任何未来实现草案必须假设：

| 维度 | 约束 |
| --- | --- |
| 服务端 | **PHP 5.4** 语言与同代扩展假设 |
| 浏览器 | Internet Explorer 6 为最低验收目标 |
| 文档类型 | 经典 HTML；允许 `.htm` |
| JS | 无 `let`/`const`、无箭头函数、无 Promise/fetch/ES6 module；使用 `var` 与经典函数 |
| DOM | 无依赖 `querySelector` 作为唯一路径；事件优先 `attachEvent` 兼容写法 |
| 布局 | 无 flex/grid/CSS 变量/媒体查询作为必需；可用 table/float/固定宽 |
| 传输 | 不得默认依赖 WebSocket/EventSource 作为唯一通道；须有 IE6 可走的降级（例如短轮询或分块策略——**待决**） |
| 框架 | 禁止前端框架与现代打包链作为运行时依赖；后端避免 PHP 7+ only 默认路径 |

权威文风与禁止项以仓库根 [`coding-style.txt`](../../coding-style.txt) 第 4 章 HTM style 为准；本文件不得放宽该章。

## 与 `yaca-web` 的关系

- **更严线约束共享协议**：若某交互在 IE6 无法安全表达，不得只做在 `yaca-web` 里然后声称产品族已支持。
- 服务端 **不共享运行时**（PHP 5.4 vs Java 8）；对齐靠共享协议与验收语义。
- `yaca-web` 可以在 IE6 子集之上做 progressive enhancement，但核心审批、取消、错误与 writer 语义必须在 IE6 线可完成，或被明确标为“仅 yaca-web 增强且非安全关键路径”。
- 两套前端/后端可以分目录构建；**不得**为了 IE6 而降低核心 TUI 的 XP/CentOS 保证，也不得为了现代浏览器而迫使核心依赖 Web。

## 待冻结（开题清单，非现行契约）

**服务端语言已定为 PHP 5.4**；下列其余项未决。

### PHP 5.4 服务端

- [ ] SAPI/宿主与启动/停止方式
- [ ] 仅 PHP 5.4 可用的扩展白名单（session、json、openssl 等是否必需）
- [ ] 与核心 yaca 的协议载体及背压
- [ ] 打包：是否捆绑 PHP、平台矩阵、许可证
- [ ] 明确禁止作为默认路径的 PHP 7+ 特性清单（类型声明扩展、`??` 等——开题时列死）

### 页面与交互

- [ ] 对话 transcript 的追加式 plain HTML 策略
- [ ] 审批（confirm / DoubleCheck 等待）在无现代 UI 下的表单流
- [ ] 忙时 queue / cancel / side 的页面等价入口
- [ ] 大输出截断、刷新与“是否丢草稿”规则

### 传输与会话

- [ ] IE6 可用的请求模型（同步 XHR 限制、超时、取消）
- [ ] 流式 token 是否降级为分块轮询；背压与重复提交
- [ ] cookie / 隐藏字段 / path token 的会话绑定

### 验收

- [ ] 真实 IE6（或等价引擎）矩阵：本地页面、脚本、表单、长会话
- [ ] 与 Windows XP 同机联调是否作为硬证据
- [ ] 无色、无 JS、JS 部分失败时的可读降级（至少错误与安全事实不可静默消失）

### 发布

- [ ] 是否与 `yaca-web` 同包双资源，或独立 `yaca-ie6` 产物
- [ ] 静态资源体积与老机器内存上限

## 明确非目标（除非另行重开）

- 以 IE6 线为借口推迟核心 TUI v0.1
- 在 IE6 上承诺 pixel-perfect 现代 UI
- 依赖 ActiveX 任意控件作为默认安全模型（若未来评估，必须单独威胁建模）
- 公网暴露的 IE6 管理面

## 下游文档钩子

- 总记录：[../subsystems/17-web.md](../subsystems/17-web.md)
- 兄弟线：[yaca-web.md](yaca-web.md)
- 决定：D-058
- 风格：[`coding-style.txt`](../../coding-style.txt) HTM / IE6 章
