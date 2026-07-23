# 决策包 07：Tool Calling、安全、进程与旧平台运行时

更新日期：2026-07-18

状态：等待项目负责人回复；本文所有方案、表格、命名和推荐均为候选

## 本包要解决的真实问题

“像 Codex 一样让模型调用原始工具”和“不要复杂 sandbox”已经给出清楚方向，但仍不能直接编码。至少要回答：

- 模型究竟看到哪些工具；raw shell 与 direct file tools 为什么可以同时存在。
- `Readonly/Std/...` 的每个设置真实约束什么，哪些对 shell 根本无法约束。
- 工具参数、审批、DoubleCheck、durable operation 和实际执行的先后顺序。
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

权限先做确定性 deny/confirm/allow，`DoubleCheck` 只能追加否决，人工批准绑定精确动作。工具首版串行；每个已接受 call 必须有真实或 synthetic result。Runtime 只承诺安全写入、冲突检测、diff/事实记录和不自动重放 unknown，不承诺通用自动 undo。

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
       deny/revise -> synthetic result; return to main model
  -> optional human approval of exact snapshot
  -> durable operation intent
  -> execute
  -> capture actual completed/failed/cancelled/unknown result
  -> durable result
  -> next main-model request
```

不允许在 streaming arguments 看似闭合时提前执行。一个 response 有多个调用时按规范顺序串行；前项失败、用户 steer 或取消使未开始项生成 `skipped` result。模型历史不出现只有 call 没有 result 的断裂结构。

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
| 敏感候选 direct read | `SensitiveRead`（仅 M05-16 C；否则仍只用 Read） | confirm | confirm | allow |
| direct create/write/patch | `Write` | deny | confirm | allow |
| direct delete | `Delete` | deny | confirm | allow |
| direct rename | `Write` + `Delete`；外部再加 modifier | deny | confirm | allow |
| raw `exec` | 宽 `Shell` | deny | confirm | allow |
| Model provider HTTP | 当前 Model 配置 | allow | allow | allow |
| direct HTTP tool（仅 TS-11 B/C） | `DirectNetwork` | deny | confirm | allow |

第一 Permission section 已确认是默认，Std 候选仍放第一。profile 名称、是否内置最信任 profile、颜色和具体默认值仍待确认。

如果首版没有 direct HTTP 工具，`Permission.DirectNetwork` 没有真实消费者，必须不显示。若 M05-16 没有选择 SensitiveRead，该行也从正式矩阵消失，普通 direct read 只消费 Read。raw shell 内运行 curl 仍由 `Shell` 决定，不能让 DirectNetwork=deny 给出虚假保证。

项目负责人此前说“不需要 sandbox”，所以本文不会宣传 OS 隔离。Permission 是 yaca 是否发起某个已知动作的策略，不阻止获准 shell 的内部行为，也不防御用户自己从另一个进程修改文件。

## 审批绑定与页面候选

人工批准至少绑定：

- tool 名称/schema 版本；
- 完整规范参数或 raw command；
- cwd 与目标规范/物理身份；
- 非秘密环境摘要；
- Permission/profile/DoubleCheck snapshot；
- operation ID；
- 文件 expected digest/身份；
- 允许范围和期限。

任一安全相关输入、文件身份、配置或工具版本在等待期间变化，旧批准失效。

```text
[TOOL #17] exec
  cwd: C:\Work\yaca
  command: git clean -fd
  capability: Shell
  warning: may read, write, delete, access network or paths outside workspace
  status: waiting-approval

[ACTION] Approve tool #17?
  allow-once
  deny                 (default)
approval>
```

为保持简单，当前推荐人工授权只有 once；想减少确认可切换 Permission profile。是否增加 turn scope 单独决定，不提供永久 project/always 记忆。

## DoubleCheck 与人工审批

`DoubleCheck` 不是新 Permission，也不授予能力。动作候选顺序：

```text
Permission -> action reviewer -> human approval -> durable operation -> execute
```

reviewer 无工具，输出 typed `allow|deny|revise`。deny/revise 形成 synthetic result，再让主模型改策。无效输出/超时/网络失败经过有限重试后等待用户，不当作通过。

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

Key 已确认可以明文长期存 INI，但不能出现在 argv、XML、普通日志、审批命令或 error text。subprocess curl 仍需要同时得到 secret header 与 JSON body，候选三路是：

1. curl config 走 stdin，body 放私有临时文件；
2. body 走 stdin，secret config 放私有临时文件；
3. 窄 libcurl/native bridge，Key 只在进程内。

技术侧先比较 XP 文件权限、curl stdin 行为、取消和崩溃残留，优先选能以 subprocess 安全闭环的最小方案；只有 1/2 无法满足才增加 3。临时文件使用 data-root 私有 temp、随机 no-replace、最小权限、manifest 和启动残留回收。

Key、命令、文件内容、审批和 tool result 在 main/side/reviewer/compactor、TUI、XML、stderr 与 export 之间的完整边界见 [数据分类候选](../DATA-CLASSIFICATION-CANDIDATE.md)。

## unknown 副作用的恢复页面

```text
[RECOVERY] Operation #28 has no recorded result.
  tool: exec
  cwd: C:\Work\demo
  command: build.bat
  started: yes
  termination confirmed: no

[ACTION]
  1  Confirm it completed
  2  Confirm it did not complete
  3  Keep it unknown             (default)
  4  Inspect Context read-only
recovery>
```

用户的解算产生新的 durable event，不改写旧 operation；“确认未完成”也不自动重放命令，是否再次执行仍是一个新动作。

## Tool Calling、安全与进程的 17 个负责人决策组

可以回复 `TS-02 A；TS-04 的 Std Shell 改为 deny；其余接受推荐`。TS-01/TS-03/TS-06/TS-09/TS-15 是已确认边界、跨包投影或技术证明门，不接收选票；未回复的正式组继续待决。TS-21 只有在 M05-16 C 时生效；其他选择下记为 not-applicable。

## TS-01 已确认的工具表面（不是负责人投票）

D-034 已确认模型直接调用少量 raw/direct tools，raw shell 是一个诚实的宽能力工具，不提供强 sandbox 或领域 wrapper 语言。本包只问 exact registry、结果、Permission 与失败行为；不能再选择“只有 wrapper + sandbox”来暗中修订已确认边界。

### TS-02 首版 exact tool set

- A：list/read/search/write/patch/rename/delete/exec 全部进入完整 Coding Agent 闭环。（推荐）
- B：list/read/search + exec；文件修改通过获批 raw shell，仍保留结构化只读证据。
- C：list/read/search/write/patch + exec；rename/delete 只通过获批 raw shell，首版 direct registry 更小。

推荐 A。B/C 缩小 direct surface，却相应失去部分 expected-digest/no-replace 保护；三项都保留 raw exec 并遵守同一 Permission/operation 契约。

关联：`AQ-033`、`AQ-111` 至 `AQ-120`、`AQ-184`、`TOOL-01`、`TOOL-02`。

### TS-16 direct tool canonical result 与 TUI preview

- A：tool 层先产生有界 canonical result（大小/digest/截断/引用都是明确字段），TUI 再生成更小 preview；binary、特殊文件和超限输入拒绝或保存有界引用，不把显示截断冒充完整事实。（推荐）
- B：canonical result 与 TUI 使用同一有界 head/tail 内容，但 XML 仍记录原始大小、digest、truncated reason 和不可恢复范围。
- C：超过较小 inline 门后 canonical result 只保存结构化统计、digest、匹配位置与有界片段；TUI 不能承诺 `.details` 找回未保存字节。

推荐 A。它给模型较完整的有界结果，同时允许旧终端更短预览。B/C 更节省 XML/内存，但都必须诚实标记未保存字节，不能把 preview 当原始完整输出。

关联：`TOOL-07`、`TOOL-10`。

### TS-17 `list`/`search` 的首版精确语义

- A：`list` 是有界、稳定排序、显式 depth/page/continuation 的目录枚举，返回 type/relative path/必要属性；`search` 采用固定文本查找方言（literal 为基线，regex 只在明确注册后启用），结果有 file/line/column/snippet/truncated。默认遵守 ignore，用户/模型显式目标仍要经路径与权限检查，不因 ignore 自动授权。（推荐）
- B：`list` 同 A；`search` 首版只支持 literal + case mode，不支持 regex，所有结果仍结构化、有界且稳定排序。
- C：`list` 首版只枚举单层并用 continuation 分页；递归必须由模型逐层调用。`search` 必须给显式 roots，默认不读取 ignore 文件，但所有路径仍经权限检查。

推荐 A。B 的实现/测试面最小，C 把递归控制交给模型但调用数更多；三项都不把宿主 `ls/dir/grep` 自由文本冒充跨平台 tool contract。

关联：`AQ-113`、`TOOL-11`。

## TS-03 raw shell 的已确认能力边界（不是负责人投票）

D-034 已确认 raw shell 使用一个宽 `Shell/Execute` 能力；allow 意味着命令可能读、写、删、联网、越界和启动程序。Runtime 不解析任意 `cmd.exe`/`sh` 来宣称 Read/Write/Network 隔离，reviewer 也不能授予 Permission 拒绝的能力。待决内容只在 Permission preset、审批和结果契约中询问。

### TS-04 Permission 预设

- A：模板依次为 Std、Readonly、Trusted。Std 对普通 workspace direct read=allow、write/delete/Shell/outside=confirm；Readonly 对普通 read=allow，其余 direct mutation/outside/Shell=deny；Trusted 对全部已存在 direct 能力/outside/Shell=allow。（推荐）
- B：只提供 Std、Readonly，矩阵同 A；没有预置自动 allow Shell/direct mutation 的 profile，用户若需要另建 section。
- C：提供 Std、Readonly、Trusted；direct 能力仍按 A 区分，但三者的 Shell 都至少 confirm，模板不提供自动 Shell。

推荐 A。三项都保持第一 Permission section 为 Std，并且 Readonly 永远 deny Shell/write/delete。若 M05-16 C 使 `SensitiveRead` 存在，Std/Readonly=confirm、Trusted=allow；若 TS-11 使 `DirectNetwork` 存在，Std=confirm、Readonly=deny、Trusted=allow。不存在的条件字段必须从三个模板同时消失。本组只拥有内置 profile 的默认矩阵：SensitiveRead 怎样分类/求值由 TS-21，具体 tool action 怎样映射能力由最终 tool-capability registry，名称/Description 都不能改变真实策略。

关联：`AQ-036` 至 `AQ-039`、`AQ-149`、`AQ-150`、`AQ-273`、`SAFE-02` 至 `SAFE-07`。

### TS-21 `SensitiveRead` 的分类来源与求值规则

条件：只有 M05-16 C 确认存在 `SensitiveRead` 字段时，本组才生效；否则本组记为 not-applicable，不生成字段、分类器或空壳页面。这里不重选字段存在性或 profile 默认值。

- A：使用版本化、确定性的 Runtime classifier：Runtime 自己管理的 secret 路径/registry，加一份可显示原因的高置信文件名/路径类别。命中后同时求值 `Read` 与 `SensitiveRead`，采用更严格结果；未命中只表示“未被分类”，绝不宣称文件安全。（推荐）
- B：只分类 Runtime 明确拥有或登记的 secret 位置（主 INI、含 secret 的临时文件/备份、secret registry target）；不按 workspace 文件名做启发式匹配。求值仍取 `Read` 与 `SensitiveRead` 更严格者。
- C：采用 A 的 Runtime classifier，并允许模型在 `read` call 中主动标记 `sensitive=true` 以进一步提高限制；模型不能声明 false 来覆盖 Runtime 命中。求值仍取更严格结果，tool result 记录分类来源。

推荐 A。它能覆盖常见 workspace secret 而不把不完美检测伪装成 sandbox；B 误报最少但会漏掉 `.env`/credential-like 工作区文件，C 允许模型谨慎上调却扩大 tool schema。三项都禁止 classifier 授权、降低 `Read`、回显 secret 内容或因“未命中”跳过普通路径/权限检查。

关联：`AQ-149`、`SAFE-09`、`THREAT-04`、M05-16、TS-04。

### TS-18 是否再增加独立 Autonomy 模式

- A：不增加；模型在普通任务中自主推进，安全与停止由 Permission、DoubleCheck、budget 和 typed ask-user/finish 的明确组合决定。（推荐）
- B：在 `[Agent]` 增加 `Autonomy=direct|explanatory`：`direct` 使用最少必要进度说明和全部必需验证，`explanatory` 增加主动解释及预算内的额外验证建议；它是 INI 默认、next-turn 生效并进入 Context session snapshot，不提供 XML override 或隐藏 dot command，也不改变 Permission、DoubleCheck、必需验证与硬预算。
- C：不增加配置字段；只允许用户通过 SystemPrompt/ContextPrompt 描述希望更主动或更解释，Runtime 安全开关完全不变。

推荐 A。B 提供稳定体验开关但增加一个 typed INI 字段和有效值快照，C 最灵活却难形成固定 UI 状态。A/C 下 `Autonomy` 必须是 unknown/deprecated 字段；任何方案都不能隐式扩大 Permission、关闭 DoubleCheck、跳过必需验证或移除预算。

关联：`PROD-02`。

### TS-05 人工授权记忆

- A：首版只有 allow-once；减少确认通过切换 profile。（推荐简洁方案）
- B：`allow-once` + `allow-identical-for-turn`；后者只复用相同 tool/schema、规范参数、cwd、目标身份和 config generation，turn 结束、任一绑定变化或显式 revoke 立即失效。
- C：在 B 上增加内存中的 `allow-session-scope`。grant grammar 固定为 `capability + workspace identity + scope kind + canonical value + expiry`：direct file 只允许 `exact-target` 或 `workspace-subtree`，外部路径只能 exact-target；DirectNetwork 只允许 exact normalized origin；Shell 只有一个显著标注的 `all-shell-in-current-process-context` scope。不接受 regex、glob、command prefix、“相似参数”或未登记 scope kind。生命周期只到当前进程退出、Context 切换、workspace/config/tool-schema 身份变化或显式 revoke，以最早者为准；不写 XML，不存在 project/always 永久授权。

推荐 A。已有 profile 就不必再造第二套授权状态；若实际使用太繁琐，可选择 B。C 的寿命、存储位置、失效条件和 Shell 含义都已闭合，不再使用含糊的 session/project/always；代价是增加 grant 列表、撤销页面和恢复测试。

关联：`AQ-039`、`AQ-104`、`AQ-226`、`SAFE-03`、`SAFE-14`。

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
- B：提供显式 `undo-protected` direct mutation：执行前必须把完整普通 preimage（含 binary）作为 typed、base64/escaped attachment 持久写入当前 Context XML，并通过 per-file/per-turn/per-Context hard quota；admission 失败就不执行受保护动作。若 preimage 是已登记 Key、proxy credential、SecretHeader，或包含 Runtime secret registry 已知值，则拒绝 capture，也拒绝这次 undo-protected 执行；不得把 D-028 的“Key 只明文存主 INI”修订成“再复制进 XML”。rename/delete 同样保存恢复所需身份与内容；undo 是新的补偿 operation，仍做冲突检查，不能承诺覆盖后续外改。
- C：不保存完整 preimage；direct file result 可生成有界 reverse-patch suggestion，用户若采用仍是新的显式 tool action，不能声称必然恢复。

推荐 A。B 是可兑现但昂贵的替代：选择它就明确重开 D-035 下“完整 XML”的普通源码/binary attachment 范围，并要求 CX 存储设计补齐 schema、配额、写放大、迁机/export/support 分类、清除与故障注入；但不重开 D-028，已登记秘密永不成为 preimage。普通源码中可能还有 Runtime 无法识别的用户秘密，capture 前必须诚实警告，不能承诺自动检测完整。C 提供辅助但不伪造 rollback。raw shell 和外部副作用在任何方案下都不承诺自动撤销。

关联：`AQ-115`、`AQ-165`、`AQ-249`、`AQ-312`、`CHANGE-01` 至 `CHANGE-07`、`TOOL-05`、`TOOL-09`。

### TS-19 Git 是证据增强还是工作流控制

- A：提供结构化只读 status/diff 证据，结束报告展示可归属 diff；commit/push/reset/stash 等可写 Git 动作不自动执行，若用户明确要求则作为 raw shell 副作用按权限处理。（推荐）
- B：Runtime 自动 stash/commit 并使用 Git 作为通用 rollback 系统。
- C：Git 全部通过 raw shell，不提供结构化 status/diff 或结束证据。

推荐 A。它让 Git 帮助说明“修改了什么”，但不把非 Git 工作区降级为二等能力，也不把没有被批准的 commit/reset 当成内部维护。

关联：`AQ-129`、`TOOL-12`。

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

若选择 B/C，配置必须条件性生成一组独立字段，而不能借用 Model connection：`DirectHttpCaMode/CaFile`、`DirectHttpProxyMode/ProxyUrl/NoProxy`、`DirectHttpRedirectMode`、`DirectHttpAllowedOrigin`。CA 可选来源服从 M05-37 已选择并被发行物证明的集合，但值独立：M05-37 A/B 下 missing/new=bundled，C 下=system；proxy=off，redirect=same-origin。allowed origin 缺失/空列表表示 direct HTTP 当前不可调用，非空项使用 exact normalized scheme+host+port，不接受 wildcard。HTTPS 普遍可列入；HTTP 只允许可证明的 loopback 且不带 registered secret。跨 origin redirect 与 HTTPS->HTTP 永远拒绝。每个 call/approval 显示 exact origin、proxy/CA snapshot、method 和数据类别。

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

推荐 A。它依赖最少发行组件且最符合 XP/CentOS 基线；B 可以统一跨机语法但增加随包 shell 和供应链；C 兼顾习惯却扩大配置与兼容矩阵。三项都要求 operation snapshot 保存 exact executable/dialect/version，且 stdin、PTY 由 F4-07，cwd/environment 由 M05-15 独占。

关联：`PROC-02`、`PROC-04`、`PROC-10`、`AQ-119`、`AQ-128`、`AQ-130`、`AQ-147`。

### TS-22 stdout/stderr 的 canonical 跨通道顺序

问题：两个 OS pipe 并没有天然的全局字节顺序；Runtime 要承诺保存哪一种可证明事实？这和 TS-13 的 shell 方言正交。

- A：stdout/stderr 分通道读取；每个有界 chunk 在进入单一事件泵时取得单调 sequence，XML 保存这个 observed arrival sequence。它只声称“Runtime 观察顺序”，不声称还原进程内部写入的纳秒级真实先后。（推荐）
- B：canonical result 只保存两个有界最终 buffer、各自大小/digest/truncation，不承诺跨通道顺序；实时 TUI 的交错只是瞬态显示并明确不可重建。
- C：启动时把 stderr 重定向进 stdout，canonical 只保存一个有界 merged byte stream；保留到达顺序但失去原始通道身份，审批/结果必须明确这一点。

推荐 A。它保留通道身份和可审计的观察次序，同时诚实承认 OS pipe 的极限；B 存储更小，C 最容易逐字回放但无法再区分 warning/error 通道。三项都把原始字节事实与解码视图分开，记录 operation ID、exit/cancel/timeout/unknown、大小/digest/truncation，并受硬上限和 backpressure 约束。

关联：`PROC-05`、`PROC-07`、`AQ-122` 至 `AQ-124`、`AQ-266`、`AQ-367`、`AQ-371`。

确认后 owner artifact：`02-process-and-resource-limits.md` 中的 ProcessRequest/ProcessResult schema、shell dialect、stdout/stderr/byte/decode 契约、资源上限结果和 PTY/background exclusion 表。

### TS-14 威胁模型与 workspace 信任仪式

问题：在“不提供 OS sandbox”的前提下，yaca 明确防什么，打开陌生 workspace 时是否增加显式 gate，以及 acknowledgement 保存多久？

- A：明确防恶意 workspace/prompt injection/模型或工具输出/恶意 endpoint/篡改发行包/误操作；不承诺防已经控制同用户或 OS 的攻击者。不增加 trusted/untrusted 持久模式；打开时显示规范 workspace 身份与将采用的规则，实际能力继续由 Permission/DoubleCheck/审批裁决。（推荐）
- B：每次进程/Context 打开陌生 workspace 都必须通过显式 trust gate；未确认前只允许查看身份和元数据，本次确认只存内存到该 Context 关闭/切换，既不写 INI/XML，也不形成跨次 trusted registry。
- C：不建立跨 Context 持久 trust；当前 Context XML 可保存一次绑定精确 workspace identity/schema 的 `WorkspaceAcknowledgement` 以免重复提示，路径/文件身份改变就失效，且 acknowledgement 不授予任何能力。

推荐 A。它最简单；B 每次都增加显式进入门但没有隐藏持久信任库，C 只减少同一 Context 的重复提示并因此增加一个条件 XML session item。A/B 下该 XML 项必须不存在。任何选项下，项目文字、reviewer、acknowledgement 与 XML 历史都不能授予 Runtime 原本拒绝的能力。

关联：`THREAT-01`、`THREAT-02`。

确认后 owner artifact：`08-permission-and-safety.md` 中的 threat actors/assets/trust-boundary 矩阵、workspace identity/trust UX 和公开“无 OS sandbox”不承诺表。

## TS-15 数据分类与 purpose 可见性投影（不是负责人投票）

Key、Context 事实、六个核心 purpose（main/side/action-review/termination-review/compaction/self-test，其中 self-test 再区分 capability/semantic phase）、PJ-12 B 才存在的条件 `context-name`，以及 export/support 的边界，已经由已确认的明文 Key、完整 XML、purpose 隔离和“未知用户秘密不能保证自动识别”共同约束。实现内部采用二维表、三维矩阵还是若干生成后的 manifest，不改变负责人可观察行为，因此不再让负责人给内部数据结构投票。

权威工件必须使用一份 versioned registry 机械生成或校验每个 `data class x purpose x destination` 的最小视图：Key/secret header 永不进 XML/argv/普通诊断/reviewer；每个 request purpose 只取得完成职责所需字段；用户正文可能含未知 secret，XML 按完整事实保存，而 export/support 必须预览、警告、允许取消，不能声称自动脱敏找全。任何新 purpose/destination 在 registry 没有显式规则时 fail closed。

关联：`PROD-08`、`THREAT-04`、`AQ-276`、`AQ-349`。

验收 artifact：`08-permission-and-safety.md` 中的 versioned data-flow registry、purpose/destination 最小视图、secret 生命周期、export/support 预览和诚实脱敏承诺。

## 推荐的整包组合

若希望采用当前推荐基线，请明确回复下列 17 个正式组；TS-01/03/06/09/15 不在清单中：

~~~text
TS-02 A
TS-16 A
TS-17 A
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
TS-14 A
~~~

也可以只回复差异，例如 `本包其余接受推荐；TS-11 B，加入只读 direct HTTP；TS-14 C，只在当前 Context 保存 acknowledgement。` 推荐不是决定，未明确回复的编号继续保持 unanswered。

## 本包确认后要产出的权威工件

1. 首版 tool registry、JSON schema、版本与 canonical result schema。
2. tool × capability × Permission profile 矩阵。
3. tool lifecycle、approval snapshot、DoubleCheck action verdict 和 command × state 表。
4. path/file type/link/open-then-verify/no-replace 契约。
5. process port `start/poll/cancel/join/close` ABI 与 XP/CentOS capability matrix。
6. subprocess stdout/stderr/encoding/backpressure/kill-tree contract。
7. Key/body 到 curl 的秘密生命周期与泄漏测试。
8. write/change guarantee、diff/归属和 unknown recovery fixtures。

这些工件通过审阅和平台原型后，才能写工具/安全/进程实现计划。未回复的推荐不会自动进入 `DECISIONS.md`。
