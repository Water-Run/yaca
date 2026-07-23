# 05 配置与模型注册表

状态：候选

## 职责

加载默认模板、完整用户 INI 和当前上下文 XML 中允许的会话覆盖，验证 General、TUI、Agent、Network、Exec、Permission、Context、Model 配置区域，产生只读的运行时配置快照，并支持受控更新与重置。

## 边界

- INI 语法由 04 号子系统处理。
- 交互式配置界面由 CLI/TUI 调用本系统提供的应用服务。
- “选择、重命名、删除上下文，并按目录树访问/搜索”的交互界面是 11 号上下文浏览器；本系统的配置编辑器只浏览配置 schema 与配置值，不能修改 `CONTEXT` 树。
- 模型协议请求由 06 号子系统处理。

## 设计要求

- 明确缺失、无效、未知字段的处理策略。
- 所有安全关键配置秘密只由同一 typed config-secret registry 枚举。当前至少包括 Key、proxy credential、条件 `SecretHeader`、条件 `EnvironmentSet` value，以及任何 adapter 后续注册的 secret；展示、日志、XML、review、clone 和导出不能维护一份会漏掉新类型的手写排除表。
- 每个已登记秘密都带 `config-file|ambient-environment|user-content|runtime` source。`M05-54` 只处理实际承载于被检查配置文件的 `source=config-file` secret 及其 ACL/mode 结论；config.ini 权限不能替 ambient/user/runtime source 背书，权限不足也不能误禁它们。
- Permission 已确认由物理第一项作为新 Context 默认；Model 的首项/disabled/无效行为仍由 M05-08 决定，不能共用一句含糊的“默认项”。
- 配置更新应原子写入并保留失败恢复所需的短期证据；是否另外制造含任一 `source=config-file` secret 的长期 backup/export 只由 M05-42 决定，不能把 temp/recovery 偷换成用户备份。

## 配置 generation 与逐 turn 自动载入

D-048 已关闭 F4-01：Model 和配置 INI 可以在 chat 持有 Context writer 时由 model-repl、config-repl 或外部编辑器修改；它们使用独立的短期配置提交锁，不与 Context writer lease 共用。每个新顶层 main/side turn admission 前，配置服务有界顺序读取完整 INI bytes并计算仅留在进程内的 private source digest：

1. digest 未变化时复用已经验证的 immutable `ConfigGeneration`，不重复构造全部 table；
2. digest 变化时对整份 bytes 做 parse、schema、cross-field、secret-source 和引用校验；全部成功后一次发布新 generation；
3. 有效变化自动从该 turn 生效，不弹 reload 确认；XML 写入不含 secret 的 generation transition；
4. 文件删除、不可读、半写或无效时阻止新 turn，只开放 bootstrap repair/status；不能静默使用旧 generation 继续；
5. current Model/Permission 被删除、重命名、禁用或失效时进入显式 switch/mapping，不按配置物理第一项猜；
6. active turn 及其 Model/tool/review/retry/compaction 子活动始终冻结 admission 时的同一 generation，绝不逐字段热换。

配置是小型控制文件，正确性基线不依赖 mtime/size 或 watcher；XP、FAT/网络盘和同尺寸快速改写都可能让这些提示漏检。实现可以选经过目标平台实测的高性能 Lua/C INI parser，并在 digest 相同后跳过解析，但不增加 reload interval、watcher 或 policy 开关。config/model REPL 保存仍用 expected source digest、完整临时文件验证和原子替换，不能覆盖外部并发编辑。

## 现有配置草案审计

逐字段讨论底稿已经单独展开为 [`../CONFIG-SCHEMA-CANDIDATE.md`](../CONFIG-SCHEMA-CANDIDATE.md)，包含八个核心区域（TUI 启动头字段始终存在，通知字段条件存在）、XML 覆盖白名单、INI 往返、registered config-secret carrier 技术证明入口和连续 `CV-001` 至 `CV-076` 的跨字段/生命周期校验。本文下面不再复制易漂移的 INI 片段；字段表冲突时也不能自行择一，必须回到正式 owner、配置 schema 与最终回复统一改写。

`src/_CONFIG_.ini` 已经列出很多字段，但“字段多”不等于配置系统完整。当前实际形态是一个全量用户 INI：

| 区域 | 已有草案 | 主要缺口 |
| --- | --- | --- |
| Network | 代理、stunnel、重试次数与延迟 | D-036 已把 retry 移到每个 Model；`UseStunnel` 没有随包资源；代理模式/URL、`NO_PROXY`、CA 与 redirect 已拆到 M05-36/37/38，显式/ambient proxy credential 必须带不同 source |
| Exec | 总超时、输出大小 | 用户资源表面由 M05-51，set/unset 由 M05-15，inherit baseline 由条件 M05-55；cwd、字节解码和 canonical retention 分别由 TS-37/38/39，termination grace 不是用户字段 |
| Permission | 当前模板仍有四个命名预设及 allow/confirm/regex | `Cautious` 和 profile 内 `DoubleCheck` 已被新回复否定；raw shell 统一为宽 `Shell`，外部 direct path 字段由 M05-16 决定 |
| Context | 自动跳目录、旧 AutoNameOnExit、压缩阈值 | 每 Context 恰好一个 root，由 XML 在 `CONTEXT` 镜像树中的父目录解码，不生成 workdir/root 配置字段；删除 AutoJump/ResumeDirectory。自动命名收敛为 `AutoNameEveryMainTurns`（0 关闭、默认 10）和 XML `AutoRenameDisabled`。列表排序只用 `ListSortBy=created|updated|name` 与 `ListSortDirection=ascending|descending`，默认 updated/descending。旧字段不猜测迁移；存储格式、配额、删除、迁移仍由 Context 系统 |
| Tui | 启动检查、性能检查、点命令补全 | 三个旧字段退出；`StartupSelfTest` 进入 General。启动头没有 master，只保留 Slogan/Version/WorkDir/DataRoot/ConfigStatus/Context/Hash/Model/Permission/DoubleCheck/StatusHint 逐字段开关；DataRoot 默认 false，其余 true，Slogan 与 `>>` 文本固定。通知字段才由 TU-27/TU-30 条件生成 |
| Model.* | endpoint、明文 key、模型 ID、窗口和 prompt | 已确认一个 Model 就是完整连接实例；streaming/retry/deadline/tool/auth/extension 等字段均已建立 M05 owner，选项仍待负责人回复 |
| Agent | 当前模板没有对应区域 | DoubleCheck 默认/会话覆盖、循环预算、彼此独立的 action-review/termination-review/compaction selector 和冻结语义已经分配给 M05/AL06/TS owner，不能凭旧模板补字段 |

旧模板跨 section 的缺口已经建立正式 owner，但还没有因“建立题目”变成已确认答案：

- `ConfigVersion`、迁移/降级、unknown/deprecated 与手工往返由 M05-07/19/28、RF/F4 组合收口。
- 内置 schema、完整用户 INI、Context XML 白名单、来源/effective-time 与 public/private generation digest 由 M05-06、M05-24 nonvote gate 和 `CV-001..076` 收口。
- 全局 `SystemPrompt`、`ContextPrompt` 与旧 `Model.CustomPrompt` 的权威顺序由 PP-03 × PP-11；不能只写“高于 SystemPrompt”。
- 文件顺序、disabled/invalid Model、引用中的 rename/delete 由 M05-08/34；不能静默跳到下一项。
- 手工编辑、REPL draft、冲突检测、原子发布与秘密副本分别由 M05-07/09/30/42、F4-01/09；temp/recovery 不等于长期 backup。

D-028 已明确选择简单模型：每个 `Model.*` 本身就是完整 LLM 连接实例，包含协议、endpoint、远端模型 ID、明文 Key、窗口、超时、流式和 retry。不会再拆独立 Provider、Credential 或 secrets 文件。重复 endpoint/key 是已接受的简单性成本；这只决定保存形态，不把 registry 缩成 Key 一种。条件 proxy credential、`SecretHeader`、`EnvironmentSet` value 与 adapter secret 仍统一登记，磁盘明文也不等于 TUI、诊断、reviewer 和 XML 可以回显任何一个值。

现有公开描述本身还有两处冲突，必须在设计阶段消除：README 说配置“注释丰富、可以手工编辑”，`_CONFIG_.ini` 文件头却写着禁止手工编辑；README 提供 `--set-default-model` / `--set-default-permission`，模板却又规定默认项完全由 section 顺序决定。前者只由 M05-07、后者只由 M05-08/49/52 与 TU-18 的最终组合收口；确认后要同时修改配置契约和公开说明，不能长期保留两套真相。

## 已被 B-08 修订的旧设计：独立终止评估开关

此前 D-020 采用独立“使用终止评估器”开关。B-08 的新回复已经改变用户配置面：结束复核并入 `DoubleCheck`，开启 `DoubleCheck` 时包含结束复核，关闭时没有结束复核。因此目标 schema 不再保留第二个 `UseTerminationEvaluator` 布尔值。

被合并的是用户开关，不是请求类型：AgentLoop 仍要把主生成、危险动作复核、结束复核、压缩、旁问和 self-test 识别成不同 request purpose，并分别记录用量、失败和关联对象。动作范围、action-review Model、termination-review Model、失败/超时与轮数预算已经分别进入 TS/AL06/M05 正式 owner；它们仍待回复，不能在配置文档里先给默认答案。尤其不能重新引入一个共用 reviewer selector：AL06-08 只拥有 action-review，AL06-49 只拥有 termination-review。

## 已确认的跨系统配置项：DoubleCheck 与 `.cautious`

`Cautious` 不再作为独立 Permission profile。`DoubleCheck` 改为谨慎复核的默认配置总开关；`.cautious` 只产生当前会话的覆盖值，不重排或切换权限组，也不重写用户默认配置。

会话覆盖写入当前上下文 XML 的会话参数元数据。加载上下文时，配置系统必须区分“用户默认值”“会话覆盖值”和“最终有效值”；`DoubleCheckOverride` 的三态/生效点只由 M05-27，完整白名单只由 M05-06，外来 XML 的降低激活只由 CX-14。对应选项仍待回复，不能退回成没有 owner 的“以后再定”。

当前推荐用三态表达 `.cautious` 覆盖：XML 中无值或 reset 表示继承 INI，`true` 表示当前上下文强制开启，`false` 表示当前上下文强制关闭。这样才能区分“用户明确关闭”和“没有覆盖”。

## 配置层级与 XML 白名单投影

长期配置来源已经收敛为内置 typed schema、完整用户 `config.ini` 和当前 Context XML 的白名单会话项；仓库不提供第三份 project config，也不能静默改变 endpoint、任一 config secret、代理、profile 定义或 Permission 定义。仍待回复的是 M05-06 对白名单宽度的三种正式路线，而不是旧底稿里的“XML 覆盖任意 INI”或“增加项目配置”：

- M05-06 A 只允许 CurrentModel、CurrentPermission、`DoubleCheckOverride` 与 `ContextPrompt` 四项。（当前推荐）
- M05-06 B 在四项上增加只会收紧的 turn budget 与 `CompactThreshold` overrides。
- M05-06 C 完整继承 B，再增加版本化、精确的 queue/side/diagnostic session preference；只有 TU-29 B/C 有真实 live-preview consumer 时才生成 `ToolPreviewKiBOverride`。

其他 `ActionReviewModelMapping`、`TerminationReviewModelMapping`、CompactionConsent、WorkspaceAcknowledgement 等条件项严格按各自 owner 路线生成，不能由 XML 自行启用功能。action mapping 只在 AL06-07 A/B + AL06-08 C 存在；termination mapping 只在 AL06-49 C 存在，两者独立校验、切换和失效，AL06-07 C 只让 action 字段 not-applicable。Exec 另有一个窄例外：**仅 M05-51 C** 才允许 `CurrentExecProfile` 精确 selector，并保存 non-secret effective resource snapshot、schema/profile-definition identity、public digest、old/new/source/generation transition 与 CX-07 mapping evidence。XML 不得定义 `[ExecProfile.*]`、保存环境 value 或让 Model 选择 profile；M05-51 A/B 时这个 selector 从 parser、writer、REPL、help 与 migration 同时消失。

无论选择 M05-06 A/B/C，都不能用任意 key 合并整个 INI；预算只能收紧，snapshot/mapping evidence 不是 override，外来 XML 也不能仅凭同名激活本机 Model/Permission/ExecProfile 或历史 approval。

## 八区 catalog 与条件字段

早期 INI 片段已经删除：把所有候选方案拼在同一个示例里，会让 `Network`、任意 header、环境注入或四套 deadline 看起来像必做配置，即使负责人选择的路线根本没有这些字段。逐字段唯一底稿是 [配置 schema 候选](../CONFIG-SCHEMA-CANDIDATE.md)，它按 owner 选择标明条件存在性。

| 区域 | 永久职责 | 主要 owner 选择 |
| --- | --- | --- |
| `General` | schema version、SystemPrompt、`StartupSelfTest`、若保留的诊断级别，以及条件 Stage 3 reviewer selector | PP-03/10/11、M05-12/17/19 |
| `TUI` | 无启动头 master；只有 Slogan/Version/WorkDir/DataRoot/ConfigStatus/Context/Hash/Model/Permission/DoubleCheck/StatusHint 逐字段开关（DataRoot 默认 false，其余 true）；只有 notification channel/event 条件生成；不承载 theme/vivid/language/keymap/prompt/renderer mode | 启动字段已确认；通知 TU-27/30 |
| `Agent` | DoubleCheck、TS-18 B 条件 Autonomy、条件 ActionReviewModel/TerminationReviewModel/CompactionModel、stuck 阈值，以及所选路线真正需要用户可调的硬预算 | TS-18、AL06-07/08/09/11/27/30/34/49/50、M05-06/27 |
| `Network` | Model 全局 proxy/CA/限额；TS-11 B/C 时另有独立 DirectHttp transport/origin policy | M05-14/36/37/38、TS-11 |
| `Exec` | 条件 timeout/output 表面、raw shell 环境配置与 inherit baseline；cwd、decoder、retention 只投影消费，不成为自由配置 | M05-15/51/55、TS-13/37/38/39、F4-07 |
| `Context` | 单一 root 的镜像路径派生事实（非配置/XML root 字段）、`AutoNameEveryMainTurns`、`ListSortBy`、`ListSortDirection`、专用 XML metadata `AutoRenameDisabled`、条件压缩阈值、特殊 purpose EndpointDisclosureConsent 与条件存储软配额；effective reserve 和 resolver scan cap 只作只读 Runtime/manifest 投影 | PJ-12/PJ-18、D-047、F4-14、AL06-11/12/51、CX-11/12 |
| `Permission.*` | direct capability 与宽 Shell 的三态策略、不具授权力的 `SystemPrompt`，以及条件 resource selector/Abbreviation | PP-03、TS-04/11/21、M05-16/56/57 |
| `Model.*` | 一个完整 LLM 连接实例及其 selector、协议/网络/retry/reasoning/scheduler | M05-57/58 与其他 M05 正式 owner、F4-02；当前 M05 选择组最晚至 M05-59，精确组以决策包 heading 为准 |

catalog 必须遵守以下删除规则：

- Permission 使用 `deny/confirm/allow`；raw shell 只消费宽 `Shell`，direct tools 才消费 Read/Write/Delete/outside/可选 DirectNetwork。
- `DirectNetwork` 只要 TS-11 B/C 真正加入 direct HTTP 就必须存在，不再由 M05-16 二次开关；TS-11 A 时从 parser、template、REPL、help 和 XML projection 同时消失。
- TS-11 A 时全部 `DirectHttp*` 配置字段同时消失；B/C 时使用独立 CA/proxy/no-proxy/redirect/exact-origin policy，绝不复用 Model 的任何 registered config-secret value。
- M05-16 只决定 workspace 外 modifier 是 A 的单一 `OutsideWorkspace`，还是 B 的 `OutsideRead/OutsideWrite/OutsideDelete`；它不再决定任何敏感读取能力。
- M05-56 独立决定 `SensitiveRead` 是否存在：A 时字段、classifier、页面和空壳帮助全部不存在；B 时才生成字段，分类和与 `Read` 取更严格值的规则由 TS-21，profile 默认由 TS-04。这个选择与 M05-16 A/B 可以任意组合。
- raw 环境 set/unset 字段只有 M05-15 B 存在；M05-15 A/B 的 `inherit` 变量成员政策只由条件 M05-55 决定。全局 configured proxy/credential 在任何方案下都不自动传播给 raw shell。
- `ExecEnvironmentSnapshot` 是 operation/approval 的 non-secret 证据，不是配置项或 override。它只保存 baseline identity/version、mode/source、canonical variable name 集合与 public digest；value、secret-derived digest 和 private keyed fingerprint 不进 XML。获准 shell 的未知输出仍可能含秘密，不能因 snapshot 是 public 就标成安全内容。
- 任意 `ShellProgram` 不存在；TS-13 A 固定 OS baseline，B 固定每个 zip manifest dialect，只有 C 可以产生发行 allowlist 驱动的 `ShellDialect`。TS-37 决定 cwd，TS-38 决定 bytes/decoder，TS-39 决定 canonical output retention；三者都不能伪装成一个自由 `ShellOptions` 字段。
- `TerminateGraceMs`、`OutputEncoding`、`CompactReserveTokens`、`MaxScanEntries` 不进入 parser、template、INI、XML override 或 REPL 编辑器。termination grace 由 Process adapter/Runtime，decoder 由 TS-38，reserve 由每次 view 计算，scan cap 由发行 manifest/Runtime 冻结；管理界面只可显示实际值与证明身份。旧草案出现这些 key 时给 unknown/deprecated diagnostic，不能自动保留成隐藏开关。
- PublicHeader/SecretHeader、ApiPath、明文 HTTP 确认、deadline 字段族、CA/Proxy 枚举、M05-40 C 的 `PublicReasoning` 与 M05-12 B 的 `SelfTestReviewerModel` 都按 owner 条件生成，不能把所有分支合并成“Advanced”。
- D-041 的 `AutoNameEveryMainTurns` 是唯一自动命名 INI 配置：0 关闭、默认 10，只计 durable main turn；退出或新 main 取消后台命名请求。初始名固定为 `Untitled Conversation [XXXX]`，`XXXX` 是四位大写 hex，不是 16 位路径 hash/永久 ID。旧 `AutoNameOnExit` 给 deprecated diagnostic 后删除，不猜间隔。XML metadata `AutoRenameDisabled` 不是 INI override：缺失/`false` 允许按周期命名，`true` 禁止；手工 rename 成功时默认与 rename 同一事务设为 `true`，自动 rename 不设置它。取消 marker 从当时 durable 水位建立新 baseline，不立即/追补；marker 变为 `true` 会使在途命名结果失效，迟到响应不能采用。
- `AutoJumpToDir` 和 `ResumeDirectory` 从 parser/template/REPL/XML 投影中删除；每个 Context 恰好一个 root，由当前 XML 的 `CONTEXT` 镜像父目录解码，不从 XML 内历史 cwd/root 值求当前绑定。新建时选哪个唯一 root 仍由 F4-14；rebind 只能是 context-repl 的 no-replace、可恢复镜像 XML 移动。
- Permission `SystemPrompt` 与 General/Context Prompt 一样是可追踪的 Prompt component，不是 capability；它不得授予、扩大或绕过 Read/Write/Delete/Shell/outside 任一三态策略。
- M05-18 只控制 non-secret config reset；含任一 `source=config-file` registered secret 的 backup/export 由 M05-42，Context purge 由 CX/F4，三者不能共享一个模糊 `factory reset`。
- `Cautious`、profile 内 DoubleCheck、独立 UseTerminationEvaluator、全局 retry、UseStunnel、旧 Tui 启动检查/性能检查/completion 空字段与 generic ExtraParameter 全部退出目标 schema；这不删除 TU-27 B/C 才存在的 notification 条件 section。旧 `Model.CustomPrompt` 的迁移/去留仍由 PP-11 明确回答；在此之前不能丢内容，也不能把它当成第三层现行权威。若 PP-11 A，迁移器逐 Model 来源选择 SystemPrompt、明确命名的 ContextPrompt 或 discard；多源同目标先生成可编辑 merge draft，先验证目标再清旧源，失败保留 partial outcome，不能猜“当前 Context”。
- quick preset 属于 model-repl 的添加模板，不把大量 disabled 空 section 预写进正式 INI；preset 不能成为另一份默认或权限真相。

## Model 级 streaming、retry 与全局代理候选语义

- `Streaming=force`：服务器不支持流式即报错，不静默降级。
- `Streaming=try`：精确 fallback 边界由 M05-25；推荐只在收到任何规范响应前且 endpoint 明确拒绝流式时允许一次非流式回退。
- `Streaming=off`：始终使用非流式。
- 一旦收到文本、工具调用或其他规范响应事件，不自动重放整次请求。
- `MaxRetry` 与退避属于各个 Model，不自动切换另一个 Model。
- `ConnectTimeoutMs`、`IdleTimeoutMs` 与 `TotalTimeoutMs` 分别约束连接、流式空闲和总请求；具体字段是否全部公开仍待决定。
- 全局代理只天然约束 yaca 自己的模型 HTTP。显式 proxy credential 是 `source=config-file`，environment 路线冻结的 proxy credential 是 `source=ambient-environment`；只有前者消费 M05-54 的 config-file ACL 政策。raw shell 内启动的 curl 等进程是否取得宿主变量属于 M05-15/55 与 Exec/安全契约，Network section 不能自动传播或假装拦截。

## 三阶段 self-test 与配置关系

用户回复已经确定总体顺序：静态基础检查完成后询问，第二阶段真实检查 LLM 配置；全部通过后进入第三阶段，用已验证 LLM 检查配置语义是否明显不合理。候选边界是：

1. 静态阶段检查 INI 语法/schema、重复/未知项、命名与顺序、跨字段约束、目录/临时写入、XML 解析和发行资源，不联网。它还遍历有界 Context Catalog：验证镜像父目录可解码、派生 workspace 存在且可进入、XML/恢复物/锁分类，并记录候选数、扫描量、hash 派生数、耗时、hard-cap/incomplete。慢的是目录遍历/metadata 探测而不是当前路径的一次短 hash；命中 cap 必须报告 partial/`ScanIncomplete`，不能宣称全量健康。
2. 在线阶段明确提示会联网/产生费用，再检查启用的 Model 的 DNS、TLS、代理、认证、协议、streaming 和工具能力；M05-41 独占是否复现 configured retry/fallback，consent 必须显示最坏 attempts。
3. 语义阶段只向模型发送由 typed registry 机械投影的脱敏配置，绝不发送任何 registered config-secret value；M05-12 明确 reviewer 的逐次选择/条件字段/多模型路线。它检查 Model logical name 与 remote model/endpoint、Permission 名称/Description/SystemPrompt 与 capability matrix 的明显错配和自然语言拼写问题；`TrustMeBro` 实际只读、`Readonly` 实际允许写/Shell 都可提示。schema key/enum/reference 拼写错误仍是 Stage 1 确定性错误。Stage 3 只形成 advisory，不能改配置、推导授权或代替 Stage 1/2 证明。

`General.StartupSelfTest=off|stage1|stage2|stage3` 决定普通 Agent 入口在打开/创建 Context 前必须执行到哪一阶段，默认 `off`。这不是 pass cache；选 stage3 也必须当次从 Stage 1 开始严格 1→2→3。Stage 2/3 仍分别显示网络、费用、Model 和外发数据后询问。取消、失败或排除 required check/Model 形成的 `partial` 都不能通过启动 gate。显式 self-test 的语义参数是 `through_stage=1|2|3`、重复 exclusions、可重复 selected checks 和不联网的 `list-checks`；精确 through-stage/list/exclude/check argv 名由 TU-18 投影，本系统不另冻结。

普通 Agent 启动在配置无效或没有有效 Model 时拒绝进入 chat，也不发布第二种“管理态有效 generation”。help/version、self-test Stage 1、config-repl、model-repl 和独立 context-repl CRUD 使用内置 typed schema 的受限 bootstrap service；它们不启动 Agent/工具、不联网、不把坏 generation 激活。context-repl 可 list/inspect/rename/delete/import/restore/repair/rebind XML，并查看、添加或取消专用 `AutoRenameDisabled` 标记，但不发送 Model request 或续接 chat；目标已有活动 writer 时只能显示不解析正文即可取得的 name/logical path/busy/PID-or-unknown 元数据，不进入 read-only Context view，全部 mutation 拒绝至 lease 释放。取消命名标记从当前 durable 水位建立新 baseline，不立即/追补；添加标记或手工 rename 置 true 会取消/逻辑失效在途命名，迟到结果不得采用。三个 REPL 都有领域自己的 `self-fix-program` 选单，只能扫描→预览 typed plan→确认→原子发布，不可自动修改。每个 TUI 领域动作由同一 registry 生成 CLI 投影；顶层 CLI 拼写只由 TU-18 投影。

## 正式 owner 覆盖（不是已确认答案）

[配置决策包 05](../decision-packets/05-model-configuration-network-selftest.md) 当前有 57 个正式 M05 选择组，编号最晚至 `M05-59`；`M05-10` 与 `M05-24` 是不另投票的跨系统/完整性门。`CV-001..076` 是机械校验，不是额外产品偏好。下面列的是题目已经归属到哪里，不表示推荐项自动生效：

| 设计面 | 唯一/组合 owner |
| --- | --- |
| 配置层级、XML override、`.cautious` 与新配置 DoubleCheck | M05-06/M05-27/M05-39；外来安全激活由 CX-14 |
| Model 顺序、资源 selector/Abbreviation、disabled 草稿、引用 rename/delete、idle 切换 | M05-08/M05-57/M05-34/M05-52；active-turn 时点由 AL06-10 |
| REPL 分工、列表/添加/clone、effective field 页面与首份发布 | M05-09/M05-29/M05-30/M05-44/M05-45/M05-47；共同事务由 F4-01/F4-09 |
| schema grammar、optional、unknown/deprecated、reset 与秘密副本 | M05-07/M05-18/M05-19/M05-28/M05-42；catalog parity 由 M05-24 + CV gate |
| Model protocol/auth/tools/stream/retry/deadline/extension/network | M05-01/M05-02/M05-03/M05-04/M05-58/M05-05/M05-13/M05-14/M05-23/M05-25/M05-26/M05-33/M05-36/M05-37/M05-38/M05-40；scheduler 另见 F4-02 |
| self-test 的范围、consent、失败继续、retry/fallback、reviewer、持久性与 rerun | M05-11/M05-12/M05-31/M05-35/M05-41/M05-46/M05-53 |
| Permission outside/SensitiveRead 字段、管理与切换 | M05-16/M05-56/M05-48/M05-49；动作分类与 direct tool owner 在 TS |
| Exec 资源、环境配置、inherit baseline、Context profile selector | M05-15/M05-51/M05-55；cwd/decoder/retention 分别由 TS-37/TS-38/TS-39 |
| config-file 权限不足与过短秘密的 consumer/scanner | M05-54/M05-59；前者只覆盖 typed registry 中 `source=config-file` 的权限 observation，后者决定低于安全扫描门槛时的可用性与正文保证 |
| 诊断、metadata 投影、标签色、CLI override 与金额来源 | M05-17/M05-20/M05-21/M05-22/M05-32/M05-43/M05-50；各字段只在所选路线生成 |

这些 owner 回复后，必须同批投影到 typed schema、parser、writer、REPL、XML whitelist、redaction、migration、self-test、help 与 `CV-001..076`。任何只改字段表、却不改 consumer 或 secret/source 分类的答案都不构成设计闭环。

## 当前讨论入口

按决策批次回复正式 owner；Prompt 权威链和 XML 覆盖白名单仍是高上游项，但不是唯一入口。每个最终保留字段都必须追溯到已回复的运行行为，并通过 M05-24/`CV-001..076` parity gate，不能因为旧模板已有或其他 Agent 有类似选项就保留。
