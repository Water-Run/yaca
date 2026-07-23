# 架构实施就绪门禁

更新日期：2026-07-18

状态：审计基线；当前尚未达到实施计划就绪。本文只定义怎样判断“可以开始编写完整实施计划”，不把任何候选方案提升为已确认决定。

## 目的

yaca 已经有大范围设计题库、项目级决定和各子系统候选文档，但三者承担的责任不同。题目数量多、推荐写得详细或某项技术做过一次 smoke test，都不能单独证明程序已经可以直接实施。

本文建立统一 readiness gate，用来回答四个问题：

1. 项目负责人明天回复后，哪些产品行为已经真正确定？
2. 哪些内容不应继续让项目负责人选择，而应由技术设计和目标平台证据证明？
3. 哪些权威工件缺失时，即使所有问题都回复过，仍不能编写可靠的实施计划？
4. 怎样从需求、决定、规格、测试一直追踪到正式发布证据？

本文不是新的产品规格，也不替代 [`DECISIONS.md`](DECISIONS.md) 或各子系统最终规格。

## 四类文档不能混为一谈

### 题库：发现和解释选择

[`QUESTIONS.md`](QUESTIONS.md) 和 [`DESIGN-CHECKLIST.md`](DESIGN-CHECKLIST.md) 用于发现遗漏、解释取舍和组织决策依赖。

- `方案` 和 `推荐` 都只是讨论材料。
- 标记为“部分”“待决”或只有推荐、没有项目负责人明确回复的条目，一律不算决定。
- 一项问题被回复，只能证明相应选择已经获得输入；还要检查回复是否存在歧义、是否改变其他题目前提，以及是否已归档。
- 当前 354 个 checklist ID 是覆盖主题，不自动等于 354 份实现契约；当前 `AQ-001` 至 `AQ-373` 是原子选择，也不自动等于接口、状态机或测试规格。编号数量以后再变化时仍以两份题库的实际唯一 ID 为准，不在本文复制另一套静态清单。

### 决策：记录项目负责人真正确认的产品边界

[`DECISIONS.md`](DECISIONS.md) 是项目级已确认结论的权威日志。

- 决定必须能追溯到项目负责人的明确回复。
- 若新回复修订旧决定，旧决定必须标明被谁取代，不能让实现者自行选择版本。
- 决定回答“产品应当怎样表现或承诺什么”，通常不负责列出全部字段、事件、错误和平台原语。
- 尚未归档的回复不能仅凭讨论文档中的“用户选择”字样成为正式契约。

### 实现规格：把决定变成无须猜测的系统契约

每个子系统最终需要一份去除被否决分支的权威规格。它至少要定义：

- 职责、输入、输出和依赖；
- 状态、事件、ID、数据所有者和 durable 点；
- 正常流程、取消、失败、部分成功和恢复；
- 资源上限、安全边界和旧平台降级；
- 配置字段、CLI/TUI 投影和错误映射；
- 可以执行的验收条件及其 fixture。

候选子系统文档当前仍包含方案比较、推荐和待讨论项；在它们被规范化为已确认规格前，不能让实施者从多个候选中任选。

### 实施计划：只拆解已经确定的规格

实施计划回答文件、任务、顺序、测试和提交边界，不负责在编码途中重新发明产品语义。若计划项仍写着“选择一种”“视情况决定”“以后确定”或要求开发者从两个不兼容方案中任选，说明设计门禁尚未通过。

```text
question/checklist
        -> explicit owner reply
        -> DECISIONS entry
        -> accepted subsystem specification
        -> executable acceptance contract
        -> implementation plan
        -> test and release evidence
```

## 责任类型

下文使用三种责任标记：

| 标记 | 责任 | 例子 |
| --- | --- | --- |
| `O` | 项目负责人决定 | 产品是否提供自动 undo、portable 数据放在哪里、旁问是否并发 |
| `T` | 技术设计与验证 | XP 进程取消 ABI、XML 原子提交证明、DLL 搜索顺序、性能基准 |
| `J` | 联合责任 | 项目负责人先确认可接受的保证/降级，技术侧再证明方案能够兑现 |

技术事实不能用投票替代。例如“完整 XML 后追加元素仍是合法 XML”不是产品偏好，而是格式事实；正确流程是技术侧给出可行方案、证据和真实取舍，再由项目负责人确认产品承诺。反过来，是否承诺自动撤销或是否允许 active WAL 属于会改变产品和数据面的决定，不能由实现者暗定。

## P0 readiness gates

P0 gate 会同时改变多个子系统或决定能否安全恢复。编写全程序实施计划前，所有 P0 gate 都必须通过。

### AR-P0-01 产品闭环、非目标和发行形态

当前状态：未通过；平台/架构与独立 zip 已确认，但安装、升级、卸载和完整 v0.1 能力边界仍未收口。

- **阻塞原因**：一个平台 zip 并不自动说明它是解压即运行的便携包、安装脚本输入还是 luainstaller 单文件的外层包装。`__yaca__` 若邻接程序目录，升级覆盖、多副本和卸载的数据语义会完全不同。v0.1 的 MCP、自定义工具、插件、hook、skill 和子 Agent 目前只有“保持简单”的方向，尚需把支持、窄语义接缝与排除逐项冻结，避免空 loader/配置使产品表面和实际边界不一致。
- **权威工件**：产品闭环说明；v0.1 支持/排除矩阵；扩展关闭/重开条件；安装→首次配置→新建/恢复→退出→升级→降级→卸载状态表。
- **通过证据**：每条用户旅程有唯一结果；被排除能力在 help、配置、loader、tool registry、公开 Lua API 和 zip 中都没有可触发空壳；README 不再把候选或未实现能力写成现状；不存在“zip 已确认，所以 portable 也已确认”一类推断。
- **责任**：`O` 决定产品形态和数据保留；`T` 验证各目标平台能够实现。
- **主要来源**：`PROD-01`、`PROD-04`、`PROD-11`、`PROD-12`、`EXT-01` 至 `EXT-03`、`REL-01` 至 `REL-03`、`AQ-044`、`AQ-215` 至 `AQ-217`、`AQ-244`、`AQ-373`。

### AR-P0-02 AgentLoop 的 terminal intent 和 typed outcome

当前状态：未通过；“正常完成由主模型主导”已确认，但模型怎样无歧义地表达完成、等待用户、部分完成或拒绝仍未定义。

- **阻塞原因**：provider 响应结束只证明一次生成结束；“没有工具调用”无法区分完成、澄清问题、拒答和部分结果。Runtime 又不能靠搜索自然语言猜测 typed outcome。typed `ask-user` 后的用户回复尚未冻结 turn/快照/预算边界，错误页上的“retry”也尚未区分安全 transport attempt、新 request/new turn 和绝不可重放的 accepted/unknown operation。
- **权威工件**：AgentLoop 状态机；主模型控制信号/envelope；`completed|waiting_user|partial|refused|cancelled|budget_exhausted|stuck|error` 枚举和转换表；turn/request/attempt/reply-to 因果表；manual action/retry registry；最终报告合成规则。
- **通过证据**：脚本化模型分别产生完成、提问、拒绝、部分结果、长度截断和无效控制信号时，trace 得到唯一且正确的 terminal outcome；等待数小时后回答 `ask-user` 仍按最终决定建立唯一新旧 turn 关系；每种 retry UI 动作都能从 trace 证明不会泛化重放副作用；`DoubleCheck` 开关不改变 Runtime 对取消/错误事实的诚实标记。
- **责任**：`O` 确认用户可感知语义；`T` 设计协议并证明 provider 映射可靠。
- **主要来源**：D-020、D-027、`MODEL-06`、`LOOP-03`、`LOOP-10`、`LOOP-22`、`LOOP-28`、`LOOP-29`、`AQ-019` 至 `AQ-023`、`AQ-099` 至 `AQ-110`、`AQ-251` 至 `AQ-259`、`AQ-363`、`AQ-364`。

### AR-P0-03 Model/Provider canonical protocol

当前状态：未通过；一个 Model 是完整连接实例和 streaming 三态已有方向，v0.1 wire profile 尚未确认。

- **阻塞原因**：`OpenAI-compatible` 不是足够精确的协议规格。角色、工具调用 delta、同一响应中的文本和工具、重复/缺失 call ID、refusal/content filter、usage、HTTP error 与断流都可能不同。
- **权威工件**：内部 `ModelRequest`、`ModelEvent`、`ModelResult`、`ModelError` schema；v0.1 provider profile；capability/self-test 契约；六个核心 purpose 与 PJ-12 B 条件 `context-name` 的权限/数据表；每 Model 调度/冷却与 aggregate budget 账本。
- **通过证据**：规范录制 fixture 覆盖流式/非流式、工具、文本+工具、畸形 JSON/SSE、截断、拒答、超限、重试和取消；单并发 Model、main/side/review 竞争、最小间隔和 `Retry-After` 冷却均不会超发或绕过总账；每项都映射为稳定内部事件。
- **责任**：`O` 决定正式支持哪些协议和降级；`T` 冻结 wire contract 与 conformance fixtures。
- **主要来源**：`MODEL-01` 至 `MODEL-12`、`MODEL-14`、`MODEL-15`、`AQ-018`、`AQ-081`、`AQ-091`、`AQ-099`、`AQ-101`、`AQ-102`、`AQ-106`、`AQ-138`、`AQ-139`、`AQ-218` 至 `AQ-222`、`AQ-259`、`AQ-359`、`AQ-362`。

### AR-P0-04 XP/CentOS 事件泵与可取消 I/O

当前状态：未通过；单线程领域状态机是候选，实际 I/O multiplex 机制未选择和证明。

- **阻塞原因**：Lua 协程不会把阻塞的 console、curl pipe、stdout/stderr 或进程等待自动变成可取消事件。没有共同端口就无法同时兑现流式响应、忙时输入、Esc、中断、工具输出和关闭期限；系统 suspend/resume 后旧连接、lease、deadline 与 workspace 也不能被当作仍连续有效。
- **权威工件**：`start/poll/cancel/join/close` 异步端口 ABI；Windows/Linux adapter 能力矩阵；suspend/resume 检测与重新验证表；事件排序、背压、关闭和 helper 崩溃协议；最小技术验证计划。
- **通过证据**：XP SP3 x86 与 CentOS 7 x86_64 上，模型流、console 输入、双输出管道和进程退出可以并行推进；取消在规定期限内可见且不会丢失已到达核心的事件；在 sampling/tool/approval/commit 时休眠再恢复不会自动重放不确定请求或副作用，并给出最终规格要求的 typed 收口。
- **责任**：`T` 为主；若最低平台只能提供明显降级，由 `O` 确认是否接受。
- **主要来源**：`RUNTIME-01`、`RUNTIME-02`、`RUNTIME-06`、`PROC-01` 至 `PROC-07`、`NET-09`、`CONC-01`、`CONC-02`、`AQ-223`、`AQ-239`、`AQ-245`、`AQ-250`、`AQ-270`、`AQ-315`。

### AR-P0-05 TUI full-duplex 输入与确定性交互

当前状态：未通过；固定快捷键意图已给出，旧终端后备和异步输出期间的输入完整性仍未闭环。

- **阻塞原因**：在 cooked/canonical 输入中，模型或工具异步输出可能穿过用户未提交的输入行；renderer 看不到 OS 正在编辑的缓冲。快捷键不可识别时还必须保持 queue/steer/side/cancel 的领域语义。
- **权威工件**：输入状态机；async output 与 line editing 协议；快捷键→文本后备映射；每个 Agent 状态下 Esc/EOF/Ctrl+C/普通输入的动作表；ASCII golden transcripts。
- **通过证据**：XP console、普通 POSIX TTY、`TERM=dumb`、SSH PTY 和重定向场景中，用户输入不丢失、不被输出污染；后备入口产生相同领域事件和默认安全结果。
- **责任**：`O` 决定可接受体验；`T` 证明平台行为和渲染等价性。
- **主要来源**：`TUI-01` 至 `TUI-19`、`TUI-21` 至 `TUI-29`、`AQ-009` 至 `AQ-015`、`AQ-066` 至 `AQ-090`、`AQ-231` 至 `AQ-233`、`AQ-264`、`AQ-265`、`AQ-299`、`AQ-331` 至 `AQ-340`、`AQ-365`、`AQ-366`。

### AR-P0-06 工具集、raw shell 与 Permission 能力矩阵

当前状态：未通过；raw shell 方向已给出，但 `Execute` 与 Read/Write/Delete/Network/OutsideWorkspace 的关系没有权威定义。

- **阻塞原因**：若 shell 只映射 `Execute`，其他细粒度权限无法约束 shell。若仍宣称能从任意 shell 文本精确识别副作用，又会制造不存在的 sandbox 保证。模型 raw `exec` 的 stdin、命令物理传输上限和自动 Git 只读 adapter 是否会启动外部 helper 也尚未形成正式工具边界；非 Agent 管理动作不能靠复用历史 tool approval 获得授权。
- **权威工件**：首版 tool registry；每个工具的参数/result schema、版本、capability、副作用、stdin、可取消性和输出上限；raw command length/encoding contract；`tool × capability × Permission state` 矩阵；provider 网络与工具网络分界；Git adapter/系统 Git 使用范围；Agent approval 与 `ManagementMutation` 的独立快照 schema。
- **通过证据**：Readonly、Std 和其他用户定义 profile 对每个直接工具和 shell 的结果可由表格机械推导；shell 明确展示其宽权限事实且子进程不能偷取 TUI 输入；超长/不可编码命令不会被 Runtime 静默拆分；所谓只读 Git 不会绕过 Shell 启动 pager/external diff/textconv；管理动作不继承 Agent approval；LLM/DoubleCheck 只能追加限制，不能授予 Runtime 拒绝的动作。
- **责任**：`O` 确认安全体验和预设含义；`T` 定义确定性求值和测试。
- **主要来源**：`ARCH-05`、`PROC-11`、`PROC-12`、`TOOL-*`、`SAFE-*`、`THREAT-*`、`AQ-033` 至 `AQ-040`、`AQ-111` 至 `AQ-130`、`AQ-149`、`AQ-150`、`AQ-224` 至 `AQ-226`、`AQ-249`、`AQ-367`、`AQ-369`、`AQ-371`。

### AR-P0-07 改动归属、审阅和 undo 范围

当前状态：未通过；19 号文档的强 preimage/undo 只是候选，没有项目负责人确认。

- **阻塞原因**：完整 preimage 会显著改变 XML 体积、秘密复制、配额、导出和崩溃提交协议；外部 checkpoint 又改变“长期只有 INI/XML”和单 XML 接盘承诺。raw shell 的副作用也无法获得同等撤销保证。
- **权威工件**：v0.1 change guarantee；结构化写入新鲜度/原子替换协议；Agent 改动与用户既有改动的归属规则；若支持 undo，则还需 preimage 存储、配额、秘密、补偿与冲突规格。
- **通过证据**：项目负责人明确选择“仅防覆盖+审阅”或“强 undo”范围；Git/非 Git、已有脏改动、多文件部分成功和 shell 未知副作用都有可执行 fixture。
- **责任**：`O` 决定是否承诺 undo；`T` 证明选定保证可在目标平台兑现。
- **主要来源**：`CHANGE-01` 至 `CHANGE-05`、`TOOL-02`、`TOOL-05`、`TOOL-09`、`TOOL-15`、19 号子系统。

### AR-P0-08 数据分类、秘密和导入信任

当前状态：未通过；明文 Key 位置已有方向，跨模型/持久化/导入/日志矩阵尚未形成。

- **阻塞原因**：外部或导入 XML 可以携带 ContextPrompt、Permission 名、`DoubleCheck=false` 和历史 approval；digest 只能检测意外损坏，不能认证来源。Key 交给 curl 的具体秘密传递协议、明文 HTTP endpoint 的 secret 边界、配置 backup 中旧 Key，以及 Context 正文误含秘密后的 purge/redaction 承诺均尚未收口。
- **权威工件**：[数据分类候选](DATA-CLASSIFICATION-CANDIDATE.md) 收口后的矩阵；secret lifecycle；HTTP/HTTPS + AuthMode/Key policy；curl/header/临时文件传递协议；配置 known-copy 清理规则；Context purge/redaction/sanitized-export 契约；XML 导入信任规则；历史事实与当前授权的分离规则；支持包/导出预览规则。
- **通过证据**：每类数据对主模型、复核模型、压缩模型、TUI、XML、日志、明文/加密传输和导出的默认处理都有唯一答案；最终禁止的结构化秘密不会经 HTTP 发出；导入的历史审批永远不能在目标机自动授予当前动作；Key 不出现在 argv、XML、普通日志或错误；清理 UI 能准确列出已处理的 yaca 已知副本、已发送内容和无法保证的物理残留。
- **责任**：`O` 确认隐私承诺和确认点；`T` 完成 threat tests 和泄漏扫描。
- **主要来源**：`PROD-08`、`CFG-04`、`NET-03`、`NET-13`、`PROC-10`、`SAFE-09`、`CTX-06`、`CTX-28`、`DIAG-03`、`AQ-017`、`AQ-040`、`AQ-137`、`AQ-159`、`AQ-165` 至 `AQ-168`、`AQ-180`、`AQ-220`、`AQ-237`、`AQ-238`、`AQ-349`、`AQ-368`。

### AR-P0-09 完整 typed 配置 schema 与 bootstrap

当前状态：未通过；当前配置文档明确只是最小讨论骨架。

- **阻塞原因**：正常启动要求完整校验，但配置缺失/损坏时 model/config REPL 和 self-test 又需要最小 bootstrap。字段、默认、INI/XML 合并、顺序语义、未知字段、手工编辑、并发外改和秘密输入尚未成为一个契约；运行中外部修改何时 reload，以及 reset/delete/migration 是否共用安全管理事务也未决定。
- **权威工件**：唯一 typed schema；逐字段 catalog；INI grammar；XML 覆盖白名单；跨字段约束；bootstrap command allowlist；外部 config digest/reload/version contract；`ManagementMutation`；配置编辑事务和迁移协议。
- **通过证据**：默认模板、parser、validator、help、REPL、脱敏和 self-test 都从同一 schema 生成或由测试证明同步；外部半写/无效版本不会穿过 turn 快照，Endpoint/Key/Permission 生效点可由事件追踪；同一 reset/delete/migration 经 CLI/REPL 得到相同 target/impact/stale-check/default-cancel/result；无效配置只允许经过确认的管理入口，绝不进入 AgentLoop。
- **责任**：`O` 确认字段行为和默认；`T` 定义语法、迁移、原子保存和 contract tests。
- **主要来源**：`ARCH-05`、`CFG-01` 至 `CFG-24`、`FMT-02`、`FMT-04`、`AQ-012` 至 `AQ-018`、`AQ-077` 至 `AQ-085`、`AQ-131` 至 `AQ-160`、`AQ-200`、`AQ-201`、`AQ-289` 至 `AQ-291`、`AQ-361`、`AQ-369`。

### AR-P0-10 Context XML schema、durability 与恢复

当前状态：未通过；单 XML 总体形态已确认，安全提交协议和性能可行性未解决。

- **阻塞原因**：每个 canonical/durable 事件都整文件重写会形成 O(n²) I/O；在闭合 XML 根后原地追加元素又不是合法 well-formed XML。active WAL 可以提高性能，但会改变单 XML 唯一事实源承诺。
- **权威工件**：公开 XML schema/namespace；event/relationship/ID schema；确定性 writer；提交、flush、lock、temp、replace、恢复和外部读取状态机；文件大小/延迟门槛；损坏和迁移协议。
- **通过证据**：正常、每个崩溃切点、磁盘满、替换失败、第二写者和外部修改都有预期旧版/新版/只读损坏结果；XP x86 长会话基准满足冻结预算，或项目负责人明确接受经证据说明的限制。
- **责任**：`J`。`O` 决定是否允许 WAL/sidecar 或接受硬上限；`T` 证明格式、原子性和性能。
- **主要来源**：D-022、D-023、`FMT-01`、`CTX-01` 至 `CTX-18`、`CTX-21` 至 `CTX-28`、`AQ-041` 至 `AQ-043`、`AQ-161` 至 `AQ-180`、`AQ-227`、`AQ-228`、`AQ-303` 至 `AQ-308`、`AQ-368`。

### AR-P0-11 Context 路径、索引、导入和生命周期

当前状态：未通过；Resolver 核心顺序已确认，平台路径映射和所有修改生命周期仍待决。

- **阻塞原因**：盘符、UNC、POSIX 根、Unicode/case、8.3、symlink/junction、非法名称和跨机映射会同时改变文件地址、hash、安全边界与浏览器结果。active Context 的 switch/archive/delete 还没有状态语义；Context/config 数据根与 workspace 是否允许 FAT/SMB/NFS/可移动盘也不能共用一个模糊“可写”承诺。运行中 workspace 被删除、卸载或断线会使旧 cwd、审批和 Prompt 快照同时失效。
- **权威工件**：`LogicalPathCodec` 规范；路径 hash 规范和 vectors；Context lifecycle；数据根/workspace 文件系统支持矩阵；Resolver/browser result schema；rename/delete/archive/import/rebind 状态机；special file/link policy。
- **通过证据**：同一规范输入跨平台产生相同逻辑路径/hash；目录枚举顺序不影响解析；每条 lock/no-replace/flush 保证绑定具体文件系统证据；数据根不满足最终 durability 等级时拒绝，workspace 能力不足时 direct mutation fail-closed；链接逃逸、同名、hash collision、损坏项、不可读环、外部移动、active delete 和中途卸载均安全失败或得到已确认结果。
- **责任**：`O` 确认用户流程；`T` 冻结路径算法并做跨平台 fixture。
- **主要来源**：D-022 至 D-024、`PROD-16`、`PLAT-01`、`PLAT-13`、`INDEX-01` 至 `INDEX-11`、`INDEX-13` 至 `INDEX-16`、`AQ-083`、`AQ-117`、`AQ-169`、`AQ-170`、`AQ-173` 至 `AQ-178`、`AQ-189`、`AQ-199`、`AQ-212` 至 `AQ-216`、`AQ-237`、`AQ-370`、`AQ-372`。

### AR-P0-12 压缩后的模型视图

当前状态：未通过；完整历史保留方向清楚，摘要 schema 和可重建算法尚未确认。

- **阻塞原因**：只说“事实历史+摘要+最近窗口”不足以决定每个工具对、Prompt、用户决定、未知副作用和模型切换怎样保留，也无法处理恢复后历史已超过当前 Model 窗口，或单个不可拆原子组自身已经大于窗口的情况。
- **权威工件**：model-view builder；结构化 compaction schema；必保槽位；来源 event range/digest；触发、取消、失败、无收益、oversized-atom 和用户纠正规则；模型切换预检。
- **通过证据**：从同一事实 XML 可确定性重建相同视图；call/result、approval/action、Prompt 和未完成事项不会被拆散；单个超大原子组在请求前得到已确认的 typed 结果且事实不丢；压缩失败不改变旧视图；更小/更大 Model 切换场景有固定结果。
- **责任**：`O` 确认提示/自动化边界；`T` 设计摘要协议和回归 fixture。
- **主要来源**：`COMP-01` 至 `COMP-10`、`AQ-061` 至 `AQ-065`、`AQ-142`、`AQ-156`、`AQ-179`、`AQ-240` 至 `AQ-243`、`AQ-298`、`AQ-309` 至 `AQ-311`、`AQ-352`。

### AR-P0-13 CLI、点命令和会话命令状态表

当前状态：未通过；主入口已确认，完整 grammar、唯一简称和各状态可执行性未冻结。

- **阻塞原因**：上下文切换、模型/权限/Prompt 修改、压缩、archive、delete 和 exit 在 busy/approval/tool/side/recovery/queued 状态中的行为会影响 AgentLoop 和 durable 事实，不能由各前端分别猜测。
- **权威工件**：CLI grammar；command registry；长名/唯一简称/兼容别名；`command × AgentState` 表；`ManagementMutation` 投影规则；stdout/stderr/exit-class/machine-output schema；点命令与快捷键领域动作映射。
- **通过证据**：命令冲突静态检查为零；同一动作经 CLI、TUI REPL 和浏览器得到相同 typed result；reset/delete/purge/import/migrate 不因入口不同改变目标、影响预览、stale-check 或默认取消；非 TTY 缺参或需确认时 fail-closed，不会吞 stdin 或弹隐藏菜单。
- **责任**：`O` 确认命名和交互；`T` 生成 parser/help 和 golden tests。
- **主要来源**：`ARCH-05`、`CLI-00` 至 `CLI-15`、`TUI-10`、`LOOP-10`、`AQ-014`、`AQ-024`、`AQ-031`、`AQ-076`、`AQ-098`、`AQ-181`、`AQ-182`、`AQ-214`、`AQ-229`、`AQ-247`、`AQ-248`、`AQ-301`、`AQ-326`、`AQ-327`、`AQ-369`。

### AR-P0-14 安全模块/工具加载与文件目标复核

当前状态：未通过；候选要求存在，但还没有权威加载契约。

- **阻塞原因**：yaca 以陌生工作区为 cwd；若 `package.path/cpath`、DLL 搜索或内部工具解析使用 CWD/PATH，仓库中的同名 Lua/C 模块、DLL 或 curl 可以在权限系统之前执行。即使 executable 路径固定，`.curlrc`、shell AutoRun/rc、Git pager/external diff/textconv 等 ambient config 仍可能改变内部动作或启动外部 helper。文件工具也不能只做字符串前缀检查或审批前检查一次。
- **权威工件**：内部资源绝对路径解析规则；Lua/C module allowlist；DLL 搜索约束；内部进程 allowlisted environment/ambient-config disable contract；tool manifest；普通文件/目录/symlink/junction/hardlink/device/FIFO/socket policy；open-then-verify 和 no-replace 契约。
- **通过证据**：在 cwd/PATH 放置恶意同名模块、DLL 和工具不会被内部加载；在 home/workspace/环境放置 curl/shell/Git 配置不会改变内部基础设施动作或启动未列 helper；审批后替换链接或文件身份会产生 `TargetChanged`，而不是操作新目标。
- **责任**：`T`；若某旧平台无法提供等价安全性，由 `O` 决定是否缩小支持能力。
- **主要来源**：`RUNTIME-04`、`THREAT-03`、`PROC-08`、`PROC-09`、`PROC-13`、`PLAT-04`、`SAFE-06`、`TOOL-04`、`AQ-118`、`AQ-213`、`AQ-225`、`AQ-250`、`AQ-267`。

### AR-P0-15 本地 ID、锁和崩溃收口

当前状态：未通过；没有永久 ContextId 已确认，但局部 ID/序号、lease 和 stale recovery 尚未形成一个协议。

- **阻塞原因**：turn、request、attempt、side、tool call、operation、approval 和 compaction 都依赖稳定关联。若崩溃后复用 ID 或信任 provider ID，会错误配对结果或重放副作用。仅按时间删除 stale lock 也会产生双写者。
- **权威工件**：identity/namespace table；局部序号分配与持久化规则；provider ID 保存/映射；request-attempt 关系；write lease/commit mutex 取得顺序；stale lock 复核和恢复协议。
- **通过证据**：在每个分配/提交切点杀进程后，恢复不会复用已 durable ID；重复/缺失 provider call ID 不破坏本地配对；两个进程无法同时成为 writer。
- **责任**：`T`；第二写者/只读/等待体验由 `O` 确认。
- **主要来源**：D-023、`CTX-07`、`CTX-09`、`CTX-16`、`CONC-03`、`AQ-095`、`AQ-103`、`AQ-130`、`AQ-166`、`AQ-171`、`AQ-174`、`AQ-221`、`AQ-225`、`AQ-234`。

### AR-P0-16 发布可行性与真实平台证据

当前状态：阻塞。

- **阻塞原因一：luainstaller Win32**。相邻 `../luainstaller` 当前 native profile 明确拒绝 Windows x86；因此“XP SP3 x86 + Lua 5.5 + 必须用 luainstaller”尚不能同时兑现。参考 [`platform.lua`](../../luainstaller/src/platform.lua) 和 `AQ-211`。
- **阻塞原因二：现有 Linux bin ABI**。当前 `bin/` 中 Linux executables 经 `file/readelf` 检查为 ELF32/i386，而正式 Linux 目标是 x86_64；它们只能作为来源线索，不能进入最终包。Windows PE32 资源也仍需 XP import/CRT/TLS 与来源验证，架构正确不等于兼容已证明。
- **阻塞原因三：支持矩阵尚未到物理层**。Win32 x86 尚未确定最低 CPU ISA；Context 数据根与 workspace 的正式文件系统等级、release signature 或明确 unsigned policy 也未冻结。仅写“支持 XP”或“提供 hash”不能代替这些承诺。
- **权威工件**：经授权的 luainstaller Win32/XP 前置项目规格；每平台 release manifest；组件来源/hash/license/架构/ISA；编译器/CRT/API/CPU baseline；数据根/workspace 文件系统支持矩阵；签名或 unsigned release policy；构建、装配和真实平台验收流程。
- **通过证据**：同一 Windows x86 候选产物在符合最终 CPU 下限的真实旧 CPU 环境及 XP 至 11 完成确认的完整测试；Linux x86_64 候选在 CentOS 7 基线和最终声明发行版通过；正式支持的数据根文件系统通过 lock/no-replace/flush/replace/断电证据，workspace 降级不冒充 Context durability；包在清空系统 Lua/PATH 帮助后仍完整运行；PE instructions/imports、ELF header 与 manifest 一致；真实性工件与最终 policy 一致。
- **责任**：`O` 授权兄弟仓库工作并确认发布范围；`T` 完成构建链、ABI 审计和真实平台证据。
- **主要来源**：D-004、D-007 至 D-012、D-015、D-016、`PLAT-13`、`REL-04` 至 `REL-14`、`SUPPLY-*`、`AQ-044`、`AQ-187`、`AQ-204` 至 `AQ-211`、`AQ-341`、`AQ-342`、`AQ-370`。

## P1 readiness gates

P1 gate 不一定改变全局架构，但会阻断对应子系统的可靠计划。由于项目负责人要求先完整规划再逐系统开发，编写全程序实施计划前也应全部关闭；若只为一个已隔离子系统写局部计划，至少关闭该系统及其上游 P1。

### AR-P1-01 精确格式语义与库边界

- **阻塞原因**：JSON 数字/重复 key/无效 UTF-8、INI 重复 section/key/注释/多行/往返仍只有 checklist 主题；XML parser 候选的 Lua 5.5/目标平台证据也不完整。
- **权威工件**：JSON、INI、XML 安全子集；parser/writer 接口；资源上限；依赖版本/hash/license；malformed corpus。
- **通过证据**：跨平台 golden vectors、fuzz/malformed fixtures、确定性 round-trip 和资源上限测试。
- **责任**：`T`；会改变手工编辑体验的部分由 `O` 确认。
- **主要来源**：`FMT-01` 至 `FMT-07`、`CTX-25`、`AQ-161`、`AQ-171`、`AQ-185` 至 `AQ-188`、`AQ-200`、`AQ-287`、`AQ-288`、`AQ-323`；技术证明 `TP-010`、`TP-019`、`TP-021`。

### AR-P1-02 网络细节和 secret-safe curl adapter

- **阻塞原因**：redirect、proxy/NO_PROXY、CA、TLS、明文 HTTP、Retry-After、content encoding、header/SSE limits、取消和 secret 传递必须组成一套协议，而不能分散实现。每 Model scheduler 还必须让六个核心 purpose 与 PJ-12 B 条件 `context-name` 共用并发、间隔和冷却，同时按各自 turn/Context/self-test/lifecycle 账本归集；内部 curl 的 ambient config 不能另行改写这些规则。
- **权威工件**：HTTP request/attempt state machine；curl argv/stdin/temp 与 ambient-config isolation contract；HTTP/HTTPS + AuthMode/Key matrix；retry matrix；per-Model scheduler/budget ledger；代理和 CA precedence；redirect/key policy。
- **通过证据**：本地可控 server/proxy fixtures 覆盖 redirect、HTTP loopback/LAN/public、认证、断流、429/Retry-After、并发 purpose、超大 header/event、慢消费者和取消；恶意 `.curlrc`/环境不改变实际 request；扫描 argv/temp/log 泄漏。
- **责任**：`T`，代理/不安全 TLS 等用户可见能力由 `O` 决定。
- **主要来源**：`PROC-13`、`NET-01` 至 `NET-13`、`MODEL-15`、`AQ-137`、`AQ-140`、`AQ-141`、`AQ-145`、`AQ-146`、`AQ-197`、`AQ-198`、`AQ-219`、`AQ-220`、`AQ-245`、`AQ-277`、`AQ-278`、`AQ-284`、`AQ-321`、`AQ-322`、`AQ-348`、`AQ-362`；技术证明 `TP-006`、`TP-007`、`TP-022`。

### AR-P1-03 进程和 shell dialect

- **阻塞原因**：raw command 仍需固定 Windows `cmd.exe`、Linux `/bin/sh` 或其他明确 dialect；argv 执行、stdin、环境/ambient config、cwd、stdout/stderr、encoding、命令物理长度、超时和进程树结果不能依赖宿主偶然行为。
- **权威工件**：process port；shell invocation/quoting/stdin contract；raw command length/encoding result；内部进程与用户 raw shell 的环境/ambient-config 分离；output/cancel/result schema。
- **通过证据**：argument corpus、Unicode path、stdin 读取/交互提示、命令长度与不可表示字符、双管道满缓冲、spawn failure、timeout、descendant survival、suspend/resume 和 cwd 删除等 fixture；子进程不能偷取 TUI/审批输入。
- **责任**：`T`；是否支持交互/后台命令由 `O` 确认。
- **主要来源**：`PROC-01` 至 `PROC-13`、`AQ-119` 至 `AQ-128`、`AQ-266`、`AQ-267`、`AQ-367`、`AQ-371`、`AQ-372`；技术证明 `TP-003`、`TP-005`、`TP-029`。

### AR-P1-04 成本、token 和预算口径

- **阻塞原因**：费用上限已经出现在候选预算中，但 Model schema 没有价格、币种、缓存 token 计价或 provider cost 来源。未知价格时无法实施费用 hard limit。
- **权威工件**：usage normalization；token estimate 标记；是否支持 cost budget 的决定；若支持，价格快照 schema 和显示免责声明。
- **通过证据**：main/side/double-check/compaction/retry，以及条件 `context-name` 的 usage 不重复也不漏计；未知 usage/价格时不会伪造精确费用。
- **责任**：`O` 决定首版是否承诺费用上限；`T` 实现可信口径。
- **主要来源**：`MODEL-09`、`MODEL-15`、`LOOP-04`、`LOOP-27`、`AQ-028`、`AQ-097`、`AQ-100`、`AQ-153`、`AQ-196`、`AQ-283`、`AQ-359`、`AQ-362`；技术证明 `TP-017`、`TP-022`。

### AR-P1-05 Prompt 原文、计划模式和工作区指令范围

- **阻塞原因**：Prompt 权威链尚在第一项决策中；项目指令自动发现和计划模式也没有最终范围。若支持计划模式，需要定义它与 Readonly/Permission 的关系。
- **权威工件**：Prompt segment/priority spec；内置英文 Prompt 原文；ContextPrompt 命令和事件；工作区指令 source/scope；计划→执行转换或明确非目标。
- **通过证据**：冲突、Prompt 修改、恢复、压缩、模型切换、恶意仓库文本和计划转执行的 golden requests。
- **责任**：`O` 决定人格/来源/计划体验；`T` 固定装配顺序和安全标记。
- **主要来源**：`INSTR-01` 至 `INSTR-05`、`LOOP-18`、`LOOP-19`、`AQ-001` 至 `AQ-008`、`AQ-046` 至 `AQ-065`、`AQ-183`、`AQ-292` 至 `AQ-298`、`AQ-346`；技术证明 `TP-016`、`TP-025`。

### AR-P1-06 Context 配额、归档和保留

- **阻塞原因**：单 XML 大小、Context 数量、总容量、回收区保留、永久清除和磁盘不足时的行为没有完整策略；误贴 secret 后是整 Context purge、sanitized export 还是 redaction rewrite，以及 previous-valid/backup/temp 的 known-copy 处理也尚未确认。
- **权威工件**：quota/retention policy；archive/delete/restore/purge/redaction state machine；known-copy 与 best-effort/secure-erase 免责声明；显示与 self-test 规则。
- **通过证据**：边界前、恰好边界和超限 fixture；清理永不选择仍活动/锁定或未知状态文件；永久删除需要明确确认；secret canary 可验证最终承诺处理了哪些 yaca 已知 generation，而不会声称撤回 provider 内容或物理擦除存储介质。
- **责任**：`O` 决定默认保留；`T` 证明扫描和删除安全。
- **主要来源**：`CTX-11`、`CTX-12`、`CTX-28`、`INDEX-15`、`AQ-178`、`AQ-238`、`AQ-307`、`AQ-308`、`AQ-349`、`AQ-368`；技术证明 `TP-008`、`TP-009`、`TP-028`。

### AR-P1-07 错误目录、诊断和 self-test

- **阻塞原因**：typed error 仍未形成 registry；已经确认长期只持久化 INI/XML，但启动前 stderr、Context 内有界诊断、显式临时 support 输出和崩溃后恢复事实的精确分工仍未冻结；三阶段 self-test 的阻断地位也尚未冻结。
- **权威工件**：error ID/category registry；错误归属和去重表；stderr/Context XML/显式 support 输出分工（不含独立轮换日志或 `crash.log`）；self-test stage schema 和 release-gate 规则。
- **通过证据**：每类阻断错误都显示发生了什么、保存了什么、可能副作用和下一步；同一根因只产生一个主错误；LLM 语义检查不会替代确定性 hard gate。
- **责任**：长期文件边界服从 D-035/D-036；`O` 决定剩余错误 UX 与 XML 诊断保留，`T` 建立 registry、脱敏和故障测试。
- **主要来源**：`DIAG-01` 至 `DIAG-13`、`AQ-013`、`AQ-074`、`AQ-130`、`AQ-158`、`AQ-201` 至 `AQ-203`、`AQ-248`、`AQ-317` 至 `AQ-320`、`AQ-328`、`AQ-334`、`AQ-337`；技术证明 `TP-017`、`TP-026`、`TP-028`。

### AR-P1-08 性能与内存预算

- **阻塞原因**：大量地方写着“有界”，但未冻结冷启动、单 XML、目录扫描、队列、工具输出、按键反馈、取消和长会话的具体预算与超限行为。
- **权威工件**：最低参考机说明；小/中/压力 workload；每项软/硬预算；基准采集方法和回归容忍度。
- **通过证据**：XP x86 和 CentOS 7 的基准记录；达到硬限制时返回 typed limit error 或已确认降级，不以 OOM/卡死作为控制流。
- **责任**：`J`。`O` 确认可接受体验，`T` 量测和证明。
- **主要来源**：`PROD-10`、`PERF-01` 至 `PERF-03`、`CONC-02`、`CONC-04`、`TEST-09`、`AQ-194` 至 `AQ-196`、`AQ-205`、`AQ-228`、`AQ-239`、`AQ-245`、`AQ-305`、`AQ-343`、`AQ-345`、`AQ-352`、`AQ-359`、`AQ-362`；技术证明 `TP-009`、`TP-022`、`TP-023`、`TP-025`。

### AR-P1-09 精确名称、枚举和常量冻结

- **阻塞原因**：命令、REPL、工具、XML element/enum、error ID、颜色、超时、输出限额和预算数字一旦进入脚本/历史/XML就形成兼容面。
- **权威工件**：name/abbreviation registry；enum registry；默认常量表及依据；schema versioning policy。
- **通过证据**：自动唯一性检查；配置/help/Prompt/XML/tests 引用同一 registry；没有实现时临时起名的公共字段。
- **责任**：`O` 审阅用户可见命名；`T` 冻结机器字段和常量证据。
- **主要来源**：`CLI-01`、`CLI-10`、`TUI-10`、`TOOL-16`、`FMT-06`、`CFG-18`、`AQ-014`、`AQ-076`、`AQ-111`、`AQ-135`、`AQ-181` 至 `AQ-185`、`AQ-190`、`AQ-193`、`AQ-203`、`AQ-209`、`AQ-259`、`AQ-326`、`AQ-327`、`AQ-333`；技术证明 `TP-024`。

### AR-P1-10 第三方 reader 与公开 XML conformance

- **阻塞原因**：“信息足够接盘”不等于 Codex、CodeWhale 等天然理解自定义 XML；公开 reader 契约和第三方写入边界还需明确。
- **权威工件**：公开 schema；字段语义；最小/完整/中断/压缩/迁移样例；reader pseudocode；unknown extension 规则；read-only/write-support 声明。
- **通过证据**：独立 reference reader 在不知道 yaca 内部 Lua table 的情况下读取 fixtures 并重建相同会话视图；不支持字段不会被静默丢弃或误授权。
- **责任**：`O` 确认公开承诺；`T` 提供 conformance suite。
- **主要来源**：`CTX-05`、`CTX-15`、`CTX-25`、`AQ-041`、`AQ-042`、`AQ-161`、`AQ-180`、`AQ-185`、`AQ-186`、`AQ-210`、`AQ-237`、`AQ-306`、`AQ-349`；技术证明 `TP-010`、`TP-020`、`TP-025`。

### AR-P1-11 供应链、依赖更新和可复现装配

- **阻塞原因**：仓库现有 `bin/` 含未必进入发行的 sqlite3、jq、7za 等资源；每多一个 executable/DLL 都扩大 XP/Linux ABI、许可和漏洞维护面。
- **权威工件**：最小 allowlist、来源/hash/license、构建 recipe、SBOM、CA 更新流程、依赖漏洞响应和包内容拒绝规则。
- **通过证据**：未列组件使构建失败；所有 native 文件架构正确；从固定输入重建可解释相同产物；未使用资源不进入 zip。
- **责任**：`T`；正式包含哪些可选能力由 `O` 确认。
- **主要来源**：`REL-10`、`REL-12`、`REL-14`、`SUPPLY-01` 至 `SUPPLY-04`、`EXT-01` 至 `EXT-03`、`AQ-187`、`AQ-206` 至 `AQ-211`、`AQ-250`、`AQ-267`、`AQ-329`、`AQ-341`、`AQ-342`、`AQ-373`；技术证明 `TP-001`、`TP-002`、`TP-006`、`TP-007`、`TP-029`、`TP-030`。

### AR-P1-12 文档同步和状态诚实性

- **阻塞原因**：公开 README 当前把未实现安装、Release 和旧平台支持写成现状；短参数、配置模板和设计决定也存在漂移。
- **权威工件**：实现/已确认目标/候选状态标识；文档同步清单；由 registry/schema 生成或校验的 help、模板和示例。
- **通过证据**：中英文 README、help、config template、XML examples 和决定日志同批检查；不存在声明可运行但核心为空或发布链明确阻塞的表述。
- **责任**：`T` 维护同步证据，`O` 审核产品承诺。
- **主要来源**：`DOC-01` 至 `DOC-05`、`TEST-10`、`AQ-208` 至 `AQ-210`、`AQ-329`、`AQ-350`、`AQ-360`、`AQ-373`；技术证明 `TP-024`、`TP-030`。

## 全生命周期 readiness matrix

这张表用于防止只完成“正常聊天路径”就宣布架构就绪。每个阶段至少需要正常、取消/失败和恢复/清理三类证据。

| 生命周期阶段 | 必须通过的主要 gate | 权威规格 | 最低证据 |
| --- | --- | --- | --- |
| 下载/解压/安装 | P0-01、P0-14、P0-16、P1-11 | release manifest、安装状态表、load-path policy | 干净目标机无系统依赖启动；恶意 CWD/PATH 不劫持；产物 ABI 正确 |
| 首次启动/缺失配置 | P0-01、P0-09、P0-13、P1-07 | startup route、bootstrap allowlist、CLI grammar | 缺失/损坏/有效配置与 TTY/非 TTY 组合得到唯一结果 |
| 配置与 self-test | P0-03、P0-08、P0-09、P1-02、P1-07 | typed schema、Model profile、self-test state machine | 静态检查离线；联网/费用显式；Key 无泄漏 |
| 创建/恢复 Context | P0-10、P0-11、P0-15、P1-06 | XML schema、path codec、open/recovery protocol | 新建 no-replace；旧/坏/锁定/外部移动/缺依赖可解释 |
| 用户输入和主模型请求 | P0-02 至 P0-05、P0-08 | AgentLoop、Prompt、ModelEvent、TUI input | 输入先 durable；流式/取消/提问/拒答/截断 trace 正确 |
| 工具调用和副作用 | P0-06、P0-07、P0-14、P0-15、P1-03 | tool registry、permission matrix、operation protocol | 审批绑定确定动作；外改冲突；未知副作用不重放 |
| queue/steer/side/审批 | P0-02、P0-04、P0-05、P0-13、P0-15 | message/control schema、command-state table | 各自独立身份、取消、预算和恢复；不会污染主历史或自动授权 |
| 取消/退出/崩溃 | P0-04、P0-10、P0-15、P1-07 | close stack、durable points、recovery table | 每个状态故障注入；真实/合成结果配对；unknown 被保留 |
| 压缩/模型切换 | P0-03、P0-08、P0-10、P0-12、P1-04 | model-view/compaction schema、switch preflight | 完整事实不丢；Prompt/工具对保持；跨 endpoint 明确确认 |
| rename/archive/delete/import | P0-08、P0-10、P0-11、P0-13、P1-06、P1-10 | mutation/import state machine | no-replace、stale snapshot、碰撞、恶意 XML 和 active Context 场景 |
| 升级/迁移/降级 | P0-01、P0-09、P0-10、P0-16、P1-10 至 P1-12 | version policy、migration/rollback protocol | 原文件不破坏；新版对旧程序只读/拒绝明确；失败可回退 |
| 发布/维护 | P0-16、P1-08、P1-11、P1-12 | test matrix、SBOM、build recipe、support policy | 每个声明平台真实测试；证据关联源码/产物/配置 schema 版本 |

## requirement → spec → test → evidence 追踪

### 每条追踪记录的最小字段

```text
requirement_id       DESIGN-CHECKLIST ID 或已确认决定 ID
decision_id          对应 D-*；若无需 owner 决定，写 TECHNICAL
normative_spec       权威规格文件和稳定 anchor
contract             可执行的不变量/输入输出/失败结果
test_ids             正常、关键失败、恢复、平台测试
platform_scope       pure / windows-x86 / linux-x86_64 / all
evidence             最近通过产物、版本、hash 和运行环境
status               open / specified / tested / release-proven
```

### 追踪规则

1. 每个 P0 requirement 至少关联一个正常测试、一个关键失败测试和一个恢复测试；涉及平台能力时还必须有对应真实平台证据。
2. 每个公开配置字段、CLI 命令、XML 元素、工具和 error ID 必须追溯到一个规范行为，不能因旧模板存在就保留。
3. 一项测试“绿色”只有在确认它覆盖目标 contract 后才算证据；广泛端到端成功不能代替 durable、权限和数据损坏不变量。
4. 真实模型质量不能宽恕确定性状态机、权限、存储或工具配对失败。
5. 模拟平台不能替代 XP/CentOS 真实发行物验收；真实平台端到端也不能替代可定位的单元/契约测试。
6. 推荐、草案、未回复问题和未归档回复的 `status` 一律保持 `open`。
7. 若决定被修订，追踪记录必须指向新决定；旧测试只有在新契约下仍有效才可复用。

### 示例（只展示追踪形状，不宣告通过）

| Requirement | Decision | Normative spec | Tests | Evidence status |
| --- | --- | --- | --- | --- |
| `INDEX-02` | D-024 | 待生成 Context Resolver 规范 | ring priority、collision、unreadable ring、enumeration shuffle | 设计方向已确认，规格/测试证据缺失 |
| `CFG-17` | D-021、D-027 | 待生成会话覆盖 schema | inherit/on/off/reset、恢复、导入不降权 | 部分决定，未通过 |
| `REL-04` | 待决/AQ-211 | 待生成 luainstaller Win32 前置规格 | PE imports、XP launch、完整闭环 | 外部硬阻塞 |

## 当前已知外部阻塞

### luainstaller Windows x86/XP

当前 `../luainstaller` 明确拒绝 Windows x86。解除它不是在 yaca 文档中写一句“支持 XP”即可完成，需要：

1. 项目负责人明确授权修改兄弟仓库或选择另一路线；
2. 独立设计 Win32/x86 native profile、Lua 5.5 runtime、launcher、CRT/API baseline；
3. 为 luainstaller 自身建立生成/打包/错误/安全和 XP 测试；
4. yaca 再消费一个已经由证据证明的 luainstaller 版本。

在这项前置未解决前，可以继续完成设计、验证计划和经单独授权的可丢弃技术证明；仍不能开始产品实现，也不能把 Windows 发布计划标为可执行完成路径。任何技术证明进入正式实现前，仍需通过本文件的 readiness 与逐子系统实施计划。

### 当前 `bin/` ABI 与来源

当前 Linux `bin/` executable 是 ELF32/i386，而目标是 Linux x86_64。它们不能通过“在 x86_64 系统上偶尔能启动”获得发布资格。所有 Linux 工具必须换成目标 ABI 的受控构建，并在 CentOS 7 基线上验证。

当前 Windows executable/DLL 多为 PE32 x86，这只满足架构外观；仍需验证 XP 最低 API、CRT、TLS、签名/来源、依赖 DLL、命令行/Unicode 和许可证。UPX 或其他包装也必须进入来源和恶意软件误报评估，不能视为透明细节。

## 明天回复后的处理顺序

1. 把项目负责人的每条回复映射到准确 `AQ-*`/checklist ID；不扩写未表达的授权。
2. 标记明确确认、明确拒绝、部分确认和仍有歧义的边界。
3. 更新 `DECISIONS.md`，为修订建立明确取代关系。
4. 重新运行冲突审计：Prompt 权威、raw shell/Permission、INI/XML 数据面、单 XML durability、TUI 后备、portable/upgrade 必须相互一致。
5. 对纯技术问题给出一个可证明的推荐设计和验证计划，不把 API 细节全部变成项目负责人问卷。
6. 将已决定部分写入对应权威子系统规格，删除被否决分支和过期“待讨论”。
7. 填写 requirement→spec→test matrix，并据此重新评估本文件每个 gate。

## 进入 writing plan 的最终判定

只有同时满足下列条件，才可以声明“架构可进入完整实施计划”：

- 所有 P0 gate 为 `passed`，而不是“推荐完成”或“没有发现新问题”。
- 所有进入 v0.1 的 P1 gate 已关闭；明确排除的能力具有非目标决定和不预留半实现的边界。
- 所有项目负责人必须决定的分支已有明确回复并归档；任何未回复推荐仍保持候选。
- 每个子系统拥有单一权威规格，正常、取消、失败、恢复、资源上限和目标平台差异均无实现者猜测空间。
- AgentLoop、Model、Tool、Permission、Context XML、CLI/TUI 使用同一套 ID、事件、错误和状态语义。
- 配置 schema、XML schema、命令/工具 registry、错误目录和测试 fixture 之间可以机械校验关键字段与枚举。
- requirement→spec→test matrix 对全部 P0/P1 没有缺失链接。
- luainstaller Win32 前置已解决或已获得授权并作为实施计划中的硬前置子项目；现有错误 ABI 资源没有被当作可发布依赖。
- 实施计划能够只拆任务、测试和提交顺序，不再承担未决产品设计。

若任一证据缺失、只间接支持结论或仍依赖“实现时再决定”，readiness 状态必须保持未通过。
