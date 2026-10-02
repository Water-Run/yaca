# R74 与首批真实模型联网证据

日期：2026-10-02。基于 `0686fb3`。负责人提供两个真实模型端点后，
联网资格自测首次执行；发现并修复适配器缺陷 R74，随后双模型
Stage 2 全项与 Stage 3 通过。密钥仅存隔离部署目录（gitignored），
未入库、未入任何文档。

### R74 与首批真实模型联网证据（10-02）

负责人提供了两个真实模型端点，联网资格自测首次执行：

- **DeepSeek（外网 API）**：deepseek-flash / deepseek-v4-pro，密钥仅存
  隔离部署目录（gitignored），未入库、未入文档。
- **本地 qwen3.8-27b（DGX Spark, sglang, 262k 上下文）**：局域网端点。

**R74（真实缺陷，已修复）**：sglang 系服务器在 OpenAI 响应中显式发送
`"tool_calls": null`（规范允许的缺省拼写）。JSON null 解码为 truthy 哨兵表，
非流式 `message.tool_calls` 与流式 `delta.content/reasoning_summary/tool_calls`
只判 Lua nil 不判 JSON null，哨兵进入数组校验即触发 `openai-tool-calls`
协议错——本地 Qwen 的 WIRE 检查因此失败，DeepSeek（不发送该拼写）不受影响。
窄修复补齐四处 JSON null 守卫；新增 adapter 回归（非流式含 null 的完整
响应 + 流式含 null 的 delta）。修复前专项 11 项中 1 项失败（真实复现），
修复后 **11/11**；完整 suite **699/699**（`full-suite-r74.log`）。

**修复后的真实联网结果**（R74 刷新后的 Win64 核心 `a310ac78...`，
隔离部署于本机 NTFS）：

| 检查 | DeepSeek | 本地 Qwen |
| --- | --- | --- |
| Stage 1（离线 15 项） | **passed**（含配置解析） | 同一部署 |
| Stage 2 七项（transport/auth/wire/stream/tools/control/usage-cancel） | **7/7 PASSED** | **7/7 PASSED** |
| Stage 2 汇总 | `outcome=passed`，两模型合计 **14 次真实联网请求** | — |
| Stage 3（advisory） | **passed**，累计 **17 次真实联网请求**；三项 WARNING 为模型 advisory 按设计保留 | — |

含金量：ST2-MODEL-TOOLS 验证了真实 provider 接受**完整生产工具 schema**
的往返；ST2-MODEL-CONTROL 验证了真实 provider 发起 schema 合法的工具调用
载体；ST2-MODEL-USAGE-CANCEL 验证了类型化取消。这些是 9 月 28 日以来
"真实模型旅程因缺 API 配置未执行"缺口的直接收口。`.ask` 通道的联网路径
由上述 purpose=ask 的请求覆盖；交互式聊天/多轮恢复的旅程仍需 TTY，
按 C33 干净机旅程执行。

### A08/A09 离线旅程在 Win64 实机复跑

`gib_log_journey.lua`（600 MiB 档、9600 块）在本机 Win64 NTFS 以当前
源码运行，win64 lua.exe + R74 核心 DLL；结果见 `a08-journey/journey-win64.log`。

### A08/A09 轮转/截断步骤补齐与 Server 2008 全档复跑（10-02 后续）

旅程脚本从 10 步扩到 **15 步**，补齐 TRACKING 剩余的两项：

- **新增 5 步**：`continuation-issued`（首页发续页令牌，next_line=4）、
  `continuation-follows-offset`（续页从第 4 行起免重扫）、
  `continuation-across-truncation`（就地截断后续页必须 `TargetChanged`）、
  `rotation-fresh-read`（rename+重建后全新读看到新文件头）、
  `continuation-across-rotation`（换 inode 后续页必须 `TargetChanged`）。
  断言依据先从 `src/tools.lua` 核实：续页令牌绑定身份摘要
  （kind/volume/object/size/modified），版本变化即拒。
- **脚本宿主平台化**：分隔符与 `platform_kind` 改由 `package.config`
  推导；fixture 尺寸改为累计写入（32 位 CRT 的 `seek("end")` 在 2.4 GiB
  上返回 -1）；CP936 auto 步骤按 `text_codec.facts.file_default` 分叉——
  传统 ANSI 缺省主机（如中文 locale 的 Server 2008）auto 透明解码为
  设计行为，严格 UTF-8 主机拒绝并给 hint。
- **本地 WSL Linux 600 MiB**：15/15、0 失败
  （`a08-journey/journey-linux-rot.log`）。
- **Server 2008 实机 2.34 GiB 全档**（38400 块，D-077 指定环境）：
  **15/15、0 失败**（`a08-journey/journey-server2008-full.log`）。
  `offset-past-2gib` 首次在真实 2 GiB+ 文件上越过边界；
  `cp936-file-default-decodes ... default=cp936` 证实该机 ANSI 缺省页
  的透明回退。配对为已验证的 win32 组合：32 位 lua.exe（subsystem 5.0）
  + win32 核心 DLL（sha1 `b7960ca5...`，与 09-30 候选逐字节一致；原生
  C 层自该构建后未改，R73/R74 均为纯 Lua 修复）+ 当前源码 Lua 树
  （`4117256`）。x64 lua.exe（PE32+ 6.0）在该机装载被拒
  （Exec format error / 拒绝访问），记录为环境事实，按 D-077 以
  win32 发行目标面完成实机证据。
- 校验：注释 **220 文件 / 5276 声明 / 0 缺项**、四校验器 PASS；产品
  源码零改动（完整 suite 699/699 仍绑定 `4117256`）。

外部资源状态更新：DeepSeek 与本地 Qwen 端点已由负责人提供并接入；
win64 full 的 Python 3.8.20 工具链仍是唯一未装配版位。

### win64 full 解锁第一步：full 锁 URL 修正与 v142 私提取工具链（10-02 第二批）

按"外部依赖常只是缺缓存"的经验（10-01），对 win64 full 剩余项
（Python 3.8.20）开工。本批落地三件事，CPython 构建与装配留待下一批。

**1. full 锁 gmp/mpfr URL 笔误修正（TR 挂账项）**：
`release/full-tool-sources.lock.json` 中
`https://ftp.gnu.org/gmp/...`、`https://ftp.gnu.org/mpfr/...` 补上缺失的
`/gnu/` 段（mpc 原本正确）；两个 URL 实际拉取并核对，SHA-256 与锁内
值逐字节一致（gmp `a3c2b802...`、mpfr `27780735...`）。四校验器复跑
PASS。

**2. VS2019 channel 稳定性复测（历史阻断解除）**：
d16.11 channel manifest 两次获取字节一致
（`ce478cd7...`，134,478 字节）；产品清单 `VisualStudio.vsman` 的
SHA-256 `fb642c3f...` 与 9 月记录的"channel 给出值"一致——当时的
"清单不一致"实为 11,154,648 字节期望值与 channel 实际清单的差异，
本轮以实取字节为准重新锚定（tier-1：清单即微软发布的逐载荷
SHA-256 载体）。

**3. v142 私提取工具链（`fetch_v142_toolchain_windows.py` 入库）**：
本机非管理员、无 VS2019 安装，沿用 py34 的"私提取 SDK"先例（见
`build_python34_windows.py`）：从锚定清单解析 MSVC 14.29.16.11 系列
（编译器 HostX64/TargetX64 + Res、CRT 头、x64 静态库、x64 redist、
Props）与 Win10SDK_10.0.19041 全部 241 个载荷（MSI + 外部 cab），
逐载荷 SHA-256 校验后 vsix 解包、`msiexec /a` 免提权行政安装；
SDK BuildTools nupkg 提供 rc.exe/mt.exe。合计 **264 载荷全部摘要
校验（`v142-toolchain=PASS`）**，产物在
`out/review-20261002/win64-full/toolchain/`（payload-digests.json 留档）。

要点与如实边界：

- MSI Media 表以 `1\<hash>.cab` 相对子目录引用外部 cab，行政安装缺
  介质时**静默跳过文件**且返回成功；取件脚本从 msiexec 日志收割
  Media 引用、硬链接补位后重装，并按每个 MSI 的内容标记（Windows.h、
  kernel32.Lib、ucrt.lib 等）校验完整性——Headers/Libs 的核心内容
  实际分别在 "Store Apps Headers/Libs" MSI 中（Desktop 同名 MSI 仅
  辅助件），标记表已如实反映。
- 16.11 通道不单独发布经典 `lib\x64` 动态导入库（msvcrt/msvcprt/
  oldnames 仅在 `lib\onecore\x64`）；hello 冒烟以 classic 静态库 +
  onecore 导入库链接：**/MT 仅依赖 KERNEL32.dll，/MD 为 KERNEL32 +
  VCRUNTIME140 + api-ms-win-crt-\*（无 api-ms-win-core-\*）**，
  与官方构建同形状（Win7 SP1 + UCRT KB 可解析）。Win7 未打补丁
  目标机的 KB2533623/UCRT 资格验证仍按 TOOL-BUNDLES 注记属 C33。
- win64 核心已随 HEAD（`647c239`）重建 PASS（onedir 核心
  `0acbd828...`；curl 8.21.0 + mbedTLS 3.6.7，subsystem 6.01），
  供 std/full 版位装配；CPython 3.8.20 x64 构建、jq/onig/sqlite/
  busybox x64 交叉构建与 prepare_win64_full.py 装配为下一批。
- Python 3.8.20 源码与 nasm 2.16.03 已取（WSL 缓存）：
  `Python-3.8.20.tgz` 摘要 `9f2d5962...`（python.org，重派生 pin）、
  `nasm-2.16.03-win64.zip` 摘要 `3ee47822...`（nasm.us 未发布官方
  校验值，tier-2 待负责人确认）。perl 取自本机 scoop git。

校验：注释 **221 文件 / 5284 声明 / 0 缺项**（新增取件脚本）、四校验器
PASS；产品源码零改动（完整 suite 699/699 仍绑定 `4117256`，
698→699 为 R74 轮次结果，本轮无源码变化）。

### win64 full 随当前源码装配（10-02 第三批，原构建机）

原构建机（Fedora 44）恢复参与收尾；此前两批在 Windows+WSL2 机完成，该机
当前不可达，本批全部输入由原构建机与一台可达 Windows 主机（192.168.10.104，
Win11 26100，Administrator SSH，业务共用机，如实记录）重新取得或重建。

**D-079 重派生 pin 与原构建机记录对齐**：原构建机 `out/full-payloads-20260929/
payloads.lock.json` 在库，逐项实核——w64devkit-x86 `d05b743d...`、
PortableGit-2.10.0 `89940cca...`（官方值）、w64devkit-x64 `bff1d13f...`、
PortableGit-2.46.2-64 `58ae5c1a...`、busybox-w32 win64 `762f8576...` 全部与
文件实测一致；sqlite-src-3530400.zip `d18fa15a...` 同。D-079 悬置的
"待负责人确认"按"原记录为准"收口：重派生值与原记录一致，无需重装配。

**入库脚本缺陷修复（fetch_v142_toolchain_windows.py，两处）**：

- `SDK_MSI_MARKERS` 三项标记指向 MSI 实际不含有的文件（Desktop Tools
  x64/x86 标 signtool、Modern Versioned 标 midlrt、Non-Versioned 标
  makecert；经 MSI File 表查证 signtool 仅在 Signing Tools MSI）。改为各
  MSI 实际安装且来自外部 cab 的文件（Desktop Tools → tracelog.exe，
  Modern Versioned → AppAnalysis.dll，Non-Versioned → genxbf.dll），介质
  消费证明力不变。
- `admin_install` 由"重跑一次"改为最多四遍循环：单遍 msiexec 只解析部分
  外部介质，Desktop Tools 与 Modern Versioned 均需多遍才完整落盘。
  顺带清除一处 return 后不可达残留。重取后 **v142-toolchain=PASS
  （262 载荷）**。

**MSBuild 16 私提取（fetch_msbuild16_windows.py 入库）**：CPython 3.8 的
PCbuild 需要能理解 v142 targets 的 MSBuild，取
Microsoft.Build（引擎）+ Build.Dependencies + VC.MSBuild.Base（Cpp
targets）+ VC.MSBuild.X64（`Platforms/x64/Platform.props`，MSB8020 的缺失
件）+ VC.MSBuild.X64.v142，全部逐载荷摘要校验。产品清单双锚定：优先
channel 声明的 19,253,644 字节变体（`fb642c3f...`），CDN 旧边带返回的
11,154,648 字节变体（`406969c3...`，9 月"清单不一致"同源）作兜底并要求
每个载荷的 URL 内嵌 SHA-256 与清单声明一致，实际使用变体记入 digest
记录。本轮两台机器分别命中过两个变体，该边界如实保留。

**CPython 3.8.20 x64（build_python38_windows.py 入库）**：v142 提取物 +
私有 MSBuild 在无 VS、无注册表写入、无 PATH 修改下驱动 PCbuild。
MSB8036/8037 以全局属性 `WindowsSDKInstalled=true`、
`WindowsSDK_Desktop_Support=true` 解决——私有提取无 UWP DesignTime
UAP.props，而桌面标记（shared/sdkddkver.h、um/x64/gdi32.lib）实际在位。
externals 按 `get_externals.bat --no-tkinter`（bzip2/sqlite/xz/zlib/libffi
源码 + libffi、openssl-bin-1.1.1w 预构建二进制）；构建机 GitHub 中断一次，
openssl-bin 由原构建机代取（commit `0650c7f...`）上传补齐。修正两处清单
（liblzma 前置库项目、_sqlite3 模块项目）后 **python38-build=PASS**
（`3.8.20 [MSC v.1929 64 bit]`，与 Win7 兼容的 14.29 工具链）。

**便携闭包（stage_python38_windows.py 入库）**：app-local VC142 CRT
（v142 Redist）+ UCRT（SDK Redist）+ openssl-bin DLL + 15 个 .pyd
（3.8 的 _asyncio/_sqlite3 并入核心、sqlite3.dll 单列，与 py34 布局的差异
如实记录）。**python38-portable=PASS 含重定位复验**；vcruntime140 验证为
本地加载；ucrtbase 在新式宿主经 apiset 取系统副本，属宿主事实——未打补丁
Win7 目标机的 KB2533623/UCRT 资格验证按 TOOL-BUNDLES 仍属 C33。

**本机交叉构建（build_win64_full_tools.sh 入库）**：jq 1.8.2（绕过
libtool 直链 `-municode`+onig/.libs 静态归档，复刻 win32 轮已记录的
"-static 重链"修法，导入表仅 KERNEL32/msvcrt/SHLWAPI）、sqlite3 3.53.4、
sqldiff（src 包 tool/sqldiff.c + ext/misc/sqlite3_stdio.c + autoconf
amalgamation）、busybox 复用原构建机 `762f8576...` 记录件、
w64devkit-x64 与 PortableGit-2.46.2-64 解包，**win64-full-tools=PASS**
（wine 冒烟全绿）。

**发现入库缺陷（遗留脚本，未修改、待负责人决定）**：
`build_win64_candidate.sh` 自 8841212 起 launcher 调用缺第 5 参数
`stage`（windows_sources.lua 要求锁定 Lua 源树）、inner.exe 链接缺
`-lshell32`、extractor 链接缺 `-municode`，三处叠加使该遗留脚本无法产出
yaca.exe。本轮核心改用统一脚本 `build_windows_candidate.sh` 的
`win64-x86_64` 目标完成，遗留脚本保持原样入库。

**发现入库缺陷（影响 win32 full，待同修重装配）**：
`prepare_win32_full.py` 对 compiler 的 lib 剪除 `*.a`，链接必挂（实测
`cannot find -lmingw32` 等）——这些归档是链接器输入不是开发冗余。win64 版
`prepare_win64_full.py` 已改为不剪并实测：包内 gcc/g++ 对 hello.c/hello.cpp
编译、链接、运行全通过（gcc-full-ok / gpp-full-ok）。win32 full 需在
WSL2 机（当前不可达）以同修重装配，本缺陷如实挂账。

**win64 核心与装配**：统一脚本随 HEAD（`4a9c4bc`）重建，onefile
`a81a3f32...`、companion notices 齐；本机 wine `--version` =
`yaca 0.1.0 (win64-x86_64)`。`prepare_win64_full.py`（6 参，源码/外部件
分立）+ `package_editions.py --edition full` → **editions=PASS**：

| 产物 | SHA-256 |
| --- | --- |
| `yaca-0.1.0-win64-x86_64-full.zip`（330 MiB，解包 14741 文件） | `ade7ea70b1c03a6e1c5fc716058a0c175f49e29fbd89a581469783987282c369` |
| `yaca-0.1.0-win64-x86_64-full-notices.zip` | `e4d9867a278e343a6b756722014fde7b216ce01b0c21692ffd030274799ed22d` |

解包核验：核心与构建件逐字节一致；10 工具（std 4 + git 2.46.2 /
python3 3.8.20 / sqlite 3.53.4 / jq 1.8.2 / busybox FRP-6075 /
compiler w64devkit-2.9.0-x64）；py3.8.20 模块面（json/csv/re/hashlib/
zipfile/ctypes/encodings/ssl 1.1.1w/sqlite 3.35.5/bz2/lzma）、py2.7.18
（OpenSSL 1.0.2t，官方 2.7.18 Windows 构建自带）、jq 管道往返、sqlite3、
sqldiff 差异输出、busybox、git、gcc/g++ 编译运行、make 4.4.1 全部通过。

**九包 9/9 全部随当前源码装配**（win64 full 本批收口；win32 full 的
compiler lib 修复重装配挂账待 WSL2 机）。校验：注释 **226 文件 / 5300
声明 / 0 缺项**（含 5 个新脚本）、注释检查器反例 15/15、四校验器 PASS
（7739 / 56 / 565 + 5 文档真值）。产品源码零改动（完整 suite 699/699 仍
绑定 `4117256`）。全部产物 candidate-unqualified，Win7 实机旅程属 C33。
