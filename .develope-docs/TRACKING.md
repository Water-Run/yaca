# 剩余开发与验收

更新日期：2026-10-01。当前快照见 [CURRENT-STATE.md](CURRENT-STATE.md)。
核心已实现，继续在当前代码上收尾；C01--C31 是已有实现的任务映射，不重新开工。
历史候选装配进度为 clean×3、std×3、Linux full，共 **7/9**；本轮新增源码修复
需要重新进入目标构建与验收。Gate R 关闭。

## 本轮已收口

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
| P0 · F3、C33 | ~~std 重装配~~ **8/9 已随当前源码装配**：std 3/3 + win32 full（D-079 三档信任分级，pin 待负责人确认）+ **linux full（C7 容器内全套重建：可重定位 gcc/g++、含 HTTPS 的 git 2.55.0、自带 ssl/sqlite 的 py314；10 工具 6016 文件验证+重定位冒烟）**。唯余 win64 full（Python 3.8.20 工具链）。**Linux Git 传输缺口已收口**（工具自带 https） | 不把旧 Python 安装包改版本；重派生 pin 与原构建机不一致时以原记录为准重装配；qualification=pending，实机旅程属 C33。锁内 gmp/mpfr/mpc URL 笔误（缺 /gnu/）待修正 |
| P1 · F2/F4、C32 | 在此前提供的实机补中文/损坏编码输出、取消/进程树、发布/恢复证据 | 按 D-077 使用指定环境；Win7 fs-open 旧 VM 五轮失败保留为历史，不阻断本次收尾 |
| P1 · A08/A09 | 在已有 2.3 GiB 离线旅程上补轮转/截断、旧代码页输出与模型使用续页 | 当前重建产物及显式联网条件就绪；检查增长/换文件的错误与续页行为，不重复宣称离线用例证明真实模型使用 |
| P1 · C33 | 最终三平台 clean/std/full 共九包完整干净机旅程 | 以最终 zip 字节验收布局、零表面、同平台核心一致、移除 tools 后核心/Lua、首次配置、Ask/工具、多轮恢复、移动/升级/卸载 |
| P1 · C33 布局 | ~~收敛两条 Windows 打包路径的 notices 布局~~ 已按 [D-078](DECISIONS.md#d-078-notices-归档统一为装配布局2026-10-01) 收敛为装配布局（core/ + edition.json + SBOM），两路径成员集合 16=16 一致；见[10-01 Review 第三批](CODE-REVIEW-2026-10-01.md#第三批剩余命名模块语义-review-与-c33-notices-布局收敛) | 后续九包干净机旅程按该唯一形状验收 |
| P2 · C34 | 汇总最终证据并复核公开文档与发布门 | 每包 SHA-256、许可证、SBOM、构建/测试摘要对应精确字节；C32/C33/C34 满足后再用独立可审计提交评审 Gate R |

每轮实现按“发现反例 → 窄修复 → 专项回归 → 完整 suite/相应检查 → 人工核对
→ 更新状态与队列”收口。源码发生变化后，相关目标包和旅程重新绑定新源码。

## 外部依赖

| 依赖 | 已知情况 | 解锁后的工作 |
| --- | --- | --- |
| Windows Python 构建环境 | 私有 VC++ 2010 / SDK 路线已完成 Python 3.4.10；14 模块与 app-local CRT 通过，Server 2008 ssl/sqlite/bz2/lzma/ctypes 通过。VS2019 channel 给出 19,253,644 字节 / fb642c...，实际清单为 11,154,648 字节 / 406969...，重复获取仍不一致 | 保留校验失败；不把候选清单当可信输入。完成 Python 3.8.20 的可验证兼容工具链，已完成 3.4.10 并入 win32 full |
| 当前模型配置 | 历史批次真实模型旅程因缺 API 配置未执行 | 通过既有配置/显式联网入口测试；不把 mock-provider 或旧包在线结果当当前源码证据 |
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
