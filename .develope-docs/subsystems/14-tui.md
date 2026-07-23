# 14 兼容 TUI

状态：候选

## 职责

提供对话输入输出、状态、确认、选择、固定快捷键和点命令交互。产品对用户只有一套 TUI 语义；内部根据终端事实自动选择原生控制台、基本终端序列或逐行后备，不暴露 theme/vivid/mode/自定义键位开关。

## 边界

- TUI 是适配器，不拥有会话、权限、配置或上下文业务规则。
- 终端能力事实来自 01 号系统。
- 所有操作必须能用键盘完成。

## 旧系统重点

- Windows XP conhost 不假设 ANSI、UTF-8、VT 输入或宽字符正确显示。
- Vista 至 11 可以在探测到能力后增强，但必须保留与 XP 一致的语义与逐行后备入口。
- CentOS 7 终端不假设 256 色、true color、鼠标或大窗口。
- 当前方向不承诺全屏、鼠标、true color、动画或用户自定义快捷键。

## 已确认的固定输入意图与兼容边界

项目负责人已给出主输入意图：空闲或忙时普通 `Enter` 发送/排队，`Ctrl+Enter` steer 当前工作，`Shift+Enter` 输入换行，`Alt+Enter` 发起一次只读旁问，`Esc` 终止。语义已确定方向，精确取消层级和旁问并发/持久化仍由 AgentLoop 决定。

这些组合键不能作为所有终端唯一入口。Windows 的 `KEY_EVENT_RECORD` 可以携带虚拟键与 modifier 状态，但 cooked `ReadConsole` 会由系统处理回车和控制键；POSIX canonical mode 只按完整行交付输入；xterm 的 modified-key 编码也是可选能力而非普遍默认。参考：[Windows console modes](https://learn.microsoft.com/en-us/windows/console/high-level-console-modes)、[KEY_EVENT_RECORD](https://learn.microsoft.com/en-us/windows/console/key-event-record-str)、[POSIX terminal interface](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap11.html)、[xterm modified keys](https://invisible-island.net/xterm/modified-keys.html)。

因此候选契约是：

- 能力足够时由原生/raw 输入后端识别上述固定快捷键。
- cooked line、`TERM=dumb`、SSH/终端不报告 modifier 或重定向时，所有语义都有固定 ASCII 文本入口；候选词根是 `.steer`、`.ask`、`.cancel` 与显式多行开始/结束命令。
- 后备入口不是另一种产品模式；它提交与快捷键相同的领域动作，XML、权限、预算和结果完全一致。
- help 只列出当前环境实际可用的按键及其固定文本等价入口，不允许重新绑定。

## 当前设计缺口

现有规则已经是一份较完整的旧终端兼容基线，但还不是 TUI 体验设计。至少还缺少：

- 启动、恢复、待输入、模型生成、工具调用、等待确认、重试、取消、压缩、失败和退出的界面状态。
- 用户、Agent、工具、状态、警告、错误和确认在无颜色 transcript 中的稳定文本语法。
- 状态是常驻区域、可更新的一行、每次变化追加一行，还是只由 `.status` 查询。
- Ctrl+C、EOF、生成期间输入、排队/steer 和多行输入语义。
- 长路径、长命令、工具输出、CJK、控制字符和 terminal injection 的处理。
- 模型/权限/上下文选择器、配置编辑器和确认框的编号、分页、取消与默认项。
- 自动能力降级、原生 Windows 颜色与基本终端颜色如何保持相同文字语义。

`DotCommandCompletion=true` 与“不要求 raw mode、方向键或 ANSI”并不天然兼容。补全只能是增强能力，不能成为普通点命令可用性的前提。`CheckModelOnStart=true` 也可能让离线或慢网络启动阻塞，必须重新讨论其默认值和可取消性。

## 已确认的 `.cautious` 语义边界

`.cautious` 管理当前会话的 `DoubleCheck` 覆盖值，并由上下文系统保存到当前 XML。TUI 只解析命令、显示默认值/覆盖值/有效值和操作结果；它不能直接改写用户配置、切换 Permission profile 或自行决定 `DoubleCheck` 包含哪些复核行为。无参数、`on/off/toggle/reset` 的具体语法仍待 `TUI-10` 确认。

## 上下文浏览器的 TUI 边界

交互式上下文浏览器的目录树、搜索、选择、重命名、删除和刷新语义由 11 号 `ContextBrowserController` 统一提供。TUI 只负责把用户输入翻译为语义动作并显示结果：

- 规范入口使用编号与 `open/select/search/rename/delete/up/root/refresh/quit` 一类逐行命令，不要求 raw mode、ANSI 或方向键。
- 能力足够时可以让固定方向键、颜色、高亮和临时状态行调用相同 controller action，但不增加鼠标、可重绑定按键或不同默认选择。
- 任一内部 renderer 对同一快照和动作序列必须选中同一候选、触发相同确认并得到相同错误。
- 普通搜索只过滤候选列表，不自动连接；精确名称/hash 输入调用统一 Resolver。
- 重命名或删除确认必须显示完整逻辑路径与当前 16 位 hash，不能只显示可能重复的名称。
- 快照过期、扫描不完整、XML 损坏和目标已变化都要有稳定文字提示，颜色不能承担唯一含义。

`.status` 显示的当前 hash 从活动 ContextHandle 的最新逻辑路径实时计算，不为显示状态扫描整棵 `CONTEXT`。如果活动 XML 已被外部移动或删除，候选体验是同时显示 `stale`/失效状态，不能只显示一个看似仍可恢复的旧 hash。

## 主界面总体方向

### A. 追加式逐行对话 REPL（当前规范候选）

每个语义事件以稳定文本块追加。当前领先视觉词汇是 `[YACA]`、`[USER]`、`[TOOL #12]`、`[STATUS]`、`[QUEUE #2]`、`[STEER #3]`、`[SIDE #1]`、`[WARNING]`、`[ERROR ID]`、`[ACTION]`；精确选择留给视觉决策包。输入始终在最后，选择和确认使用数字/字母；plain 模式完全不移动光标。

它最适合 XP conhost、`TERM=dumb`、终端 scrollback、屏幕阅读器和纯文本快照测试。代价是状态不够紧凑，流式输出和长工具日志容易产生较多行。

### B. 追加式 transcript + 可更新状态行（A 的自动增强）

正文仍永久追加，仅在确认支持时用基本 ANSI 更新当前动作或进度；不支持时把同一状态变化输出为普通行。

它可改善等待模型、网络重试和工具执行的反馈，复杂度仍可控。它是内部能力足够时对 A 的自动增强，不是用户可选择的另一种 mode，也不能成为正确性依赖。

### C. 轻量全屏分区（当前不采用）

固定 transcript、状态、输入和确认区域，依赖 raw input、尺寸和光标控制，同时维护逐行 renderer 作为后备。

它的可发现性较好，但滚动、resize、用户数据宽度、崩溃后的屏幕恢复和 XP 后端成本最高；也与当前“简单、无鼠标、无模式切换”方向不符。

## 建议的语义角色

样式必须先定义文本语义，再叠加颜色：

| 角色 | plain 模式示例 | 颜色用途 |
| --- | --- | --- |
| 用户 | `USER:` | 可选标签色 |
| Agent | `ASSISTANT:` | 可选标签色 |
| 工具 | `TOOL read_file:` | 区分执行信息，不代替状态文字 |
| 状态 | `STATUS: waiting for model` | 可选弱化色 |
| 警告 | `WARNING:` | 仍保留文字标签 |
| 错误 | `ERROR:` | 仍保留文字标签 |
| 需操作 | `CONFIRM:` / `ACTION REQUIRED:` | 必须明确输入选项与默认行为 |

模型和工具文本是不可信内容。显示前必须处理 ANSI/OSC/控制字符，避免伪造提示、清屏、改标题或隐藏输出。

## 异步输出与输入行

追加式 transcript 仍有一个不能由样式掩盖的 full-duplex 问题：在 cooked/canonical 输入中，renderer 看不到用户尚未提交的系统编辑缓冲；此时直接打印模型/tool delta 会穿过输入行。

候选契约是：raw/native editor 保存并重绘 draft；cooked 后备把高频异步 delta 暂存/合并到安全换行，用户提交一行后再追加，并用一条 status 表明有积压。不能清空 draft、让输出覆盖输入，或声称 cooked 终端能识别普通粘贴中的回车。粘贴保护在 raw/bracketed-paste 环境启用；后备使用显式 `.begin/.end` 或 `.paste` 语法。

`Esc` 只是可用环境中的快捷键，规范后备是 `.cancel request|tool|side|turn|exit`。不采用“短时间按两次 Esc”的核心协议，因为 cooked 终端可能根本不交付该按键。

## 需要逐项确认的体验

1. 启动一行、输入提示符、角色标签、留白、时间戳和整体信息密度。
2. 常驻最小状态、`.status` 详情，以及模型/权限/context hash/队列/当前动作的字段顺序。
3. 模型流式文本、provisional 文本、工具调用、shell 输出、Git diff 与完成报告的块样式。
4. queue、steer、旁问和取消的可见状态、序号、插入点与持久化提示。
5. 确认页显示的命令/路径/host、默认选择、DoubleCheck 结果和拒绝后的下一步。
6. chat、help、model-repl、config-repl、context-repl、self-test、model/permission picker 的完整页面集合与共同导航词根。
7. 配置损坏、无 Model、配置/上下文不匹配、网络重试、压缩、磁盘满和恢复的错误/提示文案。
8. Windows 原生颜色与 Linux 基本颜色的映射，以及颜色失效时的稳定 ASCII 标签。
9. 80x24、未知尺寸、长路径、长命令、非 ASCII 用户数据和超长输出的单列换行/分页规则。
10. 非 TTY、重定向、broken pipe、EOF、Ctrl+C 和终端模式恢复与 CLI 的边界。

## 可视化时机

逐行 REPL 应先用可复制的 ASCII transcript 讨论，因为它同时就是最低兼容输出和 golden test 候选。只有在确认固定状态行或全屏分区后，80×24 的并排 mockup 才比文字更有帮助；mockup 仍不能替代真实 XP/CentOS 终端验证。

## 当前讨论入口

在产品负责人已要求简单、无鼠标、基本色彩后，当前推荐把追加式逐行 REPL 作为所有平台规范，basic ANSI/原生颜色只增强标签与 diff；不再把全屏作为同等首版候选。下一步通过 80×24、40 列、XP 无色、忙时 draft、审批、Git diff、error/recovery、三个 REPL 和 self-test 的完整 ASCII transcript 决定页面风格。
