# 决策包 03：Prompt、Agent 人格与指令权威

更新日期：2026-07-18

状态：等待项目负责人回复；本文中的推荐、英文标识、样例和方案编号都不是已确认决定

## 本包要决定什么

本包决定 yaca 的模型为什么以某种方式回答、不同来源的要求发生冲突时听谁的，以及六个核心模型请求各自能看什么、能做什么、必须返回什么。若产品包最终选择 `PJ-12 B`，还会条件增加第七个 `context-name` purpose；这只是 PJ-12 的下游契约，不在本包二次投票。

它覆盖：

- 默认 Agent 人格与提示风格的实际效果。
- Agent 回复使用哪种语言，以及用户怎样临时改变详略和语气。
- 进度播报、工具叙述和默认最终报告。
- Runtime 不变量、当前/历史用户指令、`ContextPrompt`、明确采用的项目规则、全局 `SystemPrompt`、普通文件与工具输出之间的权威关系。
- 后来的用户纠正怎样替代较早要求，而不偷偷改写持久 Prompt。
- `main`、`side`、`action-review`、`termination-review`、`compaction`、`self-test` 六个核心 request purpose 的独立契约，以及 `PJ-12 B` 条件成立时 `context-name` 的最小可见性。
- provider role 不完整时的安全映射、Prompt delimiter 和不可信文本隔离。
- yaca 升级、Prompt 版本变化和 Model 切换时怎样解释历史。
- Prompt 大小、模型窗口变小和超限时的行为。
- XML 中怎样保存足够完整、又不无意义重复的 Prompt 证据。

本包不决定：

- `DoubleCheck` 何时触发、用户能否 override action review、评估失败后 AgentLoop 去哪里；它们属于 AgentLoop/安全包。
- 压缩何时触发、摘要窗口和 token 估算常量；它们属于压缩包。
- XML 元素名、namespace、提交和崩溃恢复算法；它们属于存储包。
- `SystemPrompt`/`ContextPrompt` 在 INI/XML 中的最终转义语法；它们属于配置/格式包。
- 逐字的最终英文内置 Prompt；先确认本包语义，再单独冻结可回归测试的原文。

## 已经确认、这次不重新询问的前提

1. 全局配置需要一个 `SystemPrompt`。
2. 每个 Context 可以有独立 `ContextPrompt`，使用 `.prompt` 管理并随 Context 保存。
3. 正常任务完成由主模型主导；有效 `DoubleCheck=true` 时还会发起独立完成复核请求。
4. `DoubleCheck` 是一个总开关，不再保留独立 `UseTerminationEvaluator`。
5. `side` 是一次只读旁问；它可以看会话，但不能调用工具或改变主任务。
6. Context XML 要保存足以让另一台机器或另一个 Agent 理解并继续工作的完整接盘信息。
7. 程序自有标识、配置键、机器字段和固定 UI 文案使用 English/ASCII；这不等于已经决定 Agent 只能用英语回答用户。
8. 普通仓库内容、模型输出和工具输出不能仅凭自己写着“请执行”就获得权限。

## 先区分三个平面

只画一条“system > user > file”是不够的。yaca 必须区分 Runtime 真正强制的事实、模型应该遵循的指令，以及只能被阅读的数据。

### 1. Enforcement plane：程序强制，不靠模型自律

包括：

- 权限和审批结果。
- 可用工具集合及其参数校验。
- tool call/result 配对和 operation 身份。
- 工作区、路径和网络边界。
- 存储屏障、取消、预算和真实 terminal outcome。
- `side`/review/compaction 和 `self-test phase=semantic` 没有工具时，Runtime 根本不向请求提供工具；`self-test phase=capability` 最多携带不连接 Tool Runtime 的 inert synthetic schema，用来验证 adapter 的 native tool wire，任何返回调用都只作为测试观测。

任何 Prompt 都不能让 Runtime 放宽这些规则。即使模型说“用户已经同意”，没有真正的授权事件也不能执行。

### 2. Instruction plane：模型的有效指令

推荐优先级从高到低为：

```text
built-in invariant instructions
  -> active explicit user instructions
       later explicit correction wins on actual conflict
  -> ContextPrompt
  -> explicitly adopted project rules, limited to their scope
  -> global SystemPrompt
  -> built-in default personality
```

这里的 `SystemPrompt` 是用户设置的全局默认，不因名称含有 `System` 就高于用户当前明确要求。它可以改变默认人格、详略和跨项目习惯，但不能替换 built-in invariants。

`ContextPrompt` 是当前任务的持久偏好，优先于全局默认；用户当前消息仍可明确例外。例如 `ContextPrompt` 写着“完成后运行全套测试”，用户本轮明确说“这次只做只读分析，不要运行任何命令”，本轮应服从当前用户。

### 3. Data plane：可以影响判断，但不能自升权威

包括：

- 普通 README、源码注释和其他仓库文件。
- 工具输出、网页内容和错误正文。
- 历史 assistant 回复、side 回复和模型生成摘要。
- 用户要求“分析这段提示词”时被引用的提示词文本。

它们可以提供事实，也可能包含恶意或错误命令。Runtime 和 Prompt 装配器根据来源元数据把它们作为数据；不能扫描到一句“ignore previous instructions”就改变层级。

## 三套连贯的人格与提示风格

下面用同一项假设任务比较实际体验。所有文件名、错误原因和测试数字只是人格样例中的共同假设事实，不表示当前仓库已经有这些改动。

假设用户输入：

```text
修复配置解析器在遇到重复 Model section 时静默覆盖的问题。
只改必要文件，并运行相关测试。
```

假设共同事实：根因是 parser 以 section 名作键直接覆盖前项；修复后返回带第二处行号的 `CFG-DUPLICATE-SECTION`；新增一项回归测试；相关测试 18/18 通过；没有修改其他文件。

### 风格 A：克制的工程伙伴（推荐）

开始时：

```text
我先确认重复 section 是在解析、校验还是 Model 注册阶段被覆盖，
然后做最小修复并运行相关测试。
```

定位到方向变化或关键事实时：

```text
定位到 parser 直接用后一个 section 覆盖前一个。
我会在写入映射前拒绝重复项，并保留第二处行号，不改变正常解析路径。
```

最终回复：

```text
已修复重复 Model section 被静默覆盖的问题。

- `src/ini.lua`：检测重复 section，并返回 `CFG-DUPLICATE-SECTION` 和第二处行号。
- `tests/ini_duplicates.lua`：增加重复 Model section 回归用例。
- 验证：相关测试 18/18 通过。
- 范围：没有修改其他文件。
```

特点：结果优先、主动但不过度播报；只有计划、关键发现、风险或方向变化才说话；最终报告短而有证据。

代价：完全不了解代码的用户可能还想听更多背景，需要继续追问或在当前消息里要求详细解释。

### 风格 B：教学型协作者

开始时：

```text
我会先沿着配置加载流程检查三个位置：INI parser 是否保留重复项、
schema validator 是否检查重复项，以及 Model registry 是否覆盖同名实例。
这样可以避免只在最后一层打补丁，却让其他重复 section 继续被静默吞掉。

确认根因后，我会选择最靠近输入边界的位置修复，并补一项能先失败、
修复后通过的回归测试。最后只运行与配置解析相关的测试，避免扩大改动范围。
```

定位后：

```text
现在确认问题发生在 parser：它把 section 名作为 table key，第二个同名 section
直接覆盖第一个，所以后面的 schema validator 根本看不到“曾经重复”这一事实。

最合适的修复是在 parser 第一次发现重复时立即返回结构化错误，并报告第二个
section 的行号。这样错误最接近来源，Model registry 也无需增加补偿逻辑。
```

最终回复：

```text
修复完成。问题的根因不是 Model registry，而是 INI parser 在构造 section table
时覆盖了同名键。现在 parser 会在第二个同名 section 出现时停止，并返回
`CFG-DUPLICATE-SECTION`，同时保留第二处行号供用户修复配置。

具体修改：

1. 在 `src/ini.lua` 写入 section 映射前检查名称是否已经存在。
2. 在 `tests/ini_duplicates.lua` 增加两个同名 Model section 的回归用例。
3. 保持不重复配置的解析行为不变。

验证结果：相关测试 18/18 通过。没有改动无关文件。
```

特点：推理与取舍更容易学习，适合新手、架构讨论和教学任务。

代价：日常 Coding Agent 会显得啰嗦；工具循环较长时，大量解释会淹没真正结果并增加 Token。

### 风格 C：静默执行器

开始和执行期间：

```text
[无 Agent 进度文字；只有 Runtime 的工具和状态块]
```

最终回复：

```text
已修复重复 Model section 覆盖；新增回归测试，相关测试 18/18 通过，
未修改其他文件。
```

特点：最少文本、最低干扰，熟悉工具日志的用户可以直接看结果。

代价：长任务中用户不知道 Agent 当前方向；风险动作、假设变化和卡住时缺少解释，最终也较难快速审计具体修改。

### 推荐结论

推荐风格 A 作为内置默认。用户在当前消息里要求“详细解释”时可以得到接近 B 的回答；要求“直接做，不要过程”时可以得到接近 C 的回答。首版不需要持久化 `verbosity` 枚举或三个人格预设。

`SystemPrompt` 可以长期改变默认人格，`ContextPrompt` 可以改变当前任务风格，当前用户消息可以为本轮临时调整；这些偏好仍服从证据、安全和真实状态不变量。

## 推荐的默认回复契约

### 回复语言

- 固定 UI 标签、error ID、工具名和机器字段继续使用 English/ASCII。
- Agent 自然语言默认跟随用户当前明确使用的语言。
- 用户明确指定回复语言时服从该要求。
- `ContextPrompt` 的长期语言偏好高于全局 `SystemPrompt`，但低于当前用户的明确要求。
- 文件名、命令、代码、配置键和引用内容保持原样，不为了语言一致性翻译标识符。
- side 默认使用旁问文本的语言；内部 review/compaction/self-test 的枚举保持 ASCII。

### 进度播报

简单问答和单步只读操作不需要先列计划。多步骤、长时间或高风险任务采用以下节奏：

1. 开始时用一两句说明当前目标与首个检查方向。
2. 只在发现改变方案的事实、进入长操作、将申请风险动作或阶段完成时更新。
3. 自动重试、等待网络和运行长工具时，Runtime 显示事实状态；模型不重复编造进度。
4. 没有新事实时不按固定句式反复说“仍在工作”。
5. 信息不足时，可逆且局部的细节允许显式假设；会改变架构、费用、安全或外部状态时询问用户。

### 工具叙述

- 不为每次 `read/list/search` 机械解释。
- 一组相关的只读调用可以由一句目标说明覆盖。
- 方向改变、长命令、可能产生副作用或需要审批的动作必须先简要说明原因。
- Agent 叙述不能替代 Runtime 工具卡；命令、cwd、状态、结果和 unknown 事实以工具事件为准。
- 工具失败后先说明真实影响，再决定重试、换方案或询问；不能把失败包装成成功。

### 默认最终报告

最终回复先给结果，再给必要证据。复杂开发任务的推荐结构是：

```text
结果：完成 / （仅 AL06-36 允许时）部分完成 / 等待用户 / 取消 / 失败

改了什么：只列用户真正关心的行为和文件。
验证：列实际执行及结果；未执行必须直说。
剩余/未知：只在存在时列出，包括 unknown 副作用。
下一步：只有用户需要行动时才给。
```

简单问答或单文件小改动可以压成一段，不强制打印空标题。Runtime 可以附加不可伪造的 terminal outcome、工具/测试事实和中断原因；主模型不能用自然语言覆盖这些事实。

## `SystemPrompt`、`ContextPrompt`、用户纠正和项目规则

### 全局 `SystemPrompt`

推荐把它定义为所有 Context 的用户级默认：

- 可以调整人格、详略、工作习惯和跨项目偏好。
- 可以要求更保守的行为。
- 不能删除工具协议、权限、恢复、预算、证据和诚实报告规则。
- 不自动成为某个历史 turn 的唯一解释；实际使用的快照需要随 Context 记录。

### `ContextPrompt`

推荐把它定义为当前 Context 的持久覆盖：

- 由 `.prompt show/set/edit/reset` 管理。
- `show` 是只读；修改需要预览和确认。
- 修改从下一个 turn 生效，不改变在途请求。
- `SystemPrompt` 与 `ContextPrompt` 是同时存在的两层，不是二选一；后者只在实际冲突处覆盖前者。
- reset 只删除 Context 这一层，使后续 turn 重新使用当时有效的全局 `SystemPrompt`；它既不复制旧全局内容，也不把全局层清空。
- 普通用户消息可以临时覆盖它，但不会静默重写它；需要永久改变时仍用 `.prompt`。
- 压缩历史时不摘要或删除当前有效 `ContextPrompt`。

### 后来的用户纠正

用户说“不要改代码，只分析”时，必须覆盖同一任务中较早的“直接修复”。推荐规则是：

1. 只在实际冲突处由更晚、更明确的用户要求获胜。
2. 未冲突的旧限制继续有效，例如“不要 push”。
3. 模糊提及不自动撤销明确限制；不确定时询问。
4. 当前纠正作为对话事实保存，但不自动变成 `ContextPrompt`。
5. 纠正不能让 Runtime 越过权限或伪造已经发生的事实。

### 明确采用项目规则

普通 `README.md`、源码注释和工具输出始终先是 data。如果用户明确说“读取并遵循 `docs/project-rules.md`”，才形成一次**用户授权采用的项目规则快照**：

- 记录规范来源、适用工作区/子目录、内容和 digest。
- 只在其作用域内约束工作方式。
- 低于当前用户要求和 `ContextPrompt`，高于全局默认。
- 不能授予权限、扩大工作区、启用工具、自动联网或延长授权。
- turn 开始后来源文件变化不改变本 turn；下一 turn 重新观察时显示变化。
- 跨机器恢复时，历史快照解释旧行为；当前文件缺失或改变时，继续采用旧快照还是读取新内容必须显式说明，不能暗中混合。

首版推荐不自动寻找 `AGENTS.md`、`CLAUDE.md` 或任意目录级规则。需要项目规则时由用户明确指出文件，或由模型在任务需要时把普通文档读作资料；“读作资料”不等于“采用为持久指令”。

## 六个核心 purpose 与条件第七 purpose 必须各有契约

六个核心请求具体能看见哪些 Credential、Prompt、历史、文件、工具、审批和诊断，集中列在 [数据分类候选](../DATA-CLASSIFICATION-CANDIDATE.md)；本节只决定每类请求的职责与 Prompt 语义，不能靠文字提示扩大那张 Runtime 白名单。若 `PJ-12 B` 被确认，`context-name` 自动成为条件第七份契约；若选择 `PJ-12 A/C`，该 purpose 不存在，也不产生配置、费用或 XML 请求事件。

一个 `DoubleCheck` 开关可以控制多种复核，但不能把不同请求伪装成同一种 chat。推荐候选 purpose 名称和边界如下：

| purpose | 看到的主要输入 | 工具 | 输出 | 是否进入主模型对话视图 |
| --- | --- | --- | --- | --- |
| `main` | 有效指令 bundle、当前用户目标、模型视图、工具 schema、动态状态；PJ-11 B/C 时再带 `phase=plan|execute` | execute 按 Runtime/Permission；plan 仅 direct list/read/search 且仍过 Permission/SensitiveRead | 自然语言、合法 tool calls 或 typed control；plan 可产 PlanArtifact | 是；PlanArtifact 作为控制事实而非授权 |
| `side` | 提交旁问时的已提交 Context 快照、旁问文本、只读目的 | 无 | 一条直接回答 | 默认否；作为 side 事实保存 |
| `action-review` | 已规范化动作、参数/cwd/目标、确定性权限结果、相关用户意图与风险事实 | 无 | `allow/reject/uncertain` + 原因/风险 | 否；作为控制/审计事实 |
| `termination-review` | 任务目标、当前 turn 摘要、工具/验证事实、未完成项、主模型结束理由 | 无 | `finish/continue/uncertain` + 原因/缺口 | 否；verdict 可交回主模型 |
| `compaction` | 被选中的规范历史范围和必须保留槽位 | 无 | 结构化摘要与来源范围 | 仅摘要进入派生模型视图；原历史保留 |
| `self-test` | `phase=capability`：最小 synthetic probe 与公开 Model 能力声明；`phase=semantic`：已脱敏配置和 Stage 1/2 事实 | capability 只可带 inert synthetic schema，永不连接 Tool Runtime；semantic 无 | capability 为 typed observation；semantic 为 `ok/warning` + advisory | 否；进入诊断报告，两个 phase 分开记账 |
| `context-name`（仅 `PJ-12 B`） | 首个正常完成 main turn 的有界、已持久化命名视图 | 无 | 一个有界名称建议；Runtime 本地校验并等待用户确认 | 否；建议与确认分别保存 |

每种 purpose 都需要独立 request ID、Prompt version、用量、超时、错误和结果身份。`self-test` 还必须带 `phase=capability|semantic`，不能把 Stage 2 的真实请求伪装成无身份的网络探测；Stage 1 没有 Model 请求，因此不建立 request manifest。即使都使用当前 Model，也不能在 XML 中合并身份。

每种 purpose 还需要独立的最小充分数据视图：

- 任何 purpose 都不自动获得整个 XML、原始 HTTP body、Key 或认证 header。
- action review 只看待审动作、确定性结果、相关意图和风险事实；termination review 只看判断完成所需的目标与执行证据。
- compaction 必须看到所选历史中的真实用户/模型/工具事实，才能生成有效接盘摘要，但结构化凭据仍在装配前移除。
- 若 reviewer 或 compactor 使用不同 endpoint，等于把会话事实发送给另一个数据接收方，必须由独立配置和隐私确认决定，不能把“只是复核/压缩”当作无外发。
- 用户自己写进对话或文件内容中的秘密无法可靠自动识别；最小视图降低暴露面，但不能作“绝无秘密”的虚假保证。

`context-name` 不复用 `main`、`side` 或 `compaction` 身份。它只在 `PJ-12 B` 下看到首条已提交 main 用户目标、首个完成 turn 的有界结果/继续事项和必要的语言提示；不见工具 schema、Credential、任意文件正文、完整工具输出、审批 token、隐藏推理、完整历史或同目录其他 Context 名称。碰撞检查、非法字符处理、fallback 和 no-replace 全部在本地完成。请求失败、离线、输出无效或用户拒绝时保留 provisional 名，不阻断任务。

### `main`

- 唯一可以正常驱动 AgentLoop 和请求工具的模型目的。
- 使用完整有效的用户指令层级、当前模型视图和实际可用工具。
- 若 PJ-11 A，`phase` 和 PlanArtifact 均不存在。若选 B/C，main request 必带 `phase=plan|execute`：plan phase 只装配 direct list/read/search schema，仍经过普通 Permission/SensitiveRead，且 Runtime 硬拒绝 shell、direct network、write/rename/delete；execute phase 才恢复普通工具集合。
- PlanArtifact 只记录目标、步骤、预期文件/命令/验证和绑定 digest，不包含 approval token；`.execute <plan-id>` 创建新的 execute turn，旧 plan 仅作为引用输入，所有动作都必须按新 snapshot 重新验证与审批。绑定变化或 artifact stale 时必须重新 plan，Prompt 不能要求 Runtime“继续按旧批准执行”。
- 模型切换后的第一次 main 请求得到一个短 transition：旧 Model、新 Model、切换原因和继续事项；不包含 Key。
- 必须区分已验证事实、推测和未执行检查。
- `finish(completed)` 是明确的正常结束意图；只有 AL06-36 选择允许时，main Prompt/schema 才提供 `finish(partial)` 并让它候选为真实 `partial` 终态，选择不允许时不得仍向模型宣传该 control。
- 完整、合法、无工具且无 typed control 的普通回复始终显示并保存，但它形成 `waiting-user`、先触发一次 protocol correction，还是在严格条件下兼容为 implicit completed，只由 AL06-38 决定；本包不得把它无条件写成 yield 或完成。
- `ask-user`、`refuse` 和 `finish` 等 control 只表达主模型意图；Runtime 仍负责真实等待、取消、预算、provider refusal 和错误状态。

### `side`

- 使用提交旁问时已经持久化的会话快照，不读取 provider 隐藏推理或尚未提交的主模型残片。
- Runtime 不提供任何工具；只写“请只读”不能代替这一点。
- 可以沿用全局/Context 的语言和人格偏好，但 side 专用“回答一次、不得改变主任务”的规则优先。
- side 回复作为完整事实保存，但默认不进入以后 main 的模型视图；用户若要采用结论，应明确发给 main。
- 并发、排队、预算和取消由 AgentLoop 包决定。

### `action-review`

- 只用于 `DoubleCheck` 需要复核的候选动作，不代替确定性 Permission。
- 输入必须绑定精确 tool/参数/cwd/路径或 host/operation；参数变化使旧 verdict 失效。
- `allow` 只表示复核器没有追加否决，不能把 Runtime 的 deny/confirm 变成授权。
- `reject` 给出可操作原因；是否允许用户 override 留给安全包。
- 协议错误或 `uncertain` 不能伪装成 allow。
- 用户的 SystemPrompt/ContextPrompt 可以作为任务意图证据，但不能改写 review 的安全判定规则。

### `termination-review`

- 只在有效 `DoubleCheck=true` 且主模型提出正常结束时使用。
- 不接受整个 XML 原文；输入是目标、当前 turn 的结构化事实、验证、未完成项和拟议最终报告。
- `finish` 表示可以结束，`continue` 必须列出需要主模型继续处理的缺口，`uncertain` 进入保守错误路径。
- review 文本不冒充 assistant 最终回复；verdict、原因和对应主 request 分开保存。
- 复核拒绝后怎样继续以及最多几轮由 AgentLoop 包确认。

### `compaction`

- 使用版本化的专用 Prompt，而不是默认 Agent 人格。
- 必保槽位至少包含目标、用户决定、约束、文件/行为改动、验证、未知副作用、未完成事项和最近 Model 切换。
- 当前 `SystemPrompt`、`ContextPrompt`、Runtime 规则和 Permission 状态在摘要之外单独装配，不能让模型有损改写。
- 输出记录来源事件范围和摘要代次；摘要失败不能删除原模型视图或原历史。
- 默认不跨 endpoint 自动选择另一个 Model；具体 Model 选择由压缩包决定。

### `self-test`

- Stage 1 是本地静态检查，没有 Model request，也不占用 `self-test` request identity。
- Stage 2 每个真实联网 probe 都使用 `self-test phase=capability`：输入是版本化、有界、无用户正文的 synthetic fixture；按 Model 声明选择 stream/control/tool 测项。`Tools=native` 的测试 schema 是 inert contract，返回调用只进入 parser/报告，绝不交给 Tool Runtime 执行；`Tools=off` 只验证 off 投影及该路线实际需要的 control carrier，不伪造 tool call 要求。
- Stage 3 使用 `self-test phase=semantic`，只读取脱敏配置投影和已经完成的确定性/连接测试事实，产生 advisory；`Yolo` 名称却配置只读等疑点不能反向篡改 Stage 1/2 PASS/FAIL。
- 两个 phase 都不含 Key、认证 header、完整秘密环境变量、Context 对话或工作区文件，不能自动修复配置；它们复用同一 Model scheduler，但有独立 request/attempt/usage/result 和最小数据 manifest。

### `context-name`（仅当 `PJ-12 B`）

- 这是 PJ-12 的条件投影，不是第八个待选方案，也不能由 `AutoNameOnExit` 等旧布尔字段暗中开启。
- 每个 Context 终身最多建立一个 `context-name` logical request；只在第一个 main turn 已正常完成且其事实已持久化后尝试，没有完成事实就不请求，也不通过 correction、semantic retry 或 fallback 建立第二个 logical request。
- 复用该完成 main request 的有效 Model/endpoint snapshot，不自动 fallback 到另一 Model；原 Model 已不可用就按失败保留 provisional 名。
- 它使用独立且有硬上限的 lifecycle budget，不回记已经结束的 first main turn；request/attempt/usage 记入 Context ledger 和 process/runtime ledger，并服从与 main 相同的 Model scheduler。只有 Model 自身配置允许的有界 transport attempts 可以发生。
- 一旦用户提交新的 main/queue/steer 输入，main 取得调度优先级：尚未开始或正在运行的命名请求被取消且不再重排，provisional 名继续有效。Runtime 不等待命名成功才推进任务；已无法阻止的迟到响应只保存 request/usage/cancel 事实，不再成为可应用的 rename 候选。
- 使用独立、版本化、无工具 Prompt，只返回一个候选 basename 和可选的极短理由；Runtime 不接受路径、目录跳转或覆盖指令。
- 候选先经本地字符、长度、保留名、碰撞和 no-replace 校验，再展示给用户确认；未经确认不重命名。
- 它的 request/result/usage/failure 与 rename confirmation 分开保存；失败只保留 provisional 名，不改变 main outcome。

## role mapping 与 delimiter

### 为什么不能直接拼字符串

如果把下面内容简单拼成一个 `system` 字符串：

```text
built-in rules + SystemPrompt + ContextPrompt + README + tool output
```

模型既看不出来源，也可能把工具输出里的伪指令当作高优先要求。更严重的是，不同 provider 支持的 `system/developer/tool` role 不同，适配器若各自临时拼接，会让同一个 Context 在换 Model 后改变权威链。

### 推荐的 canonical bundle

AgentLoop 先建立与 provider 无关的 typed 组件。下面按**语义权威从高到低**展示；`authority-rank` 和 `kind` 决定冲突关系，不能依赖“谁最后被拼到字符串里”：

```text
kind: builtin-invariant
source: yaca prompt bundle 3.0
authority: invariant
authority-rank: 0
content-bytes: ...
content-digest: ...

kind: context-prompt
source: current Context
authority: context-default
authority-rank: 20
content-bytes: ...
content-digest: ...

kind: adopted-project-rule
source: /workspace/docs/project-rules.md
scope: /workspace
authority: delegated-project-guidance
authority-rank: 30
content-bytes: ...
content-digest: ...

kind: user-system-prompt
source: config.ini
authority: global-default
authority-rank: 40
content-bytes: ...
content-digest: ...

kind: builtin-default-personality
source: yaca prompt bundle 3.0
authority: fallback-default
authority-rank: 50
content-bytes: ...
content-digest: ...
```

当前及历史用户消息仍是各自的 message。它们的明确指令在实际冲突处具有逻辑 rank 10，高于 rank 20 及以下的默认层，但不能覆盖 rank 0 的不变量；工具结果和普通文件继续是 data。它们都不被伪装成上述持久 instruction 组件。

这里的排序是语义契约，不要求每个 provider 恰好拥有五种 role。适配器根据 role 能力生成确定的 wire view，同时保留每个组件的 kind/rank/source；同一组件不能因为换 endpoint 就突然获得更高权威。

### role flattening 推荐规则

1. provider 支持所需 roles 时，按稳定映射发送；适配器不能重新排序权威。
2. 只有一个 system role 时，把**指令组件**按上述语义顺序和显式 rank 编码进一个 system message；当前 user 仍保持 user role，tool/file/data 仍保持 data/tool 语义。
3. 组件使用固定 ASCII header、明确 kind/source/长度/digest，并对内容中的 header/delimiter 做转义或长度边界处理。
4. delimiter 只是降低模型混淆，不是安全隔离；真正权限仍由 Runtime enforcement plane 保证。
5. provider 无法可靠表示 tool call/result 配对或会把 data 变成 system 指令时，Model 应被判为不兼容，而不是悄悄使用有损拼接。

不推荐用一对容易出现在用户文本里的裸标记，例如 `<<<BEGIN>>>...<<<END>>>`，然后假定模型或字符串 parser 永远不会被内容闭合。边界必须由结构化元数据和编码器产生，而不是从内容中猜。

## Prompt 版本与升级

推荐每份 built-in purpose Prompt 都有独立版本和内容 digest。程序升级后的行为是：

1. 历史 request 继续引用当时实际使用的完整 Prompt bundle，旧回复仍可解释。
2. 新 turn 使用当前程序的 built-in invariants、当前机器的全局 `SystemPrompt` 和 Context 中的当前 `ContextPrompt`。
3. 若和上一个 turn 的有效 bundle 不同，先记录并向用户显示一个紧凑 transition；不能把新版 Prompt 伪装成历史一直使用的规则。
4. 安全、工具协议和数据完整性修复立即适用于新请求，不能因旧 Context 而永久锁在有漏洞的 built-in Prompt。
5. 用户配置的 ContextPrompt 保持不变；当前机器的 SystemPrompt 与历史快照不同也必须记录来源变化。
6. 明确采用的项目规则若已移动/改变，历史使用旧快照解释；新 turn 在采用当前内容、继续旧快照或停止之间形成显式结果。

模型切换同理：历史 request 保持旧 Model/Prompt 证据；新 Model 的首个 main view 得到最近一次 Model transition，而不是把全部切换历史每次重复注入。

## Prompt 大小与 Model 切换

推荐同时使用两个边界：

- **持久化字节硬上限**：限制单个和合计 SystemPrompt、ContextPrompt、采用项目规则的字节数，保护 Win32 x86 内存和 XML 大小。具体数字由旧机测试冻结。
- **请求 token 预算**：在发送前根据当前 Model 窗口和安全余量判断 Prompt 占比。估算不确定时采用保守值并显示 warning。

推荐失败行为：

1. `.prompt set/edit` 超过字节硬上限时拒绝保存，并显示实际大小和限制；绝不静默截断或让模型自动改写用户指令。
2. 全局 SystemPrompt 在启动校验中超限时阻断正常 Agent，但 config-repl 仍能修复。
3. 切到窗口更小的 Model 前先预检；如果固定 Prompt 加最低必保上下文已经放不下，不发请求，也不把 Prompt 交给 compaction。
4. 建议顺序是：回到先前足够大的 Model、选择另一个已配置且能力可信的大窗口 Model、缩短用户 Prompt、再考虑压缩历史。
5. 切回大窗口时可以恢复更多原始历史视图；不能因为曾经压缩就删除 XML 事实。

## XML 中的 Prompt 证据

为了“完整接盘”又避免每个 request 重复整份 Prompt，推荐语义是：

### 每个不同组件完整保存一次

保存：

- component kind、来源、作用域和权威类别。
- 规范化后的完整文本。
- built-in/user 配置版本、内容 digest 和编码信息。
- 第一次生效及被替代的事件关系。

至少包括当时使用的 built-in purpose Prompt、SystemPrompt 快照、ContextPrompt 各版本和明确采用的项目规则快照。

### 每个 request 保存引用

保存：

- request purpose。
- 有序 component 引用和 effective bundle digest。
- role-mapping/adapter 版本。
- Model 的非秘密快照。
- 当前用户/历史/工具消息的正常事件引用。

这样第三方 reader 能重建“当时模型收到哪些控制指令”，又不会在每个 turn 重复相同长文本。

### Prompt 修改本身是事实

- `.prompt` 修改保存旧/新版本、来源、确认和生效 turn。
- SystemPrompt、built-in version、项目规则或 Model transition 发生变化时保存 transition。
- 历史记录只追加新版本/引用，不改写旧 request 当时的 bundle。

### 秘密边界必须诚实

- API Key、认证 header 和结构化凭据永不因 Prompt 快照进入 XML。
- 但是用户可能自己把 token、密码或内网信息写进 SystemPrompt、ContextPrompt、项目规则或普通对话。程序不能一边承诺完整历史，一边声称能可靠识别并自动删除所有这类文本。
- 编辑 Prompt 时应明确提醒“此内容会进入当前 Context 历史/导出”；导出前提供秘密风险预览。
- 若用户仍确认保存，文本作为用户内容持久化；自动模型改写或静默脱敏都会破坏可解释性。

XML 的元素名、去重 ID、digest 算法和写入协议留给存储包；本包只决定必须能表达上述语义。

## 真正需要项目负责人回答的十二组问题

可以回复 `PP-01 A；PP-04 只采用用户明确指定的文件；PP-13 B；其余暂缓`。没有明确回复的编号继续保持待决，不会因为本文写了“推荐”就自动写入 `DECISIONS.md`。

### PP-01 默认 Agent 人格

- A：克制的工程伙伴；在需要说话时结果优先、解释关键取舍、承认不确定性。（推荐）
- B：教学型协作者；在需要说话时默认补充背景、因果和术语解释。
- C：直接型工程师；在需要说话时只给必要结论、证据和下一步，省略教学背景。

推荐 A。它决定“已经需要输出一条 Agent 文字时怎样措辞”，不决定何时播报、是否逐工具说明或最终报告有哪些栏目；那些只由 PP-06 选择。用户仍可在自然语言或 Prompt 中临时调整详略。

关联：`AQ-004`、`AQ-048`、`AQ-049`、`AQ-183`、`INSTR-02`、`TUI-03`。

### PP-02 回复语言策略

- A：没有明确语言指令时，Agent 自然语言默认跟随当前用户消息的主要语言。（推荐）
- B：没有明确语言指令时，Agent 自然语言默认 English，即使用户只是用另一种语言提问。
- C：没有明确语言指令时，以当前 Context 第一条主用户消息的主要语言作为会话默认，之后不因单条消息混用语言而自动切换。

推荐 A。它不增加 UI 本地化系统，又能自然跟随当前对话。三项都只决定“没有明确指令时的默认”：当前用户明确要求的回复语言、ContextPrompt/SystemPrompt 的持久语言要求仍按 PP-03 的统一权威链裁决；固定 UI、error ID、配置键和机器字段始终 English/ASCII。

关联：`PROD-15`、`AQ-045`、`AQ-048`、`AQ-049`、`AQ-292`。

### PP-03 指令权威链和用户 Prompt 的替换边界

- A：Runtime/built-in invariants 不可覆盖；当前及历史有效用户指令（后来的纠正优先）高于 ContextPrompt，ContextPrompt 高于明确采用项目规则，后者高于 SystemPrompt；SystemPrompt 与 ContextPrompt 同时装配、只在冲突处由后者覆盖，二者都不能替换 invariants。（推荐）
- B：Runtime/built-in invariants 仍不可覆盖，当前用户消息和已明确标记的用户纠正仍最高；但 ContextPrompt 高于更早的普通工作习惯，使会话级长期规则可以替代旧 turn 的默认偏好，之后才是采用项目规则和 SystemPrompt。
- C：Runtime/built-in invariants 与当前/历史明确用户要求保持最高；ContextPrompt、采用项目规则和 SystemPrompt 作为同级持久默认同时送给 main，若模型判断它们不能同时满足，必须在调用工具前返回 typed `ask-user`，不得自行挑一个来源获胜。

推荐 A。它最符合“后来的明确用户纠正获胜”，且恢复时能解释每一层；B 让 ContextPrompt 更像会话政策，旧 turn 更容易被统一替代；C 最保守但会增加冲突检测和人工中断。三项都禁止持久 Prompt 压过当前明确要求，也禁止把来源混成一段让模型猜。

关联：`AQ-001`、`AQ-002`、`AQ-003`、`AQ-046`、`AQ-047`、`AQ-055`、`AQ-056`、`INSTR-02`、`SAFE-10`。

### PP-11 旧 `Model.CustomPrompt` 怎样收口

- A：删除这一独立权威层；旧内容经用户预览确认后，迁移到全局 `SystemPrompt` 或当前 `ContextPrompt`。（推荐）
- B：保留 `Model.CustomPrompt` 作为高于 `SystemPrompt` 的第三层用户 Prompt，并为模型切换定义新冲突规则。
- C：保留 `Model.CustomPrompt` 作为 Model-specific adapter compatibility instruction；它仍标为用户配置、只进入该 Model 的 instruction component，不能改写 role mapping、消息 serializer、tool/control schema 或 Runtime 规则，也不能冒充内置 adapter 权威。

推荐 A。现有 `SystemPrompt` + `ContextPrompt` 已能表达全局与会话偏好；保留第三层只会让模型改名、恢复和权威冲突变得难以解释。B/C 若被选中都必须生成有界 typed 字段、Prompt component snapshot 和 Model 切换 transition；真正的线协议模板仍是内置、版本化 adapter 事实，用户字段不能替换它。

关联：`AQ-143`。

### PP-04 项目规则怎样成为指令

- A：首版不自动发现；只有用户明确要求采用某文件时，才生成有来源/作用域/digest 的规则快照。（推荐）
- B：自动读取工作区根的一个固定规则文件。
- C：自动递归发现根和目录级规则，并按路径叠加。

推荐 A。它最符合“需要时由用户整理文档让模型阅读”和保持简单，也避免陌生仓库文本自动变成高权威指令。代价是用户必须明确指出要采用的规则。

关联：`AQ-005`、`AQ-006`、`AQ-296`、`INSTR-01`、`INSTR-03`、`INSTR-04`、`SAFE-10`。

### PP-05 六个核心 purpose 是否使用独立契约

- A：main、side、action-review、termination-review、compaction、self-test 六个核心 purpose 各自有独立 Prompt、输入白名单、工具权限、输出和版本。（推荐）
- B：main 使用独立 Prompt；其他五类共享一个版本化 utility base，但每类仍有独立输入 manifest、无工具能力、purpose-specific output schema 和短扩展指令。
- C：按四个模板族维护：main、side、review（action/termination 各自 schema）、derived（compaction/self-test 各自 schema）；每个具体 purpose 仍保留独立 request identity、Runtime 白名单和结果类型。

推荐 A。它多维护几份短 Prompt，却最容易分别评估 side/复核/压缩是否偏离职责；B 的维护文本最少，purpose 扩展和 base version 必须一起审计；C 在复用与可测试性之间折中。无论本组选什么，Runtime 的工具/数据白名单都不能放宽；若 `PJ-12 B` 成立，`context-name` 总是增加独立的条件契约，不复用上述六个核心身份，本组不对此二次投票。

main 的具体 control schema 是本组所选模板策略的下游输入，不由 PP-05 决定：`finish(partial)` 是否存在只投影 AL06-36，普通无-control reply 的 correction/yield/implicit-finish 路径只投影 AL06-38。

关联：`AQ-008`、`AQ-019`、`AQ-020`、`AQ-099`、`AQ-109`、`AQ-251`、`AQ-252`、`AQ-259`、`AQ-358`、`AQ-359`、`MODEL-12`、`CTX-07`、`DIAG-05`、`COMP-01`、`AL06-36`、`AL06-38`。

### PP-06 进度、工具叙述和最终报告

- A：复杂任务在开始/方向变化/长或风险动作/阶段完成时短更新；不逐工具播报；最终先结果，再列修改、验证和真实剩余项。（推荐）
- B：每一步和每个工具前后都详细解释。
- C：全过程静默，最终只给一句成功/失败。

推荐 A。Runtime 状态块负责机械事实，Agent 文字只解释方向和结论，避免重复与虚假进度。

关联：`AQ-050`、`AQ-051`、`AQ-052`、`AQ-053`、`AQ-054`、`AQ-071`、`AQ-110`、`AQ-293`、`AQ-294`、`LOOP-22`。

### PP-07 role flattening 与注入 delimiter

- A：先建立 typed canonical bundle；provider 适配器只做稳定 role 映射，受限 provider 只 flatten 指令组件；用户/工具/文件仍为 data，并使用长度/转义/digest 边界。（推荐）
- B：只有能无损表示 yaca 所需 instruction/user/assistant/tool-call/tool-result 关系的 provider 才可用于 `main`；任何必需 role 缺失都拒绝，不做 flatten。无工具 purpose 也只按其实际所需 role 做无损映射。
- C：采用混合兼容线：`main`、`action-review`、`termination-review` 与 `self-test phase=capability` 必须无损映射其实际需要的 role/tool wire；无工具的 `side`、`compaction`、`self-test phase=semantic`（以及条件 `context-name`）可把带长度/来源标签的指令组件受控 flatten，用户数据仍保持独立 data 边界。

推荐 A。它支持较简单的 OpenAI-compatible endpoint，又不通过降级把不可信数据升级成 system；B 的协议面最窄、可验证性最高，但会排除更多旧/简化 endpoint；C 只为无工具目的保留兼容，main 的接入门更严格。三项都禁止把文件、工具输出或用户正文提升为 system；delimiter 也不是 OS 安全边界。

关联：`AQ-046`、`AQ-055`、`AQ-056`、`AQ-064`、`AQ-297`、`MODEL-04`、`LOOP-19`、`INSTR-03`。

### PP-08 yaca/Prompt 升级后的新 turn 使用什么

- A：历史 request 保留旧 bundle；新 turn 使用当前安全规则和当前 SystemPrompt/ContextPrompt，记录并显示 Prompt transition；已采用项目规则的变化另外服从 PP-13。（推荐）
- B：历史 request 保留旧 bundle；新 turn 永远使用当前 built-in 安全/工具规则，但该 Context 继续固定采用创建/上次明确确认时的 SystemPrompt 快照，直到用户在 Prompt transition 事务中显式采用当前全局值；ContextPrompt 仍按当前 Context 版本生效。
- C：历史 request 保留旧 bundle；新 turn 永远使用当前 built-in 安全/工具规则，但检测到外部 SystemPrompt digest 改变时暂停下一次 main request，要求用户在“继续旧快照 / 采用当前值 / 清除全局层”中选择；项目规则变化另由 PP-13 独占。

推荐 A。它兼顾历史可解释性和当前机器配置；代价是恢复时可能多一条紧凑 transition。B 偏向可复现性，C 偏向每次外部 Prompt 变化都由用户知情。三项都让安全修复立即进入新请求，不能把有漏洞的 built-in bundle 永久锁进 Context。

关联：`AQ-007`、`AQ-059`、`AQ-060`、`AQ-065`、`AQ-295`、`INSTR-05`、`CTX-14`、`CTX-15`。

### PP-09 Prompt 超限和切换到小窗口 Model

- A：同时设字节硬上限和请求 token 预算；超限拒绝保存/请求，不截断；优先建议原来足够大的 Model，再建议其他大窗口 Model、编辑 Prompt 或压缩历史。（推荐）
- B：只公开按 Win32 x86 实测冻结的 Runtime 字节硬上限；保存时不按当前 Model token 窗口拒绝，发送前才对有效 Model 做 token 预检，放不下就停止并建议换大窗口/缩短 Prompt，仍不截断。
- C：使用固定字节硬上限保护存储/内存，但 token 估算只作 warning；请求可发送给 provider，由明确的 context-overflow 响应停止并推荐先前足够大的 Model，绝不自动重发或截断 Prompt。

推荐 A。它最早发现不可兑现的请求，也不会偷偷改变用户控制指令；B 允许同一 XML 日后在大窗口 Model 上继续，但错误推迟到发送前；C 对估算不准的兼容 endpoint 最宽容，却可能消耗一次失败请求。三项都有不可突破的实测字节上限并保持 Prompt 全文，均不允许静默截断或无界增长。

关联：`AQ-061`、`AQ-062`、`AQ-063`、`AQ-142`、`AQ-156`、`AQ-240`、`AQ-298`、`COMP-02`、`COMP-08`。

### Prompt bundle 重建要求（原 PP-10；无需回复）

XML 的物理表示、组件去重、引用还是重复内联只由 `CX-03` 决定，本包不再用第二组 A/B/C 重复投票。无论 CX-03 选择哪种表示，都必须能由一个独立 reader 重建每个 request 当时的有序 Prompt bundle：完整组件文本、kind/source/scope/version/digest、effective digest、role-map/adapter version，以及修改、升级、Model 切换和项目规则 transition。结构化 Credential 永不进入 Prompt 快照；用户自己写进 Prompt 的秘密只能警告、预览和明确保存，不能虚假承诺自动识别干净。

这是 `CX-03` 的 Prompt 消费者验收条件，不计入本包正式回复模板。关联：`AQ-007`、`AQ-059`、`AQ-060`、`AQ-163`、`AQ-164`、`AQ-168`、`AQ-260`、`INSTR-05`、`CTX-06`、`CTX-07`、`CTX-15`、`CX-03`。

### PP-13 AdoptedRuleTransition：已采用项目规则发生变化时怎么办

本组只拥有“用户已经采用的项目规则快照”在后续 turn 怎样过渡；PP-04 仍独占规则怎样首次成为指令，PP-08 独占 built-in/SystemPrompt 升级，存储表示仍由 CX 包决定。

- A：采用后冻结该快照，直到用户显式 `refresh` 或 `revoke`；每个新 main turn 只做廉价变化观察，发现源文件 changed/missing 时显示 warning，但继续使用旧快照。（推荐）
- B：采用后每个新 main turn 观察来源；digest changed/missing 时，在发送请求前暂停，要求用户明确选择“继续旧快照 / 采用当前内容 / 撤销规则”，形成 transition 后才继续。
- C：采用后在 turn 边界自动读取可访问的新内容并替换快照，记录 old/new digest transition；来源 missing/unreadable 时保留旧快照并 warning，不在 turn 中途热替换。

推荐 A。它把“采用”理解为对一份可复现内容的明确授权，仓库文件被工具改写时不会自动获得新指令权威；B 知情最强但更容易打断长任务；C 最接近实时项目规则，但任何文件变更都会在下一 turn 自动进入指令面。三项都保留旧快照解释历史、禁止 turn 中途漂移，也不能借 transition 扩大 Runtime 权限或作用域。

任何 keep/refresh/revoke/auto-replace 都追加 typed `AdoptedRuleTransition`，至少记录旧/新 source、scope、digest、observation、触发原因、用户决定或自动政策、effective turn 和结果，并能关联当时的规则组件身份；全文采用内联、引用还是去重仍由 CX-03 独占。来源 missing/unreadable 也是 observation，不得伪装成“规则未改变”。

关联：`AQ-005`、`AQ-006`、`AQ-059`、`AQ-060`、`AQ-295`、`INSTR-01`、`INSTR-03`、`INSTR-04`、`INSTR-05`、`CTX-15`。

### PP-12 `.prompt` 的交互形态与事务边界

- A：`.prompt` 显示当前有效层、来源和下个 turn 生效状态；`.prompt set` 进入有明确结束标记的多行 draft，结束后显示大小/digest/来源变化并确认；`.prompt reset` 单独确认。修改只在完整保存后从下个 turn 生效。（推荐）
- B：`.prompt` 进入一个 Lua 风格小型 REPL，提供 `show`、`set`、`import`、`reset`、`save`、`discard`；所有修改先进入事务 draft，显式 `save` 后从下个 turn 生效。
- C：只提供 `.prompt set "..."`、`.prompt import <file>` 和 `.prompt reset` 参数式命令；不进入子页面，较长内容主要通过文件导入，提交前仍显示大小/digest 和确认。

推荐 A。它不增加常驻子系统，又能在旧终端上可靠输入多行 Prompt；B 最适合反复编辑，C 的 UI 最少但命令引用和长文本体验较差。三项都保留完整旧/新版本事件，不修改在途 request，也不把普通用户消息静默写成 `ContextPrompt`。

本组独占 Prompt editor 的 show/set/import/reset、正文 delimiter、预览、save/discard 和生效边界；`TU-19` 只拥有 chat composer 的 main/queue/steer/side 多行语法，不能借通用输入样例改写 Prompt editor。未提交 Prompt draft 究竟仅在内存、debounce 写入 XML session state，还是显式 `.draft save` 后才写入，只服从 `F4-05`；因此 PP-12 的 A/B/C 都不能暗定 `F4-05 A`。若 `F4-05 B/C` 使 draft durable，保存/清除记录仍只是可删除 session state，不是有效 `ContextPrompt`、已提交对话或下个 request 的 Prompt 组件；只有本组定义的完整提交才会产生 Prompt transition。

关联：`AQ-003`、`AQ-057` 至 `AQ-060`、`INSTR-05`、`CTX-15`、`F4-05`、`TU-19`。

## 推荐的整包组合

若希望采用当前推荐基线，请明确回复全部 12 个正式组：

~~~text
PP-01 A
PP-02 A
PP-03 A
PP-11 A
PP-04 A
PP-05 A
PP-06 A
PP-07 A
PP-08 A
PP-09 A
PP-13 A
PP-12 A
~~~

也可以只回复差异，例如 `本包其余接受推荐；PP-01 B；PP-12 C。` 推荐不是决定，未明确回复的编号继续保持 unanswered。

## 本包确认后的归档产物

项目负责人回复后，只把明确选择归档到：

- `DECISIONS.md`：人格、语言、权威链、项目规则和 purpose 总体契约。
- `18-prompt-and-workspace-instructions.md`：来源、作用域、canonical bundle、版本和 role mapping。
- `09-agent-session.md`：六个核心 request purpose 与 `PJ-12 B` 的条件第七 purpose 怎样进入 AgentLoop；不复制 Prompt 原文。
- `05-configuration.md`：SystemPrompt、ContextPrompt 管理入口和大小校验。
- `10-context-storage.md`：Prompt 组件快照、引用和 transition 的持久语义。
- `12-context-compaction.md`：compaction purpose 的输入/输出与 Prompt 不被摘要规则。
- `15-diagnostics-and-logging.md`：self-test purpose 的脱敏和 advisory 边界。

精确英文内置 Prompt 必须在上述语义确认后作为版本化协议另行起草，并用 golden assembly、冲突、注入、Model 切换和跨 Model 行为评估测试验证（`AQ-183`、`AQ-357`）。尚未回复的 PP 条目继续保持待决。

## 完成标准

本包完成后，下面每个问题都应有唯一答案：

1. 同一个任务下，yaca 默认会说多少、什么时候说、最终怎样报告。
2. 用户用中文提问，而 UI 固定 English 时，Agent 用什么语言回答。
3. SystemPrompt、ContextPrompt 和用户刚刚的纠正冲突时听谁的。
4. 用户让 Agent 阅读项目规则与普通 README 恰好含命令时，有什么区别。
5. side 为什么即使 Prompt 被注入也不能调用工具。
6. action review 的 allow 为什么不能授予 Runtime 原本拒绝的权限。
7. termination review、compaction 和 self-test 的文字为什么不会冒充主 Agent 回复。
8. provider role 较少时，哪些内容可以 flatten，哪些必须保持 data。
9. 升级 yaca 或切换 Model 后，旧回复怎样解释、新 turn 使用什么 Prompt。
10. Prompt 太大或 XML 被复制到另一台机器时，系统保存和缺失的事实是什么。
11. 已采用项目规则被修改、移动或删除后，下一 turn 是继续快照、询问还是自动采用新内容。

这些答案确认后，才适合冻结逐字英文 Prompt；不能先写一段长 system text，再倒推它到底代表什么产品规则。
