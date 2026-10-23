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
