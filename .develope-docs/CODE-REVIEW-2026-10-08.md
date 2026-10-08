# 恢复开发与 Windows cooked reader 所有权 R82

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
