# 开发追踪

更新日期：2026-08-29

## 当前阶段

**编码就绪收尾已启动（D-071，2026-08-29）**：产品选择与 SQ/负责人问题集已收口，W1--W3 首版已落盘。
当前主线：校正 gate 真源 → 机器 schema/registry/fixture → modern proof → Gate A/B 与全程序实施计划。Gate B 前不写产品 `src/*.lua`。
`../luainstaller` 现为 1.3.0：旧 x86 guard 结论失效，P0-16 转为 yaca-specific 候选/目标证据债务。
Git：直接在 main 工作；D-071 要求完整核心节点提交并推送 `origin/main`。
Web（D-058）仍仅预留。

## 已确认约束

- 主体实现语言为 Lua。
- 语言级别固定为官方 Lua 5.5；不以 Lua 5.1--5.4 兼容为目标。
- 使用相邻仓库 `../luainstaller` 完成 Lua 程序打包。
- 设计完成后按子系统逐个实施，不同时铺开多个未完成系统。
- `.develope-docs/` 是正式设计资料，纳入 Git。
- 一切开发直接在 `main` 分支进行；D-071 与负责人本轮指令明确要求核心节点推送 `origin/main`。
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
| 00 | 产品契约与兼容性基线 | **W4-A 规格侧冻结**（journey + zero-surface machine contract） | 无 |
| 01 | 平台兼容抽象 | **W3-A 规格侧冻结**（窄端口/safe-load/identity contract） | 00 |
| 02 | 进程执行与随包资源 | **W3-A 首版**（Process AsyncPort） | 00、01 |
| 03 | 网络传输 | **W3-A 首版**（HTTP AsyncPort） | 00--02 |
| 04 | 数据格式 | 候选 | 00、01 |
| 05 | 配置与模型注册表 | **W1-B 规格侧冻结**（machine catalog/grammar/migration） | 00、01、04 |
| 06 | 模型协议适配 | **W2-C canonical 规格侧冻结**（recorded wire 待 TP） | 03--05 |
| 07 | Agent 工具系统 | **W2-B registry/matrix 规格侧冻结** | 01、02、04 |
| 08 | 权限与安全 | **W2-B fold 规格侧冻结**（W3-C 交叉声明） | 05、07、18 |
| 09 | AgentLoop 与会话状态机 | **W1-A 规格侧冻结**（machine state/outcome/trace） | 05--08、18、19 |
| 10 | 上下文存储 | **W1-C 规格侧冻结**（RNG + semantic event schema） | 04、05、09、19 |
| 11 | 上下文定位、实时索引与交互式浏览器 | **W3-B 首版**（LogicalPath/hash/Resolver） | 10 |
| 12 | 上下文压缩 | **W3-D 首版**（model-view schema） | 06、09、10 |
| 13 | CLI | **W2-A 规格侧冻结**（39-action machine registry） | 05、09--12 |
| 14 | 兼容 TUI | **输入/prompt 规格侧冻结**（chrome/proof 待补） | 01、13 |
| 15 | 诊断、自检与日志 | **W4-B 规格侧冻结**（error/exit/check registry） | 01--14、18、19 |
| 16 | 打包、安装与发布 | 候选 | 00--15、18--20 |
| 17 | Web 排除 + 双线预留 | v0.1 已排除（PJ-14 A）；D-058 预留 | 核心零 Web；`yaca-web`=Java 8，`yaca-ie6`=PHP 5.4+IE6；实现未开题 |
| 18 | Prompt、指令与工作区发现 | 候选 | 01、05、08、09 |
| 19 | 改动事务、审阅与撤销 | **W3-D 首版**（无 undo fault 矩阵） | 01、02、07--10 |
| 20 | 测试、Agent 评估与平台验收 | 候选 | 全部核心系统的已确认契约 |
| 21 | 扩展边界与未来兼容 | 候选 | 05--10、18、`PROD-11` |
| 22 | 应用运行时、生命周期与并发 | **W3-A 规格侧冻结**（事件泵/platform machine contract） | 00--15、18、19、21 的共同契约；由 20 验证 |

## 下一步

第二轮完整性审阅建立了 308 个设计 ID，并新增 22 号“应用运行时、生命周期与并发”子系统；后续轮次把改动归属、undo、command × state、Agent 评估、供应链、跨系统接缝、Model/配置、旧终端和 Context 恢复等补成当前 384 个 checklist ID。Batch 01 至 05 保存渐进式答复与修订，Batch 06 已把剩余集中问题全部写入 `DECISIONS.md` 和实时登记；当前没有负责人待答产品分支，剩余工作是 owner 规格与技术证明，不能把“实现细节尚未冻结”重新表述为偏好问题。

第三轮反向审计发现，“主题覆盖”仍不等于“可实施契约”：旧题库缺 typed finish/ask-user、raw shell 权限矩阵、外来 XML 信任、Key→curl 生命周期、XP 事件泵、单 XML 性能退路、命令×状态表和升级/卸载等闭环。第四轮又补出 config reload、per-Model scheduler、ask-user reply turn、manual retry、draft/details、raw exec stdin、Context secret purge、ManagementMutation、文件系统保证、长命令、workspace 失效和扩展关闭边界；第五轮把 `Tools` 字段存在性与无工具 Model 的 main 资格拆开；第六轮先补页面/运行时接缝，再把旧 `PROD-11` 中没有独立 owner 的 Web、图像、音频输入、remote/headless、多根、遥测和更新拆开；最后几轮继续把回答详略/指令生命周期、通知、自检页面、turn guard/完成复核人工解算、approval 恢复、direct 文件细粒度、background jobs、composer 召回、秘密文件权限、继承环境、model-yield 续接、ignore/文件属性、cwd 和输出语义、active XML 外改恢复从相邻描述中拆成独立 owner。最终体验/安全审阅又把 chat dot-command root、输入提示符、审批动作 grammar、SensitiveRead 配置面、termination-review Model 来源、资源 selector、per-Model retry、短 secret、stuck 阈值、特殊 purpose 外发同意与 reserved tree read 拆成互不代答的轴。`QUESTIONS.md` 现连续覆盖 `AQ-001` 至 `AQ-437`。

原子题库和十个 owner packet 继续承担完整性审计，但不再直接充当负责人问卷。`OWNER-QUESTIONS-01.md` 的 29 个集中问题已经全部答复；`DISCUSSION-BATCH-06.md` 保存原话与归一断言，`DECISION-PROJECTION-BATCH-06.md` 把它们回投到 248 个 atomic group。现行登记为 265 个 active 选择/排除、5 个 `not-applicable`、0 个 `unanswered`、0 个 conflict。库、内部状态、错误码、常量与性能数字继续下放到技术规格/证明，配置校验仍连续覆盖 `CV-001` 至 `CV-076`。答完问卷只关闭负责人输入门，不自动授权编码。

`DISCUSSION-BATCH-02.md` 至 `04` 捕获产品旅程和早期补缝，`DISCUSSION-BATCH-05.md` 修正 luainstaller x86 证据外推，`DISCUSSION-BATCH-06.md` 完成集中产品决策。当前工作转为把 D-049 至 D-057 展开成唯一 owner 规格、完整 typed schema/状态表/action registry，以及给 XP x86、Win7+ x64、CentOS 7 和三个最终 zip 建立技术证明。全部 P0 规格与 proof plan 通过前继续只做设计，不开始实现；上下文分支功能保持移出当前范围。

### 2026-08-29 进度快照

| 层 | 状态 |
| --- | --- |
| 负责人产品选择 | 已关闭（register `unanswered=0` / `conflict=0`） |
| 项目级决定 | D-001..D-071；D-049..D-057 主链，D-058 Web 预留，D-059..069 SQ，D-070 离线授权，D-071 readiness/proof/push 授权 |
| Owner 规格 | W1–W4 主脊柱已形成 11 份 machine contract + 6 组 fixtures；P1/页面/路径/wire 边角仍待收口 |
| 技术证明 | luainstaller 1.3.0 upstream modern；TP-003/006/008/010 已 proven-modern 并归档；无 proven-target |
| 实施就绪门 | P0 gate 仍未 passed（规格侧冻结≠目标 proof）；Gate A/B 审计前不写产品代码 |
| Web | v0.1 仍零表面；双线预留：`yaca-web`/Java 8、`yaca-ie6`/PHP 5.4+IE6 |

**近期设计工作优先级（核心优先于 Web）：**

1. 关闭 P1/ASCII chrome/path/wire 的实施计划前规格缺口。
2. 审计 Gate A，形成全程序实施计划并通过 Gate B。
3. 保留 XP/Win64/CentOS 与最终 zip qualification 为实现/发布硬门。
4. Web 双线仅维护预留文档，除非负责人开题。

主线就绪差距与 Wave 工作包见 **[`READINESS-GAP.md`](READINESS-GAP.md)**。  
规格冻结问答见 **[`SPEC-FREEZE-QUEUE.md`](SPEC-FREEZE-QUEUE.md)**：**主队列已完成**（至 D-069）。

**当前工作路线（2026-08-29）：** W1–W4 机器契约节点完成 → modern proof → P1/README 收尾 → Gate A/B 与实施计划。P0 门仍 **未通过**（主要剩 TP/目标证据）；不写产品代码直至门 A/B。


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

**仍有效禁令**：不新开 SQ 长卷；Gate A/B 前不开始产品 `src/*.lua`。D-071 已取代旧的“本轮不做 proof 原型”限制，允许可丢弃 modern proof、实施计划工具和核心节点推送。
**可继续**：modern proof、P1/README/门禁收尾、全程序实施计划与保守技术择优。
离线会话细则见 [`HANDOFF-AUTO-2026-08-10.md`](HANDOFF-AUTO-2026-08-10.md)。
