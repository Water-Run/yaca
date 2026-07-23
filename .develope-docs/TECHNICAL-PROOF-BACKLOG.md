# 技术证明债务表

更新日期：2026-07-18

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
- **要证明**：所有拟随包 C 模块严格按目标 Lua 5.5 headers/ABI 分平台重新构建，不混入 Lua 5.4、LuaJIT 或错误位数产物。
- **最小证据**：每项模块的源码 hash、patch、编译器/ABI/ISA flags、导出/导入表、反汇编或等价指令扫描、加载及错误卸载测试；Windows x86 和 CentOS 7 x86_64 各一份。
- **通过条件**：加载、调用、GC、错误抛出、重复创建/销毁和长期 soak 无 ABI 崩溃；Windows native 模块服从最终确认的 `REL-14`，构建可复现；模块搜索不从 CWD/PATH 注入替代品。
- **失败后**：`T` 优先换窄绑定或改为 helper；若所有候选都要求改变 Lua 5.5/平台保证，再转 `O`。
- **关联**：`REL-14`、`AQ-187`、`AQ-250`、`TS-09`、`AR-P0-16`。

### TP-003 Windows XP/CentOS 统一事件泵

- **当前状态**：`unplanned`。
- **要证明**：Lua 领域核心保持单线程状态所有者时，console input、curl stdout/stderr、工具进程、timer、cancel、XML commit completion 可以进入同一有界事件泵，且没有任何一个阻塞源冻结全部应用；系统 suspend/resume 或显著时钟间隙也能成为显式事件并触发最终规格要求的重新验证。
- **最小证据**：只包含 `start/poll/cancel/join/close` 的最小 port；同时运行慢 SSE、慢命令输出、用户输入和周期持久化；分别在 sampling、tool-running、approval、commit 和 idle 中 suspend/resume；记录事件顺序、墙钟/单调钟差、队列峰值、CPU、句柄与恢复后的 lease/workspace 状态。
- **通过条件**：忙时输入和 Esc 在已确认延迟预算内可观察；慢消费者产生明确 backpressure；取消后必须得到真实 completed/cancelled/failed/unknown 之一；恢复后不自动重放不能证明连续性的模型请求或副作用，旧 approval/action snapshot 按最终规格重新验证；无共享 Lua table 的后台写入。
- **失败后**：`J`。技术侧先比较原生等待层、极小 I/O 线程和 helper；若只能取消流式或取消忙时输入能力，交负责人确认降级。
- **关联**：`RUNTIME-06`、`AQ-261`--`AQ-265`、`AQ-315`、`AL06-01`、`TS-09`、`AR-P0-04`、`AR-P0-05`。

### TP-004 Windows XP console 与 QuickEdit

- **当前状态**：`unplanned`。
- **要证明**：XP 传统 console 下能够识别普通 Enter、Ctrl+Enter、Shift+Enter、Alt+Enter、Esc；能力不足时能够可靠声明并使用点命令后备；QuickEdit、窗口关闭、Ctrl+C/Ctrl+Break 不会让程序永久挂死或破坏终端状态。
- **最小证据**：真实 XP console 与重定向/管道矩阵；逐键事件 trace；raw→cooked→恢复；选择文本造成阻塞时的诊断；异常退出后的模式/代码页/光标复核。
- **通过条件**：帮助只宣传实际可用动作；无法区分的组合键不误映射为另一动作；draft 不因异步输出静默丢失；终端恢复有 best-effort 证据。
- **失败后**：`O` 只决定是否接受某组合键在 XP 必须使用文本后备；技术侧不能假装快捷键工作。
- **关联**：`AQ-009`、`AQ-264`、`AQ-265`、`TU-03`--`TU-05`、`AR-P0-05`。

### TP-005 子进程树、取消与 unknown

- **当前状态**：`unplanned`。
- **要证明**：Windows `cmd.exe` 和 Linux `/bin/sh` 启动的前台命令，其 stdin、stdout/stderr、退出、超时、取消和子孙进程可以按最终确认契约收口；无法证明终止时准确返回 unknown；过长或无法无损编码的 raw command 不会被 Runtime 静默改写成另一动作；各平台 termination grace 和内建 `auto` decoder 可以作为发行契约冻结而不暴露用户字段。
- **最小证据**：直接子进程、孙进程、继承句柄、主动读取 stdin/等待交互、忽略信号、快速退出与 cancel 竞态、创建到纳入 Job 的竞态、fork 后脱离进程组、不同 grace 值的收敛/延迟矩阵、平台命令长度边界、代码页/UTF-8/无效序列/二进制输出和不可表示字符等夹具。
- **通过条件**：模型可见 `exec` 不会偷取 TUI/审批输入；若最终选择 stdin=EOF，所有读取立即得到 EOF；命令长度/编码超限得到稳定 typed error，除非负责人另行确认并完整规定受保护脚本路线；每个平台 manifest 固定有界 grace，result 记录实际 decoder/替换/失败/原始字节；不因发送 kill 就声称已停止；不复用仍可能回调的 operation/buffer；退出后无可归属僵尸、孤立 reader 或句柄泄漏；unknown 可由恢复页解释。
- **失败后**：`J`。先收窄为“非交互、前台、有界”命令；若仍不能提供可取消性，再决定是否降低 shell 承诺。
- **关联**：`PROC-11`、`PROC-12`、`AQ-119`--`AQ-128`、`AQ-367`、`AQ-371`、`TS-03`、`TS-09`、`AR-P1-03`。

### TP-006 curl 流式、取消、ambient config 与秘密传递

- **当前状态**：`unplanned`。
- **要证明**：随包 curl 在 XP/CentOS 上支持目标 TLS/代理/SSE，能够被事件泵取消，并让明文 INI Key 不进入 argv、普通环境、日志和可恢复残留；yaca 的基础设施请求不受用户/工作区 curl 配置、home/proxy/CA 等未列 ambient input 偷偷改写。
- **最小证据**：比较“secret config 走 stdin/body 走私有 temp”和“body 走 stdin/secret config 走私有 temp”；在用户目录、工作区与环境放入会改 header、proxy、CA、redirect 或输出的恶意/冲突配置；使用 canary key 检查进程列表、环境、temp、stderr、XML、支持输出和崩溃残留；再评估是否需要 libcurl bridge。
- **通过条件**：请求体与 Key 传递无歧义；实际请求 manifest 只由 schema、受控平台信息和显式用户选择决定，不读取未列宿主配置；所有 temp no-replace、最小权限、有界、启动可回收；redirect 不向不同 origin 转发 Key；`NET-13` 最终确认禁止的 HTTP/secret 组合在发出任何正文前失败关闭；取消与断流给出确定 attempt 结果。
- **失败后**：`J`。技术侧可换 B/C 路线；若只能把 Key 暴露在已确认禁止的位置，需负责人重新确认明文 Key/外部 curl/平台目标的组合。
- **关联**：`PROC-13`、`NET-13`、`AQ-220`、`AQ-277`、`AQ-278`、`M05-02`、`AR-P0-14`、`AR-P1-02`。

### TP-007 TLS、CA 与明文 HTTP 旧平台基线

- **当前状态**：`unplanned`。
- **要证明**：最终 curl/CA 组合在 XP 和 CentOS 7 上能连接已支持协议端点，不依赖过旧系统 TLS；自定义/系统/随包 CA 的选择、证书错误和代理 CONNECT 可解释；`NET-13` 最终确认的 loopback/LAN/public HTTP 与 `AuthMode` 组合可以在发请求前确定执行、确认或拒绝。
- **最小证据**：有效链、过期、错误主机名、私有 CA、代理认证、SNI、TLS 版本/密码套件、系统时间错误、离线，以及 HTTP loopback/LAN/public、redirect、空/非空 Key 和 secret header 的组合矩阵。
- **通过条件**：不存在隐式 insecure fallback；禁止的明文传输不会只警告后继续，允许或需确认的组合产生与最终产品决定一致的稳定结果；错误能区分信任、主机名、协议、明文策略和网络；CA 来源/版本进入发布 manifest 与 self-test。
- **失败后**：`T` 更新随包 curl/CA；若端点要求目标平台无法承载的 TLS 组合，交 `O` 决定支持边界。
- **关联**：`NET-13`、`AQ-137`、`AQ-145`、`AQ-146`、`M05-01`、`M05-04`、`AR-P1-02`。

### TP-008 单 XML 完整重写的正确性

- **当前状态**：`unplanned`。
- **要证明**：流式复制旧 XML、插入 canonical event/footer、完整验证、flush 与发布的协议，在每个崩溃点最多留下一个可识别的 current/previous-valid 状态，不产生半个正式 XML。
- **最小证据**：对 open/read/copy/write/flush/close/verify/replace/directory flush 的每个边界故障注入；磁盘满、权限变化、杀进程、杀机器、杀毒软件占用和跨卷错误。
- **通过条件**：恢复算法只依据可验证证据；正式路径始终是完整 well-formed XML；副作用前 durable operation 屏障和副作用后 result 屏障可区分；不自动重放 unknown。若负责人最终选择整 Context purge 或 redaction rewrite，发布协议必须同时枚举并处理 yaca 知道的 current/temp/previous-valid/backup generation，且只宣称证据实际支持的 best-effort 删除，不把 unlink 写成物理 secure erase。
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
- **要证明**：目标构建可分块解析/验证项目 XML 安全子集，writer 能确定性转义，DTD/entity/外部读取被硬拒绝，资源上限在 C 与 Lua 两侧都生效。
- **最小证据**：目标平台构建、合法 fixtures、畸形 UTF-8、重复/未知字段、深度/属性/文本/实体炸弹、分块边界、writer→parser round-trip 与 fuzz corpus。
- **通过条件**：无 DOM 全量加载；禁用 DTD 不是只靠未注册回调；非法 XML 不触发文件/网络访问；错误包含安全位置和类型但不回显秘密正文。
- **失败后**：`T` 比较更窄 binding/helper；若没有目标可行 parser，再返回 `O` 重新讨论 XML/平台组合。
- **关联**：`AQ-186`--`AQ-188`、`CX-06`、`AR-P1-01`。

### TP-011 文件系统支持矩阵、发布、锁与 durable 原语

- **当前状态**：`unplanned`。
- **要证明**：Windows XP 与 CentOS 7 分别能在最终公开支持矩阵中的每类数据根文件系统兑现 `publish_new_no_replace`、替换已有文件、move-no-replace、文件/目录 flush、writer lease 与 stale lock 证据；workspace 使用更弱文件系统时也只提供被探测能力支持的 direct write/rename 结果。矩阵尚待 `AQ-370` 决定，本文不预先把任何文件系统标为已支持。
- **最小证据**：同名竞态、读者持有句柄、只读/ACL、候选 NTFS/FAT/SMB、Linux 本地文件系统、NFS/可移动盘、跨卷、断线、休眠、断电/崩溃和两个进程争抢夹具；数据根与 workspace 分开记录结果。
- **通过条件**：不得先删正式文件再放新文件；锁文件存在不自动等于活进程；无可靠 no-replace/flush/lease 时，相应数据根被拒绝或动作按已确认支持等级失败关闭；workspace 降级不被描述成 Context durability；每条原子性和掉电持久声明都绑定平台、文件系统与挂载前提。
- **失败后**：`J`。可改协议或降低支持文件系统；若影响“单 writer/完整 XML”承诺则由负责人确认。
- **关联**：`PLAT-13`、`AQ-172`--`AQ-175`、`AQ-290`、`AQ-370`、`CX-04`、`CX-05`、`AR-P0-11`、`AR-P0-16`。

### TP-012 Unicode 路径、LogicalPathCodec 与 hash

- **当前状态**：`unplanned`。
- **要证明**：中文/非 ASCII 路径、Windows 盘符/UNC/junction、Linux bytes 名称、大小写和规范化规则能在显示、文件操作、镜像树和固定 16 位 hash 中保持同一身份。
- **最小证据**：路径 corpus；Windows wide API；组合/分解 Unicode；大小写碰撞；尾点/空格、保留名、长路径、UNC、根目录、Linux 非 UTF-8 bytes；跨机 fixture 与固定 hash 向量。
- **通过条件**：显示替换不改变实际路径/hash；每个逻辑路径有唯一编码或明确拒绝；rename 后 hash 立即变化；碰撞/不可读范围不误选；所有入口复用同一 codec/resolver。
- **失败后**：`J`。技术侧可拒绝无法无歧义编码的路径；若要缩小已确认中文路径/平台保证，需负责人决定。
- **关联**：`AQ-177`、`AQ-189`、`AQ-223`、`CX-08`、`AR-P0-11`。

### TP-013 Context Resolver 的遍历复杂度与正确性

- **当前状态**：`unplanned`。
- **要证明**：已确认的增量搜索环、同环 name-before-hash、hash-like selector 单遍双判定和不重复处理候选，在大目录、链接环、不可读范围和并发变化下仍得到确定结果。
- **最小证据**：多祖先/子树、近 hash/远 name、同环碰撞、权限错误、百万候选、reparse/symlink cycle、扫描期间 rename/delete；在目标旧机上记录不同 hard cap 下的探测次数、首反馈、峰值内存和 stale generation。
- **通过条件**：候选最多有效探测一次；当前环未完整不能宣称唯一或不存在；每个平台发行 manifest 冻结不可放宽的 Runtime scan cap，超限返回 scan-incomplete；浏览器、CLI、rename/delete 使用同一服务且不读取 `MaxScanEntries` 配置。
- **失败后**：`J/T`。技术侧先优化遍历、分页与 manifest cap；只有改变已确认裁决顺序或产品保证才回到负责人。
- **关联**：D-024、`CX-08`、`CX-09`、`AR-P0-11`。

### TP-014 direct file tools 的字节保真与冲突检测

- **当前状态**：`unplanned`。
- **要证明**：read/search/write/patch/rename/delete 在 CRLF/LF、BOM、无效 UTF-8、二进制、大文件、权限位、case-only rename、hardlink/symlink 与外部并发修改下不会静默改写用户数据。
- **最小证据**：字节级 fixtures、expected digest 竞态、no-replace、原子替换失败、链接目标替换和特殊文件；比较操作前后内容与元数据。
- **通过条件**：文本工具只处理已声明文本；无法保真时拒绝或走 raw shell 宽能力；每次副作用重新验证目标身份；活动 workspace 失效或文件系统缺少所需原语时 fail-stop，不沿用 stale 路径或猜测重绑；结果说明内容、属性、文件系统能力和截断变化。
- **失败后**：`T` 收窄工具契约；任何扩大到自动编码转换的行为须 `O` 明确同意。
- **关联**：`PROD-16`、`PLAT-13`、`AQ-112`--`AQ-118`、`AQ-268`、`AQ-269`、`AQ-370`、`AQ-372`、`TS-02`、`TS-07`。

### TP-015 canonical Model 协议与工具增量

- **当前状态**：`unplanned`。
- **要证明**：首版 wire profile 的 role、SSE、text/reasoning/tool delta、usage、finish/refusal/error 可以归一为稳定事件；断流或畸形响应绝不提前执行看似完整的 tool call。
- **最小证据**：录制/合成 provider fixtures；任意分块边界；同响应 text+tools；重复/缺失 call ID；JSON 断尾/重复 key/深度炸弹；length/refusal/filter；streaming force/try/off。
- **通过条件**：只有完整 response 全量校验、canonical assistant 事件 durable 后工具才 accepted；每个本地 ID 唯一；重试不会把已见规范事件的响应整体重放。
- **失败后**：`T` 收窄 v0.1 wire profile；增加第二协议或宽松兼容必须回 `O` 确认范围。
- **关联**：`M05-01`、`M05-03`、`AL06-03`、`AR-P0-03`。

### TP-016 typed control 对支持 Model 的可用性

- **当前状态**：`unplanned`。
- **要证明**：`finish/ask-user/refuse` 载体、action-review/termination-review verdict、compaction schema，以及 PJ-12 B 条件 `context-name` 的有界 basename 输出，在声明支持的 Model 上达到可接受的结构化成功率，并能在无效输出时确定失败关闭。
- **最小证据**：跨 Model 固定任务、提问、部分完成、拒绝、工具后完成、注入、复核拒绝/无效 schema 和压缩 fixtures；记录 retry、token、误终止和误继续。
- **通过条件**：Runtime 不解析自然语言猜状态；无效 control 不变成 completed；typed `ask-user` 与其后用户回复按最终确认的 turn/reply-to 规则形成唯一因果关系；reviewer 不取得工具；硬预算始终收口；差异不靠逐字输出判断。
- **失败后**：`J`。先调整 prompt/schema/兼容协议；若某 Model 无法可靠使用核心控制，则负责人决定标为不支持工具 Agent、降级文本模式或移出正式 Model 范围。
- **关联**：`LOOP-28`、`AQ-251`--`AQ-259`、`AQ-363`、`PP-05`、`AL06-02`、`RF-07`。

### TP-017 AgentLoop 全出口 typed outcome

- **当前状态**：`unplanned`。
- **要证明**：完成、waiting-user、cancelled、budget-exhausted、stuck、refused、partial、error、storage-failed 和 unknown-side-effect 等所有出口都通过同一状态机产生，任何 `break/error` 不会在外层误报 completed；suspend/resume、ask-user reply 和用户手动 retry 也不绕过正式 turn/request/attempt transition。
- **最小证据**：逐 transition golden trace；在模型、tool、approval、storage、queue、steer、side、DoubleCheck、compaction、suspend/resume、waiting-user reply 和每类 retry 入口注入取消、预算和错误；恢复后再次跑判定。
- **通过条件**：每个 accepted tool call 配对真实/synthetic result；terminal review 只由 typed finish 触发；ask-user reply 的 turn/快照/预算按最终决定唯一冻结；UI 不存在无对象的泛化 retry，安全 attempt、新 request/new turn 与 inspect-unknown 可由 trace 区分；queue 的后续动作与 outcome gate 一致；最终报告与机器 outcome 同源。
- **失败后**：`T` 修正状态/事件契约；不允许通过改 TUI 文案掩盖领域误报。
- **关联**：`RUNTIME-06`、`LOOP-28`、`LOOP-29`、`AQ-363`、`AQ-364`、`AL06-02`--`AL06-12`、`AR-P0-02`。

### TP-018 operation 屏障与副作用恢复

- **当前状态**：`unplanned`。
- **要证明**：direct file 与 raw shell 在执行前有 durable operation，执行后有真实或 synthetic result；崩溃发生在任意窗口时能判定 not-started/applied/unknown/conflicted，而不盲目重放。配置、Model、Permission 与 Context 的删除/reset/purge/import/migration 若最终采用共同 `ManagementMutation`，也必须复用等价的 plan/stale-check/commit/result 证明，而不是复用 Agent approval。
- **最小证据**：在 Permission、DoubleCheck、human approval、operation commit、process spawn/file replace、result commit，以及 ManagementMutation 的 plan/impact confirmation/stale recheck/publish/result 每个边界杀进程；恢复时修改目标文件、配置引用或 Context generation 以制造 stale。
- **通过条件**：历史 approval audit-only；unknown 默认不重放；通用 manual retry 不能重新执行 accepted/unknown operation；无法判断的 shell 不被 direct-tool hash 推断为成功；人工解算产生新事件而非改写历史；管理动作使用自己的精确目标和默认取消事实，不能继承历史 Agent 授权。
- **失败后**：`J`。若单 XML durable 路线不能提供所需屏障，返回 TP-008/TP-009 的存储取舍。
- **关联**：`ARCH-05`、`LOOP-29`、`AQ-103`、`AQ-104`、`AQ-225`、`AQ-279`、`AQ-316`、`AQ-364`、`AQ-369`、`CX-04`、`AR-P0-06`、`AR-P0-09`。

### TP-019 配置 parser、往返与事务

- **当前状态**：`unplanned`。
- **要证明**：typed schema、手工 INI、model/config REPL 和 Context XML override 对缺失/空值/重复/大小写/多行/unknown/deprecated 字段给出同一结果；编辑不会覆盖外部并发修改；外部修改的检测、显式 reload/重启或其他最终选定触发点不会让半写文件或新 Endpoint/Permission 穿过 turn 冻结边界。
- **最小证据**：合法/非法 corpus、注释与顺序 round-trip、秘密保持/替换/清除、两个 writer、运行中外部原子/非原子保存、有效/无效新版本、磁盘满、backup/replace 恢复、旧/新 schema migration；对 Key clear/rotation 枚举 current/temp/previous-valid/backup 中已知副本。
- **通过条件**：模板/帮助/验证/REPL 同源；未知安全字段不被静默忽略；invalid draft/外部半文件不发布；新配置何时生效与最终 `AQ-361` 决定一致，当前 turn 快照不漂移；Key 不出现在 diff/history/XML；清除操作准确说明哪些已知备份被处理及 best-effort 边界；首项默认和 disabled 行为稳定。
- **失败后**：`T` 收窄往返承诺；若要取消手工编辑或改变层级/默认顺序，交 `O` 确认。
- **关联**：`ARCH-05`、`CFG-24`、`AQ-361`、`AQ-369`、`M05-06`--`M05-10`、`AR-P0-09`。

### TP-020 配置与 Context 恢复的交叉兼容

- **当前状态**：`unplanned`。
- **要证明**：Model/Permission 重命名、删除、禁用、endpoint 改变、Prompt 版本升级和 XML override 在恢复/导入时不会静默选择第一项、继承旧授权或把历史 endpoint 当当前连接。
- **最小证据**：旧名缺失、同名不同 endpoint、Permission 降级/升级、DoubleCheck override、Prompt 版本变化、目标机路径映射、foreign XML 等 fixtures。
- **通过条件**：历史 snapshot 完整保留；当前 effective 配置重新计算；外部配置 reload 和 Context 继续之间存在显式版本边界，不能把旧 snapshot 与新 Key/Endpoint/Permission 拼成一个未记录的有效配置；跨 endpoint 显示实际发送 manifest；历史 approval 不授权；所有 mapping/switch 成为新事实。
- **失败后**：`T` 改恢复流程；任何静默 fallback 均不得作为简化退路。
- **关联**：`CFG-24`、`AQ-235`、`AQ-236`、`AQ-274`、`AQ-295`、`AQ-347`、`AQ-361`、`CX-07`、`CX-12`。

## P1：子系统实施前必须闭环

### TP-021 INI/XML/JSON 的数值与内存边界

- **要证明**：Lua integer/number、C size、event seq、毫秒、token、usage 和外部 64 位值在 Win32 x86 上不溢出、不变负、不因转成浮点丢身份。
- **证据**：边界/越界 corpus、长会话 seq、极大 provider usage、size multiplication 和 allocation failure。
- **通过条件**：所有外部数先验证再分配/相乘；不能精确表示的计量以十进制文本或受控整数模型持久化；错误 typed。
- **责任**：`T`。关联：`RUNTIME-05`、`FMT-03`。

### TP-022 backpressure 与全局资源公平性

- **要证明**：慢 TUI、慢 XML、快 SSE、快子进程和大扫描同时发生时，有界队列不会饿死 cancel/approval/input，也不会无限积累 Lua table；六个核心 purpose 与 PJ-12 B 条件 `context-name` 共享同一个 Model 时，最终确认的并发/最小间隔/`Retry-After` 冷却和 aggregate budget 不会被各 purpose 的局部重试绕过。
- **证据**：组合压力夹具、虚拟时钟、单并发/多并发假 Model、连续 429/Retry-After、main+side+review+compaction+条件命名竞争、命名被新 main 抢占、取消等待中的请求、队列水位和事件延迟 trace、GC/CPU/内存及逐 purpose/aggregate 账本记录。
- **通过条件**：控制事件优先级明确但不重排 durable 因果；可丢 UI delta 与不可丢领域事件分开；同 Model 调度 obey 最终 `AQ-362` 契约且无饥饿/超发/冷却穿透，局部 cap 只能更早停止不能突破总账；超限产生 typed result。
- **责任**：`T`；若体验门无法达到则 `J`。关联：`MODEL-15`、`CONC-02`、`CONC-04`、`PERF-01`、`AQ-359`、`AQ-362`、`AR-P1-02`、`AR-P1-04`。

### TP-023 terminal renderer 安全与确定性

- **要证明**：模型/工具/路径中的 ANSI、OSC、C0、超长行、tab、CR、backspace、双向/零宽 Unicode 不会执行控制序列、覆盖审批文本或改变真实复制数据；40 列和无宽度信息仍可操作。
- **证据**：恶意输出 corpus、golden transcript、resize/管道/无色/旧 console 录制。
- **通过条件**：程序标签固定 ASCII；不可信控制字符可见转义；颜色只是增强；同一领域事件在 renderer 降级后语义不变。
- **责任**：`T`。关联：`AQ-231`、`AQ-300`、`AQ-331`--`AQ-340`、`TU-12`。

### TP-024 CLI、dot command 与非 TTY grammar

- **要证明**：唯一 command registry 能无冲突生成 parser/help/tests；`--`、引号、以 `-` 开头路径、点命令 literal、多行和非 TTY exit class 在 Windows/Linux shell 边界下一致；配置/Model/Context 的同一管理动作经 CLI 或 REPL 投影时产生相同 `ManagementMutation` plan/result，而不是各自放宽确认。
- **证据**：argv/property corpus、cmd/sh quoting fixtures、command × AgentState golden matrix、stdout/stderr snapshot；reset/delete/purge/import/migrate 的 CLI/三个 REPL 等价 trace，覆盖默认 Enter、取消、stale target 和非 TTY。
- **通过条件**：重复简称构建失败；无交互输入时不弹菜单或默认批准破坏动作；同一动作 CLI/TUI 使用同一领域命令和 stale-check，界面差异不改变 target/impact/default-cancel/result；错误定位到 token/状态。
- **责任**：`T`；名称和可见确认体验由 `O`。关联：`ARCH-05`、`AQ-369`、`TU-10`、`TU-11`、`AR-P0-13`。

### TP-025 compaction 的事实保留与有效性

- **要证明**：prefix summary + 最近完整原子组在目标窗口内，保持目标、决定、限制、改动、验证、unknown、未完成事项和 Model/Prompt 切换；Runtime 能按有效 Model/request shape 计算只读 effective reserve 且不会被 INI/XML 覆盖；失败/无收益不会递归耗费；当单个不可拆原子组自身超过目标 Model 窗口时，能够按最终产品选择 fail-closed 或产生有明确证据的派生表示，而不是静默切断 call/result。
- **证据**：长会话/多代摘要、用户纠正、工具配对、Model 切换、恢复、larger-model rebuild、单条超大输入/工具组、注入和 secret canary 夹具。
- **通过条件**：事实 XML 不删除；summary 可追踪 source range/digest；不能拆原子组；每个 request/view manifest 记录 effective reserve、输入摘要与算法版本，但不把它保存成 XML session parameter；超大单组在请求发出前得到稳定 typed result 且完整事实仍可查看；schema 无效保持旧 view；大窗口可重建更丰富原文 view。
- **责任**：`J`；摘要质量目标由负责人确认，算法证据由技术侧。关联：`COMP-06`、`AQ-310`、`AQ-352`、`AL06-11`、`AL06-12`、`AR-P0-12`。

### TP-026 self-test 的确定性、费用与隐私

- **要证明**：静态、在线和 LLM advisory 三阶段严格分离；非 TTY 不隐式同意联网；第三阶段不见 Key/完整工作区/真实对话，也不把名称风格当硬错误。
- **证据**：缺配置、坏配置、离线、单 Model 失败、费用取消、恶意 Model 名、不同 reviewer、非 TTY fixtures；发送 manifest 与 canary 检查。
- **通过条件**：每项检查有稳定 ID/severity/exit class；确定性失败不被 LLM 覆盖；在线测试逐 Model 可重跑；advisory 明确可忽略。
- **责任**：`J`。关联：`M05-10`--`M05-12`、`TU-09`、`AR-P1-07`。

### TP-027 Git 与非 Git 改动证据

- **要证明**：yaca 能区分会话前用户已有改动、direct tool 改动、shell 可能改动和外部并发修改；Git status/diff 只作增强，不自动 stash/reset/commit/push；非 Git 仍有完整基础报告。
- **证据**：staged/unstaged/untracked/ignored/submodule、非 Git、case/line-ending/file-mode、shell 生成文件和外部修改 fixtures。
- **通过条件**：结束报告不把用户已有脏状态归功于 Agent；Git 不可用不破坏基础工具；二进制/超限变化诚实报告；unknown 不被 diff absence 当作未发生。
- **责任**：`J`。关联：`AQ-129`、`AQ-169`、`AQ-249`、`AQ-312`、`TS-08`。

### TP-028 数据分类与 secret canary

- **要证明**：每类数据在六个核心 purpose、PJ-12 B 条件 `context-name`、TUI、XML、stderr、support、export、HTTP/HTTPS 和跨 endpoint 中严格服从同一矩阵；自动 secret detector 不夸大保证；整 Context purge、sanitized export 或 redaction rewrite 只给出最终负责人确认且物理协议可兑现的承诺。
- **证据**：Key、URL userinfo、HTTP endpoint、env secret、对话 token、私钥文件、shell 输出、编码/压缩后二进制和 foreign XML canary；在 current/temp/previous-valid/config backup/export 中放置标记，并执行 Key clear、Context purge 和候选 redaction 流程。
- **通过条件**：结构化 secret 硬阻断；最终规则禁止的 secret 不经明文 HTTP 发出；启发式只提高限制/警告；历史内容导出有诚实提示；选择性删除能列清 yaca 知道的副本、已发送内容和无法保证的物理残留，不把 best-effort unlink 称作 secure erase；LogLevel 不改变 canonical/secret 不变量。
- **责任**：`J`。关联：`NET-13`、`CTX-28`、`AQ-276`、`AQ-349`、`AQ-358`、`AQ-368`、`AR-P0-08`、`AR-P1-06`。

### TP-029 模块/DLL/tool 搜索、ambient config 与完整性

- **要证明**：yaca 内部 Lua/C 模块、DLL、curl/helper 只从 release manifest 的受控绝对路径加载；CWD、工作区、环境 `LUA_PATH/LUA_CPATH` 和普通 PATH 不能替换内部依赖；内部 curl/cmd/sh/Git/helper 也不能因用户 rc、AutoRun、pager、external diff/textconv 或其他 ambient config 改变基础设施语义。模型经宽 Shell 授权运行的 raw command 是另一条明确环境契约，不与内部环境混用。
- **证据**：每个搜索位置放置恶意同名文件；在 home/workspace/环境/平台配置位置放置会执行或改写参数的 ambient config；Git pager/external helper/textconv、shell AutoRun/rc 与 curl 配置夹具；DLL dependency/import walk；运行时 hash/身份复核；安装路径含空格/非 ASCII/只读。
- **通过条件**：内部依赖与用户 raw shell 的 PATH/环境/配置明确分离；内部动作只受 allowlisted 输入控制，不启动未列外部 helper；缺失/被替换或无法禁用 ambient config 时失败并给出组件/能力 ID，不回退到工作区同名文件或静默继承。
- **责任**：`T`。关联：`PROC-13`、`THREAT-03`、`AQ-267`、`AQ-341`、`AQ-342`、`AR-P0-14`。

### TP-030 最终 zip 的干净机闭环

- **要证明**：每个平台最终 zip 在无开发工具、无系统 Lua、无网络（除显式 Model 测试）、不同安装路径、最终确认的 CPU/文件系统支持范围和普通用户权限下完成解压、配置、任务、工具、XML 恢复、升级/降级边界和卸载数据保留；v0.1 被排除的扩展运行时不会因空 loader、配置字段或搜索路径而实际开放。
- **证据**：release manifest/hash/SBOM 及最终确认的签名或明确 unsigned policy；Windows CPU ISA/PE 指令与真实机证据；数据根/workspace 文件系统矩阵；干净机脚本与录屏/日志；每个正式 OS 版本的同一场景集；损坏 zip/只读目录/杀毒占用/旧 schema fixtures；对 MCP、插件、hook、skill、自定义工具和子 Agent 的 loader/命令/配置/公共 API 负向扫描与启动测试。
- **通过条件**：测试对象是最终 zip 字节；组件 ABI、ISA、许可证和来源齐全；只有负责人最终确认进入 v0.1 的扩展入口存在，其余不存在可触发空壳；README 的 CPU、文件系统、签名与扩展能力和实测一致；任何例外有 owner/expiry 且不违反 P0 不变量。
- **责任**：`J`。关联：`REL-14`、`PLAT-13`、`EXT-01` 至 `EXT-03`、`AQ-370`、`AQ-373`、`RF-01`--`RF-11`、`AR-P0-01`、`AR-P0-16`。

## 第四轮新增缝隙的证明归口

下表只说明“由哪里证明”，不表示相应产品选项已经确认。`O/J` 条目必须先等待负责人决定可见保证；TP 随后把决定转成可复现证据。纯 `T` 条目可以直接细化 fixture，但仍不能在目标平台证据完成前标为 `proven-target`。

| 新增边界 | 主要证明入口 | 证明失败时回到哪里 |
| --- | --- | --- |
| Win32 CPU ISA | TP-001、TP-002、TP-030 | `REL-14` 与发布范围 |
| suspend/resume | TP-003、TP-005、TP-017 | `RUNTIME-06` 与 active-turn 降级 |
| internal ambient config isolation | TP-006、TP-029 | `PROC-13`；若平台无法禁用则回安全承诺 |
| plaintext HTTP endpoint | TP-006、TP-007、TP-028 | `NET-13` 的 endpoint/secret 组合 |
| per-Model scheduler/cooldown | TP-022 | `MODEL-15`、`AQ-362` 的等待与并发体验 |
| ask-user reply/manual retry | TP-016、TP-017、TP-018 | `LOOP-28`、`LOOP-29` |
| raw exec stdin/command transport | TP-005 | `PROC-11`、`PROC-12` |
| Context secret purge/redaction | TP-008、TP-019、TP-028 | `CTX-28`、`AQ-368` 的删除承诺 |
| ManagementMutation | TP-018、TP-019、TP-024 | `ARCH-05`、`AQ-369` 的共同事务体验 |
| data-root/workspace filesystem support | TP-011、TP-014、TP-030 | `PLAT-13`、`AQ-370` 的支持矩阵 |
| extension runtime closure | TP-029、TP-030 | `EXT-01` 至 `EXT-03`、`AQ-373` |
| external config reload | TP-019、TP-020 | `CFG-24`、`AQ-361` 的生效点 |

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
