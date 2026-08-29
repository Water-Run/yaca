# 14 兼容 TUI

更新日期：2026-08-29

状态：规范逐行界面、输入后备与 Context 浏览器语义已确认；[`contracts/tui.lua`](../contracts/tui.lua) 已冻结提示符、输入状态与 action fallback；完整 ASCII transcript 和真实旧终端渲染仍待 proof

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
- 程序生成的 slogan、标签、提示符、命令和机器字段只用 ASCII。路径、Context 名和用户/模型正文仍是 Unicode 用户数据，内部与 XML 使用严格 UTF-8。
- Windows TTY 输入输出和 argv/path 边界必须使用 wide API，再与内部 UTF-8 转换；不能用当前 ANSI code page 改写用户数据。字体或终端无法显示时可输出 ASCII escape，但选择、hash、审批和文件操作继续使用未替换的真实身份。

## 已确认的固定输入意图与兼容边界

项目负责人已给出主输入意图：空闲或忙时普通 `Enter` 发送/排队，`Ctrl+Enter` steer 当前工作，`Shift+Enter` 输入换行，`Alt+Enter` 发起一次只读旁问，`Esc` 终止。语义已确定方向，精确取消层级和旁问并发/持久化仍由 AgentLoop 决定。

这些组合键不能作为所有终端唯一入口。Windows 的 `KEY_EVENT_RECORD` 可以携带虚拟键与 modifier 状态，但 cooked `ReadConsole` 会由系统处理回车和控制键；POSIX canonical mode 只按完整行交付输入；xterm 的 modified-key 编码也是可选能力而非普遍默认。参考：[Windows console modes](https://learn.microsoft.com/en-us/windows/console/high-level-console-modes)、[KEY_EVENT_RECORD](https://learn.microsoft.com/en-us/windows/console/key-event-record-str)、[POSIX terminal interface](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap11.html)、[xterm modified keys](https://invisible-island.net/xterm/modified-keys.html)。

因此已确认契约是：

- 能力足够时由原生/raw 输入后端识别上述固定快捷键。
- cooked line、`TERM=dumb`、SSH/终端不报告 modifier 或重定向时，所有语义都有固定 ASCII 文本入口：`.queue`、`.immediate`、`.side`、`.multiline` 和 `.cancel`。
- 后备入口不是另一种产品模式；它提交与快捷键相同的领域动作，XML、权限、预算和结果完全一致。
- help 只列出当前环境实际可用的按键及其固定文本等价入口，不允许重新绑定。

固定映射如下：

| 用户意图 | 快捷键 | ASCII 点命令 |
| --- | --- | --- |
| 忙时排队 | 普通 `Enter` | `.queue <message>` |
| 查看/删除/排序/编辑/清空待执行队列 | 无 | `.queue list\|delete\|move\|edit\|clear`（条目 `#N`，上限默认 9，见 D-066） |
| 插队/steer 当前工作 | `Ctrl+Enter` | `.immediate <message>` |
| 发起一次只读旁问 | `Alt+Enter` | `.side <message>` |
| 输入多行消息 | `Shift+Enter` | `.multiline` |
| 取消当前最内层可取消活动 | `Esc` | `.cancel` |

`.immediate` 是正式拼写，不保留 `.immidiate`。队列条目标识、move/edit 参数和多行结束 delimiter 仍由各自 grammar 冻结；renderer 不得用这些未决细节创造另一组动作。

## 当前设计缺口

现有规则已经是一份较完整的旧终端兼容基线，但还不是 TUI 体验设计。至少还缺少：

- 启动、恢复、待输入、模型生成、工具调用、等待确认、重试、取消、压缩、失败和退出的界面状态。
- 用户、Agent、工具、状态、警告、错误和确认在无颜色 transcript 中的稳定文本语法。
- 状态是常驻区域、可更新的一行、每次变化追加一行，还是只由 `.status` 查询。
- Ctrl+C、EOF 与 broken-pipe 的退出/取消边界；排队、steer、旁问和多行的核心入口已经冻结。
- 长路径、长命令、工具输出、CJK、控制字符和 terminal injection 的处理。
- Model picker 的分页/挤占细节，以及 Permission/Context 选择器、配置编辑器和确认框的编号、分页、取消与默认项。
- 自动能力降级、原生 Windows 颜色与基本终端颜色如何保持相同文字语义。

旧草案的 `DotCommandCompletion=true` 与“不要求 raw mode、方向键或 ANSI”并不天然兼容；目标 schema 不保留这个用户开关，若平台以后证明可以提供 completion，它也只能是自动增强，不能成为普通点命令可用性的前提。旧 `CheckModelOnStart=true` 同样退出目标 schema：启动、help、配置管理和 Context 浏览不隐式联网，真实连接检查只从显式 self-test/用户动作进入并可取消。

## 上游给出的简洁启动头常量

负责人最新答复要求启动头保持短小，只由逐字段开关投影以下字段，不存在总开关；每个启用字段独占一行并从行首开始，顺序固定为：Slogan、version、work directory、data root、config status、Context、当前实时 hash、Model、Permission、DoubleCheck、`.status` 提示。固定 Slogan 是：

```text
yaca: Yet Another Coding Agent.
```

隐藏某个字段只改变本次启动 chrome，不删除状态事实，也不改变 `.status`、XML 或错误诊断。错误、warning 和 action-required 永远不能被逐字段开关隐藏；配置、help 和 renderer 都不得重新引入 `StartupHeader`、`ShowStartupHeader` 或等价 master。这里不增加 theme、vivid、mode 或第二套 renderer。

输入提示符已由 **D-064 / SQ-07** 冻结：

| 焦点 | 提示符 | 可选基础色（增强） |
| --- | --- | --- |
| chat | `>>` | 浅色/暗淡 |
| 审批/确认 | `??` | Yellow |
| model-repl | `model>` | Green |
| config-repl | `config>` | Cyan |
| context-repl | `context>` | Blue |
| self-test 交互 | `test>` | Magenta |

无色与 `NO_COLOR` 时仅 ASCII 提示符。颜色不得作为唯一焦点/安全信号。Windows XP 不假设 ANSI；着色须平台可证明路径，失败则无色。不得改变上表字面量或另建用户自定义提示符主题。

最小启动投影示意为：

```text
yaca: Yet Another Coding Agent.
work directory: C:\Work\demo
config: valid
context: new (not saved)
model: Work
permission: Std
double check: on
Run .status for details.
>>
```

未启用的逐字段行直接不生成，不输出空占位；Unicode 路径不能显示时只转义该值，不改变字段名和真实路径。

## 已确认的 `.cautious` 语义边界

`.cautious` 管理当前会话的 `DoubleCheck` 覆盖值，并由上下文系统保存到当前 XML。TUI 只解析命令、显示默认值/覆盖值/有效值和操作结果；它不能直接改写用户配置、切换 Permission profile 或自行决定 `DoubleCheck` 包含哪些复核行为。

**语法（D-065 / SQ-08 = A）：**

| 输入 | 行为 |
| --- | --- |
| `.cautious` | 只读 status（default / override / effective） |
| `.cautious on` | 覆盖 true |
| `.cautious off` | 覆盖 false（强制关，≠ reset） |
| `.cautious toggle` | 按当前有效值翻转并写成 true/false 覆盖 |
| `.cautious reset` | 清除覆盖，inherit INI 默认 |

无参数不得 toggle。未知子参数报错并提示用法。

## Model picker

chat 内 `.model` 只有选择职责，不进入独立 `model-repl`：

- `.model` 无参数时打开 enabled Model 的上/下选择器；能力足够的终端可以用方向键和高亮，Windows XP、窄窗口、cooked line 或能力不明时必须降级为编号列表或逐行文本选择。
- `.model <selector>` 直接选择；它与选择器确认都提交同一个 `select-model(selector)` typed semantic action，所以验证、错误、Model 切换事件和下一 turn 生效语义必须一致。
- 输入 selector 时可以按当前 Model registry 自动显示补全提示。补全没有配置开关，不自动提交，也不是可用前提；无法可靠重绘或窗口空间不足时安静退化，完整文本输入和无参数选择器仍可用。

列表在窄终端怎样分页/截断、selector 的精确匹配与消歧，以及 Agent 忙时何时接纳切换，仍由对应 TUI/Model/AgentLoop 决定；本节不从“上/下选择器”推导全屏界面，也不提前冻结这些规则。

## TUI 与 CLI 的动作一致性

所有会改变或查询领域状态的 TUI action 都必须来自 CLI 共用的 typed action registry，并有 CLI 投影；同一输入快照下，两种投影调用相同 service、Permission/确认规则、typed outcome 和持久化路径。方向键、分页、颜色、补全、焦点移动和 renderer redraw 只是表现动作，不需要伪装成领域 CLI action。

这条完整性要求不发布通用 headless/remote IPC/RPC，也不把交互动作自动变成可无人值守执行的命令。非 TTY 是否可用、如何表达 consent、stdout/stderr 与机器输出，仍由 CLI 契约决定；任何投影都不能自动批准 Permission 或跳过领域确认。

## 上下文浏览器的 TUI 边界

交互式上下文浏览器的目录树、搜索、选择、重命名、删除和刷新语义由 11 号 `ContextBrowserController` 统一提供。TUI 只负责把用户输入翻译为语义动作并显示结果：

- 顶层有两个明确入口：`recent` 直接显示快速最近列表，`full` 显示完整目录树/全部 Context。二者只是同一 controller 的初始 view，进入后共用查看、搜索、选择、重命名、rebind、永久删除和刷新动作。
- 规范入口使用编号与 `open/select/search/rename/delete/up/root/refresh/quit` 一类逐行命令，不要求 raw mode、ANSI 或方向键。
- 能力足够时可以让固定方向键、颜色、高亮和临时状态行调用相同 controller action，但不增加鼠标、可重绑定按键或不同默认选择。
- 任一内部 renderer 对同一快照和动作序列必须选中同一候选、触发相同确认并得到相同错误。
- 普通搜索只过滤候选列表，不自动连接；精确名称/hash 输入调用统一 Resolver。
- 列表排序从 XML canonical metadata 读取 `created`、`updated` 或名称，并按 `ascending|descending` 投影；默认 `updated` + `descending`。文件系统 ctime/mtime 不能作为这些字段的替代；主键相同时始终按 canonical `LogicalPath` 升序，绝不随主方向反转。改变排序不改变 Resolver，也不使裸启动扫描或提示 recent Context。
- 重命名或删除确认必须显示完整逻辑路径与当前 16 位 hash，不能只显示可能重复的名称。
- `delete` 是不可恢复的永久删除；TUI 不显示 trash、soft-delete、restore 或 empty-trash 入口。确认必须明确写出永久性，活动 writer 锁定的目标仍返回 `LockConflict`。
- 快照过期、扫描不完整、XML 损坏和目标已变化都要有稳定文字提示，颜色不能承担唯一含义。
- 活动 writer 已锁定的 Context 只能显示无需解析正文即可取得的 name、logical path、busy 和可证明 PID（否则 unknown）元数据；不进入 read-only Context view，也不把 `inspect` 映射为正文读取。外部 rename、delete、rebind 和 `AutoRenameDisabled` 等 metadata mutation 显示 typed `LockConflict`，不提供按锁龄 force unlock。释放锁后用户必须重新取得/复核 Catalog 快照再读取或修改。

`.status` 显示的当前 hash 从活动 ContextHandle 的最新逻辑路径实时计算，不为显示状态扫描整棵 `CONTEXT`。如果活动 XML 已被外部移动、删除、替换或改写，TUI 必须显示 `stale`/失效状态和 fail-stop 原因，停止投影新的模型请求、工具或提交动作；不能只显示一个看似仍可恢复的旧 hash，也不能按名称/hash/内容自动追踪新文件。

## self-test 投影

self-test 页面只投影诊断服务的 stable check registry 和 typed results，不在 renderer 内复制检查逻辑：

- Stage 1 除配置/依赖的静态检查外，必须显示 Context XML codec/schema、镜像路径对应 workspace 是否存在且可进入、Catalog traversal、实时 hash derivation，以及扫描耗时、cap 与 `partial`。目录不存在、Context 过多或遍历超过预算都要给出具体 check ID、范围与 self-fix 入口，不能折叠成笼统的 `failed`。
- Stage 1 静态报告 input backend 能否区分 `Ctrl+Enter`、`Shift+Enter`、`Alt+Enter` 和 `Esc`。只有用户显式启动且运行在真实交互 TTY 的 self-test 才提供逐项按键检查；启动前自动 self-test 不等待用户按键。组合键不可辨认时显示对应 `.immediate`、`.multiline`、`.side` 或 `.cancel` 后备，不把增强能力缺失误报为核心失败。
- Stage 3 显示 Permission 名称、Description、有限 Prompt 与实际能力矩阵的语义一致性建议，并可指出面向用户的自然语言拼写问题；例如名称暗示 readonly 而矩阵允许写入时必须明确列出实际配置。这些结果标为 advisory，不能覆盖 Stage 1/2 的确定性结论，也不能直接修改 Permission。
- TUI 中的阶段选择、check list、合法排除和 self-fix 入口，与 CLI 使用同一 typed action/check IDs；TUI 不拥有额外的隐藏检查或默认排除。

## 主界面总体方向

### A. 追加式逐行对话 REPL（已确认规范）

每个语义事件以稳定文本块追加。当前待技术冻结的视觉词汇是 `[YACA]`、`[USER]`、`[TOOL #12]`、`[STATUS]`、`[QUEUE #2]`、`[STEER #3]`、`[SIDE #1]`、`[WARNING]`、`[ERROR ID]`、`[ACTION]`；它们需要 transcript fixture 证明一致性，不再返回负责人选择。输入始终在最后，chat 使用固定 `>>`，选择和确认使用各自正式 grammar；plain 模式完全不移动光标。`>>` 不外推为其他 focus 的提示符。

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

候选渲染协议是：raw/native editor 保存并重绘 draft；cooked 后备把高频异步 delta 暂存/合并到安全换行，用户提交一行后再追加，并用一条 status 表明有积压。不能清空 draft、让输出覆盖输入，或声称 cooked 终端能识别普通粘贴中的回车。粘贴保护在 raw/bracketed-paste 环境启用；规范多行后备从 `.multiline` 进入，精确结束 delimiter 仍待 grammar 冻结。

`Esc` 只是可用环境中的快捷键，规范后备是无参数 `.cancel`，二者都取消当前最内层可取消活动。不采用“短时间按两次 Esc”的核心协议，因为 cooked 终端可能根本不交付该按键。

## 终端-only 零表面

v0.1 不提供 Web、图像/clipboard-media/screenshot、音频/麦克风、公共 headless/remote controller、transcription 或 TTS。TUI 和命令 registry 中不得出现相应页面、命令、help topic、completion、状态 badge、设备提示或 disabled 占位；旧终端也不需要为不存在的媒体设计 fallback。设计归档和负向测试可以点名这些排除项，活动 renderer 与发行资源必须为零。

## 需要逐项确认的体验

1. 已确认的启动头字段、Slogan 和 chat `>>` 怎样与角色标签、留白和整体信息密度形成唯一 projection；不再重新选择另一套欢迎页。
2. 常驻最小状态、`.status` 详情，以及模型/权限/context hash/队列/当前动作的字段顺序。
3. 模型流式文本、provisional 文本、工具调用、shell 输出、Git diff 与完成报告的块样式。
4. queue、steer、旁问和取消的可见状态、序号、插入点与持久化提示。  
4b. 自动 compaction 的 STATUS 可见性（D-067）：开始/结果，不强制确认，禁止成功静默。
5. 确认页显示的命令/路径/host、默认选择、DoubleCheck 结果和拒绝后的下一步。
6. chat、help、model-repl、config-repl、context-repl、self-test、model/permission picker 的完整页面集合与共同导航词根。
7. 配置损坏、无 Model、配置/上下文不匹配、网络重试、压缩、磁盘满和恢复的错误/提示文案。
8. Windows 原生颜色与 Linux 基本颜色的映射，以及颜色失效时的稳定 ASCII 标签。
9. 80x24、未知尺寸、长路径、长命令、非 ASCII 用户数据和超长输出的单列换行/分页规则。
10. 非 TTY、重定向、broken pipe、EOF、Ctrl+C 和终端模式恢复与 CLI 的边界。

## 可视化时机

逐行 REPL 应先用可复制的 ASCII transcript 讨论，因为它同时就是最低兼容输出和 golden test 候选。只有在确认固定状态行或全屏分区后，80×24 的并排 mockup 才比文字更有帮助；mockup 仍不能替代真实 XP/CentOS 终端验证。

## 当前讨论入口

追加式逐行 REPL 已确认为所有平台规范；程序 chrome、标签和交互 grammar 使用 ASCII，用户路径、Context 名与对话正文仍按真实 Unicode 数据投影。basic ANSI/原生颜色只增强标签与 diff，全屏不再是同等首版候选。下一步通过 80×24、40 列、XP 无色、忙时 draft、审批、Git diff、error/recovery、三个 REPL 和 self-test 的完整 ASCII chrome transcript 冻结其余页面细节。
