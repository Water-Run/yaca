# 集中答复投影记录：批次 06

更新日期：2026-07-22

状态：负责人选择已捕获；owner 设计传播进行中；目标平台与最终包技术证明未完成

## 作用域

本文件把 [`DISCUSSION-BATCH-06.md`](DISCUSSION-BATCH-06.md) 的集中答案确定地展开为 [`DECISION-REGISTER.md`](DECISION-REGISTER.md) 中的 `PR-006-<GROUP-ID>`。它避免复制 248 行内容相同的传播元数据，同时仍为每个 atomic group 产生唯一、可机械展开的 PR identity。

冻结输入为 `decision-inventory-v9`，semantic SHA-256 `80efc73d45ed32e05ea991f35a8cc484700a276f6664c77bc339c7957648b044`，负责人回复前 commit 为 `909544c`。集中问题到 group 的成员集合只取 [`OWNER-QUESTIONS-01.md`](OWNER-QUESTIONS-01.md) 每节的 `覆盖` 行；28 个集合恰好覆盖回复前的 248 个 `unanswered` 一次。`CQ-15` 是新语义补缝，没有重复映射旧 group。

## 每组 PR 的确定展开

对于下表某行的每个覆盖 group `G`，登记表中的 `PR-006-G` 定义为：

```text
projection_id:          PR-006-G
group_id:               G
decision_refs:          该 CQ 行的 Decision
owner_spec_ref:         该 CQ 行的 Exactly one owner
consumer_spec_refs:     该 CQ 行的 Consumers
gate_refs:              该 CQ 行的 Gates
test_refs:              该 CQ 行的 Tests/proofs
condition_basis_reply:  普通组为 n/a:active；条件组取“条件重算”一节
no_projection_evidence: 普通组为 n/a:active；inactive 条件组取“条件重算”一节
lifecycle_refs:         B06 对应 AS；CQ-16/CQ-22 另含冲突归一
propagation_status:     pending，除明确 inactive 分支为 complete
```

这是一条逐 group expansion 规则，不是一个共享的模糊 PR：`PR-006-PP-01` 与 `PR-006-PP-02` 仍是不同记录，可以独立进入 owner/test/gate 审计。若一个 owner 文档后来拆分锚点，只更新对应 group 的显式 override，不改变负责人选择。

## 集中问题传播表

| CQ | Reply / assertion | Decision | Exactly one owner | Consumers | Gates | Tests/proofs | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CQ-01 | `B06/AS-006-01` | D-049 | `subsystems/18-prompt-and-workspace-instructions.md#默认交流契约` | 09 AgentLoop；14 TUI | AR-P0-02/13 | Prompt/final-report golden transcripts | pending |
| CQ-02 | `B06/AS-006-01` | D-049/D-052 | `subsystems/18-prompt-and-workspace-instructions.md#澄清与假设` | 08 Permission；09 AgentLoop | AR-P0-02/06 | high-impact clarification fixtures | pending |
| CQ-03 | `B06/AS-006-02` | D-049 | `subsystems/18-prompt-and-workspace-instructions.md#四层-prompt-构造` | 05 Config；06 Model；09 Loop；10 XML | AR-P0-02/03/10 | four-layer/purpose request goldens | pending |
| CQ-04 | `B06/AS-006-03` | D-045/D-057 | `subsystems/00-product-and-compatibility.md#单一-workspace-root-与显式-context-管理` | 07 Tool；08 Permission；10/11 Context | AR-P0-01/06/10/11 | real-path/Git-root/link vectors | pending |
| CQ-05 | `B06/AS-006-03` | D-051/D-057 | `subsystems/22-application-runtime-and-concurrency.md#单活动-context` | 09 Loop；10 Context；14 TUI | AR-P0-02/10/15 | switch/close/concurrency traces | pending |
| CQ-06 | `B06/AS-006-04` | D-054 | `subsystems/14-tui.md#规范逐行界面` | 13 CLI；15 Diagnostics | AR-P0-13 | XP/old-terminal transcript goldens | pending；TU-30 complete inactive |
| CQ-07 | `B06/AS-006-04` | D-054 | `subsystems/14-tui.md#输入意图与文本后备` | 09 Loop；13 CLI | AR-P0-02/13 | shortcut/fallback/draft/approval matrix | pending |
| CQ-08 | `B06/AS-006-05` | D-054 | `subsystems/13-cli.md#统一-semantic-action-registry` | 14 TUI；15 self-test | AR-P0-13 | argv/TTY/non-TTY golden matrix | pending |
| CQ-09 | `B06/AS-006-06` | D-050 | `subsystems/06-model-protocols.md#正式协议集合` | 03 Network；05 Config；09 Loop | AR-P0-03/04 | OpenAI Chat + Anthropic Messages fixtures | pending |
| CQ-10 | `B06/AS-006-07` | D-049/D-050 | `subsystems/05-configuration.md#typed-schema-与-model-section` | 06 Model；10 XML；13 REPL | AR-P0-03/09 | schema/roundtrip/reload/migration | pending |
| CQ-11 | `B06/AS-006-08` | D-050 | `subsystems/03-network-transport.md#http-https-stunnel-边界` | 05 Config；15 self-test；16 Release | AR-P0-04/09/16 | TP-006/007/029 + XP TLS/HTTP fixtures | pending |
| CQ-12 | `B06/AS-006-09` | D-050 | `subsystems/15-diagnostics-and-logging.md#三阶段-self-test` | 05/06/11/13/14/16 | AR-P1-07 | complete Stage1/2/3 target matrix | pending |
| CQ-13 | `B06/AS-006-10` | D-051 | `subsystems/09-agent-session.md#typed-controls` | 06 Protocol；10 XML；14 TUI | AR-P0-02/05 | finish/ask/refuse/model-yield traces | pending |
| CQ-14 | `B06/AS-006-10` | D-051/D-054 | `subsystems/09-agent-session.md#queue-steer-side-cancel` | 13/14 input；22 Runtime | AR-P0-02/13/15 | scheduler/cancel/focus fault traces | pending |
| CQ-16 | `B06/AS-006-10` | D-051 | `subsystems/09-agent-session.md#doublecheck` | 05 Config；08 Permission；10 XML | AR-P0-02/06 | reviewer/override/failure/cross-endpoint matrix | pending |
| CQ-17 | `B06/AS-006-11` | D-051 | `subsystems/09-agent-session.md#硬上限-retry-stuck` | 05 Config；15 Error；20 Tests | AR-P0-02/12 | cap/retry/stuck/verification traces | pending；AL06-43 complete inactive |
| CQ-18 | `B06/AS-006-11` | D-051 | `subsystems/12-context-compaction.md#结构化摘要视图` | 06 Model；09 Loop；10 XML | AR-P0-05/12 | compaction/correction/oversize fixtures | pending |
| CQ-19 | `B06/AS-006-12` | D-052 | `subsystems/07-tool-system.md#首版-tool-registry` | 06 Protocol；08 Permission；10 XML | AR-P0-06/07 | schema/carrier/result/tool traces | pending |
| CQ-20 | `B06/AS-006-12` | D-052 | `subsystems/08-permission-and-safety.md#粗粒度-permission` | 05 Config；07 Tool；14 Approval | AR-P0-06/08 | capability/profile/approval matrix | pending；TS-21 complete inactive |
| CQ-21 | `B06/AS-006-12` | D-052 | `subsystems/02-process-and-resources.md#raw-shell` | 07 Tool；08 Permission；22 Runtime | AR-P0-07/15 | XP/Linux spawn/cancel/output/env proofs | pending |
| CQ-22 | `B06/AS-006-13` | D-052 | `subsystems/19-change-transactions-and-undo.md#无通用-undo` | 07 Tool；08 Permission；10 XML | AR-P0-14 | digest/atomic/no-undo/Git boundaries | pending |
| CQ-23 | `B06/AS-006-14` | D-053 | `subsystems/10-context-storage.md#单-xml-提交` | 01 Platform；04 Format；22 Runtime | AR-P0-10/15 | TP-008/010/016 + crash/full-disk/long XML | pending |
| CQ-24 | `B06/AS-006-14` | D-053 | `subsystems/10-context-storage.md#外来-xml-原位接盘` | 05 mapping；11 Resolver；14 TUI | AR-P0-10/11 | import/schema/mapping/writer fixtures | pending |
| CQ-25 | `B06/AS-006-14` | D-053 | `subsystems/11-context-indexing.md#recent-full-双入口` | 10 Storage；13 CLI；14 TUI | AR-P0-11/13 | recent/full/search/stale/delete matrix | pending |
| CQ-26 | `B06/AS-006-15` | D-055 | `subsystems/15-diagnostics-and-logging.md#无第三种长期诊断文件` | 09/10 close；13/14 output | AR-P0-13/15 | error/close/stderr/support goldens | pending；ED-14 complete inactive |
| CQ-27 | `B06/AS-006-16` | D-056 | `subsystems/16-packaging-and-release.md#便携布局与邻接数据根` | 00 Product；01 Platform；13 CLI | AR-P0-16 | zip/layout/Install/path/data migration tests | pending |
| CQ-28 | `B06/AS-006-17` | D-056 | `subsystems/16-packaging-and-release.md#luainstaller-qualification` | 01 Platform；20 Tests | AR-P0-16; AR-P1-08 | Win x86/XP + x64 build/API/CRT qualification | pending |
| CQ-29 | `B06/AS-006-17` | D-056 | `subsystems/16-packaging-and-release.md#发布证据` | 20 Test/Release | AR-P0-16; AR-P1-11/12 | final-package SHA/SBOM/build/full-test summaries | pending |

## 条件重算与无投影证明

| PR | Upstream | Result | No-projection evidence | Status |
| --- | --- | --- | --- | --- |
| `PR-006-TU-30` | TU-27=A via CQ-06 | inactive | 配置 schema、action/event registry、TUI backend、Context snapshot、self-test 与 zip 均没有 notification channel/events | complete |
| `PR-006-ED-14` | ED-07=C via CQ-26 | inactive | 没有 standalone diagnostic XML，因此配置/help/command/network/Context/zip 均没有 diagnostic upload | complete |
| `PR-006-AL06-43` | M05-50=A via CQ-17 | inactive | v0.1 不计算金额；配置、usage event、warning/admission 与 budget ledger 均无 amount/price 字段 | complete |
| `PR-006-TS-21` | M05-56=A via CQ-20 | inactive | Permission/config/tool/TUI/self-test/Context 均无 SensitiveRead 字段、classifier 或 reason | complete |

其他条件组均按 `DISCUSSION-BATCH-06.md#条件重算` 为 active；它们仍使用上表对应 CQ 的 pending owner/proof 记录。PJ-19 的既有 inactive 记录继续由 `PR-002-18` 拥有，不重复生成 Batch 06 PR。

## 冲突归一

- `CQ-16 A` 候选中“finish 可关闭”的子句被 D-027 的已确认总规则否决；现行行为是 `DoubleCheck=true` 永远包含 finish review，仅 high-risk action review 可独立启停。
- `CQ-22 C` 字母与同句“不要 undo、Git 按用户要求”冲突；具体文字明确选择无 Runtime undo 的 A 路线。RB-006-09 又确认 `backup/` 只是一句 Prompt。
- “Win64 也发布”明确重开并修订旧 D-010/D-015/D-037，不把旧 x86-only 前提继续当成现行约束。

当前没有 unresolved conflict。`propagation_status=pending` 表示 owner/consumer/golden/proof 尚需设计或目标平台证据，不表示负责人答复丢失，也不授权开始编码。
