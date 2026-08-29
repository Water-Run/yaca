# 00 产品契约与兼容性基线

更新日期：2026-08-29

状态：**计划已确认（C33/C34）**；[`contracts/product.lua`](../contracts/product.lua) 已冻结三目标、包形态与六条旅程，target/final-zip evidence 仍受 Gate R 约束

## 职责

定义 yaca v0.1 是什么、在哪些环境必须工作、用户从启动到退出会经历什么，以及哪些能力明确不属于产品。CLI、TUI、配置、AgentLoop、Context、Permission、打包和测试必须投影同一个产品契约，不能各自增加首页、隐式恢复、后台服务或空壳配置。

## 已确认的兼容性基线

- yaca 是单 Agent、terminal-only 的 Coding Agent；主体使用官方 Lua 5.5 语言级别与 ABI。
- Lua 程序由 `../luainstaller` 打包；发布物不得依赖系统已安装 Lua。
- Windows 有两个彼此独立的正式产物：Win32 x86 32 位包覆盖 XP SP3、Vista SP2、7 SP1、8、8.1、10、11；Win64 x86_64 包覆盖 7 SP1、8、8.1、10、11。每个包都必须在自己的完整版本矩阵中独立验收和放行，不能用 Win32 结果替代 Win64，也不能反向替代。
- Linux 使用独立的 x86_64 产物，CentOS 7 x86_64 是最低硬基线；最终支持的其他发行版仍需用实际发行候选完成完整测试。
- v0.1 不承诺旧 macOS，也不建立 macOS 专用实现或发布矩阵。
- v0.1 不提供 ARM、Windows on ARM 原生产物或其他未列出的 OS/架构。正式发布恰好包含 Win32 x86、Win64 x86_64、Linux x86_64 三个独立 zip；不能用现代系统 smoke test 推断旧系统兼容。
- 程序固定文案、命令、配置键和机器字段使用 English/ASCII；路径、用户 Context 名、消息、模型正文和 XML 使用 UTF-8 保真。Windows 文件系统必须经宽字符端口访问，终端显示降级不得改变真实路径或 hash 输入。

## 发布包与数据位置

Windows 两个 zip 使用相同的外层目录契约，根目录固定包含：

```text
yaca.exe
Install.cmd
README.txt
LICENSE
docs/
```

`yaca.exe` 在解压位置原地运行，Lua runtime 与运行所需依赖由 luainstaller 嵌入，不依赖系统 Lua。`__yaca__` 永远与实际运行的 `yaca.exe` 相邻；从其他当前目录或经 PATH 启动都不能把数据根漂移到调用目录。Linux zip 使用对应的 `yaca`、`Install.sh`、`README.txt`、`LICENSE`、`docs/` 布局，并遵守相同的原地运行、依赖嵌入和相邻 `__yaca__` 规则。

`Install.cmd`/`Install.sh` 只是薄安装辅助：从脚本自身位置确定发行目录，简单检查主程序存在、能够启动并完成无网络基础检查，以及发行目录是否适合且可写；目录不合适时先询问用户，确认后只把该发行目录加入 PATH。它们不复制程序、不建立安装数据库、不计算 MD5 或其他完整性摘要，也不承担更新、回滚或卸载管理。

每个 zip 独立生成 SHA-256、component/license manifest、SBOM、构建摘要和完整测试摘要，缺少任一所需证据就不放行该包。v0.1 不做代码签名，也不内置检查、下载或安装更新；用户通过外部渠道手工取得和替换 zip。

## v0.1 的简单完整产品形态

“完整”指 terminal Coding Agent 的选定闭环能够从配置、对话、工具执行、保存、显式恢复一直走到诚实退出；它不以功能种类数量衡量。v0.1：

- 只有一个逐行 TUI，不提供首页、全屏 dashboard、鼠标或多套 theme/mode。
- 不建立独立 plan state、`.plan/.execute` 或 PlanArtifact；模型在统一 AgentLoop、Permission 和工具契约内规划并执行。
- REPL 是独立顶层 CLI action；chat 不把管理 REPL 当作子页面打开再返回。
- Permission 名称只用于选择和显示，实际能力由 typed 配置字段决定。发行模板包含 `Std` 和 `Readonly`；Permission 的 Prompt/说明不能代替 Runtime enforcement。
- 不提供 Web、图像输入、音频输入、独立 transcription、TTS、公共 remote/headless IPC/RPC、MCP、插件、hook、skills runtime、第三方工具协议、子 Agent 或 Context 分支。
- 被排除能力在配置、help、schema、Runtime、self-test、依赖和 zip 中都必须为零表面；未来只有项目负责人针对具体 use case 显式重开设计流后才能出现。
- D-058 已为本机本地 Web 产品族登记 **设计预留**（`yaca-web` / **Java 8**；`yaca-ie6` / **PHP 5.4** + IE6），但 **不** 改变 v0.1 零 Web 表面，也 **不** 授权实现；JRE/PHP 不进入核心 zip。见 [17-web](17-web.md) 与 [web-tracks](../web-tracks/README.md)。
- Context XML 为 **内部存储格式**（D-068）；跨工具/人类可读默认走 **export**，不承诺第三方 XML 公共 API。

## 正常启动契约

主入口仍是 `yaca [directory]`，裸 `yaca` 与 `yaca .` 等价，目标必须是已经存在且能够进入的真实目录。

正常交互启动按以下顺序处理：

1. 校验发行包、目录、数据根和主配置。
2. 配置缺失/损坏或没有有效可用 Model 时阻断 Agent，给出对应管理入口；不进入空 chat。
3. 缺失/损坏配置时，help/version、bootstrap model-repl、config-repl、self-test Stage 1 和不调用模型的 context-repl 仍可用。
4. 若配置启用了启动前 self-test，则按所选最大阶段顺序运行；前阶段未满足不得进入后阶段，要求的阶段失败、取消或未完成时不进入 chat。Stage 1 包括 Context 镜像/workspace/Catalog/Resolver/hash 完整性与性能检查；Stage 2/3 仍具有独立联网、费用和数据范围 consent。非 TTY 下 Stage≥2 必须有本次显式 online-consent，否则硬失败，不得静默联网（D-062）。Stage 3 可提示 Model/Permission 名称、说明和真实配置/能力的语义错配，但只作 advisory。
5. 默认没有启动前 self-test，启动也不探测网络；暂时离线只在第一次显式模型请求时报告。
6. 裸启动不扫描 Context Catalog、不提示 recent，也不按退出标记区分所谓正常/异常历史；它直接进入新的 `not saved` chat。旧 Context 只能通过 `.context`、continue action 或 context-repl 显式访问。

启动头没有总开关。产品 Slogan、version、work directory、data root、配置状态、Context、实时 hash、Model、Permission、DoubleCheck 和 `.status` 提示分别开关；每个启用字段独占一行并从行首开始，全部关闭就不输出例行启动头。固定产品 Slogan 是 `yaca: Yet Another Coding Agent.`。这些显示偏好不能隐藏 ERROR、WARNING、ACTION 或安全事实。

## 新 Context 的创建与命名

进入新的 chat 不立即创建 XML。第一条 main 用户消息之前只有有界内存草稿，立即退出不留下空 Context：

1. `.model`、`.prompt`、`.cautious` 等新会话设置可以先修改内存草稿，但尚无持久 Context/hash。
2. 第一条 main 用户消息提交时，先生成 provisional 名称，以 no-replace 建立 XML，并 durable 保存有效会话设置和该用户消息。
3. 只有保存成功后才允许发起 Model 请求、工具或其他副作用；失败时消息不能被报告为已接受。

provisional 名称是 ASCII `Untitled Conversation [XXXX]`，`XXXX` 为四位大写十六进制随机后缀；碰撞时重新生成，不覆盖已有 XML。它不是永久 ID，也不代替从逻辑 XML 路径实时计算的十六位 Context hash（D-059：用户可见为 **大写** `0-9A-F`）。

自动命名改为可关闭的后台 logical request，默认每十个已经完整收口的 main turn 触发一次。它必须有界、无工具、不阻断主任务；失败、超时、取消或退出保留当前名称。成功 rename 更新逻辑路径和实时 hash。“后台”只表示不阻塞用户体验，领域状态仍由单一事件泵串行裁决。

每个 Context 可在自身 XML metadata 中保存专用 boolean `AutoRenameDisabled`：缺失或 `false` 表示允许周期命名，`true` 表示禁止。手工 rename 成功的默认事务同时设为 `true`；自动 rename 不设置它。context-repl 可查看、添加或取消这一专用标记；取消以当时 durable main-turn 水位建立新 baseline，只恢复以后按完整周期参与的资格，不立即或追补命名。标记变为 `true` 时在途命名结果失效，迟到响应不能覆盖当前名称。它与 INI `AutoNameEveryMainTurns` 正交，不扩展成任意 flags bag。

Context 列表/浏览器另有两个全局显示偏好：`ListSortBy=created|updated|name` 与 `ListSortDirection=ascending|descending`，默认 `updated + descending`。时间来自 XML canonical metadata，不取文件 mtime/ctime；相同键始终按 canonical `LogicalPath` 升序，绝不随主排序方向反转。它们不使裸启动扫描历史，也不改变 Resolver。

## 单一 workspace root 与显式 Context 管理

每个 Context 恰好绑定一个 workspace root。新 Context 的唯一 root 就是用户传入且已经证明存在、可进入的真实目录；上级 Git root 只可作为 status/diff 等证据元数据，不能自动提升或扩大文件、Prompt、Permission 边界。该 root 不作为权威 work-directory/root 字段重复写入 XML；新 Context 发布到传入目录对应的 `__yaca__/CONTEXT/` 镜像位置，之后 yaca 从 XML 的镜像父目录解码当前 root。

- 父目录无法无损解码、解码 root 不存在/不可进入或 identity 不匹配时停止打开，不能留在调用目录继续执行，也不能猜同名路径。
- rebind 只是 context-repl 中的显式 self-fix 事务：在复核源/目标后，把 XML 以 no-replace、可恢复移动到目标 workspace 的镜像目录。只有发布成功才更新活动句柄；逻辑路径和 16 位 hash 随位置立即改变，旧 hash 失效。
- XML 可保存历史工具 cwd、当时路径/hash 和 rebind 结果作为审计事实，但打开时不得用这些历史值求当前 root。
- 不提供 `AutoJumpToDir` 或 `ResumeDirectory=jump|ask|keep`，也不允许附加第二个只读/可写 root。

model-repl、config-repl、context-repl 各自提供本领域的 `self-fix-program` 菜单，不另建 recovery surface：

- model-repl 修复、测试和管理 Model 定义；
- config-repl 修复并事务发布完整主配置；
- context-repl 浏览和管理 Context，并修复 XML、镜像路径/root 映射与可证明陈旧的本地状态；
- self-test 负责诊断，不自动修改配置或 Context。

显式打开损坏、不兼容或具有 unknown operation 的 Context 时，程序显示实际问题、已保存范围和正确 self-fix 入口后退出，不自动重放副作用。活动 writer 存在时，第二进程不得打开正文；只显示 busy 元数据和可证明的 PID，且在锁释放前不能 rename、rebind、delete、repair 或修改 Context metadata，不能仅凭锁龄 force unlock。

chat 中无参数 `.model` 打开有界 Model picker，`.model <selector>` 直接选择；两者调用同一 typed action，只切换已存在、enabled 且有效的 Model。`.context` 只执行显式 Context 选择/切换。它们都不是管理 REPL，也不能复制 REPL 的编辑器。每个 TUI 领域动作都必须有 CLI 等价投影。

Model/config INI 使用独立的短期提交锁，可以在 chat 持有 Context writer 时修改。每个新顶层 turn 前完整读取 INI；digest 未变复用旧 generation，变化时整份校验并自动发布。活动 turn 不热换，观察到半写或损坏候选会阻止下一 turn并进入修复。

## 退出承诺

用户退出不等待后台命名，也不做通用确认。Runtime 立即进入有界 close：停止接收新动作，取消模型和后台活动，丢弃未提交草稿与未开始 queue，拒绝 pending approval，尽力终止工具，并把可证明的结果收口为 completed、interrupted 或 unknown。

“直接退出”是用户体验，不是跳过正确性：已经产生的 Context 仍要尽力提交最终事实、释放 writer、清理临时资源并恢复终端。来不及证明的外部副作用必须记为 unknown，不能伪装成未发生或已完成。

## 仍待下游冻结的技术边界

单 root、手工命名标记和 `F4-14` 已收口：新 Context 使用传入且可进入的真实目录，Git root 只作证据。下游仍需冻结 Windows drive/UNC、Linux root、链接与文件系统 identity 的规范化和 golden vectors；这些技术细节不能重新引入 Git-root 自动提升、多 root 或 XML 内第二份 root authority。本文仍只记录设计目标，不将它写成“已实现”。

## 发布验收方向

Win32 x86、Win64 x86_64 和 Linux x86_64 三个正式 zip 必须各自走通完整发布测试，并分别作出放行决定。每个包至少覆盖：解压后无系统 Lua 启动、薄安装脚本、配置/修复入口、可选启动前 self-test、新 Context 第一消息原子创建、一次模型请求、至少一个工具调用、XML 保存、显式 Context 继续、锁冲突、损坏目标 self-fix 路由、相邻 `__yaca__` 和有界退出。排除能力还要有 no-empty-shell 检查，证明配置、help、schema、Runtime 和 zip 中不存在可触发残留。
