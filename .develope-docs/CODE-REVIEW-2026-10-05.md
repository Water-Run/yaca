# win32 full 最终包在 Server 2008 的干净机旅程

日期：2026-10-05。基于 `caa7860`。九包 9/9 无挂账后，按 TRACKING C33
推进 win32 版位的干净机旅程：最终装配件
`yaca-0.1.0-win32-x86-full.zip`（`96fc32cf...`，10-02 第四批）在指定实机
Server 2008（192.168.5.10，D-077 指定环境）以 std 版 7za 自举解包，
逐项走完布局/零表面/工具面/便携性/卸载。

| 旅程项 | 结果 |
| --- | --- |
| 自举解包 | std 7za.exe 解包成功；布局为 `yaca.exe` + 10 工具目录 + README |
| 核心一致性 | 实机以包内 py34 hashlib 复算 SHA-256 = `acd58d83...`，与构建件/装配件逐字节一致；亦是 py34 闭包在最低目标面的首次原生实测 |
| 非 TTY 拒绝 | 无 pty 时 `--status` 报 `TtyRequired` 且**零写入**（无 `__yaca__`） |
| 首次状态 | pty 下 `--status` 如实 `ConfigMissing`/`agent ready: false` |
| Stage 1 自检 | 建立隔离 `__yaca__` 后 **12 PASSED + 2 WARNING（配置未初始化，设计内）、0 FAILED、online-requests=0**；含 ATOMIC-WRITE、CONTEXT-CATALOG/LOCK、CA-BUNDLE、ZERO-SURFACE |
| 工具面（原生） | busybox、**git 2.10.0.windows.1**（wine i386 崩溃确认非产品问题）、Python 2.7.18、py34（hashlib/jq 输入）、jq `42`、make 4.4.1、**gcc -O2 编译链接运行 `s2k8-gcc-ok`**（PATH 含 compiler\bin；`as` 需 PATH 为既定行为） |
| 移除 tools | 改名移走后核心 `--version` 与 `--lua -E -e print(6*7)`（42）照常——与 clean 等价性在实机验证 |
| 整体移动 | 目录 move 后核心与 py34 闭包照常运行、哈希复算一致 |
| 网络 | 局域网 qwen 端点（spark:30000）可达（无密钥 401，密钥在不可达的 WSL2 机隔离目录）；出网 TLS 被路径上的拦截代理重签（呈现证书签发者 `C=US, O=Let's Encrypt, CN=YR1`，非真实 LE 中间人链）——**固定 CA 按设计正确拒绝**；未拦截出网 TLS 已由 R74 轮 Win64/DeepSeek 覆盖 |
| 卸载 | 删除目录后 C 盘与 HKCU 注册表零 yaca 残留 |

如实保留的剩余项（C33）：交互式聊天与多轮恢复的 TTY 旅程、持密钥的
授权模型往返（密钥在 WSL2 机）、win64 full 于 Win7 实机、linux full 于
CentOS 7 实机的对应旅程、九包统一 SHA-256/许可/SBOM 汇总（C34）后评审
Gate R。本轮产品源码与装配零改动，无新增提交需求（本文档与状态更新除外）。

### win64 full 最终包在 Windows 主机的旅程（10-05 续）

同日以 `yaca-0.1.0-win64-x86_64-full.zip`（`ade7ea70...`）在现代 Windows
宿主（192.168.10.104，Win11 26100）走完同型旅程；诚实边界：这是现代宿主
面，Win7 SP1 最低目标面仍属 C33。

| 旅程项 | 结果 |
| --- | --- |
| 解包与完整性 | Expand-Archive 解包；上传 zip 实机哈希 = `ade7ea70...` 与装配件一致；zip 实际 14648 文件全数解出（并以此纠正第三批记录中 14741 的误计） |
| 核心一致性 | 实机 Get-FileHash 复算 `a81a3f32...` 与构建件逐字节一致 |
| Stage 1 自检 | 计划任务内 **12 PASSED + 2 WARNING（配置未初始化）、0 FAILED、online-requests=0**（含 TTY-INPUT PASSED）；pty 直连会进 TUI，输出被终端转义吞没，以计划任务重定向取证 |
| 工具面 | yaca 0.1.0、py3.8.20/OpenSSL 1.1.1w/sqlite 3.35.5、git 2.46.2.windows.1、jq 管道、gcc 编译运行 `w64j-gcc-ok`（PATH 含 compiler\bin） |
| 移除 tools / 移动 | 改名移走后核心 `--version` 与 `--lua`（42）照常；目录 move 后核心运行、哈希复算一致 |
| 卸载 | 删除目录零残留；zip 与临时件清理，计划任务删除 |

win32/win64 两个 Windows 版位的 C33 旅程至此同型收口。剩余：linux 版位、
TTY 交互与授权模型往返、九包汇总（C34）。

### linux clean 版位随 HEAD 重建与 C7 容器旅程（10-05 终章）

Fedora 宿主如实拒绝 linux 核心构建（脚本检查 `/etc/centos-release`），
按 10-01 先例在 Docker `centos:7` 容器（vault=archive.kernel.org 源，
GCC 4.8.5-44.el7，与记录环境一致）内执行：

- **核心随 HEAD（`3a61427`）重建 PASS**：源码归档以 `git archive HEAD`
  生成（`17ce3515...`）；构建内嵌完整 Lua suite **699/699**；
  onefile `e7bb24ede41f9919803ed2f6a775eca51e3018b93027616dea012595393c6daf`，
  构建摘要 status=PASS。容器以 root 写挂载目录的权限边界以辅助容器
  收拾，如实记录。
- **clean 版位装配 editions=PASS**：companion 按既有 notices 形状从
  构建源码树重组（Expat/Mbed-TLS/curl/Lua/LuaExpat/luainstaller 许可 +
  Mozilla CA + build-summary + LINUX-QUICKSTART）；
  `yaca-0.1.0-linux-x86_64-clean.zip` = `1088d979...`（3.5 MiB）、
  notices `b7fa2147...`。
- **C7 干净机旅程**（`docker run -t` 提供 TTY）：解包布局 `yaca` 单文件；
  容器内哈希复算 `e7bb24ed...` 一致；`--version` 正常；**Stage 1 自检
  12 PASSED + 2 配置 WARNING / 0 FAILED**（含 TTY-INPUT PASSED）；
  `--lua` 输出 42；整体移动后运行正常；删除后零残留。

三平台 C33 旅程子集（布局/哈希/Stage 1/工具面/移动/卸载）至此各走一遍：
win32（Server 2008 实机，full）、win64（现代 Windows 宿主，full）、
linux（C7 容器，clean；std/full 的最终 zip 在 WSL2 机，待其回归后走同型
旅程）。剩余：TTY 交互与授权模型往返、Win7 最低面、九包统一汇总（C34）
后评审 Gate R。产品源码零改动。

### 开发状态整理与 C33/C34 工具实现（本轮续接）

本轮基于 `a71bb76`。先核对代码、状态文档、最终 ZIP 和历史证据，开发机基线
suite **699/699**。`src/`、`native/` 和 `release/launcher.lua` 未修改；与 Windows
核心所用 `eea2f1f` 至 HEAD 的产品源码差异为空。新增测试只改变开发机测试集，
不改写包内核心的历史测试数。

发现并修正的验收问题：

| 问题 | 实现与反例 |
| --- | --- |
| 旧旅程只认 clean，无法验收 std/full；当前 clean 实跑 Stage 1 失败 | `journeys.lua` 改为调用 `edition_journey.py`；先审计现代 ZIP 对，再用真实控制 PTY 运行离线 Stage 1，三档共用相同核心验收步骤 |
| 未执行的在线交互可能被排除出失败判定，最终仍打印 PASS | 离线入口在任何包/数据操作前拒绝在线选项；跨平台执行同样非零退出。在线旅程仍由指定已配置目标的 `agent_terminal_smoke.py --online` 执行 |
| version 无成功退出要求；partial 自测没有阶段、失败项和离线请求约束 | Lua 纯验证核与 Python 驱动同步核对；新增失败退出、FAILED/错误阶段/在线请求、缺 Lua/移动及缺零写入观测反例 |
| 旧脚本删除传入 scratch 中固定名称目录 | 使用独占临时子目录；只清理该目录，保留调用方内容；PTY 超时/异常停止并回收自有进程组 |
| 最终包缺可复跑的逐文件/来源/SPDX 与九包汇总 | 新增 `audit_editions.py`：流式校验 ZIP CRC、SHA-256、路径/模式、目录碰撞、目录表 pin、工具版本/入口/许可证/来源、SPDX、同平台核心及全矩阵 |
| Linux clean companion 缺项目许可证和核心依赖 SBOM | 实包审计发现缺项；本轮重装配补 `LICENSE`、核心 SPDX 及精确源码/依赖来源，逐摘要对齐缓存与既有 SBOM pin |
| Windows 两目标 companion 没有完整测试摘要 | 报告明确列出 `core-full-test-summary` 缺项；不使用本机 Linux 或旧源码结果代填 |

工具报告独立保留完整性、证据齐备性与目标资格。`--require-nine` 验收矩阵与核心一致性，
`--require-evidence` 进一步阻止缺 C34 文档的验收；均不授权发布。
离线旅程输出 `scope=offline-core qualification=pending`。

开发文档已整理：CURRENT-STATE 只保留当前快照，TRACKING 只保留剩余项，日期文档和
DEVELOPMENT-HISTORY 保存过程。入口、实施计划、readiness 的任务文件和当前执行手册同步。
根目录 README 和 quickstart 的目标资格待完成标记保留。

本轮新增/改动函数逐项语义核对：参数与返回分支、ZIP/元数据绑定、失败停止、PTY 句柄/
子进程所有权、scratch 清理和回归证据一致。全仓人工语义 Review 的 main 交互内部、
compact 状态机、原生 C 及其他测试辅助代码保留面未在本轮通读，不能宣称已全量完成。

复现脚本、完整注释清单、九包配对及离线旅程报告保存在 `out/review-20261005/`。
最终执行结果与逐包摘要见下。

本轮最终结果：

| 检查 | 结果 |
| --- | --- |
| 完整 Lua suite | **703/703**，开发机 baseline 699 + 本轮四项旅程回归 |
| Python 装配 / 发行校验 / PTY 驱动 | **5/5、13/13、6/6** |
| 注释检查器反例 / 全仓结构 | **15/15；231 文件、5347 声明、0 缺项**；`comment-inventory.json` |
| 契约 / 证明登记 / readiness / 公开文档 | **7739 / 56 / 567 条断言，5 项文档真值**；Gate R 仍 closed |
| 完整 coding readiness | **PASS**；TP-003 453、TP-006 319、TP-008 321、TP-010 5,564,743 条断言、RP-001 PASS；`coding-readiness.log` |
| 九包重装配与实字节校验 | **9/9 完整性通过，44130 个 runtime 成员逐摘要/CRC核对，同平台核心一致**；`nine-edition-audit.json` |
| C34 严格证据状态 | **未完成**：Windows 六包共用的两个目标核心缺完整测试摘要；本机 Linux full 缺 Git HTTP(S) helper；`evidence_complete=false` |
| CentOS 7 容器 clean 离线核心旅程 | **10/10**；Stage 1 13 PASSED / 2 WARNING / 0 FAILED，online-requests=0，scope=offline-core |
| CentOS 7 容器 std 离线核心旅程 | **10/10**；Stage 1 13 PASSED / 2 WARNING / 0 FAILED，online-requests=0，scope=offline-core |
| CentOS 7 容器 full 离线核心旅程 | **10/10**；Stage 1 13 PASSED / 2 WARNING / 0 FAILED，online-requests=0，scope=offline-core |

容器通过资源守卫串行运行，网络关闭、源码挂载只读、以当前用户写入独占 scratch。
驱动由本机已核对的 Python 3.14 full 闭包启动，不增加产品运行时依赖。
三档均核对最终 ZIP 字节；容器仍共享 Fedora 宿主内核，不扩展为裸机资格。

此次本机 full 工具输入的复核发现 Git 早期缓存仅有 file/ssh helper，缺
`git-remote-http` / `git-remote-https`。这与 10-01 在另一构建机完成的
HTTPS 闭包不同；新报告单列 `tool_payload_gaps`，TRACKING 已恢复这一输入刷新项。
完整性与离线核心通过不消除该缺项，也不替代最终在线、升级或工具运行旅程。

本轮九包精确摘要（对应 `out/review-20261005/<target>/`，全部候选未授权）：

| 目标 / 版位 | Runtime 文件数 | Runtime ZIP SHA-256 | Notices ZIP SHA-256 |
| --- | ---: | --- | --- |
| win32-x86 / clean | 1 | `8801134f0d2c82cc9472032de8ecfd9d5c7e0d28a2359d44fee9915b0c451f48` | `5f2192988664ce2f53c92371074dc562ba8c90f981aa690fc2fa787bc0e34ba7` |
| win32-x86 / std | 3016 | `829365ce16979d9b30923c29dc0529727ddcce8ed6256044f08c7f19469a8edb` | `28cd7be5c224ee19f0861b2e81abb38d170e855d9ff101189158b2d319996b27` |
| win32-x86 / full | 12965 | `eb14e737f1d3b707f4be3f9f424db5b7a12e0fe70df598d9775489ea4231d0f7` | `0aa7cc95d83b3e94cc7002fbcf33fc1b6952c3345f8ca874b6260aa25a31e063` |
| win64-x86_64 / clean | 1 | `3af6a1f796beac05931950b9d65ca73f956f98e0827032f787a11c3c9150049f` | `f585547166569171e93ed6382d2c5e6f96179374cae6fd43e68f0390f0628b8f` |
| win64-x86_64 / std | 3015 | `cffc70d7920c8997917f2dfce2baaa30732b2cb3c25fd9ea3287d9dbfa0aae2e` | `531f8061d0a90284a78b3b9a692d044d84b34b4698ecb6a6fd915c517db2ee1f` |
| win64-x86_64 / full | 14648 | `4920acd070a32d38f497464b9eadaf08bab6a2ab9fc6eccbf31b192d143e635d` | `faac333a8a6b46da6f4fb032e01d40a8670d5f0616b1d7c2fc7500b4523e9ddc` |
| linux-x86_64 / clean | 1 | `bc77b0b7d3523fec248041d2e53e4cdc23f71015af055df32457a0dc1c2f04d7` | `69e7c2cfa866605d1b9d109027ba5ccda49677f180d81aa6bb2e0d0a4272ffa2` |
| linux-x86_64 / std | 4508 | `ff756cd3736481efde903b5cc36c6e4453a9649fca5f666b6969f57af3fb3ef7` | `b55789464715e26fd18d08fc66c37c7b434521bdf14565a6567f4d3322dbb0ae` |
| linux-x86_64 / full | 5975 | `a546f45b9cbfaa2dcd3d86d218e3d5ac5b3c52ce504f5467ef662e97ec54519f` | `a790c393d93686b18930af300e5b9e252b151cab1c67fa25c41492171383aa3f` |

每平台输出还含 `editions.json` 与六个 ZIP 的 `SHA256SUMS.txt`。
重装配的 archive SHA-256 与旧 zip 分别记录，不把旧包旅程转写为新 zip 资格。
核心相同及历史源码/构建依据保留在配套元数据和汇总报告中。

### 目标续推：R75 与本地 Git HTTPS 补建

负责人重新提供 DeepSeek 凭据及 DGX Spark 访问，本轮在模式 0700 的
`out/goal-20261005/private/` 下准备配置，文件为 0600；凭据不入库或写入日志。
实际模型发现为 DeepSeek `deepseek-flash` / `deepseek-v4-pro`，本地为
`qwen3.8-27b`；本轮配置选 flash 与 qwen。使用旧 Linux 核心执行完整 Stage 2：
15 项离线通过，14 次在线请求，DeepSeek 7/7、Qwen 6/7。失败的控制探针随后单独
取证，不将单次失败解释成模型服务整体不可用。

**R75**：sglang 的流式工具参数片段在首片真实 ID/name 后，后续明确发送
`id:null` / `function.name:null`。旧适配器把 JSON null 哨兵当成身份变化，
以 `tool-call-id-changed` 提前失败。真实片段保存于私有捕获目录，已将不含凭据的
最小同型输入写入 adapter 回归。修复将后续 null ID/name/arguments 视为没有更新；
首片 null 身份和后续非 null 身份变化仍失败，缺参数仍按原 schema 校验。

- 旧 HEAD 模块跑新反例确实失败：`r75-negative-baseline.log`。
- 修复后 adapter **13/13**：包括整块/单字节分片、首片缺身份和真实身份变化拒绝。
- 完整 Lua suite **705/705**：`lua-suite-r75.log`。
- 人工核对 null 哨兵、原调用绑定、参数预算与终态停止，没有扩大执行准入。

核心真实复跑不能使用旧 `e7bb24ed...`。新增 `source_snapshot.py` 将 Git 维护的
当前工作树与新增文件冻结，排除忽略的构建/凭据目录，逐成员 SHA-256 回验归档，明确
`source_scope=working-tree`，不冒充完整 HEAD。三项回归检查未提交源码、私有目录排除、
符号链接拒绝及输出不覆盖。Linux 重建使用平铺快照
`5146608a973c0393925019ce7da1ea309125ea5d093cf1e3913651eedce5ba39`
（基线 `a71bb76`，387 成员），当前构建尚在执行，结果另记。

**Linux Git 补建**：当前缓存具备 GCC 13.5.0/Make 4.4.1、核心构建的静态
libcurl 8.21.0/Mbed TLS 3.6.7/Expat 2.8.2、GNU 源码中的 zlib。新增
`build_linux_git_https.sh` 用锁源在真实 C7 用户态串行构建。首轮在链接阶段发现
缓存编译器缺 `libpthread_nonshared.a`；从签名 C7 glibc-devel 在独立副本补齐，
保留失败日志后第二轮构建通过，HTTP(S) helper 只导入 libc/libdl/libm/libpthread。
第二轮仍带构建目录 RPATH，已修正脚本关闭该路径并增加 ABI 与 RPATH 拒绝检查，
还需再构建/重定位与正式来源装配。随机源采用 `/dev/urandom`，兼容 C7 3.10 内核，
没有以宿主较新内核的 getrandom 头替代最低面。

本轮这些原始证据在 `out/goal-20261005/`。旧九包保留为上一批候选；R75 三平台
核心、Windows 当前测试摘要、最终交互旅程和全仓语义 Review 继续执行，Gate R 关闭。

R75 续推结果（本批）：

- Linux 核心在签名 C7 7.9.2009 用户态、GCC 4.8.5 配方重建 **PASS**，原生组件
  与 ELF/glibc 闭包通过，目标侧完整 suite **705/705**。当前平铺工作树快照为
  `eb55a6b2730b7c394a76b63f8e3ab793bae0ad4acbdd0588fb7ada07a74a729b`。
  bootstrap 初次缺 file、随后缺 bzip2 的失败日志均保留；构建脚本增加 bzip2/xz 预检。
- 三核心 SHA-256：Linux `c0306272de020ddb78efcf205b445928500b683ec1903da90bbb92084318880e`；
  Win32 `447f9d97dd0b04e6b450cf7e5aeaf448eb17198e70c172b7bf7ecdf2437baa1a`；
  Win64 `87c1853aaf3271f3708e90bac29d8fadfca3777e5ba8e4c3912fc5cf46701977`。
  Windows 构建改用完整工作树快照，含新增未暂存检查/回归，不再手列 cp 清单。
- 新 Linux 核心双模型 Stage 2 **passed、14 次请求、两模型各 7/7**，包括 R75
  之前失败的 Qwen 控制调用，`linux-stage2-r75.log`。
- 完整 coding readiness **PASS**：注释 236 文件 / 5371 声明 / 0 缺项，反例 15/15；
  装配 5/5、ZIP 校验 13/13、离线 PTY 6/6、快照 3/3、审批核对 3/3、compiler
  staging 2/2；四校验器 7739/56/567/5；全部 TP/RP 通过（`coding-readiness-r75.log`）。
- `prepare_linux_full.py` 的源路径含不含 compiler 不应决定裁剪策略：显式 compiler
  模式保留 include/*.a，并纳入 sysroot。原先 prefix 路径会走 runtime 裁剪，已窄修复
  并形成两项回归。正式 full 来源装配、许可证和 ABI/重定位仍待收口。
- 首次 Linux 真实 TTY 交互 **PASS**：多行纯 Ask、Lua `print(6*7)`、一次精确审批、
  执行 stdout=42、结果问答和终端模式恢复（`linux-agent-online.log`）。审批脚本先
  核对可信 action 卡、工具、代码、空 args；不会盲目允许模型提出的其它命令。
- 随机 nonce 跨进程恢复验证**未通过**，不把上述普通交互扩大为多轮恢复。各失败保留：
  Qwen 动作复核约 180 秒后产出不合格 verdict，被 Runtime 记为 uncertain、未执行工具；
  memory-note 可完成但没有可见答案，脚本不应等待不存在的文字块；旧 shell prompt
  引发过早“应用退出”判断已修正；另一轮模型发起第二个 Lua 请求，动作复核拒绝、
  第二个工具未执行，但脚本把不同请求的 ID 误报成同一调用漂移，尚须修正验证口径。
  隔离配置保留 Qwen main，复核模型选择 DeepSeek；所有失败均非“恢复通过”。

上一批九包未重新绑定 R75。Windows 两目标 suite、九包重装配、Git 去 RPATH 与完整
来源装配、随机 token 恢复及升级、全仓人工语义 Review 均继续，发布门保持关闭。

### R75 目标闭环、真实恢复与 v1.0 收尾（续）

负责人按 D-080 撤回节点暂停，继续到 `1.0.0` 正式版。Gate R 仍关闭；下面的
R75 结果绑定开发核心，不转写为最终版本资格。

- Win32 当前核心在 Server 2008 non-R2 实机运行内嵌完整 suite **705/705**，
  核心 `447f9d97dd0b04e6b450cf7e5aeaf448eb17198e70c172b7bf7ecdf2437baa1a`，
  捕获源码归档 `d019f6f973231f1913969528b8a9b9df5d7bdae6ea87bacbe774c05e20dd262e`。
- Win64 当前核心在 Windows 11 x64 26100.33438 实机运行同型 suite **705/705**，
  核心 `87c1853aaf3271f3708e90bac29d8fadfca3777e5ba8e4c3912fc5cf46701977`，
  捕获源码归档 `213889e4ddacf73c198d41187f68d8464649b3ea399eef35597b82de38e2d79b`。
  两目标的日志、环境、源码/核心/日志 SHA-256 写入独立 full-test-summary.json。
- Linux 真实 PTY 在 DeepSeek main/reviewer 下通过中文多行 Ask、精确 Lua 审批、
  结果问答、主任务随机 token 写入、退出、另一进程按 Context hash 恢复并召回 token，
  两次退出终端状态一致。XML 另行核对 **1 个 operation intent/result、1 个成功 Lua
  结果、stdout=42、exit=0、后代 proven-stopped**。
  `linux-durable-evidence.json` 将日志、落盘 XML 与 R75 Linux 核心绑定。
- 脚本修复区分不同请求与实际执行、恢复后的 Ask 续号。此前将 token 写在 Ask 的探针
  不适合检查主任务记忆：`session.lua` 明确只在显式 ask-use 后投影 Ask 内容。
  失败保留为 `linux-agent-durable-deepseek.log`；有效探针为 `*-deepseek-r2.log`。
  终端驱动专项回归 **7/7**。

### R76 压缩取消的日志失败路径

通读 `compact.lua` 的规划、完整 atomic group、摘要绑定、两次尝试、发布、恢复 circuit、
取消/结算、correction 与关闭生命周期，发现 `cancel` 先调用 journal；journal 失败时
`commit` 将 active 清空，随后访问 `active.handle` 抛异常，不能继续清理 Model。

反例在旧实现得到 **11/12**、新增 case 失败；修复先保留原句柄，再提交取消 intent。
拒绝写入、错误 receipt 和抛错三种分支均执行一次原句柄 cancel，返回
`CompactionJournalFailure`，状态为 `Unknown`，旧 manifest 保留且不再接纳请求。
取消和发行版本专项 **29/29**。完整 suite 与最终目标构建仍须后续执行。

main 交互的局部语义复核另修正两处注释：Session staging 收到的是字符串；Context
切换准备函数成功时还返回当前 draft status。main 其余交互、原生层及测试辅助代码的
完整 Review 继续保留，不以本段称为全仓审核完成。

### Linux full 来源与运行闭包

装配已改为显式 Git/编译器输入，保留编译器 headers/static/sysroot；继承 std 的原始
来源绑定，为六个 full-only 工具生成各自对应来源包。Git 包含 HTTP(S)/Perl/curl/TLS/
Expat/zlib 来源，Python 包含 TLS/libffi/sqlite，编译器还含对应 C7 glibc、kernel headers
和旧 libgcc/libstdc++ 来源。新增来源摘要已冻结；三个 C7 SRPM 签名 **OK**。
模板 URL、把文件夹当许可证及共享来源包只有 std 源码的问题已修正。
来源装配专项 **5/5**；全仓结构复核 **237 文件 / 5385 声明 / 0 缺项**，
该清点在 R76/版本更新之前，不能当成后续源码的最终清点。

Git r3 已编译，但 ABI 校验的 awk 续行语法在 C7 上失败，记录保留；语法已修正。
Perl r1 上游测试 **2654 文件中 1 文件失败，1338226 tests**，另有扩展构建 RPATH，
构建未通过。失败调试器用例在无外部网络的 C7 容器独立复跑 **163 项 PASS**，
不修改或剔除上游测试。链接阶段显式清空 LD_RUN_PATH；同时修正 subshell 条件使
configure/build/test/install 任一非零均立即停止。r2 正在隔离网络容器完整复跑；
新 Git/Perl 输入尚未装配或取得工具资格。

运行时、manifest、dependency lock、发行规划与 Windows 候选元数据开始统一 `1.0.0`；
数据 schema 与原生 ABI 标识沿用其现有版本。正式核心和九包尚未构建，不宣称发布。

### R75/R76 候选预发布节点（D-081）

本段是上述工作继续执行后的节点结果。版本入口为 `1.0.0`，Gate R 保持关闭；
负责人明确授权源码推送和候选预发布，正式发布资格条件不变。

| 目标与实测环境 | 当前核心 SHA-256 | 完整 suite |
| --- | --- | --- |
| Linux / CentOS 7.9 用户态、GCC 4.8.5、glibc 2.17 | `406752564e2e68e541fd7f4078500bc3434e65f56a07c647702d1646d5a5fefa` | 706/706 |
| Win32 / Server 2008 non-R2 x64 的 WOW64 | `d681140088429ccfff8cb6a05bdc5ae9a231b4cdb2ef3f4a3851aa4c2045f728` | 706/706 |
| Win64 / Windows 11 x64 26100.33438 | `d90f49960cd03af9a9a77e6c80e02d0d605fcf1839776520841f40acc4563638` | 706/706 |

三核心构建捕获相同的 393 个源码成员。未压缩 tar SHA-256 为
`64afb701973f9be775919f1757312de3b74b55305a354e69aa16155d0f6b224e`；
Linux gzip 为 `19a2bcd9669404943e47fb7cdd866374a1a52e56df04d1d17881656dd0bf87c9`，
Windows gzip 为 `cba5465c0f267cb5f6e23370b4f8cda272120487e31b8ba99f8effa9f8be5051`。
Python/zlib 压缩编码差异没有改变 tar 或成员内容。基线仍是 `a71bb76` 加工作树，
不是该 HEAD 原样源码。包内构建摘要和目标测试日志按各自捕获摘要绑定。

构建后修正打包/审计的 Linux 大小写语义与对应回归、Lua 旅程验证器的旧版本匹配，
补充用户文档和节点记录；产品 Lua、原生 C 和启动/构建入口的捕获源码未变。
开发机完整 suite 在上述辅助代码修改后再次 **706/706**。Windows 目标的 706 项
证据仍绑定捕获的测试树，不声称实机跑过构建后的所有辅助代码改动。

Linux full 最终输入收口：

- C7 的 83 个运行库文件由签名 RPM 所属清单导出并逐摘要复制到 SDK；完整 C7
  glibc/kernel/GCC SRPM 按锁定来源提供。移动路径下 C/C++ 编译运行通过，生成
  程序最高 glibc 要求 2.17。文件/目录 alias 的逃逸、循环、缺失和摘要漂移均拒绝。
- Perl 5.42.3 静态 libxcrypt 4.4.38 闭包构建 PASS。最终上游完整测试为
  **2654 文件 / 1,338,437 项**，libxcrypt **45/45**。早期 debugger、RPATH、
  绝对静态库链接选项导致的失败保留；没有删除或改写上游测试。
- Git 2.55.0 含 HTTP(S) helper 和自带 Perl；十工具及 Git Perl 模块在 C7 的
  只读、带空格路径运行通过，真实 GitHub `ls-remote` HTTPS 成功。
- 首轮九包装配在合法 SDK 头文件 `xt_CONNMARK.h` / `xt_connmark.h` 处拒绝。
  改为 Linux runtime 大小写敏感，Windows 和 companion 保留大小写冲突拒绝，
  精确重复及文件/目录冲突仍拒绝。对应装配 **6/6**、审计 **14/14** 回归通过。
  Linux quickstart 与两语言 README 同步文件系统说明，最终 Linux companion 已刷新。

最终九包及配套 notices 审计 **PASS**：`missing_pairs=[]`、同平台核心一致、
所有成员/来源/模式/SPDX 摘要一致、`evidence_complete=true`，Git helper 缺项清空。
这是 C34 文件证据齐备，不代表完整来源语义审核或目标资格完成。
Linux 三档从待上传 ZIP 在 C7 用户态执行，每档离线核心旅程 **10/10**；
容器共享现代宿主内核，不扩展为 C7 内核实测。

当前 Linux 核心在全新私有部署再跑授权模型：Stage 2 **passed、14 次请求、
DeepSeek/Qwen 各 7/7**。真实 PTY 在 DeepSeek main/reviewer 下通过中文多行 Ask、
精确 Lua 审批、stdout=42、随机 token 主任务写入、跨进程恢复后的 ask-3 召回和
两次终端恢复。独立 XML 核对为 **1 intent / 1 operation result / 1 tool result**，
exit=0、后代 proven-stopped；Context 为 generation=36、47 个事件。
初始驱动因本机没有 `script` 命令未启动产品，失败日志保留；改用已维护的有限 PTY
驱动后通过，不增加系统依赖或放宽模型审批。

本节点最终 coding readiness **PASS**：全仓注释结构 **240 文件 / 5408 声明 /
0 缺项**、反例 15/15；装配 6/6、审计 14/14、离线 PTY 6/6、快照 4/4、审批 7/7、
full staging 10/10、Windows 证据 3/3；四校验器 **7739/56/567/5** 和全部 TP/RP
通过。人工核对本轮修改的签名、错误/句柄所有权、源/路径准入和临时目录清理；
compact 已通读，原生 C 只完成前约 3200 行，main 交互内部和测试辅助全量语义 Review
尚未完成，不以结构数字称为全仓验收通过。

原始日志位于 `out/node-r76-20261005/`；公开字节清单在
[`candidates/1.0.0-preview.20261005.json`](candidates/1.0.0-preview.20261005.json)，
构建/测试/旅程报告随预发布 evidence 包交付。三平台首次配置、完整交互与保留数据的
升级，以及剩余 C32/C33/C34 和语义 Review 留在 TRACKING，正式 Gate R 未开启。
