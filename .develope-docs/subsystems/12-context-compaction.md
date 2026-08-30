# 12 上下文压缩

更新日期：2026-08-30

状态：**手工、自动、durable recovery core 与同 workspace `--continue` 完成，其余 controller 和目标校准待闭合** — model-view/summary/atomic-group/admission、no-tool Model port、Context journal、原子 publication、accepted/pending-view 恢复、公开 `.compact`、每次 main/review 请求前 automatic preflight、STATUS/cancel、Runtime receipt gate、跨进程 failure circuit 和 exact reopen 已实现；`.context`/select-context、跨 workspace 显式确认/rebind 与 target calibration 尚待闭合

> D-063：XML **存储** hard limit 触顶时的解脱主路径是 **新开对话 + 接盘 Prompt**，不是依赖 compact 缩小事实 XML。compact 仍只服务 model view。

## 职责

在下一次模型视图接近当前 Model 窗口时，生成可追踪的结构化摘要，保留关键目标、决定、文件状态、验证证据、未知副作用、未完成工作和最近完整事件组，并支持用户查看和纠正摘要。

## 边界

- token 预算来自当前冻结的完整 Model 配置与估算器。
- 摘要生成通过 06、09 号系统，不直接发送 HTTP。
- 原始上下文的保存和模型视图 manifest 由 10 号系统完成。
- 活动 XML 始终保存完整 canonical 事实；压缩只改变下一次发给模型的派生 view，不能删除或改写被摘要覆盖的对话、工具、审批、Prompt 或 Model transition。
- 压缩不是另一个会话、分支或长期事实源。

## 已确认算法

下一次 Model view 使用一个简洁、确定性的组合：

```text
不可压缩的有效 Prompt + tool/control schema
+ 最新有效的结构化 prefix summary（需要时）
+ 从新到旧选择、仍能完整容纳的 atomic event groups
+ 当前状态、unknown side effects 与未完成事项
```

不实现多层摘要树。每一代只发布一个能够替代更老前缀的结构化 summary；旧 summary、生成请求和事实事件仍留在 XML 中供审计和重建。

不可拆 atomic group 至少包括：tool call/result、operation/approval/result、用户输入/对应直接回复、完整 Model message、当前 active turn 和一次已收口的 review。单个 atomic group 本身超过窗口时立即停止并提示换用更大窗口 Model、缩小当前输入或新建 Context；不能截成半条调用、半个结果或不完整 assistant message。

## 结构化摘要的最低内容

每份 summary 必须有独立字段，而不是一段无法验证的自由散文：

- 当前目标与负责人/用户已经确认的决定；
- 约束、Permission/workspace 边界和必须继续遵守的要求；
- 已读取、创建、修改、重命名或删除的文件事实；
- 已执行验证、真实结果、失败尝试和未验证事项；
- 已发生或 outcome=unknown 的副作用；
- 仍待完成、等待用户或可能卡住的事项；
- Global/Model/Permission/Context Prompt transition；
- 旧 Model、当前 Model、切换原因和对应事件边界。

summary 同时保存 source event range/digest、生成 Model、完整 Prompt/view manifest、算法/schema 版本和压缩代次。用户纠正产生新的 superseding fact 和后续 summary，不回写旧事件或假装旧摘要从未存在。

## 摘要请求

- 默认使用当前 turn 冻结的 Model 生成摘要，不自动换 provider 或选择所谓廉价 Model。
- `compaction` 是独立 request purpose，没有工具权限，具有独立 ID、usage、取消和不可关闭 hard cap。
- 按 18 号 Prompt 契约继承 Global 与当前 Model SystemPrompt，并加入固定 summary schema；Permission/SystemPrompt、ContextPrompt、历史 Prompt 和对话内容只作为有界 quoted data，不继承其指令权威。
- 只有 schema、source range、digest 和必填槽位全部验证通过，且新 view 确实低于安全阈值时，才能原子发布新 manifest。
- 失败、取消、无效 schema、连续无收益或仍超限时保留旧 view，不破坏 XML，也不递归计费直到成功。

### 自动压缩用户可见性（D-067 / SQ-10 = A）

- 自动 compaction：**STATUS 可见**（开始/结束结果；必要时建议换更大 Model），**不** 默认弹确认框。  
- **禁止** 成功完全静默。  
- 可 cancel；失败保留旧 view 并诚实报告。  
- 不解除 XML hard limit；不删事实史。

## 窗口推荐与 Model 切换

安全余量由 Runtime 按当前有效 Model、最大输出、四层 Prompt、tool/control schema、不可拆 group 和估算误差实时计算；它是只读 effective value，不生成自由 `CompactReserveTokens` INI/XML 字段。用户可以在安全范围内收紧触发阈值，但不能关闭 request/turn/process 硬上限。

需要压缩或已经超限时，若当前配置中存在窗口更大的 enabled Model，先给出明确推荐，不自动切换：

1. 先推荐历史中曾用于该 Context、当前仍有效且足以容纳 view 的较大窗口 Model；
2. 再列其他足够大的已启用 Model；
3. 切换前照常进行 endpoint 隐私、费用、tool/control capability preflight；
4. 用户确认切换后，从完整 XML 事实重建新 Model 能容纳的最佳 view，并把旧/新 Model、Prompt 与窗口 transition 明确送入请求。

切回较大窗口后可以重新纳入更多原文；旧 summary 仍是历史事实，但不要求继续作为 active prefix。

## 正确性与恢复不变量

1. summary 永远是派生 view，不是 canonical 对话的替代事实。
2. 工具、审批、操作和 Model/Prompt transition 不得拆分或静默丢失。
3. 发布前先 durable 保存 compaction request/result/manifest；提交失败时旧 view 仍保持有效。
4. 恢复时只有来源范围完整、digest 一致、schema/算法兼容的 summary 才可复用；否则从完整 XML 重建。
5. 压缩 request、provider retry、主 turn 和进程预算分别计数并共同受硬上限约束。
6. TUI 的预览截断不能回流成 summary 输入或 XML canonical 内容。

### 2026-08-30 实现证据

- Context journal 已覆盖 request、response、rejection、cancel request/result、accepted publication 与 correction；每条记录都绑定当前 Context generation、旧 manifest、source range/digest 和 compaction lifecycle。
- canonical source、structured summary 和 manifest 由 publication 端独立重建并校验，不能信任上游自报的 `canonical_bytes`/digest。
- accepted terminal event、`CompactionRecord` 与 `model_view_published` 必须在同一 replacement generation 内匹配；错误、取消、伪造 manifest 或发布故障均保留原 XML 与 sole active manifest。
- cache miss/重启读取 accepted bracket 时会复核 source/summary digest、相邻 publication 和 active manifest，再重建唯一 summary prefix；后续事实作为 tail 追加，内部 compaction bracket 不进入 main Model view。
- production owner 已把当前 generation 的 no-tool compaction Model、Context journal 与 Runtime external-receipt gate 组合起来；每次 durable record 都先由 Runtime 采纳精确 sequence/generation/manifest 水位，才能继续 lifecycle。
- Runtime 对 compaction 使用独占 lane 和 `opened -> request -> response|retry|cancelling -> published|terminal` 相位；普通 main、普通 cancel 和 close 不能越过该 owner。只有同一 `compaction_id` 的 accepted publication 能结算 `completed`，乱序 publication 或含混 journal receipt 一律 fail-stop。
- Runtime 在每个 main、action-review 与 termination-review Model admission 前冻结唯一待发请求；automatic compaction gate 绑定 preflight ID 与当时 Context 水位，只有 exact settlement 可恢复原请求，替换 settlement 或失败结果不能泄漏 Model effect。
- ApplicationCoordinator 已执行 `.compact` 与 automatic preflight，在 STATUS 显示 state/circuit/preflight，自动压缩开始/重试/终态均可见；活动期间只放行 status/help/cancel，退出先收口 compaction，再关闭 Agent session 和唯一 Context writer。
- bound `model_request` 现持久化 compaction/mode/attempt、source range/count/digest、Config/Model/Prompt/manifest snapshot 与 view generation；terminal 同时持久化 request/attempt/mode/automatic-failure，Runtime 和 Context relation scanner 都要求完整精确匹配。旧式无 binding 请求仍可读，但 partial binding 一律拒绝。
- existing Context open core 在向新 Runtime 暴露 writer 前恢复所有未闭合 lifecycle：request-only、response-only、cancel-pending 与 nonterminal-rejection 都归并为唯一 cancel pending/unknown 和 terminal error，保留旧 view且不重放 Model 请求；旧格式 pending 只追加 cancel unknown，不伪造无法证明的 CompactionRecord。
- compaction serial 与连续 automatic failure streak 从 canonical XML 重建；automatic process-recovery unknown 计入 streak，旧终态缺少 circuit 语义时按 history-incomplete 保守开路。进程间不能比较 monotonic timestamp，因此恢复到阈值的 circuit 从首个本地单调时钟读数重新等待完整 cooldown，再允许一次 half-open probe。
- `--continue` 只接受 exact resolved/reverified target，在同一 recorded workspace identity 下取得 writer；未完成 turn、active queue、未决 Tool/operation、unknown outcome 或 pending compaction 会阻断自动继续。quiescent Context 以 Idle Runtime 恢复 event/config/active manifest 与八类 canonical ID 水位，不自动执行或重放任何历史请求。
- production composition 测试使用真实 `compact` service 跑通手工/自动触发、摘要 Model response、response receipt、原子 publication、Runtime terminal settlement 和待发请求恢复，并注入 journal rejection 证明 lane 不会被错误释放。
- 受 `.tools/run_with_resource_guard.sh` 保护的完整 Lua suite 为 `418/418`，其中包含手工/自动的五个跨实例 crash bracket、旧格式 pending、serial 不重用、process-recovery failure 传递、recovered-circuit cooldown 和同 workspace exact reopen。它只证明平台无关 core 与 fake/native adapter 边界，不能替代跨 workspace recovery controller 或 XP/Win7/CentOS 7 target 证据。

## 仍需技术证明

冻结各 adapter 的 token 估算误差与安全余量、触发阈值、summary 字段编码和字节上限，并用长对话、大工具结果、反复 Model/Prompt 切换、摘要失败和单 group 超窗 fixture 验证。产品路线不再比较 extractive-only、丢弃旧历史或摘要树。

---

## W3-D：Model-view 与 Compaction schema（规范）

对齐：D-051、D-063、D-067、D-068；AR-P0-12；事实 XML 见 [10](10-context-storage.md)。

### ModelViewManifest（派生，可重建）

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 整数；不兼容则丢弃派生、从 XML 重建 |
| `context_generation` / `xml_digest` | 绑定事实代 |
| `model_id` / `window_tokens` | 冻结 Model 快照 |
| `prompt_bundle_digest` | 四层 Prompt + tool/control schema |
| `summary_id` | 当前 active prefix summary，或 null |
| `included_event_range` | 完整 atomic groups 的 event id 闭区间列表（有界编码） |
| `excluded_prefix_reason` | `none` / `summarized` / `budget` |
| `builder_algorithm` | 版本化算法 id |
| `estimated_tokens` | 估算；标 `estimated` 非计费 |

**不变量**：同一 XML digest + 同一 Model + 同一 algorithm → 确定性相同 manifest（允许 token 估算实现误差带，但 group 边界必须稳定）。

### StructuredSummary 记录（XML 内事件，非删除事实）

| 字段 | 必填 |
| --- | --- |
| `summary_id` | yes |
| `source_range` + `source_digest` | yes |
| `goals_decisions` | yes（结构化槽，非纯散文） |
| `constraints_permissions` | yes |
| `files_touched` | yes（path + op 类） |
| `verification_evidence` | yes |
| `unknown_side_effects` | yes |
| `open_todos` | yes |
| `prompt_model_transitions` | yes |
| `generator_model` / `usage` | yes |
| `schema_version` | yes |

用户纠正 → **新** summary 事件 supersede；不回写旧 summary 字节。

### Atomic group（不可拆）

| 组类型 | 成员必须同进同出 |
| --- | --- |
| tool_pair | call + result（或 unknown） |
| operation_pair | intent + approval? + result |
| user_turn | user message + 直接 assistant 段 |
| review_cycle | review request + verdict |
| active_turn | 当前未完成 turn 全部 |

单 group 超窗 → **停止**；提示更大窗口 Model / 缩小输入 / 新 Context（D-063 存储触顶另论）。

### Admission：自动 vs 手动 `.compact`

| | 自动 | 手动 |
| --- | --- | --- |
| 触发 | 下一次 view 估超安全阈值 | 用户 `.compact` |
| 可见性 | STATUS 开始/结束（D-067）；禁完全静默 | STATUS + 结果 |
| 确认框 | 默认无 | 默认无 |
| cancel | 可 | 可 |
| 失败 | 保留旧 view | 同左 |
| 费用 | 独立 purpose 计数 | 同左 |
| XML hard limit | **不** 解除（D-063） | **不** 解除 |

### 发布事务

```text
1. durable compaction request
2. model result validate (schema + slots + digest)
3. build candidate manifest; verify under threshold
4. atomic publish summary event + new manifest
5. failure anywhere → old manifest remains sole active
```

### 备选否决

| 方案 | 否决 |
| --- | --- |
| 删除旧 XML 事实 | D-051/068 |
| 多层摘要树 | 复杂度 |
| 静默自动换廉价 Model | 已否 |

### 完成度（W3-D compact）

- [x] Manifest / Summary / atomic group / admission 表  
- [x] no-tool Model compaction builder/port 与完整性拒绝
- [x] Context compaction journal、accepted summary + ModelView 原子 publication
- [x] accepted view 的 XML 校验、cache-miss 重建与后续 tail 保留
- [x] ApplicationCoordinator `.compact`、STATUS/cancel 与 production transport composition
- [x] 每次 main/review Model request 前的自动阈值 preflight、可见 STATUS 与精确恢复/阻断
- [x] pending lifecycle/circuit 跨进程恢复 core与同 workspace `--continue` exact reopen
- [ ] `.context`/select-context 与跨 workspace 显式确认/rebind controller
- [ ] token 估算与三目标阈值数值（TP/C32）
