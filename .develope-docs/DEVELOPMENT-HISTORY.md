# 开发历程与历史资料

整理日期：2026-09-30。当前实现看 [CURRENT-STATE.md](CURRENT-STATE.md)，
剩余工作看 [TRACKING.md](TRACKING.md)。本页只导航已有工作和证据。

## 已完成工作的脉络

| 时间 / 节点 | 主要成果 | 证据与适用范围 |
| --- | --- | --- |
| 2026-08，设计与计划 | 产品决定、16 份机读契约、测试夹具、C01--C34 依赖及现代机证明 | [决策](DECISIONS.md)、[实施计划](IMPLEMENTATION-PLAN.md)、[Gate A/B 审计](GATE-AUDIT-2026-08-29.md)；设计就绪不等于发行资格 |
| 2026-09-07 至 09-16，核心与交互收口 | status/export、Prompt 与配置编辑、Context 管理、模型管理/测试、在线 self-test、审批恢复 | [N13 基本可用验收](BASIC-USABILITY-ACCEPTANCE-2026-09-16.md)、[Windows 收尾](WINDOWS-PREVIEW-CLOSEOUT-2026-09-16.md)；对应当时源码与候选 |
| 2026-09-19，三目标候选 | Win32/Win64 构建、CentOS 7 候选、干净机旅程与证据工具 | [双 Windows 验收](TWO-TARGET-ACCEPTANCE-2026-09-19.md)、[CentOS 记录](LINUX-CENTOS7-QUALIFICATION-2026-09-19.md)、[C33/C34](C33-C34-TOOLING-2026-09-19.md)；旧包布局和当时的 Gate R 记录不适用于当前版本 |
| 2026-09-22，范围澄清与调研 | 明确通用 Agent、内嵌 Lua、可选 tools、clean/std/full；阅读三个上游固定提交 | [定位路线](PRODUCT-ROADMAP-2026-09-22.md)、[实施候选](MAJOR-REDESIGN-PLAN-2026-09-22.md)、[上游源码对照](references/agent-loop-source-review-2026-09-22.md)；设计建议中的“待实现”是当日状态 |
| 2026-09-22 至 09-23，便携实现与 Review | Lua 工具、`.ask`、首次引导、PTY/Unicode、进程回收、容量预留、FAT32/身份竞争修复；注释规范与结构覆盖 | [实现记录](PORTABLE-IMPLEMENTATION-2026-09-22.md)、[R01--R22](CODE-REVIEW-2026-09-22.md)；主要落在 `8841212`，最终目标复验和语义 Review 未完成 |
| 2026-09-26，`32d053e` | 原生代码页转换/seek、旧编码读写及输出、区间读取/续页/尾读/搜索 | 当前源码与测试；当次记录完整 suite 646/646，尚未重建目标包 |
| 2026-09-28，恢复基线与 F4 Review | `9aed60f` 整理资料并修复证明摘要漂移；`9724797` 修正编码、UTF-16、长行续页/尾读和搜索完整性 | [R23--R28](CODE-REVIEW-2026-09-28.md#r23--r28-验证范围)、[现代机证明](proofs/modern-2026-08-29/README.md)；不提升发行资格 |
| 2026-09-28，分页修复与资料收口 | `f3a69f2` 修正最终 JSON 分页预算，完成连续翻页回归；同步当前状态和剩余队列，保留旧日志与产物 | [R29](CODE-REVIEW-2026-09-28.md#r29-验证与人工-review)；当次开发机 657/657，目标与九包资格仍待完成 |
| 2026-09-28，范围一致性与失败清理 | `d2bc3a9` 修正无进展读取、预读错误、完成时身份复核、续页版本绑定和模式异常清理 | [R30--R33](CODE-REVIEW-2026-09-28.md#r30--r33-验证与人工-review)；开发机 663/663，真实增长日志与目标资格仍待完成 |
| 2026-09-28，原生转换故障注入 | `18adc05` 修正 Lua 分配失败后的原生资源释放、空输入可用性和 iconv errno 保存；新增可复现 C 探针 | [R34--R36](CODE-REVIEW-2026-09-28.md#r34--r36-原生复核)、[当前复核](CURRENT-STATE.md#最新基线复核)；Linux 与 Wine 两架构探针通过，旧目标资格仍待完成 |
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
分歧；该项留在 [TRACKING.md](TRACKING.md) 的 C33 布局待办，未转为已完成。

`23bf913` 的文档曾按 9 月 19 日的候选与资格口径记录 Gate R 通过。
之后的 D-073 三档发行、D-074 工具面以及新源码需要各自的证据。
当前 yaca 尚未发布，机读门为关闭；不能沿用旧提交的发布措辞。

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
