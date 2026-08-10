# 19 改动归属、审阅与不可撤销边界

更新日期：2026-08-10

状态：**W3-D 规格首版** — 无 undo 故障/fault 全表与 batch 语义已规范；`D-052` 零 backup/undo/rollback 表面

## 结论

v0.1 只承诺：安全 admission、expected raw-byte digest/identity、no-replace、单文件安全发布、operation/result 事实、改动归属、diff evidence 与诚实的 `unknown`。它不承诺自动 undo，不保存完整 preimage，不创建 checkpoint，不用 Git stash/commit 充当事务，也不把一组文件操作宣传成 ACID transaction。

本文件名保留 `undo` 是为了记录明确的产品边界和将来重开条件，不表示存在撤销功能。

## 职责

本系统只负责：

- 把 direct mutation 的 intent/result 与 session、turn、tool call、operation、目标身份和 config/Permission generation 关联起来。
- 从已保存的 old/new digest、规范文本和实际 postcondition 派生 Agent 可归属的 diff/review evidence。
- 区分启动前既有内容、Agent 已证明发布的结果、后续外部修改和无法判定的副作用。
- 描述串行多操作的 completed/failed/skipped/unknown 边界，供 TUI、结束报告、恢复和 self-fix 使用。
- 保证 unknown operation 不被自动重放，并允许用户以后追加有证据的解算结论。

本系统不负责：

- 保存可恢复原内容的 preimage、reverse patch、快照或影子工作区。
- 自动创建、管理、清理或恢复 `backup/`。
- 把 Git status/diff 做成专用 Runtime hook/tool，或自动执行 stash/commit/reset/checkout/revert/push 等 Git 工作流。
- 回滚 direct tool、raw shell、网络、进程、注册表、数据库、远端服务或其他外部副作用。
- 把 Context 历史“撤销”。历史永远保留真实 operation/result；后续人工修复只是新的事实和新动作。

## 与其他子系统的边界

- **07 工具系统**拥有 exact registry、typed schema、expected digest、no-replace、atomic/safe publish、rename/delete 和 `exec` 结果。本系统不重复实现文件工具。
- **08 Permission**决定动作是否允许；“有 diff”“用户说可恢复”或 Prompt 中出现 `backup/` 都不产生授权。
- **09 AgentLoop**决定 accepted batch 顺序并保证 call/result 配对；所有工具串行，首个失败后尚未开始的调用得到 `skipped`。
- **10 Context**持久化 intent、result、diff evidence 与 unknown 解算；它不因本系统创建 preimage attachment 或长期 sidecar。
- **01 文件系统**提供实际原语与身份复核；平台不能证明时必须返回 typed 降级/失败，不由本系统补成虚假事务。
- **02 进程系统**收口 raw `exec`；opaque command 的未知文件或外部副作用不能按 workspace diff 推断为完整。
- **Git**不是 Runtime 依赖或内部 adapter。模型可以通过普通获批 raw `exec` 使用只读 `git status`/`git diff` 作为证据；`commit`、`push`、`reset`、`stash` 等写入或工作流动作只有用户明确要求时才可调用。所有 Git command 都承担相同的宽副作用和 unknown 边界。

## v0.1 的事实模型

### Operation

每个会产生副作用的 direct tool call 或 `exec` 都有唯一 operation ID。operation 至少关联：

- session、turn、本地 tool call 与 provider call evidence；
- tool/schema/registry version 和 canonical accepted arguments；
- 规范 target/cwd、动作类别、effective config/Permission generation；
- 执行前 expected existence、ordinary-object identity、raw-byte digest，以及需要保留的 metadata snapshot；
- 对 direct mutation 可预先计算时的 candidate/postimage digest；
- durable intent、开始状态、真实或 synthetic result；
- `success|failed|denied|cancelled|timeout|partial|unknown|skipped` outcome；
- 实际 postcondition、old/new digest、diff 或无法产生 diff 的原因；
- `exec` 的 exit/capture/descendant 证据与仍可能存在的外部副作用。

operation record 是可审计事实，不是恢复副本。expected old digest 能防止覆盖 stale base，candidate digest 能帮助崩溃后判断发布是否发生；二者都不能还原原内容。

### Review group

v0.1 不建立有 commit/rollback 方法的 `change transaction` 对象。UI 和结束报告可以把 operation 按以下只读视图分组：

- 本 operation；
- 本 turn 中按执行顺序发生的 operations；
- 当前 Context 中由 yaca 有证据归属的净变化。

这些 group 只是派生 review view。多文件操作仍是一串独立、串行、各自收口的 operations；中途失败时先前成功项继续存在，后续项 `skipped`，不存在隐式 rollback。

## direct mutation 保证

`write`、`patch`、`rename` 和 `delete` 只消费 07 号系统冻结的简单语义：

- `write(create)` 使用 no-replace；`write(replace)` 和 `patch` 要求 expected ordinary-file identity 与 raw-byte digest。
- `patch` 全部 structured hunks 通过后才发布；任一 hunk 校验失败时正式文件零修改。
- replace/patch 使用同目录受控 temp、flush、验证和平台已证明的 safe/atomic publish；发布后重新打开验证。
- `rename` 永不覆盖、永不自动改名、永不把 cross-device copy+delete 冒充原子 rename。
- `delete` 只处理一个 ordinary file 或空目录，不递归、不进入 trash、不保存内容副本。
- direct mutation 不处理 binary，不接受任意文件属性修改；不能可靠保留/复核必要 metadata 时在副作用前拒绝。

“atomic”只描述技术证明覆盖的单文件发布临界点；不代表多个文件、一个 turn、一次模型回复或外部 command 具有全有或全无语义。

## 改动归属与 diff

归属以 operation evidence 为准，不以 Git HEAD、当前工作区脏状态或模型自述为准：

1. direct mutation intent 保存 expected identity/digest 和 candidate digest。
2. 发布后 result 保存实际 identity/digest、metadata 结果和 canonical diff。
3. 当前文件仍等于该 postimage 时，可以报告“这项 Agent 改动仍在”。
4. 当前文件后来变为另一 digest 时，报告“Agent 曾发布该 postimage，之后检测到外部变化”；不能把当前全部差异继续归给 Agent。
5. 启动前已经存在但未被该 operation 改变的脏内容不算 Agent 成果。
6. `exec` 只记录 command、cwd、进程输出和可观察结果。除非另一个 direct operation 提供证据，不扫描并宣称 opaque command 的全部文件副作用。

文本 diff 是审阅投影，不是事实源或恢复载荷。binary、超限、编码不支持、metadata-only 或 unknown 时，报告 digest/size/identity/范围与不能显示 diff 的原因；不能伪造文字 diff。

Git 不参与归属判定。模型可以通过 `exec` 运行只读 `git status`/`git diff` 并把输出作为普通 shell evidence；Runtime 不在模型调用之外自动运行 Git，也不把 Git 输出提升为比 operation/result 更高的事实权威。任何 Git 写入或工作流动作仍要求用户明确提出。

## Prompt 中的 `backup/`

`backup/` 只可能是某段用户自定义 Global、Model、Permission 或 Context Prompt 中的一句普通文字。它不是配置字段、模式、reserved directory、工具、自动动作、事务阶段、审阅事实或恢复保证。

如果模型受这段 Prompt 影响而提出创建副本，该调用仍只是普通 `write` 或 `exec`：目标、Permission、审批、expected digest、结果和失败处理完全与其他调用相同。Runtime 不自动创建目录、不选择文件、不验证备份完整性、不清理、不还原，也不因为 basename 是 `backup` 就赋予特殊含义。发行模板不依赖这段 Prompt 来兑现任何安全承诺。

## Git 证据与用户明确的写操作

没有 Git-specific tool、adapter 或隐式工作流。模型可以把只读 `git status`/`git diff` 作为证据提出普通 raw `exec`；它们仍经过 Shell Permission、必要确认和 durable operation 屏障。`stash`、临时/正式 commit、checkpoint commit、reset、checkout、revert、merge、push 等写入或工作流操作只有用户明确要求时才可提出，Runtime 绝不自动执行。

即便用户要求，Git command 仍是 opaque shell 副作用：

- 它必须经过 `Shell` Permission、必要 DoubleCheck/人工确认和 durable operation barrier。
- Runtime 不解析 command 来证明只触及当前 repository，也不把 Git 当 OS sandbox。
- 现有 staged/unstaged/untracked 内容可能属于用户；模型与用户负责明确目标，Runtime 不自动整理或覆盖。
- command 成败、输出、后代和 unknown 按普通 `exec` 收口；没有额外 rollback。

## 故障与 unknown 矩阵

| 故障窗口 | 可证明的规范结果 | 后续行为 | 禁止行为 |
| --- | --- | --- | --- |
| admission/Permission/durable intent 前失败 | 未开始副作用；`failed` 或 `denied` | 可以由模型提出新的独立 call | 执行后补记录 |
| intent durable、direct mutation 尚未开始时崩溃 | 目标仍匹配 expected old identity/digest 时记 `not-applied` synthetic result | 原 operation 关闭；是否重试必须成为新 operation | 自动重放旧 operation |
| temp 已写、正式发布前失败 | 目标保持 old identity/digest；temp residue 单列 | 清理只按文件系统恢复协议；主目标不变 | 把 temp 当正式结果、删除旧目标 |
| publish 返回成功但 result 未 durable | 目标匹配 exact candidate identity/digest 时追加 applied synthetic result | 保存真实已发生事实 | 当作失败后重写 |
| publish 返回错误或进程崩溃，目标匹配 old | 收口 `not-applied/failed`，记录 API/残留证据 | 新动作需新 ID | 无条件 rollback |
| publish 后目标既不匹配 old 也不匹配 candidate | `unknown/conflicted` | fail-stop；用户/self-fix 追加证据 | 猜测归属或覆盖当前内容 |
| rename cross-device/target exists | typed conflict，证明 source/target 未按本 operation 改变 | Agent 获得结果后重新计划 | 自动 copy+delete、覆盖 target |
| delete result 未 durable | exact target 缺失可证明 applied；原 identity 仍在可证明 not-applied；其余 unknown | 保存 synthetic result或等待解算 | 用同名新对象推断旧对象状态 |
| 一个 batch 中第 N 项失败 | 1..N-1 保持各自结果，N 真实失败，N+1..end 各自 `skipped` | Agent 取得整批配对后决定下一步 | 回滚前项、继续执行剩余副作用 |
| `exec` 退出/取消后仍有后代或外部效果 | 保存 observed result，标记 `external_effects_unsettled`/unknown | 等待用户证据或新动作 | 仅凭 root exit 宣称全部完成 |
| operation/result XML 提交失败 | 立即阻止下一副作用；恢复时以 old/candidate/当前 identity 对照 | 生成真实或 synthetic result 后才能继续 | 在事实缺口上继续 AgentLoop |
| 文件在 Agent 发布后被外部修改 | 原 operation 保留 applied；当前 drift 单独报告 | 新写必须基于新的 expected digest | 用旧 diff 覆盖、把 drift 归给 Agent |

unknown 是正式结果，不是待后台重试状态。用户可以在 context self-fix 中追加 `completed|not-completed|still-unknown` 和证据；原 intent、unknown result 与后续解算都保留。即使用户判断 old operation 已完成，任何再次执行仍必须使用新 operation ID、当前 Permission 和当前 target freshness。

## 明确删除的候选路线

下列旧草案不属于 v0.1 活动设计，只作为被拒绝方向的历史摘要保留：

- 每次修改前把完整 preimage/base64 attachment 写入 Context XML，再自动补偿撤销；
- 按 turn 建立 checkpoint、reverse patch 或自动 compensation transaction；
- 自动 Git stash/commit/reset/checkout/revert 作为统一 rollback；
- shadow workspace、overlay 或“一次应用全部文件”；
- 递归 direct delete 后依赖 trash/backup 恢复；
- 扫描 raw shell 前后文件系统并宣称得到完整可撤销事务。

这些路线不能通过隐藏 sidecar、Prompt 约定、临时目录或“内部实现细节”回到首版。

## 将来显式重开条件

只有项目负责人针对具体用例显式重开，才可重新设计 undo/backup/transaction。重开不是给现有 operation 多加一个按钮，而必须同时回答：

- 精确覆盖哪些 direct tools，raw shell 是否永远排除；
- preimage/attachment 放在哪里，怎样满足单 XML、Win32 x86 体积与写放大硬门；
- 源码、binary、API Key、未知秘密、ACL/xattr/ADS/hardlink 的保存与清除；
- 配额、跨机迁移、导出、损坏、磁盘满和崩溃窗口；
- 外部并发修改时的冲突与补偿 Permission；
- UI 怎样避免把 best-effort compensation 宣传成 ACID rollback。

在这些问题被重新确认并通过三平台测试前，公开帮助、配置 schema、Context schema 和发行包中都不得出现可触发的 undo/backup/checkpoint/rollback 空壳。

## 验收要求

- direct create/replace/patch/rename/delete 在竞争、磁盘满、只读/共享占用、kill 和 publish 不确定时满足上述矩阵。
- 每个 accepted mutation 和 `exec` 都有唯一 intent/result；首个失败后的剩余 batch 项全部得到 `skipped`，没有丢失配对。
- diff 只归属有 operation 证据的内容；启动前 dirty 与发布后 drift 不被吞并。
- unknown 不自动重放，用户解算只追加事实。
- Runtime 不生成 preimage、checkpoint、reverse patch、trash、Git stash/commit 或 rollback。
- `backup/` 只作为 Prompt 普通文字被处理；删除该文字不会留下任何 schema、tool、目录管理或恢复行为。

---

## W3-D：无 undo 操作故障全矩阵（扩展规范）

对齐：D-052、D-057、D-070；AR-P0-07；工具边界见 [07](07-tool-system.md)、[TOOL-PERMISSION-MATRIX.md](../TOOL-PERMISSION-MATRIX.md)（**不改** Std/Readonly 格）。

### Operation 状态机

```text
proposed -> admitted -> intent_durable -> executing -> { applied | failed | not_applied | skipped | unknown }
                              \-> denied (Permission/user)
```

| 状态 | 可重放旧 ID？ | 下一步 |
| --- | --- | --- |
| applied | 否 | 新 op 需新 expected digest |
| failed / not_applied / denied | 否 | 新 op |
| skipped | 否 | batch 内后续项 |
| unknown | 否 | self-fix 解算；仍新 ID 才执行 |

### Direct 文件 op × 故障（补充细表）

| Op | 故障窗口 | 规范结果 | 禁止 |
| --- | --- | --- | --- |
| create | 目标已存在 | `DestinationExists` / failed | 覆盖 |
| write/patch | expected digest 不匹配 | `TargetChanged` | 盲写 |
| write | temp 成功、replace 失败 | 目标保持 old；清理 temp | 把 temp 当事 |
| rename | 目标存在 | conflict；source 不变 | 自动覆盖 |
| rename | 跨卷 | typed CrossDevice 或受控 copy 协议失败→unknown | 静默半完成当成功 |
| delete | 确认后消失 | applied（若 identity 匹配缺失） | 用同名新文件当旧文件 |
| delete | 确认后仍在且 identity 变 | unknown/conflicted | 再删不确认 |
| batch i 失败 | 见下 | 1..i-1 保留；i 失败；i+1..n `skipped` | 回滚 1..i-1 |

### Batch 语义

| 规则 | 说明 |
| --- | --- |
| 串行 | 工具全局串行（D-051） |
| 配对 | 每项必有 result；禁止丢 pairing |
| 部分成功 | **不** 事务回滚；Agent 据结果重计划 |
| 中止 | cancel → 未开始项 skipped；执行中项 cancel/unknown 按 02 |

### Raw shell / Git

| 规则 | 说明 |
| --- | --- |
| 证据 | 仅 durable intent + observed exit/output + tree 终态 |
| 只读 git | 仍走 Shell；ambient pager/difftool **隔离** |
| 写 git | 仅用户明确要求；无自动 stash/commit/reset |
| 未知副作用 | `external_effects_unsettled` / unknown；**无** 文件系统 diff 伪事务 |

### 崩溃切点 × 存储（与 10 号衔接）

| 切点 | 文件树 | XML |
| --- | --- | --- |
| intent 前 | 不变 | 无 op |
| intent 后、mutation 前 | 不变 | intent 可恢复 → synthetic not_applied |
| temp 写后、publish 前 | old + temp | 恢复协议清 temp |
| publish 后、result 未记 | new 可能已在 | 恢复对照 identity → applied/unknown |
| result 已记 | — | 正常 |

### 零表面（发布扫描）

| 禁止出现 | 位置 |
| --- | --- |
| undo / rollback / checkpoint tool | registry、help、INI |
| preimage attachment element | XML schema |
| trash/restore | Context mutation |
| 自动 Git workflow controller | Runtime |

### 备选否决（重申）

完整 preimage XML、checkpoint commit、shadow workspace、shell 前后扫盘“事务”——均 **v0.1 否**；重开条件见上文「将来显式重开」。

### 完成度（W3-D change）

- [x] 状态机 + direct/batch/shell/崩溃表  
- [x] 零 undo 表面  
- [ ] 目标机 no-replace/kill 注入证据（TP）  
