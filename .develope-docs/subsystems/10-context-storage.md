# 10 上下文存储

更新日期：2026-08-29

状态：**W1-C 规格侧已冻结** — 内部事件目录、[`contracts/context.lua`](../contracts/context.lua) 语义 schema、[`contracts/context.rng`](../contracts/context.rng) 结构 schema 与最小 fixture 已对齐；平台原语与 hard 数字待 TP。非公共 API（D-068）。

## 职责

以单个活动 XML 持久化可以跨机接盘的规范事实：完整对话、实际 model view、工具与审批、日志相关信息、会话级参数、Model/Permission/Prompt 切换、压缩代次、专用命名 metadata、历史工具 cwd，以及无法证明副作用结果时的 `unknown` 事实；提供创建、加载、保存、永久删除和崩溃恢复。当前 workspace root 不在 XML 内重复保存，而由 XML 在 `__yaca__/CONTEXT/` 镜像树中的父目录解码。这里的“完整”仍受 **yaca 内部** 版本化 schema 与经旧机实测冻结的资源上限约束，不等于无限保存每个 token delta 和任意二进制原始字节。对外不承诺第三方 XML API（D-068）；跨工具可读默认走 export。

## 边界

- 文件格式底层能力来自 04 号系统。
- 名称与跨目录查找由 11 号系统处理。
- 压缩策略由 12 号系统处理。

## 设计要求

- 原子写入、崩溃恢复和损坏检测。
- XML 不保存 Model `Key`、代理凭据、Authorization header 或环境变量秘密值；新机器继续请求时必须从本机 INI 取得凭据。用户主动写入消息或工具输出的敏感正文仍按会话事实和既定截断/脱敏规则处理，不能声称能自动识别所有秘密。
- 从镜像父目录解码出的单一 workspace root 若不存在、身份变化或无权限，必须阻止继续并交给 `context-repl` 的显式 self-fix；不能误跳转、ordinary keep 或用 XML 内历史 cwd 猜当前 root。
- 格式必须包含版本号和迁移策略。

## 已确认的长期文件与恢复辅助边界

D-053 把长期用户事实限制为两类：主 INI，以及 `__yaca__/CONTEXT/` 下每个 Context 的单个正式 XML。JSON 只用于协议或临时内存投影，日志事实进入健康 Context XML；不能增加长期 WAL、事件 sidecar、索引数据库、恢复数据库或第二份活动事实源。

安全提交和单 writer 允许在目标 XML 同目录短寿命存在三类控制物：完整新 generation 的 temp、稳定 writer lock/lease，以及最多一个 previous-valid generation。它们不是历史、导出或备份功能，必须有可识别的命名和状态，必须被 Resolver/Catalog 忽略，并在提交、恢复或 self-fix 收口后清理。崩溃遗留允许持续到下一次恢复，但不能演化成长期增量记录。

主 INI 可以按已确认配置契约明文保存 `Key`；Context XML 只保存解释历史所需的非秘密 Model 信息和本地映射引用，绝不复制 `Key`。因此“复制 XML 可以接盘”指任务事实和执行状态完整可移交，不表示同时搬运凭据、程序二进制或目标机 Permission 授权。

## 已确认的总体形态与技术待证项

D-022/D-053 已确认以下总体形态：

- 每个上下文以一个 XML 文件作为唯一长期活动事实源，不使用 SQLite、分段事件目录或长期 WAL。
- 根目录为 `__yaca__/CONTEXT/`，其下镜像每个 Context 恰好一个 workspace root；XML 所在镜像父目录是当前 root 的权威可解码表达。
- XML 不保存可覆盖镜像父目录的 `<WorkspaceRoot>`、root list、root count、alias 或类似 authority 字段；历史工具 cwd 与 rebind 记录只作为事件事实。
- 已确认示例把 Windows `C:` 表示为路径段 `C`，得到 `CONTEXT/C/Program Files/我的任务.xml`；其他盘符、UNC、根路径与 Linux 映射待定。
- 上下文 XML 保存完整对话、日志相关信息、会话级参数及其元数据；`.cautious` 的 `DoubleCheck` 会话覆盖属于这类元数据。
- 每个已提交 XML 的有界 header metadata 提供 canonical `Name`、`CreatedAt` 和 `UpdatedAt`，供 Catalog 在不解析完整正文时列出和排序。`CreatedAt` 在初次 no-replace 建立 XML 时写入并保持不变；`UpdatedAt` 在每一次成功发布的 durable XML mutation（消息/结果、会话 metadata、手工或自动 rename、rebind 事件、修复或迁移）中与该 mutation 原子更新，失败/只读 inspect 不推进。时间必须是 XML 中的规范值，不能用文件系统 ctime/mtime 代替；`Name` 与当前 basename 的一致性由打开/修改协议校验。
- 索引由 11 号系统从当前 XML 树实时派生；任何进程内加速投影均可丢弃重建，不能成为长期文件。

仍需在 schema 技术规格中冻结 reasoning/refusal、超限工具输出、`DoubleCheck` 动作/完成复核和实际 model-view manifest 的精确元素与上限；这些不再是负责人对存储路线的选择。XML 不周期性持久化 token delta；完整 response 或明确 interrupted response 才成为 canonical 事实。压缩只改变 model view，不能删除事实历史。

路径 hash 包含 XML 文件名。D-023 已确认不建立永久 `ContextId`：当前逻辑路径是当前地址，固定 16 位 hash 由它运行时计算；重命名或移动改变逻辑路径后，新 hash 生效、旧 hash 立即失效。D-053 已排除 archive、trash、soft-delete 和 restore：Context 管理只提供经过确认的永久删除；保留期限与资源配额仍需后续技术规格收口，但不能借此重新增加归档表面。

因此，XML 内部事件不能把上下文路径 hash 当作跨重命名不变的外键。turn、message、tool call/result 等仍需要局部序号或事件关系来保证同一 XML 内的一致性；精确 schema 由 AR-P0-10 技术规格冻结，不再构成负责人补问。历史日志可以记录当时的路径/hash 快照，不得据此建立旧 hash 自动别名。

`src/_CONTEXT_.xml` 目前只有头部注释，不构成 schema。仓库虽带有 sqlite3/7za 来源，但不能因此倒推活动存储必须使用 SQLite 或压缩包；它们还涉及 Windows x86、Linux x86_64、进程层与发布验证成本。

## 已确认的新 Context 建立与打开边界

D-040/D-041 已冻结下面的产品语义：

- 裸启动只建立一个有界内存 chat draft，不扫描历史，也不创建空 XML。
- 第一条 main 用户消息被接受时，先生成 `Untitled Conversation [XXXX]` 候选名，以 no-replace 建立 XML 并 durable 保存该消息及此前内存会话设置；只有提交成功才允许 Model request。`XXXX` 是四位大写十六进制随机短标签，不是 ContextId 或 16 位路径 hash。
- `.model`、`.prompt`、`.cautious` 等在第一条 main 消息前只改变内存 draft；若用户空退出就随进程丢弃，不能伪造一个历史 Context。
- `AutoNameEveryMainTurns` 只调度低优先级命名请求；request/result、已经 durable 收口的 main-turn 水位、下一周期 baseline、原名/新名及取消事实进入同一 XML。只有周期大于零、水位达到下一周期且 `AutoRenameDisabled` 缺失/`false` 时才允许 admission；退出不等待该请求，恢复也不补跑。XML metadata 使用专用 boolean `AutoRenameDisabled`：缺失/`false` 允许，`true` 禁止；不使用通用 flags bag。
- 手工 rename 成功的同一持久化事务默认设置 `AutoRenameDisabled=true`；自动 rename 不设置它。context-repl 可查看、添加或取消标记；取消后只等待下一个满足 INI 周期与 idle 条件的调度点，不立即发起请求。
- 从 `true` 取消 marker 时，以当时已经 durable 收口的 main-turn 水位建立新的周期 baseline；marker 生效期间错过的周期不追赶、不补发，恢复后必须再完成完整的新周期才具备资格。
- marker 被添加或手工 rename 同事务置为 `true` 时，任何尚未完成的 `context-name` request 立即取消或逻辑失效。无法阻止的迟到 response 仍可保存 request/usage/cancel/result 证据，但不得进入 rename transaction 或改变当前名称。
- 每个 Context 恰好有一个 root，从当前 XML 的镜像父目录解码。XML 可保存工具当时的 cwd、路径/hash 快照和 rebind 结果，但它们只是历史事实，不是当前 root 的求值输入。
- 新 Context 使用用户传入且已经证明存在、可进入的真实目录作为唯一 root，并发布到对应镜像目录；上级 Git root 只作证据，不自动提升边界。显式 rebind 是 context-repl 修复动作：持有操作锁、复核源/目标后，以 no-replace、可恢复协议把 XML 移动到目标镜像目录。成功后逻辑路径/hash 随位置改变；普通打开不能临时 keep 或静默猜同名目录。
- 活动 writer 存在时第二进程不得解析 Context 正文。只有不打开正文即可证明的名称、路径、busy 与 PID/unknown 元数据可以显示；来自 context-repl、CLI 或其他外部管理入口的 rename、rebind、delete、命名 marker 修改及其他 XML mutation 全部返回 `LockConflict`，直到 writer 释放。陈旧锁处理必须进入 Context self-fix，不能靠 Permission 或确认绕过。

初始 ASCII 名只避免程序生成文件名受 XP 当前代码页影响，不改变用户数据规则。XML、用户消息、Prompt、手工 Context 名和路径保持 strict UTF-8；Windows adapter 必须用宽字符 argv/console/file API 转换，显示替换文本永远不能反馈成实际路径或 hash 输入。

## 已决方案与未采用方案

### A. 每个上下文一个完整 XML（已确认总体形态）

一个上下文对应镜像树中的一个 XML，文件本身承载完整对话与会话元数据。每个 canonical 提交边界必须从旧 generation 流式生成完整新 XML，经 flush 和从头验证后，再用目标平台已经证明的原子替换或两代可恢复替换发布。不能原地追加根后片段，也不能先把增量写进长期 WAL 再异步合并。对外可见的已提交版本始终必须可解析、可恢复，不能因半写入静默变成另一段有效历史。

优点是路径直观、便于 yaca 复制恢复。主要风险是长会话、大工具输出、XML 转义、保存峰值与崩溃恢复；XP x86 上尤其不能假设可以把整个大文件多份载入内存。D-068 已明确活动 XML **不是** 对外稳定公共格式；跨工具请用 export。

### B. 上下文目录 + 分段事件记录 + 派生快照（未采用为总体形态）

每个上下文使用稳定 ID 目录，保存版本化 manifest、追加式/分段事件记录以及派生的模型输入快照和压缩摘要；全局索引只是可重建缓存。XML/Markdown 作为稳定导出，而不是活动数据库。

优点是增量写入、内存有界，尾部损坏通常只影响最后记录；原始事件与压缩视图可以同时保留，索引丢失后也能重建。代价是必须明确记录边界、校验、锁、分段轮换与恢复算法。

该方案原本有更好的增量写入与尾部恢复性质，但与已确认的单 XML 活动存储不一致。短寿命 temp/lock/previous-valid 只服务一次提交或恢复，不构成重新引入该方案；长期 sidecar、附件事实或事件日志仍被排除，不能暗中把 XML 降级为只读导出。

### C. SQLite 事件与索引（未采用）

用事务表保存会话、事件、索引与压缩代次，并另行导出。

查询和迁移能力成熟，但需要可靠的 XP x86/CentOS 7 x86_64 构建、绑定或子进程协议、锁和异常文件系统验证；数据库也不适合作为直接可读日志。不能只因仓库已有 `sqlite3` 就选择它。

## 单 XML 内已确认的数据角色

单 XML 必须在一个 schema 中区分以下角色；精确元素名、局部 ID 表示和大小上限由后续技术规格冻结：

- **事实历史**：完整用户/assistant 对话，model request/response/interrupted/refusal，工具调用、真实或 synthetic/unknown 结果，Permission 判定、approval、review、重试、取消和 turn 边界。每个顶层 main/side turn 保存 immutable public effective config-generation reference，以及实际 Model、Permission、四层 Prompt component、tool registry/schema 与相关能力的 snapshot/digest；后续 INI 变化不能改写历史。用于发现 INI bytes 是否变化的 private source digest 只留在进程内，绝不写入 XML。
- **运行视图**：下一次实际发送给模型的消息集合，包含所用 Model 切换、Prompt component、压缩摘要、保留的最近原文 atomic groups 及其来源范围；可以重建，但每次已经发出的 view 必须能由 XML 解释。
- **压缩记录**：每次 compaction 的来源 event 范围/digest、使用的 Model/Prompt purpose、结构化摘要、保留窗口、结果或失败，以及被它取代的 model-view generation；压缩不删除事实历史。
- **移交与映射信息**：非秘密 Model endpoint/protocol/remote model ID/capability snapshot，Permission 名称/能力矩阵/Prompt snapshot，ContextPrompt，会话覆盖，历史 workspace/path/hash/cwd/rebind，以及目标机重新映射所需的稳定引用。凭据只由目标机 INI 提供。
- **审计信息**：历史 approval/grant、DoubleCheck 结果和其他安全决定必须保留以解释过去，但导入、复制或恢复后只作 audit，不能授权目标机的新动作。
- **实时索引投影**：名称、逻辑路径、由镜像父目录解码的唯一 root、hash、时间和状态，从当前 XML 树计算，不是独立事实源。
- **用户移交**：正式会话文件本身就是可读、可检查的移交物；从无活动 writer 的已提交 generation 复制该 XML，即可在另一台具有兼容 yaca 和本地凭据/映射的机器继续。Markdown/JSON 若未来需要只能作为 stdout 或短寿命投影，不能成为第三种长期事实格式；活动 writer 下能否取得一致副本必须由已证明的 snapshot/read 协议决定，不能承诺普通热复制。

事件序列是唯一业务事实，current projection/摘要必须记录覆盖到的 event seq/digest，失配时只能丢弃重建。每个 XML 内必须有局部单调身份，例如 event/turn/input/request/attempt/message/tool-call/operation/approval/compaction；无永久 ContextId 不影响这些局部关系。provider 原始 ID 不能替代本地身份。

这些角色只能是同一个正式 XML 内的不同 section/关系，使压缩改变模型看到的内容而不静默销毁用户历史。逻辑类型与提交语义见 **W1-C**；机器可读 schema 文件与字节上限仍待 TP。

## 已确认的持久化边界与待冻结细节

- 第一条及后续 main 用户输入都必须在发送给模型前 durable；仍需冻结 XML 中的精确原子组、失败 ID 与 draft-copy 行为。
- 工具调用意图、Permission/approval 和执行开始必须在副作用前 durable；完成、失败或无法证明结果的 `unknown` 必须在下一次模型采样前 durable。崩溃恢复绝不自动重放 `started`/`unknown` 操作。
- 流式 token delta 只是临时 UI 事件；正常完整消息或带明确 `interrupted` 状态的有界部分消息才进入规范历史。
- flush、验证、replace 或磁盘空间失败必须停止该 Context 的新模型请求和副作用，保留最后一个可证明 generation，并进入明确错误/self-fix，不得以内存新状态继续运行。
- 已确认活动 writer 存在时第二个进程完全拒绝打开正文；仍需冻结锁证据、PID unknown 与 self-fix 的陈旧锁证明协议。
- `Name`、`CreatedAt`、`UpdatedAt`、`AutoRenameDisabled` 与自动命名水位属于受 schema、digest 和同一原子发布协议保护的 metadata；不能用文件名、文件系统时间或临时缓存静默修补 XML 中的不同值。
- 创建新上下文时，临时 XML 不得参与 Catalog；完整写入、flush 和验证后才能使用 `publish_new_no_replace` 或等价能力发布，不能用“先检查、再普通 rename”冒险覆盖非协作程序刚创建的目标。
- 创建或保存期间崩溃、磁盘满或验证失败不能发布半个正式 XML；temp/target/previous-valid/lock 的完整恢复真值表、文件命名和平台错误映射仍需技术证明。

## 单 XML 的已确认提交协议

well-formed XML 在根结束标签后不能原地追加新子元素，因此每个 canonical mutation 使用同一条提交流水线：

1. 在稳定 lock/lease 下固定旧 generation、预期 schema/generation 和 mutation 输入。
2. 以分块读取旧 XML、分块写入同目录 temp 的方式生成一份完整新 XML；实现不得要求把旧、新两个完整 DOM 同时放入内存。
3. 写完根结束标签后 flush 并关闭 temp，再从头进行 XML/schema、局部关系、metadata 和 generation 一致性验证。
4. 验证通过后，使用该目标平台已经证明的原子 replace；若平台/文件系统不能提供所需原子性，则使用 target + 最多一个 previous-valid 的确定性两代恢复协议。发布与目录 durability 的成功条件必须由平台规格定义，不能把普通 rename 当作未经证明的原子保证。
5. 发布后重新确认正式 generation，再清理 temp/previous-valid 并释放稳定锁。任一步失败都保留或恢复最后一个可证明的完整 generation；多候选且无法确定先后时 fail-closed，由 self-fix 处理，绝不拼接或猜测事件。

根未闭合、根后追加和长期 WAL/sidecar 已排除。previous-valid 是一次替换窗口内的完整旧 generation，不是 undo、用户 backup 或另一条会话历史；Resolver/Catalog 在任何状态下都只把一个已证明的正式目标视为 Context。

该协议让单次提交 I/O 随 XML 大小线性增长，长会话累计仍可能达到 O(n²)。最终 XML 大小、单次提交延迟、启动扫描延迟和内存 hard limits 必须由 Windows XP x86/CentOS 7 的大 XML、慢盘、磁盘满、进程终止和掉电等价故障测试证明后冻结；Windows x64 等发行目标再执行对应回归。

**HardLimit 用户契约（D-063 / SQ-06）：**

- 数值须 **足够大**，使触顶在声明工作负载下属于 **异常**，不是日常路径。  
- 超过 hard limit 时：新 durable 写入/副作用前 **fail-stop**；不丢历史、不启用 WAL、不自动删史。  
- 已有 XML 在安全范围内可只读查看/导出。  
- **必须** 提示用户 **新开对话**，并提供可复制的 **接盘 Prompt 建议**（供下一会话的 Model 阅读关键材料/目标/未完成项）；不自动开新 Context、不自动注入历史。  
- 不得把 compact 宣传为“一定能解除 XML 体积 hard limit”。

如果某个 XML 库、flush/replace 原语或当前限额在目标机证明失败，技术退路依次是更换满足同一窄接口的流式库/平台 adapter、使用已验证的两代恢复替换、依据证据收紧 hard limits。若这些仍无法兑现固定协议，必须重新打开 D-053 的最小产品保证；实现不能自行切换到第二事实源。

## 原位移交与导入信任边界

外来 XML 由用户先放入目标 workspace 对应的正确 `__yaca__/CONTEXT/` 镜像目录；yaca 不提供“导入后再复制到内部目录”的第二条存储路线。`context-repl` 在原位、取得 writer 之前，以不可信输入方式只读执行大小/编码/XML/schema/局部关系/metadata 与 basename 一致性检查，并确认镜像父目录解码出的唯一 workspace、文件系统 identity、Model 和 Permission 映射。映射缺失或不一致必须显式修复/确认，不能按名字猜测；校验和映射收口后才可在同一路径取得 writer。

DTD/external entity 必须禁用，深度/元素/属性/文本/总大小受限。历史 Permission、`DoubleCheck`、ContextPrompt、approval/grant 和工具结果要忠实显示，但 approval/grant 永远 audit-only，不会在目标机创建授权；继续运行使用目标机当前有效 Permission 重新求值。Model `Key`、代理凭据、Authorization header 和环境变量秘密值不属于 XML schema，必须由目标机 INI 重新提供。缺凭据或映射不阻止只读检查历史，但阻止新的模型请求或副作用。

外来 XML 还必须保留并验证完整接盘信息：实际 Prompt component、Model/Permission/tool snapshot、压缩/model-view provenance、请求与工具结果、取消/重试，以及所有 `unknown` 副作用事实。任何 unsupported schema、损坏、活动锁、unknown operation 或歧义映射都保持只读/fail-closed，并路由到 context-repl self-fix；不能自动重放工具或复制成一个看似健康的新 Context。**D-068：** 上述接盘指 yaca 对用户放入镜像树的文件做产品内导入/校验/继续写，不是对外稳定公共 XML API。第三方工具不保证能解析；人类/跨工具默认使用 export。yaca 内部仍须版本化 schema 与 round-trip 正确性。

## W1-C 内部 schema 展开（2026-08-10）

状态：内部契约首版；**非** 公共 API（D-068）。元素本地名可在实现前微调，但 **角色、顺序关系、提交/恢复语义不得改弱**。

### 1. 文件与旁路控制物命名

| 角色 | 规范名模式（同目录） | Catalog/Resolver |
| --- | --- | --- |
| 正式 Context | `{Name}.xml` | 唯一事实候选 |
| 提交 temp | `{Name}.xml.yaca-tmp-{nonce}` | **忽略** |
| previous-valid | `{Name}.xml.yaca-prev`（最多一个） | **忽略**（恢复协议专用） |
| writer lock | `{Name}.xml.yaca-lock` | **忽略**；持有证据见 §5 |

`nonce` 足够避免碰撞；self-test 可回收陈旧 tmp。禁止把 tmp/prev/lock 当第二会话。

### 2. 文档骨架（逻辑结构）

```text
YacaContext
  @schemaVersion          -- 内部世代，如 0.1.0
  @generation             -- 单调递增，每次成功 publish +1
  Header                    -- 有界；Catalog 可只读 header
    Name
    CreatedAt               -- 首次 durable 固定
    UpdatedAt               -- 每次成功 publish 推进
    AutoRenameDisabled      -- bool；缺省=false
    NamingWaterline         -- 已计 durable completed main 水位（可选显式）
    AutoNameBaseline        -- 取消 marker 后的 baseline（可选）
  Session                     -- 当前会话选择（非秘密）
    CurrentModel            -- logical name + 非秘密 snapshot/digest
    CurrentPermission
    DoubleCheckOverride     -- inherit|true|false
    DoubleCheckGoalOverride
    ContextPrompt
  Facts                       -- 唯一业务事件流
    Event*                  -- 按 seq 严格递增
  ModelView                   -- 可重建；记录覆盖到的 fact 范围
    ActiveManifest
    CompactionRecord*       -- 历史代次；不删 Facts
  Audit                       -- 可选分区或并入 Event
```

说明：

- **无** `<WorkspaceRoot>` 权威字段；root = 镜像父目录解码。  
- **无** Key/secret。  
- Header 必须够 Catalog 排序（Name/CreatedAt/UpdatedAt）而无需扫完 Facts。

### 3. 局部身份

| ID | 作用域 | 规则 |
| --- | --- | --- |
| `eventSeq` | 单 XML | 从 1 单调 +1；永不复用 |
| `turnId` | 单 XML | 局部唯一；main/side 标记 |
| `requestId` | 单 XML | LogicalRequest |
| `attemptId` | 隶属 request | 1..n |
| `messageId` | 单 XML | user/assistant/system 组件 |
| `toolCallId` | 单 XML | 本地 id；可记 provider id 仅审计 |
| `operationId` | 单 XML | 副作用意图 |
| `approvalId` | 单 XML | 人批 |
| `reviewId` | 单 XML | action/termination review |
| `compactionId` | 单 XML | |

崩溃恢复 **禁止** 复用已 durable 的 id。

### 4. Event 类型目录（Facts 流）

每条 Event：`seq`, `type`, `at` (canonical time), 可选 `turnId`, 载荷。

| type | 载荷要点 | 与 W1-A 屏障 |
| --- | --- | --- |
| `turn_started` | kind=main\|side；configGeneration public digest；model/permission/prompt/tool-schema snapshots | admission 后 |
| `user_message` | text；source=main\|queue\|steer\|ask_reply… | **Model 请求前** durable |
| `model_request` | purpose；requestId；viewManifestRef | |
| `model_message` | role；完整文本或 interrupted+partial；control? | 完整/interrupted 才进 Facts；**无** token delta 洪流 |
| `model_control` | finish\|ask-user\|refuse；载荷 | |
| `model_yield` | 无 control 的完整普通回复标记 | → waiting_user |
| `tool_call` | toolCallId；name；args canonical | |
| `permission_decision` | capability；allow\|confirm\|deny；profile snapshot | |
| `approval` | decision；approvalId；绑定 operation/tool | 副作用前 |
| `operation_intent` | operationId；kind；target identity/digest | **副作用前** |
| `operation_result` | ok\|error\|cancelled\|unknown\|skipped；evidence | **下次采样前** |
| `tool_result` | 配对 toolCallId；body 有界；truncated | 同上 |
| `action_review` | verdict；reviewId；binding | |
| `termination_review` | verdict；gap? | |
| `turn_ended` | **唯一** outcome（completed\|waiting_user\|refused\|…） | Finalizing |
| `cancel` | target activity；reason | |
| `steer` | 注入摘要 | |
| `compaction` | compactionId；source range/digest；result\|fail | 发布 view 前 |
| `model_view_published` | manifest digest；covers eventSeq range | |
| `session_override` | cautious/prompt/model/permission 变更 | |
| `rename` | old/new name；AutoRenameDisabled 事务 | |
| `rebind` | old/new logical path snapshot；root 变化事件 | |
| `auto_name` | request/result/cancel；不采用迟到名 | |
| `config_generation_ref` | public digest only | 可并入 turn_started |
| `warning` | stuck 预警等 | |
| `unknown_side_effect` | 需人处理的未知副作用 | |
| `import_mapping` | 外来接盘 mapping 记录 | audit |

**不入库（transient）：** 流式 delta、spinner、未提交 draft、未开始 queue 项（D-066）。

**文本/二进制载体：** 优先 XML 安全 text；非法/二进制用 `representation=base64` + 原始长度 + digest（与 TP-010 方向一致）。

### 5. Writer lock

| 项 | 契约 |
| --- | --- |
| 互斥 | 一 Context 一 writer |
| 锁内容 | pid、startedAt、可选 hostname；无法证 pid → unknown |
| 第二进程 | 拒正文；可显示 name/path/busy/pid\|unknown |
| 管理 mutation | 外进程 rename/rebind/delete/marker → LockConflict |
| 陈旧锁 | **仅** context self-test + 平台证据；禁止按锁龄强抢 |

### 6. 提交状态机

```text
Idle(have published generation G)
  -> AcquireLock
  -> WriteTemp (stream old -> new complete XML)
  -> FlushCloseTemp
  -> ValidateTemp (well-formed + schema + ids + header)
  -> PublishReplace (atomic or two-generation)
  -> ConfirmPublished
  -> CleanupAux
  -> ReleaseLock
  -> Idle(G+1)
```

任一步失败 → **Abort**：保留最后已证明正式 generation；不拼接半文件；清理或隔离失败 temp（策略：删 temp 或留待 self-test，不得被当作正式 Context）。

### 7. 崩溃真值表（产品级）

| 崩溃/失败点 | 磁盘上可能留下 | 恢复后正式真相 |
| --- | --- | --- |
| 未获锁 | 无变 | 旧 G |
| 写 temp 中 | 半 temp | 忽略/删 temp；旧 G |
| temp 已写未验证 | 完整或半 temp | 验证失败则丢 temp；旧 G |
| 验证通过未 publish | 好 temp | 可完成 publish **或** 丢 temp 保持旧 G（须确定性；推荐：仅当 lock 仍证明为己方且 temp digest 已知时续发，否则丢 temp） |
| publish 换名中 | temp + target 模糊 | 两代协议：至多一个合法正式文件；歧义 → fail-closed + self-test |
| publish 后未清理 | 正式 G' + 残余 prev/tmp | 正式 G'；清辅助 |
| 持锁进程死 | lock 文件 | self-test 证陈旧后释放；不自动重放 operation |

**禁止：** 自动重放 `operation_intent` 无 result；把 unknown 当成功。

### 8. 与 W1-A durable 屏障对齐

| 屏障（09） | 最少 Event |
| --- | --- |
| 用户输入后、Model 前 | user_message（+ turn_started 若新 turn） |
| 助手/control 接受后 | model_message / model_control / model_yield |
| 副作用前 | operation_intent + 所需 approval/permission |
| 工具结果后、再采样前 | operation_result + tool_result |
| compaction 发布前 | compaction + model_view_published |
| review 生效前 | action_review / termination_review |
| turn 收口 | turn_ended(outcome) |

存储失败 → 停该 Context 新请求/副作用，报告最后 durable 水位。

### 9. 打开 / 恢复算法（摘要）

1. 解析路径 → 逻辑路径 → hash（D-059）。  
2. 检查 lock → 若他方持有则拒正文。  
3. 识别正式 generation（忽略 tmp/prev）。  
4. 流式解析 Header + Facts；校验 schemaVersion、id 单调、tool 配对。  
5. 重建 ModelView：manifest 与 fact range 不一致则 **丢弃 view 从 Facts 重建**。  
6. 无 result 的 intent → 标记 unknown，阻断自动继续副作用。  
7. Session 选择与本机 INI mapping；Key 仅来自 INI。

### 10. 新建 Context（首条 main）

1. 内存 draft（可含 model/prompt/cautious）。  
2. 分配 `Untitled Conversation [XXXX]`，no-replace 目标路径。  
3. WriteTemp 完整 XML：Header + Session + user_message + …  
4. Publish 成功后才允许 Model request。  
5. 失败：保留 draft 可见，无半个 Catalog 项。

### 11. HardLimit（D-063）

触顶：拒扩大 Facts 的 publish；可只读/export；提示新开对话 + 接盘 Prompt；不自动删史、不 WAL。

### 12. Export（跨工具主路径）

Markdown（或 registry 等价）从 Facts 投影；**不** 声称与 XML 元素稳定兼容。Export 可截断大 tool 输出并标注。

### 13. 安全解析

- 禁止 DTD / external entity / XInclude 外取。  
- 深度、属性数、单文本节点、总字节 hard limit（数字 TP）。  
- 未知 **可选** 扩展节点：yaca 可读时可保留 round-trip 或拒绝 — v0.1 推荐 **未知必选结构 → 拒绝打开写**；纯未知可选 audit 节点可忽略不写回（实现选更严：打开只读 + self-test）。

### 14. W1-C 完成定义

- [x] 控制物命名与忽略规则  
- [x] 逻辑文档骨架与局部 id  
- [x] Event 类型目录与屏障对齐  
- [x] 提交状态机与崩溃真值表  
- [x] 打开/新建/hardlimit/export 边界  
- [x] RNG 结构 schema + Lua event payload/cross-relation schema + minimal XML fixture
- [ ] 平台 replace/lock 原语证明（TP-008/011）  
- [ ] 大小/延迟 hard 数字（TP-009）  
- [x] AR-P0-10 规格侧勾选；gate 仍等待目标平台 proof

### 15. Wave 1 收束

| 包 | 文档 |
| --- | --- |
| W1-A | `09-agent-session.md` |
| W1-B | `05-configuration.md` catalog |
| W1-C | 本节 |

建议下一波：**W2-A action registry 草稿**（汇总 D-054/065/066 与 CLI 长名），并并行写 **TP-003/008/006** proof plan 提纲。

## 后续讨论顺序

1. Windows/Linux 路径规范化、文件名编码、长路径与碰撞。
2. “完整接盘信息”、model-view manifest、局部 ID、日志信息和会话参数元数据的 XML schema 与上限。
3. 已确认完整重写协议的提交点、锁/temp/previous-valid 真值表、目标平台原语与崩溃/副作用故障测试。
4. 事实历史、模型视图、压缩和导出的关系。
5. 敏感内容、保留、配额和永久删除。
6. 版本迁移、导入导出与损坏修复。

## 当前讨论入口

D-023 已解决外部身份问题，D-024 已确认统一 Resolver，D-053 已解决持久化路线和原位移交方式。W1-C 已给出内部事件目录与提交/崩溃表。下一步：机器 schema 文件、TP-008/009/011，以及 W2 action registry。
