# 负责人答复原话归档：正式决策批次 06

received_at: `2026-07-22` (`Asia/Shanghai`；精确时刻未记录)

source: 当前项目会话；集中问卷与随后逐项收口

inventory_version: `decision-inventory-v9`

structural_sha256: `22e724986251bd63ae75e1c7964b3a2f6d3412a4e0f9b01019662790d68df6ef`

semantic_sha256: `80efc73d45ed32e05ea991f35a8cc484700a276f6664c77bc339c7957648b044`

inventory_git_commit: `909544c`

status: 29 个集中问题全部收到回复；后续最小补缝全部收口；没有待负责人回答的产品问题

## RB-006-01：集中问卷原始回复

```text
Win64也发布吧
1. A. 交给LLM自定义;
配置中, 可以设置:
全局System Prompt
Model级 System Prompt
Permission级 System Prompt
对于context, 可以设置context级上下文: 在context-repl中, 或者.prompt
2. A
3. 各个Prompt是独立的, 合并构造
4. A. 保持简单简洁
5. A. 保持简单的单线程架构
6. A. 简洁但有效
7. A. 比如发送可以.queue和.immidiate等, 考虑兼容快捷键不可用的情况(self-test也测试). 另外.queue可以删除在排序的
8. A. 同时三套: --完整, -和/的特别版本简洁
9. 不止OpenAI,也支持Anthropic
10. A
11. 最大兼容性, 考虑yaca目标的老旧平台, 没有HTTPS才是常态. 比如xp https可以提示安装stunnel
12. A
13. A, 类似OpenCode的统一封装
14. A
15. A
16. A
17. A
18. A
19. A
20. B
21. A
22. C, 保持简单, 不需要什么undo机制. 根据用户的要求来commit之类的. 一些模式的SystemPrompt指引放backup/之类的
23. A
24. B. 还是, 保持简单
25. C+完整recent
26. A
27. luainstaller打包二进制啊, 包中(如Windows)
yaca.exe
Install.cmd
README.txt
LICENSE
docs/
28. 之后改luainstaller就行
29. 同, 按照WinX86开发计划, luainstaller打包是最后的事情
```

`CQ-01..CQ-29` 按显示序号一一对应；`CQ-15` 是补缝而不覆盖旧原子组。`CQ-22` 的具体文字与字母 C 相反：负责人明确不要 Runtime undo、自动 stash/commit 或 Git 回滚，因此以具体文字为准，归一为“CQ-22 A 路线 + Prompt 文案补充”。`CQ-29` 的本条只给出实施时序，发布证据/签名/更新范围随后由 RB-006-06 明确收口。

## RB-006-02：Win64 范围确认

```text
允许
```

本回复针对以下具体提案：Win64 是 v0.1 独立 x86_64 zip，完整支持 Windows 7 SP1 x64 至 Windows 11；Win32 x86 包继续覆盖 XP SP3 至 Windows 11。两个 Windows 架构独立构建、完整测试和放行，使用相同外层布局；不承诺 XP/Vista 原生 x64，也不发布 ARM。

## RB-006-03：四层 Prompt 合并确认

```text
允许
```

本回复针对以下具体提案：所有 LLM 请求先取得独立的 `Global.SystemPrompt` 与当前 `Model.SystemPrompt`；main/side 再取得当前 `Permission.SystemPrompt` 与 `ContextPrompt`，当前用户消息保持独立 user message。组件带来源/版本/快照后按固定顺序构造，不互相覆写；Prompt 永远不能改变 Runtime 或 Permission 事实。特殊 purpose 使用固定 purpose Prompt，只继承 Global/Model；Permission/Context 内容在确有需要时仅作为有边界 quoted data。项目规则文件不自动加载，只在用户要求时由模型读取。

## RB-006-04：HTTP、HTTPS 与 stunnel 确认

```text
允许
```

本回复针对以下具体提案：发行包自带能够在目标系统运行的 TLS-capable curl 与 CA，不能依赖 XP 系统 TLS；用户显式配置的 `http://` endpoint 可用，保存和改变 endpoint 时警告 Key、Prompt 与回复为明文，绝不从 HTTPS 自动降级。stunnel 是 self-test 在 TLS 不可用时提示安装/配置的外部兼容选项，不随包、不自动安装；用户可以把 Model endpoint 指向本机 loopback stunnel。全局 proxy 保留；自动 redirect 只允许 same-origin，跨 origin 必须通过显式配置改变目标而不是请求中临时跳转。

## RB-006-05：便携包、邻接数据根与简单安装入口确认

```text
允许. 不用什么复杂的机制. Install.cmd就是检测目录是否合适, 不合适询问, 添加环境变量
```

Windows x86/x64 zip 根固定包含 `yaca.exe`、`Install.cmd`、`README.txt`、`LICENSE`、`docs/`。`yaca.exe` 可以原地运行，运行依赖最终由 luainstaller 嵌入；`__yaca__` 永远与可执行程序相邻，不维护另一套 installed 数据根、安装数据库、复制状态或 updater。`Install.cmd` 只检查当前目录是否适合作为长期运行位置；不合适时询问，用户确认后添加该目录到 PATH。Linux 包采用对应的 `yaca`/`Install.sh` 简单便携语义。

## RB-006-06：发布证据、签名与更新确认

```text
允许
```

本回复针对以下具体提案：Win32 x86、Win64 x86_64、Linux x86_64 三个 zip 各自独立放行，发布 SHA-256、最小组件/许可证 manifest、SBOM、构建摘要和该平台完整测试摘要；v0.1 不要求来源签名，不提供内建更新检查、下载或自动安装。升级由用户手工取得新 zip，程序不管理相邻 `__yaca__`。

## RB-006-07：Install.cmd 检查与 Context 浏览入口补缝

```text
Install.cmd也包括yaca程序检查, 不用MD5之类的复杂算法, 直接简单判断即可.
两个入口: recent和full
```

- `Install.cmd` 增加简单的 yaca 程序存在/可启动/基础检查；不使用 MD5、安装数据库或复杂完整性算法。目录适合性仍使用简单、可解释的存在/可写/运行判断。
- `context-repl` 有两个显式入口：`recent` 是快速最近列表，`full` 是完整目录树/全部 Context。两者进入同一详情、搜索、rename 与永久 delete 语义；没有 trash/restore。裸 `yaca` 仍不扫描 history/recent。

## RB-006-08：CLI、快捷键后备与 action registry 确认

```text
确认
```

本回复确认：

- 规范完整形式为 `--self-test`、`--model-repl`、`--config-repl`、`--context-repl recent|full`、`--continue`、`--help`、`--version`；`--` 结束选项解析。
- 跨平台提供唯一 `-` 简写；Windows 额外提供相同词根的 `/` 简写，Linux 不把 `/...` 当选项。
- chat 文本后备为 `.queue` 及其 `list|delete|move|edit|clear`、`.immediate`、`.side`、`.multiline`、`.cancel`；负责人原始示例 `.immidiate` 按正确 English 拼写规范为 `.immediate`，不保留错误别名。
- 快捷键、点命令、CLI、help 和补全由同一个 semantic action registry 投影。self-test Stage 1 检查终端输入能力；不能区分快捷键时提示文本后备，不把产品整体判为失败。

## RB-006-09：`backup/` 只是 Prompt

```text
只是个Prompt而以
```

`backup/` 不成为 yaca 的产品能力、配置字段、工具、Runtime 自动动作、恢复保证或数据目录。它只可能作为用户自定义的某个 Permission/System Prompt 中的普通文字；模型是否按该文字提出普通文件操作，仍服从现有 Tool、Permission、审批和用户指令。发行模板不因此自动创建、管理或清理 `backup/`。

## 归一化断言

### AS-006-01：交流与澄清由 Prompt 引导，Runtime 保持一个简单策略

默认交流采用 CQ-01 A 的结果优先、适度进度和真实完成报告；LLM 可以在有效 Prompt 内调整语气与详略。只有目标、安全、费用、不可逆副作用或公开结果会实质改变时才停下来询问，其余采用最小风险假设并披露。不存在独立 Autonomy 模式。

### AS-006-02：四个独立用户 Prompt 层和固定 request-purpose 边界

用户可配置 Global、Model、Permission 三层 System Prompt，Context 另有由 `.prompt`/context-repl 管理的 ContextPrompt。四者独立保存、独立快照并固定构造；更加具体的组件可以细化措辞，不能覆写 Runtime/Permission 事实。特殊 purpose 只继承 Global/Model instruction，其他 Prompt 仅在需要时作为 quoted data。

### AS-006-03：单 root、单 active Context、单线程事件泵

传入且可进入的真实目录就是唯一 workspace root，Git root 只作为证据。一个进程恰好一个 active Context；核心使用简单单线程状态机/事件泵，所有工具串行，协作式 I/O 不产生第二份可变领域状态。

### AS-006-04：单一追加式 TUI 与完整文本后备

规范 UI 是追加式 ASCII transcript、少量基础色/highlight、有界 tool/code/diff preview。异步输出不覆盖 draft；固定快捷键能用时启用，不能用时点命令提供完整等价动作。queue 可查看、删除、编辑、移动和清空；菜单使用编号与完整动作词，空 Enter 默认拒绝/取消。

### AS-006-05：三套 argv 拼写共享同一 action registry

`--` 完整形式、`-` 唯一简写和 Windows-only `/` 简写是同一 semantic action 的三个 parser 投影；Linux `/` 保留给绝对路径。非 TTY 只执行显式完整动作，绝不弹交互审批；稳定 machine output 仍由 CLI owner 定义。

### AS-006-06：首版同时支持 OpenAI Chat 与 Anthropic Messages

正式协议为 `openai-chat` 与 `anthropic-messages`，二者都必须完整实现 streaming、native tool/control、usage、error、retry 与 self-test fixture；不包含 OpenAI Responses，也不做自然语言 tool-call emulation。

### AS-006-07：配置保持完整但直接

一个 Model section 仍是一份完整连接实例，新增正式 `SystemPrompt`。Model 配置包含连接、能力、streaming、timeout/retry、输出限制、Description 和 adapter typed options；物理顺序决定默认。Permission 采用简单粗粒度 `Read/Write/Delete/Shell/OutsideWorkspace`，模板只有 Std/Readonly，真实矩阵决定行为。INI/XML 覆盖、逐 turn generation 与配置 REPL 继续共用一份 typed schema。

### AS-006-08：旧平台网络优先兼容但不伪装保密

显式 HTTP 允许使用，并在配置/修改时明确明文风险；HTTPS 不降级。发行 curl/CA 承担 TLS，stunnel 只是外部兼容提示。网络 retry 仍是 per-Model、有界、分阶段且在任何 canonical response event 后不自动重发。

### AS-006-09：三阶段 self-test 是完整诊断而不是自动修复

Stage 1 离线检查配置、文件、Context mapping/Catalog 性能、包内组件和终端快捷键能力；Stage 2 在 consent 后完整检查所有 enabled Model 的真实 auth/stream/tool/control；required checks 全绿才进入 Stage 3 advisory LLM 审阅。启动配置可选择最高阶段，但不能跳过依赖或同意边界。

### AS-006-10：typed AgentLoop、忙时调度与 DoubleCheck

Runtime 统一封装 `finish/ask-user/refuse`；普通无 control 完整回复是 `model-yield/waiting-user`。queue/steer/side/cancel 使用有界 scheduler；最多一个 side。`DoubleCheck=true` 始终包含 finish review，可配置是否再做 high-risk action review；两类 reviewer 可以使用各自 Model，失败/uncertain 不静默通过。`DoubleCheckGoal` 是完成验收目标，不是 plan artifact 或权限。

### AS-006-11：不可关闭硬上限和结构化 Context view

request/turn/process 有不可关闭 hard caps；配置只能在安全范围内收紧。retry 有界，无进展允许一次有界策略改变后进入 stuck。压缩使用结构化摘要前缀加最近完整 atomic groups，完整 XML 事实不删除；优先提示历史中已经使用且窗口足够的 Model，不自动切换。

### AS-006-12：固定 typed tools、简单 Permission 与 raw shell

首版固定 `list/read/search/write/patch/rename/delete/exec`；direct tools 是 typed envelope，`exec.command` 是 opaque 原始字符串，全部串行。raw shell 固定 Windows `cmd.exe /d /s /c`、Linux `/bin/sh -c`，只支持前台非交互，无 PTY、tracked background job 或 direct HTTP tool。没有 OS sandbox、持久 grant、SensitiveRead 或自动 undo。

### AS-006-13：文件/Git/backup 的真实边界

direct 写入使用 expected digest、no-replace/atomic publish 与 diff 证据；Git commit/push/reset/stash 只在用户明确要求时通过普通获批 shell 执行。Runtime 不自动备份、stash、commit、回滚或管理 `backup/`；`backup/` 只可能出现在用户自定义 Prompt 文本中。

### AS-006-14：单 XML、原位接盘与两种 Context 浏览入口

长期事实只有 INI/XML，允许短寿命 temp/lock/previous-valid，不使用长期 WAL。外来 XML 由用户先放入正确镜像位置，context-repl 原位验证/mapping 后取得 writer。浏览入口为 `recent` 与 `full`；使用树、搜索、rename 和永久 delete，不提供 trash/restore 或移动候选扫描。

### AS-006-15：错误和诊断不增加第三种长期文件或网络面

错误使用稳定 ID、简明消息与 `.details`，统一 close 如实保存 completed/interrupted/unknown。诊断只投影到终端、self-test/support stdout 和 Context XML；不生成 standalone diagnostic XML、独立日志、telemetry 或 upload，因此 ED-14 为 inactive branch。

### AS-006-16：三个独立 zip、邻接数据和简单安装脚本

v0.1 发布 Win32 x86、Win64 x86_64、Linux x86_64 三个独立 zip。Windows executable 原地运行，`__yaca__` 始终邻接；`Install.cmd` 只做程序存在/基础运行、目录适合/可写和 PATH 的简单检查/询问，不使用 MD5、安装数据库或 updater。Linux 对应简单便携布局。

### AS-006-17：发布证据完整，luainstaller 适配最后实施

每个包独立完整测试和放行，发布 SHA-256、组件/许可证 manifest、SBOM、构建与测试摘要；无来源签名和内建更新。Windows x86/XP 与 x64 qualification 在打包阶段进行，证据要求时允许对 `../luainstaller` 做最小、独立设计/测试/提交的适配；回答不表示现在开始修改兄弟仓库。

## 条件重算

- `TU-30=false`：TU-27 采用无通知路线，零 Notification 配置/事件表面。
- `ED-14=false`：ED-07 采用 stdout-only support，零 diagnostic upload 表面。
- `M05-26=true`：Model 保留 `Tools=native|off`，无工具 Model 资格规则生效。
- `M05-55=true`：raw shell 使用版本化 compatibility allowlist baseline。
- `AL06-08/24/25=true`：high-risk action review 存在时，其 Model/verdict/override 契约生效。
- `AL06-30/31/34/39/47=true`：structured compaction 路线生效。
- `AL06-43=false`：v0.1 不计算金额，不产生 amount admission/warning 配置。
- `TS-21=false`：不存在 SensitiveRead 字段、分类器或页面。
- `TS-25/26/28/29/31/34/35=true`：完整 direct write/rename/delete 路线生效。

## 冲突检查结论

唯一候选文本冲突来自 `CQ-16 A` 的“finish 可单独关闭”，它违反此前 D-027。项目负责人选择的是总 `DoubleCheck` 路线，且先前明确总开关包含完成复核，因此归一为：`DoubleCheck=true` 时 finish review 永远启用；只有 high-risk action review 可单独配置。没有产品行为需要重新询问。

`CQ-22 C` 与同一回复的具体说明也冲突；具体说明清楚排除了 C 的 Runtime Git/undo 行为，因此归一为 CQ-22 A 加“backup 只是一句 Prompt”补充。RB-006-09 进一步消除了任何备份产品机制解释。
