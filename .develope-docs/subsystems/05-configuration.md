# 05 配置与模型注册表

状态：产品配置面已确认；精确字段语法、默认数值与迁移 fixture 待技术证明

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

## typed catalog

逐字段 schema 的正式实现必须从以下已确认表面生成；未列出的候选字段不能因旧模板曾出现就保留：

| 区域 | 正式职责 |
| --- | --- |
| `General` | schema/version、`SystemPrompt`、`StartupSelfTest=off|stage1|stage2|stage3` 和必要诊断开关 |
| `TUI` | Slogan/Version/WorkDir/DataRoot/ConfigStatus/Context/Hash/Model/Permission/DoubleCheck/StatusHint 的逐字段启动显示；没有 master、theme/vivid/language/mouse/Web 配置 |
| `Agent` | `DoubleCheck`、finish goal、独立 high-risk action-review 开关、各自 reviewer selector、stuck 阈值和允许用户收紧的 hard budgets |
| `Network` | Model HTTP 共用的 Proxy/CA/no-proxy/资源策略；没有 direct HTTP transport、`UseStunnel` 或全局 Model retry |
| `Exec` | raw shell 的允许用户收紧的 timeout/output/resource 与受控 environment baseline；没有 PTY/background job/direct HTTP profile |
| `Context` | 自动命名周期、recent/full 列表/排序、压缩触发偏好；workspace root 是镜像路径派生事实，不是自由配置 |
| `Permission.*` | `Description`、`SystemPrompt` 以及 `Read/Write/Delete/Shell/OutsideWorkspace` 五项 `allow|confirm|deny` |
| `Model.*` | 一个完整 LLM 连接实例的 protocol/endpoint/model/key/capability/SystemPrompt/streaming/deadline/retry/output/typed adapter options |

硬上限由发行版给出不可关闭基线。INI 只暴露确有消费者且允许收紧的预算，不允许把 request/turn/process hard cap 设为无限，也不提供 Context lifetime hard ledger 或默认金额预算。

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

`DoubleCheck` 是 Agent 默认总开关；`.cautious` 只写当前 Context 的 `DoubleCheckOverride`，不切换 Permission 或修改 INI。

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

仍需技术证明的是：字段精确拼写与多行/escaping 语法、默认数值、INI round-trip、Win32/Win64/Linux 原子提交、secret ACL observation、OpenAI/Anthropic adapter options 和长配置性能；不再把 Prompt 层级、协议数量、HTTP/stunnel、OutsideWorkspace、DoubleCheck finish review 或 backup 功能重新列为产品问题。
