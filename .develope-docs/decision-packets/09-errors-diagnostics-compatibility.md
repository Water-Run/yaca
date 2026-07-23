# 决策包 09：错误、诊断、关闭与兼容体验

更新日期：2026-07-18

状态：等待项目负责人回复；推荐与示例均不是已确认决定

## 为什么错误系统也是产品架构

yaca 会同时面对模型、网络、进程、文件、XML、配置、权限、终端和旧系统失败。若每层都打印一段字符串，用户会看到同一根因五次，却仍不知道：

- 输入是否已经保存；
- 工具是否可能已经产生副作用；
- 是否会自动重试、还剩几次；
- 现在按 Esc、Enter 或退出会发生什么；
- 下次启动是否进入 recovery；
- 哪些详情可以安全分享。

项目负责人还要求长期文件只有 INI/XML，因此不能靠“以后写一份详细 log 文件”掩盖错误模型缺失。本包把用户错误卡、typed error、retry/cancel/close、XML 诊断、stderr、support 输出和旧终端降级一起收口。

## 已确认约束下的基线与反例

### 方案 A：typed cause + 单一责任卡 + XML/stderr（推荐）

每个错误有稳定 error ID、类别、阶段、retryability、影响和安全详情。最靠近用户体验的责任层只显示一次主卡；下层 cause 作为链保存而不重复打印。

Context 已打开后，恢复所需事实和有界诊断进入 XML。配置/Context 尚未打开的启动错误写 stderr。显式 self-test/support 可以输出报告，但不默认维护第三类轮换日志。retry、cancel 和 close 是状态机，不是字符串提示。

优点：符合 INI/XML 约束，恢复与 UI 使用同一事实；脚本有稳定 exit class。代价：需要在各模块统一 typed error 与映射表。

### 反例 B：详细文本日志优先（D035 已排除）

每层写完整 trace 到独立轮换文件，TUI 只显示“请看日志”。开发初期方便，但新增第三类长期数据，秘密/配额/路径/升级都要重新设计；跨机只复制 XML 又丢失诊断。

在负责人明确改变数据格式约束前，不采用。

### 反例 C：最少错误字符串（不满足完整接盘）

失败时只打印 provider/OS 原文并退出，重试交给用户。实现量小，却无法安全恢复 unknown operation，也不能给 self-test、CLI 和 TUI 一致结果。

不适合完整可用版本。

## 候选 typed error

```text
Error
  id                 stable ASCII registry ID
  category           config|storage|network|model|tool|permission|runtime|ui|release
  stage              exact lifecycle stage
  severity           warning|action-required|error|fatal
  retryability       no|automatic|manual|after-change
  cause              nested typed cause, not another user card
  user_summary       safe English/ASCII program text
  saved_state        what is durable
  side_effect_state  none|known|unknown
  next_actions       typed actions with safe defaults
  technical          bounded and classified metadata
  secret_flags       fields that must never render/export normally
```

Error ID 代表稳定类别，不为每条自然语言句子分配进程退出码。CLI 使用少量稳定 exit class；同一 ID 可以带不同安全参数和 cause。

### 单一责任原则

例如 curl TLS 失败：

```text
process port -> ProcessExit evidence
network      -> NET-TLS typed cause
Model adapter-> request failed, retains request/attempt identity
AgentLoop    -> decides retry/wait/error outcome
TUI/CLI      -> renders one primary card
```

process、network、Model 各自都不能顺便打印一张红色错误。trace 中可保留完整 cause chain，用户 transcript 只出现一次主问题和必要状态变化。

## 错误卡样例

```text
[ERROR NET-TLS] The Model request could not establish a trusted TLS connection.
  model: DeepSeek
  endpoint: https://api.example.invalid/...
  attempt: 2 of 3
  saved: user input and request intent
  side effects: none known
  automatic retry: no

Next:
  retry
  run self-test model DeepSeek
  change model
  keep this turn waiting
```

技术详情不折叠在不可用的全屏 panel 中：

```text
> .error NET-TLS
[DETAILS NET-TLS]
  stage: tls-handshake
  curl-exit: 60
  ca-mode: bundled
  proxy-mode: environment
  request-id: 42
  attempt-id: 44
  secret fields: omitted
```

## warning、action-required、error、fatal

| severity | 含义 | AgentLoop 影响 |
| --- | --- | --- |
| `warning` | 已有安全结果，可继续；用户应知情 | 不自动结束 turn |
| `action-required` | 需要选择/审批/映射/恢复 | 进入 waiting-user，不是 error |
| `error` | 当前 operation/request 失败，但应用可继续管理或重试 | 由状态表决定 partial/waiting/error |
| `fatal` | 当前进程无法保持事实或运行不变量 | fail-stop，尽力收口后退出 |

“配置命名看起来奇怪”的 self-test 第三阶段结果是 warning；“无法持久化副作用 intent”是 fatal/fail-stop；等待审批是 action-required，不应该显示成模型错误。

## Retry 是可取消状态

```text
[WARNING NET-RETRY] Model request failed before the body was sent.
  attempt: 2 of 3
  next attempt: 4s
  reason: connection refused

busy> .cancel request
[STATUS] Retry cancelled. The turn is waiting for input.
```

卡片显示 reason、attempt、总预算、倒计时/条件和取消入口。用户可立即 retry、cancel 或改变 Model；Runtime 仍按 send phase 判断是否安全自动重放。已收到任何规范响应事件、请求体 outcome unknown 或用户取消时不自动整请求重试。

重试计数分开：transport attempt、logical Model request、tool retry、DoubleCheck、compaction；它们共享 turn 硬预算，不能一层归零后绕过总上限。

## Cancel、close 和 crash 不是同一个结果

| 动作/事件 | 候选语义 |
| --- | --- |
| Esc/`.cancel request` | 请求取消最内层 request；等真实完成事件 |
| `.cancel tool` | 请求终止进程树；结果可为 cancelled/completed/unknown |
| `.cancel turn` | 停止新动作，收口当前 operation 与 queue |
| `.exit` | 进入 graceful close；不启动新 queue/副作用 |
| EOF | idle 且无草稿时可 close；busy 时不直接假装完成 |
| broken pipe | 停止 renderer，仍尝试安全收口；避免向已关闭 stdout 无限报错 |
| OS terminate/window close | 有能力时请求 close；强杀依赖下次 recovery |
| process crash/power loss | 没有机会写“正常退出”；下次用 footer/lease/operation 事实判断 |

关闭顺序：停止接收新副作用 → 发取消 → 等有界 join/结果 → 标 unknown → 提交 XML → 释放 lease → 恢复 terminal。超过 deadline 不是 completed；退出码和下次 recovery 要反映未知范围。

## 磁盘满与持久化失败

```text
[FATAL CTX-COMMIT] yaca cannot record a safe operation state.
  context: C:\Tools\yaca\__yaca__\CONTEXT\C\Work\demo.xml
  saved through event: 418
  current operation: not started
  new model/tool actions: blocked

[ACTION]
  1  Retry after freeing disk space
  2  Inspect read-only
  3  Exit and keep recovery evidence
```

如果副作用尚未开始，保存失败就不执行；如果副作用已发生但 result 不能保存，必须标记/显示 unknown 并禁止继续，而不是只在最终报告写一句警告。

## XML、stderr 与 support 输出

### Context 已打开

XML 保存：canonical error/cause identity、状态转换、retry/cancel/approval、operation unknown、有效 LogLevel snapshot、必要非秘密诊断。LogLevel 不得控制这些恢复事实是否存在。

高频 token、spinner、重复相同错误和无限 OS/provider body 不进入事实；它们可以合并、截断或只留 digest/安全预览。

### Context 尚未打开

错误只写 stderr，保持 English/ASCII program text；路径/用户数据按 terminal adapter 安全显示。help/version/静态 self-test 仍尽可能可用。stderr 本身没有 durable 保证，不应假装已经“写进日志”。

### Support 输出

显式命令先预览包含内容：版本、平台、manifest hash、error IDs、资源/能力、脱敏配置投影、用户选择的 Context 事件范围。默认不含 Key、用户/模型正文、文件内容、原始 request/body。持久输出只能是用户明确生成的 standalone diagnostic XML；否则只写 stdout/当次 stderr。用户使用 shell 重定向保存的副本是 yaca 之外的用户 export，不成为 Context 事实源。不自动上传；v0.1 无遥测、无隐式更新联网。

## 终端与文本安全

- renderer 自己可以产生已知颜色/光标序列；模型、工具、路径和 error cause 中的 C0/C1、CSI、OSC 等控制序列要可见化。
- 程序标签、error ID、配置键和机器字段使用 English/ASCII；用户路径/正文仍是 UTF-8 数据，Windows 文件操作用 wide API。
- terminal 无颜色、宽度未知、`TERM=dumb` 或 XP 无 VT 时仍显示同一标签/选项/默认结果。
- 能力降级启动时至多提示一次，并列文本后备；不每次按键刷 warning。
- CJK 字形显示失败可以转义，但显示替换后的文字绝不用于 path/hash/审批身份。

## 兼容性错误不能静默降级

下列情况要有明确 capability/release error：

- 在错误 OS/架构运行发行包；
- Win32 binary import Vista+ API，无法在 XP 启动；
- Linux 包混入 ELF32/x32；
- terminal 后端无法提供按键，但文本后备可继续；
- 文件系统无法证明 no-replace/安全 replace；
- helper ABI/hash 与 manifest 不匹配；
- XML required feature/schema 比当前程序新。

“视觉能力不足”可降级；“数据正确性或权限无法保证”必须 fail-stop/只读。两类不能共用“兼容模式”一词掩盖。

## 负责人决策组（十二组）

D035/D036 已固定长期文件只有 INI/XML、没有 standalone log/crash.log，且恢复所需 canonical fact 不能受显示详细度或 LogLevel 影响。以下每组只决定错误体验或证据投影，不再把丢事实、自动上传、未知副作用重放列为选项。未回复项保持待决。

### ED-01 稳定 error ID 的兼容粒度

- A：为“用户可采取同一种动作”的 category + stage 分配稳定 ID，例如 `NET-TLS`；底层 OS/provider 差异放 typed cause 字段。（推荐）
- B：只稳定少量顶层 category ID，例如 `NETWORK-FAILED`；精确 stage、retryability 和 cause 作为稳定字段，不为每个阶段新增 ID。
- C：为 category + stage + actionable reason 分配更细的稳定 leaf ID；平台/adapter 原因必须映射到 registry，未知原因使用明确 fallback ID。

推荐 A。它足够稳定地驱动 help、测试和 support，又不会让每个 curl/OS 字符串膨胀成公共契约。三项都用 typed error；Context 内完整 canonical error/cause 进入 XML，Context 前走 stderr，且不创建长期 log 文件或因 ID 粒度丢失事实。

关联：`AQ-103`、`AQ-158`、`AQ-201`、`AQ-203`、`AQ-328`、`CTX-24`、`DIAG-01` 至 `DIAG-05`、`LOOP-17`。

### ED-02 severity 与 waiting-user

- A：固定 warning/action-required/error/fatal；waiting-user 是状态，不是 severity。（推荐）
- B：固定 warning/action-required/error；进程不能维持不变量时使用 error + fatal exit class，waiting-user 仍是状态。
- C：增加只用于成功诊断信息的 info，形成 info/warning/action-required/error/fatal；waiting-user 仍是状态。

推荐 A。四级足以区分可继续、需用户动作、当前动作失败和进程不可安全继续，也不会把等待审批误报为错误。

关联：`AQ-103`、`AQ-201`、`AQ-251`、`LOOP-10`、`DIAG-02`。

### ED-03 同一根因显示几次

- A：责任层只显示一张主卡；完整 cause chain 保存并可 details 查看。（推荐）
- B：显示一张主卡，并为每个跨层边界追加一行 origin 摘要；全部引用同一 error ID，完整 chain 仍保存。
- C：主 transcript 只显示一个紧凑 root-error block；ED-10 决定该 block 内是否附 safe cause summary，details 中按阶段列完整 cause chain 与影响，canonical chain 不删减。

推荐 A。用户只需理解一个问题，维护者仍能沿完整 cause chain 定位；三项都不能丢掉上层影响或底层证据。

关联：`AQ-103`、`AQ-203`、`DIAG-01`、`DIAG-11`、`DIAG-13`。

### ED-04 Retry 的可见与取消

- A：每次自动 retry 都显示 reason/attempt/预算/倒计时和取消；只有 phase-safe 才允许自动重试。（推荐）
- B：第一次失败与最终结果显示完整卡，中间安全 retry 只追加紧凑 attempt receipt；所有 attempt identity 仍进 XML/details。
- C：先追加一张 retry plan（触发条件、上限、总预算、取消入口），中间只更新 attempt 编号与下次等待，耗尽时追加完整终态卡。

推荐 A。它让时间、费用和取消入口始终可见。三项只改变显示密度，都服从 Model 绑定的 retry 配置、全局代理与 phase-safe 判定，绝不重放 outcome unknown 的请求/工具。

关联：`AQ-126`、`AQ-140`、`AQ-197`、`AQ-221`、`AQ-321`、`NET-07`。

### ED-05 Ctrl+C、EOF、broken pipe 与 `.exit`

- A：Ctrl+C 取消最内层活动；`.exit` 请求全进程 graceful close；EOF 仅在 idle/无 draft 时关闭、busy 时进入 close action；broken pipe 停止 renderer 后请求安全收口。（推荐）
- B：第一次 Ctrl+C 只取消最内层活动，第二次请求 process close；EOF/broken pipe/`.exit` 直接请求 graceful close，仍有界收口。
- C：所有退出来源都直接请求 process-wide graceful close；不再接受新动作，到达 deadline 后以 interrupted/unknown 收口。

推荐 A。它让不同信号保持最符合用户预期的最小影响范围。三项最终都映射 typed cancel/close 状态并有界收口，不能立即 kill 后声称完成，也不能在 busy 时无限忽略退出。

关联：`AQ-027`、`AQ-098`、`AQ-229`、`ARCH-02`、`PLAT-10`。

### ED-06 持久化失败

- A：立即 fail-stop 新 Model/tool/副作用；显示已保存 seq、当前 operation 和 retry/read-only/exit。（推荐）
- B：立即阻断新动作，尝试一次安全收口；无论收口结果如何都退出，并把可证明事实输出到 stderr/仍可写 XML。
- C：进入只读诊断状态，只允许查看已保存 Context、运行 self-test 第一阶段静态检查和预览 support；只有持久化恢复并验证后才能退出只读状态，第二/三阶段不得产生无法保存的新网络/Model 事实。

推荐 A。它给用户修复磁盘/权限的机会且不继续制造事实。三项都禁止删除旧 XML、降低保存级别或在无法持久化时继续执行副作用。

关联：`AQ-092`、`AQ-172`、`AQ-227`、`CTX-03`。

### ED-07 support 输出和遥测

- A：先预览版本/平台/manifest/error ID/脱敏配置投影，用户选择“本次 stdout”或“standalone diagnostic XML”；默认不含会话正文，持久 XML 不是 active Context 事实源。（推荐）
- B：在 A 之上，允许用户在预览中显式勾选 Context event range/正文字段，显示增加的隐私范围并二次确认后只生成 standalone diagnostic XML；Key/secret 仍永不进入。
- C：只向 stdout 输出最小 support summary，yaca 不生成任何持久 support 文件；用户自行重定向得到的副本明确属于外部 user export，不是 yaca 事实源。

推荐 A。support 是用户动作，不是后台 channel。三项都无遥测、自动上传或隐式更新联网；都不创建 `.log`/`.txt`/`.json`/`.zip` 长期诊断物，也不把 diagnostic XML 伪装成可自动续作的 Context。

关联：`AQ-238`、`AQ-246`、`DIAG-08`、`REL-11`、`SAFE-09`。

### ED-08 English UI 与 Unicode 数据

- A：程序文案/字段 ASCII English；数据 UTF-8，Windows 路径用 wide API，显示失败时转义但身份不变。（推荐）
- B：普通 transcript 尽力显示 Unicode；审批/错误目标同时追加精确 escaped identity，文件操作和 hash 始终使用原 identity。
- C：所有路径在审批、错误和 machine output 中固定 ASCII escape；普通用户/模型正文仍按 UTF-8 尽力显示。

推荐 A。只支持 English UI 不等于破坏中文路径；三项都不按 console code page 改写 XML，也不让显示替换参与 hash/Resolver/权限判断。

关联：`AQ-045`、`AQ-177`、`AQ-223`、`AQ-340`、`PLAT-09`、`PROD-15`。

### ED-09 terminal control 与能力降级

- A：外部控制序列使用可见 escape notation；能力不足时保留同一文字语义，只降视觉增强。（推荐）
- B：renderer 剥离外部控制序列并显示 omitted count；换行/tab 仍按有界规则保留。canonical result 由存储 schema 独立记录，renderer 的剥离/摘要既不替代也不改写它。
- C：外部内容进入带来源标签的数据块，C0/C1/CSI/OSC 一律 escape；程序自己的有限颜色仍由能力后端控制。

推荐 A。它让用户看见内容被处理过。三项都阻断终端注入，并在 `TERM=dumb`/XP 无 VT 时保留完整操作能力。

关联：`AQ-090`、`AQ-231`、`AQ-339`、`THREAT-05`、`TUI-16`、`TUI-17`。

### ED-10 error 详情交互

- A：主卡短且可行动，`.error <id>`/details 追加有界安全 cause。（推荐）
- B：fatal/unknown 默认在主卡后追加一段有界脱敏 details，其他错误仍显式请求 details。
- C：每张主卡自动追加一行 safe cause summary；更深的 typed chain 仍通过 details 显式追加。

推荐 A。plain transcript、重定向和旧终端都可用，日常错误也不会淹没主旅程。三项只决定何时展开技术详情，不改变 ED-03 的主卡责任层，也不输出 secret/raw body。

关联：`AQ-069`、`AQ-201`、`AQ-203`、`AQ-334`、`TUI-19`。

### ED-11 Context 建立前或 writer 已 faulted 时的崩溃报告

问题：当 canonical XML 还不存在或已经不能安全写入时，怎样留下可行动但不泄密的当次诊断？

- A：向 stderr 写最小 typed fatal card（error ID、阶段、程序/平台版本、last durable seq、side-effect state、exit class），不含 Prompt/Key/body；用户之后可显式运行 self-test/support。（推荐）
- B：向 stderr 只写一行稳定 error ID、safe stage 和 exit class；更完整的脱敏诊断只能由用户后续显式生成。
- C：向 stderr 写多行有界安全卡，可含脱敏 Lua symbol/stack frame，但不含正文、Key、header、原始请求或文件内容；不自动另存。

推荐 A。stderr 是当次输出，不成为第三事实源；脚本、截图或用户重定向仍能保留最小证据。三项都不开 crash.log；若 XML 尚可写，canonical crash/cause 仍进入 XML，若 writer 已 faulted 则明确未保存。

关联：`DIAG-09`。

确认后 owner artifact：`15-diagnostics-and-logging.md` 的 pre-Context/faulted-writer crash matrix，包含 stderr 字段、secret redaction、exit class 和 support 生成前置。

### ED-12 多阶段或 batch 的部分成功怎样显示

问题：一次自检、批量操作或管理事务中，已成功、失败、未开始和结果未知同时存在时，主卡如何说真话？

- A：每个子项有稳定 item ID 与 `success|failed|skipped|unknown`；先显示逐项/分组表，再显示总计，任一 failed/unknown 使总结果成为 partial/failed。（推荐）
- B：主 transcript 每个 item 一行，最后显示四类计数；完整参数与 cause 进 details/XML，failed/unknown 仍在主结果中点名。
- C：主卡先显示四类计数并列出所有 failed/unknown item ID；success/skipped 清单通过 details 查看，canonical item result 全部进 XML。

推荐 A。它最直观地呈现部分成功。三项都保存此前真实结果，不把 partial 投影为 success，也不因 UI 紧凑而丢失任何 canonical item fact。

关联：`DIAG-12`。

确认后 owner artifact：`15-diagnostics-and-logging.md` 的 aggregate/partial-result schema 与对应 TUI/XML/exit-class 投影表。

### 完整推荐回复模板

```text
ED-01 A
ED-02 A
ED-03 A
ED-04 A
ED-05 A
ED-06 A
ED-07 A
ED-08 A
ED-09 A
ED-10 A
ED-11 A
ED-12 A
```

## 本包确认后必须形成的工件

1. error ID/category/severity/retryability registry 与 cause mapping。
2. 每个 AgentLoop state 的 error/cancel/retry/close 转换表。
3. user error card、retry、fatal、broken-pipe 和 recovery golden transcripts。
4. XML diagnostic event 与 LogLevel/data-classification schema。
5. stderr/stdout/exit class 和 support output contract。
6. terminal control sanitization、Unicode display 与 capability fallback tests。
7. 持久化失败、磁盘满、网络阶段、helper 崩溃和关闭 deadline fault fixtures。

发布和平台 exact-hash 证据由包 10 收口。本包未明确回复的任何推荐都不会自动写入 `DECISIONS.md`。
