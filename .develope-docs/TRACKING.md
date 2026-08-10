# 开发追踪

更新日期：2026-08-10

## 当前阶段

**离线自动规格硬化（D-070，2026-08-10）**：产品负责人选择已于 2026-07-22 收口；SQ 与「下一负责人问题集」已由 D-070 收口。  
当前 **只做** `.develope-docs` Wave 3 规格硬化（+ 可加深 W1–W2）；**不** 写产品 `src/*.lua`；**不** 做 proof 可执行原型。  
主线顺序：W3-A Runtime → W3-B Path/Index → W3-C 数据/秘密 → W3-D 改动/压缩。  
Git：main 批次 commit；**仅重大里程碑** 少数 push。交接笔记：[`HANDOFF-AUTO-2026-08-10.md`](HANDOFF-AUTO-2026-08-10.md)。  
Web 双线（D-058）仍仅预留，不进入 v0.1。

## 已确认约束

- 主体实现语言为 Lua。
- 语言级别固定为官方 Lua 5.5；不以 Lua 5.1--5.4 兼容为目标。
- 使用相邻仓库 `../luainstaller` 完成 Lua 程序打包。
- 设计完成后按子系统逐个实施，不同时铺开多个未完成系统。
- `.develope-docs/` 是正式设计资料，纳入 Git。
- 一切开发直接在 `main` 分支进行；完整批次可以本地提交，但除非项目负责人当次明确要求，否则不推送或执行其他远端写操作。
- Windows XP SP3 x86 与 CentOS 7 x86_64 都是 v0.1 硬性发布门槛。
- Windows 客户端验证连续覆盖 XP SP3、Vista SP2、7 SP1、8、8.1、10 和 11；所有最终声明支持的平台都执行完整测试。
- Windows v0.1 分别发布 Win32 x86 与 Win64 x86_64；x86 覆盖 XP SP3 至 11，x64 覆盖 Windows 7 SP1 至 11。两个架构独立完整测试和放行；不发布 ARM。
- Linux v0.1 只发布 x86_64 产物；不发布 i686、ARM 或其他架构。
- 具体测试平台、发行版清单和构建主机安排延后到发布系统设计；不在当前架构讨论中展开。
- v0.1 不承诺旧 macOS，也不为旧 macOS 建立专门构建与测试矩阵。
- 规划阶段保持工作树有序：只保留当前正在整理的文档变更，完成后及时提交。
- 继续遵守仓库现有的旧系统、旧终端和保守依赖约束。
- 主交互入口为 `yaca [目录]`；裸 `yaca` 与 `yaca .` 完全等价，并以该目录作为工作区、指令发现和 Context Resolver 的统一初始位置。
- AgentLoop 的正常完成由主模型主导；独立“使用终止评估器”用户开关已并入 `DoubleCheck`，有效值开启时在主模型提出终止后单独发起完成复核请求。
- `Cautious` 不作为权限模式；`DoubleCheck` 是默认配置总开关并至少包含完成复核，`.cautious` 提供写入上下文 XML 的会话级覆盖。
- 每个上下文是 `__yaca__/CONTEXT/` 镜像路径树中的一个 XML，并恰好绑定一个由 XML 镜像父目录解码的 workspace root；XML 不另存 current workdir。索引从当前 XML 树实时派生，hash 输入是包含文件名的逻辑路径，显式 rebind 安全移动 XML 后 hash 随之变化。
- 上下文没有永久 `ContextId`；当前 hash 固定为 16 位大写十六进制（`0-9A-F`，D-059），由当前逻辑路径运行时计算；重命名后旧 hash 失效。
- 所有 selector 型连接、重命名和删除入口共用统一 Resolver；`.status` 直接从当前句柄计算 hash，不扫描全树。
- Resolver（D-061）：短名按环距 + `LogicalPath` 升序 **首个可用** 命中即停；精准指定用 **hash**（整条逻辑路径摘要）；hash 同环须证明唯一，碰撞 fail-closed；无短名 `AmbiguousName`。
- 交互式上下文浏览器与 CLI 共用目录扫描、路径/hash、目标复核及打开/修改服务；`recent` 是快速最近列表，`full` 是完整目录树/全部 Catalog，两者都支持详情、搜索、重命名、永久删除与刷新，不提供 trash/restore。
- 当前产品范围不包含上下文/对话分支功能；不设计或预留 `.fork` 命令、分支元数据、lineage 索引及对应 TUI/CLI 流程。以后若重新提出，重新进入决策流。

## 子系统清单

编号用于稳定文件引用，不表示当前讨论顺序；实际主线由 `DESIGN-CHECKLIST.md` 的产品级依赖决定。

| 编号 | 子系统 | 当前状态 | 主要依赖/共同确认 |
| --- | --- | --- | --- |
| 00 | 产品契约与兼容性基线 | 讨论中（兼容性已确认） | 无 |
| 01 | 平台兼容抽象 | 讨论中 | 00 |
| 02 | 进程执行与随包资源 | 候选 | 00、01 |
| 03 | 网络传输 | 候选 | 00--02 |
| 04 | 数据格式 | 候选 | 00、01 |
| 05 | 配置与模型注册表 | **W1-B 展开中**（字段 catalog 已首版） | 00、01、04 |
| 06 | 模型协议适配 | 候选 | 03--05 |
| 07 | Agent 工具系统 | 候选 | 01、02、04 |
| 08 | 权限与安全 | 候选 | 05、07、18 |
| 09 | AgentLoop 与会话状态机 | **W1-A 展开中**（状态/outcome 表已首版） | 05--08、18、19 |
| 10 | 上下文存储 | **W1-C 展开中**（事件目录/提交表已首版） | 04、05、09、19 |
| 11 | 上下文定位、实时索引与交互式浏览器 | 讨论中 | 10 |
| 12 | 上下文压缩 | 候选 | 06、09、10 |
| 13 | CLI | **W2-A 展开中**（ACTION-REGISTRY 首版） | 05、09--12 |
| 14 | 兼容 TUI | 候选 | 01、13 |
| 15 | 诊断、自检与日志 | 候选 | 01--14、18、19 |
| 16 | 打包、安装与发布 | 候选 | 00--15、18--20 |
| 17 | Web 排除 + 双线预留 | v0.1 已排除（PJ-14 A）；D-058 预留 | 核心零 Web；`yaca-web`=Java 8，`yaca-ie6`=PHP 5.4+IE6；实现未开题 |
| 18 | Prompt、指令与工作区发现 | 候选 | 01、05、08、09 |
| 19 | 改动事务、审阅与撤销 | 候选 | 01、02、07--10 |
| 20 | 测试、Agent 评估与平台验收 | 候选 | 全部核心系统的已确认契约 |
| 21 | 扩展边界与未来兼容 | 候选 | 05--10、18、`PROD-11` |
| 22 | 应用运行时、生命周期与并发 | 候选 | 00--15、18、19、21 的共同契约；由 20 验证 |

## 下一步

第二轮完整性审阅建立了 308 个设计 ID，并新增 22 号“应用运行时、生命周期与并发”子系统；后续轮次把改动归属、undo、command × state、Agent 评估、供应链、跨系统接缝、Model/配置、旧终端和 Context 恢复等补成当前 384 个 checklist ID。Batch 01 至 05 保存渐进式答复与修订，Batch 06 已把剩余集中问题全部写入 `DECISIONS.md` 和实时登记；当前没有负责人待答产品分支，剩余工作是 owner 规格与技术证明，不能把“实现细节尚未冻结”重新表述为偏好问题。

第三轮反向审计发现，“主题覆盖”仍不等于“可实施契约”：旧题库缺 typed finish/ask-user、raw shell 权限矩阵、外来 XML 信任、Key→curl 生命周期、XP 事件泵、单 XML 性能退路、命令×状态表和升级/卸载等闭环。第四轮又补出 config reload、per-Model scheduler、ask-user reply turn、manual retry、draft/details、raw exec stdin、Context secret purge、ManagementMutation、文件系统保证、长命令、workspace 失效和扩展关闭边界；第五轮把 `Tools` 字段存在性与无工具 Model 的 main 资格拆开；第六轮先补页面/运行时接缝，再把旧 `PROD-11` 中没有独立 owner 的 Web、图像、音频输入、remote/headless、多根、遥测和更新拆开；最后几轮继续把回答详略/指令生命周期、通知、自检页面、turn guard/完成复核人工解算、approval 恢复、direct 文件细粒度、background jobs、composer 召回、秘密文件权限、继承环境、model-yield 续接、ignore/文件属性、cwd 和输出语义、active XML 外改恢复从相邻描述中拆成独立 owner。最终体验/安全审阅又把 chat dot-command root、输入提示符、审批动作 grammar、SensitiveRead 配置面、termination-review Model 来源、资源 selector、per-Model retry、短 secret、stuck 阈值、特殊 purpose 外发同意与 reserved tree read 拆成互不代答的轴。`QUESTIONS.md` 现连续覆盖 `AQ-001` 至 `AQ-437`。

原子题库和十个 owner packet 继续承担完整性审计，但不再直接充当负责人问卷。`OWNER-QUESTIONS-01.md` 的 29 个集中问题已经全部答复；`DISCUSSION-BATCH-06.md` 保存原话与归一断言，`DECISION-PROJECTION-BATCH-06.md` 把它们回投到 248 个 atomic group。现行登记为 265 个 active 选择/排除、5 个 `not-applicable`、0 个 `unanswered`、0 个 conflict。库、内部状态、错误码、常量与性能数字继续下放到技术规格/证明，配置校验仍连续覆盖 `CV-001` 至 `CV-076`。答完问卷只关闭负责人输入门，不自动授权编码。

`DISCUSSION-BATCH-02.md` 至 `04` 捕获产品旅程和早期补缝，`DISCUSSION-BATCH-05.md` 修正 luainstaller x86 证据外推，`DISCUSSION-BATCH-06.md` 完成集中产品决策。当前工作转为把 D-049 至 D-057 展开成唯一 owner 规格、完整 typed schema/状态表/action registry，以及给 XP x86、Win7+ x64、CentOS 7 和三个最终 zip 建立技术证明。全部 P0 规格与 proof plan 通过前继续只做设计，不开始实现；上下文分支功能保持移出当前范围。

### 2026-08-10 进度快照

| 层 | 状态 |
| --- | --- |
| 负责人产品选择 | 已关闭（register `unanswered=0` / `conflict=0`） |
| 项目级决定 | D-001..D-058 已记录；D-049..D-057 为核心主链，D-058 为 Web 预留 |
| Owner 规格 | 23 个子系统多为「候选/讨论中」，尚无「设计已确认」 |
| 技术证明 | TP 多为 `unplanned`；少量仅 `proven-modern` |
| 实施就绪门 | P0 **全部未通过**；不可写完整实施计划，更不可写产品代码 |
| Web | v0.1 仍零表面；双线预留：`yaca-web`/Java 8、`yaca-ie6`/PHP 5.4+IE6 |

**近期设计工作优先级（核心优先于 Web）：**

1. 把 D-049..D-057 机械展开为可执行 owner 规格（schema / 状态表 / action registry）。
2. 为 TP-001/003/006/008 等 P0 证明写可复现 proof plan。
3. 推进 AR-P0-02/03/09/10 等阻塞全程序计划的门。
4. Web 双线仅维护预留文档；不抢核心主线带宽，除非负责人指定开 Web 决策包。

主线就绪差距与 Wave 工作包见 **[`READINESS-GAP.md`](READINESS-GAP.md)**。  
规格冻结问答见 **[`SPEC-FREEZE-QUEUE.md`](SPEC-FREEZE-QUEUE.md)**：**主队列已完成**（至 D-069）。

**当前工作路线（2026-08-10）：** Wave 1 **三条脊柱首版齐** — W1-A [`09`](subsystems/09-agent-session.md)、W1-B [`05` catalog](subsystems/05-configuration.md)、W1-C [`10` 内部 XML](subsystems/10-context-storage.md)。W2-A 见 [ACTION-REGISTRY.md](ACTION-REGISTRY.md)；TP-003/006/008 计划见 [PROOF-PLANS-P0.md](PROOF-PLANS-P0.md)（已 specified）。下一步 W2-B 工具矩阵 或 开始 modern 机 proof 原型。不写产品代码直至门 A/B。


### 自动推进停止点 / 下一负责人问题集（2026-08-10）

无负责人产品选择的 Wave-2 设计与 P0 证明**计划**已尽量推完：

| 已自动完成 | 位置 |
| --- | --- |
| W1-A/B/C | 09 / 05 / 10 |
| W2-A/B/C | ACTION-REGISTRY / TOOL-PERMISSION-MATRIX / MODEL-EVENT-SCHEMA |
| TP specified | 003/004/005/006/008/010 → PROOF-PLANS-P0 |

**下一负责人问题集**：**已由 D-070 收口**（2026-08-10 离线前问卷）。

| 原主题 | D-070 结论 |
| --- | --- |
| hard-cap / 预算数字 | 技术推导 + 用户可配置收紧；不写假精确偏好数字 |
| 路径显示 vs hash | hash/Resolver = LogicalPath 规范形；显示可友好，显示≠hash |
| TP 失败改用户保证 | 停 → 最小 O 包；不擅自 WAL/弱 cancel |
| Permission 扩展 | Std/Readonly 冻结；禁止静默改 |

**仍有效禁令**：不新开 SQ 长卷；不开始产品 `src/*.lua`（D-001）；本轮不做 proof 可执行原型。  
**可继续**：Wave 3 规格、W1–W2 加深、门禁文档、纯表格与保守技术择优。  
离线会话细则见 [`HANDOFF-AUTO-2026-08-10.md`](HANDOFF-AUTO-2026-08-10.md)。
