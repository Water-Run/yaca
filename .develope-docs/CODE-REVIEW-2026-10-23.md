# 实际使用与 AgentLoop 修复

日期：2026-10-23。基线 `658ed5a`，`git pull --ff-only` 确认已与远端同步，起始工作区干净。
负责人要求自行测试基本使用，并参照成熟实现修复核心循环。按 D-095 恢复开发。

## 实际发现与修复

| 复现 | 修复 |
| --- | --- |
| 原生控制台显示 `>>` 后换行，命令落到下一行 | 生产 view 输出 inline prompt；提交后确认宿主已经回显的换行；异步输出另起行并重新提示 |
| CLI 已有补全候选，但 Tab 未接入生产输入 | 从唯一 CLI registry 传入有界命令目录；Windows Vista+ ReadConsoleW 中间唤醒提供公共前缀补全，默认启用 |
| 正常文本 stop 没有 yaca_finish 就进入 waiting-user | 完整非空文本正常 stop 与 finish 共用完成/DoubleCheck 路线；不伪造 control Fact，空回复和截断不算完成 |
| read 不存在的路径使整轮 ToolAdmissionFailure | 有明确白名单的目标/参数错误持久化为 synthetic-admission-error 并反馈模型；重复错误检测、硬预算、内部故障停止边界保留 |
| 立即完成的工具没有可见结果状态 | 从已提交 Runtime trace 投影工具结果与 error ID，复用原工具显示 ID |
| Anthropic 主请求有环境信息时拒绝后续 system 层 | 按协议分别编码 system 与普通消息，分别保留原顺序；环境和历史仍是 quoted user data |
| 大文件跳行期间达到扫描预算，续读返回目标行之前的数据 | continuation 保留 remaining_skip，next_line 指向原请求目标；测试覆盖多次预算与目标超出 EOF |

## 成熟实现参照

本轮读取 [Codex turn.rs](https://github.com/openai/codex/blob/main/codex-rs/core/src/session/turn.rs)
的 needs_follow_up 和 stop hook 路线：工具/待处理输入驱动下一次请求，没有后续工作时
进入收口检查。参考 [Anthropic 的 Agent 循环说明](https://www.anthropic.com/research/building-effective-agents)
中的执行、观察结果、继续工作模式。实现保留 yaca 的单 Agent、串行工具、权限、持久化与预算，
没有引入新运行时或照搬外部项目源代码。

本轮没有把持久化历史改成 provider 原生 tool message：现有绑定的 DurableFacts 仍作为
quoted data 进入请求。真实协议驱动检查从该内容读取并验证工具结果，不能假定已有 role=tool。
这项传输设计及长会话效率仍属于后续 AgentLoop 检查范围。

## 验证记录

原始日志保存在忽略提交的 `out/review-20261023/`。模拟服务只监听 loopback，使用固定
测试内容，无模型密钥。Windows 驱动创建自己的隐藏控制台，不接管用户控制台。

- `console-before.log`：原版提示符同列断言真实失败，保留原屏幕。
- `read-before.log`：新增起始行回归失败；修复后通过。
- `console-after.log`：第一次实际工具旅程发现 ToolAdmissionFailure，已保留失败。
- `console-after-v2.log`：测试驱动最初错误假设 role=tool；检查实际 DurableFacts 后修正驱动。
- `anthropic-before-confirmed.log`：改正测试模块隔离后，旧编码器真实失败于 system 层顺序。
- `full-suite-verified.log`：WSL Lua 739/739；`windows-full-suite.log`：Win64 单文件内嵌
  Lua 739/739。覆盖工具纠错、普通完成、审查、截断、取消及续读。
- `console-openai-results/`、`console-anthropic-results/`：两协议实际控制台完整旅程通过。
  覆盖首次配置、`.sta` + 退格/Tab、Up 历史、同列输入、中文多行 Ask、缺失路径错误、
  修正后读取、工具结果回送与可见状态、普通完成复核、退出后同 Context 重开与模式恢复。
- 最终本机试用核心：`out/review-20261023/delivery/yaca.exe`，SHA-256
  `22ded14eafe2b3d053f2ab5ee14a77adefc99f26a05508e9adcf63853b0c94c6`。
  最终注释语义补充后的字节分别在 `reviewed-openai-evidence/`、`reviewed-anthropic-evidence/`
  再次完成上述旅程；与前一个通过完整 suite 的核心仅相差注释。
  交付目录只包含该核心，没有测试配置或 Context；实际执行在两个独立测试目录。
- `native-tests/`：Windows cooked reader、worker 生命周期和 terminal 输入故障程序；
  Win32 XP 宏下编译检查单列，不能代替 XP 实机运行。
- 全仓注释覆盖 `273 文件 / 5810 声明 / 0 缺项`；完整 coding readiness 退出零。
  见同目录 `comments-final.log`、`readiness-final.log`，TP-006 319 断言及 TP-010、RP-001 通过。
  最终文档/契约修改后，四个校验器再次退出零，见 `validators-final.log`。

## 注释语义 Review 与边界

逐项核对了新增函数及改变的契约：正常完成只接受完整 stop 和可见文本；工具失败白名单
不绕过 Permission 或未知副作用；continuation 保存未完成跳行且仍绑定文件身份；输出只
使用已提交结果；Tab 目录从 registry 复制到 native/worker 自有有界数组，worker 不访问 Lua。
原生读线程继续使用独立引用和原有取消/恢复路线，补全失败不提交命令。

按 [Microsoft ReadConsole 文档](https://learn.microsoft.com/en-us/windows/console/readconsole)，
中间唤醒不支持 XP/Server 2003。该增强只自动用于 Vista+ 原生控制台，旧系统走原 cooked
输入；没有把 Linux、Cygwin PTY 或 XP 的补全标为已实现。当前只补全公共命令前缀，候选
菜单、文件路径补全和忙时草稿重绘仍需进一步实现/实测。

本次可用性修复不是全部缺口闭合。全仓人工语义 Review 仍为 partial，三目标最终资格、
九包来源闭包与 Gate R 均保持原未完成状态。本机候选复用 R94 固定依赖，只用于回归试用。

## 接续：Linux 默认编辑与忙时草稿

上一批已保存为本地提交 `00742fc`。本批继续 D-095，不再将已有但未接线的 editor
当作产品输入能力。`terminal.new_chat` 依据原生 TTY/TERM/宽度事实选择 ANSI 自有编辑
或 cooked 后备，已接到生产 composition；Windows 此批保留原来的 cooked 路径。

实现覆盖命令公共前缀/候选、上下键历史、左右/Home/End/Delete、退格和 Ctrl-A/E/U/K、
分片 UTF-8、Bracketed paste，以及 Ctrl-C 先清草稿再取消活动。历史只留内存，最多
64 条/128 KiB。输入上限与 Coordinator 对齐，超限或非法输入清空并提示，避免提交截断
后的命令；一个 poll 最多处理 64 次编辑，避免连续按键阻塞 AgentLoop。

输出复用已有 line editor：只清当前输入行，追加完整消息后恢复同一草稿与字节光标。
单行 viewport 在保守的字符宽度上裁切，未显示的正文仍保留。ASCII 控制字符转义后
显示。普通多行草稿按一个消息提交，`.ask ` 前缀保留 Ask 语义；粘贴中出现 `.quit`
等文本不拆成命令。审批和 Model/Context 确认仍要求单行。

实际测试又发现并修复了两个接缝：原生层提前将单字节 Enter/Escape 分类，绕过新编辑器；
以及聊天行解析器拒绝整个多行草稿。证据保留在 `out/review-20261023/input/`，失败
日志未覆盖。首次本地构建因开发机缺少 readline 链接名而失败，改用已有 Lua 标准输入
入口构建测试核心；首次 inner 直接启动被外/内 executable 身份校验正确拒绝，随后使用
固定 luainstaller 的真实单文件封装继续测试，没有放宽产品校验。

### 当前验证

- `full-suite-final.log`、`windows-full-suite.log`：各 747/747。
- `final-pty80/`、`final-pty40/`：真实 Linux PTY，独立 pyte 屏幕解释器检查光标位置。
  两者均完成配置、补全、历史、中文插入、长行不覆盖历史、忙时草稿/光标保留、粘贴
  不提前提交、真实 Ctrl-C 取消 loopback Ask、退出及原始 termios 恢复。
- `final-dumb/`：普通输入与退出通过，确认没有发送 bracketed-paste 开启序列。
- `windows-openai-evidence/`、`windows-anthropic-evidence/`：两协议原生控制台旅程通过。
- `native-tests/`：Windows reader、worker 生命周期和输入故障回归通过；XP 宏编译通过。
- `comments-final.log`：275 文件 / 5868 声明 / 0 缺项；`readiness-final.log` 完整通过。
- 本机 Linux 回归核心 `input/linux/yaca` 的 SHA-256 为
  `b5db69a56f954119bb6af56ec5f4cb3230741a6a99df6015e002910cb1c15323`；Win64 核心
  `input/win64/package/yaca.exe` 为
  `b926cb074dec6c4ecc1346ccf648b896d366b380ac4bb8eb9ea65b51fa0f592b`。
  Linux 核心由当前 WSL 编译，用于本机回归，不能当作 glibc 2.17 发行包。

语义 Review 核对了输入事件预算、原始字节与领域动作的边界、粘贴分片与超限清理、
草稿/历史所有权、关闭后拒绝输出、stdout 失败时仍恢复原生状态，以及 ANSI 能力门禁。
ANSI 行为依据 [xterm 控制序列](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)，
屏幕验证使用 [pyte](https://pyte.readthedocs.io/en/latest/tutorial.html) 的独立解释器。
pyte/wcwidth 仅为固定版本的开发测试依赖，不引入产品运行依赖。

以上范围为本机 WSL 与 Windows；尚不证明 C7 实机/全部 SSH 终端/IME/动态缩放。
Linux 默认补全和忙时草稿已不再是空缺；Windows 忙时草稿、XP/Cygwin 输入增强与
后续 AgentLoop/目标资格继续留在 TRACKING。按 D-096，到今天 19:30 后的下一节点收尾暂停。

## 接续：Windows 原生草稿与输入恢复

Linux 输入节点提交为 `5c8a412` 后，真实 Windows 控制台复现了忙时草稿丢失：
模型回复到来前是 `>> .sta`、光标列 6，回复之后只剩 `>>`、光标列 3。
原始失败与屏幕保存在 `out/review-20261023/windows-input/before.log` 和 `before-evidence/`。

Windows 现在自动使用共享草稿编辑器与原生宽字符重绘。`console_redraw` 在输出前
完整捕获和校验帧，只清当前输入行，追加消息后恢复实际观察到的光标位置，不使用 ANSI。
原生按键将方向键、Home/End/Delete、Enter modifiers 投影到共享编辑器；原始按键批量
读取保持 text/Enter/paste 顺序，并受每 poll 编辑预算约束。

Ctrl-V/Shift-Insert 只请求 Unicode 文本：在打开剪贴板之前准备 Lua-owned 缓冲区，
严格转换 UTF-16、拒绝超限或不完整内容，解锁并关闭后才发布 Lua 事件。它不返回截断
前缀，也不把粘贴内的控制序列解释为按键。User32 导入只放行给 yaca_native.dll，
所用接口在 [Microsoft 文档](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getclipboarddata)
中支持到 Windows 2000。实际系统剪贴板没有被测试驱动读取或覆盖；格式、失败和所有权
由隔离夹具检验，真实延迟渲染与 IME 仍保留目标检查。

### 同时发现并修复

- 原控制台驱动启动后才记录模式，会把已进入的 raw 模式误当作恢复基线。改为独立隐藏
  host 在启动 yaca 之前记录模式，结束后再记录并核对；恢复证据不再依赖附着时机。
- 立即完成的工具结果分配了另一个显示 ID，Finalizing 清空 turn_id 后还会重复显示。
  现按 adapter/canonical ID 关联，并以已提交结果身份比较前后 trace；实际旅程要求每个
  结果只显示一次，沿用提议时的 tool-1/tool-2。
- 主动 Ctrl-C 的 canonical transport cancellation 被显示为 AskModelResponseError。
  现保留 cancelled 结果与已输出文本，不把已证实取消画成错误；协议错误和取消结果未知
  仍显示错误。实际延迟 Ask 取消与两类模型 lane 的反例均覆盖。
- 上一节点新增了 TUI 契约说明字段，却漏同步 `tui.registry()`。本轮完整测试以
  748/749 明确失败，已补齐运行时投影后重跑；失败日志 `full-suite-failed-registry.log`
  保留，没有将先前局部校验替代本轮全量结果。

### 验证与限定

最终证据均在 `out/review-20261023/windows-input/`：

| 检查 | 实际结果 |
| --- | --- |
| `full-suite.log`、`full-suite-win64.log`、`full-suite-win32.log` | WSL Lua、Win64 单文件、Win32 单文件各 750/750；Windows 两架构均在当前 Windows 宿主运行 |
| `win64-openai-final-evidence/`、`win64-anthropic-final-evidence/`、`win32-openai-final-evidence/` | 隐藏原生控制台；默认补全、历史、中文中间插入、Shift-Enter、忙时草稿/光标、工具纠错与结果 ID、Ctrl-C 取消、Context 重开和原始模式恢复通过 |
| `pty80-final/`、`pty40-final/`、`dumb-final/` | Linux 实际 PTY 与独立屏幕检查重跑通过，包含未提交草稿、粘贴、请求取消和 termios 恢复 |
| `native-tests/windows_editor_test.log` | 严格剪贴板文本、锁释放、快捷键、非法帧拒绝和 9 个 Lua 分配失败点通过；没有读取真实剪贴板 |
| 其他 `native-tests/` | cooked reader、worker 生命周期、输入故障及 54 个键盘分配故障场景通过；native leak/ownership error 为零 |
| `comments-final.log` | 276 文件 / 5891 声明 / 0 缺项；本批新增/改变契约已人工核对，整体语义 Review 仍 partial |
| `readiness.log` | 完整 coding readiness 退出零；包括设计/证据/公开文档检查与 TP-003/006/008/010、RP-001 |

最终本机候选及实际 PE 审计：`pe-audit.json` 核对 12 个 artifact 的导入与 subsystem，
User32 只出现在原生适配器中。核心 SHA-256：

| 核心 | SHA-256 |
| --- | --- |
| Win32 | `0964ce4bbdcdc2f4cec874055277fa05260d77046b465318806884e53bbaf1df` |
| Win64 | `7d2f086421b2047dfeaa793457d5d58f356d2626385987d842e14d395c027713` |
| Linux 本机回归 | `4e3755a20c74ef2314391835659bf5ffdce5b3a2b0999004279231134edbdfa2` |

Windows API 对照采用 [SetConsoleCursorPosition](https://learn.microsoft.com/en-us/windows/console/setconsolecursorposition)
与 [ReadConsoleInput](https://learn.microsoft.com/en-us/windows/console/readconsoleinput) 的原生边界。
Win32 按 XP 宏构建并检查实际 PE/导入，不能当作 XP 实机通过。既有 Server 2008 与另一
指定 Windows 远端的只读连接本次均超时，没有部署或改动远端；新核心的该目标证据保留待补。

本批只更新本地源码与回归候选，未改写远端发布。Cygwin、动态缩放、真实字体/IME、
剪贴板延迟渲染、长会话及正式三目标九包仍需继续，正式 Gate R 保持关闭。
