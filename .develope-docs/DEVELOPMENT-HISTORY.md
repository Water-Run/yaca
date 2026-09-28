# 开发历程与历史资料

整理日期：2026-09-28。当前实现看 [CURRENT-STATE.md](CURRENT-STATE.md)，
剩余工作看 [TRACKING.md](TRACKING.md)。本页只导航已有工作和证据。

## 已完成工作的脉络

| 时间 / 节点 | 主要成果 | 证据与适用范围 |
| --- | --- | --- |
| 2026-08，设计与计划 | 产品决定、16 份机读契约、测试夹具、C01--C34 依赖及现代机证明 | [决策](DECISIONS.md)、[实施计划](IMPLEMENTATION-PLAN.md)、[Gate A/B 审计](GATE-AUDIT-2026-08-29.md)；设计就绪不等于发行资格 |
| 2026-09-07 至 09-16，核心与交互收口 | status/export、Prompt 与配置编辑、Context 管理、模型管理/测试、在线 self-test、审批恢复 | [N13 基本可用验收](BASIC-USABILITY-ACCEPTANCE-2026-09-16.md)、[Windows 收尾](WINDOWS-PREVIEW-CLOSEOUT-2026-09-16.md)；对应当时源码与候选 |
| 2026-09-19，三目标候选 | Win32/Win64 构建、CentOS 7 候选、干净机旅程与证据工具 | [双 Windows 验收](TWO-TARGET-ACCEPTANCE-2026-09-19.md)、[CentOS 记录](LINUX-CENTOS7-QUALIFICATION-2026-09-19.md)、[C33/C34](C33-C34-TOOLING-2026-09-19.md)；旧包布局和当时的 Gate R 记录不适用于当前版本 |
| 2026-09-22，范围澄清与调研 | 明确通用 Agent、内嵌 Lua、可选 tools、clean/std/full；阅读三个上游固定提交 | [定位路线](PRODUCT-ROADMAP-2026-09-22.md)、[实施候选](MAJOR-REDESIGN-PLAN-2026-09-22.md)、[上游源码对照](references/agent-loop-source-review-2026-09-22.md)；设计建议中的“待实现”是当日状态 |
| 2026-09-22 至 09-23，便携实现与 Review | Lua 工具、`.ask`、首次引导、PTY/Unicode、进程回收、容量预留、FAT32/身份竞争修复；注释规范与结构覆盖 | [实现记录](PORTABLE-IMPLEMENTATION-2026-09-22.md)、[R01--R22](CODE-REVIEW-2026-09-22.md)；主要落在 `8841212`，最终目标复验和语义 Review 未完成 |
| 2026-09-26，`32d053e` | 原生代码页转换/seek、旧编码读写及输出、区间读取/续页/尾读/搜索 | 当前源码与测试；当次记录完整 suite 646/646，尚未重建目标包 |
| 2026-09-28，恢复基线与 F4 Review | `9aed60f` 整理资料并修复证明摘要漂移；`9724797` 修正编码、UTF-16、长行续页/尾读和搜索完整性 | [R23--R28](CODE-REVIEW-2026-09-28.md#r23--r28-验证范围)、[现代机证明](proofs/modern-2026-08-29/README.md)；不提升发行资格 |
| 2026-09-28，分页修复与资料收口 | `f3a69f2` 修正最终 JSON 分页预算，完成连续翻页回归；同步当前状态和剩余队列，保留旧日志与产物 | [R29](CODE-REVIEW-2026-09-28.md#r29-验证与人工-review)；当次开发机 657/657，目标与九包资格仍待完成 |
| 2026-09-28，范围一致性与失败清理 | `d2bc3a9` 修正无进展读取、预读错误、完成时身份复核、续页版本绑定和模式异常清理 | [R30--R33](CODE-REVIEW-2026-09-28.md#r30--r33-验证与人工-review)；开发机 663/663，真实增长日志与目标资格仍待完成 |
| 2026-09-28，原生转换故障注入 | 修正 Lua 分配失败后的原生资源释放、空输入可用性和 iconv errno 保存；新增可复现 C 探针 | [R34--R36](CODE-REVIEW-2026-09-28.md#r34--r36-原生复核)、[当前复核](CURRENT-STATE.md#本轮基线复核)；Linux 与 Wine 两架构探针通过，旧目标资格仍待完成 |

## 如何解释旧结论

`23bf913` 的文档曾按 9 月 19 日的候选与资格口径记录 Gate R 通过。
之后的 D-073 三档发行、D-074 工具面以及新源码需要各自的证据。
当前 yaca 尚未发布，机读门为关闭；不能沿用旧提交的发布措辞。

日期文档中的 N13/N23/N4、测试数、失败、人工修复以及外层 SSH 退出码均按当时
观察保留。R21 的 Lua 源码覆盖验证不能代替最终单文件包，结构注释检查不能代替
全仓人工语义 Review。旧 Windows 包也没有覆盖 9 月 26 日的新代码页转换和 seek。

原 `CURRENT-STATE.md` / `TRACKING.md` 的连续开发记录保存在整理前的提交中：

```sh
git show 32d053e:.develope-docs/CURRENT-STATE.md
git show 32d053e:.develope-docs/TRACKING.md
```

原始日期记录和本地 `out/` 证据保留。`out/` 同时包含构建缓存、虚拟机和日志；
其中的旧产物只在绑定的源码及环境范围内有效。

## 深入资料

| 需要追溯的内容 | 入口 |
| --- | --- |
| 当前已确认要求与原话 | [DECISIONS](DECISIONS.md)，特别是 D-072--D-076 |
| 早期设计问题与答复传播 | [登记表](DECISION-REGISTER.md)、[集中问卷](OWNER-QUESTIONS-01.md)、[Batch 06](DISCUSSION-BATCH-06.md)；已答问题不重新进入开发队列 |
| 子系统职责、格式、动作与权限 | [系统图](SYSTEM-MAP.md)、[contracts](contracts/README.md)、[动作注册表](ACTION-REGISTRY.md)、[权限矩阵](TOOL-PERMISSION-MATRIX.md) |
| Context、配置与模型管理的落地 | [Context 续接](CONTEXT-CONTINUE-2026-09-14.md)、[配置修复](CONFIG-REPAIR-2026-09-14.md)、[模型管理](MODEL-MANAGEMENT-2026-09-14.md) |
| 指定旧 Windows 的起点 | [Server 2008 控制台](SERVER2008-CONSOLE-2026-09-14.md)、[9 月 22 日基线复核](BASELINE-REVIEW-2026-09-22.md) |
| 平台证明、发行与工具来源 | [证明目录](proofs/modern-2026-08-29/README.md)、[旧资格手册](QUALIFICATION-RUNBOOK.md)、[工具清单](../release/TOOL-BUNDLES.md) |
| 上游 AgentLoop 的借鉴范围 | [9 月 22 日源码对照](references/agent-loop-source-review-2026-09-22.md)、[早期对照](references/agent-loop-reference-study.md)；提交已固定，不代表持续跟踪上游最新版本 |
| 未来 Web 预留 | [web-tracks](web-tracks/README.md)；不在当前实现范围 |
