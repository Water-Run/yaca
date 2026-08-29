# 当前状态分析

更新日期：2026-08-29

## yaca 仓库

yaca 当前是“产品说明、配置草案、模块骨架、设计文档体系和本地运行工具集合”，还不是可执行的 Coding Agent。

已有内容：

- 中英文 README 已描述目标产品、命令、模型、上下文和权限概念。
- `_CONFIG_.ini` 是已明确标记的 historical/non-normative 草案；现行字段真源在 `subsystems/05-configuration.md`。
- `_CONTEXT_.xml` 提供了上下文文件头部草案。
- `bin/` 本地放置 Lua 5.5.0、curl、BusyBox、jq、diff、patch、iconv、file、sqlite3 等 32 位工具。
- `coding-style.txt` 规定了 Lua 5.5、旧终端、旧浏览器和保守工具链要求。
- 核心 Lua 文件已经按职责命名，但当前均为空。

缺失内容：

- 没有可运行入口、模块接口、测试、安装脚本或发布脚本。
- README 目前描述的是目标行为，尚不能视为已实现契约。
- CLI 旧短参数冲突已在 `ACTION-REGISTRY.md` 的规格首版中消解，但尚无 parser、机读 registry 或 golden argv 实现证据。
- 旧 README 曾混用 `_yaca_` 与 `__yaca__`；现行设计统一为 executable 相邻的 `__yaca__`，三个便携 zip 都不建立另一套系统用户数据根。
- `_CONFIG_.ini` 仍保存 `[Permission.Cautious]`、profile 内 `DoubleCheck` 等历史内容，只能用于迁移 fixture，不能成为实现输入。
- `_CONTEXT_.xml` 仍只有头部注释，尚未表达 D-022 的镜像路径、完整对话、会话参数元数据和实时索引契约。
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

`OWNER-QUESTIONS-01.md` 的 29 个集中问题已经全部答复并由 `DISCUSSION-BATCH-06.md` 归档。现行 register 为 `unanswered=0/conflict=0`；D-049 至 D-057 已冻结四层 Prompt、双 Model 协议、typed AgentLoop、完整 Tool/Permission、单 XML 提交基线、统一 CLI/TUI action registry，以及 Win32 x86、Win64 x86_64、Linux x86_64 三个独立 zip。负责人输入门已经关闭，但 owner 规格、技术证明和完整实施计划尚未全部通过，因此仍不进入编码。

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

此前记录的“Windows profile guard 拒绝 x86 / recipe 仅 x64”已被 1.3.0 的实现与测试取代，不能继续作为当前阻塞原因。现存缺口是 **yaca-specific qualification**：尚未用 yaca 的 Lua 5.5 入口、XML 模块、curl/CA 与最终最小依赖闭包生成 Win32/Win64 候选，也没有 XP--11、Win7--11 的完整目标机证据。luainstaller 自身把真实 XP 列为 supplemental evidence，而 yaca 的 D-007/D-056 仍把 XP 完整测试设为硬门，因此 P0-16 只从“工具链能力未知”降为“候选与目标证据未完成”，没有通过。

## XML 库候选现状

上下文 XML 的当前领先技术候选是 LuaExpat 1.5.2 + Expat 2.8.2，写入端使用 yaca 自有的受限流式 writer；具体库由 CX-06 下游的 `TP-010` 兼容性、实体安全、流式内存和目标机证据决定，不再要求项目负责人替技术侧投库名。本轮临时 Linux x86_64 smoke test 证明 LuaExpat 1.5.2 源码可以针对 Lua 5.5.0 构建并完成分块解析，但还没有归档为可复现测试证据，更不是 CentOS 7 或 Windows XP 验收。上游公开支持目前止于 Lua 5.4，Windows XP x86 也没有现成上游保证。因此 Windows `lxp.dll` 与 Linux `lxp.so` 都必须针对 Lua 5.5 和目标架构原生构建；库选型不能替代单 XML 的原子提交、锁和崩溃恢复设计。

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
