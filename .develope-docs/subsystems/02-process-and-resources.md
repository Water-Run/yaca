# 02 进程执行与随包资源

状态：产品契约已确认；目标平台进程、管道、取消与 kill-tree 原语待技术证明

## 职责

定位实际获准随包的工具，安全启动 curl、模型要求的原始 shell 命令及少量内部 helper；统一超时、输出上限、stdout/stderr、退出码、取消和 unknown 结果。仓库现有 BusyBox、diff、patch、file、iconv、jq、sqlite3 只是候选来源，不预先承诺全部随包。

## 边界

- Runtime 自己启动 curl/helper 时使用结构化 executable/argv，不经过 shell；这类内部端口不能被模型当成另一套工具入口。
- 面向模型的 shell 工具接受 opaque 原始命令；本系统不能声称它仍具有 argv 级细分权限或可静态推断副作用。
- 权限判定属于 08 号子系统；本系统只执行已获准动作。
- 网络策略属于 03 号子系统，即使底层最终调用 curl。

## Raw shell

- Windows shell chain 固定为 `cmd.exe /d /s /c`，Linux 固定为 `/bin/sh -c`。Process adapter 负责各平台的进程创建和外层 quoting；Runtime 不拆解、改写或解释 `command` 正文。
- shell 只作为前台、非交互工具运行。v0.1 不提供 PTY、交互程序代理、tracked background job、detached job 或后台任务管理器。
- 首版没有 direct HTTP tool。模型网络由 03/06 号端口处理；获准的 raw shell 仍是宽能力，原始命令可能自行调用网络程序，不能把“没有 direct HTTP tool”宣传成 OS 级断网保证。
- Runtime 为一次 exec 分配一个 operation identity，串行等待其 typed result。取消只是请求；只有确认进程树已经结束才能返回 cancelled，无法证明最终副作用或子孙状态时返回 unknown。
- opaque 命令自行尝试脱离前台不是受支持的后台能力。Runtime 不接管或复连它，并按目标平台可证明的进程树边界终止；证明不足时如实返回 unknown。

## 旧系统重点

- Windows 命令行转义和 CreateProcess 语义。
- CentOS 7 的 POSIX 信号、超时和子进程树清理。
- 输出代码页、二进制输出及 CRLF/LF。
- 随包工具版本、完整性和替换边界。
- Windows x86 与 Windows x64 包中的工具必须分别匹配本包架构，不能混入另一架构的 DLL 或可执行文件。
- Linux 随包工具必须全部提供目标 ABI 的普通 x86_64 版本。仓库当前文件是 ELF32；curl 还是 x32 ABI，均只能作为来源清单或开发参考，不能直接进入最终 Linux 发布物。
- 当前 Windows `curl.exe` 经 UPX 压缩，静态导入表不足以证明真实程序只使用 XP API；发布审计使用未压缩、来源可追溯的构建物，并对最终产物重新验收。

## 固定平台契约，不进入用户配置

- 终止 grace 由每个平台 Process adapter 与发行 manifest 固定，数值在子进程树、取消竞态和旧机延迟测试后冻结。它可以在 status/self-test/result 中只读显示，但不存在 `TerminateGraceMs` INI/XML 字段；无法证明进程树结束时仍必须返回 unknown。
- stdout/stderr 文本解码使用 Runtime 内建 `auto`，并在 result 中记录实际 decoder、替换/失败和原始字节计数。当前不存在 `OutputEncoding` 字段；只有旧平台技术证明显示无法可靠检测时，才能提案受平台约束的 typed troubleshooting override，不能先用一个通用 code-page 开关掩盖问题。

## 技术证明门

Lua 纯标准库无法可靠提供跨平台进程控制。已确认允许窄 C bridge/helper 承载必要的平台能力；具体 ABI 仍须证明。流式 stdout/stderr、忙时键盘输入、超时、Esc/`.cancel` 和进程树清理必须接入同一可轮询/可通知的运行时端口，不能各自产生第二套领域状态。

Windows XP 可以使用 `ReadConsoleInput` 等旧控制台 API 接收输入，也支持 Job Object 与 `TerminateJobObject` 管理已成功纳入 job 的进程树；但跨线程 `CancelIoEx` 和取消同步 I/O 的 `CancelSynchronousIo` 最低是 Vista，XP 后端不能依赖它们。技术原型应验证可控的异步/overlapped I/O、短超时事件泵和关闭自有句柄/终止自有 job 的协议，不能先做阻塞同步读取再假设能从另一线程取消。参考：[ReadConsoleInput](https://learn.microsoft.com/en-us/windows/console/readconsoleinput)、[CancelIoEx](https://learn.microsoft.com/en-us/windows/win32/api/ioapiset/nf-ioapiset-cancelioex)、[CancelSynchronousIo](https://learn.microsoft.com/en-us/windows/win32/fileio/cancelsynchronousio-func)、[TerminateJobObject](https://learn.microsoft.com/en-us/windows/win32/api/jobapi2/nf-jobapi2-terminatejobobject)。

以下全部是实施技术证明，不再是产品负责人候选：管道 handle 能否进入同一等待模型、创建后到纳入 job 之间的竞态、shell 子孙进程能否全部收口、取消后如何等待真实完成、helper 崩溃怎样形成 typed port error/`unknown`，以及 Windows x86/x64 与 Linux x86_64 的输出背压和超时上限。证明失败且退路会改变上述用户保证时，只重新打开对应的最小产品差异。
