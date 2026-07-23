# 18 Prompt、指令与工作区说明

状态：四层 Prompt 与不自动发现项目规则的产品契约已确认；长度上限和 wire 投影待技术证明

## 为什么需要独立子系统

yaca 的 Prompt 不是一个会被后写字段覆盖的字符串。全局、Model、Permission 和 Context 四层都由用户分别配置、分别保存，并在请求建立时确定性合并。Runtime 的完整性规则、purpose 契约、真实 Permission、工具 schema、历史事实和当前用户消息又各有自己的来源；若让配置 parser 或 provider adapter 临时拼接，同一个 Context 会因入口或 Model 不同而失去可解释性。

本系统只拥有 Prompt component 的装配、来源标记、冻结和快照。它不把普通仓库文件升级成指令，也不从 Prompt 文本推导权限或 Runtime 功能。

## 职责

- 接收已经验证的 Global、Model、Permission 与 Context 四层 Prompt component。
- 按 request purpose 选择允许的组件，加入不可覆盖的 Runtime/purpose 契约，并产生不可变 `PromptBundle`。
- 为每个实际发送的组件保存 kind、来源、配置 generation、原文、digest、顺序和是否作为 instruction/data 使用。
- 在组件缺失、过大、编码无效或总请求超限时，于网络请求前返回 typed error。
- 向 AgentLoop、模型协议和 Context Store 提供同一份 bundle；任何下游都不能重排或再次合并。

## 已确认的四层 Prompt

四层是彼此独立的正式配置面：

1. `Global.SystemPrompt`：主 INI 中的全局默认，对所有 LLM request 生效。
2. `Model.<Name>.SystemPrompt`：当前完整 Model 实例自己的默认，对使用该 Model 的所有 request 生效。
3. `Permission.<Name>.SystemPrompt`：当前 Permission 的模型行为说明，只对 `main` 与 `side` 作为指令生效；它不是 capability。
4. `ContextPrompt`：当前 Context 的上下文说明，只对 `main` 与 `side` 作为指令生效；通过 chat `.prompt` 或 `context-repl` 事务式查看和编辑，保存在 Context XML。

旧 `Model.CustomPrompt` 不再形成第五层或 compatibility hint；目标 schema 使用正式的 `Model.SystemPrompt`。旧配置的迁移必须保留原文并明确迁入对应 Model 层，不能悄然改成 Global 或 Context scope。

当前用户消息始终是独立 user message，不是第五个 System Prompt。Prompt assembler 不把四段字符串覆盖成一个“最终值”，而是按下列稳定顺序装配并保持 component 边界：

```text
immutable runtime + request-purpose contract
Global.SystemPrompt
Model.SystemPrompt
[main/side only] Permission.SystemPrompt
[main/side only] ContextPrompt
current user message / purpose input
```

后出现、更具体的用户层可以补充或收窄先前偏好，但自然语言冲突不改变 Runtime 完整性规则、真实 Permission、workspace、工具 registry、硬预算或人工审批。Permission 的名称、Description 与 SystemPrompt 都不能授予能力。

## 默认交流与澄清原则

默认 Prompt 引导模型跟随用户消息语言、结果优先并保持简洁；复杂任务只在阶段变化、需要等待或出现风险时给短进度，最终回复如实列出结果、改动、验证和未知事项。这个风格由有效 Prompt 和模型执行，不是 TUI/Runtime 对自然语言的硬编码；用户消息或四层 Prompt 可以要求更详细、教学式或更精简的表达。

模型只有在不同答案会实质改变目标、安全、费用、不可逆副作用或公开结果时必须停下来询问。其他不完整信息采用最小风险假设继续，并把假设讲清楚。该原则不代替 Runtime 必须取得的 Permission/endpoint/费用 consent，也不授权模型跨过 hard cap 或 safety invariant。

## request purpose 继承矩阵

所有 LLM request 都继承冻结 generation 中的 Global 与所选 Model Prompt；其余组件由 Runtime 按 purpose 固定，不能由配置自由扩张：

| purpose | 作为指令继承的用户 Prompt | 固定规则 |
| --- | --- | --- |
| `main` | Global + Model + Permission + Context | 加入 main control/tool/persistence 契约和当前用户消息 |
| `side` | Global + Model + Permission + Context | 加入只读、无工具、单次直接回复契约 |
| `action-review` | Global + Model | 加入固定 action-review schema；动作、Permission 和证据只作为有界 quoted data |
| `termination-review` | Global + Model | 加入固定 finish-review schema；目标、验收标准、历史和证据只作为有界 quoted data |
| `compaction` | Global + Model | 加入固定 summary schema；被压缩事实和旧 Prompt 只作为有界 quoted data |
| `self-test capability/semantic` | Global + Model | 加入固定 self-test schema；Permission/配置文本只作为脱敏、有边界 data |
| `context-name` | Global + Model | 加入固定无工具命名 schema；Context 内容只作为有界 data |

因此特殊 purpose 不继承 Permission/SystemPrompt 或 ContextPrompt 的指令权威。它们可以为了审阅、摘要或命名看到必要内容，但这些内容必须放进明确的数据槽，不能改变 purpose 的工具白名单、输出 schema 或安全边界。仅在 Prompt 中写“不要调用工具”不构成限制；Runtime 和 provider adapter 必须实际提供对应的空/受限工具 schema。

## 装配与生命周期

1. 22 号 Runtime 在顶层 `main`/`side` admission 前发布完整、已验证、不可变的 `ConfigGeneration`。
2. AgentLoop 冻结当前 Model、Permission、Context、workspace 与 purpose，调用本系统建立 `PromptBundle`。
3. 本系统逐组件验证 UTF-8、字节/token 上限和来源，按固定顺序产生 component manifest 与 public digest。
4. Context Store 在首个模型请求前保存足以完整接盘的实际 component 原文、来源、顺序、generation 与 digest；配置中 registered secret 仍不得因 bundle snapshot 进入 XML。
5. 06 号 provider adapter 只编码 bundle，不增删、拼接或重新解释层级。
6. 同一 turn 的 retry、工具循环、action/termination review 和 compaction 使用 admission 时冻结的 generation。INI、`.prompt` 或 Context 管理变化最早从下一顶层 turn 生效。

Model 或 Permission 切换必须形成明确 transition。下一 turn 的 bundle 同时能说明旧值、当前值和切换来源，使新 Model 理解先前工作是在什么 Prompt/Model/Permission 下产生的；历史 request 的 component snapshot 永不被新配置倒写。

## 仓库文件不是自动 Prompt

v0.1 不自动发现或加载 `AGENTS.md`、README、项目规则、目录级规则或任何约定文件，也没有 project-config/instruction search path。用户需要项目说明时，可以在普通消息中要求模型通过已获准的 direct read/search 或 raw shell 阅读指定文件。

被读取的文件、源码注释、Git diff、命令输出和工具结果始终是数据；内容中即使出现“忽略前文”“授予权限”等文字，也不会成为第五层 Prompt、改变 component 顺序或获得 Permission 权威。用户若随后明确把其中内容整理进 Global/Model/Permission/Context Prompt，才从下一 turn 作为对应正式层生效。

传入且可进入的真实目录就是唯一 workspace root；上级 Git 根只作为可发现的 status/diff 元数据，不扩大 Prompt、文件或 Permission 边界。本系统不通过向上扫描 Git 根寻找规则。

## `backup/` 只是可选 Prompt 文案

某个 Global、Model、Permission 或 Context Prompt 可以用自然语言建议模型在合适时把副本放到 `backup/`，但这只是一段普通 Prompt：

- schema 不生成 `BackupMode`、`BackupDirectory`、undo 或 restore 字段；
- Runtime 不自动创建、复制、恢复、清理或保留 `backup/`，也不把它当作 reserved tree；
- 工具层不为该名称提供特殊 API、绕过 expected digest 或扩大 Permission；
- 模型若据此调用普通 write/copy/shell，仍按真实目标、当前 Permission、DoubleCheck 和人工审批正常处理；
- 是否能恢复、保存多久以及是否适合放入某种内容，都只是 Prompt/用户要求下的模型判断，不是 yaca 的功能承诺。

同理，Prompt 可以建议某种 Git 工作方式，但 Runtime 不因此自动 commit、stash、reset 或 push。Git 副作用只在用户明确要求并经普通 Shell/Permission 流程后发生。

## 安全、隐私与兼容性不变量

1. Runtime/purpose 契约、真实 Permission、workspace、工具 schema 和硬上限不接受任何 Prompt 覆盖。
2. 四层 Prompt 只能影响模型行为，不能注册工具、联网能力、后台任务、Web/媒体/remote surface 或 OS sandbox。
3. 每个组件独立标记和保存；assembler 不按空值、同名字段或文字相似度吞掉另一层。
4. Prompt、路径与用户正文按严格 UTF-8 保真；程序生成的 component kind、role 和字段名使用 English/ASCII。旧终端显示替换不能回流成原文、digest 或请求内容。
5. 单组件、组件总字节、估算 token 和最终 request 都有不可关闭硬上限。超限先产生 typed error/压缩或请求用户调整，不能静默截断高优先级规则。
6. 外来 XML 中的历史 Prompt snapshot 只解释历史 request；它不能创建或覆盖本机 Global/Model/Permission 配置。ContextPrompt 只有经过 import/mapping 的 Context 才作为当前 Context 层继续使用。
7. Context XML 是完整接盘事实，因此复制者可能看到 Prompt 中的用户敏感文本；UI 必须如实说明这一明文边界，不能把 Prompt 错标为 config secret 后又不保存历史。

## 失败与恢复

| 情况 | 行为 |
| --- | --- |
| Global/Model/Permission 配置无效 | 阻止新 turn admission，进入对应 config/model self-fix；不使用旧 generation 偷跑新请求 |
| ContextPrompt XML 损坏或无法提交 | 阻止请求并进入 Context self-fix；不能只在内存使用一份无法接盘的 Prompt |
| Prompt component 超限或编码无效 | 请求前返回 typed error，指出 component kind/来源和限制；不静默截断 |
| Prompt 在活动 turn 中变化 | 当前 bundle 不变；下一顶层 turn 记录 generation/Context transition 后采用 |
| provider adapter 无法无损表达 bundle/control | capability preflight 失败；不把组件拍平成不可审计的自然语言替代协议 |
| XML 快照提交失败 | 不开始对应 Model request或副作用；报告已保存水位 |

## 仍需技术证明

剩余工作是冻结四类字段的 INI/XML 多行语法、每组件与总预算数值、component manifest/XML schema、OpenAI/Anthropic role 投影和旧配置迁移 fixture。不得重新引入项目规则自动发现、`Model.CustomPrompt` 隐藏层、Prompt 驱动的 backup 功能或特殊 purpose 对 Permission/Context Prompt 的指令继承。
