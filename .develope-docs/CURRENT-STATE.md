# 当前状态分析

更新日期：2026-08-30

## yaca 仓库

yaca 当前已有可执行 Lua 入口和平台无关的通用 Agent 核心；代码开发是核心常见场景，同时保留本机诊断与受控系统操作定位。C01--C31 的实现、供应链规划和现代 Linux 证明已进入 `main`，手工 `.compact` 与每次 main/review Model 请求前的自动压缩链路也已接通。它仍不是可发布版本：Win32 x86/XP、Win64/Win7+、Linux x86_64/CentOS 7 的最终构建与真实目标资格尚未完成，Release Gate R 保持关闭。

当前已实现：

- bootstrap、严格 action registry/CLI parser、旧终端 TUI/line editor、typed diagnostics 和分阶段 self-test；裸 chat 在第一条消息前仍不创建 Context。
- immutable config generation、OpenAI/Anthropic adapter、HTTP/SSE/retry/cancel、匿名 curl secret carrier，以及固定无工具的 side/review/compaction purpose。
- 单 XML Context schema/store/index/lock/recovery、首消息先 durable、operation intent/result、ModelView publication 和 cache-miss 重建。
- typed AgentLoop、queue/steer/side、ask-user/yield、action/termination review、预算/stuck/cancel/finalization 和精确 Tool result 配对。
- 八个 versioned Tool、current-process one-action Permission、direct path/identity/CAS 防护，以及明确 `opaque-uncontained` 的原生 `cmd.exe`/shell exec。
- lossless model-view compaction：结构化摘要、atomic groups、Context journal、原子 manifest publication、Runtime receipt/lifecycle gate、公开 `.compact`，以及冻结待发 main/review 请求的自动 threshold preflight、STATUS/cancel/close。
- 最小发行 allowlist、component/license manifest、SPDX SBOM、package planner、资源 overlay 和资源门禁测试 Harness。
- 受 `.tools/run_with_resource_guard.sh` 保护的完整平台无关 Lua suite 当前为 `400/400`；这不是三目标资格证明。

仍缺失或不得宣称完成：

- compaction pending request/cancel/rejection 与 failure circuit 的跨进程恢复，以及三目标 token/资源阈值校准。
- 注册但尚未全部接通 controller 的交互管理动作仍须逐项以 registry → dispatcher → production port → terminal result 证明；parser 可识别不等于 action 已实现。
- 旧环境网络/HTTPS 仍须审计并加固：固定 curl/CA/TLS 闭包、XP/Win7 可用协议与证书链、代理/redirect/retry/cancel、旧 CMD carrier 和错误编码都需最终目标证据。
- C32 的三个真实 target qualification、C33 的干净机发布旅程/零表面、C34 的最终 SHA-256/license/SBOM/build/test evidence 尚未执行。
- README 中任何能力声明仍必须受实现和 target evidence 约束；现代 Linux fake/native 边界通过不能外推为 XP、Win7 或 CentOS 7 支持。
- `_CONFIG_.ini`、`_CONTEXT_.xml` 和历史 `bin/` 仍是 non-normative/候选输入，不能覆盖当前 contracts、生成配置/Context 或最小发行 allowlist。
- 图像/音频、remote/headless、核心 Web、notification 和内建 update 继续是 v0.1 零表面，不应因通用 Agent 定位而扩张。
- 图像/音频、remote/headless、transcription 与 TTS 仍被 D-044 明确排除。
- Web：**v0.1 核心** 仍零表面（D-044）；2026-08-10 的 D-058 仅为未来 **本机本地 Web** 登记设计预留，产品线为 `yaca-web`（服务端 **Java 8**）与 `yaca-ie6`（服务端 **PHP 5.4**，浏览器有意兼容 IE6）。设计正文在 `.develope-docs/web-tracks/`；仓库根 `web/` 只作说明/空预留；JRE/PHP 与 Web 实现都不得进入 v0.1 loader、help、配置或核心 zip，也不得写成已实现能力。

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
