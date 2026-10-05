# 当前状态

更新日期：2026-10-05。**九包 9/9 无挂账，win32 版位 C33 旅程已走**：10-05 最终包在 Server 2008 实机完成自举解包、核心哈希复算、Stage 1 12 PASSED、十工具原生实测（gcc 编译运行、git 2.10.0）、移除 tools/移动/卸载与固定 CA 拒绝拦截链实证（见 [10 月 5 日 Review](CODE-REVIEW-2026-10-05.md)）。此前：第四批在
原构建机重装配 win32 full（py34 3.4.10 源码构建 + `*.a` 修复后的 10 工具，
zip `96fc32cf...`，真 Windows 与 Server 2008 实机抽查通过）并修复遗留
build_win64_candidate.sh 三处缺陷（实跑验证恢复可用）；win32 full 不再等
WSL2 机。此前第三批收口 win64 full——CPython 3.8.20 x64 以 v142 私提取工具链 + 私有
MSBuild 16 在共用 Windows 主机上源码构建 PASS（`MSC v.1929`），便携闭包
含 app-local VC142 CRT/UCRT 并过重定位复验；jq/sqlite/sqldiff/busybox
x64 交叉构建与 w64devkit-x64/PortableGit-2.46.2 解包全冒烟；D-079 的
重派生 pin 与原构建机 payloads.lock.json 逐项对齐收口。发现并修复
v142 取件脚本标记表/介质多遍两处缺陷；发现两处入库缺陷挂账：遗留脚本
`build_win64_candidate.sh` 跑不通（核心已改用统一脚本 win64-x86_64 目标
重建，onefile `a81a3f32...`）、`prepare_win32_full.py` 剪除 compiler
lib 的 `*.a` 致链接必挂（win32 full 待同修重装配，WSL2 机当前不可达）。
装配产物 `yaca-0.1.0-win64-x86_64-full.zip` = `ade7ea70...`。注释 226
文件 / 5300 声明 / 0 缺项、四校验器 PASS，产品源码零改动。详见
[10 月 2 日 Review 第三批](CODE-REVIEW-2026-10-02.md)。

此前（10-02 第二批）：**win64 full 工具链已解锁**：full 锁 gmp/mpfr URL
笔误修正并实拉核对；VS2019 d16.11 channel 清单字节稳定复测后以实取字节
锚定；MSVC 14.29（v142）+ Win10 SDK 19041 私提取工具链入库
（`fetch_v142_toolchain_windows.py`，264 载荷全部摘要校验，免提权
msiexec /a + MSI 介质补位），hello 冒烟 /MT、/MD 导入表与官方构建同形状；
win64 核心随 HEAD（`647c239`）重建 PASS。余 CPython 3.8.20 x64 构建、
x64 工具件与装配。注释 **221 文件 / 5284 声明 / 0 缺项**、四校验器 PASS，
产品源码零改动。详见
[10 月 2 日 Review 第二批](CODE-REVIEW-2026-10-02.md)。

此前（10-02 第一批）：**首批真实模型联网证据已落档**：负责人提供
DeepSeek 与本地 sglang qwen3.8-27b 端点后，发现并修复适配器 R74（OpenAI
显式 null 拼写被误判协议错），修复后双模型 Stage 2 七项全过
（14 次真实联网请求）、Stage 3 passed（累计 17 次）。A08/A09 旅程随后
补齐轮转/截断 5 步并宿主平台化：本地 Linux 600 MiB **15/15**、
Server 2008 实机 **2.34 GiB 全档 15/15、0 失败**（win32 配对，真实越过
2 GiB 偏移边界）。详见
[10 月 2 日 Review](CODE-REVIEW-2026-10-02.md)。此前（2026-10-01）四批人工
语义 Review：fs/textcodec/process 错误与资源收尾及 tools 写发布路径（无缺陷，
探针 36/36）；model/runtime/session/context 的发布与恢复边界（发现并修复 R73
跨端口边界缺陷）；剩余命名模块（safety/permission/path/json/prompt/xml/tui/
config/cli 全册，无缺陷）；main.lua 组合/准入/发布面整读与协调器准入/关闭
整读、text/clock/platform/backend 全册、ini 解析核、diagnostics 脱敏面、
network 重试控制器（无缺陷）。完整 suite **698/698**、注释 219 文件 /
5266 声明 / 0 缺项、四校验器与完整 coding readiness 链（TP-003/006/008/010、
RP-001）PASS。两个 Windows 核心已随 R73 源码刷新并在本机 Stage 1 通过；两
Windows 打包路径的 notices 归档已按 [D-078](DECISIONS.md#d-078-notices-归档统一为装配布局2026-10-01)
统一为装配布局；clean 版位以 R73 核心重装配并验证。Server 2008 目标端已随
R73 复跑：单文件 Stage 1 12 PASSED / 0 FAILED、当前源码 suite **698/698**
（`out/review-20261001/server2008/`）。Linux 当前源码已在真实 CentOS 7
用户态（Docker centos:7，未修改构建脚本）重建：PASS、目标端 suite **698/698**、
单文件 `d06ec9618c73aead0f90bd2d018da9cb9839da80794487ded2c8945f381b5c1c`，
三平台 clean 版位全部绑定 `b5c0c9ff` 源码（`out/review-20261001/`）。
Windows std 两席随后按锁定源码复现装配并本机冒烟（Python 2.7.18 /
plink 0.85 / curl 8.21.0 / 7za 26.03，qualification=pending）；linux std
再于真实 CentOS 7 用户态按重建配方复现装配并在 C7 容器实跑冒烟
（py2-ok OpenSSL 1.0.2k / plink 0.85 / curl 8.21.0 / 7zz 26.03）；
win32 full 按 D-079 三档信任分级取得外部件并装配（10 工具 12478 文件
验证 + git 2.10.0/py34/GCC 16.1/Make 4.4.1/jq/sqlite/busybox 全冒烟）；
linux full 在 C7 容器内整套重建（可重定位 gcc/g++、含 HTTPS 的 git
2.55.0、自带 ssl/sqlite 的 py3.14 等，10 工具 6016 文件验证 + 全部
工具重定位冒烟；Git 传输缺口就此收口）。
**九包 9/9 绑定当前源码**（clean 3/3、std 3/3、win32 full（第四批
`96fc32cf...`）、linux full、win64 full（第三批 `ade7ea70...`），无挂账）。
证据见
[10 月 1 日 Review](CODE-REVIEW-2026-10-01.md)。9 月 30 日轮修复附带软件
索引及内核取消、超时、失败回执和 Ask 关闭路径，提交脉络见
[开发历程](DEVELOPMENT-HISTORY.md)，证据见
[9 月 30 日复核](CODE-REVIEW-2026-09-30.md)与[内核审查](KERNEL-REVIEW-2026-09-30.md)。
实机范围按 [D-077](DECISIONS.md#d-077-本次收尾的兼容检查与实机范围2026-09-30)，
不再要求本次重跑整个旧系统实机/VM 矩阵。

**核心已实现，目标资格验证待完成。** 机读阶段为 `implemented-unqualified`，
Release Gate R 为 `closed`，`release_authorized=false`。依据是
[readiness](contracts/readiness.lua)、[发行清单](../release/manifest.lua)和
[依赖锁](../release/dependencies.lock)。旧源码或旧包通过不能转为当前源码资格。

## 已有实现

| 范围 | 当前能力 | 实现或记录 |
| --- | --- | --- |
| Agent 核心 | 单 Agent、串行工具、OpenAI/Anthropic 两协议、审批、流式输出、取消、压缩、Context 持久化与恢复 | `src/runtime.lua`、`model.lua`、`session.lua`、`context.lua` |
| 交互与管理 | 首次配置、配置/模型/Context 管理、status/export、自检；`.ask` 纯问答 | `src/main.lua`、`cli.lua`、`terminal.lua` |
| 工具面 | 八个基础工具及正式内嵌 `lua` 工具；共用权限、预算、取消与收尾 | `src/tools.lua`、`process.lua`、`release/launcher.lua` |
| 附带软件 | `tools/INDEX.txt` 说明、模型环境投影和 `.software` 本地查询/问答；通过 exec/lua 使用程序 | `src/bundled.lua`；本轮统一完整读取、16 KiB 上限与无进展拒绝 |
| 便携发行 | clean/std/full 装配器；同平台核心相同，可选 tools；历史候选已装配 7/9 | [工具清单](../release/TOOL-BUNDLES.md)、`release/tool-bundles.json` |
| 旧终端与原生层 | Cygwin PTY、Unicode 路径/参数/输出、异步 stdin、进程树回收、FAT32 修复 | [便携实现](PORTABLE-IMPLEMENTATION-2026-09-22.md)、[R01--R22](CODE-REVIEW-2026-09-22.md) |
| 旧编码与资源 | 原生代码页转换、无损写回、exec 原字节保留；Lua 分配失败时原生资源清理 | `native/yaca_text.h`、`src/textcodec.lua`；[R34--R50](CODE-REVIEW-2026-09-28.md) |
| 大文件与分页 | 超过 16 MiB 时区间读取、有界搜索、尾读、续页和长行截断；身份/版本变化明确失败 | `src/tools.lua`、原生 seek；[R23--R33](CODE-REVIEW-2026-09-28.md) |
| 开发检查 | 全仓注释结构检查；支持 CRLF 文件头；Git 保持脚本、补丁和 golden 的 LF 字节 | [编码规范](CODING-STANDARD.md)、`.gitattributes`；人工语义 Review 未全量完成 |

## 本轮开发机复核

环境为 Windows 宿主上的 Ubuntu 24.04.4 / WSL2，内核
`6.6.87.2-microsoft-standard-WSL2`。Lua 5.5.1 由锁定 SHA-256 的源码本地构建，
完整 Lua suite 通过资源守卫串行运行。注释检查使用隔离的 Python 3.13.15
和 `.tools/comment_check_requirements.txt` 的固定解析器。

| 检查 | 本轮结果 |
| --- | --- |
| 内核状态机专项回归 | 52/52；覆盖取消/转向/超时/回执丢失、旧响应和 Ask 关闭 |
| 索引及模型环境专项回归 | 25/25；含 EOF 上限、无进展、完整读取、BOM 和损坏 UTF-8 |
| 完整 Lua suite | 开发机及 Server 2008 当前源码均 697/697 通过 |
| 注释检查器反例 | 15/15 通过；新增六种文件后缀的 CRLF 正反例 |
| 全仓注释结构 | 219 文件、5256 声明、0 缺项；包含新增原生最小访问权和目录身份 helper |
| 契约 / 证明登记 / readiness / 公开文档 | 7739 / 56 / 565 条断言及 5 项文档真值检查通过；Gate R 仍关闭 |
| 完整 coding readiness | TP-003/006/008/010、RP-001 全链 PASS；TP-010 为 5,564,779 条断言 |
| 发行装配 | Python 5/5；修复无 tool-inputs 的独立 clean 装配错误 |
| 收尾复核（同一工作区重跑） | 完整 suite 697/697、内核专项 52/52、四个校验器 PASS、注释 219 文件 / 5256 声明、装配单测 5/5；用已核对核心经 `package_editions.py` 重装配 win32-x86 clean 成功 |
| 人工语义核对 | 本轮内核状态转换、所有权、失败停止、索引及回归夹具已核对；不扩展为全仓完成 |

日志与完整注释清单在 `out/review-20260930/`。已重建 Win32 当前单文件/clean，
在指定 Server 2008（192.168.5.10）通过 697/697；Stage 1 在建立隔离数据目录后
12 PASSED / 0 FAILED，配置未初始化与非 TTY 警告如实保留，online-requests=0。
后续普通用户 Win64 原子发布与父目录时间戳缺陷已修复，两种 Windows 核心再次刷新；
Win32 SHA-256 为 `857680865d91c0a8cbc7f1540717c8c51631392a8cf018913b3b60150cca0a04`，
Win64 为 `a75a106cfecd7a3b053f0e895baf39bb7ea169655530868bbdab86f3fadb72f3`。
Win64 本机 Stage 1 也是 12 PASSED / 0 FAILED，实际 inherited DACL、长名称
rename/replace/delete 与 XML smoke 通过；Server 2008 刷新后的 Stage 1 再通过。
10 月 1 日 R73 修复 `model.lua` 后两个核心按同一流程再刷新：Win32
`52e9dcb260c24c05ff03de6611c7b18150caa4506423f6149bcffe3225fbfdea`、Win64
`ce92edcfe77986b6aa6ddeb383a614399fed9841d532ed8c3db013dd8de5b478`，本机
Stage 1 各 12 PASSED / 0 FAILED；win32 核心随后在指定 Server 2008 复跑
Stage 1（12 PASSED / 0 FAILED）与当前源码 suite（698/698）。上两个摘要
保留为上一源码代的证据。
Linux / 本机 Win64 / Server 2008 Win32 最终原生故障探针均 0 句柄/缓冲泄漏，
编码资源、严格 Unicode 与同状态恢复通过，原始结果在内核审查中分别记录。
本轮不补 XP/Win7/CentOS 7 的实机矩阵，未执行模型联网旅程。
历史 Fedora 开发机 readiness 和目标组件证据保留在
[9 月 28 日 Review](CODE-REVIEW-2026-09-28.md)；两批环境与证据分别记录。

收尾复核在同一工作区重跑，日志在 `out/final-verify-20260930/`。契约校验的
7739 计数含 xmllint 外部 Relax NG 检查；本机未安装该工具时为 7738 并打印
跳过说明，两者都不是失败。用已核对的 Win32 核心经 `.tools/package_editions.py`
重装配 clean 得到 `editions=PASS`：clean 载荷与已做 Stage 1 的候选件逐字节相同，
归档 SHA-256 不同（装配器写入固定时间戳，候选构建脚本保留真实 mtime）；notices
归档的成员形状也不同，见 TRACKING 的 C33 布局项。
本工作区没有 Win64 的 companion notices 与 Linux 核心，因此没有在这里
重装配这两项。

## 目标与发行候选

以下为截至 `344f864` 的历史记录，原始日志主要位于原构建机的 `out/`。
本工作区没有这些批次的完整缓存、VM 与最终包；本轮修复后仍需统一源码重建。

| 平台 | clean | std | full | 证据与缺口 |
| --- | --- | --- | --- | --- |
| win32-x86 | **当前源码已装配**（统一脚本随 HEAD 重建 `acd58d83...`，Server 2008 实机 `--version`+`--lua` 通过） | **当前源码已装配**（本机暂存逐摘要复验 3014 文件 0 坏） | **当前源码已装配**（10-02 第四批：py34 3.4.10 源码构建 + MSVCRT 提取 + `*.a` 修复；10 工具 12965 文件，真 Windows gcc/g++/git 全验，zip `96fc32cf...`） | XP 当前组件 suite 670/670、原生探针与 stage-1；实机旅程属 C33 |
| win64-x86_64 | **当前源码已装配**（R73 核心，本机 Stage 1 12 PASSED） | **当前源码已装配**（锁定源码复现，4 工具，本机冒烟；qualification=pending） | **当前源码已装配**（10-02 第三批：v142+MSBuild16 私提取、CPython 3.8.20 源码构建、x64 工具交叉构建 + 外部件解包；10 工具 14741 文件验证 + gcc/g++ 编译运行；zip `ade7ea70...`） | Win7 当前组件 suite 670/670、codec/进程流/seek 与 stage-1；fs-open 真机复跑仍缺。KB2533623/UCRT 未打补丁机资格属 C33 |
| linux-x86_64 | **当前源码已装配**（CentOS 7 用户态重建，suite 698/698，单文件 `d06ec961...`） | **当前源码已装配**（C7 容器复现，4 工具 C7 实跑冒烟；qualification=pending） | **当前源码已装配**（C7 容器重建可重定位 gcc/g++、含 HTTPS 的 git 2.55.0、自带 ssl/sqlite 的 py3.14、jq/sqlite/busybox；10 工具 6016 文件验证+重定位冒烟） | 三故障探针、真实 2.3 GiB 旅程 10/10 为旧源码证据；物理 CentOS 7 实机旅程待补。工具 git 已自带 https，传输缺口收口 |

**7/9 是候选装配进度，不是最终资格通过数。** 附带软件功能后来使历史开发机
suite 增至 678 项；本轮为 697 项。目标端旧 670 项对应早期源码，不能写成已覆盖
后续附带软件修复。详细记录见[目标及工具批次](CODE-REVIEW-2026-09-28.md)。

人工语义 Review 已记录 R01--R73 各批、附带软件特性、index.lua、network.lua 的
SSE 子面、compact.lua 的断路器/恢复子面、terminal.lua，以及 10 月 1 日四批：
fs/textcodec/process 错误与资源收尾、tools 写发布路径（无缺陷，探针 36/36）、
model/runtime/session/context 的发布与恢复边界（R73 修复）、剩余命名模块全册
及 main.lua 组合/准入/发布面、text/clock/platform/backend、ini 解析核、
diagnostics 脱敏面、network 重试控制器（无缺陷）。如实保留的剩余面：main.lua
交互事件分发内部、compact 状态机内部逐行通读、原生 C 层（有独立探针）与
测试辅助代码。

## 当前剩余与边界

- 全仓语义 Review 已按 10-01 四批口径收口（R73 为唯一缺陷）；剩余面按缺陷驱动
  补读。下一步为三目标统一重建与目标回归——其中 Linux 重建与 win32 目标端
  复跑依赖外部环境。
- Python 3.4.10 与 3.8.20 均已源码构建并装配（第四/第三批）；Linux Git
  传输能力已由 linux full 自带 https 收口；遗留脚本
  `build_win64_candidate.sh` 已修复并实跑验证（第四批）。
- 按 D-077 核对兼容源码、ABI 和导入闭包；用已有指定实机补相应运行证据。
- A08/A09 已收口：CentOS 7 离线大文件证据、轮转/截断步骤、真实模型联网自测
  与 Server 2008 2.34 GiB 全档复跑（10-02）均已落档；交互式聊天/多轮恢复
  旅程需 TTY，归 C33。
- 最终九包的布局、核心一致性、干净机旅程、SHA-256、许可证与 SBOM，之后再评审 Gate R。

大文件单次扫描预算为 256 MiB，不计算整文件摘要；超过 16 MiB 的文件不能
write/patch。`partial_start`、`truncated_lines` 和续页信息明确表示部分结果。
文件身份或版本变化返回 `TargetChanged`；身份复核不是文件系统快照，持续增长与
旧文件系统时间精度仍需目标验收。

执行顺序、依赖与完成条件统一见 [TRACKING.md](TRACKING.md)。
