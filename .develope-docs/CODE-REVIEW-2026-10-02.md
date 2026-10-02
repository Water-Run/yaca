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
