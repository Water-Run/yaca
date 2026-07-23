# 从负责人答复到可实施规格的收口协议

更新日期：2026-07-22

状态：归档工作流；现行问卷已收口，仅在负责人明确重开决定时复用

## 解决的问题

项目负责人真正需要做的是选择产品保证、体验取舍和可接受风险，不是逐个替开发者填写字段或猜 Windows API。但一次答复可能同时修改 Prompt、AgentLoop、TUI、XML 和测试；“整包接受推荐”也可能包含一条例外。若没有固定收口流程，答完上百个问题后仍可能出现：

- 同一句回复被不同文档解释成不同意思；
- 新回复与早期决定冲突，却没有明确谁取代谁；
- 推荐被误写成已确认；
- 一个产品选择没有展开成状态、错误、恢复和测试；
- 技术可行性未证明，却因为负责人选了 A 就被视为完成；
- 子系统实现时仍出现“任选一种”“以后再看”的空白。

本文定义收到答复后的确定处理流程。它是设计阶段的变更控制，不要求项目负责人使用机器格式，也不开始编码。

逐组现行状态统一登记在 [`DECISION-REGISTER.md`](DECISION-REGISTER.md)。决策包拥有选项正文，本协议拥有处理规则，登记表拥有 live state；三者不能互相替代。

## 一个问题进入负责人问卷前的质量门

负责人不负责从伪方案中猜哪一条其实能实现。每个正式 group 在进入路线图前必须同时满足：

1. **一个编号对应一个独立 owner 轴**：回复该编号后，不能还遗留“另请一并确认”“可单独回复”但没有编号的产品选择；真正独立的子轴必须升格为正式编号。
2. **选项互斥且回答同一个问题**：A/B/C 不能分别回答协议范围、页面风格和实现库，也不能让两个选项实际产生同一行为。
3. **所有可选项都在现行决定内合法**：已经确认不做 sandbox、扩展、永久 ContextId、独立长期日志或多 renderer 后，违反这些边界的旧方案只能放在“已排除背景”，不能继续作为可回复选项。若确实要修订决定，应另建明确的 re-open 请求并说明会取代哪条 D，而不是偷偷夹在普通组中。
4. **不能让负责人投票改变技术事实**：一个 API 在 XP 是否存在、XML 能否原地追加、文件系统是否具备掉电原子性、schema 是否完整，都由规格审计和技术证明回答。负责人只选择用户保证及证明失败时可接受的退路。
5. **跨组只有一个 owner**：stdin、header/body、hash/SBOM、retry、删除承诺等轴不能在两组重复选择。consumer 组引用 owner 的结果，不复制另一套 A/B/C。
6. **推荐本身可实施且有失败边界**：不得推荐“自动拆任意 raw shell 但保持完全等价”“所有可写文件系统同样可靠”或“隐藏推理完整导出”等无法验证的承诺。

问题质量门不要求所有方案都保守；可以比较不同费用、隐私、兼容和体验取舍。但每条都必须是项目在已确认边界内真正愿意实现、也能够通过证据门证明的路线。

## 项目负责人怎样回复最省力

每个决策包使用自己的组编号。下列写法都有效：

```text
TU-01 A。
TU-03 接受推荐，但 cooked 模式不显示伪 draft。
AL06-07 暂缓；先解释 reviewer 失败时人工 bypass 的风险。
CX-01 先采用 A；只有目标机 benchmark 不通过才回来讨论 B。
本包其余全部接受推荐。
```

也可以只描述想要的体验，不必强行选字母：

```text
审批时 Enter 一律不通过；必须输入明确动作。
旁问必须立即给回复，但不能看到尚未持久化的主模型流。
```

收口时会把自然语言映射到最接近的方案，并把任何差异原样记录。若一句话可能映射到两个不兼容行为，只针对该歧义继续解释，不要求整包重答。

`DECISION-BATCH-QUEUE.md` 中的 49 个批次现为历史收口证据；现行 270 组已经全部得到负责人答复。未来只有负责人明确重开某条决定或新增产品轴时，才按最小差异重新组批，不能把冻结问题包重新当作待答问卷。

“本包其余全部接受推荐”必须绑定收到回复时的 inventory version/digest。先应用同批显式上游选择/例外并重算条件，再展开到此时 active 的其余组；跨包上游仍未决的条件组保持 `unanswered`，条件不成立的组记 `not-applicable`，后来新增的组仍是 `unanswered`。显式提前字母作为 pre-answer 保留，只有上游使其 active 时才成为有效选择。

## 每组决策的唯一状态

| 状态 | 含义 | 能否进入正式规格 |
| --- | --- | --- |
| `unanswered` | 尚无明确负责人答复 | 否 |
| `explaining` | 负责人要求继续讲解或比较 | 否 |
| `selected` | 明确选择一套方案或接受推荐 | 可以进入展开，但仍受依赖/证明门约束 |
| `selected-with-exception` | 选择总体方案并明确改动部分行为 | 可以；例外必须先展开并检查冲突 |
| `deferred` | 明确暂缓且不影响当前目标 | 只有被正式移出 v0.1 或有安全默认时可以 |
| `excluded` | 明确不属于 v0.1 | 可以；规范中写清非目标和未来恢复条件 |
| `not-applicable` | 上游已选路线使一个条件 group 在当前有效组合中不成立；即使预先回答过字母也不生成运行行为、配置字段、XML 项或测试分支 | 可以；规格必须写明触发它的上游条件与“无投影”证据，依赖路线改变时重新计算 |
| `technical-proof` | 产品保证已定，具体实现由证据选择 | 只有证明计划和失败退路已冻结后可以 |
| `superseded` | 被后来的明确决定取代 | 否；保留历史链接，不再作为现行依据 |
| `conflict` | 两条现行负责人答复无法同时成立 | 否；必须返回最小冲突给负责人 |

“推荐”“当前领先”“候选”“最合适”本身都不是 `selected`。只有负责人明确表达接受、选择或等价自然语言，才改变状态。`N/A`、`dormant` 等自由拼写不另建状态；条件分支统一归档为 `not-applicable`，以免被误读成 deferred 或仍会生成空壳字段。

## 一次答复的七步归档

### 0. 锁定 inventory 与登记事务

处理原话前先记录 [`DECISION-REGISTER.md`](DECISION-REGISTER.md) 的 inventory version、structural/semantic digest、当前 Git HEAD 和本批显式/隐式作用域。当前基线是 `decision-inventory-v9` 的 270 个正式 group；semantic digest 覆盖完整正式问题 section、推荐、条件和所属包。v9 在 v8 基础上又拆出六个不能由相邻主题代答的 owner：M05-57 资源 selector/简称、M05-58 per-Model retry 配置面、M05-59 过短配置秘密政策、AL06-50 stuck 阈值来源、AL06-51 特殊 purpose 跨 Endpoint 同意寿命和 TS-40 reserved tree 精确读取。若正文、正式组集合或推荐在答复期间发生变化，不能把新版本混进旧“其余接受推荐”。先按旧 inventory payload 展开，再另行说明新增或修订项。

登记表的状态、原话证据、决定/规格/gate 引用必须作为一个文档事务更新。允许分阶段传播，但必须明确区分“回复已捕获”与“规格传播完成”，不能只改 `DECISIONS.md` 后依赖记忆补其余文档。

### 1. 保留原话

把负责人原始回复按批次保存在 `DISCUSSION-BATCH-NN.md`，使用登记表定义的固定头，记录日期、所答包、inventory version/digest、回复前 Git HEAD 和上下文；同时保存显式 ID、blanket 实际展开 ID、inactive ID 与条件未决 ID。登记表逐组只引用稳定 reply/assertion ID，不引用行号。不得只保存技术侧的转述；转述可能漏掉“除外”“以后”“仅当”等限制词。

### 2. 原子化

把一句复合答复拆为最小断言：

```text
原话：DoubleCheck 开启时检查动作和结束，但 reviewer 失败可以让我单次继续。

断言 1：DoubleCheck=true 包含 action review。
断言 2：DoubleCheck=true 包含 termination review。
断言 3：reviewer 失败不自动通过。
断言 4：用户可对精确失败项 override once。
```

每条断言分别标注：产品行为、体验文案、安全取舍、技术目标或精确常量。这样才能识别其中只有哪一部分需要技术证明。

完成原子化后立即更新登记表的 `State`、`Selection` 和 `Reply`。自然语言例外进入稀疏 assertion 记录，不把长转述塞回 270 行主表。

### 3. 对照现行决定

检查 `DECISIONS.md`：

- 完全一致：在现有决定下增加来源，不重复创建含义相同的决定。
- 细化而不冲突：创建子条目或扩展边界，并链接原决定。
- 明确修订：旧决定标记“被 D-xxx 取代/部分取代”，新决定说明差异。
- 可能冲突：不替负责人猜“新话一定覆盖旧话”，列出最小行为差异请其确认。

优先级不是简单的“最新日期赢”。必须能证明新回复确实在修订同一主题，而不是回答另一个范围。

每次新增、复用、取代或冲突都建立或更新 `PR`，并由登记表 `Projection` 引用；现有 D-001..D-057 不复制进登记表，只建立引用。

### 4. 传播影响

每条断言至少检查以下投影：

| 投影 | 要问什么 |
| --- | --- |
| 产品旅程 | 用户在哪个入口、状态和失败下看见它？ |
| Prompt/Model | 哪种 request purpose、view 和 schema 受影响？ |
| AgentLoop | 哪个事件、状态、transition、预算或 terminal outcome 改变？ |
| Tool/Safety | 是否改变参数验证、能力、审批、operation 或副作用保证？ |
| Config | 字段、默认、来源、覆盖、生效点和迁移怎样变化？ |
| Context XML | 哪条事实、snapshot、ID、durable 点和恢复行为变化？ |
| CLI/TUI | 命令、页面、按键后备、文案和非 TTY 行为怎样变化？ |
| Platform | XP/CentOS 是否有能力差异或需要 native port？ |
| Test/Release | 哪个 fixture、fault、golden trace 和目标证据证明它？ |

若一项决定只写进其中一个文档，却明显影响其他行，状态只能是“传播未完成”，不能标记规格完成。

### 5. 展开成权威规格

负责人决定回答“要什么”；子系统规格必须继续机械展开为：

1. 职责与非目标；
2. 输入、输出和依赖；
3. 类型、枚举、ID 与 schema；
4. 正常状态/流程；
5. 取消、超时、部分成功、unknown、崩溃和恢复；
6. 安全、秘密、权限与资源上限；
7. 旧 Windows/Linux 能力和诚实降级；
8. 配置/CLI/TUI 投影；
9. 可执行验收和证据。

最终权威只在一个 owner 子系统定义。其他子系统使用引用和投影，禁止复制一个略有差别的第二份枚举或默认值。

### 6. 重新过 readiness gate

逐项更新 [架构实施就绪门](ARCHITECTURE-READINESS.md)：

- `O` gate：负责人选择是否已明确且无冲突；
- `T` gate：规格/原型/目标证据是否已完成；
- `J` gate：负责人先定保证，技术侧是否证明可兑现，失败退路是否会改变保证。

题目全部答完不自动通过 `T/J`。相反，一项技术证明通过也不能替负责人选择产品行为。

## 依赖顺序与重新打开规则

### 上游先于下游

建议按以下顺序解释和收口：

```text
产品旅程和非目标
  -> Prompt/人格和界面语言
  -> Model/配置/网络能力
  -> AgentLoop 控制与预算
  -> Tool/安全/改动保证
  -> Context/压缩/恢复
  -> 错误/兼容/发布体验
  -> 测试证据和实施冻结
```

可以跳包回答，但下游只能标记“有负责人输入，等待上游一致性”，不能借机替未答上游做默认决定。

### 能在决策阶段判定的静态约束

有些组合不是“等运行时看看”的配置错误，而是所选 carrier 根本无法表达另一组选中的字段。收口器必须在传播 selection 时立即套用静态约束；不相容答复进入 `conflict`，不能同时标成 selected，也不能靠隐藏字段、配置降级或某个 Model 的特殊 parser 偷偷修正。

当前必须机械执行的一条约束是：`TS-23 B` 或 `TS-23 C` 一旦生效，`exec` 没有 typed per-call field carrier，因此同时强制 `TS-37 B`、`F4-07 A`，并从 tool schema、parser、help、approval、Context 投影和测试中完全移除 per-call `cwd`、`stdin_text` 与 deadline override。M05-51 选择的全局/Exec-profile deadline 仍可在 call admission 前冻结为 effective limit，但不能伪装成模型逐调用 override。若负责人同时选择 TS-23 B/C 与 TS-37 A/C、F4-07 B 或任何逐调用 deadline 行为，必须报告这一最小冲突；只有重新选择 TS-23 A，或放弃对应逐调用行为，才能收口。

### 哪些情况必须重新打开已经回答的组

- 新决定改变其前提，例如允许 WAL 改变“单 XML 唯一活动事实”的含义；
- 技术证明失败，所有替代都会改变用户保证；
- 新发现的安全绕过使原方案无法兑现；
- 两个包的例外产生不可同时满足的状态；
- 项目负责人明确修订旧决定；
- v0.1 范围增加此前排除的功能。

重新打开只问受影响部分，保留其他已确认断言，不让负责人机械重答整个包。

## 默认值怎样处理

项目负责人经常会说“采用最合适的”。收口规则如下：

1. 如果该项是纯技术选择且不改变产品承诺，技术侧提出候选、证据和选择理由，负责人不必再选。
2. 如果推荐会改变安全、费用、隐私、数据寿命、兼容或明显体验，必须明确得到接受。
3. 如果负责人确认总体原则但未给精确数字，先冻结语义、测量方法和失败方式；数字由最低目标机 benchmark 提案，再回看是否影响体验。
4. 安全关键缺省在待决期间不得“先按方便实现”；只能使用文档明确的 fail-closed 临时候选，且不进入发布承诺。
5. 配置 schema 中写出的候选默认，不等于正式默认。

## 例外、暂缓与非目标

### 暂缓不等于可以遗漏

一项被 `deferred` 后必须明确：

- 是否仍在 v0.1；
- 谁/什么证据触发重新讨论；
- 在此之前 Runtime 的安全行为；
- 是否阻塞某个 readiness gate。

如果没有这些信息，“以后再说”仍是未决。

### 排除也要写契约

例如 v0.1 不提供 Web、MCP、分支、自动 undo 或后台 detached process 时，相关规范仍要写：

- CLI/TUI 不宣传也不留下半成品命令；
- 配置中没有无消费者字段；
- Context schema 不冻结伪扩展对象；
- 遇到相应输入时是明确 unsupported，而不是随机忽略；
- 未来加入时重新走哪些安全/迁移门。

## 冲突报告的固定形式

发现冲突时只向负责人展示最小可感知差异：

```text
冲突 CR-xxx

已确认 A：配置损坏时 yaca 无法启动。
新要求 B：self-test 必须能诊断损坏配置。

真正需要决定的是：
A. “无法启动”仅指主 Agent；self-test/config-repl 使用内置最小 schema。
B. 所有入口都拒绝，只由外部文本错误说明修复。

推荐 A，因为它不让损坏配置启动 Agent，也保留被要求的诊断能力。
影响：产品启动表、config-repl、self-test、CLI exit class。
```

不把十几个受影响字段一次倾倒给负责人，也不以“实现方便”掩盖产品差异。

## 决定、规格和测试的最小追踪记录

每条正式追踪至少包含：

| 字段 | 含义 |
| --- | --- |
| Requirement | `PROD/LOOP/...` 或新需求 ID |
| Owner reply | 原始答复位置与日期 |
| Decision | `D-xxx` 现行结论 |
| Owner subsystem | 唯一定义该契约的子系统 |
| Spec anchor | 状态表/schema/矩阵中的唯一锚点 |
| Failure contract | 取消、超时、部分成功、unknown、恢复 |
| Test | 单元/契约/golden/fault/soak/平台场景 ID |
| Evidence target | 哪个最终平台/zip/模型组合必须提供证据 |
| Status | 待答/已决/规格化/已验证/被取代 |

登记表还必须保留 `group_id`、`inventory version`、`group_state`、`selection/assertion refs`、`reply_ref`、`active_when` 与 `supersedes/conflict/reopen refs`。这些是答复来源和条件生命周期，不应被上面的 requirement→evidence 记录吞并。

双向规则：从 requirement 能找到证据，从失败的 evidence 也能反查是哪条保证和决定受影响。

## 一个答复批次完成的判定

只有同时满足以下条件，才把该批次标为已收口：

- 每个明确回复都保留原话并原子化；
- 登记表绑定正确 inventory，逐组状态、选择、条件和原话引用已更新；
- reply batch 保存 blanket 实际展开的精确 ID 集合，不只保存“其余接受推荐”原句；
- 未回复项仍明确是 `unanswered`，没有因“整包大体接受”被吞掉；
- “其余接受推荐”只展开 active 组；条件假项为 `not-applicable` 且没有字段/页面/XML/test 空壳；
- `DECISIONS.md` 没有两条同时现行的冲突结论；
- 所有影响 owner/consumer 已登记；
- 每个非 unanswered 组都有 typed PR；产生现行行为的组的 owner spec 恰好一个，讲解/暂缓/N/A/取代/冲突按登记表 state×PR 矩阵使用唯一 typed sentinel；consumer/gate/test 为真实引用或带原因的 pending/n/a/conflict sentinel；
- 候选文档没有把旧推荐继续写成现行方向而不标状态；
- 需要负责人决定与需要技术证明的部分已拆开；
- 对应 P0/P1 gate 状态和原因已更新；
- 文档链接、编号、枚举和术语校验通过；
- 决策包正式组集合、推荐模板集合与登记表集合完全相等；
- 没有开始实现代码。

## 全部答复后的最终输出

完成所有负责人决策后，设计阶段还必须产出下列无候选分支的权威工件：

1. 产品支持/非目标与端到端生命周期契约；
2. Prompt stack、request purpose 与数据可见性契约；
3. Model/provider canonical wire/event/error 契约；
4. AgentLoop 状态机、typed outcome、预算与 command × state 表；
5. tool registry、tool × capability、operation 和改动证据契约；
6. typed config/INI/override/migration schema；
7. Context XML/path/hash/resolver/commit/recovery/compaction 规格；
8. CLI/TUI 页面、输入、错误与兼容降级 golden 契约；
9. platform/process/network/terminal/native port ABI；
10. 技术证明、测试、发布 manifest 与目标证据矩阵。

只有这些工件中所有 P0 无“任选、候选、以后决定、实现时再看”，并且 [技术证明债务表](TECHNICAL-PROOF-BACKLOG.md) 为高风险底层能力给出可执行 stop gate，才进入逐子系统 implementation planning。
