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
- `CURRENT-STATE.md`：仓库与打包基础设施现状。
- `SYSTEM-MAP.md`：子系统导航、依赖和建议顺序。
- `DECISIONS.md`：已经确认的项目级决策。
- `DESIGN-DECISION-ROADMAP.md`：把原子题库、九个主决策包、第四轮补缝包和实施就绪门串成可逐包回复的路线。
- `ARCHITECTURE-READINESS.md`：区分题库、决定、规格与计划，列出进入实施计划前必须通过的 P0/P1 门和证据。
- `DECISION-RESOLUTION-PROTOCOL.md`：规定负责人回复怎样逐项归档、消解冲突并提升为可实施规格。
- `DECISION-TRACEABILITY.md`：审计 checklist、AQ、决策组、owner、readiness gate 和未来权威规格之间的追踪缺口。
- `TECHNICAL-PROOF-BACKLOG.md`：把不应由负责人凭偏好选择的兼容、性能和安全事实变成目标平台证明义务。
- `FOURTH-ROUND-GAP-AUDIT.md`、`SUBSYSTEM-COVERAGE-AUDIT.md`、`CONFIG-COMPLETENESS-AUDIT.md`：第四轮敌对式查漏、23 子系统责任矩阵和完整配置面专项审计。
- `CONFIG-SCHEMA-CANDIDATE.md`：完整配置逐字段候选、XML 覆盖、INI 往返、Key 生命周期与跨字段校验底稿。
- `DATA-CLASSIFICATION-CANDIDATE.md`：逐类说明数据能否进入不同 Model purpose、TUI、XML、stderr、support 和跨 endpoint 请求的审阅底稿。
- `QUESTIONS.md`：`AQ-001` 至 `AQ-373` 原子设计决策题库；用于防遗漏和追踪，不再直接作为主要问答页面。
- `DESIGN-CHECKLIST.md`：覆盖全产品的待决策主题、优先级和讨论顺序。
- `DISCUSSION-BATCH-01.md`：首批 20 个高杠杆综合问题及项目负责人的原始回复；保留为决策证据，不把其中的推荐自动视为确认。
- `decision-packets/02-*.md` 至 `10-*.md`：九个通俗、成套、带 ASCII 页面/状态/替代方案的主决策包。
- `decision-packets/11-cross-system-operational-seams.md`：第四轮将跨系统外改、等待、恢复、秘密删除、管理事务和扩展关闭收成十三项新决定。
- `references/agent-loop-reference-study.md`：五个开源 AgentLoop 固定提交的源码核对与可借鉴问题。
- `subsystems/00-*.md` 至 `22-*.md`：每个子系统各自的讨论与设计文档；编号用于稳定引用，不等于当前讨论顺序。
- `subsystems/TEMPLATE.md`：单个子系统的统一设计模板。

## 状态定义

- `候选`：只完成初步识别，边界尚未确认。
- `讨论中`：正在和项目负责人逐项确认。
- `设计已确认`：目标、接口、错误、兼容性和验收标准已经确认。
- `计划已确认`：实施顺序和任务拆分已经确认，但尚未编码。
- `实现中`、`已验证`：仅供未来开发阶段使用。

## 当前阅读入口

先读 [`DESIGN-DECISION-ROADMAP.md`](DESIGN-DECISION-ROADMAP.md)，再从 [`decision-packets/02-product-journey-and-surfaces.md`](decision-packets/02-product-journey-and-surfaces.md) 开始逐包回复；十个包现有 187 组负责人决定。题库中的推荐、候选 schema 和 ASCII 文案都不会因写入仓库自动升级为决定。
