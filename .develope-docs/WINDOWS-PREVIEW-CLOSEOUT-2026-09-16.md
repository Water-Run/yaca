# Windows 首个可用预览收尾（2026-09-16）

本轮接续 ZCode 的 `9284f2f` 在线自检实现，完成剩余功能收口，并在用户指定的
`Administrator@192.168.5.10` 真实 Windows Server 2008 非 R2 x64 上验证。
现场 `ver` 为 **6.0.6003**；使用 `ssh -tt` 外加真实本地 PTY 与 `winpty cmd`。
把定时输入管道当控制台的旧方法会断连，本轮没有修改目标 SSH 配置。

## 实现与修复

- Model 管理器增加 `test <row-id>`；只测试已保存且未变化的连接，经明确确认后
  发出有限请求，显示隐藏凭据的地址、请求/token 上限及当前测试状态。
- 在线 Stage 2/3 绑定完整 ConfigGeneration，复用实际网络/Model adapter；
  Stage 2 验证 transport/auth/wire/stream/tools/control/cancel，Stage 3 仅建议。
- Stage 1 的原子发布检查使用独立随机文件，实际执行创建、flush、无覆盖重命名、
  verified replace、读取和按身份清理；不把功能测试写成断电持久性资格。
- 工具相对路径按绑定的 Context workspace 解析，并继续通过原路径/身份/权限检查。
- curl 聚合返回的 SSE 按有界块送入解析器，调整生产事件队列容量；字节限制保持生效。
- action review 是运行阶段，XML 的 Permission 决定仍只记 allow/confirm/deny；
  修复默认 DoubleCheck 下写入审批曾触发的 AgentDurabilityFailure。
- 修复自检禁止工具与惰性工具探针的提示冲突，以及主动取消被误报为连接失败；
  control 探针只接受一次具有精确参数且完整通过 schema 校验的 list 调用。
- M05-57 全名称 selector 只折叠 ASCII 大小写，Model/Permission 各自独立；
  配置引用、reviewer、`.model`、自检排除和 import mapping 保存规范原始名称。
- 控制载体中的 finish summary / refusal reason 现在显示为 Assistant 文字，
  不再因没有单独 text delta 而丢失；最终 outcome 仍由 Runtime/review 决定。
- Stage 3 仅接受完整的严格 `{"issues":[...]}`，畸形、额外字段和未完成响应均为 warning。

## 自动验证

最终平台无关 Lua suite **573/573**；design-contract/proof-evidence/coding-readiness
分别 **7612/56/553** 条断言通过。TP-003/006/008/010 与 RP-001 全部通过。
所有重型验证串行执行，先查看内存/pressure/遗留进程，再使用资源 guard。
源码缓存逐次 SHA-256 校验；Windows 构建串行且要求至少 5 GiB 可用内存。
没有在 Linux 上运行 Windows executable。

## Server 2008 + 真实服务商验收

连接为 `openai-chat`、`https://api.deepseek.com/chat/completions`、
`deepseek-flash`（DeepSeek V4.1 Flash），Streaming=force、RetryCount=0。
API Key 来自用户原授权位置，经私有 stdin 传输；不进入源码、包或证据。
配置保留 Std 写入/Shell confirm，DoubleCheck 默认开启。

N10（源码 `8bad5426a7bf4d6df55846bc0fb3498f2f636df7`）通过以下真实旅程：

| 项目 | 观察 |
| --- | --- |
| Stage 1 → 2 → 3 | outcome=passed, completed-stage=3, online-requests=10, auto-fixes=0 |
| Stage 1 | 15 项全部 passed，包括实际原子发布/清理 |
| Stage 2 | 7 项全部 passed，包括精确工具载体和 typed cancellation |
| Stage 3 | naming passed；config JSON shape 和 permission 建议为两项 warning；未自动修复 |
| Model 管理器 | 明确 TEST 确认后 connection test passed；重新 list 显示 test=passed |
| 名称解析 | `.model dEEPSEEK` 正确解析为 DeepSeek |
| 文件工具 | list `.`；经 action review + 一次审批创建 hello.txt；read 确认精确内容 YACA_TOOL_OK |
| Shell | action review + 一次审批执行 ver；exit 0，版本 6.0.6003，子进程已停止 |
| 历史恢复 | 正常退出；跨 workspace 明确 CONTINUE 后恢复；下一轮无工具正确复述文件与版本 |

N10 Context hash 为 `8DD524C1DA0F1422`。最终 XML 有 65 个连续 Event、
4 组 tool_call/tool_result、2 组 operation_intent/operation_result、
2 次 action review、2 次一次审批、3 次 termination review 和 3 个 completed turn。
真实中文 CMD 的 `ver` 输出为 GBK；按既有契约作为有类型 binary/base64 交给模型，
没有伪装成 UTF-8。N10 zip SHA-256 为
`02136a909cbd782c16eff935275afbb1678da031454c8464926f5dc1c0dd5584`。

## 复现与证据

- 本地日志/XML：`out/takeover-20260916/`（私有、忽略提交）。
- 构建入口：`.tools/qualification/build_windows_candidate.sh out/qualification/sources <new-output>`。
- 验证入口：`.tools/run_with_resource_guard.sh bin/lua55 test/run.lua`；
  `YACA_PROOF_SOURCE_CACHE=... bash .tools/run_coding_readiness.sh`。
- 运行在线自检必须是真实交互控制台；`--i-accept-online-self-test` 仅表达此次联网同意，
  不绕过 TTY gate。用户使用步骤见 [Windows quickstart](../release/WINDOWS-QUICKSTART.md)。

N8/N9 实测失败也保留在本地证据中；对应问题均以上述修复和 N10 成功旅程闭合。
这些是指定服务器的真实可用性证据。C32--C34 的 XP SP3 x86、Win7 SP1 x64、
CentOS 7 x64 全套资格/干净机旅程/最终正式发行证据仍未完成，Release Gate R 保持关闭。
