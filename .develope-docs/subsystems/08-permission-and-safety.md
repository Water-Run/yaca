# 08 权限与安全

状态：候选

## 职责

根据工具动作、路径、网络访问和权限组决定允许、拒绝、请求用户确认或调用 LLM 二次检查，并产生可审计决定。

## 边界

- 安全策略独立于 TUI；CLI、TUI 和测试都通过同一 semantic-action registry 调用同一接口、得到同一 typed decision。这里的 CLI parity 只保证本机已注册动作的等价入口，不发布公共 headless/IPC/RPC controller。v0.1 不为 Web、媒体或 remote controller 预留另一套授权入口。
- 本系统不直接执行工具。
- Regex 只能作为附加过滤条件，不能成为唯一危险动作分类机制。

## 设计要求

- 直接工具的权限判断基于结构化动作，而不是事后解析完整 shell 字符串；raw shell 只能被视为宽 `Execute` 能力。
- 发行模板必须包含名为 `Readonly` 的 profile；其 raw shell 三态值与其他精确发行矩阵仍由 `TS-04` 决定。Runtime 只读取能力字段，不按 profile 名称特殊处理；名称与矩阵不一致只能形成 Self-Test advisory。Model provider 网络不属于工具权限。
- 用户确认内容必须准确显示将要访问的路径、程序或主机。
- LLM 二次检查失败时采用保守策略。

## 命名 typed profile 与 `SystemPrompt`

Permission 是 `[Permission.<LogicalName>]` 形式的命名 typed profile。逻辑名称只是选择器；`Description` 只是展示文本；候选 `SystemPrompt` 只是模型指令组件。三者都不能授予能力、改变 `deny/confirm/allow`，也不能让历史 approval 重新生效。确定性求值只消费 schema 注册的 capability 字段及当前动作事实。

发行模板必须包含 `Readonly`，但继续把 `Std` 放在物理第一项，因此新 Context 的默认 Permission 仍是 `Std`。`Readonly` 的精确发行矩阵由 `TS-04` 决定；无论发行值、用户修改或重命名为何，实际行为都完全由能力字段决定，Self-Test 最多给出名称/描述/Prompt 与矩阵不一致的 advisory。

`Permission.SystemPrompt` 候选为有界、严格 UTF-8 的 `user-content`，不支持变量插值或把自然语言解析成 policy。当前最小投影只把它作为 `main` purpose 的独立 `permission-system-prompt` 组件；它在 PP-03 权威链中的精确位置仍待正式决定，不能由配置 parser、Prompt assembler 或本文件先行猜测。无论最终排位如何，它都不能覆盖 Runtime invariants、工具 registry、Permission 求值或人工确认。

## raw shell 的诚实安全边界

项目负责人要求向模型提供类似 Codex 的原始工具，但又明确不提供 OS sandbox。在这个组合下，Runtime 可以决定“是否允许调用 shell”、展示完整命令并记录结果，却不能可靠证明该命令只读、不会联网或不会启动另一个程序。基于 regex 或 LLM 对命令文本分类可以增加警告，不能变成隔离保证。

因此候选能力映射是：read/write/delete/network/outside-workspace 等细粒度规则只约束 yaca 直接实现且参数结构化的工具；shell 统一映射到宽 `Execute`。用户批准必须绑定 tool 版本、完整命令、cwd、相关环境非秘密摘要、operation ID 和目标新鲜度，批准后任一安全相关输入变化都要重新确认。`DoubleCheck` 只能在确定性 Permission 已经允许的范围内追加复核或否决，不能反向授予 Runtime 拒绝的动作。

每个 Context 恰好一个 workspace root，且当前 root 只由活动 XML 在 `__yaca__/CONTEXT/` 镜像树中的父目录解码；XML 内不保存可覆盖它的 root authority 字段。Permission 的 workspace/outside 判断必须消费这个经过验证的当前 root snapshot。历史 cwd、rebind 事件、显示路径或外来 XML 字段都不能改变边界；root 变化会使旧动作快照与 approval 失效。

候选权威矩阵应至少呈现：

| 动作 | 可强制能力 | `Readonly` 候选 | `Std` 候选 |
| --- | --- | --- | --- |
| direct list/read/search | `Read`；仅 M05-56 B 时敏感候选再叠加 `SensitiveRead` | `TS-04` 待决 | `TS-04` 待决 |
| direct create/write/patch | `Write` | `TS-04` 待决 | `TS-04` 待决 |
| direct delete | `Delete` | `TS-04` 待决 | `TS-04` 待决 |
| direct rename | `Write`/`Delete` + outside modifier | `TS-04` 待决 | `TS-04` 待决 |
| raw shell | 宽 `Execute/Shell` | `TS-04` 待决 | `TS-04` 待决 |
| Model provider HTTP | 选择当前 Model 即授权 | 可用 | 可用 |
| 未来 direct network tool | `Network` | `TS-04` 待决 | `TS-04` 待决 |

`Std` 第一、发行模板包含 `Readonly` 已由上游答复固定；其余预设、完整矩阵与每格仍待正式 owner 收口。表的关键不是当前候选值，而是不能再显示一个实际上约束不了 shell 的 Network/Write 开关。M05-16 只在一个 `OutsideWorkspace` 和三个按动作 outside 字段之间选择；M05-56 独立决定 `SensitiveRead` 是否存在，只有 B 才激活 TS-21 classifier。若 v0.1 没有 direct network tool，建议先不暴露 `Permission.Network`。

## 外来 XML 不是授权令牌

复制/导入的 XML 可以忠实保存当时实际使用的完整 capability snapshot、`Permission.SystemPrompt` component snapshot、`DoubleCheck=false`、ContextPrompt 和 approval，但这些只说明过去发生过什么。继续运行前必须使用目标机器当前 INI/schema 重新计算有效权限；同名 profile 不等于同一矩阵，外来 `SystemPrompt` 也不能创建、覆盖或激活本机 profile。历史 approval 永远 audit-only。任何会降低本机默认安全程度的会话覆盖都应显著显示来源并由当前用户确认，不能因 digest chain 完整就自动信任。

推荐动作顺序为：确定性 Permission → DoubleCheck action review → 人工确认 → operation durable → 执行。reviewer 只能追加拒绝或修改建议；失败后若允许人工 bypass，也只绑定这一精确动作并写入 XML。

## Config generation 与活动动作

每个顶层 `main`/`side` turn admission 时冻结当前已验证 config generation，以及由它求得的 Permission profile、capability matrix、`SystemPrompt`、`DoubleCheck` 和工具 registry snapshot。该 turn 的工具、retry、action review 与 termination review 全部沿用这一份快照；活动 turn 中修改 INI 只能影响下一顶层 turn，不能让同一动作在提议、审批与执行之间换 Permission。新的 INI generation 若跨字段验证失败，Runtime 必须拒绝下一 turn，不能退回旧 generation 后继续制造用户不知情的新动作。

Context 的 write lease 是独立于 Permission 的 Runtime/存储不变量。另一个进程通过 context-repl 或等价 CLI 发起 rename、rebind、delete、`AutoRenameDisabled` 修改等管理动作时，只要活动 writer 尚未释放就必须返回 `LockConflict`；任何 Permission 名称、矩阵、Prompt、人工确认或 DoubleCheck 都不能越过该锁。Model/config 的全局 INI 管理使用自己的原子提交边界，不因此取得活动 Context 的修改权。

## Self-Test Stage 3 的 Permission advisory

Stage 1 只做 schema 与确定性矩阵检查；Stage 3 才可把 Stage 2 已确认可用的 Model 用作顾问，检查 Permission 名称、`Description`、有界 `SystemPrompt`、capability matrix 及常见拼写是否明显矛盾，例如名为 `Readonly` 却允许宽 `Execute`。这些结果必须标为 advisory，显示实际矩阵和依据；它们不能自动改名、修复配置、改变 `deny/confirm/allow`，也不能让命名启发式进入 Runtime 求值。

## 已确认的模式边界

`Cautious` 不再是独立权限模式或内置权限组。权限 profile 回答“哪些动作允许、拒绝或需要人工确认”；默认配置 `DoubleCheck` 和会话命令 `.cautious` 回答“是否启用额外谨慎复核”。因此 `.cautious` 不能暗中改变 `AllowWrite`、`AllowDelete`、`AllowNetwork` 或当前权限组。

当前 `_CONFIG_.ini` 中的 `[Permission.Cautious]` 与每个 profile 内的 `DoubleCheck` 属于待迁移旧草案，不能继续作为目标 schema。D-027 已确认 `DoubleCheck` 包含主模型正常结束前的完成复核；它还复核哪些写入、删除、执行、联网或外部路径动作，仍需由配置、工具与 AgentLoop 共同确认。

## 终端-only 零表面

v0.1 不提供 Web、图像/截图、音频/麦克风、公共 headless/remote controller、transcription 或 TTS，因此 Permission schema、审批类型和 reviewer 输入中都不得出现这些能力的字段、空 profile 位或兼容占位。普通 Model provider HTTP 与以后若被独立选入的 direct network tool 仍按各自现有 owner 处理，不能借媒体或 remote 名称获得授权。

## 待讨论

剩余 profile 的精确定义、`Permission.SystemPrompt` 的 PP-03 精确排位与大小/多行语法、M05-16 outside 粗/细字段、M05-56 条件 SensitiveRead 与 TS-21 classifier 的组合、tool×capability 矩阵、action/termination review verdict、人工 override、批量调用逐项审批，以及导入 XML 安全降级的页面。
