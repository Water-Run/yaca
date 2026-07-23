# 设计决策实时登记表

更新日期：2026-07-22

状态：现行原子审计记录；265 个 active group 已收到选择/排除，5 个条件组为 `not-applicable`，`unanswered=0`；集中负责人问卷已经关闭

## 这份文件负责什么

本表是项目负责人回复之后的唯一**实时状态登记簿**。十个 [决策包](decision-packets/README.md) 仍拥有问题正文、A/B/C、推荐与代价；[`DECISIONS.md`](DECISIONS.md) 仍拥有已经确认的产品结论；各 `subsystems/` 最终规格拥有可实施契约；[`ARCHITECTURE-READINESS.md`](ARCHITECTURE-READINESS.md) 和技术证明拥有 gate/证据。本表只连接这些层，不复制或替代其中任何一层。

`DISCUSSION-BATCH-06.md` 已保存 [`OWNER-QUESTIONS-01.md`](OWNER-QUESTIONS-01.md) 的 28 个产品/风险选择、1 个 DoubleCheck 语义补问及逐项收口原话。248 个原先的 `unanswered` 已按集中问题覆盖表投影，条件重新计算后没有遗留产品补问或 conflict。每个 `PR-006-<GROUP-ID>` 的确定展开由 [`DECISION-PROJECTION-BATCH-06.md`](DECISION-PROJECTION-BATCH-06.md) 维护；atomic register 仍保留收到回复时的 v9 语义，不把技术证明状态伪装成实现完成。

因此：

- 推荐出现在本表，不表示已经选择；只有项目负责人的明确回复才能把 `unanswered` 改成其他状态。
- `DISCUSSION-BATCH-01.md` 形成于本套正式编号之前，是 D-001..D-039 的历史答复证据，不会自动把本表任一组标成已答。下一次正式包回复从 `DISCUSSION-BATCH-02.md` 开始按原话追加归档。
- 逐组的长例外会进入稀疏 assertion/冲突记录；主表只保存状态、选择、原话引用和传播引用，避免复制 270 份选项正文。
- 本表的 `State` 只描述负责人答复状态；`Projection` 引用独立 PR 记录，不能把 `selected`、`specified` 和 `release-proven` 混成一个状态。
- 冻结的 `decision-inventory-v9` 保留收到回复时的历史候选语义。其 RF-04/luainstaller 文本中“当前 guard 拒绝 x86”仍是代码事实，但不得再外推为底层 x86/XP 不可行；现行证据口径由 `AS-005-01` 修正，详见 `DISCUSSION-BATCH-05.md`。

## 锁定的问卷清单

| 字段 | 当前值 |
| --- | --- |
| Inventory version | `decision-inventory-v9` |
| Packet-source SHA-256 | `13b0a7cbad9556db50bbd81bdee76554900d252deb79b3ab68bd41e5f59c49f6`；825719 bytes；按 owner packet 文件名升序，逐包连接 `<UTF-8 filename><NUL><raw file bytes><NUL>`，用于证明 canonical manifest 的原始来源 |
| Structural SHA-256 | `22e724986251bd63ae75e1c7964b3a2f6d3412a4e0f9b01019662790d68df6ef`；270 records / 13575 bytes，只覆盖 ID/标题/推荐，用于快速集合检查，不得解释旧选择 |
| Semantic SHA-256 | `80efc73d45ed32e05ea991f35a8cc484700a276f6664c77bc339c7957648b044`；270 records / 471107 bytes，负责人回复必须绑定这一项 |
| Canonical record | 按包文件名升序、组号数字升序；正式标题只由该 owner packet 底部推荐回复模板的成员集判定，其他包内同 ID 的投影/非投票标题忽略；每组包含 packet、recommended letter、`active_when` 和从正式 H2/H3 标题到下一个同级/更高标题前的完整 Markdown section；统一 UTF-8/LF、删除行尾空白和首尾空行、保留一个结尾 LF；精确 framing 见下文 |
| Formal groups | 270 |
| Activation split | `22 conditional / 248 always` |
| Checklist IDs | 384 |
| Atomic questions | `AQ-001..AQ-437` |
| Current state | `110 selected / 150 selected-with-exception / 5 excluded / 5 not-applicable / 0 unanswered`；完整状态计数见下表 |

structural stream 也按 owner packet 文件名升序、packet 内 group 数字后缀升序；成员只取该 packet 底部推荐回复模板，标题取其正式 H2/H3 中 group ID 及分隔符后的完整原文。每条精确为 `<group_id><TAB><title><TAB><recommended_letter><LF>`，270 条 UTF-8 record 直接连接，无头、尾或额外空行。

canonical stream 对每组使用下面 framing（尖括号表示值，不是字面占位符）：

```text
@@group<TAB><group_id>
packet<TAB><packet_filename>
recommendation<TAB><A|B|C>
active_when<TAB><condition|always>
<normalized complete formal Markdown section>
@@end
```

`@@end` 后也保留一个 LF；所有 record 直接连接，不另加分隔空行。这个摘要锁定“本包其余接受推荐”的作用域和字母的完整语义，不只锁 ID/标题。逐组 `Sem` 是该组 canonical record 的 SHA-256 前 16 个小写十六进制字符，主表本身就是 versioned manifest；总 `Semantic SHA-256` 仍是唯一完整校验值，短标签只用于定位变化。以后若增加、删除、改名、改变推荐/条件/选项、组合矩阵、失败边界或关联，必须生成新的 inventory version/digest；旧回复只按收到时的旧 payload 解释，不能把旧 `A` 套到新选项，也不能追溯性选择后来新增的项目。纯排版改动也可能改变 digest，这是有意的保守失效；更新者必须明确说明是否只是无语义格式变化。

### 当前 group-state 计数

| State | Count |
| --- | ---: |
| `unanswered` | 0 |
| `explaining` | 0 |
| `selected` | 110 |
| `selected-with-exception` | 150 |
| `deferred` | 0 |
| `excluded` | 5 |
| `not-applicable` | 5 |
| `technical-proof` | 0 |
| `superseded` | 0 |
| `conflict` | 0 |
| **总计** | **270** |

## 当前进度与下一批

| 包 | 总数 | Active 已收口 | N/A | 未收口 | 下一步 |
| --- | ---: | ---: | ---: | ---: | --- |
| [PJ：产品旅程与表面](decision-packets/02-product-journey-and-surfaces.md) | 19 | 18 | 1 | 0 | 产品旅程已收口；继续完成 owner 规格/测试投影 |
| [PP：Prompt、人格与指令](decision-packets/03-prompt-personality-and-instructions.md) | 18 | 18 | 0 | 0 | 四层 Prompt owner 规格与 golden request 证明 |
| [TU：TUI、输入与 CLI 体验](decision-packets/04-tui-visual-input-cli-experience.md) | 32 | 31 | 1 | 0 | action registry/旧终端按键证明 |
| [M05：Model、配置、网络与 Self-Test](decision-packets/05-model-configuration-network-selftest.md) | 57 | 57 | 0 | 0 | schema、adapter 与目标网络证明 |
| [AL06：AgentLoop、DoubleCheck 与压缩](decision-packets/06-agentloop-busy-doublecheck-compaction.md) | 49 | 48 | 1 | 0 | 完整状态表、预算与 compaction fixtures |
| [TS：Tool、安全、进程与运行时](decision-packets/07-tools-safety-process-runtime.md) | 35 | 34 | 1 | 0 | Tool/Permission/进程矩阵与目标机证明 |
| [CX：Context XML、索引与恢复](decision-packets/08-context-xml-index-recovery.md) | 16 | 16 | 0 | 0 | XML schema/提交/恢复与性能证明 |
| [ED：错误、诊断与兼容体验](decision-packets/09-errors-diagnostics-compatibility.md) | 14 | 13 | 1 | 0 | error/close/self-test 输出矩阵 |
| [RF：发布、测试与冻结](decision-packets/10-release-testing-and-readiness-freeze.md) | 14 | 14 | 0 | 0 | 三目标最终包 qualification/完整测试 |
| [F4：跨系统运行接缝](decision-packets/11-cross-system-operational-seams.md) | 16 | 16 | 0 | 0 | 跨 owner fault/transition 证明 |
| **总计** | **270** | **265** | **5** | **0** | 负责人选择阶段关闭；进入规格/技术证明阶段 |

包级表只是导航派生值：`Active 已收口 = (active_when=always 或 Current=true) 且 state 属于 selected / selected-with-exception / excluded / technical-proof`；上游未决时的 activation-pending pre-answer 进入 `未收口`，不能伪装成 active 决定；`N/A = not-applicable`；其余现行 state 进入 `未收口`。三列之和必须等于总数，完整真相始终是上面的协议状态计数；传播是否完成另看 PR 记录。

负责人在 `DISCUSSION-BATCH-02.md` 至 `04` 收口产品旅程和早期跨系统补缝；`DISCUSSION-BATCH-05.md` 修正 luainstaller x86 证据口径并建立集中问卷；`DISCUSSION-BATCH-06.md` 已回答全部 29 个集中问题并完成条件/冲突收口。后续只在技术证明确实失败且替代路线会改变用户保证时，重新提出最小产品差异；不能回到旧 49 批重复询问。

## 条件组与预先回答

| 条件组 | `active_when` | Current | Basis | False 时的 no-projection ref |
| --- | --- | --- | --- | --- |
| PJ-19 | `choice(PJ-16) in [B,C]` | `false` | PJ-16=A；`B02/RB-002-02` | `PR-002-18`：零 transcription 配置/CLI/Model purpose/XML/Runtime/test 表面 |
| TU-30 | `choice(TU-27) in [B,C]` | `false` | TU-27=A；`B06/AS-006-04` | `PR-006-TU-30`：零 notification 配置/事件/Runtime 表面 |
| ED-14 | `choice(ED-07) in [A,B]` | `false` | ED-07=C；`B06/AS-006-15` | `PR-006-ED-14`：零 diagnostic-upload artifact/endpoint/command 表面 |
| M05-26 | `choice(M05-03) in [A,C]` | `true` | M05-03=A；`B06/AS-006-06/07` | — |
| M05-55 | `choice(M05-15) in [A,B]` | `true` | M05-15=A；`B06/AS-006-12` | — |
| AL06-08 / AL06-24 / AL06-25 | `choice(AL06-07) in [A,B]` | `true` | AL06-07=A；`B06/AS-006-10` | — |
| AL06-30 / AL06-31 / AL06-34 | `choice(AL06-11) == A` | `true` | AL06-11=A；`B06/AS-006-11` | — |
| AL06-39 / AL06-47 | `choice(AL06-11) in [A,B]` | `true` | AL06-11=A；`B06/AS-006-11` | — |
| AL06-43 | `choice(M05-50) == C` | `false` | M05-50=A；`B06/AS-006-11` | `PR-006-AL06-43`：零 amount/price/admission 配置与事件表面 |
| TS-21 | `choice(M05-56) == B` | `false` | M05-56=A；`B06/AS-006-12` | `PR-006-TS-21`：零 SensitiveRead 字段/classifier/page 表面 |
| TS-25 / TS-26 / TS-34 / TS-35 | `choice(TS-02) in [A,C]` | `true` | TS-02=A；`B06/AS-006-12` | — |
| TS-28 / TS-29 / TS-31 | `choice(TS-02) == A` | `true` | TS-02=A；`B06/AS-006-12` | — |

共 22 个 conditional group；其余 248 个 group 的 `active_when=always`。固定 grammar 只有 `always`、`choice(<GROUP-ID>) == <LETTER>` 和 `choice(<GROUP-ID>) in [<COMMA-SEPARATED-LETTERS>]`；GROUP-ID/letter 大小写敏感、列表按 A/B/C 顺序、不得嵌套或使用自然语言。`Current` 只允许 `unknown|true|false`。false 时必须引用上游 reply 和一条 PR no-projection 记录；true 时必须引用使其激活的上游 reply。

PJ-19 只在 PJ-16 允许音频对象时生效，且 PJ-19 C 进一步只与 PJ-16 C 相容；若 PJ-16 B + PJ-19 C 同批出现就进入 `conflict`，不能暗中增加麦克风。TU-30 只在 TU-27 建立通知渠道时选择事件范围。ED-14 只在 ED-07 A/B 允许 yaca 生成 standalone diagnostic XML 时生效；ED-07 C 下必须得到零 upload 表面，不能由 ED-14 临时生成自己的 source artifact。M05-26 的条件只表示 M05-03 所选 **schema 路线允许 `Tools=off`**，不是扫描当前某个 Model instance 是否恰好配置为 off。M05-55 只在 M05-15 A/B 采用某种宿主环境继承基线时决定其成员；M05-15 C 的 clean baseline 下不产生 ambient-inherit 分支。AL06-08/24/25 只在 AL06-07 A/B 建立 action-review 时存在；AL06-30/31/34 只消费 AL06-11 A 的 structured-summary 路线；AL06-39/47 只消费 AL06-11 A/B 产生的 CompactionRecord。AL06-43 只消费 M05-50 C 的版本化价格快照。TS-21 只在 M05-56 B 建立独立 `SensitiveRead` capability 时存在；M05-56 A 下不受 M05-16 选择影响且必须零表面。TS-25/26/34/35 只在所选工具路线含对应 direct write/patch/metadata 能力时存在；TS-28/29/31 进一步只在 TS-02 A 含 direct rename/delete 时存在。

条件组在上游未决且尚未收到本组回复时记 `unanswered`，`Active when` 保存条件。负责人可以提前给字母：此时 `State` 记 `selected`/`selected-with-exception`，`Selection` 明标 `pre-answer; activation pending`，但在上游确定前不产生规格投影。上游最终使条件为假时，组变为 `not-applicable` 并保留原话引用；以后上游被明确修订，再重新计算并恢复该 pre-answer 供冲突检查。

“本包其余接受推荐”使用固定计算顺序：先应用同批显式选择/例外，重算它们能决定的条件，再把推荐填入此时 active 的“其余”组。依赖仍未回答的跨包条件组保持 `unanswered`；inactive 条件组记 `not-applicable`，不是带空字段的 selected。若负责人显式给了条件组字母或粘贴含该行的模板，则作为 pre-answer 保存。例如同批明确 `M05-03 A` 后，“其余接受推荐”会覆盖新激活的 M05-26；尚未决定 M05-56 时，单独回复 TS 包的“其余接受推荐”不会暗选 TS-21。

## 回复登记事务

每收到一批回复，必须按同一个事务完成：

1. 把负责人原话、日期、inventory version/digest 和会话位置追加到下一份 `DISCUSSION-BATCH-NN.md`。
2. 按 [`DECISION-RESOLUTION-PROTOCOL.md`](DECISION-RESOLUTION-PROTOCOL.md) 原子化，逐组更新 `State`、`Selection` 和 `Reply`；例外写 assertion，歧义/冲突不猜。
3. 重新计算所有 `Active when`；inactive 组只变 `not-applicable`，不产生配置、XML、页面或测试空壳。
4. 对照现行 D，新增、细化、supersede 或报告最小冲突；建立 PR 传播记录并由主表 `Projection` 引用。
5. 把选择展开到唯一 owner 规格和 consumer 投影，再更新 readiness gate；传播未完成不等于回复丢失，但不得宣称规格完成。
6. 校验 group/template/register 集合、inventory digest、状态不变量、链接和编号后再提交。

每个新 reply batch 使用固定头，正文原话不改写：

```text
batch_id:
received_at:             ISO-8601 with timezone
source:                  conversation/session evidence
inventory_version:
structural_sha256:
semantic_sha256:
inventory_git_commit:    收到回复前、包含该 inventory 的 HEAD
raw_verbatim_id:
raw_verbatim: |
  <负责人原话>
explicit_group_ids:
blanket_scope:
expanded_active_ids:     实际被“其余接受推荐”展开的精确列表
inactive_ids:
unresolved_condition_ids:
assertion_ids:
```

`Reply` 只引用稳定的 `batch_id/raw_verbatim_id/assertion_id`，不引用会随编辑漂移的行号。收到回复前先记录 `inventory_git_commit`，避免在包含回复的后续 commit 中形成自引用。

选中组至少要有 `Reply` 和 `Selection/assertion`；`unanswered` 不能拥有由该组新生成的 D；`not-applicable` 必须有已选上游和无投影证据；`superseded/conflict` 必须保留双方引用。完整状态词表以收口协议为准。

## 包级 owner 与 gate 路由

| 包 | 主要 owner 子系统 | 主要 readiness gate |
| --- | --- | --- |
| PJ | `00/05/08/13/14/17` | `AR-P0-01`, `AR-P0-08`, `AR-P0-13`, `AR-P0-16` |
| PP | `18/09/06/10` | `AR-P0-02`, `AR-P0-03` |
| TU | `13/14` | `AR-P0-13` |
| M05 | `05/06/03/15` | `AR-P0-03`, `AR-P0-08`, `AR-P0-09` |
| AL06 | `09/12` | `AR-P0-02`, `AR-P0-04`, `AR-P0-05`, `AR-P0-12` |
| TS | `07/08/02/19` | `AR-P0-06`, `AR-P0-07`, `AR-P0-14`, `AR-P0-15` |
| CX | `10/11/04` | `AR-P0-10`, `AR-P0-11` |
| ED | `15/01/22` | `AR-P0-13`, `AR-P0-15`, `AR-P1-07` |
| RF | `16/20` | `AR-P0-16`, `AR-P1-08`, `AR-P1-11`, `AR-P1-12` |
| F4 | `按组唯一 owner` | `受影响的 AR-P0/P1 gate` |

`F4` 是跨系统敌对场景包，不建立“跨系统万能 owner”；每组仍要投影到已有唯一 owner。上表只是初始路由，逐组的最终 PR 必须指向恰好一个稳定 owner anchor、明确 consumer 和可执行 contract。

## 逐组实时登记

列含义：`Rec` 是包内推荐而非决定；`Sem` 是当前组语义标签；`Active when` 使用上面的固定 grammar；`Selection` 保存 A/B/C、pre-answer 标记或自然语言 assertion 引用；`Reply` 指向原话批次；`Projection` 指向下面的 `PR-*`。当前 unanswered 行的后三项为空是有意的；任何非 unanswered 行都不得保留裸 `—`。

### [PJ：产品旅程与表面](decision-packets/02-product-journey-and-surfaces.md)

| Group | Topic | Rec | Sem | Active when | State | Selection | Reply | Projection |
| --- | --- | :---: | --- | --- | --- | --- | --- | --- |
| `PJ-01` | 裸启动的通用启动信息显示多少 | A | `17e0deb8449a4818` | `always` | `selected-with-exception` | custom：无总开关，只有逐字段开关；`AS-002-01`、`AS-004-01` | `B02/RB-002-02; B04/RB-004-02` | `PR-002-01` |
| `PJ-02` | 缺失/损坏配置时还能使用哪些入口 | A | `677cf61d4a9428a4` | `always` | `selected-with-exception` | A + bootstrap context-repl；`AS-002-02` | `B02/RB-002-02` | `PR-002-02` |
| `PJ-03` | 没有可用 Model 与暂时离线的区别 | A | `5846f7ae5bbfba91` | `always` | `selected-with-exception` | A + explicit startup self-test；`AS-002-03/15` | `B02/RB-002-02` | `PR-002-03` |
| `PJ-04` | 普通最近 Context 是否在裸启动提示 | A | `0e32ee7f34c56f3f` | `always` | `selected-with-exception` | custom：裸启动零 Catalog 扫描；Context list 使用 D-047 双字段排序；`AS-002-04`、`AS-004-06` | `B02/RB-002-01/02; B04/RB-004-07` | `PR-002-04` |
| `PJ-05` | 空 Context 何时真正产生 | A | `a23cdc4910a0eb39` | `always` | `selected-with-exception` | A；精确为第一条 main 消息；`AS-002-05` | `B02/RB-002-02` | `PR-002-05` |
| `PJ-06` | recovery 的入口策略 | A | `9580635d930ab994` | `always` | `selected` | B | `B02/RB-002-02` | `PR-002-07` |
| `PJ-08` | v0.1 有哪些正式交互表面 | A | `c77bcdb7931f2894` | `always` | `selected-with-exception` | custom：六表面 + 各 REPL 本域 self-fix；`AS-002-07` | `B02/RB-002-02` | `PR-002-09` |
| `PJ-09` | 从 chat 进入管理表面的时机与返回位置 | A | `a7fe000744aa63a5` | `always` | `selected` | C；会话 actions 保留 | `B02/RB-002-02` | `PR-002-11` |
| `PJ-10` | 退出策略 | A | `7e47dc2d11763d16` | `always` | `selected` | C | `B02/RB-002-02` | `PR-002-12` |
| `PJ-11` | 普通对话是否需要独立 plan state | A | `7124bcbda994e295` | `always` | `selected` | A；Permission clarification `AS-002-13` | `B02/RB-002-02` | `PR-002-13` |
| `PJ-12` | 新 Context 第一个名称怎样产生 | A | `3b0544f89865081a` | `always` | `selected-with-exception` | custom ASCII fallback + periodic request + per-Context `AutoRenameDisabled`；`AS-002-06`、`AS-003-02` | `B02/RB-002-01/02; B03/RB-003-01/02` | `PR-002-06` |
| `PJ-13` | 继续 Context 时 `AutoJumpToDir` 怎样影响 workspace | A | `67599d9f68efa47a` | `always` | `selected-with-exception` | custom：fixed mirror-derived work directory + explicit XML move/rebind；`AS-002-09`、`AS-003-01` | `B02/RB-002-02; B03/RB-003-01` | `PR-002-10` |
| `PJ-14` | Web 是否进入 v0.1 | A | `9fb6283866cb8783` | `always` | `excluded` | A | `B02/RB-002-02` | `PR-002-14` |
| `PJ-15` | 是否支持图像输入 | A | `d58d8ae048eebe2b` | `always` | `excluded` | A | `B02/RB-002-02` | `PR-002-15` |
| `PJ-16` | 音频输入支持到哪一层 | A | `d8eae906b296fb20` | `always` | `excluded` | A | `B02/RB-002-02` | `PR-002-16` |
| `PJ-17` | 是否提供 remote/headless 控制面 | A | `1ee8dceb19709aa5` | `always` | `excluded` | A | `B02/RB-002-02` | `PR-002-17` |
| `PJ-18` | 一个 Context 是否支持多个 workspace root | A | `9639cfc715c2f733` | `always` | `selected` | A；single mirror-derived root；`AS-003-01` | `B03/RB-003-01` | `PR-002-20` |
| `PJ-19` | 是否提供独立 transcription 动作 | A | `c65e5a2926136d63` | `choice(PJ-16) in [B,C]` | `not-applicable` | pre-answer A retained; inactive by PJ-16=A | `B02/RB-002-02` | `PR-002-18` |
| `PJ-20` | 是否提供 TTS/语音播报 | A | `8f9e15c47baac699` | `always` | `excluded` | A | `B02/RB-002-02` | `PR-002-19` |

### [PP：Prompt、人格与指令](decision-packets/03-prompt-personality-and-instructions.md)

| Group | Topic | Rec | Sem | Active when | State | Selection | Reply | Projection |
| --- | --- | :---: | --- | --- | --- | --- | --- | --- |
| `PP-01` | 默认 Agent 人格 | A | `11b66fa15126e4e0` | `always` | `selected-with-exception` | custom:A + Prompt-directed; `AS-006-01` | `B06/RB-006-01` | `PR-006-PP-01` |
| `PP-02` | 回复语言策略 | A | `712aa38d3298479b` | `always` | `selected-with-exception` | custom:A + Prompt-directed; `AS-006-01` | `B06/RB-006-01` | `PR-006-PP-02` |
| `PP-03` | 指令权威链和用户 Prompt 的替换边界 | A | `74239870941afa42` | `always` | `selected-with-exception` | custom:four-layer Prompt; `AS-006-02` | `B06/RB-006-01; RB-006-03` | `PR-006-PP-03` |
| `PP-04` | 项目规则怎样成为指令 | A | `1241fa8dd6d8549e` | `always` | `selected-with-exception` | custom:four-layer Prompt; `AS-006-02` | `B06/RB-006-01; RB-006-03` | `PR-006-PP-04` |
| `PP-05` | 六个核心 purpose 是否使用独立契约 | A | `608f349e775b3862` | `always` | `selected-with-exception` | custom:four-layer Prompt; `AS-006-02` | `B06/RB-006-01; RB-006-03` | `PR-006-PP-05` |
| `PP-06` | 复杂任务的进度更新时点 | A | `8cc624c343b3d1cf` | `always` | `selected-with-exception` | custom:A + Prompt-directed; `AS-006-01` | `B06/RB-006-01` | `PR-006-PP-06` |
| `PP-07` | role flattening 与注入 delimiter | A | `f3c686b672c0f3b0` | `always` | `selected-with-exception` | custom:four-layer Prompt; `AS-006-02` | `B06/RB-006-01; RB-006-03` | `PR-006-PP-07` |
| `PP-08` | yaca/Prompt 升级后的新 turn 使用什么 | A | `801bbc989fcbd771` | `always` | `selected-with-exception` | custom:four-layer Prompt; `AS-006-02` | `B06/RB-006-01; RB-006-03` | `PR-006-PP-08` |
| `PP-09` | Prompt 超限和切换到小窗口 Model | A | `2c9b1548c8269ed7` | `always` | `selected-with-exception` | custom:four-layer Prompt; `AS-006-02` | `B06/RB-006-01; RB-006-03` | `PR-006-PP-09` |
| `PP-11` | 旧 `Model.CustomPrompt` 怎样收口 | A | `f9826b1d99a8a352` | `always` | `selected-with-exception` | custom:four-layer Prompt; `AS-006-02` | `B06/RB-006-01; RB-006-03` | `PR-006-PP-11` |
| `PP-12` | `.prompt` 的交互形态与事务边界 | A | `49a4fbec19b36b1b` | `always` | `selected-with-exception` | custom:four-layer Prompt; `AS-006-02` | `B06/RB-006-01; RB-006-03` | `PR-006-PP-12` |
| `PP-13` | AdoptedRuleTransition：已采用项目规则发生变化时怎么办 | A | `30b509c277cdffc8` | `always` | `selected-with-exception` | custom:four-layer Prompt; `AS-006-02` | `B06/RB-006-01; RB-006-03` | `PR-006-PP-13` |
| `PP-14` | 工具动作的模型叙述密度 | A | `49cb4335cd675afb` | `always` | `selected-with-exception` | custom:A + Prompt-directed; `AS-006-01` | `B06/RB-006-01` | `PR-006-PP-14` |
| `PP-15` | 完成时最终报告的结构 | A | `6e78edad0b1d1d16` | `always` | `selected-with-exception` | custom:A + Prompt-directed; `AS-006-01` | `B06/RB-006-01` | `PR-006-PP-15` |
| `PP-16` | 普通回答与设计讲解的默认详略 | A | `21dcdf194ff88443` | `always` | `selected-with-exception` | custom:A + Prompt-directed; `AS-006-01` | `B06/RB-006-01` | `PR-006-PP-16` |
| `PP-17` | 何时澄清，何时带假设继续 | A | `7bbce24591c271fa` | `always` | `selected` | A; `AS-006-01` | `B06/RB-006-01` | `PR-006-PP-17` |
| `PP-18` | 普通用户指令的生命周期 | A | `6314e96c525ef288` | `always` | `selected-with-exception` | custom:four-layer Prompt; `AS-006-02` | `B06/RB-006-01; RB-006-03` | `PR-006-PP-18` |
| `PP-19` | 内置 Prompt bundle 的文本冻结政策 | A | `e19769396e58278a` | `always` | `selected-with-exception` | custom:four-layer Prompt; `AS-006-02` | `B06/RB-006-01; RB-006-03` | `PR-006-PP-19` |

### [TU：TUI、输入与 CLI 体验](decision-packets/04-tui-visual-input-cli-experience.md)

| Group | Topic | Rec | Sem | Active when | State | Selection | Reply | Projection |
| --- | --- | :---: | --- | --- | --- | --- | --- | --- |
| `TU-01` | 单一逐行 transcript 的信息密度 | A | `283b923be116308e` | `always` | `selected` | A; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-01` |
| `TU-02` | 自动能力降级下采用哪种有限色彩策略 | A | `f53add790548a65c` | `always` | `selected` | A; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-02` |
| `TU-03` | Streaming 到达时怎样保护 draft | A | `7bfc3a04100187af` | `always` | `selected-with-exception` | custom:A + text fallbacks/queue management; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-03` |
| `TU-04` | 五种固定输入意图怎样显示结果 | A | `682ec8dbb313e5d3` | `always` | `selected-with-exception` | custom:A + text fallbacks/queue management; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-04` |
| `TU-05` | 五种输入意图在弱终端怎样后备 | A | `c90fb0a41dbd0f7e` | `always` | `selected-with-exception` | custom:A + text fallbacks/queue management; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-05` |
| `TU-06` | 工具、Markdown、代码和 diff 默认显示多少 | A | `2dc606b45749c3c6` | `always` | `selected` | A; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-06` |
| `TU-07` | 审批 prompt 的空 Enter 做什么 | A | `f616069f1fc261e4` | `always` | `selected-with-exception` | custom:A + text fallbacks/queue management; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-07` |
| `TU-08` | 错误、retry 和 recovery 的下一步动作怎样输入 | A | `78ff07bfbc474af1` | `always` | `selected-with-exception` | custom:A + text fallbacks/queue management; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-08` |
| `TU-10` | 规范命令已经固定后，简称采用什么政策 | A | `6ab52dfbba889d88` | `always` | `selected-with-exception` | custom:A + canonical short aliases; `AS-006-05` | `B06/RB-006-01; RB-006-08` | `PR-006-TU-10` |
| `TU-11` | 非 composer command x AgentState 结果怎样反馈 | A | `ee171d9e9d95a1c9` | `always` | `selected-with-exception` | custom:A + canonical short aliases; `AS-006-05` | `B06/RB-006-01; RB-006-08` | `PR-006-TU-11` |
| `TU-13` | 非 TTY 能力范围与 stdin 所有权 | A | `a503caa73da5d670` | `always` | `selected-with-exception` | custom:A + canonical short aliases; `AS-006-05` | `B06/RB-006-01; RB-006-08` | `PR-006-TU-13` |
| `TU-14` | 哪些状态在逐行 transcript 中显示 | A | `f4d1966cf68a52bb` | `always` | `selected` | A; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-14` |
| `TU-15` | Context 管理采用哪种编辑确认流程 | A | `75516da16594793d` | `always` | `selected-with-exception` | custom:A + text fallbacks/queue management; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-15` |
| `TU-16` | 异步事件怎样在 append-only transcript 中交错 | A | `15a17321c680ba7a` | `always` | `selected-with-exception` | custom:A + text fallbacks/queue management; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-16` |
| `TU-17` | 审批后参数被编辑时怎样使旧授权失效 | A | `0b2f770938fd9cad` | `always` | `selected-with-exception` | custom:A + text fallbacks/queue management; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-17` |
| `TU-18` | canonical 顶层 CLI 采用 flags、subcommands 还是混合 | A | `ae5e3da1062560eb` | `always` | `selected-with-exception` | custom:A + canonical short aliases; `AS-006-05` | `B06/RB-006-01; RB-006-08` | `PR-006-TU-18` |
| `TU-19` | chat composer 的 multiline、intent 参数与点开头正文 grammar | A | `bd4e4ab758e047a3` | `always` | `selected-with-exception` | custom:A + canonical short aliases; `AS-006-05` | `B06/RB-006-01; RB-006-08` | `PR-006-TU-19` |
| `TU-20` | TranscriptChrome 的正文标签采用哪套词汇 | A | `aaa49172a7348eb2` | `always` | `selected` | A; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-20` |
| `TU-21` | 非 TTY machine output 的格式与流式边界 | A | `6dd1f3ab5032e69d` | `always` | `selected-with-exception` | custom:A + canonical short aliases; `AS-006-05` | `B06/RB-006-01; RB-006-08` | `PR-006-TU-21` |
| `TU-22` | 非 composer prompt 怎样调用本地动作与全局命令 | A | `a9c62d9b6a587605` | `always` | `selected-with-exception` | custom:A + canonical short aliases; `AS-006-05` | `B06/RB-006-01; RB-006-08` | `PR-006-TU-22` |
| `TU-23` | stdin/stdout/stderr 拓扑与 human/machine output 怎样选择 | A | `57e8d4aafce8d5a9` | `always` | `selected-with-exception` | custom:A + canonical short aliases; `AS-006-05` | `B06/RB-006-01; RB-006-08` | `PR-006-TU-23` |
| `TU-24` | help 的 surface/topic grammar 与发现层级 | A | `60b7699e54b33083` | `always` | `selected-with-exception` | custom:A + canonical short aliases; `AS-006-05` | `B06/RB-006-01; RB-006-08` | `PR-006-TU-24` |
| `TU-25` | cooked-line 下关键事件怎样在有界时间内可见 | A | `41833d313c0d9ff1` | `always` | `selected-with-exception` | custom:A + text fallbacks/queue management; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-25` |
| `TU-26` | self-test 的逐行页面结构 | A | `e45cd77a54073c3f` | `always` | `selected` | A; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-26` |
| `TU-27` | 是否提供终端/系统通知渠道 | A | `8a306f9ac92c197d` | `always` | `selected` | A; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-27` |
| `TU-28` | 终端能力降级在什么时候提示 | A | `a6925b95aa5dd615` | `always` | `selected-with-exception` | custom:A + text fallbacks/queue management; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-28` |
| `TU-29` | 长工具输出在完成前怎样 preview | B | `298534c69ef052be` | `always` | `selected` | A; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-29` |
| `TU-30` | 通知功能启用后覆盖哪些事件 | A | `9de8c97ea6c61347` | `choice(TU-27) in [B,C]` | `not-applicable` | derived inactive: TU-27=A | `B06/RB-006-01` | `PR-006-TU-30` |
| `TU-31` | composer 输入召回的来源与生命周期 | A | `3b5cbe613b6bfd1b` | `always` | `selected-with-exception` | custom:A + text fallbacks/queue management; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-31` |
| `TU-32` | chat dot-command 使用平坦 roots 还是紧凑 namespace | A | `7971ca9cebe070d6` | `always` | `selected` | A；`.model` picker/direct selector 等价；`AS-004-02` | `B04/RB-004-03` | `PR-004-01` |
| `TU-33` | 输入提示符采用短符号、全词状态还是统一名称 | A | `6491d875f9723de2` | `always` | `selected` | A; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-33` |
| `TU-34` | 审批动作使用文字、编号还是短字母 | A | `0577636a0567e4cb` | `always` | `selected-with-exception` | custom:A + text fallbacks/queue management; `AS-006-04` | `B06/RB-006-01` | `PR-006-TU-34` |

### [M05：Model、配置、网络与 Self-Test](decision-packets/05-model-configuration-network-selftest.md)

| Group | Topic | Rec | Sem | Active when | State | Selection | Reply | Projection |
| --- | --- | :---: | --- | --- | --- | --- | --- | --- |
| `M05-01` | v0.1 协议范围 | A | `96eab8df5873519c` | `always` | `selected-with-exception` | B; `AS-006-06` | `B06/RB-006-01` | `PR-006-M05-01` |
| `M05-02` | AuthMode、空 Key 与鉴权边界 | A | `a1ef1f8152968867` | `always` | `selected-with-exception` | B; `AS-006-06` | `B06/RB-006-01` | `PR-006-M05-02` |
| `M05-03` | Tools 能力的协议边界 | A | `e6ae61909ce93e7f` | `always` | `selected` | A; `AS-006-06` | `B06/RB-006-01` | `PR-006-M05-03` |
| `M05-04` | timeout、retry-by-phase 与资源上限 | A | `65438263ac92c714` | `always` | `selected-with-exception` | custom:explicit HTTP + bundled TLS/stunnel guidance; `AS-006-08` | `B06/RB-006-01; RB-006-04` | `PR-006-M05-04` |
| `M05-05` | Model 可调请求参数的范围 | A | `5cbff683430b978a` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-05` |
| `M05-06` | 配置层级与 XML override 白名单 | A | `bde855f7d4c90b9a` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-06` |
| `M05-07` | 手工 INI、多行与 unknown 字段 | A | `9d48b3fc706814f8` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-07` |
| `M05-08` | 默认顺序、disabled Model 草稿与删除 | A | `e8c2ab86f9a6ba82` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-08` |
| `M05-09` | model-repl 与 config-repl 的责任分工 | A | `a8362c0cbb7e28b5` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-09` |
| `M05-11` | Self-Test Stage 2 的真实检查范围 | A | `4839c8437029ab7d` | `always` | `selected` | A; `AS-006-09` | `B06/RB-006-01` | `PR-006-M05-11` |
| `M05-12` | Self-Test Stage 3 的 reviewer 与结果地位 | A | `93b76dd81856378b` | `always` | `selected` | A; `AS-006-09` | `B06/RB-006-01` | `PR-006-M05-12` |
| `M05-13` | 明文 HTTP Endpoint 与 Key 的组合 | A | `3d0fbf95e1f0dcce` | `always` | `selected-with-exception` | custom:explicit HTTP + bundled TLS/stunnel guidance; `AS-006-08` | `B06/RB-006-01; RB-006-04` | `PR-006-M05-13` |
| `M05-14` | 传输资源上限是否成为用户配置 | A | `03bdd1e51d9af40b` | `always` | `selected-with-exception` | custom:explicit HTTP + bundled TLS/stunnel guidance; `AS-006-08` | `B06/RB-006-01; RB-006-04` | `PR-006-M05-14` |
| `M05-15` | raw shell 的环境配置面 | A | `604d698fddc99a59` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-M05-15` |
| `M05-16` | Permission 的 workspace 外能力采用粗粒度还是分动作 | A | `079c8806df051229` | `always` | `selected-with-exception` | B; `AS-006-12` | `B06/RB-006-01` | `PR-006-M05-16` |
| `M05-17` | `LogLevel` 是否保留以及写到哪里 | A | `947940d05fb8f867` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-17` |
| `M05-18` | `config reset` 只重置哪些配置字段 | A | `5c6892aaacb39e7c` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-18` |
| `M05-19` | optional 值的唯一语法 | A | `a89c6720c1c12794` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-19` |
| `M05-20` | conditional metadata 在 XML、reviewer 与支持输出中的可见性 | A | `195148d2c4652f07` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-20` |
| `M05-21` | Model/Permission 是否配置自定义颜色 | A | `faa4b2d386e55efb` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-21` |
| `M05-22` | 是否提供 generic CLI 一次性 override | A | `cec9ebdc2558986b` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-22` |
| `M05-23` | 自定义 request header/body 的扩展面 | A | `f4fa22141a448d6d` | `always` | `selected-with-exception` | B; `AS-006-06` | `B06/RB-006-01` | `PR-006-M05-23` |
| `M05-25` | `Streaming=try` 的 fallback 边界 | A | `7900016712541f38` | `always` | `selected-with-exception` | B; `AS-006-06` | `B06/RB-006-01` | `PR-006-M05-25` |
| `M05-26` | `Tools=off` 的 Model 能否当主 Agent | A | `3a9c721d014fab4e` | `choice(M05-03) in [A,C]` | `selected-with-exception` | B; `AS-006-06` | `B06/RB-006-01` | `PR-006-M05-26` |
| `M05-27` | `.cautious` 的 tri-state 与生效点 | A | `8d37e84e418255a1` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-27` |
| `M05-28` | unknown/deprecated 字段的读取与迁移 | A | `27380d680be76de1` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-28` |
| `M05-29` | config-repl 首页与 typed effective field view | A | `bf7af24f14e174cf` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-29` |
| `M05-30` | 第一份配置的事务发布 | A | `b8214cff916a3381` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-30` |
| `M05-31` | Stage 2 部分失败后是否继续检查其余 Model | A | `759ed669ea4138d6` | `always` | `selected` | A; `AS-006-09` | `B06/RB-006-01` | `PR-006-M05-31` |
| `M05-32` | Context XML 中的 Endpoint 投影精度 | A | `dcb8827040b83067` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-32` |
| `M05-33` | Endpoint 的物理写法 | A | `2694c823c30e8568` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-33` |
| `M05-34` | 删除或重命名仍被 Context 引用的 Model | A | `2a91576b8c158833` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-34` |
| `M05-35` | self-test 报告是否持久化 | A | `48cd78d9d3d66a8e` | `always` | `selected` | A; `AS-006-09` | `B06/RB-006-01` | `PR-006-M05-35` |
| `M05-36` | 全局 ProxyMode 的来源 | A | `2e62b4dcefe3dc17` | `always` | `selected-with-exception` | custom:explicit HTTP + bundled TLS/stunnel guidance; `AS-006-08` | `B06/RB-006-01; RB-006-04` | `PR-006-M05-36` |
| `M05-37` | CA trust source | A | `255f5de1740db882` | `always` | `selected-with-exception` | custom:explicit HTTP + bundled TLS/stunnel guidance; `AS-006-08` | `B06/RB-006-01; RB-006-04` | `PR-006-M05-37` |
| `M05-38` | HTTP redirect policy | A | `f9f1c2ab873e79f3` | `always` | `selected-with-exception` | custom:explicit HTTP + bundled TLS/stunnel guidance; `AS-006-08` | `B06/RB-006-01; RB-006-04` | `PR-006-M05-38` |
| `M05-39` | 新配置的 `DoubleCheck` 默认值 | A | `8778252a7ffb09fe` | `always` | `selected-with-exception` | custom:A corrected; finish review mandatory; `AS-006-10` | `B06/RB-006-01` | `PR-006-M05-39` |
| `M05-40` | provider 公开 reasoning 内容怎样进入产品 | A | `c7eeeb74ed7fedab` | `always` | `selected-with-exception` | B; `AS-006-06` | `B06/RB-006-01` | `PR-006-M05-40` |
| `M05-41` | Self-Test Stage 2 是否复现配置的 retry 与 streaming fallback | A | `84b077017698e7f3` | `always` | `selected` | A; `AS-006-09` | `B06/RB-006-01` | `PR-006-M05-41` |
| `M05-42` | 是否提供含配置秘密的 backup/export | A | `0d0b5e3e62765be8` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-42` |
| `M05-43` | Model/Permission Description 的 Context XML 投影 | A | `bb7e505d20c4f7a8` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-43` |
| `M05-44` | model-repl 列表的字段密度 | A | `d93fd80769e728f3` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-44` |
| `M05-45` | Add Model 的交互节奏 | A | `5b5b9276c75b79d2` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-45` |
| `M05-46` | Self-Test Stage 2 联网 consent 的批次边界 | A | `eede4e8061e841c1` | `always` | `selected` | A; `AS-006-09` | `B06/RB-006-01` | `PR-006-M05-46` |
| `M05-47` | Add Model 是否提供 clone existing | A | `584346a8f3af419d` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-47` |
| `M05-48` | Permission profile 的管理面 | A | `d93fa2b981848fcf` | `always` | `selected-with-exception` | B; `AS-006-12` | `B06/RB-006-01` | `PR-006-M05-48` |
| `M05-49` | 活动 Context 执行 Permission-switch semantic action 时怎样确认 | A | `4395b7cd7070382c` | `always` | `selected-with-exception` | B; `AS-006-12` | `B06/RB-006-01` | `PR-006-M05-49` |
| `M05-50` | 金额价格从哪里来 | A | `c9914976cadbb5c2` | `always` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-M05-50` |
| `M05-51` | 全局 Exec 配置表面 | A | `00d87157464c8088` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-M05-51` |
| `M05-52` | idle Model-switch semantic action 的兼容与隐私确认 | A | `3e984c08c72b9c38` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-52` |
| `M05-53` | Self-Test 的 rerun 选择范围 | B | `cca6ba1b96653028` | `always` | `selected` | A; `AS-006-09` | `B06/RB-006-01` | `PR-006-M05-53` |
| `M05-54` | 明文秘密配置文件权限不足时的运行政策 | A | `e9a9fef90428489b` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-54` |
| `M05-55` | raw shell 的 inherit baseline 到底包含什么 | A | `8589d6c36c145baf` | `choice(M05-15) in [A,B]` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-M05-55` |
| `M05-56` | 是否提供独立 `SensitiveRead` 能力 | A | `f25887cfe7f74b26` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-M05-56` |
| `M05-57` | Model/Permission 资源 selector 是否提供 Abbreviation | A | `40be12ff6d003df5` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-57` |
| `M05-58` | per-Model retry 配置面采用数字字段还是策略预设 | A | `0cee0ed1da49a935` | `always` | `selected-with-exception` | custom:explicit HTTP + bundled TLS/stunnel guidance; `AS-006-08` | `B06/RB-006-01; RB-006-04` | `PR-006-M05-58` |
| `M05-59` | 过短 config-secret 的兼容与 scanner 保证 | A | `2596e807f07a6e10` | `always` | `selected-with-exception` | custom:A + Model.SystemPrompt; `AS-006-07` | `B06/RB-006-01` | `PR-006-M05-59` |

### [AL06：AgentLoop、DoubleCheck 与压缩](decision-packets/06-agentloop-busy-doublecheck-compaction.md)

| Group | Topic | Rec | Sem | Active when | State | Selection | Reply | Projection |
| --- | --- | :---: | --- | --- | --- | --- | --- | --- |
| `AL06-01` | 总体 Loop 状态所有权 | A | `e70b3d2382fb0e8e` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-01` |
| `AL06-02` | typed control 的模型可见 carrier | A | `f6a7acc27c7a0956` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-02` |
| `AL06-04` | queue 的 terminal outcome 自动启动门 | A | `4a857fd30b7e84ed` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-04` |
| `AL06-05` | steer 对当前活动的抢占边界 | A | `ebb95cd204eb0871` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-05` |
| `AL06-06` | side 的活动容量与 main 忙时调度 | A | `59d40daa8b21db02` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-06` |
| `AL06-07` | DoubleCheck action-review 的动作范围 | A | `672918c0a1633f1e` | `always` | `selected-with-exception` | custom:A corrected; finish review mandatory; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-07` |
| `AL06-08` | action-review 使用哪个 Model | A | `7dd60c3972354276` | `choice(AL06-07) in [A,B]` | `selected-with-exception` | custom:A corrected; finish review mandatory; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-08` |
| `AL06-09` | 通用预算层级 | A | `5fd2cc9a10745f3f` | `always` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-09` |
| `AL06-10` | active turn 中 model-switch semantic action 的生效方式 | A | `93984e9ecd8cfeea` | `always` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-10` |
| `AL06-11` | 压缩后的 main model-view 结构 | A | `78e60e30474b57ce` | `always` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-11` |
| `AL06-12` | 历史大窗口 Model 之后的候选展示范围 | A | `9aeadf22d610f2d2` | `always` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-12` |
| `AL06-13` | text/tool block 顺序与 length 截断后的续写 | A | `a15d7ee898f098b5` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-13` |
| `AL06-14` | queue 管理能力集合 | A | `56735ab324d6ea9f` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-14` |
| `AL06-15` | 存在明确验证命令时的执行策略 | A | `f5c161658f1e0aa3` | `always` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-15` |
| `AL06-16` | 单个 atomic group 大于 Model 窗口时的产品行为 | A | `c635cefca2dacd76` | `always` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-16` |
| `AL06-17` | 系统 suspend/resume 后的活动请求处理 | A | `a8944615c65092e4` | `always` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-17` |
| `AL06-18` | 完整 response 中无效 tool batch 的接收结果 | A | `49517fbd52416bdc` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-18` |
| `AL06-19` | 模型协议纠错请求的自动次数 | A | `cb6f9f376df8818c` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-19` |
| `AL06-20` | queue 满时的新输入处理 | A | `8a7e10238d66eb6b` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-20` |
| `AL06-22` | side 的请求/token 预算归账 | A | `cbb22f66e166e5f0` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-22` |
| `AL06-23` | side 结果进入 main model view 的显式方式 | A | `451ca1c8cba864f0` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-23` |
| `AL06-24` | action-review verdict 的人工 override 范围 | A | `c91f82329471d53c` | `choice(AL06-07) in [A,B]` | `selected-with-exception` | custom:A corrected; finish review mandatory; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-24` |
| `AL06-25` | action-review 请求失败后的安全降级 | A | `e28e7fef11de56e7` | `choice(AL06-07) in [A,B]` | `selected-with-exception` | custom:A corrected; finish review mandatory; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-25` |
| `AL06-26` | termination-review 非 finish verdict 的控制流 | A | `f53c9899d08d3819` | `always` | `selected-with-exception` | custom:A corrected; finish review mandatory; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-26` |
| `AL06-27` | action/termination review 的预算池关系 | A | `268fb8d2898d2d31` | `always` | `selected-with-exception` | custom:A corrected; finish review mandatory; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-27` |
| `AL06-28` | 检测到无进展循环后的收口策略 | A | `e24e102251229c45` | `always` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-28` |
| `AL06-29` | 恢复时旧 Model 缺失的映射体验 | A | `364c9ed2e104fc8b` | `always` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-29` |
| `AL06-30` | compaction request 使用哪个 Model | A | `9c02a32e27b1c72a` | `choice(AL06-11) == A` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-30` |
| `AL06-31` | compaction schema 无效或无收益后的重试 | A | `e3ea9fd4e8a2adbd` | `choice(AL06-11) == A` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-31` |
| `AL06-32` | 崩溃后 unfinished main turn 的恢复边界 | A | `2850f7ab274ac08e` | `always` | `selected-with-exception` | custom:C + recent/full; `AS-006-14` | `B06/RB-006-01; RB-006-07` | `PR-006-AL06-32` |
| `AL06-33` | 多条 queue item 怎样组成后续 turn | A | `96bd6e8b7f1a1334` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-33` |
| `AL06-34` | 达到阈值后的 compaction 许可体验 | A | `4c70bb608c75287c` | `choice(AL06-11) == A` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-34` |
| `AL06-35` | Esc 在多活动面中的目标选择 | A | `87b8c49b0420e7d5` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-35` |
| `AL06-36` | `finish(partial)` 是否构成真实终态 | A | `402614dd6577a145` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-36` |
| `AL06-37` | 合法 mixed text + tool response 的展示与模型历史 | A | `72f98e4e8b48c6a1` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-37` |
| `AL06-38` | 普通无 control 回复怎样收口 | A | `e48dd601468ada72` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-38` |
| `AL06-39` | 手动 compaction 的生命周期 | A | `79e8e7571ace7921` | `choice(AL06-11) in [A,B]` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-39` |
| `AL06-40` | termination-review 进入人工解算后能否接受 finish | A | `a7d74ac13d9f5c25` | `always` | `selected-with-exception` | custom:A corrected; finish review mandatory; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-40` |
| `AL06-41` | termination-review 人工解算后能否重试 review | A | `389e473013bcb536` | `always` | `selected-with-exception` | custom:A corrected; finish review mandatory; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-41` |
| `AL06-42` | turn hard budget 是可配置还是发行版固定 | A | `e8736ffd3fcd75a6` | `always` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-42` |
| `AL06-43` | 本地金额估算怎样形成门 | A | `efd2fe936134b189` | `choice(M05-50) == C` | `not-applicable` | derived inactive: M05-50=A | `B06/RB-006-01` | `PR-006-AL06-43` |
| `AL06-44` | pending approval 是否随时间过期 | A | `52f3fbbc310447d1` | `always` | `selected-with-exception` | custom:A corrected; finish review mandatory; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-44` |
| `AL06-45` | 崩溃恢复后的 pending approval 怎样重新进入流程 | A | `5dd0b83c80f38361` | `always` | `selected-with-exception` | custom:A corrected; finish review mandatory; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-45` |
| `AL06-46` | 完成前默认承担多强的验证义务 | B | `e925c063ed3034dd` | `always` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-46` |
| `AL06-47` | 压缩摘要的查看与纠正入口 | A | `32043e0b9552a1b8` | `choice(AL06-11) in [A,B]` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-47` |
| `AL06-48` | 完整 model-yield 之后怎样继续 | A | `5961b9af4ae8ae14` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-48` |
| `AL06-49` | termination-review 使用哪个 Model | A | `5be1cf3224a777d1` | `always` | `selected-with-exception` | custom:A corrected; finish review mandatory; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-49` |
| `AL06-50` | stuck/no-progress 阈值的配置来源 | B | `b5cb1b7ac160f47c` | `always` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-AL06-50` |
| `AL06-51` | 特殊 purpose 跨 endpoint 的确认 cadence | C | `fa9bad854f4a44a6` | `always` | `selected-with-exception` | custom:A corrected; finish review mandatory; `AS-006-10` | `B06/RB-006-01` | `PR-006-AL06-51` |

### [TS：Tool、安全、进程与运行时](decision-packets/07-tools-safety-process-runtime.md)

| Group | Topic | Rec | Sem | Active when | State | Selection | Reply | Projection |
| --- | --- | :---: | --- | --- | --- | --- | --- | --- |
| `TS-02` | 首版 exact tool set | A | `0a406df68bb842dc` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-02` |
| `TS-04` | Permission 预设 | A | `3baadacd59c9a13d` | `always` | `selected-with-exception` | B; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-04` |
| `TS-05` | 人工授权记忆 | A | `0a504d3f4e583d2d` | `always` | `selected-with-exception` | B; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-05` |
| `TS-07` | direct file 的链接/特殊文件政策 | A | `320dae04692d72d1` | `always` | `selected-with-exception` | B; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-07` |
| `TS-08` | v0.1 undo 承诺 | A | `d09a495e02ccb4e3` | `always` | `selected-with-exception` | custom:A; no undo; backup Prompt only; `AS-006-13` | `B06/RB-006-01; RB-006-09` | `PR-006-TS-08` |
| `TS-10` | 工具并行 | A | `a8f7c4a36a01d92d` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-10` |
| `TS-11` | 是否提供 direct HTTP tool | A | `44ef8fa34e179702` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-11` |
| `TS-12` | unknown operation 的用户解算 | A | `1302b9d71496922b` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-12` |
| `TS-13` | Process/raw-shell 的方言来源 | A | `a3163a4dafdb677e` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-13` |
| `TS-14` | 威胁后果限制与 workspace 提醒 | A | `b6e6f8bd2542673a` | `always` | `selected-with-exception` | B; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-14` |
| `TS-16` | direct tool canonical result 的实际保留边界 | A | `6d7f444f2f3f765a` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-16` |
| `TS-17` | `list`/`search` 的首版精确语义 | A | `7976fe401f77be45` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-17` |
| `TS-18` | 是否再增加独立 Autonomy 模式 | A | `5904a3b9ed5e26cc` | `always` | `selected` | A; `AS-006-01` | `B06/RB-006-01` | `PR-006-TS-18` |
| `TS-19` | Git 是证据增强还是工作流控制 | A | `937f824a6b1bc299` | `always` | `selected-with-exception` | custom:A; no undo; backup Prompt only; `AS-006-13` | `B06/RB-006-01; RB-006-09` | `PR-006-TS-19` |
| `TS-20` | accepted tool batch 中途失败 | A | `89520f1a90600eba` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-20` |
| `TS-21` | `SensitiveRead` 的分类来源与求值规则 | A | `36182f902e6de9f6` | `choice(M05-56) == B` | `not-applicable` | derived inactive: M05-56=A | `B06/RB-006-01` | `PR-006-TS-21` |
| `TS-22` | stdout/stderr 的 canonical 跨通道顺序 | A | `11e71a85390d9a8e` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-22` |
| `TS-23` | raw shell 与 direct tool 的输入 schema 边界 | A | `f34f677dd2a1dc3e` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-23` |
| `TS-24` | foreground `exec` 何时算收口 | A | `4d65d6d08c92d918` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-24` |
| `TS-25` | direct `write` 的 create/replace 契约 | A | `c993ebff8ec7ea4e` | `choice(TS-02) in [A,C]` | `selected-with-exception` | custom:A; no undo; backup Prompt only; `AS-006-13` | `B06/RB-006-01; RB-006-09` | `PR-006-TS-25` |
| `TS-26` | direct `patch` 的输入方言 | A | `c0756872625f5144` | `choice(TS-02) in [A,C]` | `selected-with-exception` | custom:A; no undo; backup Prompt only; `AS-006-13` | `B06/RB-006-01; RB-006-09` | `PR-006-TS-26` |
| `TS-27` | direct `read` 的范围语义 | A | `4945a1fc9c68b1aa` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-27` |
| `TS-28` | direct `rename` 的目标冲突策略 | A | `1bb53bf36b84b20a` | `choice(TS-02) == A` | `selected-with-exception` | custom:A; no undo; backup Prompt only; `AS-006-13` | `B06/RB-006-01; RB-006-09` | `PR-006-TS-28` |
| `TS-29` | direct `rename` 的跨设备行为 | A | `b943736014143305` | `choice(TS-02) == A` | `selected-with-exception` | custom:A; no undo; backup Prompt only; `AS-006-13` | `B06/RB-006-01; RB-006-09` | `PR-006-TS-29` |
| `TS-30` | 是否提供一等 tracked background jobs | A | `5410958cff5a3c18` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-30` |
| `TS-31` | direct `delete` 是否允许递归目录树 | A | `9bd9901c15bd45cb` | `choice(TS-02) == A` | `selected-with-exception` | custom:A; no undo; backup Prompt only; `AS-006-13` | `B06/RB-006-01; RB-006-09` | `PR-006-TS-31` |
| `TS-32` | direct 文件的文本编码契约 | B | `0b9162635f1834b6` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-32` |
| `TS-33` | direct 二进制内容的读取表面 | A | `eb57b92ff55da5b0` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-33` |
| `TS-34` | direct 二进制文件的修改表面 | A | `1d3db01b8cac256f` | `choice(TS-02) in [A,C]` | `selected-with-exception` | custom:A; no undo; backup Prompt only; `AS-006-13` | `B06/RB-006-01; RB-006-09` | `PR-006-TS-34` |
| `TS-35` | direct 文件属性的保真与修改表面 | A | `1230eb94c7874c7f` | `choice(TS-02) in [A,C]` | `selected-with-exception` | custom:A; no undo; backup Prompt only; `AS-006-13` | `B06/RB-006-01; RB-006-09` | `PR-006-TS-35` |
| `TS-36` | `list`/`search` 的 ignore 与隐藏项政策 | A | `e6604df11411cc0c` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-36` |
| `TS-37` | `exec` 的 cwd 是否是逐调用状态 | A | `b12a67cb8a711e50` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-37` |
| `TS-38` | `exec` 输出怎样解码以及何时成为 binary | A | `75e788ea57d68632` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-38` |
| `TS-39` | `exec` canonical output 在上限内保留哪一部分 | A | `df16c6c852a2e01c` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-39` |
| `TS-40` | `__yaca__` reserved tree 的 direct exact-read 边界 | A | `ed04f7250e9c68c0` | `always` | `selected-with-exception` | B; `AS-006-12` | `B06/RB-006-01` | `PR-006-TS-40` |

### [CX：Context XML、索引与恢复](decision-packets/08-context-xml-index-recovery.md)

| Group | Topic | Rec | Sem | Active when | State | Selection | Reply | Projection |
| --- | --- | :---: | --- | --- | --- | --- | --- | --- |
| `CX-01` | 单 XML 的物理提交路线 | A | `804ac1bdefbe31fd` | `always` | `selected` | A; `AS-006-14` | `B06/RB-006-01` | `PR-006-CX-01` |
| `CX-02` | “复制 XML 接盘”与第三方写入边界 | A | `6b90f0a514b9d1b3` | `always` | `selected-with-exception` | B; `AS-006-14` | `B06/RB-006-01` | `PR-006-CX-02` |
| `CX-05` | temp、lock、previous-valid 与 recovery 默认动作 | A | `228e8851b12f3254` | `always` | `selected` | A; `AS-006-14` | `B06/RB-006-01` | `PR-006-CX-05` |
| `CX-07` | 外来 XML 信任、approval 与 import mapping | A | `2821ea411a409625` | `always` | `selected-with-exception` | B; `AS-006-14` | `B06/RB-006-01` | `PR-006-CX-07` |
| `CX-08` | 16 字符 hash 使用哪个可见字母表 | A | `168b53f8e105abc3` | `always` | `selected-with-exception` | custom:C + recent/full; `AS-006-14` | `B06/RB-006-01; RB-006-07` | `PR-006-CX-08` |
| `CX-09` | context-repl 搜索、浏览与 stale selection | A | `2014193d2f856fe3` | `always` | `selected-with-exception` | custom:C + recent/full; `AS-006-14` | `B06/RB-006-01; RB-006-07` | `PR-006-CX-09` |
| `CX-10` | rename、路径/hash 与活动 writer | A | `481396fe0c34657d` | `always` | `selected-with-exception` | custom:C + recent/full; `AS-006-14` | `B06/RB-006-01; RB-006-07` | `PR-006-CX-10` |
| `CX-11` | quota、保留与单 XML 硬门 | A | `ee0111d03cdbde78` | `always` | `selected` | A; `AS-006-14` | `B06/RB-006-01` | `PR-006-CX-11` |
| `CX-13` | 第二 writer 遇到活动 Context 时怎样收口 | A | `2a144c6fee37a2ed` | `always` | `selected` | B；显示可证明 PID/unknown，`AS-002-08` | `B02/RB-002-02` | `PR-002-08` |
| `CX-14` | 导入后 Permission/DoubleCheck 安全覆盖怎样激活 | A | `7df0efe61f611860` | `always` | `selected-with-exception` | B; `AS-006-14` | `B06/RB-006-01` | `PR-006-CX-14` |
| `CX-15` | archive、trash/restore 与 purge 哪些进入 v0.1 | A | `afe5ce58f29062fa` | `always` | `selected-with-exception` | custom:C + recent/full; `AS-006-14` | `B06/RB-006-01; RB-006-07` | `PR-006-CX-15` |
| `CX-16` | Context XML 明文、OS 权限与第三方 reader 的隐私边界 | A | `0cad962e5024b6a6` | `always` | `selected-with-exception` | B; `AS-006-14` | `B06/RB-006-01` | `PR-006-CX-16` |
| `CX-17` | 导入后 ContextPrompt 怎样激活 | A | `1134c6e6b6d89810` | `always` | `selected-with-exception` | B; `AS-006-14` | `B06/RB-006-01` | `PR-006-CX-17` |
| `CX-18` | compatibility gap 的继续门 | B | `18e4febcc65328c2` | `always` | `selected-with-exception` | B; `AS-006-14` | `B06/RB-006-01` | `PR-006-CX-18` |
| `CX-19` | context-repl 的 landing | A | `4435564284c66b7c` | `always` | `selected-with-exception` | custom:C + recent/full; `AS-006-14` | `B06/RB-006-01; RB-006-07` | `PR-006-CX-19` |
| `CX-20` | active XML 外部移动、替换或改写后的恢复 | A | `1a83fcfef67ffd47` | `always` | `selected-with-exception` | custom:C + recent/full; `AS-006-14` | `B06/RB-006-01; RB-006-07` | `PR-006-CX-20` |

### [ED：错误、诊断与兼容体验](decision-packets/09-errors-diagnostics-compatibility.md)

| Group | Topic | Rec | Sem | Active when | State | Selection | Reply | Projection |
| --- | --- | :---: | --- | --- | --- | --- | --- | --- |
| `ED-01` | 稳定 error ID 的兼容粒度 | A | `32a933435c5857cf` | `always` | `selected-with-exception` | custom:A outcome; ED-07=C; `AS-006-15` | `B06/RB-006-01` | `PR-006-ED-01` |
| `ED-02` | severity 与 waiting-user | A | `b1632224a9cd07f4` | `always` | `selected-with-exception` | custom:A outcome; ED-07=C; `AS-006-15` | `B06/RB-006-01` | `PR-006-ED-02` |
| `ED-03` | 同一根因显示几次 | A | `53d501254e72207d` | `always` | `selected-with-exception` | custom:A outcome; ED-07=C; `AS-006-15` | `B06/RB-006-01` | `PR-006-ED-03` |
| `ED-04` | Retry 的可见与取消 | A | `75178606540cae45` | `always` | `selected-with-exception` | custom:A outcome; ED-07=C; `AS-006-15` | `B06/RB-006-01` | `PR-006-ED-04` |
| `ED-05` | Ctrl+C、EOF、broken pipe 与 graceful-exit action | A | `631c4ffb1d161ed5` | `always` | `selected-with-exception` | custom:A outcome; ED-07=C; `AS-006-15` | `B06/RB-006-01` | `PR-006-ED-05` |
| `ED-06` | 持久化失败 | A | `f3ddd5f9a3057eb6` | `always` | `selected-with-exception` | custom:A outcome; ED-07=C; `AS-006-15` | `B06/RB-006-01` | `PR-006-ED-06` |
| `ED-07` | support 输出的本地内容与生成形态 | A | `83a0e39f256efc0f` | `always` | `selected-with-exception` | custom:A outcome; ED-07=C; `AS-006-15` | `B06/RB-006-01` | `PR-006-ED-07` |
| `ED-08` | English UI 与 Unicode 数据 | A | `938ca9e8b63db55d` | `always` | `selected-with-exception` | custom:A outcome; ED-07=C; `AS-006-15` | `B06/RB-006-01` | `PR-006-ED-08` |
| `ED-09` | terminal control 与能力降级 | A | `891dce9bf5852fa1` | `always` | `selected-with-exception` | custom:A outcome; ED-07=C; `AS-006-15` | `B06/RB-006-01` | `PR-006-ED-09` |
| `ED-10` | error 详情交互 | A | `ab7cfa3cd93d64f4` | `always` | `selected-with-exception` | custom:A outcome; ED-07=C; `AS-006-15` | `B06/RB-006-01` | `PR-006-ED-10` |
| `ED-11` | Context 建立前或 writer 已 faulted 时的崩溃报告 | A | `74c8613f749a685d` | `always` | `selected-with-exception` | custom:A outcome; ED-07=C; `AS-006-15` | `B06/RB-006-01` | `PR-006-ED-11` |
| `ED-12` | 多阶段或 batch 的部分成功怎样显示 | A | `f2e9c3a93df74e29` | `always` | `selected-with-exception` | custom:A outcome; ED-07=C; `AS-006-15` | `B06/RB-006-01` | `PR-006-ED-12` |
| `ED-13` | Aggregate telemetry 的发送策略 | A | `21de2edecc160542` | `always` | `selected-with-exception` | custom:A outcome; ED-07=C; `AS-006-15` | `B06/RB-006-01` | `PR-006-ED-13` |
| `ED-14` | 是否提供一次性诊断上传 | A | `70cae0b3a0e9d066` | `choice(ED-07) in [A,B]` | `not-applicable` | derived inactive: ED-07=C | `B06/RB-006-01` | `PR-006-ED-14` |

### [RF：发布、测试与冻结](decision-packets/10-release-testing-and-readiness-freeze.md)

| Group | Topic | Rec | Sem | Active when | State | Selection | Reply | Projection |
| --- | --- | :---: | --- | --- | --- | --- | --- | --- |
| `RF-01` | zip 的正式程序入口 | A | `87a1aa2243b40359` | `always` | `selected-with-exception` | custom:portable adjacent-data layout; `AS-006-16` | `B06/RB-006-01; RB-006-05/07` | `PR-006-RF-01` |
| `RF-02` | `__yaca__` 数据根与多副本规则 | A | `38fb484799a8234c` | `always` | `selected-with-exception` | custom:portable adjacent-data layout; `AS-006-16` | `B06/RB-006-01; RB-006-05/07` | `PR-006-RF-02` |
| `RF-03` | 升级、降级、迁移与卸载 | A | `3aa7ff170df021b5` | `always` | `selected-with-exception` | custom:portable adjacent-data layout; `AS-006-16` | `B06/RB-006-01; RB-006-05/07` | `PR-006-RF-03` |
| `RF-04` | luainstaller Win32/x86/XP 前置 | A | `64568e7832830a53` | `always` | `selected` | A; `AS-006-17` | `B06/RB-006-01` | `PR-006-RF-04` |
| `RF-05` | 依赖 allowlist、现有 `bin/` 与 UPX | A | `71b3a08b9ccf9a5b` | `always` | `selected` | A; `AS-006-17` | `B06/RB-006-01; RB-006-06` | `PR-006-RF-05` |
| `RF-06` | 公开发布完整性材料 | A | `dee5aa28d1b7e2b9` | `always` | `selected` | A; `AS-006-17` | `B06/RB-006-01; RB-006-06` | `PR-006-RF-06` |
| `RF-08` | “每个平台完整测试”的放行语义 | A | `d4f4e2e696c5852f` | `always` | `selected` | A; `AS-006-17` | `B06/RB-006-01; RB-006-06` | `PR-006-RF-08` |
| `RF-09` | 跨平台性能预算采用什么结构 | A | `aeea3fb690c2a618` | `always` | `selected` | A; `AS-006-17` | `B06/RB-006-01; RB-006-06` | `PR-006-RF-09` |
| `RF-10` | 故障注入与长会话 soak 的执行节奏 | A | `59a447ffd65f8236` | `always` | `selected` | A; `AS-006-17` | `B06/RB-006-01; RB-006-06` | `PR-006-RF-10` |
| `RF-11` | readiness 证据保留期 | A | `c7b64bdb5383d42b` | `always` | `selected` | A; `AS-006-17` | `B06/RB-006-01; RB-006-06` | `PR-006-RF-11` |
| `RF-12` | 项目维护到哪一层 Model fixture/adapter support contract | A | `ca74eb0765562f08` | `always` | `selected` | A; `AS-006-17` | `B06/RB-006-01; RB-006-06` | `PR-006-RF-12` |
| `RF-14` | Windows x86 发行包的 CPU ISA 基线 | A | `e81dfaaf35c82ab2` | `always` | `selected` | A; `AS-006-17` | `B06/RB-006-01` | `PR-006-RF-14` |
| `RF-15` | Release 来源身份签名 | A | `f9d9b20e49943362` | `always` | `selected` | A; `AS-006-17` | `B06/RB-006-01; RB-006-06` | `PR-006-RF-15` |
| `RF-16` | 更新发现与下载策略 | A | `c0a20dbe564530b4` | `always` | `selected` | A; `AS-006-17` | `B06/RB-006-01; RB-006-06` | `PR-006-RF-16` |

### [F4：跨系统运行接缝](decision-packets/11-cross-system-operational-seams.md)

| Group | Topic | Rec | Sem | Active when | State | Selection | Reply | Projection |
| --- | --- | :---: | --- | --- | --- | --- | --- | --- |
| `F4-01` | 运行中外部修改配置何时生效 | A | `94605c4d516c0bca` | `always` | `selected-with-exception` | custom：每个新顶层 turn 自动观察并完整载入有效变化；`AS-004-09` | `B04/RB-004-10` | `PR-011-01` |
| `F4-02` | 同一个 Model 的并发、请求间隔与冷却 | B | `02d33e038aef29f5` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-F4-02` |
| `F4-03` | 回答 `ask-user` 是旧 turn 继续还是新 turn | B | `2162b655a66da60f` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-F4-03` |
| `F4-04` | 用户主动 retry 到底重试什么 | B | `445fdae91ae5827e` | `always` | `selected` | A; `AS-006-11` | `B06/RB-006-01` | `PR-006-F4-04` |
| `F4-05` | 未发送 draft 是否属于“完整 Context” | A | `821a6749b9f76a3c` | `always` | `selected-with-exception` | custom:A + text fallbacks/queue management; `AS-006-04` | `B06/RB-006-01` | `PR-006-F4-05` |
| `F4-06` | history 与 details 语义动作能恢复到什么程度 | B | `5109de4985db3675` | `always` | `selected-with-exception` | custom:A + text fallbacks/queue management; `AS-006-04` | `B06/RB-006-01` | `PR-006-F4-06` |
| `F4-07` | 模型 raw `exec` 的 stdin 来源 | A | `7e9ecd4b2be0f86e` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-F4-07` |
| `F4-08` | Context 误存秘密后提供哪种删除承诺 | A | `6a6aec088db43be8` | `always` | `selected-with-exception` | custom:C + recent/full; `AS-006-14` | `B06/RB-006-01; RB-006-07` | `PR-006-F4-08` |
| `F4-09` | config/model/context 的破坏动作是否共用管理事务 | B | `9a522c6fb37540ff` | `always` | `selected-with-exception` | custom:A + text fallbacks/queue management; `AS-006-04` | `B06/RB-006-01` | `PR-006-F4-09` |
| `F4-10` | Context 数据根与 workspace 的文件系统保证 | B | `da333ce95e2924f0` | `always` | `selected` | A; `AS-006-14` | `B06/RB-006-01` | `PR-006-F4-10` |
| `F4-11` | raw shell 命令超过长度或编码边界时怎么办 | A | `b246aaa0ad211bf0` | `always` | `selected` | A; `AS-006-12` | `B06/RB-006-01` | `PR-006-F4-11` |
| `F4-12` | active turn 中工作目录消失或变成另一个对象 | A | `5a7b5d879b3778a7` | `always` | `selected` | A; `AS-006-03` | `B06/RB-006-01` | `PR-006-F4-12` |
| `F4-14` | 传入目录与上级 Git 根怎样确定工作区边界 | A | `aa895c355908621c` | `always` | `selected` | A; `AS-006-03` | `B06/RB-006-01` | `PR-006-F4-14` |
| `F4-15` | 同一进程的 active Context 数量 | A | `75b94d32290b9d71` | `always` | `selected` | A; `AS-006-03` | `B06/RB-006-01` | `PR-006-F4-15` |
| `F4-16` | 一个 Context 可积累几个 pending question | A | `fe724daceb92ffba` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-F4-16` |
| `F4-17` | 普通 Enter 怎样与 pending question 绑定 | A | `0d3ee868a5bb730c` | `always` | `selected` | A; `AS-006-10` | `B06/RB-006-01` | `PR-006-F4-17` |

## 稀疏 assertion、冲突与重新打开记录

只有出现自然语言偏离、例外、冲突或 supersede 时才新增记录，避免为 270 个未答项制造空表。每条至少使用下面字段：

```text
assertion_id
group_id
reply_ref
exact_owner_wording
normalized_assertion
kind                  product / experience / safety / technical-target / constant
supersedes
conflicts_with
reopens
decision_refs
owner_spec_refs
gate_and_proof_refs
propagation_status
```

各批原话与完整 normalized wording 由 [`DISCUSSION-BATCH-02.md`](DISCUSSION-BATCH-02.md)、[`DISCUSSION-BATCH-03.md`](DISCUSSION-BATCH-03.md) 和 [`DISCUSSION-BATCH-04.md`](DISCUSSION-BATCH-04.md) 唯一保存；下表是 lifecycle/owner 索引，不复制第二份略有不同的断言正文。

| Assertion | Group | Reply / exact wording / normalized assertion | Kind | Supersedes | Conflicts / reopens | Decision | Owner / gate-proof | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `AS-002-01` | PJ-01 | `B02/RB-002-01/02`; `DISCUSSION-BATCH-02#as-002-01` | experience/constant | — | master portion superseded by AS-004-01; field toggles retained | D-040 | `14-tui`; AR-P0-05/13 | partial supersede; TU proof pending |
| `AS-002-02` | PJ-02 | `B02/RB-002-02`; `#as-002-02` | product/safety | — | — | D-031 | `05-configuration`; AR-P0-09 | propagated |
| `AS-002-03` | PJ-03 | `B02/RB-002-02`; `#as-002-03` | product/safety | — | — | D-031/D-039 | `05-configuration`; AR-P0-09/P1-07 | propagated |
| `AS-002-04` | PJ-04 | `B02/RB-002-01/02`; `#as-002-04` | product/experience | — | — | D-040 | `00-product`; AR-P0-01 | propagated |
| `AS-002-05` | PJ-05 | `B02/RB-002-02`; `#as-002-05` | product/safety | — | — | D-040 | `10-context-storage`; AR-P0-10 | propagated |
| `AS-002-06` | PJ-12 | `B02/RB-002-01/02`; `#as-002-06` | product/constant/technical-target | `RB-002-01` exit-trigger alternatives | manual-name precedence closed by AS-003-02/D-046 | D-041/D-046 | `11-context-indexing`; AR-P0-11; platform RNG/no-replace proof pending | design propagated; proof pending |
| `AS-002-07` | PJ-06/PJ-08 | `B02/RB-002-02`; `#as-002-07` | product/experience | independent recovery surface candidate | — | D-042 | `00-product`; AR-P0-01/13 | propagated |
| `AS-002-08` | CX-13 | `B02/RB-002-02`; `#as-002-08` | safety/experience | read-only second-open candidate | — | D-041 | `10-context-storage`; AR-P0-15 | proof pending |
| `AS-002-09` | PJ-13 | `B02/RB-002-02`; `#as-002-09` | product/safety | AutoJumpToDir/ResumeDirectory candidates | — | D-041 | `10-context-storage`; AR-P0-10/11 | propagated |
| `AS-002-10` | PJ-09 | `B02/RB-002-02`; `#as-002-10` | product/experience | in-chat REPL candidates | — | D-042 | `00-product`; AR-P0-13 | propagated |
| `AS-002-11` | PJ-10 | `B02/RB-002-02`; `#as-002-11` | product/safety | — | — | D-042 | `22-runtime`; AR-P0-02/15 | deadline proof pending |
| `AS-002-12` | PJ-11 | `B02/RB-002-02`; `#as-002-12` | product | plan-state candidates | — | D-042 | `00-product`; AR-P1-05 | propagated |
| `AS-002-13` | PJ-11 | `B02/RB-002-02`; `#as-002-13` | safety/product | — | PP-03/TS-04 detail remains open | D-034/D-043 | `08-permission`; AR-P0-06/P1-05 | pending downstream choices |
| `AS-002-14` | PJ-14/15/16/17/19/20 | `B02/RB-002-02`; `#as-002-14` | product/safety | old Web/media/remote candidates | — | D-044 | `00-product` + per-capability exclusion owner; zero-surface gates | propagated design / release proof pending |
| `AS-002-15` | PJ-03 | `B02/RB-002-02`; `#as-002-15` | product/technical-target | — | TU-18 argv spelling remains open | D-031 | `13-cli`; AR-P0-13/P1-07 | semantic action propagated |
| `AS-003-01` | PJ-18/PJ-13 | `B03/RB-003-01`; `DISCUSSION-BATCH-03#as-003-01` | product/storage-address/safety | multi-root and XML current-workdir candidates | — | D-045 | `00-product`; AR-P0-01/10/11; TP-011/012/014 | owner propagated; physical proof pending |
| `AS-003-02` | PJ-12 | `B03/RB-003-01/02`; `DISCUSSION-BATCH-03#as-003-02` | product/configuration/context-metadata | open manual-name precedence | — | D-046 | `11-context-indexing`; AR-P0-10/11; TP-016/018/019 | owner/schema propagated; proof pending |
| `AS-004-01` | PJ-01 | `B04/RB-004-02`; `DISCUSSION-BATCH-04#as-004-01` | product/experience/configuration | AS-002-01 startup master | — | D-040 | `14-tui`; AR-P0-05/09/13; TP-023/024 | owner/schema propagated; golden proof pending |
| `AS-004-02` | TU-32/PJ-09 | `B04/RB-004-03`; `DISCUSSION-BATCH-04#as-004-02` | product/experience/constant | compact `.use model` route | completion key/algorithm remains open | D-042 | `13-cli`; AR-P0-13; TP-024 | owner/TUI propagated; state/terminal proof pending |
| `AS-004-03` | PJ-02/PJ-03 | `B04/RB-004-04`; `DISCUSSION-BATCH-04#as-004-03` | product/technical-target/compatibility | narrow config-only Stage 1 interpretation | — | D-031 | `15-diagnostics`; AR-P1-07; TP-026 | owner/gate propagated; check IDs/proof pending |
| `AS-004-04` | self-test/Permission | `B04/RB-004-06`; `DISCUSSION-BATCH-04#as-004-04` | product/experience/safety | — | M05-12 reviewer source remains open | D-031/D-034 | `15-diagnostics`; AR-P0-06/P1-07; TP-026 | owner/data gate propagated; reviewer choice/proof pending |
| `AS-004-05` | CLI/TUI | `B04/RB-004-06`; `DISCUSSION-BATCH-04#as-004-05` | product/architecture/compatibility | per-surface duplicate actions | non-TTY/machine grammar remains TU-13/18/21/23 | D-042 | `13-cli`; AR-P0-13; TP-024 | owner/runtime invariant propagated; grammar/proof pending |
| `AS-004-06` | PJ-04/Catalog | `B04/RB-004-07`; `DISCUSSION-BATCH-04#as-004-06` | product/experience/configuration | fixed one-order Context rows | CX-19 landing remains open | D-047 | `11-context-indexing`; AR-P0-09/11; TP-013/019/024 | owner/schema propagated; timestamp/old-platform proof pending |
| `AS-004-07` | PJ-13 | `B04/RB-004-09`; `DISCUSSION-BATCH-04#as-004-07` | product/safety | AutoJumpToDir/ResumeDirectory candidates | invocation directory cannot silently rebind old Context | D-045 | `00-product`; AR-P0-11; TP-011/014 | reaffirmed; proof pending |
| `AS-004-08` | CX-13/PJ-09 | `B04/RB-004-10`; `DISCUSSION-BATCH-04#as-004-08` | product/safety/concurrency | editing an active externally locked Context | CX-10 exact managed-rename lifecycle remains open | D-041 | `10-context-storage`; AR-P0-10/15; TP-008/018 | owner/action matrix propagated; lock proof pending |
| `AS-004-09` | F4-01 | `B04/RB-004-10`; `DISCUSSION-BATCH-04#as-004-09` | product/architecture/safety | explicit-only or confirm-on-change reload | — | D-048 | `05-configuration`; AR-P0-09; TP-019/020 | owner/runtime/schema propagated; performance/fault proof pending |
| `AS-004-10` | Permission/DoubleCheck | `B04/RB-004-05/11`; `DISCUSSION-BATCH-04#as-004-10` | design-directive/open-followup | — | “目标” meaning remains open | pending:AL06/Permission choice | pending:owner after clarification | pending question design |

## 稀疏传播记录

除 `unanswered` 外每个组都必须有独立 `PR-*`；即使当前只是讲解、暂缓、被取代或冲突，也不能把“此时没有规格投影”和“忘记传播”都写成空白。记录格式固定为：

```text
projection_id:
group_id:
decision_refs:           D-*，或 pending:<reason> / n/a:<reason> / conflict:<CR-*>
owner_spec_ref:          恰好一个稳定 owner anchor，或 pending:<reason>
consumer_spec_refs:      零到多个明确 consumer anchor，或 pending:<reason>
gate_refs:
test_refs:
condition_basis_reply:   条件组必填；普通组 n/a
no_projection_evidence:  not-applicable 必填，证明 config/XML/CLI/TUI/Runtime/test 无空壳
lifecycle_refs:          superseded/conflict 必填新旧双方或 CR；其他 n/a
propagation_status:      pending | complete | conflict
```

`decision_refs` 和其他 ref 字段都可用 `pending:<reason>`、`n/a:<reason>` 或 `conflict:<CR-*>`；`owner_spec_ref` 只有在现行行为真正产生时才必须恰好一个 owner anchor。各 state 的唯一要求为：

| State | PR 中的决定/owner 要求 | `propagation_status` |
| --- | --- | --- |
| `unanswered` | 不建 PR；主表 `Projection=—` | n/a |
| `explaining` | `decision_refs=n/a:awaiting-selection`；owner/consumer/gate/test 为 `n/a:no-current-projection` | `pending` |
| `selected` / `selected-with-exception` | D 与恰好一个 owner；尚在传播时使用带原因的 `pending` | `pending` 或 `complete`；发现冲突则先转组 state |
| `deferred` | 若已正式移出 v0.1/冻结安全默认，引用 D 与 owner；否则使用 `pending:deferred` 和 `n/a:no-current-projection` | `pending` 或 `complete` |
| `excluded` | 引用非目标 D 和恰好一个 owner 中的 unsupported/re-entry 契约 | `pending` 或 `complete` |
| `not-applicable` | `decision_refs=n/a:derived-from-upstream`；`owner_spec_ref=n/a:inactive-branch`；必填 condition basis 和 no-projection evidence | `complete` |
| `technical-proof` | 引用已定产品保证、唯一 owner、proof/gate/test 和失败退路 | `pending` 或 `complete` |
| `superseded` | 保留旧 D/owner 历史引用，`lifecycle_refs` 指向新 D/PR；不生成新现行 owner | `complete` |
| `conflict` | `decision_refs=conflict:<CR-*>`，owner/consumer/gate/test 为带原因的 `pending`，`lifecycle_refs` 引用双方 | `conflict` |

### B02/B03/B04 独立传播记录

`condition`、`no-projection` 与 `lifecycle` 分别对应固定格式中的 `condition_basis_reply`、`no_projection_evidence` 和 `lifecycle_refs`。`n/a:active` 表示该字段只对 inactive branch 有意义，不表示漏填。

| PR | Group | Decision | Exactly one owner spec | Consumer specs | Gates | Tests | Condition | No-projection | Lifecycle | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `PR-002-01` | PJ-01 | D-040 | `subsystems/14-tui.md#上游给出的简洁启动头常量` | `CONFIG-SCHEMA-CANDIDATE.md#tui`; `00-product#正常启动契约` | AR-P0-05/09/13 | pending:no-master/independent-field startup golden transcripts | n/a | n/a:active | AS-004-01 supersedes AS-002-01 master only | design propagated; golden proof pending |
| `PR-002-02` | PJ-02 | D-031 | `subsystems/05-configuration.md#三阶段-self-test-与配置关系` | `13-cli#bootstrap 与独立管理入口`; `00-product#正常启动契约` | AR-P0-09/13 | pending:bootstrap command matrix | n/a | n/a:active | n/a | pending:downstream M05/TU choices |
| `PR-002-03` | PJ-03 | D-031/D-039 | `subsystems/05-configuration.md#三阶段-self-test-与配置关系` | `CONFIG-SCHEMA-CANDIDATE#general`; `13-cli#self-test semantic action`; `15-diagnostics#three-stage-self-test` | AR-P0-09; AR-P1-07 | pending:Context catalog/performance + Permission semantic advisory matrix | n/a | n/a:active | n/a | design propagated; exact M05 reviewer/check choices and TP-026 proof pending |
| `PR-002-04` | PJ-04 | D-040/D-047 | `subsystems/11-context-indexing.md#交互式上下文浏览器` | `subsystems/00-product-and-compatibility.md#正常启动契约`; `CONFIG-SCHEMA-CANDIDATE.md#context`; `22-application-runtime-and-concurrency#启动顺序候选` | AR-P0-01/09/11 | pending:TP-013/019/024 zero-scan startup + created/updated/name × direction + LogicalPath ascending tie-break vectors | n/a | n/a:active | n/a | design propagated; physical timestamp/sort proof pending |
| `PR-002-05` | PJ-05 | D-040 | `subsystems/10-context-storage.md#已确认的新-context-建立与打开边界` | `00-product#新-context-的创建与命名`; `22-runtime#启动顺序候选` | AR-P0-10 | pending:first-message crash/fault matrix | n/a | n/a:active | n/a | pending:CX physical commit choices |
| `PR-002-06` | PJ-12 | D-041/D-046 | `subsystems/11-context-indexing.md#初始名称与周期命名` | `CONFIG-SCHEMA-CANDIDATE#context`; `DATA-CLASSIFICATION#context-name已确认的周期后台-purpose`; `10-context-storage#已确认的新-context-建立与打开边界` | AR-P0-10/11; AR-P1-09 | pending:RNG/collision/manual-rename marker/toggle/new-baseline/inflight-late-result vectors | n/a | n/a:active | n/a | design/schema propagated; physical vectors pending |
| `PR-002-07` | PJ-06 | D-042 | `subsystems/00-product-and-compatibility.md#单一-workspace-root-与显式-context-管理` | `13-cli#bootstrap 与独立管理入口`; `10-context-storage#导入信任边界` | AR-P0-01/13/15 | pending:self-fix routing matrix | n/a | n/a:active | n/a | pending:exact REPL command choices |
| `PR-002-08` | CX-13 | D-041 | `subsystems/10-context-storage.md#已确认的新-context-建立与打开边界` | `00-product#单一-workspace-root-与显式-context-管理`; `13-cli#bootstrap 与独立管理入口`; `22-runtime#并发基线候选` | AR-P0-10/15 | pending:XP/Linux active/stale-lock + zero-management-mutation proof | n/a | n/a:active | AS-004-08 narrows active-lock edit surface | pending:CX lock format/proof |
| `PR-002-09` | PJ-08 | D-042 | `subsystems/00-product-and-compatibility.md#单一-workspace-root-与显式-context-管理` | `13-cli#bootstrap 与独立管理入口`; `14-tui#需要逐项确认的体验` | AR-P0-01/13 | pending:six-surface navigation/help matrix | n/a | n/a:active | n/a | pending:exact CLI/TUI grammar |
| `PR-002-10` | PJ-13 | D-041/D-045/D-057 | `subsystems/00-product-and-compatibility.md#单一-workspace-root-与显式-context-管理` | `10-context-storage#已确认的新-context-建立与打开边界`; `11-context-indexing#镜像布局与-hash-输入`; `22-runtime#启动顺序候选` | AR-P0-10/11 | pending:mirror-parent identity/rebind/cross-machine matrix | n/a | n/a:active | n/a | design propagated; F4-14=A confirmed, physical proof pending |
| `PR-002-11` | PJ-09 | D-042 | `subsystems/00-product-and-compatibility.md#单一-workspace-root-与显式-context-管理` | `13-cli#bootstrap 与独立管理入口`; `14-tui#需要逐项确认的体验` | AR-P0-13 | pending:chat-command/top-level registry + active-lock action matrix | n/a | n/a:active | TU-32 closed separately by PR-004-01 | pending:TU-18 and remaining state choices |
| `PR-002-12` | PJ-10 | D-042 | `subsystems/00-product-and-compatibility.md#退出承诺` | `22-application-runtime-and-concurrency#关闭顺序候选` | AR-P0-02/15 | pending:close deadline/unknown fault matrix | n/a | n/a:active | n/a | pending:AL/ED close details |
| `PR-002-13` | PJ-11 | D-042/D-043 | `subsystems/00-product-and-compatibility.md#v01-的简单完整产品形态` | `08-permission-and-safety#命名-typed-profile-与-systemprompt`; `18-prompt#permission-systemprompt-的候选位置` | AR-P0-06; AR-P1-05 | pending:no-plan registry + Permission prompt enforcement | n/a | n/a:active | n/a | pending:PP-03/TS-04 details |
| `PR-002-14` | PJ-14 | D-044 | `subsystems/17-web.md#生效的产品结论` | `00-product#v01-的简单完整产品形态`; config/CLI/TUI/release zero-surface consumers | AR-P0-01/04/05/16 | pending:final zip zero-Web scan | n/a | n/a:active | n/a | pending:release proof |
| `PR-002-15` | PJ-15 | D-044 | `subsystems/00-product-and-compatibility.md#v01-的简单完整产品形态` | config/CLI/TUI/Model/tool/XML/release zero-image consumers | AR-P0-01/03/05/08/16 | pending:zero-image/clipboard-media scan | n/a | n/a:active | n/a | pending:release proof |
| `PR-002-16` | PJ-16 | D-044 | `subsystems/00-product-and-compatibility.md#v01-的简单完整产品形态` | config/CLI/TUI/Model/tool/XML/release zero-audio consumers | AR-P0-01/03/05/08/16 | pending:zero-audio/device/codec scan | n/a | n/a:active | n/a | pending:release proof |
| `PR-002-17` | PJ-17 | D-044 | `subsystems/00-product-and-compatibility.md#v01-的简单完整产品形态` | config/CLI/TUI/Runtime/network/release zero-controller consumers | AR-P0-01/04/05/16 | pending:zero-listener/IPC/RPC scan | n/a | n/a:active | n/a | pending:release proof |
| `PR-002-18` | PJ-19 | n/a:derived-from-PJ-16=A | n/a:inactive-branch | n/a:no-current-consumer | n/a:inactive | n/a:negative registry scan owned by D-044 | `B02/RB-002-02; PJ-16=A` | D-044 requires zero transcription command/purpose/config/XML/artifact/Runtime surface | n/a | complete |
| `PR-002-19` | PJ-20 | D-044 | `subsystems/00-product-and-compatibility.md#v01-的简单完整产品形态` | config/CLI/TUI/Model/XML/release zero-TTS consumers | AR-P0-01/03/05/08/16 | pending:zero-speech/device/codec scan | n/a | n/a:active | n/a | pending:release proof |
| `PR-002-20` | PJ-18 | D-045/D-057 | `subsystems/00-product-and-compatibility.md#单一-workspace-root-与显式-context-管理` | `10-context-storage#已确认的总体形态与剩余语义`; `11-context-indexing#镜像布局与-hash-输入`; `13-cli#主指令`; `22-runtime#启动顺序候选` | AR-P0-01/10/11; AR-P1-03 | pending:single-root/no-root-list/mirror-parent/rebind/hash vectors | n/a | n/a:active | n/a | design propagated; F4-14=A confirmed, physical proof pending |
| `PR-004-01` | TU-32 | D-042 | `subsystems/13-cli.md#chat-内-model-选择` | `14-tui#model-picker`; `06-model-protocols#capability-preflight 与兼容性结果` | AR-P0-05/13 | pending:picker/direct-selector/completion/narrow-terminal/state parity | n/a | n/a:active | n/a | design propagated; TU state choices and TP-024 proof pending |
| `PR-011-01` | F4-01 | D-048 | `subsystems/05-configuration.md#配置-generation-与逐-turn-自动载入` | `subsystems/22-application-runtime-and-concurrency.md#config-generation-与逐-turn-载入`; `CONFIG-SCHEMA-CANDIDATE#配置-generation-与运行中-reload` | AR-P0-09; AR-P1-03 | pending:per-turn bytes/digest/atomic-generation/invalid-current-mapping/XP latency matrix | n/a | n/a:active | n/a | design propagated; TP-019/020 fault/performance proof pending |

一个答复批次只有在每个非 unanswered 组都引用 PR、PR 的每个字段为真实引用或带原因的 typed sentinel、且所有产生现行行为的组都能机械计数为恰好一个 owner 时才能关闭。Batch 02 至 04 使用下方稀疏 PR 表；Batch 06 的 248 条确定性展开由 [`DECISION-PROJECTION-BATCH-06.md`](DECISION-PROJECTION-BATCH-06.md) 保存，并与主表 `Projection` 一一对应。`selected` 只表示负责人选择已捕获；`propagation_status=complete` 才表示决定、owner、consumer、gate/test 已完成设计传播。

## 机械一致性门

每次更新至少证明：

- 十包正式 group 集合 = 推荐模板集合 = 本表集合 = 270，且逐包分布仍为 `19/18/32/57/49/35/16/14/14/16`。
- 本表 `Rec` 与包内推荐模板一致；inventory canonical stream 覆盖完整选项 section、推荐、条件和关联，重算后与登记 digest 一致。
- 384 个 checklist ID、`AQ-001..AQ-437`、`D-001..D-057`、配置文件声明的连续 `CV-*`、`TP-001..TP-030` 连续性/唯一性符合各自契约；历史审计快照不因 live 数量更新而被改写。
- 状态计数等于 270；任何 `selected*` 都有原话和选择，任何 `not-applicable` 都有成立的上游条件及无投影结果。
- D、spec、test、gate 引用真实存在；一项现行保证只有一个 owner，consumer 不复制另一份略有差异的枚举或默认。
- 没有把候选/推荐写成已实现事实，没有开始实现代码。

## 恢复阅读位置

下次继续时先看本表“当前进度与下一批”、[`DECISIONS.md`](DECISIONS.md) 的 D-049 至 D-057 和 [`ARCHITECTURE-READINESS.md`](ARCHITECTURE-READINESS.md)。当前没有下一批负责人问卷；继续完成 owner 规格、proof plan 和 gate。只有技术证明失败且退路会改变用户保证时，才从对应最小 group 重新进入答复事务，不依赖聊天记忆重建状态。
