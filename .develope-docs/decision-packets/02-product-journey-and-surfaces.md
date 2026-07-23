# 决策包 02：产品旅程、启动路由与交互表面

更新日期：2026-07-22

状态：十九个正式组已全部收到项目负责人回复；`PJ-12` 的手工名称与周期自动命名优先级补缝也已确认。以下正式问题正文继续作为 `decision-inventory-v9` 的冻结证据，不因回复原地改写。

## 本轮现行投影

本节把项目负责人写在旧候选区中的批注和随后逐项回复归并为一份简洁投影。原话已经保存到 `DISCUSSION-BATCH-02.md` 至 `DISCUSSION-BATCH-04.md`；这里不再混放临时批注。D-040 至 D-048 和实时登记表拥有现行归档，owner 规格与技术证明仍按传播状态继续收口。

### 产品形态与启动原则

- yaca 是 English/ASCII 程序界面、单 Agent、terminal-only 的 Coding Agent；不提供首页、全屏 dashboard 或鼠标交互。
- 裸 `yaca` 与 `yaca .` 等价。配置有效时，它不扫描 Context Catalog、不提示 recent 或所谓“正常/异常结束”，而是直接进入一个新的、尚未保存的 chat。旧 Context 只能由 `.context`、`continue` semantic action 或 `context-repl` 显式访问。
- 正常启动头没有总开关。产品 Slogan、version、workspace、data root、配置状态、Context、实时 hash、Model、Permission、DoubleCheck 和 `.status` 提示分别有独立显示开关；每个启用字段都在新行行首独立输出，全部关闭就不显示例行启动头。固定产品 Slogan 是 `yaca: Yet Another Coding Agent.`；强制错误、警告和 ACTION 不受这些显示开关隐藏。
- chat 的输入提示采用简洁 ASCII `>>` 方向；其余 surface/focus 的精确提示符仍由 TUI owner 统一收口。

### 配置、Model 与启动前 self-test

- 缺失或损坏主配置时，正常 Agent 一律阻断；help/version、bootstrap `model-repl`、`config-repl`、self-test Stage 1 和不调用模型的 `context-repl` 仍可用。
- `context-repl` 可以管理 Context 的本地生命周期与目录树，不因 Model 缺失而失效；活动锁、损坏对象和不兼容对象仍服从 Context 自身的 fail-closed 规则。
- 没有有效可用 Model 属于 Agent 启动配置错误。已有有效 Model 时，默认启动不探测网络；机器离线只在第一次显式模型请求时形成网络错误。
- 配置新增显式的启动前 self-test 选择。最简 typed 形态应表达 `off|stage1|stage2|stage3`：默认 `off`；选择某阶段就严格执行 `1 -> 2 -> 3`，前阶段未满足不得进入后阶段。Stage 1 除配置/schema 外，还检查 Context 镜像父目录能否解码、派生 workspace 是否存在/可进入，以及 Catalog/Resolver/hash 扫描是否 incomplete、命中 hard cap 或超出旧机性能预算。Stage 2/3 仍要显示联网、endpoint、最坏请求/Token/费用并取得对应 consent；取消、失败或未完成要求的阶段时不进入 chat。Stage 3 可以提示 Model/Permission 名称、说明、Prompt 与真实配置/能力明显错配或疑似拼写错误，但只作 advisory，不能改配置或改写 Stage 1/2 的确定性结果。
- 顶层 CLI 必须能完整表达 self-test 的阶段上限、合法排除和 Model/check 范围。任意参数组合都不能跳过依赖阶段；最终 flag/subcommand 拼写仍由 CLI owner 决定。

### Context 创建、命名与固定工作目录

新的 chat 在第一条 main 用户消息之前只持有有界内存草稿：

1. `.help`、`.status` 或立即退出不创建 XML，也没有可连接的 Context hash。
2. `.model`、`.prompt`、`.cautious` 等新 Context 设置可以先进入未保存内存草稿；若用户未发送第一条 main 消息便退出，它们一起丢弃。
3. 第一条 main 用户消息提交时，先产生碰撞安全的 provisional 名称，以 no-replace 建立 XML，并 durable 保存该消息及有效会话草稿；只有成功后才能开始 Model 请求或任何副作用。
4. 初始 ASCII 名称采用 `Untitled Conversation [XXXX]`，其中 `XXXX` 是四位大写十六进制随机后缀。碰撞时重新生成，绝不覆盖现有 XML；这个短后缀只用于可读 fallback，不是永久 ContextId，也不代替由逻辑路径实时计算的十六位 hash。
5. 自动命名不再绑定退出。它是可关闭的后台 logical request，全局 `AutoNameEveryMainTurns` 默认 10、0 关闭；只计已经 durable 完整收口的 main turn，side/review/self-test/失败或取消 turn 不计。失败、超时、取消或退出都保留当前名称且不阻断主任务。成功 rename 必须同步更新逻辑路径和实时 hash。它在单一事件泵中有界调度，“后台”不授权第二套并发领域状态。
6. Context XML metadata 保存 `AutoRenameDisabled`。手工 rename 默认在同一管理事务中发布 canonical `Name`、`UpdatedAt` 与 `AutoRenameDisabled=true`，`CreatedAt` 不变；自动命名自身不设置 marker。context-repl 可以添加或取消标记，取消只从新的调度基线恢复全局间隔，不立即命名或追补禁用期间的请求；标记变为 `true` 会取消/逻辑失效在途命名，迟到结果不得采用。

Context 列表/浏览器的显示顺序由 `[Context] ListSortBy=created|updated|name` 与 `ListSortDirection=ascending|descending` 控制，默认 `updated + descending`。created/updated 读取 XML canonical metadata，不使用复制或原子替换会改变的文件 mtime/ctime；相同键始终按 canonical `LogicalPath` 升序打破平局，绝不随主排序方向反转。该偏好不使裸启动扫描 Catalog，也不改变 Resolver 顺序或 hash。

每个 Context 恰好绑定一个固定 workspace root：

- 当前绑定不保存为 XML 内的 `current workdir` 字段；显式选中旧 Context 后，yaca 从该 XML 位于 `__yaca__/CONTEXT/` 下的规范镜像父目录解码唯一 root。
- 不提供 `AutoJumpToDir`、`ResumeDirectory` 或普通 `jump/keep` 路线；invocation directory 不能临时覆盖、静默替换或另存为第二个绑定。
- 目录缺失、不可进入或文件系统 identity 不匹配时，停止打开并进入 `context-repl` 的 self-fix 流程；不能留在调用目录继续运行，也不能猜同名路径。
- 跨机接盘需要改变绑定时，context-repl 在同一 no-replace、可恢复管理事务中追加 rebind 历史事件、原子推进 `UpdatedAt` 并把完整 XML 安全发布到新 root 对应的镜像目录；`CreatedAt` 不变。成功后新父目录成为唯一绑定，逻辑路径和实时 hash 随之改变，旧 hash 失效；失败/inspect 不推进时间。
- XML 仍可保存工具实际 cwd、历史路径和 Git/digest 等会话证据，但这些不是当前绑定的第二事实源。一次性获准访问外部路径也不会建立第二 root。
- `F4-14` 仍独立决定新 Context 的初始唯一 root 怎样从 invocation directory 和可能的 Git root 得出。

### REPL、self-fix、锁与显式恢复

- `model-repl`、`config-repl` 和 `context-repl` 是独立顶层 CLI action，不从 chat 打开并返回。chat 中的 `.model` 只切换已经存在、enabled 且有效的 Model；无参数打开有界 picker，`.model <selector>` 直接选择，两者提交同一个 typed action。补全/候选提示只读当前 Model registry，旧/窄终端可退化为逐行候选；`.model` 不添加、编辑或测试连接。
- 每个 TUI 领域动作必须由同一 registry 产生 CLI 等价投影；renderer 的滚动/分页不是独立领域 API，非 TTY 也不会因此绕过确认或输入所有权。
- `.context` 是显式选择/切换 Context 的会话动作，不使裸启动扫描历史，也不等于打开完整 `context-repl`。
- 不建立独立 recovery surface。每个 REPL 提供本领域的 `self-fix-program` 菜单：Model 问题由 model-repl 处理，配置问题由 config-repl 处理，Context/XML/workspace mapping 问题由 context-repl 处理。self-test 负责诊断，不静默修复。
- 显式打开损坏、不兼容或具有 unknown operation 的 Context 时，程序显示实际问题、已保存范围和对应 self-fix 入口后退出；不自动重放工具，也不按一个笼统“异常结束”标签猜测恢复动作。
- 同一 Context 已有活动 writer 时采用 `CX-13 B`：第二进程拒绝打开正文，context-repl 只显示名称、路径、busy 状态和可证明的 PID。锁释放前，其他进程不能 rename/rebind/delete/archive/repair、修改 Prompt/metadata 或切换 `AutoRenameDisabled`；活动 chat 的 writer 仍可使用自己的会话 action。不能只凭锁龄 force unlock；无法可靠证明 owner 时显示 unknown。
- Model/config INI 使用独立的短期提交锁，可以在 chat 运行时由 model/config REPL 修改。每个新顶层 turn 前读取完整 INI；digest 未变复用旧 generation，变化则整份验证并自动发布，新 turn 使用新配置。活动 turn 不热换；观察到半写/损坏配置会阻止新 turn并进入修复。

### 退出、Permission 与已排除产品面

- chat 不建立独立 plan state，不注册 `.plan/.execute`，也不产生 PlanArtifact；模型在统一 AgentLoop 和 Permission 契约中规划与执行。
- Permission 名称只是名称，真实行为由配置矩阵决定。发行模板继续包含 `Std` 和 `Readonly`；Permission 可以拥有自己的有界 Prompt/说明等配置，但这些文本不能代替 Runtime 权限字段或扩大能力。
- `DoubleCheck可以设定目标` 已作为 AgentLoop 后续设计约束保存；“目标”究竟指 reviewer Model、复核范围还是交给 reviewer 的任务目标尚未被本包猜成字段，待对应正式组用窄选项确认。
- 退出不等待自动命名，也不增加通用确认。Runtime 立即进入有界 close：取消模型与后台命名、丢弃未提交草稿和未开始 queue、拒绝 pending approval、尽力终止工具，并把可证明结果如实收口为 completed/interrupted/unknown。这里的“直接退出”不授权跳过必要的 XML 提交和终端恢复。
- v0.1 明确不提供 Web、图像输入、音频输入、transcription、TTS/语音播报和公共 remote/headless IPC/RPC；相应配置、help、schema、Runtime loader、self-test、依赖与 zip 内容都不得留下空壳。
- 用户仍可让模型通过已经获准的普通文件/direct tool 或 raw shell 读取用户自行准备的目录/文件；这不产生专用 clipboard、image、audio 或 remote 能力。

### 旧系统与 Unicode 边界

程序自带文案、命令、配置键和生成的 provisional basename 使用 English/ASCII，以降低旧控制台显示风险；这不降低真实用户数据要求。Windows XP 至 11 的路径、用户手工 Context 名、消息和 XML 必须保真 Unicode/UTF-8，Windows 文件系统端口必须使用宽字符 API。终端不能显示某字符时只能改变显示投影，不能改变真实路径、文件操作或 hash 输入。

## 后续批注的现行结论

1. `PJ-18=A`：一个 Context 恰好一个由 XML 镜像父目录决定的 workspace root；没有附加 root、root alias 或 root list。
2. `PJ-12` 补缝：手工 rename 默认设置每 Context 的 `AutoRenameDisabled=true`；context-repl 可以取消，且取消不立即命名。全局周期间隔与该标记独立。
3. `PJ-01`：启动头删除 master，只保留逐字段 bool。
4. `TU-32=A`：chat 使用平坦 `.model` root；picker 与直接 selector 等价。
5. `F4-01=custom`：每个新顶层 turn 自动观察完整 INI，变化后整份验证并自动激活；不在 turn 中途热换。
6. Context Catalog 的列表默认更新时间倒序；所有 TUI 领域动作必须有 CLI 等价投影。

## 冻结问题证据说明

下面十九个正式 H3 及其完整推荐回复模板逐字保留，用于维持 `decision-inventory-v9` 的结构与语义校验。它们记录提问时的候选空间，不再代表“十九组都无人回复”；现行回复以本节、`DISCUSSION-BATCH-02.md`、后续 `DECISIONS.md` 和 owner 规格为准。

## 真正需要项目负责人回答的十九组问题

以下每组只决定一个产品轴；所有选项都服从 D031 至 D038，不再把“首次页面、全屏应用、自动续接、OS sandbox、扩展运行时”等已经排除或已经确认的事项伪装成可选项。可以逐项回复，也可以复制本节末尾的完整推荐回复。没有明确回复的编号继续保持待决；不会因为本文写了“推荐”就自动写入 `DECISIONS.md`。

### PJ-01 裸启动的通用启动信息显示多少

配置、Model 和普通/异常 Context 的实际路由由 PJ-02 至 PJ-06 决定；writer 冲突只投影 CX-13 的结果（见非投票的 PJ-07）。本组不再决定哪些历史需要提示。

- A：不显示通用启动摘要；只有下游路由真的需要用户选择时才追加 action-required semantic block，其字面 label 只由 TU-20 投影。（推荐）
- B：进入目标表面前总是追加一行 `cwd/data-root/config/Model` 的脱敏状态摘要，再执行同一条下游路由。
- C：进入目标表面前总是追加一个多行启动检查块，列出本地配置、Context 扫描和 writer 状态，但不形成首页或额外选择。

推荐 A。正常路径最短，真正的风险/歧义仍由对应路由主动显示；B/C 提供更强可见性，但不会改变 PJ-04 的 ordinary-recent 策略或静默续接旧 Context。

关联：`PROD-01`、`PROD-12`、`TUI-18`、`AQ-011`、`AQ-215`、TU-20。

### PJ-02 缺失/损坏配置时还能使用哪些入口

- A：正常 Agent 阻断；`help`/`version`、bootstrap `model-repl`/`config-repl` 和 self-test 第一阶段仍可用。（推荐）
- B：正常 Agent 阻断；`help`/`version`、bootstrap `model-repl` 和 self-test 第一阶段可用；`config-repl` 只有在 INI 至少可解析时才开放。
- C：正常 Agent 阻断；只保留 `help`/`version` 与 bootstrap `model-repl`；self-test 第一阶段和 `config-repl` 都要求 INI 至少可解析。

推荐 A。它服从“配置载入包含配置检查，坏配置不能启动 Agent”，同时保留人工修复路径。三项都不提供首次页面、不自动生成/重置配置；bootstrap 入口不得打开 Context、调用模型或执行工具。self-test 第二阶段仍需用户明确同意，第三阶段仍只使用第二阶段确认合格且被用户选中的 LLM。

关联：`PROD-14`、`CFG-21`、`DIAG-05`、`AQ-012`、`AQ-013`、`AQ-201`、`AQ-217`。

### PJ-03 没有可用 Model 与暂时离线的区别

- A：没有可用 Model 定义时阻断 chat 并给出 `model-repl` action；已有有效定义时启动不联网，允许进入，第一次显式采样才报告网络错误。（推荐）
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

通俗解释：`yaca .` 可以先让用户看到 chat，但“看到输入框”不一定等于磁盘上已经有一个可继续的任务。过早建 XML 会让 Context 浏览器堆满从未发送过消息的空任务；过晚建又可能在已经请求 Model、保存 Prompt/会话参数或执行工具后没有可恢复事实。PJ-12 独占 basename 怎样产生，本组只决定从内存态跨到真实 XML/writer 的时点。

- A：进入 `new (not saved)`，只持有有界内存候选；help/status/直接退出不创建 XML。第一项必须成为会话事实的动作被接受时，先按 PJ-12 取得名称、以 no-replace 建立 Context 并 durable 保存该动作，成功后才允许对应 Model 请求或副作用；创建失败则保留可见草稿并 fail-closed。F4-05 若最终允许保存未提交 draft，该保存动作也属于“必须成为事实”。（推荐）
- B：进入 chat 前立即用 PJ-12 路线建立 provisional Context 和 writer，即使用户没有输入便退出也保留一个可浏览/可删除的空任务；启动失败时不进入 composer。
- C：在显示可提交的 chat composer 前先要求用户确认合法名称，成功建立 XML 后才进入 chat；取消命名等于取消新建，不留下 provisional 文件。

推荐 A。它让 Context 清单只出现真实会话，同时保证任何外发请求或副作用之前已经有恢复锚点；代价是第一项 durable 动作前没有名称、hash、writer 或可供 `continue` action 选择的目标，UI 必须明确显示 `new (not saved)`。B 最容易立即恢复空页面，但会制造空任务和清理语义；C 的身份最明确，却把每次临时提问都多加一道命名阻塞。三项都禁止“先执行，稍后再补 XML”，也不能让 Context 创建失败后继续运行 Agent。

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

本组只决定普通对话是否增加一个独立 plan state。D-038 的封闭单 Agent、D-025 的无 Context 分支，以及 Web、图像/音频输入、独立 transcription、TTS、remote/headless、多根 workspace 和更新范围都不能从本题的答案推出；这些产品面分别由 PJ-14 至 PJ-20 的对应组决定，更新策略由发布包决定。

- A：不建立独立 plan state；模型可以在普通回复中说明计划，随后按同一 AgentLoop/权限/工具契约执行。（推荐）
- B：提供显式 `.plan <text>`：创建 `main phase=plan` turn，只能使用仍受 Permission 约束的 direct list/read/search；若 M05-56 B 启用 `SensitiveRead`，敏感候选读取还须叠加该能力。plan 不能使用 shell、direct network、write/rename/delete；成功产生可恢复 PlanArtifact。用户只有执行 `.execute <plan-id>` 才创建新的普通 execute turn，所有工具仍需重新提议/审批，plan 绝不是授权。
- C：每个新 main 先以 B 的 plan phase 运行；纯只读回答可以直接完成，任何会产生文件/命令/网络副作用的路线必须先 durable PlanArtifact，再由 `.execute <plan-id>` 创建 execute turn。Runtime 不靠自然语言分类在请求前猜任务是否会修改。

推荐 A。它保持单一状态机和简单体验，又不限制模型先思考后行动。B/C 的不可分割后果是：PlanArtifact 绑定 goal、model-view、workspace、config、Model、Permission、tool-schema identity/digest，任一变化即 stale；XML 保存创建/取消/失效/execute 引用，恢复后可查看但不能把旧计划当审批；`.plan/.execute` 作为 TU-32 条件命令，AgentLoop 负责 plan/execute/cancel 状态。只有确实需要强制分段体验时才值得承担这些成本。

关联：`LOOP-18`、`AQ-346`。

确认后 owner artifact：`00-product-and-compatibility.md` 中普通 turn 与可选 plan state 的产品契约，以及 AgentLoop 对应的 phase/PlanArtifact 状态表；本组不拥有产品非目标总表。

### PJ-14 Web 是否进入 v0.1

通俗场景：仓库里存在 Web 占位或核心内部已经有可供 TUI 调用的 application service，都不能说明用户已经能用浏览器安全地操作 yaca。一个真正的 Web 产品面会带来监听地址、浏览器兼容、认证、CSRF/origin、秘密显示、审批、断线重连和第二套端到端测试；“只在本机打开”也不会自动消除这些责任。

- A：v0.1 不发布、不启动 Web UI，也不监听为 Web 准备的端口；核心 terminal 版本达到正式发布证据后，只有项目负责人针对具体 use case 显式重开，才进入独立 Web 设计流。（推荐）
- B：v0.1 提供显式启动、loopback-only 的只读本地浏览页，只能查看经过脱敏的状态、历史与诊断；不能发送消息、回答审批、修改配置、切换/删除 Context 或触发工具。
- C：v0.1 提供与本机 TUI 领域动作等价的本地交互 Web UI；它可以发送消息和执行已注册管理动作，但所有权限、审批、Context writer 和 typed outcome 都复用同一核心契约。

推荐 A。它符合 terminal-first、旧 Windows/Linux 和“先把核心做完整”的目标，也避免占位代码反向变成发布承诺。B 有利于只读观察，但仍需要 HTTP、浏览器、安全与隐私证据；C 是完整第二前端，绝不能用一个能显示 transcript 的 demo 代替。

共同契约：内部 Lua application service、事件投影、测试 adapter 或未来可复用端口都不是公开 HTTP/API 兼容承诺。选择 A 时，配置、help、schema、Runtime、zip 和 self-test 中不得出现 Web loader、假命令或无消费者字段；选择 B/C 时，必须先冻结浏览器基线、绑定地址、认证/origin/CSRF、缓存与 secret redaction、事件流/backpressure、writer/approval 身份、断线恢复和目标平台测试。B/C 都只能消费 AgentLoop、Permission 与 Context 应用服务，不能复制业务循环；PJ-14 的本地 Web 选择不授予 LAN/remote 能力，后者只由 PJ-17 决定。

关联：`PROD-11`、`WEB-01` 至 `WEB-04`、`AQ-382`、`SAFE-09`、`TUI-26`、PJ-17。

### PJ-15 是否支持图像输入

通俗场景：用户可能想把截图交给 Coding Agent，但“Model 支持 vision”只是远端能力的一部分。yaca 还必须决定怎样选文件、限制解码炸弹、保存到单一 Context XML、在另一台机器接盘、切换到不支持图像的 Model，以及旧终端无法预览时怎样让用户确认实际发送了什么。

- A：v0.1 只接受文本、Prompt 和结构化工具事实，不提供图像附件、剪贴板图像、截图捕获或视觉 Model 输入。（推荐）
- B：允许用户从本地文件或 clipboard paste 显式建立 typed 静态图像附件，再交给声明支持 image/vision 的当前 Model；只接受冻结的格式、尺寸和字节上限，并在外发前显示来源与规范元数据。
- C：在 B 的基础上增加用户显式发起的本地 screenshot capture action；采集前显示目标/范围，采集后先形成未发送的静态附件并预览，再由用户决定是否加入 draft 或发送。它不是 Model 可调用 tool，不能因模型请求了图片就静默抓屏。

推荐 A。文本和 direct tools 已能完成完整 Coding Agent 闭环；排除图像可以保持 provider、XML、TUI 和旧平台依赖简单。B 能解决常见截图场景，但会让媒体 bytes 成为正式用户内容；C 还增加桌面采集、隐私与审批面。

共同契约：B/C 必须使用 typed Model capability，当前 Model 不支持时在请求前失败并给出可执行说明，绝不按 D-028 静默换 Model。file attachment 是所有支持平台的规范输入/后备；terminal/SSH 的普通文字 paste 不会变成图片。clipboard handler 只有平台 adapter 能证明真实 GUI clipboard image format/owner snapshot/大小限制时才显示，否则返回稳定 `unavailable`，不能让整个 B 失效，也不能偷偷启动系统 `xclip`/PowerShell 等外部工具。文件、可用的 clipboard image 和 C 的 capture result 都只是用户显式建立的静态 attachment source，进入同一校验/预览/持久化流水线；clipboard/capture bytes 不可绕过格式、大小或 durable 门。被接受的图像在首次外发前必须以有界 canonical bytes、source kind、media type、尺寸、大小和 digest 成为 durable Context 事实；长期只有 INI/XML，因此不能靠易失临时路径或永久 sidecar 假装“复制 XML 可接盘”。旧终端可以只显示 ASCII 元数据而不渲染图片，但必须允许用户确认目标与大小。必须冻结格式 allowlist、解码后像素/内存硬门、metadata 处理、clipboard owner race、导出/删除、Model 切换与不支持 provider 的结果；C 还必须冻结采集目标、逐次同意和平台能力失败。TS-02 的 Model tool registry 在 A/B/C 下都不增加 screenshot tool；C 只向 TU-32 的用户动作 registry 投影一个条件入口。选择 A 时这些配置、schema、命令、clipboard image handler 和媒体库全部不存在。

关联：`PROD-11`、`PROD-17`、`AQ-383`、M05-01、`MODEL-03`、`MODEL-04`、`MODEL-07`、`CTX-01`、`CTX-05`、`CTX-06`、`SAFE-09`、CX-02。

### PJ-16 音频输入支持到哪一层

通俗场景：把已有音频文件交给 Model 与实时访问麦克风是两个递进输入面；它们都不同于“单独转写成文字”和“把回复朗读出来”。本组只决定音频怎样进入 current Model request，独立 transcription 与 TTS 分别由 PJ-19/PJ-20 决定。

- A：v0.1 不提供音频附件或麦克风采集；相关 input 配置、help、schema、设备访问和 codec 组件全部不存在。（推荐）
- B：只允许用户显式导入有界音频文件；校验成功后先形成未发送的 canonical audio object，再由用户选择发送给声明支持 audio input 的当前 Model，或在 PJ-19 生效时发起独立 transcription；不访问麦克风。
- C：在 B 的基础上提供显式开始/停止的麦克风实时采集；录音期间持续显示状态和 hard limit，停止后先形成未发送、可预览的有界 canonical audio object，再由用户决定发送到 main Model、交给 PJ-19 的独立 transcription，或丢弃。

推荐 A。Coding Agent 的核心闭环不依赖音频输入。B 比实时采集窄，但仍把大体积媒体和 provider 专有协议带进 Context；C 还增加 XP/Linux 设备、codec、隐私指示与取消残片的完整测试面。

共同契约：B/C 的 ingestion 只建立本地 canonical audio object，不自动外发、不计一次 main 请求，也不自动激活 transcription 或 speech output。随后每个 main-send/transcribe 动作各自显示 purpose、Model/endpoint、费用与数据范围，并取得自己的 durable intent；不得自动换 Model/provider 或把未知费用隐藏在普通 main 请求中。任何外发音频都必须在请求前 durable 保存其有界 canonical 输入、格式、时长、大小、digest、来源和用户动作，使单 XML 能解释并接盘真实模型输入；超限时在采样前拒绝。麦克风永不因启动、恢复或模型文字自动激活；选择 C 时还需冻结设备丢失、录音指示、取消/崩溃残片、codec 随包来源与各目标系统实测。所有错误都有完整文本路径，选择 A 时不保留空 audio-input seam。

关联：`PROD-11`、`PROD-18`、`AQ-384`、M05-01、`MODEL-03`、`MODEL-04`、`MODEL-07`、`CTX-01`、`CTX-05`、`SAFE-09`、`SUPPLY-01`、PJ-19、PJ-20。

### PJ-17 是否提供 remote/headless 控制面

通俗场景：编辑器、本机另一个进程或远端客户端若能启动 turn、回答审批和接收事件，就会争夺输入所有权、Context writer 与取消目标。核心内部有 ApplicationCoordinator，或测试能直接喂事件，都不代表项目已经发布一个稳定、可认证、可重连的 app-server 协议。

- A：v0.1 不发布通用 headless IPC/RPC，也不为第三方 controller 监听控制端口；若 PJ-14 C 同时被选中，只允许那个 Web 前端自身的 origin-bound browser-private loopback transport，不能被编辑器/脚本当作公共 API。（推荐）
- B：提供显式启动、默认关闭的本机 loopback 或 OS-local IPC headless API；控制器必须呈现审批与错误，所有动作进入同一领域状态机，不允许无人值守默认批准。
- C：提供 LAN/remote control；除 B 的契约外，还必须同时支持远端认证、TLS、会话接管、重放保护、远程审批和网络断线恢复。

推荐 A。它最符合简单本地 Agent 与旧平台边界。B 有利于编辑器集成，但立即冻结公共协议、兼容版本和无 TTY 审批模型；C 是独立网络产品，不能夹带在“headless”这个词里。

共同契约：private application service、Lua port、测试 fake、非 TTY 只读机器输出，以及用户通过 SSH 获得一个普通终端后运行 TUI，都不自动构成公共 remote/headless control surface。B/C 必须定义版本化 command/event schema、认证与 peer identity、Context/turn/expected-target 身份、单 writer/controller 规则、输入与审批所有权、取消、断线重连/replay window、backpressure、secret redaction、durable audit 和未知副作用；历史 XML approval 不能给新客户端授权。不得后台启动 daemon/listener。PJ-17 不自动开启 Web，PJ-14 的本地 Web 也不自动开放远程；两者若同时选择，仍共用一套核心状态而不是互相桥接出第二事实源。

PJ-14/PJ-17 组合必须按下表解释，不能用一个选择暗改另一个：

| PJ-14 | PJ-17 A | PJ-17 B | PJ-17 C |
| --- | --- | --- | --- |
| A | 无 Web、无公共 controller | 无 Web；显式本机 headless API | 无 Web；显式 LAN/remote API |
| B | 只读本机 Web；没有控制 API | 只读 Web + 独立本机 headless API | 只读本机 Web + 独立 remote API |
| C | 交互 Web 只用 frontend-private、origin-bound loopback transport；不承诺第三方 API | 交互 Web + 明确发布的本机 headless API，可共享应用服务但身份/客户端规则分别可见 | 交互本机 Web + 明确发布的 remote API；只有选定 browser transport 时才应用 origin/CSRF，其他 transport 使用自己的 channel binding/replay 契约 |

因此 PJ-14 C + PJ-17 A 是合法组合，不等于“既允许又禁止同一端口”：前者只授权随包浏览器前端的专用本机 transport，后者仍拒绝任何通用 controller contract。若实现无法证明两者隔离，必须把组合标为冲突并回来重选，不能偷偷把 private route 文档化成公共 API。

关联：`PROD-11`、`PROD-19`、`AQ-385`、`CLI-02`、`CLI-03`、`CLI-13` 至 `CLI-15`、`SAFE-01`、`SAFE-03`、`SAFE-09`、`SAFE-12`、`SAFE-14`、`THREAT-01`、TU-13、PJ-14。

### PJ-18 一个 Context 是否支持多个 workspace root

通俗场景：F4-14 只决定一次启动怎样从传入目录得到一个初始安全边界；用户偶尔批准读取边界外文件，也不等于该目录从此成为第二个 workspace root。真正的多根会让相对路径、项目规则、Git 身份、shell cwd、审批、Context hash 与跨机 mapping 都需要知道“这是哪个根”。

- A：v0.1 一个 Context 恰好绑定一个 workspace root；显式访问外部路径仍按单次 Permission/目标处理，但不会因此升级成第二根。（推荐）
- B：一个主 root 加多个用户显式绑定的 `direct-readonly` root；每个附加根有稳定 alias、identity 与独立规则快照。direct write/patch/rename/delete 不能借“边界外单次授权”绕过该限制；未绑定的其他外部路径仍服从现有单次 Permission。这个词只承诺 yaca 的 direct tools 只读，不冒充 OS 级只读。
- C：多个 root 都可供 direct tools 读写；每个 direct tool、规则发现、审批和 Context 事件必须携带明确 root identity，跨根 direct rename/delete 另行授权。raw exec 只把一个 root 记录为 cwd，不因此缩成 root-scoped capability。

推荐 A。它与 `yaca [directory]`、单 Context/单任务、实时 hash 和旧平台路径模型一致；需要处理另一个目录时可以开启独立 Context/进程。B/C 适合组合仓库，但不是简单增加一个路径数组，而是 root-aware 的工具、Prompt、安全与恢复模型。

共同契约：任何方案都先由 F4-14 产生唯一 initial root，再由 PJ-13 处理恢复时的 recorded workspace；不得自动把上级 Git root、symlink 目标、外部工具访问或同名目录变成附加根。B/C 必须冻结稳定 root alias/identity、顺序、每根规则与 Git 元数据、相对路径显示、direct-tool schema、shell cwd、Permission/approval snapshot、Context XML mapping、主 Context 文件归属、某根失效后的只读/rebind/recovery 以及跨机路径映射。附加 root alias/mapping 只进入 XML workspace snapshot，不进入由 Context 逻辑 XML 路径实时计算的 16 字符 hash/Resolver，也不形成永久 ContextId。多根不等于同进程多个 active Context；一个根的 **direct-tool** approval 不能授权另一个根。

raw exec 的边界必须单独说真话：D-034 已确认它是宽能力且 Runtime 不解析 command。无论 B/C，批准 exec 都可能经绝对路径、链接、子进程或脚本触及并修改所有 OS 可访问的 bound/unbound path；审批必须列出当前全部 bound roots 和这一事实，不能承诺“只在 cwd root”或“附加根硬只读”，也不能把 shell approval 按 root 复用/切片。bound-root identity/order digest 必须进入 exec approval/plan/schema/Prompt snapshot；bind、unbind、reorder、rebind 或 root identity 变化都会使旧 snapshot 与授权 stale，不能让旧单根宽授权自动扩到后来加入的敏感根。需要物理只读只能依靠用户在 yaca 外设置的 ACL/mount；yaca 不把它宣传成自己的保证。选择 A 时配置/XML/help 不保留无消费者的 root list。

关联：`PROD-05`、`PROD-11`、`AQ-386`、`INSTR-01`、`INSTR-04`、`TOOL-11`、`SAFE-03`、`CTX-13`、F4-14、PJ-13。

### PJ-19 是否提供独立 transcription 动作

适用性：只有 PJ-16 B/C 使 v0.1 能建立合法音频输入对象时，本组才生效；PJ-16 A 下记为 `not-applicable`，不能保留空 `.transcribe`、Model purpose、配置或 XML artifact。PJ-19 C 进一步只与 PJ-16 C 相容，因为没有麦克风采集就不存在 live source。

通俗场景：把音频直接交给 main Model 回答任务，与“先把音频转成一份可以检查和编辑的文字”是两个不同动作。后者需要单独的 Model purpose、费用、进度、取消、失败和 artifact 身份，也必须决定转写文字是否自动变成用户消息。

- A：不提供独立 transcription；PJ-16 B/C 的音频只能作为用户显式选择的 main Model 输入，不注册转写命令或 artifact。（推荐）
- B：用户可显式选择一个已由 PJ-16 接受并 durable 的音频对象，发起独立、可取消的 bounded transcription request；成功产生 TranscriptArtifact，只预览并允许 copy/insert-into-draft/discard，不自动发送或改变 active turn。
- C：包含 B，并在 PJ-16 C 下允许显式 live incremental transcription；provisional 片段只属于当前 transcription activity，停止/收口后才原子发布最终 TranscriptArtifact。

推荐 A。它让音频能力保持为一种 main input，不增加第二个媒体工作流。B 适合语音笔记且结果边界清楚；C 还要处理 provisional 修订、麦克风中断和更复杂取消。三项都不自动换 Model/provider；B/C 必须显示 exact transcription Model/purpose、endpoint、费用预算、语言提示与是否外发，并让 failure/cancel 保留原音频而不制造半条用户消息。

共同契约：TranscriptArtifact 保存 source audio digest、Model/purpose snapshot、final/provisional 边界、文本、语言/置信度的诚实可选字段、费用/取消和创建事件。插入 draft 是新的用户动作，发送仍走普通 composer；artifact 本身不是指令、approval 或 main reply。跨机缺 transcription Model 时仍可阅读历史 artifact，不静默重新转写。选择 A 时配置/help/schema/zip 没有 transcription seam。

关联：`PROD-20`、`AQ-388`、`MODEL-02`、`MODEL-03`、`MODEL-07`、`CTX-01`、`CTX-05`、`TUI-04`、PJ-16、M05-01、AL06-09。

确认后 owner artifact：`00-product-and-compatibility.md` 的 transcription 产品契约，以及条件启用时 Model purpose、TranscriptArtifact、request/cancel/publication、draft insertion 和跨机缺失能力矩阵。

### PJ-20 是否提供 TTS/语音播报

通俗场景：把一条文字回复朗读出来不需要麦克风或 audio input，却会引入另一种 Model/本地引擎、扬声器设备、费用、公共场所隐私和停止目标。显式朗读一条完成消息与自动朗读每次回复也不是同一种打扰程度。

- A：v0.1 不提供 TTS/语音播报；没有 speech-output 配置、命令、设备访问或 codec。（推荐）
- B：用户可显式选择一条已完成的文本消息并请求朗读；开始前显示文本范围、语言、engine/Model、endpoint/费用与输出设备，活动可单独停止，不改变消息事实。
- C：包含 B，并提供默认关闭的 Context/session 级 auto-speak；只对完整、最终 assistant 正文生效，streaming delta、工具输出、审批、错误、安全警告、secret-classified 内容和 side/reviewer 内部结果永不自动朗读。

推荐 A。核心 Coding Agent 不依赖声音。B 是窄、可预期的可访问性增强；C 更流畅但增加误播隐私、busy audio 与会话覆盖。三项都必须保留完整文字等价路径，语音不能成为审批、警告或错误的唯一表达，也不能因朗读失败改变 main turn outcome。

共同契约：B/C 必须把 speech output 作为独立 activity/purpose，冻结 engine/Model capability、输入文本上限、费用/网络、设备、queue/interrupt/stop、退出收口和 XML receipt；默认不持久化生成音频 bytes，若要保存/导出则必须另开数据面决定，不能暗中制造长期媒体 sidecar。C 的 auto-speak 只消费当前 opt-in generation 之后新提交的一条 final assistant event；generation 绑定 exact engine/Model、endpoint、output device identity 和 text-selection policy，任一配置/Model/device 改变或 Context import/copy/rebind 后旧 opt-in 都回到 off/需重新确认，不能自动授权新目标。启动/continue、XML replay、renderer redraw、Web/remote reconnect 和 model-view rebuild 都不是新事件，绝不重播历史。receipt 绑定 event identity + opt-in generation，保证同一事件至多自动朗读一次；关闭再开启产生新 generation，但也不回扫旧消息。选择 A 时所有 speech-output 字段和组件为零表面。

关联：`PROD-21`、`AQ-389`、`MODEL-02`、`MODEL-03`、`MODEL-07`、`CTX-05`、`TUI-15`、`SAFE-09`、M05-01、AL06-35。

确认后 owner artifact：`00-product-and-compatibility.md` 的 speech-output 产品契约，以及 B/C 条件下 engine/Model、设备、费用、停止/退出、auto-speak exclusions、文字等价与 XML receipt 矩阵。

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
PJ-14 A
PJ-15 A
PJ-16 A
PJ-17 A
PJ-18 A
PJ-19 A
PJ-20 A
```

## 本包确认后的归档产物

项目负责人回复后，应当只把明确选择归档到：

- `DECISIONS.md`：产品级启动/表面/退出决定。
- `00-product-and-compatibility.md`：完整主旅程、启动路由、plan-state 终态，以及 Web、图像、音频、remote/headless、多根分别为 supported/confirmed-excluded/deferred/open 的能力状态表。
- `13-cli.md`：各入口怎样选择表面，但不在这里重复业务规则。
- `14-tui.md`：ACTION 块与表面投影要求。
- `22-application-runtime-and-concurrency.md`：启动/关闭必须兑现上述产品结果。
- `17-web.md`：只投影 PJ-14 的实际答案；A 写 exclusion/re-entry record，B/C 才进入浏览器与 HTTP 规格，不能继续保留含混“暂缓”。
- 对 PJ-15/PJ-16/PJ-19/PJ-20/PJ-17/PJ-18 选择 B/C 的任何能力，分别建立 image/audio-input/transcription/speech-output、公开控制协议或 root-aware 工具/Context 的 owner artifact 与 readiness gate；选择 A 或条件不成立时则生成 no-empty-shell 检查，而不是空模块。

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
8. `continue` action 命中健康、损坏、依赖缺失或被占用 Context。
9. chat 空闲、正在请求、正在审批或正在运行工具时退出。
10. REPL 有未保存草稿时返回或 EOF。
11. 浏览器访问时，产品明确是 unsupported、只读本地面或完整本地交互面，并且不会从内部 application service 推导出公开 API。
12. 用户通过文件/clipboard 附加图像、通过文件/麦克风建立音频、当前 Model 不支持对应 capability、媒体超限或复制 XML 到另一台机器时，均有与 PJ-15/PJ-16 一致的唯一结果。
13. 另一个本机进程、编辑器或远端客户端尝试驱动 Agent 时，监听、认证、审批与输入所有权严格服从 PJ-17，而不是因存在内部端口就意外开放。
14. 用户访问第二个目录、上级 Git root 或边界外文件时，能够区分一次性外部访问、Context rebind 与正式多根，不产生隐式 root。
15. 用户请求 standalone transcription、live transcription、显式朗读或 auto-speak 时，PJ-19/PJ-20 的适用性、Model/purpose、artifact/receipt、取消与文字等价路径只有一个结果，且不会从 PJ-16 暗中继承。
16. 选择排除的 Web/媒体/transcription/TTS/remote/multi-root 能力在配置、help、schema、Runtime、self-test 和 zip 中都没有可触发空壳；未来只有显式 re-entry 才能重新出现。

这些场景经负责人确认后，后续 AgentLoop、存储和 TUI 设计才有稳定的上游产品契约。
