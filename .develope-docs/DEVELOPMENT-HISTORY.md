# 开发历程与历史资料

整理日期：2026-10-08。当前实现看 [CURRENT-STATE.md](CURRENT-STATE.md)，
剩余工作看 [TRACKING.md](TRACKING.md)。本页只导航已有工作和证据。

## 已完成工作的脉络

| 时间 / 节点 | 主要成果 | 证据与适用范围 |
| --- | --- | --- |
| 2026-10-08，R83 键盘重复与控制台模式 | 修复 raw 重复字符/退格、surrogate 配对和字节上限；两指定目标真实控制台各 86 例通过，另有持续 Lua 分配故障与 R82/R81 回归 | [本日 Review](CODE-REVIEW-2026-10-08.md#r83raw-键盘重复utf-16-配对与字节上限)；直接生产函数与自建控制台，不替代最终完整交互/发行包 |
| 2026-10-08，恢复开发与 R82 | 同步 `origin/main` 至 `df38087`，修复 cooked reader 取消失败后的终端/worker 所有权；指定 Windows 目标各 176 例零泄漏 | [本日 Review](CODE-REVIEW-2026-10-08.md)；真实线程及有界 console/wait double，不扩展为真实控制台或最终发行资格 |
| 2026-10-06，R77--R81 与暂停交付 | 修复 Windows reparse 及原生资源/字符串生命周期，三目标从同一冻结源码重建、九包重新装配；按 D-082 交付后暂停 | [本日 Review](CODE-REVIEW-2026-10-06.md)、[节点清单](candidates/1.0.0-preview.20261006.json)；三平台各 706/706，Linux 三档离线核心旅程各 10/10，正式资格和剩余语义 Review 保留 |
| 2026-08，设计与计划 | 产品决定、16 份机读契约、测试夹具、C01--C34 依赖及现代机证明 | [决策](DECISIONS.md)、[实施计划](IMPLEMENTATION-PLAN.md)、[Gate A/B 审计](GATE-AUDIT-2026-08-29.md)；设计就绪不等于发行资格 |
| 2026-09-07 至 09-16，核心与交互收口 | status/export、Prompt 与配置编辑、Context 管理、模型管理/测试、在线 self-test、审批恢复 | [N13 基本可用验收](BASIC-USABILITY-ACCEPTANCE-2026-09-16.md)、[Windows 收尾](WINDOWS-PREVIEW-CLOSEOUT-2026-09-16.md)；对应当时源码与候选 |
| 2026-09-19，三目标候选 | Win32/Win64 构建、CentOS 7 候选、干净机旅程与证据工具 | [双 Windows 验收](TWO-TARGET-ACCEPTANCE-2026-09-19.md)、[CentOS 记录](LINUX-CENTOS7-QUALIFICATION-2026-09-19.md)、[C33/C34](C33-C34-TOOLING-2026-09-19.md)；旧包布局和当时的 Gate R 记录不适用于当前版本 |
| 2026-09-22，范围澄清与调研 | 明确通用 Agent、内嵌 Lua、可选 tools、clean/std/full；阅读三个上游固定提交 | [定位路线](PRODUCT-ROADMAP-2026-09-22.md)、[实施候选](MAJOR-REDESIGN-PLAN-2026-09-22.md)、[上游源码对照](references/agent-loop-source-review-2026-09-22.md)；设计建议中的“待实现”是当日状态 |
| 2026-09-22 至 09-23，便携实现与 Review | Lua 工具、`.ask`、首次引导、PTY/Unicode、进程回收、容量预留、FAT32/身份竞争修复；注释规范与结构覆盖 | [实现记录](PORTABLE-IMPLEMENTATION-2026-09-22.md)、[R01--R22](CODE-REVIEW-2026-09-22.md)；主要落在 `8841212`，最终目标复验和语义 Review 未完成 |
| 2026-09-26，`32d053e` | 原生代码页转换/seek、旧编码读写及输出、区间读取/续页/尾读/搜索 | 当前源码与测试；当次记录完整 suite 646/646，尚未重建目标包 |
| 2026-09-28，恢复基线与 F4 Review | `9aed60f` 整理资料并修复证明摘要漂移；`9724797` 修正编码、UTF-16、长行续页/尾读和搜索完整性 | [R23--R28](CODE-REVIEW-2026-09-28.md#r23--r28-验证范围)、[现代机证明](proofs/modern-2026-08-29/README.md)；不提升发行资格 |
| 2026-09-28，分页修复与资料收口 | `f3a69f2` 修正最终 JSON 分页预算，完成连续翻页回归；同步当前状态和剩余队列，保留旧日志与产物 | [R29](CODE-REVIEW-2026-09-28.md#r29-验证与人工-review)；当次开发机 657/657，目标与九包资格仍待完成 |
| 2026-09-28，范围一致性与失败清理 | `d2bc3a9` 修正无进展读取、预读错误、完成时身份复核、续页版本绑定和模式异常清理 | [R30--R33](CODE-REVIEW-2026-09-28.md#r30--r33-验证与人工-review)；开发机 663/663，真实增长日志与目标资格仍待完成 |
| 2026-09-28，原生转换故障注入 | `18adc05` 修正 Lua 分配失败后的原生资源释放、空输入可用性和 iconv errno 保存；新增可复现 C 探针 | [R34--R36](CODE-REVIEW-2026-09-28.md#r34--r36-原生复核)、[当前复核](CURRENT-STATE.md)；Linux 与 Wine 两架构探针通过，旧目标资格仍待完成 |
| 2026-09-28，Windows 内存错误分类 | `4b54dc8` 修正原生分配失败的错误码与编码失败返回值；扩充原生故障探针 | [R37--R38](CODE-REVIEW-2026-09-28.md#r37--r38-windows-原生分配与错误返回)；Wine 两架构各九个 malloc 失败位置、清理和恢复通过，目标资格仍待完成 |
| 2026-09-28，工具层解码错误 | `ca6d7c5` 保留 read/search、write/patch 的资源与转换器错误，校验原生成功形态，write 候选解码移到发布前 | [R39--R41](CODE-REVIEW-2026-09-28.md#r39--r41-工具层错误传播与写入顺序)；完整 667/667、readiness 通过，目标资格仍待完成 |
| 2026-09-28，XP 当前组件复验 | `8af7397` 修复旧系统有损解码丢字、GB18030 API 标志及严格 UTF-8 校验；旧/新原生组件对照 | [R42--R44](CODE-REVIEW-2026-09-28.md#r42--r44-xp-原生转换与目标对照)；XP 原生探针和源码 suite 667/667 通过，最终单文件/三档包资格待完成 |
| 2026-09-28，编码名称边界 | `21eb615` 拒绝把 HKSCS、EUC、TIS-620 等不同编码直接当成 Windows 代码页 | [R45](CODE-REVIEW-2026-09-28.md#r45-不同字符集的名称边界)；原生 iconv 差异对照、规范化反例及完整 667/667 |
| 2026-09-28，进程输出投影 | `709aa85` 转换器失败和损坏 UTF-16 使用原字节 Base64 与诊断，保留命令真实完成状态；UTF-8 标签与实际相符 | [R46--R47](CODE-REVIEW-2026-09-28.md#r46--r47-进程输出与执行结果)；32 组故障/恢复、脱敏回归、开发机与 XP 完整 670/670 |
| 2026-09-28，文件读取资源与 seek | `5384b8e` 的 fs_read 由 Lua 持有缓冲；新增分配故障和原生字节偏移探针 | [R48 与 seek](CODE-REVIEW-2026-09-28.md#原生-seek-与-r48-文件读取资源)；Linux/Wine/XP 故障恢复与 XP NTFS/FAT32 边界读取；完整 670/670、readiness 通过 |
| 2026-10-01，语义 Review 续推 | 基于 `9188a2e`（与 origin 一致）完成 fs/textcodec/process 错误与资源收尾及 tools 写发布路径人工核对，无缺陷、源码未改；探针 36/36、完整 suite 697/697 | [10-01 Review](CODE-REVIEW-2026-10-01.md)；仅覆盖当日核对子面，不代表全仓 Review 或发行资格完成 |
| 2026-10-01，R73 与内核边界续推 | model/runtime/session/context 发布与恢复边界人工核对；修复 R73（model 活动队列上限未绑定适配器事件上限，终态批量可悬挂）；两 Windows 核心随源码再刷新并本机 Stage 1 通过 | [10-01 Review 第二批](CODE-REVIEW-2026-10-01.md#第二批model--runtime--session--context-的发布与恢复边界r73)；suite 698/698、完整 readiness 链 PASS；Linux 重建仍待 CentOS 7 构建机 |
| 2026-10-01，第三批 Review 与 D-078 | safety/permission/path/json/prompt/xml/tui/config/cli 全册与 main 抽检的人工语义 Review（无缺陷）；两 Windows 打包路径 notices 归档统一为装配布局（D-078），成员集合 16=16 一致 | [10-01 Review 第三批](CODE-REVIEW-2026-10-01.md#第三批剩余命名模块语义-review-与-c33-notices-布局收敛)、[D-078](DECISIONS.md)；装配 5/5、注释 5266/0、四校验器与 698/698 复跑通过 |
| 2026-10-01，第四批 Review 收口 | main.lua 组合/准入/发布面整读、协调器准入与关闭次序整读；text/clock/platform/backend 全册、ini 解析核、diagnostics 脱敏面、network 重试控制器（无缺陷、源码未改）；全仓产品源码 Review 按 10-01 四批口径收口 | [10-01 Review 第四批](CODE-REVIEW-2026-10-01.md#第四批mainlua-组合根与剩余支撑模块)；main 交互事件分发内部、compact 状态机内部、原生 C 层与测试辅助代码为如实保留面 |
| 2026-10-02，模型与九包收口 | R74 修复显式 JSON null；真实双模型 Stage 2/3、Server 2008 2.34 GiB 15 步旅程；源码构建 Python 3.4.10/3.8.20、Windows full 工具与九包装配 | [10-02 Review](CODE-REVIEW-2026-10-02.md)；候选 9/9，目标资格仍待完成 |
| 2026-10-05，目标旅程与发行检查实现 | 三平台已有布局/运行/移动/卸载子集；新增 ZIP 对逐文件与来源/SPDX 校验、九包汇总及真实 PTY 离线核心旅程；修正过期状态与旅程误通过判定 | [10-05 Review](CODE-REVIEW-2026-10-05.md)；补齐 Linux companion 许可证/SBOM，保留 Windows 测试摘要和最终交互旅程缺项 |
| 2026-10-05，R75/R76 与 1.0.0 候选节点 | 修复 Qwen 工具流 null 续片和压缩取消日志失败；三平台核心各 706/706、九包完整性/文件证据齐备；复现 Linux Git/Perl/SDK 闭包、三档 C7 离线 10/10、当前 Linux 双模型各 7/7 与跨进程恢复 | [节点 Review](CODE-REVIEW-2026-10-05.md#r75r76-候选预发布节点d-081)、[候选预发布](https://github.com/Water-Run/yaca/releases/tag/v1.0.0-preview.20261005)；正式 Gate R 关闭，剩余语义 Review 和完整目标旅程继续 |

## 如何解释旧结论

9 月 29--30 日补齐 std 三平台与 Linux full，候选装配达到 7/9；随后修复
附带索引 CRLF 并记录 index/SSE/compaction/terminal 的语义 Review。
这些节点见 [9 月 28 日续接记录](CODE-REVIEW-2026-09-28.md)。
`344f864` 同步后的 R51--R54、开发机 682/682 与 Windows 换行复核见
[9 月 30 日 Review](CODE-REVIEW-2026-09-30.md)；均未提升最终资格。

随后 R55--R72 的取消/超时/Ask 所有权、普通用户 NTFS 发布、父目录绑定及 clean
装配修复，连同 697/697、Server 2008、双 Windows 当前单文件和 Python 3.4.10
源码闭包，见[内核审查](KERNEL-REVIEW-2026-09-30.md)。D-077 缩小了本次实机
矩阵要求，仍保留代码兼容底线与未完成的发行物。收尾复核在同一工作区重跑上述
检查并用已核对核心重装配 win32 clean，同时登记两条 Windows 打包路径的布局
分歧。该布局项后来按 D-078 收口，见 10-01 Review；本段保留的是当时的收尾经过。

`23bf913` 的文档曾按 9 月 19 日的候选与资格口径记录 Gate R 通过。
之后的 D-073 三档发行、D-074 工具面以及新源码需要各自的证据。
当前 yaca 尚未正式发布，机读门为关闭；候选预发布不能沿用旧提交的正式发布措辞。

日期文档中的 N13/N23/N4、测试数、失败、人工修复以及外层 SSH 退出码均按当时
观察保留。R21 的 Lua 源码覆盖验证不能代替最终单文件包，结构注释检查不能代替
全仓人工语义 Review。旧 Windows 包也没有覆盖 9 月 26 日的新代码页转换和 seek。

原 `CURRENT-STATE.md` / `TRACKING.md` 的连续开发记录保存在整理前的提交中：

```sh
git show 32d053e:.develope-docs/CURRENT-STATE.md
git show 32d053e:.develope-docs/TRACKING.md
```

原始日期记录和本地 `out/` 证据保留。`out/` 同时包含构建缓存、虚拟机和日志；
其中的旧产物只在绑定的源码及环境范围内有效。

## 本地证据定位

以下目录不进入 Git；日期记录保留其观察结果和适用范围。失败日志用于复现缺陷，
不删除或覆盖为成功日志。源码基线以对应提交为准。

| 实现节点 | 日志目录 | 主要记录 |
| --- | --- | --- |
| `9aed60f`，恢复开发基线 | `out/development-reset-20260928/` | 既有 suite、注释与证明复核；摘要漂移处理 |
| `9724797`，R23--R28 | `out/f4-review-20260928/` | 编码/长行修复前反例、原生 smoke、完整回归 |
| `f3a69f2`，R29 | `out/page-review-20260928/` | JSON 分页预算的失败与连续翻页验证 |
| `d2bc3a9`，R30--R33 | `out/range-stability-20260928/` | 文件变化、读失败、模式异常及句柄收尾 |
| `18adc05`，R34--R36 | `out/native-codec-review-20260928/` | Linux/Wine 原生故障注入、编码 smoke、完整回归 |
| `18adc05` 源码的资料整理复核 | `out/handoff-baseline-20260928/` | suite 663/663、完整 readiness；注释结构 208 文件 / 5098 声明 / 0 缺项；产品源码未改 |
| R37--R38，Windows 错误分类 | `out/codec-errors-20260928/` | 三平台原生构建和 smoke、Linux/Wine 故障注入；原始九个错误分类反例保留 |
| R39--R41，解码错误传播 | `out/codec-propagation-20260928/` | 读/搜索/写入故障回归、667/667、完整 readiness 和 Linux 编码 smoke |
| R42--R44，XP 转换修复 | `out/codec-xp-20260928/` | 三平台 native 构建、Linux/Wine 探针、XP 旧/新对照与 667/667；原始失败、介质快照和哈希保留 |
| R45，编码名称边界 | `out/codec-alias-20260928/` | 系统 iconv 差异、规范化修复前反例、667/667 与 readiness |
| R46--R47，进程输出投影 | `out/exec-projection-20260928/` | 旧实现重放反例、32 组故障/恢复、UTF-16/UTF-8 与脱敏回归、670/670 |
| 2026-10-01，fs/textcodec/process 与 tools 写侧 Review | `out/review-20261001/` | 专项探针 36/36（probe-run.log）、完整 suite 697/697（full-suite.log）；探针脚本随日志保留 |
| 2026-10-01，R73 修复与核心刷新 | `out/review-20261001/` | R73 修复前后专项（r73-focused.log 前身见 stash 验证）、完整 suite 698/698（full-suite-r73.log）、注释与四校验器、完整 readiness 链（readiness-full.log）、双核心刷新与 Stage 1（windows-refresh-r73.log、win64-stage1-r73.log、win32-stage1-r73.log） |
| 2026-10-01，D-078 notices 收敛 | `out/review-20261001/` | 形状验证（verify_notices_shape.py 输出 CONVERGED）、装配 5/5、注释与四校验器及 698/698 复跑（verify-r2.log、comments-r2.log） |
| 2026-10-01，R73 后 clean 版位重装配 | `out/review-20261001/editions/` | win32/win64 clean 以 R73 核心重装配；载荷摘要逐字节绑定、editions.json 未授权、两路径 notices 16=16（verify_clean_editions.py） |
| 2026-10-01，Server 2008 随 R73 复跑 | `out/review-20261001/server2008/` | R73 win32 单文件 Stage 1 12 PASSED / 0 FAILED、当前源码（0a41727）suite 698/698；纯 Lua ustar 展开器与部署通道记录在案（stage1-r73-win32.log、full-suite-r73.log、expand_ustar.lua） |
| 2026-10-01，Linux 当前源码重建 | `out/review-20261001/linux-r73-build/`、`editions/linux/` | 真实 CentOS 7 用户态（Docker，GCC 4.8.5/glibc 2.17 官方包）内未修改脚本构建 PASS；suite 698/698、冒烟、ELF/GLIBC 基线断言通过；单文件 `d06ec961...`；Linux clean 版位装配并验证（build-summary.txt、verify_linux_clean.py）；容器共享宿主内核边界已记录 |
| 2026-10-01，Windows std 复现装配 | `out/review-20261001/tool-cache/`、`editions/win32-std/`、`editions/win64-std/`、`std-smoke/` | 七锁定源下载验 SHA、msi_inventory 本机产 TSV、原样 std 脚本双目标 staging=PASS、两席装配 4 工具/3016/3015 文件逐摘要验证；本机冒烟 Python/plink/curl/7za 通过（fetch_std_sources.py、verify_std_editions.py）；工具资格 pending，摘要与原构建机不同的边界已记录 |
| 2026-10-01，linux std 复现装配 | `out/review-20261001/linux-std-build/`、`linux-std-staged/`、`editions/linux-std/` | C7 容器内按 prepare 契约重建配方（python2 系统库基线、putty+cmake3、7zz 用 make4.4.1+devtoolset-11、curl 复用核心静态件）；staging=PASS、装配 4 工具/4511 文件逐摘要验证；C7 容器副本冒烟四工具通过（verify_linux_std.py、linux-std-*-entry.sh）；配方选择与 .pyc mtime 教训入档 |
| 2026-10-01，win32 full 装配（D-079） | `out/review-20261001/full-cache/`、`full-smoke/`、`editions/win32-full/` | PortableGit 官方哈希验证、w64devkit/sqlite-src 重派生 pin；jq/sqlite3/sqldiff/busybox-w32 交叉构建；prepare_win32_full.py 入库；10 工具 12478 文件装配验证+全工具冒烟（verify_win32_full.py）；重派生 pin 待原构建机记录确认 |
| 2026-10-02，R74 与真实模型联网 | `out/review-20261001/online-test/`、`a08-journey/` | 双真实端点（DeepSeek flash / 本地 sglang qwen3.8-27b）首次联网自测；修复 R74（OpenAI 显式 null 拼写四处守卫），专项 11/11、完整 suite 699/699；R74 核心 Stage 2 双模型各 7/7（14 次真实请求）、Stage 3 passed（17 次）；A08/A09 600 MiB 旅程 10/10 步 0 失败（WSL Linux，当前源码）。密钥仅存 gitignored 部署目录 |
| 2026-10-02，A08/A09 轮转截断与全档实机 | `out/review-20261001/a08-journey/`（journey-linux-rot.log、journey-server2008-full.log）、Server 2008 `/tmp/yaca-a08-journey/` | 旅程扩至 15 步（续页签发/跟随、截断与轮转 `TargetChanged` 守卫、轮转后全新读）并宿主平台化；本地 Linux 600 MiB 15/15、Server 2008 实机 2.34 GiB 全档 15/15 均 0 失败（win32 配对：32 位 lua.exe + 核心 DLL b7960ca5 + 当前源码 Lua 树；真实越过 2 GiB 偏移；cp936 auto 透明回退 default=cp936）；注释 220/5276/0、四校验器 PASS、产品源码零改动 |
| 2026-10-02，win64 full 工具链解锁（第二批） | `out/review-20261002/win64-full/toolchain/`（payload-digests.json）、`~/.cache/yaca-kernel-build-20261002/win64-core/` | full 锁 gmp/mpfr URL 修正并实拉核对；VS2019 channel 字节稳定复测并以实取锚定；`fetch_v142_toolchain_windows.py` 入库（MSVC 14.29 + SDK 19041 私提取，264 载荷摘要校验，MSI 介质补位 + 内容标记防静默缺件）；hello /MT 仅 KERNEL32、/MD 无 api-ms-win-core；win64 核心随 `647c239` 重建 PASS（onedir `0acbd828...`）；注释 221/5284/0、四校验器 PASS；CPython 3.8.20 构建与装配留下一批 |
| 2026-10-02，win64 full 装配收口（第三批，原构建机） | `out/win64-full-edition-20261002/`、`out/win64-full-tools-20261002/`、`out/win64-core-20261002/`、`out/py38-win64-20261002/`、192.168.10.104 `C:\yaca-build\` | CPython 3.8.20 x64 源码构建 PASS（v142 + 私有 MSBuild 16，`MSC v.1929`；fetch_msbuild16/build_python38/stage_python38 入库）；v142 取件脚本标记表与介质多遍两缺陷修复，重取 262 载荷 PASS；D-079 pin 与原构建机 payloads.lock.json 对齐收口；x64 工具交叉构建 + 外部件解包全冒烟；win64 核心随 HEAD 统一脚本重建（`a81a3f32...`）；editions=PASS，full zip `ade7ea70...`（14648 文件，gcc/g++ 编译运行）；发现挂账缺陷：遗留 build_win64_candidate.sh 跑不通、win32 full 的 compiler lib `*.a` 剪除致链接必挂；注释 226/5300/0、四校验器 PASS |
| 2026-10-02，win32 full 无挂账重装配（第四批，原构建机） | `out/win32-full-edition-20261002/`、`out/win32-full-tools-20261002/`、`out/win32-core-20261002/`、`out/py34-win32-20261002/`、192.168.10.104 `C:\yaca-build\`、Server 2008 `C:\yaca-w32full-test.exe` | prepare_win32_full.py `*.a` 同修；遗留 build_win64_candidate.sh + windows_package_win64.py 缺陷修复实跑验证（`db52e8ec...`）；SDK 7.1 提取 + py34 全管线（MSC v.1600）+ msvcr100 内嵌 cab 提取（`60c06e0f...`）；editions=PASS win32 full `96fc32cf...`（12965 文件，真 Windows git/gcc/g++/make 全验）；Server 2008 实机核心+Lua 抽查；注释 227/5303/0、四校验器 PASS |
| 2026-10-05，C33 win32 版位干净机旅程 | Server 2008 `C:\yaca-c33\`（旅程后零残留） | 最终 win32 full 包（`96fc32cf...`）在指定实机：7za 自举解包；核心哈希经包内 py34 hashlib 复算一致（`acd58d83...`）；非 TTY 零写入拒绝；Stage 1 自检 12 PASSED + 2 配置 WARNING / 0 FAILED；十工具原生实测（git 2.10.0.windows.1、Python 2.7.18、jq、make 4.4.1、gcc 编译链接运行 s2k8-gcc-ok）；移除 tools 与整体移动后核心/Lua/py34 照常；出网 TLS 拦截链（伪 Let's Encrypt CN=YR1）被固定 CA 正确拒绝；卸载零残留 |
| 2026-10-05，C33 win64 版位旅程 | 192.168.10.104 `C:\yaca-build\w64c33\`（零残留） | 最终 win64 full 包（`ade7ea70...`）现代宿主旅程：zip 哈希在机一致、14648 文件全解出（纠正第三批 14741 误计）、核心 `a81a3f32...` 复算一致、Stage 1 计划任务取证 12 PASSED + 2 配置 WARNING / 0 FAILED、py3.8.20/1.1.1w、git 2.46.2、jq、gcc 编译运行、移除 tools/移动/卸载零残留；Win7 最低面仍属 C33 |
| 2026-10-05，linux clean 版位重建与 C7 旅程 | `out/linux-core-20261005/`、`out/linux-clean-edition-20261005/`、Docker centos:7 | 核心随 HEAD（`3a61427`）在 C7 容器（GCC 4.8.5-44.el7）重建 PASS，内嵌 suite 699/699，onefile `e7bb24ed...`；clean 版位 editions=PASS（`1088d979...`，companion 从构建源码树重组）；容器旅程：哈希一致、Stage 1 12 PASSED + 2 配置 WARNING / 0 FAILED、Lua 42、移动/卸载零残留 |
| 2026-10-01，linux full 装配（8/9） | `out/review-20261001/linux-full-staged/`、`editions/linux-full/`、Docker 卷 `yaca-tc` | C7 容器重建：可重定位 gcc 13.5/g++（prefix 自带 CRT 与改写 libc 脚本，任意目录编译运行通过）、git 2.55.0 含 HTTPS（curl+mbedTLS/openssl，getrandom syscall shim）、py3.14 自带 ssl/sqlite（$ORIGIN rpath）、jq/sqlite/busybox1.37（can UAPI shim）；10 工具 6016 文件逐摘要验证+重定位冒烟（verify_linux_full.py、linux-full-smoke.log）；Git 传输缺口收口；全仓暂存修复链入档 |
| `709aa85`，XP 收尾复验 | `out/xp-closeout-20260928/` | 当前 Lua suite 670/670、同一当前 native 编码/故障探针通过；输入快照与 SHA-256 保留 |
| 原生字节偏移 | `out/seek-qualification-20260928/` | 12 个偏移、负值/关闭拒绝、身份一致性；Linux/Wine/XP NTFS/FAT32 |
| R48，文件读取资源 | `out/native-io-review-20260928/` | 旧实现五个缓冲泄漏位置；新 Lua 缓冲、分配故障、同句柄恢复及 OS 读取错误路径 |
| R49--R50，open/create 与进程流资源 | `out/native-open-review-20260928/` | 旧实现三环境各 4 句柄 + 9 缓冲泄漏位置；修正后 0 泄漏、同状态恢复与终端监督通过；670/670 |
| 目标资格批次，四环境实测与 GiB 旅程 | `out/release-20260928/` 等 | 三目标重建、XP/Win7/CentOS/2008 当前组件实测、A08/A09 10/10、clean×3+win32 std 装配 |
| std 三平台装配批次 | `out/editions-*-2026092*` | win64/Linux std 工具树构建+冒烟+装配;九包达六 |
| full 档启动:版本钉定与 Linux 三小工具 | `out/linux-full-20260929/` | busybox 1.36.1/jq 1.8.2/sqlite 3.53.4 容器构建+冒烟;七源 SHA 锁 |
| full 闭包取得(第二批) | `out/full-payloads-20260929/` | PortableGit×2/w64devkit×2 下载入锁;busybox-w32 双架构 mingw 构建冒烟通过 |
| Linux full 编译器闭包自举 | `out/linux-full-20260929/compiler-smoke.log` | GCC13.5/Binutils2.47/Make4.4.1+glibc2.17 sysroot,C/C++/STL 全验证 |
| Linux full 装配(九包 7/9) | `out/editions-linux-full-20260929/` | 10 工具 staged+INDEX 入包;解包全工具冒烟通过 |

XP、Win7、CentOS 7 及 Server 2008 的旧候选路径从各自日期记录查阅；
不因本地仍留有可执行文件或虚拟机就认定当前版本已通过目标验收。

## 深入资料

| 需要追溯的内容 | 入口 |
| --- | --- |
| 当前已确认要求与原话 | [DECISIONS](DECISIONS.md)，特别是 D-072--D-076 |
| 早期设计问题与答复传播 | [登记表](DECISION-REGISTER.md)、[集中问卷](OWNER-QUESTIONS-01.md)、[Batch 06](DISCUSSION-BATCH-06.md)；已答问题不重新进入开发队列 |
| 子系统职责、格式、动作与权限 | [系统图](SYSTEM-MAP.md)、[contracts](contracts/README.md)、[动作注册表](ACTION-REGISTRY.md)、[权限矩阵](TOOL-PERMISSION-MATRIX.md) |
| Context、配置与模型管理的落地 | [Context 续接](CONTEXT-CONTINUE-2026-09-14.md)、[配置修复](CONFIG-REPAIR-2026-09-14.md)、[模型管理](MODEL-MANAGEMENT-2026-09-14.md) |
| 指定旧 Windows 的起点 | [Server 2008 控制台](SERVER2008-CONSOLE-2026-09-14.md)、[9 月 22 日基线复核](BASELINE-REVIEW-2026-09-22.md) |
| 平台证明、发行与工具来源 | [证明目录](proofs/modern-2026-08-29/README.md)、[旧资格手册](QUALIFICATION-RUNBOOK.md)、[工具清单](../release/TOOL-BUNDLES.md) |
| 上游 AgentLoop 的借鉴范围 | [9 月 22 日源码对照](references/agent-loop-source-review-2026-09-22.md)、[早期对照](references/agent-loop-reference-study.md)；提交已固定，不代表持续跟踪上游最新版本 |
| 未来 Web 预留 | [web-tracks](web-tracks/README.md)；不在当前实现范围 |
