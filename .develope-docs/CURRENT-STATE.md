# 当前状态分析

更新日期：2026-08-30

## yaca 仓库

yaca 当前已有可执行 Lua 入口和平台无关的通用 Agent 核心；代码开发是核心常见场景，同时保留本机诊断与受控系统操作定位。C01--C31 的实现、供应链规划和现代 Linux 证明已进入 `main`，手工 `.compact` 与每次 main/review Model 请求前的自动压缩链路也已接通。它仍不是可发布版本：Win32 x86/XP、Win64/Win7+、Linux x86_64/CentOS 7 的最终构建与真实目标资格尚未完成，Release Gate R 保持关闭。

当前已实现：

- bootstrap、严格 action registry/CLI parser、旧终端 TUI/line editor、typed diagnostics 和分阶段 self-test；顶层诊断会把非 ASCII 字节稳定转义，避免旧 CMD 代码页损坏错误输出；裸 chat 在第一条消息前仍不创建 Context。
- immutable config generation、OpenAI/Anthropic adapter、HTTP/SSE/retry/cancel、匿名 curl secret carrier，以及固定无工具的 side/review/compaction purpose。
- 单 XML Context schema/store/index/lock/recovery、首消息先 durable、operation intent/result、ModelView publication 和 cache-miss 重建。
- typed AgentLoop、queue/steer/side、ask-user/yield、action/termination review、预算/stuck/cancel/finalization 和精确 Tool result 配对。
- 八个 versioned Tool、current-process one-action Permission、direct path/identity/CAS 防护，以及明确 `opaque-uncontained` 的原生 `cmd.exe`/shell exec。
- 生产 native bridge 已接通 trusted component 的结构化 argv：Windows 以绝对 `CreateProcessW`、Linux 以 `execve` 绕过命令 shell，配置字节经有界匿名 stdin pipe 发送；现代 Linux 实际模块探针与 Win32/Win64 交叉编译已通过，但真实目标资格仍待 C32。
- Win32/XP HTTPS 候选闭包已锁定：curl 8.21.0 与 Mbed TLS 3.6.7 的窄下游补丁绑定 archive/patch/基文件 SHA-256；全新 i686 串行复现得到 PE32/Windows 5.01、HTTP/HTTPS、blocking IPv4、CryptoAPI entropy，且最终导入审计无 BCrypt、Vista 同步原语、UCRT 和新 `_s` CRT 符号。该结果明确为 cross-build/static candidate，真实 XP TLS/proxy/CA 仍待 C32。
- lossless model-view compaction：结构化摘要、atomic groups、Context journal、原子 manifest publication、Runtime receipt/lifecycle gate、公开 `.compact`，以及冻结待发 main/review 请求的自动 threshold preflight、STATUS/cancel/close。
- existing Context publication core 已能在持有精确 verified target/writer 后重建 plain 或 compacted active ModelView；新格式 pending request/response/cancel/rejection bracket 会先落唯一 cancel pending/unknown 与绑定 terminal error，旧格式 pending 只落保守 unknown、不伪造新式终态，旧 active view 始终保留。compaction serial、连续 automatic failure streak 与不完整旧历史也会从 XML 恢复；自动 compaction 的进程恢复 unknown 计入失败 streak，跨进程 monotonic 时间不可继承时重新开启完整 cooldown。
- 公开 `--continue` 已接到 existing Context core：selector 必须精确解析并在加 writer 前后复核，调用 workspace 必须与 Context 镜像路径记录的 workspace 具有同一逻辑键和文件系统 identity；打开后先执行保守恢复门禁、整份配置重载与 self-test，再以 Idle Agent 恢复 event/config/ModelView 及八类 serial 水位，绝不自动重放未完成工作。跨 workspace 返回 typed confirmation requirement；存在 unfinished turn、active queue item、未决 operation/tool、unknown terminal outcome 或 pending compaction 时拒绝自动继续并释放 writer。
- chat `.context` 已复用同一 reopen core：无参数只投影最多 32 行的 bounded recent Catalog；有 selector 时先只读解析并复核目标、冻结其精确 hash/逻辑路径，只有当前 Agent 为 Idle/WaitingUser 且 queue/side/approval/compaction 全部安全时才关闭旧 owner，随后只按该 hash 在全新 composition 中再次解析/复核并打开。关闭后的 target/config/lock 竞态会作为 fatal switch failure 恢复终端并退出，绝不按短名称改开替代对象；未保存 chat 切换不会发布空 Context。
- chat `.details` 已接到 ApplicationCoordinator：每次交互错误分配当前进程内单调 `error-N`，只保留最多 64 条经控制字节清理且分别限长的 code/message/suggestion/next-action；无参数读取最新项，显式 ID 精确读取，过期 ID 返回 typed `NotFound`，不保存 raw exception、Tool body 或 transport payload。
- chat `.cautious status|on|off|toggle|reset` 已接到唯一 Session owner：首条消息前只更新有界内存草稿；保存后先用完整 Context overrides 重载一个 Agent-ready ConfigGeneration，再由单一 Context writer 在同一 XML generation 追加不含明文值的 `session_override` 与匹配 `model_view_published`，最后由 AgentLoop 精确采纳双事件回执。当前 turn 的 Model/Permission/Prompt/DoubleCheck snapshot 不热换，新值只从下一 turn 生效；plain 与 compacted active ModelView 都保持原 publication/compaction identity 链，回执失配会 fail-stop。
- chat `.prompt show|set|clear` 已复用同一 Session owner：未保存 chat 只改有界内存草稿，保存后的 ContextPrompt 先经完整 ConfigGeneration 校验和 registered-secret 扫描，再以 digest-only `session_override` 与刷新后的 ModelView 原子发布并由 Runtime 精确采纳；当前 turn 的 Prompt bundle 不热换，新值只从下一 turn 生效。`show` 使用显式引用样式投影当前值；`.prompt edit` 在有界 editor transaction 接通前明确返回 typed unavailable，不调用 ambient editor。
- chat `.model` 已接到 draft/production 双 owner：无参数最多投影 64 个 enabled/native-tool 候选的普通文本行，精确 selector 不依赖 ANSI、补全或新式终端。预检保守按 `1 byte <= 1 token` 绑定当前 config、Context generation/sequence、活动 ModelView、四层 Prompt、tool/control schema、输出与 transition reserve；目标放不下时在任何配置/XML 变更前返回 `ModelIncompatible`，不缩水历史、Prompt 或工具。endpoint route、credential slot/policy、Protocol、RemoteModel/usage、Model Prompt、adapter/streaming 或能力边界变化进入默认 deny 的 `model-change-N` 确认；只显示 origin/path、`?configured` 和非秘密 credential identity。确认绑定的 waterline/manifest/Prompt 环境/目标定义任一变化即 stale；保存态经完整配置重载、目标定义复核、Context `session_override + model_view_published` 原子提交和 Runtime receipt adoption 后只在下一 turn 生效，active turn 不热换，也不建立失败 fallback Model。
- 最小发行 allowlist、component/license manifest、SPDX SBOM、package planner、资源 overlay 和资源门禁测试 Harness。
- 运行时 curl config 已逐请求用锁定 CLI 可解析的 standalone/no-option 语法显式固定 HTTP/1.1、TLS 1.2+、服务端/HTTPS 代理随包 CA 校验；代理 TLS 下限由 `proxy-tlsv1` 与只启用 TLS 1.2/1.3 的锁定 Mbed TLS 后端共同闭合。代理/主机 DNS 和普通握手只在无 canonical event 时有界重试，证书/CA/CRL/issuer/pin/status 错误立即终止。真实目标 TLS/代理资格仍待 C32。
- 受 `.tools/run_with_resource_guard.sh` 保护的完整平台无关 Lua suite 当前为 `442/442`；这不是三目标资格证明。

仍缺失或不得宣称完成：

- `--continue` 与同 workspace `.context` 已接通，但显式跨 workspace 确认/rebind 尚未开放；三目标 token/资源阈值仍待校准。
- `.cautious`、`.prompt show|set|clear` 与 `.model` 已接通 registry → dispatcher → production port → terminal result；`.prompt edit` 仍明确 unavailable，待有界 editor transaction 实现，不能调用 ambient editor。
- 旧环境网络/HTTPS 的源码锁、XP compatibility patch、静态 import/CRT 黑名单和最小协议闭包已有可重复候选证据；仍须在真实 XP/Win7/CentOS 7 证明 TLS/CA、显式代理、redirect/retry/cancel、旧 CMD 路径与错误分类，不能据此开放 Release Gate R。
- C32 的三个真实 target qualification、C33 的干净机发布旅程/零表面、C34 的最终 SHA-256/license/SBOM/build/test evidence 尚未执行。
- README 中任何能力声明仍必须受实现和 target evidence 约束；现代 Linux fake/native 边界通过不能外推为 XP、Win7 或 CentOS 7 支持。
- `_CONFIG_.ini`、`_CONTEXT_.xml` 和历史 `bin/` 仍是 non-normative/候选输入，不能覆盖当前 contracts、生成配置/Context 或最小发行 allowlist。
- 图像/音频、remote/headless、核心 Web、notification 和内建 update 继续是 v0.1 零表面，不应因通用 Agent 定位而扩张。
- 图像/音频、remote/headless、transcription 与 TTS 仍被 D-044 明确排除。
- Web：**v0.1 核心** 仍零表面（D-044）；2026-08-10 的 D-058 仅为未来 **本机本地 Web** 登记设计预留，产品线为 `yaca-web`（服务端 **Java 8**）与 `yaca-ie6`（服务端 **PHP 5.4**，浏览器有意兼容 IE6）。设计正文在 `.develope-docs/web-tracks/`；仓库根 `web/` 只作说明/空预留；JRE/PHP 与 Web 实现都不得进入 v0.1 loader、help、配置或核心 zip，也不得写成已实现能力。

### 下次接盘检查点（2026-08-30 暂停）

- 最后一个已经实现、完整回归并推送的核心节点是 `95a0e9c11360cc97f9818c7239ac06210b3c32c7`（`feat: switch models with bound disclosure`）。该节点的受资源门禁串行 suite 为 `442/442`，coding readiness、TP-003/006/008/010 与 RP-001 均通过；`target_qualification=false`，Release Gate R 仍关闭。
- 暂停前只进行了旧环境 HTTPS/代理/CA 的只读审查。曾开始但未闭合的 `config.lua` 局部草稿已经完整撤回；没有未测试的运行时代码、没有遗留 `lua test/run.lua` 进程，也没有把 cross-build 写成真实目标资格。
- 下一实现节点先关闭两个已经定位的边界：其一，`.model` 目前只公开 `off|explicit-public-url|explicit-secret-slot`，尚未显示去 userinfo、隐藏 query value 的 normalized proxy route；同一次预览到 apply 之间，目标 Model Key、secret adapter option 或代理 credential 若只改变值而不改变公开 shape，也需要进程内不泄值的精确 TOCTOU binding。其二，`.tools/qualification/build_linux_x86_64.sh` 仍硬编码旧的 `329/329` suite 数量，并在 onefile 声明至少需要 5 GiB 时使用 `-j2` 与 4096 MiB 默认门槛；应改成串行构建、强制不低于实际峰值的 guard floor，并从唯一 `SUMMARY total=N passed=N failed=0` 动态记录证据。
- 上述修改必须先补 config/production Model selection/资格脚本静态契约测试，再按“人工查看 `free -h`、`/proc/pressure/memory`、遗留 test runner → guarded targeted → guarded full suite → guarded coding readiness”的顺序串行验证。不得复用本轮内存数字；本轮曾观察到 Swap 基本耗尽，因此尤其不能跳过新鲜 preflight，也不能并行跑 proof。
- 真实 XP SP3 x86、Win7 SP1 x64、CentOS 7 x64 仍是 C32 唯一有效证据来源。保留未来提交名不提前使用：`test: qualify all release targets`、`test: prove release journeys and zero surface`、`docs: publish qualified release evidence`。

### 本轮已冻结的产品主链

- 裸 `yaca [directory]` 不扫描历史，直接进入新的未保存 chat；旧 Context 只通过 `.context`、continue 或 context-repl 显式打开。
- 配置损坏或无有效 Model 阻断 Agent，但 help/version、受限管理 REPL、self-test Stage 1 与不依赖 Model 的 Context 管理仍可使用。
- `General.StartupSelfTest=off|stage1|stage2|stage3` 默认关闭；启用后严格按阶段顺序运行，在线阶段仍逐次确认。
- 例行启动头没有总开关，Slogan、版本、work directory、data root、配置状态、Context/hash、Model、Permission、DoubleCheck 和 `.status` 提示只由各自 bool 控制；全部关闭也不能隐藏 ERROR/WARNING/ACTION。
- 第一条 main 用户消息先用 ASCII provisional name 建立并 durable 写入 XML，之后才能请求 Model；周期后台命名的全局间隔默认 10、0 关闭且只计 durable completed main turn。手工 rename 默认在 Context XML metadata 设置 `AutoRenameDisabled`；context-repl 取消标记从当前水位建立新 baseline，不立即/追补，自动 rename 不设置标记，标记变为 true 后在途迟到结果也不得采用。退出不等待命名请求。
- 每个 Context 恰好一个 workspace root，由 XML 在 `__yaca__/CONTEXT/` 下的镜像父目录决定，不在 XML 内另存 current workdir；显式 rebind 安全移动 XML 并改变逻辑路径/hash。活动 writer 存在时第二进程完全拒绝打开正文和一切外部 Context mutation。三个管理 REPL 各有本域 self-fix，不建立 recovery surface。
- Context 列表以 INI 的 `created|updated|name` 和 `ascending|descending` 排序，默认 `updated+descending`；时间取 XML canonical metadata，不取文件 mtime/ctime；主键相同始终按 canonical `LogicalPath` 升序且不随主方向反转，也不改变 Resolver 或裸启动。
- `.model` 无参数打开可降级 picker，`.model <selector>` 直接选择，两者与 CLI 投影提交同一个 typed Model 选择动作；补全是增强，不是命令可用前提。所有 TUI 领域动作必须由同一 registry 提供 CLI 等价入口，但这不开放 remote/headless controller。
- 每个顶层 main/side turn admission 前完整读取并比较 INI bytes；变化时整份验证后原子激活 immutable generation，当前 turn 及其工具/复核/重试/压缩不热换。Stage 1 self-test 检查 Context 镜像、workspace 与 Catalog 扫描完整性/性能，Stage 3 只 advisory 检查 Model/Permission 名称、说明、Prompt 与实际配置的明显错配和拼写。
- Permission 是命名 typed profile，`SystemPrompt` 不参与授权；普通对话没有独立 plan state。

`OWNER-QUESTIONS-01.md` 的 29 个集中问题已经全部答复并由 `DISCUSSION-BATCH-06.md` 归档。现行 register 为 `unanswered=0/conflict=0`；D-049 至 D-057 已冻结四层 Prompt、双 Model 协议、typed AgentLoop、完整 Tool/Permission、单 XML 提交基线、统一 CLI/TUI action registry，以及 Win32 x86、Win64 x86_64、Linux x86_64 三个独立 zip。16 contracts、12 fixture sets、Gate Audit 与实施计划维持 Gate A/B；C01--C31 平台无关实现已完成并持续回归。三目标 proof 尚未通过，Release Gate R 保持关闭。

### `bin/` 不是可直接发布的依赖集合

2026-07-18 的静态检查进一步证明，`bin/` 只能作为历史来源和候选清单，不能整体复制进发行包：

- Linux 侧 `lua55`、`curl`、BusyBox、diff、patch、jq、sqlite3 等都是 `ELF 32-bit`；其中 curl 自报 `x86_64-pc-linux-muslx32`，属于 x32 ABI，也不是已经确认的 CentOS 7 x86_64 普通 64 位发布基线。
- Windows 侧文件是 PE32 x86，架构方向正确，但“PE32、子系统版本 4.0”只能说明文件头，不能证明它以及全部 DLL、TLS 后端和 CRT 真能在 XP SP3 上启动并工作。
- 当前 `curl.exe` 经 UPX 压缩。静态导入表主要显示 UPX 解压 stub，而不是完整程序真实导入；在取得未压缩的可追溯构建物或先安全解包前，不能完成最低 Win32 API 审计。
- `bin/list.txt` 收录了 7za、BusyBox、file、iconv、jq、sqlite3 等大量候选工具；“仓库里已经有”不等于产品真正需要，也不等于可以进入发布攻击面。
- `cacert.pem` 的内容是 PEM 文本，但其编码、换行、来源版本、证书集合更新时间和 curl 读取结果仍须由发布测试确定，不能只相信 `file` 的标签。

因此发布系统必须从零生成按平台区分的最小 allowlist；每个组件记录来源、版本、架构/ABI、构建选项、hash、许可证、真实动态导入和目标系统运行证据。UPX 等打包步骤只能在未压缩产物已经完成导入审计后考虑，且压缩后的最终文件仍需重新跑完整平台测试。

## luainstaller 能力

相邻的 `../luainstaller` 当前为已打 tag 的 **1.3.0**（2026-08-24；commit `97192d1`）：

- 支持官方 Lua 5.1--5.5；yaca 将固定使用 Lua 5.5 ABI。
- 能生成目录包和自解压单文件；官方建议先验证目录包。
- 入口和纯 Lua 模块会嵌入生成的 C launcher。
- Lua C 模块及匹配的 Lua runtime 可以复制到包内。
- 打包必须在目标平台家族上原生完成，不提供跨平台编译。
- Lua 5.5 安装路径要求 LuaRocks 3.13.0 或更新版本。
- native profile 已覆盖 x86/x86_64，Windows 生成代码对 x86/x86_64 固定 `_WIN32_WINNT=0x0501`，PE subsystem 分别为 5.01/5.02。
- 1.3.0 已加入 i686/x86_64 MinGW 生成源码与 XP import/subsystem 静态检查、Windows XP onefile watchdog 后备及 Linux native x86 CI。

此前记录的“Windows profile guard 拒绝 x86 / recipe 仅 x64”已被 1.3.0 的实现与测试取代，不能继续作为当前阻塞原因。现存缺口是 **yaca-specific qualification**：尚未用 yaca 的 Lua 5.5 入口、XML 模块、curl/CA 与最终最小依赖闭包生成 Win32/Win64 候选，也没有 XP--11、Win7--11 的完整目标机证据。luainstaller 自身把真实 XP 列为 supplemental evidence，而 yaca 的 D-007/D-056 仍把 XP 完整测试设为硬门；因此 AR-P0-16 已达到 `qualification-bound` 计划状态，但 Gate R 未通过。

## XML 库候选现状

上下文 XML 路线已锁为 LuaExpat 1.5.2 + Expat 2.8.2，写入端使用 yaca 自有的受限流式 writer。TP-010 已用固定 SHA-256 在现代 Linux x86_64 可复现构建 Lua 5.5.1/LuaExpat/Expat，并通过 5,564,743 条分块、Unicode、binary、invalid UTF-8、实体安全和 roundtrip 断言；证据为 `proven-modern`。Windows `lxp.dll` 与 Linux `lxp.so` 仍须针对三个目标原生构建/加载并校准资源上限；modern 结果不替代 CentOS 7 或 Windows XP 验收，也不替代单 XML 的目标 replace/lock/崩溃恢复证明。

## 与 yaca 的接入结论

luainstaller 负责把 Lua 入口、Lua/C 模块和最终确认的最小运行依赖打进平台 executable；D-056 已固定最终 zip 根不暴露历史 `bin/` 依赖树。Windows 根只有 `yaca.exe`、`Install.cmd`、`README.txt`、`LICENSE`、`docs/`，Linux 对应 `yaca`/`Install.sh`。随包 curl/CA 等能力若被最终实现需要，必须由 luainstaller 的资源/嵌入路线或经批准的最小适配兑现，不能把当前候选 `bin/` 整体复制到 zip、也不能临时增加未确认的根级文件。该能力在最后打包阶段 qualification；当前不修改兄弟仓库。

## 主要风险

### 旧 Windows

luainstaller 1.3.0 已消除旧的 x86 profile guard，并提供 XP API/subsystem、MinGW import closure 与 watchdog 的现代机静态证据；这足以支持制定 yaca qualification 计划，但不等于真实 XP 运行通过。Win32 x86/XP 仍取决于 XP-capable compiler/CRT、Lua DLL、LuaExpat/Expat、curl/TLS 与最终依赖闭包；Win64 路线还需证明 Windows 7 SP1 下的同一闭包。yaca v0.1 采用目录 zip/原地 executable，不采用更复杂的单文件自解压产品形态。

### CentOS 7

Linux 包依赖构建环境中的匹配 Lua 5.5 头文件与共享库。为了获得可在 CentOS 7 上运行的 glibc 基线，原则上应在该目标环境类别中原生构建并验证。

当前 Linux `bin/` 不是简单的“i686 工具”：至少 curl 是 ELF32/x32 ABI，整组文件也都不是目标的普通 ELF64 x86_64 发行输入。后续不能通过重命名或只检查 `uname -m` 放行，必须检查 ELF class、machine、interpreter/静态链接方式和实际目标机启动结果。

### 外部命令

依赖随包 curl 等工具有利于旧系统兼容，但必须定义：工具查找顺序、版本契约、输出编码、超时、退出码、证书路径以及用户自行替换工具后的支持边界。
