# 技术证明债务表

更新日期：2026-08-29

状态：编码/资格阶段证明计划；TP-001..030 均至少 `specified`，TP-002/003/006/008/010 含范围明确的 modern evidence；无条目因写入本文而自动 `proven-target`

## 为什么需要这张表

设计题库负责问清产品取舍，但有些问题不能让项目负责人凭偏好选择。例如，Windows XP 能否可靠取消一个正在读管道的进程、单 XML 在长会话中的写放大是否可接受、LuaExpat 能否以 Lua 5.5 ABI 在 Win32 x86、Win64 x86_64 和 Linux x86_64 三个发行目标上稳定工作，答案必须来自最小原型、故障注入和目标机证据。

本文把这些“必须由工程证据回答”的问题单独列出，防止出现两种错误：

1. 把一个尚未证明可行的候选写成已确认架构；
2. 把纯技术事实包装成 A/B/C，让项目负责人替实现承担猜测。

每条证明债务只验证一个边界。这里的“原型”不是开始产品编码，而是相关负责人决策完成后、编写该子系统实施计划之前需要安排的最小可丢弃验证。当前阶段只冻结问题、观察点、通过条件和失败后的产品取舍。

## 状态与责任

| 状态 | 含义 |
| --- | --- |
| `unplanned` | 已识别，但测试环境、夹具或方法仍未冻结 |
| `specified` | 问题、步骤、通过条件和产物已经可复现 |
| `proven-modern` | 只在现代开发机证明，不能代表 XP/CentOS 目标 |
| `proven-target` | 在规定目标机和最终架构产物上通过 |
| `failed` | 候选无法达到已确认保证，需要改技术路线或返回负责人取舍 |
| `superseded` | 上游决定改变后，此证明已被另一条明确取代 |

`O` 表示失败会改变产品承诺，需要项目负责人决定退路；`T` 表示技术侧可以在不改变承诺的前提下换实现；`J` 表示两者都有。

负责人输入门已经关闭，本文只验证 D-049 至 D-056 和 `AS-006-*` 的现行路线，不再并列测试被否决的 A/B/C 产品分支。D-044 已把 PJ-14、PJ-15、PJ-16、PJ-17、PJ-19 和 PJ-20 锁定为 terminal-only 下的排除项；D-055 同时固定零 aggregate telemetry、零 diagnostic upload，D-056 固定零内建更新检查/下载/安装。历史问卷 ID 仍作来源引用，但当前技术责任只证明相应 parser、worker、endpoint、依赖、配置、CLI/help、XML 和 zip surface 为零，不得因旧候选文本重开。PJ-19 与 ED-14 的 `not-applicable` 分支也必须产生同等负向证据。

## P0：进入完整实施计划前必须有路线

### TP-001 luainstaller 的 Win32 x86/XP qualification 与 CPU ISA 目标

- **当前状态**：`specified` + upstream `proven-modern`；`../luainstaller` 1.3.0（tag `v1.3.0`，commit `97192d1`）已经消除旧 x86 profile guard，加入 Windows x86/x86_64 XP API/subsystem、MinGW import closure、watchdog 与 Linux native x86 CI 证据。尚未生成 yaca-specific Win32/Win64 包，也未取得 XP--11/Win7--11 目标机结果。
- **要证明**：相邻打包器可以产生使用 Lua 5.5、Win32 x86、XP SP3 可启动的 yaca launcher，并能纳入项目所需 Lua/C 模块和资源；依照已确认的 RF-14 A，整个产物采用保守 IA-32 候选基线，精确最低 ISA 由最终工具链审计与旧 CPU/目标机证据冻结，而不是只有 launcher 服从。
- **最小证据**：固定消费 `v1.3.0` 或明确后继 commit；先构建与 yaca 相同 Lua 5.5 ABI/依赖形状的最小 hello onedir，记录 host/target/toolchain/profile；固定 ISA flags；审计 PE machine、subsystem、imports、CRT 与指令；再用完整 yaca 候选在满足最终 ISA 下限的真实旧 CPU/虚拟化约束环境及 XP SP3 到 Windows 11 上记录同一产物结果。Win64 与 Linux x86_64 各自重复，不把 luainstaller 自身 CI 代替 yaca 依赖闭包。
- **通过条件**：不是修改 PE 标志伪装；最终包不引用最低 Vista+ API；Lua、C 模块和每个随包 executable/DLL 都没有暗中使用高于最终确认基线的指令；不依赖目标机预装 Lua/CRT；错误架构或 ISA 被构建门拒绝。
- **失败后**：先由 `T` 在不改变产品承诺的范围内适配 toolchain/profile、依赖闭包或 yaca 装配；只有目标证据证明 1.3.x 路线无法满足保证，才转 `O` 在“进一步扩展 luainstaller、更换 Windows 打包链、改变 XP/x86/Lua 5.5 硬目标”之间重新选择。
- **关联**：`REL-14`、`AQ-206`、`AQ-211`、`RF-04`、`AR-P0-16`。

### TP-002 Lua 5.5 与 native 模块 ABI

- **当前状态**：`proven-modern`；现代 Linux 源码 smoke 不能代表三个发行目标。
- **要证明**：所有拟随包 C 模块严格按目标 Lua 5.5 headers/ABI 分平台重新构建，不混入 Lua 5.4、LuaJIT 或错误位数产物；D-044 排除的 Web/image/audio/remote/transcription/TTS 不得带入 listener、codec、capture、IPC、device 或 speech helper，“默认关闭”不等于 zero-surface。
- **最小证据**：每项模块的源码 hash、patch、编译器/ABI/ISA flags、导出/导入表、反汇编或等价指令扫描、加载及错误卸载测试；Win32 x86、Win64 x86_64 和 CentOS 7/Linux x86_64 各一份；由最终 scope 生成 component manifest 和被排除能力的 negative manifest。
- **通过条件**：加载、调用、GC、错误抛出、重复创建/销毁和长期 soak 无 ABI 崩溃；Windows native 模块服从 RF-14 A 的 proof-derived 保守 ISA 基线，构建可复现；模块搜索不从 CWD/PATH 注入替代品；最终 component/import manifest 与 zip 中不存在 D-044 六类能力的 native 模块、helper 或间接可调用依赖。
- **失败后**：`T` 优先换窄绑定或改为 helper；若所有候选都要求改变 Lua 5.5/平台保证，再转 `O`。
- **关联**：`PROD-17` 至 `PROD-21`、`REL-14`、`AQ-187`、`AQ-250`、`AQ-382` 至 `AQ-385`、`AQ-388`、`AQ-389`、PJ-14 至 PJ-17、PJ-19、PJ-20、`TS-09`、`AR-P0-14`、`AR-P0-16`。

### TP-003 Windows XP/CentOS 统一事件泵

- **当前状态**：`proven-modern`（确定性 fake-port/core 范围；证据见 [modern-2026-08-29](proofs/modern-2026-08-29/README.md)）；真实 Win32/XP、CentOS wait/console/process/network adapter 与 suspend/resume 尚未 `proven-target`。
- **要证明**：Lua 领域核心保持单线程状态所有者时，console input、curl stdout/stderr、工具进程、timer、cancel、XML commit completion 以及 D-041 周期 `context-name` 完成/取消可以进入同一有界事件泵，且没有任何一个阻塞源冻结全部应用；系统 suspend/resume 或显著时钟间隙也能成为显式事件并触发最终规格要求的重新验证。命名 admission 同时要求 `AutoNameEveryMainTurns>0`、durable main-turn waterline 到期且 Context XML 的 `AutoRenameDisabled!=true`；取消标记只建立新基线，不追补请求。PJ-18 已选单 root：每个 active Context 的唯一 root 由其 XML 在 `__yaca__/CONTEXT` 镜像树中的父目录经 `LogicalPathCodec` 解码，不建立 root list/alias/selector 或第二 root 资源域。D-044 意味着泵中不存在 Web/remote client、media device、capture/transcription/speech 流或它们的保留队列。
- **最小证据**：只包含 `start/poll/cancel/join/close` 的最小 port；同时运行慢 SSE、慢命令输出、用户输入、周期持久化和低优先级 `context-name`；覆盖 marker missing/false/true、运行中设置/取消、到期水位、禁用期间跨过多个间隔与新基线，证明 true 时零排队/零费用，取消后不立即或追赶命名，新 main 消息或退出能取消已在途请求且不等待它收口；按 F4-15 A 只覆盖一个进程恰好一个 active Context、一个由镜像父目录解码的 root，并扫描零第二 Context/附加-root 队列或账本；对 D-044/D-055/D-056 做零 listener/device/client/codec/upload/update worker/queue 的 registry 与运行 trace 扫描；分别在 sampling、tool-running、approval、commit 和 idle 中 suspend/resume；记录事件顺序、墙钟/单调钟差、队列峰值、CPU、句柄与恢复后的 lease/workspace/root 状态。
- **通过条件**：忙时输入和 Esc 在已确认延迟预算内可观察；慢消费者产生明确 backpressure；取消后必须得到真实 completed/cancelled/failed/unknown 之一；`context-name` 永不取得工具、不抢占 main/side/review 的已就绪请求、marker=true 时不进入 scheduler，取消 marker 后只从新基线计数且不在退出或恢复时幽灵继续；close barrier 后无遗留请求/helper，且从未创建 D-044 排除的 listener/device/client 状态；恢复后不自动重放不能证明连续性的模型请求或副作用，旧 approval/action snapshot 按最终规格重新验证；无共享 Lua table 的后台写入。
- **失败后**：`J`。技术侧先比较原生等待层、极小 I/O 线程和 helper；若只能取消流式或取消忙时输入能力，交负责人确认降级。
- **关联**：`RUNTIME-06`、`RUNTIME-07`、`PROD-05`、`PROD-18` 至 `PROD-21`、`AQ-261`--`AQ-265`、`AQ-315`、`AQ-381`、`AQ-382`、`AQ-384` 至 `AQ-386`、`AQ-388`、`AQ-389`、PJ-14、PJ-16 至 PJ-20、`AL06-01`、`F4-15`、`TS-09`、`AR-P0-04`、`AR-P0-05`。

### TP-004 Windows XP console 与 QuickEdit

- **当前状态**：`specified`（计划见 [PROOF-PLANS-P0.md](PROOF-PLANS-P0.md)）；尚未 proven。
- **要证明**：XP 传统 console 下能够识别普通 Enter、Ctrl+Enter、Shift+Enter、Alt+Enter、Esc；能力不足时能够可靠声明并使用点命令后备；QuickEdit、窗口关闭、Ctrl+C/Ctrl+Break 不会让程序永久挂死或破坏终端状态。
- **最小证据**：真实 XP console 与重定向/管道矩阵；逐键事件 trace；raw→cooked→恢复；选择文本造成阻塞时的诊断；异常退出后的模式/代码页/光标复核。
- **通过条件**：帮助只宣传实际可用动作；无法区分的组合键不误映射为另一动作；draft 不因异步输出静默丢失；终端恢复有 best-effort 证据。
- **失败后**：`O` 只决定是否接受某组合键在 XP 必须使用文本后备；技术侧不能假装快捷键工作。
- **关联**：`AQ-009`、`AQ-264`、`AQ-265`、`TU-03`--`TU-05`、`AR-P0-05`。

### TP-005 子进程树、取消与 unknown

- **当前状态**：`specified`（计划见 [PROOF-PLANS-P0.md](PROOF-PLANS-P0.md)）；尚未 proven。
- **要证明**：Windows `cmd.exe` 和 Linux `/bin/sh` 启动的前台命令，其 stdin、stdout/stderr、退出、超时、取消和子孙进程可以按最终确认契约收口；无法证明终止时准确返回 unknown；过长或无法无损编码的 raw command 不会被 Runtime 静默改写成另一动作；各平台 termination grace 和内建 `auto` decoder 可以作为发行契约冻结而不暴露用户字段。D-044 排除的录音、转写、codec 和播放 helper 不是 process port 的条件分支，而是必须证明不存在的路由。
- **最小证据**：直接子进程、孙进程、继承句柄、主动读取 stdin/等待交互、忽略信号、快速退出与 cancel 竞态、创建到纳入 Job 的竞态、fork 后脱离进程组、不同 grace 值的收敛/延迟矩阵、平台命令长度边界、代码页/UTF-8/无效序列/二进制输出和不可表示字符等夹具；同时扫描 process/helper registry、发行 manifest 和实际子进程 trace，确认无媒体设备、codec、转写或播放进程入口。
- **通过条件**：模型可见 `exec` 不会偷取 TUI/审批输入；已确认的前台非交互契约不能让子进程取得 TUI stdin，读取请求按进程规格得到稳定 EOF/typed non-interactive result；命令长度/编码超限得到稳定 typed error，不写临时脚本偷换调用；每个平台 manifest 固定有界 grace，result 记录实际 decoder/替换/失败/原始字节；不因发送 kill 就声称已停止；不复用仍可能回调的 operation/buffer；媒体/转写/TTS helper、process route 和孤立 reader 计数为零；unknown 可由恢复页解释。
- **失败后**：`J`。先收窄为“非交互、前台、有界”命令；若仍不能提供可取消性，再决定是否降低 shell 承诺。
- **关联**：`PROC-11`、`PROC-12`、`PROD-18`、`PROD-20`、`PROD-21`、`AQ-119`--`AQ-128`、`AQ-367`、`AQ-371`、`AQ-384`、`AQ-388`、`AQ-389`、PJ-16、PJ-19、PJ-20、`TS-03`、`TS-09`、`AR-P1-03`。

### TP-006 curl 流式、取消、ambient config 与秘密传递

- **当前状态**：`proven-modern`（现代 curl + loopback carrier/cancel/retry/scanner 范围；证据见 [modern-2026-08-29](proofs/modern-2026-08-29/README.md)）；随包 curl、XP/CentOS TLS/proxy/CA、target timer/jitter 与 redirect controller 联调尚未 `proven-target`。现代夹具中的 `MinimumScannableSecretBytes=8` 与 retry manifest 只是候选，不得冒充发行冻结值。
- **要证明**：随包 curl 在 XP/CentOS 上支持目标 TLS/代理/SSE，能够被事件泵取消，并让明文 INI Key 不进入 argv、普通环境、日志和可恢复残留；yaca 的基础设施请求不受用户/工作区 curl 配置、home/proxy/CA 等未列 ambient input 偷偷改写。每个 logical request admission 把当前 Model 的 `RetryCount`、`RetryBaseDelayMs` 与发行 manifest 中的 exponent/max/deterministic-jitter 展开成不可变 retry snapshot；默认、单位、范围、饱和退避公式、jitter 输入/算法与 Runtime maximum 均由真实 endpoint 和旧机 fixture 冻结。M05-59 A 的 exact-byte scanner 以有界尾窗工作：发行版冻结跨目标平台一致、用户不可调低的 `MinimumScannableSecretBytes`，ConfigGeneration 和每次 consumer admission 都阻断过短 secret。D-055/D-056 要求 aggregate telemetry、diagnostic upload 与 update query/download 的 endpoint、purpose 和 worker 全部不存在。
- **最小证据**：比较“secret config 走 stdin/body 走私有 temp”和“body 走 stdin/secret config 走私有 temp”；在用户目录、工作区与环境放入会改 header、proxy、CA、redirect 或输出的恶意/冲突配置；使用 canary key/正文/路径检查进程列表、环境、temp、stderr、XML、支持输出和崩溃残留。使用真实兼容 endpoint 与可编程故障 endpoint，在 XP x86 和 CentOS 上覆盖 count=`0|1|max|max+1`、base/manifest max 边界、manifest 升级、DNS/connect/TLS、body 未发送、body outcome unknown、429/503、`Retry-After` delta/date/畸形/过长、首个 canonical event、partial SSE、协议/auth/普通 4xx/内容拒绝、cancel、suspend/resume、wall-clock 跳变和 timer 粒度；用固定 logical-request identity/attempt/manifest 生成跨平台 jitter golden vector，记录计划/实际等待、attempt、deadline/turn 剩余量、CPU 与句柄。为 scanner 覆盖门槛前后长度、每一种 chunk split、零长度/空值 schema 拒绝、同值多个 secret class/source、前缀/后缀/嵌套与相交 occurrence、超长 pattern、慢消费者与输出上限；随机排列 registry、matcher 返回顺序、chunk 大小和 backend，证明短值 consumer ineligible 且错误不泄露值/实际长度。对 D-055/D-056 执行零 request-purpose、endpoint、worker、receipt 和启动/定时请求扫描；再评估是否需要窄 libcurl bridge。
- **通过条件**：请求体与 Key 传递无歧义；实际请求 manifest 只由 schema、受控平台信息和显式用户选择决定，不读取未列宿主配置；所有 temp no-replace、最小权限、有界、启动可回收；redirect 只允许 same-origin，绝不向不同 origin 转发 Key。显式 HTTP endpoint 可以工作，但保存/变更时必须出现明文 Key/Prompt/reply 风险警告且 HTTPS 永不自动降级。`RetryCount` 机械表示首次 attempt 之后允许的自动 retry 数，Model 数字与 manifest 展开为公开、可快照的有效 tuple，整数运算饱和且 deterministic jitter golden vector 在两平台一致。local backoff、合法 `Retry-After`、logical-request deadline、turn 剩余预算与 Runtime hard cap 始终取更严格结果；等待超出剩余门即返回 typed deadline/budget outcome，不后台排队。body outcome unknown、收到任何 canonical event、畸形协议、auth/普通 4xx、内容拒绝或 cancel 都不 retry，active request 不热换配置，retry 不切换 Model。ConfigGeneration 激活与每次 consumer admission 都执行同一短 secret 资格门，升级后不静默放宽；完全相同 pattern 只保留一份并携带稳定排序的 class/source 集，scanner 检查全部 pattern、跨 chunk 保留有界必要尾窗，并将所有相交 hit 合并为 maximal byte-interval union。最终 Runtime 中 telemetry、diagnostic-upload、update endpoint/purpose/receipt 均为零；取消与断流给出确定 attempt 结果。
- **失败后**：`J`。技术侧可更换不改变已选保证的 timer、受控 carrier、matcher 或窄 bridge；若当前 retry/short-secret 保证在目标平台不能通过，则把最小反例交回对应 owner/CFG-28/CFG-29，不能自动放宽门槛、重试资格或改配置面。若只能把 Key 暴露在已确认禁止的位置，才重新打开明文 Key/外部 curl/平台目标的最小产品差异。
- **关联**：D-036、D-039、`PROC-13`、`NET-06`、`NET-13`、`MODEL-15`、`LOOP-14`、`LOOP-27`、`DIAG-08`、`DIAG-14`、`REL-11`、`AQ-140`、`AQ-197`、`AQ-220`、`AQ-221`、`AQ-246`、`AQ-277`、`AQ-278`、`AQ-387`、`AQ-390`、`AQ-433`、`AQ-437`、ED-13、ED-14、RF-16、`CFG-28`、`CFG-29`、M05-58、M05-59、HCFG-02、HCFG-05、F4-02、`SAFE-09`、`AR-P0-14`、`AR-P1-02`。

### TP-007 TLS、CA 与明文 HTTP 旧平台基线

- **当前状态**：`specified`；由 C19/C31/C32 执行，target curl/CA matrix 未证明。
- **要证明**：发行包自带的 curl/CA 组合在 XP 和 CentOS 7 上能连接已支持协议端点，不依赖系统 TLS；用户自定义 CA、证书错误、代理 CONNECT 和本机 stunnel endpoint 可解释。显式 `http://` endpoint 在 loopback/LAN/public 都可使用，但配置保存/改变时必须警告 Key、Prompt 与 reply 明文风险，绝不由 HTTPS 自动降级；自动 redirect 只允许 same-origin。D-044/D-055/D-056 下不存在 Web/remote listener、telemetry/diagnostic endpoint 或 update manifest/download endpoint；stunnel 只作为外部安装配置建议，不随包、不自动安装。
- **最小证据**：有效链、过期、错误主机名、私有 CA、代理认证、SNI、TLS 版本/密码套件、系统时间错误、离线，以及 HTTP loopback/LAN/public、same-origin/cross-origin redirect、空/非空 Key 和 secret header 的组合矩阵；覆盖 bundled curl/CA、用户 CA、全局 proxy 和本机 loopback stunnel 配置；对 Web/remote、telemetry/diagnostic upload、update 执行零 bind/listener/endpoint/auth-policy/manifest/download 扫描。
- **通过条件**：不存在隐式 insecure fallback；显式 HTTP 按配置执行并在配置边界稳定警告，HTTPS 不降级，跨 origin redirect 在任何正文/Key 外发前拒绝并要求用户显式修改 Model endpoint；PJ-14/PJ-17、ED-13、ED-14、RF-16 对应 listener/endpoint/request purpose 计数为零；CA/curl 来源与版本进入发布 manifest 和 self-test，stunnel 不进入 component manifest。
- **失败后**：`T` 更新随包 curl/CA；若端点要求目标平台无法承载的 TLS 组合，交 `O` 决定支持边界。
- **关联**：D-039、`NET-13`、`PROD-19`、`DIAG-14`、`REL-11`、`AQ-137`、`AQ-145`、`AQ-146`、`AQ-246`、`AQ-382`、`AQ-385`、`AQ-387`、`AQ-390`、PJ-14、PJ-17、ED-13、ED-14、RF-15、RF-16、`M05-01`、`M05-04`、`AR-P1-02`。

### TP-008 单 XML 完整重写的正确性

- **当前状态**：`proven-modern`（Linux/POSIX full-rewrite、31 个进程崩溃切点、writer lock、manual rename/rebind recovery；证据见 [modern-2026-08-29](proofs/modern-2026-08-29/README.md)）；Windows replace/no-replace、目标文件系统、断电、AV/share violation 尚未 `proven-target`。
- **要证明**：流式复制旧 XML、插入 canonical event/footer、完整验证、flush 与发布的协议，在每个崩溃点最多留下一个可识别的 current/previous-valid 状态，不产生半个正式 XML；手工 rename 的 canonical `Name`、`UpdatedAt` 与 `AutoRenameDisabled=true` 必须作为一个可恢复管理事务发布；workspace rebind 的历史事件、`UpdatedAt` 与目标镜像路径也必须作为一个可恢复管理事务收口。`CreatedAt` 始终不变，自动 rename 不置标记，显式增删标记也不能产生名称/metadata 半状态。
- **最小证据**：对 open/read/copy/write/flush/close/verify/replace/directory flush 的每个边界故障注入；磁盘满、权限变化、杀进程、杀机器、杀毒软件占用和跨卷错误；再在手工/自动 rename、workspace rebind、marker add/remove、basename/path move、rebind event 与 XML metadata publication 每个切点杀进程，并覆盖 inspect/验证失败不得推进时间。
- **通过条件**：恢复算法只依据可验证证据；正式路径始终是完整 well-formed XML；手工 rename 成功后 `Name`、`UpdatedAt`、marker 与新路径必然同时为新值，失败后必然同时保持旧值；自动 rename 同样要求 `Name`、`UpdatedAt` 与新路径全成或全不成，同时绝不创建禁用 marker；rebind 成功后事件、`UpdatedAt` 与目标路径全部生效，失败后全部不生效；`CreatedAt` 永不改变，任何 inspect/失败 mutation 不推进 `UpdatedAt`；marker 取消只建立新调度基线；副作用前 durable operation 屏障和副作用后 result 屏障可区分；不自动重放 unknown。D-053 的永久 delete 不建立 trash/restore 或 selective-redaction 历史；删除协议必须枚举 current/temp/previous-valid 等 yaca 已知 generation，逐项报告 best-effort 结果，绝不把 unlink 宣传成物理 secure erase或撤回已发送内容。
- **失败后**：`J`。技术侧先修正 replace/previous-valid 协议；若单文件基线无法达到已确认 durability，负责人需决定是否允许短期 WAL/recovery sidecar 或改变承诺。
- **关联**：`CTX-28`、`AQ-303`--`AQ-305`、`AQ-368`、`CX-01`、`CX-04`、`CX-05`、`AR-P0-08`、`AR-P0-10`。

### TP-009 单 XML 写放大、x86 内存与硬门

- **当前状态**：`specified`；由 C17/C28/C32 的 long-Context workload 执行。
- **要证明**：正确性基线在 Win32 x86、旧磁盘和长会话上不会因 O(n) 单次重写、累计 O(n²) I/O、parser buffer 或 Lua 大字符串失控。
- **最小证据**：小/中/压力 XML，短消息、大工具结果、反复压缩/Model 切换、慢磁盘、磁盘接近满；记录 p50/p95/最大提交延迟、峰值 private bytes、写入字节和恢复时间。
- **通过条件**：不同时构造完整旧 XML + DOM + 新 XML；超过 provisional 门前提前告警；达到 hard gate 后 fail-stop 并保留可接盘文件；结果可在目标参考机复现。
- **失败后**：`O`。由负责人在允许 WAL、降低 durable 频率/保证、限制 Context 大小之间选择；不能暗中换长期事实源。
- **关联**：`AQ-228`、`AQ-303`--`AQ-305`、`CX-11`、`RF-09`、`RF-10`。

### TP-010 XML parser/writer 与 Lua 5.5

- **当前状态**：`proven-modern`（Linux x86_64 固定源码 hash 构建 + SAX threat/Unicode/carrier corpus；证据见 [modern-2026-08-29](proofs/modern-2026-08-29/README.md)）；Win32 x86、Win64、CentOS 7 build/load 与 target resource limits 尚未 `proven-target`。
- **要证明**：目标构建可分块解析/验证项目 XML 安全子集，writer 能确定性转义，DTD/entity/外部读取被硬拒绝，资源上限在 C 与 Lua 两侧都生效。D-052/TS-23 A 已固定 direct tools 使用 typed envelope、`exec.command` 为 envelope 中的 opaque 原始字符串；canonical scalar 必须先成为“有效 Unicode scalar sequence 的精确 UTF-8 bytes + missing/present-empty 身份”，再由 `representation=text|base64` 进入 XML 1.0-safe carrier。M05-59 A 的 scanner 必须在公开 digest、approval、operation 和 XML persistence 前执行，以 TP-006 冻结的门槛、跨 chunk 与 maximal-union 语义工作。D-044/D-055/D-056 要求 schema 中不存在 media/remote、telemetry、diagnostic-upload 或 update 的 parser/element/namespace/receipt；D-045 要求 current-root/workdir/root-list/alias/selector 权威元素数为零，D-046 只加入 typed `AutoRenameDisabled` metadata。
- **最小证据**：目标平台构建、合法 fixtures、畸形 UTF-8、重复/未知字段、深度/属性/文本/实体炸弹、分块边界、writer→parser round-trip 与 fuzz corpus。对 scalar/carrier 做逐 byte oracle：枚举 `0x00..0xFF` 经 typed binary/base64 的 round-trip；逐个枚举 U+0000..U+10FFFF（surrogate 区间除外）的单 scalar UTF-8，并以代表性多 scalar 序列覆盖 ASCII、非 BMP、组合序列、非字符、XML 1.0 禁止但仍是合法 UTF-8 的控制字符、BOM、`&<>`、单双引号、反斜杠、`]]>`、HT/LF/CR/CRLF、前后/连续空格；另枚举 surrogate 区间编码、超出 U+10FFFF、overlong/truncated UTF-8、孤立 continuation、NUL 和 maximum boundary。每个 corpus 逐一验证 missing/empty、text/base64 分类、original byte length、公开 digest、任意 parser/writer chunk split 和重新载入后的 byte equality；不合法 text 必须证明“拒绝且不替换/规范化”，同一原始 bytes 只有在 schema 明确为 binary 时才可 base64 无损承载。为 M05-59 A 再把门槛前后、重复 source、相同/前缀/嵌套/交叠 secret 放在 canonical 输入的 entity/base64-serializer 输入边界与所有 chunk split，排列 registry/匹配顺序并比较 consumer-ineligible 结果或 marker 后 XML 的 maximal-union golden bytes。D-044/D-055/D-056 执行 zero-element/namespace/parser/receipt scan；D-045 执行 zero-current-root/workdir/list/alias/selector scan；D-046 覆盖 marker missing/false/true、未知 enum/type、手工 rename 与 marker 同事务、自动 rename 不置位、rebind/copy/import 保留 marker。
- **通过条件**：无 DOM 全量加载；禁用 DTD 不是只靠未注册回调；非法 XML 不触发文件/网络访问。每个 accepted canonical field 都满足 `protocol wire -> canonical bytes -> XML carrier -> canonical bytes` 逐 byte 等同，missing/empty 不合并，writer/parser 不做 Unicode normalization、replacement、NUL 截断、换行改写或尾空格处理；所有 256 个 byte 值可由 typed binary carrier 无损往返，所有允许的 scalar 要么经 text 往返相同、要么确定选择 base64，非法 text 只返回稳定 `carrier-not-lossless|invalid-scalar` 而不“修好后”接受。secret gate 在选择 representation/计算公开 digest 前运行；过短 registered secret 无法激活 consumer，重复/相交 hit 的 marker 与拒绝结果在 XML chunking、matcher 和平台间完全一致且不泄露原值、原长度或 equality fingerprint。media/remote/telemetry/upload/update namespace、element、parser、外部附件目录或 receipt 数为零；错误包含安全位置和类型但不回显秘密正文。
- **失败后**：`T` 比较更窄 binding/helper；若没有目标可行 parser，再返回 `O` 重新讨论 XML/平台组合；若 parser 可用但已选 typed carrier 或 M05-59 A 保证无法兑现，则只把最小反例交回对应 owner，不能规范化数据、放行过短 secret 或改回被否决的 carrier。
- **关联**：`PROD-05`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-186`--`AQ-188`、`AQ-246`、`AQ-383` 至 `AQ-390`、`AQ-437`、PJ-15 至 PJ-20、ED-13、ED-14、RF-16、`CFG-29`、M05-59、TS-23、HCFG-02、HCFG-05、`CX-06`、`AR-P0-10`、`AR-P1-01`。

### TP-011 文件系统支持矩阵、发布、锁与 durable 原语

- **当前状态**：`specified`；由 C04/C17/C32 的 target filesystem matrix 执行。
- **要证明**：Windows XP 与 CentOS 7 分别能在最终公开支持矩阵中的每类数据根文件系统兑现 `publish_new_no_replace`、替换已有文件、move-no-replace、文件/目录 flush、writer lease 与 stale lock 证据；数据根能力不足时拒绝成为可写事实源，workspace 的 direct write/rename/delete 只使用经逐动作证明的能力并在不足时 fail-closed。具体 NTFS/FAT/SMB/Linux 本地/NFS 等矩阵行由目标证据填写，不再形成负责人产品投票。每个测试 Context 只探测从其 XML 镜像父目录解码出的唯一 root；context-repl rebind 必须以 no-replace 语义把 XML 移到目标镜像目录而不改 XML 内的 workdir 字段，并保留 `AutoRenameDisabled`；手工 basename rename 则与 marker=true 一起可恢复发布。D-056 下不存在 update download target 或 staging。
- **最小证据**：同名竞态、读者持有句柄、只读/ACL、候选 NTFS/FAT/SMB、Linux 本地文件系统、NFS/可移动盘、跨卷、断线、休眠、断电/崩溃和两个进程争抢夹具；数据根与每个 Context 的唯一 workspace root 分开记录结果；手工/自动 rename、marker add/remove 与 rebind 的所有 publication 切点。
- **通过条件**：不得先删正式文件再放新文件；锁文件存在不自动等于活进程；无可靠 no-replace/flush/lease 时，相应数据根被拒绝或 workspace 动作按已确认支持等级失败关闭；workspace 降级不被描述成 Context durability；rebind 只有在目标镜像目录可发布且旧/新位置的 move 结果可证明时才成功，不会留下两个 writer 候选；update download target/staging 数为零；每条原子性和掉电持久声明都绑定平台、文件系统与挂载前提。
- **失败后**：`J`。可改协议或降低支持文件系统；若影响“单 writer/完整 XML”承诺则由负责人确认。
- **关联**：`PLAT-13`、`PROD-05`、`REL-11`、`AQ-172`--`AQ-175`、`AQ-290`、`AQ-370`、`AQ-386`、`AQ-387`、PJ-18、RF-16、`CX-04`、`CX-05`、`AR-P0-11`、`AR-P0-16`。

### TP-012 Unicode 路径、LogicalPathCodec 与 hash

- **当前状态**：`specified`；hash 算法/vectors 已冻结，由 C09/C16/C32 执行 target codec/identity corpus。
- **要证明**：中文/非 ASCII 路径、Windows 盘符/UNC/junction、Linux bytes 名称、大小写和规范化规则能在显示、文件操作、镜像树和固定 16 位 hash 中保持同一身份；唯一 current root 只由 Context XML 的镜像父目录经 `LogicalPathCodec` 解码，XML 本身不保存 current root/workdir，tool/Prompt/XML 不存在 root list、alias 或 selector；basename rename、workspace rebind、复制/导入时 `AutoRenameDisabled` 均按明确规则保留或迁移，不能因路径变化丢失用户命名意图。
- **最小证据**：路径 corpus；Windows wide API；组合/分解 Unicode；大小写碰撞；尾点/空格、保留名、长路径、UNC、根目录、Linux 非 UTF-8 bytes；跨机 fixture 与固定 hash 向量；覆盖镜像父目录解码、缺失/非法镜像路径、context-repl 把 XML 移到另一目标镜像目录的 rebind、手工 rename 设置 marker、自动 rename 不设置、marker true/false 在 rebind/copy/import 后保持、旧/新逻辑路径与 hash 向量，以及 root-list/alias/selector 零 schema 扫描。
- **通过条件**：显示替换不改变实际路径/hash；镜像父目录可唯一解码为 current root 或明确拒绝；Context rename/rebind 后逻辑 XML 路径与 hash 立即重算；碰撞/不可读范围不误选；tool/Prompt/XML/approval 只消费该唯一 root 且无 root selector，外部一次性访问不会暗中新增 root。
- **失败后**：`J`。技术侧可拒绝无法无歧义编码的路径；若要缩小已确认中文路径/平台保证，需负责人决定。
- **关联**：`PROD-05`、`AQ-177`、`AQ-189`、`AQ-223`、`AQ-386`、PJ-18、`CX-08`、`AR-P0-11`。

### TP-013 Context Resolver 的遍历复杂度与正确性

- **当前状态**：`specified`；由 C16/C28/C32 执行 traversal/cap benchmark。
- **要证明**：已确认的增量搜索环、同环 name-before-hash、hash-like selector 单遍双判定和不重复处理候选，在大目录、链接环、不可读范围和并发变化下仍得到确定结果；Catalog view 的 `created|updated|name` + 双向排序只改变已发现结果的投影，不改变 Resolver 胜负或触发裸启动扫描。
- **最小证据**：多祖先/子树、近 hash/远 name、同环碰撞、权限错误、百万候选、reparse/symlink cycle、扫描期间 rename/delete；对每个集合跑三键×两方向、相同主键、复制/replace 改变 mtime/ctime、跨机导入与随机枚举顺序；另覆盖 `CreatedAt` 初建后不变、成功 durable mutation（含 rename/rebind）推进 `UpdatedAt`、失败/inspect 不推进。在目标旧机上分别记录 traversal、路径解码、候选 hash 派生、metadata 探测和排序的次数、首反馈、耗时、峰值内存、hard cap 与 stale generation。
- **通过条件**：候选最多有效探测一次；当前环未完整不能宣称唯一或不存在；每个平台发行 manifest 冻结不可放宽的 Runtime scan cap，超限返回 scan-incomplete；self-test 报告探测范围、数量、耗时和 partial，而不是把慢或不完整报告为 healthy；列表只使用 XML canonical CreatedAt/UpdatedAt/名称，主键相等时始终按 canonical `LogicalPath` 升序，绝不随 `ListSortDirection` 反转，也不读取 mtime/ctime；`CreatedAt` 在初次 durable 创建后永不改变，`UpdatedAt` 只在成功 durable mutation 中原子推进，失败或 inspect 不推进；改变排序不能改变同一 selector 的 Resolver 结果；浏览器、CLI、rename/delete 使用同一服务且不读取 `MaxScanEntries` 配置。
- **失败后**：`J/T`。技术侧先优化遍历、分页与 manifest cap；只有改变已确认裁决顺序或产品保证才回到负责人。
- **关联**：D-024、`CX-08`、`CX-09`、`AR-P0-11`。

### TP-014 direct file tools 的字节保真与冲突检测

- **当前状态**：`specified`；由 C24/C25 的 direct-tool/fault suite 执行。
- **要证明**：read/search/write/patch/rename/delete 在 CRLF/LF、BOM、无效 UTF-8、二进制、大文件、权限位、case-only rename、hardlink/symlink 与外部并发修改下不会静默改写用户数据；workspace 外 direct path 统一服从已确认的粗粒度 `OutsideWorkspace` 与基础能力取更严格值，不改变路径规范化或 raw shell 边界；M05-56 A 要求整个 SensitiveRead classifier surface 为零。每个 direct call/approval 都只绑定 Context XML 镜像父目录解码出的唯一 root，tool/Prompt/XML 没有 root selector；raw exec 的 cwd 只是 provenance，不能被误写成 OS sandbox。
- **最小证据**：字节级 fixtures、expected digest 竞态、no-replace、原子替换失败、链接目标替换和特殊文件；比较操作前后内容与元数据；生成 `Read/Write/Delete/Shell/OutsideWorkspace` 的 allow/confirm/deny 矩阵，并对 SensitiveRead parser/schema/help/classifier 做零项扫描。单 root 覆盖镜像父目录外改、rebind 后 stale approval、伪造 root-list/alias/selector 字段的拒绝；另用绝对路径、链接和子进程证明获批 raw exec 可能触及任意 OS 可访问路径，UI 不宣称 root-scoped shell。
- **通过条件**：文本工具只处理已声明文本；无法保真时拒绝或走诚实标为宽能力的 raw shell；每次 direct 副作用重新验证目标与当前镜像路径 generation；`OutsideWorkspace` 与基本能力取更严格结果且不存在拆分 outside/SensitiveRead 字段、parser、help 或 classifier；tool schema/Prompt/XML 的 root-list/alias/selector 数为零；rebind 后旧 approval 不得用于新 root；raw exec approval 明示当前 cwd 与 OS 外部可达风险；活动 workspace 失效时 fail-stop，不沿用 stale 路径或猜测重绑；结果说明内容、属性、文件系统能力和截断变化。
- **失败后**：`T` 收窄工具契约；任何扩大到自动编码转换的行为须 `O` 明确同意。
- **关联**：`PROD-05`、`PROD-16`、`PLAT-13`、`AQ-112`--`AQ-118`、`AQ-149`、`AQ-150`、`AQ-268`、`AQ-269`、`AQ-370`、`AQ-372`、`AQ-386`、`AQ-430`、PJ-18、M05-16、M05-56、`TS-02`、`TS-07`、TS-21、`AR-P0-06`、`AR-P0-11`。

### TP-015 canonical Model 协议与工具增量

- **当前状态**：`specified`；exact synthetic inventory 已冻结，由 C21 录制 provider bytes 并执行 conformance。
- **要证明**：D-050 已选的 `openai-chat` 与 `anthropic-messages` 两个 wire profile，其 role、SSE、text/reasoning/tool delta、usage、finish/refusal/error 可以归一为稳定事件；断流或畸形响应绝不提前执行看似完整的 tool call。D-052/TS-23 A 的 typed ToolInputRegistry 必须让 Model 请求中的 exact registry/schema identity、response admission、canonical accepted arguments、approval/XML snapshot 和 result pairing 一致；`exec.command` 在 typed envelope 中保持 opaque 原始字符串，不被 Runtime 分词或改写。D-044 排除 image/audio/transcription/speech content-part、capability 和 purpose，宽松 passthrough 也不得意外开启它们；`openai-responses` 不属于 v0.1 adapter/profile/fixture 集合。
- **最小证据**：为 `openai-chat` 与 `anthropic-messages` 分别保存真实录制与合成 fixture，覆盖 native object function/tool、任意分块边界、同响应 text+tools、重复/缺失 call ID、call/result 错配、JSON 断尾/重复 key/深度炸弹、typed argument 空/超限/无效 encoding、length/refusal/filter、streaming force/try/off、逐工具 required/unknown/type/size/encoding 变异与 schema digest 不匹配。两个 adapter 都发布完整 core registry，逐工具跑 TP-010 canonical scalar/XML carrier corpus并验证 request wire、accepted argument bytes、approval/XML snapshot、operation 与 result 配对；再做 manifest 能力伪报、只支持部分工具、Model 切换、重试/断流/取消以及 `openai-responses`/free-form/custom item 稳定拒绝测试。对四个媒体轴固定执行 zero-profile/content-part/capability/purpose/request scan。
- **通过条件**：Model request 前发布 exact tool schema；只有完整 response、call ID/envelope/arguments 全量校验、canonical assistant/call 事件 durable 后工具才 accepted；畸形调用不建立 operation，raw command 不被分词、重写或推断细粒度 capability；每个本地 ID 唯一。`openai-chat` 与 `anthropic-messages` 都必须无损承载完整 core registry；只有通过 fixture 的 adapter/Model 才有 main-tool 资格，不匹配者按 Model capability 规则在发送前稳定阻断。每个 accepted scalar 通过 TP-010 的 wire→canonical→XML→canonical byte-exact gate；provider registry 中 `openai-responses`、free-form carrier、image/audio/transcription/speech 条目数为零，不支持的外来 payload 在采样前拒绝且不静默换 Model；重试不会把已见 canonical event 的响应整体重放。
- **失败后**：`T` 可修正同一 `openai-chat`/`anthropic-messages` profile 的 adapter/parser；若任一正式协议无法无损承载已选 typed core registry，则该 adapter 不得发布。只有两套正式协议都无法满足完整产品闭环时，才把最小反例交回 owner 重开协议范围或工具保证，不能偷加 `openai-responses`、free-form fallback 或缩小 registry。
- **关联**：`PROD-17`、`PROD-18`、`PROD-20`、`PROD-21`、`AQ-034`、`AQ-383`、`AQ-384`、`AQ-388`、`AQ-389`、TS-02、TS-23、PJ-15、PJ-16、PJ-19、PJ-20、`M05-01`、`M05-03`、M05-26、TP-010、TP-021、`AL06-03`、`AR-P0-03`、`AR-P0-06`。

### TP-016 typed control 对支持 Model 的可用性

- **当前状态**：`specified`；native control schemas/fixtures 已冻结，由 C21/C22 执行 provider capability matrix。
- **要证明**：`finish/ask-user/refuse` 载体、action-review/termination-review verdict、compaction schema，以及 D-041 周期 `context-name` 的有界 basename 输出，在声明支持的 Model 上达到可接受的结构化成功率，并能在无效输出时确定失败关闭。`context-name` 只有在 `AutoNameEveryMainTurns>0`、每 N 个已 durable 完成 main turn 的新基线到期且 `AutoRenameDisabled!=true` 时低优先级触发；它无工具权，新 main 或退出可取消，退出不等待，恢复不重放。
- **最小证据**：跨 Model 固定任务、提问、部分完成、拒绝、工具后完成、注入、复核拒绝/无效 schema 和压缩 fixtures；命名另覆盖 `N=0|1|10`、marker missing/false/true、设置/取消标记、取消后的新基线、未完成/取消 main turn 不计数、同时到达新 main、退出、请求失败、无效 basename、崩溃/恢复和工具调用注入；专门注入“命名 request 在途时手工 rename/添加 marker，随后 endpoint 返回迟到成功”竞态并记录 admission、cancel、usage/result、名称/hash、retry、token/费用、误终止和误继续。
- **通过条件**：Runtime 不解析自然语言猜状态；无效 control 不变成 completed；typed `ask-user` 与其后用户回复通过 durable turn/reply-to identity 形成唯一因果关系；reviewer 和 `context-name` 都不取得工具；周期计数只消费已提交的完成 main turn，marker=true 时零新 request/zero cost，取消标记不立即命名、不追补，marker 变 true/取消/退出/恢复后的迟到结果只留完整事实且绝不采用名称，不产生幽灵重命名；硬预算始终收口；差异不靠逐字输出判断。
- **失败后**：`J`。先调整 prompt/schema/兼容协议；若某 Model 无法可靠使用核心控制，则负责人决定标为不支持工具 Agent、降级文本模式或移出正式 Model 范围。
- **关联**：`LOOP-28`、`AQ-251`--`AQ-259`、`AQ-363`、`PP-05`、`AL06-02`、`RF-07`。

### TP-017 AgentLoop 全出口 typed outcome

- **当前状态**：`specified`；synthetic traces 已冻结，由 C26/C27 执行 fault/cap/target exits。
- **要证明**：完成、waiting-user、cancelled、budget-exhausted、stuck、refused、partial、error、storage-failed 和 unknown-side-effect 等所有出口都通过同一状态机产生，任何 `break/error` 不会在外层误报 completed；suspend/resume、ask-user reply、用户手动 retry，以及已选 AL06-39 A 的 idle `manual-compaction` maintenance turn 都不绕过正式 turn/request/attempt/maintenance transition。AL06-50 A 从版本化发行 manifest 取得只读 threshold tuple，并机械应用到 `exact-repeat`、`same-error`、`abab-cycle` 与 `semantic-no-progress`；INI/XML 不生成 stuck/no-progress 阈值字段。registry 仍必须冻结输入事实、signature/fingerprint、counter、canonical progress/reset、Runtime hard maximum 和 unfinished-turn 恢复语义。算法与具体数值属于技术证明，不改变 AL06-28 A 的一次 warning/escape-step 后 `stuck` 行为。
- **最小证据**：逐 transition golden trace；在模型、tool、approval、storage、queue、steer、side、DoubleCheck、周期命名、自动 compaction、idle manual-compaction、suspend/resume、waiting-user reply 和每类 retry 入口注入取消、预算和错误；命名覆盖 marker=true 零 admission、取消 marker 新基线以及在途请求被新 main/退出取消。对 detector 建立表驱动 oracle：同 tool/version/canonical args 且相关 pre-state digest 不变的 exact repeat；同 canonical action 连续得到相同 typed error ID/category/stage 的 same-error；`A-B-A-B` action/result signature cycle 与近似反例；多次 model-only 回复、termination-review 同一缺口、compaction 无收益和文字变化但 progress fingerprint 不变的 semantic no-progress。逐项注入真正 canonical progress 以及不得 reset 的换措辞、换 Model、retry、review、无收益 compaction、queue/steer 重排；在 counter 增量、progress reset、warning commit、escape step 和 terminal outcome 每个 durable 边界杀进程并恢复。对 manifest threshold tuple 覆盖合法边界、0/off/infinite/越界构建拒绝、旧 snapshot、manifest identity 不匹配与 detector 算法升级，并扫描 INI/XML/config-repl 中相关用户字段为零；手动 compaction 覆盖 idle admission、busy typed reject、独立 maintenance ledger、取消/退出/崩溃和原子 view publication。
- **通过条件**：每个 accepted tool call 配对真实/synthetic result；terminal review 只由 typed finish 触发；ask-user reply 的 turn/快照/预算按已选规则唯一冻结；UI 不存在无对象的泛化 retry，安全 attempt、新 request/new turn 与 inspect-unknown 可由 trace 区分；queue 的后续动作与 outcome gate 一致；最终报告与机器 outcome 同源。四类 detector 只消费已提交 canonical facts 和稳定 typed identity，不以自然语言相似度、provider ID、Model 名或平台枚举顺序猜进展；相同 trace 在 XP/CentOS、不同 chunking 和恢复前后得到相同 fingerprint、counter、warning 与 terminal outcome。只有 registry 明定的 canonical progress 才 reset 对应模式；重启、retry、review、compaction、换 Model 或改措辞不清空当前 turn 已 durable state。一个合法的 manifest threshold tuple 机械应用到全部已登记 detector；缺失、0/off/infinite、超 hard maximum、INI/XML override 与无法验证的 snapshot 都在任何新 Model request/tool effect 前 fail closed。达到阈值后的 warning/escape/wait/stuck 只服从 AL06-28 A，用户配置不能改写出口。manual-compaction 只在 durable idle 接受，使用独立 maintenance identity/ledger，失败、取消或崩溃保持旧 view 和完整事实。
- **失败后**：`J`。技术侧先修正 signature、fingerprint、durable state 或 registry；若已选 manifest threshold tuple 无法在目标平台确定恢复，则把最小反例交回 AL06-50/LOOP-31，不能静默改成用户 scalar/多字段 map、清空计数或通过 TUI 文案掩盖领域误报。
- **关联**：`RUNTIME-06`、`LOOP-05`、`LOOP-14`、`LOOP-28`、`LOOP-29`、`LOOP-31`、`COMP-11`、`CFG-13`、`CFG-15`、`AQ-363`、`AQ-364`、`AQ-379`、`AQ-434`、`AL06-02`--`AL06-12`、`AL06-28`、AL06-39、AL06-42、AL06-50、`AR-P0-02`、`AR-P0-12`。

### TP-018 operation 屏障与副作用恢复

- **当前状态**：`specified`；由 C17/C25/C27 的 kill-point/operation suite 执行。
- **要证明**：direct file 与 raw shell 在执行前有 durable operation，执行后有真实或 synthetic result；崩溃发生在任意窗口时能判定 not-started/applied/unknown/conflicted，而不盲目重放。配置、Model、Permission 与 Context 的删除/reset/purge/import/migration，以及已确认的 Context rename/rebind/`AutoRenameDisabled` add/remove，必须复用等价的 `ManagementMutation` plan/stale-check/commit/result 证明，而不是复用 Agent approval；活动 writer 锁定的 Context 对外部 mutation 在 plan 前即拒绝。
- **最小证据**：在 Permission、DoubleCheck、human approval、operation commit、process spawn/file replace、result commit，以及 ManagementMutation 的 plan/impact confirmation/stale recheck/publish/result 每个边界杀进程；恢复时修改目标文件、配置引用或 Context generation 以制造 stale；对活动锁 target 尝试 rename/delete/rebind/Prompt/marker mutation，并在释放后用新 observation 重试。
- **通过条件**：历史 approval audit-only；unknown 默认不重放；通用 manual retry 不能重新执行 accepted/unknown operation；无法判断的 shell 不被 direct-tool hash 推断为成功；人工解算产生新事件而非改写历史；管理动作使用自己的精确目标和默认取消事实，不能继承历史 Agent 授权。
- **失败后**：`J`。若单 XML durable 路线不能提供所需屏障，返回 TP-008/TP-009 的存储取舍。
- **关联**：`ARCH-05`、`LOOP-29`、`AQ-103`、`AQ-104`、`AQ-225`、`AQ-279`、`AQ-316`、`AQ-364`、`AQ-369`、`CX-04`、`AR-P0-06`、`AR-P0-09`。

### TP-019 配置 parser、往返与事务

- **当前状态**：`specified`；grammar/config fixtures 已冻结，由 C07/C10 执行 parser/transaction/target matrix。
- **要证明**：typed schema、手工 INI、model/config REPL 和 Context XML override 对缺失/空值/重复/大小写/多行/unknown/deprecated 字段给出同一结果；编辑不会覆盖外部并发修改。D-049 固定 `Global.SystemPrompt`、当前 `Model.SystemPrompt`、当前 `Permission.SystemPrompt` 和 Context XML `ContextPrompt` 四个独立数据层；主/side request 按 Global、Model、Permission、Context 顺序标注构造，不覆盖、回写或自动读取项目规则。`.prompt` 与 context-repl 只编辑同一 ContextPrompt；`backup/` 只能是 Prompt 正文中的普通文字，不生成 Runtime 配置或动作。D-048 固定每个顶层 main/side turn admission 前完整读取 INI bytes 并计算 private digest：未变复用 immutable generation，变化后整份 parse/cross-validate 并一次发布，有效变化自动生效，半写/删除/无效引用阻止新 turn，active turn 及其 tool/review/retry/compaction 子活动绝不热换。M05-57 A 要求唯一版本化 `LogicalResourceNameCodec` 且不注册 `Abbreviation`：`Model.`/`Permission.` 是 ASCII schema prefix 与类型分隔，后续 suffix 是非空、严格 UTF-8 valid Unicode scalar sequence 的用户数据并保留原始 bytes；codec 冻结 delimiter/forbidden scalar、字节长度 cap、空格、dot 与 comment/quote/backslash 边界，匹配只 fold ASCII `A-Z`，其他 bytes 不做 locale case、Unicode normalization 或 filesystem folding。D-044/D-055/D-056 必须机械投影为零 Web/media/remote/transcription/TTS/standalone-log/spool/telemetry/upload/update 字段；D-045 固定 current-root/workdir/root-list/alias/selector 配置字段数为零；D-046 的 `AutoRenameDisabled` 只存在于 Context XML；D-047 固定两个 INI-only Context 列表排序字段；启动头 master 不得注册。
- **最小证据**：合法/非法 corpus、注释与顺序 round-trip、秘密保持/替换/清除、两个配置 writer、短提交锁与 expected digest、运行中外部原子/非原子保存、每个顶层 main/side turn、子活动不重载、相同 bytes/同尺寸快速改写/粗粒度 mtime、有效/无效/删除新版本、磁盘满、previous-valid/replace 恢复、旧/新 schema migration；在 XP/CentOS 测完整小 INI 顺序读、digest、变化时 parse/validate 的延迟与峰值。四层 Prompt 覆盖 missing/present-empty/多行/超限/版本、`.prompt` 与 context-repl 往返、main/side 次序与 source label、特殊 purpose 的 fixed+Global+Model 构造及 Permission/Context 仅作有界 quoted data 的夹具；对 project-rule loader、`backup/` Runtime 字段/动作执行零项扫描。名称 corpus 同时从手工 INI、writer、model/config REPL、CLI selector 和 Context XML current/history mapping 进入，覆盖 empty、1 byte、cap-1/cap/cap+1、ASCII case pair、CJK、非 BMP、组合/预组合 Unicode、不同 normalization、土耳其 I/ß、畸形 UTF-8、surrogate/NUL/CR/LF/C0/DEL、raw `[`/`]`、`=;#'"\\`、前后/内部 ASCII 与非 ASCII space、前后/连续/内部 dot、同名重复和 Model/Permission 跨 namespace 同名；对 `Abbreviation` 做 parser/writer/REPL/help/completion/XML 零项扫描。对每个 accept case 做 parse→typed draft→write→parse 和 INI↔REPL↔XML byte-exact round-trip；对每个 reject case比较 XP/Windows 与 Linux 的 stable error/offset，排列 section 顺序并制造 logical-name ASCII-fold collision。再从 typed registry 枚举 secret 副本，验证粗粒度 `OutsideWorkspace` 与零 SensitiveRead；生成无 startup master、D-044/D-055/D-056 零字段、D-045 zero-root-field、D-046 XML-only marker和 D-047 排序字段 snapshot，并做迁移/冲突测试。
- **通过条件**：模板/帮助/验证/REPL 同源；四个 Prompt 层独立保存、限制和快照，main/side 以稳定 Global→Model→Permission→Context 顺序构造且保留 source/version，user message 仍是独立消息；特殊 purpose 不让 Permission/Context 文本取得指令权威，也不存在 project-rule loader 或 Runtime `backup/` 能力。同一发行在所有目标平台使用同一 name-codec version、UTF-8 validator、byte cap、delimiter 与边界分类。ASCII type prefix/分隔符不会被吞进 logical name，suffix 中被 codec 接受的 dot/space 不被再次切段或 trim；raw closing delimiter、控制字符或其他拒绝项得到同一 typed error，绝不替换、normalize、自动加引号/数字或按物理顺序选第一项。accepted logical name 的显示原拼写、INI bytes、selector resolution 和 XML current reference 一致；只折叠 ASCII A-Z，NFC/NFD 与非 ASCII 大小写仍按原 bytes 区分。`Abbreviation` surface 为零，selector admission 后始终冻结完整 logical name。Permission 只有粗粒度 `OutsideWorkspace`，没有 SensitiveRead 字段或分类器；startup master、D-044/D-055/D-056 字段/section、D-045 root 字段与 INI `AutoRenameDisabled` 数均为零，D-047 两字段只有完整默认/枚举/敏感性/生效点；未知安全字段不被静默忽略。每个顶层 main/side turn 只在 admission 前观察完整 INI；digest 未变不重复 parse，有效变化自动发布一个完整 generation，无效/半文件/当前 Model 或 Permission 失效时阻断该新 turn并给 self-fix，不混用新旧字段、不 fallback 第一项；active turn 与全部子活动快照不漂移，也不存在 watcher/reload interval/policy 字段。任一 registered config-secret exact value 不出现在 diff/history/XML，普通正文未知 secret 的限制如实说明；清除操作准确说明 yaca 已知副本与 best-effort 边界；首项默认和 disabled 行为稳定。
- **失败后**：`J`。技术侧先修正 parser/writer/codec 并可收窄不能无歧义 round-trip 的语法；若会排除 D-029 已确认的 Unicode 用户数据或无法兑现 zero-Abbreviation selector surface，则把最小反例交回对应 owner，不能改成 ASCII-only、locale match 或隐藏 alias。若要取消手工编辑或改变层级/默认顺序，同样交 `O` 确认。
- **关联**：D-029、`ARCH-05`、`PROD-15`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`FMT-02`、`CFG-24`、`CFG-27`、`AQ-149`、`AQ-150`、`AQ-246`、`AQ-361`、`AQ-369`、`AQ-382` 至 `AQ-390`、`AQ-430`、`AQ-432`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16、`M05-06`--`M05-10`、M05-16、M05-56、M05-57、`AR-P0-09`。

### TP-020 配置与 Context 恢复的交叉兼容

- **当前状态**：`specified`；由 C10/C15/C18 的 mapping/import/recovery matrix 执行。
- **要证明**：Model/Permission 重命名、删除、禁用、endpoint 改变、Description 投影、Prompt 版本升级和 XML override 在恢复/导入时不会静默选择第一项、继承旧授权或把历史 endpoint 当当前连接。CX-18 B 使用版本化 `required-now|action-specific|history-only` compatibility severity，未知/无法分类默认 `required-now`；每项 mapping/acknowledgement 都形成 durable event。AL06-51 C 使用 canonical `EndpointDisclosureBinding`：按 `action-review|termination-review|compaction` purpose 分别绑定当前 main/目标 Model 的完整逻辑身份与非秘密 snapshot、normalized endpoint origin/path、Protocol/tenant/auth-policy identity、proxy route、Model/config generation、data-class envelope、Context/mapping/import generation 和 codec/version；每个 Context/purpose/binding 的首次跨 endpoint 请求 fresh confirm 并 durable 保存可复用 consent，后续每次请求仍保存 exact range/view receipt。本机原 Context 恢复且 binding 未变时可复用；foreign/import、复制、workspace rebind、目标机 remap 或 mapping generation 改变后的历史 consent 一律 audit-only。D-044 的 media/remote 历史只能成为 unknown/history gap，不能激活本机能力；D-055/D-056 下没有 telemetry/diagnostic-upload/update endpoint 或 source-verifier gap。
- **最小证据**：旧名缺失、同名不同 endpoint、Permission 降级/升级、Description 投影、DoubleCheck override、Prompt 版本变化、顶层 turn 之间配置有效/无效变化、目标机路径映射、workspace rebind/copy/import、marker true/false、Model/Permission/Prompt/tool/evidence/unknown-extension gap、foreign XML 等 fixtures。对三 purpose × endpoint/binding/本机恢复/foreign import 做 AL06-51 C trace matrix，在 consent、receipt、network write 与每个 durable 边界杀进程；对 CX-18 B 覆盖三类 severity、unknown severity、action-specific 阻断和 durable acknowledgement。D-044 覆盖外来 media/remote 历史只进入 unknown/history、当前 capability/codec/device/controller surface 为零；D-045 覆盖目标父目录决定唯一 root、零 root list；D-055/D-056 覆盖 telemetry/diagnostic/update gap 与 receipt 零项扫描。
- **通过条件**：历史 snapshot 完整保留；当前 effective 配置只在顶层 turn admission 重新计算并原子冻结，active turn 不热换；Description 不能推导能力或授权；新的 Context mapping/config generation 与旧历史之间存在显式版本边界。三个特殊 purpose 的 consent namespace 永不共享；durable per-purpose consent、binding、network-write 前复核与崩溃 unknown 严格服从 AL06-51 C，历史 approval/receipt 不授权新请求。所有 mapping/switch/acknowledgement 成为新事实；`required-now` 全局阻断，`action-specific` 只阻断依赖动作，`history-only` 醒目标记但不伪装完整证据；被阻断的 purpose/action 不先发请求或执行工具。copy/import/rebind 保留 marker、由目标父目录派生 root且不读取 XML root authority；D-044 外来 media/remote XML 只能作为 history/unknown extension 解释，不能反向激活本机 surface；telemetry/upload/update compatibility surface 为零。
- **失败后**：`J`。技术侧可改 canonical encoding、digest 或恢复协议；若 AL06-51 C 的 durable cadence 无法在目标平台关闭 replay/TOCTOU，则把反例交回 AL06-51/MODEL-17，不能静默改成逐次/进程内/永久复用或 fallback main/第一 Model。其他静默 fallback 同样不得作为简化退路。
- **关联**：`CFG-24`、`CFG-25`、`CTX-29`、`MODEL-17`、`SAFE-08`、`SAFE-09`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-235`、`AQ-236`、`AQ-246`、`AQ-274`、`AQ-295`、`AQ-347`、`AQ-361`、`AQ-378`、`AQ-380`、`AQ-383` 至 `AQ-390`、`AQ-435`、PJ-15 至 PJ-20、ED-13、ED-14、RF-16、`M05-43`、M05-52、AL06-08、AL06-30、AL06-49、AL06-51、`CX-07`、`CX-12`、`CX-18`、`AR-P0-08`、`AR-P0-10`、`AR-P0-11`。

## P1：子系统实施前必须闭环

### TP-021 INI/XML/JSON 的数值与内存边界

- **当前状态**：`specified`；由 C05--C10/C15/C32 的 boundary corpus 与 target calibration 执行。

- **要证明**：Lua integer/number、C size、event seq、毫秒、token、usage 和外部 64 位值在 Win32 x86 上不溢出、不变负、不因转成浮点丢身份；D-044 不建立媒体/remote size 字段，D-045 固定 root count/list/alias/selector 数值字段为零；D-055/D-056 固定 telemetry、diagnostic upload 和 update 的 content-length/receipt/download 数值字段为零。
- **证据**：边界/越界 corpus、长会话 seq、极大 provider usage、size multiplication 和 allocation failure；D-044 size/limit、D-045 root-count/list 与 D-055/D-056 telemetry/upload/update 数值 registry 零项扫描。
- **通过条件**：所有外部数先验证再分配/相乘；D-044 对应 parser/limit、D-045 root-count/list 与 ED-13/ED-14/RF-16 的 telemetry/upload/update 字段数均为零；不能精确表示的计量以十进制文本或受控整数模型持久化。
- **责任**：`T`。关联：`RUNTIME-05`、`FMT-03`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-382` 至 `AQ-390`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16、`AR-P1-08`。

### TP-022 backpressure 与全局资源公平性

- **当前状态**：`specified`；TP-003 core 提供 modern 基线，由 C03/C20/C26/C28/C32 执行组合压力。

- **要证明**：慢 TUI、慢 XML、快 SSE、快子进程和大扫描同时发生时，有界队列不会饿死 cancel/approval/input，也不会无限积累 Lua table；六个核心 purpose 与 D-041 周期 `context-name` 共享同一 Model scheduler，使并发、最小间隔、`Retry-After` 与 aggregate budget 不被局部重试绕过。命名只在全局间隔启用、durable waterline 到期且 marker!=true 时低优先级进入；新 main/退出取消，退出不等待，恢复不补跑，取消 marker 从新基线开始。M05-58 A 的 retry snapshot 由每 Model `RetryCount`/`RetryBaseDelayMs` 与发行 manifest 的 exponent/max/deterministic-jitter 构成；AL06-50 A 从同类版本化 manifest 取得只读 detector threshold tuple，不生成用户阈值字段。F4-15 A 固定每进程恰有一个 active Context，每个 Context 恰有一个 root；D-044/D-055/D-056 的 Web/remote/media/telemetry/upload/update 队列和 worker 全部为零。
- **证据**：组合压力夹具、真实/可编程 endpoint、虚拟时钟、XP/CentOS timer、单/多并发假 Model、429/503/`Retry-After`、suspend/resume、main+side+review+compaction+周期命名竞争、取消等待中的 request/retry、队列水位和逐 purpose/Context/aggregate 账本。命名覆盖 `N=0|1|10`、marker missing/false/true、设置/取消、新基线、阈值、失败、退出、新 main 与崩溃恢复。对已选 retry tuple 与 AL06-50 A manifest threshold tuple 运行全边界/故障矩阵，并扫描未注册阈值配置为稳定错误；按 F4-15 A 只覆盖一个 active Context 及其唯一镜像派生 root，另扫描零第二 Context/root 队列或账本。D-044/D-055/D-056 执行零 client/device-stream/telemetry/upload/update worker 扫描。
- **通过条件**：控制事件优先级明确但不重排 durable 因果；可丢 UI delta 与不可丢领域事件分开；同 Model 调度服从 `AQ-362` 且无饥饿/超发/冷却穿透。已选 retry snapshot、`Retry-After`、logical/turn/Context/Runtime 总账与 AL06-50 A detector state 在 XP/CentOS/重启间保持确定；cancel 不产生幽灵重试。周期命名只消费已提交 main-turn 水位、marker=true 时零 queue/cost、无工具且不阻塞退出；取消 marker 不立即或追赶命名。F4-15 A 下没有第二 active Context/root worker 或账本，D-044/D-055/D-056 没有后台资源域；超限产生 typed result。
- **责任**：`J`。技术侧可优化 timer、scheduler、fingerprint 或有界 registry；若已选 retry snapshot/AL06-50 A 路线无法在目标旧机满足确定性、恢复或硬预算，只把反例交回对应 owner，不得未经最小重开就改配置形态、放宽总账或清空 detector。关联：D-036、`RUNTIME-07`、`MODEL-15`、`NET-06`、`LOOP-05`、`LOOP-14`、`LOOP-27`、`LOOP-31`、`CFG-13`、`CFG-15`、`CFG-28`、`CONC-02`、`CONC-04`、`PERF-01`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-140`、`AQ-197`、`AQ-221`、`AQ-359`、`AQ-362`、`AQ-381` 至 `AQ-390`、`AQ-433`、`AQ-434`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16、M05-58、AL06-28、AL06-42、AL06-50、F4-02、`F4-15`、`AR-P0-04`、`AR-P1-02`、`AR-P1-04`、`AR-P1-08`。

### TP-023 terminal renderer 安全与确定性

- **当前状态**：`specified`；40-column synthetic transcripts 已冻结，由 C13/C14 执行 target recordings。

- **要证明**：模型/工具/路径中的 ANSI、OSC、C0、超长行、tab、CR、backspace、双向/零宽 Unicode 不会执行控制序列、覆盖审批文本或改变真实复制数据；40 列和无宽度信息仍可操作。D-044 已排除 image/audio/transcription/speech 渲染，用户数据只通过文本或既有文件工具结果进入 transcript。
- **证据**：恶意输出 corpus、golden transcript、resize/管道/无色/旧 console 录制；不可信 Unicode 路径/Context 名；help/renderer 对媒体、设备、转写、播报标签和占位的零项 snapshot。
- **通过条件**：程序标签固定 ASCII；不可信控制字符可见转义；颜色只是增强；同一领域事件在 renderer 降级后语义不变；媒体/语音状态与动作数为零；用户路径或内容显示降级不改变真实 identity/hash。
- **责任**：`T`。关联：`CLI-17`、`PROD-17`、`PROD-18`、`PROD-20`、`PROD-21`、`AQ-231`、`AQ-300`、`AQ-331`--`AQ-340`、`AQ-376`、`AQ-383`、`AQ-384`、`AQ-388`、`AQ-389`、PJ-15、PJ-16、PJ-19、PJ-20、`TU-12`、`TU-23`、`AR-P0-05`、`AR-P0-13`。

### TP-024 CLI、dot command 与非 TTY grammar

- **当前状态**：`specified`；action/argv/fd/machine fixtures 已冻结，由 C12/C14 执行 target shell matrix。

- **要证明**：唯一 command/help/action registry 能无冲突生成 parser、topic help、TUI 投影和 tests；每个 TUI 领域动作都有 CLI 等价投影，renderer-only 上下移动/滚动/分页不是领域动作，也不由此开放 public headless controller。`--`、引号、以 `-` 开头路径、点命令 literal、多行、focus-scoped local/global namespace 和非 TTY exit class 在 Windows/Linux shell 边界下一致；stdin/stdout/stderr 独立能力与显式 machine mode 得到确定 prompt/output；配置/Model/Context 的同一管理动作经 CLI 或 REPL 投影时产生相同 `ManagementMutation` plan/result，而不是各自放宽确认。`.model` picker、`.model <selector>` 与 CLI Model 选择必须提交同一 typed `select-model`；`--context-repl recent|full` 分别投影快速最近列表与完整 Catalog/目录树，但共用同一 Resolver/controller。D-044 从 registry 生成零 Web/media/remote/transcription/TTS action；D-045 生成 zero root-list/add/remove/select/alias action，只保留单根 rebind；ED-13、ED-14、RF-16 的 telemetry/upload/update action 数均为零。
- **证据**：argv/property corpus、cmd/sh quoting fixtures、command/topic × AgentState/focus golden matrix、stdin×stdout×stderr×machine-mode stdout/stderr snapshot；对每个 TUI 领域 action ID 反查唯一 CLI projection；`.model` picker/direct/CLI 覆盖相同 selector、invalid/disabled target、取消、narrow terminal 编号/文字后备、补全启用/禁用与相同 receipt；unknown topic 建议、overview/detail help、reset/delete/purge/import/migrate/rename/rebind/marker add-remove 的 CLI/三个 REPL 等价 trace，覆盖 `context-repl recent|full`、活动 Context `LockConflict`、释放后新 observation、默认 Enter、取消、stale target 和非 TTY；D-044、multi-root、telemetry/upload/update action/help/completion 零项 snapshot。
- **通过条件**：重复简称、action ID 或 topic 构建失败；每个领域动作经 TUI/CLI 得到同一 target、admission、Permission、confirmation、stale-check、default-cancel、result 和 error，补全或方向键不可用不影响完整操作；这套映射不产生 listener/controller/自动审批。D-044、multi-root、telemetry/upload/update action/topic/completion 数为零，recent/full、rebind/marker 有完整结果；活动 writer 存在时外部 Context mutation 在任何入口都拒绝。modal 输入不能在 local verb、global action、chat 文本和 approval 之间静默换义；human pipe 不自动变成 machine payload；无交互输入时不弹菜单或默认批准破坏动作；错误定位到 token/focus/状态。
- **责任**：`T`；名称和可见确认体验已由 D-054/AS-006-04..05 固定，技术侧证明 parser/renderer 投影一致。关联：`ARCH-05`、`CLI-16`、`CLI-17`、`CLI-18`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-246`、`AQ-369`、`AQ-375`--`AQ-390`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16、`TU-10`、`TU-11`、`TU-22`--`TU-24`、`AR-P0-13`。

### TP-025 compaction 的事实保留与有效性

- **当前状态**：`specified`；由 C28 的 golden reconstruction 与 long-Context suite 执行。

- **要证明**：结构化 prefix summary + 最近完整原子组在目标窗口内，保持目标、决定、限制、改动、验证、unknown、未完成事项和 Model/Prompt 切换；Runtime 能按有效 Model/request shape 计算只读 effective reserve 且不会被 INI/XML 覆盖；失败/无收益不会递归耗费。AL06-16 A 下，单个不可拆必需原子组超过目标 Model 窗口时在发请求前阻断，优先提示 Context 历史中曾使用且窗口足够的 Model，不自动切换或静默切断 call/result。AL06-39 A 的 `.compact` 只在 durable idle 接受为独立 maintenance turn，费用/预算、取消、恢复与 view publication 不伪装成普通回复。
- **证据**：长会话/多代摘要、用户纠正、工具配对、Model 切换、恢复、larger-model rebuild、单条超大输入/工具组、注入和 secret canary 夹具；覆盖 AL06-39 A 的 idle admission、busy typed reject、独立 maintenance identity/ledger、取消/退出/崩溃与原子 publication，以及 AL06-16 A 的大窗口历史 Model 提示次序和无合格 Model 结果。
- **通过条件**：事实 XML 不删除；summary 可追踪 source range/digest；不能拆原子组；每个 request/view manifest 记录 effective reserve、输入摘要与算法版本，但不把它保存成 XML session parameter；超大单组在请求发出前得到稳定 typed result 且完整事实仍可查看；schema 无效保持旧 view；大窗口可重建更丰富原文 view。
- **责任**：`J`；摘要质量与失败边界已由 D-051 固定，算法和目标机证据由技术侧完成。关联：`COMP-06`、`COMP-11`、`AQ-310`、`AQ-352`、`AQ-379`、`AL06-11`、`AL06-12`、`AL06-39`、`AR-P0-12`。

### TP-026 self-test 的确定性、费用与隐私

- **当前状态**：`specified`；由 C29/C30/C32 的 staged/target suite 执行。

- **要证明**：静态、在线和 LLM advisory 三阶段严格分离；非 TTY 不隐式同意联网。Stage 1 必须检查 `CONTEXT` 镜像/codec、唯一 workspace root 是否存在/可进入/identity 一致、XML/lock/recovery object，以及 Catalog traversal、路径解码、候选 hash 派生的数量、耗时、hard cap 和 partial；单个当前 hash 的快速计算不得误报成 Catalog 扫描。Stage 3 只看脱敏的 Model/Permission 名称、Description/SystemPrompt 与实际 endpoint/model ID/capability matrix 摘要，提示明显错配或自然语言拼写，不能看 Key/完整工作区/真实对话、改配置、授予能力或把风格当硬错误。D-044 的 Web/remote/media checks、listener 与设备均不存在；D-045 只检查镜像派生单 root/zero-multi-root；D-055/D-056 的 telemetry、diagnostic upload 和 update check 均不存在。
- **证据**：缺配置、坏配置、Context 镜像非法、workspace deleted/unreadable/identity mismatch、损坏/不兼容/锁定 XML、少量/大量 Context、不可读目录、scan cap、慢 I/O、`.status` 当前 hash、离线、单 Model 失败、费用取消、恶意/误导/拼写错误的 Model 与 Permission 名、名称-能力双向错配、不同 reviewer、非 TTY fixtures；每项稳定 check ID 均从 TUI 与 CLI 做 list/select/legal-exclude；发送 manifest 与 canary 检查；D-044、multi-root、telemetry/diagnostic-upload/update 做零 check-ID/route/request snapshot。
- **通过条件**：每项检查有稳定 ID、stage、severity、scanned scope/count、duration、complete|partial、exit class 与 self-fix owner；当前目标损坏按规则阻断，其他历史损坏与 scan cap/性能问题不会被谎报为全局 healthy。确定性失败不被 LLM 覆盖；在线测试逐 Model/purpose 可重跑；Stage 3 advisory 明确可忽略且实际 Permission 始终由 capability matrix 决定；TUI/CLI 选择同一 check 得到同一结果，排除不能跳过阶段依赖；D-039 禁止的启动/定时/本地动作零联网，ED-13/ED-14/RF-16 对应 check/consent/request 数为零。
- **责任**：`J`。关联：D-039、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-246`、`AQ-382` 至 `AQ-390`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16、`M05-10`--`M05-12`、`TU-09`、`AR-P1-07`。

### TP-027 Git 与非 Git 改动证据

- **当前状态**：`specified`；由 C24/C25 的 dirty-worktree/fault suite 执行。

- **要证明**：yaca 能区分会话前用户已有改动、direct tool 改动、shell 可能改动和外部并发修改；Git status/diff 只作增强，不自动 stash/reset/commit/push；非 Git 仍有完整基础报告。
- **证据**：staged/unstaged/untracked/ignored/submodule、非 Git、case/line-ending/file-mode、shell 生成文件和外部修改 fixtures。
- **通过条件**：结束报告不把用户已有脏状态归功于 Agent；Git 不可用不破坏基础工具；二进制/超限变化诚实报告；unknown 不被 diff absence 当作未发生。
- **责任**：`J`。关联：`AQ-129`、`AQ-169`、`AQ-249`、`AQ-312`、`TS-08`。

### TP-028 数据分类与 secret canary

- **当前状态**：`specified`；TP-006 scanner 提供 modern 基线，由 C19/C23--C25/C32 执行完整 registry canary。

- **要证明**：每类数据在六个核心 purpose与 D-041 周期 `context-name`、TUI、XML、stderr、support、export、HTTP/HTTPS 和跨 endpoint 中严格服从同一矩阵；自动 secret detector 不夸大保证。`context-name` 只见有界命名视图、无工具，达到 durable main-turn 水位且 `AutoRenameDisabled!=true` 才发送，marker=true 时不形成 request/费用，取消 marker 只建新基线，取消/退出/恢复不重放。Stage 3 只接收脱敏的 Permission/Model 名称、Description/SystemPrompt 与真实能力/连接摘要，绝不接收 Key、完整工作区或对话。M05-56 A 要求 SensitiveRead 分类、数据类别和 gate 全部为零。AL06-51 C 的三个特殊 purpose 以 durable per-Context/purpose/binding consent 隔离，并在每次最终 network write 前复核。TS-40 B 只允许当前 ContextHandle 的已提交 canonical XML exact direct read，绑定 exact path/store generation/file identity/digest 并强制一次 exact-action 人工确认；其他 reserved object 均硬拒绝。D-044/D-055/D-056 的 media/remote/telemetry/upload/update 数据类别、peer、endpoint、carrier 和 consent 均为零。
- **证据**：由 typed registry 自动生成的 config-file/ambient/runtime secret、URL userinfo、HTTP endpoint、对话 token、私钥文件、shell 输出、编码/压缩后二进制和 foreign XML canary；覆盖 current/temp/previous-valid/config previous-valid/export、跨 chunk marker/digest、AL06-51 C 三 purpose durable consent/TOCTOU/crash 与 TS-40 B 当前 canonical XML exact-read/alias/race 矩阵。周期命名覆盖 `N=0|1|10`、marker missing/false/true、设置/取消/new baseline、最小视图、秘密排除、新 main/退出/恢复；Stage 3 覆盖 permitted manifest、Key/正文 canary 排除和 reviewer 输出仅 advisory。扫描零 SensitiveRead 与 D-044/D-055/D-056 category/payload/endpoint/device/carrier/consent。
- **通过条件**：结构化 secret 硬阻断；最终规则禁止的 secret 不经明文 HTTP 发出；M05-56 A、AL06-51 C 与 TS-40 B 严格按现行路线收口，历史 approval/consent 不授权新 Model、endpoint、purpose 或新 XML generation。周期命名无工具、只消费最小视图，marker=true 时零 request/cost，取消 marker 不追赶，并在退出/恢复后无幽灵请求；Stage 3 无 secret/工作区/对话 canary且不能改变 Permission。D-044/D-055/D-056 数据与 endpoint 数为零；raw shell 宽可达性只产生风险与审计，不被 direct gate 虚构成 containment；永久删除诚实列出已知副本、已发送内容和物理残留边界；LogLevel 不改变 canonical/secret 不变量。
- **责任**：`J`。若 AL06-51 disclosure identity/replay/TOCTOU 证明失败，技术侧先改 encoding/durable gate；仍不能兑现时把反例交回 AL06-51/MODEL-17，不得自动改 cadence或复用范围。关联：`NET-13`、`MODEL-17`、`SAFE-08`、`SAFE-09`、`CFG-25`、`CFG-29`、`CTX-28`、`CTX-29`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-246`、`AQ-276`、`AQ-349`、`AQ-358`、`AQ-368`、`AQ-378`、`AQ-380`、`AQ-382` 至 `AQ-390`、`AQ-430`、`AQ-435`、`AQ-436`、`AQ-437`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16、`M05-43`、M05-56、M05-59、AL06-08、AL06-30、AL06-49、AL06-51、TS-15、TS-16、TS-21、TS-40、`SAFE-18`、`CX-07`、`CX-18`、`AR-P0-08`、`AR-P0-10`、`AR-P0-11`、`AR-P1-06`。

### TP-029 模块/DLL/tool 搜索、ambient config 与完整性

- **当前状态**：`specified`；allowlists 已冻结，由 C01/C04/C31/C32 的 malicious-environment matrix 执行。

- **要证明**：yaca 内部 Lua/C 模块、DLL、curl/helper 只从 release manifest 的受控绝对路径加载；CWD、工作区、环境 `LUA_PATH/LUA_CPATH` 和普通 PATH 不能替换内部依赖；内部 curl/cmd/sh/Git/helper 也不能因用户 rc、AutoRun、pager、external diff/textconv 或其他 ambient config 改变基础设施语义。TS-40 B 的 `ReservedIdentitySet` 必须识别 Runtime canonical data-root `__yaca__` 的真实物理树并关闭 alias/race。宽 Shell 是另一条明确环境契约。D-044 的 listener/media/IPC 组件、loader、asset 搜索路径和 helper，以及 D-055/D-056 的 upload/update 组件，全部必须为零。
- **证据**：每个搜索位置放置恶意同名文件；在 home/workspace/环境/平台配置位置放置会执行或改写参数的 ambient config；Git pager/external helper/textconv、shell AutoRun/rc 与 curl 配置夹具；DLL dependency/import walk；运行时 hash/身份复核；安装路径含空格/非 ASCII/只读。为 reserved tree 在 XP/各正式 Windows 与 Linux 目标上建立真实 data root 和普通 workspace 同名目录，分别从内外创建 symlink、junction、各类 reparse point、mount/bind alias、case-fold/大小写别名、可用与禁用 8.3 short name、file hardlink 和链式组合；覆盖 alias 指向主 INI、current/other Context、temp/previous-valid/lock 及目录 parent。对 list/search 的隐式/显式 target，以及 read/create/write/patch/rename/delete 的 source/target/publish parent，在 canonical check 后、open 前、取 handle 后、用户确认后和读取/发布返回前交换 link、mount、目录项或 file identity；还覆盖不可读 ancestor、扫描 cap/权限导致 identity set 不完整、外部推进 Context generation 和 catalog stale。比较 component manifest 与三个最终 zip，对排除能力执行 loader/route/asset/helper 负向扫描；对实际 core 组件执行替换、错误架构/ISA 与 parser/helper 崩溃测试。
- **通过条件**：内部依赖与用户 raw shell 的 PATH/环境/配置明确分离；内部动作只受 allowlisted 输入控制，不启动未列外部 helper。TS-40 B reserved identity/handle 验证在 alias/race 下失败关闭，普通同名 workspace 目录不误判，raw shell 不被虚构成受 containment。D-044/D-055/D-056 对应 module/DLL/executable/asset/route/search-path 数为零；实际 core 组件缺失、被替换或受 ambient config 影响时按组件 ID 失败；不存在 RF-16 verifier/updater 或 RF-03 自动安装调用链。
- **责任**：`J`。技术侧先比较能保持同一 TS-40 B 保证的 handle/identity 实现；若目标平台无法证明 exact-read 的 alias/race closure，必须把最小反例交回 TS-40/SAFE-18，不能静默改成显示路径放行或扩大 reserved-tree 读取。关联：`PROC-13`、`THREAT-03`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-246`、`AQ-267`、`AQ-341`、`AQ-342`、`AQ-382` 至 `AQ-385`、`AQ-387` 至 `AQ-390`、`AQ-436`、PJ-14 至 PJ-17、PJ-19、PJ-20、ED-13、ED-14、RF-16、TS-07、TS-36、TS-40、`SAFE-18`、`AR-P0-14`、`AR-P1-11`。

### TP-030 最终 zip 的干净机闭环

- **当前状态**：`specified`；由 C31--C34 在三个最终包和干净目标机执行。

- **要证明**：Win32 x86、Win64 x86_64、Linux x86_64 三个最终 zip 在无开发工具、无系统 Lua、无网络（除用户显式允许的 Model/self-test 网络请求）、不同安装路径、最终 CPU/文件系统支持范围和普通用户权限下完成解压、配置、任务、工具、XML 恢复、升级/降级边界和卸载数据保留；被排除的扩展运行时及 D-044 六类能力不会因空 loader、配置字段、help/schema、endpoint 或搜索路径开放；D-045 的 multi-root surface 与旧 startup master 同样为零，单 root/rebind、D-046 marker、D-047 排序、D-048 每 turn reload 在 exact zip 中可用；D-055/D-056 的 telemetry、diagnostic upload 与内建更新保持零表面。
- **证据**：release manifest、SHA-256、SBOM 与明确 unsigned policy；Windows CPU ISA/PE 与真实机证据；数据根/workspace 文件系统矩阵；每个正式 OS 的干净机场景；损坏 zip/只读目录/杀毒占用/旧 schema fixtures；对 MCP、插件、hook、skill、自定义工具、子 Agent 和 D-044 能力执行 loader/command/config/help/schema/XML/Model-tool/clipboard-media/page/listener/endpoint/component/API 负向扫描；对 root list/alias/selector/action/component、startup master、telemetry/upload/updater 做零项扫描，并覆盖镜像父目录单 root、rebind、marker、六种列表排序、活动锁 mutation 拒绝、`.model` picker/direct/CLI 等价、有效/无效逐 turn 配置 generation、Stage 1 Catalog 检查与 Stage 3 Permission advisory，以及 D-039 零隐式网络。
- **通过条件**：测试对象是最终 zip 字节；组件 ABI、ISA、许可证和来源齐全；只有负责人确认的入口存在。D-044 每项、multi-root、startup master、telemetry、diagnostic upload 和内建 updater 都有配置/help/schema/zip 零表面证据；single-root/rebind/marker/sort/reload/model-select/self-test 在全部声明 Windows/Linux 版本通过功能、安全、取消、恢复和资源门，其中 XP/CentOS 不可由现代机替代；每个包都带 SHA-256、组件/许可证 manifest、SBOM、构建摘要和对应完整测试摘要，且保持 RF-15 的 unsigned、RF-16 的无更新组件边界；README 与实测一致。
- **责任**：`J`。关联：D-039、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`REL-14`、`PLAT-13`、`EXT-01` 至 `EXT-03`、`AQ-246`、`AQ-370`、`AQ-373`、`AQ-382` 至 `AQ-390`、PJ-14 至 PJ-20、ED-13、ED-14、RF-03、RF-15、RF-16、`RF-01`--`RF-11`、`AR-P0-01`、`AR-P0-16`。

## 已识别跨系统缝隙的证明归口

下表只说明现行决定“由哪里证明”。负责人输入已经关闭；`J` 表示技术证明失败时只有最小反例确实会改变用户保证才重开 owner，`T` 可以直接细化 fixture。任何条目都不能在目标平台证据完成前标为 `proven-target`。

| 新增边界 | 主要证明入口 | 证明失败时回到哪里 |
| --- | --- | --- |
| Win32 CPU ISA | TP-001、TP-002、TP-030 | `REL-14` 与发布范围 |
| suspend/resume | TP-003、TP-005、TP-017 | `RUNTIME-06` 与 active-turn 降级 |
| internal ambient config isolation | TP-006、TP-029 | `PROC-13`；若平台无法禁用则回安全承诺 |
| plaintext HTTP endpoint | TP-006、TP-007、TP-028 | `NET-13` 的 endpoint/secret 组合 |
| per-Model retry expansion / deterministic backoff | TP-006、TP-022 | M05-58 A 的 `RetryCount`/`RetryBaseDelayMs` + manifest max/jitter；证明失败不得偷换配置面 |
| short config-secret threshold / deterministic exact scanner | TP-006、TP-010 | M05-59 A 的门槛下 consumer ineligible 保证；证明失败不得自动放宽短 secret 使用 |
| canonical scalar / XML 1.0-safe lossless carrier | TP-010、TP-015、TP-021 | TS-23 的 canonical admission 契约与所选 schema；不得以 replacement/normalization 兜底 |
| Protocol × tool carrier feasibility | TP-015 | 已选 `openai-chat`/`anthropic-messages` × TS-23 A typed carrier；任一协议不能承载完整 registry 就不得发布该 adapter |
| reserved-tree exact read / alias race | TP-028、TP-029 | TS-40 B：仅当前 ContextHandle 已提交 canonical XML 的 exact-read；不能按 basename、显示路径或其他 reserved object 放行 |
| Model/Permission Unicode logical-name codec | TP-019 | M05-57、`CFG-27`、`AQ-432`；D-029 下只回技术 grammar，不新增 ASCII-only 产品票 |
| stuck detector / threshold snapshot recovery | TP-017、TP-022 | AL06-50 A：manifest tuple、零用户阈值字段；算法失败不得清零或改选 threshold source |
| special-purpose endpoint disclosure consent | TP-020、TP-028 | AL06-51 C：durable per-Context/purpose/binding consent；foreign/rebind state 只作 audit |
| per-Model scheduler/cooldown | TP-022 | `MODEL-15`、`AQ-362` 的等待与并发体验 |
| ask-user reply/manual retry | TP-016、TP-017、TP-018 | `LOOP-28`、`LOOP-29` |
| raw exec stdin/command transport | TP-005 | `PROC-11`、`PROC-12` |
| Context secret purge/redaction | TP-008、TP-019、TP-028 | `CTX-28`、`AQ-368` 的删除承诺 |
| ManagementMutation | TP-018、TP-019、TP-024 | `ARCH-05`、`AQ-369` 的共同事务体验 |
| data-root/workspace filesystem support | TP-011、TP-014、TP-030 | `PLAT-13`、`AQ-370` 的支持矩阵 |
| extension runtime closure | TP-029、TP-030 | `EXT-01` 至 `EXT-03`、`AQ-373` |
| per-turn config generation | TP-019、TP-020、TP-030 | D-048 / F4-01 的完整 bytes/digest、原子 generation、active-turn freeze 与 invalid-next-turn gate |
| modal local/global command grammar | TP-024 | `CLI-16`、`AQ-375` 的 focus namespace 选择 |
| stdin/stdout/stderr topology | TP-023、TP-024 | `CLI-17`、`AQ-376` 的 prompt/output 选择 |
| help topic architecture | TP-024 | `CLI-18`、`AQ-377` 的 topic grammar |
| Description XML projection | TP-020、TP-028 | `CFG-25`、`AQ-378` 的历史可解释性与数据分类 |
| manual compaction lifecycle | TP-017、TP-025 | `COMP-11`、`AQ-379` 的 admission/identity/publication |
| imported Context compatibility gap | TP-020、TP-028 | `CTX-29`、`AQ-380` 的 continuation gate |
| same-process Context topology | TP-003、TP-022 | `RUNTIME-07`、`AQ-381` 的事件归属、资源与关闭 |
| Web scope / zero surface | TP-003、TP-007、TP-022、TP-024、TP-028 至 TP-030 | D-044 / PJ-14 的已确认零 listener/page/asset/API |
| image input / screenshot capture | TP-002、TP-010、TP-015、TP-021、TP-023、TP-024、TP-028 至 TP-030 | D-044 / PJ-15 的已确认零 attachment/capture/clipboard-media |
| audio input / microphone capture | TP-002、TP-003、TP-005、TP-010、TP-015、TP-021 至 TP-024、TP-028 至 TP-030 | D-044 / PJ-16 的已确认零 audio/device/codec |
| remote/headless control | TP-003、TP-007、TP-022、TP-024、TP-028 至 TP-030 | D-044 / PJ-17 的已确认零 IPC/RPC/listener/controller |
| single Context root / mirror rebind / rename marker | TP-003、TP-008、TP-010 至 TP-014、TP-016 至 TP-020、TP-022、TP-024、TP-028、TP-030 | D-045/D-046：镜像父目录唯一 root、zero-multi-root、rebind、`AutoRenameDisabled` 与 raw exec 宽可达边界 |
| standalone transcription | TP-002、TP-003、TP-005、TP-010、TP-015、TP-021 至 TP-024、TP-028 至 TP-030 | D-044 / PJ-19 的 not-applicable 同等零 action/purpose/artifact |
| speech output / TTS | TP-002、TP-003、TP-005、TP-010、TP-015、TP-021 至 TP-024、TP-028 至 TP-030 | D-044 / PJ-20 的已确认零 speech purpose/device/output |
| aggregate telemetry | TP-006、TP-007、TP-019、TP-022、TP-024、TP-026、TP-028 至 TP-030 | ED-13：零 telemetry endpoint/request/spool/receipt/opt-in |
| diagnostic upload | TP-006、TP-007、TP-019、TP-022、TP-024、TP-026、TP-028 至 TP-030 | ED-14 not-applicable：零 upload command/preview/consent/endpoint/receipt |
| update discovery/download | TP-006、TP-007、TP-011、TP-019、TP-021、TP-022、TP-024、TP-026、TP-028 至 TP-030 | RF-16：零 updater/check/download；RF-15 unsigned，发布身份只依赖 SHA-256/manifest/SBOM 证据 |

## 证明之间的依赖顺序

```text
TP-001/TP-002/TP-029
        -> TP-003/TP-004/TP-005/TP-006/TP-007/TP-011/TP-012
        -> TP-008/TP-010/TP-013/TP-014/TP-015/TP-021
        -> TP-016/TP-017/TP-018/TP-019/TP-020/TP-025
        -> TP-022/TP-023/TP-024/TP-026/TP-027/TP-028
        -> TP-009 and final budgets
        -> TP-030 final zip evidence
```

这不是编码顺序。它表示证据依赖：例如没有目标打包链，就无法把现代机上的 XML 或 event-port smoke 当作最终 ABI 证明；没有 durable operation 协议，也不能用 Agent 场景测试证明副作用恢复。

## 失败时怎样返回决策流

技术证明失败不自动降低目标，也不自动选择更复杂方案：

1. 记录失败的目标、环境、fixture、观察值和最小反例。
2. 先尝试不改变产品承诺的窄技术替代；新依赖必须重新做供应链和平台审计。
3. 若所有窄替代都失败，写出会改变的用户承诺、数据格式、安全边界、性能或兼容性。
4. 只把这部分真实取舍重新交给项目负责人，形成新的明确决定。
5. 原证明标记 `failed` 或 `superseded`；禁止删除失败证据后假装从未选择过。

## 进入实施计划时的用法

- 负责人输入门已关闭；现在为每条 TP 冻结具体 fixture、命令、目标机和证据保存位置。
- 一个子系统的 implementation plan 只能依赖已经 `proven-target` 的底层能力，或把对应最小证明作为该计划第一阶段且设置 stop gate。
- `proven-modern` 只能用于筛选候选，不能解除 XP/CentOS 发布门。
- 最终发布必须把 TP 结果接入 requirement → decision → spec → test → evidence 追踪，而不是单独留在实验笔记里。
