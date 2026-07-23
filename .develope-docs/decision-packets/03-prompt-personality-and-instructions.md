# 决策包 03：Prompt、Agent 人格与指令权威

更新日期：2026-07-22

状态：等待项目负责人回复；本文中的推荐、英文标识、样例和方案编号都不是已确认决定

## 本包要决定什么

本包决定 yaca 的模型为什么以某种方式回答、不同来源的要求发生冲突时听谁的，以及六个核心模型请求各自能看什么、能做什么、必须返回什么。D-041/D-046 已另行确认条件周期 `context-name` purpose；它不是第七个核心 purpose，也不在本包二次投票。

它覆盖：

- 默认 Agent 人格与提示风格的实际效果。
- Agent 回复使用哪种语言，以及用户怎样临时改变详略和语气。
- 进度播报、工具叙述、普通讲解详略、澄清阈值和默认最终报告；它们分别决定，不再捆成一个“风格”票。
- Runtime 不变量、当前/历史用户指令、`ContextPrompt`、明确采用的项目规则、全局 `SystemPrompt`、普通文件与工具输出之间的权威关系。
- 普通用户指令的 task/turn/Context 生命周期，以及后来的纠正怎样替代较早要求而不偷偷改写持久 Prompt。
- `main`、`side`、`action-review`、`termination-review`、`compaction`、`self-test` 六个核心 request purpose 的独立契约，以及 D-041/D-046 周期 `context-name` 的最小可见性。
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

## 三套连贯的完整体验组合

下面用同一项假设任务比较实际体验。所有文件名、错误原因和测试数字只是人格样例中的共同假设事实，不表示当前仓库已经有这些改动。

这些是帮助理解整体感受的**组合样例**，不是 PP-01 的三个原子选项。完整组合为：样例 A = `PP-01 A + PP-06 A + PP-14 A + PP-15 A + PP-16 A + TS-18 A`；样例 B = `PP-01 B + PP-06 B + PP-14 C + PP-15 B + PP-16 B + TS-18 B / Autonomy=explanatory`；样例 C = `PP-01 C + PP-06 C + PP-14 A + PP-15 C + PP-16 C + TS-18 B / Autonomy=direct`。正式回复时，人格语气、进度时点、工具叙述、最终报告、普通回答详略和既有文字块内部解释粒度分别由 PP-01、PP-06、PP-14、PP-15、PP-16、TS-18 决定，任何一组都不能暗改其他列。

假设用户输入：

```text
修复配置解析器在遇到重复 Model section 时静默覆盖的问题。
只改必要文件，并运行相关测试。
```

假设共同事实：根因是 parser 以 section 名作键直接覆盖前项；修复后返回带第二处行号的 `CFG-DUPLICATE-SECTION`；新增一项回归测试；相关测试 18/18 通过；没有修改其他文件。

### 组合样例 A：克制的工程伙伴（推荐）

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

### 组合样例 B：温和解释型协作者

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

### 组合样例 C：事务式静默执行器

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

推荐组合 A 作为整体基线。用户在当前消息里要求“详细解释”时可以得到接近 B 的回答；要求“直接做，不要过程”时可以得到接近 C 的回答。这三套不成为人格 preset；是否提供窄 `Autonomy` 字段只由 TS-18 决定。

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

## 六个核心 purpose 与周期 `context-name` purpose 必须各有契约

六个核心请求具体能看见哪些 Credential、Prompt、历史、文件、工具、审批和诊断，集中列在 [数据分类候选](../DATA-CLASSIFICATION-CANDIDATE.md)；本节只决定每类请求的职责与 Prompt 语义，不能靠文字提示扩大那张 Runtime 白名单。D-041/D-046 另行确认了条件周期 `context-name`：它只有在 interval、durable main-turn watermark 与 `AutoRenameDisabled` gate 同时满足时才产生请求、费用和 XML 事实，不是常驻第七个核心 purpose。

一个 `DoubleCheck` 开关可以控制多种复核，但不能把不同请求伪装成同一种 chat。推荐候选 purpose 名称和边界如下：

| purpose | 看到的主要输入 | 工具 | 输出 | 是否进入主模型对话视图 |
| --- | --- | --- | --- | --- |
| `main` | 有效指令 bundle、当前用户目标、模型视图、工具 schema、动态状态；PJ-11 B/C 时再带 `phase=plan|execute` | execute 按 Runtime/Permission；plan 仅 direct list/read/search，仍过 Permission，并在 M05-56 B 时叠加 SensitiveRead | 自然语言、合法 tool calls 或 typed control；plan 可产 PlanArtifact | 是；PlanArtifact 作为控制事实而非授权 |
| `side` | 提交旁问时的已提交 Context 快照、旁问文本、只读目的 | 无 | 一条直接回答 | 默认否；作为 side 事实保存 |
| `action-review` | 已规范化动作、参数/cwd/目标、确定性权限结果、相关用户意图与风险事实 | 无 | `allow/reject/uncertain` + 原因/风险 | 否；作为控制/审计事实 |
| `termination-review` | 任务目标、当前 turn 摘要、工具/验证事实、未完成项、主模型结束理由 | 无 | `finish/continue/uncertain` + 原因/缺口 | 否；verdict 可交回主模型 |
| `compaction` | 被选中的规范历史范围和必须保留槽位 | 无 | 结构化摘要与来源范围 | 仅摘要进入派生模型视图；原历史保留 |
| `self-test` | `phase=capability`：最小 synthetic probe 与公开 Model 能力声明；`phase=semantic`：已脱敏配置和 Stage 1/2 事实 | capability 只可带 inert synthetic schema，永不连接 Tool Runtime；semantic 无 | capability 为 typed observation；semantic 为 `ok/warning` + advisory | 否；进入诊断报告，两个 phase 分开记账 |
| `context-name`（D-041/D-046 条件周期） | 当前名称、目标和最近已完成 main turns 的有界持久化命名视图 | 无 | 一个有界 basename 候选；Runtime 本地校验并按当前 marker 自动提交或丢弃 | 否；request/result/采用或取消分别保存 |

每种 purpose 都需要独立 request ID、Prompt version、用量、超时、错误和结果身份。`self-test` 还必须带 `phase=capability|semantic`，不能把 Stage 2 的真实请求伪装成无身份的网络探测；Stage 1 没有 Model 请求，因此不建立 request manifest。即使都使用当前 Model，也不能在 XML 中合并身份。

每种 purpose 还需要独立的最小充分数据视图：

- 任何 purpose 都不自动获得整个 XML、原始 HTTP body 或任一 registered config-secret value；最小视图由 typed data registry 生成。
- action review 只看待审动作、确定性结果、相关意图和风险事实；termination review 只看判断完成所需的目标与执行证据。
- compaction 必须看到所选历史中的真实用户/模型/工具事实，才能生成有效接盘摘要，但结构化凭据仍在装配前移除。
- 若 reviewer 或 compactor 使用不同 endpoint，等于把会话事实发送给另一个数据接收方，必须由独立配置和隐私确认决定，不能把“只是复核/压缩”当作无外发。
- 用户自己写进对话或文件内容中的秘密无法可靠自动识别；最小视图降低暴露面，但不能作“绝无秘密”的虚假保证。

`context-name` 不复用 `main`、`side` 或 `compaction` 身份。它只看到当前名称、目标和最近已完成 main turns 的有界持久化投影；不见工具 schema、Credential、任意文件正文、完整工具输出、审批 token、隐藏推理、完整历史或同目录其他 Context 名称。碰撞检查、非法字符处理和 no-replace 全部在本地完成。请求失败、离线、输出无效、取消或 marker 已变为 `true` 时保留当前名称，不阻断任务；传输迟到只能保存 usage/result/cancel 事实，不能采用候选。

### `main`

- 唯一可以正常驱动 AgentLoop 和请求工具的模型目的。
- 使用完整有效的用户指令层级、当前模型视图和实际可用工具。
- 若 PJ-11 A，`phase` 和 PlanArtifact 均不存在。若选 B/C，main request 必带 `phase=plan|execute`：plan phase 只装配 direct list/read/search schema，仍经过普通 Permission；只有 M05-56 B 时再叠加 SensitiveRead。Runtime 硬拒绝 shell、direct network、write/rename/delete；execute phase 才恢复普通工具集合。
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

### `context-name`（D-041/D-046 已确认的周期 purpose）

- 它不是第八个核心 purpose，也不能由 `AutoNameOnExit` 等旧字段暗中开启。只有 `AutoNameEveryMainTurns=N>0`、durable main-turn 水位达到下一周期且 XML `AutoRenameDisabled` 缺失/`false` 时才能 admission；`N=0` 全局关闭，默认 `N=10`。
- 每次合格周期至多建立一个低优先级、无工具 logical request。side、review、self-test、工具迭代和失败/取消 turn 不计水位；禁用期间不累积待补请求，取消 marker 时从当时 durable 水位建立新 baseline，不立即命名。
- 使用触发时当前、已经验证可用的 Model/endpoint/ConfigGeneration snapshot，不自动 fallback 到另一 Model；目标失效或不支持该 purpose 时按失败保留当前名称。
- 它有独立 request identity、版本化 Prompt、硬上限 lifecycle budget、attempt/usage/result，并进入与 main 共用的有界 Model scheduler；不能复用 main/side/compaction 的身份或预算。
- 新 main、退出、显式取消或超时都可终止尚未完成的命名请求，Runtime 不等待它才推进任务；已无法阻止的迟到响应只保存 request/usage/cancel 事实，不得采用名称，也不在恢复后补跑。
- Prompt 只接收完成命名所需的有界会话投影，只返回一个候选 basename；Runtime 不接受路径、目录跳转、权限或覆盖指令。
- 候选必须先经过本地字符、长度、保留名、碰撞和 no-replace 校验，再由统一 rename transaction 发布；成功自动 rename 不设置 `AutoRenameDisabled`，失败不改变 main outcome。
- 手工 rename 成功则在同一事务设置 `AutoRenameDisabled=true`；context-repl 可以查看、添加或取消这一专用 marker，但不能把它扩展成通用 flags bag。

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

- 任一 registered config-secret exact value 永不因 Prompt 快照进入 XML；普通 Prompt/用户文字可能含 Runtime 不认识的秘密，不能承诺自动找全。
- 但是用户可能自己把 token、密码或内网信息写进 SystemPrompt、ContextPrompt、项目规则或普通对话。程序不能一边承诺完整历史，一边声称能可靠识别并自动删除所有这类文本。
- 编辑 Prompt 时应明确提醒“此内容会进入当前 Context 历史/导出”；导出前提供秘密风险预览。
- 若用户仍确认保存，文本作为用户内容持久化；自动模型改写或静默脱敏都会破坏可解释性。

XML 的元素名、去重 ID、digest 算法和写入协议留给存储包；本包只决定必须能表达上述语义。

## 已确认周期命名对冻结题面的解释

下面正式题面继续逐字保留。其后任何“只有 `PJ-12=B` 才在第一个 main turn 后产生一次 `context-name`”或“终身最多一次”的旧候选文字，已经被 D-041/D-046 取代：现行 `context-name` 是由 `AutoNameEveryMainTurns>0`、durable main-turn 周期和 `AutoRenameDisabled!=true` 共同生成的低优先级条件 purpose；取消 marker 从当前 durable 水位建立新 baseline，marker 变 true 会使在途结果失效。Prompt 组以后无论选择哪条人格/组件路线，都只能消费这个现行 purpose，不能恢复一次性 lifecycle 或旧开关。

## 真正需要项目负责人回答的十八组问题

可以回复 `PP-01 A；PP-04 只采用用户明确指定的文件；PP-13 B；其余暂缓`。没有明确回复的编号继续保持待决，不会因为本文写了“推荐”就自动写入 `DECISIONS.md`。

### PP-01 默认 Agent 人格

- A：克制、平静、协作式；措辞中性而明确，承认不确定性，不夸张、不谄媚。（推荐）
- B：温和、耐心、鼓励式；对同一份内容使用更友好的措辞，但不自动增加背景、解释、消息或报告栏目。
- C：干脆、事务式；对同一份内容使用主动语态、减少寒暄，但不删除 PP-06/PP-14/PP-15 要求的事实，也不缩短或扩大其消息/报告上限。

推荐 A。它只决定“已经需要输出同一份 Agent 内容时怎样措辞”。何时播报、是否逐工具说明、最终报告栏目和普通解释深度分别只由 PP-06、PP-14、PP-15、PP-16 选择；既有文字块内部解释粒度只在 TS-18 B 时由 `Autonomy` 调整。用户仍可在自然语言或 Prompt 中临时改变语气，但不能借人格词改变 Runtime 事实、安全或控制流。

关联：`AQ-004`、`AQ-048`、`AQ-183`、`INSTR-02`、`TUI-03`。

### PP-02 回复语言策略

- A：没有明确语言指令时，Agent 自然语言默认跟随当前用户消息的主要语言。（推荐）
- B：没有明确语言指令时，Agent 自然语言默认 English，即使用户只是用另一种语言提问。
- C：没有明确语言指令时，以当前 Context 第一条主用户消息的主要语言作为会话默认，之后不因单条消息混用语言而自动切换。

推荐 A。它不增加 UI 本地化系统，又能自然跟随当前对话。三项都只决定“没有明确指令时的默认”：当前用户明确要求的回复语言、ContextPrompt/SystemPrompt 的持久语言要求仍按 PP-03 的统一权威链裁决；固定 UI、error ID、配置键和机器字段始终 English/ASCII。

关联：`PROD-15`、`AQ-045`、`AQ-292`。

### PP-03 指令权威链和用户 Prompt 的替换边界

- A：Runtime/built-in invariants 不可覆盖；当前及历史有效用户指令（后来的纠正优先）高于 ContextPrompt，ContextPrompt 高于明确采用项目规则，后者高于 SystemPrompt；SystemPrompt 与 ContextPrompt 同时装配、只在冲突处由后者覆盖，二者都不能替换 invariants。（推荐）
- B：Runtime/built-in invariants 仍不可覆盖，当前用户消息和已明确标记的用户纠正仍最高；但 ContextPrompt 高于更早的普通工作习惯，使会话级长期规则可以替代旧 turn 的默认偏好，之后才是采用项目规则和 SystemPrompt。
- C：Runtime/built-in invariants 与当前/历史明确用户要求保持最高；ContextPrompt、采用项目规则和 SystemPrompt 作为同级持久默认同时送给 main，若模型判断它们不能同时满足，必须在调用工具前返回 typed `ask-user`，不得自行挑一个来源获胜。

推荐 A。它最符合“后来的明确用户纠正获胜”，且恢复时能解释每一层；B 让 ContextPrompt 更像会话政策，旧 turn 更容易被统一替代；C 最保守但会增加冲突检测和人工中断。三项都禁止持久 Prompt 压过当前明确要求，也禁止把来源混成一段让模型猜。

本组只排序已经被 PP-18 判定仍 active 的用户指令，不自行定义“历史有效”“普通习惯”能活多久。普通用户消息、明确 correction、`.prompt` 持久层和 adopted project rule 必须保留不同 kind/source/scope；压缩或恢复不能把一段旧 assistant/side/tool 文字升级为用户指令。若 PP-18 的 lifecycle 无法确定某条旧文字是否仍 active，必须按 PP-17 的澄清策略处理，不能因它在历史里出现过就永久生效。

关联：`AQ-001`、`AQ-002`、`AQ-003`、`AQ-046`、`AQ-047`、`AQ-055`、`AQ-056`、`INSTR-02`、`SAFE-10`。

### PP-11 旧 `Model.CustomPrompt` 怎样收口

- A：删除这一独立权威层；每一段旧 `Model.CustomPrompt` 都先作为独立来源列出，由用户逐项选择迁入全局 `SystemPrompt`、一个明确选中的 `ContextPrompt`，或明确丢弃。（推荐）
- B：保留 `Model.CustomPrompt` 作为 Model-specific 用户默认；它不能压过 Runtime invariants、当前明确用户要求或历史有效纠正，具体位置服从下面的 PP-03 × PP-11 组合表。
- C：保留 `Model.CustomPrompt` 作为最低优先级的 Model-specific compatibility hint；它仍标为用户配置，只进入该 Model 的 instruction component，低于其他持久用户 Prompt，不能改写 role mapping、消息 serializer、tool/control schema、purpose 白名单或 Runtime 规则，也不能冒充内置 adapter 权威。

推荐 A。现有 `SystemPrompt` + `ContextPrompt` 已能表达全局与会话偏好；保留第三层只会让模型改名、恢复和权威冲突变得难以解释。A 不是“把所有旧文本拼到当前会话”：迁移器不得猜哪个 Context 是目标，也不得把同名 Model 的多段旧文本静默合并。B/C 若被选中都必须生成有界 typed 字段、Prompt component snapshot 和 Model 切换 transition；真正的线协议模板仍是内置、版本化 adapter 事实，用户字段不能替换它。

#### CustomPrompt 与指令链的九种组合（PP-03 × PP-11）

下面的“高于”只表示用户指令发生真实冲突时的裁决顺序；无冲突组件仍一起装配。所有九种组合中，Runtime/built-in invariants 始终最高，当前明确用户要求始终不能被持久 Prompt 压过。

| PP-03 | PP-11 A：删除层 | PP-11 B：Model-specific 用户默认 | PP-11 C：compatibility hint |
| --- | --- | --- | --- |
| A：后来明确指令优先 | 迁移后的文本按目标层正常参加：有效用户指令 > ContextPrompt > adopted project rules > SystemPrompt | 有效用户指令 > ContextPrompt > adopted project rules > Model.CustomPrompt > SystemPrompt | 有效用户指令 > ContextPrompt > adopted project rules > SystemPrompt > compatibility hint |
| B：ContextPrompt 可替代旧习惯 | 当前用户/明确纠正 > ContextPrompt > 较早普通用户习惯 > adopted project rules > SystemPrompt | 当前用户/明确纠正 > ContextPrompt > 较早普通用户习惯 > adopted project rules > Model.CustomPrompt > SystemPrompt | 当前用户/明确纠正 > ContextPrompt > 较早普通用户习惯 > adopted project rules > SystemPrompt > compatibility hint |
| C：持久默认冲突即询问 | 迁入目标后成为该目标层；ContextPrompt、adopted rules、SystemPrompt 的不可兼容冲突形成 typed `ask-user` | Model.CustomPrompt 加入 ContextPrompt、adopted rules、SystemPrompt 的同级持久冲突集合；不可兼容时 typed `ask-user`，不让模型自行挑选 | compatibility hint 仍在整个持久冲突集合之下；它与高层冲突时直接由高层获胜，不把适配提示升级成需要用户裁决的权威 |

PP-11 C 中的“compatibility”只是类似“该模型更适合短句/避免某种可选格式”的用户提示。协议、认证、role、tool、control、stream parser 和安全限制只来自版本化 adapter 与 Runtime；用户文字即使声称“忽略 tool schema”也没有这种能力。

#### PP-11 A 的迁移必须是管理事务

1. 读取旧 INI 后，按 Model identity 列出每个非空来源、字节数和 digest；正文可在明确打开详情后查看，不能只显示一个笼统“发现旧 Prompt”。
2. 每个来源分别选择 `SystemPrompt`、一个明确命名且已存在的 Context 的 `ContextPrompt`，或 `discard`。没有“当前 Context”默认目标；非交互运行不能猜。
3. 多个来源进入同一目标时先生成有稳定顺序的合并 draft，展示来源边界、重复/冲突提示和最终 digest；用户可以编辑、改目标或取消。不得简单串接后发布。
4. 先原子保存目标 Prompt/Context transition 并验证，再清除对应旧字段。一个目标失败时保留尚未迁移的旧来源，记录 partial outcome，不把部分成功伪装成全成功。
5. 已完成 request 的历史 Prompt bundle 和旧 XML snapshot 永不改写。迁移只改变下一 turn；新 request 记录旧来源、目标、迁移事务和 effective digest。

若 PP-11 A 迁入 `SystemPrompt` 或 `ContextPrompt`，以后权威位置完全由 PP-03 的目标层决定，不再保留隐藏的 Model scope。若 B/C 保留字段，Model 切换必须写 `ModelTransition`，并在下个 request snapshot 中清楚记录旧/新 Model、旧/新 CustomPrompt component identity、选中的 PP-11 route 与 effective Prompt digest。跨机只有 XML、没有原 INI 时，reader 仍能解释历史 request；继续运行则按目标机当前 Model 配置产生显式 transition，不能把快照悄悄当作现行配置。

配置 schema、config/model REPL、Prompt assembler、Context XML 与测试必须同时投影本组：A 验证逐来源迁移、取消、部分失败和恢复；B 验证九宫格中三条优先链及 Model switch；C 还要有恶意 compatibility hint 不能改变 serializer/tool/control/权限的 contract tests。

关联：`AQ-001` 至 `AQ-003`、`AQ-059`、`AQ-060`、`AQ-143`、`ARCH-05`、`CFG-05`、`CFG-10`、`CFG-12`、`CFG-19`、`INSTR-02`、`INSTR-05`、`CTX-15`、`F4-09`。

### PP-04 项目规则怎样成为指令

通俗解释：仓库里的 README、注释和任意文本本来只是模型可读取的数据；一旦自动把某个文件提升为“项目规则”，它就会持续影响 Prompt、工具使用和最终报告。陌生仓库可以故意放置这种文件，因此这里决定的是**谁有权把仓库文本提升成指令**，不是模型能否普通读取文件。无论选择哪项，项目规则只能在 PP-03 权威链内约束任务，不能扩大 Permission、跳过审批或覆盖 Runtime 硬门；采用后都保存规范来源、作用域、内容 digest 和版本快照，后续变化只由 PP-13 收口。

- A：首版不自动发现。用户通过明确动作指定一个或多个文件并确认作用域后，才生成规则快照；没有采用动作时，同名文件仍只是普通项目数据。（推荐）
- B：只自动发现工作区根的一个固定、文档化文件名；启动时先显示来源和 digest，按所选启动/信任流程采用或拒绝。子目录同名文件不叠加，缺失即无项目规则。
- C：按确定的根到叶顺序自动发现工作区根和目标目录链上的固定规则文件，显式显示叠加顺序、冲突来源和最终 digest；目录/目标改变时旧快照按 PP-13 失效或重新确认。

推荐 A。它最符合“需要时由用户整理文档让模型阅读”和保持简单，也避免陌生仓库文本仅凭文件名自动取得指令权威；代价是常用仓库每个新 Context 都需要明确采用。B 提供熟悉的单文件约定，但首次进入陌生仓库仍必须让采用行为可见；C 最适合大型分层仓库，却新增作用域、优先级、移动文件后的失效和注入审计成本。三项都不允许默默 live-read 后让同一 turn 中途换规则。

关联：`AQ-005`、`AQ-006`、`AQ-296`、`INSTR-01`、`INSTR-03`、`INSTR-04`、`SAFE-10`。

### PP-05 六个核心 purpose 是否使用独立契约

- A：main、side、action-review、termination-review、compaction、self-test 六个核心 purpose 各自有独立 Prompt、输入白名单、工具权限、输出和版本。（推荐）
- B：main 使用独立 Prompt；其他五类共享一个版本化 utility base，但每类仍有独立输入 manifest、无工具能力、purpose-specific output schema 和短扩展指令。
- C：按四个模板族维护：main、side、review（action/termination 各自 schema）、derived（compaction/self-test 各自 schema）；每个具体 purpose 仍保留独立 request identity、Runtime 白名单和结果类型。

推荐 A。它多维护几份短 Prompt，却最容易分别评估 side/复核/压缩是否偏离职责；B 的维护文本最少，purpose 扩展和 base version 必须一起审计；C 在复用与可测试性之间折中。无论本组选什么，Runtime 的工具/数据白名单都不能放宽；若 `PJ-12 B` 成立，`context-name` 总是增加独立的条件契约，不复用上述六个核心身份，本组不对此二次投票。

main 的具体 control schema 是本组所选模板策略的下游输入，不由 PP-05 决定：`finish(partial)` 是否存在只投影 AL06-36，普通无-control reply 的 correction/yield/implicit-finish 路径只投影 AL06-38。

关联：`AQ-008`、`AQ-019`、`AQ-020`、`AQ-099`、`AQ-109`、`AQ-251`、`AQ-252`、`AQ-259`、`AQ-358`、`AQ-359`、`MODEL-12`、`CTX-07`、`DIAG-05`、`COMP-01`、`AL06-36`、`AL06-38`。

### PP-06 复杂任务的进度更新时点

- A：只在任务开始、方向实质变化、进入长/高风险阶段和阶段完成时给一条短更新；短问答不额外播报。（推荐）
- B：每个 main request/修正循环开始和结束都给一条短更新；工具本身怎样叙述仍由 PP-14 决定。
- C：不生成独立的模型进度块；Runtime 的 typed STATUS/TOOL/ACTION 事实仍照常显示，PP-14 所选的工具目的说明也不因此消失。

推荐 A。它让用户知道长任务正在做什么，又不让进度文字重复 Runtime 的机械状态。三项只决定**什么时候出现进度块**；PP-14 独占工具叙述，PP-15 独占最终报告，PP-16 独占普通回答详略，不能再由一个选择同时改变四件事。

PP-01 只改变已经要输出的语气。TS-18 B 若存在，也只能改变本组选定进度块内部的解释粒度，不能增加更新时点、额外工具、验证或费用。每条进度只能描述已知方向/事实，不能把计划写成已完成。

关联：`AQ-051`、`AQ-293`、`PROD-02`、`TS-18`。

### PP-14 工具动作的模型叙述密度

- A：默认不逐工具复述；Runtime 的 TOOL/ACTION block 展示规范动作，模型只在一批工具目的不明显、风险较高或方向改变时给一句原因。（推荐）
- B：每个 tool batch 前给一句目的，整批 results 收口后给一句结果摘要；不为同批每个 call 单独播报。
- C：完全不生成模型撰写的工具目的或结果叙述，只显示 Runtime 的 canonical TOOL/ACTION/result 事实；最终报告仍服从 PP-15。

推荐 A。它保持 transcript 简洁，同时在真正需要理解“为什么要做”时提供模型解释。B 让每批动作都容易跟踪，C 是完整的模型叙述静默路线。三项都不能用模型摘要替代 canonical tool 参数/result、审批或错误，也不能让“解释”本身取得授权；PP-06 C 只关闭独立进度块，不能暗中选择本组 C。

v0.1 不提供“每个 call 前后都由模型再复述一次”的第四路线：Runtime 已经逐项显示 canonical TOOL/ACTION/result，逐 call 双重叙述只会在旧终端制造重复和更高 Token；需要这种个人偏好的用户仍可在 Prompt 中请求，但它不能改变 Runtime 事实块或形成受保证的产品模式。

关联：`AQ-050`、`AQ-071`、`INSTR-06`、`TUI-09`、`TOOL-07`。

### PP-15 完成时最终报告的结构

- A：结果优先；只在适用时追加 `Changes`、`Verification`、`Remaining/Unknown`，没有改动或验证时不显示空栏目，但不得隐去未验证和 unknown effect。（推荐）
- B：每个 main terminal outcome 固定显示 `Outcome / Changes / Verification / Remaining` 四段；不适用项明确写 `none` 或 `not run`。
- C：使用一个紧凑段落说明结果；若存在 failed/unverified/unknown，必须在同一段以稳定标签点名，不能只说 success/failure。

推荐 A。简单回答可以很短，Coding Agent 的真实改动和验证仍有稳定位置；B 最可预测但日常噪声最大，C 最紧凑却更依赖标签纪律。本组决定报告形状，不决定完成真假；typed outcome、工具事实和验证证据仍由 AgentLoop/Runtime 决定。

关联：`AQ-053`、`AQ-110`、`AQ-294`、`LOOP-22`、`PROD-03`、`DIAG-12`。

### PP-16 普通回答与设计讲解的默认详略

- A：按任务自适应：简单事实/确认直接回答；架构、风险、学习型问题先给结论，再用通俗分层解释关键原因和取舍；用户的“简短/详细”明确要求优先。（推荐）
- B：默认解释型；即使简单问题也补背景、推理依据、替代方案和下一步，仍受有界输出限制。
- C：默认极简；除非用户明确要求详细，否则只给结论和必要动作，设计问题也不主动展开完整取舍。

推荐 A。它最符合既要日常简洁、又要能把复杂架构讲明白的目标。本组只改变同一回答需要多少解释，不增加工具、联网、验证、进度消息或最终报告栏目。

关联：`AQ-391`、`INSTR-07`、`PROD-02`、PP-01、PP-15。

### PP-17 何时澄清，何时带假设继续

- A：只有答案会改变目标/安全边界、产生不可逆或外部副作用、需要新权限/费用，或多个路线会造成显著不同结果时才先问；可逆、局部、低风险细节用显式假设继续，并在结果中说明。（推荐）
- B：只要存在两个合理解释就先问，不在用户回答前采用任何语义假设。
- C：除非物理上无法继续，否则模型总选最合理路线推进；只在 Permission/Runtime 强制阻断时停下询问。

推荐 A。它让 Agent 有自主性又不替用户决定真正改变产品/数据/费用的事项。三项都不能用“假设”绕过 Permission、DoubleCheck、外部写入授权或已确认项目决定；假设被用户纠正后按 PP-18 形成明确 supersede，而不是悄悄改写历史。

关联：`AQ-054`、`INSTR-08`、`LOOP-10`、`PROD-02`、`SAFE-03`。

### PP-18 普通用户指令的生命周期

- A：普通用户消息默认绑定当前 durable work-item：从一个 idle main 输入或 queue item 建立 root work-item-id，经其 causally-linked steer、ask-user 回答、协议纠错和后续 turn 延续，直到该工作项形成真正 terminal outcome；`waiting_user` 本身不关闭 work item。新建无关 main/queue item 是新 work item，不继承；“仅这一次/本轮”可缩成 turn-local。跨无关工作长期生效的偏好必须通过 `.prompt`/ContextPrompt/SystemPrompt 显式保存。（推荐）
- B：普通消息只对创建它的 turn 有效；下一 turn 若要继续遵守，用户必须重述或写入 `.prompt`，历史只作为 data。
- C：普通消息中的指令默认持续整个 Context，直到用户明确撤销；任务完成不会自动结束其作用域。

推荐 A。它保留连续工作中的真实约束，又不让一句临时要求永久污染以后所有任务。这里的 work-item-id 只是 append-only 因果元数据，不是 PJ-11 的 PlanArtifact、隐藏 AgentState 或永久 ContextId；F4-03 仍决定 ask-user 回答创建旧 turn 延续还是新 turn，F4-04 的 `retry task` 是否建立新 work item 必须由其 action 规范明确投影，不能靠相邻文本猜。

Runtime 不尝试从任意自然语言完美抽取“真正意图”。普通 Enter/queue/steer 的 user event 只写本组选中的 default scope；自然语言中的“仅本轮”等文字仍由模型理解，但不会被 Runtime 偷偷改成 scope metadata。若用户需要精确缩短/扩大范围或撤销旧要求，统一使用 typed `.instruction list`、`.instruction add --scope turn|work-item|context ...`、`.instruction supersede <user-event-id> ...`、`.instruction revoke <user-event-id>`。

任何 `add/supersede` 都必须同时绑定 TU-19 的明确 `main|queue|steer` intent 或一个仍新鲜的 exact turn/work-item ID；idle、busy、queued 目标含糊时拒绝，不使用“当前大概是哪一轮”。当前 turn 已开始采样后的变更形成 steer/correction，只从下一个 model-safe point 生效，不追溯改写已发送 Prompt；Context scope 则作为管理变更从下一 turn 生效。这些动作必须由 TU-32 registry/help 生成、显示目标全文摘要并写 append-only link，不能让模型事后替用户补 metadata。

XML 保存完整 user event、declared/default scope、work-item/turn link、seq 和显式 supersedes/revokes link；Prompt/model-view 使用这些来源建立 `ActiveUserInstructionSet`，无法确定自然语言内容是否冲突时按 PP-17 询问，但不会改写 scope。assistant、side、review、tool/file 内容永远只是 data，不能进入该集合；用户执行 `side-use` 也只新增一条“请考虑这份 data”的用户指令，不把 side 正文升级成权威。

关联：`AQ-046`、`AQ-047`、`AQ-392`、`INSTR-09`、`CTX-07`、`COMP-06`、AL06-23、PP-03、PP-12、F4-03、F4-04。

### PP-19 内置 Prompt bundle 的文本冻结政策

本组现在只决定“最终文字怎样成为协议”，不提前写最终英文正文。PP/AL/tool/control owner 尚未确认前，任何样稿仍是 illustrative；等语义闭合后再按本组政策冻结。

- A：逐段 ASCII-English 原文、变量插槽、组件顺序、bundle version、digest 与 golden assembly 一起进入版本控制；任何措辞变化都建立新 version，并保留旧 request 可重建性。（推荐）
- B：只冻结 typed 语义组件/字段，维护者可在不升 bundle version 的情况下调整英文措辞；每次 request 仍保存实际全文/digest 解释历史。
- C：启动时根据 schema、Model 能力和当前配置动态生成内置 Prompt；只保存本次生成结果与 generator version，不维护稳定逐段 golden 原文。

推荐 A。Prompt 微小措辞就可能改变 Agent 行为，把它当协议审阅和回归最可靠；B 维护快但同版本行为可漂移，C 最灵活却最难跨机/跨版本复现。三项都要求每个 request/XML 能重建当时 exact bundle，adapter wire template 与 model-facing Prompt 分离；Runtime enforcement、Permission、tool schema、budget 和真实 outcome 永远不依赖模型遵守这段文字。

关联：`AQ-183`、`INSTR-02`、`INSTR-05`、`INSTR-10`、`CTX-15`、PP-03、PP-05、PP-07、AL06-02、TS-23、TP-016。

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

若希望采用当前推荐基线，请明确回复全部 18 个正式组：

~~~text
PP-01 A
PP-02 A
PP-03 A
PP-11 A
PP-04 A
PP-05 A
PP-06 A
PP-14 A
PP-15 A
PP-16 A
PP-17 A
PP-18 A
PP-19 A
PP-07 A
PP-08 A
PP-09 A
PP-13 A
PP-12 A
~~~

也可以只回复差异，例如 `本包其余接受推荐；PP-01 B；PP-12 C。` 推荐不是决定，未明确回复的编号继续保持 unanswered。

## 本包确认后的归档产物

项目负责人回复后，只把明确选择归档到：

- `DECISIONS.md`：人格、语言、回答/进度/工具叙述/报告风格、澄清阈值、用户指令生命周期、权威链、项目规则和 purpose 总体契约。
- `18-prompt-and-workspace-instructions.md`：来源、作用域、canonical bundle、版本和 role mapping。
- `09-agent-session.md`：六个核心 request purpose 与 D-041/D-046 的周期 `context-name` purpose 怎样进入 AgentLoop；不复制 Prompt 原文。
- `05-configuration.md`：SystemPrompt、ContextPrompt 管理入口和大小校验。
- `10-context-storage.md`：Prompt 组件快照、引用和 transition 的持久语义。
- `12-context-compaction.md`：compaction purpose 的输入/输出与 Prompt 不被摘要规则。
- `15-diagnostics-and-logging.md`：self-test purpose 的脱敏和 advisory 边界。

精确英文内置 Prompt 必须在上述语义确认后作为版本化协议另行起草，并用 golden assembly、冲突、注入、Model 切换和跨 Model 行为评估测试验证（`AQ-183`、`AQ-357`）。尚未回复的 PP 条目继续保持待决。

## 完成标准

本包完成后，下面每个问题都应有唯一答案：

1. 同一个任务下，普通解释、进度、工具叙述和最终报告分别默认说多少、什么时候说。
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
12. 普通用户消息是仅本轮、当前任务还是整个 Context 的指令；`side-use` 为什么仍不会把模型文字升级成权威。
13. 哪些低风险细节可以声明假设继续，哪些目标、安全、费用和副作用分歧必须先问。

这些答案确认后，才适合冻结逐字英文 Prompt；不能先写一段长 system text，再倒推它到底代表什么产品规则。
