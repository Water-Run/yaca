# 决策日志

更新日期：2026-08-10

> 注：D-059 起为规格冻结问答（`SPEC-FREEZE-QUEUE.md`）归档。

## D-001 文档与设计先行

状态：已确认

在项目级设计和关键子系统设计得到确认前，不编写实现代码。当前空模块保持为空，不用占位实现制造虚假的完成度。

## D-002 按子系统顺序推进

状态：已确认

先建立整体边界和依赖，再逐个讨论、设计和实施子系统。后续系统依赖前一系统的已确认契约，不同时展开多个半成品实现。

## D-003 Lua 版本

状态：已确认

yaca 使用官方 Lua 5.5 语言级别和 ABI。不要求源代码向 Lua 5.1--5.4 降级兼容，也不使用 LuaJIT 特性。

## D-004 打包基础设施

状态：已确认

Lua 程序使用相邻仓库 `../luainstaller` 打包。yaca 只设计自己的发布装配层，不复制 luainstaller 已承担的依赖发现、launcher 生成和 Lua runtime 打包能力。

## D-005 本地追踪目录

状态：已被 D-006 取代

最初约定规划资料写入 `.develope-docs/` 并只在本地保存。项目负责人随后明确要求正常提交、推送，因此不再执行本决定。

## D-006 Git 开发方式

状态：已被 D-018 部分取代

`.develope-docs/` 纳入版本控制。一切设计和开发直接在 `main` 分支进行。除非项目负责人明确说明不要，否则完成一批完整变更后执行 Git commit 和 push。

## D-007 v0.1 兼容性硬门槛

状态：已确认

Windows XP SP3 x86 与 CentOS 7 x86_64 都必须通过 v0.1 的原生打包与运行验收。只在现代系统成功不构成发布完成。

## D-008 macOS 支持范围

状态：已确认

v0.1 不承诺旧 macOS，当前兼容性工作集中在旧 Windows 与旧 Linux。平台边界可以保持普通 POSIX 可移植性，但不为旧 macOS 增加专用实现、构建产物或发布测试门槛。

## D-009 Windows 客户端支持矩阵

状态：已确认

v0.1 的 Win32 x86 客户端验证连续覆盖 Windows XP SP3、Vista SP2、7 SP1、8、8.1、10 和 11；原生 Win64 x86_64 客户端验证覆盖 Windows 7 SP1 x64、8 x64、8.1 x64、10 x64 和 11 x64。两个架构都对各自声明支持的系统执行完整测试，不区分“完整测试”和“只冒烟”，也不以 x86 在 x64 系统上的兼容运行代替 x64 原生产物测试。Windows Server、Windows 2000、ReactOS、XP/Vista 原生 x64 与 Windows on ARM 不在当前承诺范围。

## D-010 Windows CPU 架构

状态：已被 2026-07-22 的 Win64 范围修订

Windows v0.1 同时提供两个独立发布物：Win32 x86 覆盖 XP SP3 至 Windows 11，原生 Win64 x86_64 覆盖 Windows 7 SP1 至 Windows 11。二者独立构建、完整测试和放行，使用相同外层产品布局。仍不提供 ARM 构建，不承诺 Windows on ARM，也不承诺 XP/Vista 原生 x64；这些旧系统使用 Win32 x86 包。

## D-011 Linux CPU 架构

状态：已确认

Linux v0.1 只提供 x86_64 发布物，CentOS 7 x86_64 是正式旧 Linux 兼容基线；任何额外发行版支持声明都必须先加入完整目标测试矩阵，不作为当前开放产品问题。不提供 i686、ARM 或其他 Linux 架构。

## D-012 测试深度与讨论时机

状态：已确认

所有最终声明支持的平台都必须执行完整测试，不建立只做冒烟验证的次级支持层。具体测试平台、发行版版本、构建主机和发布矩阵延后到 16 号打包发布系统设计；当前优先确认系统架构和抽象边界。

## D-013 总体依赖架构

状态：已确认

yaca 采用“多个窄模块与显式依赖”的轻量 ports/adapters 架构。`main.lua` 是唯一组合入口；高层模块只接收实际需要的接口。`platform.lua` 只描述平台事实，路径、文件系统、文本、时间、进程、网络和终端能力保持独立边界。禁止统一 platform 大门面，也禁止业务模块自行散落平台判断。

## D-014 平台后端选择

状态：已确认

`main.lua` 在启动时只探测一次平台，以字面量 `require` 选择 Windows 或 Linux 的具体后端，并将窄接口显式注入高层模块。公共模块不在加载时偷偷选择后端，也不在每次调用时重复判断平台。测试可以注入替代实现。

## D-015 分平台发行

状态：已由 D-054 细化

Windows x86、Windows x86_64 与 Linux x86_64 是三个独立发行包，各自在对应目标平台使用 luainstaller 原生打包。项目不生成跨平台通用二进制，也不把另一平台/架构的可执行工具或 native runtime 混入发行包。每个包单独满足自己的完整测试与发布证据门。

## D-016 统一 Lua 入口

状态：已确认

所有平台发行包共用一个 `main.lua` 和同一份业务源码。Windows/Linux 的差异仅存在于注入的后端、luainstaller 原生产物和外层资源装配。项目不维护 `main_windows.lua` / `main_linux.lua` 双入口，也不在构建时生成入口源码。允许两个很小的纯 Lua 后端同时被静态发现并嵌入，但运行时只实例化当前平台后端。

## D-017 平台身份契约

状态：已确认

`platform.lua` 只产生一次最小、不可变的平台身份：`os`、`arch`、规范化 `target` 与 `supported`。它不执行平台操作，也不集中保存文件系统、进程、网络、编码或终端能力。各窄适配器自行报告能力；OS 具体版本只用于诊断与测试证据，不成为 Agent 业务逻辑分支。

## D-018 Git 上传策略

状态：已确认

所有设计与开发继续直接在 `main` 分支进行，完整变更批次可以本地提交以保持工作树干净；除非项目负责人在当次任务中明确要求，否则不执行 `git push`、不创建远端分支，也不进行其他远端写操作。本决定取代 D-006 中“默认推送”的部分。

## D-019 设计讨论层级

状态：已确认

先建立覆盖整个产品的设计决策清单，再逐项由项目负责人决策。讨论优先聚焦用户可感知的系统机制：生命周期、数据流、状态、失败恢复、安全边界、配置面和交互体验；文件命名、适配器布局等实现细节延后到相关系统行为确定之后。上下文、配置与 TUI 是重要示例，但清单不得局限于这三个系统。

## D-020 AgentLoop 完成权与终止评估器

状态：完成权与独立请求类型已确认；独立用户开关已被 D-027 修订

正常任务终止由主模型主导：主模型产生终止意图后，AgentLoop 不再用 Runtime 自己推导的验证充分性否决该意图。早期草案曾把“响应正常结束且没有待执行工具”写成常见表现，但这不是可靠映射。D-051 已固定 `finish|ask-user|refuse` typed controls；没有 control 的完整普通回复是 `model-yield/waiting-user`，普通 provider stop 绝不自动等于 completed。

原决定要求配置增加独立“使用终止评估器”布尔开关。D-027 已将这个用户开关并入 `DoubleCheck`：有效 `DoubleCheck=false` 时接受主模型的正常终止意图；有效 `DoubleCheck=true` 时在真正结束前单独发起一次完成复核请求。终止复核与主模型本次生成仍是两个可区分、可计量的请求，不因合并配置开关而合并请求身份。

“模型主导”只决定正常任务完成权，不把取消、硬预算耗尽、未收口工具、传输/协议/存储错误等 Runtime 事实伪装成正常完成。评估器拒绝终止后的控制流、默认开关值、评估模型选择、评估输入、结构化输出、失败与超时降级策略分别留给后续问题确认。

## D-021 Cautious 与 DoubleCheck

状态：已确认早期结构；复核范围与失败控制流已由 D-051 收口

`Cautious` 不再作为独立权限模式或权限预设。谨慎复核改由默认配置总开关 `DoubleCheck` 表达；权限组只描述动作是否允许、是否需要人工确认等权限策略，不因开启谨慎复核而切换成另一权限组。

TUI 增加 `.cautious` 会话级开关，用于覆盖当前会话的 `DoubleCheck` 有效值。该操作不重写用户默认配置，覆盖值作为会话级参数元数据写入当前上下文 XML，并在恢复该上下文时恢复。D-027 已确认结束复核属于 `DoubleCheck`；其他动作复核范围仍需单独确认。

## D-022 上下文 XML 布局、路径 hash 与实时索引

状态：已确认早期布局；路径/root 与物理提交已由 D-045/D-053 收口

每个上下文使用一个 XML 文件作为活动存储，放在 `__yaca__/CONTEXT/` 下，并镜像其关联工作目录的路径层级。已确认的 Windows 示例把 `C:` 表示为路径段 `C`，形成 `CONTEXT/C/Program Files/我的任务.xml`；其他盘符、UNC、根路径和 Linux 映射规则另行确认。

用于计算上下文 hash 的输入是从 `CONTEXT` 根开始、带前导 `/`、统一使用 `/` 分隔并包含 `.xml` 文件名的逻辑路径。上述示例的 hash 输入严格为 `/C/Program Files/我的任务.xml`；双引号不属于输入。hash 算法、字符串编码、大小写与路径规范化细节另行确认。

上下文索引从 `__yaca__/CONTEXT/` 当前 XML 树实时派生；任何缓存都不能代替当前文件树成为唯一事实源。D-053 已固定 `recent/full` 两个入口、单 XML 完整事实和 active 外改 fail-stop；缓存、分页、重扫 cap 与精确事件 schema 属于 10/11 号 owner 规格和目标平台证明，不再是产品分支。

## D-023 上下文没有永久 ContextId

状态：已确认

上下文不另存跨重命名保持不变的永久 `ContextId`、UUID 或隐藏主键。当前逻辑 XML 路径是当前地址；面向用户的固定 16 位 hash 在运行时严格由该路径计算。重命名或移动改变逻辑路径时必须重新计算 hash，旧 hash 立即失效，也不自动保留为历史查找别名。

hash 不能作为跨重命名不变的持久外键。事件可以记录发生时的路径/hash 快照，单个 XML 内也可以为 turn、message、tool call 等建立局部序号或关系，但这些都不能变相恢复永久 ContextId。由 yaca 执行 rename/rebind 时必须原子更新运行时句柄与 hash；活动 XML 被外部移动、替换或改写时按 D-053 立即 stale/fail-stop，只允许显式刷新、self-fix、rebind、recovery 或退出，不自动追踪猜测。

## D-024 统一上下文解析入口与 `.status` hash

状态：已确认

所有接受上下文选择器的连接、重命名和删除入口共用同一个 Context Resolver。搜索以当前工作目录对应的镜像目录为起点，由近到远扩大到祖先及其递归子树，最终覆盖 `CONTEXT` 根。列表和交互式浏览器共用同一目录扫描与路径/hash 语义，不能各自实现不同规则。

Resolver 采用互不重叠的增量搜索环：距离是第一优先级。选择器形态分流见 **D-061**：

- **短名（非 hash）**：环序由近到远，环内按稳定 `LogicalPath` 升序；**首个可用** 精确名称命中即胜出并停止（不要求同环名称唯一，不产生 `AmbiguousName`）。
- **hash 形态**：当前环须完成 hash 唯一性所需扫描；唯一可用则胜出；同环多可用相同 hash → `HashCollision`；不得按裸枚举顺序“第一个 hash 就返回”。

非 hash 输入不计算候选 hash。hash 与短名不要为各扫两遍完整树；每个 XML 候选在一次解析中最多一次有效性探测与匹配。有界内存下允许重新枚举边界目录项，但不能重新处理候选 XML。环应扫范围不可读时不能把不完整观察假装成唯一 hash 命中（`ScanIncomplete`）。

`.status` 不调用全树解析器反查当前会话，而是从当前运行时句柄的最新逻辑路径直接计算并显示当前 16 位 hash。重命名成功后句柄与 hash 同步更新。用户可见 hash 形态见 D-059；损坏近处名称见 D-060；短名首个命中与精准 hash 见 D-061。

## D-025 当前范围不包含上下文分支

状态：已确认

当前产品范围不提供上下文或对话分支功能，不提供 `.fork` 命令，也不设计历史 turn 分叉、lineage、父子关系或配套存储、CLI、TUI 流程。未来若重新提出，重新进入决策流，不在当前架构中预留半成品契约。

## D-026 主入口的目录参数

状态：已确认入口、唯一 workspace root 与 CLI 结束选项；路径编码/链接原语待技术证明

主交互入口为 `yaca [目录]`。省略目录时以 `.` 作为参数，因此裸 `yaca` 与 `yaca .` 在路径规范化后必须具有完全相同的初始工作目录、工作区发现起点、指令发现起点和上下文 Resolver 起点。`yaca <目录>` 使用给定目录作为这些流程的初始位置。该目标必须已经存在、确实是目录且能够成功进入；文件、缺失目录和不可进入目录都不能由 yaca 自动创建、猜测或替换。

传入并可进入的真实目录就是新 Context 的唯一 workspace root；即使上级存在 Git repository，也只把 Git root/status/diff 作为可选证据，不自动提升、扩大 Permission 边界或改变 Context 镜像位置。恢复 Context 的目录语义由 D-041/D-045 固定：每个 Context 只有一个由其 XML 在 `__yaca__/CONTEXT/` 下的镜像父目录确定的 workspace root，续接只使用该目录；目录缺失、不可进入或不匹配时进入 `context-repl` 的 self-fix 路径，不提供 `AutoJumpToDir`、`ResumeDirectory` 或基于相似 Git 根的静默猜测。

相对路径以启动时解析出的真实目录为基准；符号链接/junction 的规范路径、显示路径、identity 和镜像编码由路径规格与目标平台证明冻结。`--continue` 是正式长入口之一，CLI 同时提供 D-054 的唯一短式与 Windows `/` 形式；标准 `--` 结束选项解析已经确认。宿主 shell 的引号只负责把带空格等名称保留为一个 argv，不改变以 `-` 开头 token 的 CLI 语义。

## D-027 DoubleCheck 包含完成复核

状态：已确认；动作/完成复核与失败控制流已由 D-051 收口

不再提供与 `DoubleCheck` 并列的 `UseTerminationEvaluator` 用户配置项。当前上下文的有效 `DoubleCheck` 开启时，谨慎流程至少包含主模型提出正常终止后的独立完成复核；关闭时不进行完成复核。`.cautious` 继续只覆盖当前上下文的 `DoubleCheck`，因此也会同时改变是否进行完成复核。

完成复核仍使用独立 `termination-review` request purpose、用量和 verdict，不拥有工具执行权。D-051 已进一步固定：明确缺口回到同一 turn，uncertain/失败/超限进入 waiting-user；finish review 在 `DoubleCheck=true` 时不可关闭，高风险 action review 可单独启停；两类 reviewer 分别使用自己的 Model selector 与 request snapshot，不能合并身份或同意。

该模式的产品定位由项目负责人给出：花费更多时间、花费更多 Token、获得更多安全。English UI 使用简洁 slogan：`Spend more time and tokens for greater safety.`

## D-028 Model 是完整连接实例，Key 明文存 INI，失败不静默换 Model

状态：已确认结构；协议字段已由 D-049/D-050 收口，传输证明待完成

一个 `Model.<Name>` section 表示一个完整、可单独选择和测试的 LLM 连接实例。它自行拥有 endpoint、协议、远端 model ID、Key、能力、streaming 与 retry 等连接所需配置；v0.1 不把 Provider、Credential 和 Model 拆成需要跨 section 引用的三层对象。不同 Model 可以重复相同 endpoint 或 Key，换取简单、直接的读取和迁移语义。

API Key 直接以明文写在主 INI，不改成环境变量引用或独立 secrets 文件。这个决定接受“能读取该 INI 的本地主体能读取 Key”的风险，但不授权把 Key 写入 Context XML、argv、普通日志、support/export、public digest 或 TUI 回显；Key 到网络 adapter 的具体 carrier 必须由泄漏测试和目标平台证据选择。后续 schema 若把 proxy credential、SecretHeader、EnvironmentSet value 或 adapter 字段登记为 config secret，它们必须进入同一开放 registry 和同一禁止目的地规则，不能另写只保护 Key 的手工名单；这不改变“一个 Model 是完整连接、Key 明文 INI”的已确认保存形态。

当当前 Model/provider 请求失败时，yaca 不得自动 fallback 到配置中的另一个 Model，也不得按 INI 顺序猜一个替代项。这种静默切换会改变 endpoint、费用、隐私域和行为。用户显式切换当前 Model，或为 action/termination review 显式配置另一 Model 时，XML 必须记录实际实例、原因和生效边界；两个 reviewer selector 是彼此独立的 purpose 路由，不是失败 fallback，也不能让一方配置变化带动另一方。structured compaction 使用当前 turn 冻结的 main Model，不建立 `CompactionModel` 字段或第三套隐式选择。

每个 Model 的 `Streaming` 使用 `force|try|off` 三态。`force` 不得静默降级，`off` 不请求流式；`try` 何时证明不支持、断流后怎样收口和是否缓存观察结果仍由 Model/Network 技术规格冻结。本决定归档 `AQ-016`、`AQ-017`、`AQ-018` 与 `MODEL-10` 的项目负责人原始选择；协议、HTTP/TLS、retry 与 self-test 产品路线已经由 D-050 收口，剩余资源限额和失败细节不再是负责人待答项。

## D-029 程序界面固定 English/ASCII，并保持单一简单 TUI

状态：已确认产品表面；交互语义已由 D-054 收口，旧终端表现证明待完成

yaca 自带的 UI 标签、机器字段、配置键、命令名和稳定 ID 只提供 English/ASCII，不提供 `Language`、`Mode`、`Vivid`、`Theme` 或多 renderer 显示模式。TUI 保持单一逐行交互形态，使用老终端能够支持的基本颜色和高亮；不支持鼠标，也不增加用户自定义快捷键系统。固定快捷键和文本后备直接由 help 说明。

这个 ASCII 边界不禁止真实用户数据。项目负责人已经用 `C:/Program Files/我的任务.xml` 一类中文路径定义 Context 核心场景，因此路径、文件名、用户消息、模型正文和 XML 内容必须保真 Unicode/UTF-8；Windows 原生路径层仍需 wide API。终端无法显示某字符时可以转义显示，但不得改变实际路径、hash 输入或文件操作。模型回复风格与输入语义已经由 D-049/D-054 收口；具体颜色、页面密度和旧终端按键投影由 TUI 技术规格与目标机 transcript 证明冻结。

本决定使 `PROD-09` 的独立本地化问题被更精确的 `PROD-15` 取代，并归档 `AQ-157` 中已经明确的删除方向；它不把候选页面文案提前写成已实现事实。

## D-030 Context selector 不增加显式类型前缀

状态：已确认

通用 Context Resolver 不提供 `name:`、`hash:`、`path:` 显式 selector 前缀。裸 selector 继续遵守已确认的距离优先、同一搜索环名称优先于运行时 hash 的规则；交互浏览器、连接、重命名和删除入口不得各自另造前缀语法。

取消显式前缀不等于碰撞时任取。若同一获胜范围内存在同名候选、hash 碰撞或扫描不完整，Resolver 必须返回歧义/不完整结果或进入候选选择，不得按目录枚举顺序静默连接。精确候选页面、机器错误和 hash collision 证据仍由 Index/TUI 规格确定。本决定归档 `INDEX-13` 已记录的项目负责人回复。

## D-031 首次配置与三阶段 self-test

状态：已确认；三阶段深度与启动门已由 D-050 收口，check registry/平台证明待完成

yaca 不提供首次运行欢迎页或自动设置向导。用户第一次建立 Model 配置时显式运行 canonical `yaca --model-repl`；完整配置浏览/编辑器通过 `yaca --config-repl` 进入，是可选管理入口而不是正常启动的强制步骤。D-054 同时固定每个 action 的唯一跨平台 `-` 简写和 Windows `/` 简写；所有拼写只投影同一个 semantic action，不能保留多套行为 parser。

配置加载包含完整配置校验；正常 Agent 不能带着损坏配置或零个可用 Model 启动。项目负责人原话中的“配置损坏就无法启动”不应被改写成自动进入恢复向导。`help/version`、bootstrap `model-repl`、`config-repl`、self-test Stage 1 和不依赖 Model 的 `context-repl` 使用只依赖内置 schema 的受限入口；它们不得进入 AgentLoop、联网、调用 Model 或执行 Agent 工具。`context-repl` 可以浏览、导入/恢复、重命名、删除和修复已有 Context；“增加”不表示创建一个与 D-040 冲突的空 Context。

self-test 采用三个有明确同意边界的阶段：Stage 1 离线检查配置/schema、Context mapping、Catalog/Resolver/hash 性能、包组件与终端能力；Stage 2 在显示范围/请求/Token 并取得 consent 后检查全部 enabled Model 的真实 auth/stream/tool/control，继续收集失败且 required checks 全绿才进入下一阶段；Stage 3 只用已通过 Model 做脱敏 advisory，提示名称、远端 model ID、Prompt 与 Permission matrix 的明显错配，不自动修改或覆盖 Stage 1/2。精确 check ID、硬限额和旧机耗时由 owner 规格/证明冻结。

配置可以用一个 typed 值 `StartupSelfTest=off|stage1|stage2|stage3` 显式要求普通 Agent 入口在进入 chat 前运行到指定最高阶段，默认 `off`。这不是旧式隐式连接检查：选到 Stage 2/3 仍必须显示本次实际联网范围、费用上限并取得阶段同意；拒绝、取消或 required failure 使本次 Agent 启动失败。阶段只能按 1→2→3 前进，不能跳过失败的前置阶段。显式 `--self-test` action 必须能够表达最高阶段、列出检查以及按稳定 check ID/Model selector 做 inclusion/exclusion；子参数的精确 grammar 属于 CLI registry 技术收口，不再改变 action 名称或阶段语义。

主配置与 Context 中保存的 Model、Permission 或其他会话依赖不一致时，Runtime 必须明确提示并要求按恢复契约处理，不能静默映射成另一个对象。

本决定归档 `AQ-013` 的三阶段骨架、`AQ-217` 的无首次页面方向及 `AS-004-03/04` 的完整静态/语义检查要求；`AQ-012`、`AQ-085`、`AQ-289`、`AQ-317` 至 `AQ-320` 仍只询问受限入口、确认、失败、预算与输出细节。

## D-032 SystemPrompt、ContextPrompt 与 `.prompt`

状态：已确认数据层；权威顺序已由 D-049 收口，大小/迁移规格待完成

主配置提供全局 `SystemPrompt`。每个 Context 可以拥有自己的 `ContextPrompt`，使用 `.prompt` 管理并保存在该 Context XML 中；它不是 Model section 的隐藏别名，也不能只存在于终端内存。D-049 已固定 Global、Model、Permission、Context 四个独立组件的构造顺序、特殊 purpose 边界与不自动加载项目规则；版本、大小、provider role 投影和旧配置迁移由 Prompt 技术规格冻结。

本决定归档 `AQ-002`/`AQ-003` 的数据存在与持久化方向；`AQ-001`、`AQ-055` 至 `AQ-063` 仍负责权威链、装配、命令、事件和大小边界。

## D-033 忙时输入的五个固定意图

状态：已确认领域意图；终端后备与取消语义已由 D-051/D-054 收口

主交互的固定意图是：`Enter` 提交当前输入，忙时形成 queue；`Ctrl+Enter` steer 当前任务；`Shift+Enter` 输入换行；`Alt+Enter` 发起一次 side；`Esc` 发起取消。side 是一条直接回复的只读 LLM 请求，只能查看允许的已提交会话信息，不能调用工具或改变主任务。组合键不可辨认的旧控制台、cooked/canonical line 与远程终端必须提供等价文本命令；不得因为后备困难而把五种领域动作重新合并成同一种输入。

`Esc` 在 model、tool、approval、retry、draft 与 idle 中究竟取消最内层活动、拒绝当前动作还是请求退出，steer 对已接受/已执行副作用怎样收口，仍由 AgentLoop/TUI 状态表确认。此决定只冻结动作身份，不提前伪造取消能力。

本决定归档 `AQ-024` 中的动作类别和 `AQ-008` 的 side 只读边界；`AQ-009`、`AQ-025` 至 `AQ-027`、`AQ-086` 至 `AQ-098` 仍负责输入端口、调度、历史、展示与逐状态取消。

## D-034 Permission 顺序、raw tools 与无 sandbox 边界

状态：已确认；能力矩阵与 raw shell 边界已由 D-052 收口，平台证明待完成

Permission section 的物理顺序决定新 Context 的默认项，不增加另一套 DefaultPermission ID；发行模板把 `Std` 放在第一项，因此默认是 `Std`。删除、禁用或重排第一项时怎样校验，Context 引用失效时怎样提示，继续由配置与恢复契约确认。

发行模板同时包含名为 `Readonly` 的 profile，但名称只是人类可读名称。Permission 的名称、Description 和 `SystemPrompt` 都不能授予、拒绝或确认能力；Runtime 只消费 schema 登记的 typed capability 字段。用户若把名为 `Readonly` 的 profile 配成允许写入，实际行为仍以 capability map 为准；self-test Stage 3 只给 advisory。D-049 已固定 Permission SystemPrompt 在 main/side 中位于 Global、Model 之后和 Context 之前；特殊 purpose 不把它当 instruction，确需审阅时只作为有边界 quoted data。

yaca 的工具面保持接近 Codex 的模型调用方式：模型直接调用清楚、原始而有界的工具能力，不在其上堆叠一套假装更安全的业务脚本语言。raw shell 是独立的宽能力工具，direct file/search 工具仍可以提供确定的参数、冲突和结果契约；“相信模型”不允许 Runtime 伪造工具结果、越过用户配置或重放未知副作用。

v0.1 不承诺或实现统一 OS sandbox。Permission、DoubleCheck、人工审批、工作区路径约束与 LLM reviewer 都是策略、限制和证据，不得在 UI/README 中宣传为进程隔离。D-052 已固定 `Read/Write/Delete/Shell/OutsideWorkspace` 三态矩阵和 raw shell 宽能力；精确 action snapshot/error/target 文案由 08 号 owner 和目标平台 fixture 冻结。

本决定归档 `AQ-033` 的模型直调方向、`AQ-036` 和 `AQ-037`；`AQ-034`、`AQ-038`、`AQ-149`/`AQ-150` 与工具/安全包仍定义 schema、能力和审批。

## D-035 长期 INI/XML 数据面与可移交 Context

状态：已确认产品保证；物理提交、短寿命控制物与导入映射已由 D-053 收口

yaca 的长期用户数据面只使用 INI 与 XML：完整主配置在 INI，Context 的完整会话事实与允许的会话覆盖在单个 XML。不得新增长期 `.log`、SQLite、永久 WAL 目录、draft 文件或隐藏索引作为第二事实源。为原子替换、锁、崩溃恢复或有界网络/进程传输所需的短期 temp/lock/previous-valid 控制物是否允许、怎样命名和清理，必须由存储证明决定，且不能悄悄演化为长期事实源。

Context XML 的可移交目标是：把该 XML 复制到另一台兼容机器后，接收方拥有理解历史、识别缺失依赖并继续工作的完整语义信息。它必须保存规范完整对话、控制事实、会话参数及来源、Prompt/Model/Permission 快照、Model 切换的旧值/新值/原因、工具与验证证据和压缩视图来源。这个保证不要求把任何 registered config-secret exact value 或本机绝对能力秘密写入 XML；目标机缺少对应 Model、Permission、workspace 或程序能力时，应只读说明并显式 mapping，而不是静默假装原环境仍存在。普通用户/工具正文仍可能含 Runtime 不认识的秘密，因此“排除配置秘密”不能被宣传为 XML 已自动脱敏。

“完整接盘”不等于无上限保存任意原始字节，也不授权第三方任意改写活动 XML。canonical result 的上限/引用、公开 schema、解析库、原子提交、恢复、迁移和 reference-reader 测试仍由 Context/格式/平台证明收口。

本决定归档 `AQ-041` 的语义接盘方向和 `AQ-132` 的长期数据面解释；`AQ-042`/`AQ-043`、`AQ-161` 至 `AQ-180` 与 `AQ-303` 至 `AQ-311` 仍负责兼容、控制物、schema、提交、恢复和压缩细节。

## D-036 Model 级 retry、全局 proxy 与日志去向

状态：已确认配置归属；网络/诊断现行路线已由 D-050/D-055 收口

retry 策略属于每个完整 `Model.<Name>`，不作为会让所有连接同时改变的全局重试开关；是否走代理及代理来源属于全局网络配置，不在每个 Model 中复制一套互相漂移的代理定义。请求级重试只适用于能够证明安全的网络阶段，不能因字段归属已定就自动重放已经接收 canonical event 或可能产生副作用的操作。

长期文件只有 INI/XML，因此 `LogLevel` 不能暗中指向独立 `.log` 文件。D-055 已固定诊断只投影到终端、self-test/support stdout 和健康 Context XML；无健康 writer 的 fatal error 只写 stderr 与稳定 exit code。精确事件级别、正文/secret 边界和 error ID 由 05/15 号 owner 规格冻结。

本决定归档 `AQ-140` 的 Model 归属、`AQ-145` 的全局归属和 `AQ-158` 的无独立日志文件边界；D-050/D-055 已收口显式 HTTP/TLS/stunnel、每 Model retry、全局 proxy 和零独立日志/外发的产品路线，精确字段 grammar 与平台常量仍由配置/网络/诊断规格证明。

## D-037 分平台 zip 发布物

状态：已确认早期发行单位；三个便携 zip、安装入口与数据根已由 D-056 取代收口

D-037 最初只确认 Windows x86 与 Linux x86_64 不生成混合平台档案；D-056 已加入 Win64 x86_64，并保持三个目标分别发布独立 `.zip`。每个 zip 只装配该平台实际需要并通过证据门的 Lua runtime、后端、helper、CA 和工具；不能因为仓库当前存在某文件就自动带入发布包。

D-056 已把早期双包扩展为 Win32 x86、Win64 x86_64、Linux x86_64 三个独立便携 zip，并固定解压后原地运行、邻接 `__yaca__`、简单 Install 脚本和发布证据；本条只保留最初形成“每个平台独立发行单位”的历史来源。

本决定归档 `AQ-044`，但不替代 `AQ-207` 至 `AQ-211`、`AQ-329`/`AQ-330` 和 RF 包中的内容、安装、升级及证据选择。

## D-038 v0.1 是完整但封闭的单 Agent 产品

状态：已确认；零表面与三个发行目标已由 D-044/D-056/D-057 收口

v0.1 必须是所选 Coding Agent 闭环的完整可用版本，不能把 README、空模块、现代开发机 smoke test 或“以后再补恢复”当成完成。同时，完整不以功能种类数量衡量：当前产品保持简单、终端优先和单 Agent，不提供 MCP、进程内插件、hook、skill runtime、自定义第三方工具协议、子 Agent 或 Context 分支。用户需要额外知识时，可以显式让模型阅读其准备的文档，而不是要求首版先实现扩展生态。

首版不得留下无消费者的配置、loader、假命令或公共 API 来伪装这些功能“已经预留”。未来若要加入任一种扩展，必须由项目负责人显式重新进入设计流，并重新审查权限、状态、Context schema、兼容、迁移和平台证据；当前只允许为既有事实保留必要的版本/来源字段。

本决定归档 `AQ-373` 与 `EXT-01` 至 `EXT-03` 的当前关闭方向。后续只设计明确的 unsupported 行为、无空壳检查和未来显式 re-entry gate，不再提供“v0.1 开放一种扩展”的可选分支。

## D-039 启动和本地管理不隐式联网

状态：已确认网络触发边界；telemetry/upload/update 已由 D-055/D-056 明确排除

默认正常启动、help/version、配置与 Context 浏览、静态 self-test 和其他只读取本机状态的管理动作不得自动发起网络请求。联网必须来自用户已经明确触发的 Model/tool 动作、self-test 在线阶段，或以后经单独确认进入产品的显式网络命令；每条入口仍要服从自己的 endpoint、Permission、预算、取消和记录契约。D-031 的 `StartupSelfTest=stage2|stage3` 是用户在 INI 中显式开启的启动门，但每次运行仍保留对应在线阶段的可见 consent，不能复活含糊的 `CheckModelOnStart`。

因此，aggregate telemetry、诊断上传和更新检查/下载不能借“维护”名义在启动、定时器或本地浏览时静默运行。Batch 06 已进一步选择 ED-13=A、ED-07=C→ED-14 not-applicable、RF-16=A：v0.1 对三者都是零 endpoint、零 request purpose、零配置/命令/receipt，而不是仅仅“默认关闭”。程序安装与数据迁移服从 D-056 的便携邻接数据和手工 zip 路线。

本决定归档 `DISCUSSION-BATCH-01.md` 中 B-07 对“启动和本地浏览不隐式联网”的明确接受，并约束 `PROD-07`、`DIAG-08` 与 `REL-11` 的所有下游方案。

## D-040 简洁裸启动与第一条消息落盘

状态：已确认；精确 renderer 与失败 ID 待下游冻结

裸 `yaca [directory]` 永远开始一个新的未保存 chat，不扫描 Context Catalog、不提示 recent，也不根据“正常/异常结束”分类旧任务。旧 Context 只由 `.context`、continue 或 `context-repl` 等显式动作读取。启动头保持逐行 TUI 的简洁形式，没有总显示开关；Slogan、版本、work directory、data root、配置状态、Context/实时 hash、Model、Permission、DoubleCheck 和 `.status` 提示各自使用独立 bool，每个启用字段独占一行并从行首开始。全部关闭就不显示例行启动头；固定 Slogan 为 `yaca: Yet Another Coding Agent.`，chat 输入提示为 `>>`。这些 display-only 偏好永远不能隐藏错误、警告或要求动作。

仅显示 chat、help/status、修改尚未保存的会话设置或直接退出都不建立 XML。第一条 main 用户消息被接受时，Runtime 必须先取得 D-041 的初始名称，以 no-replace 建立 Context XML，durable 保存该消息及此前内存会话设置，成功后才允许 Model 请求或任何副作用；创建失败就保留可见 draft 并失败关闭。

本决定归档 `DISCUSSION-BATCH-02.md` 的 `AS-002-01`、`AS-002-04`、`AS-002-05` 以及 `DISCUSSION-BATCH-04.md` 的 `AS-004-01`；后者取代前者中的启动头 master，但不改变逐字段/逐行方向。本决定收口 `PJ-01`、`PJ-04` 和 `PJ-05` 的负责人方向。

## D-041 Context 初始名称、固定目录与单 writer

状态：已确认；workspace 绑定来源和手工名称优先级分别由 D-045/D-046 细化

新 Context 的初始 basename 固定为 `Untitled Conversation [XXXX]`；`XXXX` 是四位大写十六进制随机短标签。它只是 ASCII 碰撞兜底，不是永久 ContextId，也不是由完整逻辑 XML 路径实时计算的 16 位 hash。创建使用平台安全随机源、bounded retry 和 no-replace，不能先检查再覆盖。用户路径、手工名称、Prompt 和对话仍按 UTF-8 保真；Windows XP 的 argv、console 和文件 API 使用宽字符边界，显示降级不得改变真实路径或 hash 输入。

`AutoNameEveryMainTurns` 是唯一全局自动命名间隔：默认 `10`，`0` 表示关闭。每 N 个成功收口且已持久化的 main turn 最多触发一次低优先级、无工具后台命名请求；side、review、self-test、工具迭代和失败/取消 turn 不计数。新 main、退出、取消或超时都可终止它，失败不阻断 main、不在退出时等待，也不在下次启动自动补跑。D-046 已确认手工 rename 默认在 XML metadata 设置独立 `AutoRenameDisabled`，context-repl 可添加/取消该标记，取消不立即命名。

每个 Context 绑定一个固定 work directory。D-045 进一步确认它就是由 XML 在 `__yaca__/CONTEXT/` 下的镜像父目录解码出的唯一 workspace root，而不是 XML 内的 current-workdir 字段。显式打开时总是验证并使用该目录；目录缺失、不可进入或 identity 不符就失败并交给 `context-repl` 的 self-fix，不提供普通 jump/keep。跨机显式 rebind 通过安全移动 XML 改变镜像父目录，成功后新目录成为固定目录且逻辑路径/hash 随之变化。

同一 Context 只允许一个 writer。活动 writer 存在时第二进程完全拒绝打开正文，只可显示名称、路径、busy 与能够证明的 PID；无法证明时显示 unknown，绝不按锁龄强抢。其他进程的 context-repl/CLI 在锁释放前也不能 rename、rebind、永久删除、import/mapping、修改 Prompt/metadata 或切换 `AutoRenameDisabled`。活动 chat 的 writer 仍可通过已登记会话 action 修改自己的 next-turn state；这不是第二 writer。陈旧锁只由 Context self-fix 在平台证据充分时处理。

本决定归档 `AS-002-06`、`AS-002-08`、`AS-002-09` 和 `AS-004-08`，对应 `PJ-12`、`PJ-13` 与 `CX-13`。

## D-042 独立管理 REPL、领域 self-fix 与直接退出

状态：已确认产品表面；命令 grammar 已由 D-054 收口，close deadline 待平台规格冻结

正式交互表面只有 chat、model-repl、config-repl、context-repl、self-test 和 help，不建立独立 recovery surface。三个管理 REPL 都是顶层 CLI semantic action，不能从 chat 打开后再返回；每个 REPL 提供自己的 `self-fix-program` 菜单，只诊断/修复本领域。用户显式打开损坏、不兼容或 unknown 的目标时，程序先显示事实、已保存范围和对应修复入口，然后退出，不自动进入恢复交互或重放副作用。

chat 中保留平坦 `.model` root，并且只切换已经存在、有效且 enabled 的 Model。无参数 `.model` 打开有界 Model picker，`.model <selector>` 直接选择；两者提交同一个 typed action、使用同一 resolver/校验并在 next-turn 生效。补全/候选提示只读取当前 enabled Model registry，窄屏或旧终端退化为逐行候选，不得改变选择结果。`.context`、`.prompt`、`.cautious`、`.status` 等仍是会话 action，而不是管理 REPL。普通对话不建立独立 plan state、PlanArtifact、`.plan` 或 `.execute`。

每个 TUI 暴露的领域动作都必须来自同一 action registry，并存在可由 CLI 调用的等价投影；纯滚动、分页、焦点移动等 renderer 手势不是第二套领域 API。D-054 已固定 canonical `--` action、唯一跨平台 `-` 简写和 Windows `/` 简写；非 TTY 仍不能跳过缺失参数、秘密输入或人工确认。

退出不额外确认，也不等待后台命名。统一 close 状态机立即取消/中断活动和未开始 queue、拒绝 pending approval，并在有界 deadline 内把事实诚实保存为 completed/interrupted/unknown；“直接退出”不等于跳过 XML 收口或伪造副作用已撤销。

本决定归档 `AS-002-07`、`AS-002-10` 至 `AS-002-12`、`AS-004-02` 与 `AS-004-05`，收口 `PJ-06`、`PJ-08` 至 `PJ-11`；平坦 `.model` 同时选择 `TU-32=A`。

## D-043 Permission 的 SystemPrompt 不参与授权

状态：已确认字段与安全边界；Prompt 排位与能力矩阵已由 D-049/D-052 收口

`Permission.<Name>.SystemPrompt` 是 optional、有界、逐字保存的用户内容。配置浏览器必须把“Capabilities — Runtime enforced”和“SystemPrompt — model instruction”分开显示；Prompt 即使写着允许 shell 或跳过确认，也不能改变 capability map、工具 registry、DoubleCheck 或人工审批。每个请求/XML 保存实际采用的 Permission 名称、能力 snapshot/digest 和 Prompt component snapshot/digest，使另一台机器能够解释历史；外来 XML 只能提供历史证据，不能创建、覆盖或激活本机 Permission 定义。

本决定细化 D-032/D-034，来源为 `AS-002-13`。它不预先回答 PP-03 的完整权威链或 TS-04 的具体 `Readonly` capability matrix。

## D-044 v0.1 只发布 TUI，不保留 Web/媒体/远程空壳

状态：已确认排除范围

v0.1 完全不提供 Web、图像附件或 clipboard-media/screenshot、音频文件或麦克风、公共 headless/IPC/RPC/LAN/remote controller、独立 transcription、TTS 或自动朗读。用户仍可把普通文本粘贴进 TUI，或把资料放在工作目录后明确要求模型通过既有工具读取；这不会创建 clipboard、媒体或远程能力。

这些排除项在配置、CLI/help/completion、Prompt/Model purpose、工具 registry、Context XML、Runtime listener/device/helper/self-test 和各平台 zip 中都必须是零表面。内部 application service、测试 fake 或设计文档中的 exclusion record 不构成公开 remote API。未来只有项目负责人针对具体 use case 显式重开设计流，才可新增相应 schema、依赖和测试；不得先留 disabled placeholder。

`PJ-16=A` 使条件组 `PJ-19` 当前为 not-applicable，同时负责人也明确不要 transcription。本决定归档 `AS-002-14`，收口 `PJ-14` 至 `PJ-17`、`PJ-19` 和 `PJ-20`；`PJ-18` 的单 root 路线随后由 D-045 独立收口。

## D-045 单 Context、单 workspace root，绑定由镜像位置决定

状态：已确认拓扑、初始 root 与权威来源；跨平台路径编码待技术证明

v0.1 每个 Context 恰好绑定一个 workspace root。一次获准访问 workspace 外路径不会把该路径升级为第二个 root；配置、Context XML、工具 schema、Prompt、Permission 和帮助中都不生成附加 root、root alias 或 root list。

当前 workspace root 的权威来源不是 Context XML 内的 `current workdir` 字段。yaca 打开一个 Context 时，从该 XML 位于 `__yaca__/CONTEXT/` 下的规范镜像父目录解码唯一 root；XML basename 只表达当前 Context 名称。XML 仍可保存工具实际 cwd、历史路径和 Git/digest 等会话证据，但这些只能解释历史，不能覆盖由当前物理位置导出的绑定。

显式 workspace rebind 是 context-repl 管理事务：在完整 XML 中追加 rebind 历史事件、原子推进 canonical `UpdatedAt`，并以 no-replace、可恢复的安全发布协议把该 generation 移动到新 root 对应的镜像目录；`CreatedAt` 不变。只有事件、metadata 与目标路径全部发布成功，新父目录才成为唯一绑定，完整逻辑 XML 路径与运行时 16 位 hash 一起变化，旧 hash 立即失效；失败或只读 inspect 不推进 `UpdatedAt`，也不得留下两个都可被 Resolver 当作 active 的候选。普通 basename rename 不改变 root，但仍因文件名变化而改变逻辑路径与 hash。

本决定选择 `PJ-18=A`，并以 `AS-003-01` 细化 D-041/PJ-13 中“记录的固定 work directory”：固定的是由镜像位置确定的单 root，不是 XML 内另一份 current-workdir 真相。Batch 06 又以 `F4-14=A`/`AS-006-03` 冻结新 Context 的初始唯一 root 为用户传入且可进入的真实目录；上级 Git root只作证据，不自动提升边界。Windows drive、UNC、Linux root、链接与非法名称的镜像编码仍由路径规格和目标平台证明冻结。

## D-046 手工名称默认设置每 Context 自动重命名禁用标记

状态：已确认会话标记与管理语义；精确 XML 元素拼写和管理事务物理协议待 Context schema 收口

Context XML metadata 保存布尔 `AutoRenameDisabled`。新 Context 默认没有禁用标记；用户手工 rename 成功时，canonical `Name`、`UpdatedAt` 与 `AutoRenameDisabled=true` 发布为同一个管理事务，`CreatedAt` 不变，默认保护用户明确给出的名称。自动命名请求自身成功改变名称时不设置该标记。

context-repl 可以显式添加或取消该标记。取消等价于把有效值恢复为 `false`，只允许该 Context 从新的调度基线开始、以后继续按全局 `AutoNameEveryMainTurns` 间隔参与周期命名；它不立即发起命名、不追补禁用期间错过的请求。添加标记或手工 rename 把它置为 `true` 时，尚未完成的自动命名 request 必须被取消或逻辑失效；即使传输无法及时停止，迟到结果也只保存 request/usage/cancel 事实，绝不能采用名称覆盖用户刚确认的结果。

`AutoNameEveryMainTurns` 继续是全局间隔：默认 `10`、`0` 全局关闭。修改一个 Context 的 `AutoRenameDisabled` 不修改这个全局值，修改全局值也不清除任何 Context 的标记；只有“全局间隔启用且当前 Context 未禁用”时，周期命名才有资格进入有界调度。

本决定归档 `AS-003-02`，关闭 D-041/PJ-12 遗留的手工名称优先级补缝。

## D-047 Context 列表排序是两个简单的全局显示偏好

状态：已确认字段、默认与 canonical 时间角色；时间编码、名称 collation 和旧平台性能 fixture 待索引规格/技术证明冻结

Context 列表、浏览器和相同 Catalog view 提供一个排序键与一个方向偏好。排序键只有 `created|updated|name`，方向只有 `ascending|descending`；默认是 `updated + descending`，即最近完整更新的 Context 在前。它们是用户 INI 的全局显示偏好，不进入 Context XML，不改变 Resolver 的距离/名称/hash 优先级，也不让裸 `yaca [directory]` 扫描 recent。

`created`/`updated` 必须读取 Context canonical metadata，而不是文件系统 mtime/ctime：复制、原子 replace、恢复和跨机导入都会改变文件时间，不能借此重排会话事实。`CreatedAt` 在初次 durable 建立 XML 时固定；`UpdatedAt` 只在一次 durable XML mutation 成功发布时原子推进，失败尝试与只读 inspect 不推进。`name` 按规范逻辑名称排序；主键相同始终使用 canonical `LogicalPath` 升序 tie-break，绝不随 `ListSortDirection` 反转，目录枚举顺序不得影响结果。目标字段拼写为 `[Context] ListSortBy` 与 `ListSortDirection`，不保留多组同义字段。

本决定归档 `AS-004-06`。`CX-19` 仍只决定 context-repl landing，不得把本排序偏好误当成选择 global-recent 首页。

## D-048 配置和 Model 定义在每个新 turn 边界自动完整载入

状态：已确认 `F4-01` custom 路线；文件观察、原子 generation 与目标平台性能证据待配置/Runtime 规格收口

yaca 在每个新顶层 turn admission 前有界地读取完整 INI bytes 并计算仅留在进程内的 private source digest。bytes 未变化时直接复用已校验的 immutable `ConfigGeneration`；变化时必须对整份配置做 parse、schema/cross-field validation，并一次性发布新 generation。model-repl/config-repl 或外部编辑产生的有效 Model/配置变化由下一 turn 自动采用，不弹 reload 确认，也不要求重启。

“每轮载入、实时”严格指顶层 turn 边界，不是逐字段热更新。一个 main/side turn 派生的 Model/tool/review/retry/compaction 活动继续使用该 turn 开始时的原快照；新 generation 不可反向改变它们。若本次观察到文件删除、半写、不可读或无效，新 turn 失败关闭并进入 bootstrap 修复路径，不能静默用旧 generation 继续。当前 Model/Permission 被删除、重命名或变得无效时明确要求 switch/mapping，不按物理第一项猜。

配置文件是小型控制文件，简单且正确的基线是每 turn 一次有界顺序读；不能只依赖 mtime/size，因为旧文件系统和快速同尺寸改写会漏检。实现可以用经过实测的高性能 Lua/C parser、缓存已验证 generation，并在 digest 相同后跳过解析，但不能用 watcher、局部 table 重读或缓存借口改变上述观察语义。

本决定选择 `F4-01` 的 custom `selected-with-exception` 路线并归档 `AS-004-09`。它与候选 B 都使用 turn boundary，但不包含“发现有效变化后询问是否载入”；用户已经要求自动生效。

## D-049 四层 Prompt 独立构造，不自动加载项目规则

状态：已确认

用户 Prompt 数据层固定为 `Global.SystemPrompt`、当前 `Model.SystemPrompt`、当前 `Permission.SystemPrompt` 与 Context XML 中的 `ContextPrompt`。四个组件独立保存、独立限制、独立标注来源/版本并进入实际 request snapshot；构造时保持组件身份，不把后项写回或覆盖前项。main/side 请求按 Global、Model、Permission、Context 的顺序提供这些 system instruction，当前用户输入保持独立 user message。更具体的 Prompt 可以细化模型行为，但任何自然语言都不能改写 Runtime 不变量、真实 Permission、工具 schema、预算或审批。

特殊 purpose 使用自己的固定 purpose Prompt，并继承 Global/Model 两个通用组件；Permission/Context 内容只有在该 purpose 确实需要审阅时才以有边界 quoted data 提供，不取得指令权威。workspace 项目规则文件不自动发现或加载；用户需要时明确要求模型通过既有获准工具读取。`.prompt` 与 context-repl 管理同一个 ContextPrompt。`backup/` 只可能是用户自定义 Prompt 中的普通文字，不是配置能力、Runtime 自动动作或恢复保证。

默认模型交流采用结果优先、按用户语言、复杂任务只在阶段变化或等待时给短进度、结束如实报告结果/改动/验证/未知项；有效 Prompt 和明确用户要求可以调整措辞与详略。只有会实质改变目标、安全、费用、不可逆副作用或公开结果的歧义才必须停下来询问，其余以最小风险假设推进并说明假设。

本决定取代 D-032/D-043 中仍待确认的 Prompt 排位与 Model Prompt 空缺，来源为 `B06/RB-006-01/03/09`、`AS-006-01/02/13`。

## D-050 Model 协议、网络与三阶段 self-test

状态：已确认产品契约；目标平台传输与 adapter 证明待完成

v0.1 正式支持 `openai-chat` 与 `anthropic-messages` 两套协议 adapter。两者都必须完整实现并测试 streaming、native tool/control、usage、错误、取消与 retry；不包含 OpenAI Responses，也不以自然语言模拟 tool calling。一个 `Model.<Name>` 仍是完整连接实例，正式拥有自己的 `SystemPrompt`、endpoint、协议、远端 model ID、明文 Key、能力、streaming、timeout/retry、输出限制、Description 和 adapter typed options；配置物理顺序决定默认，不拆 Provider/Credential 层。

发行包自带经目标平台证明的 TLS-capable curl 与 CA，不依赖 XP 系统 TLS。用户显式配置的 HTTP endpoint 可以使用，但配置保存与 endpoint 变化必须清楚警告 Key、Prompt 和回复会以明文传输；HTTPS 永不自动降级。stunnel 只是 self-test 在实际 TLS 不可用时给出的外部安装/配置建议，不随包、不自动安装；用户可以显式配置本机 loopback stunnel endpoint。全局 proxy 保留，自动 redirect 只允许 same-origin，改变 origin 必须显式修改配置。每 Model retry 按阶段有界，接收任何 canonical response event 后不自动重发 logical request。

self-test Stage 1 离线检查完整配置、文件/组件、Context mapping/Catalog 性能和终端快捷键能力；Stage 2 在清楚 consent 后检查全部 enabled Model 的真实 auth/stream/tool/control，继续收集全部失败且 required checks 全绿才可进入下一阶段；Stage 3 只使用已通过 Model 做 advisory 语义合理性审阅，不自动修改配置或覆盖 Stage 1/2 事实。启动配置可以指定运行到 `off|stage1|stage2|stage3`，但不能跳阶段或绕过在线 consent。

本决定细化 D-028、D-031、D-036 与 D-039，来源为 `B06/RB-006-01/04`、`AS-006-06..09`。

## D-051 AgentLoop、DoubleCheck、预算与压缩

状态：已确认产品与状态机方向；精确内部常量由规格和证明冻结

AgentLoop 使用固定 typed controls `finish`、`ask-user`、`refuse`；没有 control 的完整普通回复保存为 `model-yield` 并进入 waiting-user，不把 provider stop 猜成 completed。queue 只在上一 main turn 安全 completed 且没有 pending/unknown 时自动启动，并支持 list/delete/edit/reorder/clear；steer 取消可取消的采样/复核和未开始工具，在同一 turn 注入；最多一个 side 与 main 并存；取消始终作用于当前焦点最内层活动。所有 logical request 通过同一有界 Model scheduler，核心保持一个简单的单线程事件泵和单一领域状态源。

有效 `DoubleCheck=true` 时完成复核始终启用，不能被 targets 子项关闭；高风险动作复核可以单独启停。完成复核与动作复核默认使用当前 turn Model，也可分别指定 `TerminationReviewModel`/`ActionReviewModel`，跨 endpoint 首次使用需确认。reviewer 不能放宽 Permission；finish 明确指出缺口时同一 turn 继续，uncertain/失败/超限进入 waiting-user。`DoubleCheckGoal` 是有界的完成验收目标，不创建 plan state 或授权。

request、turn 与进程都具有不可关闭 hard caps；用户配置只能在安全范围内收紧。retry 有界，无进展先产生一次 durable warning并允许一个受剩余预算约束的策略改变，重复后进入 stuck。v0.1 不计算金额。压缩只重建 model view：一个结构化摘要前缀加最近完整 atomic groups，XML 完整事实不删除；摘要失败保留旧 view，单个必需 group 超窗时停止，优先提示 Context 历史中曾使用且窗口足够的 Model，不自动切换。

本决定细化 D-020、D-021、D-027 与 D-033，来源为 `B06/RB-006-01`、`AS-006-03/10/11`。

## D-052 Tool、Permission、raw shell 与改动边界

状态：已确认产品能力；平台进程与文件原语证明待完成

首版固定 tool registry 为 `list/read/search/write/patch/rename/delete/exec`，全部使用版本化 typed envelope 并串行执行。direct tools 使用严格字段；`exec` 的 command 是 opaque 原始字符串，Runtime 不解析它来伪造细粒度 containment。Windows shell 固定 `cmd.exe /d /s /c`，Linux 固定 `/bin/sh -c`；只支持前台非交互进程，无 PTY、tracked background job、detached job 或 direct HTTP tool。

Permission 的正式能力字段保持简单：`Read/Write/Delete/Shell/OutsideWorkspace`，每项按 typed allow/confirm/deny 语义求值；发行模板只有顺序为 Std、Readonly 的两个 profile，物理第一项是默认。名称、Description 和 SystemPrompt 只帮助模型理解，实际行为只看矩阵。首版没有持久 grant、独立 SensitiveRead、OS sandbox 或 Runtime 自动 backup/undo。

direct 写入使用 expected raw-byte digest、no-replace/atomic publish 和 diff 证据；direct delete 只处理文件或空目录，不提供 direct binary mutation。Git status/diff 可以作为证据增强，但 commit/push/reset/stash 只在用户明确要求时作为普通获批 raw shell 动作；Runtime 不自动 stash、commit、回滚或管理 `backup/`。

本决定细化 D-034，并关闭 D-043 的能力矩阵空缺，来源为 `B06/RB-006-01/09`、`AS-006-07/12/13`。

## D-053 Context XML 提交、原位接盘与浏览入口

状态：已确认产品与存储协议基线；XML 库/旧机性能与替换原语待证明

长期事实仍只有主 INI 与每个 Context 的单 XML。为正确并发和崩溃恢复，允许同目录短寿命 temp、lock、previous-valid 控制物，但不允许长期 WAL 或第二事实源。每次提交从旧 XML 流式生成完整新 XML，flush/验证后通过目标平台可证明的原子或可恢复替换发布；不能把不合法的根后追加当成实现。单 XML 大小、延迟与内存 hard limits 由 XP x86/CentOS 7 长会话证明冻结。

外来 XML 由用户先放到正确镜像位置；context-repl 原位只读完成 schema/大小/一致性与 Model/workspace/Permission mapping，确认后直接取得该文件 writer，不自动复制来源。历史 approval/grant 只作审计。

context-repl 有两个显式入口：`recent` 是快速最近列表，`full` 是完整目录树/全部 Context Catalog。两者共用同一个 Resolver、详情、搜索、rename/rebind 和永久 delete controller；不提供 trash/restore，也不按 digest 扫描移动候选。活动锁对象不可外部管理修改；selection stale 或 active XML 被移动/替换/改写时 fail-stop，只有显式刷新/self-fix/rebind/recovery/exit。裸 `yaca` 不触发 recent/full 扫描。

本决定细化 D-035、D-041、D-045 与 D-047，来源为 `B06/RB-006-01/07`、`AS-006-14`。

## D-054 CLI 与兼容 TUI 共用 semantic action registry

状态：已确认语义与正式拼写；目标终端按键证明待完成

顶层规范长名包括 `--self-test`、`--model-repl`、`--config-repl`、`--context-repl recent|full`、`--continue`、`--help`、`--version`；`--` 明确结束选项解析。跨平台提供唯一、不冲突的 `-` 简写；Windows 另外接受相同词根的 `/` 简写，Linux 永远把 `/...` 保留为绝对路径。长名是文档和错误中的 canonical spelling，短形式不建立第二行为。非 TTY 只执行参数完整的显式动作，不弹交互审批。

chat 的文本后备固定为 `.queue` 及 `list|delete|move|edit|clear`、`.immediate`、`.side`、`.multiline`、`.cancel`；它们分别与 queue/Ctrl+Enter/Alt+Enter/Shift+Enter/Esc semantic action 等价。`.immediate` 使用正确 English 拼写，不保留 `.immidiate`。快捷键、点命令、argv、help 与补全全部由同一 registry 投影。

规范界面是追加式逐行 ASCII transcript、少量基础颜色/高亮、有界代码/tool/Git diff preview；能力不足只降级表现和快捷键，不删除动作。Stage 1 报告输入后端能力，显式 TTY self-test 可以做交互按键检查；无法区分组合键时显示点命令 fallback，不把 yaca 整体判为失败。v0.1 不提供 bell、desktop notification 或显示模式开关。

本决定完成 D-029、D-033 与 D-042 的 CLI/TUI 待决部分，来源为 `B06/RB-006-01/08`、`AS-006-04/05`。

## D-055 诊断只使用终端与既有 XML，不提供网络外发

状态：已确认

用户错误使用稳定 error ID、简明 English/ASCII 消息和 `.details`；自动 retry 显示原因/次数并可取消。Ctrl+C、Esc、EOF 与 broken pipe 进入统一 close，已发生副作用不伪装回滚，无法证明结果就持久化 unknown。

诊断只投影到终端、self-test/support stdout 与健康 Context XML 中的审计事实；不生成 standalone diagnostic XML、独立轮换日志、telemetry、一次性 diagnostic upload 或后台 spool。配置/Context 尚未建立的 fatal error 只写 stderr 和稳定 exit code。这个选择使 diagnostic-upload 条件分支不适用，并继续禁止启动/定时器的隐式联网。

来源为 `B06/RB-006-01`、`AS-006-15`，细化 D-036/D-039。

## D-056 三个便携 zip、邻接数据根与发布证据

状态：已确认发行契约；实际构建和目标平台证据待完成

v0.1 发布三个独立 zip：Win32 x86、Win64 x86_64、Linux x86_64。Windows zip 根包含 `yaca.exe`、`Install.cmd`、`README.txt`、`LICENSE`、`docs/`；Linux 使用对应 `yaca`、`Install.sh`、`README.txt`、`LICENSE`、`docs/`。可执行程序原地运行，运行依赖最终由 luainstaller 嵌入，`__yaca__` 永远与 executable 相邻；没有另一套 system data root、安装数据库或 updater。

`Install.cmd`/`Install.sh` 只做简单且可解释的程序存在/可启动/基础自检、目录适合与可写判断；目录不合适时询问，用户确认后添加 executable 所在目录到 PATH。脚本不使用 MD5、安装状态数据库、复制引擎或复杂完整性算法。发布完整性由发行 SHA-256 负责，不由安装脚本重算一套算法。

三个包分别执行完整测试、独立放行，并发布 SHA-256、最小组件/许可证 manifest、SBOM、构建摘要和对应平台完整测试摘要。v0.1 不要求来源签名，不提供内建更新检查、下载或自动安装。Windows x86/XP 与 x64 qualification 放在最后打包阶段；证据证明需要时，允许对 `../luainstaller` 做最小、独立设计/测试/提交的 guard/toolchain/profile 适配，现在不提前修改。

本决定取代 D-037 的双包/安装形态待决状态并细化 D-004/D-015，来源为 `B06/RB-006-01/02/05/06/07`、`AS-006-16/17`。

## D-057 集中问卷已回答，但实施仍受规格和技术证明门约束

状态：已确认流程状态

`OWNER-QUESTIONS-01.md` 的 29 个集中问题已经全部收到负责人回复，原先 248 个 atomic `unanswered` 不再代表产品选择缺失。集中答案必须按 `DISCUSSION-BATCH-06.md` 的断言投影到原子登记、唯一 owner 规格、配置/Context schema、状态机、CLI/action registry、测试与 readiness gate；纯库/API/常量/性能问题转为技术证明，不再要求负责人凭偏好选择。

答完产品问卷不等于可以立即编码。进入逐子系统实施计划之前，P0 owner 规格仍须消除“候选/任选”分支，关键旧平台能力、XML 提交、进程取消、网络/TLS、luainstaller 三目标构建和最终包必须有明确 proof plan 与失败退路。若证明失败且任何退路会改变本文件的用户保证，只重新打开那个最小产品差异。

来源为 `B06/RB-006-01..09` 与 `DECISION-RESOLUTION-PROTOCOL.md`。

## D-058 本机 Web 产品族预留：`yaca-web` 与 `yaca-ie6`

状态：已确认预留意图与服务端技术栈基线；**不**撤销 D-044 的 v0.1 零表面；Web 实现未授权

2026-08-10，项目负责人在设计恢复阶段明确要求：为 **本地 Web 版本** 留出设计位置，并按兼容级别分为两条产品线。同日补充服务端技术栈：

| 产品线 | 角色 | 浏览器意图 | 服务端技术栈（已确认） |
| --- | --- | --- | --- |
| `yaca-web` | 本机本地 Web 主线 | 可宽于 IE6；默认仍保守，不默认现代 SPA | **Java 8** |
| `yaca-ie6` | 同族 IE6 线 | **有意** 兼容到 Internet Explorer 6；HTM/JS/CSS 以 `coding-style.txt` IE6 规则为硬约束 | **PHP 5.4** |

技术栈含义（现行约束，细节仍待 Web 决策包）：

1. **分栈、不混用**：`yaca-web` 不以 PHP 为实现语言；`yaca-ie6` 不以 Java 为实现语言。两条线通过 **共享领域协议 / 对核心 yaca 的消费边界** 对齐语义，不要求共享同一进程或同一运行时。
2. **不进入核心 Lua 发行物**：Java 8 与 PHP 5.4 都不是 v0.1 核心 `yaca` zip 的依赖；不得把 JRE/PHP 塞进 terminal 三目标包。
3. **版本即基线，不是“最低可试”口号**：
   - `yaca-web` 以 **Java 8** 语言级别与可用标准库为设计/验收基线；不得默认升级到需要更高 JDK 才可构建/运行的语法或 API，除非日后单独修订本决定。
   - `yaca-ie6` 以 **PHP 5.4** 语言级别与同代扩展假设为设计/验收基线；不得默认使用仅 PHP 7+ 才有的语法/标准库行为。
4. **前端仍分轨**：服务端栈不取消 IE6 前端硬约束；`yaca-ie6` 的页面交付仍须在 IE6 可解析的 HTM/JS 内完成。
5. **与核心的耦合方式未决**：HTTP 旁路进程、本地 IPC、显式启动的独立服务等仍属 Web 决策包；无论何种方式，都不得削弱 Context 单 writer、Permission 与 DoubleCheck 不变量。
6. **框架默认保守**：未批准前，不引入现代重型 Web 框架作为默认（例如强迫 Java 8 线使用仅新版 Spring 支持的特性，或 PHP 5.4 线使用 Composer-only 现代栈）；具体库白名单在开题时再冻结。

本决定与 D-044 的关系：

1. **v0.1 核心 TUI 产品** 继续完全排除 Web：配置、CLI/help、Runtime listener、self-test、依赖与三个核心 zip 仍必须零 Web 表面。
2. **允许** 在 `.develope-docs/web-tracks/` 与 17 号子系统文档中维护空预留与未来决策提纲；允许仓库根 `web/` 仅作指向设计预留的说明目录。
3. **禁止** 借预留之名写入可触发的 Web 空壳实现、假 server、未审计前端/后端框架依赖，或把内部 application service 宣传成已稳定的浏览器 API。
4. Web 两条线默认视为 **独立产品面/独立设计包**，不阻塞核心 v0.1 的规格硬化、技术证明与实施顺序。
5. 进入任一 Web 线的实现前，仍须完成 17 号文档所列的实现级重开清单（本机边界、身份/CSRF、审批与 writer、IE6 传输降级、打包与验收矩阵、各栈的宿主/打包证据等）。
6. 本决定 **不** 重开图像/音频/transcription/TTS/public remote-headless；那些仍受 D-044 约束，除非另行单独重开。

设计入口：`subsystems/17-web.md`、`web-tracks/README.md`、`web-tracks/yaca-web.md`、`web-tracks/yaca-ie6.md`。

来源：2026-08-10 负责人会话指示（本地 Web + 双兼容线预留；`yaca-ie6`=PHP 5.4，`yaca-web`=Java 8）。

## D-059 Context hash 用户可见形式：大写十六进制

状态：已确认（SQ-01 = B）

面向用户的 Context hash 固定为 **16 个大写十六进制字符**，字母表为 `0-9A-F`。

规则：

1. **显示**：TUI、CLI、`.status`、列表、导出 Markdown、错误文案中出现的 hash 一律输出为大写 `0-9A-F`。
2. **输入**：选择器在判定“是否为 hash 形态 token”时，先检验长度恰好 16 且每个字符属于 `0-9A-Fa-f`；若成立，则把 `a-f` **规范化为大写** 后再与候选 hash 比较。规范化不得作用于非 hash 形态的名称选择器。
3. **形态判定**：只有“长度 16 且（规范化后）为合法 hex”的 token 才进入 hash 匹配路径；否则整段按 **精确名称** 规则处理（仍无 `hash:` / `name:` 前缀）。长度不是 16、或含非 hex 字符的输入不得被截断/补齐成 hash。
4. **算法归属**：从逻辑路径字节到 16 位 hex 的具体摘要算法、编码与截断方式属于技术证明；必须保证同一逻辑路径稳定映射到同一规范大写 hash，路径变化后旧 hash 立即失效（D-023）。
5. **兼容**：历史文档或用户笔记中的小写 16 位 hex 在输入时有效；程序自身永不“只认小写显示”。

本决定细化 D-023/D-024 中用户可见 hash 契约，关闭 SQ-01。碰撞呈现、损坏近处同名策略仍分别由后续 SQ 冻结。

来源：2026-08-10 负责人答复 `SQ-01 B`。

## D-060 近处同名但不可用：MatchedUnavailable fail-stop

状态：已确认（SQ-02 = A）

当 Context Resolver 在某一搜索环内观察到 **精确名称命中**，但该候选 XML **损坏、不可读或未通过有效性探测** 时：

1. 本次解析以结构化结果 **`MatchedUnavailable`** 终止（或与之等价的稳定错误 ID，由 15 号 registry 命名）。
2. **不得** 继续扫描更远搜索环，寻找同名且可用的其它会话并自动连接。
3. **不得** 把已观察到的损坏近处命中丢弃后，假装“未找到”或静默降级为更远 `Unique`。
4. 用户可见信息必须指出：近处存在同名目标但不可用，并给出可定位的路径/诊断线索与 self-fix / context-repl 入口；不得只显示笼统 NotFound。
5. 用户仍可改用 **合法 hash 选择器**、在 context-repl 中显式点选其它候选，或修复/移除损坏文件后重试；这些都是 **显式** 动作，不是 Resolver 的自动回退。
6. 若该环 **应扫范围不可读** 以致无法证明“近处是否还有其它同名”，仍优先 **`ScanIncomplete`**（既有规则），不能用部分观察冒充 `MatchedUnavailable` 或 `Unique`。
7. “一个可用 + 一个损坏同名”等更细混合状态的优先级由后续 SQ-04 冻结；本决定至少锁定：**仅有损坏近处名称命中时不得自动连远处**。

本决定细化 D-024 的 Resolver 收口语义，关闭 SQ-02。

来源：2026-08-10 负责人答复 `SQ-02 A`。

## D-061 短名首个命中；精确指定只用 hash

状态：已确认（负责人澄清 + 收口 SQ-03 前提）

Context 的长期身份仍是 **逻辑路径**；用户可见 hash 仍是对该路径整串做摘要后的 16 位大写 hex（D-023、D-059）。文件系统上 **同一完整路径** 不能有两个 XML；跨目录可以出现相同 **显示名/basename**，但短名解析不再要求“同环唯一”。

选择器规则：

1. **hash 形态**（D-059：长度 16 且 `0-9A-Fa-f`，规范化为大写）  
   - 用于 **精准指定** 某一个 Context。  
   - 仍按搜索环距离优先；当前环完整必要扫描后：唯一可用 hash → 连接；多个可用相同 hash → `HashCollision` fail-closed（极低频安全网）；环不完整 → `ScanIncomplete`。  
   - 不得按枚举顺序“碰到第一个 hash 就返回”而不完成当前环的 hash 唯一性证明。

2. **非 hash 形态（短名 / 显示名）**  
   - 用于便捷选择，**不**承诺全局或同环唯一。  
   - 按既定 Resolver 扩环顺序（由近到远）流式查找 **精确名称** 命中；**首个可用** 命中立即胜出并停止，**不** 为排查其它同名而扫完当前环，也 **不** 产生 `AmbiguousName` 选择页。  
   - “首个”的扫描顺序必须是规格写死的确定性顺序：环序（距离）优先；环内按稳定键（规范 `LogicalPath` 升序）遍历候选，**禁止** 依赖文件系统裸枚举顺序作为产品语义。  
   - 若按该顺序将命中的 **第一个精确名称候选** 存在但不可用（损坏/不可读/未通过有效性探测）→ 适用 D-060：`MatchedUnavailable` fail-closed，**不得** 跳过该损坏项改连更远的同名可用会话。  
   - 全部可读范围无可用精确名称命中 → `NotFound`（或环不完整时的 `ScanIncomplete`）。

3. **产品话术**  
   - 短名 = 方便，可能随工作目录/镜像位置不同而连到不同会话。  
   - 需要稳定、可脚本、可分享的指定 → **必须用 hash**（或 context-repl 点选已解析行，点选携带的是已解析候选，不是再猜短名）。

4. **取代关系**  
   - 本决定修订 D-024 中“同环名称必须证明唯一 / `AmbiguousName`”对 **短名** 的要求。  
   - SQ-03 原 A/B/C（歧义列表页）对短名 **不再适用**；hash 碰撞仍 fail-closed，不提供“静默连第一个 hash”。

来源：2026-08-10 负责人答复：短名「首个命中」；精准指定要用 hash。

## D-062 非 TTY 在线 self-test：无显式授权则硬失败

状态：已确认（SQ-05 = A）

self-test 仍严格 Stage 1→2→3。Stage 1 离线；Stage 2/3 涉及真实 Model 联网与费用/数据范围，必须先有 consent。

**非 TTY**（无交互确认能力：管道、重定向、CI、非交互脚本等）规则：

1. **仅 Stage 1**（`through_stage=1` 或等价“只跑到离线阶段”）允许在无额外授权时执行。
2. 目标阶段 **≥ 2**（将进入 Stage 2，或声明要跑到 2/3）时：若本次调用 **没有** 面向该次 invocation 的 **显式 online-consent 授权**（具体 argv 拼写由 CLI action registry 冻结，语义为“我接受本次在线 self-test 的联网与费用风险”），则 **立即硬失败**：稳定 error ID、非零 exit、**不发起任何 Model 网络请求**。
3. **禁止** 因 INI `StartupSelfTest=stage2|stage3`、环境变量、或“上次同意过”而在非 TTY 自动进入 Stage 2/3。
4. **禁止** 把缺少 TTY 当成“默认同意”或从 stdin 半交互猜 Yes。
5. 交互 TTY 仍使用可见 consent 流程（展示 Model/范围/费用上界等）；与非 TTY 的显式授权是同一语义服务的不同投影，不是两套阶段规则。
6. 非 TTY 下若配置了启动前 `StartupSelfTest` 要求 stage2/3，而本次启动无法完成交互 consent 且无合法显式授权 → **Agent 启动失败**，不得静默降级为跳过在线阶段后进入 chat（除非用户显式只要 stage1 的配置值）。
7. Stage 3 不得跳过 Stage 2；非 TTY 下若要以同一命令跑到 Stage 3，必须在进入 Stage 2 之前已具备第 2 条的显式授权（一次授权可覆盖该次 invocation 内随后的 Stage 3，因 A 要求的是“无授权则不得进入 ≥2”，不是“每阶段单独 flag”——与“无授权硬失败”一致：有授权则可按 1→2→3 顺序执行；**无**授权则在拟进入 2 之前失败）。

说明：负责人选择 A 的核心是 **无显式授权不得在非 TTY 联网**；同一次已授权 invocation 内 2→3 顺序执行不要求第二个产品级 consent 开关（与“B 的产品差异”相比，A 强调失败默认，不禁止单次授权后跑完声明阶段）。精确 flag 词形留给 registry，不在此用未确认拼写写入用户契约。

来源：2026-08-10 负责人答复 `SQ-05 A`。

## D-063 Context HardLimit：足够大；触顶为异常；引导新开对话与接盘 Prompt

状态：已确认（SQ-06 负责人产品语义）

Context 单 XML 的文件大小、提交延迟、内存等 **hard limit** 仍由目标机技术证明给出可复现数字并写入发行 manifest（TP-008/009 等）。产品对 limit 与触顶体验的要求如下：

1. **HardLimit 必须足够大**  
   - 设计与证明目标是：正常 Coding 长会话在声明支持的工作负载下 **不应** 常规触顶。  
   - 触顶应被当作 **异常/容量事故**，不是日常“该去压缩一下”的主路径。  
   - 不得把 hard limit 设得过小，以致正常使用频繁 fail-stop；也不得为了“几乎永不触顶”而取消 limit 或改用未证明的第二事实源/WAL。

2. **触顶时的运行时行为**  
   - 在新的会扩大正式 XML / 突破 hard limit 的 durable 写入与 Model/工具副作用之前 **fail-stop**。  
   - 不得丢弃历史、静默截断事实、自动永久删除，或谎称已通过压缩腾出了事实存储配额（压缩只重建 model view，不删除完整事实史——D-051/D-053）。  
   - 已写入的正式 generation 保持可打开、可导出、可只读查看（在不突破 limit 的前提下）。

3. **用户可见引导（产品必须做）**  
   触顶时用清晰 English/ASCII 状态（可附稳定 error ID）告诉用户这是 **异常容量状态**，并至少提供：  
   - **提醒新开对话**：建议在合适工作区开始 **新的 Context** 继续工作，而不是继续往当前 XML 硬写。  
   - **建议的接盘 Prompt**：提供一段可复制的 **handoff prompt**（及如何使用的简短说明），供用户粘贴到 **下一个** 会话，让后续 Model **阅读/承接关键上下文**（例如：要求先读导出的 Markdown/关键文件路径、目标、未完成项、约束与风险）。  
   - 文案不得暗示 Runtime 已自动把完整历史注入新 Context，或已自动调用下一 LLM；接盘是 **用户显式** 开新会话并粘贴/附带材料。

4. **明确不做**  
   - 不因触顶自动创建新 Context、自动 fork、自动切换会话。  
   - 不以“自动 compact 后继续无限写”作为默认解脱路径（用户仍可手动 compact 改善 model view，但不得当作解除 XML hard limit 的保证）。  
   - 不提供 trash/软删历史来“腾配额”作为 v0.1 主路径。

5. **与数字证明的关系**  
   - 具体 MB/ms/峰值内存阈值 = 技术证明产物，须满足本决定“足够大以至于触顶为异常”的产品检验：在代表性长会话夹具上触顶率应符合发行测试对“异常”的定义。  
   - 若证明无法在旧机上同时满足“足够大”与稳定运行，只能把 **最小反例** 交回负责人调整保证，不得私自改 WAL 或砍历史。

来源：2026-08-10 负责人答复 SQ-06：HardLimit 应足够大，触发属异常；提醒新开对话并给出建议 Prompt 供下一 LLM 接盘阅读关键内容。

## D-064 分焦点提示符 + 可选基础色（XP 可降级）

状态：已确认（SQ-07 = A + 色彩增强）

### 提示符（权威身份；无色也必须可读）

| 焦点 | 提示符（行首 ASCII） |
| --- | --- |
| chat | `>>` |
| 等待审批 / 需确认动作 | `??` |
| model-repl | `model>` |
| config-repl | `config>` |
| context-repl | `context>` |
| self-test 交互步 | `test>` |

规则：

1. 提示符是焦点的 **主线索**；不得只靠颜色区分焦点。  
2. 无颜色、`NO_COLOR`、dumb 终端、重定向非 TTY 时：仅输出上表纯文本提示符，行为与有色时相同。  
3. 不引入用户自定义快捷键或自定义提示符主题系统（D-029）。

### 可选色彩（增强，非必需）

允许对提示符（及必要时同一行的标签）使用 **基础终端色** 做区分，例如：

| 焦点 | 建议色（逻辑名） | 说明 |
| --- | --- | --- |
| chat `>>` | 浅色 / 暗淡（bright black 或低对比 white） | “普通输入” |
| 审批 `??` | Yellow | 需人决定 |
| model-repl `model>` | Green | 与发行模板 Permission/Model 常用绿可区分开即可 |
| config-repl `config>` | Cyan | |
| context-repl `context>` | Blue | |
| self-test `test>` | Magenta | |

精确到 16 色名表中的哪一个枚举值，由 TUI 规格与目标机 transcript 微调，但不得使用 true-color / 256 色作为必需。

### XP / 旧终端兼容

1. **能力探测**：仅在确认当前输出端支持安全的基础着色时上色（Windows 可用 console 属性 API；POSIX 可用基础 ANSI **仅当** 判定可接受）。  
2. **Windows XP conhost**：不假设默认启用 ANSI 转义；着色必须走该平台已证明的路径，失败则无色。  
3. **禁止**：闪烁、复杂光标动画、用颜色表达唯一安全状态（例如“绿色=已批准”而无文字）。  
4. 审批通过/拒绝仍以 **显式文本动作** 为准，颜色只辅助。

来源：2026-08-10 负责人答复 `SQ-07 A`，并要求可做色彩区分（如 `>>` 浅色、`model>` 绿色等），考虑 XP 兼容。

## D-065 `.cautious` 语法：status / on / off / toggle / reset

状态：已确认（SQ-08 = A）

`.cautious` 只管理 **当前 Context** 对 `DoubleCheck` 的会话覆盖，写入该 Context XML；**不**修改用户 INI 默认、**不**切换 Permission profile、**不**自行解释 DoubleCheck 含哪些子复核（子复核范围仍由 D-027/D-051 与配置 schema 决定）。

### 语法

| 形式 | 行为 |
| --- | --- |
| `.cautious` | **只读 status**：显示 INI 默认值、当前覆盖（inherit 或 true/false）、**有效值**；不修改任何状态 |
| `.cautious on` | 覆盖 = true（本 Context 有效开启 DoubleCheck） |
| `.cautious off` | 覆盖 = false（本 Context 有效关闭 DoubleCheck） |
| `.cautious toggle` | 以 **当前有效值** 为基准翻转，并写成显式 true/false 覆盖（不是 toggle inherit） |
| `.cautious reset` | 清除覆盖 → inherit，有效值回到 INI 默认 |

### 语义要点

1. **`off` ≠ `reset`**：`off` 是强制关；`reset` 是跟随配置（配置若为 on，reset 后仍为 on）。  
2. 修改成功后须 durable 写入 Context XML 的会话元数据（与既有 `.cautious` 持久化决定一致）；失败则明确错误且不假装已切换。  
3. 无参数 **禁止** 当作 toggle，避免误触改安全相关开关。  
4. 未知子参数 → 稳定错误 + 短用法提示；不部分执行。  
5. CLI/TUI 同一 semantic action 投影；非 TTY 需要改覆盖时走 registry 中的等价 action，不得静默忽略。  
6. status 输出为可阅读的固定字段顺序（default / override / effective），English/ASCII 机器字段名可在规格中最终拼写。

来源：2026-08-10 负责人答复 `SQ-08 A`。

## D-066 队列条目 `#N` + 可配置上限（默认 9）

状态：已确认（SQ-09 = A + 配置最大数量，默认 9）

### 用户可见 identity

1. 每个 **尚未开始** 的 queue 项在当前 Context 的排队生命周期内拥有用户可见序号 **`#1` … `#N`**（显示与命令中可写 `1` 或 `#1`，规范化为同一 id）。  
2. 序号在 **该项存活期间稳定**：list 重绘、插入其它项、编辑正文 **不得** 改变已有项的 `#N`。  
3. `.queue list` 展示 `#N` + **单行截断摘要**（完整正文仅经 edit/详情取得）。  
4. `.queue delete|move|edit` **必须** 使用该稳定 `#N`，不得使用“当前屏幕第几行”的临时行号。  
5. **clear** 或队列变空后，序号 **重新从 `#1` 分配**（A1：不长期保留空洞号段，上限小且默认 9 时更清晰）。  
6. 内部可另有实现级 id；用户与点命令契约只暴露 `#N`。未开始 queue **默认不** 作为完整 turn 事实写入 XML；进程退出可丢弃未开始 queue（既有 close 语义）。不打开“跨会话保留 queue 号”的产品面。

### 数量上限（配置）

1. 主 INI 提供 **可配置的 queue最大条数** 字段（精确 section/key 拼写由配置 schema 冻结；逻辑名建议落在 Agent 相关区，例如 `QueueMaxItems`）。  
2. **发行默认值 = 9**（即最多同时存在 `#1`…`#9`）。  
3. 合法范围由 schema 给出有界整数（至少含默认 9；上限硬顶由 Runtime/发行 manifest 收紧，用户只能在安全范围内配置，不能设为无限）。  
4. 当队列已满（当前未开始项数 ≥ 配置值）时：新的 queue 接纳（含普通 Enter 排队）**必须拒绝**，稳定错误 + 提示删/改/clear 或等待自动出队；**不得**静默丢弃最旧项或自动覆盖。  
5. 将配置值调 **小于** 当前已有项数时：不自动删除已有项；在项数回落到新上限之前拒绝新增（或要求用户先删到合规——规格可选固定为“只拒新增”）。  
6. 配置变更按既有 turn 边界 generation 规则生效于后续接纳，不撕毁已在队项的 `#N`。

### 与标签的一致性

TUI 中 queue 相关状态标签可与 `#N` 对齐（如既有 `[QUEUE #2]` 方向），避免另一套编号。

来源：2026-08-10 负责人答复 SQ-09：A，并含配置文件最大数量限制，默认 `#9`（最多 9 条）。

## D-067 自动压缩：状态可见、不打断确认

状态：已确认（SQ-10 = A）

当 Runtime 因 model-view 窗口策略 **自动** 发起 compaction（独立 `compaction` purpose）时：

1. **必须** 在 transcript 中追加简洁、可理解的 STATUS 块，覆盖至少：开始、结束（成功 / 失败 / 取消 / 无收益仍超限）、以及若适用的“建议换用更大窗口 Model（不自动切换）”。  
2. **不得** 在自动路径上弹出必须回答的确认框（`??` Yes/No）作为默认；费用敏感通过可见 STATUS 与 usage 记录满足，不靠每次打断。  
3. **不得** 在成功时完全静默（避免用户不知道发生了独立 Model 请求与 usage）。  
4. 不得静默丢弃用户未提交 draft；与 busy/queue 规则一致，输入可继续按既有 lane 处理。  
5. 进行中的 compaction 在仍可取消时，用户可用既有 cancel 路径（Esc / `.cancel` 等焦点规则）取消；取消后保留旧 model view，并 STATUS 说明。  
6. 失败保留旧 view、不破坏 XML 事实（既有不变量）；STATUS 须诚实，不得把失败写成成功。  
7. 手动 `.compact`（若 registry 提供）默认采用 **同等可见 STATUS**；是否另加确认不在本题强制——默认与自动路径一致（无强制确认），除非日后单独开题。  
8. 本决定不改变：compact 只改建 model view、不删事实史；不解除 XML 存储 hard limit（D-063）。

来源：2026-08-10 负责人答复 `SQ-10 A`。

## D-068 Context XML 为内部格式；对外以导出为主

状态：已确认（SQ-11 = C）

v0.1 对 Context 持久化格式的 **对外产品承诺** 如下（修订此前“优先第三方可读公共 schema”的表述强度）：

1. **内部格式**  
   - 活动 Context XML 是 **yaca 私有/内部** 的持久化与恢复格式，服务 yaca↔yaca 的打开、保存、崩溃恢复与同机/拷贝后由 **yaca** 继续写入。  
   - **不** 将 Context XML 标为稳定公共 API，**不** 承诺第三方工具读写兼容，**不** 提供第三方 writer conformance 套件作为 v0.1 发布门。

2. **人类与跨工具可读主路径**  
   - 面向人、其它 LLM 或外部流程的默认可读交付是 **显式导出**（如 Markdown export 等 registry 中的 export action），以及用户工作区内的普通文件。  
   - HardLimit 触顶时的接盘 Prompt（D-063）应引导使用 **导出/关键文件**，不得暗示“把原始 XML 交给任意第三方阅读器即可获得保证语义”。

3. **schema 演进**  
   - 元素与版本可随 yaca 小版本调整；yaca 对自己的世代负责迁移/拒绝不兼容文件并给出明确错误。  
   - 可提供 **尽力而为** 的内部说明或注释供开发者理解，但 **不是** 冻结的公共契约，也不对外部解析器的正确性背书。

4. **外来 XML 与 yaca 导入**  
   - 用户仍可将 XML 放进镜像树并由 **yaca** context-repl 做校验/mapping/确认后接盘（D-053）：这是 **yaca 产品功能**，不是对第三方格式生态的承诺。  
   - 历史 approval 仍只审计；Key 仍不进 XML；不自动重放工具。

5. **明确不做（v0.1）**  
   - 不承诺“任何符合公开 XSD 的第三方写入 yaca 必须接受”。  
   - 不以第三方 reader 黄金测试作为发布阻断（可用内部 fixture 测 yaca 自身 round-trip）。

6. **与实现的关系**  
   - 实现仍须有 **确定、版本化** 的内部 schema 与 writer/parser（供 yaca 正确性与 TP）；“内部”不等于“无 schema 乱写”。  
   - 文档与 README 须诚实写明：XML 为内部存储；跨工具请用 export。

来源：2026-08-10 负责人答复 `SQ-11 C`。

## D-069 发布退路题不展开；假定三包含 XP 可 qualification

状态：已确认（SQ-12 关闭方式：不考虑降级分支）

规格冻结队列中原 SQ-12（“若 Win32 x86/XP 经合理努力仍无法 qualification，产品如何退路”）**不再作为产品选择题展开**。

1. v0.1 继续以既有硬门槛为准：Win32 x86（含 XP SP3）、Win64 x86_64、Linux x86_64 三个独立 zip（D-007、D-009、D-056 等），**不** 预写砍 XP、缩成双包或“实验性 XP”等降级产品面。  
2. 负责人立场：假定相邻 `luainstaller` **能够** 经 qualification（及若证据需要时的最小适配）支撑上述目标；发布工程按此假设排期与举证。  
3. 若未来 **实际证据** 证明该假设不成立，再单独立项、以最小差异重开兼容/发布决定；**现在不** 为假想失败预留 schema、README 双叙事或半吊子支持矩阵。  
4. 本决定不免除 TP-001/P0-16 的 **证明义务**：仍须在目标机给出启动与完整测试证据；“假定可以” ≠ “免测放行”。

来源：2026-08-10 负责人答复：不考虑 SQ-12 退路问题；假设 luainstaller 确实可以。

## D-070 离线自动规格硬化授权与停损（2026-08-10）

状态：已确认

项目负责人在设备离线前授权本轮 **无人值守的设计推进**，并冻结下列运行规则。本决定 **不** 授权产品 `src/*.lua` 实现（D-001 / D-057 仍有效）。

### 授权范围

1. **允许**：`.develope-docs/` 内 Wave 3 规格硬化、加深既有 W1–W2 首版、门禁/追踪文档同步、技术表格与保守方案择优（不改用户保证时）。  
2. **不允许**：产品源码实现、静默改 Std/Readonly Permission 矩阵或 capability 轴、新开 SQ 长卷、Web 实现、把 `bin/` 或 proof 半成品混入产品契约。  
3. **证明原型**：本轮 **未** 授权 modern proof 原型代码；若仅文档侧更新 TP 步骤/通过条件可写，不新建可执行产品路径。

### 产品规则（原「下一负责人问题集」收口）

1. **hard-cap / 预算数字**：**技术推导 + 用户可配置收紧**。发行 `RuntimeMax`（及同类不可关闭 hard caps）由规格/证明给出保守表与推导依据；用户 INI 只能在安全范围内收紧，不能抬高到超过发行 max。v0.1 仍不计算金额（D-051）。规格可先写维度、公式与「待目标机校准」范围，不得用随意偏好填假精确数字。  
2. **路径显示 vs hash**：**hash 与 Resolver 只消费 `LogicalPath` 规范形**。TUI/列表可显示对用户友好的本机路径（盘符、UNC 原貌等）；任何「显示路径」不得单独充当 hash 输入。文档必须说明「显示 ≠ hash 输入」。不引入双 hash。  
3. **TP 证明失败且退路改用户保证**：**停止擅自改保证**；写入最小 O 决策包（失败证据、影响面、可选最小产品差异），等负责人。禁止为通过证明暗加长期 WAL、弱 cancel 或缩小用户保证。D-069 仍只管打包 qualification 假定，不覆盖全部 TP 退路。  
4. **Permission**：Std/Readonly 矩阵与 capability 轴 **冻结**；离线不得增轴或改 allow/confirm/deny 结果。

### 工作顺序与技术择优

1. 主线优先级：**Wave 3 全线规格**（Runtime 窄 ABI → Path/Index → 数据/秘密矩阵 → 改动事务/压缩 view），可并行加深 W1–W2 至更接近「设计已确认」。  
2. 纯技术多方案且 **不** 改用户保证时：选 **最保守、最可证明** 的方案写入规格，记录备选与否决理由；不并列卡住等人。

### Git

1. 继续在 `main` 工作。  
2. 完整批次可本地 **commit**。  
3. **push** 仅在 **重大里程碑**（例如某一 Wave 3 子包整体完成、或门禁文档阶段性闭环），控制为少数几次；非里程碑中间态只 commit 不 push。  
4. 推送范围仅本仓库约定分支，不擅自开 PR/改远端保护规则。

### 停止条件

1. 做到 **自然断点** 即停（可交付的规格批次结束）；不设固定墙钟。  
2. 若触碰需改用户保证、Permission 轴、或 D-001 边界的事项：停并记入交接笔记 / 最小 O 包。  
3. 进度落盘：更新 `TRACKING.md`、`READINESS-GAP.md`、本文件，并维护简短交接笔记（见 `HANDOFF-AUTO-2026-08-10.md`）。

来源：2026-08-10 负责人离线前问卷答复（授权规格硬化；Wave 3 优先；hard-cap 技术推导；LogicalPath hash；TP 失败停等 O；Permission 冻结；重大里程碑才 push；自然断点停；保守技术择优）。
