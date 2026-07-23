# yaca 设计决策路线图

更新日期：2026-07-18

状态：讨论材料；尚未得到项目负责人明确回复的推荐均不是决定

## 这份路线图解决什么问题

此前的 20 个综合问题太宽，后来的 250 个原子问题虽覆盖更广，却仍像一份审计索引：项目负责人可以回答很多零件，但不一定能看见它们最终拼出的启动旅程、页面、AgentLoop 和失败恢复。

第三轮闭环审计把材料分成三个层次：

1. [原子问题题库](QUESTIONS.md) 现有 `AQ-001` 至 `AQ-373`，负责证明没有漏掉关键分支、依赖和失败路径。
2. `decision-packets/` 把原子问题重新组织成九个主包和一个第四轮跨系统补缝包。这里才是项目负责人主要阅读和回复的材料；每包有实际 transcript、状态表或场景、2--3 套完整方案、推荐和代价。
3. [实施就绪门](ARCHITECTURE-READINESS.md) 检查回复是否已经转成状态机、schema、矩阵、测试和平台证据。题库答过不等于实现规格完成。

完整配置字段另有 [配置 schema 候选](CONFIG-SCHEMA-CANDIDATE.md) 和 [配置完整性专项审计](CONFIG-COMPLETENESS-AUDIT.md)，跨 Model、存储、显示与导出的边界另有 [数据分类候选](DATA-CLASSIFICATION-CANDIDATE.md)。它们是逐字段/逐数据类别审阅底稿，不会因写得详细就自动成为正式契约。技术可行性不混入负责人偏好题，统一进入 [技术证明积压](TECHNICAL-PROOF-BACKLOG.md)。

## 决策流怎么进行

每次只打开一个决策包，按包内编号讨论。项目负责人可以这样回复：

```text
PJ-01 选 A。
PJ-02 接受推荐，但“最近 Context”只提示，不默认选中。
PJ-03 暂缓；先解释锁冲突下只读打开的代价。
```

收到回复后依次做四件事；逐条状态、回复 grammar、冲突处理和规格提升规则以 [`DECISION-RESOLUTION-PROTOCOL.md`](DECISION-RESOLUTION-PROTOCOL.md) 为准：

1. 把明确选择和负责人原话写入 `DECISIONS.md`；没有回答的项继续待决。
2. 更新相关子系统文档，消除旧草案漂移，并把选择展开成状态、数据、错误和验收契约。
3. 更新 `QUESTIONS.md` 的原子项状态和跨包依赖；同一决定覆盖的推导项必须可追踪。
4. 对照 `ARCHITECTURE-READINESS.md` 检查还缺产品选择、技术原型还是平台证据。

推荐不采用“整包回复一个接受”来掩盖例外。若负责人确实接受整包，可回复“本包全部接受推荐，以下条目除外……”，仍会逐项归档。

## 十个成套决策包

现行清单共 **187 组负责人决定**：`PJ 12 + PP 12 + TU 19 + M05 40 + AL06 36 + TS 17 + CX 13 + ED 12 + RF 13 + F4 13`。这不是把 373 个原子问题换个编号重抄，而是第五轮问题质量审阅后的 live inventory：隐藏在说明段里的体验/控制轴已升格，捆绑的配置、安全和导入选择已拆开，重复 owner 与纯 API/算法/测试组织投票已经移回技术证明。

原子题库比负责人决定更多，是因为一个产品选择常常需要同时约束多个字段、失败分支和测试点；不要求负责人机械回答 373 个 AQ。反过来，187 也不是必须一次答完的考试，可以每次只讨论一包或一小组；未明确回复的编号保持 `unanswered`。

| 包 | 负责人真正决定什么 | 必须随包可见的材料 | 主要原子问题 |
| --- | --- | --- | --- |
| [02 产品旅程与表面地图](decision-packets/02-product-journey-and-surfaces.md) | 裸启动、新建/继续、空 Context、锁冲突、恢复入口、退出；有哪些正式页面 | 启动路由、无配置/正常/最近 Context/writer 冲突 transcript | `AQ-011`、`AQ-046`--`AQ-049`、`AQ-212`--`AQ-217`、`AQ-229`、`AQ-313`--`AQ-316` |
| [03 Prompt、人格与工作区指令](decision-packets/03-prompt-personality-and-instructions.md) | 权威链、SystemPrompt/ContextPrompt、默认语言/风格、进度、最终报告、项目规则、Prompt 升级 | 同一任务三套回复样例、Prompt stack、purpose views、最终报告 | `AQ-001`--`AQ-008`、`AQ-050`--`AQ-065`、`AQ-183`、`AQ-251`--`AQ-260`、`AQ-292`--`AQ-298`、`AQ-357`--`AQ-359` |
| [04 TUI 视觉、输入与 CLI 体验](decision-packets/04-tui-visual-input-cli-experience.md) | transcript 样式、ASCII 标签、密度、颜色、快捷键后备、多行/粘贴、draft、审批/错误/REPL 页面 | 80×24、40 列、XP 无色、忙时输入、tool/diff/error/self-test 页面；状态输入矩阵 | `AQ-009`--`AQ-015`、`AQ-066`--`AQ-090`、`AQ-181`--`AQ-193`、`AQ-231`--`AQ-233`、`AQ-264`--`AQ-265`、`AQ-299`--`AQ-302`、`AQ-326`--`AQ-340`、`AQ-351`--`AQ-356`、`AQ-360` |
| [05 Model、配置、网络与 self-test](decision-packets/05-model-configuration-network-selftest.md) | 完整 Model 实例、协议、流式三态、明文 Key、HTTP、配置 schema、REPL/reset、代理/TLS、日志去留、Permission 字段、三阶段 self-test | 旧模板与候选字段逐项审计、跨字段校验、Key/metadata 生命周期、model/config REPL 和 self-test 四屏 | `AQ-016`--`AQ-018`、`AQ-074`--`AQ-083`、`AQ-131`--`AQ-160`、`AQ-197`--`AQ-202`、`AQ-218`--`AQ-222`、`AQ-245`--`AQ-248`、`AQ-276`--`AQ-291`、`AQ-317`--`AQ-325`、`AQ-348` |
| [06 AgentLoop、忙时动作、DoubleCheck 与压缩](decision-packets/06-agentloop-busy-doublecheck-compaction.md) | task finish 信号、turn/request、queue/steer/side/cancel、复核顺序、预算/stuck、Model 切换、压缩 view | 状态转换表、四条忙时动作时序、typed outcome、复核拒绝、压缩结构 | `AQ-019`--`AQ-032`、`AQ-091`--`AQ-110`、`AQ-234`--`AQ-243`、`AQ-251`--`AQ-260`、`AQ-279`--`AQ-281`、`AQ-309`--`AQ-311`、`AQ-321`、`AQ-324`--`AQ-325`、`AQ-359` |
| [07 Tool Calling、安全、进程与运行时](decision-packets/07-tools-safety-process-runtime.md) | 模型可见 raw tool、直接文件工具、宽 Shell 权限、审批/unknown、原生 event port、路径/特殊文件、Key 传递 | tool registry/result schema、tool×capability 矩阵、审批卡、operation 状态、I/O ABI 和取消时序 | `AQ-033`--`AQ-040`、`AQ-111`--`AQ-130`、`AQ-203`、`AQ-223`--`AQ-226`、`AQ-239`、`AQ-249`--`AQ-250`、`AQ-254`--`AQ-258`、`AQ-261`--`AQ-278`、`AQ-312`、`AQ-322`--`AQ-323` |
| [08 Context XML、索引、恢复与可移植接盘](decision-packets/08-context-xml-index-recovery.md) | 单 XML 的语义/物理边界、公开读取契约、事件和 snapshot、锁/提交/backup、导入信任、Resolver/浏览器、配额 | XML 概念 schema、ID 表、崩溃点真值表、恢复页、跨机 mapping、目录树/搜索页面 | `AQ-041`--`AQ-045`、`AQ-161`--`AQ-180`、`AQ-186`--`AQ-190`、`AQ-227`--`AQ-230`、`AQ-235`--`AQ-238`、`AQ-244`、`AQ-257`--`AQ-260`、`AQ-274`--`AQ-278`、`AQ-303`--`AQ-311`、`AQ-347`、`AQ-349`、`AQ-354`--`AQ-356` |
| [09 错误、诊断、关闭与兼容体验](decision-packets/09-errors-diagnostics-compatibility.md) | error/retry/cancel/close、日志只用 INI/XML 的准确含义、support 输出与旧终端/平台能力降级 | error/retry/recovery transcript、退出类别、诊断 schema 与兼容失败 | `AQ-069`、`AQ-103`、`AQ-158`、`AQ-201`--`AQ-203`、`AQ-229`--`AQ-231`、`AQ-238`、`AQ-246`--`AQ-248`、`AQ-314`--`AQ-321`、`AQ-328`、`AQ-334`、`AQ-339`--`AQ-340` |
| [10 测试、性能、发布与实施冻结](decision-packets/10-release-testing-and-readiness-freeze.md) | zip/数据升级、哪些数字由实测决定、故障注入/soak、平台完整测试、供应链证据、何时允许写实施计划 | readiness gate、requirement→spec→test→evidence、性能 workload、发布硬门 | `AQ-181`--`AQ-211`、`AQ-244`、`AQ-303`--`AQ-305`、`AQ-329`--`AQ-330`、`AQ-341`--`AQ-346`、`AQ-350`、`AQ-357`、`AQ-360` |
| [11 跨系统运行接缝与遗漏收口](decision-packets/11-cross-system-operational-seams.md) | 配置外改、Model 调度、ask-user/retry、draft/details、raw stdin、秘密删除、管理事务、文件系统、workspace 失效和扩展关闭边界 | 十三个敌对场景、旧组去重表、回复后必须生成的规格增量 | `AQ-361`--`AQ-373` |

交叉引用是有意的。例如 finish control 同时影响 Prompt/协议与 AgentLoop；Key 生命周期同时影响配置、网络与安全。最终权威只会在一个子系统规范中定义，其他包说明用户体验和依赖，不复制两套事实。

## 建议讨论顺序

建议按 `02 → 03 → 04 → 05 → 06 → 07 → 08 → 09 → 10 → 11`。02--10 先建立九条主干，11 再用外改、休眠、长时间等待、目录失效和数据删除等敌对场景收口交叉缝隙。理由不是模块编号，而是决策依赖：

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

如果希望先解决最高风险，可以在 02 后插入以下五项，不必等整包顺序：

1. `AQ-251/AQ-252`：模型如何明确区分任务完成和只是向用户提问。
2. `AQ-271`--`AQ-275`：raw shell 的真实权限，以及导入 XML 不能带来新授权。
3. `AQ-303`--`AQ-305`：单 XML、durable 屏障和 O(n²) 写放大的取舍。
4. `AQ-261`--`AQ-263`：XP/CentOS 上流式、输入和取消所需的事件泵。
5. `AQ-312`：首版是否真的需要自动 undo；当前推荐是不承诺。

## 已经不能靠一句“选最合适”自动消除的矛盾

### 1. “单 XML 始终完整”与高频 durable 写入

标准 well-formed XML 在根结束标签后不能原地追加子节点。每次 canonical event 都生成完整新 XML 可保持正确，却使长会话累计 I/O 成为 O(n²)。WAL/recovery sidecar 可以改善性能，但活动期间事实不再只在正式 XML。

因此先以“完整流式重写 + 原子/可恢复 replace”做正确性基线和 benchmark；若在 XP x86/旧磁盘超过负责人确认的门，必须明确允许短期 recovery WAL 或调整承诺。所谓“选择合适 XML 库”不会自动解决这个物理问题。

### 2. “相信模型的 raw shell”与细粒度权限

没有 OS sandbox 时，允许 shell 就意味着命令可能读、写、删、联网和访问工作区外。Runtime 无法可靠解析任意 `cmd.exe`/`sh` 字符串再保证 `Write=deny` 或 `Network=deny`。

因此权限界面必须诚实：Readonly 拒绝 Shell；Std 对 Shell 逐次确认；最信任 profile 才允许。direct file tools 可以继续受细粒度能力约束，Model provider 网络则由选择 Model 本身授权。

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

## 当前外部硬阻塞

- 相邻 `../luainstaller` 1.0 明确拒绝 Windows x86；在得到单独授权并为其建立 Win32/XP profile 前，yaca 无法同时兑现“XP x86 + Lua 5.5 + luainstaller”。记录阻塞不等于授权修改兄弟仓库。
- 当前 Linux `bin/` 是 ELF32，其中 curl 为 x32 ABI；不是目标的普通 CentOS 7 x86_64 发行输入。
- 当前 Win32 `curl.exe` 经 UPX 压缩，现有静态 imports 主要是解压 stub；PE 头 4.0 不能证明真实 XP 兼容。

这些问题不会阻止继续完成产品/架构设计，但会阻止发布实施计划宣称已经可构建。
