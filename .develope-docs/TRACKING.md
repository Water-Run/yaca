# 开发追踪

更新日期：2026-07-22

## 当前阶段

整体分析与系统分解。只完善文档和设计，不开始编码。

## 已确认约束

- 主体实现语言为 Lua。
- 语言级别固定为官方 Lua 5.5；不以 Lua 5.1--5.4 兼容为目标。
- 使用相邻仓库 `../luainstaller` 完成 Lua 程序打包。
- 设计完成后按子系统逐个实施，不同时铺开多个未完成系统。
- `.develope-docs/` 是正式设计资料，纳入 Git。
- 一切开发直接在 `main` 分支进行；完整批次可以本地提交，但除非项目负责人当次明确要求，否则不推送或执行其他远端写操作。
- Windows XP SP3 x86 与 CentOS 7 x86_64 都是 v0.1 硬性发布门槛。
- Windows 客户端验证连续覆盖 XP SP3、Vista SP2、7 SP1、8、8.1、10 和 11；所有最终声明支持的平台都执行完整测试。
- Windows v0.1 只发布 Win32 x86 32 位产物；不发布原生 x64 或 ARM 产物。
- Linux v0.1 只发布 x86_64 产物；不发布 i686、ARM 或其他架构。
- 具体测试平台、发行版清单和构建主机安排延后到发布系统设计；不在当前架构讨论中展开。
- v0.1 不承诺旧 macOS，也不为旧 macOS 建立专门构建与测试矩阵。
- 规划阶段保持工作树有序：只保留当前正在整理的文档变更，完成后及时提交。
- 继续遵守仓库现有的旧系统、旧终端和保守依赖约束。
- 主交互入口为 `yaca [目录]`；裸 `yaca` 与 `yaca .` 完全等价，并以该目录作为工作区、指令发现和 Context Resolver 的统一初始位置。
- AgentLoop 的正常完成由主模型主导；独立“使用终止评估器”用户开关已并入 `DoubleCheck`，有效值开启时在主模型提出终止后单独发起完成复核请求。
- `Cautious` 不作为权限模式；`DoubleCheck` 是默认配置总开关并至少包含完成复核，`.cautious` 提供写入上下文 XML 的会话级覆盖。
- 每个上下文是 `__yaca__/CONTEXT/` 镜像路径树中的一个 XML，并恰好绑定一个由 XML 镜像父目录解码的 workspace root；XML 不另存 current workdir。索引从当前 XML 树实时派生，hash 输入是包含文件名的逻辑路径，显式 rebind 安全移动 XML 后 hash 随之变化。
- 上下文没有永久 `ContextId`；当前 hash 固定为 16 位并从当前逻辑路径运行时计算，重命名后旧 hash 失效。
- 所有 selector 型连接、重命名和删除入口共用统一 Resolver；`.status` 直接从当前句柄计算 hash，不扫描全树。
- Resolver 已确认采用“增量搜索环 + 单遍双判定”：距离优先、同环名称优先于 hash，当前环获胜后不扫描外层，每个 XML 候选最多探测和匹配一次。
- 交互式上下文浏览器与 CLI 共用目录扫描、路径/hash、目标复核及打开/修改服务，支持选择、目录树访问、搜索、重命名、删除与刷新；具体交互和删除语义待逐项确认。
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
| 05 | 配置与模型注册表 | 候选 | 00、01、04 |
| 06 | 模型协议适配 | 候选 | 03--05 |
| 07 | Agent 工具系统 | 候选 | 01、02、04 |
| 08 | 权限与安全 | 候选 | 05、07、18 |
| 09 | AgentLoop 与会话状态机 | 讨论中 | 05--08、18、19 |
| 10 | 上下文存储 | 候选 | 04、05、09、19 |
| 11 | 上下文定位、实时索引与交互式浏览器 | 讨论中 | 10 |
| 12 | 上下文压缩 | 候选 | 06、09、10 |
| 13 | CLI | 候选 | 05、09--12 |
| 14 | 兼容 TUI | 候选 | 01、13 |
| 15 | 诊断、自检与日志 | 候选 | 01--14、18、19 |
| 16 | 打包、安装与发布 | 候选 | 00--15、18--20 |
| 17 | Web 排除记录 | 已排除（PJ-14 A） | v0.1 零 Web 配置/命令/listener/asset/依赖；未来只可显式重开设计 |
| 18 | Prompt、指令与工作区发现 | 候选 | 01、05、08、09 |
| 19 | 改动事务、审阅与撤销 | 候选 | 01、02、07--10 |
| 20 | 测试、Agent 评估与平台验收 | 候选 | 全部核心系统的已确认契约 |
| 21 | 扩展边界与未来兼容 | 候选 | 05--10、18、`PROD-11` |
| 22 | 应用运行时、生命周期与并发 | 候选 | 00--15、18、19、21 的共同契约；由 20 验证 |

## 下一步

第二轮完整性审阅建立了 308 个设计 ID，并新增 22 号“应用运行时、生命周期与并发”子系统；第三至第五轮把改动归属、undo、command × state、Agent 评估、供应链、跨系统接缝和无工具 main 资格补成正式主题；第六轮从页面/命令体验、fd 拓扑、help、XML 身份投影、手动压缩、import compatibility 和进程级 Context 拓扑反查，又把图像、音频输入、remote/headless、独立转写、TTS 与一次性诊断上传等遗漏产品面升格；最新反向审计再补齐配置 selector/retry/短 secret、stuck 阈值、跨 Endpoint 同意和 reserved tree direct-read，当前共 384 个 checklist ID。项目负责人在 `DISCUSSION-BATCH-01.md` 回复首批综合问题，在 `DISCUSSION-BATCH-02.md` 确认第二批产品旅程取舍，在 `DISCUSSION-BATCH-03.md` 收口单 root 与手工名称优先级，又在 `DISCUSSION-BATCH-04.md` 修订启动头、选择平坦 `.model` 与逐 turn 自动配置 generation，并补充 Context 排序/self-test/锁不变量；已确认部分写入 `DECISIONS.md`，仅真正未回答或明确保留的细节继续待决。

第三轮反向审计发现，“主题覆盖”仍不等于“可实施契约”：旧题库缺 typed finish/ask-user、raw shell 权限矩阵、外来 XML 信任、Key→curl 生命周期、XP 事件泵、单 XML 性能退路、命令×状态表和升级/卸载等闭环。第四轮又补出 config reload、per-Model scheduler、ask-user reply turn、manual retry、draft/details、raw exec stdin、Context secret purge、ManagementMutation、文件系统保证、长命令、workspace 失效和扩展关闭边界；第五轮把 `Tools` 字段存在性与无工具 Model 的 main 资格拆开；第六轮先补页面/运行时接缝，再把旧 `PROD-11` 中没有独立 owner 的 Web、图像、音频输入、remote/headless、多根、遥测和更新拆开；最后几轮继续把回答详略/指令生命周期、通知、自检页面、turn guard/完成复核人工解算、approval 恢复、direct 文件细粒度、background jobs、composer 召回、秘密文件权限、继承环境、model-yield 续接、ignore/文件属性、cwd 和输出语义、active XML 外改恢复从相邻描述中拆成独立 owner。最终体验/安全审阅又把 chat dot-command root、输入提示符、审批动作 grammar、SensitiveRead 配置面、termination-review Model 来源、资源 selector、per-Model retry、短 secret、stuck 阈值、特殊 purpose 外发同意与 reserved tree read 拆成互不代答的轴。`QUESTIONS.md` 现连续覆盖 `AQ-001` 至 `AQ-437`。

为避免让项目负责人逐条机械回答 437 项，`DESIGN-DECISION-ROADMAP.md` 把 owner 正文组织成 02--10 九个主决策包和 11 号跨系统补缝包；现行 `decision-inventory-v9` 合计 270 组负责人决定，分布为 `PJ 19 / PP 18 / TU 32 / M05 57 / AL06 49 / TS 35 / CX 16 / ED 14 / RF 14 / F4 16`，每组提供连贯方案、场景/页面、推荐与代价。`DECISION-BATCH-QUEUE.md` 再按跨包依赖把它们拆成 49 个小批次和一次不重复投票的最终一致性 gate；配置候选的跨字段验证连续覆盖 `CV-001` 至 `CV-076`。`ARCHITECTURE-READINESS.md` 的门禁、`TECHNICAL-PROOF-BACKLOG.md` 的平台证明和 `DECISION-RESOLUTION-PROTOCOL.md` 的归档流程，确保明确回复最终会落成 schema、状态机、测试和证据，而不是答完问卷就直接编码。

`DISCUSSION-BATCH-02.md` 已捕获十八个 PJ 组与 `CX-13`，`DISCUSSION-BATCH-03.md` 又确认 `PJ-18=A` 和手工 rename 默认设置 `AutoRenameDisabled`：十九个 PJ 组及该补缝现已全部收到回复。`DISCUSSION-BATCH-04.md` 进一步选择 `TU-32=A`、`F4-01=custom`，删除启动头 master，并固定 Context 列表默认 updated-descending、self-test Context/Permission 检查与活动锁外部零 mutation。当前共有 21 个 active group 已收口、1 个条件组 not-applicable、248 个 unanswered；下一次回到队列最早尚未回答的 `F4-15`/`F4-14`。每批仍先保留原话并更新登记表，再传播到决定、规格和 gate。全部 P0 规格通过前继续只做设计，不开始实现；上下文分支功能保持移出当前范围。
