# 决策包 04：TUI 视觉、输入与 CLI 体验

更新日期：2026-07-18

状态：等待项目负责人回复；本文中的推荐、样稿、命令名、简称、颜色和状态词都不是已确认决定

## 本包要决定什么

本包不讨论“终端里加一点颜色”这种零散美化，而是决定用户从启动到退出实际怎样操作 yaca：什么是永久 transcript，输入期间异步输出怎样不破坏 draft，queue/steer/side/cancel 怎样看得见，危险动作怎样确认，错误和恢复怎样让人知道真实状态，以及三个 REPL 与 self-test 是否像同一个产品。

它覆盖：

- 单一规范视觉语言及两个被排除反例的 80x24 ASCII 对照，用来说明取舍而不是重开 fullscreen/theme。
- 40 列与 Windows XP 无色控制台的真实降级结果。
- chat 头部、角色标签、输入提示符、状态、留白和信息密度；TranscriptChrome 词汇与密度分别决策。
- Streaming、provisional assistant 文本、raw/native draft 重绘与 cooked-line 后备。
- `Enter` queue、`Ctrl+Enter` steer、`Shift+Enter` 换行、`Alt+Enter` side、`Esc` cancel 及文本等价入口。
- 输入编辑、历史、普通粘贴、bracketed paste、多行和发送以 `.` 开头正文的规范 grammar。
- 工具生命周期卡、审批、Markdown、代码、Git diff、错误、重试和崩溃恢复。
- `model-repl`、`config-repl`、`context-repl` 与 self-test 的共同导航语法。
- canonical 顶层/dot-command registry、简称唯一性、非 TTY 能力、machine output 和 command x state 摘要。
- 如何用 golden transcript/trace 验证旧终端、无色、窄屏与降级等价性。

本包不决定：

- queue/steer/side 的精确持久化点、并发预算和调度时序；它们属于 AgentLoop 包。
- 哪些动作需要 Permission 或 DoubleCheck、reviewer 是否允许、override 范围；它们属于安全包。
- Model/配置全部字段、self-test 每个探针和网络重试数字；它们属于配置/网络包。
- Context 浏览器的搜索距离、hash、重命名、删除和锁的领域规则；它们属于 Context 包。
- Windows Console、POSIX tty、事件泵和取消进程树的 ABI；它们属于平台/Runtime 包。
- 逐字实现代码或 Lua 模块布局。本文是负责人决策材料，不是实施计划。

## 已确认、这次不重新询问的约束

1. 目标包含 Windows XP、Vista、7、8、8.1、10、11 的 Win32 x86 包，以及 CentOS 7/旧 Linux 的 x86_64 包；不承诺旧 macOS。
2. yaca 保持简单：无鼠标、无用户自定义快捷键、无 vivid/theme 系统；只需要基本颜色和高亮。
3. 程序自带 UI、配置键、命令、枚举和机器字段使用 English/ASCII；用户/模型正文、真实路径与 Context 名仍是 Unicode 用户数据，不能因为 UI 不本地化就拒绝或改写。
4. 负责人已经给出五个输入意图：普通 `Enter` 发送或排队，`Ctrl+Enter` steer，`Shift+Enter` 换行，`Alt+Enter` 发起只读 side，`Esc` 终止当前活动。
5. 组合键在老控制台、cooked/canonical line、SSH 和 `TERM=dumb` 上可能不可区分，因此不能成为唯一入口。
6. chat、`model-repl`、`config-repl`、`context-repl`、self-test、help、recovery 是七个简单逐行 surface；本包只设计共同体验，不重新合并或删除它们。
7. Context XML 是会话事实和跨机接盘核心；终端 scrollback、颜色和当前屏幕绝不是事实源。
8. 当前产品没有 `.fork` 或分支对话，help/命令表不得残留相关入口。

第 4 条描述 **chat composer 拥有输入焦点** 时的意图。审批、recovery 和 REPL 有独立 prompt；尤其 approval 不能让同一个 Enter 同时代表“排队消息”和“允许副作用”。本文在 TU-07 中编号询问 `action>` 的默认项，chat 消息在 approval prompt 中必须走显式 queue 文字后备。这不是额外的未编号选择，也不暗中改写已确认的 chat 快捷键。

## 先固定架构边界：TUI 是投影，不是状态机

推荐把终端交互拆成四条窄边界：

```text
domain events -> semantic view blocks -> terminal renderer -> stdout/console
key/line input -> input intent       -> controller action -> domain result
```

- Domain 产生 `assistant-provisional`、`tool-running`、`approval-required`、`queue-added`、`retry-waiting`、`recovery-required` 等带 ID 的事实。
- Semantic view 层决定一个事实应该显示哪些字段、哪些字段属于 details，以及无颜色时的 ASCII 标签。
- Renderer 只决定颜色、软换行、是否能安全重绘 draft/临时状态行；不能改变默认选择、审批结果或命令可用性。
- Input adapter 报告 `send`、`queue`、`steer`、`side`、`cancel`、`multiline-newline` 等意图；不能直接修改 AgentLoop table。
- XML 保存 canonical event 和实际用户动作，不能把屏幕转义序列、光标位置或截断后的卡片当完整事实。

因此“Windows XP plain”“Linux basic color”“native/raw 输入”不是三个产品模式。它们是同一语义界面的自动能力投影。若两个后端对相同事件和输入序列产生不同领域动作，就是正确性错误，不是主题差异。

## 一个推荐视觉候选与两个反例：同一事件、同一 80x24 窗口

三个样稿都使用同一组假设事实：用户要求修复重复 Model section；Agent 已定位根因；search 完成；patch 需要审批；用户允许一次；工具开始执行；用户在忙时输入一条默认 queue 的补充消息。A 是已确认约束内的推荐形态，其留白由 TU-01、固定词汇由 TU-20 决定；B/C 只保留为说明为何不采用框线/全屏的反例，不是待回复选项，也不表示仓库已经实现这些行为。

所有固定 UI 文本都使用 ASCII English。为便于审阅，下面每个代码块恰好表示 24 行，行宽不要求用空格填满，但任何有意义内容都应在 80 列内完成。

### 风格 A：稀疏追加式 transcript（推荐）

```text
yaca 0.1 | ctx parser-fix [9f2a15c03d881e74] | Work | Std | DC on
cwd: C:\src\demo
[STATUS] raw keys | Enter queue | Ctrl+Enter steer | Alt+Enter side

[USER]
Fix duplicate Model sections. Run the related tests.

[ASSISTANT]
I found silent replacement in the INI parser. I will reject the second
section and preserve its line number.

[TOOL 12] search | completed | 0.1s
target: src\  result: 3 matches
[TOOL 13] patch | waiting-approval
target: C:\src\demo\src\ini.lua

[ACTION 13] approval required | default: deny
operation: patch  target: C:\src\demo\src\ini.lua
reason: reject duplicate Model sections
allow 13 once | deny 13 | details 13
action> allow 13 once

[STATUS] tool 13 running | queue: 0 | saved
!> Add a regression test_
```

特点：

- 没有框线；语义标签、空行和稳定字段顺序形成层级。
- transcript 永久向下追加，适合 scrollback、复制、重定向、screen reader 和 golden test。
- 80 列下有足够信息，40 列时去掉横向字段组合即可自然变成单列。
- `!>` 只用两个字符说明“系统正忙，普通 Enter 会 queue”，不把 Context 路径塞进输入行。

代价：状态不像 dashboard 那样常驻；长会话主要依赖 `.status`、`.history`、`.details` 和终端 scrollback 查旧内容。

### 反例 B：复古密集 ASCII 面板（不进入决策）

```text
+------------------------------------------------------------------------------+
| YACA 0.1 | CTX parser-fix [9f2a15c03d881e74] | Work | Std | DC on            |
| CWD C:\src\demo                                                              |
+-- USER ----------------------------------------------------------------------+
| Fix duplicate Model sections. Run the related tests.                         |
+-- YACA ----------------------------------------------------------------------+
| I found silent replacement in the INI parser. I will reject the second       |
| section and preserve its line number.                                        |
+-- TOOLS ---------------------------------------------------------------------+
| 12 SEARCH  completed  0.1s  src\  3 matches                                  |
| 13 PATCH   waiting-approval  C:\src\demo\src\ini.lua                         |
+-- ACTION 13 -- DEFAULT DENY -------------------------------------------------+
| operation: patch                                                             |
| target: C:\src\demo\src\ini.lua                                              |
| reason: reject duplicate Model sections                                      |
|                                                                              |
| allow 13 once | deny 13 | details 13                                         |
| action> allow 13 once                                                        |
+-- STATUS --------------------------------------------------------------------+
| tool 13 running | queue 0 | saved                                            |
+-- INPUT ---------------------------------------------------------------------+
| !> Add a regression test_                                                    |
| Enter queue | Ctrl+Enter steer | Alt+Enter side                              |
+------------------------------------------------------------------------------+
```

特点：无颜色也很像完整应用，区域边界明确，喜欢 DOS/复古工具的用户容易辨认。

代价：每一行要支付左右边框和标题空间；40 列、长路径、Unicode 宽度、流式输出与复制 diff 时框线很快变成噪声。只要内容换行，边框 renderer 就必须正确计算显示宽度；这在 XP 代码页、组合字符和未知终端宽度上是额外风险。

### 反例 C：轻量全屏分区（已排除）

```text
+ YACA 0.1 -- parser-fix [9f2a15c03d881e74] -- Work / Std / DC on -------------+
| cwd C:\src\demo                                                              |
+ TRANSCRIPT ------------------------------------------------------------------+
| USER  Fix duplicate Model sections. Run the related tests.                   |
|                                                                              |
| YACA  I found silent replacement in the INI parser. I will reject the        |
|       second section and preserve its line number.                           |
|                                                                              |
|                                                                              |
|                                                                              |
|                                                                              |
+ ACTIVITY --------------------------------------------------------------------+
| TOOL 12  search  completed  0.1s  src\  3 matches                            |
| TOOL 13  patch   running                                                     |
| ACTION 13  allowed once                                                      |
| target: C:\src\demo\src\ini.lua                                              |
| reason: reject duplicate Model sections                                      |
+ STATUS ----------------------------------------------------------------------+
| tool 13 running | queue 0 | saved | raw input                                |
| Enter queue | Ctrl+Enter steer | Alt+Enter side | Esc cancel                 |
+ INPUT -----------------------------------------------------------------------+
| !> Add a regression test_                                                    |
|                                                                              |
+------------------------------------------------------------------------------+
```

特点：状态、活动工具和输入位置始终固定，视觉上最像现代终端应用；在大屏上容易发现当前焦点。

代价：必须拥有 raw input、可靠尺寸、光标寻址、resize、滚动区和崩溃恢复；还要另写逐行后备。XP/cooked 只能运行另一套视觉实现，两个实现很容易在审批焦点、流式残片或关闭时漂移。它还会削弱原生 scrollback 与复制完整 transcript 的体验。

### 推荐结论

推荐 A 作为唯一规范视觉语言。支持可靠光标控制时，可以自动增加基本颜色和一条临时状态行，但正文仍是追加式 transcript；不要把 C 作为首版的“增强模式”。B 的复古气质可以保留在标签和简洁 ASCII 细节里，不应让整屏框线成为布局协议。

当前“单一、简单、append-only TUI”已经明确，B/C 仅记录被淘汰的成本证据，不能通过回复 TU 编号选中，也不会留下 theme/fullscreen loader。若未来产品范围真的改变，应另开新一轮设计，而不是复用本包中的反例。

## 40 列、Windows XP、完全无色时必须仍然完整

下面是风格 A 对同一审批事实的 40 列 plain 投影。它不依赖 ANSI、图标、Unicode 边框、鼠标或组合键，仍可完成危险动作确认：

```text
yaca 0.1
[STATUS] plain input (XP fallback)
shortcuts: unavailable; use .help

[USER]
Fix duplicate Model sections.

[TOOL 13]
state: waiting-approval
operation: patch
target:
 C:\src\demo\src\ini.lua

[ACTION 13]
default: deny
allow 13 once
deny 13
details 13
action> allow 13 once

[STATUS] tool 13 running
queue: 0
saved: yes
!> Add a regression test_
```

窄屏规则推荐固定为：

- 单列；标签独占一行，字段逐项换行，不维持表格或并排按钮。
- 审批的完整规范目标不能省略。普通工具卡可以显示有标记的摘要，完整值由 `details <id>` 追加查看。
- 长正文和代码由终端软换行，不向事实文本插入伪换行或省略中间字符。
- 可见截断必须同时显示 `shown N/M`、完整内容所在 event ID 和 details 入口。
- 颜色从来不承载唯一含义；`[WARNING]`、`[ERROR id]`、`[ACTION id]` 与状态词始终存在。
- 固定 UI 是 ASCII；用户正文和真实路径若含终端不能显示的字符，显示层使用稳定可见 escape，底层规范路径和 hash 输入不被替换。

## 一个语义界面、三档自动能力

能力不是 `plain/basic/enhanced` 用户模式开关，而是启动时和终端变化后观察到的事实。推荐内部形成以下能力矩阵：

| 能力事实 | native/raw 可用 | cooked/canonical TTY | 非 TTY / broken output |
| --- | --- | --- | --- |
| 永久 transcript | 逐块追加 | 逐块追加 | 只按 CLI 契约输出，不启动 TUI |
| 基本颜色 | 探测后 8/16 色 | 探测后可有 | 禁用 |
| 固定组合键 | 可识别才显示 | 不承诺 | 不适用 |
| 未提交 draft | yaca 拥有并可重绘 | 系统 line editor 拥有，yaca 看不到 | 不适用 |
| 异步状态 | 可在完整块后恢复 draft | 合并并延后到安全换行 | stderr/退出码按 CLI 契约 |
| 普通粘贴 | bracketed paste 或 native paste 可保护 | 无法区分粘贴内换行与 Enter | stdin 必须只有一个显式用途 |
| 文本后备动作 | 始终可用 | 唯一完整入口 | 只允许声明为非交互的命令 |

启动时最多追加一条能力提示，例如：

```text
[STATUS] cooked input: use .steer, .side and .cancel; see .help input
```

不能每次按键都警告，也不能静默显示一个当前终端无法产生的 `Ctrl+Enter`。help 应根据能力事实显示“可用按键 + 永远可用的文本等价入口”，而不是打印理想平台的固定截图。

### 基本颜色的推荐映射

颜色只由 renderer 生成，模型、工具、路径和文件内容中的控制序列先可见化。候选 8/16 色语义是：

| 语义 | 可选颜色增强 | 永久文字事实 |
| --- | --- | --- |
| Assistant | cyan 或默认亮色 | `[ASSISTANT]` |
| User | 默认亮色 | `[USER]` |
| Tool | cyan/blue | `[TOOL id]` + 状态词 |
| Status | 默认暗色（可读时） | `[STATUS]` |
| Warning | yellow | `[WARNING]` |
| Error | red | `[ERROR error-id]` |
| Action required | yellow | `[ACTION action-id]` + `default: deny` |
| Diff add/delete/hunk | green/red/cyan | 行首 `+`、`-`、`@@` |

首版不提供 palette/theme/vivid 配置。不支持颜色、输出被重定向、能力未知或环境明确要求 no-color 时自动关闭；关闭后不会改变间距、选项、默认值或状态词。v0.1 也不发 bell、声音或桌面通知。

## Streaming 与正在编辑的 draft

### Runtime 看到的事实必须比动画更重要

Streaming 至少有三种不同事实，UI 不能混为一段“已经完成”的 assistant 消息：

1. `provisional`：provider 已送来部分文本，但响应尚未合法结束。
2. `completed`：完整响应已验证并持久化为规范 assistant event。
3. `incomplete`：断流、取消或协议错误后留下可见残片；它可以保留作诊断，但不能伪装为完成消息。

plain renderer 可以逐个合并块显示 provisional 文本，但开始处应有 request ID；结束、取消或断流时必须追加明确收口：

```text
[YACA request 42 | streaming]
I found the parser overwrite in...
[WARNING] request 42 incomplete: stream closed before a valid response end
```

刷新按时间片和字节阈值合并，遇到换行、工具调用边界、完成或错误立即 flush。具体毫秒/字节数字由 XP/CentOS 实测冻结，不应由本包凭感觉写死。

### native/raw 输入：保存、让路、恢复

当 yaca 真正拥有 draft buffer 时，任何异步块都采用同一事务式重绘动作：

```text
1. save prompt + draft + cursor position
2. move to a clean line
3. append one complete semantic block
4. render the current short status
5. restore prompt + exact draft + cursor position
```

例如用户已经输入但尚未提交：

```text
!> Also keep the old error code for compatibility_
```

工具状态到达后，屏幕应成为：

```text
[TOOL 13] patch | completed | 0.2s
changed: src\ini.lua
!> Also keep the old error code for compatibility_
```

draft 的字节、光标位置和输入动作不能因输出到达而改变。renderer 崩溃或 resize 时宁可退回新行重显，也不能清空用户输入或在旧字符上任意覆盖。

### cooked-line 后备：承认看不到 draft

在 `ReadConsole`/canonical line 由系统持有编辑缓冲时，yaca 不知道用户键入了什么，也就无法安全擦除再重画。推荐行为是：

1. 等待输入期间将高频 model/tool/status delta 有界合并到内存队列。
2. 不让异步字节穿过系统正在回显的输入行。
3. 用户提交一行后，先把该输入形成相应 main/queue/command 事件。
4. 再显示一条 `N updates buffered while editing`，按语义边界 flush；超出内存边界时合并状态而不是丢 canonical 事实。
5. 组合键用 `.steer`、`.side`、`.cancel`、显式 multiline 文本入口替代。

实际顺序示例：

```text
!> Add a regression test
[QUEUE 2] queued for the next turn
[STATUS] 4 updates were buffered while line input was active
[TOOL 13] patch | completed | 0.2s
[STATUS] validating related tests
!> _
```

代价是 cooked 用户在编辑一行时看不到逐 token 动画，但输入不会损坏，四个核心忙时动作仍可通过文本完成。这是诚实的能力降级。

## queue、steer、side、cancel 必须看得见“去了哪里”

四种输入不是同一个文本队列加不同颜色。每项至少有短 ID、所属 Context/turn、目标 request、创建序号和状态；UI 使用 XML/AgentLoop 的真实状态，不能按按键成功就提前宣布模型已经看到。

### 普通 Enter：idle 发送，busy 排到下一 turn

```text
!> Add a regression test
[QUEUE 2] queued | after turn 18 | items: 1
```

推荐提供：

```text
.queue list
.queue remove 2
.queue clear
.queue "Add a regression test"
```

未开始的 queue 在自动启动前必须可见、可删，并绑定原 Context；切换 Context 时不能跟着用户悄悄迁移。

### Ctrl+Enter / `.steer`：三态而不是假装立即生效

```text
!> Do not change the public error ID
[STEER 3] accepted | target request 42 | waiting for a safe injection point
[STEER 3] injected | next model sample for turn 18
```

若旧模型响应已经产生尚未执行的 tool calls，怎样 skipped、何时形成下一采样属于 AgentLoop；TUI 只显示 `accepted -> waiting -> injected/rejected/cancelled` 的真实转换。

### Alt+Enter / `.side`：独立、只读、不会暗改 main

```text
!> Why is the parser layer the right place?
[SIDE 4] running | snapshot turn 18 | read-only | no tools
[SIDE 4]
Because the later validator never sees the overwritten section. Rejecting it at
the input boundary preserves the original evidence.
[SIDE 4] completed | main task unchanged
```

side block必须带 ID 和 `main task unchanged`。它的回复作为 XML 事实保存，但是否进入 main 模型视图由 AgentLoop 契约决定，不能由颜色暗示。

### Esc / `.cancel`：cancel requested 不等于已经停止

```text
[STATUS] cancel requested | target tool 13
[TOOL 13] cancel-requested
[TOOL 13] unknown | process exit could not be confirmed
[WARNING] external side effects may have occurred; inspect before retry
```

推荐默认取消“当前最内层活动”：draft、side、model request、tool 或 approval。UI 必须显示实际 target；空闲且 draft 为空时 Esc 不应直接退出。精确层级和竞态由 AgentLoop/Runtime 包确认，文本后备是：

```text
.cancel request
.cancel tool 13
.cancel side 4
.cancel turn
.exit
```

不推荐把“双击 Esc 的时间窗口”作为规范协议：cooked 终端可能不交付 Esc，慢机也难稳定测试。若 enhanced 后端提供连续 Esc 快捷升级，它只能映射到同样的显式 cancel target，并在 help 中说明，不能改变默认安全结果。

## 输入、历史、粘贴和多行的完整后备

### 增强编辑能力与最低能力

native/raw editor 可以提供固定的 Left/Right、Home/End、Backspace/Delete、有限 Up/Down history 和 bracketed paste；这些是自动增强，不是完成任务的必要条件。cooked-line 只依赖系统可交付的一整行。

推荐共同不变量：

- 输入先做编码验证、NUL 拒绝、CRLF 规范化和有界大小检查；超限保留 draft 并给出实际大小/限制。
- 进程内 history 有界；API Key、审批答案、秘密字段和被取消的 secret draft 不入 history/补全。
- 已提交的普通用户消息本来就在 Context XML；`.history [count]` 从当前 Context 的规范事件追加显示，不另建 history 文件。
- 未提交 chat/Prompt draft 是否进入 XML 只服从 `F4-05`：A 为进程内，B 为 debounce session state，C 只在显式 `.draft save` 后写入。discard 后不再有效；若 B/C 已持久化，必须追加相应 clear/removal session-state 事实。已经提交的 main/queue/steer/side 是规范事实，不能为“清屏”而抹除。
- completion 只补全 registry 中当前 state 可用的命令/枚举，不读取 Key，不扫描任意文件内容；没有 completion 仍可完整输入命令。

### 普通粘贴不能在 cooked 终端被虚假保护

raw/bracketed-paste 能把带换行文本作为一个 draft；cooked 终端通常无法分辨“用户按 Enter”和“粘贴中自带换行”。因此 chat composer 的最低兼容入口必须是显式多行收集；下面样例投影 TU-19 A，不会因样例存在而自动确认。Prompt editor 的 delimiter/import/save/discard grammar 另由 PP-12 决定：

```text
.begin queue
Add these cases:
1. duplicate Model section
2. duplicate Permission section
..end
.end
```

TU-19 A 的候选 chat composer 语法：

- `.begin` 或 `.begin main`：收集普通 main 消息；结束时按 D-033 的正常 Enter 语义在 idle 时 send、busy 时 queue。
- `.begin queue|steer|side`：预先固定提交目的，避免粘贴完成后猜测；intent enum 仅为 `main|queue|steer|side`。
- 单独一行 `.end`：结束，显示提交目的/字节/行数，并在边界校验通过后提交。
- multiline 状态只把 `.end` 和 `.cancel draft` 当控制命令；其他行保持正文。`..end` 在正文中产生字面 `.end`。chat 普通单行仍用前置双点去掉一个点，例如 `..help` 发送 `.help`。
- `.cancel draft`：丢弃当前 multiline draft，不影响 active turn。

空行不能自动结束多行，因为 chat 正文和代码都可能合法包含空行。`Shift+Enter` 在 raw/native editor 中插入换行；它不能替代上述 cooked 后备。Prompt 正文怎样输入仍只看 PP-12，未提交 draft 的物理持久性仍只看 `F4-05`。

## 工具卡：一眼看方向，details 保留证据

工具不能只有 `running/done`，否则取消竞态、审批等待、未知副作用和被 steer 跳过都会丢失。推荐稳定词汇：

```text
accepted
validating
waiting-approval
running
cancel-requested
completed
failed
unknown
skipped
```

同一 tool ID 在追加式 transcript 中只在有意义的生命周期边界追加新卡；高频 stdout/progress 可由临时状态行合并。历史卡不回写：

```text
[TOOL 21] exec | accepted
command: lua55 tests\config.lua
cwd: C:\src\demo

[TOOL 21] exec | running | 1.2s
output: 12 tests completed...

[TOOL 21] exec | completed | exit 0 | 1.8s
stdout: 18 passed, 0 failed | shown 1/1 lines
event: tool-result:21
```

默认卡只显示规范工具名、主要目标、状态、耗时、退出/结果摘要、截断信息和 event ID。完整参数、stdout/stderr、digest、编码与 unknown 证据用统一入口追加：

```text
.details tool:21
```

这不是把完整输出藏在不可访问的折叠 UI；plain、40 列和 screen reader 都能取得相同 details。工具输出中的 ESC、OSC、C0/C1 和不可打印字节必须可见化，不能清屏、改标题、写剪贴板或伪造 `[ACTION]`。

## 审批：参数才是授权对象，Enter 默认 deny

审批状态使用独立 input grammar。自然语言不能既可能是“允许执行”，又可能是“给 Agent 的新消息”。普通 Enter 始终选择 `deny`；queue/steer/side/cancel 必须显式使用相应命令。

多个动作不能由一个模糊 `yes` 全批放行：

```text
[ACTION batch 8] 2 operations require a decision | default: deny

[ACTION 8.1]
tool: exec
command: del /q "C:\src\demo\tmp\cache.bin"
cwd: C:\src\demo
capability: delete
reason from model: remove generated cache before validation

[ACTION 8.2]
tool: exec
command: git status --short
cwd: C:\src\demo
capability: execute
reason from model: inspect changed files

action> allow 8.2 once
[ACTION 8.2] allowed once | bound to exact command/cwd snapshot
[ACTION 8.1] still waiting | Enter denies
```

推荐只接受完整动作 ID 和明确范围：

```text
allow 8.2 once
deny 8.1
details 8.1
```

不提供单字母 `a` 作为危险动作授权，也不根据模型“低风险”改变默认焦点。若命令/路径/host/参数在审批后改变，旧 allow 自动失效。模型 reason 可帮助理解，但不能代替规范参数、Permission 结果和 DoubleCheck verdict。

## Markdown、代码与 Git diff：增强可读性，不重写事实

推荐采用“保留原始块语义 + 基本颜色增强”，不实现浏览器式 Markdown 排版器：

- plain 保留标题字符、列表、blockquote 和 fenced code 原文。
- basic 只给完整行标题、inline code、代码 fence 和 diff 前缀基本色；不执行 HTML，不解释模型提供的 ANSI。
- Streaming 中只对已经闭合的行/fence 更新样式；未闭合部分保持 provisional，不回写历史字符。
- Markdown 表格在窄屏按原文软换行，不强制维持列，也不改写成另一份可能改变含义的表。
- 代码块不自动执行；语言标签只作文字。超长代码行由终端显示换行，XML/复制 details 仍引用原始文本。

Git diff 使用可复制的 unified diff，不做左右双栏：

```diff
[DIFF tool:34] src/ini.lua | 2 lines changed
--- a/src/ini.lua
+++ b/src/ini.lua
@@ -41,6 +41,7 @@
 local previous = sections[name]
+if previous then return duplicate_section(name, line_no) end
 sections[name] = current
[STATUS] diff shown 7/7 lines | event: tool-result:34
```

`+`/`-`/`@@` 可分别用 green/red/cyan，但无色信息完全相同。二进制变更只显示路径、旧/新大小、digest 和 `binary changed`，不把任意字节当文本染色。大型 diff 默认显示头尾/文件摘要和 `shown N/M`；审批所需的精确目标仍不能因摘要而消失。

## 错误与重试：先说真实影响，再说下一步

默认错误卡需要回答五件事：发生了什么、什么已经保存、可能有什么副作用、是否正在重试、用户下一步能做什么。技术 stack 不应淹没主 transcript，但必须能通过 ID 取得。

```text
[ERROR NET-TIMEOUT] Model request timed out after the configured deadline.
saved: user message, request start, 0 completed assistant messages
side effects: no tool call was accepted
retry: 2/3 in 4s | .retry now | .cancel request
details: .error NET-TIMEOUT or .details request:42
```

重试开始、等待、取消和耗尽各有真实状态：

```text
[STATUS] retry 2/3 waiting 4s | reason: transient connect timeout
[STATUS] retry 2/3 started | request 42.2
[ERROR NET-TIMEOUT] retries exhausted | waiting for user
```

同一根因只显示一次主错误；下层 cause 放 details。不能用 spinner 掩盖每次真实计费请求，也不能把 response 已开始后的整请求重发描述成“网络自动恢复”。具体哪些错误可重试由 Model/Network 配置决定，本包只固定可见性和取消入口。

## recovery：默认检查，不自动重放副作用

崩溃、断电或 writer 冲突后，恢复页首先说明最后 durable 事实和 unknown，而不是显示“继续”大按钮：

```text
[RECOVERY] context parser-fix [9f2a15c03d881e74]
last saved: turn 18, user message and tool 21 start
assistant: incomplete request 42
operation 21: unknown (process completion was not recorded)
queue: 1 item not started
damage: XML is valid through event 188

1  Inspect read-only
2  Start a corrective turn without replay
3  Remove unstarted queue items, then inspect
4  Abandon the unfinished turn (keep history)
5  Exit

Default: 1. No operation will be replayed automatically.
recovery> 1
```

显式 `--continue` 命中异常 Context、裸启动提示异常项、context-repl 打开恢复详情，都应投影同一 recovery controller；入口不同不能改变 unknown 的含义。损坏到无法安全打开时仍允许只读诊断/备份原件，不静默新建替代 XML。

启动前、配置尚未加载或 Context 尚未打开的致命错误只能写 stderr；在“只持久化 INI/XML”的约束下不能偷偷创建第三种永久日志文件。

## 三个 REPL 与 self-test 应像同一个产品

“共享导航”不等于把四个业务系统塞进一个巨大 menu。推荐共享一套 `LineBrowser` 语义：同样的 header、view generation、row ID、分页、search、details、back、refresh、help、quit 和 stale-selection 处理；每个 surface 再增加自己的动作。

### 共同导航词根

```text
help
list
show <row-id>
details <row-id-or-event-id>
search "text"
next
prev
refresh
back
quit
```

- 每次 list/search 结果带 view generation；屏幕行号只在该 generation 内稳定。
- refresh、搜索条件变化或外部文件变化后，旧 row ID 变 stale；open/rename/delete/save 前必须复核并要求重选。
- `back` 返回上一层/上一 view，并保留合理的搜索位置；有未保存草稿时先显示 `save/discard/stay`。
- `quit` 只退出当前 REPL；不会顺便关闭另一个正在运行的 yaca Context。
- 纯文本命令始终完整；能力足够时可提供固定方向键翻页/历史，但 help 不把它们当唯一入口。

### `model-repl` 样稿

```text
[YACA model-repl] view: models | gen: 17 | source: __yaca__\config.ini
ID     Name       Protocol          Model ID       Stream  State
17:1   Work       openai-compatible gpt-example    try     current
17:2   Long       openai-compatible long-example   force   enabled
17:3   Offline    openai-compatible local-example  off     disabled

Key values are hidden. Order 1 is the default for new Contexts.
Commands: show add edit test enable disable move delete refresh back quit
model> show 17:2
```

Model 专属动作在内存草稿上工作；静态校验、预览和确认后一次保存。列表不会打印 Key，删除当前/默认 Model 前必须显示对在途 turn 和“顺序即默认”的影响。

### `config-repl` 样稿

```text
[YACA config-repl] view: groups | gen: 8 | draft: none
ID    Group          Errors  Overrides  Restart
8:1   General        0       0          no
8:2   AgentLoop      0       2          no
8:3   Network        1       0          no
8:4   Exec           0       0          no
8:5   Permission     0       1          no
8:6   Context/TUI    0       3          no

Commands: open show edit reset validate diff save discard refresh back quit
config> open 8:3
```

详情显示 schema 类型、默认值、INI 值、Context XML 覆盖、effective value、来源和生效时点。Model section 只给摘要并跳转 model-repl，不在两个 surface 实现两套写入。

### `context-repl` 样稿

```text
[YACA context-repl] view: C:\Program Files | gen: 31 | page: 1/2
ID     Kind  Name             Hash              State
31:1   up    ..               -                 -
31:2   dir   project-a        -                 -
31:3   ctx   parser-fix       9f2a15c03d881e74  closed
31:4   ctx   upgrade-check    0d2a3e88aa021f10  recovery

Commands: open up root search show rename delete refresh next back quit
context> show 31:4
```

普通 search 只过滤名称、逻辑路径和精确 hash 元数据；不会因搜索唯一就自动连接，也不会每次按键读取全部 XML 正文。rename/delete/open 使用 controller 复核目标，不能把 stale 行号重新当 selector 搜索。

### self-test 样稿

```text
[YACA self-test] stage 1/3: static | completed
PASS  platform/package       8 checks
PASS  INI syntax/schema      42 checks
WARN  Model Long             ContextLength is not verified
FAIL  Model Work             RetryCount must be 0..10

Online checks have not started. No network request was made.
Commands: details fix-hint retry-static back quit
self-test> details Model:Work
```

修复静态错误后进入第二阶段时，页面先显示 endpoint、Model 数、预计请求数、可能费用/隐私并要求明确确认；每个 Model 有独立进度和结果。第三阶段 LLM advisory 与静态/连接 PASS/FAIL 分区显示，不能把“名字叫 Yolo 却只读”升级成硬错误。`retry-failed` 只重跑用户明确选择的阶段/Model。

## CLI command registry：名称、参数、TTY 和输出必须来自一份 schema

README、parser、help、completion、状态可用性和测试若分别手写，`-dc/-rc` 这类冲突一定会回来。推荐建立一个 registry，至少为每项冻结：

```text
canonical long name
unique short alias (if any)
primary action or modifier
positional/options grammar
mutual exclusions
TTY/input requirement
allowed app states
stdout/stderr class
exit class
deprecated aliases
```

### 推荐 A 的候选顶层 CLI（TU-18 A + TU-13 A 条件投影）

```text
yaca [global-options] [primary-action] [--] [directory]
```

| Primary action | 候选短名 | 用途 | TTY（仅投影 TU-13 A） |
| --- | --- | --- | --- |
| 无；`yaca [directory]` | - | 新建 chat；裸命令等于 `yaca .` | required |
| `--continue <selector>` | `-r` | 用统一 Resolver 恢复/resume | required |
| `--model-repl` | `-m` | 管理完整 Model 实例 | required |
| `--config-repl` | `-g` | 管理 general config；`g` 是命名代价 | required |
| `--context-repl` | `-c` | 管理 Context | required |
| `--self-test` | `-s` | 静态检查并可交互进入在线阶段 | no for static; TTY for prompts |
| `--help` | `-h` | 按当前 surface/主题显示帮助 | no |
| `--version` | `-V` | 版本/target/schema 摘要 | no |

同一次调用最多一个 primary action；`--continue` 不是可以与 `--model-repl` 混用的 modifier。长名/入口形态由 TU-18 独占，短名只由 TU-10 独占，TTY/stdin 可用性只由 TU-13 独占：上表的长名投影 TU-18 A，短名列投影 TU-10 A，TTY 列只是 TU-13 A 示例；若 TU-13 选择 B/C，必须由 registry 重新生成该列，不能把本表当作反向约束。正文不得再保留一套 `-x/-t/-c` 旧候选与正式组选项冲突。

`--` 明确结束 option parsing。宿主 shell 的引号只负责把含空格路径作为一个 argv；它不能阻止 `-project` 被 CLI 当 option，因此应写：

```text
yaca -- "-project"
yaca --continue "parser fix" -- "C:\Program Files\demo"
```

Windows `/x`、旧 README 混合长名和重复短名不作为首版正式 grammar；若以后保留兼容 alias，help 必须标 deprecated，且 alias 不能与规范名产生不同语义。

### Dot-command grammar

下面是 TU-18 A + TU-19 A 的推荐投影：TU-18 冻结 canonical root 和共享 lexical envelope；TU-19 只冻结 chat composer 的 main/queue/steer/side 正文、intent 参数、多行和点开头正文 grammar。其他 root 的可接受参数由各自领域 owner 决定，尤其 Prompt editor 只服从 PP-12；任何组合都不执行 shell expansion。

```text
message       := any line not beginning with ".", or ".." + literal-rest
dot-command   := "." command-name *(SP argument)
command-name  := lower-alpha *(lower-alpha | digit | "-")
argument      := bare | double-quoted
option-end    := "--"
```

- command name ASCII lowercase、大小写敏感；unknown command 只给一个最接近建议，不自动执行。
- whitespace 分隔 bare 参数；双引号组合空格。双引号内 `\"` 和 `\\` 可转义，其他 backslash 保持字面，因此 Windows path 不被 `\P` 误解析。这个 lexical envelope 不替任何领域 owner 发明 subcommand 或参数。
- 不做 `$VAR`、`%VAR%`、glob、command substitution、管道或重定向；raw shell 文本只存在专用 tool 参数中。
- 行首 `..hello` 发送字面 `.hello`；精确多行内容使用 `.begin ... .end`。
- `--` 结束 dot command 的 options，使以 `-` 开头的 selector/name 可安全传入。
- approval/recovery/REPL 是有明确 prompt 的子 grammar，命令不带点；chat 中相同 registry action 使用点前缀。

TU-18 A 的候选 chat command roots（`.end` 是 TU-19 的 multiline 终止 token，不是 idle chat root）：

```text
.help       .status      .details     .error       .history
.queue      .steer       .side        .cancel      .retry
.begin      .prompt      .cautious    .context     .model
.permission .exit
```

这是一组 TU-18 A baseline roots，不吞并其他正式 owner 的条件产物。例如只有 `F4-05 C` 被选择时，registry 才额外注册该组选项已经命名的 `.draft save`/`.draft discard` 动作；它的存在性和持久语义仍归 `F4-05`，TU-18 只负责把最终有效 root 纳入同一 parser/help/completion 冲突检查。

`.cautious` 推荐统一为 `show|on|off|toggle|reset`；无参数等于安全只读的 `show`。`.context` 无参数进入 context-repl，有 selector 调统一 Resolver。每个 root 的最终参数、简称与 state 表要由 registry 自动生成文档和冲突测试。

## command x state：命令不能交给 handler 临时猜

UI 至少要区分以下用户可感知状态：

```text
idle
main-request
tool-running
waiting-approval
finalizing/compacting
recovery
repl-draft
plan-ready (only PJ-11 B/C)
```

side-active 可以与 main-request/tool-running 正交存在，但仍有独立 ID 和 cancel。下表使用 TU-18 A 的 root 拼写展示推荐领域语义；若选择 TU-18 B/C，只替换 registry spelling，不改变 action ID 或 state result。`now` 表示控制器立即处理，`stage` 表示记录后在下一安全 turn 生效，`reject` 必须带原因和可用替代，而不是静默无效。

| 输入/命令 | idle | main-request | tool-running | approval | finalizing | recovery / REPL draft |
| --- | --- | --- | --- | --- | --- | --- |
| 普通文字 + Enter | start main | queue | queue | reject；用 `.queue` | queue | state-specific only |
| `.queue <text>` | add then scheduler may start | add | add | add without deciding action | add | recovery: manage old queue only |
| `.steer <text>` | reject；suggest send/queue | accept for safe point | accept, wait after tool fact | accept for later; approval unchanged | reject or queue | reject |
| `.side <text>` | start side | start side | start side | start side; approval unchanged | start if snapshot valid | recovery: reject until target opened |
| `.cancel [target]` | clear draft / no-op | request cancel | request cancel | cancel exact approval using AL06-35's selected synthetic result/continuation | request cancel | cancel draft or selected recovery action |
| `.status/.help/.details` | now | now | now | now | now | now |
| `.cautious/.prompt/.model/.permission` | next turn | stage next turn | stage next turn | cannot change pending decision | stage next turn | REPL uses own transaction |
| `.context <selector>` | switch after checks | stage, then resolve old work | reject until tool settles/cancels | deny/resolve action first | reject | context-repl handles selection |
| `.retry` | retry selected failed fact | reject duplicate active request | reject duplicate active tool | no | no | recovery requires explicit non-replay action |
| `.exit` / EOF | graceful close | cancel/close state machine | cancel/close with deadline | deny then close | close after durable result | prompt save/discard/exit |

表中的几个关键安全点：

- approval prompt 中普通 Enter 是 deny，不是 queue；要排队必须写 `.queue`，避免一行自然语言被当授权。
- `.steer` 在 tool-running 时只能等待安全注入点，不能修改已经审批/执行的参数。
- staged Model/Permission/DoubleCheck/Prompt 变更不能追溯改变当前 turn 或 pending approval。
- Context switch 不携带 queue/steer/side 到新 Context；原 Context 的未开始项保留、删除或收口必须明确。
- cancel 是请求，UI 等待最终 `completed/cancelled/failed/unknown`，不能先清掉卡片。
- busy EOF、窗口关闭和 Ctrl+C 的精确 deadline 属于 Runtime，但最终显示必须复用相同 typed close outcome。

PJ-11 B/C 启用时再投影两条条件 action，而不是偷偷变成常驻命令：`.plan <text>` 创建/重建 plan-phase main turn，`.execute <plan-id>` 只在 idle/plan-ready 且 artifact bindings 仍完全匹配时创建新的 execute turn。A 下 parser/help/completion 不注册二者。B 下普通文字仍走普通 main，只有显式 `.plan` 进入 plan；C 下普通新 main 自动走 plan phase，纯只读可直接完成，任何副作用必须停在 plan-ready 等 `.execute`。新的目标、Model/Permission/config/workspace/tool-schema 变化使旧 plan 显示 `stale`，不能靠确认继续；Esc/cancel 仍投影 AL06-35，不把 plan approval 当 Permission approval。

## chat chrome 与 `.status` 的信息层级

推荐首屏只用两三行核对身份：程序版本、Context 名/hash、Model、Permission、DoubleCheck effective value 和 cwd。没有 Context 时明确写 `new (not saved)`；不打印欢迎词、完整配置或整张快捷键表。

推荐短 prompt：

```text
>          idle; Enter starts main
!>         busy; Enter queues
action>    approval; Enter denies
...        multiline collection
model>     model-repl
config>    config-repl
context>   context-repl
self-test> self-test
recovery>  recovery
```

不默认打印时间戳；耗时、事件时间和 retry deadline 在相关卡/details 中显示。状态只在变化时追加，完整查询由 `.status` 固定顺序输出：

```text
[STATUS]
context: parser-fix
hash: 9f2a15c03d881e74
path: /C/Program Files/demo/parser-fix.xml
model: Work
permission: Std
double-check: on (Context override)
active: tool 13 running, turn 18
queue/side: 1 / 0
budget: steps 4/40, tokens 8120/64000
saved: event 188, clean
```

`.status` 的 hash 从当前 ContextHandle 最新逻辑路径实时计算，不扫描整棵树。活动 XML 外部移动/删除时显示 `stale`，不能继续展示一个看似有效的旧 hash 而不告警。

## 验收不是“截图看起来不错”

实现前推荐冻结两类独立 fixtures：

1. **Domain trace**：给定输入动作和事件，验证 queue/steer/side/cancel、approval、tool、retry、recovery 的状态/ID/持久化关系。
2. **Golden transcript**：把同一 semantic blocks 投影到 80x24 basic、40 列 plain、XP no-color、raw draft、cooked buffering、redirected output 和 error/recovery 页面。

至少包含：

- 三套视觉候选确认后保留规范样稿，删除未采用方案的实现承诺。
- Markdown fence 中断、混合文本/tool call、断流残片和大型 unified diff。
- 模型/工具输出含 CSI、OSC clipboard/title、C0/C1、超长行和伪 `[ACTION]`。
- 普通 paste 含换行、`.begin/.end`、字面 `.end`、点开头消息、引号、反斜杠和以 `-` 开头参数。
- draft 输入期间 tool/status 高频到达，resize，输出失败，Ctrl+C/EOF 和 best-effort terminal restore。
- 多 action 审批默认 deny、stale row ID、Context 外部变化、unknown operation recovery。
- 颜色完全关闭时每个状态仍有唯一文字；screen reader 顺序按块而非逐 token。

平台增强可以产生额外的颜色/光标控制快照，但必须先通过 plain semantic transcript。真实 XP x86 和 CentOS 7 上还要测输入事件、代码页、窄宽度、慢输出和取消；mockup 不能替代实机证据。

## 真正需要项目负责人回答的十九组问题

以下问题只在“单一、简单、append-only 的逐行 TUI”内选择体验细节，不再把 theme、vivid、全屏、鼠标、自定义快捷键或另一套业务语义列为选项。D033 的五种输入意图也已固定：Enter 排队、Ctrl+Enter 插队、Shift+Enter 换行、Alt+Enter 旁问、Esc 终止；旁问只读已提交会话事实，不能观察未提交 draft 或改变 main。这里仅决定这些意图怎样显示和怎样在弱终端降级。没有明确回复的编号继续保持待决；本文的推荐、样稿或代码块不会自动写入 `DECISIONS.md`。

### TU-01 单一逐行 transcript 的信息密度

- A：稀疏追加式；无框线，用稳定 ASCII 标签、空行和短状态形成层级。（推荐）
- B：仍是无框线逐行 transcript，但将 Model/状态/耗时等非秘密元数据压缩到每个块的单行 header，空行更少。
- C：仍是无框线逐行 transcript；对 TU-14 选定要显示的每个 block，默认用多行字段完整解释，减少紧凑 header。

推荐 A。它在 80x24 看起来清楚，在 40 列、XP 无色、重定向和 screen reader 中仍是同一份文本结构。B 更紧凑但容易形成 header 噪声；C 更明示但会在长任务中大量滚屏。三项都不重新引入框线、全屏或鼠标。

关联：`AQ-010`、`AQ-066` 至 `AQ-069`、`AQ-331`、`TUI-01`、`TUI-02`、`TUI-03`、`TUI-17`、`TUI-19`。

### TU-02 自动能力降级下采用哪种有限色彩策略

40 列改成单列、能力未知回到 plain、raw/cooked 后端保持同一语义均为共同前提；draft 保护由 TU-03 独立决定。

- A：能力明确时自动使用固定 8/16 色角色映射；无颜色时保留相同标签、选项和默认值。（推荐）
- B：能力明确时最多使用固定 8 色角色映射，不使用 16 色亮度差表达层级；无颜色时语义不变。
- C：正式 transcript 永远无色；raw 输入快捷键仍可在能力足够时使用，所有输出含义只由 ASCII 文字标签表达。

推荐 A。它满足“简单、基本颜色、老系统兼容”，又不把新终端降到最低能力。三项都不提供 mode/theme/vivid，也不改变 TU-03、TU-05 的输入安全与后备契约。

关联：`AQ-009`、`AQ-090`、`AQ-191`、`AQ-231`、`AQ-265`、`AQ-332`、`AQ-338` 至 `AQ-340`、`PLAT-05`、`PLAT-11`、`TUI-12` 至 `TUI-17`、`TUI-21`、`TUI-27`。

### TU-03 Streaming 到达时怎样保护 draft

- A：native/raw 保存并重绘准确 draft；cooked-line 有界合并异步块，用户提交后再 flush；assistant 明确 provisional/completed/incomplete。（推荐）
- B：所有后端都先缓冲为完整 semantic block 再追加；streaming 只更新不穿过 draft 的短 `STATUS`，正文完成后一次输出。
- C：raw 后端只在换行边界追加已完成片段并安全重绘 draft；cooked 后端缓冲正文，但仍周期性追加不覆盖输入的 `STATUS`。

推荐 A。它在能力允许时保留流式体验，在 cooked-line 中优先保证用户草稿完整。三项都禁止把 token 字节穿过 draft，也不把 incomplete 残片伪装成完成消息。

关联：`AQ-070`、`AQ-194`、`AQ-232`、`AQ-239`、`AQ-264`、`AQ-265`、`AQ-299`、`TUI-08`、`TUI-22`、`TUI-24`、`TUI-25`。

### TU-04 五种固定输入意图怎样显示结果

- A：Enter/Ctrl+Enter/Alt+Enter/Esc 产生带 ID、目标和真实状态的 receipt；Shift+Enter 只改变 draft。queue 显示 queued，steer 显示 waiting/injected，side 标明 read-only/main unchanged，cancel 从 requested 跟到真实终态。（推荐）
- B：五种意图不变，但每次只追加一行紧凑 receipt；完整状态通过 `.status`/details 查看。
- C：五种意图不变，每次 accepted/staged/injected/cancel-requested/final 变化都追加完整的多行状态块。

推荐 A。它能让用户看见消息到底去了下一 turn、当前 turn、旁问还是取消路径；Shift+Enter 不创建会话事件。代价是 AgentLoop 必须为异步输入提供稳定身份和状态。

关联：`AQ-024` 至 `AQ-027`、`AQ-086` 至 `AQ-089`、`AQ-182`、`AQ-234`、`AQ-301`、`AQ-302`、`AQ-359`、`LOOP-04` 至 `LOOP-08`、`TUI-04`、`TUI-06`。

### TU-05 五种输入意图在弱终端怎样后备

- A：能力足够时使用固定五种按键；cooked/不可识别组合键时，help 显示由 command registry 冻结的等价文字命令，多行使用显式 begin/end；raw 可增强有限 history 与 bracketed paste。（推荐）
- B：无论 raw 或 cooked，help 和 prompt 都同时显示按键与等价文字命令；用户始终可任选一种，能力只影响编辑反馈。
- C：raw 只实现五个固定按键和基本行编辑；cooked 提供相同五种意图的文字后备与 begin/end，不提供 history/bracketed-paste 增强。

推荐 A。新终端保持顺手，XP/SSH/cooked 仍能完成完全相同的领域动作。三项都保留 Enter/Ctrl+Enter/Shift+Enter/Alt+Enter/Esc 的语义，不因终端弱而删除旁问、多行或取消；秘密永不进入 history。

关联：`AQ-067`、`AQ-084`、`AQ-232`、`AQ-327`、`AQ-351` 至 `AQ-353`、`TUI-05`、`TUI-10`、`TUI-22`、`TUI-23`。

### TU-06 工具、Markdown、代码和 diff 默认显示多少

- A：工具显示生命周期、目标、耗时和有标记摘要，完整证据用 `.details`；Markdown 保留原文结构、代码不重排，Git 使用 unified diff；颜色只增强，控制序列可见化。（推荐）
- B：默认显示有界的规范参数与 stdout/stderr 头尾片段；Markdown 仍线性，Git 仍为 unified diff，超限部分以 digest/截断说明进入 details。
- C：主 transcript 只显示 lifecycle、目标、结果、digest 和截断状态；正文与完整 unified diff 通过 details 追加查看。

推荐 A。它平衡日常可读性与证据可追踪性；三项都保持线性文本、unified diff、明确截断和 canonical result，不引入双栏/fullscreen renderer。

关联：`AQ-071`、`AQ-072`、`AQ-125`、`AQ-190` 至 `AQ-192`、`AQ-231`、`AQ-300`、`AQ-333`、`TUI-09`、`TUI-14`、`TUI-25`。

### TU-07 审批默认与输入 grammar

- A：显示精确 action ID、tool/参数/cwd/目标/capability/reason；Enter 默认 deny，显式 `allow <id> once`、`deny <id>`、`details <id>`，多调用逐项决定。（推荐）
- B：Enter 不选择任何结果并重新显示短提示；必须显式输入 allow/deny，details 可随时查看。
- C：显示编号化的 allow once/deny/details 选择，默认光标停在 deny；plain/cooked 中仍要求输入完整编号并回显目标。

推荐 A。误按 Enter 不会产生副作用，也不会把模型摘要当授权对象。参数编辑后的失效规则由 TU-17 单独决定，本组只拥有审批输入和默认项。

关联：`AQ-073`、`AQ-225`、`AQ-233`、`AQ-281`、`AQ-335`、`SAFE-03`、`SAFE-07`、`TUI-05`。

### TU-08 错误、retry 和 recovery 的下一步动作怎样输入

ED 包独占 error 字段、cause 保存、retry 可见度和 details 展开策略；本组只决定逐行 TUI 如何让用户选择已经由领域层提供的 typed next actions。

- A：错误卡后追加 ASCII verb 列表，例如 `retry`、`details`、`recover`、`exit`；同时有多个对象时必须带 event/action ID。（推荐）
- B：错误卡后追加稳定编号列表，用户输入完整编号；执行前回显规范动作和目标，编号只对当前 view generation 有效。
- C：进入独立的 `recovery>`/`error>` 行提示，列出可用 verbs；返回 transcript 后追加选择 receipt，不使用全屏菜单。

推荐 A。它在 plain/cooked 中最容易复制和理解，也不会为错误系统发明第二套页面。三项都只投影领域层已允许的动作，默认 recovery 仍只读，unknown operation 不自动重放，canonical error/cause 仍完整保存在 XML。

关联：`AQ-074`、`AQ-201`、`AQ-203`、`AQ-229`、`AQ-230`、`AQ-314` 至 `AQ-316`、`AQ-328`、`AQ-334`、`AQ-356`、`DIAG-03`、`DIAG-04`、`DIAG-10`、`TUI-18`。

### REPL 导航内核（原 TU-09；技术证明投影，无需回复）

model/config/context REPL 与 self-test 已确认是四个独立逐行 surface；负责人真正需要决定的是各自的页面动作、事务和文案，而不是 Lua 控制器复用多少代码。实现侧应优先共享 line-browser、view generation、stable row ID、help/search/details/back/refresh/quit 等无领域含义的 primitives；若旧平台约束要求拆分控制器，也必须保持同一 action token、typed error、stale-selection、save/discard/back 语义和跨表面 trace。业务 mutation、验证和事务仍由各 subsystem 独占。

这是一项 `TP-024`/`TP-026` 的实现与一致性证明，不计入正式回复模板，也不能把七个已确认 surface 合并成全屏 settings 应用。关联：`AQ-011` 至 `AQ-015`、`AQ-075` 至 `AQ-085`、`AQ-181`、`AQ-326`、`AQ-336`、`AQ-337`、`AQ-354`、`AQ-355`、`CLI-08`、`TUI-11`、`TUI-26`、`TP-024`、`TP-026`。

### TU-10 规范命令已经固定后，简称采用什么政策

canonical 顶层形态与 dot roots 由 TU-18 管理；本组只为对应的语义 action 分配短名，不能改长名、增删 action、改变 dot grammar 或产生冲突简称。

- A：冻结精确短名：`-m` = Model management、`-g` = general config management、`-c` = Context management、`-s` = self-test、`-r` = continue/resume、`-h` = help、`-V` = version；它们展开为 TU-18 选定的 canonical action，其他入口只有规范长名，未来命令不得复用。（推荐）
- B：v0.1 不提供任何短名，help 和脚本一律使用规范长名。
- C：registry 为规范长名生成“最短唯一 ASCII 前缀（至少两字符）”；一旦随 schema 发布即永久冻结，未来碰撞命令不改变旧 alias，只能没有 alias。

推荐 A。它把唯一性和记忆成本一次冻结，不留给实现期凭感觉挑简称；`-g` 取自 confiG，help 必须明确显示。dot grammar 由 TU-19 决定；本组不创建第二套规范命名体系。

关联：`AQ-014`、`AQ-076`、`AQ-135`、`AQ-181`、`AQ-182`、`AQ-214`、`AQ-248`、`AQ-326`、`AQ-327`、`CLI-01`、`CLI-04`、`CLI-10`、`CLI-12`。

### TU-11 非 composer command x AgentState 结果怎样反馈

除 TU-04 已拥有的五种 chat composer 意图外，每个管理/dot command 在 idle/request/tool/approval/finalizing/recovery/REPL-draft 中的 now/stage/queue/reject/cancel-first 结果必须先由统一矩阵决定；本组只决定 TUI 怎样显示这个既定结果。

- A：立即追加带 command ID、结果、目标状态和理由的 receipt；staged/queued 再在真正执行或失效时追加终态。（推荐）
- B：立即追加单行 `command -> result`；完整理由和目标状态通过 details 查看，终态仍必须追加。
- C：now 只追加一行，staged/queued/rejected/cancel-first 使用两行 `ACTION/WHY` 块；终态仍必须追加。

推荐 A。用户不会把“已接收”误解为“已执行”，且弱终端看到同一事实。五种固定输入意图继续服从 D033；本组不能把忙时行为统一改成 queue，也不能由 handler 临时猜。

关联：`AQ-031`、`AQ-098`、`AQ-107`、`AQ-233`、`AQ-234`、`AQ-301`、`AQ-302`、`CLI-11`、`LOOP-04`、`TUI-04`、`TUI-06`。

### Transcript/降级证据（原 TU-12；技术证明投影，无需回复）

页面风格、旧终端兼容和状态正确性必须留下可重复证据，这不是可放弃的产品偏好。每个主要 surface、AgentState、失败、审批、恢复、输入状态和降级路径至少要有 normalized plain ASCII golden anchor 与完整 domain event trace；稳定文案冻结后，可对关键页面使用逐字 golden，其余场景允许去除计时、终端宽度等明确易变字段后比较。平台增强不得改变 semantic action/default/result，截图或 controller 单测不能替代 XP/CentOS 实机证据。

具体 fixture 组织由测试架构决定，`TP-023`/`TP-024` 负责证明，不计入正式回复模板。关联：`AQ-194`、`AQ-205`、`AQ-264`、`AQ-299`、`AQ-331`、`AQ-343`、`AQ-360`、`LOOP-26`、`TEST-04`、`TEST-07`、`TEST-10`、`TUI-19`、`TP-023`、`TP-024`。

### TU-13 非 TTY 能力范围与 stdin 所有权

问题：当 yaca 被 pipe、CI 或另一个进程调用时，哪些功能可以在没有 TTY 的情况下运行，stdin 如何避免同时被当作正文、秘密和审批？机器输出编码由 TU-21 独立决定，本组不绑定 JSON、JSONL 或文本格式。

共同边界：非 TTY 的 stdin 不自动成为 chat、Key、审批答案或 self-test consent。只有某个 registry action 未来显式声明 `--input=-` 才能取得一次唯一所有权；下列 v0.1 action 都不读取 stdin，EOF 也不能被解释成默认同意。

- A：v0.1 主 Agent 交互要求 TTY；非 TTY 只运行 help/version 与显式 `--self-test --static`，不开放其他 Context/Model 查询；需要菜单、审批、秘密、写入或缺参时 fail-closed。（推荐）
- B：非 TTY 只支持 help/version；其他入口即使只读也返回 typed `non-tty-unsupported`，不启动菜单或读取 stdin。
- C：非 TTY 支持 help/version 和完整三阶段 self-test；在线/LLM 阶段必须由显式 `--online`/`--llm-review` 参数选择并预先给定 Model 范围，绝不从 stdin 询问或默认同意费用；仍不提供 Agent、Context 查询、审批或写入能力。

推荐 A。它保留安全的诊断与只读自动化，同时不为 v0.1 引入 batch Agent；B 的非 TTY 面最小；C 允许显式在线自动化，但必须承担费用/隐私参数和 CI 凭据边界。三项都不从 stdin 猜正文、秘密或审批用途；broken pipe 必须映射为安全 close，不能把未知副作用标为成功。

关联：`CLI-02`、`CLI-03`、`CLI-05`、`CLI-06`、`CLI-09`、`CLI-13`、`CLI-14`、`CLI-15`、`AQ-247`、`AQ-320`。

确认后 owner artifact：`13-cli.md` 中的 command x TTY matrix、stdin single-owner grammar、非 TTY 允许动作和 broken-pipe/EOF 收口表；stdout/stderr payload 契约由 TU-21 归档。

### TU-14 哪些状态在逐行 transcript 中显示

- A：不放常驻状态栏；状态变化时追加短 `STATUS`。`.status` 按 `name/hash/path/Model/Permission/DoubleCheck/activity/budget/save` 固定顺序输出。（推荐）
- B：每个 request/tool/approval/finalizing 生命周期块结束后追加一行紧凑状态；其他字段由 `.status` 展开。
- C：日常状态只在显式 `.status` 时显示；`ACTION REQUIRED`、`WARNING`、`ERROR` 和保存失败仍必须主动追加。

推荐 A。它让关键变化可见又不在旧终端反复重绘。三项都使用 append-only 输出、固定 `.status` 字段和同一 domain snapshot；renderer 不得自由改变字段含义或顺序。

关联：`AQ-193`、`TUI-07`。

### TU-15 Context 管理采用哪种编辑确认流程

`.prompt` 的 show/set/import/reset、draft 与生效边界只由 PP-12 选择，本组不再重复。Context 动作的稳定规范名、通用 Resolver、typed selector result 和领域 lifecycle 由 CX 包提供；本组只决定 rename/archive/delete/restore/purge 等管理动作怎样进入逐行确认体验。

- A：chat/context-repl 的显式动作显示稳定目标、影响/引用、old/new 预览和 confirm，完成后追加逐目标结果。（推荐）
- B：非破坏 Context 修改先进入 draft，统一用 save/discard/back；delete/purge 另用带规范目标名称和影响清单的独立确认，不混入 draft save。
- C：chat 内 Context 修改命令只打开 context-repl 的预选动作；所有预览/确认在 REPL 中提交，仍使用同一规范动作和 Resolver observation credential。

推荐 A。常用重命名/归档路径短，又保留完整预览。三项都不能自行解析 selector、自动接受模糊命中或用临时行号代替稳定目标；PP-12 的 Prompt 流程只共享已选 renderer primitives，不被本组改变。

关联：`AQ-117`、`AQ-118`、`AQ-178`、`AQ-237`、`AQ-308`、`CLI-07`、`INDEX-15`、PP-12。

### TU-16 异步事件怎样在 append-only transcript 中交错

- A：单一 event sequencer 只追加完整 semantic block，并按 durable sequence 排序；很长的 assistant 流按编号 `ASSISTANT PART` 分块，其他事件只能出现在块边界。（推荐）
- B：当前可见块完成前，其他输出先进入有界队列；输入和取消仍立即被状态机接收，块结束后按 sequence 追加 receipt。
- C：允许高优先级的一行 receipt 插入 assistant 的换行边界；每条 lane 带稳定 ID，lane 内顺序与 durable sequence 都可重建。

推荐 A。它最容易阅读、复制和由其他 Agent 接盘，又不会让慢 stream 阻塞 cancel。所有选项都禁止字符级交错、原地改写旧块和无界 UI 队列；canonical XML 顺序不由屏幕刷新时机决定。

关联：`TUI-08`、`TUI-24`、`CONC-02`、`CONC-04`、`CTX-07`。

### TU-17 审批后参数被编辑时怎样使旧授权失效

- A：审批 prompt 本身只读；Agent/runtime 提交的 canonical tool、参数、cwd、目标、capability 或 expected digest 任一变化，旧 action ID 立即标为 superseded，并呈现新 action ID 重新审批。（推荐）
- B：允许用户在审批界面编辑参数，但每次编辑都生成新 action ID 和新预览；旧批准永不继承，新 action 必须显式批准。
- C：审批 prompt 只读且不自动接受修订；用户必须先 deny 并把修改要求发回 Agent，经过新的模型步骤生成新 action ID 后再进入完整审批。

推荐 A。授权对象始终是精确 canonical action，而不是一句摘要。三项都禁止“只改一点所以沿用批准”；若 action 执行前文件 digest 已变化，同样按新事实重新评估。

关联：`SAFE-03`、`SAFE-07`、`TOOL-07`、`AQ-281`、`AQ-335`。

### TU-18 canonical 顶层 CLI 与 dot-command registry

本组独占规范长名、baseline action 集合、dot root 拼写和共享 lexical envelope；TU-10 只决定这些 action 是否有短名，TU-19 只决定 chat composer 的 main/queue/steer/side 正文、多行和字面点转义，command x state 仍由领域矩阵决定。Prompt editor 的内部 grammar 由 PP-12 独占；其他正式 owner 明确要求的条件 root（当前包括 `F4-05 C` 的 `.draft`，以及 `PJ-11 B/C` 的 `.plan/.execute`）只在条件成立时加入同一 registry，存在性和领域语义仍归原 owner。三项都由一份版本化 registry 生成 parser/help/completion/tests，未知命令不自动执行。

- A：顶层使用 primary flags：`yaca [directory]`、`--continue`、`--model-repl`、`--config-repl`、`--context-repl`、`--self-test`、`--help`、`--version`；chat 使用平坦 roots：`.help/.status/.details/.error/.history/.queue/.steer/.side/.cancel/.retry/.begin/.prompt/.cautious/.context/.model/.permission/.exit`。（推荐）
- B：顶层改用 subcommands：`yaca [directory]`、`yaca continue`、`yaca model-repl`、`yaca config-repl`、`yaca context-repl`、`yaca self-test`、`yaca help/version`；chat 继续使用 A 的平坦 roots。目录 basename 与 subcommand 冲突时必须用 `yaca -- <directory>`。
- C：顶层保持 A 的 primary flags；chat 保留已约定的 `.status/.prompt/.cautious` 及高频 `.queue/.steer/.side/.cancel/.begin/.context/.retry/.exit/.help`，将 `.details/.error/.history` 合并为 `.show <target>`，将 `.model/.permission` 合并为 `.use model|permission`。

推荐 A。它最接近 Lua 风格的直接、小型命令面，也让最常用动作无需额外层级；B 对熟悉 subcommand CLI 的用户更自然，但会占用潜在目录名；C 缩小 root 数量，却增加二级 verb 和 help 查找成本。确认任一方案后，未选名称不得作为无文档兼容入口残留；deprecated alias 只能显式登记、显示且不能拥有不同语义。

关联：`CLI-00` 至 `CLI-04`、`CLI-10` 至 `CLI-13`、`AQ-014`、`AQ-076`、`AQ-135`、`AQ-181`、`AQ-182`、`AQ-214`、`AQ-248`、`AQ-326`、`AQ-327`、`TP-024`。

### TU-19 chat composer 的 multiline、intent 参数与点开头正文 grammar

本组只拥有 chat composer 的 `main|queue|steer|side`：cooked-line 下怎样收集这些消息的多行、怎样发送字面 dot-command，以及 composer intent 的 bare/double-quoted/`--` 边界；TU-18 提供 command roots 和共享 lexical envelope。它不拥有 `.prompt` 的 editor/delimiter/import/save/discard grammar，也不拥有 context/model/config REPL 的内部命令。所有选项都拒绝 NUL、做有界 UTF-8/CRLF 校验，不执行 shell expansion，Shift+Enter 在 raw/native editor 中仍只向 chat draft 插入换行。

- A：单行 `..text` 去掉一个前导点；`.begin [main|queue|steer|side]` 开始多行，省略 intent 等于 `main`，精确 `.end` 提交，`..end` 产生字面 `.end`，`.cancel draft` 丢弃；composer 参数支持 bare、double-quoted（仅 `\"`/`\\` 转义）和 `--`。（推荐）
- B：单行仍用 `..text`；多行由 `.begin [main|queue|steer|side] --until <ASCII-token>` 选择本次终止行，省略 intent 等于 `main`，除精确 token 外所有行完全按正文保存，不再解释 dot-command；composer 参数仍为 bare/double-quoted/`--`。
- C：单行仍用 `..text`；多行由 `.begin [main|queue|steer|side] --lines <positive-integer>` 声明随后精确行数，省略 intent 等于 `main`，读满后在 composer substate 预览行数/字节并用 bare `send|discard` 提交或丢弃，不注册新的 idle chat root；composer 参数仍为 bare/double-quoted/`--`。

推荐 A。固定终止标记最短、help 最容易解释，双点转义也覆盖字面 `.end`；B 更适合粘贴大量以点开头的内容，但用户必须选择不碰撞 token；C 没有终止标记碰撞，却容易因行数数错进入恢复提示。任何方案都必须在进入 multiline 时冻结 intent，空行不是结束，EOF/超限保留或丢弃 draft 的结果必须明确，普通 paste 不能被虚假宣称为 bracketed paste。

未提交 composer/Prompt draft 的持久性只由 `F4-05` 决定；若选择 B/C，本组的 discard 动作必须清除相应 session state，但不能删除已提交输入。若 `F4-05 C` 条件注册 `.draft save`，它只改变 session-state 持久性，不改变本组的提交 intent 或 PP-12 的 Prompt commit。Prompt editor 的完整语法继续由 PP-12 决定。

关联：`CLI-04`、`CLI-12`、`AQ-084`、`AQ-182`、`AQ-232`、`AQ-327`、`AQ-351` 至 `AQ-353`、`TUI-05`、`TUI-10`、`TUI-22`、`TUI-23`、`TP-024`、`D-033`、`F4-05`、`PP-12`。

### TU-20 TranscriptChrome：标签、提示符和块头采用哪套固定词汇

TU-01 只拥有留白/密度，TU-14 独占 `STATUS` 是否以及何时发射，TU-16 只拥有异步块排序；本组只拥有已经决定显示的同一 semantic block 的稳定 ASCII chrome、label 和输入提示符拼写。颜色、宽度和 renderer 降级不得改变所选 label，也不能让模型/工具正文伪造程序 chrome；TU-20 的任一选项都可与 TU-14 的任一选项组合。

- A：方括号全词标签：`[USER]`、`[ASSISTANT]`、`[TOOL 21]`、`[SIDE 4]`、`[STATUS]`、`[WARNING]`、`[ERROR]`、`[ACTION 8.1]`；输入提示符使用 `>`、`!>`、`action>`、`...`、`model>`、`config>`、`context>`、`self-test>`、`recovery>`。（推荐）
- B：紧凑前缀：`U>`、`A>`、`T#21>`、`S#4>`、`STATUS>`、`WARN>`、`ERROR>`、`ACTION#8.1>`；所有输入提示符都用 `<surface-or-state>>` 全词，例如 `idle>`、`busy>`、`action>`、`context>`。
- C：冒号式全词块头：`USER:`、`ASSISTANT:`、`TOOL 21:`、`SIDE 4:`、`STATUS:`、`WARNING:`、`ERROR:`、`ACTION 8.1:`；输入提示符统一拼写为 `yaca>`。是否在提示前、状态变化时或仅显式 `.status` 时发射 `STATUS:`，完全由 TU-14 决定。

推荐 A。全词标签在无色、40 列、复制文本和 screen reader 中仍容易区分，短提示符又不会重复滚屏；B 最省列宽但需要学习缩写；C 最像普通日志、提示符也最统一，但焦点/state 的可见性更依赖 TU-14 所选状态策略。所有方案都保留稳定 ID、正文转义、程序 chrome 与 canonical XML 事实分离，并为无颜色环境提供完整语义；本组不会增加或减少任何 `STATUS` 事件。

关联：`AQ-010`、`AQ-066` 至 `AQ-069`、`AQ-190`、`AQ-193`、`AQ-231`、`AQ-300`、`AQ-331`、`TUI-01` 至 `TUI-03`、`TUI-07`、`TUI-17`、`TUI-19`、`TP-023`。

### TU-21 非 TTY machine output 的格式与流式边界

TU-13 只决定哪些 action 可在非 TTY 运行、stdin 归谁；本组只决定已允许 action 的 stdout/stderr payload。三项都固定 UTF-8、ASCII field names、稳定 schema/exit class，stdout 只有机器数据，stderr 只有安全诊断；human transcript 不是机器协议，broken pipe 不能被报告为成功。

- A：单结果使用带 `schema_version`/`kind` 的 JSON document；可能产生多条独立结果或进度的 action 使用 JSONL，每行自足、带 sequence/final，最后一条给 typed outcome。（推荐）
- B：所有 action 都只输出一个版本化 JSON document；进度不写 stdout，多个结果在有界数组中，无法在上限内缓冲就以稳定 resource-limit exit 失败。
- C：使用版本化 UTF-8 tab-separated records：首列 ASCII record kind，后续字段为 `ASCII-name=JSON-string`；重复 record 表示流，最终必须有 `outcome` record，不支持任意嵌套对象。

推荐 A。JSON 适合一次性查询，JSONL 又能让 self-test/列表按条消费而不等待全量；B 的解析面最小但需要缓冲；C 在老脚本和逐行工具中直接，却更难表达嵌套诊断。任何方案都必须为 unknown/deprecated 字段、partial stream、stderr、exit class 和 schema mismatch 提供确定规则，且不把 Key、ANSI 或本应遮蔽的正文带入诊断。

关联：`CLI-02`、`CLI-03`、`CLI-05`、`CLI-06`、`CLI-09`、`CLI-14`、`CLI-15`、`AQ-247`、`AQ-320`、`TP-024`。

### 完整推荐回复模板

```text
TU-01 A
TU-02 A
TU-03 A
TU-04 A
TU-05 A
TU-06 A
TU-07 A
TU-08 A
TU-10 A
TU-11 A
TU-13 A
TU-14 A
TU-15 A
TU-16 A
TU-17 A
TU-18 A
TU-19 A
TU-20 A
TU-21 A
```

## 本包确认后的归档产物

负责人回复后，只把明确选择分别归档到：

- `DECISIONS.md`：视觉密度、自动降级、输入后备、审批默认、canonical registry、TranscriptChrome、异步交错、授权失效和 machine output 总决定。
- `14-tui.md`：semantic blocks、固定标签/prompt、颜色、40 列、draft、工具/错误/recovery 的详细体验契约。
- `13-cli.md`：canonical command registry、顶层/multiline/dot grammar、唯一简称、TTY、stdout/stderr、machine schema 和 exit class。
- `09-agent-session.md`：command x state 和 queue/steer/side/cancel 的领域动作；不复制视觉样式。
- `11-context-indexing.md`：context-repl 的目录树、stable selection、搜索与复核；不复制通用 LineBrowser 实现。
- `15-diagnostics-and-logging.md`：error/retry/self-test/recovery 的事实来源和 details。
- `20-testing-and-agent-evaluation.md`：domain trace、golden transcript、控制序列注入和实机矩阵。

未回答的 TU 条目继续保持待决；没有选择 TU-01 前，不应先冻结 transcript 密度和标签样稿再让负责人从已实现成本中被迫选择。

## 完成标准

本包确认后，下面每个问题都应有唯一答案：

1. 同一 chat 在 80x24、40 列和 XP 无色时分别长什么样，语义是否完全相同。
2. 用户正在输入时，stream/tool/status 到达会不会破坏 draft。
3. cooked-line 为什么看不到未提交 draft，又怎样保留全部核心动作。
4. Enter queue、Ctrl+Enter steer、Shift+Enter newline、Alt+Enter side 和 Esc cancel 的意图、ID 与真实状态怎样显示。
5. 普通 paste、多行代码、字面 `.end` 和点开头消息怎样安全提交。
6. tool call 从 accepted 到 unknown 怎样展示，完整输出在哪里看。
7. 多动作审批中普通 Enter 做什么，授权究竟绑定什么参数。
8. Markdown、代码、unified diff、二进制和控制序列怎样降级。
9. 网络重试、错误耗尽和 unknown operation recovery 分别告诉用户什么。
10. model/config/context REPL 与 self-test 的共同导航语义怎样证明一致，同时保持各自领域事务独立。
11. canonical 顶层 action、dot root 和唯一短名分别是什么，未来怎样避免碰撞。
12. `--`、双引号、多行、终止标记和点开头普通正文的唯一 grammar 是什么。
13. 任一 command 在每个 AgentState 中是立即、stage、queue、拒绝还是先取消。
14. 哪些 golden transcript、domain trace 和 XP/CentOS 实机证据允许实现被称为完成。
15. `.status` 何时主动出现、字段顺序是什么。
16. Prompt/Context 修改怎样预览、确认并复用同一 Resolver。
17. stream、tool、receipt 与 cancel 怎样在 append-only transcript 中交错而不破坏 durable 顺序。
18. action 参数、cwd、目标、capability 或 digest 变化后，旧批准怎样失效并形成新 action ID。
19. USER/ASSISTANT/TOOL/ACTION 等 chrome 和输入提示符使用哪套固定 ASCII 词汇。
20. 非 TTY 能运行哪些 action，stdin 的唯一用途怎样声明。
21. 非 TTY 的机器输出使用 JSON/JSONL、单 JSON 还是行记录，partial/broken pipe 怎样收口。
