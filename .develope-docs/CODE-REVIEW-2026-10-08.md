# 原生终端生命周期与键盘输入 Review

## R82：Windows cooked reader 的取消失败与最终释放

开发按 [D-083](DECISIONS.md#d-083-同步项目并恢复开发2026-10-08) 恢复。
`git fetch origin --prune` 和 `git pull --ff-only` 完成；基线为
`df38087c6c7855a45e94cf63b51528da4da0b345`，远端没有新增源码提交。

### 缺陷和修复

`l_terminal_gc` 在 `cancel_windows_cooked_read` 失败时直接丢弃 `cooked_read`。
worker 使用独立堆记录，不会访问已被收集的 userdata，但返回后没有释放堆记录、
wide buffer 和原线程句柄的路径。显式 cancel/restore/close 失败会保留 owner，
供调用方重试；最终 GC 丢弃该 owner 时仍会发生泄漏。

R82 为 reader 加入原子引用计数。创建线程之前初始化终端和 worker 两个引用；
worker 在最后一次访问 `received` 后释放其引用。终端正常 join 或 emergency detach
时先清空 `cooked_read`，关闭自己持有的线程句柄，再释放终端引用。最后一个引用
释放 wide buffer 和记录。线程在 `CreateThread` 返回前完成时，终端引用仍保持记录
有效；GC 先于 worker 完成时，worker 引用保持缓冲区有效。

显式端口的拒绝、重试和返回形状保持原有语义。GC 的恢复模式尝试也保留原有次序。
失败 detach 不宣称线程已经终止；永久未返回的 worker 保留自己仍需要的资源，
直到线程返回或进程结束。线程句柄关闭不等于终止线程，原子释放采用兼容 XP 的
`InterlockedDecrement`。依据为微软的 [CloseHandle](https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-closehandle)
与 [InterlockedDecrement](https://learn.microsoft.com/en-us/windows/win32/api/winnt/nf-winnt-interlockeddecrement) 文档。

已更新 completed-reader 和同步 reader 夹具的所有权初始化。两条 Windows 构建入口
纳入维护探针 `windows_console_lifetime_faults.c`。未增加公开 native 接口。

### 对照与回归

新探针直接包含生产源码，实际启动 Windows 线程；ReadConsoleW、WriteConsoleInputW
及取消等待的故障通过有界 double 注入。线程暂停在读入处，实际 Lua GC 或 lua_close
先销毁终端 owner 和状态，再放行 worker 写入缓冲区并返回。另一组在 CreateThread
返回前完成 worker，另有完成与 finalization 的并发调度。

取消矩阵包含 synthetic Enter 拒绝、成功但零条写入、join 超时和初始 wait 失败；
分别检查显式 cancel/restore/close 的失败后同 owner 重试，及 GC/lua_close detach。
每个固定失败场景执行两轮，两个完成调度各执行 64 轮。启动另覆盖两次原生分配和
线程创建失败后的同 owner 恢复。每次以独立副本的真实线程句柄 join 后核对所有缓冲
和进程句柄数；只有确认的旧实现泄漏才由探针救援，救援不计为产品成功。

| 环境 | 检查数 | 基线缓冲区 / 句柄泄漏 | 修复后缓冲区 / 句柄泄漏 |
| --- | --- | --- | --- |
| Server 2008 non-R2 x64 / Win32 WOW64 | 176 | 160 / 80 | 0 / 0 |
| Server 2025 Standard x64 / Win64 | 176 | 160 / 80 | 0 / 0 |

本次读取的两个 OS 版本分别为 6.0.6003 和 10.0.26100。既有 Win64 SSH 目标当前
实际系统是 Server 2025，与 R81 历史记录的 Windows 11 不同；本批按实际环境记录，
不将历史系统名代入当前日志。

两目标原有 R81 输入故障、UTF-16 片段/surrogate、EOF 与错误 reader 回归通过；
Linux 从同份源码严格构建 native 模块及输入故障探针，输入故障回归零泄漏、
零所有权/协议错误。编译为 C99、`-Wall -Wextra -Werror -O2`；Windows 的最低
API 宏分别保持 0x0501/0x0601。以上是原生函数专项，不替代真实控制台交互、
终端模式故障或最低系统实测。

### 验收与 Review 范围

完整 Lua suite **706/706**，coding readiness **PASS**；全仓注释结构检查
**247 文件 / 5527 声明 / 0 缺项**。检查器反例 15/15、装配/审计/旅程回归、
四校验器和全部 TP/RP 通过；完整检查与构建/实机运行均经资源守卫串行执行。

已人工逐项核对生产 reader 类型、两个引用的初始化、线程抢先返回、GC detach、
正常 join、线程/缓冲区分离释放、startup 部分获取清理及所有调用点。探针逐项核对
线程门限、独立观察句柄、失败保留、同 owner 重试、实际状态销毁、完成调度和
救援仅在真实线程 join 后执行；所有函数、类型、回调及构建注释已核对。
全仓人工语义 Review 仍为 **partial**。下一面为原生键盘输入投影、终端模式错误
路径及 main 交互内部，不以本批通过替代这些审核。

15 个维护输入与 10 个基线输入、实际探针/DLL、Lua import library、原始日志、
完整检查及声明清点绑定在 [R82 证据](native-review/R82.json)。目标端重算的
12 个接收件摘要全部与本地一致。
原始失败、编译、实机和回归日志在 `out/native-console-lifetime-review-20261008/`。
已发布 R81 候选不含 R82；新的最终单文件/九包尚未统一重建。Gate R 保持关闭，
`release_authorized=false`，目标资格验证待完成。

## R83：raw 键盘重复、UTF-16 配对与字节上限

基线为 R82 提交 `5fc23ac`。`push_windows_key_action` 忽略 `wRepeatCount`，
合并的连续字符和退格只发出一次。它还把合法 Unicode 的字节限额返回成
`InvalidEncoding`；连续 high surrogate 会覆盖已有的半个字符，不拒绝畸形序列。
微软 [KEY_EVENT_RECORD](https://learn.microsoft.com/en-us/windows/console/key-event-record-str)
明确说明重复按键可能合并在一个 record 中，不能只按 record 数量计字符。

修复为每个 text action 保留完整重复次数，UTF-8 重复存储使用 Lua-owned buffer，
分配错误不泄漏独立原生缓冲区。先用除法检查总字节上限，再计算长度和复制。
high surrogate 同时保留重复次数，low surrogate 必须匹配；重复 high 或次数不匹配
返回 `InvalidEncoding` 并清空半字符状态。合法输入超过上限返回 `Limit`。
Enter/Esc 继续按一个 record 发出一个命令，既有修饰键优先级和零次数单键后备保留。

维护探针 `windows_terminal_input_smoke.c` 自建真实 Windows 控制台，通过实际
WriteConsoleInputW/ReadConsoleInputW 验证 ASCII、两/三/四字节字符、退格、最大
WORD 次数、跨 poll 的 surrogate、畸形后的同 owner 恢复及字节限额。
同时验证 raw 入场、restore 和 close 的 setter 拒绝及重试；仅 SetConsoleMode 的
拒绝用 double 注入，实际模式前后读回比较。另在真实控制台启动 cooked reader，
通过生产 synthetic Enter 取消、join 并核对终态与恢复模式。所有输入仅为固定非秘密
夹具，测试进程独占其控制台，不修改 SSH 终端或调用模型。

| 指定环境 | 真实控制台检查 | 基线失败 | 修复后失败 | 最终模式 / 句柄 |
| --- | --- | --- | --- | --- |
| Server 2008 non-R2 x64 / Win32 WOW64 | 86 | 26 | 0 | 原模式恢复 / 无增长 |
| Server 2025 Standard x64 / Win64 | 86 | 26 | 0 | 原模式恢复 / 无增长 |

`windows_keyboard_faults.c` 另使用有界 KEY_EVENT double，对三种大重复文本分别
枚举 18 个 Lua 增长分配点；每目标共 54 个阈值，持续拒绝包含 emergency GC 重试。
每例在同一 terminal owner 尝试相同阈值两次，每次后提供新的夹具输入并核对完整
UTF-8 字节；不把消耗的原记录记作成功重放，也不手工重置 owner 的 surrogate 状态。
实测每目标 54 次初始内存异常、36 次重复内存异常，另 18 次暖状态调用成功：
初次创建的 Lua buffer 元表等结构已保留，暖调用没有到达对应初始阈值。
这 18 次不记作注入异常。两轮内容恢复均通过，原生泄漏和所有权错误均为零。

两 Windows 的 R82 176 例生命周期、R81 输入投影和 bounded cooked-reader 回归
通过；Linux 严格构建同份 native 和输入故障探针，输入故障回归通过。编译使用 C99、
`-Wall -Wextra -Werror -O2`，Windows API 宏仍为 0x0501/0x0601。
首次新增探针严格构建遇到共享 tracker 中 getter helper 未使用的告警；保留失败日志，
在本窄探针显式引用共享符号后重建，未关闭告警或执行无关 getter 伪充键盘测试。

完整 Lua suite **706/706**、coding readiness **PASS**，全仓注释结构为
**249 文件 / 5548 声明 / 0 缺项**。检查器反例、发行/旅程回归、四校验器和
全部 TP/RP 通过。人工已逐项核对重复计数、缓冲区所有权、乘法限额、半字符失败清理、命令
保留行为及探针的真实控制台/故障 double 边界。全仓语义 Review 仍为 partial，
剩余异步线程的 DLL 生命周期、Cygwin PTY 失败路径、终端 Lua 适配器的失败关闭、
main 交互内部和测试辅助代码继续核对。

17 个维护输入、10 个基线输入、目标编译件、完整检查及实际环境绑定在
[R83 证据](native-review/R83.json)。16 个接收件的目标端 SHA-256 与本地一致。
原始输入、失败/成功日志与编译件位于 `out/native-input-mode-review-20261008/`。
本批直接验证生产函数，仍不替代最终单文件、完整交互旅程或最低系统实测。
已发布 R81 不含 R82/R83，最终三目标九包待统一重建，Gate R 继续关闭。
