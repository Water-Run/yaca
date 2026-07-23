# 22 应用运行时、生命周期与并发

状态：候选

## 为什么需要独立子系统

现有文档已经分别讨论平台、进程、网络、AgentLoop、存储和 TUI，但还缺少一个共同回答“程序怎样启动、谁拥有状态、阻塞 I/O 怎样变成可取消事件、怎样有界地并发、退出时先关闭什么”的系统。如果这些规则散落在各适配器里，最容易出现 TUI、CLI、网络和存储各自维护一套 busy/cancel/retry 状态。

本系统只定义应用运行时与组合关系，不吞并 AgentLoop 的业务决策，也不替平台、进程或网络实现具体能力。

## 职责

- 定义唯一 composition root，以及服务构造、启动和关闭顺序。
- 定义领域状态、领域事件、适配器事件和 UI 投影的所有权。
- 定义 Lua 5.5 协程、事件泵、阻塞适配器和极小原生 C bridge/helper 的边界。
- 定义单上下文写者、active turn、跨进程锁和全局资源上限。
- 定义网络、进程、TUI、日志与存储之间的有界队列和背压。
- 定义 Win32 x86 下的内存上限、流式处理、GC 安全点和过载退化。
- 定义部分启动失败、正常退出、取消、崩溃恢复和强制终止的生命周期。

## 边界

- AgentLoop 决定 turn、工具、终止评估和业务结果；本系统只调度已经定义的状态转换。
- 01 号系统提供平台身份和能力，02/03 号系统提供进程与网络端口。
- 10 号系统拥有上下文 durable 事实和写锁语义，本系统只遵守其屏障。
- 13/14 号前端只消费视图状态并发送同一 registry 中的语义动作，不能成为领域状态事实源。所有有领域效果的 TUI 动作必须有等价 CLI 投影并返回同一 typed result；方向键、焦点和分页等 renderer gesture 不是第二套领域动作。内部 action registry 不因此成为公共 headless/IPC/RPC API。
- 20 号系统验证调度、背压、故障注入和长时间运行；本系统不拥有发布判定。

## 已确认前提

- D-013/D-014 已确认 `main.lua` 是唯一组合入口，由它选择具体后端并向业务核心显式注入窄依赖；本系统不重新比较隐藏自动选择或多套平台入口。
- D-017 已确认业务核心不按 Windows 版本分支。XP 至 11 的差异由适配器内部探测为能力结果，高层只消费能力或结构化降级错误。
- Windows 与 Linux 使用同一业务源码但分别打包；原生 C bridge/helper 若获准，也必须按发行平台分别构建和验证。

## 候选总体结构

```text
main.lua（唯一组合入口）
  -> Platform/Path/FS/Text/Clock capabilities
  -> Process/Network/Terminal adapters
  -> Config/Context/Permission/Tool services
  -> ApplicationCoordinator
       -> 单线程领域事件泵
       -> AgentLoop 状态机
       -> 有界 I/O 完成队列
       -> 前端视图投影
  -> CLI 或 TUI adapter
```

推荐让应用核心成为唯一领域状态所有者。provider 流事件、进程输出和按键都是输入事件；上下文记录、工具动作和视图状态是经过核心裁决的输出。TUI 不另建 busy、approval 或 retry 状态机，存储也不从 UI 文本反推业务结果。

## 启动顺序候选

 1. 读取最小平台身份并拒绝错误 OS/架构的发行包。
 2. 选择并构造 path、fs、text、clock、process、network、terminal 等窄后端。
 3. 确定程序资源目录、用户数据目录和临时目录，检查最低文件能力。
 4. 加载 schema，再完整读取 INI bytes、计算 digest、parse/schema-validate/cross-validate，并发布启动时第一份 immutable config generation。无效配置或零个可用 Model 阻断 Agent；help/version、三个 bootstrap 管理 REPL 和 self-test Stage 1 只进入各自受限路径。
 5. 根据顶层 semantic action 选择 chat、独立管理 REPL、self-test 或一次性操作。裸 chat 永远新建且不扫描 Context Catalog；只有 `.context`、continue/context-repl 等显式动作调用 Resolver。
 6. 若 `StartupSelfTest` 不是 `off`，调用同一 self-test domain action，从 Stage 1 顺序运行到指定最高阶段。Stage 1 包含 Context Catalog/header、父目录派生 root、目录存在/可进入和有界扫描/hash 性能诊断；Stage 2 才真实检查获准的 LLM；Stage 3 只使用 Stage 2 已确认 Model 做配置与 Permission 名称/说明/Prompt/矩阵/拼写 advisory。需要联网的阶段继续取得可见同意，required failure/cancel 阻止 chat，Stage 3 advisory 不改写 Stage 1/2。
 7. 显式打开旧 Context 时，从 XML 在 `CONTEXT` 镜像树中的父目录解码并验证其唯一 workspace root，再取得单 writer；XML 内不存在 root authority/list 字段，历史工具 cwd/root 也不参与当前 root 求值。活动 writer 存在就拒绝正文，不建立只读正文状态。
 8. 创建 AgentLoop 并显示可配置的简洁启动头。新 chat 直到第一条 main 消息被接受才先建立并提交 XML。
 9. 最后启动会联网、运行进程或接受用户输入的前端；启动头本身不触发这些动作。

任何阶段失败都只清理已经成功构造的较早阶段。模块加载本身不得联网、写文件、修改终端或取得锁；副作用只能发生在显式 `start/open/run` 调用中。

## Config generation 与逐 turn 载入

配置不依赖 watcher、定时轮询或 reload interval。每个顶层 `main`/`side` turn admission 前，ApplicationCoordinator 都执行同一条确定流程：

1. 以发行 hard cap 完整读取一次 INI bytes；读取失败或超过上限就拒绝这个新 turn。
2. 对完整 bytes 计算 digest。若与当前 generation 的 source digest 相同，直接复用同一个 immutable generation，不重新 parse。
3. 若 digest 变化，则对这份完整 bytes 做 parse、schema validation、引用解析和跨字段 validation；全部成功后才以单一原子状态转换发布新 immutable generation。
4. 从该 generation 冻结本 turn 的 Model、Permission、Prompt、DoubleCheck、网络/重试、工具 registry 及其他有效配置 snapshot，再允许请求或副作用。

解析或跨字段验证失败时，旧 generation 只继续服务已经 admission 的活动 turn；新的 main/side 必须显示错误并阻断，不能静默回退旧配置后继续。active turn 的工具、provider retry、action/termination review、compaction 和其他 child activity 始终沿用它 admission 时的 generation；文件在中途变化不能改写同一 turn。model-repl/config-repl 使用自己的原子 INI 提交协议，可以在某个 Context 活动时修改全局配置；变化由下一次顶层 main/side admission 观察，不向核心推送异步 mutation。

## Semantic action registry 与前端等价

ApplicationCoordinator 维护一份版本化 semantic-action registry：action identity、typed 参数、前置条件、锁/Permission 要求、结果/错误和 help metadata 只定义一次。TUI 菜单、dot-command、补全候选和顶层 CLI 都解析为这里的同一动作；不同入口不能给同一 rename、Model 选择、self-test 排除或 Context 列表建立不同默认值。Context 列表动作把已验证的 `ListSortBy`/`ListSortDirection` 交给 11 号系统，排序只消费 XML canonical metadata，不改变 Resolver。

“所有 TUI 领域动作可由 CLI 调用”只保证本地调用表面的完整性。它不注册 daemon、不监听端口、不承诺第三方稳定协议，也不允许无 TTY 调用绕过交互确认、锁、Permission、联网 consent 或费用说明。

## 关闭顺序候选

 1. 停止接受新的 turn、工具和破坏性动作；取消未开始 queue 和后台 Context 命名，不等待命名结果。
 2. 把当前取消请求送入 AgentLoop，并要求网络、进程/helper 等 I/O producer 在规定期限内停止或 join；pending approval 以拒绝/取消事实收口。
 3. 排空已经到达核心的完成事件；超时后仍无法确认的副作用记录为 unknown，不能伪造成功。
 4. 提交能够真实提交的最终结果，flush 上下文与必要审计，再释放会话 write lease。
 5. 清理临时资源，并恢复终端 raw mode、颜色、光标、QuickEdit 与代码页。
 6. 把前述清理结果作为能够提交的 XML 诊断事实收口；Context 尚未打开或 XML 已不可写时只 best-effort 写 stderr，不假设存在独立轮换日志。

正常退出、Ctrl+C、SIGTERM、Lua error 和 renderer 降级共享同一 best-effort 清理栈；强制杀进程只能依赖下次启动的恢复协议。

## Lua 5.5 运行模型候选

推荐采用单线程核心状态机与明确事件泵：Lua 协程用于协作式流程，不把核心可变 table 交给后台线程。Lua 标准库不能独自兑现 XP 上完整 Unicode 文件/控制台与可取消进程树；这些能力可以由平台专用的极小 C bridge/helper 提供，但原生层只返回结构化能力结果或 I/O 事件，不能拥有 AgentLoop、权限或上下文语义。

“单线程核心”不等于“所有 I/O 都在 Lua 主线程阻塞”。规范模型需要区分：

- Lua 领域状态只在一条逻辑事件序列上推进。
- 平台后端可以使用 OS 异步 I/O、极小原生线程或受控 helper 等待控制台、管道和网络，并把有界完成事件送回核心。
- 每个异步操作都有 operation/request identity；取消只是请求，直到收到完成/终止事实前都不能复用缓冲区、关闭领域记录或宣称副作用未发生。
- Windows XP 不能依赖最低 Vista 的 `CancelIoEx`/`CancelSynchronousIo`；可行后端需围绕 XP 已有的 console wait、overlapped I/O、completion port/事件和 Job Object 设计，并由原型证明。`GetQueuedCompletionStatus` 支持 XP，但 XP 上关闭 completion-port handle 不会像新系统那样唤醒无限等待，因此等待必须使用有限 timeout 或显式唤醒包。参考：[GetQueuedCompletionStatus](https://learn.microsoft.com/en-us/windows/win32/api/ioapiset/nf-ioapiset-getqueuedcompletionstatus)、[CancelIoEx](https://learn.microsoft.com/en-us/windows/win32/api/ioapiset/nf-ioapiset-cancelioex)。

这仍是候选可行性方向，不是已确认实现。实施前必须用最小原型同时证明：主模型流持续输出时用户仍能输入；Esc/`.cancel` 有界响应；stdout/stderr 不死锁；进程树在 XP 与 CentOS 7 可收口；取消竞态会落为 completed/cancelled/unknown 中的真实一种；队列满时生产者不会无限占用 Win32 x86 内存。

需要确认的运行时规则包括：

- `require` 只加载受控发行路径，不默认从当前工作目录加载 Lua/C 模块。
- 模块顶层不得探测环境或产生 I/O 副作用。
- 大文件、XML、SSE 和工具输出都流式处理，不靠一次性 Lua 字符串承载。
- event sequence、字节数、时间和 provider 的 64 位数值必须经过范围校验；必要时以十进制字符串持久化。
- GC 只能在已知安全点增量推进，不能以频繁全量 GC 掩盖无界保留。

## 并发基线候选

首版推荐：

- 同一上下文只有一个 writer 和一个 active turn；活动 writer 存在时第二进程完全拒绝打开正文，只能读取不需要解析正文的 busy/PID 元数据。
- write lease 存续期间，来自另一个 context-repl、CLI 或管理进程的 rename、rebind、delete、`AutoRenameDisabled` 修改及其他 Context mutation 一律返回 `LockConflict`；释放前不能靠 Permission、确认或锁龄强夺。全局 model/config INI 编辑使用独立锁与原子提交，可以进行，但只按上节边界影响新 turn。
- 工具调用先全部串行；工具 schema 可以保留只读性、可取消性和互斥资源键，等正确性稳定后再开放并行。
- 不同进程可以运行不同上下文；同一 XML 不提供第二进程只读正文路线。
- 模型请求数、活跃进程数、待渲染事件、待写日志和扫描结果页都有进程级硬上限。
- 会话生命周期 `write lease` 用来阻止第二个 writer，可以跨 TUI/网络等待持有；第二进程只显示不解析正文的忙状态。短时 `commit mutex` 只保护实际文件提交，禁止跨 TUI 输入或长期网络请求持有。
- 两类锁必须有固定取得顺序。陈旧 lease 不能只按时间抢占；必须结合进程存活、存储恢复和用户确认。
- 周期 Context 命名只能在 `AutoNameEveryMainTurns>0`、durable main-turn 水位达到当前 baseline 的下一周期且 XML `AutoRenameDisabled` 缺失/`false` 时 admission。marker 为 `true` 时不排队；取消 marker 以当时 durable 水位建立新 baseline，不立即发请求、不追赶错过周期。新 main、退出、显式取消、purpose deadline，或 marker 被置为 `true`，都会取消/逻辑失效尚未完成的命名 request；无法停止的迟到 response 只保存 usage/result/cancel 事实，不采用名称。命名请求进入同一有界事件泵和 Model scheduler，不拥有第二份领域状态。

## 背压与有界内存

每一条生产链都必须说明消费者变慢时怎么办：网络流快于模型事件处理、进程输出快于 TUI、TUI 慢于日志、扫描快于页面显示、上下文写入慢于 AgentLoop。推荐使用有界队列并按数据性质选择暂停生产者、落盘、合并状态或显式截断；绝不无限累积 Lua table。

事实事件不能因 UI 慢而丢失，临时 spinner 或 token 级状态可以合并。工具原始输出达到上限时由工具层形成带原始大小和截断标记的 canonical result，不能先无限接收再由 TUI 截断。

## 必须确认的性能预算

预算应在最低参考机器上度量，而不是只写“尽量快”：

- 冷启动到可输入时间，以及启动期间允许的磁盘扫描量。
- 空闲内存、单 turn 峰值内存和长会话稳定内存。
- 单 XML 建议/硬大小、单工具输出、单事件与队列上限。
- Context Resolver 当前环、浏览器首屏和翻页的反馈时间。
- Ctrl+C 到可见确认、进程树终止和安全退出的期限。
- 慢网络、慢磁盘和慢终端下的状态反馈最大间隔。

具体数字等测试平台和代表性工作负载确认后再冻结，但在实施前必须形成可测预算和超限行为。

## 设计不变量候选

- D-017 已确认业务核心不按 Windows 版本分支，只消费能力结果；平台适配器内部可以保守探测并降级。
- 只有应用核心产生领域状态转换，renderer 和 provider 不能越权改状态。
- 任何队列、缓存、扫描结果和 UI 历史都有上限。
- 一次副作用只有一个 operation 身份；取消或崩溃后不因重放自动再执行。
- 启动未完成时不隐式联网或运行工作区命令。
- 每个新 main/side turn 只使用一次完整 INI 观察所确定的 immutable generation；活动 turn/child 不受中途配置变化影响，也不存在 watcher 路径。
- 每个 Context 的当前 root 只由 XML 镜像父目录派生；XML 字段、历史事件和 Permission 不能覆盖它。
- TUI 与 CLI 的同一领域意图必须落到同一 semantic action、锁和 typed result；入口差异不能形成额外授权。
- 关闭失败不把 unknown 副作用报告成成功，也不删除仍可能用于恢复的临时事实。
- helper、线程或子进程崩溃形成端口错误，不成为第二个应用事实源。

## 待逐项确认

 1. 单线程事件泵是否作为所有平台的规范运行模型。
 2. 极小原生 C bridge/helper 是否正式允许，以及 Windows Unicode 文件/控制台、原子文件能力和进程/管道的 ABI 边界。
 3. 同一进程是否允许多个上下文同时 active，还是首版一进程一个上下文。
 4. 会话 write lease、短时 commit mutex、第二个写者和陈旧锁恢复的完整体验。
 5. 工具首版全部串行是否确认，以及以后开放并行所需 capability。
 6. 各 I/O 链路的背压动作和硬上限。
 7. 启动/关闭每一步的失败结果与清理期限。
 8. Lua 模块加载路径、协程重入、数字范围和 GC 规则。
 9. XP x86 最低机器上的性能与内存预算。
 10. 运行时事件、领域事件、持久事件和 UI 事件的精确映射。
