# 决策包 11：跨系统运行接缝与遗漏收口

更新日期：2026-07-18

状态：F4-01 至 F4-12、F4-14 等待项目负责人回复；扩展关闭/重入门已由 D-038 确认

## 为什么还需要这一包

前九个主包已经分别讨论产品旅程、Prompt、TUI、Model、AgentLoop、工具、安全、Context、错误、发布和测试。第四轮审阅不再按“一个子系统一个子系统”顺读，而是从用户输入开始，反向模拟外部编辑、休眠、断网、目录消失、进程卡住、配置备份、跨机恢复和升级，再检查每一条责任有没有唯一归属。

第四轮敌对式审阅发现 31 个接缝：其中 21 个可以准确补入已有决策组或技术证明，10 个确实缺少主问题。责任归属审计又发现 raw 命令传输、活动 workspace 失效两个独立缺口；复审还发现“传入目录与上级 Git 根”的权限边界必须独立作答。因此本包集中 13 个正式决定。原 F4-13 的扩展运行时关闭已经由 D-038 确认，只在本包保留非回复式重入门；新发现的 Git 根轴使用 F4-14，避免复用已经归档的编号。若把另外 21 个重新包装成新题，只会让负责人对同一个意思回答两次。

- 一次 `ask-user` 跨过几小时后，究竟还是不是原 turn；
- 外部改过 INI 后，正在运行的 Agent 何时换 Key、Endpoint 和 Permission；
- main、side、review、compaction 同用一个 Model 时谁排队、谁消耗总账；
- shell 是否能偷走 TUI stdin，长命令又是否会被 Runtime 悄悄改写；
- 草稿、history/details、误贴的秘密到底有没有进入“完整 Context”；
- config/model/context 的删除是否共用一个可靠的管理事务；
- Context 数据根与 workspace 位于 FAT、SMB、NFS 等文件系统时，产品究竟承诺什么；
- 工作目录在 active turn 中消失后，旧审批和相对路径还能不能继续使用；
- 传入仓库子目录时，工作区边界是否保持原目录、提示提升，还是自动提升到 Git 根。

本包是补缝包，不替代 02--10。完整查漏证据见 [`FOURTH-ROUND-GAP-AUDIT.md`](../FOURTH-ROUND-GAP-AUDIT.md)，旧题到决策组和 readiness gate 的覆盖见 [`DECISION-TRACEABILITY.md`](../DECISION-TRACEABILITY.md)。

## 怎样回复

可直接回复：

```text
F4-01 A。
F4-02 接受 B。
F4-08 暂缓，先解释整 Context purge 会删除哪些已知副本。
F4-14 A。
其余接受推荐。
```

没有明确回答的条目继续保持待决。选择一项后，还要按 [`DECISION-RESOLUTION-PROTOCOL.md`](../DECISION-RESOLUTION-PROTOCOL.md) 归档到 `DECISIONS.md`、权威子系统规格、配置/XML schema、测试和证据门；不会因为本文标了“推荐”就自动生效。

## 已经确认、不在本包重问的前提

1. yaca 使用 Lua 5.5；Windows 是 Win32 x86，目标 XP SP3 至 11；Linux 是 x86_64，最低 CentOS 7；不承诺旧 macOS。
2. `yaca` 等于 `yaca .`；传入目录必须真实存在且可进入，并作为工作区发现、指令发现与 Resolver 的共同初始位置；是否进一步提升到 Git 根仍由 F4-14 决定。
3. 一个 Model section 是完整 LLM 连接实例，Key 直接明文写 INI；streaming 有 force/try/off。
4. DoubleCheck 同时覆盖危险动作和结束复核；`.cautious` 是当前 Context 的 DoubleCheck 覆盖，不是 Permission 模式。
5. Enter queue、Ctrl+Enter steer、Shift+Enter newline、Alt+Enter side、Esc cancel 的领域意图已经给出；旧终端仍需文本后备。
6. 模型调用 raw tools；不承诺 OS sandbox。Permission 仍要诚实表达 direct tool 与宽能力 shell 的差别。
7. Context 活动事实源是单 XML；长期项目数据只使用 INI/XML；复制 XML 的目标是让另一台机器取得继续工作的完整语义信息。
8. Context 没有永久 Context ID；名称、逻辑路径和 16 位运行时 hash 的 Resolver 规则已确认；分支对话不进入 v0.1。
9. v0.1 是所选闭环的完整可用版本，但保持封闭和简单；不把 MCP、插件、hook、skill runtime、子 Agent 等种类数量当成“完整”的定义。

## 本包十三项在系统里的位置

| 决策 | 直接改变 | 最终权威归属 |
| --- | --- | --- |
| F4-01 | 配置版本、生效点、外改冲突 | 05 配置、22 Runtime |
| F4-02 | Model 请求排队、冷却和总账 | 06 Model、09 AgentLoop、22 Runtime |
| F4-03 | `ask-user` 后 turn、快照和预算 | 09 AgentLoop、10 Context |
| F4-04 | 手动 retry 与副作用重放 | 03 Network、07 Tool、09 AgentLoop |
| F4-05 | 未提交 draft 的隐私和恢复 | 10 Context、14 TUI |
| F4-06 | `.history/.details` 的事实来源 | 10 Context、14 TUI |
| F4-07 | raw `exec` stdin 与交互边界 | 02 Process、07 Tool、14 TUI |
| F4-08 | Context 秘密删除与旧副本 | 08 Safety、10 Context、16 Release |
| F4-09 | 非 Agent 管理型破坏动作 | 05 Config、10 Context、11 Index、22 Runtime |
| F4-10 | data root/workspace 文件系统保证 | 01 Platform、10 Context、16 Release |
| F4-11 | raw 命令长度与编码失败 | 02 Process、07 Tool |
| F4-12 | active workspace 中途失效 | 00 Product、09 AgentLoop、10 Context |
| F4-14 | 传入目录与上级 Git 根边界 | 00 Product、01 Platform、07 Tool、10 Context |

## 建议的共同原则

下面十三项的推荐遵循同一条简化原则：一个 turn 使用冻结的有效配置；用户新动作建立清楚的新因果边界；任何可能重复外部副作用的动作都不被模糊的 retry 重放；未提交内容不伪装成 durable 事实；数据保证和工作区边界按真实平台能力明确声明。D-038 已排除的扩展不进入这些选项。

```text
external/user event
  -> normalize and validate
  -> freeze a versioned intent
  -> durable fact when required
  -> execute once within explicit capability/budget
  -> typed result or honest unknown
  -> project the same fact to TUI/CLI/XML
```

## 十三组正式决定

### F4-01 运行中外部修改配置何时生效

用户可能在 yaca 运行时用编辑器改变 `config.ini`。保存期间文件还可能短暂为空或只有一半。若 Runtime 每次读取字段，就可能让一次 turn 前半段使用旧 Permission、后半段使用新 Endpoint；若完全忽略外改，用户又可能以为保存已经生效。

- A：外部修改永不自动载入；只有显式 reload 或重启才全量解析、校验并建立新 generation。busy 时 reload 形成一个可查看/取消的排队意图，到 durable idle 才读取当前完整文件、显示脱敏 digest/diff 并激活；不自动 cancel 当前活动。（推荐）
- B：只在 idle/turn 边界比较 digest；发现变化后显示脱敏差异并询问是否载入。busy 期间只记录“磁盘候选已变化”，不解析或应用字段；回到 idle 后全量验证，无效候选保留旧 generation 但阻止新 turn，直到用户处理。
- C：仍只允许显式 reload；busy 时返回 typed `ReloadBusy`，不排队也不自动 cancel。用户可以另行用 Esc 收口当前活动，进入 idle 后再执行 reload。

推荐 A。三项都把每个已接受的 `ConfigGeneration` 视为不可变对象：reload 只会在完整 parse、schema/cross-field 校验和外部变化复核通过后建立新 generation；活动 turn 永远引用开始时冻结的旧 generation，绝不热改其中一个字段。A 不代表看不见外改：`.status`、reload 和下次管理入口仍显示磁盘候选与活动 generation 是否不同。

关联：AQ-361、`CFG-11`、`CFG-24`、`LOOP-15`、`ARCH-05`、TP-019、TP-020。

### F4-02 同一个 Model 的并发、请求间隔与冷却

main、side、action review、termination review、compaction、self-test 可能引用同一个 Model。仅有 HTTP retry 不足以回答：本地服务只能单并发怎么办、429 的 `Retry-After` 是否阻塞 side、review 是否能挤掉 main、不同 purpose 的 token 又算到哪一笔总账。

- A：不增加 Model 调度字段；每个逻辑 Model 固定单并发、零最小间隔，同一 Model 的所有 purpose 严格按进入 scheduler 的 FIFO 顺序执行，取消只移除自己的等待项。
- B：每个 Model 至少提供 `MaxConcurrentRequests` 和 `MinRequestIntervalMs`；同一逻辑 Model 的所有 purpose 共用一个 scheduler，等待项严格 FIFO，不让 main/review 插队；每项仍可单独取消并有自己的 local budget。（推荐）
- C：整个 yaca 同时只运行一个 Model request；全局队列按逻辑 Model 做无饥饿轮转、同一 Model 内 FIFO，没有 per-Model 并发/间隔字段。

推荐 B。它只增加两个容易理解的控制量，能表达单并发本地端点和常见限速；不在 v0.1 实现复杂 RPM/TPM 计费器。三项都明确公平性，也都把服务端 `Retry-After`/429 cooldown 只绑定到触发它的逻辑 `Model.<Name>`，不因 endpoint/remote model ID 相同而阻塞另一个 Model section；A/B 让该 Model 的所有 purpose 共享冷却，C 则在它冷却时调度其他可运行 Model。scheduler 只决定何时可以尝试，不能突破 Runtime hard cap，也不能把等待超时报告成 provider 已拒绝。

调度范围和计费/预算范围在三项中都分开：main/side/review/compaction 按所属 Context/turn aggregate 归集；显式 self-test 没有 Context/turn 时进入独立 `self_test_run` aggregate，同时仍受相同 Model scheduler 和进程 hard cap。

若且仅若 PJ-12=B，第一个 main turn 正常结束后还会产生一次 `context-name` purpose。它与其他 purpose 一样进入所选 Model 的同一 scheduler/cooldown，计入 Context/runtime aggregate，并拥有独立的“最多一次 request”lifecycle budget；它不属于已结束 main turn，不能重开该 turn 或消耗其剩余预算。等待/取消/失败只保留 provisional name，不阻断下一 main turn。PJ-12 选 A/C 时这个 purpose、队列项和预算不存在。

关联：AQ-362、`MODEL-15`、`CONC-04`、`NET-06`、`LOOP-04`、PJ-12、TP-015、TP-021、TP-022。

### F4-03 回答 `ask-user` 是旧 turn 继续还是新 turn

主模型提出问题后，用户可能几分钟或几天后才回答。期间配置、Model、Permission、工作目录和预算都可能改变。若仍把它当同一个 turn，旧冻结权限可能跨越很长时间；若完全视为无关新任务，又会丢掉“这是对哪个问题的回答”。

- A：继续原 turn，沿用原配置快照和剩余预算。
- B：旧 turn 以 `waiting_user` durable 收口；回答创建新 turn，并用 `reply_to_question`/`caused_by_turn` 关联旧问题，重新冻结配置、workspace、Prompt、Permission 和预算。（推荐）
- C：旧 turn 以 `waiting_user` durable 收口；回答作为普通 durable 用户输入创建新 turn，不建立 typed `reply_to_question` 关系，只依靠 canonical transcript 中相邻的问题/回答给模型恢复语义。

推荐 B。任务仍是连续的，但每次用户重新授权 Agent 推进都有清楚边界。TUI 可以显示 `replying to question 12:4`，模型视图则同时看到原问题、用户回答和中间发生的有效 Model/Prompt 变化。C 也不会绕过 durable user event，但跨压缩、多个待答问题或恢复后因果关系更弱。

```text
turn 12 -> model asks -> waiting_user (durable)
user replies
turn 13 -> reply_to question 12:4 -> freeze current configuration
```

关联：AQ-363、`LOOP-01`、`LOOP-28`、`CTX-07`、AL06-02、TP-017。

### F4-04 用户主动 retry 到底重试什么

错误卡上的 `retry` 如果没有对象，可能表示重新连接、重发模型 body、让模型重新生成，甚至再次执行 shell。最后一种会重复外部副作用；在上次结果 unknown 时尤其危险。

- A：只提供一个明确的 `retry task`；它总是建立带 `caused_by` 的新 turn 并冻结当前配置，绝不重放 accepted/unknown operation，也不复用旧 request ID。
- B：按阶段提供准确动作：只有证明请求尚未被接受、且没有规范响应时，Runtime 才能为同一 logical request 新建 transport attempt；`regenerate response` 只在没有 accepted tool/operation 且原 turn 仍活动时建立同 turn 的新 logical request，沿用冻结 snapshot 并消耗剩余 turn budget；终态错误后的 `retry task` 建立带 `caused_by` 的新 turn并冻结当前配置；accepted 或 unknown operation 只能 inspect/reconcile，绝不由通用 retry 重放。（推荐）
- C：完全没有手动恢复动作；用户重新输入自然语言任务。

推荐 B。它保留最准确的恢复动作；A 更简单但连安全的连接重试也会变成新任务，C 则把因果表达交给自然语言。三项都禁止“原样重放最后一步”。选择 B 时界面不显示没有对象的 `retry`，而使用下列唯一映射；每项都在 XML 中记录来源：

| UI action | 新身份 | snapshot / budget |
| --- | --- | --- |
| `retry connection` | 同一 logical request 的新 attempt | 同 turn snapshot；继续消耗同一 request/turn 预算 |
| `regenerate response` | 同一活动 turn 的新 logical request；仅限尚无 accepted side effect | 同 turn snapshot；重新计 request，但只使用 turn 剩余预算 |
| `retry task` | 新 turn，`caused_by` 指向失败 turn | 重新冻结当前配置/权限/工作区并取得新 turn budget |
| `inspect unknown` | 不执行新 request/operation | 只读显示并等待 reconcile |

关联：AQ-364、`LOOP-29`、`NET-07`、`LOOP-14`、`TOOL-15`、ED-04、TP-017、TP-018。

### F4-05 未发送 draft 是否属于“完整 Context”

用户可能已经写了几屏文字但还没发送。持续写入 XML 可以在崩溃后找回，却会把尚未提交的秘密持久化，并让单 XML 因每次按键频繁重写。完全不保存则可能丢掉草稿，需要明确告知。

- A：只有按发送后形成的 main/queue/steer/side 输入才 durable；draft 只在当前进程内，页面切换可以保留，崩溃后可能丢失，并显示 `draft: not saved`。（推荐）
- B：idle debounce 后将 draft 作为可删除 session state 写入 XML。
- C：draft 默认只在内存；用户显式执行 `.draft save` 后才作为可删除 session state 写入当前 Context XML，发送或 `.draft discard` 后追加清除事件。

推荐 A。它给“完整对话”一个清楚起点：用户明确提交之后。B 换取自动崩溃恢复，但会增加隐私、重写频率、导出与跨机含义；C 让用户显式决定何时持久化，代价是多一个命令和 XML session-state 生命周期。三项都不新增长期 draft 文件。正常 `.exit` 若仍有未保存 draft，应确认放弃，而不是静默丢失。

关联：AQ-365、`TUI-28`、`CTX-23`、TU-03、TP-022、TP-023。

### F4-06 `.history` 与 `.details` 能恢复到什么程度

如果 `.history` 只读当前终端缓存，恢复 Context 或换机后就看不到；若 `.details` 宣称总能显示原始全部工具输出，又会与 canonical result 的截断和配额事实冲突。

- A：两个命令只查看当前进程 UI cache。
- B：都从 canonical XML 和稳定局部 event ID 派生；`.history` 是事实 transcript 的分页投影，`.details` 只展示 XML 实际保存的完整、截断、摘要或引用状态，不声称找回从未持久化的字节。（推荐）
- C：`.history` 从 canonical XML 派生；`.details` 优先显示当前进程的 expanded cache，恢复后只显示 XML 中的 canonical 摘要/截断/引用字段，并明确标记 `expanded detail unavailable`。

推荐 B。这样恢复、跨机接盘和终端 scrollback 不再是三份互相漂移的历史。A 最简单但恢复后的浏览能力弱，C 保留当次运行的更丰富详情却不承诺跨机等价。三项都不新增长期 history/detail 文件；若 canonical result 记录 `truncated=true, original_bytes=...`，details 必须诚实显示这一事实，而不是生成一个看似完整的新摘要。

关联：AQ-366、`TUI-29`、`CTX-01`、`CTX-06`、TU-06、CX-03、TP-008、TP-010、TP-023。

### F4-07 模型 raw `exec` 的 stdin 来源

一个命令可能意外询问 `Are you sure?`，也可能故意从继承的 stdin 读取。若它继承 yaca 的终端，聊天、queue、审批和快捷键都可能被子进程偷走；若 Runtime 转发交互，则首版实际上需要 PTY/console bridge，而不再是简单的非交互 raw shell。

- A：模型 `exec` 的 stdin 固定关闭/EOF；v0.1 只支持有界、非交互、前台命令。内部 curl/helper 必须显式声明自己的受控 stdin source。（推荐）
- B：`exec` 允许模型在同一工具调用中提交一个有硬上限的 immutable `stdin_text` payload；Runtime 按明确编码完整写入后立即关闭 pipe，不从 yaca TUI 读取后续字节，不支持对话式应答。

推荐 A。需要固定输入的命令可在已批准的 raw shell 中使用管道/重定向；B 在不引入 PTY、不让子进程偷走聊天/审批键盘的前提下支持较大固定输入。两项都可在 v0.1 的非交互进程契约内完整测试；继承 TUI stdin 和交互 PTY 不再伪装成本组的普通分支。输入 EOF、进程仍不退出时，继续按 timeout/cancel/kill tree 契约收口。

关联：AQ-367、`PROC-11`、`PROC-03`、`TOOL-03`、TS-09、TP-005。

### F4-08 Context 误存秘密后提供哪种删除承诺

用户可能把 token 粘进普通消息、Prompt 或 shell。它可能已经进入正式 XML、previous-valid、临时文件、导出，也可能被 RF-03 的 migration/upgrade backup 保留在 yaca 已记录的旧 data root，或已发送给 provider。选择性重写既会改变事实 digest，也不能撤回已经发送的数据；“secure erase”在 SSD、备份和网络文件系统上更不能随便承诺。

- A：v0.1 不自动生成“sanitized”任务副本，只提供整 Context purge；执行前列出 yaca 管理的 active/previous/temp/trash/archive、已记录 diagnostic/export、RF-03 migration/upgrade backup 中该 Context 的副本，以及 yaca 已记录旧 data root 中可精确定位的同一目标；执行后逐项报告已删除/未找到/失败/无法证明。（推荐）
- B：在 purge 前，由用户手工编写或粘贴一段已自查的 clean handoff 文本，yaca 只预览该精确文本并建立一个全新、无 lineage 的 Context，不从旧 XML 自动抽取/摘要任何字段；新 Context durable 后再单独确认 purge 原任务。
- C：明确重开 canonical fact 不可变与 D-035 “完整对话”范围，提供 schema-aware selective redaction；用户精确指定字段/事件，yaca 为所有受管 generation 生成带 redaction tombstone 和新 digest chain 的替代历史，旧副本再按 purge 清单删除。选 C 必须以新决定 supersede 完整/不可变历史契约，不能当成小功能。

推荐 A 作为简单而诚实的首版。A 不伪称能自动判断任意文本里的秘密；B 保留继续工作的手工逃生路，但安全性由用户对精确 handoff 文本负责；C 是一个需要 schema、迁移、reader 和 digest 全面改动的正式范围重开。三项的 inventory 都必须查询 RF-03 产生/保留的迁移备份和 yaca 已记录旧 data roots，但只能 best-effort 清理当前知道、能精确绑定目标且有权操作的副本；不得为删除目标 Context 而删掉旧 data root 中其他 Context/配置。未被 yaca 记录的旧根、手工复制、OS/云备份、SSD 残留和已发 provider 内容无法撤回，不声称 secure erase。UI 都必须提示立即轮换已暴露 credential。

关联：AQ-368、`CTX-28`、`SAFE-09`、`CTX-06`、CX-16、RF-03、ED-07、TP-008、TP-019、TP-028。

### F4-09 config/model/context 的破坏动作是否共用管理事务

`config-repl reset`、删除仍被 Context 引用的 Model、永久清除 Context、import 和 migration 都不是 Agent tool call，不能复用模型 Permission/approval；但它们同样可能丢数据，而且会遇到“展示后目标已变化”的 stale race。

- A：每个 REPL 各自拥有完整的 plan、精确 target、stale check、逐资源发布、partial result 和 recovery 流程；不共享 `ManagementMutation` 类型或状态机。
- B：共用内部 `ManagementMutation` 契约：plan、精确 target、引用/影响、stale check、默认 cancel、每个资源自己的 durable commit barrier、typed partial result 和 recovery plan；各 REPL 只负责显示和收集选择。（推荐）
- C：破坏性管理动作只能在 Agent/Context writer 全部关闭的 offline management session 中执行，并且每次只改一个 INI 或 XML 资源；需要跨资源改变时拒绝并要求用户分步处理。

推荐 B。它不增加 Permission profile，也不意味着界面复杂；最简单的删除仍可以只显示一张确认卡，但底层必须用同一套正确性协议。B 不承诺多个 INI/XML 文件拥有文件系统级原子事务：plan 必须声明提交顺序和可恢复中间态，后一个资源失败时返回 `partial/recovery-required`，不能把已发布的前一个资源报告成“全部回滚”。A/C 也不得继承 Agent Permission 或历史 approval。

```text
plan(generation, targets, impact)
  -> user confirms exact plan
  -> stale check
  -> stage and validate each resource
  -> publish in declared order
  -> completed | failed-before-publish | partial/recovery-required
```

关联：AQ-369、`ARCH-05`、`CFG-10`、`CTX-11`、`INDEX-15`、TP-018、TP-019、TP-024。

### F4-10 Context 数据根与 workspace 的文件系统保证

Context 数据根需要 lock、flush、no-replace、atomic/recoverable replace；workspace 只要用户能访问，就可能位于 FAT、U 盘、SMB 或 NFS。对两者承诺完全相同，会让单 XML durability 变成无法兑现的口号；全部拒绝网络 workspace 又会不必要地限制实际使用。

- A：data root 和 workspace 都只允许通过完整本地文件系统验证的目录。
- B：data root 必须通过 durability/lock 能力证明；workspace 可以位于其他可访问文件系统，但 direct write/rename/delete 逐项做 capability check，不足时 fail-closed，并明确显示哪些保证降级；无法逐动作约束的 raw shell 只有在该 workspace 写入 tier 已通过证明时才可启用。（推荐）
- C：data root 仍必须通过 durability/lock 能力证明；未通过 workspace 写入能力证明的文件系统只允许读取/搜索，该 Context 的 direct write/rename/delete 和 raw shell 全部拒绝，直到显式换到受支持位置。

推荐 B。A 的保证最整齐但会拒绝很多真实网络/移动项目，B 逐动作降级，C 采用更容易解释的整 workspace 只读降级。三项都不对未经证明的文件系统宣称相同的锁、原子替换和掉电保证。产品文档应分成两张 support matrix，而不是只列 OS 名：

| 位置 | 最低需要 | 能力不足时 |
| --- | --- | --- |
| data root | 单 writer、可靠提交、恢复、可验证 replace | 拒绝成为可写数据根 |
| workspace | 安全枚举/读取；写动作所需的逐项原语 | 允许只读或拒绝该动作 |

具体 NTFS/FAT/SMB/ext4/NFS 结论由真实目标测试填写，负责人现在决定的是这条产品分层。

关联：AQ-370、`PLAT-13`、`PLAT-04`、`CTX-21`、`REL-02`、TP-011、TP-030。

### F4-11 raw shell 命令超过长度或编码边界时怎么办

Windows CreateProcess、目标 shell 和平台编码都有真实边界。Runtime 若自动把长命令写成脚本，会新增长期/临时文件、编码、权限、秘密、审计和删除语义；自动拆成多条则可能改变 `&&`、变量和副作用顺序。

- A：返回 typed `CommandTooLong`/`CommandEncodingUnsupported`；让模型缩短命令，或显式使用已获授权的文件工具在 workspace 创建可见脚本，再以一个新 `exec` 调用执行。（推荐）
- B：在正式 tool registry 中增加显式 `exec_script`；模型把完整脚本文本作为一个有硬上限的原子 payload 提交，审批卡绑定 shell/payload digest，Runtime 使用经目标平台证明的受控临时 carrier 执行，记录创建/执行/清理的 completed/failed/unknown；原始 `exec` 过长时仍只报错，不自动转换。

推荐 A。raw 的价值之一就是 Runtime 不猜 shell 语义，且用户可在 workspace 看见/审查脚本；B 是另一个明确、可验收的工具契约，不再伪装成 Runtime 的透明 fallback。两项都不自动拆分原命令；B 必须另行证明脚本编码、权限、secret、临时文件身份、清理、审计和目标 shell 行为。错误结果包含允许安全显示的实际长度、测量单位、目标 shell 与限制类别，不回显可能含 secret 的完整命令/payload。

关联：AQ-371、`PROC-12`、`TOOL-03`、`PROC-10`、TS-03、TP-005。

### F4-12 active turn 中工作目录消失或变成另一个对象

目录可能被外部重命名、卸载、断开或删除。此前已批准的相对路径和命令保存的是旧 workspace snapshot；自动找同名目录会把动作落到未经审阅的新对象。

- A：尚未开始的副作用 fail-stop；尽力取消/收口在途动作；Context 仍可只读检查。只有显式 rebind 成功后，才建立新的 workspace identity、Prompt、Permission 和 path snapshot，再从新 turn 继续。（推荐）
- B：只有目标平台/文件系统证明目录 handle 提供稳定 same-object identity，且每个已批准目标都能相对于该对象重新验证时，已经开始的 operation 才可继续收口；未开始的 operation 仍 fail-stop。任何一项证据缺失就自动退回 A，不能只凭“handle 还开着”继续。
- C：一旦 workspace 路径不可达或 identity 改变，当前 Context 立即退出可执行状态并要求关闭；不提供进程内 rebind，用户修复目录后必须重新启动/continue，重新冻结全部快照。

推荐 A。它在所有目标文件系统上语义一致；B 可减少本地 rename/挂载抖动造成的中断，但资格完全取决于 TP-012 对稳定对象身份、子路径约束和删除/重建 race 的证明，不能把 handle 当作天然授权；C 最保守但恢复步骤最长。已完成的副作用仍作为事实保存，无法确认结果的 operation 标记 unknown，不能假装 cancel 回滚。任何 rebind 都是管理动作，必须显示新旧规范路径和 Git/指令变化，旧审批全部失效。

关联：AQ-372、`PROD-16`、`CTX-13`、`LOOP-07`、`ARCH-05`、TP-012、TP-017。

### F4-14 传入目录与上级 Git 根怎样确定工作区边界

`yaca sub/dir` 已经确定了所有发现流程的初始位置，但当 `sub/dir` 位于更大 Git 仓库中时，还要明确 direct tool、raw shell、项目指令、Context 镜像和 Git status/diff 的安全边界。F4-14 只生成 initial invocation/new-Context boundary；工具各自向上猜会让同一 turn 同时拥有多个不一致的根。已选定旧 Context 的 recorded workspace 不是“发现上级 Git 根”，它在后一阶段专门由 PJ-13 处理。

- A：传入目录就是 initial boundary，也是新 Context 的 workspace 安全边界；发现的上级 Git 根只作可显示元数据，Git status/diff 必须用 pathspec/过滤限制在 boundary 内，不自动扩大读取、写入、Prompt 指令发现或 Resolver 起点。（推荐）
- B：若发现不同的上级 Git 根，在建立 initial boundary 前显示一次选择：保持传入目录或显式提升到 Git 根；对新 Context，选定值就是 workspace，改变必须走 rebind/new-turn。对 continue，它只是与 recorded workspace 比较的 initial boundary，不自动绑定旧 Context。
- C：启动时把 initial boundary 提升到最近上级 Git 根，但必须在任何 Model 请求/工具前明确显示“传入路径 -> initial boundary”并允许退出；没有 Git 根时仍使用传入目录。对新 Context，该 boundary 就是 workspace；对 continue，它不自动取代 recorded workspace。

推荐 A。它使 `yaca [目录]` 的参数本身就是可预测初始授权边界；B 适合经常从仓库子目录启动的用户，但增加一个启动决策；C 最省操作，却会扩大可见文件、项目指令和 shell cwd，因此只能在请求前醒目标示。三项都要求 Git helper 与 direct tools 使用同一个冻结 workspace snapshot，不能让 Git 自己把安全边界静默扩大。

#### F4-14 与 PJ-13 的固定组合顺序

| 场景 | 第 1 步：D-026 | 第 2 步：F4-14 | 第 3 步：Resolver/选择 | 第 4 步：PJ-13 | 禁止的捷径 |
| --- | --- | --- | --- | --- | --- |
| 新 Context | 规范化传入目录，它仍是所有发现起点 | 按 A/B/C 先得到 initial boundary，它直接成为新 workspace | 不选旧 Context | 不运行；还没有 recorded workspace | 用 Git 自行向上猜另一个根 |
| 显式 `--continue` 或用户选中 recent Context | 规范化传入目录，Resolver 起点不改 | 按 A/B/C 先产生 initial comparison boundary | Resolver 始终从传入目录镜像起步，选定精确 Context；选定动作不回写 initial boundary | 选定后才比较 recorded workspace；同 identity/boundary 按所选快捷策略，跨 boundary/不同 identity 显示精确 target 并确认 | 把 recorded Git root 当成 F4-14 B/C 已自动提升 |
| Context 继续后 rebind | 不改变本次 invocation 起点 | F4-14 已结束，不重跑也不再授权变根 | 不重跑 Resolver 猜目标 | PJ-13/F4-12 管理动作显示 old/new identity，使旧 approval 失效，从新 turn 继续 | 把 rebind 伪装成 `chdir` 或 Git metadata 刷新 |

因此 F4-14=A 也不禁止用户显式继续一个 recorded workspace 在上级目录的 Context；它只禁止“因为发现 Git 根就静默扩权”。反过来，F4-14=C 也不意味着可以无提示跳到任意 recorded workspace；跨 initial boundary/identity 仍必须经 PJ-13 确认。

关联：AQ-212、`CLI-00`、`PROD-05`、`PROD-16`、`INSTR-01`、`INDEX-05`、`CTX-13`、`TOOL-11`、D-026、TP-012、TP-029。

## 推荐的整包组合

若希望采用当前推荐基线，请明确回复本包 13 个正式组；F4-13 是已由 D-038 收口的非回复项，因此编号清单会跳过它：

~~~text
F4-01 A
F4-02 B
F4-03 B
F4-04 B
F4-05 A
F4-06 B
F4-07 A
F4-08 A
F4-09 B
F4-10 B
F4-11 A
F4-12 A
F4-14 A
~~~

也可以只回复差异，例如 `本包其余接受推荐；F4-02 B；F4-07 B。` 推荐不是决定，未明确回复的编号继续保持 unanswered。

## 已确认的扩展运行时关闭与未来重入门（原 F4-13；不需回复）

D-038 已确认 v0.1 采用封闭单 Agent 核心：只运行随包内置工具和内部生命周期逻辑；MCP、自定义第三方工具协议、进程内插件、用户 hook、skill runtime 和子 Agent 全部排除。配置/help/schema 不保留无消费者字段、空 loader、假命令或公共 Lua plugin API，遇到相应输入返回稳定 `UnsupportedFeature`，不静默忽略。

未来只有项目负责人明确提出具体 use case 才重入设计流。重新打开时必须同时给出信任边界、生命周期、配置、错误、Context 记录、权限矩阵、迁移和 Windows XP/CentOS 7 证据计划；不能仅以来源 ID/schema version 等已有窄字段推导“扩展已经预留”。这是一条现行规格门，不是 F4 选项，也不计入本包十三个待回复编号。

关联：AQ-373、`EXT-01`、`EXT-02`、`EXT-03`、`PROD-04`、`PROD-11`、`TOOL-14`、`LOOP-21`、D-038、TP-029。

## 另外二十一个发现怎样处理

这些项目同样必须收口，但已有决策组能够承担负责人选择，或完全属于技术证明。本表防止它们在本包之外再次失踪。

| 发现 | 不新增问题的原因 | 应补入的位置 |
| --- | --- | --- |
| Win32 CPU ISA floor | 已是发布 toolchain 选择的必要分支 | RF-04、AQ-206、REL-14、TP-001/002/030 |
| suspend/resume | 已有专用 suspend/resume 组与恢复/事件泵证据，只缺长时间间隙真值 | AL06-17、ED-05、AQ-270/AQ-315、RUNTIME-06 |
| plaintext HTTP Endpoint | Endpoint/TLS/Auth 已有主组 | M05-01/M05-02、AQ-137/AQ-146/AQ-220、NET-13 |
| purpose local cap 与 aggregate budget | 已有预算主组 | AL06-06/AL06-09、AQ-028/AQ-097/AQ-153/AQ-359 |
| `Tools=off` 主模型资格 | 已有 capability 主组 | M05-03、AQ-144 |
| 审批页编辑参数 | 已有审批主组；补“编辑使旧审批失效” | TU-07、TS-06、AQ-225/AQ-279 |
| queue list/drop/edit/reorder | 已有 busy-input 主组 | TU-04、AL06-04、AQ-032/AQ-086 |
| queue full 保留哪一边 | 是同一 queue policy 的 overflow 分支 | AL06-04、AQ-086、CONC-02 |
| main/side/tool/status 块交错 | 已有 transcript renderer 主组 | TU-03、AQ-299/AQ-333、TP-022/023 |
| direct `list` 精确语义 | 已有 tool registry 主组 | TS-02/TS-07、AQ-113、TP-014 |
| direct `search` dialect | 已有 tool registry 主组 | TS-02、AQ-114/AQ-184、TP-014 |
| stdout/stderr 跨管道顺序 | 物理上只能记录 observed arrival；属端口证明 | AQ-122、PROC-04、TP-005 |
| Git status/diff 外部 helper 风险 | 已有 Git/direct tool 主组 | TS-02/TS-11、AQ-129/AQ-249、TP-029 |
| config backup 复制明文 Key | 已有 secret lifecycle/migration 主组 | M05-02/M05-08、RF-03、AQ-132、TP-025/027 |
| `SensitiveRead` classifier | 不假定该能力必然存在；只在 M05-16 选中对应拆分后，再由 TS-04 定义各 preset 精确处理，classifier 只能提高限制 | M05-16、TS-04、AQ-149、SAFE-09、TP-014/027 |
| 单个 atomic group 已超窗口 | 已有压缩不可拆组主组 | AL06-11、AQ-062/AQ-310/AQ-352、TP-020 |
| Context 自动命名 request purpose | 新 Context 名称策略已有唯一 owner；只在所选路线需要 Model purpose 时生成对应 contract | PJ-12、PP-05、AQ-216/AQ-259 |
| release hash 与签名 | zip hash/manifest 与来源身份签名分属两个 owner | RF-06、RF-15、AQ-208、REL-10、TP-030 |
| 本地明文数据防谁 | 已有 threat/data-root 主组 | RF-02、AQ-040、THREAT-01、TP-027 |
| terminal resize/reflow | 已有 renderer 主组；推荐旧块不重画 | TU-01/TU-03、AQ-299/AQ-332、TP-023 |
| ambient `.curlrc`/Git/cmd/sh 配置 | 是兑现既有安全承诺的硬不变量，不是风格选择 | PROC-13、TP-006/029 |

这 21 行与 F4-01 至 F4-10 对应的十个第四轮新问题，合起来恰好覆盖 `FGA-001` 至 `FGA-031`。F4-11、F4-12 来自子系统责任审计；F4-14 把 AQ-212 与 D-026 尚未冻结的 Git 根边界提升成独立回复轴。原 F4-13 的扩展 namespace/关闭边界已经由 D-038 收口，只保留上面的非回复式重入门；完整来源和去重理由分别以相关审计文档为准。

## 十三项确认后必须同步生成什么

不能停在“选了 A/B”。本包至少要机械生成下列规格增量：

1. `ConfigGeneration`、reload command/state/error 与 turn freeze 表。
2. per-Model scheduler、purpose queue、cooldown 和 aggregate budget ledger。
3. `ask-user -> waiting_user -> reply turn` 的事件/ID/schema 和 golden trace。
4. transport attempt、send-again 与 unknown operation 的 retry matrix。
5. draft/history/details 的数据源、durability 和隐私矩阵。
6. process stdin、command length/encoding 和非交互契约。
7. Context purge/export/redaction 的正式承诺与 known-copy 清单。
8. `ManagementMutation` plan/confirm/stale/commit/recovery 状态机。
9. data-root/workspace 两张 filesystem support matrix。
10. workspace invalidation/rebind 状态机及旧 approval 失效规则。
11. startup directory、有效 workspace、Git metadata scope 与指令/Resolver/tool 边界矩阵。
12. 对应的 plain ASCII 页面、typed errors、fault fixtures 和真实平台证据。
13. 依据 D-038 生成 extension unsupported/无空壳检查与未来 re-entry gate；它不依赖负责人再次选择。

## 建议回答顺序

若一次回答全部，按 `F4-01 -> F4-02 -> F4-03 -> F4-04 -> F4-07 -> F4-11 -> F4-12 -> F4-14 -> F4-09 -> F4-05 -> F4-06 -> F4-08 -> F4-10`。它先锁配置/Loop/进程事实，再锁 workspace、管理、存储和隐私边界。

若只先回答最影响架构的六项，选：

1. F4-02：一个 Model 的 request scheduler 与总账；
2. F4-03：`ask-user` 后 turn 边界；
3. F4-04：retry 不得重放副作用；
4. F4-07：raw shell stdin；
5. F4-09：管理型变更事务；
6. F4-10：data root/workspace 文件系统承诺。

## 本包完成标准

- F4-01 至 F4-12 与 F4-14 每项有项目负责人明确回复，未答项仍标 open；原 F4-13 只按 D-038 生成规格，不等待再次选择；
- 回复已消除与旧决定的冲突，而不是让两个候选同时存在；
- AQ-361 至 AQ-372 加 AQ-212、十九个新增 checklist ID、旧组补充和技术证明可以双向追踪；
- D-038 排除的扩展从配置/help/schema 同时消失；非交互 stdin 契约与秘密 purge/redaction 范围则严格反映 F4-07/F4-08 的实际选择，不预先假装已经排除或已经支持；
- 对 suspend、ambient config、filesystem、CPU ISA、进程 I/O 等事实有目标平台证明；
- 在这些上游决定和 readiness P0 未收口前，仍不开始编码。
