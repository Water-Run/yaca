# yaca 设计决策路线图

更新日期：2026-07-22

状态：负责人答复前的历史路线图；270 组现已全部收口，本文件不再指向下一批问卷

> 现行状态只看 [`DECISION-REGISTER.md`](DECISION-REGISTER.md)、[`DECISIONS.md`](DECISIONS.md) 与 [`ARCHITECTURE-READINESS.md`](ARCHITECTURE-READINESS.md)。本文件保留当时如何组织问题和区分产品选择/技术证明的理由；其中“当前批次”“未回答”和候选推荐都是收到 Batch 06 之前的历史语境，不能覆盖 D-049 至 D-057。

## 这份路线图解决什么问题

此前的 20 个综合问题太宽，后来的 250 个原子问题虽覆盖更广，却仍像一份审计索引：项目负责人可以回答很多零件，但不一定能看见它们最终拼出的启动旅程、页面、AgentLoop 和失败恢复。

多轮闭环审计把材料分成四个层次：

1. [原子问题题库](QUESTIONS.md) 现有 `AQ-001` 至 `AQ-437`，负责证明没有漏掉关键分支、依赖和失败路径。
2. `decision-packets/` 把原子问题重新组织成九个主包和一个持续收口跨系统接缝的补缝包。这里才是项目负责人主要阅读和回复的材料；每包有实际 transcript、状态表或场景、2--3 套完整方案、推荐和代价。
3. [分批队列](DECISION-BATCH-QUEUE.md) 按真实上游依赖把跨 packet 的问题重组为 49 个回复批次，并在末尾做一次不重复投票的全局一致性 gate；它决定阅读节奏，不拥有选择状态。
4. [实施就绪门](ARCHITECTURE-READINESS.md) 检查回复是否已经转成状态机、schema、矩阵、测试和平台证据。题库答过不等于实现规格完成。

[`LIVE-DESIGN-COVERAGE.md`](LIVE-DESIGN-COVERAGE.md) 另做当前闭包审计：逐一证明 checklist/AQ 有负责人组、已确认决定、技术证明或明确排除路线，但不另存任何回复状态。

逐组现行状态另由 [设计决策实时登记表](DECISION-REGISTER.md) 唯一记录；它锁定 `decision-inventory-v9` 的 270 组 inventory、条件、原话和传播位置。路线图负责解释全局依赖，不再靠聊天记忆判断“答到哪里”。

完整配置字段另有 [配置 schema 候选](CONFIG-SCHEMA-CANDIDATE.md) 和 [配置完整性专项审计](CONFIG-COMPLETENESS-AUDIT.md)，其跨字段验证连续覆盖 `CV-001` 至 `CV-076`；跨 Model、存储、显示与导出的边界另有 [数据分类候选](DATA-CLASSIFICATION-CANDIDATE.md)。它们是逐字段/逐数据类别审阅底稿，不会因写得详细就自动成为正式契约。技术可行性不混入负责人偏好题，统一进入 [技术证明积压](TECHNICAL-PROOF-BACKLOG.md)。

## 决策流怎么进行

负责人问卷阶段曾以登记表指出的 `Bxx` 为单位讨论；一批可以跨越多个 owner packet，因此只打开这一批涉及的正式 group 正文，而不是先把某个 packet 全部答完。当时的回复 grammar 如下：

```text
PJ-01 选 A。
PJ-04 接受推荐，但“最近 Context”只提示，不默认选中。
PJ-05 暂缓；先解释内存候选与第一次持久化的差异。
```

收到回复后的归档事务仍适用于未来被证据重新打开的最小差异；逐条状态、回复 grammar、冲突处理和规格提升规则以 [`DECISION-RESOLUTION-PROTOCOL.md`](DECISION-RESOLUTION-PROTOCOL.md) 为准：

1. 把原话按 inventory 锁定到 `DISCUSSION-BATCH-NN.md`，更新 `DECISION-REGISTER.md`；没有回答的项继续 `unanswered`。
2. 把明确选择归档或链接到 `DECISIONS.md`，例外/冲突/取代保持可追踪。
3. 更新相关子系统文档，消除旧草案漂移，并把选择展开成状态、数据、错误和验收契约。
4. 更新 `QUESTIONS.md` 的原子项状态和跨包依赖；同一决定覆盖的推导项必须可追踪。
5. 对照 `ARCHITECTURE-READINESS.md` 检查还缺产品选择、技术原型还是平台证据。

推荐不采用“整包回复一个接受”来掩盖例外。若负责人确实接受整包，可回复“本包全部接受推荐，以下条目除外……”，仍会逐项归档。

## 十个成套决策包

现行清单共 **270 组负责人决定**：`PJ 19 + PP 18 + TU 32 + M05 57 + AL06 49 + TS 35 + CX 16 + ED 14 + RF 14 + F4 16`。这不是把 437 个原子问题换个编号重抄，而是多轮问题质量、体验和交叉传播审阅后的 live inventory：隐藏在说明段里的体验/控制轴已升格，捆绑的配置、安全和导入选择已拆开，Web、图像、音频输入、独立转写、TTS、remote/headless、多根、aggregate telemetry、一次性诊断上传和更新发现/下载也分别拥有 owner，raw shell/direct input schema 不再藏在技术描述里，重复 owner 与纯 API/算法/测试组织投票已经移回技术证明。v9 又补出此前被候选 schema 或安全说明暗定的六轴：资源 selector/简称、per-Model retry 配置面、过短配置秘密政策、stuck 阈值来源、特殊 purpose 跨 Endpoint 同意寿命和 reserved tree 精确读取。

最新拆分继续覆盖 composer 输入召回、配置秘密文件权限、raw shell 继承环境、完整 model-yield 后续接、direct 文件属性、ignore/隐藏项、`exec` cwd、输出解码与 canonical 保留，以及 active XML 外部移动/替换/改写恢复。最终五个去捆绑轴是 TU-32 chat dot-command root、TU-33 输入提示符、TU-34 审批动作 grammar、M05-56 SensitiveRead 字段存在性和 AL06-49 termination-review Model 来源；它们分别独立于顶层 CLI、正文标签、空 Enter、安全 outside 粒度和 action-review Model。所有推荐均未因进入 inventory 而成为决定。

原子题库比负责人决定更多，是因为一个产品选择常常需要同时约束多个字段、失败分支和测试点；不要求负责人机械回答 437 个 AQ。270 组已经通过集中问卷全部收口：现行登记为 265 个 active、5 个 `not-applicable`、0 个 `unanswered/conflict`。旧分批节奏只作审计证据，下一步是机械展开 owner 规格和技术证明，不是继续按 49 批提问。

| 包 | 负责人真正决定什么 | 必须随包可见的材料 | 主要原子问题 |
| --- | --- | --- | --- |
| [02 产品旅程与表面地图](decision-packets/02-product-journey-and-surfaces.md) | 裸启动、新建/继续、空 Context、锁冲突、恢复入口、退出；Web、图像、音频输入、转写、TTS、remote/headless 与多根是否成为正式表面 | 启动路由、无配置/正常/最近 Context/writer 冲突 transcript，以及各范围轴的零表面或条件规格 | `AQ-011`、`AQ-046`--`AQ-049`、`AQ-212`--`AQ-217`、`AQ-229`、`AQ-313`--`AQ-316`、`AQ-382`--`AQ-386`、`AQ-388`--`AQ-389` |
| [03 Prompt、人格与工作区指令](decision-packets/03-prompt-personality-and-instructions.md) | 权威链、SystemPrompt/ContextPrompt、默认语言/风格、进度、回答详略、普通指令生命周期、最终报告、项目规则、Prompt 升级 | 同一任务三套回复样例、Prompt stack、purpose views、最终报告 | `AQ-001`--`AQ-008`、`AQ-050`--`AQ-065`、`AQ-183`、`AQ-251`--`AQ-260`、`AQ-292`--`AQ-298`、`AQ-357`--`AQ-359`、`AQ-391`--`AQ-392` |
| [04 TUI 视觉、输入与 CLI 体验](decision-packets/04-tui-visual-input-cli-experience.md) | transcript 样式、ASCII 标签、密度、颜色、快捷键后备、多行/粘贴、draft、输入召回、通知、审批/错误/REPL 页面、chat command root、输入提示符、审批动作 grammar、modal 命令、fd 模式与 help | 80×24、40 列、XP 无色、忙时输入、tool/diff/error/self-test 页面；状态输入矩阵、composer 召回生命周期与独立 stdin/stdout/stderr 拓扑 | `AQ-009`--`AQ-015`、`AQ-066`--`AQ-090`、`AQ-181`--`AQ-193`、`AQ-231`--`AQ-233`、`AQ-264`--`AQ-265`、`AQ-299`--`AQ-302`、`AQ-326`--`AQ-340`、`AQ-351`--`AQ-356`、`AQ-360`、`AQ-375`--`AQ-377`、`AQ-398`、`AQ-413`、`AQ-426`--`AQ-429` |
| [05 Model、配置、网络与 self-test](decision-packets/05-model-configuration-network-selftest.md) | 完整 Model 实例、协议、流式三态、明文配置秘密、HTTP、配置 schema、资源 selector、per-Model retry、短 secret、REPL/reset、代理/TLS、日志去留、Permission outside 粗/细与独立 SensitiveRead 字段、继承环境与三阶段 self-test | 旧模板与候选字段逐项审计、跨字段校验、秘密/metadata 生命周期、model/config REPL 和 self-test 页面/consent | `AQ-016`--`AQ-018`、`AQ-074`--`AQ-083`、`AQ-131`--`AQ-160`、`AQ-197`--`AQ-202`、`AQ-218`--`AQ-222`、`AQ-245`--`AQ-248`、`AQ-276`--`AQ-291`、`AQ-317`--`AQ-325`、`AQ-348`、`AQ-374`、`AQ-378`、`AQ-407`--`AQ-409`、`AQ-411`、`AQ-417`、`AQ-423`、`AQ-430`、`AQ-432`--`AQ-433`、`AQ-437` |
| [06 AgentLoop、忙时动作、DoubleCheck 与压缩](decision-packets/06-agentloop-busy-doublecheck-compaction.md) | task finish 信号、turn/request、queue/steer/side/cancel、复核顺序与人工解算、action/termination review 独立 Model 来源、跨 Endpoint 同意、turn guard、预算/stuck 阈值来源、approval 恢复、Model 切换、完整 model-yield 续接、自动与手动压缩 view | 状态转换表、四条忙时动作时序、typed outcome、model-yield continuation、复核拒绝/人工解算、压缩结构与 manual-compaction 生命周期 | `AQ-019`--`AQ-032`、`AQ-091`--`AQ-110`、`AQ-234`--`AQ-243`、`AQ-251`--`AQ-260`、`AQ-279`--`AQ-281`、`AQ-309`--`AQ-311`、`AQ-321`、`AQ-324`--`AQ-325`、`AQ-359`、`AQ-379`、`AQ-393`--`AQ-395`、`AQ-410`、`AQ-412`、`AQ-421`、`AQ-431`、`AQ-434`--`AQ-435` |
| [07 Tool Calling、安全、进程与运行时](decision-packets/07-tools-safety-process-runtime.md) | 模型可见 raw tool、raw/direct input schema、direct 文件细粒度与属性、ignore/隐藏项、reserved tree exact-read、宽 Shell/background jobs 权限、`exec` cwd/输出语义、审批/unknown、原生 event port、路径/特殊文件、秘密传递 | tool input/result registry、tool×capability 矩阵、reserved-object 矩阵、审批卡、operation/background 状态、cwd/bytes/canonical output 契约、I/O ABI 和取消时序 | `AQ-033`--`AQ-040`、`AQ-111`--`AQ-130`、`AQ-203`、`AQ-223`--`AQ-226`、`AQ-239`、`AQ-249`--`AQ-250`、`AQ-254`--`AQ-258`、`AQ-261`--`AQ-278`、`AQ-312`、`AQ-322`--`AQ-323`、`AQ-399`--`AQ-406`、`AQ-414`--`AQ-416`、`AQ-418`--`AQ-419`、`AQ-422`、`AQ-424`--`AQ-425`、`AQ-436` |
| [08 Context XML、索引、恢复与可移植接盘](decision-packets/08-context-xml-index-recovery.md) | 单 XML 的语义/物理边界、公开读取契约、事件和 snapshot、锁/提交/backup、active XML 外改恢复、导入信任/兼容缺口、Resolver/浏览器、配额 | XML 概念 schema、ID 表、崩溃点真值表、外部移动/替换/改写恢复页、跨机 mapping、compatibility gate、目录树/搜索页面 | `AQ-041`--`AQ-045`、`AQ-161`--`AQ-180`、`AQ-186`--`AQ-190`、`AQ-227`--`AQ-230`、`AQ-235`--`AQ-238`、`AQ-244`、`AQ-257`--`AQ-260`、`AQ-274`--`AQ-278`、`AQ-303`--`AQ-311`、`AQ-347`、`AQ-349`、`AQ-354`--`AQ-356`、`AQ-380`、`AQ-420` |
| [09 错误、诊断、关闭与兼容体验](decision-packets/09-errors-diagnostics-compatibility.md) | error/retry/cancel/close、日志只用 INI/XML 的准确含义、本地 support、aggregate telemetry 与一次性 diagnostic upload、旧终端/平台能力降级 | error/retry/recovery transcript、退出类别、诊断 schema、两条网络诊断轴的零表面/条件契约与兼容失败 | `AQ-069`、`AQ-103`、`AQ-158`、`AQ-201`--`AQ-203`、`AQ-229`--`AQ-231`、`AQ-238`、`AQ-246`--`AQ-248`、`AQ-314`--`AQ-321`、`AQ-328`、`AQ-334`、`AQ-339`--`AQ-340`、`AQ-390` |
| [10 测试、性能、发布与实施冻结](decision-packets/10-release-testing-and-readiness-freeze.md) | zip/数据升级、显式更新发现/下载、哪些数字由实测决定、故障注入/soak、平台完整测试、供应链证据、何时允许写实施计划 | readiness gate、requirement→spec→test→evidence、性能 workload、发布与更新硬门 | `AQ-181`--`AQ-211`、`AQ-244`、`AQ-303`--`AQ-305`、`AQ-329`--`AQ-330`、`AQ-341`--`AQ-346`、`AQ-350`、`AQ-357`、`AQ-360`、`AQ-387` |
| [11 跨系统运行接缝与遗漏收口](decision-packets/11-cross-system-operational-seams.md) | 配置外改、Model 调度、ask-user/retry、draft/details、raw stdin、秘密删除、管理事务、文件系统、workspace 失效、扩展关闭与单进程 Context 边界 | 十六个敌对场景、旧组去重表、回复后必须生成的规格增量 | `AQ-361`--`AQ-373`、`AQ-381`、`AQ-396`--`AQ-397` |

交叉引用是有意的。例如 finish control 同时影响 Prompt/协议与 AgentLoop；Key 生命周期同时影响配置、网络与安全。最终权威只会在一个子系统规范中定义，其他包说明用户体验和依赖，不复制两套事实。

## 建议讨论顺序

正式顺序以 [`DECISION-BATCH-QUEUE.md`](DECISION-BATCH-QUEUE.md) 为准，而不是把 `02 → ... → 11` 每包答完。队列会把同一用户旅程或同一状态边界的跨包问题放在一起，例如在启动/退出批次提前询问单进程 Context 数量，在压缩主形态确认后才询问手动压缩。宏观依赖仍是：

```text
产品旅程
  -> Agent 是怎样说话、用户看见哪些表面
  -> Model/配置/网络能提供哪些真实能力
  -> AgentLoop 怎样调度这些能力
  -> 工具与安全怎样约束副作用
  -> XML 怎样保存和恢复全部事实
  -> 错误、发布与平台怎样兑现同一体验
  -> 用测试与证据冻结实施边界
  -> 用跨系统失败场景检查责任是否仍有空洞
```

如果希望先解决最高风险，可以在 02 后插入以下正式组；纯技术证明单独列出，不让负责人按 AQ 编号猜实现事实：

1. `AL06-02`、`AL06-36`、`AL06-38`：模型如何明确区分完成、部分完成、提问和普通无 control 回复。
2. `TS-04`、`CX-07`、`CX-14`：raw shell 的真实权限，以及导入 XML 不能带来新授权。
3. `CX-01`、`CX-05`、`CX-11`：单 XML、durable/恢复路径、大小硬门和性能失败后的产品退路。
4. `TS-08`：首版是否承诺自动 undo；当前推荐是不承诺。
5. **技术证明而非负责人问题**：`TP-003` 证明 XP/CentOS 的事件泵、流式输入与取消；`TP-008..TP-010` 证明 XML 提交、写放大和 parser。证明失败且会改变产品保证时，才带最小退路重新询问。

## 已经不能靠一句“选最合适”自动消除的矛盾

### 1. “单 XML 始终完整”与高频 durable 写入

标准 well-formed XML 在根结束标签后不能原地追加子节点。每次 canonical event 都生成完整新 XML 可保持正确，却使长会话累计 I/O 成为 O(n²)。WAL/recovery sidecar 可以改善性能，但活动期间事实不再只在正式 XML。

因此先以“完整流式重写 + 原子/可恢复 replace”做正确性基线和 benchmark；若在 XP x86/旧磁盘超过负责人确认的门，必须明确允许短期 recovery WAL 或调整承诺。所谓“选择合适 XML 库”不会自动解决这个物理问题。

### 2. “相信模型的 raw shell”与细粒度权限

没有 OS sandbox 时，允许 shell 就意味着命令可能读、写、删、联网和访问工作区外。Runtime 无法可靠解析任意 `cmd.exe`/`sh` 字符串再保证 `Write=deny` 或 `Network=deny`。

因此权限界面必须诚实：raw shell 只能显示和求值为宽 `Shell/Execute` 能力，不能伪装成受 Read/Write/Network 逐项隔离；`Readonly`、`Std` 与其他发行 profile 的精确三态值仍由 `TS-04` 决定。direct file tools 可以继续受细粒度能力约束，Model provider 网络则由选择 Model 本身授权。

### 3. “英文/ASCII”与真实中文路径

程序自带标签、枚举和配置键可以全部使用英文 ASCII；但项目负责人已明确以中文 Context 路径为核心例子。若禁止非 ASCII 用户数据，就无法支持该已确认场景。

当前推荐是：UI 固定 English/ASCII；用户正文、路径、文件名和 XML 使用 UTF-8；Windows 原生层使用 wide API；终端显示能力不足时可见转义，但 hash 与文件操作始终使用真实规范数据。

### 4. “单线程 Lua”与流式时继续输入/取消

Lua coroutine 不会把阻塞 console、pipe 或 process wait 自动变成异步。核心仍可保持单线程状态所有者，但平台层必须用 OS 异步能力、极小原生线程或 helper 把 I/O 变成事件。

Windows XP 不能依赖最低 Vista 的 `CancelIoEx`/`CancelSynchronousIo`。候选 ABI 必须先以最小原型证明 console、curl SSE、stdout/stderr、进程树和 XML 屏障能同时工作，再写实现计划。

### 5. “复制 XML 可接盘”与导入安全

XML 可以完整保存历史 Permission、DoubleCheck、ContextPrompt 和 approval，但它们是历史事实，不是目标机器的新授权。外部 XML 也可能是恶意输入，digest chain 只能发现损坏，不能认证作者。

当前推荐是：历史忠实保留；审批永远 audit-only；继续运行时用本机配置重新计算有效安全状态；任何降低本机默认的覆盖都显著展示并让当前用户确认。

### 6. “明文 Key 保持简单”与 curl 子进程

Key 留在 INI 已得到方向性回复，但它仍需要从 Lua 安全到达 curl。放 argv 会出现在进程列表，放环境会被子进程继承，临时 config/body 又有权限与崩溃残留。

配置包会比较“config 走 stdin/body 走私有 temp”“body 走 stdin/secret config 走私有 temp”“窄 libcurl bridge”三条路线；这属于必须有技术证据的实现选择，不能用一句“不记日志”代替。

## 谁来决定什么

| 类型 | 负责人决定 | 技术设计/原型负责 | 例子 |
| --- | --- | --- | --- |
| 产品语义 | 用户看见什么、默认动作、允许哪些能力、失败后选择 | 把选择展开成一致状态和 schema | 裸启动是否提示最近 Context；side 是否要求即时并发 |
| 安全取舍 | 哪些风险可接受、何时人工批准、是否允许 WAL/undo | 证明 enforcement 不变量和绕过边界 | raw shell 宽能力；导入 XML 安全降级 |
| 体验风格 | transcript 密度、标签、语言、回复人格 | 旧终端降级和 golden transcript | 稀疏 transcript 或 ASCII 框 |
| 技术可行性 | 只确认目标和可接受退路 | 以原型、benchmark、平台测试选择 API/常量 | XP 事件泵；XML 提交延迟；curl Key 传递 |
| 精确常量 | 确认性能/费用/等待体验的上下限偏好 | 在最低机器实测后提出数字 | refresh interval、XML hard size、kill grace |

负责人不需要凭感觉选择 `ReadConsoleInput` 还是 IOCP，也不需要现在填写毫秒数。技术侧必须先给出能运行的证据、失败边界和最小方案；只有当两条路线改变产品承诺时才返回负责人取舍。

## 回复完成后仍要产出的权威规格

全部包回答后，还需要把决定落成下列实现前工件；它们不是新一轮无限讨论，而是对已选语义的机械展开与审阅：

1. 启动、恢复、退出、升级生命周期表。
2. AgentLoop 状态机、event/terminal outcome 枚举、command × state 表。
3. canonical Model request/provider event/response/error 契约。
4. 内置 tool registry、参数/result schema 与 tool × capability 矩阵。
5. 完整 typed config schema、INI grammar、XML override 白名单和迁移表。
6. Context XML schema、局部 ID 表、commit/lock/backup/recovery 协议及 fixtures。
7. Context Resolver/hash/path、浏览器分页与 stale selection 规范。
8. compaction view 算法与结构化 summary schema。
9. CLI registry、点命令 grammar、stdout/stderr 和 exit classes。
10. TUI 页面 golden transcripts、所有状态下的输入矩阵和能力降级表。
11. platform/process/network/terminal port ABI 与 native helper manifest。
12. error/data-classification/diagnostic schema。
13. release manifest、构建链、性能/fault/soak/platform test matrix。
14. requirement → decision → spec → test → target evidence 双向追踪。

只有 [实施就绪门](ARCHITECTURE-READINESS.md) 中的 P0 全部通过，才调用 planning 流程编写逐系统实施计划。现在仍处于设计讨论期，不开始编码。

## 当前发布证据阻塞

- 相邻 `../luainstaller` 1.3.0 已支持 native x86/x86_64 profile，并提供 XP API/subsystem、MinGW import closure 与 Linux native x86 的 upstream modern 证据；此前 1.0 的 x86 guard 风险事实已经失效。当前仍须固定版本、构建 yaca-specific Lua 5.5/依赖闭包并完成 XP 至 11、Win7 至 11 和 CentOS 7 验收。
- 当前 Linux `bin/` 是 ELF32，其中 curl 为 x32 ABI；不是目标的普通 CentOS 7 x86_64 发行输入。
- 当前 Win32 `curl.exe` 经 UPX 压缩，现有静态 imports 主要是解压 stub；PE 头 4.0 不能证明真实 XP 兼容。

这些问题不会阻止继续完成产品/架构设计，但会阻止发布实施计划宣称已经可构建。
