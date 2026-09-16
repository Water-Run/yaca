# 基本可用验收与 N13 交付（2026-09-16）

指定的 Windows Server 2008 非 R2 x64（6.0.6003）已完成真实模型驱动的代码修复、
验证、文件管理与两次进程重启后继续执行工具。N13 是本次最终可用预览。
此前 N8--N11 的实现、在线自检与管理器测试见[早期收尾记录](WINDOWS-PREVIEW-CLOSEOUT-2026-09-16.md)。

本次结论限于首版基本可用及指定服务器。XP SP3 x86、Win7 SP1 x64、CentOS 7 x64
的 C32--C34 全套资格仍待执行，机读状态为 `implemented-unqualified`，Release Gate R 关闭。

## 验收范围与证据

| 要求 | 实际结果 |
| --- | --- |
| 独立便携程序、旧终端、配置及本地文件操作 | N13 实机 Stage 1 的 15 项全部 passed，online-requests=0，含实际原子发布与清理 |
| 真实服务商与流式回复 | DeepSeek / openai-chat / deepseek-flash；N13 main、action review、termination review 均实际联网成功 |
| 在线自检与 Model 管理器 | N10/N11 Stage 2 全部 passed，Stage 3 完成并保留 advisory warnings；N10 管理器经 TEST 确认后 connection test passed |
| 完整代码修复 | N11 先 list/search/read，再 exec 观察 RESULT=35、exit 1；patch 仅修改一行，复跑 RESULT=42、exit 0 |
| 文件管理 | N11 read 后 rename notes.txt 为 CHANGES.txt，delete 仅删除 scratch.txt，再 list 验证；N13 write VERIFY.txt 后 read 精确核对 |
| 权限与审查 | Std 的 Write/Delete/Shell confirm；默认 DoubleCheck 与 action review 保持开启，副作用逐次 allow once |
| 保存与恢复后执行工具 | 同一完整 Context 在 N13 两次退出再打开；审批依次为 8、9，再次重启后为 10，全部成功写入历史并执行 |
| 完成判定与错误恢复 | 四个工作 turn 最终均 completed；N13 两次终审均 pass；既有工具错误保留且由模型修正后重试 |
| 未决审查的用户提示 | N12 起明确显示 termination-review 的澄清/取消入口及 action-review 的取消后修改入口；集成测试覆盖两种状态 |
| 自动回归与证明 | Lua suite 575/575；design/proof/readiness 7612/56/553；TP-003/006/008/010、RP-001 全部 PASS |
| 交付完整性 | 干净源码构建；本地/远端 executable SHA-256 一致；便携包不含 config.ini、Context 或已注册 Key |

Windows executable 始终只在授权服务器运行。控制台由真实本地 PTY、`ssh -tt` 和
`winpty cmd` 提供。配置密钥沿用用户授权位置，经私有通道设置，未进入源码或发行包。
重型本地测试、证明和 Windows 交叉构建串行执行，均先检查资源并使用 resource guard。

## 恢复审批故障及修复

N11 原先的恢复验收仅验证继续回答历史。本次扩大为真实工具操作后，N12 在第一次
`allow approval-1 once` 处触发 AgentDurabilityFailure：ApplicationCoordinator
重启后重新分配 approval-1，但旧 XML 已有 approval-1 至 approval-7；schema 拒绝重复。
失败发生在新操作 intent/执行之前，没有冒充成功或重放旧操作。失败 XML 保留为
`out/takeover-20260916/coding-n12-failed.xml`，未手工改写或强行继续。

提交 `8bbef191ba525699bad79b00dc924f804aca6041` 从已验证历史的规范 approvalId
提取最大编号，经 existing Context receipt 传入 Agent，协调器从该编号继续分配。
最大值独立于八类 Runtime serial；非规范导入 ID 不计入，乱序、defer、编号耗尽均
有明确处理。历史批准仍仅作审计，新的操作仍需本次审批。XML 格式没有变更。

测试覆盖 schema 最大值投影、publication receipt、生产 Agent 组合及协调器。
另一提交 `953c16e24e7934f95a5852e7ecadb3686b784c60` 补齐未决 review 提示，
并同步 README/实施计划/readiness 的阶段标记，保持目标资格待完成的真实状态。

## 代码、文件与持久化结果

测试仅使用独立 `coding-smoke` 目录。脚本唯一改动为：

```diff
-set /a RESULT=7*5 >nul
+set /a RESULT=6*7 >nul
```

原脚本包含 `if not "%RESULT%"=="42" exit /b 1`。修复前实际 stdout 为
`RESULT=35\r\n`、exit 1；修复后及两次恢复执行均为 `RESULT=42\r\n`、exit 0，
stderr 为空，子进程已停止。文件仍为 103 bytes，全部 CRLF 保留。

模型曾先调用依赖 PATH 的 `cmd` 包装，得到 shell 错误；改为直接运行 multiply.cmd
后才观察到算术失败。第一次 patch 行锚不匹配得到 PatchConflict，模型重读后修正锚点。
上述失败没有被删去或算作成功。

| 最终文件 | 精确结果 | SHA-256 |
| --- | --- | --- |
| multiply.cmd | 修复后的 103 bytes，CRLF | `77b4c25b42d03148d5d0cdc21f70e6d2f74b2006474d2cbc009c5c8401a4549f` |
| CHANGES.txt | 原 notes.txt 内容 `version one\r\n`，13 bytes | `142948ac233e0563ba1984966c009f4a938808d395bbdee55acc9250bc529657` |
| VERIFY.txt | `BASIC_USABILITY_OK`，18 bytes，无末尾换行 | `ff015500442e204ccf5a507c5220d2cc84c245cac8659b63d409e371ec0f1112` |
| scratch.txt、notes.txt | 均不存在；scratch 已删除，notes 已重命名 | — |

Context hash 为 `56E362DBD1B1831E`。N13 使用关闭后的干净 N11 XML 副本，
保留原 workspace 绑定；跨目录打开均确认精确 CONTINUE hash。最终 XML 为 **201 条
连续事件、21 对工具调用/结果、10 对操作 intent/result、10 个唯一审批 ID、4 个
completed turn**，覆盖全部八种工具。前 142 条事件与 N11 原记录逐项相等。
两次恢复后的 exec 均 exit 0；退出后无遗留锁、previous 或自检临时文件。

最终 XML SHA-256：`78b4a41eefff4cd7bb8df5ab0d856a8086eb8dfe8f90ba8c492cc6c634e8fd81`。
归档与校验位于忽略提交的 `out/takeover-20260916/`：
`coding-n11.xml`、`coding-n12-failed.xml`、`coding-n13.xml`、
`coding-n13-verification.json`、`coding-n13-files.json`、`remote-n13.ansi.log`。

服务商仍可能不按严格 review JSON 契约回答。N11 已观察到 uncertain，并在澄清后
通过；此时界面会说明恢复方式，未决任务不会被标记完成。Stage 3 建议也不是硬失败，
不能将历史在线验收描述成“所有项目均无警告”。

## 最终交付

N13 基于干净提交 `8bbef191ba525699bad79b00dc924f804aca6041`，构建记录的
`source-changes.patch` 为空。后续提交只更新验收文档，不改变该 executable。

| 产物 | SHA-256 |
| --- | --- |
| `yaca-0.1.0-preview-win32-x86.zip` | `76d38241e276a1a8b412ae0623d69bd36e1a5a2fe93b4f2ce35c3608ed61a6f9` |
| `yaca-0.1.0-preview-win32-x86-source.tar.gz` | `cb30663f1b91610cab3e0dd779a46a9c12fbbcfef462e9513c06846aa5348af7` |
| executable `yaca.exe` | `136feb2ea7abe507f2a777ad01d7fd9f4a0f3a4f3652a2c6d9a73e327eed7920` |
| 项目快照 `yaca-source.tar.gz` | `90a39b8a3888ea3d4e6113e004fc0e00811acd22b020b431298fa65dad32c952` |

本地产物目录：`out/windows-preview-20260916-n13/`。服务器已解压至
`C:\Users\Administrator\yaca-0.1.0-preview-n13`，私有配置已就位；可新建工作会话：

```bat
cd /d C:\Users\Administrator\yaca-0.1.0-preview-n13
yaca.exe work
```

使用方法见 [Windows quickstart](../release/WINDOWS-QUICKSTART.md)。测试日志为
`full-suite-n13.log`、`readiness-n13.log`、`build-n13.log`；构建入口为
`.tools/qualification/build_windows_candidate.sh out/qualification/sources <new-output>`。
