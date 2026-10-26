# 2026-10-26 交互修复 Review

按 D-097 恢复实际使用修复，按 D-098 收束当前节点、打包推送后暂停。目标“实现 yaca”
尚未完成，正式 Gate R 关闭。

## 复现与实现

`windows_editor_test.c` 的隔离剪贴板夹具在 `GetClipboardData` 延迟 400 毫秒。
原同步按键处理耗时 422 毫秒，返回 `nonblocking=FAIL`，说明会阻塞同线程的 AgentLoop
轮询。此夹具替换剪贴板 API，没有读取或覆盖用户的系统剪贴板。

Windows Ctrl-V/Shift-Insert 现在启动独立读取线程。线程只持有自己的有界堆缓冲区和模块
引用，不持有 Lua、terminal 或 stdin 指针。完整严格 UTF-16 转换结束并解锁、关闭剪贴板后，
主线程以零等待投影结果。最多复制一 MiB，实际输入上限仍受 terminal request 约束。

`paste-start` 保留输入顺序：等待期间暂存后续编辑和 Enter，完整文本接纳后再依次回放。
Ctrl-C/Esc 先取消这一层输入并清草稿，再次取消才传给模型。两秒未完成则拒绝本次粘贴，
丢弃等待的按键及同批已取到的后续按键，防止 Enter 提交缺少粘贴内容的指令。
队列同时限制字节数与 256 个观察项；超限在任何排队提交前停止输入。

取消、恢复、关闭和 GC 均立即释放 terminal 的线程句柄与记录引用；迟到文本不再发布。
Windows 的延迟渲染调用本身可能仍在另一线程等待。该线程独立保活存储和 DLL，最终自行
关闭剪贴板并退出；同一 native 模块只允许一个尚未结束的读取，包含已经超时或失去 owner
的读取。不强杀线程，也不从其他线程关闭它的剪贴板锁。重复粘贴手势在已有请求期间忽略；
这一交互限制保留在接续事项，不能将本节点称为全部输入问题已解决。

API 所有权对照 [GetClipboardData](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getclipboarddata)
与 [Clipboard Operations](https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-operations)：
剪贴板句柄仍归系统，复制后解锁，不释放该句柄，不在 CloseClipboard 后使用它。

## 验证记录

证据目录：`out/review-20261026/`。本轮先处理缺失的本机检查环境：从固定摘要的
Lua 5.5.1 缓存恢复解释器，用 Python 3.13 和固定解析器要求重建检查环境。
初次完整 Lua 为 753/754，唯一失败是 AsyncPort 新增方法尚未同步精确方法清单，已补齐。
之后 Win32/Win64 的 755/755 包含五项新增粘贴次序、取消、拒绝和有界队列回归。
收尾 Review 又发现拒绝路径清空已取批次时会丢弃唯一的 terminal outcome。现只删除
未处理的 user_action，保留结束事实，并新增该回归；最终三套完整测试为 756/756。

原生夹具现在得到按键分发 0 毫秒；严格文本与九项转换/发布分配失败点、七项异步开始
发布失败点、六项结果发布失败点、取消、超时、迟到结果丢弃和全局读取上限通过。
保护调用在进入 C 函数前也可能分配失败，夹具已修正该处错误的“必须已有 worker”假设。
所有失败后均通过同一 owner 或未开始状态恢复，没有把失败的开始当作已执行读取。

其他原生 reader/生命周期、输入故障和 54 项键盘分配故障回归通过；Win32 使用 XP 宏做
语法检查。全仓注释结构检查为 276 文件 / 5914 声明 / 0 缺项。本批函数、回调、结构字段、
并发读写及所有权注释已逐项人工核对，全仓语义 Review 仍为 partial。

首次 readiness 已通过解析器、合同和 TP-003/006/008/010 的运行部分，随后由于当前 shell
缺少固定 `LUAINSTALLER_SOURCE` 而退出；保留 `readiness.log`，修正环境后完成最终重跑。
最终终端旅程、完整 readiness、产物与公开摘要的结果见交接及发布回执。
`readiness-final.log` 已完整退出零，含固定 luainstaller 的 RP-001；最终核心在末项清理修复
后重新构建，避免把修复前嵌入的 Lua 字节作为交付核心。Windows 最终旅程日志带 `-settled`。

最终 Linux 首次 80 列旅程在等本地 Ask 到达时超时，保留 `pty80-settled.log` 与屏幕。
原驱动直接阻塞等事件，期间不读取 PTY；现保持原十秒 deadline，等待时持续排空输出并检查
子进程退出，防止观察器自己形成终端背压。相同核心随后在 80/40 列及 dumb 完整通过，
日志为 `*-handoff`。不能仅凭重跑通过认定第一次超时的唯一原因。此驱动修改后的实际三种
旅程、注释结构检查和人工语义 Review 通过；前述完整 readiness 是驱动修改前的产品源码
检查，没有据此扩大旧系统或全部终端资格。最终 12 个 PE artifact 导入/子系统检查通过。

## 保留边界

本轮是当前 Windows 宿主和 WSL 的回归。Linux host 核心不代表 glibc 2.17 资格。
指定旧系统、真实 IME/字体、真实跨程序延迟剪贴板、Cygwin、动态缩放和长会话仍需验证。
来源闭包、最终九包 C32/C33/C34 与全仓语义 Review 不因本节点测试通过而完成。
