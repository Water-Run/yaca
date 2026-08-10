# 架构实施就绪门禁

更新日期：2026-08-10

状态：负责人输入门已通过；当前仍未达到完整实施计划就绪，更未达到编码就绪

> D-068：AR-P1-10 由“第三方公开 XML reader”改为“内部 schema + export + yaca 导入路径”。

## 当前判定

`DISCUSSION-BATCH-06.md` 已使 `DECISION-REGISTER.md` 达到 `unanswered=0/conflict=0`，因此不再缺项目负责人产品选择。阻塞项已经转为两类：其一是若干 owner 文档仍需把决定机械展开为完整 schema/状态表/错误与恢复矩阵；其二是 XP x86、Win7+ x64、CentOS 7、单 XML durability、可取消进程/网络和 luainstaller 三目标包仍缺可执行 proof plan 或实际目标证据。当前可以继续完善设计和技术证明计划，不能开始产品实现。

运营向差距清单、Wave 工作包与“可开发”两道门定义见 [`READINESS-GAP.md`](READINESS-GAP.md)。Web 产品族预留（D-058）不计入 v0.1 主线就绪。

## 目的

yaca 已经有大范围设计题库、项目级决定和各子系统候选文档，但三者承担的责任不同。题目数量多、推荐写得详细或某项技术做过一次 smoke test，都不能单独证明程序已经可以直接实施。

本文建立统一 readiness gate，用来回答四个问题：

1. 项目负责人回复后，哪些产品行为已经真正确定？
2. 哪些内容不应继续让项目负责人选择，而应由技术设计和目标平台证据证明？
3. 哪些权威工件缺失时，即使所有问题都回复过，仍不能编写可靠的实施计划？
4. 怎样从需求、决定、规格、测试一直追踪到正式发布证据？

本文不是新的产品规格，也不替代 [`DECISIONS.md`](DECISIONS.md) 或各子系统最终规格。

optional scope 已全部收口为 terminal-only、无 Web/media/remote/transcription/TTS、单 workspace root、无 telemetry/diagnostic upload/built-in update。下文只检查这些排除项的 zero-surface 证据，不再保留 A/B/C 条件实现路线。

## 四类文档不能混为一谈

### 题库：发现和解释选择

[`QUESTIONS.md`](QUESTIONS.md) 和 [`DESIGN-CHECKLIST.md`](DESIGN-CHECKLIST.md) 用于发现遗漏、解释取舍和组织决策依赖。

- `方案` 和 `推荐` 都只是讨论材料。
- 标记为“部分”“待决”或只有推荐、没有项目负责人明确回复的条目，一律不算决定。
- 一项问题被回复，只能证明相应选择已经获得输入；还要检查回复是否存在歧义、是否改变其他题目前提，以及是否已归档。
- 当前 384 个 checklist ID 是覆盖主题，不自动等于 384 份实现契约；当前 `AQ-001` 至 `AQ-437` 是原子选择，配置候选的 `CV-001` 至 `CV-076` 是跨字段验证，三者都不自动等于接口、状态机或测试规格。编号数量以后再变化时仍以各自权威文件的实际唯一 ID 为准，不在本文复制另一套静态清单。

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

## 全局负责人输入门

所有 P0/P1 gate 之前先检查 [`DECISION-REGISTER.md`](DECISION-REGISTER.md)：决策包正式 group 集合、推荐模板集合与登记表集合必须都是同一 `decision-inventory-v9` 的 270 项 inventory。现行分布为 `PJ 19 / PP 18 / TU 32 / M05 57 / AL06 49 / TS 35 / CX 16 / ED 14 / RF 14 / F4 16`。负责人已回答 [`OWNER-QUESTIONS-01.md`](OWNER-QUESTIONS-01.md) 的全部 29 题，集中覆盖经机械检查恰好命中回复前 248 个 `unanswered` 一次；当前为 265 个 active 收口、5 个 inactive、0 个 unanswered/conflict。进入完整实施计划前：

新增拆分继续用于检查 composer 输入召回、配置秘密文件权限、raw shell 继承环境、完整 model-yield 后续接、direct 文件属性、ignore/隐藏项、`exec` cwd、输出解码与 canonical 保留、active XML 外改恢复没有遗漏。它们不再天然都是负责人问题：集中答案能唯一决定用户保证时按覆盖投影；不改变用户保证的内部选择转 technical-proof。任何一类都必须形成完整规格/证据，不能把问卷变短误写成 gate 已通过。

- 不得存在现行 `unanswered`、`explaining` 或 `conflict`；`deferred` 只有在明确移出 v0.1、写出恢复条件且不阻塞任何现行 gate 时才算收口。
- active 组必须是 `selected`、`selected-with-exception`、`excluded` 或已经转换为有产品保证/失败退路的 `technical-proof`；inactive 条件组必须是有已选上游依据的 `not-applicable`。
- 每个 selected 类状态都有负责人原话引用、选择/assertion、现行 D 或明确“细化既有 D”的引用、唯一 owner 规格锚点和 gate/test 路由。
- `not-applicable` 必须证明没有生成配置字段、XML 项、命令、页面、Runtime 分支或测试空壳；上游被修订时自动重新打开。
- `superseded` 只保留历史，不计作当前有效选择；当前同一保证只能有一条现行决定和一个 owner。

这道门只证明负责人输入已经捕获并传播，不代替任何 `T/J` 平台原型、故障注入或发布证据。

下文所有 optional-scope gate 都按现行排除决定验证零字段、零命令、零 endpoint、零组件和零运行分支；只有负责人未来显式重开决定，才重新设计正向能力。

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

当前状态：未通过；terminal-only、零 Web/媒体/remote/TTS、单 root、便携邻接数据、无 telemetry/upload/update 与三目标 zip 已确认，但完整旅程矩阵、公开文档同步和最终零表面扫描尚未完成。

- **阻塞原因**：D-056 已确认三个解压后原地运行的便携 zip、邻接 `__yaca__` 和简单 Install 脚本；当前缺口不是产品形态，而是完整生命周期规格、公开文档同步和最终包证据。D-044 已排除 Web、图像、音频、remote/headless、transcription 和 TTS，D-045 已排除 multi-root，D-055/D-056 又排除 telemetry、诊断上传和内建更新；必须证明这些能力真正从发行面消失。
- **权威工件**：产品闭环说明；v0.1 支持/排除矩阵；Web/媒体/remote/multi-root/telemetry/upload/update 的 zero-surface manifest 与重开条件；portable 邻接数据的安装→首次配置→新建/恢复→退出→手工升级→卸载状态表。
- **通过证据**：每条用户旅程有唯一结果；排除能力在 CLI/help、配置 schema/模板、XML schema、Model/tool registry、页面/listener、loader/公开 API 与最终 zip 中都没有可触发空壳；唯一 root 可由 XML 镜像父目录解码；三个最终 zip 都匹配 D-056 的布局、邻接数据和手工升级语义；README 不再把候选或未实现能力写成现状。
- **责任**：`O` 决定产品形态和数据保留；`T` 验证各目标平台能够实现。
- **主要来源**：`PROD-01`、`PROD-04`、`PROD-05`、`PROD-11`、`PROD-12`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`EXT-01` 至 `EXT-03`、`REL-01` 至 `REL-03`、`DIAG-08`、`REL-11`、`AQ-044`、`AQ-215` 至 `AQ-217`、`AQ-244`、`AQ-373`、`AQ-382` 至 `AQ-390`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16。

### AR-P0-02 AgentLoop 的 terminal intent 和 typed outcome

当前状态：未通过；`finish/ask-user/refuse/model-yield` 和主要 queue/steer/side 路线已确认，但完整事件/transition/terminal-outcome/恢复表及 golden trace 尚未冻结。

- **阻塞原因**：provider 响应结束只证明一次生成结束；“没有工具调用”无法区分完成、澄清问题、拒答和部分结果。Runtime 又不能靠搜索自然语言猜测 typed outcome。typed `ask-user` 后的用户回复尚未冻结 turn/快照/预算边界，错误页上的“retry”也尚未区分安全 transport attempt、新 request/new turn 和绝不可重放的 accepted/unknown operation。
- **权威工件**：AgentLoop 状态机；主模型控制信号/envelope；`completed|waiting_user|partial|refused|cancelled|budget_exhausted|stuck|error` 枚举和转换表；turn/request/attempt/reply-to 因果表；manual action/retry registry；最终报告合成规则。
- **通过证据**：脚本化模型分别产生完成、提问、拒绝、部分结果、长度截断和无效控制信号时，trace 得到唯一且正确的 terminal outcome；等待数小时后回答 `ask-user` 仍按 D-051 建立唯一新旧 turn 关系；每种 retry UI 动作都能从 trace 证明不会泛化重放副作用；`DoubleCheck` 开关不改变 Runtime 对取消/错误事实的诚实标记。
- **责任**：`O` 确认用户可感知语义；`T` 设计协议并证明 provider 映射可靠。
- **主要来源**：D-020、D-027、`MODEL-06`、`LOOP-03`、`LOOP-10`、`LOOP-22`、`LOOP-28`、`LOOP-29`、`AQ-019` 至 `AQ-023`、`AQ-099` 至 `AQ-110`、`AQ-251` 至 `AQ-259`、`AQ-363`、`AQ-364`、`AQ-421`、AL06-48。

### AR-P0-03 Model/Provider canonical protocol

当前状态：未通过；`openai-chat` 与 `anthropic-messages`、完整 Model 实例和 streaming 三态已确认，但两个 adapter 的 canonical event schema、carrier 和录制 fixture 尚未完成。

- **阻塞原因**：`OpenAI-compatible` 不是足够精确的协议规格。角色、工具调用 delta、同一响应中的文本和工具、重复/缺失 call ID、refusal/content filter、usage、HTTP error 与断流都可能不同；TS-23 选中的 carrier 还必须被所选 Protocol 无损承载，不能靠把 bare payload 偷包成另一语义。每 Model retry 的用户配置面、Runtime hard cap、`Retry-After` 和 request snapshot 也要闭合。D-044 已排除图像、音频、独立转写与语音输出，因此 provider profile、宽 passthrough 和 capability 探测都不得偷留可触发的 media content-part 或 purpose。
- **权威工件**：内部 `ModelRequest`、`ModelEvent`、`ModelResult`、`ModelError` schema；v0.1 provider/content-part profile；capability/self-test 契约；六个核心 purpose与 D-041 周期 `context-name` 的权限/数据表；每 Model 调度/冷却与 aggregate budget 账本；D-044 的零 image/audio/transcription/speech purpose manifest。
- **通过证据**：规范录制 fixture 覆盖流式/非流式、工具、文本+工具、畸形 JSON/SSE、截断、拒答、超限、重试和取消；单并发 Model、main/side/action-review/termination-review 与周期 `context-name` 的竞争、最小间隔和 `Retry-After` 冷却不会超发或绕过总账；action 与 termination 分别冻结 AL06-08/49 所选实例，不会因名称/endpoint 相同而共享隐式选择或失败 fallback；provider schema/capability/purpose/request registry 的 image/audio/transcription/speech 成员数为零，外来 payload 在网络发送前稳定拒绝。
- **责任**：`O` 决定正式支持哪些协议和降级；`T` 冻结 wire contract 与 conformance fixtures。
- **主要来源**：`MODEL-01` 至 `MODEL-12`、`MODEL-14` 至 `MODEL-16`、`PROD-17`、`PROD-18`、`PROD-20`、`PROD-21`、`AQ-018`、`AQ-081`、`AQ-091`、`AQ-099`、`AQ-101`、`AQ-102`、`AQ-106`、`AQ-138`、`AQ-139`、`AQ-218` 至 `AQ-222`、`AQ-259`、`AQ-359`、`AQ-362`、`AQ-374`、`AQ-383`、`AQ-384`、`AQ-388`、`AQ-389`、`AQ-433`、M05-01、M05-03、M05-58、TS-23、PJ-15、PJ-16、PJ-19、PJ-20。

### AR-P0-04 XP/CentOS 事件泵与可取消 I/O

当前状态：未通过；单线程领域状态机/事件泵、单 active Context 和串行工具已确认，实际 XP/CentOS console/network/process I/O multiplex 与取消原语仍须技术设计和证明。

- **阻塞原因**：Lua 协程不会把阻塞的 console、curl pipe、stdout/stderr 或进程等待自动变成可取消事件。没有共同端口就无法同时兑现流式响应、忙时输入、Esc、中断、工具输出和关闭期限；系统 suspend/resume 后旧连接、lease、deadline 与 workspace 也不能被当作仍连续有效。D-051 已固定单进程只有一个 active Context 和一个单线程领域状态源，当前责任是证明这套拓扑在旧平台可工作，而不是再选择 Context 数量。
- **权威工件**：`start/poll/cancel/join/close` 异步端口 ABI；Windows/Linux adapter 能力矩阵；单 active Context 的资源、事件归属与关闭投影；single-root derivation 与 zero-root-list 资源清单；Web/remote 零 listener/client 端口清单；suspend/resume 检测与重新验证表；事件排序、背压、关闭和 helper 崩溃协议；最小技术验证计划。
- **通过证据**：XP SP3 x86 与 CentOS 7 x86_64 上，模型流、console 输入、双输出管道和进程退出可以并行推进；取消在规定期限内可见且不会丢失已到达核心的事件；唯一 active Context 不饿死控制事件或突破进程资源上限；每个 Context 的 root 只从当前 XML 镜像位置导出，rebind 后旧 root 快照失效；进程不建立 Web/remote listener/client 队列；在 sampling/tool/approval/commit 时休眠再恢复不会自动重放不确定请求或副作用，并给出 typed 收口。
- **责任**：`T` 为主；若最低平台只能提供明显降级，由 `O` 确认是否接受。
- **主要来源**：`RUNTIME-01`、`RUNTIME-02`、`RUNTIME-06`、`RUNTIME-07`、`PROD-05`、`PROD-19`、`PROC-01` 至 `PROC-07`、`NET-09`、`CONC-01`、`CONC-02`、`AQ-223`、`AQ-239`、`AQ-245`、`AQ-250`、`AQ-270`、`AQ-315`、`AQ-381`、`AQ-382`、`AQ-385`、`AQ-386`、PJ-14、PJ-17、PJ-18。

### AR-P0-05 TUI full-duplex 输入与确定性交互

当前状态：未通过；固定快捷键、完整点命令后备、追加式 transcript 和 `>>` 已确认，旧 console/TTY 的按键识别、draft 保护和 full-duplex 证据尚未完成。

- **阻塞原因**：在 cooked/canonical 输入中，模型或工具异步输出可能穿过用户未提交的输入行；renderer 看不到 OS 正在编辑的缓冲。快捷键不可识别时还必须保持 queue/steer/side/cancel 的领域语义。stdin/stdout/stderr 的 TTY 能力不能合成一个布尔值；D-051 已固定单 active Context，仍须冻结唯一焦点下的异步事件与 draft 保护。
- **权威工件**：输入状态机；三条标准 fd 的独立能力与 prompt gate 矩阵；async output 与 line editing 协议；快捷键→文本后备映射；单 active Context 的焦点规则；Web/remote/media 零输入表面清单；每个 Agent 状态下 Esc/EOF/Ctrl+C/普通输入的动作表；ASCII golden transcripts。
- **通过证据**：XP console、普通 POSIX TTY、`TERM=dumb`、SSH PTY 和重定向场景中，用户输入不丢失、不被输出污染；后备入口产生相同领域事件和默认安全结果；TUI/CLI/help/completion 没有 clipboard image、screenshot、audio device、transcription、speech 或 remote-client handler；普通文本粘贴和要求模型通过既有文件工具读取目录仍可完成。
- **责任**：`O` 决定可接受体验；`T` 证明平台行为和渲染等价性。
- **主要来源**：`RUNTIME-07`、`CLI-17`、`PROD-17` 至 `PROD-21`、`TUI-01` 至 `TUI-19`、`TUI-21` 至 `TUI-29`、`AQ-009` 至 `AQ-015`、`AQ-066` 至 `AQ-090`、`AQ-231` 至 `AQ-233`、`AQ-264`、`AQ-265`、`AQ-299`、`AQ-331` 至 `AQ-340`、`AQ-365`、`AQ-366`、`AQ-376`、`AQ-381` 至 `AQ-385`、`AQ-388`、`AQ-389`、`AQ-426`、PJ-14 至 PJ-17、PJ-19、PJ-20、TU-31。

### AR-P0-06 工具集、raw shell 与 Permission 能力矩阵

当前状态：未通过；完整 tool registry、`Read/Write/Delete/Shell/OutsideWorkspace`、Std/Readonly、无 SensitiveRead/direct HTTP 已确认，但逐工具 capability/approval/result 与 raw shell 宽边界矩阵尚未完成证明。

- **阻塞原因**：若 shell 只映射 `Execute`，其他细粒度权限无法约束 shell。若仍宣称能从任意 shell 文本精确识别副作用，又会制造不存在的 sandbox 保证。模型 raw `exec` 与 direct tool 的 input carrier/schema、stdin、命令物理传输上限，以及自动 Git 只读 adapter 是否会启动外部 helper，都尚未形成正式工具边界；`__yaca__` reserved tree 的 list/search、mutation 与 exact-read 必须分别闭合，且不得把 direct deny 冒充 shell containment；非 Agent 管理动作不能靠复用历史 tool approval 获得授权。D-044 同时禁止 screenshot/media capture tool 与 headless/remote approval source。
- **权威工件**：首版 tool registry；TS-23 所选 ToolInputRegistry；每个工具的 carrier、参数/result schema、版本、capability、副作用、stdin、可取消性、unknown-field 规则和输出上限；raw command length/encoding contract；`tool × capability × Permission state` 矩阵，其中 M05-16 A/B 机械生成 coarse/split outside，M05-56 A 生成零 SensitiveRead surface、B 才接入 TS-21；provider 网络与工具网络分界；Git adapter/系统 Git 使用范围；Agent approval 与 `ManagementMutation` 的独立快照 schema；零 media-capture/remote-client tool 与 approval-source manifest。
- **通过证据**：Model 请求前发布的 registry/schema identity 与 response admission、canonical accepted arguments、approval snapshot、XML schema snapshot 和 result pairing 机械一致；畸形/超限/未知字段不会产生 executable operation，raw shell command 不被 Runtime 分词、重写或推断细粒度 capability；Readonly、Std 和其他用户定义 profile 对每个直接工具和 shell 的结果可由表格机械推导；M05-16 两条路线只改变 outside 字段粒度，M05-56 A 时 parser/template/help/classifier 均为零、B 时 TS-21 命中只会提高限制且未命中不宣称安全；shell 明确展示其宽权限事实且子进程不能偷取 TUI 输入；超长/不可编码命令不会被 Runtime 静默拆分；所谓只读 Git 不会绕过 Shell 启动 pager/external diff/textconv；管理动作不继承 Agent approval；registry 不含 screenshot、audio、transcription、speech 或 remote-client tool/action；LLM/DoubleCheck 只能追加限制，不能授予 Runtime 拒绝的动作。
- **责任**：`O` 确认安全体验和预设含义；`T` 定义确定性求值和测试。
- **主要来源**：`ARCH-05`、`PROD-17`、`PROD-19`、`PROC-11`、`PROC-12`、`TOOL-*`、`SAFE-*`、`THREAT-*`、`AQ-033` 至 `AQ-040`、`AQ-111` 至 `AQ-130`、`AQ-149`、`AQ-150`、`AQ-224` 至 `AQ-226`、`AQ-249`、`AQ-367`、`AQ-369`、`AQ-371`、`AQ-383`、`AQ-385`、`AQ-418`、`AQ-419`、`AQ-422`、`AQ-424`、`AQ-425`、`AQ-430`、`AQ-436`、M05-16、M05-56、TS-04、TS-21、TS-23、TS-35 至 TS-40、SAFE-18、PJ-15、PJ-17；技术证明 TP-014/028/029。

### AR-P0-07 改动归属、审阅和 undo 范围

当前状态：未通过；已明确选择 expected-digest/atomic/diff 证据且不提供通用 undo，仍需把每个文件操作、部分成功、Git/raw-shell unknown 与崩溃切点写成可执行事务/fault 矩阵。

- **阻塞原因**：完整 preimage 会显著改变 XML 体积、秘密复制、配额、导出和崩溃提交协议；外部 checkpoint 又改变“长期只有 INI/XML”和单 XML 接盘承诺。raw shell 的副作用也无法获得同等撤销保证。
- **权威工件**：v0.1 change guarantee；结构化写入新鲜度/原子替换协议；Agent 改动与用户既有改动的归属规则；若支持 undo，则还需 preimage 存储、配额、秘密、补偿与冲突规格。
- **通过证据**：D-052 的“仅防覆盖+diff 证据、无通用 undo”在 Git/非 Git、已有脏改动、多文件部分成功、崩溃切点和 shell 未知副作用 fixture 中得到一致结果；配置/schema/help/Runtime 中没有 undo/backup/Git workflow controller 空壳。
- **责任**：`T` 证明已确认保证可在目标平台兑现；只有证据迫使降低 D-052 的用户保证时才重开最小 `O` 差异。
- **主要来源**：`CHANGE-01` 至 `CHANGE-05`、`TOOL-02`、`TOOL-05`、`TOOL-09`、`TOOL-15`、19 号子系统。

### AR-P0-08 数据分类、秘密和导入信任

当前状态：未通过；明文配置秘密、Permission Prompt 非授权边界和零媒体/remote 数据面已有方向，跨模型/持久化/导入/日志矩阵尚未形成。

- **阻塞原因**：外部或导入 XML 可以携带 ContextPrompt、Permission 名、`DoubleCheck=false`、跨 Endpoint 同意和历史 approval；digest 只能检测意外损坏，不能认证来源。已确认的明文 Key、显式 HTTP、过短 secret A 路线、无 secret-bearing backup/export、外来 XML 原位接盘和历史 approval audit-only 仍需合成一张可机械验证的数据矩阵；不能把多个 owner 的决定留给实现者重新解释。D-044/D-055/D-056 已消除媒体、remote、telemetry、诊断上传和更新网络面。
- **权威工件**：[数据分类候选](DATA-CLASSIFICATION-CANDIDATE.md) 收口后的现行矩阵；secret lifecycle；HTTP/HTTPS + AuthMode/Key policy；curl/header/临时文件传递协议；Context 永久删除与已知副本说明；XML 导入信任规则；历史事实与当前授权的分离规则；零 media/remote/telemetry/upload/update 类别清单。
- **通过证据**：每类数据对 main、side、action-review、termination-review、compaction、周期 `context-name`、self-test、TUI、XML、stderr/support stdout 和 HTTP/HTTPS 的默认处理都有唯一答案；两个 review purpose 的 Model/mapping、endpoint 确认和发送 manifest 彼此独立；导入的历史审批永远不能在目标机自动授予当前动作；每种 registered config secret 自动进入 argv/XML/error/support/tool-output canary，新增类型无需改手工名单；media/remote/telemetry/upload/update payload、device、endpoint 和 purpose 数为零；永久删除说明准确区分 yaca 已知副本、已发送内容和无法保证的物理残留。
- **责任**：`O` 确认隐私承诺和确认点；`T` 完成 threat tests 和泄漏扫描。
- **主要来源**：`PROD-08`、`PROD-17` 至 `PROD-21`、`CFG-04`、`CFG-25`、`CFG-29`、`MODEL-17`、`NET-03`、`NET-13`、`PROC-10`、`SAFE-09`、`CTX-06`、`CTX-28`、`CTX-29`、`DIAG-03`、`DIAG-08`、`DIAG-14`、`REL-11`、`AQ-017`、`AQ-040`、`AQ-137`、`AQ-159`、`AQ-165` 至 `AQ-168`、`AQ-180`、`AQ-220`、`AQ-237`、`AQ-238`、`AQ-246`、`AQ-349`、`AQ-368`、`AQ-378`、`AQ-380`、`AQ-382` 至 `AQ-390`、`AQ-417`、`AQ-435`、`AQ-437`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16、M05-54、M05-59、AL06-51。

### AR-P0-09 完整 typed 配置 schema 与 bootstrap

当前状态：未通过；现行配置面、四层 Prompt、双协议、粗 Permission、DoubleCheck、HTTP/stunnel、self-test 与逐 turn generation 已确认，仍需冻结每个字段的精确拼写/grammar/default/migration/secret 与生成式 schema fixture。

- **阻塞原因**：正常启动要求完整校验，但配置缺失/损坏时 model/config REPL 和 self-test 又需要最小 bootstrap。字段、默认、INI/XML 合并、顺序语义、未知字段、手工编辑、并发外改和秘密输入尚未全部成为一个生成式契约；不过 Model/Permission selector、per-Model retry、stuck 阈值、过短 secret、reset/delete/migration 路线和排除字段都已有选择，不能再写成实现时任选。D-048 已固定每个顶层 main/side turn 的 immutable generation 边界；剩余责任是完成 catalog/校验表并证明半写、删除、无效引用和旧机延迟。
- **权威工件**：唯一 typed schema；逐字段 catalog；INI grammar；XML 覆盖白名单；跨字段约束；可选能力的 choice→schema 投影和 zero-field manifest；bootstrap command allowlist；完整 INI bytes/digest→parse/validate→atomic `ConfigGeneration` contract；`ManagementMutation`；配置编辑事务和迁移协议。
- **通过证据**：默认模板、parser、validator、help、REPL、脱敏和 self-test 都从同一 schema 生成或由测试证明同步；启动头 master、SensitiveRead、Web/media/remote/telemetry/upload/update、multi-root、undo/backup 字段与占位 section 数为零；逐字段启动 bool 全关不会隐藏 ERROR/WARNING/ACTION；Context 列表默认 `updated+descending`；每个顶层 main/side turn恰好观察一次完整 INI，变化后只发布完整有效 generation，child activity 不重载；action/termination reviewer selector 分别按 D-051 生成且 finish review 不可从 `DoubleCheck=true` 中删除；`AutoRenameDisabled` 只在 Context XML metadata 出现；外部半写/无效版本不会穿过 turn 快照；同一 reset/delete/migration 经 CLI/REPL 得到相同 target/impact/stale-check/default-cancel/result。
- **责任**：`O` 确认字段行为和默认；`T` 定义语法、迁移、原子保存和 contract tests。
- **主要来源**：`ARCH-05`、`PROD-17` 至 `PROD-21`、`CFG-01` 至 `CFG-29`、`FMT-02`、`FMT-04`、`LOOP-31`、`DIAG-08`、`DIAG-14`、`REL-11`、`AQ-012` 至 `AQ-018`、`AQ-077` 至 `AQ-085`、`AQ-131` 至 `AQ-160`、`AQ-200`、`AQ-201`、`AQ-246`、`AQ-289` 至 `AQ-291`、`AQ-361`、`AQ-369`、`AQ-378`、`AQ-382` 至 `AQ-390`、`AQ-417`、`AQ-423`、`AQ-432` 至 `AQ-434`、`AQ-437`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16、M05-54、M05-55、M05-57 至 M05-59、AL06-50。

### AR-P0-10 Context XML schema、durability 与恢复

当前状态：未通过；单 XML 总体形态已确认，安全提交协议和性能可行性未解决。

- **阻塞原因**：每个 canonical/durable 事件都整文件重写会形成 O(n²) I/O；在闭合 XML 根后原地追加元素又不是合法 well-formed XML。D-053 已选完整流式重写、短寿命 temp/lock/previous-valid 和无长期 WAL；当前只需证明该路线满足旧机 hard limit，不能暗中切换事实源。XML 还必须对全部排除能力保持零 element/namespace。
- **权威工件**：公开 XML schema/namespace；event/relationship/ID schema；zero-element manifest；`AutoRenameDisabled` 元数据；确定性 writer；完整重写、flush、lock、temp、replace、恢复和外部读取状态机；文件大小/延迟门槛；损坏和迁移协议。
- **通过证据**：正常、每个崩溃切点、磁盘满、替换失败、第二写者和外部修改都有预期旧版/新版/只读损坏结果；排除能力、current-root/workdir/list/alias/selector、telemetry/upload/update 元素数为零；`AutoRenameDisabled` 的 rename/取消/迟到竞态稳定；XP x86 长会话满足冻结 hard limit。若证明失败，只提交改变 D-053 保证的最小反例供负责人重开，不自行加入长期 WAL。
- **责任**：`T` 证明已选格式、原子性和性能；失败且替代路线改变单 XML保证时才回到 `O`。
- **主要来源**：D-022、D-023、`FMT-01`、`CFG-25`、`PROD-05`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`CTX-01` 至 `CTX-18`、`CTX-21` 至 `CTX-29`、`AQ-041` 至 `AQ-043`、`AQ-161` 至 `AQ-180`、`AQ-227`、`AQ-228`、`AQ-246`、`AQ-303` 至 `AQ-308`、`AQ-368`、`AQ-378`、`AQ-380`、`AQ-383` 至 `AQ-390`、`AQ-420`、PJ-15 至 PJ-20、ED-13、ED-14、RF-16、CX-20。

### AR-P0-11 Context 路径、索引、导入和生命周期

当前状态：未通过；Resolver 核心顺序、单 Context 单固定 work directory、镜像父目录为当前位置权威、首消息建立、活动 writer 外部零 mutation 与 Context 列表默认排序已确认；平台路径 codec 和其余生命周期技术规格仍未完成。

- **阻塞原因**：盘符、UNC、POSIX 根、Unicode/case、8.3、symlink/junction、非法名称和跨机映射会同时改变文件地址、hash、安全边界与浏览器结果。active Context 的 switch/rename/rebind/permanent-delete 还需完整状态表；FAT/SMB/NFS/可移动盘也不能共用一个模糊“可写”承诺。运行中 workspace 被删除、卸载或断线会使当前 root、审批和 Prompt 快照同时失效。外来 XML 已选择原位验证/mapping/确认与历史授权 audit-only，不能再从三条导入策略任选。
- **权威工件**：`LogicalPathCodec` 规范；路径 hash 规范和 vectors；Context lifecycle；镜像父目录→唯一 root 契约；canonical time/name 排序键；文件系统支持矩阵；Resolver/browser result schema；switch/rename/rebind/permanent-delete/import 状态机；compatibility-gap 分类；special file/link policy。
- **通过证据**：同一规范输入跨平台产生相同逻辑路径/hash；created/updated/name 排序稳定且不读取文件 mtime/ctime；每条 lock/no-replace/flush 保证绑定具体文件系统证据；Context/tool/Prompt/XML 只有一个 root；活动 writer 的外部管理 mutation 稳定冲突；rebind 后路径/hash/approval 快照一起 stale；链接逃逸、collision、损坏、不可读、active delete、外部移动和卸载安全失败；外来 XML 只有 D-053 的原位 mapping/确认结果，历史 approval 永不授权当前动作。
- **责任**：`O` 确认用户流程；`T` 冻结路径算法并做跨平台 fixture。
- **主要来源**：D-022 至 D-024、`PROD-05`、`PROD-16`、`PLAT-01`、`PLAT-13`、`CTX-29`、`INDEX-01` 至 `INDEX-11`、`INDEX-13` 至 `INDEX-16`、`AQ-083`、`AQ-117`、`AQ-169`、`AQ-170`、`AQ-173` 至 `AQ-178`、`AQ-189`、`AQ-199`、`AQ-212` 至 `AQ-216`、`AQ-237`、`AQ-370`、`AQ-372`、`AQ-380`、`AQ-386`、`AQ-420`、PJ-18、CX-20。

### AR-P0-12 压缩后的模型视图

当前状态：未通过；结构化摘要前缀加最近完整 atomic groups 已确认，摘要 schema、view manifest、纠正/失败/超大 group 算法和可重建 fixture 尚未冻结。

- **阻塞原因**：只说“事实历史+摘要+最近窗口”不足以决定每个工具对、Prompt、用户决定、未知副作用和模型切换怎样保留，也无法处理恢复后历史已超过当前 Model 窗口，或单个不可拆原子组自身已经大于窗口的情况。用户显式 `.compact` 还需要确定 admission、turn/intent 身份、费用/预算、取消、恢复和 view 发布，不能借用普通 main turn 的含糊生命周期。
- **权威工件**：model-view builder；结构化 compaction schema；必保槽位；来源 event range/digest；自动与手动触发的 admission/身份/费用/预算/取消/恢复/publication 规则；失败、无收益、oversized-atom 和用户纠正规则；模型切换预检。
- **通过证据**：从同一事实 XML 可确定性重建相同视图；call/result、approval/action、Prompt 和未完成事项不会被拆散；单个超大原子组在请求前得到已确认的 typed 结果且事实不丢；压缩失败不改变旧视图；更小/更大 Model 切换场景有固定结果。
- **责任**：`O` 确认提示/自动化边界；`T` 设计摘要协议和回归 fixture。
- **主要来源**：`COMP-01` 至 `COMP-10`、`COMP-11`、`AQ-061` 至 `AQ-065`、`AQ-142`、`AQ-156`、`AQ-179`、`AQ-240` 至 `AQ-243`、`AQ-298`、`AQ-309` 至 `AQ-311`、`AQ-352`、`AQ-379`。

### AR-P0-13 CLI、点命令和会话命令状态表

当前状态：未通过；长名、唯一 `-` 简写、Windows-only `/`、`--`、recent/full 与 chat 点命令已确认，仍需完整 action × state/admission/result 表、非 TTY schema 和静态冲突/golden fixture。

- **阻塞原因**：Context 切换、Model/Permission/Prompt 修改、压缩、永久 delete 和 exit 在 busy/approval/tool/side/recovery/queued 状态中的行为会影响 AgentLoop 和 durable 事实，不能由各前端分别猜测。D-054 已冻结长式、跨平台短式、Windows `/` 式、点命令与快捷键共享 action registry；剩余责任是逐状态 admission/result 与 machine output，而不是再选择命名空间。排除能力、archive/trash、multi-root、telemetry/upload/update 动作都必须为零。
- **权威工件**：CLI grammar；focus-scoped local/global command registry；长名/唯一简称/兼容别名；help topic/overview registry；可选范围选择到 action/help 成员的机械投影；`command × AgentState` 表；`ManagementMutation` 投影规则；stdin×stdout×stderr×显式 machine mode 矩阵；stdout/stderr/exit-class/machine-output schema；点命令与快捷键领域动作映射。
- **通过证据**：命令和 topic 冲突静态检查为零；`.model` picker、`.model <selector>` 与其 CLI 投影提交同一 normalized target/action/receipt；每个 TUI 领域 action ID 都恰有一个 CLI registry projection；Web/media/remote/transcription/TTS、multi-root、archive/trash、telemetry/upload/update 的 action/topic/completion 数为零；rebind、永久 delete 与 `AutoRenameDisabled` 有完整 state/admission/cancel/error/result；同一动作经 CLI 与 TUI REPL 得到相同 typed result；non-TTY 缺参或需确认时 fail-closed。
- **责任**：`O` 确认命名和交互；`T` 生成 parser/help 和 golden tests。
- **主要来源**：`ARCH-05`、`CLI-00` 至 `CLI-15`、`CLI-16` 至 `CLI-18`、`TUI-10`、`LOOP-10`、`DIAG-14`、`REL-11`、`AQ-014`、`AQ-024`、`AQ-031`、`AQ-076`、`AQ-098`、`AQ-181`、`AQ-182`、`AQ-214`、`AQ-229`、`AQ-246` 至 `AQ-248`、`AQ-301`、`AQ-326`、`AQ-327`、`AQ-369`、`AQ-375` 至 `AQ-377`、`AQ-382` 至 `AQ-390`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16。

### AR-P0-14 安全模块/工具加载与文件目标复核

当前状态：未通过；候选要求存在，但还没有权威加载契约。

- **阻塞原因**：yaca 以陌生工作区为 cwd；若 `package.path/cpath`、DLL 搜索或内部工具解析使用 CWD/PATH，仓库中的同名 Lua/C 模块、DLL 或 curl 可以在权限系统之前执行。即使 executable 路径固定，`.curlrc`、shell AutoRun/rc、Git pager/external diff/textconv 等 ambient config 仍可能改变内部动作或启动外部 helper。文件工具也不能只做字符串前缀检查或审批前检查一次。所有已排除的 helper/listener/update/telemetry/upload 资源必须从 allowlist 消失。
- **权威工件**：内部资源绝对路径解析规则；Lua/C module allowlist；DLL 搜索约束；内部进程 allowlisted environment/ambient-config disable contract；tool/component/listener negative manifest；普通文件/目录/symlink/junction/hardlink/device/FIFO/socket policy；open-then-verify 和 no-replace 契约。
- **通过证据**：在 cwd/PATH 放置恶意同名模块、DLL 和工具不会被内部加载；ambient curl/shell/Git 配置不会改变内部基础设施动作或启动未列 helper；Web/remote/media/update/telemetry/upload 组件和 route 不在 manifest/zip；审批后替换链接或文件身份产生 `TargetChanged`。
- **责任**：`T`；若某旧平台无法提供等价安全性，由 `O` 决定是否缩小支持能力。
- **主要来源**：`RUNTIME-04`、`PROD-17` 至 `PROD-21`、`THREAT-03`、`PROC-08`、`PROC-09`、`PROC-13`、`PLAT-04`、`SAFE-06`、`TOOL-04`、`DIAG-08`、`DIAG-14`、`REL-11`、`AQ-118`、`AQ-213`、`AQ-225`、`AQ-246`、`AQ-250`、`AQ-267`、`AQ-382` 至 `AQ-385`、`AQ-387` 至 `AQ-390`、PJ-14 至 PJ-17、PJ-19、PJ-20、ED-13、ED-14、RF-16。

### AR-P0-15 本地 ID、锁和崩溃收口

当前状态：未通过；没有永久 ContextId 与 `CX-13=B` 已确认，但局部 ID/序号、lease 证据和 stale self-fix 尚未形成一个协议。

- **阻塞原因**：turn、request、attempt、side、tool call、operation、approval 和 compaction 都依赖稳定关联。若崩溃后复用 ID 或信任 provider ID，会错误配对结果或重放副作用。仅按时间删除 stale lock 也会产生双写者；若所选单进程拓扑允许加载多个 Context，还必须证明每个 lease、commit mutex 和关闭动作都绑定正确 Context。D-045 不建立永久 root ID 或 root list；operation/approval/request snapshot 必须绑定当时由 XML 镜像位置解码出的规范 root 与 Context generation，rebind 后旧快照不得被重定向到新 root。
- **权威工件**：identity/namespace table；局部序号分配与持久化规则；provider ID 保存/映射；request-attempt 关系；所选单进程 Context 与 workspace-root 拓扑；write lease/commit mutex 取得顺序；stale lock 复核和恢复协议。
- **通过证据**：在每个分配/提交切点杀进程后，恢复不会复用已 durable ID；重复/缺失 provider call ID 不破坏本地配对；两个进程无法同时成为 writer；同一进程稳定拒绝第二个 active Context；rebind 后携带旧规范 root/Context generation 的动作稳定 stale，且不存在 root alias/selector identity。
- **责任**：`T`；第二写者/只读/等待体验由 `O` 确认。
- **主要来源**：D-023、`RUNTIME-07`、`PROD-05`、`CTX-07`、`CTX-09`、`CTX-16`、`CONC-03`、`AQ-095`、`AQ-103`、`AQ-130`、`AQ-166`、`AQ-171`、`AQ-174`、`AQ-221`、`AQ-225`、`AQ-234`、`AQ-381`、`AQ-386`、PJ-18。

### AR-P0-16 发布可行性与真实平台证据

当前状态：阻塞。

- **阻塞原因一：luainstaller Win32 发布证据**。相邻 `../luainstaller` 当前 Windows profile guard 会拒绝非 x86_64，随附 MSVC recipe/tests 也固定为 x64；因此未修改的默认路径尚不能交付“XP SP3 x86 + Lua 5.5”的 yaca 包。这不证明 launcher/bundler 底层无法支持 x86，也不证明 XP 不兼容；缺口是 qualification、可能的最小适配和最终目标机证据。参考 [`platform.lua`](../../luainstaller/src/platform.lua)、`AS-005-01` 和 `AQ-211`。
- **阻塞原因二：现有 Linux bin ABI**。当前 `bin/` 中 Linux executables 经 `file/readelf` 检查为 ELF32/i386，而正式 Linux 目标是 x86_64；它们只能作为来源线索，不能进入最终包。Windows PE32 资源也仍需 XP import/CRT/TLS 与来源验证，架构正确不等于兼容已证明。
- **阻塞原因三：支持矩阵尚未到物理层**。Win32 x86 尚未确定最低 CPU ISA；Win64 最低系统 API/CRT、Context 邻接数据根与 workspace 的正式文件系统等级也未形成目标证据。unsigned + 无内建更新已确认，不能再列为产品待决，但仍需证明每个最终 zip 的 SHA-256/SBOM/manifest 与真实 bytes 一致。仅写“支持 XP/Win7/CentOS 7”不能代替这些承诺。
- **权威工件**：经授权的 luainstaller Win32/x86/XP 与 Win64/Win7 qualification 及必要适配规格；三个 release manifest；D-044 negative component/asset manifest；D-045 zero-multi-root component/protocol manifest；组件来源/hash/license/架构/ISA；编译器/CRT/API/CPU baseline；数据根/workspace 文件系统支持矩阵；明确 unsigned/no-update negative manifest；简单 Install 脚本、构建、装配和真实平台验收流程。
- **通过证据**：同一 Win32 x86 候选在符合最终 CPU 下限的真实旧 CPU 环境及 XP 至 11 完成完整测试；Win64 x86_64 候选在 Windows 7 SP1 至 11 完成完整测试；Linux x86_64 候选在 CentOS 7 基线和最终声明发行版通过。三个 zip 分别放行；正式支持的数据根文件系统通过 lock/no-replace/flush/replace/断电证据，包在清空系统 Lua/PATH 后仍完整运行；最终 zip 无 Web/media/remote/notification/update executable、DLL、codec、browser asset、listener 或空壳，也无 multi-root registry/mapper/selector 组件；PE/ELF、SHA-256、component/license manifest、SBOM、build/test summary 一致。
- **责任**：`O` 授权兄弟仓库工作并确认发布范围；`T` 完成构建链、ABI 审计和真实平台证据。
- **主要来源**：D-004、D-007 至 D-012、D-015、D-016、D-039、D-056、`PLAT-13`、`PROD-05`、`REL-03` 至 `REL-14`、`DIAG-08`、`SUPPLY-*`、RF-01 至 RF-16。

## P1 readiness gates

P1 gate 不一定改变全局架构，但会阻断对应子系统的可靠计划。由于项目负责人要求先完整规划再逐系统开发，编写全程序实施计划前也应全部关闭；若只为一个已隔离子系统写局部计划，至少关闭该系统及其上游 P1。

### AR-P1-01 精确格式语义与库边界

- **阻塞原因**：JSON 数字/重复 key/无效 UTF-8、INI 重复 section/key/注释/多行/往返仍只有 checklist 主题；XML parser 候选的 Lua 5.5/目标平台证据也不完整。D-044 已排除 media/Web/remote payload profile，宽 JSON/XML/HTTP parser 不得因此顺带接纳这些类型。
- **权威工件**：JSON、INI、XML 安全子集；D-044 zero media/Web/remote payload registry；parser/writer 接口；资源上限；依赖版本/hash/license；malformed corpus。
- **通过证据**：跨平台 golden vectors、fuzz/malformed fixtures、确定性 round-trip 和资源上限测试；image/audio/transcription/speech/Web/remote parser/profile 数为零，外来相关 payload 以稳定 unknown/unsupported 结果拒绝。
- **责任**：`T`；会改变手工编辑体验的部分由 `O` 确认。
- **主要来源**：`FMT-01` 至 `FMT-07`、`CTX-25`、`PROD-17` 至 `PROD-21`、`AQ-161`、`AQ-171`、`AQ-185` 至 `AQ-188`、`AQ-200`、`AQ-287`、`AQ-288`、`AQ-323`、`AQ-382` 至 `AQ-385`、`AQ-388`、`AQ-389`；技术证明 `TP-010`、`TP-015`、`TP-019`、`TP-021`。

### AR-P1-02 网络细节和 secret-safe curl adapter

- **阻塞原因**：redirect、proxy/NO_PROXY、CA、TLS、显式明文 HTTP、Retry-After、content encoding、header/SSE limits、取消和 secret 传递必须组成一套协议，而不能分散实现。每 Model scheduler 还必须让六个核心 purpose 与周期 `context-name` 共用并发、间隔和冷却；内部 curl 的 ambient config 不能改写这些规则。网络 registry 不得产生 Web/remote/telemetry/upload/update purpose。
- **权威工件**：HTTP request/attempt state machine；curl argv/stdin/temp 与 ambient-config isolation contract；HTTP/HTTPS + AuthMode/Key matrix；retry matrix；per-Model scheduler/budget ledger；零 Web/remote/telemetry/upload/update purpose registry；代理和 CA precedence；same-origin redirect/key policy；显式联网入口矩阵。
- **通过证据**：本地可控 server/proxy fixtures 覆盖 same-origin redirect、显式 HTTP 的每次保存/改变警告、认证、断流、429/Retry-After、并发 purpose、超大 header/event、慢消费者和取消；HTTPS 不降级，stunnel 只在实际 TLS 路线不可用时建议；排除网络面没有 endpoint/request；启动/定时/纯本地浏览不隐式联网；恶意 `.curlrc`/环境不改变实际 request；扫描 argv/temp/error 泄漏。
- **责任**：`T`，代理/不安全 TLS 等用户可见能力由 `O` 决定。
- **主要来源**：D-039、`PROC-13`、`NET-01` 至 `NET-13`、`MODEL-15`、`PROD-19`、`DIAG-08`、`DIAG-14`、`REL-11`、`AQ-137`、`AQ-140`、`AQ-141`、`AQ-145`、`AQ-146`、`AQ-197`、`AQ-198`、`AQ-219`、`AQ-220`、`AQ-245`、`AQ-246`、`AQ-277`、`AQ-278`、`AQ-284`、`AQ-321`、`AQ-322`、`AQ-348`、`AQ-362`、`AQ-382`、`AQ-385`、`AQ-387`、`AQ-390`、PJ-14、PJ-17、ED-13、ED-14、RF-16；技术证明 `TP-006`、`TP-007`、`TP-022`、`TP-028`、`TP-030`。

### AR-P1-03 进程和 shell dialect

- **阻塞原因**：raw command 仍需固定 Windows `cmd.exe`、Linux `/bin/sh` 或其他明确 dialect；argv 执行、stdin、inherit/clean 环境基线、ambient config、cwd、stdout/stderr、encoding/binary 判定、canonical 保留、命令物理长度、超时和进程树结果不能依赖宿主偶然行为。D-044 已排除音频采集、转写和语音输出设备/helper，不能借通用进程端口把它们复活。
- **权威工件**：process port；shell invocation/quoting/stdin contract；raw command length/encoding result；内部进程与用户 raw shell 的环境/ambient-config 分离；零 media device/codec/helper port 清单；output/cancel/result schema。
- **通过证据**：argument corpus、Unicode path、stdin 读取/交互提示、命令长度与不可表示字符、双管道满缓冲、spawn failure、timeout、descendant survival、suspend/resume 和 cwd 删除等 fixture；发行进程/helper registry 不含 capture/transcription/speech device 或 codec，子进程不能偷取 TUI/审批输入。
- **责任**：`T`；D-052 已排除交互 PTY、tracked background 和 detached job，当前只证明前台非交互路线。
- **主要来源**：`PROC-01` 至 `PROC-13`、`PROD-18`、`PROD-20`、`PROD-21`、`AQ-119` 至 `AQ-128`、`AQ-266`、`AQ-267`、`AQ-367`、`AQ-371`、`AQ-372`、`AQ-384`、`AQ-388`、`AQ-389`、`AQ-422` 至 `AQ-425`、PJ-16、PJ-19、PJ-20、M05-55、TS-37 至 TS-39；技术证明 `TP-002`、`TP-003`、`TP-005`、`TP-029`、`TP-030`。

### AR-P1-04 成本、token 和预算口径

- **阻塞原因**：D-051 已确认 v0.1 不计算金额；当前缺口是 request、reported/estimated token 和 active time 的规范化与跨 purpose 账本，不能让 UI 或 XML重新生成价格、币种或 cost budget。
- **权威工件**：usage normalization；token estimate 标记；request/token/time ledger；零 amount/currency/price/cost-budget schema。
- **通过证据**：main/side/double-check/compaction/retry 与周期 `context-name` 的 usage 不重复也不漏计；取消不伪造完成 usage；provider 未返回 usage 时只显示 unavailable/estimated；配置、XML、TUI 和 admission 中 amount/price/currency/cost-limit 字段数为零。
- **责任**：`T` 实现已确认的非金额口径。
- **主要来源**：`MODEL-09`、`MODEL-15`、`PROD-20`、`PROD-21`、`LOOP-04`、`LOOP-27`、`AQ-028`、`AQ-097`、`AQ-100`、`AQ-153`、`AQ-196`、`AQ-283`、`AQ-359`、`AQ-362`、`AQ-388`、`AQ-389`、PJ-19、PJ-20；技术证明 `TP-017`、`TP-022`。

### AR-P1-05 Prompt 原文与工作区指令范围

- **阻塞原因**：D-049 已固定 Global→Model→Permission→Context 的独立构造、特殊 purpose 边界和“不自动发现项目规则”；当前缺口是精确 segment schema、内置英文 Prompt 原文与 golden request，而不是继续选择权威链。D-042 已排除独立 plan state。
- **权威工件**：Prompt segment/source/version spec；内置英文 Prompt 原文；ContextPrompt 命令和事件；显式工具读取项目规则的 quoted-data 边界；零 PlanArtifact/plan-phase manifest。
- **通过证据**：冲突、Prompt 修改、恢复、压缩、模型切换和恶意仓库文本的 golden requests；Prompt/CLI/XML/tool registry 不含 `.plan`、`.execute`、PlanArtifact 或 plan-only capability。
- **责任**：`O` 决定人格/来源体验；`T` 固定装配顺序和安全标记。
- **主要来源**：`INSTR-01` 至 `INSTR-05`、`LOOP-18`、`LOOP-19`、`AQ-001` 至 `AQ-008`、`AQ-046` 至 `AQ-065`、`AQ-183`、`AQ-292` 至 `AQ-298`、`AQ-346`；技术证明 `TP-016`、`TP-025`。

### AR-P1-06 Context 配额、归档和保留

- **阻塞原因**：CX-11=A 已确认不公开 quota/auto-purge 字段，CX-15=C 已确认无 archive/trash/restore、只有显式永久 delete；当前缺口是 Runtime hard limit、磁盘不足、锁冲突和 known-copy 的可执行状态表。误贴 secret 不获得局部 redaction/secure erase 承诺。
- **权威工件**：版本化 Runtime capacity manifest；永久 delete/purge 状态机；零 archive/trash/restore/auto-purge/quota-field 清单；known-copy 与 best-effort/secure-erase 免责声明；显示与 self-test 规则。
- **通过证据**：边界前、恰好边界和超限 fixture；无 media、archive、trash、restore、quota 或 auto-purge 分支；永久 delete 对活动/锁定/stale 对象 fail-closed并要求非默认确认；secret canary 只证明处理了列出的 yaca 已知 generation，不声称撤回 provider 内容或物理擦除介质。
- **责任**：`T` 证明已确认 hard-limit 与永久删除路线。
- **主要来源**：`CTX-11`、`CTX-12`、`CTX-28`、`PROD-17`、`PROD-18`、`PROD-20`、`PROD-21`、`INDEX-15`、`AQ-178`、`AQ-238`、`AQ-307`、`AQ-308`、`AQ-349`、`AQ-368`、`AQ-383`、`AQ-384`、`AQ-388`、`AQ-389`、PJ-15、PJ-16、PJ-19、PJ-20；技术证明 `TP-008`、`TP-009`、`TP-010`、`TP-021`、`TP-028`。

### AR-P1-07 错误目录、诊断和 self-test

当前状态：未通过；三阶段顺序与可选启动门已确认，精确 check registry、partial/failure、输出和诊断边界仍待收口。

- **阻塞原因**：typed error/check registry 尚未冻结；D-055 已确认长期只持久化 INI/XML、fatal bootstrap error 走 stderr、无独立日志/support file/telemetry/upload/update。三阶段顺序和深度已确定，剩余是 check ID、局部历史损坏 severity、CLI 排除 grammar 与 Stage 3 输入 manifest。
- **权威工件**：error ID/category registry；错误归属和去重表；stderr/Context XML/self-test-support stdout 分工；self-test stage/check schema、Catalog scan budget 与 release-gate 规则；Stage 3 Permission/Model advisory 输入 manifest；零 telemetry/upload/update error/receipt/endpoint 清单。
- **通过证据**：每类阻断错误都显示发生了什么、保存了什么、可能副作用和下一步；Stage 1 能识别路径/mapping/Catalog/性能问题并以 partial/ScanIncomplete 如实收口；Stage 2 完整检查 enabled Model；Stage 3 只做脱敏 advisory，不自动修复或授予能力；每项 check ID 可由 TUI 与 CLI 同一 registry 选择/排除；不存在 send/check-update/download stage、endpoint、receipt 或错误空壳。
- **责任**：长期文件边界服从 D-035/D-036；`O` 决定剩余错误 UX 与 XML 诊断保留，`T` 建立 registry、脱敏和故障测试。
- **主要来源**：D-039、`DIAG-01` 至 `DIAG-14`、`REL-11`、`AQ-013`、`AQ-074`、`AQ-130`、`AQ-158`、`AQ-201` 至 `AQ-203`、`AQ-246`、`AQ-248`、`AQ-317` 至 `AQ-320`、`AQ-328`、`AQ-334`、`AQ-337`、`AQ-387`、`AQ-390`、ED-13、ED-14、RF-16；技术证明 `TP-006`、`TP-007`、`TP-017`、`TP-026`、`TP-028`、`TP-030`。

### AR-P1-08 性能与内存预算

- **阻塞原因**：大量地方写着“有界”，但未冻结冷启动、单 XML、单根镜像目录扫描与 rebind、Context 列表排序、每 turn INI bytes/digest 检查、队列、工具输出、按键反馈、取消和长会话的具体预算与超限行为。已排除的 Web/media/remote/multi-root/telemetry/upload/update 不得占用 worker 或临时空间。
- **权威工件**：最低参考机说明；小/中/压力 workload；每项软/硬预算；零排除 worker/decoder/device 账本；单根镜像扫描/rebind、稳定排序和 unchanged/changed/invalid INI workload；基准采集方法和回归容忍度。
- **通过证据**：XP x86、Win7+ x64 和 CentOS 7 的基准记录；达到硬限制时返回 typed limit error，不以 OOM/卡死作为控制流；排除能力的资源成本为零；单根大目录、镜像树搜索、稳定排序和 rebind 不饿死控制事件；每 turn 完整读取小型 INI 的 p95/峰值满足预算。
- **责任**：`J`。`O` 确认可接受体验，`T` 量测和证明。
- **主要来源**：`PROD-10`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`PERF-01` 至 `PERF-03`、`CONC-02`、`CONC-04`、`TEST-09`、`REL-11`、`AQ-194` 至 `AQ-196`、`AQ-205`、`AQ-228`、`AQ-239`、`AQ-245`、`AQ-246`、`AQ-305`、`AQ-343`、`AQ-345`、`AQ-352`、`AQ-359`、`AQ-362`、`AQ-382` 至 `AQ-390`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16；技术证明 `TP-003`、`TP-009`、`TP-021`、`TP-022`、`TP-023`、`TP-030`。

### AR-P1-09 精确名称、枚举和常量冻结

- **阻塞原因**：命令、REPL、工具、XML element/enum、error ID、颜色、超时、输出限额和预算数字一旦进入脚本/历史/XML就形成兼容面。D-054 已固定三套 CLI/action registry，D-046/D-047/D-048 固定少量公共名称；所有排除能力、启动头 master、multi-root、archive/trash、telemetry/upload/update 都必须为零名称。
- **权威工件**：name/abbreviation/action registry；enum registry；默认常量表及依据；schema versioning policy；排除能力的 zero-entry 清单。
- **通过证据**：自动唯一性检查；配置/help/Prompt/XML/tests 引用同一 registry；排除能力的公开名称、简称、enum、completion 和 schema element 数为零；rebind、永久 delete 与 `AutoRenameDisabled` 只有唯一 owner/version/state/unknown 规则；没有实现时临时起名的公共字段。
- **责任**：`O` 审阅用户可见命名；`T` 冻结机器字段和常量证据。
- **主要来源**：`PROD-17` 至 `PROD-21`、`DIAG-14`、`CLI-01`、`CLI-10`、`TUI-10`、`TOOL-16`、`FMT-06`、`CFG-18`、`REL-11`、`AQ-014`、`AQ-076`、`AQ-111`、`AQ-135`、`AQ-181` 至 `AQ-185`、`AQ-190`、`AQ-193`、`AQ-203`、`AQ-209`、`AQ-246`、`AQ-259`、`AQ-326`、`AQ-327`、`AQ-333`、`AQ-382` 至 `AQ-390`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16；技术证明 `TP-019`、`TP-024`。

### AR-P1-10 Context XML 内部 schema 与 export（D-068 修订）

当前状态：产品承诺已由 D-068 收口为 **内部格式**；门禁改为 yaca 自身正确性与 export，而非第三方 public reader。

- **阻塞原因（修订后）**：仍须冻结 **yaca 内部** 版本化 schema、迁移/拒绝不兼容文件、以及 Markdown（等）export 的稳定用户契约；不再以“独立第三方 reader 重建相同视图”为发布硬门。
- **权威工件**：内部 schema/版本策略；yaca round-trip 与故障 fixture；export 格式说明；外来 XML 经 **yaca** 导入/mapping 的状态机；zero 排除能力元素；`AutoRenameDisabled` 等 metadata。
- **通过证据**：yaca 对自产 XML 的打开/保存/恢复一致；不兼容世代明确失败；export 可用于人类/接盘 Prompt；文档不声称第三方 XML API；恶意/外来文件经 yaca 路径 fail-closed。
- **责任**：`O` 确认公开承诺；`T` 提供 conformance suite。
- **主要来源**：`CTX-05`、`CTX-15`、`CTX-25`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-041`、`AQ-042`、`AQ-161`、`AQ-180`、`AQ-185`、`AQ-186`、`AQ-210`、`AQ-237`、`AQ-246`、`AQ-306`、`AQ-349`、`AQ-383` 至 `AQ-390`、PJ-15 至 PJ-20、ED-13、ED-14、RF-16；技术证明 `TP-010`、`TP-020`、`TP-021`、`TP-028`。

### AR-P1-11 供应链、依赖更新和可复现装配

- **阻塞原因**：仓库现有 `bin/` 含未必进入发行的 sqlite3、jq、7za 等资源；每多一个 executable/DLL 都扩大 XP/Linux ABI、许可和漏洞维护面。浏览器、媒体、remote、upload/update verifier 均已排除，不能进入 allowlist。
- **权威工件**：最小 allowlist、来源/hash/license、构建 recipe、SBOM、CA 更新流程、依赖漏洞响应、negative manifest 和包内容拒绝规则。
- **通过证据**：未列组件使构建失败；所有 native 文件架构正确；从固定输入重建可解释相同产物；排除 component/asset/codec/listener/route 数为零；未使用资源不进入 zip。
- **责任**：`T`；正式包含哪些可选能力由 `O` 确认。
- **主要来源**：`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-10` 至 `REL-14`、`SUPPLY-01` 至 `SUPPLY-04`、`EXT-01` 至 `EXT-03`、`AQ-187`、`AQ-206` 至 `AQ-211`、`AQ-246`、`AQ-250`、`AQ-267`、`AQ-329`、`AQ-341`、`AQ-342`、`AQ-373`、`AQ-382` 至 `AQ-385`、`AQ-387` 至 `AQ-390`、PJ-14 至 PJ-17、PJ-19、PJ-20、ED-13、ED-14、RF-16；技术证明 `TP-001`、`TP-002`、`TP-006`、`TP-007`、`TP-029`、`TP-030`。

### AR-P1-12 文档同步和状态诚实性

- **阻塞原因**：公开 README 当前仍可能把未实现安装、Release 和旧平台支持写成现状；短参数、旧配置模板和新设计决定存在漂移。Web/媒体/remote/notification/telemetry/upload/update 排除、single-root、四层 Prompt、双协议和三目标 zip 都必须与“尚未实现”状态同时诚实表述。
- **权威工件**：实现/已确认目标/候选状态标识；optional-scope 支持/排除矩阵；文档同步清单；由 registry/schema 生成或校验的 help、模板和示例。
- **通过证据**：中英文 README、help、config template、XML examples 和决定日志同批检查；排除项既无虚假支持也无空入口；唯一镜像派生 root、rebind、永久 delete、`AutoRenameDisabled` 与实际命令、字段和 schema 一致；telemetry/upload/update 明确为零表面；不存在声明可运行但核心为空或发布链明确阻塞的表述。
- **责任**：`T` 维护同步证据，`O` 审核产品承诺。
- **主要来源**：`PROD-11`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`DOC-01` 至 `DOC-05`、`TEST-10`、`REL-11`、`AQ-208` 至 `AQ-210`、`AQ-246`、`AQ-329`、`AQ-350`、`AQ-360`、`AQ-373`、`AQ-382` 至 `AQ-390`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16；技术证明 `TP-019`、`TP-024`、`TP-030`。

## 全生命周期 readiness matrix

这张表用于防止只完成“正常聊天路径”就宣布架构就绪。每个阶段至少需要正常、取消/失败和恢复/清理三类证据。

| 生命周期阶段 | 必须通过的主要 gate | 权威规格 | 最低证据 |
| --- | --- | --- | --- |
| 下载/解压/安装 | P0-01、P0-14、P0-16、P1-11 | release manifest、安装状态表、load-path policy | 干净目标机无系统依赖启动；恶意 CWD/PATH 不劫持；产物 ABI 正确 |
| 首次启动/缺失配置 | P0-01、P0-09、P0-13、P1-07 | startup route、bootstrap allowlist、CLI grammar | 缺失/损坏/有效配置与 TTY/非 TTY 组合得到唯一结果 |
| 配置与 self-test | P0-03、P0-08、P0-09、P1-02、P1-07、P1-08 | typed schema、per-turn `ConfigGeneration`、self-test check registry | 静态检查离线；Context/catalog partial 可见；Stage 3 Permission advisory 不授权；联网/费用显式；Key 无泄漏 |
| 创建/恢复/浏览 Context | P0-10、P0-11、P0-13、P0-15、P1-06、P1-08 | XML schema、path codec、open/recovery protocol、canonical sort metadata | 新建 no-replace；旧/坏/锁定/外部移动/缺依赖可解释；活动锁外部零 mutation；六种排序稳定且不改变 Resolver |
| D-044 零表面 + D-045 单根 + D-046 命名标记 | P0-01、P0-03 至 P0-06、P0-08 至 P0-11、P0-13 至 P0-16、P1-01 至 P1-04、P1-06、P1-08 至 P1-12 | zero-surface manifest、single-root derivation/rebind、zero-multi-root schema、`AutoRenameDisabled` fixtures、权限与兼容矩阵 | Web、图像、音频、remote、transcription、TTS 和 multi-root 表面在配置/help/schema/Runtime/zip 为零；唯一 root 由 XML 镜像父目录解码；命名标记在 XML/REPL/迁移中一致 |
| 用户输入和主模型请求 | P0-02 至 P0-05、P0-08 | AgentLoop、Prompt、ModelEvent、TUI input | 输入先 durable；流式/取消/提问/拒答/截断 trace 正确 |
| 工具调用和副作用 | P0-06、P0-07、P0-14、P0-15、P1-03 | tool registry、permission matrix、operation protocol | 审批绑定确定动作；外改冲突；未知副作用不重放 |
| queue/steer/side/审批 | P0-02、P0-04、P0-05、P0-13、P0-15 | message/control schema、command-state table | 各自独立身份、取消、预算和恢复；不会污染主历史或自动授权 |
| 取消/退出/崩溃 | P0-04、P0-10、P0-15、P1-07 | close stack、durable points、recovery table | 每个状态故障注入；真实/合成结果配对；unknown 被保留 |
| 压缩/模型切换 | P0-03、P0-08、P0-10、P0-12、P1-04 | model-view/compaction schema、switch preflight | 完整事实不丢；Prompt/工具对保持；跨 endpoint 明确确认 |
| rename/rebind/permanent-delete/import | P0-08、P0-10、P0-11、P0-13、P1-06、P1-10 | mutation/import state machine | no-replace、stale snapshot、碰撞、恶意 XML 和 active Context 场景 |
| Telemetry/诊断上传/内建更新零表面 | P0-01、P0-08、P0-09、P0-13、P0-14、P0-16、P1-02、P1-07、P1-11、P1-12 | zero-surface manifest、手工发布/迁移契约 | 命令、字段、endpoint、request purpose、后台请求、receipt、UpdateManifest 和下载组件均为零；RF-03 的手工迁移不产生 updater |
| 升级/迁移/降级 | P0-01、P0-09、P0-10、P0-16、P1-10 至 P1-12 | version policy、migration/rollback protocol | 原文件不破坏；新版对旧程序只读/拒绝明确；失败可回退 |
| 发布/维护 | P0-16、P1-08、P1-11、P1-12 | test matrix、scope/component manifest、SBOM、build recipe、support policy | 每个声明平台真实测试；排除能力负向扫描、选入能力完整证据与源码/产物/配置 schema 版本对应 |

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
| `REL-04` | D-056 | 待生成 luainstaller Win32/Win64 qualification 与必要适配规格 | x86/x64 产物、PE imports、XP/Win7 launch、完整闭环 | 产品范围已定，发布证据阻塞 |

## 当前已知发布证据阻塞

### luainstaller Windows x86/XP

当前 `../luainstaller` 1.0 能识别 x86，但默认 Windows profile guard 会拒绝非 x86_64，随附 MSVC recipe/tests 也固定为 x64。它说明当前路径尚不能发布 x86 包，不说明底层设计不能适配 x86；代码中没有 XP 专用拒绝，而 XP 兼容也完全未证明。解除 release veto 需要：

1. 使用已经确认的 qualification 范围，并只在证据明确需要时修改兄弟仓库；
2. 先审计和试构建现有 launcher/bundler，确认哪些部分已经架构无关；
3. 只按证据做必要的 guard、toolchain、profile、Lua 5.5 runtime 或 CRT/API 适配；
4. 为 luainstaller 自身建立 x86 生成/打包/错误/安全与 XP 至 11 测试；
5. yaca 再消费一个已经由证据证明的版本和产物 manifest。

在这项前置未解决前，可以继续完成设计、验证计划和经单独授权的可丢弃技术证明；仍不能开始产品实现，也不能把 Windows 发布计划标为可执行完成路径。任何技术证明进入正式实现前，仍需通过本文件的 readiness 与逐子系统实施计划。

### 当前 `bin/` ABI 与来源

当前 Linux `bin/` executable 是 ELF32/i386，而目标是 Linux x86_64。它们不能通过“在 x86_64 系统上偶尔能启动”获得发布资格。所有 Linux 工具必须换成目标 ABI 的受控构建，并在 CentOS 7 基线上验证。

当前 Windows executable/DLL 多为 PE32 x86，这只满足架构外观；仍需验证 XP 最低 API、CRT、TLS、签名/来源、依赖 DLL、命令行/Unicode 和许可证。UPX 或其他包装也必须进入来源和恶意软件误报评估，不能视为透明细节。

## 负责人回复后的处理顺序

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
- 所有进入 v0.1 的 P1 gate 已关闭；明确排除的能力具有非目标决定，并由最终配置/help/schema/registry/zip 的 zero-surface 证据证明没有半实现边界；选入的 optional surface 具有对应旧平台、安全、隐私、恢复和发布证据。
- 所有项目负责人必须决定的分支已有明确回复并归档；任何未回复推荐仍保持候选。
- 每个子系统拥有单一权威规格，正常、取消、失败、恢复、资源上限和目标平台差异均无实现者猜测空间。
- AgentLoop、Model、Tool、Permission、Context XML、CLI/TUI 使用同一套 ID、事件、错误和状态语义。
- 配置 schema、XML schema、命令/工具 registry、错误目录和测试 fixture 之间可以机械校验关键字段与枚举。
- requirement→spec→test matrix 对全部 P0/P1 没有缺失链接。
- luainstaller Win32/x86 qualification 已完成，或已获授权并作为实施计划中的硬前置证明/必要适配任务；现有错误 ABI 资源没有被当作可发布依赖。
- 实施计划能够只拆任务、测试和提交顺序，不再承担未决产品设计。

若任一证据缺失、只间接支持结论或仍依赖“实现时再决定”，readiness 状态必须保持未通过。
