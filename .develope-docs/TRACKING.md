# 剩余开发与验收

更新日期：2026-10-05。当前快照见 [CURRENT-STATE.md](CURRENT-STATE.md)。
核心已实现，继续在当前代码上收尾；C01--C31 是已有实现的任务映射，不重新开工。
九包进度 **9/9 无挂账**（10-02 第三批收口 win64 full；第四批在原构建机
重装配 win32 full 并修复遗留脚本，不再等 WSL2 机）。Gate R 关闭。

## 本轮已收口

10-05：**C33 win32 版位干净机旅程**。最终 win32 full 包（`96fc32cf...`）在
指定实机 Server 2008 自举解包后走完：核心哈希实机复算一致（经包内 py34
hashlib）、非 TTY 零写入拒绝、pty 下如实 ConfigMissing、Stage 1 自检
12 PASSED + 2 配置 WARNING / 0 FAILED、十工具原生实测（git 2.10.0、
py2/py34、jq、make、**gcc 编译链接运行**）、移除 tools 与整体移动的
clean 等价/便携性、出网 TLS 被拦截代理重签时固定 CA 正确拒绝（环境实证）、
卸载零残留。证据见 [10 月 5 日 Review](CODE-REVIEW-2026-10-05.md)。
同日 win64 版位在现代 Windows 宿主走完同型旅程（Win7 最低面仍待）；linux
核心随 HEAD 在 C7 容器重建（suite 699/699、`e7bb24ed...`）并装配 clean
版位（`1088d979...`），C7 容器旅程全绿（Stage 1 12 PASSED/Lua 42/移动/卸载）。
剩余：TTY 交互旅程、持密钥授权模型往返、linux std/full 旅程（最终 zip 在
WSL2 机）、Win7 最低面。

10-02 第四批（原构建机）：**win32 full 无挂账重装配**。prepare_win32_full.py
的 `*.a` 剪除与 win64 同修（`a2c1c7d`）；遗留 build_win64_candidate.sh 三处
缺陷 + windows_package_win64.py 两处豁免缺失修复，实跑端到端验证（
`db52e8ec...`）；win32 核心随 HEAD 统一脚本重建（`acd58d83...`，Server 2008
实机 `--version`/`--lua` 通过）；SDK 7.1 便携提取 + 现行 prepare 重跑（9-22
r2 输入缺免 perl nt.mak 为 ssl 首败根因）+ py2 驱动远端构建
**python34-build=PASS**；msvcr100.dll 经 msi.dll 原生 API 从 python-3.4.4.msi
内嵌 cab 提取（`60c06e0f...` 与 pin 一致；COM 封送破坏字节、行政安装不释放
PrivateCRT 的边界如实记录）；**python34-portable=PASS**；build_win32_full_tools.sh
入库；**editions=PASS**：win32 full zip `96fc32cf...`（12965 文件）。本机
wine + 真 Windows（git 2.10.0/gcc/g++/make 全过；wine i386 git 崩溃为 wine
环境事实）双重验证。注释 227/5303/0、四校验器 PASS、装配单测 5/5。证据见
[10 月 2 日 Review 第四批](CODE-REVIEW-2026-10-02.md)。

10-02 第三批（原构建机）：**win64 full 收口**。D-079 重派生 pin 与原构建机
payloads.lock.json 逐项对齐（w64devkit-x86/x64、两 PortableGit、busybox
w64、sqlite-src）；修复入库取件脚本两处缺陷（MSI 标记表三错、介质需多遍
行政安装）后 v142-toolchain=PASS（262 载荷）；MSBuild 16 私提取入库
（产品清单双锚定 + URL 内嵌哈希交叉验证）；CPython 3.8.20 x64 源码构建
PASS（build_python38_windows.py；MSB8036/8037 全局属性解决；liblzma/
_sqlite3 清单修正）；便携闭包 app-local CRT/UCRT 过重定位复验
（stage_python38_windows.py）；x64 工具交叉构建 + 外部件解包全冒烟
（build_win64_full_tools.sh，jq 静态直链 -municode）；win64 核心随 HEAD
以统一脚本重建（`a81a3f32...`）；prepare_win64_full.py + package_editions
装配 editions=PASS（full zip `ade7ea70...`，14648 文件，gcc/g++ 编译运行
验证）。发现两处入库缺陷：遗留 build_win64_candidate.sh 跑不通（未修改，
核心改走统一脚本）、prepare_win32_full.py 剪 `*.a` 致链接必挂（win64 版
已修，win32 待同修重装配）。注释 226/5300/0、四校验器 PASS，产品源码
零改动。证据见
[10 月 2 日 Review 第三批](CODE-REVIEW-2026-10-02.md)。

10-02 第二批：**win64 full 解锁第一步**。full 锁 gmp/mpfr URL 笔误修正
（`/gnu/` 段补齐，实拉核对 SHA 一致）；VS2019 d16.11 channel 清单字节
稳定复测通过并以实取字节重新锚定；v142 私提取工具链入库
（`fetch_v142_toolchain_windows.py`：264 载荷全部摘要校验，免提权
msiexec /a + MSI 介质补位，内容标记防静默缺件）；hello 冒烟 /MT 仅
KERNEL32、/MD 与官方同形状（无 api-ms-win-core）；win64 核心随 HEAD
（`647c239`）重建 PASS（onedir `0acbd828...`）。注释 221 文件 /
5284 声明 / 0 缺项、四校验器 PASS，产品源码零改动。CPython 3.8.20
构建、x64 工具交叉构建与装配留下一批。证据见
[10 月 2 日 Review 第二批](CODE-REVIEW-2026-10-02.md)。

10-02 后续：A08/A09 剩余两项收口。旅程脚本扩至 15 步（续页签发/跟随、
截断与轮转后的 `TargetChanged` 守卫、轮转后全新读）并宿主平台化
（`package.config` 推导分隔符与 platform_kind、fixture 尺寸累计、CP936
auto 按 `file_default` 分叉）。本地 WSL Linux 600 MiB **15/15**；Server 2008
实机（D-077 指定环境）**2.34 GiB 全档 15/15、0 失败**，win32 配对
（32 位 lua.exe + 核心 DLL `b7960ca5...` + 当前源码 Lua 树）；x64 lua.exe
在该机装载被拒已记录为环境事实。注释 220/5276/0、四校验器 PASS，产品
源码零改动。证据见 [10 月 2 日 Review](CODE-REVIEW-2026-10-02.md)。

10-02 上午：负责人提供 DeepSeek 与本地 sglang qwen3.8-27b 端点。发现
适配器 R74——OpenAI 显式 `"tool_calls": null` 等 null 拼写被判
`openai-tool-calls` 协议错（JSON null 哨兵为 truthy 表，四处守卫只判
Lua nil）。窄修复 + adapter 回归，专项 11/11、完整 suite **699/699**。
R74 刷新 Win64 核心（`a310ac78...`）后：Stage 1 **passed**；Stage 2 两模型
**各 7/7**（合计 14 次真实联网请求，含生产工具 schema 往返与类型化取消）；
Stage 3 **passed**（17 次，advisory WARNING 按设计保留）。A08/A09 600 MiB
离线旅程在 WSL Linux 以当前源码复跑。证据见
[10 月 2 日 Review](CODE-REVIEW-2026-10-02.md)。

此前（10-01 深夜）：四批 Review、8/9 装配等见下。

10 月 1 日第四批收口 main.lua（组合/准入/发布面整读、交互协调器准入与
关闭次序整读）与 text/clock/platform/backend_windows/backend_linux 全册、
ini 解析核、diagnostics 脱敏面、network 重试控制器，无缺陷、源码未改；
证据见[10 月 1 日 Review 第四批](CODE-REVIEW-2026-10-01.md)。

此前三批：第三批按队列收口剩余命名模块（safety/permission/path/json/prompt/
xml/tui/config/cli 全册、main 布局与准入抽检）的人工语义 Review，无缺陷；
微妙推导（json 代理对、path UNC 往返、safety 流扫描器）与既有测试/TP-006
证据交叉核实。同批按 D-078 把两条 Windows 打包路径的 notices 归档统一为
装配布局（core/ + edition.json + SBOM.spdx.json），两路径成员集合 16=16
逐项一致；两目标重打包后装配单测 5/5、注释 219/5266/0、四校验器与完整
suite 698/698 复跑通过。证据见
[10 月 1 日 Review 第三批](CODE-REVIEW-2026-10-01.md)。

此前两批：10 月 1 日按队列收口人工语义 Review 两批：fs/textcodec/process 的错误与资源
收尾、tools 的读写/写发布路径（无缺陷，探针 36/36），以及
model/runtime/session/context 的发布与恢复边界。后者发现 R73：model 活动
队列上限未与适配器响应事件上限绑定（组合根 16386 = 16384+2 只靠魔法数字
维持），终态批量入队失败会使活动悬挂；修复为 `new_activity` 入场校验
`maximum_events + 2 ≤ maximum_queued_events`，专项修复前反例失败、修复后
6/6。完整 suite **698/698**、注释 **219 文件 / 5266 声明 / 0 缺项**、四校验器
与完整 readiness 链（TP-003 453、TP-006 319、TP-008 321、TP-010 5,564,743、
RP-001）PASS。两个 Windows 核心已随 R73 源码刷新（Win32 `52e9dcb2...`、
Win64 `ce92edcf...`），本机 Stage 1 各 12 PASSED / 0 FAILED。证据见
[10 月 1 日 Review](CODE-REVIEW-2026-10-01.md)。

此前内核取消、超时、转向、失败回执及 Ask 关闭已收口；索引读取和 UTF-8/BOM 边界
已修复。完整 Lua suite 在开发机及 Server 2008 均 697/697，完整 readiness 链
PASS；注释反例 15/15、全仓 219 文件 / 5256 声明 / 0 缺项；发行装配 5/5。
Win32/Win64 单文件及 clean 已以本轮源码刷新；普通用户 NTFS metadata 访问权和
父目录身份问题已修复。Server 2008 与本机 Win64 Stage 1 各 12 PASSED / 0 FAILED，
真实 inherited DACL 与长名称发布通过；源码 suite 697/697，注释现为 5256 声明。
证据见[内核审查](KERNEL-REVIEW-2026-09-30.md)与[先前索引/换行复核](CODE-REVIEW-2026-09-30.md)。

这些属于开发机复核，不解除目标或发行门。win64/Linux std、Linux full 装配和
已有 GiB 离线旅程已从待实现队列移出；后续只补其真正缺少的证据。

收尾复核在同一工作区重跑：完整 suite 697/697、内核专项 52/52、注释反例
15/15 与全仓 219 文件 / 5256 声明、四个校验器 PASS、装配单测 5/5，并用已核对
的 Win32 核心经 `package_editions.py` 重装配 clean 成功。日志在
`out/final-verify-20260930/`。

## 下一项与执行顺序

| 优先级 / 任务 | 剩余工作 | 依赖与完成条件 |
| --- | --- | --- |
| P0 · D-075/D-076、F4/F5 | ~~继续人工语义 Review~~ 10-01 四批收口：端口层四模块、model/runtime/session/context 发布/恢复边界、cli/tui/config/json/xml/path/safety/prompt/permission 全册、main.lua 组合/准入/发布面整读+协调器准入/关闭整读、text/clock/platform/backend 全册、ini 解析核、diagnostics 脱敏面、network 重试控制器；除 R73 外无缺陷 | 剩余如实保留：main.lua 交互事件分发内部、compact 状态机内部逐行通读、原生 C 层（有独立探针）、测试辅助代码；后续按缺陷驱动补读，不再作为独立批次 |
| P0 · F4、C32 | ~~刷新 Linux 当前源码产物~~ 已在真实 CentOS 7 用户态（Docker centos:7，GCC 4.8.5-44.el7 / glibc 2.17-326.el7）内以**未修改**的构建脚本完成：PASS、目标端 suite 698/698、单文件 `d06ec961...`；三平台 clean 版位全部绑定 `b5c0c9ff` 源码。物理 CentOS 7 的实机旅程仍属 C33 | Windows 两核心已随 R73 刷新并本机 Stage 1 通过；**win32 的 Server 2008 目标端已复跑**：R73 单文件 Stage 1 12 PASSED / 0 FAILED、当前源码 suite 698/698（见 10-01 Review）。容器共享宿主内核的边界已如实记录 |
| P0 · F3、C33 | ~~std 重装配~~ **9/9 无挂账**：std 3/3 + win32 full（D-079 三档信任分级，pin 已与原构建机记录对齐）+ **linux full（C7 容器内全套重建：可重定位 gcc/g++、含 HTTPS 的 git 2.55.0、自带 ssl/sqlite 的 py314；10 工具 6016 文件验证+重定位冒烟）** + **win64 full（10-02 第三批：CPython 3.8.20 源码构建 + x64 工具交叉构建 + 外部件；10 工具 14648 文件验证 + gcc/g++ 编译运行；zip `ade7ea70...`）**。**Linux Git 传输缺口已收口**（工具自带 https）。win32 full 已于第四批在本机重装配（`96fc32cf...`），不再等 WSL2 机 | 不把旧 Python 安装包改版本；重派生 pin 与原构建机不一致时以原记录为准重装配；qualification=pending，实机旅程属 C33。~~锁内 gmp/mpfr URL 笔误~~ 10-02 已修正并实拉核对 |
| P1 · F2/F4、C32 | 在此前提供的实机补中文/损坏编码输出、取消/进程树、发布/恢复证据 | 按 D-077 使用指定环境；Win7 fs-open 旧 VM 五轮失败保留为历史，不阻断本次收尾 |
| P1 · A08/A09 | ~~余：2.3 GiB 全档目标端复跑与轮转/截断步骤补齐~~ **已收口**（10-02 后续）：旅程扩至 15 步并宿主平台化；本地 Linux 600 MiB 15/15、Server 2008 实机 2.34 GiB 全档 15/15 均 0 失败（win32 配对，见 10-02 Review）。600 MiB 离线旅程与真实模型联网自测此前已绿 | 交互式聊天/多轮恢复的旅程需 TTY，归 C33 |
| P1 · C33 | 最终三平台 clean/std/full 共九包完整干净机旅程 | 以最终 zip 字节验收布局、零表面、同平台核心一致、移除 tools 后核心/Lua、首次配置、Ask/工具、多轮恢复、移动/升级/卸载。**三平台已于 10-05 各走一遍布局/哈希/Stage1/工具面/移动/卸载**（win32=Server 2008 实机 full、win64=现代宿主 full、linux=C7 容器 clean）；余 TTY 交互、授权模型往返、Win7 最低面、linux std/full 旅程（zip 在 WSL2 机） |
| P1 · C33 布局 | ~~收敛两条 Windows 打包路径的 notices 布局~~ 已按 [D-078](DECISIONS.md#d-078-notices-归档统一为装配布局2026-10-01) 收敛为装配布局（core/ + edition.json + SBOM），两路径成员集合 16=16 一致；见[10-01 Review 第三批](CODE-REVIEW-2026-10-01.md#第三批剩余命名模块语义-review-与-c33-notices-布局收敛) | 后续九包干净机旅程按该唯一形状验收 |
| P2 · C34 | 汇总最终证据并复核公开文档与发布门 | 每包 SHA-256、许可证、SBOM、构建/测试摘要对应精确字节；C32/C33/C34 满足后再用独立可审计提交评审 Gate R |

每轮实现按“发现反例 → 窄修复 → 专项回归 → 完整 suite/相应检查 → 人工核对
→ 更新状态与队列”收口。源码发生变化后，相关目标包和旅程重新绑定新源码。

## 外部依赖

| 依赖 | 已知情况 | 解锁后的工作 |
| --- | --- | --- |
| Windows Python 构建环境 | 私有 VC++ 2010 / SDK 路线已完成 Python 3.4.10；14 模块与 app-local CRT 通过，Server 2008 ssl/sqlite/bz2/lzma/ctypes 通过。~~VS2019 channel 清单不一致~~ 10-02 第二批复测字节稳定并以实取字节锚定；v142 私提取工具链入库并 PASS（原构建机重取 262 载荷，标记表/介质多遍两处缺陷已修）；MSBuild 16 私提取入库（双锚定） | ~~完成 Python 3.8.20 的可验证兼容工具链~~ 已完成；~~CPython 3.8.20 x64 构建 + win64 full 装配~~ 10-02 第三批完成（`MSC v.1929`，共用 Windows 主机如实记录） |
| 当前模型配置 | ~~历史批次真实模型旅程因缺 API 配置未执行~~ **已提供**：DeepSeek 外网 API + 本地 sglang qwen3.8-27b（DGX Spark）。密钥在隔离部署目录，不入库 | 已执行 Stage 2/3 双模型联网自测全绿；后续旅程直接使用，不把 mock-provider 或旧包在线结果当当前源码证据 |
| 旧系统完整实机矩阵 | D-077 明确本轮不要求重跑；兼容底线保留 | 按代码、ABI/导入和已有指定实机证明，未测环境不声称实测通过 |
| 原构建机证据与缓存 | 本工作区只留旧 preview 包和部分源码，9 月 28--30 日大部分路径为历史构建机记录 | 恢复锁定缓存、目标机与证据目录；逐项核对摘要后复用，缺失证据保持待验收 |

外部依赖不阻断本地 Review、错误回归和文档整理。涉及实际版本、兼容保证或发行
范围的变化须先形成具体方案和证据，不能以构建暂时失败自动降低承诺。

## 执行约束与记录

- 修改前读 [编码规范](CODING-STANDARD.md)，全部新增/改动函数和类型同步完整注释。
- 构建、完整测试、VM 通过 `.tools/run_with_resource_guard.sh` 串行执行。
- 注释检查使用 Python 3.13 与固定解析器；本轮隔离路径见 Review。全仓结构通过与人工 Review 完成分别记录。
- Git 保持 LF；不改变锁定补丁的期望 SHA 来迁就换行转换。证明源码缓存仍逐项验证 SHA-256。
- 现代开发机、旧候选、当前目标组件和最终发行包的结果分别记录；只按实测缺陷调整既有核心。

当前结果只在 [CURRENT-STATE.md](CURRENT-STATE.md) 维护，剩余项只在本页维护；
缺陷与目标证据进入日期 Review，[DEVELOPMENT-HISTORY.md](DEVELOPMENT-HISTORY.md)
保留历史索引。每完成一项，缩小或删除对应待办，不复制第二套状态表。

C01--C34 定义见[实施计划](IMPLEMENTATION-PLAN.md)，F 分类/A01--A15 来源见
[实施候选](MAJOR-REDESIGN-PLAN-2026-09-22.md#6-必须形成的新验收证据)，任务依赖与
发布门以 [readiness](contracts/readiness.lua) 为准。
