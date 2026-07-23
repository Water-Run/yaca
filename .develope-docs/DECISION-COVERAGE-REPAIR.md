# 决策覆盖修复计划

更新日期：2026-07-18

状态：已执行的第四轮历史修复计划；本文中的 124/131、旧 group 形态和新增名单是执行前快照，不是现行问卷或实时计数

> 现行负责人入口、正式组数量和回复模板以 `decision-packets/` 与 `DESIGN-DECISION-ROADMAP.md` 的实时清单为准。执行本计划后又通过问题质量门把隐藏子轴拆成独立编号、把重复 owner/技术事实改成非回复投影，因此不能再拿本文件原先预计的 131 组做验收目标。本文保留 A--F 路线和原始缺口集合，供追踪“为何修过”；不用于决定“现在有多少题”。

## 1. 结论

[`DECISION-TRACEABILITY.md`](DECISION-TRACEABILITY.md) 找到的 101 个 checklist 直接缺口与 62 个 AQ 直接缺口，不应全部变成新选择题。逐项复核现有九个决策包、[`SUBSYSTEM-COVERAGE-AUDIT.md`](SUBSYSTEM-COVERAGE-AUDIT.md) 和 [`TECHNICAL-PROOF-BACKLOG.md`](TECHNICAL-PROOF-BACKLOG.md) 后，修复结果是：

| 关闭类型 | Checklist | AQ | 合计 | 含义 |
| --- | ---: | ---: | ---: | --- |
| A | 21 | 21 | 42 | 现有 group 的选项已经完整回答，只漏 `关联：` |
| B | 23 | 17 | 40 | 现有 group 方向正确，但必须增加一个明确选项或子问题 |
| C | 27 | 16 | 43 | 没有合适负责人入口，必须新增 owner decision group |
| D | 5 | 2 | 7 | 项目负责人已经明确回答，应归档/合并，不再重复询问 |
| E | 21 | 6 | 27 | 纯规格或目标平台证明，不能让项目负责人对技术事实投票 |
| F | 4 | 0 | 4 | v0.1 明确排除/暂缓，只保存重开条件，不设计空实现 |
| **合计** | **101** | **62** | **163** | 每项恰好一个主关闭路线 |

执行前 02--11 包共有 124 个负责人 group：原 101 组、packet 11 的 13 组，以及配置整合新增的 M05-13..22 十组。当时预计新增 7 组后到 131；这只是本计划的容量估算。实际修复发现不少所谓“给原组增加子问题”是可以独立回答的 owner 轴，必须升为正式编号；也发现部分旧组只是技术证明或其他 owner 的投影，应退出回复清单。因此最终实时数量必须从正式标题和模板生成，不能由 `124 + 7` 推算。

本文件只新增修复计划，不修改现有决策包、题库或决定日志。执行修复时仍需项目负责人明确回复 C 组与 B 组新增加的选择；推荐本身不是决定。

## 2. A--F 的机械语义

| 类型 | 允许的关闭动作 | 禁止的伪关闭 |
| --- | --- | --- |
| A | 只在指定 group 的 `关联：` 增加 ID/AQ；正文和选项不改 | 把一个“沾边”但没有回答该问题的 group 当覆盖 |
| B | 若缺口与原组是同一个不可分 owner 轴，则扩充该组互斥选项；若能独立回复，必须升为新的正式编号，再补关联 | 藏一个“可单独回复”但无编号的子问题；只补关联；把推荐句当用户选择 |
| C | 必须有新的唯一 owner group；packet 11 已提供的精确 F4 group 直接复用，其余在指定 packet 新增，并具备选项、推荐、代价、关联和归档产物 | 把问题分散给多个 consumer group，最后没人拥有答案 |
| D | 写入/合并 `DECISIONS.md` 的生效决定或 supersede 关系；题库改成已确认/已取代 | 再问一次已明确回答的问题 |
| E | 指向唯一 owner specification、proof ID、fixture 与 readiness gate | 让负责人选择某 API 是否存在、XML 是否物理可追加等事实 |
| F | 由产品范围决定标记 excluded/deferred，并记录重开条件 | 为首版不实现的能力冻结运行时字段、空 API 或详细页面 |

每项可以在多个 consumer 规范中被引用，但本文件中的“主关闭路线”只能有一个。后续交叉引用不能改变 owner。

## 3. C 类负责人入口：复用 2 个、再新增 7 个

### C-PJ-11：`PJ-11 v0.1 产品非目标与主交互模式边界`（新增）

Owner：00 产品契约；写入 `02-product-journey-and-surfaces.md`。

扩展运行时已经由 `F4-13` 单独负责，本组不重复问 MCP/plugin/hook/custom tool/sub-Agent。这里只问产品层剩余非目标：显式 plan mode、Web、媒体、远程控制、自动更新和多根 workspace。

- A：上述能力全部 excluded/deferred；普通 turn 中模型可以先说明计划，但不进入独立 plan state；以后逐项重新进入设计流。（推荐）
- B：增加只读 plan→execute 状态机，其余能力 deferred。
- C：选择更多能力进入 v0.1；每项必须先增加独立产品、权限、状态、存储、TUI 和测试规格。

Web 的四个细项只有在本组选择重开后才讨论。自动更新是否联网仍与 `REL-11/ED-07` 的隐私决定一致。

关联：`PROD-11`、`LOOP-18`、`AQ-346`。`WEB-01` 至 `WEB-04` 走 F，不作为四个额外投票。

### C-F4-12：扩充 `F4-12 active turn 中工作目录消失或变成另一个对象`（已存在）

Owner：00 产品契约；现位于 `11-cross-system-operational-seams.md`。

F4-12 已完整询问 active workspace 失效，但还需在同组前置一个可单独回复的 root/Git 子问题：

- A：传入目录就是 workspace/safety root；相对路径相对启动 cwd；Git 根只提供 status/diff 元数据，不自动扩大根；非 Git 具备完整基础能力。（推荐）
- B：进入仓库子目录时自动提升到 Git 根。
- C：首版支持多根 workspace。

活动根中途失效继续使用 F4-12 已有 A/B/C，不重新编号；对应 `AQ-372` 已经承接原 `SCA-NQ02`。

关联补充：`PROD-05`、`PROD-06`、`AQ-212`。保留已有 `AQ-372`、`PROD-16` 等关联。

### C-F4-13：扩充 `F4-13 v0.1 是否彻底关闭扩展运行时`（已存在）

Owner：21 扩展边界，产品范围仍由 00 最终发布；现位于 packet 11。

F4-13 已经完整提供封闭核心/单一进程外协议/全面扩展三条路线，不增加重复问题。只需把遗漏的 AgentLoop 兼容条目补入关联，并明确 native I/O worker/helper 不属于 Agent。

关联补充：`LOOP-21`。`PROD-04`、`PROD-11`、`TOOL-14` 已在 F4-13；其中 `PROD-11` 的非扩展部分仍由新 `PJ-11` 关闭。

### C-M05-23：`M05-23 TLS/CA、代理、redirect 与传输扩展安全`（新增）

Owner：03 网络传输；写入 `05-model-configuration-network-selftest.md`。

- A：typed `ProxyMode=off|environment|explicit`；CA 只允许 bundled/system/custom/combined，不提供 insecure；跨 origin redirect 默认拒绝且永不转发 Key；压缩体、解压后字节、ratio、header、单事件、总响应分别有硬门；自定义 header/body 只走有界 allowlist/schema。（推荐）
- B：大部分继承 curl/environment 默认，但仍禁止 insecure 和跨 origin credential 转发。
- C：允许任意 redirect、原始 header/body 和跳过证书验证以追求兼容。

组选项只决定用户可见的安全保证与配置语义；CA 文件 API、curl flag、精确字节数和旧平台可行性继续由 TP-006/007/022 证明。

M05-13 已决定 cleartext HTTP + Key，M05-14 已决定传输资源字段公开范围；本组只关闭尚未被它们回答的 CA 来源、proxy 语义、跨 origin redirect 与自定义 header/body。

关联：`NET-02`、`NET-04`、`AQ-146`、`AQ-220`、`AQ-348`。资源炸弹 `AQ-322` 只补到现有 `M05-14`。

### C-M05-24：`M05-24 完整配置 catalog 的最终封口`（新增）

Owner：05 配置；写入 `05-model-configuration-network-selftest.md`。

- A：“完整”表示 M05-01..23 与 typed schema 已覆盖所有真实可调行为，每项有 owner/type/default/missing/secret/source/effective-time/snapshot；删除无消费者的 Mode/Vivid/Language/Update/UseStunnel 等字段，不再追加笼统 Advanced section。（推荐）
- B：模板必须显式写出所有候选字段，任一缺失都阻断；保留旧字段即使没有行为消费者。
- C：各模块自行读取自由字段并决定默认，配置浏览器只显示最终值。

本组不重复 M05-13..22 已回答的 HTTP、limits、Exec environment、Permission 字段、LogLevel、reset、optional、metadata、颜色和 generic override。`CFG-14` 回到 `M05-09`，`CFG-15` 回到 `M05-18`，`AQ-155` 回到 `M05-14`，`AQ-291` 回到 `M05-19`；本组只让负责人确认“配置题面已经封口”和哪些遗留字段正式删除。精确数值默认仍由 schema、测试和旧机证据冻结。

关联：`CFG-13`。

### C-TS-14：`TS-14 威胁模型与 workspace 信任仪式`（新增）

Owner：08 权限与安全；写入 `07-tools-safety-process-runtime.md`。

- A：明确防恶意 workspace/prompt injection/模型与工具输出/恶意 endpoint/篡改发行包/误操作；不承诺防已经控制同用户或 OS 的攻击者；不增加 trusted/untrusted 持久模式，只在打开时显示规范 workspace 身份和将采用的规则，实际能力继续由 Permission/DoubleCheck/审批逐动作裁决。（推荐，最符合“简单、无 sandbox”）
- B：首次打开陌生 workspace 必须先通过显式 trust gate，未信任前只允许元数据查看。
- C：workspace 默认完全可信，项目文字和命令可在 Permission 前运行。

无论 A/B，项目规则、模型 reviewer 和 XML 历史都不能授予 Runtime 原本拒绝的能力；“无 OS sandbox”必须出现在公开边界中。

关联：`THREAT-01`、`THREAT-02`。

### C-TS-15：`TS-15 数据分类、purpose 可见性与 secret/export 生命周期`（新增）

Owner：08 权限与安全；写入 `07-tools-safety-process-runtime.md`。

- A：采用 versioned data-class x purpose x destination 矩阵；Key/secret header 永不进入 XML/argv/log/reviewer；main/side/action-review/termination-review/compaction/self-test 分别使用最小输入；用户正文可能含未知 secret，XML/export 保留事实但必须预览、警告和允许取消，不宣称自动脱敏完整。（推荐）
- B：只给所有数据一个 `sensitive` 布尔标记，各目的自行解释。
- C：完整 Context 默认可发送给任意 reviewer/endpoint/support/export。

组选项决定产品的隐私承诺；canary、结构化 secret detector、泄漏扫描和跨 endpoint manifest 由 TP-028 证明。

关联：`PROD-08`、`THREAT-04`、`AQ-276`、`AQ-349`。

### C-TS-13：`TS-13 Process/raw-shell 结果与输出契约`（新增）

Owner：02 进程与资源；写入 `07-tools-safety-process-runtime.md`。

推荐路线 A 必须一次确认以下整套简单契约：

1. 模型的 `exec` 接受原始命令；Runtime 内部程序启动只接受 structured program+argv；Windows/Linux shell 方言固定。
2. 只支持有界、非交互、前台进程；PTY、detached/background 和重连排除。
3. stdout/stderr 分通道保留，并记录有界 arrival sequence；保留原始字节事实/摘要和显式解码结果；binary 只保存大小、digest、受限预览/引用。
4. 每个调用有 operation ID、typed phase/outcome/exit/cancel/timeout/truncated/unknown；timeout、无输出和 output hard limit 有界。
5. 模型 `exec` 的 stdin 固定关闭/EOF；命令长度/编码越界返回 typed error；不自动拆命令或暗建脚本。

- A：采用上述保守路线。（推荐）
- B：在上述基础上允许受保护临时脚本 fallback，并把脚本编码、权限、清理、审计与语义等价性纳入首版。
- C：沿用用户默认 shell 语法，合并自由文本输出，并允许 PTY/后台进程；环境配置仍由 `M05-15` 决定。

第 5 项不再新增问题：packet 11 的 `F4-07/AQ-367` 已负责 stdin，`F4-11/AQ-371` 已负责长度/编码边界。cwd 与 raw shell environment 配置由已有 `M05-15` 扩充承接；TS-13 引用这些结果，只询问其余尚无 owner 的 process contract。

关联：`PROC-02`、`PROC-04`、`PROC-05`、`PROC-07`、`PROC-10`、`AQ-122` 至 `AQ-124`、`AQ-128`、`AQ-130`、`AQ-147`、`AQ-266`、`AQ-367`、`AQ-371`。`PROC-06`、`AQ-121`、`AQ-148` 由 `M05-15` 关闭。

### C-TU-13：`TU-13 非 TTY、stdin/stdout、exit 与机器输出`（新增）

Owner：13 CLI；写入 `04-tui-visual-input-cli-experience.md`。

- A：v0.1 主 Agent 交互要求 TTY；help/version、静态 self-test 和明确只读查询可非交互；stdin 每次调用由显式参数选择唯一用途；需要菜单、审批、秘密或缺参时 fail-closed；机器输出固定 UTF-8、ASCII 字段和版本化 JSON/JSONL，stdout 只有数据，stderr 是诊断，exit class 稳定。（推荐）
- B：实现完整无人值守 Agent/batch event 协议，包括审批输入、恢复、steer 和机器事件流。
- C：非 TTY 仍按 TTY 菜单 best-effort 读取 stdin，输出混合人类文字和数据。

broken pipe 仍映射安全 close；它不是把模型或副作用突然标成成功。

关联：`CLI-02`、`CLI-03`、`CLI-05`、`CLI-06`、`CLI-09`、`CLI-13`、`CLI-14`、`CLI-15`、`AQ-247`、`AQ-320`。

## 4. 必须扩充的 23 个现有 group

下面每项都属于 B。执行时先加选项/子问题，再补关联；只改关联不算完成。

| 修复号 | 现有 group | 必须新增的明确问题 | 推荐基线 | 本次关闭项 |
| --- | --- | --- | --- | --- |
| `BE-01` | `TS-04` | 是否另设 Autonomy/Yolo 模式，还是自主性只由 Permission、DoubleCheck、budget、typed ask-user 共同决定 | 不另设模式；安全边界由确定性开关组成，普通推进由模型主导 | `PROD-02` |
| `BE-02` | `M05-10` | 无配置时首份配置怎样事务发布；是否有向导、最低字段、连接测试能否跳过、secret/非 secret 草稿怎样处理 | 无首次页面；显式 model-repl bootstrap，连接测试可跳过，完整静态校验后原子发布 | `PROD-13` |
| `BE-03` | `M05-03` | `Streaming=try` 何时可降级；公开 reasoning 怎样显示/保存；配置、preset、self-test observation 的能力权威顺序 | 任何 canonical event 前才可降级；只保留 provider 公开 summary；配置授权、preset 预填、self-test 只告警 | `NET-01`、`MODEL-14`、`AQ-222`、`AQ-285` |
| `BE-04` | `M05-07` | unknown/missing/deprecated/拼错/越界字段的逐类结果；REPL 保存前发现 INI 外改怎么办 | 安全未知/拼错阻断，普通未知可保留并警告；digest 冲突必须 reload/compare/discard | `CFG-08`、`AQ-290` |
| `BE-05` | `M05-06` | `.cautious` 的 show/on/off/reset、INI default/XML tri-state/effective source 和生效点 | 无参 show；on/off 写 XML override；reset 回 inherit；下一 turn 生效并显示来源 | `CFG-17` |
| `BE-06` | `TS-02` | canonical tool output 与 TUI preview 的两层上限；文件类型/大小；ignore 与显式路径规则 | 有界 canonical result + 更小 preview；binary/超限拒绝或引用；搜索默认遵守 ignore，显式目标仍经权限确认 | `TOOL-07`、`TOOL-10`、`TOOL-11` |
| `BE-07` | `TS-08` | Git 是证据增强还是工作流控制；status/diff 是否 direct；审阅时点是什么 | 结构化只读 status/diff 可用；commit/push/reset/stash 不自动执行；结束报告展示可归属 diff | `TOOL-12`、`AQ-129` |
| `BE-08` | `AL06-09` | 有明确验证命令时是否必须尝试；验证失败允许几轮修正；怎样形成 typed verification evidence | 能安全执行时至少尝试一次；修正受同一 turn budget/stuck gate；不能验证时明确说明 | `TOOL-13`、`LOOP-09` |
| `BE-09` | `TS-10` | 一个 accepted batch 中某个工具失败时，后续调用继续、停止还是回滚 | 全部串行；失败后停止未开始调用，给 completed/failed/skipped 配对结果，不虚构通用 rollback | `LOOP-12`、`AQ-105` |
| `BE-10` | `TU-10` | `.prompt show/set/edit/reset` 语义；Context list/resume/rename/archive/delete/export/repair 的命名和 selector 错误映射 | 无参只读 show；修改预览确认；Context 动作共享 Resolver/registry/唯一简称 | `CLI-07`、`AQ-057`、`AQ-058` |
| `BE-11` | `TU-01` | 哪些状态常驻、哪些只在 `.status`；字段顺序是否固定 | transcript 不常驻密集 status bar；`.status` 固定 name/hash/path/Model/Permission/DoubleCheck/activity/budget/save | `TUI-07`、`AQ-193` |
| `BE-12` | `ED-01` | Context 建立前或 writer 已 faulted 时，未捕获错误的最小崩溃报告放哪里 | 安全 stderr 卡 + 显式 support 输出；有健康 Context 才追加 typed diagnostic；不暗建第三类长期日志 | `DIAG-09` |
| `BE-13` | `ED-04` | 自动重试之外，批量/多阶段部分成功如何显示 | 同一结果列 success/failed/skipped/unknown、已保存状态和下一步；不可用一条 success 覆盖 | `DIAG-12` |
| `BE-14` | `RF-11` | README 状态、help/schema/template 同步、旅程/故障文档和版本迁移说明是否属于 release gate | 全部进入 trace/release gate；从同一 registry/golden 生成或校验，候选不得写成已实现 | `DOC-01` 至 `DOC-04` |
| `BE-15` | `PP-03` | 旧 `Model.CustomPrompt` 保留为独立权威层、迁移到已有 Prompt，还是删除 | 删除独立层；内容经用户确认迁到 SystemPrompt/ContextPrompt，协议模板仍内置版本化 | `AQ-143` |
| `BE-16` | `M05-09` | 配置浏览时怎样同时显示字段默认值、用户值、Context override、最终值、来源与 secret 状态；model-repl 跳转后是否保持同一语义 | 两个 REPL 共用 typed field-view；默认/用户/会话/最终/来源/secret 分列，secret 永不回显 | `CFG-14` |
| `BE-17` | `M05-02` | 完整 Endpoint URL、AuthMode、URL userinfo/query、Runtime required headers 与自定义 headers 的冲突语义 | Endpoint 为完整 URL；protocol/none；Key 出现在 URL 为硬错误；Runtime 字段不可覆盖 | `AQ-284` |
| `BE-18` | `M05-11` | 一个 Model 失败后是否继续测其余项、是否可用已通过 Model 进入 Stage 3；consent 页必须列什么 | 继续逐项；Stage 3 只用明确通过者且另行同意；列 origin/Model/request/token/cost possibility/data/proxy/CA | `AQ-317`、`AQ-319` |
| `BE-19` | `AL06-03` | 同一 response 的 text+tools 顺序；`finish_reason=length` 是否自动 continuation | 保留规范 block 顺序，text 不等于 finish；length 为 incomplete/partial，默认不自动续写 | `AQ-324`、`AQ-325` |
| `BE-20` | `RF-07` | Prompt/control/tool/ask-user/finish/compaction 是否在所有正式支持 Model 上跑固定行为集 | 使用版本化跨 Model fixtures 和统计阈值；不比较逐字文本，不覆盖确定性 hard gate | `AQ-357` |
| `BE-21` | `M05-14` | Context XML 是否只能覆盖策略/预算，哪些 durability/repair/commit 规则属于不可配置硬不变量 | XML 只覆盖已登记的会话策略/更严格预算；durability、repair、完整历史与 commit 协议不可关闭 | `AQ-155` |
| `BE-22` | `M05-19` | 每个字段怎样区分 required、missing、schema default、显式 sentinel、继承和最终生效值 | typed schema 逐字段声明；parser/REPL/XML/self-test 共用同一状态，不用缺失猜多种含义 | `AQ-291` |
| `BE-23` | `M05-15` | raw shell 的 cwd 与环境 snapshot 怎样确定；内部 curl/Git/helper 如何与用户 shell 的环境/代理/配置隔离 | cwd 为规范 workspace/显式 tool cwd；raw shell 使用所选受控快照；内部程序用独立最小环境，不能继承 shell override | `PROC-06` |

Git 的主关闭路线只在 `BE-07/TS-08`；TS-10 只拥有工具 batch 调度，防止按关键词误建双 owner。

### 4.1 A 类最小关联补丁

下表是 A 的完整执行清单。每格只修改指定 group 的 `关联：`，不得顺手改正文、推荐或选项；这样既能补 direct trace，又不会把已有决定重新打开。

| 现有 group | 只需追加的关联 |
| --- | --- |
| `AL06-02` | `PROD-03` |
| `RF-09` | `PROD-10` |
| `RF-02` | `PLAT-02` |
| `TU-02` | `PLAT-05` |
| `ED-08` | `PLAT-09` |
| `TS-09` | `PROC-01` |
| `RF-03` | `FMT-06`、`CFG-07` |
| `M05-18` | `CFG-15` |
| `AL06-09` | `MODEL-09`、`AQ-283` |
| `TS-08` | `TOOL-05`、`TOOL-09` |
| `ED-09` | `THREAT-05` |
| `AL06-03` | `LOOP-16` |
| `ED-01` | `LOOP-17`、`CTX-24` |
| `TU-12` | `LOOP-26` |
| `CX-03` | `CTX-23` |
| `TU-08` | `DIAG-10` |
| `ED-03` | `DIAG-11` |
| `ED-07` | `REL-11` |
| `TS-10` | `AQ-035` |
| `CX-02` | `AQ-041`、`AQ-042`、`AQ-210` |
| `CX-05` | `AQ-043` |
| `M05-15` | `AQ-121`、`AQ-148` |
| `TS-02` | `AQ-184` |
| `CX-07` | `AQ-274`、`AQ-275` |
| `M05-05` | `AQ-282` |
| `M05-08` | `AQ-286` |
| `M05-07` | `AQ-287`、`AQ-288` |
| `M05-10` | `AQ-289` |
| `PJ-05` | `AQ-313` |
| `M05-12` | `AQ-318` |
| `M05-14` | `AQ-322` |
| `AL06-10` | `AQ-347` |
| `RF-11` | `AQ-350` |

验收展开后必须恰好得到 42 个对象：21 个 checklist 与 21 个 AQ；相同 group 的多个关联不拆成多个补丁事务。

## 5. 101 个 checklist 缺口的唯一关闭表

`路线` 是唯一主关闭路线。A/B/C 项修复后必须出现在对应 group 的 `关联：`；D/E/F 不应为了追求“直接 group 覆盖率”被塞回问卷。

| Checklist ID | 类别 | 路线 | 精确动作 |
| --- | --- | --- | --- |
| `PROD-02` | B | `BE-01/TS-04` | 增加“是否存在独立自主性模式”子问题 |
| `PROD-03` | A | `AL06-02` | 只补关联；typed finish/partial/ask/refuse 已决定产品终态入口 |
| `PROD-04` | C | `F4-13` | 由扩展关闭组决定单 Agent/子 Agent 边界 |
| `PROD-05` | C | `F4-12+root` | 决定 workspace root、rebind 与活动根失效 |
| `PROD-06` | C | `F4-12+root` | 决定 Git 只作证据增强及非 Git 保证 |
| `PROD-08` | C | `C-TS-15` | 由安全 owner 冻结数据分类总矩阵 |
| `PROD-09` | D | `D-029` | 已标记被 `PROD-15` 取代；归档 English/ASCII UI 与 Unicode 用户数据边界 |
| `PROD-10` | A | `RF-09` | 只补关联；预算冻结阶段与最低平台证据已完整询问 |
| `PROD-11` | C | `C-PJ-11` | 形成逐能力 supported/excluded/deferred 表 |
| `PROD-13` | B | `BE-02/M05-10` | 增加手动首次配置事务，不新增首次页面 |
| `ARCH-03` | D | `D-013/D-014` | 已确认 main.lua 组合与窄注入；只传播到规格/测试 |
| `ARCH-04` | E | `SCA-D03/SCA-D04` | 由 Domain Registry + AgentLoop transition spec 冻结事件所有权 |
| `RUNTIME-04` | E | `TP-029` | 受控 module/DLL/tool 搜索证明，不交负责人投票 |
| `RUNTIME-05` | E | `TP-021` | 数值/内存边界和 Win32 x86 corpus |
| `CONC-02` | E | `TP-022` | 逐队列背压 truth table 与组合压力证据 |
| `CONC-04` | E | `TP-022` | 进程级资源公平/硬上限由 workload 证明 |
| `PLAT-01` | E | `SCA-D02/TP-012` | PathPort/LogicalPathCodec 和目标平台 vectors |
| `PLAT-02` | A | `RF-02` | 只补关联；portable/system data-root 与多副本已完整询问 |
| `PLAT-03` | E | `SCA-D02` | Environment/Text port 规格与缺失 HOME/locale fixtures |
| `PLAT-04` | E | `TP-011` | no-replace/replace/flush/lock/filesystem 原语证明 |
| `PLAT-05` | A | `TU-02` | 只补关联；override + 保守探测 + 等价降级已询问 |
| `PLAT-06` | E | `SCA-D02/ClockTemp contract` | monotonic/wall/random/temp-name 规格和 deterministic fixtures |
| `PLAT-07` | E | `SCA-D02` | adapter 布局是实现规格，不是产品选择 |
| `PLAT-08` | E | `ApplicationCompositionV1` | 错 OS/arch 的 startup guard 与 contract test |
| `PLAT-09` | A | `ED-08` | 只补关联；ASCII UI、UTF-8 数据、wide API 分层已询问 |
| `PLAT-12` | E | `TP-023/TP-024` | 旧 Linux/SSH/TERM/非 TTY 终端证据 |
| `PROC-01` | A | `TS-09` | 只补关联；窄 native port 与纯 Lua 阻塞路线已询问 |
| `PROC-02` | C | `C-TS-13` | 区分模型 raw command 与内部 structured argv |
| `PROC-04` | C | `C-TS-13` | 决定 stdout/stderr/bytes/arrival/binary 用户契约 |
| `PROC-05` | C | `C-TS-13` | 决定 timeout/output/no-output/override 边界 |
| `PROC-06` | B | `BE-23/M05-15` | 在现有 raw-shell 环境组选定 cwd，并明确内部程序环境隔离 |
| `PROC-07` | C | `C-TS-13` | 决定 typed process outcome 与 operation identity |
| `PROC-08` | E | `TP-029/ComponentManifest` | 内部资源只按 manifest 绝对路径解析 |
| `PROC-09` | E | `TP-029/SelfTestCheck registry` | hash/ABI 校验时点由启动成本和证据推导 |
| `PROC-10` | C | `C-TS-13` | 决定大输出/请求体临时载体与清理产品保证 |
| `NET-01` | B | `BE-03/M05-03` | 补 `try` 降级、partial stream 与资源收口 |
| `NET-02` | C | `C-M05-23` | 决定 CA 信任来源与禁止 insecure |
| `NET-04` | C | `C-M05-23` | 决定 typed proxy 语义及 environment 边界 |
| `FMT-03` | E | `TP-021/JSON safe profile` | 数值、重复 key、深度/大小与 UTF-8 corpus |
| `FMT-05` | E | `SCA-D06/TP-008` | 不建独立日志；完整记录/损坏恢复归 Context commit schema |
| `FMT-06` | A | `RF-03` | 只补关联；三类版本、迁移、备份、降级已询问 |
| `FMT-07` | E | `TP-010/TP-019` | XML/INI/JSON deterministic writer 与 round-trip 证明 |
| `CFG-07` | A | `RF-03` | 只补关联；config schema 版本/迁移/降级已询问 |
| `CFG-08` | B | `BE-04/M05-07` | 增加 invalid/unknown/deprecated 逐类矩阵 |
| `CFG-13` | C | `C-M05-24` | 决定完整 section/field catalog 的边界 |
| `CFG-14` | B | `BE-16/M05-09` | 增加 default/user/override/effective/source/secret 字段视图 |
| `CFG-15` | A | `M05-18` | 只补关联；reset 粒度、Key/Context、备份与事务已经完整询问 |
| `CFG-16` | D | `D-020/D-027` | 独立终止评估开关已被 DoubleCheck 取代；只做迁移 |
| `CFG-17` | B | `BE-05/M05-06` | 补 `.cautious` tri-state/default/source/effective-time |
| `CFG-18` | E | `SCA-D07/TP-019` | typed schema 单一事实源是规范/一致性测试 |
| `MODEL-09` | A | `AL06-09` | 只补关联；usage receipt、未知价格与 cost hard-cap 边界已询问 |
| `MODEL-14` | B | `BE-03/M05-03` | 补公开 reasoning summary 与 hidden reasoning 禁区 |
| `TOOL-05` | A | `TS-08` | 只补关联；diff/归属/undo 路线已询问 |
| `TOOL-07` | B | `BE-06/TS-02` | 增加 canonical result 与 UI preview 两层上限 |
| `TOOL-08` | E | `SCA-D05/ToolRegistryV1` | read-only/side-effect/cancel/resource-key metadata 由 registry 冻结 |
| `TOOL-09` | A | `TS-08` | 只补关联；expected digest/freshness/unknown 已询问 |
| `TOOL-10` | B | `BE-06/TS-02` | 增加 binary/large/special input contract |
| `TOOL-11` | B | `BE-06/TS-02` | 增加 ignore 与显式路径覆盖规则 |
| `TOOL-12` | B | `BE-07/TS-08` | 增加 Git direct-read 与 shell action 分工 |
| `TOOL-13` | B | `BE-08/AL06-09` | 增加 typed verification result 与修正预算 |
| `TOOL-14` | C | `F4-13` | 由扩展关闭组决定 custom tool/MCP/plugin/hook 的排除/重开 |
| `TOOL-16` | E | `SCA-D05/ToolRegistryV1` | 名称/schema/result/capability version 是规范 |
| `THREAT-01` | C | `C-TS-14` | 负责人确认保护对象与明确不承诺的攻击者 |
| `THREAT-02` | C | `C-TS-14` | 负责人确认 workspace trust/identity UX |
| `THREAT-03` | E | `TP-029` | module/DLL/PATH/CWD 劫持必须由恶意 fixture 证明 |
| `THREAT-04` | C | `C-TS-15` | 决定 secret 生命周期与各 purpose 可见性 |
| `THREAT-05` | A | `ED-09` | 只补关联；控制序列净化和不可降级安全能力已询问 |
| `LOOP-09` | B | `BE-08/AL06-09` | 增加验证责任、失败修正轮与预算 |
| `LOOP-12` | B | `BE-09/TS-10` | 增加 batch 中途失败后的执行/跳过顺序 |
| `LOOP-16` | A | `AL06-03` | 只补关联；完整响应验收前 provisional、不提前执行已询问 |
| `LOOP-17` | A | `ED-01` | 只补关联；typed error owner/retry/wait/terminal 路线已询问 |
| `LOOP-18` | C | `C-PJ-11` | 决定显式 plan mode 是否排除 |
| `LOOP-21` | C | `F4-13` | 决定子/后台 Agent 是否排除，不先冻未来字段 |
| `LOOP-26` | A | `TU-12` | 只补关联；domain trace 与 renderer 语义等价已询问 |
| `CTX-23` | A | `CX-03` | 只补关联；canonical event/snapshot/view 完整性已询问 |
| `CTX-24` | A | `ED-01` | 只补关联；Context XML/stderr/无第三日志已询问 |
| `INDEX-13` | D | `D-030` | 已归档不增加 name:/hash:/path:，碰撞返回歧义 |
| `CLI-00` | D | `D-026` | `yaca [目录]` 与裸命令等价已确认；剩余 grammar 由其他 ID |
| `CLI-02` | C | `C-TU-13` | 决定非 TTY 主 Agent/只读命令边界 |
| `CLI-03` | C | `C-TU-13` | 决定版本化机器输出面 |
| `CLI-05` | C | `C-TU-13` | 决定 stdout/stderr 路由 |
| `CLI-06` | C | `C-TU-13` | 决定稳定 exit class |
| `CLI-07` | B | `BE-10/TU-10` | 增加 Context action 命名与统一 Resolver 结果 |
| `CLI-09` | C | `C-TU-13` | 决定 signal/EOF/broken pipe 的非交互收口 |
| `CLI-13` | C | `C-TU-13` | 决定 prompt/approval 的 TTY 门 |
| `CLI-14` | C | `C-TU-13` | 决定 stdin 单一用途 |
| `CLI-15` | C | `C-TU-13` | 决定 JSON/JSONL、UTF-8、stdout 隔离 |
| `TUI-07` | B | `BE-11/TU-01` | 增加常驻状态与 `.status` 固定顺序 |
| `DIAG-09` | B | `BE-12/ED-01` | 增加 pre-Context/faulted-writer 崩溃报告 |
| `DIAG-10` | A | `TU-08` | 只补关联；错误卡字段与 details 已询问 |
| `DIAG-11` | A | `ED-03` | 只补关联；单根因/单主卡/cause chain 已询问 |
| `DIAG-12` | B | `BE-13/ED-04` | 在 retry UX 外增加 partial/unknown 分项结果 |
| `REL-11` | A | `ED-07` | 只补关联；无隐式更新检查/遥测已在选项中 |
| `DOC-01` | B | `BE-14/RF-11` | 增加 implemented/confirmed/proposed 状态门 |
| `DOC-02` | B | `BE-14/RF-11` | 增加 README/help/schema/template 同批校验 |
| `DOC-03` | B | `BE-14/RF-11` | 增加旅程/故障文档与 state/golden 同源 |
| `DOC-04` | B | `BE-14/RF-11` | 增加兼容/迁移/降级公开说明 |
| `WEB-01` | F | `PJ-11 exclusion record` | 只记录“核心 v0.1 发布且负责人显式重开后再讨论” |
| `WEB-02` | F | `17-web deferred` | 不冻结 IE/浏览器基线；重开时重新评估 |
| `WEB-03` | F | `17-web deferred` | 不设计 v0.1 Web 安全模型；重开时重新威胁建模 |
| `WEB-04` | F | `17-web deferred` | 只保留“不复制核心”的重开约束，不实施空 Web seam |

## 6. 62 个 AQ 缺口的唯一关闭表

| AQ | 类别 | 路线 | 精确动作 |
| --- | --- | --- | --- |
| `AQ-016` | D | `D-028` | 已归档“一个 Model section 是完整 LLM 连接实例” |
| `AQ-035` | A | `TS-10` | 只补关联；v0.1 全部工具串行已完整询问 |
| `AQ-041` | A | `CX-02` | 只补关联；语义接盘与外部依赖边界已询问 |
| `AQ-042` | A | `CX-02` | 只补关联；公开 reader schema/唯一 writer 已询问 |
| `AQ-043` | A | `CX-05` | 只补关联；temp/lock/previous-valid 与单 XML 事实源已询问 |
| `AQ-057` | B | `BE-10/TU-10` | 增加无参 `.prompt` 只读 show 选项 |
| `AQ-058` | B | `BE-10/TU-10` | 增加 show/set/edit/reset、预览/确认/生效点 |
| `AQ-105` | B | `BE-09/TS-10` | 增加多工具中途失败/跳过配对 |
| `AQ-121` | A | `M05-15` | 只补关联；raw shell environment 的继承/typed set-unset 路线已询问 |
| `AQ-122` | C | `C-TS-13` | stdout/stderr 分离与 arrival sequence |
| `AQ-123` | C | `C-TS-13` | raw bytes、显式 decode、替换/失败证据 |
| `AQ-124` | C | `C-TS-13` | binary size/digest/preview/reference |
| `AQ-128` | C | `C-TS-13` | v0.1 非交互前台；PTY/background deferred |
| `AQ-129` | B | `BE-07/TS-08` | 增加 Git read wrapper 与 shell action 分工 |
| `AQ-130` | C | `C-TS-13` | operation ID 与 typed process error/result |
| `AQ-143` | B | `BE-15/PP-03` | 明确删除/迁移 Model.CustomPrompt 独立层 |
| `AQ-146` | C | `C-M05-23` | CA source、TLS diagnosis、无 insecure |
| `AQ-147` | C | `C-TS-13` | Exec section 只表达全局执行策略 |
| `AQ-148` | A | `M05-15` | 只补关联；environment inherit/set/unset 配置语义已完整询问 |
| `AQ-155` | B | `BE-21/M05-14` | 增加 Context 可配策略/预算与不可配置 durability 的边界 |
| `AQ-157` | D | `D-029` | 已归档移除 Mode/Vivid/Language 配置；终端自动适配 |
| `AQ-171` | E | `SCA-D06/TP-010` | seq/digest/integrity 字段由 schema、威胁模型和 corruption fixture 决定 |
| `AQ-184` | A | `TS-02` | 只补关联；list/read/search/write/patch/rename/delete/exec 已给稳定名称 |
| `AQ-193` | B | `BE-11/TU-01` | 增加 `.status` 固定字段顺序 |
| `AQ-210` | A | `CX-02` | 只补关联；public schema/examples/reference reader/conformance 已列为交付物 |
| `AQ-212` | C | `F4-12+root` | 决定相对 cwd、workspace root 与 Git 根不自动提升 |
| `AQ-220` | C | `C-M05-23` | 决定 redirect/origin/Key forwarding |
| `AQ-222` | B | `BE-03/M05-03` | 增加公开 reasoning summary/hidden reasoning 边界 |
| `AQ-247` | C | `C-TU-13` | 决定非 TTY 主 Agent 与安全查询范围 |
| `AQ-266` | C | `C-TS-13` | 固定 Windows cmd/Linux sh 方言 |
| `AQ-267` | E | `TP-029` | 绝对 manifest 搜索与 CWD/PATH 劫持 fixtures |
| `AQ-270` | E | `SCA-D02/ClockPort` | UTC wall time + monotonic deadline 由 port spec/test 冻结 |
| `AQ-274` | A | `CX-07` | 只补关联；外来 XML 重算本机安全覆盖已询问 |
| `AQ-275` | A | `CX-07` | 只补关联；历史 approval 永远 audit-only 已询问 |
| `AQ-276` | C | `C-TS-15` | 决定 data-class x purpose x destination 矩阵 |
| `AQ-277` | E | `TP-006` | stdin/temp/native 候选由 secret canary 和 XP/curl 证据选择 |
| `AQ-278` | E | `TP-006` | temp secret/body 生命周期、残留与启动回收证明 |
| `AQ-282` | A | `M05-05` | 只补关联；固定字段、typed protocol optional 与“缺失即不发送”已完整询问 |
| `AQ-283` | A | `AL06-09` | 只补关联；token/request/time hard budget 与 price snapshot 边界已询问 |
| `AQ-284` | B | `BE-17/M05-02` | 增加完整 Endpoint/AuthMode/required header 语义 |
| `AQ-285` | B | `BE-03/M05-03` | 增加 config/preset/observation 权威顺序 |
| `AQ-286` | A | `M05-08` | 只补关联；enabled/disabled 完整性已询问 |
| `AQ-287` | A | `M05-07` | 只补关联；INI multiline/escape 路线已询问 |
| `AQ-288` | A | `M05-07` | 只补关联；注释/顺序/未知字段往返已询问 |
| `AQ-289` | A | `M05-10` | 只补关联；bootstrap model-repl 已询问 |
| `AQ-290` | B | `BE-04/M05-07` | 增加手工外改 digest 冲突处理 |
| `AQ-291` | B | `BE-22/M05-19` | 增加 required/missing/default/sentinel/inherit/effective 状态矩阵 |
| `AQ-313` | A | `PJ-05` | 只补关联；首项 durable 会话动作创建 XML 已询问 |
| `AQ-317` | B | `BE-18/M05-11` | 解决“一个失败是否阻断其余/Stage 3”的未闭环 |
| `AQ-318` | A | `M05-12` | 只补关联；Stage 3 advisory/non-writing 地位已询问 |
| `AQ-319` | B | `BE-18/M05-11` | 增加 consent 页 endpoint/费用/data/proxy/CA 清单 |
| `AQ-320` | C | `C-TU-13` | 决定 self-test 非 TTY output/flag/exit class |
| `AQ-322` | A | `M05-14` | 只补关联；多级 Runtime hard cap 与少量用户低上限已经完整询问 |
| `AQ-323` | E | `TP-015/JSON tool-argument corpus` | 重复 key、深度、大小、UTF-8、数值/schema 由 parser conformance 证明 |
| `AQ-324` | B | `BE-19/AL06-03` | 增加 text+tools block 顺序和非 terminal 文本 |
| `AQ-325` | B | `BE-19/AL06-03` | 增加 length=incomplete/partial 与默认不自动续写 |
| `AQ-346` | C | `C-PJ-11` | 在首版范围组决定 plan mode 排除/进入 |
| `AQ-347` | A | `AL06-10` | 只补关联；Model rename/missing mapping/switch event 已询问 |
| `AQ-348` | C | `C-M05-23` | 决定 custom header/body allowlist 与 secret/redirect 边界 |
| `AQ-349` | C | `C-TS-15` | 决定正文潜在 secret 的 export 预览与诚实警告 |
| `AQ-350` | A | `RF-11` | 只补关联；requirement→decision→spec→test→evidence 门已询问 |
| `AQ-357` | B | `BE-20/RF-07` | 增加跨 Model 固定行为评测集和统计判定 |

## 7. D、E、F 的归档与规格动作

### D：三条新归档记录，并复用既有决定链

本轮已经把三条明确的历史回复归档为正式决定：

1. **D-028 Model 是完整连接实例**：归档 `AQ-016`，并一并记录同批明确的明文 Key 与 streaming 三态；一个 section 自含 endpoint/protocol/remote model/key/capability/retry，carrier 等技术路线仍待证明。
2. **D-029 显示配置收口**：归档 `AQ-157` 与 `PROD-09` 的已答部分；不提供 Mode/Vivid/Language/Theme 配置，程序 UI/ID 固定 English/ASCII，用户正文/路径/XML 的 Unicode 边界仍服从 `PROD-15`/`ED-08`。
3. **D-030 Selector 无显式前缀**：归档 `INDEX-13`；没有 `name:`/`hash:`/`path:`，歧义不得任取。

`ARCH-03` 直接引用 D-013/D-014，`CFG-16` 引用 D-020/D-027 的 supersede 链，`CLI-00` 引用 D-026。不能新建重复决定。

### E：规格/证明登记

E 项不出现在负责人回复清单中，但必须在 trace matrix 有以下字段：owner subsystem、normative spec、proof/fixture、readiness gate、失败后的产品退路。若没有现成 TP，先扩充 proof backlog 的可复现步骤，而不是新增 A/B/C。

尤其需要避免三种错误：

- `AQ-277`/`AQ-278` 不能让负责人凭感觉选 stdin 还是 temp；M05-02 只确认“不允许泄漏”的产品保证，实际 carrier 由 TP-006 选。
- `PLAT-04`、`THREAT-03`、`RUNTIME-04` 不能因文档推荐绝对路径/no-replace 就标 proven；必须在最终 XP/CentOS 产物做攻击/故障 fixture。
- `FMT-03`、`AQ-323` 的限制数字不能写成随意常量；先冻结拒绝语义，再用 Win32 x86 与 provider corpus 证明上限。

### F：Web 暂缓记录

`PJ-11` 选择排除后，17 号文档只保留一页 exclusion/re-entry record：v0.1 不运行 Web server、不监听端口、不提供浏览器 UI、不冻结 IE 基线；只有核心 CLI/TUI 已发布且项目负责人显式重开后才重新做浏览器、安全和复用设计。不得为了“以后可能需要”在 Context、Permission、Runtime 或发行包加入 Web 字段和依赖。

## 8. 执行顺序

1. 先归档 D，避免已答内容继续混在待决问题中。
2. 复核 23 个 B group：同一 owner 轴扩充真实选项；独立轴提升为新正式编号；完成后才补关联。
3. 扩充 packet 11 的 `F4-12/F4-13` 关联与 root 子问题，并在既有 packet 中加入另外 7 个 C group；`SCA-NQ01/02` 已分别由 `AQ-371/AQ-372` 承接，不再编号。
4. 批量补 42 个 A 关联和全部 B/C 关联。
5. 把 E 项写入 owner spec/proof 路线，把 F 写入产品范围/重开记录。
6. 重新生成 `DECISION-TRACEABILITY.md`；不要靠手改计数。
7. 再修 116 个 readiness gate 来源缺口。它不是本文件 163 项的一部分，但不修就仍不能宣布实施就绪。
8. 更新 roadmap/packet README/Questions 状态；只有负责人明确回复的 B/C 才进入 confirmed decision。

## 9. 修复后的机器验收规则

### 9.1 路线表自身

1. 从第 5 节只读取形如 ``| `ID` | A..F |`` 的行，必须得到 101 个唯一 checklist ID；与追踪审计原始缺口集合完全相等。
2. 从第 6 节按同样规则必须得到 62 个唯一 AQ；与原始缺口集合完全相等。
3. 分类计数必须严格是 checklist `A21/B23/C27/D5/E21/F4`，AQ `A21/B17/C16/D2/E6/F0`。
4. 任一 ID/AQ 不得有两个主路线；route target 不得为空。

### 9.2 决策组（执行前预计；实时计数规则已取代）

1. 原规则预计 124 修复为 131，并限制七个新增 ID；该数量规则已经 superseded。现行规则是从全部正式 `### <GROUP-ID>` 标题生成唯一清单，逐包与完整推荐模板精确相等；非回复的已确认边界、consumer 投影和 technical proof 必须使用 `##`，不能混入清单。新增/退出 group 都要说明唯一 owner 与原因，不追求固定总数。
2. 每个 C group 必须有问题、至少两个互斥选项、推荐、主要代价、`关联：` 和确认后 owner artifact；不能只有主题说明。
3. 每个 `BE-*` 指定 group 必须出现对应新增子问题和至少两个互斥答案；随后 B 项才算 direct-covered。
4. A/B/C 的 125 个 checklist/AQ 路线（checklist 71，AQ 54）必须在指定 group 的 `关联：` 中出现；range 展开后逐项相等。这里按对象分别计数，不把同名字符串跨表相加。
5. association 可以有 consumer 交叉引用，但本文件 primary route 保持唯一；机器不得用“最后出现的 group”决定 owner。

### 9.3 D/E/F 合法例外

1. D 项必须引用一个状态为已确认的有效决定或明确 supersede 记录；在负责人待答清单中出现即失败。
2. E 项必须有 owner spec + proof/fixture + readiness gate；只有“技术侧决定”一句而无证据路线即失败。
3. F 项必须有生效的产品范围决定和 re-entry condition；首版 schema/tool/runtime 若出现无消费者的 Web 字段即失败。
4. 修复后的“未分类缺口”必须为 0。纯 group-direct 统计允许剩余 checklist 30 项、AQ 8 项，但它们必须精确等于 D/E/F 集合；出现其他剩余项即失败。

### 9.4 全局一致性

1. 所有关联 ID/AQ 必须已定义；range 不能穿过未定义编号空洞。
2. 每个 checklist ID 只有一个 owner subsystem；新增 group 不改变 owner，只提供负责人输入。
3. `AQ-016`、`AQ-157` 和 D 类 checklist 不再显示“待决”；`AQ-361` 至 `AQ-373` 连续唯一；原 `SCA-NQ01/02` 只映射到 `AQ-371/AQ-372`，不能再生成重复 AQ。
4. `M05-02` 不再把 secret carrier 的技术候选写成未经 proof 的产品事实；`AQ-282` 必须直接关联已合并参数面的 `M05-05`，`AQ-322` 必须直接关联已有 `M05-14`；`M05-11` 与 `AQ-317` 的 Stage 3 条件必须无矛盾。
5. `PROD-09` 明确 superseded/alias 到 `PROD-15`，不保留第二套语言规范。
6. 所有 28 个 readiness gate 都有机器可读 `主要来源`；当前 354 个设计 ID 至少到达一个 owner、一个 closure route、一个 gate 和未来 test/evidence。
7. recommendation、confirmed、specified、proven、implemented、released 状态不能互相代替；机器只接受有效决定和证据状态，不从“推荐”文字推断确认。

## 10. 本计划何时算完成

本文完成只表示 163 个直接缺口都有唯一修复路线。结构性 coverage repair 的验收是：

- A 的关联已经补齐；
- B 的独立子轴已经提升成正式编号或证明与原组选项不可分，不能藏无编号选择；
- C 的 owner 入口已经进入实时决策包；后来被 D-038 收口或被证明属于 technical/consumer projection 的旧入口已明确退出回复清单；
- D 已进入有效决定/supersede 链；
- E 已进入唯一规格和 proof gate；
- F 已有生效范围决定与重开条件；
- 追踪脚本按第 9 节通过，116 个 readiness 来源缺口也已经闭合。

当前文档已经执行结构修复，但项目负责人尚未回复实时决策包，技术证明与 readiness 也未完成。因此正确状态是“问题和闭合路线已经精确化，等待决策流”，不是“已经可以编码”。负责人回复属于下一阶段的 decision resolution，不应反过来改变本历史计划的题目数量。
