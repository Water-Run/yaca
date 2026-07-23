# 设计决策分批队列

更新日期：2026-07-22

状态：保留为原子覆盖与依赖审计；不再作为项目负责人当前问卷

## 当前负责人入口

项目负责人认为 248 个原子问题过多，因此通过 [`OWNER-QUESTIONS-01.md`](OWNER-QUESTIONS-01.md) 的 28 个集中选择和 1 个 DoubleCheck 补问一次完成答复。`DISCUSSION-BATCH-06.md` 已归档回复，`DECISION-PROJECTION-BATCH-06.md` 已回投全部覆盖 ID；本文件的 49 批现在只用于证明旧 270 group 没有丢失、重复或违反依赖，不再是待答队列。

## 这份队列解决什么

270 组正式问题不应让项目负责人逐组作答，也不应只按文件顺序回答。某些跨系统问题实际是后续三个包的前置：例如一个进程允许几个 active Context，会直接改变 AgentLoop、writer lease、TUI 和关闭流程。

本文把当前十个 owner packet 回复模板中的 270 个 formal groups 每 3--6 组组成一批，且每个 group 恰好登记一次。owner 分布为 `PJ=19, PP=18, TU=32, M05=57, AL06=49, TS=35, CX=16, ED=14, RF=14, F4=16`；对应原子题库为 `AQ-001..AQ-437`，主题清单为 384 个唯一 ID。它现在只承担旧原子依赖与覆盖审计；实时状态、当前集中问题、原话和传播仍由 [`DECISION-REGISTER.md`](DECISION-REGISTER.md)、`OWNER-QUESTIONS-01.md` 与 discussion archive 连接。每次集中回复后都必须重算条件组与冲突，不能因为问卷变短就跳过仍 active 的产品保证。

## 回复节奏

1. 默认一次只讨论一批。先用通俗语言讲清“这个选择会让你实际看到什么”，再给 A/B/C、推荐和代价。
2. 可以回复 `接受本批推荐，但 <ID> ...`；仍会逐组展开归档，不会将一句话当作整个后续阶段的默认同意。
3. 如果一组的技术可行性尚未证明，先选择用户可见保证；具体 API、库、编译器和数字继续进入 TP，不让项目负责人猜。
4. 条件组只在上游使其 active 时产生规格；提前回答只保存 pre-answer，不生成空配置或空命令。

## Phase A：产品、界面和 Prompt 形状

| 批次 | 正式 groups | 为什么放在一起 |
| --- | --- | --- |
| `B01` | `PJ-01..PJ-05` | 已捕获；启动、bootstrap、离线、零历史扫描和首消息落盘已归档。 |
| `B02` | `F4-15`, `PJ-08`, `PJ-06`, `PJ-09`, `PJ-10` | PJ 四组已捕获；只剩 `F4-15` 的每进程 active Context 数量。 |
| `B03` | `F4-14`, `PJ-13`, `PJ-12`, `PJ-11` | PJ 三组及手工名称优先级补缝已捕获；只剩 `F4-14` 的初始唯一 root。 |
| `B04` | `PJ-14`, `PJ-17`, `PJ-18` | Web/remote 已排除，`PJ-18=A` 已确认单 root；本批已捕获。 |
| `B05` | `PJ-15`, `PJ-16`, `PJ-19`, `PJ-20` | image/audio/TTS 已排除；`PJ-19` 由 `PJ-16=A` 导出 not-applicable，本批已捕获。 |
| `B06` | `PP-01`, `PP-02`, `PP-06`, `PP-14..PP-16` | 一次冻结人格/语言、进度、工具叙述、最终报告与普通讲解详略，避免多个文字 owner 互相扩大输出。 |
| `B07` | `PP-03..PP-05`, `PP-07`, `PP-18`, `PP-19` | 权威链、项目规则、purpose/role、普通指令作用域与内置 bundle 冻结共同决定一次 request 的可重建指令协议。 |
| `B08` | `PP-08`, `PP-09`, `PP-11..PP-13`, `PP-17` | Prompt 升级/超限、旧 CustomPrompt、`.prompt` 编辑、规则变化与澄清门共同决定 Prompt 的变更生命周期。 |

## Phase B：TUI、输入、命令和 Help

| 批次 | 正式 groups | 为什么放在一起 |
| --- | --- | --- |
| `B09` | `TU-01`, `TU-02`, `TU-14`, `TU-20`, `TU-26`, `TU-33` | 一次选定 transcript 密度、基本色、状态、固定 ASCII chrome、独立输入提示符，以及 self-test 事实在同一逐行界面的组织方式；正文标签与 prompt 可自由组合。 |
| `B10` | `TU-03..TU-05`, `TU-16`, `TU-25`, `TU-28` | streaming/draft、五种输入意图、异步块排序、cooked-line 紧急可见性与能力降级提示共同保证弱终端输入不丢。 |
| `B11` | `TU-06..TU-08`, `TU-17`, `TU-29`, `TU-34` | 工具/diff 与 live preview、审批空 Enter/显式选择 grammar、错误/recovery 和授权失效是一条高风险操作体验；preview 不改变 canonical result，安全默认与页面语法可自由组合。 |
| `B12` | `TU-18`, `TU-10`, `TU-19`, `TU-22`, `TU-24`, `TU-32` | `TU-32=A` 已由 `.model` picker/direct 批注提前捕获；其余继续冻结顶层 CLI、简称、multiline/点转义、modal 跨界命令和 help topic grammar。 |
| `B13` | `TU-11`, `TU-13`, `TU-21`, `TU-23`, `TU-27`, `TU-30` | command×state receipt、非 TTY/machine/fd 拓扑与通知 transport 形成同一 CLI 真值表；`TU-30` 仅在 `TU-27 B/C` 时 active。 |

## Phase C：Model、完整配置、网络和 Self-Test

| 批次 | 正式 groups | 为什么放在一起 |
| --- | --- | --- |
| `B14` | `M05-01..M05-03`, `M05-25`, `M05-40` | 协议、Auth、Tools、streaming fallback 与公开 reasoning 先决定 Model adapter 的真能力；无工具 main 资格等 AL06-02 的 control carrier 明确后再问。 |
| `B15` | `M05-04`, `M05-05`, `M05-14`, `M05-23`, `M05-33`, `M05-50` | Endpoint 形状、timeout/retry、生成/资源参数、自定义 body/header 与 amount 来源共同决定 request/usage schema。 |
| `B16` | `M05-13`, `M05-36..M05-38`, `M05-32`, `TS-11` | 明文 HTTP、proxy、CA、redirect、Endpoint 投影与是否存在 direct HTTP tool 是一张网络信任/凭据传递表。 |
| `B17` | `M05-06`, `M05-16`, `M05-27`, `M05-39`, `M05-48`, `M05-56` | INI/XML 层级、Permission outside 粒度/管理、独立 SensitiveRead 字段、`.cautious` 与 DoubleCheck 默认值共同决定 effective session config；M05-16 与 M05-56 可自由组合。 |
| `B18` | `M05-07`, `M05-19`, `M05-28`, `M05-51`, `M05-54`, `M05-55` | INI multiline、optional、unknown/deprecated、Exec 资源、明文秘密文件权限和子进程环境基线共同决定 parser/writer 输入契约及外部执行边界。`M05-55` 只在 `M05-15 A/B` 时 active，在 B22 冻结上游前只能保存 pre-answer。 |
| `B19` | `M05-08`, `M05-30`, `M05-21`, `M05-34`, `M05-43`, `M05-44` | 先定 Model 顺序/disabled 草稿再发布首份配置；删除、颜色、Description 投影和列表密度共同表达 Model 身份。 |
| `B20` | `M05-09`, `M05-18`, `M05-29`, `M05-42`, `M05-45`, `M05-47` | model/config REPL 分工、effective view、reset/secret 副本与 Add Model/clone 草稿共同决定管理边界。 |
| `B21` | `M05-11`, `M05-31`, `M05-41`, `M05-46`, `M05-12`, `M05-53` | Stage 2 scope/failure/fidelity 先形成 exact manifest，再决定联网 consent、Stage 3 和 fresh rerun；每次 rerun 都重新走当前 consent。 |
| `B22` | `M05-15`, `M05-17`, `M05-20`, `M05-22`, `M05-35`, `M05-52` | raw shell env、日志、外发 metadata/override、self-test 持久化与 idle Model switch 共同封口配置怎样进入外界和 Context 历史。 |
| `B23` | `M05-57..M05-59` | 最后单独审核三个曾被候选 schema 暗定的配置面：资源简称是否存在、per-Model retry 暴露哪些控制、以及过短明文 secret 如何在兼容与 exact-scan 保证间取舍。 |

## Phase D：AgentLoop、DoubleCheck、预算与 Compaction

| 批次 | 正式 groups | 为什么放在一起 |
| --- | --- | --- |
| `B24` | `AL06-01`, `AL06-02`, `M05-26`, `AL06-09`, `AL06-18`, `AL06-19` | 状态 owner 与 typed control 先决定无工具 main 资格；`M05-26` 仅在 `M05-03 A/C` 时 active。预算骨架、无效 response 和协议纠错随后冻结一次采样的硬边界。 |
| `B25` | `AL06-04`, `AL06-13`, `AL06-36`, `AL06-37`, `AL06-38`, `AL06-48` | text/tool 顺序、partial 终态、mixed/普通无 control response、queue 自动启动与模型 yield 后续接共同决定完整 response 后的唯一路由。 |
| `B26` | `AL06-05`, `AL06-14`, `AL06-20`, `AL06-33`, `AL06-42`, `AL06-50` | steer、queue 管理/满载、多 queue item 组 turn、turn hard guard 和 stuck 阈值来源共同决定忙时 main lane 何时继续或必须收口。 |
| `B27` | `AL06-06`, `AL06-22`, `AL06-23`, `AL06-35` | side 容量/账本/结果合并与 Esc 目标共同决定多 lane 体验。 |
| `B28` | `AL06-07`, `AL06-08`, `AL06-24`, `AL06-25`, `AL06-44`, `M05-49` | action-review 范围/Model、人工 override/失败、pending approval 寿命与活动 Permission 切换是一条安全链；`AL06-08/24/25` 仅在 `AL06-07 A/B` 时 active。 |
| `B29` | `AL06-26`, `AL06-27`, `AL06-40`, `AL06-41`, `AL06-49`, `AL06-51` | 独立选择 termination-review Model、自动与人工解算、review retry 和特殊 purpose 跨 Endpoint 同意寿命，共同决定结束复核的隐私、上限和失败收口；AL06-49 不跟随 action-review 开关。 |
| `B30` | `AL06-43`, `AL06-10`, `AL06-15`, `AL06-46`, `AL06-17`, `AL06-29` | 金额门、验证义务/执行策略、active Model switch、suspend 与缺失映射共同决定运行环境变化；`AL06-43` 仅在 `M05-50 C` 时 active。 |
| `B31` | `AL06-11`, `AL06-12`, `AL06-16`, `AL06-30`, `AL06-34` | compaction view、大 Model 提示、超大原子组和 producer Model 先明确；`AL06-30/34` 仅在 `AL06-11 A` 时 active。 |
| `B32` | `AL06-31`, `AL06-32`, `AL06-45`, `AL06-39`, `AL06-47`, `AL06-28` | 先按 `AL06-32` 冻结 unfinished main 恢复，再决定 pending approval 重建，最后收口 compaction 失败/手动/纠正和 no-progress stuck；`AL06-31` 仅在 `AL06-11 A`、`AL06-39/47` 仅在 `AL06-11 A/B` 时 active，`AL06-45` 还消费 B28 的 `AL06-44`。 |

## Phase E：Tool Calling、权限、进程和改动证据

| 批次 | 正式 groups | 为什么放在一起 |
| --- | --- | --- |
| `B33` | `TS-02`, `TS-23`, `TS-16`, `TS-27`, `TS-32`, `TS-33` | exact tool/carrier 与 canonical retention 先定，再冻结 text read 范围、编码和 binary read；三种读取选择都消费同一 raw-byte identity。 |
| `B34` | `TS-04`, `TS-05`, `TS-07`, `TS-14`, `TS-18`, `TS-21` | Permission profile、授权记忆、链接/特殊文件、workspace trust、Autonomy 与 SensitiveRead 共同冻结能力矩阵；`TS-21` 仅在 `M05-56 B` 时 active。 |
| `B35` | `TS-08`, `TS-19`, `TS-25`, `TS-26`, `TS-28`, `TS-29` | undo/Git 证据与 direct write/patch/rename 契约共同决定改动怎样发布和归属；`TS-25/26` 仅在 `TS-02 A/C`、`TS-28/29` 仅在 `TS-02 A` 时 active。 |
| `B36` | `TS-10`, `TS-12`, `TS-13`, `TS-20`, `TS-22`, `TS-24` | tool 并行/batch 失败、unknown operation、shell 方言、跨通道输出和 foreground exec 收口共同决定宽进程边界。 |
| `B37` | `TS-35..TS-40` | direct 文件属性保真、list/search ignore、raw exec cwd、输出字节解码/binary、canonical 保留与 reserved-tree exact read 共同关闭“模型看到并修改了什么、命令在哪里运行、最终留下什么证据”的工具边界。 |

## Phase F：Context XML、导入、Resolver 和生命周期

| 批次 | 正式 groups | 为什么放在一起 |
| --- | --- | --- |
| `B38` | `CX-01`, `CX-05`, `CX-11`, `CX-13`, `CX-20`, `TU-15` | `CX-13=B` 已提前捕获；其余单 XML 提交、恢复、quota、外改和确认仍按本批讨论。 |
| `B39` | `CX-02`, `CX-07`, `CX-14`, `CX-16..CX-18` | 第三方/跨机接盘、明文隐私、Permission/Prompt 激活与 compatibility gap 共同冻结 import gate。 |
| `B40` | `CX-08..CX-10`, `CX-15`, `CX-19`, `TS-17` | 16 字符 hash、context-repl landing/搜索/rename/lifecycle 与通用 list/search 契约共同决定有界、稳定、可 stale 的浏览体验。 |

## Phase G：错误、关闭、旧终端与诊断

| 批次 | 正式 groups | 为什么放在一起 |
| --- | --- | --- |
| `B41` | `ED-01..ED-04` | error ID、severity/waiting-user、去重和 retry 可见性共同生成 ErrorRegistry。 |
| `B42` | `ED-05`, `ED-06`, `ED-11`, `ED-12` | Ctrl+C/EOF/broken pipe、writer 失败、Context 前崩溃与部分成功共同决定真实收口。 |
| `B43` | `ED-07..ED-10`, `ED-13`, `ED-14` | 先选本地 support，再计算一次性 upload：`ED-14` 仅在 `ED-07 A/B` 时 active；aggregate telemetry、Unicode/terminal/details 与 consent 仍保持独立。 |

## Phase H：发布、完整测试和跨系统收口

| 批次 | 正式 groups | 为什么放在一起 |
| --- | --- | --- |
| `B44` | `RF-01..RF-04` | zip 入口、data root、迁移/降级与 luainstaller 前置共同决定可交付生命周期。 |
| `B45` | `RF-05`, `RF-06`, `RF-14`, `RF-15`, `RF-16` | 组件 allowlist/UPX、SBOM/hash、CPU ISA、发布者签名与显式 update discovery/download 共同决定 exact zip 身份；RF-16 B/C 不能在没有 RF-15 B 的来源认证时成立。 |
| `B46` | `RF-08..RF-12` | 完整平台放行、性能、fault/soak、证据保留和 Model support contract 共同决定 release gate。 |
| `B47` | `F4-01..F4-04`, `F4-16`, `F4-17` | `F4-01 custom` 已提前固定逐顶层 turn 自动载入完整有效配置；其余 Model scheduler、ask-user 续 turn、pending question 数量/Enter 绑定与手动 retry 继续在同一时间边界讨论。 |
| `B48` | `F4-05..F4-07`, `F4-11`, `TS-30`, `TU-31` | draft/history/details/composer recall、raw exec stdin/命令传输与 tracked background job 共同检查进程内记忆和进程边界；`TS-30` 消费 B36 的 foreground 收口契约。 |
| `B49` | `F4-08..F4-10`, `F4-12`, `TS-31`, `TS-34` | secret purge、管理事务、data-root/workspace 失效、递归 delete 与 binary mutation 共同检查破坏性失败；`TS-31` 仅在 `TS-02 A`、`TS-34` 仅在 `TS-02 A/C` 时 active。 |
负责人选择共 49 批、270 个 formal groups。全部答复传播完成后另做一次**不投票的 final consistency gate**：

1. 机械证明 270 个 group 各出现一次，回复模板、register、owner 规格和 consumer 投影没有 missing/duplicate/extra；`AQ-001..AQ-437` 与 384 个 checklist ID 分别连续/唯一并能回到 owner。
2. 按最终上游选择重算全部静态条件：`PJ-19 <- PJ-16 B/C`（且 `PJ-19 C` 只与 `PJ-16 C` 相容）；`M05-26 <- M05-03 A/C`；`M05-55 <- M05-15 A/B`；`TU-30 <- TU-27 B/C`；`AL06-08/24/25 <- AL06-07 A/B`；`AL06-30/31/34 <- AL06-11 A`；`AL06-39/47 <- AL06-11 A/B`；`AL06-43 <- M05-50 C`；`TS-21 <- M05-56 B`；`TS-25/26/34/35 <- TS-02 A/C`；`TS-28/29/31 <- TS-02 A`；`ED-14 <- ED-07 A/B`。`AL06-49` 始终 active，不能因 `AL06-07 C` 关闭 action-review 而变成 inactive；其他 inactive 组的预先回答只保留审计，不得生成字段、命令、页面或空状态。
3. 重新对照 `F4-14` 已在 `B03` 选定的传入目录/安全根/Git 根规则，并验证 `RF-16 B/C` 不会绕过 `RF-15 B` 的来源认证；证明后续工具、指令、Context、更新与发布规格没有偷换边界。发现矛盾时按冲突协议重开原组，不能把同一组再选一遍。

## 每批完成后的硬动作

一批不是在聊天中说完就算完成。必须同一个事务完成：原话归档、register state、冲突/条件重算、`DECISIONS.md`、唯一 owner 规格、consumer 投影、readiness gate 和 inventory 校验。任一一项缺失时，可以进入下一批讨论，但不能宣称上一批已经 `specified`。

所有批次回复完成后，仍必须生成 readiness 要求的全部权威规格、矩阵、状态机与证据工件；TP 还必须对 XP x86/CentOS 7、Lua 5.5/ABI、事件泵、curl、XML、文件系统和最终 zip 给出目标证据。只有 [`ARCHITECTURE-READINESS.md`](ARCHITECTURE-READINESS.md) 的 P0 都通过，才按子系统生成 implementation plan；本文不是提前的编码计划。
