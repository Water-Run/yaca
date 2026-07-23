# 13 CLI

状态：核心 CLI、三套 argv 拼写与 semantic action registry 已确认；完整参数 grammar 和机器输出待技术规格冻结

## 职责

定义稳定命令行语法，解析参数并调用配置、上下文、诊断和会话服务；负责帮助、版本和可脚本化输出。

## 边界

- CLI 不包含业务逻辑。
- 交互式界面属于 14 号 TUI。
- 长命令、唯一短名、Windows 兼容别名、chat 点命令、快捷键和 help/completion 都从同一份 typed semantic action registry 投影；任何适配器都不能复制动作语义。
- `--` 长名是规范 CLI 拼写；`-` 简写跨平台可用；`/` 简写只在 Windows 解析，在 Linux 必须继续作为绝对路径开头处理。

## 设计要求

- 修复当前 `-dc`、`-rc` 短参数冲突。
- 明确退出码和 stdout/stderr 分工。
- 路径和上下文名称可以安全包含空格与非 ASCII 字符。
- 旧 shell 环境不要求现代终端特性。
- Windows XP/Vista/7/8/10 x86 的 argv、cwd 和文件名必须在窄平台边界转为宽字符 API；CLI parser 不得先用当前 OEM/ANSI code page 损坏中文等非 ASCII 名称。UI 标签保持 English/ASCII，但用户路径和 Context 名不可被改名或用替换字符参与 hash。
- 所有 TUI 领域动作与 CLI 投影必须来自同一份 typed action registry；renderer 的方向键、颜色、高亮和补全只是输入/显示增强，不得创建第二套业务动作或默认值。这里的 CLI 投影只保证用户可以从命令行表达同一动作，不等于发布公共 headless/remote controller，也不允许非交互调用绕过确认、Permission 或审批。

## 已确认的命令注册表规则

每个动作在一份注册记录中定义 stable semantic action ID、规范 `--` 长名、唯一 `-` 简写、可选的 Windows-only `/` 简写、参数 schema、可用表面、TTY 要求和 help 文本。parser、help、completion、TUI 点命令和测试只消费这份记录；相同输入不得因入口不同而改变默认值、确认、Permission、typed outcome 或持久化。

本轮冻结的顶层投影是：

| Semantic action | 规范长名 | 跨平台简写 | Windows-only 简写 |
| --- | --- | --- | --- |
| self-test | `--self-test` | `-st` | `/st` |
| model management | `--model-repl` | `-mr` | `/mr` |
| config management | `--config-repl` | `-cfg` | `/cfg` |
| Context management | `--context-repl recent\|full` | `-ctx recent\|full` | `/ctx recent\|full` |
| continue Context | `--continue <selector>` | `-c <selector>` | `/c <selector>` |
| help | `--help` | `-h` | `/h` |
| version | `--version` | `-v` | `/v` |

`recent|full` 是 `context-repl` 的必选 typed 入口参数，不是两个分别实现的浏览器。`--context-repl recent` 打开快速最近列表，`--context-repl full` 打开完整目录树/全部 Context；详细语义由 11 号系统拥有。

Windows parser 只有在 Windows 构建中才识别已注册的 `/` token；不能把任意 `/word` 当作选项。Linux 构建完全不注册 `/` 别名，因此 `/home/...` 等绝对路径不会产生参数歧义。所有平台都支持独立 token `--` 结束选项解析；其后的值只按位置参数处理，从而允许目录或 selector 以 `-` 开头。宿主 shell 仍负责用引号把含空格的值交成一个 argv token。

未在上表冻结的动作仍必须经过同一 registry 分配唯一拼写，不能重新使用已有别名，也不能恢复旧冲突的 `-dc`、`-rc`。旧 README 名称是否作为兼容别名保留，必须在完整 registry 审阅时显式决定；它们不能绕过规范名称成为第二套接口。

## 已确认的主入口

主交互语法为：

```text
yaca [目录]
```

目录参数省略时按 `.` 处理，所以裸 `yaca` 与 `yaca .` 完全等价。CLI 将该目录作为初始工作位置交给工作区发现、指令发现、Context Resolver 和 AgentLoop 启动流程；各下游系统不得分别猜一个不同的默认目录。

目录必须已经存在、是可进入的真实目录；相对路径相对于启动 yaca 时的进程目录解析。该真实目录就是新 Context 的唯一 workspace root；上级 Git root 只作 status/diff 等证据，不自动提升边界。引号是宿主 shell 的分词规则，不能解决一个参数值本身以 `-` 开头时被 parser 当作选项的问题；这类值使用已经确认的 `--` 结束选项。文件、缺失目录和无权限目标不自动创建或猜测。

每个 Context 恰好有一个 workspace root，由当前 XML 在 `CONTEXT` 镜像树中的父目录解码，不从 XML 内历史 cwd/root 字段取值。新建 Context 直接把传入且可进入的真实目录编码为这个镜像父目录；不因发现上级 Git root 改变它。`continue` 只能在解码 root 仍存在且可进入时续接；不用当前 cwd 静默 rebind，也不跳转到相似 Git 根。

正常启动头只接受已经确认的逐字段显示配置，不存在总开关。CLI/help/schema 不得重新发明 `StartupHeader`、`ShowStartupHeader` 或等价 master；每个启用字段独占一行，强制错误、warning 和 action-required 也不受逐字段显示设置隐藏。

## 已确认的会话命令

TUI 点命令 `.cautious` 管理当前会话的 `DoubleCheck` 覆盖值。它不修改用户默认配置或切换 Permission profile；覆盖值由上下文系统写入当前 XML，恢复上下文时恢复。无参数行为、`on/off/toggle/reset` 语法、脚本化等价命令和状态输出仍待 TUI/CLI 契约确认。

忙时输入、旁问、多行和取消的固定 ASCII 后备已经确认：

| 点命令 | Semantic action | 固定快捷键等价入口 |
| --- | --- | --- |
| `.queue <message>` | 把消息加入待执行队列 | 普通 `Enter` 在忙时提交 |
| `.queue list` | 查看队列及稳定条目标识/顺序 | 无 |
| `.queue delete ...` | 删除尚未开始的队列项 | 无 |
| `.queue move ...` | 调整尚未开始的队列项顺序 | 无 |
| `.queue edit ...` | 编辑尚未开始的队列项 | 无 |
| `.queue clear` | 清空尚未开始的队列项 | 无 |
| `.immediate <message>` | 插队/steer 当前活动工作 | `Ctrl+Enter` |
| `.side <message>` | 发起一条只读旁问 | `Alt+Enter` |
| `.multiline` | 进入显式多行输入 | `Shift+Enter` |
| `.cancel` | 取消当前最内层可取消活动 | `Esc` |

`.immediate` 是唯一正式拼写，不保留误拼 `.immidiate`。队列的条目标识、move/edit 参数细节和多行结束 delimiter 仍由 AgentLoop/TUI grammar 冻结，但不能改变上表动作含义。点命令不是兼容模式：它们与快捷键提交相同 action ID、输入 payload 和 durable/取消规则；不能支持快捷键时，help 直接显示点命令后备。

## chat 内 Model 选择

chat 中的 `.model` 是一个扁平命令根，只选择已经存在、enabled 且有效的 Model，不添加、编辑、删除或测试 Model：

- `.model` 无参数时打开上/下选择器；旧控制台、窄终端或不能可靠提供方向键事件时，投影为编号选择或等价的逐行文本选择。
- `.model <selector>` 直接提交同一个 `select-model(selector)` typed semantic action；选择器视图最终确认某项后也只提交这个 action，因此两条路径的验证、状态变化、错误与 XML 事实必须相同。
- 输入 `.model <selector>` 时可以从当前 enabled Model registry 自动提供补全提示；补全是能力允许时的无配置增强，不是命令可用前提，也不能自动提交候选。没有补全时，用户仍可输入完整 selector 或打开无参数选择器。

Model selector 的精确匹配、歧义规则、窄窗口挤占/分页细节，以及 Agent 忙时该动作何时接纳，仍分别由 Model registry、TUI 与 AgentLoop owner 决定；本节不提前冻结这些规则。独立 `model-repl` 继续负责 Model 的增删查改和连接测试，chat 的 `.model` 不跳转到它。

## 与统一上下文 Resolver 的契约

接受用户输入的上下文 selector 时，CLI 只解析参数边界，然后把 selector 和当前工作目录交给 11 号 `ContextResolver`。CLI 不得自行规定“这个命令名称优先、另一个命令 hash 优先”。

| Semantic action（不是 CLI 拼写） | 11 号服务使用方式 |
| --- | --- |
| `continue(selector)` | 统一 Resolver，唯一命中后恢复 |
| `context-select(selector)` | 同一 Resolver，不能继续使用“仅全局 hash/仅本地名称”旧规则 |
| `context-rename(selector, ...)` | Resolver 定位，MutationService 复核并重命名 |
| `context-rebind(selector, target-root)` | Resolver 定位，MutationService 复核后 no-replace/可恢复移动 XML 到目标镜像目录 |
| `context-set-auto-rename-disabled(selector, bool)` | Resolver 定位并事务修改专用 XML metadata；不是通用 flags 入口 |
| `context-delete(selector)` | Resolver 定位，MutationService 复核、确认并删除 |
| `context-list(scope)` | 枚举瞬时 Catalog 快照，不解析 selector |
| `context-repl(view)` | 以 `recent|full` 入口打开同一 Catalog 上的交互式浏览器 |
| `current-context-status` | 从当前 ContextHandle 直接计算 16 位 hash，不调用 Resolver |
| `current-context-mutation` | 操作当前句柄；若未来接受其他目标参数，才转为 selector 入口 |

Resolver 的 `AmbiguousName`、`HashCollision`、`MatchedUnavailable`、`ScanIncomplete`、`NotFound` 等结构化结果必须映射为稳定的退出码和可行动错误。目标复核的 `TargetChanged`、打开服务的 `OpenConflict` 以及修改服务的 `DestinationExists`/`LockConflict` 属于后续阶段，不能伪装成 Resolver 的 `NotFound`。非交互模式不能遇到多个候选就取目录枚举中的第一个；应输出候选的逻辑路径和 hash，且不得在 stdout 机器数据中混入 TUI 提示。

`continue`、context rename/delete 和 context-select actions 的帮助文本必须一致说明已确认的“距离优先、同环名称优先于 hash、单遍双判定”规则，不能让不同入口看起来采用不同优先级。所有 help 拼写从同一 registry 生成；已冻结的 continue/context-repl 根使用上表规范名称，其他 context actions 不得私设别名。

## `context-repl` action 的适配边界

`context-repl(view)` 以已确认的 `recent|full` typed 参数启动交互式上下文浏览器。`recent` 是快速最近列表入口；`full` 是完整目录树/全部 Context 入口。二者复用同一个 controller、Resolver、查看、搜索、选择连接、重命名、rebind、查看/添加/取消 `AutoRenameDisabled`、永久删除、刷新和取消动作，不维护两份数据或 mutation 规则。取消命名标记从当前 durable 水位建立新 baseline，不立即或追补 Model 请求；添加标记会使在途命名结果失效。

列表视图从统一 Catalog 快照读取 XML 中的 canonical `created`、`updated` 和 Context 名称，按配置选择 `created|updated|name`，再按 `ascending|descending` 排序；默认是 `updated` + `descending`。不得用文件系统 ctime/mtime 冒充 canonical metadata；主键相同时始终按 canonical `LogicalPath` 升序，绝不随主方向反转。排序只影响 list/browser 投影，不改变 Resolver 的距离、名称/hash 顺序，也不授权裸启动扫描或提示 recent Context。

若目标 Context 已由活动 writer 加锁，`context-repl` 只可显示无需解析正文即可取得的 name、logical path、busy 和可证明 PID（否则 unknown）元数据；不得进入 read-only Context view，也不得把普通 `inspect` 解释成读取正文。从另一个进程发起 rename、delete、rebind 或 `AutoRenameDisabled` 等 metadata mutation 必须返回 typed `LockConflict`，直到活动 writer 正常释放。不能因操作“只有一个 XML 字段”就绕过锁，也不能按锁龄强制解锁。

plain 模式和能力有限的 TTY 仍应有编号/文本命令界面；在完全非 TTY、输入重定向的脚本环境中是拒绝启动、读取 stdin 命令流还是要求显式标志，留给 `CLI-02`。列表选中项携带快照中的明确候选，执行前复核，不应转回名称字符串再次搜索。裸 `yaca`/`yaca .` 不调用 recent/full Catalog action，也不扫描或提示历史 Context。

`model-repl`、`config-repl` 和 `context-repl` 均是独立顶层 management action，不从 chat 内点命令跳转。没有有效 Model 或 Agent ConfigGeneration 不可发布时，help/version、三个 REPL 和 self-test Stage 1 仍可用 bootstrap service；它们不启动 Agent/工具、不联网。context-repl 的管理面包括 list/inspect/rename/rebind/permanent-delete/import/repair 和专用命名标记修改；“add”只能是导入现有 XML，不创建空 Context。v0.1 不建立 trash、soft-delete 或 restore action。每个 REPL 都投影各自领域的 `self-fix-program` 选单，只提供扫描、typed plan 预览、确认与原子提交，不自动修改；活动锁目标只投影上一段列出的 busy metadata，不解析正文、不进入只读 Context view。

## `self-test` action 的适配边界

CLI 只投影一个 self-test semantic action。完整语义面包含：`through-stage` 选择终止阶段；`list` 不联网列出 stable Model/check ID；`exclude` 可重复排除 Model 或 check；`check` 可重复明确选择 check。传给领域服务的 typed request 规范化为 `through_stage=1|2|3`、`excluded_models[]`、`excluded_checks[]`、`selected_checks[]`，列表动作为 `list-checks`。规范 action 根已冻结为 `--self-test`/`-st`/Windows `/st`；其阶段、排除和 check 子参数的最终唯一拼写仍由完整 registry 审阅冻结。

执行始终是 Stage 1→Stage 2→Stage 3；`through_stage=3` 不允许直跳 Stage 3，前一阶段未通过则后一阶段不可用。排除 required Model/check 必须返回 `partial`，不得进入 Stage 3，也不得满足 `General.StartupSelfTest` 启动 gate；启动 gate 不携带 exclusions。Stage 2/3 开始前的用户同意仍是语义服务返回的 `waiting-user`，CLI 只决定交互/非交互如何显示或失败。

Stage 1 的 stable check registry 必须覆盖 Context XML codec/schema、由镜像路径解码得到的 workspace 是否存在且可进入、Catalog traversal、实时 hash derivation，以及目录/Context 量过大时的扫描耗时、cap 和 `partial` 结果；它不能为了检查而连接或修改 Context。Stage 1 同时静态报告当前 TTY/input backend 是否能够区分 `Ctrl+Enter`、`Shift+Enter`、`Alt+Enter` 和 `Esc`。用户显式运行、且当前是真实交互 TTY 的 self-test 可以进入有界的交互式按键检查，逐项验证实际收到的 key event；启动前自动 self-test 不等待这组按键输入。不能区分某个组合键时，该项结果是带固定点命令 fallback 的兼容性降级，不因增强快捷键缺失宣称整个 yaca 不可用。

Stage 3 在仅使用 Stage 2 已确认 Model 的前提下，还要审阅 Permission 名称、Description、有限 Prompt、实际能力矩阵之间的语义偏差，以及面向用户的自然语言拼写问题。这些 Stage 3 结果都是 advisory warning，不能改写 Stage 1/2 的确定性通过/失败，也不能自动修复配置。

self-test 的 TUI 菜单和 CLI 调用提交同一 typed request/check IDs；列表、排除、阶段依赖和结果分类不得出现两套语义。CLI parity 不意味着非 TTY 可以自动表示 Stage 2/3 consent：不能呈现所需确认时必须明确失败或要求合适的显式授权契约，其最终形式仍待 CLI 安全问题收口。

## 待讨论

- context rename action 的新名称参数、引用规则及与目录移动的边界。
- 永久删除的确认文字和脚本化 `--yes` 安全边界；软删除、trash 与 restore 已明确排除。
- `context-repl` action 在非 TTY 下的行为。
- 完整 command registry 中尚未冻结动作的长名/唯一简称、参数位置/引号、互斥、TTY 要求、stdout/stderr、exit class 与每个 AgentState 的可用性。
- README 中 `--interactive-config-changer` 等旧名是删除还是只作为兼容别名，以及 self-test 阶段/exclusion/list-checks 子参数的最终唯一拼写。
