# 负责人答复原话归档：正式决策批次 04

received_at:             `2026-07-22T14:08:52+08:00`
source:                  当前项目会话；负责人把 packet 02 全文贴回并在相关位置加入批注
inventory_version:       `decision-inventory-v9`
structural_sha256:       `22e724986251bd63ae75e1c7964b3a2f6d3412a4e0f9b01019662790d68df6ef`
semantic_sha256:         `80efc73d45ed32e05ea991f35a8cc484700a276f6664c77bc339c7957648b044`
inventory_git_commit:    `233f5f613dd6afd1167243dfae1de4ea691c96d9`
packet_base_sha256:      `afb055438142fd9e3ce2d4864feac34f8ac89f3944483f5f0aaa93926721b295`；负责人所贴 packet 02 的无批注基线
annotation_verbatim_ids: `RB-004-01..RB-004-11`
explicit_group_ids:      `PJ-01`, `PJ-04`, `PJ-09`, `PJ-12`, `PJ-13`, `TU-32`, `CX-13`, `F4-01`
blanket_scope:           none
expanded_active_ids:     none
inactive_ids:            none
unresolved_condition_ids: none
unanswered_ids:          none
open_followups:          `Permission` 完整矩阵继续进入安全设计流；`DoubleCheck` 的“目标”究竟是 reviewer Model、复核范围还是任务目标，等待 AgentLoop 批次精确询问
assertion_ids:           `AS-004-01..AS-004-10`

## 归档边界

负责人本次贴回了 packet 02 的完整正文。未加批注的正文只是定位上下文，已经由 `packet_base_sha256` 对应的仓库版本保存，不在这里复制第二份。下面逐字保存全部新增批注和批注中的相邻列表；它们才是本批的新负责人原话。贴回正文中仍写着“PJ-18 尚未回答”等旧状态，不构成撤销 D-045/D-046，因为负责人随后已经明确完成那两项补答，本批也写了“已经提供”。

## RB-004-01：完成本轮文档批注

```text
我已经完成你的编辑
```

## RB-004-02：启动头没有总开关

```text
不需要总开关
```

## RB-004-03：`.model` 的两种等价交互

```text
注意yaca输入.
.model 上下选择模型(TUI注意控制展示, 挤占处理等)
和比如 .model Deepseek
都是等价的
.model Deepseek
最好有补全提示
```

## RB-004-04：self-test 覆盖 Context 缺失与索引性能

```text
self-test注意完整. 比如, context对应目录已移除, context太多hash计算太久之类的
```

## RB-004-05：继续深入设计 Permission

```text
合理的思考设计Permission
```

## RB-004-06：Stage 3 Permission advisory 与 CLI 等价面

```text
self-test的第三阶段包括Permission名称检查, 比如实际上是TrustMeBro的"Readonly". 还包括拼写错误等提示
一切TUI操作可使用CLI
```

## RB-004-07：Context 列表排序配置

```text
文件系统最近时间排序选择. 可定义于配置

- 创建时间
- 更新时间
- 字母表顺序

以及开关

- 正序
- 倒序

默认: 更新时间倒序(最近更新在前)
```

## RB-004-08：初始名称与后续覆盖重申

```text
第一次持久化就是"未命名的上下文[4位同目录唯一性确保哈希]"啊
后面自动命名还是手动命名可以覆盖
```

## RB-004-09：不需要自动跳目录配置

```text
不需要这个配置了?
等于直接 yaca [对应目录], 毕竟yaca不再只能yaca .
```

## RB-004-10：Context 锁与逐 turn 配置载入

```text
占用锁. 锁的上下文不可编辑, 除非释放
模型和配置则可以修改. yaca每轮载入变更, 实时. 留意高性能的库
```

## RB-004-11：DoubleCheck 目标与补答状态

```text
DoubleCheck可以设定目标

已经提供
```

两句话原本位于不同位置：第一句批注在 PJ-11，第二句批注在 packet 的“当前仅剩补答”之后。这里只为减少无意义空节而共用一个 raw block，不把它们规范化成同一断言。

## 原子断言

### AS-004-01：启动头只有逐字段开关

- group_id: `PJ-01`
- normalized_assertion: 删除启动头 master。Slogan、version、work directory、data root、配置状态、Context、实时 hash、Model、Permission、DoubleCheck 和 `.status` 提示分别使用独立 bool；全关即可隐藏例行启动头。ERROR、WARNING、ACTION 与修复要求从来不受这些 display-only 字段控制。
- kind: product / experience / configuration
- supersedes: `AS-002-01` 中“总开关 + 逐字段开关”的总开关部分

### AS-004-02：`.model` picker 与直接 selector 是同一动作

- group_id: `TU-32`；细化 `PJ-09`
- normalized_assertion: chat 保留平坦 `.model` root。无参数 `.model` 打开有界、可降级的 Model picker；`.model <selector>` 直接提交同一 typed `select-model` action。两条路径使用同一 resolver、校验、next-turn 生效和 receipt。补全/候选提示只从当前 enabled Model registry 产生；窄屏或旧终端可以退化为逐行候选而不能改变选择结果。
- kind: product / experience / constant

### AS-004-03：self-test 必须覆盖 Context 地址健康与索引性能

- group_id: `PJ-02/PJ-03` 的 self-test 细化；不替代 M05 的阶段内失败策略选择
- normalized_assertion: Stage 1 的稳定检查清单必须包括 Context XML 镜像父目录能否解码、派生 workspace 是否存在且可进入、Catalog/Resolver/hash 扫描是否命中 hard cap 或超出目标旧机性能预算。大量 Context 导致扫描不完整或过慢必须形成带检查 ID、范围、耗时和下一步的确定性结果，不能报告健康或让 Stage 3 覆盖。
- kind: product / technical-target / compatibility

### AS-004-04：Stage 3 检查名称与实际配置是否合理

- group_id: self-test / Permission 设计细化
- normalized_assertion: Stage 3 的 LLM advisory 可以检查 Permission 名称、Description/SystemPrompt 与真实 capability matrix 是否明显错配，并提示拼写错误；例如宽能力 profile 却叫 `Readonly`，或只读矩阵却叫 `TrustMeBro`。它只给 advisory，不能改配置、不能由名称推导授权，也不能覆盖 Stage 1/2 的确定性结果。相同原则也用于 Model 名称与真实 remote model/endpoint 的明显错配。
- kind: product / experience / safety

### AS-004-05：每个 TUI 领域动作都有 CLI 投影

- group_id: CLI/TUI 跨系统不变量；精确顶层 grammar 仍由 `TU-18` 决定
- normalized_assertion: 任何能在 TUI 触发的领域动作都必须进入同一 command/action registry，并有可从 CLI 调用的等价投影。方向键、滚动、分页等纯 renderer 导航不是新的领域动作；交互确认在非 TTY 下仍服从后续能力/输入所有权决定，不能因“有 CLI”就默认批准。
- kind: product / architecture / compatibility

### AS-004-06：Context 列表默认按更新时间倒序

- group_id: `PJ-04` 的 Catalog 显示细化；不重新启用裸启动 Catalog 扫描，也不选择 `CX-19` landing
- normalized_assertion: Context 列表/浏览器提供保存于 INI 的两个 typed 默认：排序键 `created|updated|name`，方向 `ascending|descending`；默认 `updated + descending`。created/updated 取 Context canonical metadata，不取复制、替换或恢复时会漂移的文件 mtime；name 使用规范逻辑名称稳定排序，完全相同键始终用 canonical `LogicalPath` 升序 tie-break，绝不随主方向反转。该偏好只影响显示顺序，不参与 Resolver 优先级、hash 或 Context XML。
- kind: product / experience / configuration

### AS-004-07：`AutoJumpToDir` 保持删除

- group_id: `PJ-13`
- normalized_assertion: 不提供 `AutoJumpToDir`/`ResumeDirectory`。`yaca [directory]` 决定新入口/Resolver 起点；显式继续旧 Context 时，其唯一 workspace root 仍由该 XML 在 `__yaca__/CONTEXT` 镜像树中的父目录决定。若要改变绑定，必须由 context-repl 执行 D-045 的显式 rebind，而不是把 invocation directory 静默写成新绑定。
- kind: product / safety

### AS-004-08：活动 Context 在释放 writer 前不可由管理面编辑

- group_id: `CX-13`；细化 `PJ-09`
- normalized_assertion: Context 已被活动 writer 锁定时，其他进程的 context-repl/CLI 只可显示允许的 busy 元数据，不能 rename、rebind、删除、归档、恢复、修改 Prompt/metadata 或切换 `AutoRenameDisabled`。释放并重新取得新鲜 observation/lease 后才能编辑。活动 chat 的拥有者仍可通过已登记的会话 action 修改自己的 next-turn state；这不是第二 writer。
- kind: product / safety / concurrency

### AS-004-09：每个新 turn 自动观察并载入完整配置变化

- group_id: `F4-01`
- normalized_assertion: 每个新 turn admission 前读取完整 INI bytes 并计算 private source digest；未变化时复用已验证的 immutable `ConfigGeneration`，变化时整份 parse/cross-validate 后一次发布新 generation。有效的 Model/配置变更自动从该新 turn 生效，不再询问 reload；active turn、在途请求和已启动工具永不热换。观察到删除、半写或无效候选时阻止新 turn并进入修复；当前 Model/Permission 引用失效时明确要求 mapping/switch，不自动选第一项。配置文件很小，优先用一次有界顺序读和高性能 parser，不用不可靠 mtime watcher 或逐字段重读。
- kind: product / architecture / safety

### AS-004-10：Permission 与 DoubleCheck 仍需独立深入设计

- group_id: `Permission` / `DoubleCheck` 后续设计流
- normalized_assertion: 负责人要求继续深入设计 Permission；`DoubleCheck可以设定目标` 是必须保留的上游用语，但“目标”可能指 reviewer Model、动作/结束复核范围，或交给 reviewer 的任务目标。三者会生成不同 schema 和 AgentLoop，因此本批不猜成一个字段；在 AL06/Permission 对应问题中给出窄选项后再确认。
- kind: design-directive / open-followup

## 本批收口结果

- `PJ-01` 的现行例外改为“无 master、只有逐字段显示开关”。
- `TU-32` 明确选择平坦 root 路线 A，并细化 `.model` 的 picker/direct-selector 等价语义。
- `F4-01` 由自然语言明确选择 custom turn-boundary auto reload；它不等同于候选 B 的“发现后询问是否载入”。
- Context 列表新增两个简单 INI 偏好；它们不让裸启动扫描 recent，也不改变 Resolver。
- self-test 与 active Context 锁语义获得新的硬边界；Permission/DoubleCheck 的剩余轴继续进入后续决策流。
- D-041/D-045/D-046 没有被本批旧基线文字撤销；初始 ASCII fallback、单 root 与 `AutoRenameDisabled` 仍按 B03 现行决定。
