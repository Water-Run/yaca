# 05 配置与模型注册表

更新日期：2026-08-10

状态：**W1-B 规格展开进行中** — 下文「现行字段 catalog」为 v0.1 **唯一权威字段集合**（产品语义）；INI 多行 grammar、部分数值硬顶、原子写原语仍待技术证明。`src/_CONFIG_.ini` 与 `CONFIG-SCHEMA-CANDIDATE.md` **不是**现行契约（后者仅审计底稿）。

## 职责

加载内置 typed schema、完整用户 INI 和当前 Context XML 允许的会话覆盖，验证 General、TUI、Agent、Network、Exec、Permission、Context、Model 各区，产生不可变运行时 `ConfigGeneration`，并为 `config-repl`、`model-repl` 和 self-test 提供同一 schema 服务。

## 边界

- INI/XML 基础语法由 04 号系统处理；本系统拥有字段 schema、引用和跨字段校验。
- `config-repl` 与 `model-repl` 只编辑主 INI；`context-repl` 和 chat `.prompt` 管理 Context XML 会话项。
- Context 选择、rename/delete/import/rebind 与目录树由 11 号系统处理。
- provider wire 与 AgentLoop 分别由 06、09 号系统处理；配置字段不能自行发请求、授予权限或创建后台状态。
- v0.1 没有 project config、环境覆盖整个 INI、Web 配置、媒体配置、remote/headless、MCP、plugin 或 direct network tool 空壳。

## 配置来源与优先级

长期来源只有：

1. 发行物内置 typed schema/default；
2. `__yaca__` 中一份完整用户 INI；
3. 当前 Context XML 中严格白名单的会话值。

CLI 可以产生本次 invocation 的显式动作参数，但不形成第四份长期配置。仓库文件永远只是数据，不会自动成为 project config 或 Prompt。

主 INI 可以手工编辑；`config-repl`/`model-repl` 使用同一 schema 做事务式草稿、预览、完整校验和原子发布。unknown、重复、类型错误、越界、无效引用或条件字段不成立都会使候选 generation 无效，不能静默忽略或保留成 hidden advanced option。

Model 与 Permission 的物理 section 顺序决定各自默认选择；发行模板把 `Std` 放在 Permission 第一项，并包含 `Readonly`。`Std` 的 Read=allow，其余四项为 confirm；`Readonly` 的 Read=allow，其余四项为 deny。名称只用于选择/显示，真实 Model 能力和 Permission 行为始终看字段；用户修改后不再根据名称套回发行值。

## 配置 generation 与逐 turn 生效

Model/config INI 可以在 chat 持有 Context writer 时由独立 REPL 或外部编辑器修改；配置提交锁与 Context writer lease 分离。每个新顶层 `main`/`side` admission 前，配置服务有界读取完整 INI bytes，并计算只留在进程内的 private source digest：

1. digest 未变化时复用已验证 immutable generation；
2. 变化时对整份 bytes 做 parse、schema、cross-field、secret-source、顺序和引用校验；
3. 全部成功后一次发布新 generation，并从该 turn 自动生效；
4. 文件删除、不可读、半写或无效时阻止新 turn，只开放对应 bootstrap/status/self-fix；
5. current Model/Permission 被删除、重命名、禁用或失效时要求显式 switch/mapping，不按第一项猜；
6. active turn 和其 retry/tool/review/compaction 子活动冻结 admission 时 generation，不逐字段热换。

正确性基线不依赖 mtime/size 或 watcher。实现可以在完整 bytes digest 相同后跳过重复 parse，但不增加 reload interval 或 watcher policy。REPL 保存使用 expected source digest、完整临时文件验证和可恢复原子替换，不能覆盖外部并发编辑。

## typed catalog（区域职责）

实现必须 **只** 从下列区域与后文逐字段表生成 parser/REPL/help/self-test；未列出的旧候选不得保留：

| 区域 | 正式职责 |
| --- | --- |
| `General` | schema 版本、`SystemPrompt`、`StartupSelfTest` |
| `TUI` | 启动头逐字段 bool；无 master/theme/language/mouse/Web |
| `Agent` | DoubleCheck 族、reviewer 选择、queue 上限、用户可收紧预算 |
| `Network` | Model HTTP 的 proxy/CA/no-proxy；无 UseStunnel/全局 Model retry/DirectHttp |
| `Exec` | raw shell 超时/输出/环境基线；无 PTY/background/direct HTTP |
| `Context` | 自动命名周期、列表排序、压缩触发比；无 workspace root 配置项 |
| `Permission.<Name>` | Description、SystemPrompt、五项 allow\|confirm\|deny |
| `Model.<Name>` | 完整连接实例（见下表） |

硬上限由发行 manifest 给出 **不可关闭** 基线。INI 只暴露允许用户 **收紧** 的预算；禁止把 request/turn/process hard cap 配成无限；无金额预算；无 Context lifetime hard ledger。

---

## W1-B 现行字段 catalog（权威）

### 列说明

| 列 | 含义 |
| --- | --- |
| Key | 规范拼写（PascalCase）；实现与 help 必须一致 |
| Type | 类型 / 枚举 |
| Default | 新模板与字段缺失时的行为（除非标 required） |
| Secret | 是否 registered config secret（禁止 argv/XML/普通日志/export 明文） |
| XML | 可否被 Context 白名单覆盖 |
| Notes | 消费者与不变量 |

**Sentinel：** 不用布尔 false 表示“无限”。可选上限用 **缺失 = 不额外收紧 / Runtime 默认**；关闭能力用枚举（如 `Streaming=off`）。

**禁止出现（非穷尽）：** `Permission.Cautious` 内置语义、`Permission.*.DoubleCheck`、`UseStunnel`、`UseTerminationEvaluator`、可关 finish 的 `DoubleCheckTargets`、`DirectHttp`/`DirectNetwork`、`SensitiveRead`、`Autonomy`、Web/telemetry/upload/update、`Language`/`Theme`/`Vivid`、`AutoJumpToDir`/`AutoNameOnExit`/`ResumeDirectory`、`Model.CustomPrompt`（迁到 SystemPrompt）、`CompactionModel`、金额字段、backup/undo 配置、multi-root、MCP/plugin。

### `[General]`

| Key | Type | Default | Secret | XML | Notes |
| --- | --- | --- | --- | --- | --- |
| SchemaVersion | string | 发行写入 | no | no | 迁移与拒绝不兼容 |
| SystemPrompt | UTF-8 text（有界） | 空 | no | no | Global Prompt；不能授权 |
| StartupSelfTest | off\|stage1\|stage2\|stage3 | off | no | no | Agent 入口 gate；非 TTY≥2 须 D-062 |

### `[TUI]` 启动头

| Key | Type | Default | Secret | XML | Notes |
| --- | --- | --- | --- | --- | --- |
| StartupShowSlogan | bool | true | no | no | 固定 `yaca: Yet Another Coding Agent.` |
| StartupShowVersion | bool | true | no | no | |
| StartupShowWorkDir | bool | true | no | no | |
| StartupShowDataRoot | bool | false | no | no | 默认隐藏 |
| StartupShowConfigStatus | bool | true | no | no | |
| StartupShowContext | bool | true | no | no | 无 XML 不伪造 |
| StartupShowContextHash | bool | true | no | no | D-059 大写 hex |
| StartupShowModel | bool | true | no | no | |
| StartupShowPermission | bool | true | no | no | |
| StartupShowDoubleCheck | bool | true | no | no | 有效值 |
| StartupShowStatusHint | bool | true | no | no | 提示 .status |

无 INI 主题/颜色系统；提示符色见 D-064。

### `[Agent]`

| Key | Type | Default | Secret | XML | Notes |
| --- | --- | --- | --- | --- | --- |
| DoubleCheck | bool | true | no | tri-state ov | true 时 finish review 不可关 |
| DoubleCheckGoal | text（有界） | 空 | no | override | 空则 Runtime 构造；不授权 |
| ActionReviewEnabled | bool | true | no | no | 仅 DoubleCheck 有效 true 时 |
| ActionReviewModel | Model 名或空 | 空=turn Model | no | no | 跨 endpoint 首次 disclosure |
| TerminationReviewModel | Model 名或空 | 空=turn Model | no | no | 与 Action 独立 |
| QueueMaxItems | int 1..RuntimeMax | **9** | no | no | D-066 |
| CompactThreshold | float (0,1) | 0.75 | no | 可选下调 | 只触发 model-view 压缩 |
| MaxTurnModelRequests | int optional | unset | no | 可选下调 | 不可超 Runtime hard |
| MaxTurnToolCalls | int optional | unset | no | 可选下调 | 同上 |
| StuckNoProgressRounds | int optional | unset | no | no | 默认 TP |

禁止 INI 关闭 hard cap；无金额字段。

### `[Network]`

| Key | Type | Default | Secret | XML | Notes |
| --- | --- | --- | --- | --- | --- |
| FollowProxy | bool | true | no | no | 不读任意 ambient curlrc |
| ProxyUrl | string | 空 | 含凭证则 secret | no | |
| NoProxy | string | 空 | no | no | |
| CaBundlePath | path | 发行 CA | no | no | |
| ConnectTimeoutMs | int optional | unset | no | no | |
| MaxResponseBytes | int optional | unset | no | no | |

无 UseStunnel；无全局 Model retry。

### `[Exec]`

| Key | Type | Default | Secret | XML | Notes |
| --- | --- | --- | --- | --- | --- |
| TimeoutMs | int optional | unset | no | no | |
| MaxOutputKB | int optional | 1024 | no | no | |
| EnvironmentMode | minimal\|inherit_filtered | minimal | no | no | 过滤表 TP |

### `[Context]`

| Key | Type | Default | Secret | XML | Notes |
| --- | --- | --- | --- | --- | --- |
| AutoNameEveryMainTurns | int ≥0 | 10（0=关） | no | no | durable completed main only |
| ListSortBy | created\|updated\|name | updated | no | no | 非 mtime |
| ListSortDirection | ascending\|descending | descending | no | no | LogicalPath tie-break 升序 |
| RecentListLimit | int optional | unset | no | no | |

无 AutoJumpToDir；无 root 配置项。

### `[Permission.<Name>]`

顺序第一 = 默认。发行模板：**Std** 然后 **Readonly**。

| Key | Type | Std | Readonly | Notes |
| --- | --- | --- | --- | --- |
| Description | string | 发行文案 | 发行文案 | 非授权 |
| SystemPrompt | text | 空 | 空 | 非授权 |
| Read | allow\|confirm\|deny | allow | allow | |
| Write | allow\|confirm\|deny | confirm | deny | |
| Delete | allow\|confirm\|deny | confirm | deny | |
| Shell | allow\|confirm\|deny | confirm | deny | |
| OutsideWorkspace | allow\|confirm\|deny | confirm | deny | |

### `[Model.<Name>]`

| Key | Type | Default | Secret | Notes |
| --- | --- | --- | --- | --- |
| Enabled | bool | 模板 | no | |
| Description | string | 空 | no | |
| Protocol | openai-chat\|anthropic-messages | required | no | |
| Endpoint | URL | required if enabled | no | HTTP 警告明文 |
| RemoteModel | string | required if enabled | no | |
| Key | string | 可空 | **yes** | 禁 XML/argv/export |
| SystemPrompt | text | 空 | no | |
| ContextLength | int or unset | 模板 | no | |
| MaxOutputTokens | int optional | unset | no | |
| Streaming | force\|try\|off | try | no | |
| RequestTimeoutMs | int optional | unset | no | |
| RetryCount | int ≥0 | 模板/Runtime | no | per Model |
| RetryBaseDelayMs | int optional | unset | no | |
| ToolsEnabled | bool | true | no | false 不可 main coding |
| AdapterOptions | typed map | 空 | 视键 | 未知键 error |

失败不自动换 Model。

### Context XML 白名单

`CurrentModel`, `CurrentPermission`, `DoubleCheckOverride` (inherit\|true\|false), `DoubleCheckGoalOverride`, `ContextPrompt`, `AutoRenameDisabled` (metadata)。

### 跨字段校验（必须）

1. Agent 需要 ≥1 可用 enabled Model（Endpoint/RemoteModel/Protocol 合法）。
2. Reviewer Model 名若非空必须 enabled。
3. CompactThreshold ∈ (0,1)；QueueMaxItems ∈ [1, RuntimeMax]。
4. Streaming=force 与能力冲突 → error。
5. 未知 section/key → generation 无效。
6. HTTP+Key → 保存警告。
7. 旧 CustomPrompt / Permission.DoubleCheck / Cautious 身份 → migration diagnostic。

### 发行模板骨架（示意）

```ini
[General]
SchemaVersion = 0.1.0
SystemPrompt =
StartupSelfTest = off

[TUI]
StartupShowSlogan = true
StartupShowVersion = true
StartupShowWorkDir = true
StartupShowDataRoot = false
StartupShowConfigStatus = true
StartupShowContext = true
StartupShowContextHash = true
StartupShowModel = true
StartupShowPermission = true
StartupShowDoubleCheck = true
StartupShowStatusHint = true

[Agent]
DoubleCheck = true
DoubleCheckGoal =
ActionReviewEnabled = true
ActionReviewModel =
TerminationReviewModel =
QueueMaxItems = 9
CompactThreshold = 0.75

[Network]
FollowProxy = true

[Exec]
MaxOutputKB = 1024
EnvironmentMode = minimal

[Context]
AutoNameEveryMainTurns = 10
ListSortBy = updated
ListSortDirection = descending

[Permission.Std]
Description = Standard: confirm write/delete/shell/outside
Read = allow
Write = confirm
Delete = confirm
Shell = confirm
OutsideWorkspace = confirm
SystemPrompt =

[Permission.Readonly]
Description = Readonly: deny mutating capabilities
Read = allow
Write = deny
Delete = deny
Shell = deny
OutsideWorkspace = deny
SystemPrompt =
```

### W1-B 完成定义

- [x] 唯一字段集合与禁止列表
- [x] 默认值（QueueMaxItems=9、排序、Permission 矩阵等）
- [x] XML 白名单与 secret 边界
- [x] 跨字段校验要点
- [ ] 多行 Prompt grammar + round-trip fixture
- [ ] RuntimeMax / 预算发行数字表
- [ ] 旧 ini migration 用例表
- [ ] AR-P0-09 规格侧勾选

### 下一步

**W1-C**：Context 内部 XML 事件与提交状态机（D-068 下仍必需）。

## 四层 Prompt 配置

正式 Prompt 字段是：

- `Global.SystemPrompt`；
- `Model.<Name>.SystemPrompt`；
- `Permission.<Name>.SystemPrompt`；
- Context XML 中的 `ContextPrompt`。

四层独立保存、验证和快照；没有“后一个字段覆盖并删除前一个字段”的合并。18 号系统按固定顺序构造请求：Runtime/purpose 契约之后依次加入 Global、Model，并只为 `main`/`side` 再加入 Permission、Context，最后发送独立用户消息。

review、compaction、self-test 和 context-name 继承 Global + 实际使用 Model 的 SystemPrompt，并使用 Runtime 固定 purpose prompt。Permission/Context 文本若为检查所需，只能作为有界 quoted data，不能取得特殊 purpose 的指令权威。

旧 `Model.CustomPrompt` 被正式 `Model.SystemPrompt` supersede，不形成 compatibility hint 或隐藏第五层。迁移必须逐 Model 保留原文、先验证目标再删除旧字段；不能猜成 Global/Context Prompt。任意 Prompt 都只是模型文本，不能授予 Permission 或开启功能。

某个 Prompt 可以建议模型使用 `backup/`，但 schema 不因此生成 backup/undo/restore 字段；Runtime、工具和配置系统不自动创建、复制、恢复或清理该目录。它完全是可选 Prompt 文案。

## Model 注册表

一个 `Model.<LogicalName>` 就是一份完整连接实例，不拆 Provider/Credential/secrets 文件。正式 adapter 值只有：

- `openai-chat`
- `anthropic-messages`

`openai-responses` 不进入 v0.1。两个 adapter 都必须完整支持 streaming、native structured tool/control、usage、errors、cancel 和 self-test fixture；不能从 endpoint/名称自动猜 adapter。

每个 Model 至少表达 endpoint、远端 model ID、明文 Key、窗口/输出上限、`SystemPrompt`、streaming、分阶段 deadline、retry、Description、enabled/capabilities 和 adapter 注册的 typed options。`Streaming=force|try|off`：`try` 只可在尚无 canonical response event、且明确证明不支持 streaming 时降级一次。retry 属于 Model，不自动切换到另一 Model。

Key 直接明文保存在主 INI，这是已接受的简单性选择；它仍属于 registered config secret。Key、代理凭据或 adapter secret 不得进入 argv、TUI 回显、普通错误、review Prompt、Context XML 或导出。主配置不制造含这些 secret 的长期 backup/export；原子提交所需短寿命 temp/recovery 不是用户备份。

## Network 配置

- HTTPS 使用随包、经平台验证的 curl/CA 基线，不依赖旧 Windows 系统 TLS 或 CentOS 7 系统 OpenSSL。
- 用户显式配置的 HTTP endpoint 完整允许，包括带 Key 的本地、内网或公开 endpoint；保存/改变为 HTTP 时明确提示 Key、Prompt 和回复可能明文传输。
- Runtime 永不把 HTTPS 自动降级到 HTTP，也不猜 scheme/port/endpoint。
- stunnel 是用户外部安装的兼容路线，不随包、不自动配置、没有 `UseStunnel`。self-test 可以诊断 TLS 问题并建议把 Model endpoint 显式指向本机 stunnel。
- 全局 proxy/CA 只用于 yaca Model HTTP，不传播给 raw shell。redirect 只 same-origin 自动跟随；cross-origin 要求用户修改 Model endpoint。
- 没有 DirectHttp/DirectNetwork 配置或 Permission 字段。

## DoubleCheck 配置

`DoubleCheck` 是 Agent 默认总开关；`.cautious` 只写当前 Context 的 `DoubleCheckOverride`，不切换 Permission 或修改 INI。命令语法见 **D-065**：无参 status；`on`/`off`/`toggle`/`reset`（`off`≠`reset`）。

- `DoubleCheck=false`：action/finish review 都停用。
- `DoubleCheck=true`：每个主模型 typed finish 必须完成独立 termination review；finish review 没有可关闭子开关。
- high-risk action review 是独立 boolean；它只在 DoubleCheck=true 时生效。
- action 与 termination reviewer 默认各使用当前 turn Model，也可以有彼此独立的 Model selector；跨 endpoint 首次使用按统一 disclosure consent。
- `DoubleCheckGoal` 是有界的 finish 验收目标：INI 提供默认，Context 可 override/reset；为空时 Runtime 从 task facts 构造。它不影响 action review 或 Permission。
- review 次数/墙钟/token/output 都受不可关闭 hard cap；失败、uncertain 或超限进入 waiting-user，不静默通过。

不再存在 `Cautious` Permission、profile 内 DoubleCheck、`UseTerminationEvaluator` 或允许关闭 finish review 的 `DoubleCheckTargets`。

## Context XML 白名单

Context XML 只允许保存当前会话真正需要的覆盖/元数据：

- `CurrentModel`
- `CurrentPermission`
- `DoubleCheckOverride=inherit|true|false`
- `DoubleCheckGoalOverride=inherit|value`
- `ContextPrompt`
- 专用 `AutoRenameDisabled` metadata

它不能覆盖 endpoint、Key、proxy/CA、Model/Permission 定义、五项 capability、Global/Model/Permission Prompt、reviewer Model 定义、Exec 环境或 hard-cap 基线。外来 XML 的同名 selector/Prompt/approval 都要按目标机器当前 schema 做 mapping；历史 snapshot 只解释过去，不自动激活本机安全配置。

`ContextPrompt` 通过 `.prompt` 或 `context-repl` 事务式编辑。`AutoRenameDisabled` 是专用 Context metadata，不是 INI override：手工 rename 默认同事务设为 true；取消时从当前 durable main-turn 水位重新建立命名周期，不追补旧周期。

## Context、TUI 与已删除旧字段

- 新 Context 初始名为 `Untitled Conversation [XXXX]`，四位大写 hex 只做同目录碰撞安全 fallback，不是 16 位实时路径 hash。
- `AutoNameEveryMainTurns=0` 关闭，默认 10；只计已 durable 收口的 main turn，退出不等待命名。
- Context 浏览有显式 `recent` 和 `full` 两个入口；recent 按 configured list order/limit 快速投影，full 访问完整 catalog/tree。
- 列表排序使用 created/updated/name 与 ascending/descending，默认 updated/descending。
- 删除 `AutoNameOnExit`、`AutoJumpToDir`、`ResumeDirectory`、project root list、永久 ContextId 和分支功能。
- 启动头没有总开关；每个启用字段独占一行。固定 Slogan 为 `yaca: Yet Another Coding Agent.`，chat prompt 为 `>>`。
- 删除 vivid/theme/language/mouse/Web/notification 空壳、全局 retry、generic extra parameter、`UseStunnel`、DirectHttp、SensitiveRead、Autonomy 和 backup/undo 配置。

## 三阶段 self-test

`General.StartupSelfTest=off|stage1|stage2|stage3` 默认 off。选择某阶段就必须当次严格执行 `1 -> 2 -> 3`；不能用缓存跳过依赖阶段。

1. Stage 1 离线检查 INI/schema/引用/顺序、文件与原子写入、Context mapping/XML/锁、catalog 扫描性能、包内组件和终端快捷键能力。达到 catalog hard cap 时报告 partial/ScanIncomplete，不能声称全量健康。
2. Stage 2 在一次清楚 consent 后，检查全部 enabled Model 的真实 DNS/TLS/proxy/auth、对应 `openai-chat|anthropic-messages` wire、stream、native tool/control、usage/cancel 能力，并继续收集全部失败。只有 required checks 全绿才进 Stage 3。
3. Stage 3 只使用 Stage 2 已通过且纳入范围的 Model，对脱敏配置做 advisory 审阅，检查 Model 名称/远端 ID/endpoint 和 Permission 名称/Description/SystemPrompt/矩阵的明显不一致与自然语言拼写；不修改配置、不授予能力、不推翻 Stage 1/2。

启动 gate 取消、失败或排除 required check/Model 时不进入 chat。显式 self-test 可以选择 through-stage、合法 exclusions 和 Model/check 范围，但参数组合不能跳过依赖。报告默认只显示/返回，不创建第三种永久日志文件。

## bootstrap 与 REPL

配置无效或没有有效 Model 时普通 Agent 阻断。help/version、self-test Stage 1、config-repl、model-repl 和不调用 Model 的 context-repl 使用内置 schema 的受限 bootstrap service；它们不启动 Agent/工具或把坏 generation 激活。

三个 REPL 各有本领域 `self-fix-program`：扫描 -> 展示 typed plan -> 用户确认 -> 原子发布；self-test 只诊断，不静默修复。model/config REPL 可在另一个 chat 活动时发布 INI，新值从那个 chat 的下一顶层 turn 生效；活动 writer 的 Context 不允许 context-repl mutation。

## schema 完整性门

typed schema 必须同时生成/校验默认值、INI parser/writer、REPL 表单/help、XML whitelist、secret registry/redaction、migration、self-test 和跨字段 fixture。任何字段只有 producer 没有 consumer，或只改文档没有改 redaction/lifecycle，都不构成完整配置项。

仍需技术证明的是：多行 Prompt 唯一 grammar、RuntimeMax 与各 optional 预算发行数字、INI round-trip、Win32/Win64/Linux 原子提交、secret ACL observation、AdapterOptions 键表和长配置性能。字段 **集合与默认** 以本文 W1-B catalog 为准；不再把 Prompt 层级、协议数量、HTTP/stunnel、OutsideWorkspace、DoubleCheck finish review 或 backup 功能重新列为产品问题。
