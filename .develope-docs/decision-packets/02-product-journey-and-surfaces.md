# 决策包 02：产品旅程、启动路由与交互表面

更新日期：2026-07-18

状态：等待项目负责人回复；本文的推荐、示例文案和方案编号都不是已确认决定

## 本包要决定什么

本包只回答一个面向用户的问题：从输入 `yaca` 到安全退出，用户会依次进入哪里、看到什么、什么时候需要选择，以及异常会被路由到哪里。

它覆盖：

- 正常主旅程：解压、配置 Model、打开工作目录、开始任务、退出、再次继续。
- 裸 `yaca` / `yaca .` 的启动路由。
- 配置缺失、配置损坏、没有可用 Model 和暂时离线时的入口。
- 当前工作区没有 Context、存在最近 Context、存在未正常结束 Context 时的区别。
- 空 Context 什么时候真正成为一个可恢复任务。
- chat、`model-repl`、`config-repl`、`context-repl`、self-test、help 和 recovery 的关系。
- Context 被其他进程占用时的用户体验。
- 空闲退出、忙时退出和异常关闭的产品承诺。

本包不决定：

- Agent 的人格、回答语言和 Prompt 原文；它们属于 Prompt 决策包。
- queue、steer、side、工具循环和 DoubleCheck 的内部状态机；它们属于 AgentLoop 与安全决策包。
- Context XML 的元素、提交算法、锁文件格式和恢复算法；它们属于存储决策包。
- 每个 REPL 的字段布局、完整命令语法和颜色表；它们属于配置/TUI/CLI 决策包。

这里可以决定“用户被路由到 recovery interaction，并且不得自动重放工具”，但不在本包设计 recovery 怎样解析或修复底层文件。该 interaction 是独立 surface、context-repl view 还是 chat state，只由 PJ-08 决定。

## 已经确认、这次不重新询问的前提

1. 主入口是 `yaca [目录]`；裸 `yaca` 与 `yaca .` 完全等价。
2. 传入目标必须是已经存在、能够进入的真实目录；更细的链接和路径规范化规则由路径/平台子系统的编号契约拥有，不在本包形成额外选择。
3. 没有首次运行欢迎页或自动设置向导。首次 Model 配置由用户显式运行 `yaca --model-repl`。
4. 配置加载包含配置检查；正常 Agent 不能带着损坏配置继续运行。
5. 启动、帮助、配置浏览、Context 浏览和静态自检不得隐式联网。
6. 主配置和当前 Context 中记录的 Model/Permission 等状态不一致时，必须给用户可见提示，不能静默伪装为原状态。
7. 产品是简单、终端优先的单 Agent；不引入全屏 dashboard、鼠标或项目首页。
8. Context 没有永久 Context ID；名称或逻辑路径变化会改变实时 hash。

## 先统一几个通俗术语

为了避免把所有东西都叫“页面”，本文使用以下词：

| 术语 | 本文含义 |
| --- | --- |
| 一次启动（invocation） | 用户运行一次 `yaca ...`，直到该进程退出 |
| 工作区（workspace） | 本次 Agent 可以围绕其工作的起始目录边界；Git 根发现与边界关系由路径/权限子系统的编号契约拥有 |
| Context | 一个可保存、可恢复的任务及其完整接盘信息 |
| session | 某个 Context 在一次 yaca 进程中的打开期间 |
| 交互表面（surface） | 一个拥有独立进入/退出语义的逐行交互环境；候选集合由 PJ-08 确认 |
| 视图（view） | 某个表面内部的一种状态，例如列表、详情、编辑草稿、确认或错误 |
| ACTION 块 | 追加在终端中的短选择提示，不是全屏页面，也不是首次运行向导 |
| 新任务草稿 | 用户已经进入 chat，但尚未产生需要保存的任务状态 |
| recovery required | 继续之前必须先处理未完成、损坏或依赖缺失状态；另一个 writer 占用时使用独立的 lock conflict |

内部可以有不同终端后端，但 PJ-08 选中的表面集合及其动作在各平台必须一致。能力不足时只改变颜色、快捷键和状态行的表现，不改变路由结果。

## 编码前应能走通的完整主旅程

推荐把 v0.1 的正常用户旅程定义为：

```text
download/unzip platform zip
  -> yaca --version
  -> yaca --model-repl
       -> add/edit Model draft
       -> validate locally
       -> explicitly test if the user chooses network access
       -> save valid config
  -> yaca --self-test
       -> static checks
       -> optional explicit online stages
  -> yaca [directory]
       -> validate startup prerequisites
       -> choose new/continue only when relevant
       -> enter chat
       -> perform task
       -> graceful exit
  -> yaca --continue <selector>
       -> resolve and open the intended Context
       -> show any dependency mismatch before sending a model request
       -> continue work
```

这条旅程不是要求每次都运行 self-test，也不是首次设置向导。它只定义用户能用显式命令完成从零到可工作的闭环。

## 已收口的启动基线与对照

### 方案 A：按状态轻量路由，默认新任务（推荐）

正常启动没有首页。程序完成本地检查后，能直接进入 chat 就直接进入；只有当前状态确实存在选择时，才追加一个短 ACTION 块：

- 配置缺失/损坏：阻止正常 chat，打印可执行的管理入口。
- 没有相关 Context：进入 `new (not saved)` 的 chat 草稿。
- 存在普通最近 Context：显示“新建、继续、打开 context-repl”的短选择，默认新建，绝不静默继续。
- 存在未正常结束 Context：先进入 recovery；不能把它当作普通最近会话。
- 显式 `--continue`：只处理用户指定目标，不再弹普通最近列表。
- Context 被占用：显示冲突事实，允许返回、重试或在安全可行时只读查看，绝不自动抢占。

优点：没有 dashboard，也不会因静默恢复把新任务接到旧对话；异常仍然显著。每个状态只多一小段必要交互。

代价：同一工作区经常保留 Context 时，裸启动可能多一次选择。需要明确何时把一个 Context 称为“最近相关”。

### 方案 B：裸启动永远新建，所有恢复都必须显式命令

只要配置有效，`yaca [目录]` 永远直接进入新任务。旧 Context、未完成 Context 和锁冲突不会影响裸启动；用户必须使用 `--continue` 或 `context-repl` 才会看到。

优点：启动最短，行为极易记忆；没有任何自动扫描造成的提示。

代价：用户可能忘记一个刚刚崩溃或仍有未完成工作的 Context，随后在同一工作区开始重复工作。恢复能力虽然存在，但不容易发现。

### 反例 C：每次启动先进入任务中心（D031 已排除）

裸启动总是先列出最近 Context、新建、恢复和管理入口；用户选择后才进入 chat。

优点：历史最容易发现，适合把 Context 当作项目管理器使用。

它实质上是一个启动首页，与“没有首次页面、yaca 保持简单”的确认决定冲突；即使全新目录也要多一次选择，旧终端输出也更长。因此它只记录淘汰理由，不是待回复路线。

### 推荐结论

推荐方案 A。它把“没有首页”与“不能隐藏恢复风险”同时兑现：正常路径直接进入，只有存在真正分支时才出现一段运行时提示。方案 B 仍是 PJ-01 内合法的安静路线；反例 C 不可通过回复本包重新启用。

如果项目负责人认为普通最近 Context 不值得每次提示，可以对 A 做一个收缩：只对未正常结束 Context 强制提示，普通已完成 Context 只能通过 `--continue`/`context-repl` 找到。这仍然比方案 B 更重视崩溃恢复，但更安静。

## 候选的交互表面地图（PJ-08=A 时）

```text
                         +-> help/version
                         +-> model-repl
                         +-> config-repl
CLI router -------------+-> context-repl
                         +-> self-test
                         +-> chat  <----------------------+
                                |                         |
                                | open manager while idle |
                                +-------------------------+

Context target from bare-start notice / --continue / context-repl
                                |
                                +-> healthy -------------> chat
                                |
                                +-> recovery required ---> recovery
                                                            |
                                         resolved/read-only/exit
```

### 各表面的职责

| 表面 | 用户来这里做什么 | 不应该在这里做什么 |
| --- | --- | --- |
| chat | 提交任务、查看工作、执行会话级动作 | 修复损坏主配置、直接编辑底层 Context 文件 |
| model-repl | 添加、测试、启停、重排完整 Model 连接实例 | 修改当前 Context 的历史事实 |
| config-repl | 浏览有效配置来源，事务式修改非 Model 配置，并修复可修配置错误 | 管理 Context 目录树 |
| context-repl | 浏览、搜索、选择、重命名、删除和查看 Context 状态 | 编辑主配置字段 |
| self-test | 执行静态检查，以及用户明确同意后的在线/LLM 检查 | 自动修复或静默联网 |
| help | 显示当前表面可用命令和当前终端真正可用的快捷键 | 依赖有效配置或联网 |
| recovery | 解释为什么不能直接继续，并让用户安全处理恢复选择 | 自动重放未知工具副作用 |

`model-repl` 是配置系统的 Model 专用表面，不应拥有第二套配置文件或第二种保存规则。`config-repl` 是否把 Model section 显示为只读摘要并跳转到 `model-repl`，留给配置包决定。

本文 transcript 中的 `--config-repl` 是候选规范名称，目的是让表面容易理解；旧名 `--interactive-config-changer` 是否保留为兼容别名、所有参数怎样组合，统一留给 CLI 精确契约包确认。

## 启动路由状态表

下表描述推荐方案 A 的用户可见路由。它不是底层函数调用顺序，也不冻结退出码或错误 ID 的最终拼写。

| 启动条件 | 交互 Agent `yaca [目录]` | 显式管理/诊断入口 | 是否联网 | 是否进入 chat |
| --- | --- | --- | --- | --- |
| `--help` / `--version` | 不适用 | 直接输出 | 否 | 否 |
| 平台/架构与发行包不匹配 | 显示阻断错误并退出 | help/version 仍尽量可用 | 否 | 否 |
| 目录不存在、不是目录或不可进入 | 显示准确路径错误并退出 | 与目录无关的 help/version 可用 | 否 | 否 |
| 主配置缺失 | 显示配置缺失与 `model-repl`/`config-repl` 下一步 | bootstrap 管理入口、静态 self-test 可用 | 否 | 否 |
| 主配置语法/schema 损坏 | 显示定位后的配置错误 | help/version、bootstrap config-repl、静态 self-test 可用是推荐候选 | 否 | 否 |
| 配置有效，但没有可用 Model | 显示没有可用 Model 与管理下一步 | model/config/context REPL 和静态 self-test 可用 | 否 | 否 |
| 配置有效，Model 已配置但网络暂时不可用 | 不在启动时探测；照常进入本地 chat | 用户显式 model test/self-test 才联网 | 启动否 | 是 |
| 没有相关 Context | 进入 `new (not saved)` chat | context-repl 仍可显式打开 | 否 | 是 |
| 有普通最近 Context | 显示短 ACTION：new / continue / context-repl | 可转入 context-repl | 否 | 选择后 |
| 有一个未正常结束 Context | 显示 recovery required，不当作普通 recent | recovery/context-repl | 否 | 解决后 |
| 有多个未正常结束 Context | 打开 context-repl 的 recovery 过滤视图 | context-repl/recovery | 否 | 选择并解决后 |
| 显式 `--continue` 唯一命中且健康 | 打开指定 Context | 不显示其他 recent 候选 | 否 | 是 |
| 显式目标损坏、版本不兼容或依赖缺失 | 进入对应 recovery/只读说明 | recovery/context-repl/self-test | 否 | 解决后 |
| 显式目标已有 writer | 显示 lock conflict | retry / inspect read-only / back / exit 候选 | 否 | 不取得 writer 就否 |
| stdin 非 TTY | 不启动交互菜单；当前推荐失败关闭 | help/version/静态查询按 CLI 契约工作 | 否 | 否 |

### 多个问题同时存在时的推荐优先级

用户一次只应先处理最靠前且足以阻止后续判断的问题：

```text
invalid invocation / wrong package
  -> invalid directory or data root
  -> missing/damaged main config
  -> no usable Model definition
  -> Context selection
  -> Context health/lease/dependency recovery
  -> enter chat
```

例如配置已经损坏时，不应再用一串“Model 不存在、Context Model 对不上、无法联网”淹没根因。self-test 可以汇总多个静态错误，但普通启动只显示一个主阻断原因和下一步。

## ASCII transcript：主状态示例

以下示例用于决定信息和路由，不冻结最终空格、颜色或错误 ID。固定程序文字保持 English/ASCII；Context 名、路径和用户内容可以是用户数据。

### 1. 主配置缺失

```text
C:\Work\demo> yaca .

[ERROR CFG-NOT-FOUND] yaca cannot start an agent session.
  config: C:\Tools\yaca\__yaca__\config.ini
  reason: the main configuration does not exist
  network access: not attempted

Next:
  yaca --model-repl     Add the first Model.
  yaca --config-repl    Review or create the full configuration.
  yaca --self-test      Run static startup checks.

No Context was created.
```

这里不自动创建配置、不进入向导，也不显示空 chat。

### 2. 正常裸启动，没有相关 Context

```text
C:\Work\demo> yaca

YACA 0.1.0
workspace: C:\Work\demo
model: DeepSeek
permission: Std
context: new (not saved)

Type .help for commands.
>
```

`context: new (not saved)` 明确说明用户仅进入了新任务草稿。此时没有可显示的稳定 Context 名或 hash，不应伪造一个看似已经保存的身份。

### 3. 正常裸启动，发现普通最近 Context

```text
C:\Work\demo> yaca

[NOTICE] A recent Context exists for this workspace.
  name: fix-parser
  hash: 8a21f5c0d34071be
  last activity: 2026-07-18 17:42
  state: completed

[ACTION] Start from:
  1  New task                    (default)
  2  Continue "fix-parser"
  3  Open context-repl
start>
```

它是一次运行时选择，不是常驻首页。直接按 Enter 新建；程序绝不静默把新输入附加到 `fix-parser`。

如果负责人选择“普通 recent 不提示”的收缩方案，这一整块不会出现；只有未正常结束状态才触发 recovery。

### 4. 显式继续时发生 writer 冲突

```text
C:\Work\demo> yaca --continue fix-parser

[ERROR CTX-IN-USE] This Context is already open for writing.
  name: fix-parser
  hash: 8a21f5c0d34071be
  logical path: /C/Work/demo/fix-parser.xml
  writer: another yaca process

[ACTION]
  1  Retry
  2  Inspect read-only
  3  Open context-repl
  q  Exit                         (default)
context>
```

不显示“force unlock”作为普通快捷选项。陈旧 lease 的判定与接管证据属于存储/并发设计；产品层只保证不会因一个时间戳就自动抢走 writer。

## 空 Context 的产品语义

### A. 延迟到第一个需要保存的会话动作（推荐）

进入 chat 时显示 `new (not saved)`。只有用户提交第一条任务，或执行另一个明确需要持久化的会话动作时，才创建真正的 Context。用户立即退出不会留下空 Context。

优点：Context 列表不会被误启动、看帮助和立即退出产生的空文件污染；“Context”始终代表有可接盘信息的任务。

代价：第一条输入提交时必须先完成 Context 建立，失败就不能把输入视为已经接受。启动头部在此之前没有 hash。

### B. 一进入 chat 就创建 Context

启动立即产生一个 provisional Context，哪怕用户没有输入。

优点：从第一秒就有名称/hash，后续任何会话设置都有保存位置。

代价：误启动会产生大量空 Context；退出、命名和清理规则变复杂。

### C. 启动前强制命名

每个新任务必须先命名，再进入 chat。

优点：没有 provisional 名称，也没有匿名状态。

代价：每次启动多一道门槛；用户尚未描述任务时往往起不出好名字，也接近一个启动向导。

推荐 A。后续命名包再决定第一条任务后是否由模型建议名称以及怎样确认；本包只决定空启动是否落下一个 Context。

## 普通最近 Context 与异常 Context 必须分开

| 类型 | 含义 | 推荐启动行为 |
| --- | --- | --- |
| completed recent | 上次任务正常结束，仅可能与当前工作区相关 | 可提示 new/continue，默认 new；或按负责人选择完全不提示 |
| waiting-user recent | 上次明确等待用户信息，不存在未知副作用 | 应提示 continue，但仍不得静默恢复 |
| cancelled recent | 上次已按取消结果收口 | 作为普通历史，不强制 recovery |
| interrupted request | 模型回复没有正常收口 | recovery required |
| pending approval | 崩溃前等待批准，旧批准不能自动沿用 | recovery required，重新决定 |
| unknown operation | 工具可能已经产生副作用但结果未记录 | recovery required，默认只读检查 |
| damaged/incompatible | 无法证明可安全继续 | recovery/repair 或只读说明 |
| in use | 另一个 writer 正在使用 | lock conflict，不自动抢占 |

这里的关键原则是：普通 history 帮助用户找回工作；recovery 则阻止程序假装异常没有发生。两者不能共用一个“最近会话，是否继续？”提示。

## recovery 入口的基线与对照

### A. 先解释事实，再进入 recovery interaction（推荐）

- 裸启动只发现一个异常 Context：显示一段摘要，路由到该 Context 的 recovery interaction。
- 裸启动发现多个异常 Context：交给 `context-repl` 的 recovery-filtered selection view 先选目标，选定后再按 PJ-08 路由到该目标的 interaction。
- 显式 `--continue` 命中异常目标：直接路由到该目标的 recovery interaction。
- recovery interaction 默认动作是只读查看；任何未知工具都不自动重放。
- 用户退出 recovery interaction 不改变原证据。

优点：用户知道为什么没进入 chat，也不会误执行重复副作用；多个异常任务仍有明确入口。

代价：需要一套真正可操作、可测试的 recovery interaction，而不能只打印一行 `context corrupted`。它的 surface/view/state 容器仍服从 PJ-08。

### B. 所有异常都只报错退出

优点：实现表面最少。

代价：用户必须记住额外 repair 命令；错误发生后最需要帮助的时刻，产品反而没有接盘流程。

### 反例 C. 自动恢复到最后一条可读消息并继续（已排除）

优点：看起来最无缝。

它无法证明工具是否已经执行，可能重复删除、写入或命令；违反 unknown operation 不自动重放的已确认边界。因此这里只记录淘汰理由，不能作为 PJ-06 回复。

推荐 A。recovery 具体提供“标记 turn interrupted、确认 operation 已完成/未完成、映射新 Model、只读导出”等哪些动作，留给恢复决策包。

## 退出旅程

### 推荐的用户承诺

退出是一个有状态动作，不是直接杀掉进程，也不是把未完成工作伪装成完成：

| 退出时状态 | 推荐体验 |
| --- | --- |
| `new (not saved)` 且没有会话动作 | 立即退出，不留下空 Context |
| chat 空闲且状态已保存 | 安静、快速退出 |
| 正在编辑未提交用户草稿 | 按 F4-05 选择显示 `not saved`、已保存 session draft 或显式 save 状态；退出必须说明实际去向并允许返回，不能在本表暗定是否持久化 |
| 正在模型请求/流式生成 | 请求取消当前活动并显示正在收口；不把残片标成完成回复 |
| 正在等审批 | 默认拒绝/取消 pending approval，再退出；绝不因退出自动允许 |
| 工具正在运行 | 请求终止工具并等待有界收口；无法确认时显示 unknown 再退出 |
| 存在尚未开始的 queue/side | 清楚列出尚未执行项；默认不在退出过程中启动它们 |
| REPL 有未保存配置草稿 | 明确选择 save/discard/back；EOF 不静默保存 |
| recovery interaction | 默认不修改证据，直接退出可用；容器形态服从 PJ-08 |
| 窗口关闭/系统信号 | 尽可能执行同一收口；时间不足时由下次启动 recovery |

### 退出确认策略对照

1. **按状态优雅退出（推荐）**：空闲时不额外确认；有未提交草稿、活动副作用或未执行输入时才显示 ACTION。
2. **所有退出都确认**：一致但很打扰，用户每次正常完成后仍多一步。
3. **反例：任何退出都立即 kill**：最短，但无法兑现 Context 完整接盘和 unknown 副作用诚实报告，已排除且不能作为 PJ-10 回复。

推荐第 1 种。精确的 `.exit`/`.quit` 名称、Esc/Ctrl+C/EOF 层级和关闭 deadline 属于 CLI/AgentLoop 包。

## 真正需要项目负责人回答的十二组问题

以下每组只决定一个产品轴；所有选项都服从 D031 至 D038，不再把“首次页面、全屏应用、自动续接、OS sandbox、扩展运行时”等已经排除或已经确认的事项伪装成可选项。可以逐项回复，也可以复制本节末尾的完整推荐回复。没有明确回复的编号继续保持待决；不会因为本文写了“推荐”就自动写入 `DECISIONS.md`。

### PJ-01 裸启动的通用启动信息显示多少

配置、Model 和普通/异常 Context 的实际路由由 PJ-02 至 PJ-06 决定；writer 冲突只投影 CX-13 的结果（见非投票的 PJ-07）。本组不再决定哪些历史需要提示。

- A：不显示通用启动摘要；只有下游路由真的需要用户选择时才追加 `ACTION REQUIRED`。（推荐）
- B：进入目标表面前总是追加一行 `cwd/data-root/config/Model` 的脱敏状态摘要，再执行同一条下游路由。
- C：进入目标表面前总是追加一个多行启动检查块，列出本地配置、Context 扫描和 writer 状态，但不形成首页或额外选择。

推荐 A。正常路径最短，真正的风险/歧义仍由对应路由主动显示；B/C 提供更强可见性，但不会改变 PJ-04 的 ordinary-recent 策略或静默续接旧 Context。

关联：`PROD-01`、`PROD-12`、`TUI-18`、`AQ-011`、`AQ-215`。

### PJ-02 缺失/损坏配置时还能使用哪些入口

- A：正常 Agent 阻断；`help`/`version`、bootstrap `model-repl`/`config-repl` 和 self-test 第一阶段仍可用。（推荐）
- B：正常 Agent 阻断；`help`/`version`、bootstrap `model-repl` 和 self-test 第一阶段可用；`config-repl` 只有在 INI 至少可解析时才开放。
- C：正常 Agent 阻断；只保留 `help`/`version` 与 bootstrap `model-repl`；self-test 第一阶段和 `config-repl` 都要求 INI 至少可解析。

推荐 A。它服从“配置载入包含配置检查，坏配置不能启动 Agent”，同时保留人工修复路径。三项都不提供首次页面、不自动生成/重置配置；bootstrap 入口不得打开 Context、调用模型或执行工具。self-test 第二阶段仍需用户明确同意，第三阶段仍只使用第二阶段确认合格且被用户选中的 LLM。

关联：`PROD-14`、`CFG-21`、`DIAG-05`、`AQ-012`、`AQ-013`、`AQ-201`、`AQ-217`。

### PJ-03 没有可用 Model 与暂时离线的区别

- A：没有可用 Model 定义时阻断 chat 并给出 `--model-repl`；已有有效定义时启动不联网，允许进入，第一次显式采样才报告网络错误。（推荐）
- B：没有可用 Model 时仍可进入本地 chat composer、查看帮助和 Context，但采样入口明确 disabled；已有定义时同样不做启动联网。
- C：没有可用 Model 时阻断 chat；已有有效定义时，在第一次采样前要求用户显式选择“直接尝试”或“先做连接检查”，但启动阶段本身仍不隐式联网。

推荐 A。它把确定的配置错误与变化中的网络状态分开，也不把 `CheckModelOnStart` 一类隐式联网重新带回启动路径。

关联：`PROD-07`、`PROD-14`、`CFG-09`、`NET-12`、`TUI-18`、`AQ-081`、`AQ-217`、`AQ-246`。

### PJ-04 普通最近 Context 是否在裸启动提示

- A：同工作区存在任何健康 recent（completed、waiting-user 或已收口 cancelled）时显示一次短选择，默认新建；recovery-required 状态强制 recovery。（推荐）
- B：健康 recent 中只提示 clean waiting-user/unfinished；completed/cancelled 静默留在历史；recovery-required 状态仍强制 recovery。
- C：所有健康 recent 都不在裸启动提示；只有 unknown operation、damaged/incompatible、pending approval、interrupted request 等 recovery-required 状态强制 recovery。

推荐 A。它让用户在不进入任务中心的前提下发现可继续历史，且默认动作仍是新建，不会静默接错任务。B 只保留真正等待回复的健康任务提示，C 对所有健康历史保持安静。三项都不静默继续旧 Context；recovery-required 使用上表固定分类，不把普通 waiting-user 偷换成异常。

关联：`PROD-12`、`INDEX-07`、`AQ-215`、`AQ-230`。

### PJ-05 空 Context 何时真正产生

- A：进入 `new (not saved)`；第一项需要保存的会话动作到来时才建立 Context，直接退出不留空任务。（推荐）
- B：进入 chat 立即建立 provisional Context。
- C：先强制命名，再进入 chat。

推荐 A。代价是第一项保存动作前没有 hash，但 Context 清单更干净、含义更真实。

关联：`CTX-18`、`INDEX-06`、`AQ-092`、`AQ-216`、`AQ-313`。

### PJ-12 新 Context 第一个名称怎样产生

PJ-05 只决定何时创建 XML，不决定 basename。任何方案都先保护用户已经明确输入或后来手工改过的名称；自动建议绝不能覆盖它，也不能用碰撞覆盖现有 XML。

- A：第一次需要持久化时，从首条已提交 main 用户文本做版本化、本地、确定性的安全名称建议；非法/空结果使用本地时间+计数 fallback，碰撞追加短序号并 no-replace，不发额外 Model 请求。（推荐）
- B：先使用碰撞安全的 provisional 名；第一个正常完成且已持久化的 main turn 后，每个 Context 终身最多发起一次有界、无工具 `context-name` logical request，复用该 turn 的 Model/endpoint snapshot并进入同一 Model scheduler，使用独立 lifecycle cap且只计 Context/runtime。新 main 到达即取消尚未完成的命名请求且永不重排，迟到结果不可采用；成功建议仍需用户确认 rename，任何失败/离线/取消都保留 provisional 且不阻断任务。
- C：不自动建议；若 PJ-05 尚未取得用户名称，第一次需要持久化时先要求用户输入合法 basename，确认后才建立 Context。

推荐 A。它没有额外 Token/隐私外发，也能让浏览器尽早出现可读名称；B 的建议质量可能更好，但新增 purpose、费用和失败状态；C 最明确，却会在第一条消息提交后多一次阻塞。旧 `AutoNameOnExit` 在 A/B/C 三条路线中都删除，不新增自动命名偏好字段；是否发起建议完全由本题所选路线决定。用户名称、非法字符映射、Unicode 保真和 collision suffix 都进入 golden vectors。

关联：`INDEX-06`、`AQ-216`、`AQ-259`、`CFG-13`、`CTX-18`。

### PJ-06 recovery 的入口策略

- A：先显示真实异常；唯一目标路由到 recovery interaction，多个目标交给 `context-repl` 选择后再路由；默认只检查，不重放副作用。（推荐）
- B：显示异常、已保存事实和下一步后退出；用户显式运行 recovery 入口或 `context-repl` 后才路由到 interaction。
- C：所有异常都先路由到只读 recovery interaction；用户确认修复/继续计划后才取得 writer，任何 unknown operation 都不自动重放。

推荐 A。它用最短路径处理唯一候选，同时在歧义时复用 Context 选择交互；三项只决定“何时路由”，recovery interaction 落在独立 surface、context-repl view 还是 chat state 完全服从 PJ-08。三项都保留 canonical fact，也都禁止自动重放未知副作用。

关联：`PROD-12`、`CTX-17`、`CTX-27`、`DIAG-07`、`AQ-030`、`AQ-175`、`AQ-230`、`AQ-236`。

## PJ-07 writer/锁冲突旅程投影（不是负责人投票）

第二进程能否只读打开、完全拒绝，或请求活动 writer 协作交接，只由 CX-13 选择。本包不能再用另一套 retry/exit/wait A/B/C 覆盖它。

产品旅程必须把 CX-13 的结果投影为同一张 typed busy 页面：显示规范 Context 和可证明的 owner/busy 信息，绝不按锁年龄 force unlock；CX-13 A 提供只读查看与重新竞争，B 只显示 busy 元数据和退出/刷新，C 还显示可取消 handoff 状态，失败退回 A。`context-repl` 只能提供所选策略允许的动作。

关联：`CONC-03`、`CTX-26`、`INDEX-14`、`AQ-174`、`AQ-226`、CX-13。

### PJ-08 v0.1 有哪些正式交互表面

本组真正决定 surface 集合，而不是先宣布“已有七个”再只问 help 排版。D-031 已确认 model-repl 和三阶段 self-test，项目负责人也已要求独立的 config/context 管理交互；因此 chat、model-repl、config-repl、context-repl、self-test 和 help 是六个有依据的基础表面，本组的真正剩余轴是 recovery 成为第七个专用表面，还是复用已有表面内的受限状态。无论选哪项，顶层 help 都必须列出全部规范入口、用途与可用前提，相关错误都必须给出可执行入口。

- A：七个独立表面：chat、model-repl、config-repl、context-repl、self-test、help、recovery；recovery 是只有异常目标才能路由进入的专用表面，不是首页。（推荐）
- B：六个独立表面；recovery 是 context-repl 内的受限视图，启动异常直接路由到该视图，多目标选择与日常 Context 管理共用面包屑/返回语义。
- C：六个独立表面；recovery 是 chat 的受限只读状态，只接受 inspect/map/resolve/exit 动作；多目标时仍先交给 context-repl 选定目标，选定后返回该 chat recovery 状态。

推荐 A。它让高风险恢复与日常浏览有清楚生命周期；B 最复用 Context 管理，C 最接近主会话但需要更明确的受限状态。三项都保留 D-031 确认的 model-repl/self-test 和项目负责人要求的 config/context 管理，都是简单逐行交互，不引入首页、任务中心、permission-repl 或 prompt-repl；ContextPrompt 仍由 `.prompt`/Context 管理。

关联：`CLI-01`、`CLI-08`、`TUI-26`、`AQ-011`、`AQ-014`、`AQ-015`、`AQ-076`。

### PJ-13 继续 Context 时 `AutoJumpToDir` 怎样影响 workspace

本组是“显式 continue/浏览器已选定一个旧 Context 之后”workspace open/resume 的唯一 owner。F4-14 先产生 initial invocation/new-Context boundary，Resolver 仍从 D-026 规定的传入目录起步；目标 Context 选定后，本组才决定是否切到 recorded workspace。若 recorded workspace 越出 initial boundary、是上级 Git root，或文件系统 identity 不同，必须显示精确 `initial boundary -> recorded workspace`、Git/指令/工具范围变化，并按本组选项取得用户确认；不能把 Context 恢复伪装成 F4-14 的静默 Git-root 提升。任何跳转都必须先证明目录存在、可进入且与 Context mapping 一致；失败就进入 mapping/recovery interaction，不猜同名目录。

- A：保留 boolean `AutoJumpToDir`。`true` 在同一已证明 identity/boundary 内可在显示目标后跳转；越出 initial boundary、命中上级 Git root 或 identity 不同时必须显示差异并确认 `jump / cancel`。`false` 总是显示 `jump / keep and rebind / cancel`，用户选定前只读。（推荐）
- B：保留 boolean。`true` 同 A，包括跨 boundary/identity 必须确认；`false` 永远保留 initial boundary，必须通过显式 rebind 事件建立新 workspace 后才恢复可写，不提供当次 jump 快捷选项。
- C：用 typed `ResumeDirectory=jump|ask|keep` 取代 boolean；`jump` 只在同一已证明 identity/boundary 内可直接跳转，跨 boundary/identity 仍必须显示差异并确认；`ask` 每次显示选择，`keep` 必须显式 rebind 后才恢复可写。

推荐 A。它保留已有配置名称和最简单的 true/false 心智模型，同时不让 `false` 被误解为“无提示地把旧对话绑到新目录”。三项都要在 XML 记录 old/new workspace、原因和 mapping/rebind 事件，且使旧 approval 失效。

关联：D-026、`PROD-05`、`CTX-13`、`CTX-27`、`CLI-00`、`INDEX-05`、AQ-212、AQ-236、F4-12、F4-14。

### PJ-09 从 chat 进入管理表面的时机与返回位置

- A：只有 chat 空闲时打开管理表面；退出后返回同一 chat/session 和原位置，未保存管理草稿必须 save/discard/back。（推荐）
- B：Agent 忙时可以打开只读管理视图；修改只保留为进程内 pending draft，只能在当前 turn 完成后再次确认并生效，不能改变活动 turn，进程关闭则明确丢弃。
- C：chat 中不能打开管理表面，只能另起进程。

推荐 A。它避免一个正在执行的 turn 被配置删除或 Context 切换，同时保持使用方便。哪些设置在下一 turn 生效由其他包决定。

关联：`CFG-11`、`CFG-19`、`TUI-26`、`AQ-031`、`AQ-079`、`AQ-108`。

### PJ-10 退出策略

- A：按状态优雅退出；空闲不确认，有草稿/活动/unknown/未执行输入才提示并收口。（推荐）
- B：每次退出都确认。
- C：退出从不确认；立即把退出意图交给统一 close 状态机，未发送 draft 明确丢弃、queue 不执行，最终 completed/interrupted/unknown 由 ED-05/Runtime 真实结果决定。

推荐 A。它只在存在可能丢失或未收口内容时打断。三项只决定“何时确认”，不拥有 Ctrl+C/EOF/broken-pipe、deadline 或进程取消机制；退出时都绝不启动 queue、自动批准动作或把 interrupted 投影成 completed。

关联：`ARCH-02`、`PLAT-10`、`TUI-06`、`AQ-098`、`AQ-229`、`AQ-230`。

### PJ-11 普通对话是否需要独立 plan state

D-038 只确认封闭单 Agent，排除 MCP、plugins、hooks、skills runtime、自定义第三方工具协议和子 Agent；D-025 另行排除 Context 分支。Web 目前只是 deferred 候选，媒体、远程控制和多根 workspace 的精确范围仍由各自 checklist owner 决定，不能伪称是 D-038 已确认事实。自动更新也不归 plan state：在 REL-11 明确决定前，现行“本地启动不隐式联网”基线意味着 v0.1 不得暗中检查或安装更新。本组只决定 plan state。

- A：不建立独立 plan state；模型可以在普通回复中说明计划，随后按同一 AgentLoop/权限/工具契约执行。（推荐）
- B：提供显式 `.plan <text>`：创建 `main phase=plan` turn，只能使用仍受 Permission/SensitiveRead 约束的 direct list/read/search，不能使用 shell、direct network、write/rename/delete；成功产生可恢复 PlanArtifact。用户只有执行 `.execute <plan-id>` 才创建新的普通 execute turn，所有工具仍需重新提议/审批，plan 绝不是授权。
- C：每个新 main 先以 B 的 plan phase 运行；纯只读回答可以直接完成，任何会产生文件/命令/网络副作用的路线必须先 durable PlanArtifact，再由 `.execute <plan-id>` 创建 execute turn。Runtime 不靠自然语言分类在请求前猜任务是否会修改。

推荐 A。它保持单一状态机和简单体验，又不限制模型先思考后行动。B/C 的不可分割后果是：PlanArtifact 绑定 goal、model-view、workspace、config、Model、Permission、tool-schema identity/digest，任一变化即 stale；XML 保存创建/取消/失效/execute 引用，恢复后可查看但不能把旧计划当审批；`.plan/.execute` 作为 TU-18 条件命令，AgentLoop 负责 plan/execute/cancel 状态。只有确实需要强制分段体验时才值得承担这些成本。

关联：`PROD-11`、`LOOP-18`、`AQ-346`。

确认后 owner artifact：`00-product-and-compatibility.md` 中普通 turn 与可选 plan state 的产品契约。范围表必须分别标注 confirmed-excluded、deferred 和 open，不得把 D-038 扩写到未确认能力。

### 完整推荐回复模板

```text
PJ-01 A
PJ-02 A
PJ-03 A
PJ-04 A
PJ-05 A
PJ-12 A
PJ-06 A
PJ-08 A
PJ-13 A
PJ-09 A
PJ-10 A
PJ-11 A
```

## 本包确认后的归档产物

项目负责人回复后，应当只把明确选择归档到：

- `DECISIONS.md`：产品级启动/表面/退出决定。
- `00-product-and-compatibility.md`：完整主旅程、启动路由、plan-state 终态，以及区分 confirmed-excluded/deferred/open 的能力状态表。
- `13-cli.md`：各入口怎样选择表面，但不在这里重复业务规则。
- `14-tui.md`：ACTION 块与表面投影要求。
- `22-application-runtime-and-concurrency.md`：启动/关闭必须兑现上述产品结果。

尚未回复的条目继续保留待决。后续包可以引用本包的已确认结果，但不得把推荐文字当成默认授权。

## 完成标准

本包完成不是“文档里出现了 startup 一词”，而是下面的场景都只有一个可解释去向：

1. 无配置运行 `yaca`。
2. 配置损坏但用户要运行 self-test/config-repl。
3. 配置有效但没有 Model。
4. Model 已配置但机器暂时离线。
5. 新目录第一次进入并立即退出。
6. 同工作区存在普通最近 Context。
7. 同工作区存在一个或多个异常 Context。
8. `--continue` 命中健康、损坏、依赖缺失或被占用 Context。
9. chat 空闲、正在请求、正在审批或正在运行工具时退出。
10. REPL 有未保存草稿时返回或 EOF。

这些场景经负责人确认后，后续 AgentLoop、存储和 TUI 设计才有稳定的上游产品契约。
