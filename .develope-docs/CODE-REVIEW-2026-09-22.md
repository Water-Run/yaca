# 实现代码 Review 与验收记录

按 D-075 对未发布实现逐项审查。此记录仍在进行，不能据此宣称完整 Review 或发行验收通过。
对象为当前工作树（基线 `36abd51cf74ab3cd51f3a1ea7def464b90c48a0e`），
包含核心 Lua、原生 C、入口、构建与打包代码，以及对应测试。

## 已定位的问题

| 编号 | 问题与影响 | 处理与证据 |
| --- | --- | --- |
| R01 | 无效输入提交后仍保留在 coordinator 缓冲，下一行被隐式拼接；实机 `.side` 拒绝后 `.status`、`.help` 也失败 | 已修复：被拒绝草稿可取消或重试，新输入替换它；新增真实命令组合回归，586 项 suite 通过；N18 实机命令组合通过 |
| R02 | Model 使用 request 局部 Tool ID，Runtime 使用 turn Tool ID，界面把一次调用显示为 tool-1 与 tool-2 | 已修复：执行事件携带两种 ID，显示沿用请求 ID；driver 与 coordinator 回归覆盖；N18 真实模型调用从请求到结果均为 tool-1 |
| R03 | 仅重命名 `.ask` 界面仍保留 side purpose、事件字段、方法和错误码，增加未发布实现的认知负担 | 已清理：内部统一 ask，原生 Alt+Enter、Prompt、XML 契约和测试同步；无别名与迁移；586 项 suite 通过 |
| R04 | Windows 内层解释器通过 CRT 的 ANSI argv 接收 Unicode，结构化 Lua 参数可能损坏 | 已修复：CommandLineToArgvW 后统一 UTF-8；SHELL32 导入仅对内层入口放行；Server 2008 原生 Lua 工具探针通过中文、非 BMP、空参数和特殊符号 |
| R05 | Context 事件/字节上限与运行预算无统一收尾预留；操作后可能没有空间提交结果 | 已实现：发布前计算实际 XML 与持久化事实导出的收尾预留；重开仍可恢复预留；已接纳工具结果及终态能落盘。容量拒绝不损坏 writer，模型视图过大与压缩首请求拒绝可正常收尾；597 项回归通过 |
| R06 | 单文件外层提取器仍使用 ANSI 命令行/路径接口 | 已修复：外层宽字符 argv 与 UTF-8 路径适配、内层 Lua 文件 API 同步；Server 2008 中文及非 BMP 安装/temp/脚本/文件/参数实测通过；Lua 模块路径缓冲按 UTF-8 字节不足也已修复，N21 超过 260 UTF-8 字节的中文模块路径通过 |
| R07 | 生产 chat 固定 cooked 输入，却按 Windows 平台宣告增强快捷键；独立 line editor 尚未接入生产 chat | 已修复能力声明；生产按系统行编辑提供 Enter、文本命令和 `.multiline`。N19 Cygwin 中文多行输入、查看/取消、无效命令恢复、退出与 stty 恢复通过；N22 XP 原生控制台的离线向导、中文 Ask、保存重开及模式恢复通过；CentOS 7 的实际模型旅程也通过 |
| R08 | Shell 父进程已退出但子进程尚在运行时，取消因 `reaped` 提前返回，GC 也可能跳过终止 | 已修复：以整个活动的终态为准；原生 Linux、Server 2008 各两项实测通过，取消分别约 509/525 ms；自然完成会等待子进程 |
| R09 | Linux 进程组为空不能证明通过 setsid 离组的后代已经停止 | 已实现每活动独立 subreaper；仅收齐后代并收到完整监督回执后才报告证明。开发机及 CentOS 7 的 3.10.0-1160.el7 内核均通过 7 项原生检查（setsid、双 fork、取消、自然结束、GC、监督进程故障及主进程骤停） |
| R10 | 大量 stdin 同步写入，遇子进程不读或先大量输出时阻塞主循环 | 已修复：Windows 独立有界输入写线程，Linux 监督进程非阻塞写；两平台各 2 项真实 1 MiB 反压/取消/双向读写通过 |
| R11 | 生产 Windows chat 经窄字符 CRT 写 UTF-8，中文显示乱码；全平台 UI 又把中文转义 | 已修复：控制台使用 WriteConsoleW，管道保持 UTF-8；UI 保留合法 Unicode。Server 2008 Unicode 字体/OEM 437 探针通过，N19 Cygwin 中文原样显示。栅格字体缺字是宿主限制，探针对照保留，不修改用户字体/代码页 |
| R12 | 首条 `.ask` 要求先创建 main；接入后又发现真实存储会把追加首批问答事实的空视图误判为 stale | 已修复：先发布空 Context；空历史前缀在追加 admission 事实时仍有效。补上实际 Context store 的发布/重开测试，收紧 Session fixture；N21 首次多行中文 `.ask` 实际请求通过 |
| R13 | 原生进程启动后再分配 Lua userdata，分配失败可能遗留活动进程 | 已修复：先创建可 GC 的所有权对象再创建进程；Windows Job、输入线程引用与 Linux supervisor 句柄分别回收 |
| R14 | 工具执行后才发现 result 外壳过大，错误文本也可能无界 | 已修复：授权/intent/副作用前校验不可变结果外壳，给错误和摘要预留空间；截断按 UTF-8 边界，覆盖超限写入不产生 intent 或文件 |
| R15 | 生产 Tool 上限收紧到 64 KiB，exec policy 仍使用配置默认 1 MiB，真实 Lua 被 InvalidExecPolicy 拒绝 | 已修复：从同一组已接纳 Tool options 生成执行策略；生产 fixture 改用实际默认值，并覆盖更小配置上限。599 项完整回归通过；N21 真实 Lua 输出 42、后续 Ask 无工具回答 42 |
| R16 | Windows 文件操作假设文件编号在改名后不变，FAT32 的替换已发生却被误报 Unknown | 已改用贯穿操作的属性句柄绑定对象；字节长度、修改时间与元数据检查保留。独立 XP FAT32/NTFS 探针证明属性句柄可穿过 ReplaceFile，文件编号变化后仍指向同一对象；新增长名称文件/目录改名、替换、删除回归；Server 2008 及 N22 的 XP FAT32/NTFS 全部通过 |
| R17 | XP 在取消时用 ERROR_NO_DATA（232）表示 stdin 读端关闭，原生层误报 unknown | 已按读端关闭处理，与 ERROR_BROKEN_PIPE 一致；保留其他 IO 错误。XP 诊断捕获了 232；修复后的正式 Lua 7 项及 stdin 2 项通过 |
| R18 | 单文件缓存要求私有 DACL，TEMP 在 FAT32 时提取失败 | 仅对已绑定到实际句柄卷的本地 FAT/FAT32/exFAT 公共程序缓存使用无 ACL 路径；逐字节校验及禁止写入/删除的句柄保留。NTFS 和未知文件系统仍执行原有 ACL 处理；N22 在 XP FAT32/NTFS 的长中文及非 BMP 路径通过；FAT32 缓存被损坏后重新提取逐字节一致，运行中写入/删除/改名均被拒绝 |
| R20 | 自检在发布成功后仍使用旧文件编号，FAT32 上误报 Unknown 且无法确认临时文件清理 | 已让 Windows/Linux 的 direct rename/replace 返回经过原生后置条件验证的发布后身份；fs 校验并冻结该回执，自检据此读回与清理。600 项回归通过；9 月 23 日 N23 在 XP 的 FAT32/NTFS 原生回执检查及 FAT32 ST1-ATOMIC-WRITE 通过，Linux 新回执仍待目标复测 |
| R19 | jq 1.8.2 的 MinGW 构建导入 XP msvcrt 不提供的 _mkgmtime64 | 已加入仅 XP 构建启用的 UTC 历法计算补丁，不修改进程时区。XP 加载、数值查询、闰年、2038 后日期及月份归一化通过；纳入 full 工具构建/来源清单仍待收口 |
| R21 | Windows FAT32 写句柄关闭时仍会更新 LastWriteTime；Context、配置、curl 载体和 writer 锁把关闭前时间戳当成最终身份，可能误报保存失败或无法清理 | Win7 N4 的 r4 原生探针证实 flush 后关闭仍改变时间戳；r5 在第二次 Context 写入的 flush 后延迟 2.2 秒，以未修改核心复现首次 `.ask` 的 ContextTemporaryMismatch / AgentDurabilityFailure。已补共享的关闭后身份与按需字节读回校验，仍拒绝对象替换、尺寸变化和同尺寸内容损坏；48 项定向与 606 项完整回归通过；r6 用修正的 Lua 源码和 N4 原生组件在真实 Win7 FAT32、NTFS 上保留相同延迟，两组控制台旅程均通过。最终内嵌修复的一体包仍须重建验收 |
| R22 | 失败清理将路径重新观察到的身份当作自有文件，可能删除被替换的外来对象；直接工具还可能把同字节替换误当作原文件 | 已修复：fs、配置和直接工具从创建句柄绑定对象，清理只接受同对象身份；直接工具在读回前复核父目录和全部物理祖先，原生 verified delete 再核验。新增 8 项竞争回归覆盖早期写失败、关闭后目录持久化失败、同字节替换、发布失败时临时路径替换和祖先替换；原有相关 56 项通过，新场景 8 项通过。当前完整回归 623 项中 607 通过，16 项旧发行状态/布局检查仍失败；修正核心的最终目标包尚待重建实测 |

## 审查范围与剩余工作

| 范围 | 当前审查状态 |
| --- | --- |
| CLI、输入/输出、ask、生产组合 | 已审查 ask 全链路和输入拒绝/工具显示；R07 及其余交互路径待继续 |
| Lua 工具、进程、Permission 与审查 | 已审查新增 Lua 的结构化输入、解释器身份绑定、权限与异步操作路径；完整进程故障/取消树仍须实测 |
| Context、Session、Index、Compaction、恢复 | 已确认 R05；持久化与容量边界继续审查 |
| Model、Prompt、Network、重试、秘密传递 | ask 无工具投影已回归；网络故障矩阵及其余代码继续审查 |
| 文件、路径、文本、编码、JSON/XML/INI、配置 | 继续审查，重点为大文件、旧编码、外部修改与解析限制 |
| native、平台后端、时钟、入口 | Unicode 内层参数已修复；完整原生资源生命周期与 R06 待继续 |
| 发行、工具闭包与构建脚本 | 新增 std 与三档装配已有验证；full、三目标实际运行与对应源码闭包待完成 |

## 本次证据

- 2026-09-23：`out/xp-20260922-r1/evidence-n23/summary.txt` 中 **13 组全部通过**。
  同目录 `core.log` 是 N23 的 **600/600**；包括 FAT32/NTFS 的发布后身份回执、
  中文/非 BMP 路径、正式 Lua 7 项、stdin 2 项、jq、缓存损坏修复及运行中句柄保护。
  `console/result.txt` 证明首次离线配置、中文纯 Ask、Context 重开及控制台模式恢复。
  `selftest.log` 的 ST1-ATOMIC-WRITE 通过；因本次只选择单项检查，总体仍按契约为
  partial / exit 1，未把其余 SKIPPED 项当作通过。客体已正常关机。
- 2026-09-23：Server 2008 N23 的 `agent-online-r2-transcript.log` 记录首次中文
  Ask、唯一 Lua 工具调用、后续无工具 Ask、应用退出 0、精确 stty 恢复。
  外层 SSH 返回 255，使原测试脚本整体失败，失败记录保留；
  `ssh-exit-baseline.log` 证明同一登录 PTY 不启动 yaca、只执行 `exit 0` 也返回 255，
  非 PTY 对照返回 0。不能把该脚本整体记为 PASS，也不能把 255 归因为 yaca。
  此后服务器开始在 SSH 握手阶段关闭连接，NTFS 继承权限的追加检查未完成。
  前置 PowerShell 1.0 夹具因参数兼容及未形成不同 DACL 失败；新增
  `windows_inherited_smoke.py` 使用 Windows API 创建夹具，并先验证实际自动继承位
  与继承 ACE，再运行原生检查；该夹具随后在 Win7 N4 上通过，Server 2008 仍待运行。
- 2026-09-23：Win7 SP1 x64 N4 的 `out/win7-20260923-n4/evidence-r1/`
  记录核心 **600/600**、FAT32/NTFS 原生发布及 Unicode、正式 Lua、stdin、
  继承 DACL、HTTPS、缓存修复和运行中保护通过。`inherited.log` 的夹具验证
  实际 control=8404、继承 ACE=3。原生控制台旅程失败见 R21。
  r1 metadata 夹具误放 FAT32，未满足其 NTFS DACL 前提；独立 r2 在 NTFS 通过，
  未因此改动产品或删除 r1 失败记录。r2 未修改 N4 的两种文件系统控制台旅程均通过。
  r2 的源码诊断启动器把 Lua 负索引 arg 误传给 CLI，入口即拒绝；属于诊断夹具错误，
  不能用该结果判断 Context。后续 r3 只复制正式 argv，继续诊断。
- Win7 N4 的 r3 七轮 FAT32 控制台旅程通过；第八轮 NTFS 因诊断启动器自行拼接路径、
  未复用原生大小写规范化而失败。r4 使用未改动的原生 executable_paths 后通过。
  r4 `filetime.log` 的第 3、4 项显示同一对象、同一长度在关闭写句柄后修改时间变化；
  [Windows 文件时间约定](https://learn.microsoft.com/en-us/windows/win32/sysinfo/file-times)
  也明确最后写入时间要在写句柄全部关闭后才完整更新。
  r5 仅注入写入调度延迟，`diagnostic-00-diagnostic.txt` 记录临时文件对象及长度不变、
  时间戳改变，并逐层出现 ContextTemporaryMismatch、AgentDurabilityFailure。
  r2–r5 证据均在 `out/win7-20260923-n4/`；已正常关闭客体后取回。
- `review-write-close-r1.log`：关闭后身份、Context 提交、配置、curl 载体及 native ports
  **48/48**。补充覆盖真实对象被替换、同长度内容损坏和长度变化，未放宽后续稳定身份检查。
- `out/full-build-20260922/review-full-r6.log`：此前核心完整 suite **599/599**；
  R20 后的 `review-fat-receipt-r1.log` 为 **600/600**。
- XP SP3 客体的 N22 完整 suite **599/599**：`out/xp-20260922-r1/evidence-n22/core.log`。
  同目录的 native-fat/native-ntfs、Lua 7 项、stdin 2 项、jq 和缓存修复/句柄保护通过。
  Unicode 日志退出 0 且实际 marker 为 `windows-unicode=PASS`；首版 driver 误匹配了另一
  marker，summary 的两项 FAIL 保留并单独说明。原生控制台探针的后续独立记录
  `evidence-n22-console-r4/` 已通过向导、中文 Ask、无工具请求、保存重开和模式恢复；
  其自检揭示 R20，失败记录保留。之前三次探针分别受整屏读取、DBCS 字符数等问题影响。
- XP SP3 实机客体的 N21 完整 suite **599/599**：
  `out/xp-20260922-r1/evidence-debug/core-suite.log`。首次 TCG 的外层 300 秒超时
  记录保留在 `evidence-tcg/`，没有当作通过；KVM 重跑使用独立证据目录。
  同机 std 的 Python 2/SSH 主机密钥/HTTPS/7-Zip，以及 full 原型中的 Python 3.4.10、
  Git 本地提交、SQLite、C/C++ 编译运行和 BusyBox 已通过；这不是 full 发行资格。
  `evidence-r2/` 记录 R17、R18、R19 的局部修复验证。
- CentOS 7 N21 从锁定源码完整重建核心与第三方依赖，`centos-n21-build.log`
  记录 **599/599**、ELF/依赖及 glibc 2.17 审计；未复用此前编译产物。
  `centos-supervisor-n21.log` 为 7 项进程监督检查，`centos-lua_tool-n21.log`
  与 `centos-process_stdin-n21.log` 分别为 7 项正式 Lua 工具与 2 项 stdin 反压检查。
  `centos-agent-n21-result.log` 为首次中文 Ask、真实模型 Lua 42、后续无工具 Ask、
  正常退出与终端状态恢复。日志均在 `out/full-build-20260922/`。
- `review-first-ask-store-r2.log`：真实 Context store、publication 和首次输入 **52/52**；
  `review-exec-policy-r1.log`：生产执行策略和工具执行 **34/34**。
- `review-capacity-integration-r1.log`：Session、压缩 owner 与压缩服务 **62/62**；
  `review-view-capacity-r1.log`：模型视图容量与 Context publication **51/51**。
- `out/process-tree-20260922/supervisor-r2.log`：Linux 原生六场景加主进程骤停，**7 项**。
- `stdin-linux-r2.log` 与 `stdin-console-windows-r3.log`：两平台 stdin **各 2 项**。
- `console-windows-r6.log`：真实 Unicode 控制台字符和换行通过；r5 保存栅格字体退化对照。
  [Microsoft 的控制台说明](https://learn.microsoft.com/en-us/windows/console/setconsoleoutputcp)
  也区分 Unicode 字体与栅格字体的行为。
- `out/windows-preview-20260922-n19/agent-offline-result.log`：聊天命令、多行中文和终端恢复通过。
- `out/windows-preview-20260922-n21/agent-online-result.log`：首次多行中文纯问答、Lua 42、
  再次纯问答 42、单一 Tool ID、退出码 0 与 stty 恢复全部通过。
- N21 `unicode-long-result.log`：UTF-8 字节长度超过 260 的临时模块路径、中文及非 BMP
  安装/脚本/文件/参数通过；`lua_tool-r2-result.log`、`process_stdin-r2-result.log`、
  `native-publication-r2-result.log` 分别为正式工具 7 项、stdin 反压 2 项及真实文件/XML 原语通过。
- N19 由完整 builder 重建核心和第三方依赖，PE/DLL/API 导入审计通过；
  源码、锁定依赖、生成启动器和构建记录均在候选附件中，不含测试配置。

- `out/full-build-20260922/ask-clean-suite.log`：586/586。
- `ask-clean-design.log`：7658 条断言；`ask-clean-readiness.log`：553 条，Gate R closed。
- `ask-clean-proof-readiness.log` 中历史 proof 检查为 56/56；后续 readiness 的失败已通过
  同步当前 C27 名称解决，最终结果以上一条独立 readiness 日志为准。历史独立证明的行为不变；
  D-076 要求其维护源码也补齐文件头和注释，历史证据不改写为当前源码的新证明。
- N17 `lua-tool-native.log`：Server 2008，7 项正式 Lua 工具的真实进程检查通过。
- N17 `agent-ask-transcript.log`：真实 Agent 调用 `lua` 得到 42；Ask 回答 42，未调用工具；
  同时复现 R01、R02。该候选仍有 side 内部名，不能代表 R03 后的新实现。
- N18 `agent-ask-transcript.log`：真实 Lua 工具 42、`ask-1` 无工具回答 42、Tool ID 一致。
  该次复合 shell 脚本的后置终端检查异常，不能当作完整退出验收。
- N18 `agent-ask-lines-result.log`、`agent-ask-lines.log`：真实 SSH login shell 逐行进入，
  无效命令恢复、正常退出 0、退出后 shell 可用、stty 状态一致；脚本退出 0。
  复合 shell 脚本的异常在无 yaca 基线也出现，没有因此修改核心或降低终端断言。
- `out/process-tree-20260922/{linux,windows}.log`：父进程先退出的取消与自然完成各两项。
  Windows 探针使用 N18 inner 加当前源码新建 native DLL；不是旧 N18 DLL 的证据。

正式验收仍需完整审查收口、缺陷修复、三目标产物与实际运行证据，以及各发行包的许可和源码附件。

## 2026-09-23 注释约束执行记录（进行中）

- 全仓文件头已统一。`out/code-comment-audit-20260923/header-token-equivalence.json`
  记录 196 个文件修改前后的散列及相同的非注释语法 token 散列；空的未使用构建占位文件已删除。
- 已 Review 并补齐 28 个只读代理实现及其内联元方法、70 个共用辅助函数、31 个弱键注册表。
  平台、时钟、两套后端、文本、safety、断言辅助和可执行契约的当前声明覆盖缺项为零；这不代表全仓完成。
- 检查器覆盖具名/匿名/嵌套函数、C 宏和接口、元表/类型字段、PowerShell 匿名脚本块，以及
  Shell 内直接传给解释器的 here-document 和单引号执行片段。动态生成模板仍须逐项 Review。
  检查器反例 **14/14**；新增验收入口实际返回 **1**，保持拒绝剩余缺项。
- 当前报告 `out/code-comment-audit-20260923/inventory-r8.json`：**203 文件，4954 声明，
  13019 条缺项**。同一声明可能有多个缺项；未将它们误报为 13019 个不同函数。
- R22 修复后的最新报告为 `out/code-comment-audit-20260923/inventory-r22.json`：**203 文件，
  4976 声明，12988 条缺项**；仍需逐项补全并进行语义 Review。
- 注释相关定向回归 **32/32**，日志为 `annotated-modules-regression-r1.log`。
  随后当前整个工作区回归为 **615 项、599 通过、16 失败**，见 `comment-pass-full-r1.log`。
  失败集中于后来并入的旧发行状态/包布局检查与当前清单不一致；待统一发布状态和新三版布局，
  不沿用之前 606/606 的结论，也不通过放宽断言把当前全仓测试改报为通过。
- R22 修复及新增竞争场景后的完整回归为 **623 项、607 通过、16 失败**；
  `out/code-comment-audit-20260923/r22-full-r1.log` 证实上述 16 项仍为同组发行状态/布局失败，
  文件身份修复和新增竞争测试没有新增回归失败。
- 2026-09-23：将 `release/dependencies.lock`、readiness 契约和历史现代主机证明的**当前结论**
  与未发行的 D-073 三档目标对齐；保留旧候选环境记录，但 Release Gate R 关闭、三个目标待验收。
  clean 包检查器只接纳目标主程序，测试另证安装器和文档不能混入 clean 包。
  中英文 README 与 Windows/Linux quickstart 明确候选状态、内嵌 Lua、`.ask` 和三档工具关系。
  readiness **559 条断言通过**；文档真值检查 **5 项通过**。完整 Lua 回归
  `out/code-comment-audit-20260923/r23-full-r2.log` 为 **631/631**。
- 路径、权限、进程模块及 clean 包检查器、readiness 校验器已逐声明补齐并通过结构检查；
  路径/权限单元回归 **18/18**，进程适配定向回归 **12/12**。当前全仓报告
  `out/code-comment-audit-20260923/inventory-process-r1.json` 为 **203 文件、4976 声明、
  12708 条缺项**；注释验收仍拒绝通过，后续需继续完整语义 Review。
- Prompt、JSON、INI、XML 模块也已按所有函数、闭包和原生回调补全并通过逐文件结构检查；
  对应定向回归分别为 **11/11、8/8、24/24、15/15**。最新全仓报告
  `out/code-comment-audit-20260923/inventory-xml-r1.json` 为 **203 文件、4976 声明、
  12355 条缺项**。模块头部日期同步为本次实质更新日期；完整注释验收仍未通过。
- clean 包检查器增加精确清单边界：即使修改 manifest，也不能把安装器/文档或额外 map 键
  扩进只含主程序的 clean 根目录；结果摘要不再暗示 clean 自带安装器。
  新增回归和该测试文件所有声明注释后，全量 Lua suite
  `out/code-comment-audit-20260923/r24-full-r1.log` 为 **632/632**。
  最新结构报告 `out/code-comment-audit-20260923/inventory-clean-r1.json` 为
  **203 文件、4977 声明、12304 条缺项**，发行与注释资格仍待全部目标及全仓收口。
- TUI 与终端端口的所有渲染器、代理方法、回调和输入编辑函数注释已逐声明核对；
  对应定向回归 **18/18** 与 **19/19**。当前全仓报告
  `out/code-comment-audit-20260923/inventory-terminal-r1.json` 为 **203 文件、4977 声明、
  12085 条缺项**。这两个模块自身均无结构缺项，仍需其他模块和测试代码继续补齐。
- 诊断模块的 59 个函数/元表声明以及 Context 索引模块的 68 个声明已逐项补全，
  两个模块自身均无结构缺项；诊断与分阶段自检定向回归 **19/19**，索引、
  目标重验与关联故障回归 **41/41**。对索引扫描的注释语义复核修正了端口失败值
  和部分统计先于最终确认的描述。最新全仓报告
  `out/code-comment-audit-20260923/inventory-index-r1.json` 为 **203 文件、4977 声明、
  11771 条缺项**；完整注释和发行资格仍未达到。
- 压缩模块 54 个声明已逐项补齐，并检查了计划、原子分组、持久化回执、重试、
  取消和 Unknown 生命周期的注释契约；Model 压缩端口、长 Context 与单元测试
  **18/18** 通过。全仓 `out/code-comment-audit-20260923/inventory-compact-r1.json`
  为 **203 文件、4977 声明、11634 条缺项**，模块自身零缺项。
- 网络模块 91 个声明和对应资格测试文件 10 个声明已逐项补齐；资格测试原先
  与标题相反，仍断言旧 D-072 `target_qualified=true`。现改为当前 D-073
  三档目标待验收的 `false`，并更新测试。网络定向回归 **26/26**，完整 Lua suite
  `out/code-comment-audit-20260923/r25-full-r1.log` 为 **632/632**。最新报告
  `out/code-comment-audit-20260923/inventory-network-r3.json` 为 **203 文件、4977 声明、
  11398 条缺项**。网络和该资格测试文件自身零结构缺项；最终目标资格仍未通过。
- CLI 模块 71 个声明已补齐并通过结构检查，覆盖语义注册表、argv/行命令、
  编辑器、TTY 门禁和机器输出；解析器、管理 REPL 与文档真值定向回归 **44/44**。
  `out/code-comment-audit-20260923/inventory-cli-r1.json` 为 **203 文件、4977 声明、
  11227 条缺项**；仍需其余核心、测试、构建和原生代码的逐项审查。
- 配置模块 93 个声明已逐项补齐并通过结构检查，区分普通字段解码、适配器秘密值、
  弱键代际私有值，以及临时文件身份/持久化错误。配置单元与 bootstrap/publication
  定向回归 `out/code-comment-audit-20260923/config-target-r2.log` 为 **80/80**。
  全仓 `out/code-comment-audit-20260923/inventory-config-r1.json` 为 **203 文件、
  4977 声明、11030 条缺项**；配置模块自身零缺项。
