# 决策包 07：Tool Calling、安全、进程与旧平台运行时

更新日期：2026-07-22

状态：等待项目负责人回复；本文所有方案、表格、命名和推荐均为候选

## 本包要解决的真实问题

“像 Codex 一样让模型调用原始工具”和“不要复杂 sandbox”已经给出清楚方向，但仍不能直接编码。至少要回答：

- 模型究竟看到哪些工具；raw shell 与 direct file tools 为什么可以同时存在。
- `Readonly/Std/...` 的每个设置真实约束什么，哪些对 shell 根本无法约束。
- raw shell 的 command 是 JSON 对象中的 opaque string、bare text，还是和 direct tools 一样由自由文本二次解析；工具参数、审批、DoubleCheck、durable operation 和实际执行的先后顺序。
- 取消、崩溃或断流后怎样区分未执行、已执行和 unknown。
- XP/CentOS 上怎样同时读取模型流、键盘、stdout/stderr 并终止进程树。
- direct file tools 怎样避免覆盖用户刚修改的文件、链接逃逸和特殊文件副作用。
- 首版是否承诺自动 undo；如果不承诺，仍提供哪些可靠保护。

这不是“多包一层就更安全”的设计。目标是把模型的能力保持直接，同时让 Runtime 对自己真正能强制的边界说实话。

## 已确认路线与被排除的总体对照

### 已确认路线：少量 direct tools + 一个 raw shell + 确定性权限

模型看到：

- list/read/search；
- create/write/patch/rename/delete；
- `exec(command, cwd, timeout)` 原始 shell。

direct tools 有结构化目标、expected digest、no-replace 和清楚的 capability；raw shell 统一属于宽 `Shell/Execute`，不尝试解析命令后宣称它受 Read/Write/Network 细分隔离。yaca 自己启动 curl/native helper 时不走模型 shell，而走内部结构化 process port。

权限先做确定性 deny/confirm/allow，`DoubleCheck` 只能追加否决，人工批准绑定精确动作。同一 batch 的启动并行度只投影 TS-10，observed failure 后尚未开始调用的 admission 只投影 TS-20；公共不变量仅是每个已接受 call 恰好产生一个真实或 synthetic terminal result。Runtime 只承诺安全写入、冲突检测、diff/事实记录和不自动重放 unknown，不承诺通用自动 undo。

优点：符合“简单、直接、相信模型”；权限与实际 enforcement 一致；非 Git 目录也完整工作。代价：允许 raw shell 本来就是广泛授权，用户不能同时要求 Shell=allow 又声称 Network/Write=deny 能隔离它。

### 已排除背景：只有 raw shell

模型通过 `cmd.exe`/`sh` 完成 read、search、patch、delete、Git 等一切操作。工具面最少，模型自由度最高。

问题是 Runtime 无法得到稳定的文件目标、expected digest、调用/result 配对和安全 diff。只读 profile 只能完全禁止 shell；任何写入都缺少跨平台一致的 no-replace/冲突契约。模型还必须依赖 XP/CentOS 上实际存在的外部命令。

它看似最简单，实际把路径、编码、文件类型、输出截断和恢复复杂度转给 Prompt 与宿主工具，不适合作为完整 Coding Agent 唯一能力。

### 已排除背景：所有动作包装 + 强 sandbox/事务

模型不能调用任意 shell，只能使用很多细粒度 wrapper；所有写入进入 shadow workspace/preimage journal，命令运行在 OS sandbox/overlay 中。

安全承诺最强，但 XP 与 CentOS 7 没有统一的现代 sandbox/overlay；wrapper 数量、维护成本和行为差异也违背当前“原始工具、保持简单”的方向。可作为未来另立项目的执行环境，不适合 v0.1。

### 总体推荐

推荐方案 A。这里的关键不是 direct tools 比模型更聪明，而是它们让 Runtime 能提供少量、真实、可测试的保证；无法细分的高级动作仍交给 raw shell。

## 候选模型可见工具表

名字与字段还需在命令冻结阶段确认，下面先决定能力面：

| 候选工具 | 核心参数 | Runtime 可真实保证 | 不承诺 |
| --- | --- | --- | --- |
| `list` | path、depth/page | 有界、稳定结果、文件类型 | 全盘索引 |
| `read` | path、range | 普通文件、字节/文本边界、digest | 自动识别所有 secret |
| `search` | pattern、paths、limits | 有界结果、控制字符处理 | 任意二进制语义 |
| `write` | path、content、expected digest/create mode | no-replace 或版本匹配、安全 replace | 多文件 ACID、自动 undo |
| `patch` | 文件边界、上下文、expected digest | 全部校验后单文件原子失败 | 任意脚本 patch |
| `rename` | source、target、expected identities | 默认 no-replace、链接/跨设备显式结果 | 跨文件系统原子性 |
| `delete` | target、expected identity | 类型/身份复核、明确结果 | shell 产生的所有删除可追踪 |
| `exec` | raw command、cwd、timeout | 固定 shell 方言、输出/进程状态、取消请求 | 命令内部只读、无网络、可回滚 |

Git status/diff 可以作为 Runtime/TUI 的只读展示适配器；模型仍可通过 `exec` 使用 Git。v0.1 不需要为 commit/reset/stash/push 各建模型 wrapper，也绝不因任务结束自动执行它们。

## 模型 raw shell 与 Runtime process port

这是两个不同层次：

```text
model tool:
  exec("git diff && make test", cwd)
      -> Windows cmd.exe / Linux /bin/sh

runtime internal port:
  spawn(executable=".../bin/curl", argv=[...], stdin=...)
  spawn(executable=".../helper", argv=[...])
      -> never parsed by a shell
```

推荐固定 Windows `cmd.exe`、Linux `/bin/sh` 的经测试调用契约，不继承 PowerShell/bash 作为隐式方言。XP 不保证 PowerShell，兼容 Linux 也不应让模型猜默认 shell。

Runtime internal port 使用明确 executable、argv、cwd、env、stdin source、stdout/stderr limits 和 deadline。它是网络/helper 的基础设施，不是第二个模型工具；因此既不增加模型选择负担，也避免 Key 与内部参数经过 shell quoting。

## 一个 tool call 的完整生命周期

```text
provider response complete
  -> validate all call IDs / JSON / schemas / limits
  -> canonical assistant response durable
  -> call accepted (local tool_call_id)
  -> deterministic Permission
       deny -> synthetic denied result
       confirm/review -> next step
  -> optional DoubleCheck action review
       reject/uncertain -> synthetic result or typed human-resolution path
  -> optional human approval of exact snapshot
  -> durable operation intent
  -> execute
  -> capture actual completed/failed/cancelled/unknown result
  -> durable result
  -> next main-model request
```

不允许在 streaming arguments 看似闭合时提前执行。这里的 `accepted` 只表示完整 call 已通过 response/schema admission 并成为 canonical call fact，不表示已经取得 Permission 或获准执行。一个 response 有多个调用时，先冻结 call 顺序、ID、schema 与 batch identity；哪些已接受调用可以同时启动只由 TS-10 选择，observed failure 后哪些尚未开始调用继续或形成 `skipped` 只由 TS-20 选择，steer/cancel 的目标与收口另服从 AgentLoop。无论选择怎样组合，每个 accepted call 最终恰好有一个 `completed|failed|cancelled|unknown|skipped|denied` 的真实或 synthetic result；模型历史不出现只有 call 没有 result，也不为同一 call 追加两个 terminal result。

候选状态词：

```text
accepted
validating
waiting-approval
running
cancel-requested
completed | failed | cancelled | unknown | skipped | denied
```

`cancel-requested` 不是 `cancelled`。命令可能在取消到达前已经完成，也可能留下无法确认的外部副作用。

## Permission 的诚实能力矩阵

当前建议把 direct tool 能力与 raw shell 分开：

| 动作 | 权威能力 | Readonly 候选 | Std 候选 | 最信任 profile 候选 |
| --- | --- | --- | --- | --- |
| 工作区 direct list/read/search | `Read` | allow | allow | allow |
| 敏感候选 direct read | `SensitiveRead`（仅 M05-56 B；否则仍只用 Read） | confirm | confirm | allow |
| direct create/write/patch | `Write` | deny | confirm | allow |
| direct delete | `Delete` | deny | confirm | allow |
| direct rename | `Write` + `Delete`；外部再加 modifier | deny | confirm | allow |
| raw `exec` | 宽 `Shell` | deny | confirm | allow |
| Model provider HTTP | 当前 Model 配置 | allow | allow | allow |
| direct HTTP tool（仅 TS-11 B/C） | `DirectNetwork` | deny | confirm | allow |

第一 Permission section 已确认是默认，Std 候选仍放第一。profile 名称、是否内置最信任 profile、颜色和具体默认值仍待确认。

如果首版没有 direct HTTP 工具，`Permission.DirectNetwork` 没有真实消费者，必须不显示。若 M05-56 选择 A，该行也从正式矩阵消失，普通 direct read 只消费 Read。M05-16 的 A/B 只改变 outside modifier 是一列还是三列，不改变本行是否存在。raw shell 内运行 curl 仍由 `Shell` 决定，不能让 DirectNetwork=deny 给出虚假保证。

项目负责人此前说“不需要 sandbox”，所以本文不会宣传 OS 隔离。Permission 是 yaca 是否发起某个已知动作的策略，不阻止获准 shell 的内部行为，也不防御用户自己从另一个进程修改文件。

## 审批绑定与页面候选

人工批准至少绑定：

- tool 名称/schema 版本；
- 完整规范参数或 raw command；
- cwd 与目标规范/物理身份；
- `ExecEnvironmentSnapshot` 的公开部分：mode、baseline ID/version、source、canonical 变量名集合/public digest；以及只在进程内参与 stale 判断的 private environment-generation binding；
- Permission/profile/DoubleCheck snapshot；
- operation ID；
- 文件 expected digest/身份；
- 允许范围和期限。

任一安全相关输入、文件身份、配置或工具版本在等待期间变化，旧批准失效。下面只演示这一领域事实的页面投影：方括号 block、`approval>`、空 Enter=deny 和带精确 action ID 的完整 verb 分别投影 TU-20 A、TU-33 B、TU-07 A 和 TU-34 A。选择其他 TU 路线时必须生成对应 chrome/prompt/default/approval grammar，TS 包不拥有这些拼写。

```text
[TOOL 17] exec
  cwd: C:\Work\yaca
  command: git clean -fd
  environment: inherit / compat-allowlist-v1 / 12 names
  env details: values hidden; exact generation bound to this action
  capability: Shell
  warning: may read, write, delete, access network or paths outside workspace
  status: waiting-approval

[ACTION 17] Approve tool 17?
  allow 17 once
  deny 17              (Enter default)
  details 17
approval>
```

为保持简单，当前推荐人工授权只有 once；想减少确认可切换 Permission profile。是否增加 turn scope 单独决定，不提供永久 project/always 记忆。

M05-55 B/C 必须在第一条 raw-shell 风险说明及每个 approval details 中追加明确警告：unknown ambient credentials 可能进入获准进程，变量过滤不是 sandbox。A 也必须说明 allowlist 只限制结构化继承，获准命令仍可读取用户本来有权访问的文件或凭据工具。界面只显示公开名称/类别，不显示值；baseline/mode/name set 或 private generation 的任一变化都会生成新 action identity，使旧 review、approval 与 grant stale。

## DoubleCheck 与人工审批

`DoubleCheck` 不是新 Permission，也不授予能力。动作候选顺序：

```text
Permission -> action reviewer -> human approval -> durable operation -> execute
```

reviewer 无工具，输出 typed `allow|reject|uncertain`，可另带不具授权力的 `suggested_revision` 文本。reviewer 永远不能原地修改 canonical action：reject/uncertain 按 AL06-24/25 形成 synthetic result 或进入 typed human-resolution；若主模型采用建议，必须提交新参数、新 action ID 并重新走完整 Permission/review/approval。无效输出/超时/网络失败经过有限重试后等待用户，不当作通过。

若 reviewer 自身故障，候选允许用户只对这个精确动作 bypass once；UI 必须展示故障与风险，XML 记录 override。多个 tool calls 逐项复核/批准，不能一个模糊的“全部允许”授权尚未展示的后项。

结束复核属于 `termination-review`，与 `action-review` 是不同 request purpose；二者共同受总 `DoubleCheck` 开关，但 verdict、视图和控制流不同。

## 文件、链接与执行时复核

direct file tools v0.1 候选只处理普通文件和真实目录。device、FIFO、socket 等特殊对象拒绝；用户确需高级操作可在宽 Shell 授权下自行承担。

路径检查不能只有字符串前缀：

1. 规范化逻辑路径并解析当前物理目标。
2. 显示 symlink/junction 目标是否越出工作区。
3. 记录文件类型、digest 和可用的身份事实。
4. 审批后、执行前通过打开的对象/父目录重新复核。
5. 目标被替换、链接改变或 hardlink 身份不再匹配时返回 `TargetChanged`。

[`GetFinalPathNameByHandleW`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfinalpathnamebyhandlew) 最低是 Vista，Windows XP 不能直接把这个现代 API 当统一实现。平台后端需要经原型验证的 XP fallback；无法安全证明时应拒绝该 direct 操作，不得静默降低为字符串前缀。另一方面 `ReplaceFileW`/`MoveFileExW`/`FlushFileBuffers` 有 XP 候选基础，但原子性与掉电语义仍须目标文件系统实测。

## 写入保证与 undo 边界

当前推荐的 v0.1 保证：

- read 返回 digest；write/patch 带 expected digest；create 是 no-replace。
- 单文件临时写、验证、flush、安全 replace；失败保留旧文件。
- rename/delete 执行时复核目标身份；跨设备/非原子情况显式报告。
- operation/result/diff 记录真实状态；unknown 不自动重放。
- Git/非 Git 均可审阅 Agent 有证据归属的改动。

当前不推荐承诺通用 automatic undo/preimage。完整 preimage 会把源码、秘密和大二进制复制到单 XML，扩大 O(n²) 写放大，也无法覆盖 raw shell。若项目负责人选择强 undo，必须同时批准附件/存储、配额、秘密、导出和跨机迁移方案；不能只在 write tool 中顺手保存一份。

## 旧平台事件泵不是可选装饰

要在模型流式输出时接收 queue/steer/side/Esc，并实时读取 shell stdout/stderr，Lua 领域核心不能直接阻塞在 `io.read` 或 `popen`。

推荐架构：

```text
Lua single-owner state machine
       ^ bounded typed events
       |
platform I/O port
  console | pipe stdout/stderr | process exit | network/helper | wake/cancel
```

原生 ABI 候选只暴露 `start/poll/cancel/join/close` 与 operation ID，不拥有 Config、Permission、AgentLoop 或 XML tables。平台后端可用 OS 异步 I/O、极小线程或 helper 等待，核心仍按单一事件序列推进。

Microsoft 官方资料确认：[ReadConsoleInput](https://learn.microsoft.com/en-us/windows/console/readconsoleinput) 最低 Windows 2000，并可把 console input handle 交给 wait；[GetQueuedCompletionStatus](https://learn.microsoft.com/en-us/windows/win32/api/ioapiset/nf-ioapiset-getqueuedcompletionstatus) 支持 XP；Job Object 与 [TerminateJobObject](https://learn.microsoft.com/en-us/windows/win32/api/jobapi2/nf-jobapi2-terminatejobobject) 支持 XP。另一方面，[CancelIoEx](https://learn.microsoft.com/en-us/windows/win32/api/ioapiset/nf-ioapiset-cancelioex) 和 [CancelSynchronousIo](https://learn.microsoft.com/en-us/windows/win32/fileio/cancelsynchronousio-func) 最低 Vista，XP 后端不能先阻塞同步读取再假设能跨线程取消。

这些事实只缩小方案空间，不代表实现已经证明。实施前最小原型必须同时验证：

- console 输入与模型/curl 流并行；
- stdout/stderr 双管道不会互相死锁；
- Esc/`.cancel` 到可见反馈有界；
- shell 及子孙进程树在 XP/CentOS 可收口；
- cancel 与自然完成竞态最终得到唯一 completed/cancelled/unknown；
- 队列满时暂停/截断而非耗尽 Win32 x86 内存；
- 关闭 helper/port 不永久卡住 event loop。

项目负责人需要确认可接受的体验与退路，不需要现在替实现选择 IOCP、线程或具体 API。

## Key 与 curl 的交叉边界

Key 已确认可以明文长期存 INI；Runtime 从 typed registry 结构化取得的 config-secret value 只能进入该 consumer 登记的精确私有 carrier，任何路线都不能把它复制到 argv、XML 字段、普通日志、审批命令或 error text。普通用户/模型/文件/工具正文中碰巧出现相同 bytes 是另一类 ingress，只按 M05-59 最终路线纳入 ordinary-content 扫描的 eligible patterns 处理；M05-59 B 明确豁免的过短 coincidence 可能进入 XML，不能被本节的结构化 carrier 禁令误报成“已全局排除”。subprocess curl 仍需要同时得到网络 auth secret 与 JSON body，候选三路是：

1. curl config 走 stdin，body 放私有临时文件；
2. body 走 stdin，secret config 放私有临时文件；
3. 窄 libcurl/native bridge，Key 只在进程内。

技术侧先比较 XP 文件权限、curl stdin 行为、取消和崩溃残留，优先选能以 subprocess 安全闭环的最小方案；只有 1/2 无法满足才增加 3。临时文件使用 data-root 私有 temp、随机 no-replace、最小权限、manifest 和启动残留回收。

typed secret registry、命令、文件内容、审批和 tool result 在 main/side/reviewer/compactor、TUI、XML、stderr 与 export 之间的完整边界见 [数据分类候选](../DATA-CLASSIFICATION-CANDIDATE.md)。

## unknown 副作用的恢复页面

下列方括号 warning/action label、编号动作和 `recovery>` 分别投影 TU-20 A、TU-08 B 和 TU-33 A；`Keep it unknown` 是 unknown-operation 领域安全默认，不是 TU-07/TU-34 的 approval 默认或 grammar。本节只拥有 unknown operation 的事实、允许动作和安全默认；其他 TU 路线必须生成对应 label/prompt/selection grammar。

```text
[WARNING] Operation 28 has no recorded result.
  tool: exec
  cwd: C:\Work\demo
  command: build.bat
  started: yes
  termination confirmed: no

[ACTION 28]
  1  Confirm it completed
  2  Confirm it did not complete
  3  Keep it unknown             (default)
  4  Inspect Context read-only
recovery>
```

用户的解算产生新的 durable event，不改写旧 operation；“确认未完成”也不自动重放命令，是否再次执行仍是一个新动作。

## Tool Calling、安全与进程的 35 个负责人决策组

可以回复 `TS-02 A；TS-04 的 Std Shell 改为 deny；其余接受推荐`。TS-01/TS-03/TS-06/TS-09/TS-15 是已确认边界、跨包投影或技术证明门，不接收选票；未回复的正式组继续待决。TS-21 只有在 M05-56 B 时生效；M05-56 A 下记为 not-applicable。

## TS-01 已确认的工具表面（不是负责人投票）

D-034 已确认模型直接调用少量 raw/direct tools，raw shell 是一个诚实的宽能力工具，不提供强 sandbox 或领域 wrapper 语言。本包只问 exact registry、结果、Permission 与失败行为；不能再选择“只有 wrapper + sandbox”来暗中修订已确认边界。

### TS-02 首版 exact tool set

- A：list/read/search/write/patch/rename/delete/exec 全部进入完整 Coding Agent 闭环。（推荐）
- B：list/read/search + exec；文件修改通过获批 raw shell，仍保留结构化只读证据。
- C：list/read/search/write/patch + exec；rename/delete 只通过获批 raw shell，首版 direct registry 更小。

推荐 A。B/C 缩小 direct surface，却相应失去部分 expected-digest/no-replace 保护；三项都保留 raw exec 并遵守同一 Permission/operation 契约。

关联：`AQ-033`、`AQ-111` 至 `AQ-119`、`AQ-184`、`TOOL-01`、`TOOL-02`。

### TS-23 raw shell 与 direct tool 的输入 schema 边界

通俗场景：“原始工具”可能只是指 shell command 不被 yaca 改写，也可能被误解为所有工具都接收一段自由文本。前者仍能在执行前知道目标字段、拒绝畸形参数并把 exact call 写入 XML；后者会让路径、expected digest、timeout 和审批目标都依赖另一套模糊文本解析。schema 是通信边界，不是 sandbox，也不代表 Runtime 理解 command 内部会做什么。

- A：所有工具调用都有版本化 JSON object envelope；direct tools 使用各自严格字段，`exec` 使用一个必填 `command` opaque string，并可按独立 owner 的有效选择条件携带 `cwd`、`stdin_text` 和只会收紧的 deadline。Runtime 校验 envelope/大小/类型/unknown key 后原样把 command 交给 TS-13 选定的 shell，不分词、不重写、不从文本推断 Read/Write/Network。（推荐）
- B：direct tools 使用严格 JSON object；`exec` 的整个 arguments payload 是 bare raw text，没有 JSON object。只有所选 Model 协议能无损表达 free-form tool arguments 时才可暴露 `exec`，call ID、预算与 operation metadata 仍在协议 envelope 外层配对。
- C：direct tools 与 `exec` 都接收自由文本，再由各工具 parser 解释 path/content/command；每个 parser 必须有版本、上限和确定错误，但不提供 JSON 字段级 schema。

推荐 A。它最符合“模型直调清楚、原始而有界的工具”：shell command 仍是完整原文，同时 direct file tools 保有确定参数，OpenAI-compatible function/tool carrier 也能统一表达。B 的 shell 最接近纯文本 REPL，却使 provider capability 与 schema snapshot 分叉；C 表面简单，实际重新发明多套命令语言并削弱审批、冲突检测和恢复。

共同契约：任何选项都必须在 Model 请求前发布 exact tool registry/schema identity，在 response admission 时先完成 call ID、大小、encoding、required/unknown/type 校验，校验失败不得建立可执行 operation。TS-02 的每条候选 core registry 都包含 `exec`；因此 B 与不能无损承载 bare payload 的 Model/Protocol 静态不相容，C 与不能为每个 core tool 无损承载 free-text payload 的 Model/Protocol 同样不相容，对应 Model 不能承担需要 core registry 的 main Agent。Runtime 必须在配置/资格检查中报告 carrier mismatch，绝不能只为这个 Model 静默隐藏 `exec` 或缩水 registry。已接受 call 必须按 LOOP-13/TOOL-06 产生真实或 synthetic result；Context XML 保存模型当时看见的 registry/schema digest 和 canonical accepted arguments，使跨机 reader 能解释历史。schema 不能授予 Permission、不能让 reviewer 扩权，也不能把 shell 文本解析成虚假的细粒度 capability。F4-07 独占 stdin，M05-15/M05-55 独占环境，TS-37 独占 cwd state，F4-11 独占超长 command transport，TS-13 独占 shell dialect；本组只拥有模型到 Runtime 的 input carrier。

#### Canonical scalar 到 XML-safe carrier 的 admission 契约（技术不变量，不投票）

无论 A/B/C，Protocol adapter 都先把每个 text scalar 交成“有效 Unicode scalar sequence 的精确 UTF-8 bytes + present/empty 身份”；不得做 NFC/NFD、大小写、斜杠、CRLF、尾空格、引号、反斜杠或 shell escape 规范化。invalid UTF-8、孤立 surrogate、NUL、超过 wire/canonical 双重 hard limit，或 schema 不接受的 `null` 在 accepted call 之前 typed reject；任意 bytes 只能进入明确登记的 typed binary/base64 字段，不能伪装成 text scalar。

Context XML 对 canonical scalar 使用 `representation=text|base64` 的 lossless carrier。只有实际 XML writer/parser fixture 能证明 entity escaping 与 XML line-end rules 后逐 byte 相等的值才用 text；其他仍合法的 UTF-8 scalar（例如 XML 1.0 不允许的控制字符或不能证明保真的 CR 边界）使用 base64，并记录 original byte length、representation 和公开 canonical digest。missing 与 empty string 永不合并。接收普通 tool scalar 时必须先经过 TS-15 ingress secret gate：只对 M05-59 最终路线纳入 ordinary-content 扫描的 eligible patterns 做 exact match；命中就拒绝且不保存原值或其 digest，只有通过该 gate 的 canonical bytes 才能进入 digest、approval、operation 或 XML。M05-59 B 豁免的过短普通 scalar coincidence 保留原数据类并携带 guarantee-contracted 状态；它不能被误报为已扫描。Runtime 从 registry 结构化取得的 secret 根本不得进入普通 tool scalar，只能走登记的精确私有 consumer carrier。

一个 call 只有在 `protocol wire -> canonical scalar -> XML carrier -> canonical scalar` 对每个字段逐 byte round-trip，且执行所需的最后 carrier 也已证明可表达时才可 accepted；否则返回稳定 `carrier-not-lossless`，不得截断到 NUL、替换字符、改换行或“尽量执行”。`exec` 到目标 shell 的最后一步仍服从 F4-11/TS-13，direct path/content 仍服从各自 tool schema。golden corpus 至少覆盖 missing/empty、非 BMP、组合字符、`&<>`、引号/反斜杠、`]]>`、CR/LF/CRLF、前后空格、XML-invalid control、最大边界与跨 chunk secret；TP-010、TP-015、TP-021 必须用最终 Lua XML 库和每个发布 Protocol adapter 证明这条链，而不是只单测内存 JSON。

#### TS-23 条件字段兼容矩阵

| TS-23 路线 | TS-37 cwd | F4-07 B `stdin_text` | M05-51 per-call 收紧 |
| --- | --- | --- | --- |
| A typed envelope | 可搭配 TS-37 A/B/C；A 把 optional `cwd` 作为本 call override，C 把它作为显式 cwd state transition，B 不注册该字段 | 可表达；F4-07 A 时字段不存在 | 可表达只会缩短的 deadline |
| B bare exec payload | 强制 TS-37 B | 不兼容，F4-07 必须 A | 不提供逐 call 字段，只用冻结有效值 |
| C free-text parsers | 强制 TS-37 B | 不兼容，F4-07 必须 A | 不提供逐 call 字段，只用冻结有效值 |

该矩阵只判断 carrier 能否无歧义承载字段，不替 TS-37、F4-07 或 M05-51 选择产品行为。若 owner 的选择与 carrier 不相容，配置/Model 资格检查必须明确报错，不能暗中删除字段、解析 shell 文本或改变所选路线。

#### TS-23 Protocol × carrier 技术可行矩阵门

下表是 M05-01 当前候选 adapter profile 与本组 carrier 的静态组合门；“条件”不是 Runtime fallback，而是发布前必须由 TP-015 的真实 wire fixture 证明的资格。Protocol 名进入范围不等于它自动拥有另一种 arguments carrier。

| M05-01 Protocol profile | 已声明 native arguments 形态 | A：typed object | B：bare `exec` payload | C：全部工具 free-text |
| --- | --- | --- | --- | --- |
| `openai-chat` | function/tool JSON object | 可行；仍需 round-trip fixture | conflict：该 profile 没有 bare arguments item | conflict：该 profile 没有全 core free-text item |
| `anthropic-messages` | `tool_use.input` object | 可行；仍需 round-trip fixture | conflict：object 不能冒充 bare payload | conflict：object 不能冒充全 core free-text |
| `openai-responses` | function object；free-form/custom item 只有 adapter manifest 明确实现时才存在 | 可行；仍需 round-trip fixture | 条件：必须为 `exec` 实现 native free-form item、call/result identity 与完整 fixture | 条件：每个 TS-02 core tool 都必须有 native free-form item、版本 parser 与完整 fixture |
| 未来 adapter | 发行 manifest 的 exact carrier capability | 只有 object capability 才可行 | 只有 bare/free-form capability 才可行 | 只有所有 core tool 的 free-form capability 才可行 |

决策校验器据此给确定结果：`M05-01 A/B + TS-23 B/C` 直接是 answer-set conflict；`M05-01 C + TS-23 B/C` 是绑定 `openai-responses` free-form TP-015 的条件组合，证明失败就转为 conflict，不能退回 object wrapper。若最终 M05-01 所选范围中没有至少一个能无损承载 TS-02 完整 core registry 的 Protocol，TS-23 B/C 不可确认、不可进入实现；若只有部分 Model/adapter 匹配，只有匹配者具有 main-tool 资格，其他 Model 按 M05-03/M05-26 的真实用途处理，不能隐藏 `exec`、缩小 registry 或临时改用 A。

关联：`AQ-034`、`MODEL-05`、`TOOL-01`、`TOOL-06`、`LOOP-13`、M05-01、M05-03、M05-26、F4-07、F4-11、TS-13、TP-010、TP-015、TP-021。

确认后 owner artifact：`07-tools-and-change-management.md` 的 ToolInputRegistry，逐工具固定 carrier/schema/version/limits/unknown-field/error/accepted-argument projection，并与 provider fixture、approval snapshot、Context schema snapshot 和 result pairing 机械对照。

### TS-37 `exec` 的 cwd 是否是逐调用状态

通俗场景：模型连续运行“配置”“构建”“测试”时，命令可能需要从 workspace 子目录启动。Runtime 可以要求每次 call 明确 cwd、永远从 workspace root 启动，或像长寿 shell 一样把 cwd 跨调用保留。三者会直接改变命令含义、审批目标和并发恢复，不能由 `command` 字符串中的 `cd` 被猜测出来。

- A：TS-23 A 的 `exec` envelope 可带 optional canonical `cwd`；缺失时使用该 turn 冻结的 workspace root。admission 与真正 spawn 前都复核 cwd 的 canonical path、目录身份、可进入性、workspace/OutsideWorkspace policy 和 generation，任一变化使旧 action stale。（推荐）
- B：每个 `exec` 永远从该 turn 冻结的 workspace root 启动，不接受逐 call cwd，也没有跨调用 cwd 状态。
- C：维护 process-local、跨 call 的 current shell cwd；新进程从 workspace root 初始化，TS-23 A 中带 `cwd` 的 accepted call 在 durable state transition 后把它设为本次及后续缺省 cwd。cwd 变化、审批、恢复和并发必须绑定稳定 generation；它不写成可跨进程恢复的 Context 权威状态，重启后从当前 workspace 重新开始。

推荐 A。模型能精确运行子目录任务，而每个 operation 仍自足、可审计、可恢复；B 最简单，却迫使模型把 `cd` 与 quoting 写进 opaque command；C 最像交互 shell，但引入隐藏可变状态、并发串行化、恢复重置提示和 stale approval 成本。TS-23 B/C 因 carrier 无处表达 typed cwd，静态强制本组 B。所有路线都把实际 spawn cwd 写入 action/approval/operation/result；Runtime 不解析 command 内部的 `cd` 来更新状态，目标变化后不沿用旧批准。

关联：`AQ-120`、`AQ-422`、`PROC-06`、`TOOL-03`、TS-23、TU-17、F4-12。

### TS-16 direct tool canonical result 的实际保留边界

本组只拥有 `list/read/search/write/patch/rename/delete` 等 direct tool 的 canonical result，不拥有 raw `exec` 的 stdout/stderr 保留；后者只由 TS-39 决定。

- A：tool 层保存有界但尽量丰富的 canonical result；内容、原始大小、digest、截断/拒绝原因和受管引用都是明确字段。binary、特殊文件和超限输入按 registry 拒绝或保存有界证据，不把未保存字节冒充完整事实。（推荐）
- B：canonical result 只保存统一的有界 head/tail 内容，同时记录原始大小、digest、truncated reason 和不可恢复范围。
- C：超过较小 inline 门后 canonical result 只保存结构化统计、digest、匹配位置与有界片段，不保留可供后续展开的连续正文。

推荐 A。它给模型与跨机 reader 较完整的有界事实；B/C 更节省 XML/内存。TU-06 独立决定屏幕 preview 多短，所以任一路线都可搭配摘要式 TUI；details 语义动作只能显示本组实际保留的 canonical evidence，绝不能找回或重新生成从未持久化的字节，chat 中的实际 root 只由 TU-32 A/B 投影。

三项都先消费 TS-15 的统一 secret boundary，而不是各自维护 Key 名单。direct read/search/list/result 在进入 canonical body、model view、XML 或持久 digest 前，只对 M05-59 最终路线纳入 ordinary-content 扫描的 eligible patterns 做有界流式扫描；命中部分保存 typed redaction marker，digest 改为 `redacted-canonical` scope，raw identity digest 只可作为本进程内 expected-file binding。M05-59 B 豁免的过短普通正文 coincidence 原样保留并标明 guarantee-contracted；未知、变形或未纳入扫描的秘密仍可能进入正文，必须如实标成 possibly-secret。direct/raw tool argument、command 或 stdin 命中同一 eligible pattern 时，admission 在持久化 call/approval 前 typed reject；B 豁免的过短 coincidence 不触发这项普通内容 gate。需要网络/exec secret 的合法消费者只能从 registry 走 schema 已登记的专用私有 carrier，Runtime 不得把实际 secret 复制成普通 argument 来利用 B 的豁免。普通用户提供但未登记的敏感正文仍按 user-content、Permission 与预览处理，不能假装自动识别。

关联：`AQ-125`、`TOOL-07`、`TOOL-10`、`SAFE-09`、TS-15、TU-32、HCFG-05。

### TS-17 `list`/`search` 的首版精确语义

- A：`list` 是有界、稳定排序、显式 depth/page/continuation 的目录枚举，返回 type/relative path/必要属性；`search` 采用固定文本查找方言（literal 为基线，regex 只在明确注册后启用），结果有 file/line/column/snippet/truncated。（推荐）
- B：`list` 同 A；`search` 首版只支持 literal + case mode，不支持 regex，所有结果仍结构化、有界且稳定排序。
- C：`list` 首版只枚举单层并用 continuation 分页；递归必须由模型逐层调用。`search` 必须给显式 roots，所有结果仍经同一候选集合、路径与权限检查。

推荐 A。B 的实现/测试面最小，C 把递归控制交给模型但调用数更多；三项都不把宿主 `ls/dir/grep` 自由文本冒充跨平台 tool contract。ignore 来源、隐藏项和显式目标覆盖只由 TS-36 决定，本组不能借搜索方言再次选择。

关联：`AQ-113`、`TOOL-01`、`TOOL-06`、TS-16、TS-36。

### TS-36 `list`/`search` 的 ignore 与隐藏项政策

通俗场景：ignore 决定隐式递归会不会看见生成目录、隐藏源码和潜在秘密。它可以减少旧机扫描量，却不是 Permission：仓库里的 ignore 文件也是不可信数据，被忽略的路径既没有自动获准，也不应在用户给出精确目标后被假装成不存在。

- A：隐式递归读取沿途 nested `.gitignore`，使用版本化、文档化的 Git-compatible grammar；dotfile 和 Windows hidden 不因“隐藏”自动排除。用户/模型给出精确路径时绕过 ignore，再正常经过 canonical path、类型、边界与 Permission 检查。（推荐）
- B：在 A 上再读取 workspace 根的 `.yacaignore`，并默认排除 dotfile/Windows hidden；只有精确目标或 typed `include_hidden=true` 才把隐藏项纳入候选，ignore 仍不授予访问。
- C：不读取任何项目 ignore 文件，也不按 dotfile/Windows hidden 属性排除；候选集合只受显式 roots、Runtime 资源硬门、Permission 和 yaca 保留树限制。

推荐 A。它最符合常见源码仓库，又不会让隐藏文件静默消失；B 给项目专用控制但新增一个仓库输入与页面开关，C 语义最直接却可能在 vendor/build 树上产生大量无用 I/O。三项都固定：ignore 只影响普通 workspace 的隐式 list/search traversal，不覆盖精确目标、权限、敏感读取分类或 TS-40 的 reserved-tree gate；它永远不能打开 reserved scanner/mutation，exact direct read 也只有 TS-40 B/C 才有对应窄出口。非 Git 工作区同样按选中 grammar 解释文件，不依赖宿主 Git。每个 ignore 文件必须有 byte/rule/depth/encoding 硬门并作为不可信数据解析；读取失败、畸形、超限或扫描取消要返回 partial 范围与原因，不能冒充完整结果。ignore 文件、隐藏属性或目录 identity 改变会使 continuation/view generation stale；循环、链接与 case-fold 仍服从路径层，不由规则文本绕过。

关联：`AQ-419`、`TOOL-04`、`TOOL-10`、`TOOL-11`、`SAFE-13`、TS-07、TS-17、TS-21、TP-009、TP-024。

### TS-40 `__yaca__` reserved tree 的 direct exact-read 边界

通俗场景：`__yaca__` 同时承载明文 Key 的主 INI、完整 Context XML 和 Runtime 维护中的临时/恢复对象。隐式 search 不该把它当源码爬进模型视图，direct mutation 也绝不能改坏自己的事实源；但用户可能希望模型在明确知道某一份 Context XML 路径时读取原始接盘文件。因此这里只选择 **exact direct `read`** 是否有窄出口，不把目录枚举、修改或 shell containment 偷绑进选项。

这里的 reserved tree 是 Runtime 当前解析并持有的 canonical data-root `__yaca__` 物理树及其受管临时/previous/backup identity，不是“任意 basename 恰好叫 `__yaca__` 的源码目录”。所有路线先固定以下硬边界：

- `list/search` 的隐式 scanner 与显式 target 都不进入、枚举或返回 reserved tree；命中时返回 typed `reserved-tree-excluded`，不能伪装成空结果。TS-36 的 ignore/hidden 路线不能覆盖这项 exclusion。
- direct `create/write/patch/rename/delete` 的 source、target 或发布 parent 任一落入 reserved tree 都 hard-deny；Permission、DoubleCheck、reviewer、人工 approval 或 undo 不能放宽，rename 也不能把受管文件移出树。
- admission 与实际 open/publish 前都解析 canonical ancestor identity，并在取得 handle 后重验 final object identity。symlink/junction/reparse/mount alias、case/8.3 alias 和 Runtime 已登记的 hardlink identity 一律按真实 reserved target 处理；identity set/ancestor scan 不完整或二次结果不一致时 fail closed 为 `reserved-alias-unknown|stale`，不能按显示路径放行。
- B/C 允许的 exact read 仍经过 `Read`、M05-16 对实际外部路径适用的 outside capability、条件存在时更严格的 `SensitiveRead`，并取最严格结果；随后还要经过 TS-15 按 M05-59 路线生成的 eligible-pattern ingress/result boundary、TS-16 retention 与大小/类型限制。M05-59 B 豁免的过短普通 XML coincidence 可能进入结果，页面必须显示 guarantee-contracted；Runtime 结构化 secret 仍无此出口。它绝不允许主 INI、secret-bearing config temp/backup、lease/lock、未完成 temp 或 recovery implementation object。exact path 不是授权，未分类不表示安全。
- Runtime 自己的 config/context/store 服务通过内部 typed port 访问这棵树，不伪装成模型 direct tool。反过来，获准的 raw `exec` 属于 TS-03 的宽 Shell：没有 OS sandbox 阻止它用绝对路径、alias、脚本或子进程读写 reserved tree；每次 Shell 风险说明都必须明确“direct reserved-tree deny does not contain shell”，不能通过解析 command 作虚假保证。

- A：所有模型发起的 direct exact read 都 hard-deny；查看配置/Context 事实只走对应 REPL、status/details、canonical model view 或用户在 yaca 外自行复制的文件。（推荐）
- B：只允许读取 **当前已打开 ContextHandle 的已提交 canonical XML**。目标必须逐字指向该 handle 当前路径并绑定 store generation、file identity 与 digest；即使 Permission 为 allow 也要求一次 exact-action 人工确认，任何外部替换、rename、保存推进或 handle stale 都生成新 action 或拒绝。其他 Context 与所有非 Context 对象仍 hard-deny。
- C：允许读取 Context Catalog 中任一已提交、schema 可识别的 canonical Context XML，但只能使用用户/模型已经给出的 exact physical path，不开放 reserved list/search 或 selector 猜测。每次都绑定 Catalog snapshot generation、file identity/digest，并强制 exact-action 人工确认；页面明确标出 current/other Context、名称/hash/逻辑路径和“完整历史可能含未知秘密”。

推荐 A。当前模型已经通过 canonical model view 获得完成任务所需的当前会话事实，配置与 Context 又有专用管理/接盘表面；全面 hard-deny 最简单，也不会让一个普通 `Read=allow` 变成读取明文 Key 或其他任务历史的旁路。B 提供当前 XML 的窄调试出口，C 方便跨 Context 调查，但二者都把完整会话原文引入逐次审批、secret scan、并发 generation 和隐私矩阵。无论选哪项，用户复制 XML 给另一台机器继续工作的 D-035 承诺不受影响；本组只约束运行中模型 direct tool。

关联：`AQ-436`、`TOOL-04`、`TOOL-10`、`SAFE-09`、`SAFE-18`、`CTX-18`、`INDEX-04`、M05-16、TS-03、TS-07、TS-15、TS-16、TS-21、TS-36、TP-010、TP-014、TP-028、TP-029。

确认后 owner artifact：`07-tools-and-change-management.md` 的 ReservedIdentitySet、direct action × reserved object 矩阵、exact-read gate/result，以及 alias race fixtures；`08-permission-and-safety.md` 只消费其分类与诚实 Shell 警告，不另造放行路线。

### TS-24 foreground `exec` 何时算收口

raw shell 的根进程退出后，后台化或继承 handle 的后代仍可能继续写文件、占 pipe 或联网。任意 `cmd.exe`/`sh` 文本都无法可靠证明“不会产生后代”，所以本组只选择 foreground completion criterion；是否提供一等 background job 产品面由 TS-30 独立决定。

- A：等待并 join 直接 root shell；root 退出后进入发行 manifest 固定的短 `orphan-drain-grace`，只继续 drain 已到达的 stdout/stderr，grace 到期即关闭 capture read handles 并收口，不等待 descendants。结果报告 `capture_cutoff=root-exit+grace`、`descendant_state=none|running|unknown` 和可观察 PID/handle/pipe 证据；后代之后的输出不可见且可能因 pipe 关闭收到错误。存在 running/unknown 时明确 `external_effects_unsettled=true`，不得宣称整条命令副作用已经结束。（推荐）
- B：除 root shell 外，还等待平台 adapter 能稳定追踪的 attached descendant tree；全部退出才 completed。达到 deadline/cancel grace 后尽力终止 attached tree，任何无法证明退出的节点使结果为 unknown。

推荐 A。它不把 XP/Linux 对任意逃逸进程的有限观察能力伪装成强 containment，普通同步子命令仍由 shell 自己等待；B 对构建器产生的附着子进程更整齐，但会因继承 handle、daemonize 和平台追踪差异更常卡到 deadline。B 在 tracked tree 退出或 deadline 后也使用同一个有界 drain/close 收口，任何路线都不能留下无人拥有的 pipe reader/后台 Lua task。两项都不提供 OS sandbox、不阻止 deliberate detach，也不通过解析 shell 字符串“检测并拒绝后台语法”；detached/escaped process 始终可能存活，审批页必须把这项风险写在 `Shell` 能力下。

关联：`AQ-399`、`PROC-03`、`PROC-06`、`PROC-09`、`TOOL-03`、TS-13、TS-22、F4-07、TP-005。

### TS-30 是否提供一等 tracked background jobs

本组只决定 yaca 是否主动提供 background-job 产品能力；foreground `exec` 的 root/tree 收口仍由 TS-24 决定。raw shell 即使在 A 下仍可能自行 detach，但那不等于 yaca 能 list/wait/cancel/reconnect。

- A：v0.1 不注册一等 background job。没有 `exec-job` tool、job REPL、跨 turn reconnect 或“后台成功”状态；若获批 shell 自行留下后代，只按 TS-24 保存 running/unknown 风险和 reconciliation 证据。（推荐）
- B：条件增加一个仍属于宽 `Shell` Permission 的 `exec-job` tool/action，接收 opaque command 并建立 durable job-id；提供 `job list|show|wait|cancel|reconcile`，有界捕获输出和资源。TS-23 A 用 typed object，B/C 则用独立 tool identity 保持 raw command carrier；registry/schema digest 必须保存。

推荐 A。它符合首版非交互、前台命令和旧平台简单性；B 适合长构建/服务，但引入 job scheduler、输出背压、关闭策略和恢复页面。B 也只跟踪由 `exec-job` 建立且仍可证明 identity 的 process tree：故意逃逸不受 sandbox 保证，进程崩溃/换机后 running job 默认恢复为 stale/unknown，只有本机 identity reconciliation 成功才能继续管理，绝不因旧 PID 相同就认领另一进程。

选择 B 时，Context switch、graceful exit 或 writer close 遇到 active job 必须进入 close barrier：页面只提供 `cancel-and-wait` 与显著风险的 `leave-running-unknown`，没有默认 leave。前者在有界 grace 后以 completed/cancelled/unknown 收口；后者先 durable 保存最后 identity/output digest、关闭 capture handles、标记 job detached/unknown，成功提交后 writer 才能关闭。窗口强杀/崩溃无法先写这条事实，恢复必须从 `interrupted-running` 开始 reconciliation，绝不能把进程退出或 pipe EOF当作 job success。

关联：`AQ-400`、`PROC-03`、`PROC-09`、`RUNTIME-02`、`CTX-07`、TS-02、TS-23、TS-24、F4-15、TP-005、TP-017。

### TS-25 direct `write` 的 create/replace 契约

条件：只有 TS-02 A/C 含 direct write 时生效；TS-02 B 下本组 `not-applicable`，不能保留空字段或让 raw shell 冒充 direct guarantee。

- A：调用必须显式 `mode=create|replace`；create 使用 no-replace，replace 必须匹配 expected regular-file identity 与 content digest，全部校验后在同目录安全发布。（推荐）
- B：保留 A 的 create/replace，并增加显式 `force-replace`；它即使 digest 不匹配也只在重新展示当前/候选 digest、精确目标并取得新 action ID/approval 后执行。
- C：只提供 upsert，不要求 expected digest；目标不存在就创建、存在就替换，仍避免发布半文件，但不检测用户在模型读取后对基础内容的修改。

推荐 A。它把“新建”和“基于已读版本替换”分开，最能避免覆盖用户并发编辑；B 给人工强制出口，C 最接近简单写文件但失去 stale-base 保护。三项都只处理已复核的 ordinary file/parent，拒绝 symlink/reparse/special target；temporary/stage、flush、validate、publish 和旧 generation 恢复必须留下 typed operation/result。所谓原子发布只能在平台/文件系统证明范围内承诺，不能把多文件 ACID 写进宣传。

关联：`AQ-401`、`TOOL-07`、`TOOL-08`、`CHANGE-01`、TS-02、TS-16、TU-17、TP-008、TP-014。

### TS-26 direct `patch` 的输入方言

条件：只有 TS-02 A/C 含 direct patch 时生效；TS-02 B 下 `not-applicable`。本组选 grammar，不把 target 数量、expected digest 和提交原子性重新捆进选项：三条路线都只处理一个 canonical ordinary-file target，要求 expected identity/digest，全部 parse/context/limit 校验通过后一次发布，任一 hunk/replacement 失败则零修改。

- A：版本化 structured hunks：每个 hunk 有 old range、context、delete/insert lines 和 newline metadata；file target/expected digest 在 envelope 中。（推荐）
- B：严格、版本化的 single-file unified-diff subset；禁止多文件 header、rename/mode/binary patch 和未登记 extension，完整解析后再应用。
- C：结构化 exact-replacement 列表，每项包含 old text、new text、expected occurrence count 和可选 range；不支持通用行号 hunk。

推荐 A。它最容易稳定表达行号、上下文、CRLF/EOF newline 和局部冲突；B 最贴近用户熟悉的 diff，但必须冻结自己的 subset，不能依赖宿主 `patch`；C 对小改动最简单、歧义由 expected count 消除，却不擅长大段重排。三项都保存 canonical request、实际 old/new digest、diff evidence 与失败位置，并受 TS-25 的发布/文件类型保证；模型生成的 patch 文本不经过 shell。

关联：`AQ-402`、`TOOL-07`、`CHANGE-01`、`CHANGE-02`、TS-02、TS-23、TS-25、TP-014。

### TS-27 direct `read` 的范围语义

`read` 在 TS-02 A/B/C 全部存在，不能跟 write/patch 条件合并。本组只决定经 TS-32/TS-33 判定为可读文本后的分页单位；binary 内容表面由 TS-33 独占。所有路线都先复核 ordinary-file identity、给原始 byte size/digest、使用硬输入/输出上限；超限从不静默冒充完整文件。

- A：text-first line range，参数为 `start_line/max_lines`；返回稳定 line number、newline kind、next line/eof、byte span 与 digest。不能可靠解码为受支持文本时返回 typed binary/encoding result，建议 byte-safe shell/后续能力，不伪造文字。（推荐）
- B：text byte-window `offset/max_bytes`；Runtime 在 TS-32 已选 decoder 下把边界调整到完整 code unit/character/newline，返回实际 raw byte span、decoded text、next offset/eof，不切半字符也不把 arbitrary binary 当文字。
- C：只允许整文件文本读取；文件超过 hard cap 或无法可靠解码时整次失败，不返回自动截断片段。

推荐 A。源码/配置的行定位最直接，也与 search/patch 证据自然衔接；B 对超长行/精确 byte evidence 更直接，C schema 最小却让大文件难以处理。任何路线都不能让 display decoder 改变真实 digest/hash，也不能因 ignore 规则跳过用户显式、已授权的目标。

关联：`AQ-403`、`TOOL-07`、`TOOL-10`、`PLAT-09`、TS-02、TS-16、TP-011、TP-014。

### TS-28 direct `rename` 的目标冲突策略

条件：只有 TS-02 A 包含 direct rename 时生效；B/C 下 `not-applicable`。本组只选择目标已经存在时怎么办，跨设备由 TS-29 独立决定。

- A：target 存在即 typed conflict，永不覆盖，也不自动改名。（推荐）
- B：只有显式 `replace=true` 才允许替换；审批前同时复核 source/target identity，能力按 `Rename + Delete(target)` 的更严格 Permission/DoubleCheck union 求值，并绑定新 action ID。
- C：冲突时在既定规则下计算一个未占用的新 target，并在审批前显示/绑定实际名称；若发布前竞态使它再次冲突，旧 operation stale，必须生成新 target/new action，不能在执行中继续猜名。

推荐 A。它最可预测、不会因 rename 隐式丢目标内容；B 满足显式替换但本质含 delete，C 适合“保留两份”却会改变模型原目标。三项都使用 source/target expected identity、no-follow/open-then-verify 和 no-clobber primitive；TUI 模型理由不是授权对象。

关联：`AQ-404`、`TOOL-08`、`SAFE-03`、TS-02、TS-05、TU-17、TP-012、TP-014。

### TS-29 direct `rename` 的跨设备行为

条件：只有 TS-02 A 包含 direct rename 时生效；B/C 下 `not-applicable`。本组只选择平台报告 cross-device/not-atomic 时的行为；target 冲突仍服从 TS-28。

- A：明确拒绝并返回 `CrossDeviceRenameUnsupported`；不把 copy+delete 称为 rename。（推荐）
- B：只有调用显式允许 `non_atomic_fallback=true` 且审批显示完整风险时，才对 regular file 执行 copy -> flush -> digest/identity verify -> delete source；任一阶段可返回 partial/unknown。
- C：对已批准为“允许 non-atomic fallback”的 rename policy 自动采用与 B 相同的 regular-file流程；初次 action snapshot 必须预先显示可能发生 copy/delete，不能在收到 EXDEV 后暗中扩大能力。

推荐 A。它保持 rename 的原子心智模型；B 把复合行为交给这次调用明确选择，C 操作更少但 approval 更宽。B/C 都按 `Read(source) + Write(target) + Delete(source)` 的更严格 capability union 求值，每阶段先 durable intent、后 durable result；目标发布成功而 source 删除失败时报告两份文件/partial，不能自动重试删除。目录树、symlink/reparse 和特殊文件跨设备一律拒绝，避免把 recursive copy/delete 的另一组风险藏进本题。

关联：`AQ-405`、`TOOL-08`、`CHANGE-03`、`SAFE-03`、TS-02、TS-25、TS-28、TP-008、TP-012、TP-014。

### TS-31 direct `delete` 是否允许递归目录树

条件：只有 TS-02 A 包含 direct delete 时生效；B/C 下 `not-applicable`。raw shell 始终可在 `Shell` 获批后执行其自身删除语法，但不取得本组 direct guarantees。

- A：direct delete 只接受一个精确 ordinary file 或空目录；执行前复核 expected identity，不跟随 symlink/reparse，非空目录返回 typed conflict。递归树删除只能走显著标为宽能力的 raw shell。（推荐）
- B：在 A 上增加显式 `recursive=true`：先用有界 no-follow walk 冻结完整 manifest/identity digest、entry/byte counts 和外部 mount/reparse 拒绝项，再按 `DeleteTree` 风险重新审批；manifest 在执行前变化即 stale。删除逐项记录，失败允许 partial/unknown，不宣传事务回滚。

推荐 A。它让 direct delete 保持单目标、可复核且容易恢复；B 为常见清理提供结构化证据，但大树扫描、竞态、partial deletion 和 Win32 x86 内存/路径都成为发布硬门。两项都不自动选择 trash、不跨 filesystem boundary、不把文件内容 preimage/undo 作为承诺；用户必须看到 canonical root、类型、identity 和不可逆说明。

关联：`AQ-406`、`TOOL-08`、`SAFE-03`、`CHANGE-03`、TS-02、TS-05、TU-07、TP-012、TP-014。

### TS-32 direct 文件的文本编码契约

本组决定 direct read/search/write/patch 把哪些 raw bytes 当作可安全往返的文本；终端显示代码页与文件编码是两回事。read 在所有 TS-02 路线消费该选择，写回分支只在 direct write/patch 存在时生效。

- A：只接受 ASCII/严格 UTF-8（可识别并保留 UTF-8 BOM）；其他 encoding 返回 typed error，建议 raw exec/外部转换。
- B：A 加上 BOM 明示的 UTF-16LE/UTF-16BE；保留原 encoding、BOM、newline kind 与 final-newline，修改后按原编码无损写回。（推荐兼容路线）
- C：B 加上发行 manifest 的有限 legacy codepage allowlist；调用必须显式指定 codepage 或由文件的已登记 metadata 提供，不根据当前 console/locale/字节频率静默猜测。

推荐 B。UTF-8 覆盖现代源码，BOM UTF-16 又是旧 Windows 常见真实格式；C 可兼容遗留工程，但每个 codepage 都扩大 round-trip fixture。三项的 digest/expected digest 始终对 raw bytes，decoder、encoding、BOM、newline=`LF|CRLF|CR|mixed`、final-newline 和 replacement=none 进入 result/XML；未修改行保持原始 bytes，read->no-op write 必须 byte-identical。mixed-newline 文件新增/替换行必须由 patch/write 显式给 newline policy，否则拒绝，不能偷偷统一全文件。

分类顺序固定为：先按 BOM/显式 codepage 选择唯一 decoder，再做严格无损解码；invalid sequence/unpaired surrogate 返回 `UnsupportedOrInvalidTextEncoding`，不偷偷换 decoder；解码成功但含 NUL 或 XML 1.0 禁止的 control/scalar 时分类为 `binary-content` 并转交 TS-33 的读取表面，不能先按本组 text error 吞掉 binary 路线。HT/LF/CR 按文本/newline 契约允许，其他可表示且 XML-safe、但终端危险的 control 由显示层可见化。不得使用 replacement character 后写回，也不让显示 escape 改变文件事实。

关联：`AQ-414`、`PLAT-09`、`TOOL-07`、TS-25、TS-26、TS-27、TP-011、TP-014。

### TS-33 direct 二进制内容的读取表面

本组只决定 binary ordinary file 的内容能否进入模型；TS-34 独立决定 direct 修改，所以“可读但不可写”与“不可读但可精确创建”都能表达。binary search 首版固定不提供，需高级查找走获批 raw exec。

- A：只返回 type、raw size、digest 和 bounded metadata；direct `read` 拒绝内容，终端/XML 不产生 base64 body。（推荐简洁路线）
- B：允许 hard cap 内的 whole-file base64 content；超过 cap 整次 content read 失败，不截断后冒充完整。
- C：允许 byte-range `offset/length`，返回 base64、actual bytes、next offset/eof 和 whole-file digest；每段及总请求都有 hard cap。

推荐 A。Coding Agent 通常不需把二进制塞进上下文，raw shell 仍可在宽 Shell 授权下调用专用工具；B 适合小资源文件，C 最灵活但 Token/XML 膨胀最大。B/C 的 effective content cap 是 binary-read hard cap、当前 turn/tool cap 与 TS-16 canonical-retention cap 的最小值：B 只有整文件能完整落入这个最小门时才成功，否则 typed too-large；C 每段长度也不能越过最小门，并另受整次请求总量门。两者绝不把 raw bytes 写到 terminal，base64 字段明确标 encoding/byte count/truncated=false，preview/canonical retention 仍受 TS-16，不能由模型输出伪造 binary digest。

关联：`AQ-415`、`TOOL-07`、`TOOL-10`、TS-16、TS-27、TS-32、TS-34、TU-06、TP-011、TP-014。

### TS-34 direct 二进制文件的修改表面

条件：只有 TS-02 A/C 含 direct write/patch 时生效；TS-02 B 下 `not-applicable`。本组与 TS-33 的读取选择正交，所有写入仍服从 Permission、TS-25 create/replace、expected raw-byte digest、no-replace 和安全发布。

- A：不提供 direct binary mutation；write/patch 遇到 binary payload typed reject，用户使用获批 raw exec。（推荐）
- B：允许 hard cap 内的 base64 whole-file create/replace；不支持 binary patch，payload 解码后 size/digest 必须与 envelope 声明一致。
- C：在 B 上增加 byte-range replacement list；每项有 offset、old length、new base64，整文件 expected digest 必填，Runtime streaming 复制到 temp、全部校验后一次发布。

推荐 A。避免把大型不可审阅 bytes 送进 XML/审批；B 支持小图标/fixture 的精确替换，C 支持局部修改但 range 重叠、文件增长和 32 位内存/流式复制测试更多。B/C 的审批显示 canonical target、old/new size/digest 与 base64 payload size，不打印 raw/base64 全文；任何 decode/size/range/digest 错误零修改，多文件事务仍不承诺。

关联：`AQ-416`、`TOOL-07`、`TOOL-08`、`CHANGE-01`、TS-02、TS-16、TS-25、TS-33、TU-07、TP-008、TP-014。

### TS-35 direct 文件属性的保真与修改表面

条件：只有 TS-02 A/C 含 direct write/patch 时生效；TS-02 B 下 `not-applicable`。本组拥有 direct create/replace/patch 对 POSIX mode/可执行位、Windows readonly、ACL/xattr/ADS、owner 与 hardlink 拓扑的承诺；TS-32 只拥有文本编码/newline，TS-25 只拥有内容 create/replace admission。

通俗场景：同目录 temp + replace 可以让内容安全落盘，却可能把可执行脚本变成不可执行、让安全 ACL 继承成另一套、丢掉扩展属性或断开 hardlink。内容 digest 没变化也不能证明文件行为和访问边界没变；反过来，让模型任意设置 OS metadata 又会把 direct tool 变成另一套宽系统管理接口。

- A：direct mutation 不接受属性修改参数；create 使用平台证明过的安全默认，replace/patch 必须保留 registry 中已声明的行为与安全 metadata。发现 hardlink、多数据流或无法可靠读取、复制、发布后复核的 owner/ACL/xattr/attribute 时 typed reject，用户改用获批 raw shell/外部工具。（推荐）
- B：在 A 上增加窄 typed 变更：Linux ordinary file 的 `executable=true|false` 与 Windows ordinary file 的 `readonly=true|false`；它们必须单列在 action、diff、Permission/approval snapshot 和 result 中，其他 metadata 仍只能保留或拒绝。
- C：强制保留基础 POSIX mode/Windows readonly；检测到其他 ACL/xattr/ADS/owner 或 hardlink 拓扑时，可以在冻结并展示将丢失、继承或断开的精确清单后取得新的高风险 approval，再继续内容发布。

推荐 A。它使 direct write/patch 的默认含义保持“只改内容”，不会在旧 Windows/Linux 上悄悄降权、提权或改变链接拓扑；B 便利脚本/只读标志管理但扩大跨平台 schema，C 兼容更多文件却允许有意损失安全/行为 metadata。所有路线都必须在 durable operation 前冻结 target identity、raw digest 和 metadata snapshot，在 publish 后重新打开并验证最终内容与 metadata；任何复制、设置、flush、publish 或复核失败都不得自动退回 content-only。无法证明发布是否发生时返回 partial/unknown、保留可观察证据并阻止下一副作用；create 不接受模型指定任意 owner/ACL/mode，symlink/reparse/special object 仍由 TS-07 拒绝或裁决，raw shell 永不继承本组 direct guarantee。

关联：`AQ-418`、`CHANGE-01`、`CHANGE-04`、`TOOL-02`、`TOOL-08`、`TOOL-09`、TS-02、TS-07、TS-25、TS-26、TP-008、TP-014。

## TS-03 raw shell 的已确认能力边界（不是负责人投票）

D-034 已确认 raw shell 使用一个宽 `Shell/Execute` 能力；allow 意味着命令可能读、写、删、联网、越界和启动程序。Runtime 不解析任意 `cmd.exe`/`sh` 来宣称 Read/Write/Network 隔离，reviewer 也不能授予 Permission 拒绝的能力。待决内容只在 Permission preset、审批和结果契约中询问。

### TS-04 Permission 预设

- A：模板依次为 Std、Readonly、Trusted。Std 对普通 workspace direct read=allow、write/delete/Shell/outside=confirm；Readonly 对普通 read=allow，其余 direct mutation/outside/Shell=deny；Trusted 对全部已存在 direct 能力/outside/Shell=allow。（推荐）
- B：只提供 Std、Readonly，矩阵同 A；没有预置自动 allow Shell/direct mutation 的 profile，用户若需要另建 section。
- C：提供 Std、Readonly、Trusted；direct 能力仍按 A 区分，但三者的 Shell 都至少 confirm，模板不提供自动 Shell。

推荐 A。三项都保持第一 Permission section 为 Std，并且 Readonly 永远 deny Shell/write/delete。若 M05-56 B 使 `SensitiveRead` 存在，Std/Readonly=confirm、Trusted=allow；若 TS-11 使 `DirectNetwork` 存在，Std=confirm、Readonly=deny、Trusted=allow。不存在的条件字段必须从三个模板同时消失。本组只拥有内置 profile 的默认矩阵：SensitiveRead 怎样分类/求值由 TS-21，具体 tool action 怎样映射能力由最终 tool-capability registry，名称/Description 都不能改变真实策略；M05-16 只决定 outside 列是 coarse 还是 split。

关联：`AQ-036` 至 `AQ-039`、`AQ-149`、`AQ-150`、`AQ-271`、`AQ-273`、`SAFE-02` 至 `SAFE-07`。

### TS-21 `SensitiveRead` 的分类来源与求值规则

条件：只有 M05-56 B 确认存在 `SensitiveRead` 字段时，本组才生效；M05-56 A 下本组记为 not-applicable，不生成字段、分类器或空壳页面。M05-16 的 outside 粗/细选择不影响本组激活。这里不重选字段存在性或 profile 默认值。

- A：使用版本化、确定性的 Runtime classifier：Runtime 自己管理的 secret 路径/registry，加一份可显示原因的高置信文件名/路径类别。命中后同时求值 `Read` 与 `SensitiveRead`，采用更严格结果；未命中只表示“未被分类”，绝不宣称文件安全。（推荐）
- B：只分类 Runtime 明确拥有或登记的 secret 位置（主 INI、含 secret 的临时文件/备份、secret registry target）；不按 workspace 文件名做启发式匹配。求值仍取 `Read` 与 `SensitiveRead` 更严格者。
- C：采用 A 的 Runtime classifier，并允许模型在 `read` call 中主动标记 `sensitive=true` 以进一步提高限制；模型不能声明 false 来覆盖 Runtime 命中。求值仍取更严格结果，tool result 记录分类来源。

推荐 A。它能覆盖常见 workspace secret 而不把不完美检测伪装成 sandbox；B 误报最少但会漏掉 `.env`/credential-like 工作区文件，C 允许模型谨慎上调却扩大 tool schema。三项都禁止 classifier 授权、降低 `Read`、回显 secret 内容或因“未命中”跳过普通路径/权限检查。

关联：`AQ-149`、`AQ-430`、`SAFE-09`、`THREAT-04`、M05-56、TS-04。

### TS-18 是否再增加独立 Autonomy 模式

- A：不增加；模型在普通任务中自主推进，安全与停止由 Permission、DoubleCheck、budget 和 typed ask-user/finish 的明确组合决定。（推荐）
- B：在 `[Agent]` 增加 `Autonomy=direct|explanatory`：它只调整 PP-06/PP-14/PP-15/PP-16 已经允许的文字块内部解释粒度。`direct` 使用最少必要说明；`explanatory` 可补关键原因和可选额外验证建议，但不能因此新增消息、执行验证、调用工具、改变最终报告结构或增加副作用。它是 INI 默认、next-turn 生效并进入 Context session snapshot，不提供 XML override 或隐藏 dot command，也不改变 Permission、DoubleCheck、必需验证、费用与硬预算。
- C：不增加配置字段；只允许用户通过 SystemPrompt/ContextPrompt 描述希望更主动或更解释，Runtime 安全开关完全不变。

推荐 A。B 提供稳定体验开关但增加一个 typed INI 字段和有效值快照，C 最灵活却难形成固定 UI 状态。A/C 下 `Autonomy` 必须是 unknown/deprecated 字段；任何方案都不能隐式扩大 Permission、关闭 DoubleCheck、跳过必需验证或移除预算。

权责固定如下：PP-01 独占语气；PP-06 独占进度时点；PP-14 独占工具叙述密度；PP-15 独占最终报告形状；PP-16 独占普通回答详略；TS-18 B 只拥有这些既有文字块内部的可选解释粒度。`explanatory` 不能恢复 PP-06 C 排除的进度、突破 PP-14/PP-15 的消息/栏目数量，或把 PP-16 C 变成默认长教程。用户自然语言或 Prompt 也只能影响模型措辞，不能绕过各 PP 组的已选外形或 Runtime 的安全/控制流。

关联：`AQ-049`、`PROD-02`、`PP-01`、`PP-06`、`PP-14` 至 `PP-16`。

### TS-05 人工授权记忆

- A：首版只有 allow-once；减少确认通过切换 profile。（推荐简洁方案）
- B：`allow-once` + `allow-identical-for-turn`；后者只复用相同 tool/schema、规范参数、cwd、目标身份和 config generation，turn 结束、任一绑定变化或显式 revoke 立即失效。
- C：在 B 上增加内存中的 `allow-session-scope`。grant grammar 固定为 `capability + workspace identity + scope kind + canonical value + expiry`：direct file 只允许 `exact-target` 或 `workspace-subtree`，外部路径只能 exact-target；DirectNetwork 只允许 exact normalized origin；Shell 只有一个显著标注的 `all-shell-in-current-process-context` scope。不接受 regex、glob、command prefix、“相似参数”或未登记 scope kind。生命周期只到当前进程退出、Context 切换、workspace/config/tool-schema 身份变化或显式 revoke，以最早者为准；不写 XML，不存在 project/always 永久授权。

推荐 A。已有 profile 就不必再造第二套授权状态；若实际使用太繁琐，可选择 B。C 的寿命、存储位置、失效条件和 Shell 含义都已闭合，不再使用含糊的 session/project/always；代价是增加 grant 列表、撤销页面和恢复测试。

若选择 B/C，每个仍有效的复用授权都必须有当前进程内唯一、可显示的 `grant-id`；list 只显示 capability、scope、canonical target 摘要、绑定 generation 和 expiry，不回显 secret 值。revoke/revoke-all 立即推进 grant generation，使尚未 admission 的复用失效，但不追溯取消已经启动的 operation，也不替 pending exact-action approval 作决定；这些管理动作只存在内存，不把 grant 本体写入 XML。条件命令、help 和 command×state 拼写由 TU-32/TU-24 投影。A 下 `grant-id`、list/revoke action、help topic 和空状态都不存在。

关联：`AQ-039`、`AQ-104`、`SAFE-03`、`SAFE-14`、TU-32、TU-24。

## TS-06 DoubleCheck 动作流水线投影（不是负责人投票）

动作先经过确定性 Permission；`deny` 立即收口，任何 reviewer/用户都不能授予。其余 accepted action 是否需要 review 由 AL06-07，verdict 的人工 override 由 AL06-24，请求失败由 AL06-25 唯一决定；本包不再复制三套 bypass 选项。

若所选策略需要 action-review，流水线固定为 `Permission -> action-review -> 必要的人工批准 -> durable operation -> execute`。这样 reviewer 不能扩大 Permission，用户也不会先批准一项随后才被 reviewer 改写。参数/cwd/目标/配置 generation 改变会使旧 verdict 与 approval 一并失效。该顺序是兑现既有授权边界的安全推导和测试对象，不是额外产品模式。

关联：`AQ-019` 至 `AQ-023`、`AQ-104`、`AQ-279` 至 `AQ-281`、`SAFE-11`、AL06-07、AL06-24、AL06-25。

### TS-07 direct file 的链接/特殊文件政策

- A：只处理普通文件/真实目录；链接显示物理目标并在执行时重验；特殊对象拒绝。（推荐）
- B：direct tools 不跟随 symlink/junction；只返回链接元数据与规范目标，用户需通过显式 real target 再调用。特殊对象拒绝。
- C：只允许跟随最终目标仍在 workspace 内的链接；指向外部的链接即使 Permission 可外读写也拒绝。特殊对象拒绝。

推荐 A。它支持常见链接并让外部目标仍走 Permission；B 最保守，C 给 workspace 更强封闭性。三项都要求执行时重验身份，并拒绝 device/FIFO/socket 等特殊对象。

关联：`AQ-113` 至 `AQ-118`、`AQ-213`、`AQ-268`、`AQ-269`、`SAFE-13`。

### TS-08 v0.1 undo 承诺

- A：安全写入、expected digest、diff/归属/unknown；不承诺自动 undo。（推荐）
- B：提供显式 `undo-protected` direct mutation：执行前必须把完整普通 preimage（含 binary）作为 typed、base64/escaped attachment 持久写入当前 Context XML，并通过 per-file/per-turn/per-Context hard quota；admission 失败就不执行受保护动作。preimage 本身若是 config-secret carrier，任何路线都拒绝 capture；普通 preimage 若命中 M05-59 最终路线纳入 ordinary-content 扫描的 eligible pattern，也拒绝 capture 和这次 undo-protected 执行。M05-59 B 豁免的过短普通 coincidence 可以按 ordinary-content 保存，但 attachment/export 页面必须显示 guarantee-contracted，不能声称其中没有同值 secret。排除集合由 registry 生成，不得把 D-028 的“config secret 只在主 INI”修订成“Runtime 再复制进 XML”。rename/delete 同样保存恢复所需身份与内容；undo 是新的补偿 operation，仍做冲突检查，不能承诺覆盖后续外改。
- C：不保存完整 preimage；direct file result 可生成有界 reverse-patch suggestion，用户若采用仍是新的显式 tool action，不能声称必然恢复。

推荐 A。B 是可兑现但昂贵的替代：选择它就明确重开 D-035 下“完整 XML”的普通源码/binary attachment 范围，并要求 CX 存储设计补齐 schema、配额、写放大、迁机/export/support 分类、清除与故障注入；但不重开 D-028，已登记秘密永不成为 preimage。普通源码中可能还有 Runtime 无法识别的用户秘密，capture 前必须诚实警告，不能承诺自动检测完整。C 提供辅助但不伪造 rollback。raw shell 和外部副作用在任何方案下都不承诺自动撤销。

文件属性保真只由 TS-35 拥有；本组的 undo 路线只能消费该组最后选定的 metadata guarantee。

关联：`AQ-115`、`AQ-165`、`AQ-249`、`AQ-312`、`CHANGE-01` 至 `CHANGE-03`、`CHANGE-05` 至 `CHANGE-07`、`TOOL-05`、`TOOL-09`。

### TS-19 Git 是证据增强还是工作流控制

- A：提供结构化只读 status/diff 证据，结束报告展示可归属 diff；commit/push/reset/stash 等可写 Git 动作不自动执行，若用户明确要求则作为 raw shell 副作用按权限处理。（推荐）
- B：Runtime 自动 stash/commit 并使用 Git 作为通用 rollback 系统。
- C：Git 全部通过 raw shell，不提供结构化 status/diff 或结束证据。

推荐 A。它让 Git 帮助说明“修改了什么”，但不把非 Git 工作区降级为二等能力，也不把没有被批准的 commit/reset 当成内部维护。

关联：`AQ-129`、`PROD-06`、`TOOL-12`。

## TS-09 原生运行时证明门（不是负责人投票）

已确认的忙时输入、流式、取消、Unicode 路径与单一 Lua 领域状态要求一个窄、版本化 I/O port；原生层只能返回事件，不能拥有 AgentLoop/配置/XML。具体是 C bridge、helper 还是目标平台异步 API 由 `AQ-223`、`AQ-239`、`AQ-250`、`AQ-261` 至 `AQ-263`、`PROC-01`、`RUNTIME-01` 至 `RUNTIME-03` 和对应 TP 证明，不让负责人投票选择不存在的纯 Lua 阻塞能力。

### TS-10 工具并行

- A：v0.1 所有工具串行，side request 是唯一受限模型并发。（推荐）
- B：Runtime 只对经 registry 标为 read-only、目标资源键互不冲突的调用并行；模型看到的结果仍按 call 顺序。
- C：只有模型在同一 batch 显式声明 independent 且 Runtime 再证明 read-only/resource-disjoint 时并行；其他全部串行。

推荐 A。它最容易保证副作用、审批和 XML 顺序；B/C 降低只读延迟但要求调度、取消和稳定结果顺序证明。任何方案都不并行 mutating/unknown-effect tools。

关联：`AQ-035`、`AQ-100`、`AQ-256`、`CONC-01`、`TOOL-06`。

### TS-20 accepted tool batch 中途失败

- A：第一个 observed failure 后不再 admission 任何尚未开始的调用；已经按 TS-10 合法并行启动的 read-only 调用只收口真实/cancelled/unknown 结果，为整批保存 completed/failed/skipped 一一配对结果，再交回 Agent 决定新一步。（推荐）
- B：失败后仍可 admission 被 registry 与模型共同显式标成 dependency-free、read-only 的后续调用；其余 skipped，每个 call 仍有配对结果。
- C：失败后仍可 admission 同批剩余的全部 read-only calls；停止所有尚未开始的 mutating/unknown-effect calls，不推断业务依赖已经满足。

推荐 A。它避免在前置失败后执行失去语义的调用；B/C 可收集更多只读证据但需要明确 dependency/capability。TS-10 独占“哪些调用能并行 admission”，本组只决定 failure 发生后尚未开始的调用是否继续；任何方案都不把已成功副作用标为自动回滚。

关联：`AQ-105`、`LOOP-12`。

### TS-11 是否提供 direct HTTP tool

- A：v0.1 不提供 direct HTTP tool，因此 Permission 没有 `DirectNetwork` 字段；选择 Model 只授权 provider 请求，raw shell 仍由宽 Shell 能力承担。（推荐最简）
- B：提供只读、bounded HTTP GET/HEAD direct tool，受独立 `DirectNetwork` 三态与下述 `DirectHttp*` transport/origin policy 约束。
- C：提供 typed HTTP request direct tool；method 与 public header name 只来自发行 allowlist，Host/Content-Length/Connection/Authorization/Cookie/Proxy-Authorization 等 transport/auth 保留名拒绝，body 有界；仍受 `DirectNetwork` 与同一独立 `DirectHttp*` policy。首版不提供 direct-tool SecretHeader/credential 字段；需要认证的任意请求仍走获批 raw shell，或未来另立 secret 生命周期。

若选择 B/C，配置必须条件性生成一组独立字段，而不能借用 Model connection：`DirectHttpCaMode/CaFile`、`DirectHttpProxyMode/ProxyUrl/NoProxy`、`DirectHttpRedirectMode`、`DirectHttpAllowedOrigin`。CA 可选来源服从 M05-37 已选择并被发行物证明的集合，但值独立：M05-37 A/B 下 missing/new=bundled，C 下=system；proxy=off，redirect=same-origin。allowed origin 缺失/空列表表示 direct HTTP 当前不可调用，非空项使用 exact normalized scheme+host+port，不接受 wildcard。HTTPS 普遍可列入；HTTP 只允许可证明的 loopback，且不得使用 Runtime 从 registry 取得的 secret credential/carrier；public header/body 的普通内容仍服从 M05-59 eligible-pattern gate，B 豁免的过短 coincidence 不会被误当成 credential。跨 origin redirect 与 HTTPS->HTTP 永远拒绝。每个 call/approval 显示 exact origin、proxy/CA snapshot、method 和数据类别。

这组字段有自己的 secret registry 与 redaction：它绝不读取或复制任何 Model Key、Model SecretHeader、Model Endpoint auth 或 Model proxy credential；`DirectHttpProxyUrl` 若含凭据也只属于 direct-tool transport。C 的 public header/body 可能包含 Runtime 不认识的用户秘密，UI 必须诚实警告，但不能把它自动升级为复用 Model credential。

推荐 A。B/C 是新的内置工具能力、完整配置区和安全面；无论选择哪项，Model provider 网络不消费 tool Permission，`DirectNetwork=deny` 也不宣称能隔离任意 raw shell。

关联：`AQ-145`、`AQ-149`、`AQ-272`、`NET-11`、`SAFE-08`。

### TS-12 unknown operation 的用户解算

- A：恢复时允许追加 completed/not-completed/still-unknown 结论与证据；不自动重放。（推荐）
- B：Runtime 永远不允许把 unknown 改成 completed/not-completed，只能追加 evidence 和保持 unknown；用户若要再试必须提出一个有新 operation ID 的独立动作。
- C：允许只读 reviewer 对已有证据给 advisory suggestion，最终仍由用户选择三态；原 operation 与 unknown 事实永久保留。

推荐 A。它让用户能在获得外部证据后收口；B 最保守，C 增加辅助判断。三项都不自动重放、删除或改写旧 operation。

关联：`AQ-030`、`AQ-103`、`AQ-230`、`AQ-263`、`AQ-316`、`TOOL-15`。

### TS-13 Process/raw-shell 的方言来源

问题：模型提交原始 command string 时，哪个 shell grammar 负责解释？本组只决定 executable/dialect 来源，不决定 stdout/stderr 的跨通道顺序。

- A：Windows 固定目标系统的 `cmd.exe /d /s /c` 契约，Linux 固定 `/bin/sh -c`；不提供用户 shell 选择。（推荐）
- B：每个目标发行 zip 的 manifest 固定一个经过随包证明的 canonical shell/dialect；可以是发行物自带 shell，但同一 zip 内用户不能切换，operation 保存 exact manifest identity。
- C：每个平台从发行 allowlist 暴露 typed `ShellDialect`，用户可在 INI 选择；每项分别证明 quoting、Unicode/bytes、取消、环境和旧系统可用性，不接受任意 executable path。

推荐 A。它依赖最少发行组件且最符合 XP/CentOS 基线；B 可以统一跨机语法但增加随包 shell 和供应链；C 兼顾习惯却扩大配置与兼容矩阵。三项都要求 operation snapshot 保存 exact executable/dialect/version，且 stdin、PTY 由 F4-07，cwd 由 TS-37，environment 由 M05-15/M05-55 独占。

关联：`PROC-02`、`PROC-04`、`PROC-10`、`AQ-119`、`AQ-128`、`AQ-130`、`AQ-147`。

### TS-22 stdout/stderr 的 canonical 跨通道顺序

问题：两个 OS pipe 并没有天然的全局字节顺序；Runtime 要承诺保存哪一种可证明事实？这和 TS-13 的 shell 方言正交。

- A：stdout/stderr 分通道读取；每个有界 chunk 在进入单一事件泵时取得单调 sequence，XML 保存这个 observed arrival sequence。它只声称“Runtime 观察顺序”，不声称还原进程内部写入的纳秒级真实先后。（推荐）
- B：canonical result 只保存两个有界最终 buffer、各自大小/digest/truncation，不承诺跨通道顺序；实时 TUI 的交错只是瞬态显示并明确不可重建。
- C：启动时把 stderr 重定向进 stdout，canonical 只保存一个有界 merged byte stream；保留到达顺序但失去原始通道身份，审批/结果必须明确这一点。

推荐 A。它保留通道身份和可审计的观察次序，同时诚实承认 OS pipe 的极限；B 存储更小，C 最容易逐字回放但无法再区分 warning/error 通道。三项都把原始字节事实与解码视图分开；decoder/binary 契约只由 TS-38 决定，哪些 bytes 成为 canonical retained result 只由 TS-39 决定。

关联：`PROC-04`、`PROC-05`、`PROC-07`、`AQ-122`、`AQ-266`、`AQ-367`、`AQ-371`、TS-38、TS-39。

确认后 owner artifact：`02-process-and-resource-limits.md` 中的 ProcessRequest/ProcessResult schema、shell dialect、stdout/stderr/byte/decode 契约、资源上限结果和 PTY/background exclusion 表。

### TS-38 `exec` 输出怎样解码以及何时成为 binary

通俗场景：Windows XP 的 `cmd.exe`/旧工具可能按 OEM codepage 输出，Linux 工具也可能吐出非 UTF-8 或包含 NUL 的 bytes。如果 Runtime 用 replacement character“修好”再当成原文，模型、XML 和另一台机器都会误以为这些字符就是进程真实输出。

共同不变量：无论选择哪条路线，Process adapter 先观察 raw bytes；在任何 XML、model-view、TUI history 或持久 digest 之前，统一 secret boundary 只对 M05-59 最终路线纳入 ordinary-content 扫描的 eligible patterns 做跨 chunk exact scan。无命中时，TS-39 retained segment 使用 base64 或等价 carrier 无损保存；命中时用 typed redaction marker 替换，只记录类别/occurrence 与 `digest_scope=redacted-canonical`，不得保存原值或 raw-secret-derived digest。M05-59 B 豁免的过短普通输出 coincidence 不扫描、不 marker，按普通 possibly-secret bytes 保留并标明 guarantee-contracted；Runtime 从 registry 结构化取得的 secret 永远不得被注入普通 process output/argument carrier。随后记录每通道 observed size、retained span 和 exact decoder identity。decoded view 只是派生投影；任何解码失败或 binary 分类都保留有界安全样本和失败位置，绝不把 replacement 后文本冒充原文。扫描只能保证当前路线纳入的 exact pattern，未知、豁免、编码或派生秘密仍可能进入 canonical output，产品必须如实警告。

- A：spawn 时冻结目标平台的 subprocess-output encoding snapshot；严格按该 snapshot 解码。非法序列、无法证明 decoder 或出现 NUL 时，不做有损替换，该 retained segment 形成 typed binary result，并提供控制字符可见化的有界安全样本。（推荐）
- B：所有平台都只尝试严格 UTF-8；非法序列或 NUL 形成与 A 相同的 typed binary result，不读取 console codepage/locale 来猜。
- C：默认同 A；仅 TS-23 A 的 typed envelope 允许逐 call 从发行 allowlist 选择 decoder，其他 carrier 只能使用 spawn 时平台 snapshot。decoder 名必须是稳定 ID，不接受任意系统 converter 名或自由文本。

推荐 A。它最符合旧 Windows/旧 Linux 程序的真实输出来源，同时保持“secret boundary 之后的 canonical bytes”才是可移交事实；B 最可重复却会把大量 legacy 文本归为 binary；C 能处理已知特殊工具，但扩大 schema、审批和平台 fixture。三条路线都不执行 ANSI/OSC，不让终端显示 decoder 改变 digest，也不因换机缺 decoder 而改写历史；第三方 reader 至少可用 base64/typed redaction marker、大小、digest scope 和 decoder ID 完整解释 retained evidence。测试必须覆盖 secret 跨 chunk、跨 head/tail 边界和 binary segment 的命中，不把 chunking 变成泄漏绕过。

关联：`AQ-123`、`AQ-124`、`AQ-424`、`PROC-04`、`TOOL-10`、TS-22、TS-23、TS-39、ED-08。

### TS-39 `exec` canonical output 在上限内保留哪一部分

通俗场景：有副作用的构建或部署命令可能输出数百 MiB，而 M05-51 必须给 Win32 x86 一个 stdout+stderr combined cap。达到上限后仍要持续 drain，但被丢弃的中间或尾部不能靠“再跑一次命令”安全找回；因此必须先决定模型和 XML 最终真正保留哪段证据。

下列“每通道”指 TS-22 最终保留的 canonical channel：TS-22 A/B 下是 stdout 与 stderr，TS-22 C 下只有 merged stream；本组不反向改变通道身份或 observed ordering。

- A：在 combined cap 内按发行版固定、确定性的通道配额分别保留 head+tail；每通道记录 observed/captured/discarded bytes、retained spans、truncation reason 和统一 secret boundary 之后允许持久化的 canonical full-stream digest。（推荐）
- B：在同一 combined cap 内按确定性通道配额分别只保留 prefix；仍记录每通道 observed/captured/discarded、retained span 与统一 secret boundary 之后允许持久化的 canonical full-stream digest。
- C：canonical body 只保存每通道统计、统一 secret boundary 之后允许持久化的 canonical full-stream digest 和极小的安全 head/tail diagnostic samples，不保存较长连续正文。

推荐 A。报错通常在尾部、启动上下文通常在头部，head+tail 对一次不可安全重跑的命令最有诊断价值；B 最适合流式前缀语义，C 最省 XML/内存但给模型的证据最少。三项都服从 M05-51 的 combined capture cap；TS-22 只决定通道身份/观察顺序，TS-38 只决定 retained canonical bytes 的解码/binary view，TU-29 只决定运行中 preview，TS-16 只决定 direct tools。若 eligible-pattern boundary 没有命中，`digest_scope=raw-canonical`；一旦命中 M05-59 要求扫描的 registered pattern，所有三项都只对替换 marker 后的流计算并持久化 `digest_scope=redacted-canonical`，原始命中流 digest 不能离开进程。M05-59 B 豁免的过短 coincidence 保持 raw canonical scope，同时必须显示 guarantee-contracted，而不是伪装成 secret-free。TUI、details 语义动作（chat root 服从 TU-32）和下一次模型请求只能消费本组实际保存的 canonical evidence，明确显示截断、redaction、guarantee contraction 和不可恢复范围，绝不为找回丢失 bytes 重跑命令。

关联：`AQ-125`、`AQ-425`、`PROC-04`、`PROC-05`、`TOOL-07`、M05-51、TS-16、TS-22、TS-38、TU-29、TU-32、F4-06。

### TS-14 威胁后果限制与 workspace 提醒

问题：在“不提供 OS sandbox”的前提下，yaca 能强制限制哪些后果，打开陌生 workspace 时是否增加显式 gate，以及 acknowledgement 保存多久？这里不把“看出一段文字是否恶意”写成可证明的安全能力。

所有路线的强制保证相同：workspace 文件/规则、模型文字、tool output 和 endpoint response 都只是非可信输入，不能靠正文扩大 Runtime tool registry、Permission、DoubleCheck、预算或既有 approval；每个可执行动作仍经过 schema/大小校验、确定性 Permission、必要的 exact-action approval、durable operation barrier 和结果配对。Runtime 结构化取得的 registered config-secret 永远受 private-carrier 禁入边界；普通正文 coincidence 只受 TS-15 按 M05-59 生成的 eligible-pattern boundary，B 的过短豁免必须诚实标记。发行包的 hash/manifest/身份材料及其取得方式只服从 RF-06/RF-15；可信结论必须依赖运行载荷之外、用户独立取得的预期值或 trust material。正在运行的程序可以报告自己看见的证据，但不能把“自己说自己未被篡改”当证明，也不能把 hash 偷换成来源认证。

明确不保证：yaca 不承诺识别或消除任意 prompt injection、恶意 workspace 指令、恶意模型/工具输出或恶意 endpoint；用户批准宽能力 raw shell/network 后，也没有 OS sandbox 阻止该进程触及当前用户原本有权访问的资源。若同一用户、OS，或程序、verifier、manifest 与 trust anchor 一起被控制，yaca 不能建立可信自证，也不能阻止事后伪造本地记录。

- A：不增加 trusted/untrusted 持久模式；打开时显示规范 workspace 身份、将采用的规则来源和上述后果限制，实际能力继续由 Permission/DoubleCheck/审批裁决。（推荐）
- B：每次进程/Context 打开陌生 workspace 都必须通过显式 trust gate；未确认前只允许查看身份和元数据，本次确认只存内存到该 Context 关闭/切换，既不写 INI/XML，也不形成跨次 trusted registry。
- C：不建立跨 Context 持久 trust；当前 Context XML 可保存一次绑定精确 workspace identity/schema 的 `WorkspaceAcknowledgement` 以免重复提示，路径/文件身份改变就失效，且 acknowledgement 不授予任何能力。

推荐 A。它用最短流程说明真实边界，同时保留全部可强制的后果限制；B 每次都增加显式进入门但没有隐藏持久信任库，C 只减少同一 Context 的重复提示并因此增加一个条件 XML session item。A/B 下该 XML 项必须不存在。任何选项下，项目文字、reviewer、acknowledgement 与 XML 历史都不能授予 Runtime 原本拒绝的能力；gate/acknowledgement 只证明用户看过精确 workspace 身份，不证明其中内容安全。

关联：`THREAT-01`、`THREAT-02`、TS-15、RF-06、RF-15。

确认后 owner artifact：`08-permission-and-safety.md` 中的 threat actors/assets/trust-boundary 矩阵、workspace identity/trust UX 和公开“无 OS sandbox”不承诺表。

## TS-15 数据分类与 purpose 可见性投影（不是负责人投票）

typed secret registry、Context 事实、六个核心 purpose（main/side/action-review/termination-review/compaction/self-test，其中 self-test 再区分 capability/semantic phase）、D-041/D-046 已确认的条件周期 `context-name`，以及 export/support 的边界，已经由已确认的明文配置秘密、完整 XML、purpose 隔离和“未知用户秘密不能保证自动识别”共同约束。实现内部采用二维表、三维矩阵还是若干生成后的 manifest，不改变负责人可观察行为，因此不再让负责人给内部数据结构投票。

权威工件必须使用一份 versioned registry 机械生成或校验每个 `data class x source x purpose x destination` 的最小视图，并把两类来源严格分开。第一，Runtime 从 registry 结构化取得的实际 config-secret value 无论 M05-59 选择哪条路线，都只能去登记的精确私有 consumer carrier，永不复制进 XML 字段、argv、普通诊断或 reviewer。第二，用户/模型/文件/工具的 ordinary content 只对 M05-59 最终路线纳入扫描的 eligible patterns 做 exact gate：命中才在 canonical retention 前形成 typed redaction marker；M05-59 B 豁免的过短 coincidence 保留原数据类并标记 guarantee-contracted。每个 request purpose 只取得完成职责所需字段；ordinary content 还可能含未知、豁免、编码或派生 secret，XML 按完整事实保存，而 export/support 必须预览、警告、允许取消，不能声称自动脱敏找全。任何新 secret/purpose/destination 在 registry 没有显式规则时 fail closed。

同一 registry 还生成 ingress gate：未提交的 chat/Prompt/名称/Description 与任何 tool argument/stdin 只在命中上述 eligible pattern 时，才在产生 canonical fact 或 approval 前 typed reject且不自动改写用户文字；M05-59 B 的过短 coincidence 不触发此 gate。已经执行后才出现的 tool result 对 eligible pattern 走 TS-16/TS-39 marker；外来 XML 也只对 eligible pattern 形成 `registered-secret-content` gap，原文件只读，writable continuation 只能由 CX-07 显式生成 sanitized copy 或在 registry value 移除/轮换后重评。B 豁免的过短 coincidence 不形成该 exact-match gap，但浏览/import/export 必须保留 guarantee-contracted 说明。实际 private secret carrier 永远不能通过伪装成普通正文来利用 B 的豁免。

关联：`PROD-08`、`THREAT-04`、`AQ-276`、`AQ-349`。

验收 artifact：`08-permission-and-safety.md` 中的 versioned data-flow registry、purpose/destination 最小视图、secret 生命周期、export/support 预览和诚实脱敏承诺。

## 推荐的整包组合

若希望采用当前推荐基线，请明确回复下列 35 个正式组；TS-01/03/06/09/15 不在清单中：

其中 `TS-21 A` 是对条件组的预先回答，不表示它无条件生成字段。当前跨包推荐是 `M05-56 A`，所以如果两个包都整体接受推荐，TS-21 的有效状态应是 `not-applicable`；只有 M05-56 最终选择 B 时，预先回答的 A 才转成 active selection。M05-16 A/B 的选择不会改变这个状态。

~~~text
TS-02 A
TS-23 A
TS-37 A
TS-16 A
TS-17 A
TS-36 A
TS-40 A
TS-24 A
TS-30 A
TS-25 A
TS-26 A
TS-27 A
TS-28 A
TS-29 A
TS-31 A
TS-32 B
TS-33 A
TS-34 A
TS-35 A
TS-04 A
TS-21 A
TS-18 A
TS-05 A
TS-07 A
TS-08 A
TS-19 A
TS-10 A
TS-20 A
TS-11 A
TS-12 A
TS-13 A
TS-22 A
TS-38 A
TS-39 A
TS-14 A
~~~

也可以只回复差异，例如 `本包其余接受推荐；TS-11 B，加入只读 direct HTTP；TS-38 B，只把严格 UTF-8 解码为文本；TS-14 C，只在当前 Context 保存 acknowledgement。` 推荐不是决定，未明确回复的编号继续保持 unanswered。

## 本包确认后要产出的权威工件

1. 首版 tool registry、TS-23 所选 input carrier/schema、TS-37 cwd state、版本与 canonical result schema。
2. tool × capability × Permission profile 矩阵。
3. tool lifecycle、approval snapshot、DoubleCheck action verdict 和 command × state 表。
4. path/file type/link/open-then-verify/no-replace、ignore、reserved identity 与 metadata 保真契约。
5. process port `start/poll/cancel/join/close` ABI 与 XP/CentOS capability matrix。
6. subprocess stdout/stderr ordering、TS-38 raw/decode/binary、TS-39 retention、backpressure 与 kill-tree contract。
7. Key/body 到 curl 的秘密生命周期与泄漏测试。
8. write/change guarantee、diff/归属和 unknown recovery fixtures。

这些工件通过审阅和平台原型后，才能写工具/安全/进程实现计划。未回复的推荐不会自动进入 `DECISIONS.md`。
