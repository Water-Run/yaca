# 恢复开发与关闭路径 R82 / R83 / R84 / R85

日期：2026-10-08。负责人要求同步最新进展、检查梳理并推进开发，按
[D-083](DECISIONS.md#d-083-同步最新进展并恢复开发2026-10-08) 恢复。
本地无未提交修改，从 `4a9c4bc` 快进 15 个提交到
`df38087c6c7855a45e94cf63b51528da4da0b345`。Windows Git 的 schannel 和
OpenSSL 两次 TLS 拉取失败后，WSL Git 成功获取 `origin/main`；保留 `main`，
没有创建分支、提交、推送或新预发布。R81 已交付九包与三平台 706/706 的记录
按原源码范围保留，不再重复 10 月 2 日已完成的 Python/full 装配工作。

## R82 反例与修复

`l_terminal_gc` 在 `cancel_windows_cooked_read` 失败后只把 `cooked_read` 置空。
worker 的 heap record 不引用 Lua userdata，避免了该处直接访问已回收 userdata，
但 worker 结束时也不释放 record、wide buffer 或 thread handle，三个资源均永久遗留。

修复为独立引用计数：在 `CreateThread` 前设立终端和 worker 两份引用。终端完成
读取或 emergency detach 时清空其指针、关闭其 thread handle、释放终端引用；
worker 存储结果后释放另一引用，最后一份引用释放 record 与 wide buffer。
worker 不读取线程句柄，也不访问 Lua。启动失败仍直接收回未转移的分配。
显式 cancel/restore/close 的失败保持原来的 owner 和 OS 错误，可由调用方重试。

创建前建立两份引用也覆盖 worker 先于 `CreateThread` 返回而结束的情况；该调度
可能性按 [Microsoft CreateThread 文档](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createthread)
核对。保留既有 XP 可用的原子引用模式，没有引入新的操作系统版本依赖。

既有 `windows_console_reader_smoke.c` 的直接 callback 夹具为 stack record，
显式保留 caller 引用；R81 的 completed-reader double 没有真实 worker，
只持有终端引用。两类 fixture 的初始化同步调整，没有扩大其真实控制台证据范围。

## 故障取证

新增 `windows_cooked_lifetime_smoke.c`，直接包含生产 native；`CreateThread`、
Lua userdata GC、线程等待、复制句柄及 OS handle count 都是真实操作。
`ReadConsoleW`、synthetic Enter 和取消错误使用同步事件控制的有界 double，
每个 worker 最多等待五秒，不读取用户控制台。原生分配计数跨线程使用原子操作。

每架构各 56 个场景：六个 setup 失败/恢复、八个显式取消失败/重试、十个
实际 Lua state GC/detach，以及 32 个 worker 在创建调用返回前已结束的竞争控制。
五种 detach 覆盖注入失败、零写入、join 超时、wait 失败、worker 完成后注入报错；
各重复两次。只有确认基线 worker 已停止且确有泄漏后才救援清理，救援不计为通过。

| 本机运行面 | 精确 df38087 native 基线 | 修复后 | 既有回归 |
| --- | --- | --- | --- |
| Win32 / Windows 11 WOW64 | 20 内存块 + 10 thread handles；探针退出 1 | 0 泄漏，56 场景通过 | cooked reader PASS；terminal input 零泄漏/所有权错误/协议失败 |
| Win64 / Windows 11 x64 | 20 内存块 + 10 thread handles；探针退出 1 | 0 泄漏，56 场景通过 | cooked reader PASS；terminal input 零泄漏/所有权错误/协议失败 |
| Linux / Ubuntu WSL2 | Windows 专属反例不适用 | 当前 native 模块编译通过 | terminal input 零泄漏/所有权错误/协议失败 |

Windows 宿主为 Windows 11 Pro for Workstations Insider Preview `10.0.26220`。
两架构使用缓存的私有 GCC 13-win32 工具链；Lua 5.5.1 源归档按已锁定
`1c4b4068...` 核对，Win32 DLL/import library 本轮串行构建，Win64 复用已核对缓存。
编译使用 C99、`-Wall -Wextra -Werror -O2`；Win32 `_WIN32_WINNT=0x0501`、
subsystem 5.01，Win64 `_WIN32_WINNT=0x0601`、subsystem 6.01。
本轮未在 Server 2008、XP 或 Win7 重新运行，不能把现代宿主结果写成最低系统实测。

两条 Windows 构建入口纳入维护探针；旧独立 Win64 入口也改用现有
`source_snapshot.py`，使未暂存的新回归文件进入维护源码快照，忽略的凭据与缓存
继续排除。既有 source snapshot 回归负责其字节与过滤规则。

## 完整检查与人工语义 Review

同步后的基线及修复后的完整 Lua suite 均 **706/706**。完整 coding readiness
**PASS**；Python **3.13.16** 与固定解析器的全仓注释清点为
**247 文件 / 5524 声明 / 0 缺项**。检查器反例 15/15、装配/发行审计/旅程/
源码快照/审批/Linux full staging/Windows 证据回归共 50/50 通过。
四校验器分别 7739 / 56 / 567 / 5，通过且 Gate R 仍关闭。
TP-003/006/008/010、RP-001 全链通过，TP-010 为 5,564,743 条断言。

首次 readiness 在 TP-008 因宿主缺少 `xmllint` 停止，失败日志保留为
`coding-readiness-first.log`。通过 Ubuntu 官方包下载并在本轮隔离目录提取
`libxml2-utils`，未安装到系统；补齐 PATH 后完整链复跑通过。解析器与 Python
也在忽略的开发目录内，不增加产品或发行运行时依赖。

人工核对了终端/worker 两份引用的建立和释放、启动失败、worker 提前完成、
完成后的投影重试、显式取消失败保留、GC detach 的句柄收回、原生分配跟踪，
以及既有两类 fixture 的所有者边界。此子面已核对，全仓语义 Review 仍为 partial。
真实控制台取消/回显和最终包旅程未由 double 替代。

原始输入、二进制、Lua 依赖、构建和测试日志在 `out/review-20261008/`；
本轮摘要清单在 [`native-review/R82.json`](native-review/R82.json)。R81 已发布 ZIP
未改变，也不包含 R82。后续 Review、统一重建、C32/C33/C34 和正式 Gate R 仍待完成。

## R83 DLL 卸载后的线程代码生命周期

R82 已形成本地提交 `1456a16`，尚未推送。继续检查发现仅保留 heap record
仍不够：生产 `package.loadlib` 加载 native DLL，Lua 5.5.1 的 library string
在 `lua_close` 中调用 `FreeLibrary`。cooked reader 或异步 stdin writer 仍在
阻塞时，其 DLL 代码会先被卸载，线程之后可能返回已经释放的代码地址。

新增 `windows_worker_lifetime_fixture.c` DLL、共享 host context 和
`windows_worker_lifetime_smoke.c`。通过实际 Lua `package.loadlib` 加载实际
DLL，启动生产 reader/writer、关闭实际 Lua state，再核对 DLL 映射和实际线程状态。
IO 使用私有事件控制的有界 double；不操作用户控制台。精确 R82 native 与同一份
最终维护探针组合，在两个架构各四个场景均确认 `module_resident=0 worker_live=1`。
反例进程立即退出，不再唤醒已经失去 DLL 映射的线程。

修复在启动前通过私有数据地址定位所属模块。DLL 场景获取一份 worker 独占引用，
EXE 场景不获取；启动失败收回引用并保留原始 OS 错误。worker 先保存模块引用，
再完成 IO、句柄和 storage 收尾，最后由 `FreeLibraryAndExitThread` 释放 DLL 并
结束线程，避免在自身 DLL 已卸载后返回。终端与 process owner 不释放这份引用。
多线程各持有一份，最后一个 worker 退出才允许 DLL 被实际卸载。

模块按地址定位和引用规则依据
[GetModuleHandleExW](https://learn.microsoft.com/en-us/windows/win32/api/libloaderapi/nf-libloaderapi-getmodulehandleexw)，
结束时的释放顺序依据
[FreeLibraryAndExitThread](https://learn.microsoft.com/en-us/windows/win32/api/libloaderapi/nf-libloaderapi-freelibraryandexitthread)。
两 API 最低支持 XP，不使用永久 PIN 标志；借用的 unchanged-refcount 句柄不交给
FreeLibrary。主程序代码仍保持原来的正常 callback 返回路径。

本机 Win32/Win64 各 **26** 个场景：两轮 reader/writer 的正常 IO、IO 错误、
模块查询失败、模块引用获取失败、线程启动失败与提前退出，以及两轮双 worker。
所有场景通过，最终 DLL 未驻留、原生 block 为 0、OS 句柄恢复基线。
双 worker 在 writer 先退出后核对 DLL 仍在、reader 的两个 block 仍由它持有；
reader 退出后才允许卸载。两架构既有 cooked/terminal、process stream/start
故障回归也通过。Linux 当前 native 编译通过，Windows 专属卸载反例不扩展到 Linux。

先完成一次 Lua 标准库与 Windows pipe 初始化，再测每个 owner 的实际句柄数。
首次未预热导致的一次性缓存计数差异及错误的 nil/error fixture 断言保留在
`out/review-20261008/r83/`、`r83-final/`；最终证据只使用 `r83-complete/`。
原生 failure 实际为 false/error，探针已与生产返回协议对齐，没有放宽资源断言。
两条 Windows 构建入口纳入 DLL/host 探针，fixture 不进入产品 runtime。

冻结的 native 与维护探针、各架构 Lua 依赖、二进制、原始 stdout 与构建日志
保存在 `out/review-20261008/r83-complete/`，逐项摘要见
[`native-review/R83.json`](native-review/R83.json)。本轮结构检查 **250 文件 / 5541 声明 /
0 缺项**；完整 Lua **706/706**、完整 readiness 全链 **PASS**。
本批 worker DLL/storage/pipe/thread 所有权、失败回收、返回协议和所有探针已完成人工
语义核对。正式源码冻结和三目标九包重建仍待后续 Review，全仓语义 Review 保持 partial。

## R84 终端关闭失败后的同句柄重试

基线为 R83 提交 `6a6dae4`。`terminal.lua` 的 `port:close()` 在 native
`terminal_close` 返回失败或抛错后也无条件标记 `closed`，下一次清理只能得到
"terminal port is closed"，原生 owner 尚未释放却失去重试入口。
process 适配器已经只在 native 关闭成功后推进状态；terminal 现遵守同一所有权边界。

窄修复只在 `close_ok` 为真时改变状态。native close 失败保留原来的 started/joined
owner；成功恢复的设置不重复恢复，失败恢复可再尝试。原有错误优先级保留；如果
native close 实际成功而此前 restore 失败，仍报告先前错误，但 owner 已关闭，
不能为重试而再次触碰已释放的句柄。

新增两个 integration case，覆盖 joined 的 typed close 拒绝、started 的 restore
与 close 连续失败、native close 异常，以及先前 restore 失败但实际 close 成功。
最新维护回归与精确 R83 `src/` 在隔离 test root 中组合：专项 **9/10**，原失败为
第二次关闭被错误的 closed 状态拒绝；修复后 **10/10**，核对同一个原生 handle、
restore/close 次数及成功后不二次释放。

完整 Lua suite **708/708**，完整 coding readiness **PASS**；全仓结构清点
**250 文件 / 5547 声明 / 0 缺项**。修改后的 close 参数、返回、错误先后、状态与
所有权注释及每个测试 callback 已逐项核对。该批没有修改 C 或发行版本，不重写
R83 的 native/DLL 结果；已发布 R81 包不含 R84。
原始专项、全套检查、精确基线与维护回归在 `out/review-20261008/r84/`，
冻结来源与实际日志摘要见 [R84 清单](lua-review/R84.json)。
整体语义 Review、主交互和正式资格继续按 TRACKING 收尾。

## R85 管理输入面的 owner 保留与模式切换边界

基线为 R84 提交 `23d9402`。`new_model_setup_input` 共用于模型、配置和 Context
输入面。普通和时钟退化的 close 路径都在端口关闭失败后清空 active，最终清理
因而把仍存活的终端当作已释放；失败模式切换还可能创建新终端覆盖旧 owner。

修复只在确认 close 返回 true 后清空 active、模式及缓冲；失败保留 owner，并记录
closing 和已经成功的 join。最终清理重试同一端口，避免重复 join；模式激活会先
处理 pending cleanup，不能复用或替换未关闭的 owner。时钟退化仍尝试无时钟
close，失败保留 owner，成功清理后继续如实报告时钟错误。

新增真实 Model manager 控制流回归：准确输入连接测试同意后，typed close 拒绝、
close 异常及收尾前时钟退化分别要求第二次清理成功；join 次数为 1/1/0，close
均为 2。另在 Key 字段的 cooked→hidden 切换注入 close 失败，回到下一提示前必须
先关闭旧终端。所有路径核对配置字节不变、零网络请求，不通过私有函数测试入口。

最终维护测试与精确 R84 `src/` 在隔离 root 中运行为 **25/27**，两个新增 case
确认未关闭 owner；修复后 **27/27**，连同 coordinator/native ports 专项通过。
完整 suite **710/710**、完整 readiness **PASS**、全量结构清点 **250 文件 /
5552 声明 / 0 缺项**。本批 close/activate 的参数、结果、失败优先级、join 状态、
缓冲和 owner 边界及每个新 callback 完成人工语义核对。

冻结源码、维护回归及实际输出绑定于 [R85 清单](lua-review/R85.json)，日志位于
`out/review-20261008/r85/`。全仓语义 Review 仍为 partial，ApplicationCoordinator
及后续交互内部继续核对；新三目标核心、九包及其旅程尚未完成。

## R81 来源与证据缓存恢复

从现存 GitHub 预发布恢复 12 个已交付附件：三目标 clean runtime/notices、
三目标来源包、完整证据包、audit 与 SHA256SUMS。每件大小与 SHA-256 均逐项核对
仓库已有 publication 回执，保存于忽略的 `out/release-cache-20261006/`；
[恢复清单](candidates/restored-inputs-20261008.json) 记录精确字节。
Windows urllib 下载两次遭遇 TLS EOF，已完成文件复核后通过 Linux curl 继续，
失败与成功日志均保留。本轮未恢复 std/full runtime，不把缓存恢复当作当前源码资格。
