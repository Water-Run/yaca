# yaca 开发设计追踪区

此目录用于在编码前追踪 yaca 的分析、讨论、设计和决策。

## 目录性质

- 本目录是项目正式的设计与开发追踪资料，纳入 Git 版本控制。
- 设计资料直接在 `main` 分支维护并按完整批次本地提交。
- 除非项目负责人在当次任务中明确要求，否则不向远端推送或进行其他远端写操作。
- 这里可以持续修订；项目源码和公开用户文档只有在相关设计确认后才修改。
- 当前阶段禁止编写实现代码，也不把占位模块填成伪实现。

## 工作方式

1. 先建立覆盖全产品的设计决策清单，避免只深入局部实现细节。
2. 先讨论用户可感知的机制、数据生命周期、失败恢复、安全和交互，再讨论接口与文件布局。
3. 确认项目级目标、兼容性范围、子系统边界和依赖关系。
4. 默认每次深入一个决策主题；项目负责人要求集中盘点时，可以先给出带依赖顺序的综合决策包，再把回复逐项归档。
5. 每个子系统依次完成：现状分析、方案比较、设计确认、验收标准。
6. 全部关键设计确认后，再编写实施计划。
7. 实施阶段仍按子系统逐个完成，不并行铺开半成品。

## 文件索引

- `TRACKING.md`：阶段、子系统状态和下一步。
- `HANDOFF-AUTO-2026-08-10.md`：2026-08-10 离线自动规格硬化交接笔记（D-070）。
- `OWNER-QUESTIONS-01.md`：已经回答并冻结的负责人集中问卷；保留 29 题收到回复时的候选语境。
- `DECISION-PROJECTION-BATCH-06.md`：把集中答复确定展开为 248 个 atomic `PR-006-*` 传播记录。
- `CURRENT-STATE.md`：仓库与打包基础设施现状。
- `SYSTEM-MAP.md`：子系统导航、依赖和建议顺序。
- `DECISIONS.md`：已经确认的项目级决策。
- `DESIGN-DECISION-ROADMAP.md`：解释原子题库、十个 owner packet、跨 packet 分批队列与实施就绪门的全局关系。
- `DECISION-BATCH-QUEUE.md`：保留把全部正式问题按真实依赖重组后的 49 个旧原子审计批次；当前不再要求负责人逐批作答。
- `ARCHITECTURE-READINESS.md`：区分题库、决定、规格与计划，列出进入实施计划前必须通过的 P0/P1 门和证据。
- `TOOL-PERMISSION-MATRIX.md`：W2-B tool×Permission 矩阵。
- `MODEL-EVENT-SCHEMA.md`：W2-C canonical Model 事件/请求。
- `ACTION-REGISTRY.md`：W2-A semantic action 注册表。
- `PROOF-PLANS-P0.md`：TP-003/006/008 证明提纲。
- `READINESS-GAP.md`：主线就绪差距与 Wave 工作包（从“决定已收口”到“可开发”的运营清单）。
- `SPEC-FREEZE-QUEUE.md`：规格冻结问答（主队列已完成 → D-059..D-069）；再有缺口另开题，不默认续 SQ。


- `DECISION-RESOLUTION-PROTOCOL.md`：规定负责人回复怎样逐项归档、消解冲突并提升为可实施规格。
- `DECISION-REGISTER.md`：`decision-inventory-v9` 的 270 组正式问题唯一实时状态、条件、回复证据和决定/规格/gate 传播登记；从这里恢复当前进度。
- `LIVE-DESIGN-COVERAGE.md`：当前 checklist/AQ 到负责人决定、已确认结论、技术规格/证明或排除重入的覆盖审计；不另存回复状态。
- `DECISION-TRACEABILITY.md`：审计 checklist、AQ、决策组、owner、readiness gate 和未来权威规格之间的追踪缺口。
- `TECHNICAL-PROOF-BACKLOG.md`：把不应由负责人凭偏好选择的兼容、性能和安全事实变成目标平台证明义务。
- `FOURTH-ROUND-GAP-AUDIT.md`、`SUBSYSTEM-COVERAGE-AUDIT.md`、`CONFIG-COMPLETENESS-AUDIT.md`：第四轮敌对式查漏、23 子系统责任矩阵和完整配置面专项审计。
- `CONFIG-SCHEMA-CANDIDATE.md`：完整配置逐字段候选、XML 覆盖、INI 往返、秘密生命周期与连续 `CV-001` 至 `CV-076` 跨字段校验底稿。
- `DATA-CLASSIFICATION-CANDIDATE.md`：逐类说明数据能否进入不同 Model purpose、TUI、XML、stderr、support 和跨 endpoint 请求的审阅底稿。
- `QUESTIONS.md`：`AQ-001` 至 `AQ-437` 原子设计决策题库；用于防遗漏和追踪，不再直接作为主要问答页面。
- `DESIGN-CHECKLIST.md`：覆盖全产品的设计主题与历史讨论顺序；现行选择只看 register/decisions。
- `DISCUSSION-BATCH-01.md`：首批 20 个高杠杆综合问题及项目负责人的原始回复；保留为决策证据，不把其中的推荐自动视为确认。
- `DISCUSSION-BATCH-02.md`：正式 PJ/CX 首轮回复原话、编号解释与原子断言。
- `DISCUSSION-BATCH-03.md`：`PJ-18` 单 root、镜像父目录权威来源，以及 `AutoRenameDisabled` 手工名称优先级补缝的原话与断言。
- `DISCUSSION-BATCH-04.md`：本轮增量批注原话；无启动头 master、`.model` picker/direct、逐 turn 配置 generation、Context 排序/self-test/锁，以及仍待细化的 Permission/DoubleCheck 目标。
- `DISCUSSION-BATCH-05.md`：luainstaller x86 证据口径修正，以及“原子登记不再直接充当负责人问卷”的流程决定。
- `DISCUSSION-BATCH-06.md`：集中问卷原话、逐项确认、条件重算和冲突归一；负责人产品补问现为零。
- `decision-packets/02-*.md` 至 `10-*.md`：九个通俗、成套、带 ASCII 页面/状态/替代方案的主决策包。
- `decision-packets/11-cross-system-operational-seams.md`：持续收口跨系统外改、等待、恢复、秘密删除、管理事务、扩展关闭及其后续运行接缝。
- `references/agent-loop-reference-study.md`：五个开源 AgentLoop 固定提交的源码核对与可借鉴问题。
- `subsystems/00-*.md` 至 `22-*.md`：每个子系统各自的讨论与设计文档；编号用于稳定引用，不等于当前讨论顺序。
- `subsystems/TEMPLATE.md`：单个子系统的统一设计模板。
- `web-tracks/`：未来本机 Web 产品族空预留（`yaca-web` / `yaca-ie6`，D-058）；不进入 v0.1 实现。

## 状态定义

- `候选`：只完成初步识别，边界尚未确认。
- `讨论中`：正在和项目负责人逐项确认。
- `设计已确认`：目标、接口、错误、兼容性和验收标准已经确认。
- `计划已确认`：实施顺序和任务拆分已经确认，但尚未编码。
- `实现中`、`已验证`：仅供未来开发阶段使用。

## 当前阅读入口

当前先读 [`DECISION-REGISTER.md`](DECISION-REGISTER.md) 的状态汇总、[`DECISIONS.md`](DECISIONS.md) 的 D-049 至 D-058，以及 [`ARCHITECTURE-READINESS.md`](ARCHITECTURE-READINESS.md)。`OWNER-QUESTIONS-01.md` 的 29 题已经全部答复，现行 `decision-inventory-v9` 为 `unanswered=0`；270 组、384 个 checklist ID、`AQ-001..AQ-437`、`CV-001..CV-076` 和 49 个旧批次继续保留为审计证据。负责人选择完成不等于技术证明、owner 规格或实施计划完成；P0 门通过前仍不开始编码。

本轮新增拆分把 composer 输入召回、配置秘密文件权限、raw shell 继承环境、完整 model-yield 后续接、direct 文件属性、ignore/隐藏项、`exec` cwd、输出解码与 canonical 保留、active XML 外改恢复等交给独立 owner。M05-57..59、AL06-50/51 与 TS-40 等原子组也已随 Batch 06 收口；旧 packet 中的推荐仍只是收到回复前的历史候选，现行选择只看登记表和 D-049 至 D-057。

2026-08-10：D-058 登记本机 Web 双线预留（[`web-tracks/`](web-tracks/README.md)、[`subsystems/17-web.md`](subsystems/17-web.md)）：`yaca-web`=**Java 8**，`yaca-ie6`=**PHP 5.4** + IE6。这不改变 v0.1 零 Web 表面，也不授权 Web 实现。
