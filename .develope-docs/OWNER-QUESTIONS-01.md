# 项目负责人集中决策包 01

更新日期：2026-07-22

状态：已于 2026-07-22 全部回复；本文件保留为 `decision-inventory-v9` 的冻结提问证据

## 当前答复入口

项目负责人对 29 题的原话、随后逐项确认、冲突归一和条件重算已经归档到 [`DISCUSSION-BATCH-06.md`](DISCUSSION-BATCH-06.md)。现行结论写入 [`DECISIONS.md`](DECISIONS.md) 的 D-049 至 D-057，并传播到各 owner 子系统文档。本文件下面的 A/B/C 仍逐字保留收到回复时的候选空间；其中的“推荐”不再表示当前待答项，也不能覆盖答复中的例外。

当前没有遗留给项目负责人的集中补问。产品选择完成不等于技术证明或实施计划完成；后续状态以 [`DECISION-REGISTER.md`](DECISION-REGISTER.md) 与 [`ARCHITECTURE-READINESS.md`](ARCHITECTURE-READINESS.md) 为准。

## 当时的回复说明（历史）

这份问卷把原登记表中的 248 个 `unanswered` 收成 28 个产品/风险选择，再加 1 个负责人批注的语义补问，共 29 题。248 个原子组继续用于完整性审计，不再要求项目负责人逐条回答。库、API、内部状态字段、错误编号、默认毫秒数、缓冲区大小、退避公式、XML 解析器和编译参数等实现细节，由技术证明选择并写入规格。

可以直接回复：

```text
全部按推荐。
例外：CQ-07 B；CQ-09 B；CQ-19 的 Outside 使用粗粒度。
```

当时也允许逐项回复 `CQ-01 A`；没有明确回复的集中问题会继续待决。该流程现已完成：Batch 06 保存原话与冲突归一，projection 将集中答案确定展开到 248 个原子组。本段只解释冻结问卷当时怎样使用，不是新的答题入口。

## 已确认前提，不再重复投票

- yaca 是 Lua 5.5、单 Agent、terminal-only 的 Coding Agent；不提供 Web、媒体、remote/headless、MCP、插件或多根 workspace。
- 收到本问卷回复前的冻结前提是 Windows 只发布 Win32 x86；RB-006-01/02 已明确修订为 Win32 x86、Win64 x86_64 与 Linux x86_64 三个独立 zip。这里保留该差异用于审计旧选项语境。
- 一个 Context 只有一个固定 workspace root；Context 是单 XML，逻辑路径的 16 字符 hash 实时计算，没有永久 ContextId。
- 裸 `yaca` 等于 `yaca .`，直接建立未保存的新 chat；历史只能显式选择。
- `DoubleCheck` 是一个总开关，开启时包含完成复核；`.cautious` 是 Context 级覆盖。
- Model 和 Permission 都按 INI 中的顺序决定默认项；一个 Model section 表示一份完整 LLM 连接实例；Key 明文保存在主 INI。
- 固定输入意图仍是 Enter 排队、Ctrl+Enter steer、Shift+Enter 换行、Alt+Enter side、Esc 取消；本包只决定旧终端怎样可靠兑现它们。

## CQ-01 默认交流风格

普通 chat 中，模型默认应该怎样说话？这里不改变用户可以明确要求“详细解释”或“只给结果”的能力。

- A：跟随用户消息语言；结果优先、默认简洁；复杂任务只在阶段变化或等待时给短进度；结束时列结果、改动、验证和未确认事项。（推荐）
- B：跟随用户语言；默认采用教学式详细讲解，每个重要动作都说明原因。
- C：跟随用户语言；默认极简，只在阻塞、审批和最终结果时输出必要文字。

推荐 A。它适合日常 Coding Agent，又能在设计讨论中按用户要求展开。程序固定 UI、配置键和机器字段仍为 English/ASCII。

覆盖：`PP-01`、`PP-02`、`PP-06`、`PP-14`、`PP-15`、`PP-16`。

## CQ-02 何时询问，何时自行推进

模型遇到不完整信息时，什么情况必须停下来问用户？

- A：只有不同答案会实质改变目标、安全、费用、不可逆副作用或公开结果时才问；其余采用最小风险假设继续，并明确写出假设。（推荐）
- B：只要存在两种合理理解就先问，不带假设推进。
- C：除 Runtime 必须取得的审批外一律自行选择，不主动澄清。

推荐 A。它保持模型主导，又不会替用户猜高影响决定。不增加独立 `Autonomy` 模式；自然语言 Prompt 可以调整措辞，但不能扩大 Permission。

覆盖：`PP-17`、`TS-18`。

## CQ-03 Prompt、项目规则与版本变化

`SystemPrompt`、当前 Permission 的 `SystemPrompt`、`ContextPrompt`、当前用户消息以及仓库里的说明文件怎样组成一次请求？Permission Prompt 已确认存在，但它只是模型指令，不能改变真实权限。

- A：不可覆盖的 Runtime 完整性规则最高；用户层为“当前用户消息 > ContextPrompt > Permission.SystemPrompt > 全局 SystemPrompt”。项目文件只是数据，不自动升级成指令；用户可要求模型读取。新 turn 使用当前 Prompt bundle，并把实际来源、版本和有效快照写入 XML。（推荐）
- B：采用 A 的权威链，但在 ContextPrompt 与 Permission.SystemPrompt 之间自动发现并加载 workspace root 的一个固定项目规则文件；规则不能扩大 Permission，变化在下一 turn 显示后采用。
- C：采用 A 的权威链，并在相同位置支持从 root 到当前目录的分层项目规则；越接近当前目录优先级越高，每层来源和变化都进入请求快照。

推荐 A。它符合“需要项目说明时由用户整理并让模型阅读”，也最少产生仓库 Prompt injection 和旧规则漂移。所有方案中 `.prompt` 都是 ContextPrompt 的事务式编辑；旧 `Model.CustomPrompt` 只迁移或报错，不形成第三条隐含 Prompt 链。`Permission.SystemPrompt` 只作为 `main` 请求的独立组件；self-test/review/compaction 若需要检查它，只把它作为有边界的 quoted data，不继承其指令权威。

覆盖：`PP-03`、`PP-04`、`PP-05`、`PP-07`、`PP-08`、`PP-09`、`PP-11`、`PP-12`、`PP-13`、`PP-18`、`PP-19`。

## CQ-04 传入目录与 Git 根的关系

用户在仓库子目录运行 `yaca subdir` 时，真正的 workspace root 是什么？

- A：传入且可进入的真实目录就是唯一 root；上级 Git 根只作为 status/diff 元数据，不扩大文件、指令或 Permission 边界。（推荐）
- B：发现上级 Git 根时自动把它提升为 root，并在启动信息中显示提升结果。
- C：发现二者不同时，在第一条 main 消息前要求用户选择传入目录或 Git 根。

推荐 A。路径、Context 镜像和安全边界最可预测，也符合 `yaca [directory]` 的字面含义。活动期间 root 消失或身份改变都停止新副作用，进入 context self-fix，不猜同名目录。

覆盖：`F4-12`、`F4-14`。

## CQ-05 一个进程可以同时拥有几个活动 Context

这里讨论一个 yaca 进程内部，不限制用户另开进程处理另一个 Context。

- A：恰好一个 active Context；显式切换前先收口当前 turn、writer、side 和草稿。（推荐）
- B：可以只读加载多个 Context，但同一时刻只有一个拥有 writer/AgentLoop。
- C：多个 Context 可以在同一进程并发运行各自 AgentLoop。

推荐 A。它与单 Agent、单 TUI 焦点和旧系统资源目标一致；B/C 会引入多 writer、调度、取消归属和恢复页面。

覆盖：`F4-15`。

## CQ-06 TUI 的页面风格

在 XP 控制台、旧 Linux 终端和现代终端上，规范界面应该长什么样？

- A：追加式逐行 transcript；少量基础色和高亮；固定 English/ASCII 标签；代码和 Git diff 做有限语法/增删高亮；工具默认显示摘要与有界 preview；能力不足自动降级；不发系统通知。（推荐）
- B：仍是逐行 transcript，但显示更多常驻状态、分隔线和完成通知；支持用户显式开启终端铃声/系统通知。
- C：最小无色逐行文本；代码、diff 和状态都只使用 ASCII 标签，不做颜色或通知。

推荐 A。它保持 yaca 简洁，同时明显优于纯日志；不是全屏 dashboard，也不提供鼠标或显示模式开关。

覆盖：`TU-01`、`TU-02`、`TU-06`、`TU-14`、`TU-20`、`TU-26`、`TU-27`、`TU-29`、`TU-30`、`TU-33`。

## CQ-07 输入、异步输出与菜单

固定快捷键在旧终端不一定都能区分，同时 streaming 和工具输出不能破坏正在输入的 draft。采用哪条兼容路线？

- A：能力允许时使用 raw/native key events 兑现固定快捷键；始终提供等价点命令后备。异步块只追加，不覆盖 draft；Esc 按当前焦点取消最内层活动。审批和 REPL 使用编号 + 完整动作词，空 Enter 默认拒绝/取消，编辑参数会使旧审批失效。（推荐）
- B：所有平台只使用 cooked line 和点命令；组合键仅作不可承诺的增强提示。
- C：把 raw/native key events 作为硬要求；无法区分固定快捷键的终端拒绝进入交互 chat。

推荐 A。现代体验完整，旧终端仍能完成所有动作。输入召回只保留当前进程已提交的普通用户文本；秘密、审批输入和未提交 draft 不进历史。

覆盖：`TU-03`、`TU-04`、`TU-05`、`TU-07`、`TU-08`、`TU-15`、`TU-16`、`TU-17`、`TU-25`、`TU-28`、`TU-31`、`TU-34`、`F4-05`、`F4-06`、`F4-09`。

## CQ-08 CLI、REPL、Help 与非 TTY

所有 TUI 领域动作都要有 CLI 投影，但不需要维护两套含义。正式 argv 采用哪种风格？

- A：保持现有 long-option 风格：`yaca [directory]`、`--continue`、`--model-repl`、`--config-repl`、`--context-repl`、`--self-test[=stage]`、`--help`、`--version`；除 `-h/-v` 外不承诺短别名，`--` 结束选项。非 TTY 只有显式完整参数才能运行，`--json` 输出稳定事件且绝不弹交互审批。（推荐）
- B：采用 subcommand：`yaca model-repl`、`yaca context-repl`、`yaca self-test`；flags 只修饰动作。
- C：A/B 两套拼写都作为永久等价契约并完整测试。

推荐 A。它与负责人已经使用的命令形式一致，并从根源消除 `-dc/-rc` 冲突。chat 保持平坦 dot roots；`.model` picker 与 `.model NAME` 仍是同一动作。

覆盖：`TU-10`、`TU-11`、`TU-13`、`TU-18`、`TU-19`、`TU-21`、`TU-22`、`TU-23`、`TU-24`。

## CQ-09 v0.1 的 Model wire protocol

“OpenAI-compatible”不等于 Anthropic Messages 或 OpenAI Responses；每增加一套都要完整测试 streaming、tools、usage、errors 和 retry。

- A：v0.1 只正式支持 `openai-chat` compatible。（推荐）
- B：同时支持 `openai-chat` 与 `anthropic-messages`。
- C：同时支持 `openai-chat`、`openai-responses` 与 `anthropic-messages`。

推荐 A。先把一套协议在旧平台上闭环最稳；以后新增 adapter 不改变“一个 Model 是完整连接实例”的配置模型。结构化 tool/control 是正式能力，不做自然语言模拟 tool calling。

覆盖：`M05-01`、`M05-02`、`M05-03`、`M05-23`、`M05-25`、`M05-26`、`M05-40`。

## CQ-10 Model 与主配置的复杂度

主 INI 既要能手工维护，也要能由 REPL 安全编辑。首版暴露多少配置能力？

- A：每个 Model 只包含完整连接、能力、streaming、timeout/retry、输出限制、Description 和 adapter 注册的 typed options；配置顺序决定默认。INI 可手工编辑，REPL 事务式编辑并共用同一 schema。XML 只覆盖 CurrentModel、CurrentPermission、DoubleCheck 的会话字段和 ContextPrompt。Key 明文只保存在主 INI，不做含 Key 的 backup/export。（推荐）
- B：在 A 上增加自由 public/secret headers、更多 XML 会话覆盖、价格、颜色和资源简称。
- C：比 A 更窄：不允许 XML 覆盖 Model/Permission/DoubleCheck，只能修改 ContextPrompt；所有生成参数使用 endpoint 默认。

推荐 A。功能完整但没有无消费者字段；unknown/重复/越界字段使候选 generation 无效，旧有效配置不被半写覆盖。每个新顶层 turn 自动观察完整 INI，变化后整份验证并一次生效。

覆盖：`M05-05`、`M05-06`、`M05-07`、`M05-08`、`M05-09`、`M05-17`、`M05-18`、`M05-19`、`M05-20`、`M05-21`、`M05-22`、`M05-27`、`M05-28`、`M05-29`、`M05-30`、`M05-32`、`M05-33`、`M05-34`、`M05-42`、`M05-43`、`M05-44`、`M05-45`、`M05-47`、`M05-52`、`M05-54`、`M05-57`、`M05-59`。

## CQ-11 网络、TLS 与自动重试

模型连接需要兼容本地 endpoint、企业代理和旧系统 CA，但不能因为兼容而静默泄露 Key 或重放已开始的生成。

- A：HTTPS 正常允许；HTTP 只允许可证明的 loopback 且无鉴权。全局 Proxy=`off|environment|explicit`，CA=`bundled|system|custom|combined`，只自动跟随 same-origin redirect。公开分阶段 deadline 和每 Model retry；任何 canonical response event 到达后不自动重发。（推荐）
- B：更严格：只允许 HTTPS，Proxy=`off|explicit`，拒绝全部 redirect；网络失败由用户手工 retry。
- C：更兼容：允许显式 private-LAN HTTP 和经确认的跨-origin redirect；仍禁止通过 HTTP 发送 Key，且每次新 origin 都要确认。

推荐 A。覆盖旧系统和企业环境，同时保持费用、副作用和凭据边界可解释。`Streaming=try` 只在尚无响应且得到“不支持 streaming”的明确证据时降级一次。

覆盖：`M05-04`、`M05-13`、`M05-14`、`M05-36`、`M05-37`、`M05-38`、`M05-58`。

## CQ-12 Self-Test 的实际深度

Stage 1/2/3 已确认顺序执行；这里决定“完整通过”到底要检查什么。

- A：Stage 1 离线检查配置、文件、Context mapping、索引性能和包内组件；Stage 2 经一次清楚 consent 后检查全部 enabled Model 的真实 auth/stream/tool/control 能力，并继续收集全部失败；只有 required checks 全绿才进 Stage 3。Stage 3 使用已通过 Model 做 advisory 合理性审阅，不改配置。（推荐）
- B：Stage 2 只做最小连接检查；stream/tool/control 另作为可选 deep checks，未运行时报告 partial。
- C：Stage 2 除 enabled Model 外也联网检查所有完整的 disabled draft；它们失败不阻断 Stage 3，但必须显示。

推荐 A。它最符合“self-test 很强大”，同时让离线静态事实、真实联网能力和 LLM 建议保持不同证据等级。报告默认只显示/返回，不额外创建永久日志文件。

覆盖：`M05-11`、`M05-12`、`M05-31`、`M05-35`、`M05-41`、`M05-46`、`M05-53`。

## CQ-13 AgentLoop 怎样表达完成、提问和拒绝

主模型主导完成，但普通文本不能可靠区分“做完了”“还在解释”或“等用户回答”。

- A：Runtime 向模型提供固定 typed controls：`finish`、`ask-user`、`refuse`。工具和文本可以正常混合；没有 control 的完整普通回复保存为 `model-yield` 并进入 waiting-user，不自动算完成。Runtime 只校验工具配对、持久化和真实副作用状态。（推荐）
- B：仍提供 typed controls，但完整普通回复没有工具时最多追加一次只允许 control 的纠错请求；再次缺失才 waiting-user。
- C：provider 的普通 stop 在没有未完成工具时隐式等于 `finish(completed)`。

推荐 A。它保持“模型决定完成”，又不把自然语言猜测写进 Runtime。`ask-user` 回答继续同一 turn；一个 Context 同时只保留一个需要普通 Enter 回答的 pending question，其他新输入保持显式 queue/steer 意图。

覆盖：`AL06-01`、`AL06-02`、`AL06-13`、`AL06-18`、`AL06-19`、`AL06-36`、`AL06-37`、`AL06-38`、`AL06-48`、`F4-03`、`F4-16`、`F4-17`。

## CQ-14 Queue、Steer、Side 与取消

忙时的四种输入都已经确定；这里决定它们怎样调度。

- A：queue 只在上一 turn `completed` 且没有 pending/unknown 时自动启动；支持 list/drop/edit/reorder/clear。steer 取消可取消的模型/review和未开始工具，在同一 turn 注入。最多一个 side 与 main 并发，新 side 忙时拒绝并保留 draft。Esc 按焦点取消最内层活动。（推荐）
- B：queue 永不自动启动且只支持 list/drop/clear；steer 等当前 tool batch 收口后注入；side 与 main 串行。
- C：queue 在 completed/refused 后都自动启动；允许一个 active side 加一个 pending side；steer 不取消已接受 batch。

推荐 A。它最接近负责人指定的快捷键含义，同时每条 lane 都有硬上限。不同 purpose 对同一 Model 的并发、间隔和 cooldown 由一个有界 scheduler 串行/限流，不让后台请求绕过 Model 配置。

覆盖：`AL06-04`、`AL06-05`、`AL06-06`、`AL06-14`、`AL06-20`、`AL06-22`、`AL06-23`、`AL06-33`、`AL06-35`、`F4-02`。

## CQ-15 “DoubleCheck 可以设定目标”具体指什么

这句批注意味不同，会产生完全不同的配置和 Prompt。这里先只确认“目标”的含义，不顺带猜 reviewer 或失败控制流。

- A：目标是完成复核要检查的任务目标/验收标准，字段为有界 `DoubleCheckGoal`；INI 可给默认值，Context XML 可 override/reset，为空时从当前任务事实构造检查输入。（推荐）
- B：目标是哪些事件触发复核，即 `DoubleCheckTargets`；不增加自由文本 Goal。
- C：目标是复核请求使用哪个 Model；不增加自由文本 Goal，也不把触发范围称为目标。

推荐 A。该批注出现在“不要独立 plan state”的语境下，最自然的含义是给完成复核一组验收标准。无论选择哪项，它都不改变 Permission，也不让模型自行扩大工具能力。

覆盖：负责人批注 `B04/RB-004-11`；这是对既有原子组之前缺失语义的补缝，不另造重复 group。

## CQ-16 DoubleCheck 的触发范围、Reviewer 与失败行为

总开关已经确认包含完成复核；这里独立决定是否也复核动作、使用哪个 Model，以及 reviewer 失败时怎样收口。若 CQ-15=A，`DoubleCheckGoal` 只约束 finish review，不作为 action approval 文本。

- A：默认 targets 为 `finish,high-risk-action`，两项可单独关闭，但总 `DoubleCheck=false` 时都停用；两类复核默认各自使用当前 turn 的 Model，也可分别配置 `TerminationReviewModel` 与 `ActionReviewModel`。跨 Endpoint 首次使用要确认。action reviewer 不能放宽 Permission；finish reviewer 指出明确缺口时在同一 turn 继续，uncertain/失败/超上限时进入 waiting-user。（推荐）
- B：只复核 finish，不复核工具动作；默认使用当前 Model，也可单独配置 `TerminationReviewModel`，失败时进入 waiting-user。
- C：复核所有 executable tools 和 finish；两类复核都必须分别配置 reviewer Model，任何 reviewer 失败都拒绝动作或停止完成。

推荐 A。它直接兑现“花费更多时间和 Token，获得更多安全”，又不让普通只读工具都增加一次模型请求。人工只能覆盖 reviewer 的建议，不能覆盖 Permission=deny 或未知副作用；pending approval 恢复后必须重新确认。

覆盖：`M05-39`、`AL06-07`、`AL06-08`、`AL06-24`、`AL06-25`、`AL06-26`、`AL06-27`、`AL06-40`、`AL06-41`、`AL06-44`、`AL06-45`、`AL06-49`、`AL06-51`。

## CQ-17 预算、Retry、卡死与验证义务

AgentLoop 不能无限请求，也不能把一次失败伪装成完成。

- A：request、turn 和进程都有不可关闭 hard caps；Context 只累计审计，不因历史总量永久锁死。用户配置只能在安全范围内收紧。安全 retry 有界；无进展先警告并允许一次策略改变，再 `stuck`。存在明显且安全的验证命令时默认运行；无法验证就如实报告。（推荐）
- B：在 A 上增加 Context 级 hard token/request/tool ledger，并允许配置价格快照和金额门。
- C：只使用发行版固定 hard caps，不暴露任何预算/阈值字段；一旦检测到 stuck 立即停止，不给 escape step。

推荐 A。它有完整防卡死边界，但不让长期 Context 因过去消耗永久不可用。yaca 默认不计算货币金额，只区分 provider reported/estimated token usage。

覆盖：`M05-50`、`AL06-09`、`AL06-10`、`AL06-12`、`AL06-15`、`AL06-17`、`AL06-28`、`AL06-29`、`AL06-42`、`AL06-43`、`AL06-46`、`AL06-50`、`F4-04`。

## CQ-18 长 Context 的压缩方式

XML 必须保留完整事实；压缩只改变下一次发给模型的 view。

- A：结构化摘要前缀 + 最近完整 atomic groups；默认使用当前 Model 生成摘要，保存来源范围、Model 和 view manifest。用户可查看/纠正；摘要失败不破坏旧 view。若已知已配置 Model 有更大窗口，优先提示，不自动切换。（推荐）
- B：只使用 deterministic extractive checkpoint + 最近完整 groups，不发摘要 Model 请求。
- C：不压缩；只保留能完整容纳的最新 groups，超限时停止并要求用户换 Model 或新建 Context。

推荐 A。语义密度和可接盘性最好，完整 XML 仍是事实源。单个不可分割 group 本身超窗时必须停止，不能截成半条工具调用或半个结果。

覆盖：`AL06-11`、`AL06-16`、`AL06-30`、`AL06-31`、`AL06-34`、`AL06-39`、`AL06-47`。

## CQ-19 首版 Tool Calling 表面

“相信模型、调用原始工具”仍需要一份固定 tool schema，才能正确配对、审批、恢复和记录；它不等于 OS sandbox。

- A：`list/read/search/write/patch/rename/delete/exec` 全部进入首版；direct tools 使用严格 typed fields，`exec` 只有一个 opaque 原始 command string；所有工具串行。（推荐）
- B：只提供 `list/read/search/exec`；所有文件修改、重命名和删除都通过获批 raw shell。
- C：提供 `list/read/search/write/patch/exec`；rename/delete 通过 raw shell。

推荐 A。它是完整 Coding Agent 闭环，也让常见文件改动拥有 expected digest、冲突检测和清楚 diff。文本支持 ASCII/严格 UTF-8 及 BOM UTF-16；二进制 direct read 默认只返回 metadata/size/digest，隐式搜索永不进入 `__yaca__` reserved tree。

覆盖：`TS-02`、`TS-16`、`TS-17`、`TS-23`、`TS-27`、`TS-32`、`TS-33`、`TS-36`、`TS-38`、`TS-39`。

## CQ-20 Permission 的完整形状

Permission 的名字、Description 和 Prompt 只帮助理解，真实授权始终由字段矩阵决定。

- A：能力为 `Read/Write/Delete/Shell/OutsideRead/OutsideWrite/OutsideDelete`，每项 `allow|confirm|deny`；模板顺序为 Std、Readonly、Trusted，并允许自定义 section/Prompt。只有 allow-once，不增加持久授权、SensitiveRead 启发式、Autonomy 或 sandbox 声明。（推荐）
- B：使用更短的 `Read/Write/Delete/Shell/OutsideWorkspace`；模板只有 Std、Readonly；减少确认依靠切换 profile。
- C：采用 A 的矩阵，并增加 identical-for-turn 与当前进程 session grants，以及独立 SensitiveRead 分类。

推荐 A。它能表达“仓库外 SDK 可读但不可写”，同时授权生命周期仍简单。Std 默认普通 workspace read=allow，其余危险能力 confirm；Readonly 除 read 外 deny；Trusted 对已存在能力 allow。第一项仍是默认，但名称永远不产生权限。

覆盖：`M05-16`、`M05-48`、`M05-49`、`M05-56`、`TS-04`、`TS-05`、`TS-07`、`TS-14`、`TS-21`、`TS-40`。

## CQ-21 Raw shell、进程和直接网络

raw shell 是宽能力，Runtime 不解析 command 来伪造细粒度 containment。

- A：Windows 固定 `cmd.exe /d /s /c`，Linux 固定 `/bin/sh -c`；继承经过冻结和脱敏的宿主环境基线；只支持非交互 foreground，统一收口进程树和 stdout/stderr；无 PTY、tracked background job 或 direct HTTP tool。（推荐）
- B：在 A 上增加一等 tracked background jobs，提供 list/wait/cancel/reconcile；仍不提供 direct HTTP。
- C：在 B 上再增加独立、受 Permission 和 origin allowlist 控制的 typed HTTP tool。

推荐 A。模型仍可在 Shell 获批后运行 curl 或平台工具，但 yaca 不额外维护第二套网络凭据和 job scheduler。超长或不可无损传输的 command 在 spawn 前失败，不写临时脚本冒充同一调用。

覆盖：`M05-15`、`M05-51`、`M05-55`、`TS-10`、`TS-11`、`TS-12`、`TS-13`、`TS-20`、`TS-22`、`TS-24`、`TS-30`、`TS-37`、`F4-07`、`F4-11`。

## CQ-22 文件改动、Git、Undo 与二进制

Coding Agent 能修改文件，但首版对“可以恢复”承诺到哪一层？

- A：direct 写入使用 expected raw-byte digest、no-replace/atomic publish 和 diff 证据；Git 只提供 status/diff 增强，commit/push/reset/stash 仅在用户明确要求时作为 raw shell。无通用自动 undo；direct delete 只处理文件或空目录；不提供 direct binary mutation。（推荐）
- B：在 A 上增加受配额保护的完整 preimage undo、递归 direct delete 和小型 base64 binary create/replace。
- C：把 Git 当作工作流控制，Runtime 自动 stash/commit，并用 Git 回滚受管改动。

推荐 A。它不把 raw shell、外部进程或非 Git 目录宣传成可自动回滚，也避免完整 preimage 把源码和未知秘密复制进 XML。

覆盖：`TS-08`、`TS-19`、`TS-25`、`TS-26`、`TS-28`、`TS-29`、`TS-31`、`TS-34`、`TS-35`。

## CQ-23 单 XML 的物理提交与辅助文件

“用户数据只有 INI/XML”需要区分长期事实与事务过程；合法 XML 不能在根结束标签后无限原地追加事件。

- A：长期事实只有主 INI 和每个 Context XML；允许同目录短寿命 temp、lock 和 previous-valid recovery 文件。每次从旧 XML 流式生成完整新 XML，flush/验证后原子或可恢复替换；没有长期 WAL/sidecar。（推荐）
- B：允许一个短期 WAL/recovery sidecar 先追加事件，再周期性合并回 XML；XML 仍是可导出的主事实。
- C：字面禁止任何非 INI/XML 辅助文件，包括 temp/lock/previous；若平台无法同时证明并发和崩溃安全，就只允许只读打开。

推荐 A。它最符合“复制 XML 接盘”和文件简洁要求；代价是提交成本随 XML 增长，必须通过 XP x86 长会话基准决定 hard quota。磁盘满、replace 失败或第二 writer 都不能发布半份 XML。

覆盖：`CX-01`、`CX-05`、`CX-11`、`F4-10`。

## CQ-24 外来 XML 怎样导入并继续

已经确认活动 XML 本身就是完整接盘文件：它以公开明文 schema 保存 canonical 对话、工具事实、Prompt/配置/Model/Permission snapshots、Model 切换、压缩 view 和未知副作用；不保存 Key、Runtime 隐藏推理或无限原始字节。这里不重开这些决定，只决定另一台机器怎样把一份外来 XML 变成可写 Context。

- A：`context-repl` 先只读完成 schema/大小/一致性检查和 Model/workspace/Permission mapping，再以 no-replace 把验证后的副本发布到本机正确镜像位置；不修改来源文件。历史 approval/grant 永远只作审计，用户确认映射后新副本可以继续。（推荐）
- B：用户先自行把 XML 放进正确镜像位置；yaca 原地只读检查并确认映射，成功后直接取得该文件的 writer，不额外保留导入副本。
- C：所有外来 XML 永远只读打开；若要继续，用户必须显式执行 `clone-to-local-context`，以新名称和当前映射建立另一份可写 XML。

推荐 A。它既保持“复制 XML 就能接盘”，又不会在验证完成前改写唯一来源。格式和 schema 公开，第三方可以编写 reader；不承诺 Codex/CodeWhale 无适配直接原生读取。普通正文仍可能含 Runtime 不认识的秘密，导入页必须明示明文隐私边界。

覆盖：`CX-02`、`CX-07`、`CX-14`、`CX-16`、`CX-17`、`CX-18`。

## CQ-25 Context 浏览、删除与外部改写

`context-repl` 既是浏览器，也是本领域 self-fix 程序。

- A：从 invocation/current workspace 对应镜像目录进入，提供有界目录树、搜索、详情、rename、trash/restore 和显式 purge；活动锁对象不可管理编辑。selection stale 或 active XML 被移动/替换/改写时 fail-stop，由用户显式刷新、rebind、恢复 previous-valid 或退出。（推荐）
- B：首页先显示全局 recent；纯移动时可按精确 digest 扫描并给 rebind 建议；其余同 A。
- C：只提供目录树、搜索、rename 和永久 delete；不提供 trash/restore，也不扫描移动候选。

推荐 A。它延续当前目录 Resolver 心智，避免全盘扫描和按内容猜身份。16 字符 hash 用小写 hex；重命名成功后实时 hash 立即变化，旧 hash 不保留别名。

覆盖：`AL06-32`、`CX-08`、`CX-09`、`CX-10`、`CX-15`、`CX-19`、`CX-20`、`F4-08`。

## CQ-26 错误、退出、日志和诊断外发

用户需要知道哪里失败、保存了什么和下一步，但负责人要求长期用户文件保持 INI/XML。

- A：稳定 error ID + 简明消息 + `.details`；retry 显示次数并可取消；Ctrl+C/Esc/EOF/broken pipe 都由统一 close 状态机收口，副作用 unknown 就明确标 unknown。诊断只在终端、self-test/support 输出和 Context XML 审计中保存；无独立日志文件、遥测或上传。（推荐）
- B：A 加本地轮换诊断日志和用户显式生成的 support bundle；仍不联网上传。
- C：B 加用户显式一次性诊断上传和 opt-in aggregate telemetry。

推荐 A。最符合离线、隐私和“两种长期格式”的方向。配置/Context 尚未建立前的 fatal error 仍输出 stderr 和稳定 process exit code，不为此创建第三种永久文件。

覆盖：`ED-01`、`ED-02`、`ED-03`、`ED-04`、`ED-05`、`ED-06`、`ED-07`、`ED-08`、`ED-09`、`ED-10`、`ED-11`、`ED-12`、`ED-13`、`ED-14`。

## CQ-27 Zip、数据根与升级

不同平台独立 zip 已确认；这里决定用户怎样运行和保留 `__yaca__`。

- A：portable zip 是正式入口，解压即运行；数据根是程序旁的 `__yaca__`。升级采用 side-by-side 解压，用户显式选择旧数据并做验证后迁移；卸载默认保留数据，永久删除单独确认。（推荐）
- B：zip 中的 luainstaller 安装入口是正式入口；程序安装到 application tree，`__yaca__` 使用系统用户数据目录；升级可覆盖程序但数据仍先备份/迁移。
- C：同一 zip 同时正式支持 portable 与 installed，两条入口都完整测试；各自使用邻接/系统数据根。

推荐 A。旧系统离线使用和搬移最简单，也与“Release 是一个 zip”一致。不可写时明确失败，不静默换 data root。

覆盖：`RF-01`、`RF-02`、`RF-03`。

## CQ-28 luainstaller x86/XP qualification 与兄弟仓库范围

先更正事实：当前检出的 luainstaller 1.0 认识 `x86`，但公开 Windows profile guard 会拒绝非 x86_64，随附 MSVC recipe/tests 也固定为 x64；这证明当前默认路径不能直接发布 yaca x86 包，却不证明 launcher/bundler 底层无法支持 x86，也没有证明 XP 不兼容。正确动作是先 qualification，再按证据做最小适配。三项都先使用保守、不暗含 SSE2 的 CPU 候选基线；最终由真实旧 CPU 和产物审计冻结，只有证据迫使产品缩小支持面时才回来做最小补问。

- A：把 qualification 作为 Windows 发布前置；先审计、试构建和测试现有设计。若证据证明必须修改，允许在 `../luainstaller` 自己的设计、测试和提交中做最小的 guard/toolchain/profile 适配；yaca 只消费已经证明的产物和 manifest。（推荐）
- B：允许 qualification 和可丢弃 prototype，但在 yaca 设计阶段只报告所需修改；任何持久修改兄弟仓库的工作以后再单独授权，Windows release 在此之前保持 evidence-blocked。
- C：不修改兄弟仓库，只等待项目负责人另行提供已经证明 x86/XP 的 luainstaller artifact；在它到位前不发布 Windows 版。

推荐 A。它保留“Windows x86 + luainstaller”两个既定目标，又不预判一定需要重写 launcher；选择 A 只冻结未来工作范围，不代表现在越过设计门开始编码。最终证据必须包含 PE/CRT/API 审计和 XP SP3 至 11 对同一产物的完整测试。

覆盖：`RF-04`、`RF-14`。

## CQ-29 发布证据、来源签名与更新

luainstaller 能否产出 x86 是构建前置；发行包需要哪些公开证明、是否联网检查更新是另一条独立产品策略。

- A：各平台独立放行；发布 SHA-256、最小组件/许可证 manifest、SBOM、构建摘要和对应平台完整测试摘要；不要求来源签名，不内建更新检查、下载或安装。（推荐）
- B：采用 A 的全部材料，并要求可离线验证的来源签名和用户显式 `--check-update`；只检查并报告，不下载或安装。
- C：采用 B，并允许用户显式下载和验证新 zip；仍不覆盖当前程序、不自动迁移数据，也不自动运行新版本。

推荐 A。它提供足够的可审计性，不把签名密钥运营和更新状态机塞入 v0.1。Windows 与 Linux 分别满足自己的证据门即可发布；现有 `bin/` 只作来源线索，最终包使用最小 allowlist，不使用 UPX。性能、fault 和长会话 soak 使用最终候选包执行，发布证据按版本长期保留。

覆盖：`RF-05`、`RF-06`、`RF-08`、`RF-09`、`RF-10`、`RF-11`、`RF-12`、`RF-15`、`RF-16`。

## 回复之后怎样收口

1. 逐项保存负责人原话和集中选项，不把推荐当作默认授权。
2. 对照下方覆盖 ID，把能由集中答案唯一推出的原子组标为 selected/superseded；纯实现叶子标为 technical-proof，不再向负责人提问。
3. 如果一个集中答案无法唯一决定某个原子组，只保留真正改变产品承诺的最小补问；内部实现分歧不补问。
4. 生成完整配置 schema、AgentLoop 状态表、Permission 矩阵、Tool registry、Context XML schema、CLI/action registry 和 release manifest。
5. 完成目标平台技术证明与 readiness gate 后，才进入逐子系统实施计划。
