# 技术证明债务表

更新日期：2026-07-22

状态：设计阶段证明计划；全部条目均未因写入本文而视为已经通过

## 为什么需要这张表

设计题库负责问清产品取舍，但有些问题不能让项目负责人凭偏好选择。例如，Windows XP 能否可靠取消一个正在读管道的进程、单 XML 在长会话中的写放大是否可接受、LuaExpat 能否以 Lua 5.5 ABI 在两个目标平台稳定工作，答案必须来自最小原型、故障注入和目标机证据。

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

下文对尚待决的 optional scope 仍用“选 A/选 B/C”简写：`A` 表示排除并要求 zero-surface，`B/C` 表示选入后需补齐正向证据。D-044 已把 PJ-14、PJ-15、PJ-16、PJ-17、PJ-19 和 PJ-20 锁定为 terminal-only 下的排除项，它们不再属于条件路线：历史问卷 ID 仍作来源引用，当前技术责任只是证明零 parser、零 worker、零 endpoint、零依赖、零配置、零 CLI/help 和零 XML surface，不得因旧 B/C 候选文本重开。PJ-19 由 PJ-16 排除而 `not-applicable` 也要产生同等负向证据；ED-14 因 ED-07 C 而 `not-applicable` 时同理。

## P0：进入完整实施计划前必须有路线

### TP-001 luainstaller 的 Win32 x86/XP 与 CPU ISA 目标

- **当前状态**：`unplanned`；现有 `../luainstaller` 1.0 明确拒绝 Windows x86。
- **要证明**：相邻打包器可以产生使用 Lua 5.5、Win32 x86、XP SP3 可启动的 yaca launcher，并能纳入项目所需 Lua/C 模块和资源；待负责人确认 `REL-14` 后，整个产物还必须服从同一最低 CPU ISA，而不是只有 launcher 服从。
- **最小证据**：独立授权后的 luainstaller target/profile 设计；固定工具链与 ISA flags；最小 hello/package；PE machine、subsystem、imports、CRT 与指令审计；在满足最终选定 ISA 下限的真实旧 CPU/虚拟化约束环境及 XP SP3 到 Windows 11 上记录同一产物启动结果。
- **通过条件**：不是修改 PE 标志伪装；最终包不引用最低 Vista+ API；Lua、C 模块和每个随包 executable/DLL 都没有暗中使用高于最终确认基线的指令；不依赖目标机预装 Lua/CRT；错误架构或 ISA 被构建门拒绝。
- **失败后**：`O`。需要在“扩展 luainstaller、更换 Windows 打包链、改变 XP/x86/Lua 5.5 硬目标”之间重新选择，不能由 yaca 实现者暗改。
- **关联**：`REL-14`、`AQ-206`、`AQ-211`、`RF-04`、`AR-P0-16`。

### TP-002 Lua 5.5 与 native 模块 ABI

- **当前状态**：`proven-modern`；现代 Linux 源码 smoke 不能代表两个目标。
- **要证明**：所有拟随包 C 模块严格按目标 Lua 5.5 headers/ABI 分平台重新构建，不混入 Lua 5.4、LuaJIT 或错误位数产物；D-044 排除的 Web/image/audio/remote/transcription/TTS 不得带入 listener、codec、capture、IPC、device 或 speech helper，“默认关闭”不等于 zero-surface。
- **最小证据**：每项模块的源码 hash、patch、编译器/ABI/ISA flags、导出/导入表、反汇编或等价指令扫描、加载及错误卸载测试；Windows x86 和 CentOS 7 x86_64 各一份；由最终 scope 生成 component manifest 和被排除能力的 negative manifest。
- **通过条件**：加载、调用、GC、错误抛出、重复创建/销毁和长期 soak 无 ABI 崩溃；Windows native 模块服从最终确认的 `REL-14`，构建可复现；模块搜索不从 CWD/PATH 注入替代品；最终 component/import manifest 与 zip 中不存在 D-044 六类能力的 native 模块、helper 或间接可调用依赖。
- **失败后**：`T` 优先换窄绑定或改为 helper；若所有候选都要求改变 Lua 5.5/平台保证，再转 `O`。
- **关联**：`PROD-17` 至 `PROD-21`、`REL-14`、`AQ-187`、`AQ-250`、`AQ-382` 至 `AQ-385`、`AQ-388`、`AQ-389`、PJ-14 至 PJ-17、PJ-19、PJ-20、`TS-09`、`AR-P0-14`、`AR-P0-16`。

### TP-003 Windows XP/CentOS 统一事件泵

- **当前状态**：`unplanned`。
- **要证明**：Lua 领域核心保持单线程状态所有者时，console input、curl stdout/stderr、工具进程、timer、cancel、XML commit completion 以及 D-041 周期 `context-name` 完成/取消可以进入同一有界事件泵，且没有任何一个阻塞源冻结全部应用；系统 suspend/resume 或显著时钟间隙也能成为显式事件并触发最终规格要求的重新验证。命名 admission 同时要求 `AutoNameEveryMainTurns>0`、durable main-turn waterline 到期且 Context XML 的 `AutoRenameDisabled!=true`；取消标记只建立新基线，不追补请求。PJ-18 已选单 root：每个 active Context 的唯一 root 由其 XML 在 `__yaca__/CONTEXT` 镜像树中的父目录经 `LogicalPathCodec` 解码，不建立 root list/alias/selector 或第二 root 资源域。D-044 意味着泵中不存在 Web/remote client、media device、capture/transcription/speech 流或它们的保留队列。
- **最小证据**：只包含 `start/poll/cancel/join/close` 的最小 port；同时运行慢 SSE、慢命令输出、用户输入、周期持久化和低优先级 `context-name`；覆盖 marker missing/false/true、运行中设置/取消、到期水位、禁用期间跨过多个间隔与新基线，证明 true 时零排队/零费用，取消后不立即或追赶命名，新 main 消息或退出能取消已在途请求且不等待它收口；按最终 `RUNTIME-07` 选择覆盖单/多 active Context，但每个 Context 只有一个由镜像父目录解码的 root，并扫描零附加-root 队列/账本；对 D-044 做零 listener/device/client/codec worker/queue 的 registry 与运行 trace 扫描；分别在 sampling、tool-running、approval、commit 和 idle 中 suspend/resume；记录事件顺序、墙钟/单调钟差、队列峰值、CPU、句柄与恢复后的 lease/workspace/root 状态。
- **通过条件**：忙时输入和 Esc 在已确认延迟预算内可观察；慢消费者产生明确 backpressure；取消后必须得到真实 completed/cancelled/failed/unknown 之一；`context-name` 永不取得工具、不抢占 main/side/review 的已就绪请求、marker=true 时不进入 scheduler，取消 marker 后只从新基线计数且不在退出或恢复时幽灵继续；close barrier 后无遗留请求/helper，且从未创建 D-044 排除的 listener/device/client 状态；恢复后不自动重放不能证明连续性的模型请求或副作用，旧 approval/action snapshot 按最终规格重新验证；无共享 Lua table 的后台写入。
- **失败后**：`J`。技术侧先比较原生等待层、极小 I/O 线程和 helper；若只能取消流式或取消忙时输入能力，交负责人确认降级。
- **关联**：`RUNTIME-06`、`RUNTIME-07`、`PROD-05`、`PROD-18` 至 `PROD-21`、`AQ-261`--`AQ-265`、`AQ-315`、`AQ-381`、`AQ-382`、`AQ-384` 至 `AQ-386`、`AQ-388`、`AQ-389`、PJ-14、PJ-16 至 PJ-20、`AL06-01`、`F4-15`、`TS-09`、`AR-P0-04`、`AR-P0-05`。

### TP-004 Windows XP console 与 QuickEdit

- **当前状态**：`unplanned`。
- **要证明**：XP 传统 console 下能够识别普通 Enter、Ctrl+Enter、Shift+Enter、Alt+Enter、Esc；能力不足时能够可靠声明并使用点命令后备；QuickEdit、窗口关闭、Ctrl+C/Ctrl+Break 不会让程序永久挂死或破坏终端状态。
- **最小证据**：真实 XP console 与重定向/管道矩阵；逐键事件 trace；raw→cooked→恢复；选择文本造成阻塞时的诊断；异常退出后的模式/代码页/光标复核。
- **通过条件**：帮助只宣传实际可用动作；无法区分的组合键不误映射为另一动作；draft 不因异步输出静默丢失；终端恢复有 best-effort 证据。
- **失败后**：`O` 只决定是否接受某组合键在 XP 必须使用文本后备；技术侧不能假装快捷键工作。
- **关联**：`AQ-009`、`AQ-264`、`AQ-265`、`TU-03`--`TU-05`、`AR-P0-05`。

### TP-005 子进程树、取消与 unknown

- **当前状态**：`unplanned`。
- **要证明**：Windows `cmd.exe` 和 Linux `/bin/sh` 启动的前台命令，其 stdin、stdout/stderr、退出、超时、取消和子孙进程可以按最终确认契约收口；无法证明终止时准确返回 unknown；过长或无法无损编码的 raw command 不会被 Runtime 静默改写成另一动作；各平台 termination grace 和内建 `auto` decoder 可以作为发行契约冻结而不暴露用户字段。D-044 排除的录音、转写、codec 和播放 helper 不是 process port 的条件分支，而是必须证明不存在的路由。
- **最小证据**：直接子进程、孙进程、继承句柄、主动读取 stdin/等待交互、忽略信号、快速退出与 cancel 竞态、创建到纳入 Job 的竞态、fork 后脱离进程组、不同 grace 值的收敛/延迟矩阵、平台命令长度边界、代码页/UTF-8/无效序列/二进制输出和不可表示字符等夹具；同时扫描 process/helper registry、发行 manifest 和实际子进程 trace，确认无媒体设备、codec、转写或播放进程入口。
- **通过条件**：模型可见 `exec` 不会偷取 TUI/审批输入；若最终选择 stdin=EOF，所有读取立即得到 EOF；命令长度/编码超限得到稳定 typed error，除非负责人另行确认并完整规定受保护脚本路线；每个平台 manifest 固定有界 grace，result 记录实际 decoder/替换/失败/原始字节；不因发送 kill 就声称已停止；不复用仍可能回调的 operation/buffer；媒体/转写/TTS helper、process route 和孤立 reader 计数为零；unknown 可由恢复页解释。
- **失败后**：`J`。先收窄为“非交互、前台、有界”命令；若仍不能提供可取消性，再决定是否降低 shell 承诺。
- **关联**：`PROC-11`、`PROC-12`、`PROD-18`、`PROD-20`、`PROD-21`、`AQ-119`--`AQ-128`、`AQ-367`、`AQ-371`、`AQ-384`、`AQ-388`、`AQ-389`、PJ-16、PJ-19、PJ-20、`TS-03`、`TS-09`、`AR-P1-03`。

### TP-006 curl 流式、取消、ambient config 与秘密传递

- **当前状态**：`unplanned`。
- **要证明**：随包 curl 在 XP/CentOS 上支持目标 TLS/代理/SSE，能够被事件泵取消，并让明文 INI Key 不进入 argv、普通环境、日志和可恢复残留；yaca 的基础设施请求不受用户/工作区 curl 配置、home/proxy/CA 等未列 ambient input 偷偷改写。M05-58 所选配置面必须在每个 logical request admission 时展开为不可变 retry snapshot：A 是 count/base 加 manifest 的 exponent/max/deterministic-jitter，B 是 count/base/max 加 manifest jitter，C 是 preset 名加当前 manifest 的完整 count/base/max/exponent/jitter 展开；默认、单位、范围、饱和退避公式、jitter 输入/算法与 Runtime maximum 均由真实 endpoint 和旧机 fixture 冻结。M05-59 所需 exact-byte scanner 必须能在流式 request/response、process output 和其他 canonical ingress/egress 上以有界尾窗运行：A 路线冻结一个跨目标平台一致、版本化且用户不可调低的 `MinimumScannableSecretBytes` 并在每次 consumer admission 阻断过短值；B 路线只证明过短值能进入精确私有 carrier，同时普通正文明确不获得该值的全局扫描保证；C 路线则证明任意非空长度都参与 exact scan，并如实承受高频误阻断/marker。ED-13 aggregate telemetry、ED-14 diagnostic upload 和 RF-16 update query/download 若选入，必须成为与 Model/tool 及彼此正交的显式 purpose，遵守 D-039 且不复用 Key、consent 或 retry authority。这里测出的 retry 常量、门槛、scanner 或 carrier 只是兑现负责人最终选择的技术证据，不选择 M05-58/M05-59 A/B/C，也不生成新的配置偏好。
- **最小证据**：比较“secret config 走 stdin/body 走私有 temp”和“body 走 stdin/secret config 走私有 temp”；在用户目录、工作区与环境放入会改 header、proxy、CA、redirect 或输出的恶意/冲突配置；使用 canary key/正文/路径检查进程列表、环境、temp、stderr、XML、支持输出和崩溃残留。为 M05-58 同时使用真实兼容 endpoint 与可编程故障 endpoint，在 XP x86 和 CentOS 上覆盖 count=`0|1|max|max+1`、base/max 边界、B 的 max<base、C 的每个 preset 与 manifest 升级、DNS/connect/TLS、body 未发送、body outcome unknown、429/503、`Retry-After` delta/date/畸形/过长、首个 canonical event、partial SSE、协议/auth/普通 4xx/内容拒绝、cancel、suspend/resume、wall-clock 跳变和 timer 粒度；用固定 logical-request identity/attempt/manifest 生成跨平台 jitter golden vector，记录计划/实际等待、attempt、deadline/turn 剩余量、CPU 与句柄。为 scanner 预先冻结正常正文碰撞、吞吐、峰值内存和取消延迟预算，再覆盖门槛前后长度、每一种 chunk split、零长度/空值 schema 拒绝、同值来自多个 secret class/source、前缀/后缀/嵌套 pattern、相邻/相交/重复 occurrence、超长 pattern、慢消费者与输出上限；随机排列 registry、matcher 返回顺序、chunk 大小和 matcher backend，比较 raw-byte hit 与 maximal interval union。分别验证 A 的短值 consumer ineligible 且错误不泄露值/实际长度，B 的短值只到私有 carrier 而普通正文可原样保留，C 的短值命中会按目的地稳定拒绝或 marker。对 ED-13、ED-14、RF-16 分别覆盖选 A 的零 request-purpose trace，以及 B/C 最终允许的正向触发、preview/consent、取消、失败、重试、receipt 和无启动/定时请求；再评估是否需要 libcurl bridge。
- **通过条件**：请求体与 Key 传递无歧义；实际请求 manifest 只由 schema、受控平台信息和显式用户选择决定，不读取未列宿主配置；所有 temp no-replace、最小权限、有界、启动可回收；redirect 不向不同 origin 转发 Key；`NET-13` 最终确认禁止的 HTTP/secret 组合在发出任何正文前失败关闭。M05-58 的 `RetryCount` 机械表示首次 attempt 之后允许的自动 retry 数；A/B 数字或 C preset 对同一 manifest 展开为同一公开、可快照的有效 tuple，整数运算饱和且 deterministic jitter golden vector 在两平台一致。local backoff、合法 `Retry-After`、logical-request deadline、turn 剩余预算与 Runtime hard cap 始终取更严格结果；等待超出剩余门即返回 typed deadline/budget outcome，不后台排队。body outcome unknown、收到任何 canonical event、畸形协议、auth/普通 4xx、内容拒绝或 cancel 都不 retry，active request 不热换配置，retry 不切换 Model。M05-59 A 使用同一发行级门槛和算法，ConfigGeneration 激活与每次 consumer admission 都执行资格门且升级后不静默退到 B；B 仍禁止 Runtime secret 进入 argv/XML 字段/temp/诊断/reviewer/support，但不谎称过短同值普通正文被扫描；C 对全部已注册非空 raw bytes 执行相同规则。完全相同 pattern 只保留一份并携带稳定排序的 class/source 集，scanner 检查全部 pattern、在 schema secret hard cap 内跨 chunk 保留至多 `max_pattern_bytes-1` 的有界必要尾窗，所有相交 hit 合并为 maximal byte-interval union；拒绝结果、marker 边界与类别只由 union 决定，不随登记/遍历/平台变化，marker 不保存原值、原长度或 equality fingerprint。ED-13/ED-14/RF-16 各自选 A 时最终 Runtime 没有对应 endpoint/purpose，选 B/C 时 one-shot/persistent consent、diagnostic preview 和 update source identity 不能互相替代；取消与断流给出确定 attempt 结果。
- **失败后**：`J`。技术侧可更换不改变已选保证的 timer、受控 carrier、matcher 或窄 bridge；若最终 M05-58/M05-59 路线在目标平台不能通过，则把最小反例交回对应 owner/CFG-28/CFG-29，不能由技术实现自动切换 A/B/C。若只能把 Key 暴露在已确认禁止的位置，需负责人重新确认明文 Key/外部 curl/平台目标的组合。
- **关联**：D-036、D-039、`PROC-13`、`NET-06`、`NET-13`、`MODEL-15`、`LOOP-14`、`LOOP-27`、`DIAG-08`、`DIAG-14`、`REL-11`、`AQ-140`、`AQ-197`、`AQ-220`、`AQ-221`、`AQ-246`、`AQ-277`、`AQ-278`、`AQ-387`、`AQ-390`、`AQ-433`、`AQ-437`、ED-13、ED-14、RF-16、`CFG-28`、`CFG-29`、M05-58、M05-59、HCFG-02、HCFG-05、F4-02、`SAFE-09`、`AR-P0-14`、`AR-P1-02`。

### TP-007 TLS、CA 与明文 HTTP 旧平台基线

- **当前状态**：`unplanned`。
- **要证明**：最终 curl/CA 组合在 XP 和 CentOS 7 上能连接已支持协议端点，不依赖过旧系统 TLS；自定义/系统/随包 CA 的选择、证书错误和代理 CONNECT 可解释；`NET-13` 最终确认的 loopback/LAN/public HTTP 与 `AuthMode` 组合可以在发请求前确定执行、确认或拒绝。D-044 下 Web/remote 不产生 listener、bind/origin/peer 或独立 CA policy；ED-13/ED-14 的发送 endpoint 和 RF-16 的 manifest/download endpoint 仍只在对应未决路线选入后存在，RF-16 B/C 只接受与 RF-15 强制来源身份相容的 update manifest/artifact。
- **最小证据**：有效链、过期、错误主机名、私有 CA、代理认证、SNI、TLS 版本/密码套件、系统时间错误、离线，以及 HTTP loopback/LAN/public、redirect、空/非空 Key 和 secret header 的组合矩阵；对 Web/remote 执行零 bind/listener/endpoint/auth-policy 扫描，telemetry/diagnostic upload 增加错误 endpoint/consent，update 增加未签名/错签名、错 OS/架构、manifest/artifact 替换和截断下载。
- **通过条件**：不存在隐式 insecure fallback；禁止的明文传输不会只警告后继续，允许或需确认的组合产生与最终产品决定一致的稳定结果；PJ-14/PJ-17 的 listener/endpoint/CA-policy 计数为零，ED-13、ED-14、RF-16 则按各自最终 A/B/C 路线证明零端点或精确网络结果；RF-16 不把 TLS 或同源 hash 当发布者身份，也不执行 RF-03 安装；CA 来源/版本进入发布 manifest 与 self-test。
- **失败后**：`T` 更新随包 curl/CA；若端点要求目标平台无法承载的 TLS 组合，交 `O` 决定支持边界。
- **关联**：D-039、`NET-13`、`PROD-19`、`DIAG-14`、`REL-11`、`AQ-137`、`AQ-145`、`AQ-146`、`AQ-246`、`AQ-382`、`AQ-385`、`AQ-387`、`AQ-390`、PJ-14、PJ-17、ED-13、ED-14、RF-15、RF-16、`M05-01`、`M05-04`、`AR-P1-02`。

### TP-008 单 XML 完整重写的正确性

- **当前状态**：`unplanned`。
- **要证明**：流式复制旧 XML、插入 canonical event/footer、完整验证、flush 与发布的协议，在每个崩溃点最多留下一个可识别的 current/previous-valid 状态，不产生半个正式 XML；手工 rename 的 canonical `Name`、`UpdatedAt` 与 `AutoRenameDisabled=true` 必须作为一个可恢复管理事务发布；workspace rebind 的历史事件、`UpdatedAt` 与目标镜像路径也必须作为一个可恢复管理事务收口。`CreatedAt` 始终不变，自动 rename 不置标记，显式增删标记也不能产生名称/metadata 半状态。
- **最小证据**：对 open/read/copy/write/flush/close/verify/replace/directory flush 的每个边界故障注入；磁盘满、权限变化、杀进程、杀机器、杀毒软件占用和跨卷错误；再在手工/自动 rename、workspace rebind、marker add/remove、basename/path move、rebind event 与 XML metadata publication 每个切点杀进程，并覆盖 inspect/验证失败不得推进时间。
- **通过条件**：恢复算法只依据可验证证据；正式路径始终是完整 well-formed XML；手工 rename 成功后 `Name`、`UpdatedAt`、marker 与新路径必然同时为新值，失败后必然同时保持旧值；自动 rename 同样要求 `Name`、`UpdatedAt` 与新路径全成或全不成，同时绝不创建禁用 marker；rebind 成功后事件、`UpdatedAt` 与目标路径全部生效，失败后全部不生效；`CreatedAt` 永不改变，任何 inspect/失败 mutation 不推进 `UpdatedAt`；marker 取消只建立新调度基线；副作用前 durable operation 屏障和副作用后 result 屏障可区分；不自动重放 unknown。若负责人最终选择整 Context purge 或 redaction rewrite，发布协议必须同时枚举并处理 yaca 知道的 current/temp/previous-valid/backup generation，且只宣称证据实际支持的 best-effort 删除，不把 unlink 写成物理 secure erase。
- **失败后**：`J`。技术侧先修正 replace/backup 协议；若单文件基线无法达到已确认 durability，负责人需决定是否允许短期 WAL/recovery sidecar 或改变承诺。
- **关联**：`CTX-28`、`AQ-303`--`AQ-305`、`AQ-368`、`CX-01`、`CX-04`、`CX-05`、`AR-P0-08`、`AR-P0-10`。

### TP-009 单 XML 写放大、x86 内存与硬门

- **当前状态**：`unplanned`。
- **要证明**：正确性基线在 Win32 x86、旧磁盘和长会话上不会因 O(n) 单次重写、累计 O(n²) I/O、parser buffer 或 Lua 大字符串失控。
- **最小证据**：小/中/压力 XML，短消息、大工具结果、反复压缩/Model 切换、慢磁盘、磁盘接近满；记录 p50/p95/最大提交延迟、峰值 private bytes、写入字节和恢复时间。
- **通过条件**：不同时构造完整旧 XML + DOM + 新 XML；超过 provisional 门前提前告警；达到 hard gate 后 fail-stop 并保留可接盘文件；结果可在目标参考机复现。
- **失败后**：`O`。由负责人在允许 WAL、降低 durable 频率/保证、限制 Context 大小之间选择；不能暗中换长期事实源。
- **关联**：`AQ-228`、`AQ-303`--`AQ-305`、`CX-11`、`RF-09`、`RF-10`。

### TP-010 XML parser/writer 与 Lua 5.5

- **当前状态**：`proven-modern`；LuaExpat 1.5.2 + Expat 2.8.2 只做过现代 Linux smoke。
- **要证明**：目标构建可分块解析/验证项目 XML 安全子集，writer 能确定性转义，DTD/entity/外部读取被硬拒绝，资源上限在 C 与 Lua 两侧都生效。TS-23 的 canonical scalar 必须先成为“有效 Unicode scalar sequence 的精确 UTF-8 bytes + missing/present-empty 身份”，再由 `representation=text|base64` 进入 XML 1.0-safe carrier：只有实际 writer/parser 能证明 entity 与 line-end 处理后逐 byte 相等时才用 text，否则用 base64；畸形 UTF-8、孤立 surrogate、text NUL 或 schema-invalid null 在 accepted call 前稳定拒绝，任意 raw bytes 只走明确 typed binary/base64 字段。M05-59 scanner 必须在 secret gate 先于公开 digest、approval、operation 和 XML persistence 的边界，以与 TP-006 相同的门槛、跨 chunk 和 maximal-union 语义工作。D-044 要求 schema 中根本不存在 media bytes、transcript/speech provenance 或 remote controller/peer audit 的 parser/element/namespace；D-045 要求 current-root/workdir/root-list/alias/selector 权威元素数为零，D-046 只加入 typed `AutoRenameDisabled` metadata；ED-13/ED-14/RF-16 的 consent/receipt 仅在各自未决路线选入时通过版本化、有界 schema 表达。本项只验证已选协议/secret 路线可被最终 XML 库无损承载，不替负责人选择 TS-23 或 M05-59 路线。
- **最小证据**：目标平台构建、合法 fixtures、畸形 UTF-8、重复/未知字段、深度/属性/文本/实体炸弹、分块边界、writer→parser round-trip 与 fuzz corpus。对 scalar/carrier 做逐 byte oracle：枚举 `0x00..0xFF` 经 typed binary/base64 的 round-trip；逐个枚举 U+0000..U+10FFFF（surrogate 区间除外）的单 scalar UTF-8，并以代表性多 scalar 序列覆盖 ASCII、非 BMP、组合序列、非字符、XML 1.0 禁止但仍是合法 UTF-8 的控制字符、BOM、`&<>`、单双引号、反斜杠、`]]>`、HT/LF/CR/CRLF、前后/连续空格；另枚举 surrogate 区间编码、超出 U+10FFFF、overlong/truncated UTF-8、孤立 continuation、NUL 和 maximum boundary。每个 corpus 逐一验证 missing/empty、text/base64 分类、original byte length、公开 digest、任意 parser/writer chunk split 和重新载入后的 byte equality；不合法 text 必须证明“拒绝且不替换/规范化”，同一原始 bytes 只有在 schema 明确为 binary 时才可 base64 无损承载。为 M05-59 再把门槛前后、重复 source、相同/前缀/嵌套/交叠 secret 放在 canonical 输入的 entity/base64-serializer 输入边界与所有 chunk split，排列 registry/匹配顺序并比较拒绝或 marker 后 XML 的 maximal-union golden bytes。D-044 六类能力执行 zero-element/namespace/parser scan；D-045 执行 zero-current-root/workdir/list/alias/selector scan；D-046 覆盖 marker missing/false/true、未知 enum/type、手工 rename 与 marker 同事务、自动 rename 不置位、rebind/copy/import 保留 marker；ED-13、ED-14、RF-16 再按最终路线补零表面或 receipt/version fixtures。
- **通过条件**：无 DOM 全量加载；禁用 DTD 不是只靠未注册回调；非法 XML 不触发文件/网络访问。每个 accepted canonical field 都满足 `protocol wire -> canonical bytes -> XML carrier -> canonical bytes` 逐 byte 等同，missing/empty 不合并，writer/parser 不做 Unicode normalization、replacement、NUL 截断、换行改写或尾空格处理；所有 256 个 byte 值可由 typed binary carrier 无损往返，所有允许的 scalar 要么经 text 往返相同、要么确定选择 base64，非法 text 只返回稳定 `carrier-not-lossless|invalid-scalar` 而不“修好后”接受。secret gate 在选择 representation/计算公开 digest 前运行；A 的过短值无法激活 consumer，B 对过短普通正文不虚构扫描，C 对任意已注册非空值执行 exact scan；重复/相交 hit 的 marker 与拒绝结果在 XML chunking、matcher 和平台间完全一致且不泄露原值、原长度或 equality fingerprint。D-044 的 media/remote namespace、element、parser、外部附件目录数为零；尚待决轴按其最终 A/B/C 路线给出零元素或 typed gap 证据；错误包含安全位置和类型但不回显秘密正文。
- **失败后**：`T` 比较更窄 binding/helper；若没有目标可行 parser，再返回 `O` 重新讨论 XML/平台组合；若 parser 可用但所选 TS-23 carrier 或 M05-59 保证无法兑现，则只把该组合标为冲突并回对应 owner，不能规范化数据或改选路线。
- **关联**：`PROD-05`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-186`--`AQ-188`、`AQ-246`、`AQ-383` 至 `AQ-390`、`AQ-437`、PJ-15 至 PJ-20、ED-13、ED-14、RF-16、`CFG-29`、M05-59、TS-23、HCFG-02、HCFG-05、`CX-06`、`AR-P0-10`、`AR-P1-01`。

### TP-011 文件系统支持矩阵、发布、锁与 durable 原语

- **当前状态**：`unplanned`。
- **要证明**：Windows XP 与 CentOS 7 分别能在最终公开支持矩阵中的每类数据根文件系统兑现 `publish_new_no_replace`、替换已有文件、move-no-replace、文件/目录 flush、writer lease 与 stale lock 证据；workspace 使用更弱文件系统时也只提供被探测能力支持的 direct write/rename 结果。矩阵尚待 `AQ-370` 决定，本文不预先把任何文件系统标为已支持。每个测试 Context 只探测从其 XML 镜像父目录解码出的唯一 root；context-repl rebind 必须以 no-replace 语义把 XML 移到目标镜像目录而不改 XML 内的 workdir 字段，并保留 `AutoRenameDisabled`；手工 basename rename 则与 marker=true 一起可恢复发布。RF-16 C 若允许下载，只能写入受控临时目标并在验证失败/取消后按明确协议清理，不能越权执行 RF-03 安装。
- **最小证据**：同名竞态、读者持有句柄、只读/ACL、候选 NTFS/FAT/SMB、Linux 本地文件系统、NFS/可移动盘、跨卷、断线、休眠、断电/崩溃和两个进程争抢夹具；数据根与每个 Context 的唯一 workspace root 分开记录结果；手工/自动 rename、marker add/remove 与 rebind 的所有 publication 切点；条件 update download 再覆盖 partial file、磁盘满、错卷、恶意文件名/archive、外部替换、取消和重启清理。
- **通过条件**：不得先删正式文件再放新文件；锁文件存在不自动等于活进程；无可靠 no-replace/flush/lease 时，相应数据根被拒绝或动作按已确认支持等级失败关闭；workspace 降级不被描述成 Context durability；rebind 只有在目标镜像目录可发布且旧/新位置的 move 结果可证明时才成功，不会留下两个 writer 候选；RF-16 选 A/B 时没有 download target，选 C 时未认证/不完整产物绝不成为可运行版本；每条原子性和掉电持久声明都绑定平台、文件系统与挂载前提。
- **失败后**：`J`。可改协议或降低支持文件系统；若影响“单 writer/完整 XML”承诺则由负责人确认。
- **关联**：`PLAT-13`、`PROD-05`、`REL-11`、`AQ-172`--`AQ-175`、`AQ-290`、`AQ-370`、`AQ-386`、`AQ-387`、PJ-18、RF-16、`CX-04`、`CX-05`、`AR-P0-11`、`AR-P0-16`。

### TP-012 Unicode 路径、LogicalPathCodec 与 hash

- **当前状态**：`unplanned`。
- **要证明**：中文/非 ASCII 路径、Windows 盘符/UNC/junction、Linux bytes 名称、大小写和规范化规则能在显示、文件操作、镜像树和固定 16 位 hash 中保持同一身份；唯一 current root 只由 Context XML 的镜像父目录经 `LogicalPathCodec` 解码，XML 本身不保存 current root/workdir，tool/Prompt/XML 不存在 root list、alias 或 selector；basename rename、workspace rebind、复制/导入时 `AutoRenameDisabled` 均按明确规则保留或迁移，不能因路径变化丢失用户命名意图。
- **最小证据**：路径 corpus；Windows wide API；组合/分解 Unicode；大小写碰撞；尾点/空格、保留名、长路径、UNC、根目录、Linux 非 UTF-8 bytes；跨机 fixture 与固定 hash 向量；覆盖镜像父目录解码、缺失/非法镜像路径、context-repl 把 XML 移到另一目标镜像目录的 rebind、手工 rename 设置 marker、自动 rename 不设置、marker true/false 在 rebind/copy/import 后保持、旧/新逻辑路径与 hash 向量，以及 root-list/alias/selector 零 schema 扫描。
- **通过条件**：显示替换不改变实际路径/hash；镜像父目录可唯一解码为 current root 或明确拒绝；Context rename/rebind 后逻辑 XML 路径与 hash 立即重算；碰撞/不可读范围不误选；tool/Prompt/XML/approval 只消费该唯一 root 且无 root selector，外部一次性访问不会暗中新增 root。
- **失败后**：`J`。技术侧可拒绝无法无歧义编码的路径；若要缩小已确认中文路径/平台保证，需负责人决定。
- **关联**：`PROD-05`、`AQ-177`、`AQ-189`、`AQ-223`、`AQ-386`、PJ-18、`CX-08`、`AR-P0-11`。

### TP-013 Context Resolver 的遍历复杂度与正确性

- **当前状态**：`unplanned`。
- **要证明**：已确认的增量搜索环、同环 name-before-hash、hash-like selector 单遍双判定和不重复处理候选，在大目录、链接环、不可读范围和并发变化下仍得到确定结果；Catalog view 的 `created|updated|name` + 双向排序只改变已发现结果的投影，不改变 Resolver 胜负或触发裸启动扫描。
- **最小证据**：多祖先/子树、近 hash/远 name、同环碰撞、权限错误、百万候选、reparse/symlink cycle、扫描期间 rename/delete；对每个集合跑三键×两方向、相同主键、复制/replace 改变 mtime/ctime、跨机导入与随机枚举顺序；另覆盖 `CreatedAt` 初建后不变、成功 durable mutation（含 rename/rebind）推进 `UpdatedAt`、失败/inspect 不推进。在目标旧机上分别记录 traversal、路径解码、候选 hash 派生、metadata 探测和排序的次数、首反馈、耗时、峰值内存、hard cap 与 stale generation。
- **通过条件**：候选最多有效探测一次；当前环未完整不能宣称唯一或不存在；每个平台发行 manifest 冻结不可放宽的 Runtime scan cap，超限返回 scan-incomplete；self-test 报告探测范围、数量、耗时和 partial，而不是把慢或不完整报告为 healthy；列表只使用 XML canonical CreatedAt/UpdatedAt/名称，主键相等时始终按 canonical `LogicalPath` 升序，绝不随 `ListSortDirection` 反转，也不读取 mtime/ctime；`CreatedAt` 在初次 durable 创建后永不改变，`UpdatedAt` 只在成功 durable mutation 中原子推进，失败或 inspect 不推进；改变排序不能改变同一 selector 的 Resolver 结果；浏览器、CLI、rename/delete 使用同一服务且不读取 `MaxScanEntries` 配置。
- **失败后**：`J/T`。技术侧先优化遍历、分页与 manifest cap；只有改变已确认裁决顺序或产品保证才回到负责人。
- **关联**：D-024、`CX-08`、`CX-09`、`AR-P0-11`。

### TP-014 direct file tools 的字节保真与冲突检测

- **当前状态**：`unplanned`。
- **要证明**：read/search/write/patch/rename/delete 在 CRLF/LF、BOM、无效 UTF-8、二进制、大文件、权限位、case-only rename、hardlink/symlink 与外部并发修改下不会静默改写用户数据；M05-16 A/B 只改变 workspace 外 direct path 的 coarse/split policy，不改变路径规范化或 raw shell 边界；M05-56 B 时 TS-21 classifier 在读取前稳定分类且只会提高限制，A 时整个 classifier surface 为零。PJ-18 下每个 direct call/approval 都只绑定 Context XML 镜像父目录解码出的唯一 root，tool/Prompt/XML 没有 root selector；raw exec 的 cwd 只是 provenance，不能被误写成 OS sandbox。
- **最小证据**：字节级 fixtures、expected digest 竞态、no-replace、原子替换失败、链接目标替换和特殊文件；比较操作前后内容与元数据；分别生成 M05-16 A 的单 outside modifier 与 B 的 read/write/delete 三 modifier 矩阵；M05-56 A 做 zero classifier/schema scan，B 覆盖 Runtime secret registry、高置信文件名、用户登记路径、误报、漏报、链接改向、分类版本变化和 approval stale。单 root 覆盖镜像父目录外改、rebind 后 stale approval、伪造 root-list/alias/selector 字段的拒绝；另用绝对路径、链接和子进程证明获批 raw exec 可能触及任意 OS 可访问路径，UI 不宣称 root-scoped shell。
- **通过条件**：文本工具只处理已声明文本；无法保真时拒绝或走诚实标为宽能力的 raw shell；每次 direct 副作用重新验证目标与当前镜像路径 generation；M05-16 两条路线都与基本能力取更严格结果且未选字段数为零，M05-56 A 时无 SensitiveRead parser/help/classifier，B 时命中采用 `Read` 与 `SensitiveRead` 更严格值、未命中绝不标记为安全；tool schema/Prompt/XML 的 root-list/alias/selector 数为零；rebind 后旧 approval 不得用于新 root；raw exec approval 明示当前 cwd 与 OS 外部可达风险；活动 workspace 失效时 fail-stop，不沿用 stale 路径或猜测重绑；结果说明内容、属性、文件系统能力和截断变化。
- **失败后**：`T` 收窄工具契约；任何扩大到自动编码转换的行为须 `O` 明确同意。
- **关联**：`PROD-05`、`PROD-16`、`PLAT-13`、`AQ-112`--`AQ-118`、`AQ-149`、`AQ-150`、`AQ-268`、`AQ-269`、`AQ-370`、`AQ-372`、`AQ-386`、`AQ-430`、PJ-18、M05-16、M05-56、`TS-02`、`TS-07`、TS-21、`AR-P0-06`、`AR-P0-11`。

### TP-015 canonical Model 协议与工具增量

- **当前状态**：`unplanned`。
- **要证明**：首版 wire profile 的 role、SSE、text/reasoning/tool delta、usage、finish/refusal/error 可以归一为稳定事件；断流或畸形响应绝不提前执行看似完整的 tool call。TS-23 所选 ToolInputRegistry 必须让 Model 请求中的 exact registry/schema identity、response admission、canonical accepted arguments、approval/XML snapshot 和 result pairing 一致，并逐项兑现下列 Protocol × carrier 可行矩阵：`openai-chat` 与 `anthropic-messages` 只把 TS-23 A typed object 视为候选可行，B bare exec/C all-tools free-text 均为静态 conflict；`openai-responses` 的 A 为候选可行，B 只有 native free-form `exec` item、call/result identity 与 lossless fixture 全部通过才可行，C 只有 TS-02 每个 core tool 都有 native free-form item、版本 parser 与完整 fixture 才可行；未来 adapter 只按发行 manifest 声明且实测的 exact carrier capability 获得资格。D-044 排除了 image/audio/transcription/speech content-part、capability 和 purpose，provider 的宽松 passthrough 也不得将其意外开启。矩阵是对负责人答案的技术资格门，不推荐或代选 M05-01/TS-23。
- **最小证据**：为 `openai-chat`、`anthropic-messages`、`openai-responses` 分别保存真实录制与合成 fixture，覆盖 object function/tool、Responses native free-form/custom item、任意分块边界、同响应 text+tools、重复/缺失 call ID、call/result 错配、JSON 断尾/重复 key/深度炸弹、free-form 空/超限/无效 encoding、length/refusal/filter、streaming force/try/off、逐工具 required/unknown/type/size/encoding 变异与 schema digest 不匹配。每个组合都发布 TS-02 完整 core registry，逐工具跑 TS-23 canonical scalar/XML carrier corpus并验证 request wire、accepted argument bytes、approval/XML snapshot、operation 与 result 配对；Responses+B 必须证明 `exec` 是协议原生 bare/free-form item而非把 text 塞入 object wrapper，Responses+C 必须对每个 core tool 重复同一证明。再做 manifest 能力伪报、只支持部分工具、Model 切换、重试/断流/取消和无 free-form endpoint 的负向测试；对四个媒体轴固定执行 zero-profile/content-part/capability/purpose/request scan，不保留 B/C 正向 fixture。
- **通过条件**：Model request 前发布 exact tool schema；只有完整 response、call ID/envelope/arguments 全量校验、canonical assistant/call 事件 durable 后工具才 accepted；畸形调用不建立 operation，raw command 不被分词/重写或推断细粒度 capability；每个本地 ID 唯一。资格判定机械等于矩阵：`M05-01 A/B + TS-23 B/C` 直接返回 answer-set conflict；`M05-01 C + TS-23 B/C` 只有对应 `openai-responses` free-form 证明通过才可发布，失败即 conflict，不能退回 object wrapper、自动改 TS-23 A、隐藏 `exec` 或缩小 registry。最终协议集合至少有一个 Protocol 能无损承载 TS-02 完整 core registry；只有部分 adapter/Model 匹配时，只给匹配者 main-tool 资格并按 M05-03/M05-26 解释其余用途。每个 accepted scalar 还必须通过 TP-010 的 wire→canonical→XML→canonical byte-exact gate；provider schema/capability/purpose/request registry 中 image/audio/transcription/speech 条目数为零，不支持的外来 payload 在采样前拒绝且不静默换 Model；重试不会把已见规范事件的响应整体重放。
- **失败后**：`T` 可修正同一 profile 的 adapter/parser；若真实 wire 不提供所选 carrier，结论是该 M05-01 × TS-23 answer-set conflict，必须回原 owner 改答案或正式协议范围，不能以技术 fallback 偷换产品选择。增加第二协议或宽松兼容仍须回 `O` 确认范围。
- **关联**：`PROD-17`、`PROD-18`、`PROD-20`、`PROD-21`、`AQ-034`、`AQ-383`、`AQ-384`、`AQ-388`、`AQ-389`、TS-02、TS-23、PJ-15、PJ-16、PJ-19、PJ-20、`M05-01`、`M05-03`、M05-26、TP-010、TP-021、`AL06-03`、`AR-P0-03`、`AR-P0-06`。

### TP-016 typed control 对支持 Model 的可用性

- **当前状态**：`unplanned`。
- **要证明**：`finish/ask-user/refuse` 载体、action-review/termination-review verdict、compaction schema，以及 D-041 周期 `context-name` 的有界 basename 输出，在声明支持的 Model 上达到可接受的结构化成功率，并能在无效输出时确定失败关闭。`context-name` 只有在 `AutoNameEveryMainTurns>0`、每 N 个已 durable 完成 main turn 的新基线到期且 `AutoRenameDisabled!=true` 时低优先级触发；它无工具权，新 main 或退出可取消，退出不等待，恢复不重放。
- **最小证据**：跨 Model 固定任务、提问、部分完成、拒绝、工具后完成、注入、复核拒绝/无效 schema 和压缩 fixtures；命名另覆盖 `N=0|1|10`、marker missing/false/true、设置/取消标记、取消后的新基线、未完成/取消 main turn 不计数、同时到达新 main、退出、请求失败、无效 basename、崩溃/恢复和工具调用注入；专门注入“命名 request 在途时手工 rename/添加 marker，随后 endpoint 返回迟到成功”竞态并记录 admission、cancel、usage/result、名称/hash、retry、token/费用、误终止和误继续。
- **通过条件**：Runtime 不解析自然语言猜状态；无效 control 不变成 completed；typed `ask-user` 与其后用户回复按最终确认的 turn/reply-to 规则形成唯一因果关系；reviewer 和 `context-name` 都不取得工具；周期计数只消费已提交的完成 main turn，marker=true 时零新 request/zero cost，取消标记不立即命名、不追补，marker 变 true/取消/退出/恢复后的迟到结果只留完整事实且绝不采用名称，不产生幽灵重命名；硬预算始终收口；差异不靠逐字输出判断。
- **失败后**：`J`。先调整 prompt/schema/兼容协议；若某 Model 无法可靠使用核心控制，则负责人决定标为不支持工具 Agent、降级文本模式或移出正式 Model 范围。
- **关联**：`LOOP-28`、`AQ-251`--`AQ-259`、`AQ-363`、`PP-05`、`AL06-02`、`RF-07`。

### TP-017 AgentLoop 全出口 typed outcome

- **当前状态**：`unplanned`。
- **要证明**：完成、waiting-user、cancelled、budget-exhausted、stuck、refused、partial、error、storage-failed 和 unknown-side-effect 等所有出口都通过同一状态机产生，任何 `break/error` 不会在外层误报 completed；suspend/resume、ask-user reply、用户手动 retry，以及最终选择支持的手动 compaction 生命周期也不绕过正式 turn/request/attempt/maintenance transition。AL06-50 还要求一个版本化 detector registry：至少登记 `exact-repeat`、`same-error`、`abab-cycle` 与 `semantic-no-progress` 的输入事实、signature/fingerprint 算法、counter 语义、canonical progress/reset 条件和 hard maximum；同一 registry 必须把 A 的 manifest threshold tuple、B 的 effective scalar 和 C 的完整 detector map 展开为 turn 创建时冻结的 threshold snapshot，并让 unfinished turn 跨重启恢复原 detector state。算法、registry 与具体数值属于技术证明，不替负责人选择 AL06-50 A/B/C，也不改变 AL06-28 命中后的产品行为。
- **最小证据**：逐 transition golden trace；在模型、tool、approval、storage、queue、steer、side、DoubleCheck、周期命名、自动/手动 compaction、suspend/resume、waiting-user reply 和每类 retry 入口注入取消、预算和错误；命名覆盖 marker=true 零 admission、取消 marker 新基线以及在途请求被新 main/退出取消。对 detector 建立表驱动 oracle：同 tool/version/canonical args 且相关 pre-state digest 不变的 exact repeat；同 canonical action 连续得到相同 typed error ID/category/stage 的 same-error，改变自由错误文字不改变判断；`A-B-A-B` action/result signature cycle 与近似但不成环的反例；多次 model-only 回复、termination-review 同一缺口、compaction 无收益和文字变化但 progress fingerprint 不变的 semantic no-progress。逐项注入真正 canonical progress——目标/文件或结构化状态 digest 改变、新验证证据、不同工具结果、未完成项变化或新用户决定——以及不得 reset 的换措辞、换 Model、retry、review、无收益 compaction、queue/steer 重排；在 counter 增量、progress reset、warning commit、escape step 和 terminal outcome 每个 durable 边界杀进程并恢复。分别跑 A 的 manifest identity+tuple、B 的 scalar/source+detector version、C 的 registry version+完整 map，覆盖缺失、0/off/infinite、越界、未知 detector、active-turn 配置变化、外来/旧 snapshot 与算法升级；若 `.compact` 进入 v0.1，再覆盖 busy admission、独立 maintenance turn 或排队意图的最终选择及恢复。
- **通过条件**：每个 accepted tool call 配对真实/synthetic result；terminal review 只由 typed finish 触发；ask-user reply 的 turn/快照/预算按最终决定唯一冻结；UI 不存在无对象的泛化 retry，安全 attempt、新 request/new turn 与 inspect-unknown 可由 trace 区分；queue 的后续动作与 outcome gate 一致；最终报告与机器 outcome 同源。四类 detector 只消费已提交 canonical facts 和稳定 typed identity，不以自然语言相似度、provider ID、Model 名或平台枚举顺序猜进展；相同 trace 在 XP/CentOS、不同 chunking 和恢复前后得到相同 fingerprint、counter、warning 与 terminal outcome。只有 registry 明定的 canonical progress 才 reset 对应模式；重启、retry、review、compaction、换 Model 或改措辞不清空当前 turn 已 durable state。A 不产生配置字段且恢复 manifest tuple，B 把一个合法 scalar 机械应用到全部已登记 detector，C 要求 registry map 完整且无未知项；三路都拒绝 0/off/infinite、超 hard maximum、XML override 与 active-turn 热换，snapshot 不能验证时在任何新 Model request/tool effect 前 fail closed。达到阈值后的 warning/escape/wait/stuck 只服从 AL06-28，threshold 字段不能改写出口。
- **失败后**：`J`。技术侧先修正 signature、fingerprint、durable state 或 registry；若所选 threshold source 无法在目标平台确定恢复，则把最小反例交回 AL06-50/LOOP-31，不能静默换 A/B/C、清空计数或通过改 TUI 文案掩盖领域误报。
- **关联**：`RUNTIME-06`、`LOOP-05`、`LOOP-14`、`LOOP-28`、`LOOP-29`、`LOOP-31`、`COMP-11`、`CFG-13`、`CFG-15`、`AQ-363`、`AQ-364`、`AQ-379`、`AQ-434`、`AL06-02`--`AL06-12`、`AL06-28`、AL06-39、AL06-42、AL06-50、`AR-P0-02`、`AR-P0-12`。

### TP-018 operation 屏障与副作用恢复

- **当前状态**：`unplanned`。
- **要证明**：direct file 与 raw shell 在执行前有 durable operation，执行后有真实或 synthetic result；崩溃发生在任意窗口时能判定 not-started/applied/unknown/conflicted，而不盲目重放。配置、Model、Permission 与 Context 的删除/reset/purge/import/migration，以及已确认的 Context rename/rebind/`AutoRenameDisabled` add/remove，必须复用等价的 `ManagementMutation` plan/stale-check/commit/result 证明，而不是复用 Agent approval；活动 writer 锁定的 Context 对外部 mutation 在 plan 前即拒绝。
- **最小证据**：在 Permission、DoubleCheck、human approval、operation commit、process spawn/file replace、result commit，以及 ManagementMutation 的 plan/impact confirmation/stale recheck/publish/result 每个边界杀进程；恢复时修改目标文件、配置引用或 Context generation 以制造 stale；对活动锁 target 尝试 rename/delete/rebind/Prompt/marker mutation，并在释放后用新 observation 重试。
- **通过条件**：历史 approval audit-only；unknown 默认不重放；通用 manual retry 不能重新执行 accepted/unknown operation；无法判断的 shell 不被 direct-tool hash 推断为成功；人工解算产生新事件而非改写历史；管理动作使用自己的精确目标和默认取消事实，不能继承历史 Agent 授权。
- **失败后**：`J`。若单 XML durable 路线不能提供所需屏障，返回 TP-008/TP-009 的存储取舍。
- **关联**：`ARCH-05`、`LOOP-29`、`AQ-103`、`AQ-104`、`AQ-225`、`AQ-279`、`AQ-316`、`AQ-364`、`AQ-369`、`CX-04`、`AR-P0-06`、`AR-P0-09`。

### TP-019 配置 parser、往返与事务

- **当前状态**：`unplanned`。
- **要证明**：typed schema、手工 INI、model/config REPL 和 Context XML override 对缺失/空值/重复/大小写/多行/unknown/deprecated 字段给出同一结果；编辑不会覆盖外部并发修改。D-048 固定每个顶层 main/side turn admission 前完整读取 INI bytes 并计算 private digest：未变复用 immutable generation，变化后整份 parse/cross-validate 并一次发布，有效变化自动生效，半写/删除/无效引用阻止新 turn，active turn 及其 tool/review/retry/compaction 子活动绝不热换。M05-57 还需要唯一版本化 `LogicalResourceNameCodec`：`Model.`/`Permission.` 是 ASCII schema prefix 与类型分隔，后续 suffix 是非空、严格 UTF-8 valid Unicode scalar sequence 的用户数据并保留原始 bytes；codec 冻结 raw section delimiter/forbidden scalar、字节长度 cap、首尾/内部空格、首尾/重复/内部 dot 及 comment/quote/backslash 等边界的 accept-or-reject 规则，匹配只 fold ASCII `A-Z`，其他 bytes 不做 locale case、Unicode normalization 或 filesystem folding。A/B/C 只决定是否以及何时存在 schema 限定的 ASCII `Abbreviation`；logical-name grammar 是 D-029 Unicode 用户数据边界下的技术 codec，不新增产品投票。D-044 必须机械投影为零 Web/media/remote/transcription/TTS 字段；D-045 固定 current-root/workdir/list/alias/selector 配置字段数为零；D-046 的 `AutoRenameDisabled` 只存在于 Context XML；D-047 固定两个 INI-only Context 列表排序字段；启动头 master 不得注册；ED-13、ED-14、RF-16 才按最终路线产生条件 schema，不能以 disabled placeholder 预留兼容面。
- **最小证据**：合法/非法 corpus、注释与顺序 round-trip、秘密保持/替换/清除、两个配置 writer、短提交锁与 expected digest、运行中外部原子/非原子保存、每个顶层 main/side turn、子活动不重载、相同 bytes/同尺寸快速改写/粗粒度 mtime、有效/无效/删除新版本、磁盘满、backup/replace 恢复、旧/新 schema migration；在 XP/CentOS 测完整小 INI 顺序读、digest、变化时 parse/validate 的延迟与峰值。名称 corpus 同时从手工 INI、writer、model/config REPL、CLI selector 和 Context XML current/history mapping 进入，覆盖 empty、1 byte、cap-1/cap/cap+1、ASCII case pair、CJK、非 BMP、组合/预组合 Unicode、不同 normalization、土耳其 I/ß、畸形 UTF-8、surrogate/NUL/CR/LF/C0/DEL、raw `[`/`]`、`=;#'"\\`、前后/内部 ASCII 与非 ASCII space、前后/连续/内部 dot、同名重复、Model/Permission 跨 namespace 同名，以及 A 的 zero-Abbreviation、B optional、C required/disabled-draft 条件。对每个 accept case 做 parse→typed draft→write→parse 和 INI↔REPL↔XML byte-exact round-trip；对每个 reject case 比较 XP/Windows 与 Linux 的 stable error/offset，排列 section 顺序并制造 logical-name/Abbreviation ASCII-fold collision。再从 typed registry 枚举 secret 副本，覆盖 M05-16/M05-56 组合；生成无 startup master、D-044 零能力字段、D-045 zero-root-field、D-046 XML-only marker、D-047 排序字段与 ED/RF 条件 snapshot，并做迁移/冲突测试。
- **通过条件**：模板/帮助/验证/REPL 同源；同一发行在所有目标平台使用同一 name-codec version、UTF-8 validator、byte cap、delimiter 与边界分类。ASCII type prefix/分隔符不会被吞进 logical name，suffix 中被 codec 接受的 dot/space 不被再次切段或 trim；raw closing delimiter、控制字符或其他拒绝项得到同一 typed error，绝不替换、normalize、自动加引号/数字或按物理顺序选第一项。accepted logical name 的显示原拼写、INI bytes、selector resolution 和 XML current reference 一致；只折叠 ASCII A-Z，NFC/NFD 与非 ASCII 大小写仍按原 bytes 区分。M05-57 A 的 `Abbreviation` surface 为零；B 不自动生成且缺失合法；C 对 Permission/enabled Model 强制、disabled draft 只按 owner 允许暂缺；B/C 中同类型全部长名/简称共享 fold namespace，跨 Model/Permission 同名合法，admission 后始终冻结完整 logical name且 XML 不把简称升级为 identity。M05-16 只能改变 outside 粒度，M05-56 只能改变 SensitiveRead 字段存在性，任一组合都不偷带另一个轴；startup master、D-044 字段/section、D-045 root 字段与 INI `AutoRenameDisabled` 数均为零，D-047 两字段只有完整默认/枚举/敏感性/生效点，ED-13、ED-14、RF-16 按最终路线提供零字段或完整组合约束；未知安全字段不被静默忽略。每个顶层 main/side turn 只在 admission 前观察完整 INI；digest 未变不重复 parse，有效变化自动发布一个完整 generation，无效/半文件/当前 Model 或 Permission 失效时阻断该新 turn并给 self-fix，不混用新旧字段、不 fallback 第一项；active turn 与全部子活动快照不漂移，也不存在 watcher/reload interval/policy 字段。任一 registered config-secret exact value 不出现在 diff/history/XML，普通正文未知 secret 的限制如实说明；清除操作准确说明哪些已知备份被处理及 best-effort 边界；首项默认和 disabled 行为稳定。
- **失败后**：`J`。技术侧先修正 parser/writer/codec 并可收窄不能无歧义 round-trip 的语法；若会排除 D-029 已确认的 Unicode 用户数据或改变 M05-57 A/B/C selector surface，则把反例交回对应 owner，不能改成 ASCII-only、locale match 或隐藏 alias。若要取消手工编辑或改变层级/默认顺序，同样交 `O` 确认。
- **关联**：D-029、`ARCH-05`、`PROD-15`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`FMT-02`、`CFG-24`、`CFG-27`、`AQ-149`、`AQ-150`、`AQ-246`、`AQ-361`、`AQ-369`、`AQ-382` 至 `AQ-390`、`AQ-430`、`AQ-432`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16、`M05-06`--`M05-10`、M05-16、M05-56、M05-57、`AR-P0-09`。

### TP-020 配置与 Context 恢复的交叉兼容

- **当前状态**：`unplanned`。
- **要证明**：Model/Permission 重命名、删除、禁用、endpoint 改变、Description 投影、Prompt 版本升级和 XML override 在恢复/导入时不会静默选择第一项、继承旧授权或把历史 endpoint 当当前连接；跨机 compatibility gap 能按负责人最终规则阻断全部续作、只阻断依赖 action/purpose，或要求 durable acknowledgement。AL06-51 需要一个 canonical `EndpointDisclosureBinding`：按 `action-review|termination-review|compaction` purpose 分别绑定当前 main/目标 Model 的完整逻辑身份与非秘密 snapshot、normalized endpoint origin/path、Protocol/tenant/auth-policy identity、proxy route、Model/config generation、data-class envelope、Context/mapping/import generation 和 codec/version；每次 request 的 exact event/view range、输入量与 exclusions 另存 disclosure manifest/receipt，不能把自然增长的 range 偷写成 C 的 binding 失效，也不能让 A/B 复用。A 每个 logical request fresh confirm，B 只在当前进程+active Context handle+purpose+binding 内复用，C 只有本机原 Context 恢复且 binding 未变时复用 durable per-purpose consent；foreign/import、复制、workspace rebind、目标机 remap 或 mapping generation 改变后的历史 consent 一律 audit-only。D-048 的新 `ConfigGeneration` 只可在下一顶层 turn admission 发布；D-045 的 rebind/复制/导入由目标 XML 镜像父目录决定唯一 root并使旧 root consent stale，D-046 的 `AutoRenameDisabled` 随 XML 保留；D-044 的 media/remote 历史只能成为 unknown/history gap，不能激活本机能力；telemetry/diagnostic-upload/update 仅在最终选入后形成 endpoint/source-verifier gap。
- **最小证据**：旧名缺失、同名不同 endpoint、Permission 降级/升级、Description 投影、DoubleCheck override、Prompt 版本变化、顶层 turn 之间配置有效/无效变化、目标机路径映射、workspace rebind/copy/import、marker true/false、Model/Permission/Prompt/tool/evidence/unknown-extension gap、foreign XML 等 fixtures。对 AL06-51 做三 purpose × A/B/C × endpoint/binding/恢复 trace matrix并在每个 durable/network 边界杀进程。D-044 覆盖外来 media/remote 历史只进入 unknown/history、当前 capability/codec/device/controller surface 为零；D-045 覆盖目标父目录决定唯一 root、零 root list；telemetry/diagnostic receipt、update source identity/version 按最终路线形成精确 gap。
- **通过条件**：历史 snapshot 完整保留；当前 effective 配置只在顶层 turn admission 重新计算并原子冻结，active turn 不热换；Description 不能推导能力或授权；新的 Context mapping/config generation 与旧历史之间存在显式版本边界。三个特殊 purpose 的 consent namespace 永不共享；A/B/C 的复用、binding、durable intent、network-write 前复核与崩溃 unknown 都严格服从 AL06-51，历史 approval/receipt 不授权新请求。所有 mapping/switch/acknowledgement 成为新事实；被阻断的 purpose/action 不先发请求或执行工具；copy/import/rebind 保留 marker、由目标父目录派生 root且不读取 XML root authority；D-044 外来 media/remote XML 只能作为 history/unknown extension 解释，不能反向激活本机 surface。
- **失败后**：`J`。技术侧可改 canonical encoding、digest 或恢复协议；若所选 AL06-51 cadence 无法在目标平台关闭 replay/TOCTOU，则把反例交回 AL06-51/MODEL-17，不能静默改成逐次、永久复用或 fallback main/第一 Model。其他静默 fallback 同样不得作为简化退路。
- **关联**：`CFG-24`、`CFG-25`、`CTX-29`、`MODEL-17`、`SAFE-08`、`SAFE-09`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-235`、`AQ-236`、`AQ-246`、`AQ-274`、`AQ-295`、`AQ-347`、`AQ-361`、`AQ-378`、`AQ-380`、`AQ-383` 至 `AQ-390`、`AQ-435`、PJ-15 至 PJ-20、ED-13、ED-14、RF-16、`M05-43`、M05-52、AL06-08、AL06-30、AL06-49、AL06-51、`CX-07`、`CX-12`、`CX-18`、`AR-P0-08`、`AR-P0-10`、`AR-P0-11`。

## P1：子系统实施前必须闭环

### TP-021 INI/XML/JSON 的数值与内存边界

- **要证明**：Lua integer/number、C size、event seq、毫秒、token、usage 和外部 64 位值在 Win32 x86 上不溢出、不变负、不因转成浮点丢身份；D-044 不建立媒体/remote size 字段，D-045 固定 root count/list/alias/selector 数值字段为零；telemetry/diagnostic upload/update 若选入时的 content length 和 receipt seq 仍服从同一先验证后分配规则。
- **证据**：边界/越界 corpus、长会话 seq、极大 provider usage、size multiplication 和 allocation failure；D-044 size/limit 与 D-045 root-count/list registry 零项扫描；条件路线增加错误 content-length、超大 manifest/download 和计数回绕。
- **通过条件**：所有外部数先验证再分配/相乘；D-044 对应 parser/limit 与 D-045 root-count/list 字段数为零，ED-13、ED-14、RF-16 按最终路线没有字段或在读取/解码/分配前返回 typed hard-limit error；不能精确表示的计量以十进制文本或受控整数模型持久化。
- **责任**：`T`。关联：`RUNTIME-05`、`FMT-03`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-382` 至 `AQ-390`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16、`AR-P1-08`。

### TP-022 backpressure 与全局资源公平性

- **要证明**：慢 TUI、慢 XML、快 SSE、快子进程和大扫描同时发生时，有界队列不会饿死 cancel/approval/input，也不会无限积累 Lua table；六个核心 purpose与 D-041 周期 `context-name` 共享同一 Model scheduler，使并发、最小间隔、`Retry-After` 与 aggregate budget 不被局部重试绕过。命名只在全局间隔启用、durable waterline 到期且 marker!=true 时低优先级进入；新 main/退出取消，退出不等待，恢复不补跑，取消 marker 从新基线开始。M05-58 retry tuple 与 AL06-50 detector registry 仍必须有界、确定且可恢复。每个 Context 恰有一个 root，不建立未计入总账的第二 root 资源域；D-044 的 Web/remote/media 队列数为零，telemetry/diagnostic upload/update 若选入也不能绕过全局预算。
- **证据**：组合压力夹具、真实/可编程 endpoint、虚拟时钟、XP/CentOS timer、单/多并发假 Model、429/503/`Retry-After`、suspend/resume、main+side+review+compaction+周期命名竞争、取消等待中的 request/retry、队列水位和逐 purpose/Context/aggregate 账本。命名覆盖 `N=0|1|10`、marker missing/false/true、设置/取消、新基线、阈值、失败、退出、新 main 与崩溃恢复。M05-58 A/B/C 与 AL06-50 detector registry 按其 owner 全矩阵验证。按 `RUNTIME-07` 覆盖单/多 active Context且各自恰一镜像派生 root；D-044 执行零 client/device-stream worker 扫描，ED/RF 条件能力按最终路线覆盖零 worker 或慢 upload/download。
- **通过条件**：控制事件优先级明确但不重排 durable 因果；可丢 UI delta 与不可丢领域事件分开；同 Model 调度服从最终 `AQ-362` 且无饥饿/超发/冷却穿透。M05-58 frozen tuple、`Retry-After`、logical/turn/Context/Runtime 总账与 AL06-50 detector state 在 XP/CentOS/重启间保持确定；cancel 不产生幽灵重试。周期命名只消费已提交 main-turn 水位、marker=true 时零 queue/cost、无工具且不阻塞退出；取消 marker 不立即或追赶命名。D-044 无后台资源域，D-045 无第二 root worker/账本；未决轴按最终路线证明零 worker 或在同一预算内收口；超限产生 typed result。
- **责任**：`J`。技术侧可优化 timer、scheduler、fingerprint 或有界 registry；若所选 M05-58/AL06-50 路线无法在目标旧机满足确定性、恢复或硬预算，只把反例交回对应 owner，不自动换 A/B/C、放宽总账或清空 detector。关联：D-036、`RUNTIME-07`、`MODEL-15`、`NET-06`、`LOOP-05`、`LOOP-14`、`LOOP-27`、`LOOP-31`、`CFG-13`、`CFG-15`、`CFG-28`、`CONC-02`、`CONC-04`、`PERF-01`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-140`、`AQ-197`、`AQ-221`、`AQ-359`、`AQ-362`、`AQ-381` 至 `AQ-390`、`AQ-433`、`AQ-434`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16、M05-58、AL06-28、AL06-42、AL06-50、F4-02、`F4-15`、`AR-P0-04`、`AR-P1-02`、`AR-P1-04`、`AR-P1-08`。

### TP-023 terminal renderer 安全与确定性

- **要证明**：模型/工具/路径中的 ANSI、OSC、C0、超长行、tab、CR、backspace、双向/零宽 Unicode 不会执行控制序列、覆盖审批文本或改变真实复制数据；40 列和无宽度信息仍可操作。D-044 已排除 image/audio/transcription/speech 渲染，用户数据只通过文本或既有文件工具结果进入 transcript。
- **证据**：恶意输出 corpus、golden transcript、resize/管道/无色/旧 console 录制；不可信 Unicode 路径/Context 名；help/renderer 对媒体、设备、转写、播报标签和占位的零项 snapshot。
- **通过条件**：程序标签固定 ASCII；不可信控制字符可见转义；颜色只是增强；同一领域事件在 renderer 降级后语义不变；媒体/语音状态与动作数为零；用户路径或内容显示降级不改变真实 identity/hash。
- **责任**：`T`。关联：`CLI-17`、`PROD-17`、`PROD-18`、`PROD-20`、`PROD-21`、`AQ-231`、`AQ-300`、`AQ-331`--`AQ-340`、`AQ-376`、`AQ-383`、`AQ-384`、`AQ-388`、`AQ-389`、PJ-15、PJ-16、PJ-19、PJ-20、`TU-12`、`TU-23`、`AR-P0-05`、`AR-P0-13`。

### TP-024 CLI、dot command 与非 TTY grammar

- **要证明**：唯一 command/help/action registry 能无冲突生成 parser、topic help、TUI 投影和 tests；每个 TUI 领域动作都有 CLI 等价投影，renderer-only 上下移动/滚动/分页不是领域动作，也不由此开放 public headless controller。`--`、引号、以 `-` 开头路径、点命令 literal、多行、focus-scoped local/global namespace 和非 TTY exit class 在 Windows/Linux shell 边界下一致；stdin/stdout/stderr 独立能力与显式 machine mode 得到确定 prompt/output；配置/Model/Context 的同一管理动作经 CLI 或 REPL 投影时产生相同 `ManagementMutation` plan/result，而不是各自放宽确认。`.model` picker、`.model <selector>` 与 CLI Model 选择必须提交同一 typed `select-model`；D-044 从 registry 生成零 Web/media/remote/transcription/TTS action；D-045 生成 zero root-list/add/remove/select/alias action，只保留单根 rebind；ED-13、ED-14、RF-16 按最终路线生成 zero action 或精确窄 action。
- **证据**：argv/property corpus、cmd/sh quoting fixtures、command/topic × AgentState/focus golden matrix、stdin×stdout×stderr×machine-mode stdout/stderr snapshot；对每个 TUI 领域 action ID 反查唯一 CLI projection；`.model` picker/direct/CLI 覆盖相同 selector、invalid/disabled target、取消、narrow terminal 编号/文字后备、补全启用/禁用与相同 receipt；unknown topic 建议、overview/detail help、reset/delete/purge/import/migrate/rename/rebind/marker add-remove 的 CLI/三个 REPL 等价 trace，覆盖活动 Context `LockConflict`、释放后新 observation、默认 Enter、取消、stale target 和非 TTY；D-044 与 multi-root action/help/completion 零项 snapshot及 ED/RF 最终 action trace。
- **通过条件**：重复简称、action ID 或 topic 构建失败；每个领域动作经 TUI/CLI 得到同一 target、admission、Permission、confirmation、stale-check、default-cancel、result 和 error，补全或方向键不可用不影响完整操作；这套映射不产生 listener/controller/自动审批。D-044 与 multi-root action/topic/completion 数为零，rebind/marker 有完整结果；活动 writer 存在时外部 Context mutation 在任何入口都拒绝。ED-13、ED-14、RF-16 按最终路线提供零入口或准确的 admission/cancel/error/receipt；modal 输入不能在 local verb、global action、chat 文本和 approval 之间静默换义；human pipe 不自动变成 machine payload；无交互输入时不弹菜单或默认批准破坏动作；错误定位到 token/focus/状态。
- **责任**：`T`；名称和可见确认体验由 `O`。关联：`ARCH-05`、`CLI-16`、`CLI-17`、`CLI-18`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-246`、`AQ-369`、`AQ-375`--`AQ-390`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16、`TU-10`、`TU-11`、`TU-22`--`TU-24`、`AR-P0-13`。

### TP-025 compaction 的事实保留与有效性

- **要证明**：prefix summary + 最近完整原子组在目标窗口内，保持目标、决定、限制、改动、验证、unknown、未完成事项和 Model/Prompt 切换；Runtime 能按有效 Model/request shape 计算只读 effective reserve 且不会被 INI/XML 覆盖；失败/无收益不会递归耗费；当单个不可拆原子组自身超过目标 Model 窗口时，能够按最终产品选择 fail-closed 或产生有明确证据的派生表示，而不是静默切断 call/result；若手动 `.compact` 进入 v0.1，其费用/预算、取消、恢复与 view publication 必须服从最终生命周期而不伪装成普通回复。
- **证据**：长会话/多代摘要、用户纠正、工具配对、Model 切换、恢复、larger-model rebuild、单条超大输入/工具组、注入和 secret canary 夹具；按最终 `COMP-11` 选择覆盖 busy/idle admission、maintenance turn 或下一轮意图、崩溃前后 publication，或证明被排除的命令不存在。
- **通过条件**：事实 XML 不删除；summary 可追踪 source range/digest；不能拆原子组；每个 request/view manifest 记录 effective reserve、输入摘要与算法版本，但不把它保存成 XML session parameter；超大单组在请求发出前得到稳定 typed result 且完整事实仍可查看；schema 无效保持旧 view；大窗口可重建更丰富原文 view。
- **责任**：`J`；摘要质量目标由负责人确认，算法证据由技术侧。关联：`COMP-06`、`COMP-11`、`AQ-310`、`AQ-352`、`AQ-379`、`AL06-11`、`AL06-12`、`AL06-39`、`AR-P0-12`。

### TP-026 self-test 的确定性、费用与隐私

- **要证明**：静态、在线和 LLM advisory 三阶段严格分离；非 TTY 不隐式同意联网。Stage 1 必须检查 `CONTEXT` 镜像/codec、唯一 workspace root 是否存在/可进入/identity 一致、XML/lock/recovery object，以及 Catalog traversal、路径解码、候选 hash 派生的数量、耗时、hard cap 和 partial；单个当前 hash 的快速计算不得误报成 Catalog 扫描。Stage 3 只看脱敏的 Model/Permission 名称、Description/SystemPrompt 与实际 endpoint/model ID/capability matrix 摘要，提示明显错配或自然语言拼写，不能看 Key/完整工作区/真实对话、改配置、授予能力或把风格当硬错误。D-044 的 Web/remote/media checks、listener 与设备均不存在；D-045 只检查镜像派生单 root/zero-multi-root；telemetry/diagnostic upload/update 只按最终选入能力检查，且在线动作再次取得本次授权。
- **证据**：缺配置、坏配置、Context 镜像非法、workspace deleted/unreadable/identity mismatch、损坏/不兼容/锁定 XML、少量/大量 Context、不可读目录、scan cap、慢 I/O、`.status` 当前 hash、离线、单 Model 失败、费用取消、恶意/误导/拼写错误的 Model 与 Permission 名、名称-能力双向错配、不同 reviewer、非 TTY fixtures；每项稳定 check ID 均从 TUI 与 CLI 做 list/select/legal-exclude；发送 manifest 与 canary 检查；D-044 与 multi-root zero-check snapshot，以及 ED/RF 最终路线的静态/在线检查、拒绝和取消 trace。
- **通过条件**：每项检查有稳定 ID、stage、severity、scanned scope/count、duration、complete|partial、exit class 与 self-fix owner；当前目标损坏按规则阻断，其他历史损坏与 scan cap/性能问题不会被谎报为全局 healthy。确定性失败不被 LLM 覆盖；在线测试逐 Model/purpose 可重跑；Stage 3 advisory 明确可忽略且实际 Permission 始终由 capability matrix 决定；TUI/CLI 选择同一 check 得到同一结果，排除不能跳过阶段依赖；D-039 禁止的启动/定时/本地动作零联网，ED-13/ED-14/RF-16 的 consent 互不复用。
- **责任**：`J`。关联：D-039、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-246`、`AQ-382` 至 `AQ-390`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16、`M05-10`--`M05-12`、`TU-09`、`AR-P1-07`。

### TP-027 Git 与非 Git 改动证据

- **要证明**：yaca 能区分会话前用户已有改动、direct tool 改动、shell 可能改动和外部并发修改；Git status/diff 只作增强，不自动 stash/reset/commit/push；非 Git 仍有完整基础报告。
- **证据**：staged/unstaged/untracked/ignored/submodule、非 Git、case/line-ending/file-mode、shell 生成文件和外部修改 fixtures。
- **通过条件**：结束报告不把用户已有脏状态归功于 Agent；Git 不可用不破坏基础工具；二进制/超限变化诚实报告；unknown 不被 diff absence 当作未发生。
- **责任**：`J`。关联：`AQ-129`、`AQ-169`、`AQ-249`、`AQ-312`、`TS-08`。

### TP-028 数据分类与 secret canary

- **要证明**：每类数据在六个核心 purpose与 D-041 周期 `context-name`、TUI、XML、stderr、support、export、HTTP/HTTPS 和跨 endpoint 中严格服从同一矩阵；自动 secret detector 不夸大保证。`context-name` 只见有界命名视图、无工具，达到 durable main-turn 水位且 `AutoRenameDisabled!=true` 才发送，marker=true 时不形成 request/费用，取消 marker 只建新基线，取消/退出/恢复不重放。Stage 3 只接收脱敏的 Permission/Model 名称、Description/SystemPrompt 与真实能力/连接摘要，绝不接收 Key、完整工作区或对话。M05-56 B 的 SensitiveRead classifier 只提高 direct read 限制。AL06-51 的特殊 purpose manifest/consent 仍按 purpose 隔离并在最终 network write 前复核。TS-40 对 reserved tree 的选择必须投影成精确可见性。D-044 的 media/remote 数据类别、peer、endpoint 和 carrier 数为零；aggregate telemetry、diagnostic upload 和 update 若选入也不得借 Model/tool/support 授权。
- **证据**：由 typed registry 自动生成的 config-file/ambient/runtime secret、URL userinfo、HTTP endpoint、对话 token、私钥文件、shell 输出、编码/压缩后二进制和 foreign XML canary；覆盖 current/temp/previous-valid/config backup/export、跨 chunk marker/digest、AL06-51 三 purpose consent/TOCTOU/crash 与 TS-40 A/B/C reserved-tree 矩阵。周期命名覆盖 `N=0|1|10`、marker missing/false/true、设置/取消/new baseline、最小视图、秘密排除、新 main/退出/恢复；Stage 3 覆盖 permitted manifest、Key/正文 canary 排除和 reviewer 输出仅 advisory。D-044 运行 category/payload/endpoint/device/carrier 零项扫描；ED-13、ED-14、RF-16 按最终路线执行 zero-send 或 exact manifest/consent/receipt/跨 endpoint 测试。
- **通过条件**：结构化 secret 硬阻断；最终规则禁止的 secret 不经明文 HTTP 发出；M05-56 A/B、AL06-51 A/B/C 与 TS-40 A/B/C 各自严格按 owner 规则收口，历史 approval/consent 不授权新 Model、endpoint 或 purpose。周期命名无工具、只消费最小视图，marker=true 时零 request/cost，取消 marker 不追赶，并在退出/恢复后无幽灵请求；Stage 3 无 secret/工作区/对话 canary且不能改变 Permission。D-044 media/remote 数据与 endpoint 数为零；ED-13 consent 不授权 ED-14，二者都不授权 RF-16；raw shell 宽可达性只产生风险与审计，不被 direct gate 虚构成 containment；选择性删除诚实列出已知副本、已发送内容和物理残留边界；LogLevel 不改变 canonical/secret 不变量。
- **责任**：`J`。若 AL06-51 disclosure identity/replay/TOCTOU 证明失败，技术侧先改 encoding/durable gate；仍不能兑现时把反例交回 AL06-51/MODEL-17，不得自动改 cadence或复用范围。关联：`NET-13`、`MODEL-17`、`SAFE-08`、`SAFE-09`、`CFG-25`、`CFG-29`、`CTX-28`、`CTX-29`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-246`、`AQ-276`、`AQ-349`、`AQ-358`、`AQ-368`、`AQ-378`、`AQ-380`、`AQ-382` 至 `AQ-390`、`AQ-430`、`AQ-435`、`AQ-436`、`AQ-437`、PJ-14 至 PJ-20、ED-13、ED-14、RF-16、`M05-43`、M05-56、M05-59、AL06-08、AL06-30、AL06-49、AL06-51、TS-15、TS-16、TS-21、TS-40、`SAFE-18`、`CX-07`、`CX-18`、`AR-P0-08`、`AR-P0-10`、`AR-P0-11`、`AR-P1-06`。

### TP-029 模块/DLL/tool 搜索、ambient config 与完整性

- **要证明**：yaca 内部 Lua/C 模块、DLL、curl/helper 只从 release manifest 的受控绝对路径加载；CWD、工作区、环境 `LUA_PATH/LUA_CPATH` 和普通 PATH 不能替换内部依赖；内部 curl/cmd/sh/Git/helper 也不能因用户 rc、AutoRun、pager、external diff/textconv 或其他 ambient config 改变基础设施语义。TS-40 的 `ReservedIdentitySet` 必须识别 Runtime canonical data-root `__yaca__` 的真实物理树并关闭 alias/race。宽 Shell 是另一条明确环境契约。D-044 的 listener/media/IPC 组件、loader、asset 搜索路径和 helper 必须为零；ED/RF 若选入 upload/update 组件则进入同一 allowlist。
- **证据**：每个搜索位置放置恶意同名文件；在 home/workspace/环境/平台配置位置放置会执行或改写参数的 ambient config；Git pager/external helper/textconv、shell AutoRun/rc 与 curl 配置夹具；DLL dependency/import walk；运行时 hash/身份复核；安装路径含空格/非 ASCII/只读。为 reserved tree 在 XP/各正式 Windows 与 Linux 目标上建立真实 data root 和普通 workspace 同名目录，分别从内外创建 symlink、junction、各类 reparse point、mount/bind alias、case-fold/大小写别名、可用与禁用 8.3 short name、file hardlink 和链式组合；覆盖 alias 指向主 INI、current/other Context、temp/backup/lock 及目录 parent。对 list/search 的隐式/显式 target，以及 read/create/write/patch/rename/delete 的 source/target/publish parent，在 canonical check 后、open 前、取 handle 后、用户确认后和读取/发布返回前交换 link、mount、目录项或 file identity；还覆盖不可读 ancestor、扫描 cap/权限导致 identity set 不完整、外部推进 Context generation 和 catalog stale。按最终 scope 比较 component manifest 与 zip，执行 A 路线 loader/route/asset/helper 负向扫描和 B/C 路线组件替换、错误架构/ISA、codec/listener/verifier 崩溃测试。
- **通过条件**：内部依赖与用户 raw shell 的 PATH/环境/配置明确分离；内部动作只受 allowlisted 输入控制，不启动未列外部 helper。TS-40 reserved identity/handle 验证在 alias/race 下失败关闭，普通同名 workspace 目录不误判，raw shell 不被虚构成受 containment。D-044 module/DLL/executable/asset/route/search-path 数为零；ED/RF 条件组件缺失、被替换或受 ambient config 影响时按组件 ID 失败；RF-16 verifier 只消费 RF-15 来源身份且不装载 RF-03 安装器。
- **责任**：`J`。技术侧先比较能保持同一 TS-40 保证的 handle/identity 实现；若目标平台无法证明 B/C 的 alias/race closure，必须把反例交回 TS-40/SAFE-18，不能静默退成 A 或按显示路径放行。关联：`PROC-13`、`THREAT-03`、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`AQ-246`、`AQ-267`、`AQ-341`、`AQ-342`、`AQ-382` 至 `AQ-385`、`AQ-387` 至 `AQ-390`、`AQ-436`、PJ-14 至 PJ-17、PJ-19、PJ-20、ED-13、ED-14、RF-16、TS-07、TS-36、TS-40、`SAFE-18`、`AR-P0-14`、`AR-P1-11`。

### TP-030 最终 zip 的干净机闭环

- **要证明**：每个平台最终 zip 在无开发工具、无系统 Lua、无网络（除用户显式允许的 Model/条件网络测试）、不同安装路径、最终 CPU/文件系统支持范围和普通用户权限下完成解压、配置、任务、工具、XML 恢复、升级/降级边界和卸载数据保留；被排除的扩展运行时及 D-044 六类能力不会因空 loader、配置字段、help/schema、endpoint 或搜索路径开放；D-045 的 multi-root surface 与旧 startup master 同样为零，单 root/rebind、D-046 marker、D-047 排序、D-048 每 turn reload 在 exact zip 中可用；ED-13、ED-14、RF-16 按最终路线兑现零表面或完整承诺。
- **证据**：release manifest/hash/SBOM 及签名或明确 unsigned policy；Windows CPU ISA/PE 与真实机证据；数据根/workspace 文件系统矩阵；每个正式 OS 的干净机场景；损坏 zip/只读目录/杀毒占用/旧 schema fixtures；对 MCP、插件、hook、skill、自定义工具、子 Agent 和 D-044 能力执行 loader/command/config/help/schema/XML/Model-tool/clipboard-media/page/listener/endpoint/component/API 负向扫描；对 root list/alias/selector/action/component 与 startup master 做零项扫描，并覆盖镜像父目录单 root、rebind、marker、六种列表排序、活动锁 mutation 拒绝、`.model` picker/direct/CLI 等价、有效/无效逐 turn 配置 generation、Stage 1 Catalog 检查与 Stage 3 Permission advisory；ED/RF 条件路线覆盖 consent、签名、平台、取消与 D-039 零隐式网络。
- **通过条件**：测试对象是最终 zip 字节；组件 ABI、ISA、许可证和来源齐全；只有负责人确认的入口存在。D-044 每项、multi-root 和 startup master 都有配置/help/schema/zip 零表面证据；single-root/rebind/marker/sort/reload/model-select/self-test 在全部声明 Windows/Linux 版本通过功能、安全、取消、恢复和资源门，其中 XP/CentOS 不可由现代机替代；ED-13、ED-14、RF-16 按最终路线提供零表面或完整证据；RF-16 只发现/下载经 RF-15 认证的目标平台产物，不执行 RF-03 未授权安装；README 与实测一致。
- **责任**：`J`。关联：D-039、`PROD-17` 至 `PROD-21`、`DIAG-14`、`REL-11`、`REL-14`、`PLAT-13`、`EXT-01` 至 `EXT-03`、`AQ-246`、`AQ-370`、`AQ-373`、`AQ-382` 至 `AQ-390`、PJ-14 至 PJ-20、ED-13、ED-14、RF-03、RF-15、RF-16、`RF-01`--`RF-11`、`AR-P0-01`、`AR-P0-16`。

## 已识别跨系统缝隙的证明归口

下表只说明“由哪里证明”，不表示相应产品选项已经确认。`O/J` 条目必须先等待负责人决定可见保证；TP 随后把决定转成可复现证据。纯 `T` 条目可以直接细化 fixture，但仍不能在目标平台证据完成前标为 `proven-target`。

| 新增边界 | 主要证明入口 | 证明失败时回到哪里 |
| --- | --- | --- |
| Win32 CPU ISA | TP-001、TP-002、TP-030 | `REL-14` 与发布范围 |
| suspend/resume | TP-003、TP-005、TP-017 | `RUNTIME-06` 与 active-turn 降级 |
| internal ambient config isolation | TP-006、TP-029 | `PROC-13`；若平台无法禁用则回安全承诺 |
| plaintext HTTP endpoint | TP-006、TP-007、TP-028 | `NET-13` 的 endpoint/secret 组合 |
| per-Model retry expansion / deterministic backoff | TP-006、TP-022 | M05-58、`CFG-28`、`AQ-433` 的数字/预设路线；证明失败不得偷换配置面 |
| short config-secret threshold / deterministic exact scanner | TP-006、TP-010 | M05-59、`CFG-29`、`AQ-437` 的 A/B/C 保证；证明失败不得自动降级路线 |
| canonical scalar / XML 1.0-safe lossless carrier | TP-010、TP-015、TP-021 | TS-23 的 canonical admission 契约与所选 schema；不得以 replacement/normalization 兜底 |
| Protocol × tool carrier feasibility | TP-015 | `M05-01` × TS-23 answer-set；`openai-responses` free-form 失败即 conflict |
| reserved-tree exact read / alias race | TP-028、TP-029 | TS-40、`SAFE-18`、`AQ-436` 的 exact-read 路线；不能按 basename 或显示路径放行 |
| Model/Permission Unicode logical-name codec | TP-019 | M05-57、`CFG-27`、`AQ-432`；D-029 下只回技术 grammar，不新增 ASCII-only 产品票 |
| stuck detector / threshold snapshot recovery | TP-017、TP-022 | AL06-50、`LOOP-31`、`AQ-434`；算法失败不得清零或改选 threshold source |
| special-purpose endpoint disclosure consent | TP-020、TP-028 | AL06-51、`MODEL-17`、`AQ-435` 的 cadence/binding；foreign/rebind state 只作 audit |
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
| aggregate telemetry | TP-006、TP-007、TP-019、TP-022、TP-024、TP-026、TP-028 至 TP-030 | ED-13、`AQ-246` 的无发送/one-shot/persistent opt-in 边界 |
| diagnostic upload | TP-006、TP-007、TP-019、TP-022、TP-024、TP-026、TP-028 至 TP-030 | ED-14、`AQ-390` 的无上传/逐次预览确认边界 |
| update discovery/download | TP-006、TP-007、TP-011、TP-019、TP-021、TP-022、TP-024、TP-026、TP-028 至 TP-030 | RF-16、`AQ-387` 与 RF-15 来源身份、RF-03 安装所有权 |

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

- P0 决策包全部答复后，为每条 TP 冻结具体 fixture、命令、目标机和证据保存位置。
- 一个子系统的 implementation plan 只能依赖已经 `proven-target` 的底层能力，或把对应最小证明作为该计划第一阶段且设置 stop gate。
- `proven-modern` 只能用于筛选候选，不能解除 XP/CentOS 发布门。
- 最终发布必须把 TP 结果接入 requirement → decision → spec → test → evidence 追踪，而不是单独留在实验笔记里。
