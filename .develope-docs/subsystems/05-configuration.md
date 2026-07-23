# 05 配置与模型注册表

状态：候选

## 职责

加载默认模板、完整用户 INI 和当前上下文 XML 中允许的会话覆盖，验证 General、Agent、Network、Exec、Permission、Context、Model 等配置区域，产生只读的运行时配置快照，并支持受控更新与重置。

## 边界

- INI 语法由 04 号子系统处理。
- 交互式配置界面由 CLI/TUI 调用本系统提供的应用服务。
- “选择、重命名、删除上下文，并按目录树访问/搜索”的交互界面是 11 号上下文浏览器；本系统的配置编辑器只浏览配置 schema 与配置值，不能修改 `CONTEXT` 树。
- 模型协议请求由 06 号子系统处理。

## 设计要求

- 明确缺失、无效、未知字段的处理策略。
- API key 属于秘密字段，展示、日志和导出必须脱敏。
- Permission 已确认由物理第一项作为新 Context 默认；Model 的首项/disabled/无效行为仍由 M05-08 决定，不能共用一句含糊的“默认项”。
- 配置更新应原子写入并保留失败恢复所需的短期证据；是否另外制造含 Key 的长期 backup/export 只由 M05-42 决定，不能把 temp/recovery 偷换成用户备份。

## 现有配置草案审计

逐字段讨论底稿已经单独展开为 [`../CONFIG-SCHEMA-CANDIDATE.md`](../CONFIG-SCHEMA-CANDIDATE.md)，包含七个区域、XML 覆盖白名单、INI 往返、Key→curl 技术候选和连续 `CV-001` 至 `CV-065` 的跨字段/生命周期校验。本文下面的 INI 片段只保留为早期边界示意，不再代表最完整字段表；两者冲突时也不能自行择一，必须回到决策包确认并统一改写。

`src/_CONFIG_.ini` 已经列出很多字段，但“字段多”不等于配置系统完整。当前实际形态是一个全量用户 INI：

| 区域 | 已有草案 | 主要缺口 |
| --- | --- | --- |
| Network | 代理、stunnel、重试次数与延迟 | D-036 已把 retry 移到每个 Model；`UseStunnel` 没有随包资源；代理模式/URL、`NO_PROXY`、CA 与 redirect 已拆到 M05-36/37/38 |
| Exec | 总超时、输出大小 | 取消/进程树与 Runtime `auto` 解码契约、条件环境、逐工具限制；termination grace 与 decoder 都不是用户字段 |
| Permission | 当前模板仍有四个命名预设及 allow/confirm/regex | `Cautious` 和 profile 内 `DoubleCheck` 已被新回复否定；raw shell 统一为宽 `Shell`，外部 direct path 字段由 M05-16 决定 |
| Context | 自动跳目录、旧 AutoNameOnExit、压缩阈值 | PJ-12 已把命名拆为首次持久化的本地建议/首 turn 后 Model 建议/显式输入；旧 AutoNameOnExit 删除，B 的建议固定执行也不另设偏好。存储格式、配额、删除、迁移仍由 Context 系统 |
| Tui | 启动检查、性能检查、点命令补全 | 启动自动联网与三阶段 self-test 冲突；用户已要求不提供 theme/vivid/mode/自定义键配置，因此是否还保留整个 section 待定 |
| Model.* | endpoint、明文 key、模型 ID、窗口和 prompt | 已确认一个 Model 就是完整连接实例；仍缺 streaming 枚举、Model 级 retry、分阶段超时、工具能力与可选请求参数 |
| Agent | 当前模板没有对应区域 | 全局 `DoubleCheck`、循环预算、DoubleCheck 轮次上限和会话冻结语义 |

跨 section 还缺少：

- `ConfigVersion` 和可回滚迁移契约。
- 内置 schema 默认、完整用户 INI 与上下文 XML 白名单覆盖的层级与来源显示。
- 全局 `SystemPrompt` 及其与 `ContextPrompt` 的权威顺序；旧草案 `Model.CustomPrompt` 当前推荐删除但尚待确认。
- 文件顺序默认模型/权限在首项禁用、无效或重排时的严格语义。
- 未知/废弃字段的往返、警告与拒绝策略。
- 同时手工编辑和交互式更新时的锁、冲突检测与备份。

D-028 已明确选择简单模型：每个 `Model.*` 本身就是完整 LLM 连接实例，包含协议、endpoint、远端模型 ID、明文 Key、窗口、超时、流式和 retry。不会再拆独立 Provider、Credential 或 secrets 文件。重复 endpoint/key 是已接受的简单性成本；磁盘明文不等于 TUI、诊断、reviewer 和 XML 可以默认回显 Key。

现有公开描述本身还有两处冲突，必须在设计阶段消除：README 说配置“注释丰富、可以手工编辑”，`_CONFIG_.ini` 文件头却写着禁止手工编辑；README 提供 `--set-default-model` / `--set-default-permission`，模板却又规定默认项完全由 section 顺序决定。后续选择任一方案时都要同时修改配置契约和公开说明，不能长期保留两套真相。

## 已被 B-08 修订的旧设计：独立终止评估开关

此前 D-020 采用独立“使用终止评估器”开关。B-08 的新回复已经改变用户配置面：结束复核并入 `DoubleCheck`，开启 `DoubleCheck` 时包含结束复核，关闭时没有结束复核。因此目标 schema 不再保留第二个 `UseTerminationEvaluator` 布尔值。

被合并的是用户开关，不是请求类型：AgentLoop 仍要把主生成、危险动作复核、结束复核、压缩、旁问和 self-test 识别成不同 request purpose，并分别记录用量、失败和关联对象。尚未确认的是 DoubleCheck 复核哪些动作、使用哪个 Model、失败/超时策略和最大复核轮数。

## 已确认的跨系统配置项：DoubleCheck 与 `.cautious`

`Cautious` 不再作为独立 Permission profile。`DoubleCheck` 改为谨慎复核的默认配置总开关；`.cautious` 只产生当前会话的覆盖值，不重排或切换权限组，也不重写用户默认配置。

会话覆盖写入当前上下文 XML 的会话参数元数据。加载上下文时，配置系统需要区分“用户默认值”“会话覆盖值”和“最终有效值”，但具体 XML 字段、覆盖值缺失/损坏时的回退，以及 `DoubleCheck` 统辖哪些复核子能力尚未确认。

当前推荐用三态表达 `.cautious` 覆盖：XML 中无值或 reset 表示继承 INI，`true` 表示当前上下文强制开启，`false` 表示当前上下文强制关闭。这样才能区分“用户明确关闭”和“没有覆盖”。

## 配置层级总体方向

### A. 内置 schema 默认 + 完整用户 INI + XML 白名单覆盖（当前推荐）

Lua 内的 typed schema 定义字段、类型、默认和跨字段约束；`config.ini` 保存完整用户配置；当前 context XML 只保存经过白名单允许的会话选择和覆盖。候选白名单是当前 Model、当前 Permission、`DoubleCheck` 三态覆盖与 `ContextPrompt`。仓库文件不能静默改变 endpoint、Key、代理或权限定义。

这最贴合“配置由 INI 全量配置和 XML 覆盖组成”，且长期数据仍只有 INI/XML。是否允许 XML 覆盖更多 Agent/Context 字段需要逐项确认，不能用任意 key 合并整个 INI。

### B. XML 可覆盖任意 INI 字段

表达力最强，但一个复制来的 context 可以改写 Key、代理、权限 profile 和执行上限；来源解释、跨版本迁移和安全边界都会显著变复杂，不推荐。

### C. 再增加项目配置文件

会在 INI/XML 之外引入第三个配置来源，也让陌生仓库有机会影响模型或权限。当前没有明确需求，不建议进入 v0.1。

## 七区 catalog 与条件字段

早期 INI 片段已经删除：把所有候选方案拼在同一个示例里，会让 `Network`、任意 header、环境注入或四套 deadline 看起来像必做配置，即使负责人选择的路线根本没有这些字段。逐字段唯一底稿是 [配置 schema 候选](../CONFIG-SCHEMA-CANDIDATE.md)，它按 owner 选择标明条件存在性。

| 区域 | 永久职责 | 主要 owner 选择 |
| --- | --- | --- |
| `General` | schema version、SystemPrompt、若保留的诊断级别，以及条件 Stage 3 reviewer selector | PP-03/10/11、M05-12/17/19 |
| `Agent` | DoubleCheck、TS-18 B 条件 Autonomy、条件 ReviewModel/CompactionModel，以及所选路线真正需要用户可调的硬预算 | TS-18、AL06-07/08/09/11/27/30/34、M05-06/27 |
| `Network` | Model 全局 proxy/CA/限额；TS-11 B/C 时另有独立 DirectHttp transport/origin policy | M05-14/36/37/38、TS-11 |
| `Exec` | raw shell timeout/output 以及条件环境/dialect；平台 termination grace 与内建 auto decoder 只作只读 Runtime/manifest 投影 | M05-15、TS-13/22、F4-07 |
| `Context` | Context 体验、命名建议、条件压缩阈值与条件存储软配额；effective reserve 和 resolver scan cap 只作只读 Runtime/manifest 投影 | PJ-12、AL06-11/12、CX-11/12 |
| `Permission.*` | direct capability 与宽 Shell 的三态策略 | TS-04/11/21、M05-16 |
| `Model.*` | 一个完整 LLM 连接实例及其协议/网络/retry/reasoning/scheduler | M05-01..42、F4-02 |

catalog 必须遵守以下删除规则：

- Permission 使用 `deny/confirm/allow`；raw shell 只消费宽 `Shell`，direct tools 才消费 Read/Write/Delete/outside/可选 DirectNetwork。
- `DirectNetwork` 只要 TS-11 B/C 真正加入 direct HTTP 就必须存在，不再由 M05-16 二次开关；TS-11 A 时从 parser、template、REPL、help 和 XML projection 同时消失。
- TS-11 A 时全部 `DirectHttp*` 配置字段同时消失；B/C 时使用独立 CA/proxy/no-proxy/redirect/exact-origin policy，绝不复用 Model Key/header/proxy credential。
- M05-16 只决定 coarse/split outside 与 `SensitiveRead` 字段是否存在；只有 C 产生 SensitiveRead，分类和更严格求值由 TS-21，profile 默认由 TS-04。
- raw 环境字段只有 M05-15 B 存在；全局 configured proxy/credential 在任何方案下都不自动传播给 raw shell。
- 任意 `ShellProgram` 不存在；TS-13 A 固定 OS baseline，B 固定每个 zip manifest dialect，只有 C 可以产生发行 allowlist 驱动的 `ShellDialect`。TS-22 的 stdout/stderr 顺序是结果契约，不是配置字段。
- `TerminateGraceMs`、`OutputEncoding`、`CompactReserveTokens`、`MaxScanEntries` 不进入 parser、template、INI、XML override 或 REPL 编辑器。前两项由 Process adapter/Runtime，reserve 由每次 view 计算，scan cap 由发行 manifest/Runtime 冻结；管理界面只可显示实际值与证明身份。旧草案出现这些 key 时给 unknown/deprecated diagnostic，不能自动保留成隐藏开关。
- PublicHeader/SecretHeader、ApiPath、明文 HTTP 确认、deadline 字段族、CA/Proxy 枚举、M05-40 C 的 `PublicReasoning` 与 M05-12 B 的 `SelfTestReviewerModel` 都按 owner 条件生成，不能把所有分支合并成“Advanced”。
- PJ-12 A/B/C 都不产生自动命名配置字段；B 固定在首个完成 main turn 后执行一次建议。旧 `AutoNameOnExit` 给 deprecated diagnostic 后删除，不能迁成隐藏开关。
- M05-18 只控制 non-secret config reset；含 Key/Proxy credential 的 backup/export 由 M05-42，Context purge 由 CX/F4，三者不能共享一个模糊 `factory reset`。
- `Cautious`、profile 内 DoubleCheck、独立 UseTerminationEvaluator、全局 retry、UseStunnel、Tui 空壳与 generic ExtraParameter 全部退出目标 schema。旧 `Model.CustomPrompt` 的迁移/去留仍由 PP-11 明确回答；在此之前不能丢内容，也不能把它当成第三层现行权威。
- quick preset 属于 model-repl 的添加模板，不把大量 disabled 空 section 预写进正式 INI；preset 不能成为另一份默认或权限真相。

## Model 级 streaming、retry 与全局代理候选语义

- `Streaming=force`：服务器不支持流式即报错，不静默降级。
- `Streaming=try`：精确 fallback 边界由 M05-25；推荐只在收到任何规范响应前且 endpoint 明确拒绝流式时允许一次非流式回退。
- `Streaming=off`：始终使用非流式。
- 一旦收到文本、工具调用或其他规范响应事件，不自动重放整次请求。
- `MaxRetry` 与退避属于各个 Model，不自动切换另一个 Model。
- `ConnectTimeoutMs`、`IdleTimeoutMs` 与 `TotalTimeoutMs` 分别约束连接、流式空闲和总请求；具体字段是否全部公开仍待决定。
- 全局代理只天然约束 yaca 自己的模型 HTTP。raw shell 内启动的 curl 等进程是否继承代理环境属于 Exec/安全契约，不能由 Network section 假装拦截。

## 三阶段 self-test 与配置关系

用户回复已经确定总体顺序：静态基础检查完成后询问，第二阶段真实检查 LLM 配置；全部通过后进入第三阶段，用已验证 LLM 检查配置语义是否明显不合理。候选边界是：

1. 静态阶段检查 INI 语法/schema、重复/未知项、命名与顺序、跨字段约束、目录/临时写入、XML 解析和发行资源，不联网。
2. 在线阶段明确提示会联网/产生费用，再检查启用的 Model 的 DNS、TLS、代理、认证、协议、streaming 和工具能力；M05-41 独占是否复现 configured retry/fallback，consent 必须显示最坏 attempts。
3. 语义阶段只向模型发送脱敏配置，绝不发送 Key；M05-12 明确 reviewer 的逐次选择/条件字段/多模型路线。“Yolo 却只读”等命名判断只形成 advisory，不能代替确定性 schema 证明。

普通 Agent 启动在配置无效时拒绝进入 TUI 已得到明确方向。`--self-test`、`--config-repl` 和重置命令能否使用最小 bootstrap parser 在无效配置下运行，仍需确认；若也全部拒绝，用户只能手工修文件。

## 后续必须分别讨论

1. XML 会话覆盖的最终白名单，以及每项何时冻结生效。
2. 默认项按文件顺序时，第一项禁用/无效、重复 section 和重排的行为。
3. Permission 的 `deny/confirm/allow` 矩阵，以及 raw shell 的宽 `Shell` 权限边界。
4. `Model.CustomPrompt` 去留、SystemPrompt/ContextPrompt 优先级、多行编码与恢复快照。
5. Model 是否需要自定义 HTTP headers/body 参数和显式工具能力字段。
6. `DoubleCheck` 的动作范围、复核 Model、失败策略和轮数预算。
7. schema 未知/废弃字段、迁移、降级和手工编辑往返策略。
8. 原子更新、短期 temp/lock、冲突和恢复；M05-42 单独决定含 secret 的长期 backup/export。
9. config/model/context REPL 的统一命名、简称、草稿事务和保存确认。
10. self-test Stage 2 的 retry/fallback 复现方式，以及 Stage 3 reviewer 的显式选择、条件字段或全部通过 Model 路线。

## 当前讨论入口

先确认 Prompt 权威链和 XML 覆盖白名单；随后逐 section 审核候选字段。每个保留字段都必须能追溯到一个已经确认的运行行为，不能因为旧模板已有或其他 Agent 有类似选项就保留。
