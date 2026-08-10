# 02 进程执行与随包资源

更新日期：2026-08-10

状态：**W3-A 规格首版** — Process AsyncPort ABI 与 result 枚举已冻结；kill-tree/grace 数值待 TP 校准（D-070 技术推导）

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

以下全部是实施技术证明，不再是产品负责人候选：管道 handle 能否进入同一等待模型、创建后到纳入 job 之间的竞态、shell 子孙进程能否全部收口、取消后如何等待真实完成、helper 崩溃怎样形成 typed port error/`unknown`，以及 Windows x86/x64 与 Linux x86_64 的输出背压和超时上限。证明失败且退路会改变上述用户保证时，只重新打开对应的最小产品差异（D-070）。

---

## W3-A：Process AsyncPort ABI（规范）

对齐：D-052、D-057、AR-P0-04/06、P1-03、TP-003/005。组合见 [22](22-application-runtime-and-concurrency.md)。

### 端口生命周期

| 方法 | 语义 |
| --- | --- |
| `start(spec) → handle` | 创建进程/管道；返回本地 `op_id`；失败不分配 durable 副作用 |
| `poll(handle) → events[]` | 非阻塞；事件：`stdout_chunk`, `stderr_chunk`, `exit`, `error`, `cancelled` |
| `cancel(handle)` | **请求** 终止；不保证立即结束 |
| `join(handle, deadline) → result` | 等到终态或 deadline；超时后仍须可再次 join/close |
| `close(handle)` | 释放句柄；未 join 时隐含 best-effort cancel+unknown |

### `start` 规格字段

| 字段 | 内部 exec | 模型 raw shell |
| --- | --- | --- |
| `mode` | `argv` | `shell` |
| `executable` / `argv` | 绝对路径 allowlist | — |
| `command` | — | opaque 字符串 |
| `cwd` | 显式绝对路径 | 当前 Context root（冻结） |
| `env` | clean + allowlist | inherit baseline 按 M05-15/55（无用户 ambient 偷带 Key） |
| `stdin` | bytes 或 closed | 默认 closed；若工具要求则有界 bytes |
| `limits` | stdout/stderr/total bytes、wall clock | 同左；受 turn/process hard cap |

Windows shell：`cmd.exe /d /s /c`。Linux：`/bin/sh -c`。Runtime **不** 解析 command 正文。

### 终态 result

| `status` | 何时 | 用户/Agent 含义 |
| --- | --- | --- |
| `completed` | exit 已知且进程树已证明结束 | exit_code + 有界输出 |
| `cancelled` | 取消且树已证明结束 | 无自动重放 |
| `failed` | spawn/API 失败，无副作用或已记录 | typed error |
| `unknown` | 无法证明树/外部效果 | **禁止** 伪造成功；需 self-fix 解算 |

### 取消与 kill-tree（保守）

| 平台 | 策略（待 TP 校准数值） |
| --- | --- |
| Windows | Job Object + `TerminateJobObject`；创建→入 job 竞态必须覆盖；**不** 依赖 XP 上的 `CancelIoEx` |
| Linux | process group + SIGTERM→SIGKILL grace；grace **发行固定**，无 INI 字段 |

### 输出解码

- Runtime 内建 `auto` 解码；result 记录 decoder、replacement 计数、raw byte 计数。  
- 达 cap → typed `Limit` + 截断标记；**禁止** 无限 Lua 缓冲。

### 备选否决

| 方案 | 否决 |
| --- | --- |
| PTY / 交互代理 | D-052 排除 |
| tracked background job | D-052 排除 |
| 弱 cancel（exit 即当树死） | 违反 unknown 诚实；失败走 O 包 |

### 完成度

- [x] start/poll/cancel/join/close 与 result 枚举  
- [x] shell dialect 固定  
- [ ] grace ms / 管道背压数值（TP-005）  
