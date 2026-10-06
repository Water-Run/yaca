# R78 原生文件系统资源生命周期

故障取证与完整检查于 2026-10-05 执行，2026-10-06 核对并收口。
基线为 `1e97083b783d0d65634125a2eabf97467015d567`；本批运行源码仍在工作树。
冻结输入与当前文件逐字节核对一致，基线 native 九个成员与该提交逐字节一致。

## 问题与实现

Lua 的内存分配错误和调用方身份表的 getter 异常通过 longjmp 离开原生函数。
原实现把 snapshot、路径、xattr、walk vector 和临时句柄留在 C 栈上，后续 free/close
无法执行。POSIX verified open 还在身份读取之后才把已打开 fd 交给文件 userdata。

新增私有 Lua userdata 资源守卫，在获取原生资源前建立 finalizer 和初始化的上下文。
正常返回与类型化失败显式释放；Lua 异常展开后由 GC 释放。释放前清空 callback，
避免重复收尾；finalizer 不调用调用方 Lua。前次分配错误可能留下未完成的元表，
后续创建守卫时会重新补齐 finalizer，重复故障验证覆盖这一恢复路径。

Windows 与 POSIX 的 snapshot/metadata 投影、walk 和 verified open/create 已接入
所有者。POSIX verified open 在读取身份字段前转移 fd；create 的父 fd 和路径也由
守卫持有。成功结果只含原有 Lua 表或文件 userdata，未增加公开接口。
两条 Windows 构建入口纳入维护探针 `filesystem_snapshot_faults.c`。

## 故障证据

探针直接包含冻结的生产 native 源码，分别跟踪原生内存与 OS 句柄，不把 Lua 堆算作
原生泄漏。逐个 Lua 增长分配点持续拒绝分配，包含 emergency GC 重试；verified
open/create 另使用会抛错的身份 getter。每例在同一状态执行故障、正常恢复、相同
故障、再次恢复；两次完整 GC 后审计资源。正常恢复核对快照和 walk 内容，文件端口
实际读取，create 实际写入、回绕和读取十六字节。只在基线证实泄漏后由探针救援清理，
防止各反例相互污染，不将这一清理记为产品成功。

| 环境 | 基线累计泄漏资源 | 修复后泄漏 / 所有权错误 | 恢复 |
| --- | --- | --- | --- |
| Linux x86_64 开发宿主 | 1706 | 0 / 0 | 同状态两次恢复通过 |
| Server 2008 non-R2 x64 / Win32 WOW64 | 5814 | 0 / 0 | 同状态两次恢复通过 |
| Windows 11 x64 | 10062 | 0 / 0 | 同状态两次恢复通过 |

覆盖 inspect-file、inspect-directory、walk、open-verified、create-verified。
这些数字是所有故障例的累计资源数，分配点数量受路径与环境影响。POSIX 夹具在
文件系统支持时带实际 user xattr。本批不声称覆盖所有 symlink/特殊元数据分支或
delete/replace/rename 的异常路径。

基线来自精确 `git archive` native；探针使用同一份维护源。编译开启
`-std=c99 -Wall -Wextra -Werror -O2`，Windows 另使用固定 Lua DLL/import library、
Win32 `_WIN32_WINNT=0x0501`、Win64 `0x0601`，没有关闭警告。
早期 snprintf 编译告警和 Windows strdup 跟踪缺项已修正；早期失败日志保留，
只将 `*-final.log` 作为本批故障结论。

## 回归与语义复核

Linux 原生 open、read、process stream、text codec 故障探针均通过，零泄漏；
text codec 含 1,114,113 个 UTF-8 scalar 候选。同源码新建 Linux native 模块后，
既有 seek 探针通过十二个偏移、负偏移拒绝、关闭句柄拒绝和稳定身份检查。
本批现有故障探针的 Windows 回归未另行全跑，R77 二十项日志保留原有源码范围。

完整 Lua suite **706/706**；完整 coding readiness **PASS**，注释结构
**242 文件 / 5454 声明 / 0 缺项**，检查器反例 15/15、发行和旅程回归、四校验器与
全部 TP/RP 通过。以上完整检查在取证环境执行；当前沙箱限制 32 位解释器，正常
seek 复核使用已有 64 位 Lua，资源守卫使用其 `/tmp` 锁目录。

人工核对本批 guard/context 的初始化、所有权转移、callback 注释、部分获取清理、
栈恢复和结果形状。整体人工语义 Review 仍为 partial。下一面为原生删除/替换/改名，
其后继续其它原生接口、main 交互与测试辅助代码，不用结构覆盖数字替代这些审核。

原始记录位于 `out/native-lifetime-review-20261005/`，输入、二进制、Lua 库和日志的
精确摘要见 [`native-review/R78.json`](native-review/R78.json)。两台 Windows 的
接收目录与日志保留，探针独占的临时夹具已清理。首次封包时环境的 `.git` 为只读，
因此先形成可应用补丁、399 成员源码快照和 79 成员证据包；旧交付清单如实保留该边界。
同日负责人恢复权限后，继续执行已授权的源码提交与推送，不改写初次封包的字节。

已发布的 R75/R76 候选单文件不含 R77/R78。最终三平台核心与九包仍须重新构建，
补齐 C32/C33/C34 后评审；Gate R 保持关闭，`release_authorized=false`。
