# 10 上下文存储

状态：讨论中

## 职责

以单个活动 XML 持久化可接盘的规范事实：完整对话、实际 model view 引用、工具与审批、日志相关信息、会话级参数、模型/Prompt 切换、专用命名 metadata 及历史工具 cwd；提供创建、加载、保存、归档、删除和恢复。当前 workspace root 不在 XML 内重复保存，而由 XML 在 `__yaca__/CONTEXT/` 镜像树中的父目录解码。这里的“完整”仍受公开 schema 与明确资源上限约束，不等于无限保存每个 token delta 和任意二进制原始字节。

## 边界

- 文件格式底层能力来自 04 号系统。
- 名称与跨目录查找由 11 号系统处理。
- 压缩策略由 12 号系统处理。

## 设计要求

- 原子写入、崩溃恢复和损坏检测。
- 上下文中的 API key、环境变量和敏感工具输出需要明确处理。
- 从镜像父目录解码出的单一 workspace root 若不存在、身份变化或无权限，必须阻止继续并交给 `context-repl` 的显式 self-fix；不能误跳转、ordinary keep 或用 XML 内历史 cwd 猜当前 root。
- 格式必须包含版本号和迁移策略。

## 已确认的总体形态与剩余语义

D-022 已确认以下总体形态：

- 每个上下文以一个 XML 文件作为活动存储，不以 SQLite 或分段事件目录作为首选事实源。
- 根目录为 `__yaca__/CONTEXT/`，其下镜像每个 Context 恰好一个 workspace root；XML 所在镜像父目录是当前 root 的权威可解码表达。
- XML 不保存可覆盖镜像父目录的 `<WorkspaceRoot>`、root list、root count、alias 或类似 authority 字段；历史工具 cwd 与 rebind 记录只作为事件事实。
- 已确认示例把 Windows `C:` 表示为路径段 `C`，得到 `CONTEXT/C/Program Files/我的任务.xml`；其他盘符、UNC、根路径与 Linux 映射待定。
- 上下文 XML 保存完整对话、日志相关信息、会话级参数及其元数据；`.cautious` 的 `DoubleCheck` 会话覆盖属于这类元数据。
- 每个已提交 XML 的有界 header metadata 提供 canonical `Name`、`CreatedAt` 和 `UpdatedAt`，供 Catalog 在不解析完整正文时列出和排序。`CreatedAt` 在初次 no-replace 建立 XML 时写入并保持不变；`UpdatedAt` 在每一次成功发布的 durable XML mutation（消息/结果、会话 metadata、手工或自动 rename、rebind 事件、修复或迁移）中与该 mutation 原子更新，失败/只读 inspect 不推进。时间必须是 XML 中的规范值，不能用文件系统 ctime/mtime 代替；`Name` 与当前 basename 的一致性由打开/修改协议校验。
- 索引由 11 号系统从当前 XML 树实时派生；缓存和重扫机制待定。

仍需明确 reasoning/refusal、超限工具输出、`DoubleCheck` 动作/完成复核和实际 model-view manifest 的精确 schema。当前候选不周期性写 token delta；完整 response 或明确 interrupted response 才成为 canonical 事实。压缩只改变模型 view，不能删除事实历史。

路径 hash 包含 XML 文件名。D-023 已确认不建立永久 `ContextId`：当前逻辑路径是当前地址，固定 16 位 hash 由它运行时计算；重命名或移动改变逻辑路径后，新 hash 生效、旧 hash 立即失效。归档是否改变路径、软删除/彻底删除、备份和配额仍需讨论。

因此，XML 内部事件不能把上下文路径 hash 当作跨重命名不变的外键。turn、message、tool call/result 等仍需要局部序号或事件关系来保证同一 XML 内的一致性，但精确 schema 以后确认。历史日志可以记录当时的路径/hash 快照，不得据此建立旧 hash 自动别名。

`src/_CONTEXT_.xml` 目前只有头部注释，不构成 schema。仓库虽带有 sqlite3/7za 来源，但不能因此倒推活动存储必须使用 SQLite 或压缩包；它们还涉及 Windows x86、Linux x86_64、进程层与发布验证成本。

## 已确认的新 Context 建立与打开边界

D-040/D-041 已冻结下面的产品语义：

- 裸启动只建立一个有界内存 chat draft，不扫描历史，也不创建空 XML。
- 第一条 main 用户消息被接受时，先生成 `Untitled Conversation [XXXX]` 候选名，以 no-replace 建立 XML并 durable 保存该消息及此前内存会话设置；只有提交成功才允许 Model request。`XXXX` 是四位大写十六进制随机短标签，不是 ContextId 或 16 位路径 hash。
- `.model`、`.prompt`、`.cautious` 等在第一条 main 消息前只改变内存 draft；若用户空退出就随进程丢弃，不能伪造一个历史 Context。
- `AutoNameEveryMainTurns` 只调度低优先级命名请求；request/result、已经 durable 收口的 main-turn 水位、下一周期 baseline、原名/新名及取消事实进入同一 XML。只有周期大于零、水位达到下一周期且 `AutoRenameDisabled` 缺失/`false` 时才允许 admission；退出不等待该请求，恢复也不补跑。XML metadata 使用专用 boolean `AutoRenameDisabled`：缺失/`false` 允许，`true` 禁止；不使用通用 flags bag。
- 手工 rename 成功的同一持久化事务默认设置 `AutoRenameDisabled=true`；自动 rename 不设置它。context-repl 可查看、添加或取消标记；取消后只等待下一个满足 INI 周期与 idle 条件的调度点，不立即发起请求。
- 从 `true` 取消 marker 时，以当时已经 durable 收口的 main-turn 水位建立新的周期 baseline；marker 生效期间错过的周期不追赶、不补发，恢复后必须再完成完整的新周期才具备资格。
- marker 被添加或手工 rename 同事务置为 `true` 时，任何尚未完成的 `context-name` request 立即取消或逻辑失效。无法阻止的迟到 response 仍可保存 request/usage/cancel/result 证据，但不得进入 rename transaction 或改变当前名称。
- 每个 Context 恰好有一个 root，从当前 XML 的镜像父目录解码。XML 可保存工具当时的 cwd、路径/hash 快照和 rebind 结果，但它们只是历史事实，不是当前 root 的求值输入。
- 新 Context 由 F4-14 选出这个唯一 root 后发布到对应镜像目录。显式 rebind 是 context-repl 修复动作：持有操作锁、复核源/目标后，以 no-replace、可恢复协议把 XML 移动到目标镜像目录。成功后逻辑路径/hash 随位置改变；普通打开不能临时 keep 或静默猜同名目录。
- 活动 writer 存在时第二进程不得解析 Context 正文。只有不打开正文即可证明的名称、路径、busy 与 PID/unknown 元数据可以显示；来自 context-repl、CLI 或其他外部管理入口的 rename、rebind、delete、命名 marker 修改及其他 XML mutation 全部返回 `LockConflict`，直到 writer 释放。陈旧锁处理必须进入 Context self-fix，不能靠 Permission 或确认绕过。

初始 ASCII 名只避免程序生成文件名受 XP 当前代码页影响，不改变用户数据规则。XML、用户消息、Prompt、手工 Context 名和路径保持 strict UTF-8；Windows adapter 必须用宽字符 argv/console/file API 转换，显示替换文本永远不能反馈成实际路径或 hash 输入。

## 已决方案与未采用方案

### A. 每个上下文一个完整 XML（已确认总体形态）

一个上下文对应镜像树中的一个 XML，文件本身承载完整对话与会话元数据。每次整体重写、追加可恢复片段，还是采用其他 XML 更新策略尚未确认；无论怎样实现，对外可见的已提交版本都必须可解析、可恢复，不能因半写入静默变成另一段有效历史。

优点是路径直观、便于复制和直接查看。主要风险是长会话、大工具输出、XML 转义、保存峰值与崩溃恢复；XP x86 上尤其不能假设可以把整个大文件多份载入内存。公开 schema 也可能长期束缚迁移，因此“活动 XML”不自动等于“第三方可写的稳定公共格式”。

### B. 上下文目录 + 分段事件记录 + 派生快照（未采用为总体形态）

每个上下文使用稳定 ID 目录，保存版本化 manifest、追加式/分段事件记录以及派生的模型输入快照和压缩摘要；全局索引只是可重建缓存。XML/Markdown 作为稳定导出，而不是活动数据库。

优点是增量写入、内存有界，尾部损坏通常只影响最后记录；原始事件与压缩视图可以同时保留，索引丢失后也能重建。代价是必须明确记录边界、校验、锁、分段轮换与恢复算法。

该方案原本有更好的增量写入与尾部恢复性质，但与已确认的单 XML 活动存储不一致。以后若提出 sidecar、临时恢复记录或附件，必须逐项说明其必要性，不能暗中把 XML 降级为只读导出。

### C. SQLite 事件与索引（未采用）

用事务表保存会话、事件、索引与压缩代次，并另行导出。

查询和迁移能力成熟，但需要可靠的 XP x86/CentOS 7 x86_64 构建、绑定或子进程协议、锁和异常文件系统验证；数据库也不适合作为直接可读日志。不能只因仓库已有 `sqlite3` 就选择它。

## 单 XML 内仍需分离的数据角色

以下是待确认的设计方向，不是已决策契约：

- **事实历史**：用户输入、完成的模型消息、工具调用/结果、权限决定和 turn 边界，只追加或显式标记撤销；每个顶层 main/side turn 还要保存其 immutable public effective config-generation digest/非秘密 generation reference，与有效 Model/Permission/Prompt/tool-schema snapshot 或可完整验证的引用，使后续 INI 变化不改写历史。用于发现 INI bytes 是否变化的 private source digest 只留在进程内，绝不写入 XML。
- **运行视图**：下一次发送给模型的消息集合，可由压缩、截断和模型能力派生。
- **实时索引投影**：名称、逻辑路径、由镜像父目录解码的唯一 root、hash、时间和状态，从当前 XML 树计算，不是独立事实源。
- **用户导出**：正式会话文件仍是可读、可检查的 XML；Markdown/JSON 若未来需要只能作为显式 stdout/临时投影另行决定，不成为第三种长期事实格式。是否允许直接热复制活动 XML 仍待决定。

事件序列应是唯一事实，current projection/摘要如存在必须记录覆盖到的 event seq/digest，失配时可丢弃重建。每个 XML 内需要局部单调身份，例如 event/turn/input/request/attempt/message/tool-call/operation/approval/compaction；无永久 ContextId 不影响这些局部关系。provider 原始 ID 不能替代本地身份。

这种逻辑分离可以存在于同一个 XML 的不同 section 中，使压缩改变模型看到的内容而不必静默销毁用户历史。具体 schema 尚未确认。

## 必须定义的持久化边界

- 已确认第一条及后续 main 用户输入都在发送给模型前 durable；仍需冻结 XML 中的精确原子组、失败 ID 与 draft-copy 行为。
- 工具调用意图、权限决定、执行开始和结果各自是否单独记录。
- 工具产生副作用后、结果写入前崩溃时如何避免自动重复执行。
- 流式文本增量是临时 UI 事件还是规范历史；中途断流是否保留部分文本。
- flush 失败或磁盘满时是否立即停止 Agent Loop。
- 已确认活动 writer 存在时第二个进程完全拒绝打开正文；仍需冻结锁证据、PID unknown 与 self-fix 的陈旧锁证明协议。
- `Name`、`CreatedAt`、`UpdatedAt`、`AutoRenameDisabled` 与自动命名水位属于受 schema、digest 和同一原子发布协议保护的 metadata；不能用文件名、文件系统时间或临时缓存静默修补 XML 中的不同值。
- 创建新上下文时，临时 XML 不得参与 Catalog；完整写入、flush 和验证后才能使用 `publish_new_no_replace` 或等价能力发布，不能用“先检查、再普通 rename”冒险覆盖非协作程序刚创建的目标。
- 创建或保存期间崩溃、磁盘满或验证失败不能发布半个正式 XML；临时残留的识别、清理和恢复协议仍需确认。

## 单 XML 的物理限制

well-formed XML 在根结束标签后不能原地追加新子元素。当前只有三类路线：

1. 每个 canonical 边界流式生成完整新 XML、验证/flush 后 replace；正式文件始终合法，但长会话累计 I/O 是 O(n²)。
2. 活动期间允许 durable recovery WAL/sidecar，安全点合并回 XML；性能更好，但暂时不再只有正式 XML 承载最新事实。
3. 保持根未闭合或闭合后追加片段；文件不是始终合法 XML，直接排除。

领先候选是先用路线 1 做正确性基线，不写周期性 token checkpoint，并在 XP x86/旧磁盘测试 1/10/50/100 MiB 等长会话。达到已确认大小/提交时延硬门后 fail-stop/只读/导出，而不是继续副作用。如果基准不达标，必须请负责人明确允许路线 2 或调整单 XML 承诺，不能由实现暗中引入第二事实源。

同目录 temp、稳定 writer lock/lease 和最多一个 previous-valid generation 可以是有界恢复辅助，但它们必须被 Resolver 忽略并有完整真值表。锁旧 XML handle 后再 replace 不会自然锁住新路径，因此 stable lock 不能省略为“文件已打开”。Windows XP 可用的 replace/flush 原语也必须在目标文件系统上实测；库只负责 XML parse/write，不负责 durability。

## 导入信任边界

外部 XML 是不可信输入。DTD/external entity 必须禁用，深度/元素/属性/文本/总大小受限。历史 Permission、`DoubleCheck=false`、ContextPrompt 和 approval 要忠实显示，但不是目标机新授权：继续运行前用本机配置重新验证，审批永远 audit-only，任何降低本机安全默认的覆盖显著确认。公开 schema 的 v0.1 承诺优先是第三方可读、yaca 为受支持 writer；第三方原地写入可另行建立 conformance contract。

## 后续讨论顺序

1. Windows/Linux 路径规范化、文件名编码、长路径与碰撞。
2. “完整对话”、model-view manifest、局部 ID、日志信息和会话参数元数据的 XML schema。
3. 提交点、完整重写基线、锁/temp/backup 真值表、崩溃恢复与副作用去重。
4. 事实历史、模型视图、压缩和导出的关系。
5. 敏感内容、保留、配额、归档和删除。
6. 版本迁移、导入导出与损坏修复。

## 当前讨论入口

D-023 已解决外部身份问题，D-024 已确认统一 Resolver。下一步继续定义 XML 内“完整对话”、日志信息、会话参数元数据和局部事件关系。
