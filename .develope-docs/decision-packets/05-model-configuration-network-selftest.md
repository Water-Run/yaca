# 决策包 05：Model、完整配置、网络与 Self-Test

更新日期：2026-07-22

状态：等待项目负责人回复；本文的推荐、字段名、默认数字、页面示例和方案编号都不是已确认决定

## 本包要决定什么

本包把四件实际上无法分开设计的事情放在一起：

1. 一个 Model connection 到底要写清哪些信息，才能不用猜测就发出请求。
2. Streaming、Tools、timeout、retry、proxy、CA 和资源上限如何共同形成可测试的网络契约。
3. 完整主 INI、Context XML 会话覆盖、手工编辑、model-repl 与 config-repl 怎样共享同一份真相。
4. 三阶段 self-test 怎样从纯静态检查，经过用户明确同意的真实联网检查，走到只作建议的 LLM 语义审阅。

逐字段候选、secret 标记、生效点、XML snapshot 和 65 条跨字段/生命周期校验已经集中在 [配置 Schema 候选注册表](../CONFIG-SCHEMA-CANDIDATE.md)。本包不再复制那张大表，只决定会改变其结构或用户体验的上游选择。

第四轮 [配置完整性专项审计](../CONFIG-COMPLETENESS-AUDIT.md) 又从“外部编辑配置后下一 turn 会怎样”“HTTP 会不会明文发送 Key”“只有 INI/XML 时 LogLevel 写到哪里”等实际运行场景反查了一遍。本版已经把 `CCA-Q-01` 至 `CCA-Q-15` 全部归档：reload 和 Model scheduler 由 F4 包承担；宿主配置隔离、双 digest、内部 hard cap 与 catalog parity 属于不可关闭的技术责任；其余真实产品轴各有独立 M05 编号。文末交叉表禁止同一问题在两个组重复回答。

本包不决定：

- Agent 默认人格和 SystemPrompt 英文原文；
- tool call 执行、DoubleCheck verdict 和 AgentLoop 的完整状态机；
- Context XML 元素与原子提交算法；
- 最终 CLI 简称、颜色常量和精确退出码。

它可以决定 Model 声明 native tools、网络 adapter 怎样测试它，却不能在这里决定收到 tool call 后怎样审批和执行。

## 已经确认、这次不重新询问的前提

1. 一个 Model section 就是一个完整 LLM 连接实例。不会拆 Provider、Credential 或共享 secret object。
2. Key 直接明文保存在主 INI；所有条件 secret 字段也进入同一 typed registry。本文仍要决定怎样避免 registered config-secret value 进入 argv、XML、日志和不受控临时文件；Runtime 自己放置 secret 的结构化 carrier 永远受禁入规则约束，普通正文中与过短 secret 恰好相同的字节怎样处理只由 M05-59 决定。
3. Streaming 有 force、try、off 三态，不退回布尔开关。
4. retry 配置属于各个 Model；代理属于全局配置。
5. 不因 Model 失败而静默切到另一个 Model。
6. 全局可以有 SystemPrompt；每个 Context 可以用 .prompt 保存 ContextPrompt。
7. 配置由完整用户 INI 和 Context XML 中允许的会话覆盖共同形成。
8. 第一 Model 和第一 Permission 的物理顺序表示新 Context 默认项，不增加第二套 Default ID。
9. 没有首次设置首页。首次配置由用户显式运行 model-repl；config-repl 是可选的完整配置浏览/编辑入口。
10. 正常 Agent 在主配置无效时不能启动。help/version、首次创建配置和静态 self-test 是否走 bootstrap reader 是本包需要收口的恢复边界。
11. 启动、浏览配置和静态 self-test 不隐式联网。
12. 文件长期数据面保持 INI/XML；临时文件、锁和 report XML 是否允许仍以其他决策包为准。

## 先统一几个术语

| 术语 | 本包含义 |
| --- | --- |
| Model logical name | Model.DeepSeek 这类 section suffix；用户通过 Model-switch semantic action 或 model-repl 选择的名字，chat root 只由 TU-32 投影 |
| RemoteModel | 真正发送给 endpoint 的远端模型 ID |
| Protocol | 请求/响应线格式，例如 openai-chat；不是厂商品牌 |
| Endpoint | 连接的 HTTP(S) 地址；是完整 URL 还是 base URL 待决 |
| AuthMode | Key 怎样成为鉴权 header，或者明确不鉴权 |
| declared capability | INI 中用户声明的 Streaming/Tools 等能力 |
| observed capability | self-test 本次真实观察；不是永久权威配置 |
| logical request | AgentLoop 的一次模型意图，拥有稳定 request ID |
| attempt | logical request 的一次网络尝试；重试会产生新的 attempt ID |
| Context override | XML 中允许覆盖 INI 默认的少量会话值 |
| snapshot | XML 保存的历史非秘密投影；不是目标机的新配置定义 |
| bootstrap reader | 只依赖内置 schema、用于创建/诊断配置的受限入口，不启动 Agent |

## 三套连贯总体方案

### 方案 A：显式、严格、单协议先闭环（推荐）

- 每个 Model 明确写 Protocol、完整 Endpoint、RemoteModel、AuthMode、明文 Key、Streaming、Tools、窗口、四阶段 timeout 和 Model 级 retry。
- v0.1 先把 openai-chat compatible 的流式、tool calling、usage 和错误完整闭环；其他 native protocol 后续按相同内部接口加入。
- Endpoint 是最终请求 URL，preset 可以帮用户填写，但 Runtime 不猜 path。
- AuthMode 只有 protocol 和 none；Key 只在 INI。
- Tools 首版只有 native/off，不实现 prompt-emulated tool calling。
- retry 依据网络阶段决定；一旦 request body 可能已被处理或收到任何规范响应事件，不盲目重放。
- 全局代理、随包 CA 和严格 TLS；不提供 insecure 开关。
- typed schema 驱动 INI、两个 REPL、help、脱敏和 self-test。
- XML 最小覆盖 Model/Permission 选择、DoubleCheck 和 ContextPrompt；连接和安全定义留在本机 INI。

优点：每个行为可解释、可离线校验，失败不会靠自动猜测掩盖。首版协议范围有限，但在这个范围内可以做完整契约测试。

代价：自定义 gateway 需要精确 URL 和可能的附加 header；Anthropic native 等协议不会因为 README 列出品牌就自动成为 v0.1 硬承诺。

### 方案 B：双协议与兼容参数优先

- v0.1 同时正式支持 openai-chat 和 anthropic-messages。
- Endpoint 可以写 base URL，由 protocol adapter 拼 path。
- Auth 仍 typed，但允许更多 protocol-specific version/header。
- Model 可配置较丰富的公共采样参数、public/secret headers 和白名单 extra parameters。
- 其余严格 retry、secret、INI/XML 和 self-test 边界与方案 A 相同。

优点：首版可直接覆盖更多原生厂商 API，不必要求用户使用兼容 gateway。

代价：消息角色、system Prompt、tool call streaming、usage、refusal、错误和测试 fixture 都要维护两套。XP/CentOS 7 网络和 XML 测试不减少，Model 协议测试几乎翻倍。

### 方案 C：最少字段、运行时自动猜

- Model 只填 URL、Key 和远端模型名。
- Runtime 根据 URL/响应自动猜 Protocol、鉴权、path、Streaming 和 Tools。
- 一个总 timeout，一个宽松 retry；未知字段尽量忽略。
- XML 尽量复制当前完整配置，恢复时自动 fallback。

优点：添加 Model 的表单最短。

代价：一次“探测”可能已经联网、计费或把 Key 发到错误地址；同一个配置在不同网络错误下会得到不同能力结论。静默 fallback 还会改变隐私和费用。它无法兑现强 self-test、可移植 Context 和可解释失败，不推荐。

### 推荐基线

推荐方案 A。它不是“功能少”，而是把第一套正式协议做完整；Model preset、extra headers 和以后新增 adapter 仍有明确扩展点。若负责人认为 Anthropic native 必须是 v0.1 的完整能力，可在 A 的其余边界不变时采用 B 的双协议范围。

## 推荐的完整配置数据流

~~~text
typed schema / Runtime hard limits
             |
             v
full user config.ini
  General / Agent / Network / Exec / Context
  Permission.* / Model.*
             |
             +---- model-repl edits Model.* through one transaction service
             |
             +---- config-repl edits all other schema fields
             |
             v
Context XML whitelist override
  CurrentModel / CurrentPermission
  DoubleCheckOverride / ContextPrompt
  optional budget overrides (still pending)
             |
             v
immutable effective snapshot at turn start
             |
             +---- Model protocol + network request
             +---- XML non-secret historical snapshot
             +---- status / diagnostics / self-test
~~~

项目文件不在这条链上。手工编辑和 REPL 也不是两个 schema：二者最终必须经过同一个 parser、校验器、跨字段规则和安全发布服务。

## Model 的候选最小闭环

完整字段定义见 CONFIG-SCHEMA-CANDIDATE.md。这里用一条用户能理解的模型说明它们为什么同时存在：

~~~text
Model.DeepSeek
  identity       Enabled / conditional Abbreviation (M05-57) / Description / optional Color (M05-21)
  wire protocol Protocol=openai-chat
  destination   Endpoint=https://.../v1/chat/completions
  remote id     RemoteModel=deepseek-chat
  authentication AuthMode=protocol / Key=...
  capability    Streaming=force|try|off / Tools=native|off
  limits        ContextLength / MaxOutputTokens
  deadlines     Connect / FirstEvent / Idle / Total
  retry         per-Model minimal fields or typed preset (M05-58)
  optional      adapter generation fields or intents / public reasoning policy / allowed headers
~~~

这些值组成同一个连接实例。重复 endpoint/Key 是已经接受的简单性成本；REPL 可以提供“复制 Model”来减少手工重复，但磁盘上不建立跨 section 引用。

## Streaming、timeout 与 retry 的候选语义

### Streaming 三态

| 值 | 候选行为 |
| --- | --- |
| force | 必须使用 streaming；adapter 已知不支持或 endpoint 明确拒绝时失败，不静默降级 |
| try | 先请求 streaming；只有任何规范 response event 之前、错误明确表示“不支持 streaming”时，允许一次 non-stream fallback |
| off | 直接请求完整响应；不先做联网能力探测 |

try 的观察结果候选只按 Model 非秘密配置 digest 缓存在当前进程。self-test 可以显示 observed capability，但不能永久把一次临时失败改写成 off。

### 四种 deadline

| deadline | 从哪里开始，到哪里结束 |
| --- | --- |
| ConnectTimeoutMs | DNS/connect/TLS 建立阶段 |
| FirstEventTimeoutMs | request body 发送完成到首个规范 response event |
| IdleTimeoutMs | streaming 中两个有效协议事件之间 |
| TotalTimeoutMs | 推荐覆盖整个 logical request，包括 attempts 与 backoff；是否改成 per-attempt 待决 |

所有 deadline 还受 AL06-42 的有效 turn active-time guard 限制。TCP 收到几个无意义字节不应重置 IdleTimeout；只有 parser 接受的协议事件才算进展。

### Retry-by-phase

| 失败阶段 | 是否自动 retry（推荐） | 原因 |
| --- | --- | --- |
| DNS/connect/TLS，尚未发送 request body | 可以，在 Model 次数和 turn 总预算内 | 服务端还没有收到生成意图 |
| request body 可能已发送，没有 HTTP response | 不自动 retry，标记 outcome unknown | 服务端可能已生成/计费 |
| 明确 429/服务不可用且 adapter 能证明没有生成事件 | 按 Retry-After 和安全 allowlist 有界 retry | 有明确瞬时失败证据 |
| 已收到 text/tool/reasoning/usage 任一规范事件 | 不重发整次 request | 会重复内容、tool call 或费用 |
| JSON/SSE/tool arguments 协议畸形 | 不用相同 payload 盲 retry | 通常不是瞬时网络错误 |
| auth、普通 4xx、内容拒绝 | 不 retry | 配置/请求/策略问题不会靠重放修复 |
| 用户取消 | 不 retry | 取消不能变成延迟后的自动执行 |

每个 logical request 和每个 attempt 分开记录用量、时间和错误。curl 自带 retry 关闭，避免 Runtime 不知道发生了多少次请求。

### 资源上限

网络至少需要 header、单 SSE event、总缓冲和 response/tool arguments 的硬上限。达到上限返回 typed limit error，不把内存耗尽当作普通断网。具体候选字段和值在 CONFIG-SCHEMA-CANDIDATE.md；数字必须由 XP x86 和 CentOS 7 fixture 校准。

## Key、Auth 与 curl 的候选边界

明文 Key 是可读配置的明确选择，不等于 Key 可以出现在所有地方：

- INI 中以 secret 字段保存；
- REPL 只提供 keep/replace/clear，不揭示当前值；
- Runtime 自己从 registry 取出的 secret 不进入 XML、Model snapshot digest、普通错误、支持输出或 argv；普通正文恰好命中过短 secret 时的 exact-scan 保证服从 M05-59；
- Endpoint userinfo、proxy password 和 SecretHeader 使用同样规则；
- 用户自己把 secret 粘进 conversation/command 时无法保证自动识别，导出必须提醒。

CONFIG-SCHEMA-CANDIDATE.md 已比较三套 curl 传递：

1. curl config 从 stdin 读取 secret，request body 使用受保护临时文件；
2. request body 从 stdin，secret curl config 使用临时文件；
3. 极小 native libcurl/helper 全部在内存传递。

当前推荐先验证第 1 套，因为 Key 不落临时磁盘，又能继续使用随包 curl。若最终原生 helper 已因 XP Unicode/进程控制成为正式依赖，再比较第 3 套。任何方案都必须把临时 request body 当作可能含 secret 的数据。

## INI、XML 与事务边界

### 主 INI

候选正式支持手工编辑，但严格而不宽猜：

- UTF-8；section/key/enum 使用 ASCII；
- bool 只有 true/false，整数十进制，单位写在名字里；
- string 使用双引号和唯一转义规则；
- singleton section/key 不得重复；
- Model/Permission section 顺序完整保留；
- 第一 Model/Permission 就是新 Context 默认项；
- unknown security field 是硬错误，不可忽略后继续；
- REPL parser 保留注释、空行、顺序和未修改文本；
- SystemPrompt 多行候选使用 quoted string 中的明确换行转义；三引号仍可选择。

### Context XML

推荐最小 override whitelist：

- CurrentModel；
- CurrentPermission；
- DoubleCheckOverride=inherit|true|false；
- ContextPrompt。

是否允许 Context 下调 turn budget/压缩阈值是独立选择。XML 不覆盖任何 registered config-secret value、Endpoint/Protocol 定义、proxy/CA、Permission 定义、Exec 环境或 profile 定义。

XML 可以保存历史 Model 的非秘密 snapshot，让接盘者知道原 Protocol、Endpoint、RemoteModel、窗口、Streaming 与 Tools；目标机仍需在本机 INI 提供该连接所需的全部匹配 config-file secrets。导入 XML 若选择更宽松 Permission 或关闭本机默认 DoubleCheck，推荐继续前显著确认。

### 手工编辑与 REPL 共用的保存事务

~~~text
read bytes + file identity/digest
  -> parse a comment/order-preserving draft
  -> edit only in memory
  -> field validation + cross-field validation
  -> show redacted diff and default-order changes
  -> recheck external file identity
  -> write same-directory no-replace temp
  -> flush + parse again
  -> platform-proven safe replace
  -> preserve old file if any step fails
~~~

model-repl 和 config-repl 只能是这个服务的两个 UI adapter，不能各写一套 INI。

## model-repl 的 ASCII 页面候选

固定程序文字只用 English/ASCII；用户 Model 名、endpoint 和说明属于用户数据，可经过边界编码显示。下列 transcript 决定信息层级，不冻结最后空格和颜色。为保持逐行样稿可读，代码块中的 `model>`/`config>` 只投影 TU-33 A，后续 `choice>`/`models>` 只是 local focus 的可读占位；它们都不冻结输出字面量。TU-33 B/C 时必须由同一 prompt registry 生成所选完整 surface/state 名，或统一 `yaca>` 加不可省略的 focus/state 行，本包不拥有提示符字面量。

### Model list

~~~text
MODEL REPL
config: C:\Tools\yaca\__yaca__\config.ini
ordinary Agent: physical item 1 must be enabled and valid; no skip
dirty: no

 #  MODEL       ABBR  ON  PROTOCOL     STREAM  TOOLS   KEY  STATUS
 1  DeepSeek    ds    yes openai-chat  try     native  set  not tested
 2  Local       lo    no  openai-chat  off     native  none draft

Commands:
  add  edit <name>  copy <name>  enable <name>  disable <name>
  first <name>  move-before <name> <target>
  test <name|all>  delete <name>  save  discard  help  exit

model>
~~~

Key 只显示 set/none。上例假设 M05-57 B/C，因此有 `ABBR` 列；M05-57 A 时该列和 detail 字段整体消失，不保留一列 `-`。允许 Abbreviation 的路线中，disabled 草稿尚未填写时才显示 `-`，选择/编辑使用 row ID 或完整 logical name，不能临时发明简称。not tested 是观察状态，不把联网测试变成配置有效性的前提。

### Model detail

~~~text
MODEL: DeepSeek
logical name: DeepSeek
abbreviation: ds  # only when M05-57 B/C
enabled: true

Connection
  protocol: openai-chat
  endpoint: https://api.example/v1/chat/completions
  remote model: deepseek-chat
  auth: protocol
  key: ******** (configured)

Capability
  streaming: try
  tools: native
  context length: 128000 (declared)
  max output: 8192

Network policy
  proxy: environment (global)
  CA: bundled (global)
  timeout: connect 10s / first 60s / idle 60s / total 600s
  retry: 2 / 1s..10s

Actions: edit  test  copy  disable  delete  back
~~~

### Secret edit

~~~text
EDIT KEY: DeepSeek
Current value is configured and cannot be revealed.

  1  Keep current value        (default)
  2  Replace value
  3  Clear value
  4  Cancel

choice>
~~~

Replace 输入不得进入 terminal history。终端无法安全关闭 echo 时，必须显示能力限制并提供安全的手工 INI 路径，不能把星号显示等同于真实隐藏。

### Save confirmation

~~~text
MODEL CONFIG DRAFT
changes:
  + Model.Local
  ~ Model.DeepSeek.Streaming: off -> try
  ~ default Model: Local -> DeepSeek
  ~ Model.DeepSeek.Key: unchanged

validation: OK
network access: not attempted

save changes? [y/N]
~~~

## config-repl 的 ASCII 页面候选

config-repl 浏览同一 typed schema。Model section 显示只读摘要并跳转 model-repl，避免两个编辑器对同一 secret 字段形成不同体验。

### Home

~~~text
CONFIG REPL
config: C:\Tools\yaca\__yaca__\config.ini
schema: 1.0
dirty: no
validation: OK

  1  General       SystemPrompt, LogLevel, optional self-test reviewer
  2  Agent         DoubleCheck, budgets, stuck limits
  3  Network       Model proxy/CA/limits; optional DirectHttp policy
  4  Exec          command timeout, output, environment
  5  Context       jump, naming, compaction, size limits
  6  Permissions   3 profiles; first = Std
  7  Models        2 entries; first = DeepSeek   [open model-repl]
  8  Effective     show INI + Context override + final value
  9  Validate      run static schema checks

Commands: open <number|name>  search <text>  save  discard  help  exit
config>
~~~

### Field detail and source

~~~text
FIELD: Agent.DoubleCheck
type: boolean
INI value: false
Context override: true
effective value: true
applies: next turn
secret: no
snapshot: yes

Meaning:
  Spend more time and tokens for greater safety.
  Includes termination review. Action-review scope is decided elsewhere.

Actions: set true|false  reset  back
~~~

### Schema validity 与 Agent eligibility 分开显示

~~~text
SCHEMA VALID / AGENT INELIGIBLE

  CFG-MODEL-DEFAULT-DISABLED
    Model.Local is the first Model but Enabled=false.
    Ordinary Agent startup does not skip to a later item.
    Fix: enable it or move another valid Model to physical item 1.

This management-only generation may be saved only under M05-30 B.
Actions: enable  move-first  save  discard  back

VALIDATION FAILED (2 errors)

  CFG-TIMEOUT-ORDER
    Model.DeepSeek.ConnectTimeoutMs exceeds TotalTimeoutMs.

  CFG-SECRET-IN-PUBLIC-HEADER
    Model.DeepSeek.PublicHeader.Authorization is reserved.
    Fix: use Key/AuthMode; this field will not be saved.

No file was changed.
Actions: edit  show-all  discard  back
~~~

`SCHEMA VALID / AGENT INELIGIBLE` 是可管理状态，不得伪装成字段错误；只有 M05-30 B 允许把它作为第一份配置发布。`VALIDATION FAILED` 才阻止任何路线的保存。如果原配置已经损坏，bootstrap config-repl 可以显示 raw location、解析错误和修复草稿；它不能启动 Agent、联网或把无法理解的 unknown required field 重写掉。

## 三阶段 self-test：四屏状态机

self-test 是显式诊断命令，不是每次启动的隐藏网络探测。候选流程：

~~~text
screen 1: Stage 1 static result
  -> fatal static error: stop with management actions
  -> static pass: offer Stage 2

screen 2: network/cost consent
  -> back/exit: finish with static-only result
  -> selected models: run Stage 2

screen 3: Stage 2 online result
  -> any selected required Model failed: do not offer Stage 3
  -> all selected required Model checks pass: offer Stage 3

screen 4: Stage 3 semantic advisory + final summary
~~~

### Screen 1：静态基础检查

~~~text
YACA SELF-TEST 1/3 - STATIC
network access: disabled

PASS  package target             windows-x86
PASS  required resources         14/14
PASS  config syntax/schema       0 errors, 2 warnings
PASS  default Model              DeepSeek
PASS  default Permission         Std
PASS  proxy/CA syntax            environment / bundled
PASS  config-secret registry     4 values in allowed sources
PASS  exec env baseline          compat-allowlist-v1 / 12 names
PASS  internal helper env        isolated
PASS  writable data/temp         verified
PASS  XML parser/security        DTD/entities disabled
PASS  Context scan sample        18 valid, 0 damaged
WARN  config file permissions    cannot prove ACL on this volume

Static result: PASS WITH WARNINGS
No network request was made.

Next:
  1  Review warnings
  2  Continue to online Model checks
  3  Exit with static-only result
choice>
~~~

Stage 1 候选检查：发行包架构与资源 hash、Lua/native ABI、INI grammar/schema、命名/顺序、所有跨字段规则、所有 registered config secret 的来源/位置与承载文件权限、proxy/CA 字段、M05-15/M05-55 所选 exec baseline manifest/公开变量名集合/credential canary、内部 helper 环境隔离、临时写入/替换能力、XML parser 安全、Context 目录可读性和已知残留。它只比较名称、类别、source、baseline identity 和不含值的 public digest，不显示环境值，也不执行工作区命令。

### Screen 2：联网与费用确认

~~~text
SELF-TEST - ONLINE CONSENT

This stage will contact configured LLM endpoints and may use tokens.
Conversation and Context content will NOT be sent.

 #  MODEL       ORIGIN                    PROXY        KEY  REQUESTS
 1  DeepSeek    https://api.example       environment  set  up to 3
 2  Local       http://127.0.0.1:11434    bypass       none up to 3

Checks:
  DNS/connect/TLS/proxy/auth
  protocol response and usage
  configured streaming mode
  native tool-call capability (tool will not be executed)

Select: all | 1,2 | back
models>
~~~

同意必须显示目标 origin、代理、Key 是否 configured、最大 request 数和会发生 token 消耗。不能只显示“开始深度测试吗？”。

### Screen 3：真实 Model 检查结果

~~~text
YACA SELF-TEST 2/3 - ONLINE

MODEL DeepSeek
  PASS connect/TLS              182 ms
  PASS authentication
  PASS protocol                 openai-chat
  PASS streaming=try            streaming used
  PASS tools=native             one valid call, not executed
  PASS usage                    provider reported

MODEL Local
  PASS connect                  12 ms
  PASS authentication           none
  PASS protocol                 openai-chat
  PASS streaming=off
  PASS tools=native             one valid call, not executed

Online result: PASS (2/2)
Requests: 4   Input tokens: 214   Output tokens: 37

Next:
  1  Run semantic configuration review
  2  Show request details (secrets removed)
  3  Finish without semantic review
choice>
~~~

工具能力测试只要求模型返回一个无副作用的 synthetic tool call，Runtime 验证但绝不执行。Streaming=force 失败就是 Model 检查失败；try 可以记录实际 fallback，但只有明确 unsupported 错误才算合法。

### Screen 4：LLM 语义审阅与最终结果

~~~text
YACA SELF-TEST 3/3 - SEMANTIC REVIEW
reviewer: DeepSeek
prompt version: config-review/1
authority: advisory only

WARN  Permission.TrustMeBro
  The description says "read only", but Shell=allow and Write=allow.
  Deterministic schema is valid; review the intended meaning.

WARN  Model.DeepSeek
  The logical name suggests DeepSeek, but RemoteModel is mimo-v2.
  This may be intentional. Names do not change protocol behavior.

PASS  No obvious mismatch in 7 other reviewed summaries.

FINAL RESULT
  Static:   PASS WITH WARNINGS
  Online:   PASS (2/2)
  Semantic: 2 ADVISORIES

No configuration was changed.
No registered config-secret value was sent to the reviewer.
~~~

Stage 3 只读取脱敏、结构化配置摘要。它可以发现“Yolo 名称却只读”“DeepSeek 名称却指向 Mimo”等意图疑点，但不能把名称当作安全事实，也不能覆盖 Stage 1/2 结果。reviewer 无工具；输出必须注明模型、Prompt 版本、输入摘要 digest 和 advisory 权威。

## 已确认逐 turn 配置载入对冻结题面的解释

D-048 已经确认：每个新顶层 main/side turn admission 前完整读取 INI；bytes 改变时整份验证并自动原子激活有效 generation，无需也不提供显式 reload、重启确认、watcher 或 reload-policy 字段。因此下面冻结问题中任何“手工编辑后显式 reload/重启”的旧字句都只保留为提问时证据，不能成为现行行为。

这尤其约束 `M05-48`：它仍只决定 config-repl 对 Permission profile 生命周期的管理覆盖。若以后选择 B，add/rename/delete/reorder 仍可要求用户手工编辑 INI，但合法结果在下一顶层 turn 由 D-048 自动观察；不得再要求显式 reload/重启。本文末尾称 `F4-01` 尚待回复的文字同样是冻结历史，现行状态以 D-048 和 packet 11 的上游投影为准。

## Model、配置与 self-test 的 57 个负责人决定

下面每组回复后才会写入 DECISIONS.md。未回复、只阅读或没有否定推荐都不算确认。

### M05-01：v0.1 协议范围

问题：首版正式闭环哪些 wire protocol？Endpoint 的物理写法由 M05-33 独占，本组不再夹带决定。

- A：只正式闭环 `openai-chat` compatible。（推荐）
- B：同时正式闭环 `openai-chat` 与 `anthropic-messages`。
- C：同时正式闭环 `openai-chat`、`openai-responses` 与 `anthropic-messages`；三套都必须通过各自 stream/tool/usage/error/retry fixtures 才能发布。

推荐 A。一套协议先把 stream/tool/usage/error/retry 测透；选择 B/C 是真实增加正式 adapter 与跨 Model 测试面，不是把协议名写进枚举就算支持。

关联：AQ-138、AQ-218、MODEL-01、MODEL-04 至 MODEL-06、NET-10。

### M05-33 Endpoint 的物理写法

问题：每个完整 Model instance 怎样表达请求地址，才能支持代理前缀和非标准部署，又不让 adapter 猜出不同 URL？

- A：保存完整请求 URL；adapter 不追加 path。（推荐最直接）
- B：保存 origin/base URL，adapter 按 Protocol 版本追加一个固定、可显示的标准 path；非标准 path 必须选另一个 adapter。
- C：保存 base URL（可含部署前缀）和独立 typed `ApiPath`；两者规范拼接，最终 URL 在 model-repl/self-test 中完整预览。

三项都禁止 URL userinfo、在 query/fragment 放 secret，以及 adapter 静默重复/丢失 path。

推荐 A。它最不容易因服务兼容层差异猜错；B 配置更短，C 对反向代理最灵活但多一个必须验证的字段。

关联：`AQ-284`、`NET-10`、`MODEL-01`。

### M05-02：AuthMode、空 Key 与鉴权边界

问题：一个 Model 的完整 Endpoint、AuthMode、空 Key、URL 中的凭据与 Runtime 必需 header 如何组成不会被自定义字段偷换的产品契约？

- A：`AuthMode=protocol|none`；空 Key 只在 `none` 或 adapter 明确允许时合法。（推荐最简）
- B：在 A 上增加 adapter 注册的 typed `bearer-header|api-key-header`；header 名来自 adapter schema，不能自由覆盖 Runtime 保留字段。
- C：不提供用户 `AuthMode`；每个 Protocol adapter 固定自己的鉴权方式，`none` endpoint 必须由独立 adapter 类型表达。

三项都服从同一硬边界：URL userinfo/query 不得携带 Key/secret，Runtime auth/content/tool headers 不可被自定义字段覆盖，所有 secret 都进入同一 typed registry，并标明 `config-file|ambient-environment|user-content|runtime` source；文件权限政策只能消费实际承载于该文件的 source，不能拿 config.ini ACL 替环境值背书。

推荐 A。B 支持更多非标服务但扩大 schema，C 最窄却需要为无鉴权本地服务提供清楚的 adapter 身份。M05-23 独占 custom header/body 的普通扩展面。

**技术证明，不是负责人投票：** Key/header/body 究竟使用 stdin、受保护临时文件或 native helper，必须由 TP-006 在 XP x86 与最终 curl/helper 上用 registry 生成的 secret canary、残留恢复和进程检查选出。无论证据选哪条 carrier，Runtime 从 registry 取出的 secret 都不得被 carrier 写入 argv、XML、诊断或可读临时残留；普通 canonical 正文与过短值相同的字节是否全局扫描只服从 M05-59，不能把候选实现路径写成已确认产品偏好。

关联：AQ-017、AQ-040、AQ-137、AQ-219、AQ-223、AQ-250、`AQ-284`、CFG-04、NET-03、SAFE-09、TP-006。

### M05-54 明文秘密配置文件权限不足时的运行政策

通俗场景：Key 已确认直接写在主 INI；条件配置还可能含 proxy credential、`SecretHeader`、`EnvironmentSet` value 或 adapter 登记的其他 secret。NTFS/POSIX 通常可以把文件限制为当前用户可读，但 FAT、共享目录、旧 Windows ACL adapter 失败或无法证明权限时，yaca 必须在“兼容旧机器”和“不要静默使用暴露风险未知的配置秘密”之间作出明确选择；TUI 把值显示成星号并不能保护磁盘文件。

“secret-bearing consumer”是由 typed registry 确定的实际消费者：例如将 Key/SecretHeader/带凭据 proxy 用于 Model 请求，把 `EnvironmentSet` secret 注入 raw exec，或让其他显式网络 purpose 经过带凭据 proxy。M05-54 只处理 `source=config-file` 且实际由被检查文件承载的 secret；`ambient-environment` proxy/credential、普通用户正文和 Runtime 临时值分别服从自己的 observation/数据生命周期，不能因 config.ini 权限良好就被放行，也不能因 config.ini 权限不可证明而被误禁。配置中有秘密不代表每个本地动作都消费它；Runtime 不得为了绕过本题而静默换 proxy route、丢弃环境值或改用另一身份。

- A：配置浏览、静态 self-test 和不消费配置秘密的本地/网络路径仍可用；每个进程第一次让任一 secret-bearing consumer 使用该规范配置位置、文件身份与 config generation 前，显示权限状态、秘密类别、受影响 Model/purpose 和风险，但不显示值，并要求一次明确确认。确认只在内存中绑定这些事实，非 TTY 失败关闭。（推荐）
- B：每个新 config generation 载入时输出一次显著 warning，secret-bearing consumer 仍可直接运行，不增加阻断确认；self-test、config status 和 support 摘要持续保留权限 warning。
- C：当权限为 `weak|unverifiable` 时，只禁用会消费配置秘密的精确 consumer：例如需要 Key/SecretHeader/凭据 proxy 的 Model 或网络 purpose，以及会注入 `EnvironmentSet` secret 的 raw exec。它们直到用户修复权限、迁移配置或显式移除该秘密配置才恢复；不消费秘密的 Model/工具、配置修复和静态诊断继续可用。

推荐 A。它不牺牲 XP/FAT/便携环境的可用性，也不把“检查不了”静默解释成“只有本人可读”；B 最简但风险提示容易被忽略，C 最严格却会让一部分目标平台上的秘密消费者不可用。

三项都固定两条必须分开的结果。第一，config create/replace 的内容、flush、最终文件身份或发布结果无法证明时，新 generation 不得激活，也不得留下半写配置。第二，内容已证明完整发布、但 ACL/mode 只能得到 `weak|unverifiable` 时，不得冒充发布失败；新配置可以作为该权限类别的有效 generation 发布，然后严格执行所选 A/B/C。temp、previous-valid 和 backup 也必须尽力使用同级权限并分类，不能用一份更宽的副本绕过结论。

权限不只在读 INI 时看一次。Runtime 在 generation 载入/激活、secret-bearing publish 结束后，以及每次 `config-file` secret-bearing consumer 真正取值前重新取得权限 observation credential；只有规范路径、文件身份、generation、权限结论与可用的 ACL/mode fingerprint 都未改变时，A 的进程内确认或 B 的已显示 generation warning 才能复用。平台无法生成 fingerprint 时仍如实得到 `unverifiable`，不虚构变化检测承诺。A 的确认不授权 endpoint、费用、Permission 或单次联网，Stage 2/3 仍需各自 consent；Runtime 控制的 secret carrier 仍不进入 XML、argv、普通日志、诊断正文或确认记录，普通正文的过短 exact match 只按 M05-59 所选保证处理。

关联：`AQ-417`、`CFG-04`、`CFG-09`、`NET-03`、`SAFE-09`、M05-02、M05-15、M05-23、M05-30、M05-36、M05-42、TS-11、TP-006、TP-010。

### M05-59 过短 config-secret 的兼容与 scanner 保证

通俗场景：如果 Key 恰好是 `a`、`ok` 或另一个很短的字节串，那么在每段模型回复、文件内容和工具输出中做 exact-value 扫描，会把大量正常正文误认成秘密；如果完全不扫，又不能继续承诺“registered config-secret 的 exact bytes 绝不会进入 XML”。本组只决定**低于可安全扫描长度的 config-secret 能否被真实 consumer 使用，以及产品对普通正文保留什么保证**。长度按 INI 解码后的原始 secret bytes 计算，不按字符数、显示宽度、单词边界或运行时出现频率猜测。

- A：由目标平台 fixture 冻结一个版本化、不可由用户调低的 `MinimumScannableSecretBytes`；低于门槛的配置仍可由 model/config-repl 查看、替换、清除和迁移，但任何会实际使用该 secret 的精确 consumer 都标为 ineligible，要求用户换成达到门槛的值、移除该 secret 或改用本来就合法的无鉴权路线。错误只显示字段 identity、secret class、所需最小字节数和修复动作，不显示值或实际长度。（推荐）
- B：允许短 secret 被 consumer 使用；Runtime 只允许它进入本次已授权 consumer 的精确私有 carrier/目的地，仍不得复制到 argv、XML 字段、临时残留、普通诊断或 reviewer/support 投影，但普通用户/模型/文件/工具正文不再为低于门槛的值做全局 exact scan。产品必须明确收缩保证：相同短字节可能作为普通 canonical 内容进入 Context XML、模型输入或导出，不能再声称所有 registered config-secret exact values 都被正文扫描排除。
- C：允许任意长度并继续对全部普通正文做全局 exact scan；命中后仍按目的地规则拒绝发送或在 canonical retention 前写 typed marker，即使它只是正常单词的一部分。这样保留最强的 exact-byte 排除保证，但短值会造成大量误阻断、误脱敏和不可读历史；Runtime 不得以“看起来常见”为由临时跳过。

推荐 A。它让“exact config secret 不进入 XML/普通日志”仍是一条可测试的统一保证，同时把不可靠的短值问题在真正使用前暴露出来；代价是某些接受极短 token 的旧本地服务必须换值或选择 B。B 的连接兼容性最好，但它缩小了已经反复引用的 XML/普通正文秘密排除承诺；C 表面最严格，却可能让一个一字节 Key 几乎阻断所有对话和工具输出。三项都不改变“Key 明文存主 INI”、不发明 secret 文件，也不承诺识别用户正文、工作区或环境中从未注册的秘密、编码/派生值或语义等价凭据。

门槛数字、目标平台一致性和 scanner 内存/吞吐由 TP fixture 冻结，不让负责人猜字节数，也不生成普通 INI 开关。判定发生在 ConfigGeneration 激活和每次 consumer admission；active request/turn 使用已经冻结的 generation，升级后发现旧值过短时从下一次 admission 起给出 typed ineligible 结果，绝不静默降级到 B、自动填充、hash 后发送或切换 Model。M05-54 的文件权限 admission 与本组正交：一个 secret 必须同时满足所选长度政策和权限政策，任一失败都不能被另一个确认覆盖。

**重复/重叠匹配是不可投票的确定性算法：** registry 中 raw bytes 完全相同的值折叠为一个 matcher pattern，并携带稳定排序的 secret class/source 集合；scanner 必须检查全部 exact patterns、跨 chunk 边界保留必要尾窗，所有相交命中合并成 maximal byte-interval union。禁止目的地时 admission 结果、允许保留目的地中的 marker 边界和类别集合都只由该 union 决定，不得随 registry 顺序、pattern matcher 遍历顺序或平台改变；marker 不保存原值、原长度或可离线比较的 equality fingerprint。相同/重叠值不会另开“选第一个 secret”的用户问题，也不使用高频启发式改变 M05-59 的已选保证。

关联：`AQ-017`、`AQ-040`、`AQ-168`、`AQ-238`、`AQ-277`、`AQ-349`、`AQ-437`、`CFG-04`、`CFG-29`、`CTX-06`、`NET-03`、`SAFE-09`、HCFG-02、HCFG-05、TP-006、TP-010。

### M05-03：Tools 能力的协议边界

问题：可执行 tool call 是否只允许 provider native/off，还是加入文本模拟协议？

- A：`Tools=native|off`，不做文本 emulation。（推荐）
- B：Model 中不存在 `Tools` 字段；每个可用于 Model 的 Protocol adapter 都必须在发行 manifest 中静态声明并实现 native tool/control schema，不具备者不能注册为这种 Model adapter。在线 self-test 没运行、失败或观察不一致都只形成 support 状态/warning，不改写配置，也不阻止保存或启用。
- C：`Tools=native|off|required-native`；`required-native` 与 Protocol adapter 静态不兼容时配置硬错误，运行请求或显式在线 self-test 观察到缺失时该次结果硬失败；从未运行在线测试仍可保存/启用。`native` 继续按用户声明授权，不由 observation 静默改写。

推荐 A。它让 self-test 和 AgentLoop 知道能否依赖结构化 call，又不新增另一套 Prompt/文本解析协议。B 直接删除整个 `Tools` 字段并把 native 变成 Protocol adapter 的静态资格，不把联网测试变成配置 gate；这是 D-031“静态检查不联网、在线检查需同意”的直接约束。`Tools=off` 能否承担 main 由 M05-26 独占；Streaming 只由 M05-25 决定。

共同组合门：`native` 不只表示“能返回某种 tool call”，还必须无损表达 TS-23 最终选择的 exact input carrier 和 TS-02 的完整 core registry。TS-23 B 若要求 bare raw exec payload，而某 Protocol 只能表达 JSON object arguments，该 Model/adapter 静态不具备 main-tool 资格；配置/Stage 1/Stage 2 必须准确报告 carrier mismatch，不能按 Model 临时隐藏 `exec`、缩小 registry 或把 bare payload 偷包成另一语义。

关联：`AQ-144`、MODEL-02、MODEL-05。

### M05-25 `Streaming=try` 的 fallback 边界

- A：只有在尚未接受任何 canonical response event、且 adapter 得到明确“streaming unsupported”证据时，允许一次 non-stream fallback；普通断网、timeout、畸形事件和任何已开始的规范输出都不 fallback。（推荐）
- B：`try` 不做自动 fallback；流式尝试失败就返回 typed error，由用户手工切到 `off` 后发起新的 logical request。
- C：在尚未接受任何 canonical response event 时，明确 unsupported 或可重试的 pre-response 传输失败都可 fallback 一次；fallback 是同一 logical request 的新 attempt，consent、预算和账单上限必须计入。

推荐 A。它让 `try` 真正提供兼容降级，又不会把普通断流重放成第二次生成、第二批 tool calls 或第二笔不可解释费用。配置仍是授权权威，preset 只预填，self-test observation 只警告，不自动改写 `Streaming`。

关联：`AQ-018`、`AQ-139`、`AQ-198`、`AQ-222`、`NET-01`、`MODEL-03`。

### M05-40 provider 公开 reasoning 内容怎样进入产品

问题：有些协议会公开返回 reasoning summary、reasoning text 或单独的 explanation block；这和 provider 不公开的 hidden reasoning 不是一回事。首版怎样处理公开字段？

- A：adapter 只接收协议明确公开、允许交付给用户的 reasoning summary，把它作为 typed canonical 内容显示并保存；hidden reasoning 不请求、不推断、不伪造，也不承诺跨 provider 恢复。（推荐）
- B：不请求、显示或保存任何 reasoning 字段，包括 provider 明确公开的 summary；只消费最终文本、tool call、usage 和控制结果。
- C：允许每个 Protocol adapter 注册 `summary|full-public|off` 能力；Model 明确选择后才请求/保存，XML 记录 exact public kind 与来源，仍绝不把 hidden reasoning 当可获取数据。

推荐 A。它保留 provider 主动交付的可见解释，同时不把内部思维链纳入“完整上下文”承诺；B 的数据面最小，C 最灵活但会增加 Model 字段、协议 fixture 与跨机 gap。

关联：`AQ-285`、`MODEL-14`、`CTX-01`、`SAFE-09`。

### M05-26 `Tools=off` 的 Model 能否当主 Agent

适用条件：仅当 M05-03 选择 A 或 C、配置中真实存在 `Tools=off` 时生效。若 M05-03 选择 B，每个可注册 Model 的 adapter 都静态要求 native tool/control schema，根本没有 `Tools` 字段或 off 路线；本组强制记为 `not-applicable`，不得生成空字段、隐藏资格开关或另一条无工具 main 分支。

- A：不能成为 main Agent，只能在 purpose 契约不需要 executable tool/control carrier 时用于 side/review/compaction，以及 PJ-12 B 下可用普通有界 basename 输出的 `context-name`。（推荐）
- B：只在该 adapter 能原生承载 AL06-02 已选择并经 fixture 证明的 control carrier 时，允许它作为无 executable tools 的受限 main chat；它不能定义第二套 finish/ask-user/refuse 协议，且需要 Coding 工具闭环时必须在发送前阻断。

推荐 A。AL06-02 是 control carrier 的唯一 owner；本题只决定所选 carrier 在 `Tools=off` 时是否足以承担受限 main，不再让 Model 配置层发明一套平行协议。

关联：`AQ-144`、`AQ-374`、`MODEL-16`、`AL06-02`。

### M05-04：timeout、retry-by-phase 与资源上限

问题：是否采用 connect/first-event/idle/total 四 deadline、按传输阶段 retry，并让总 timeout 覆盖整个 logical request？

- A：公开 connect/first-event/idle/total 四个 deadline；Total 覆盖同一 logical request 的 attempts 与 backoff。（推荐）
- B：公开 connect/first-event/idle 三个阶段值，再单独公开 `MaxLogicalElapsed`；每 attempt 的 total 重置，但所有 attempts 仍受后者硬限。
- C：用户只配置一个 `RequestDeadline`；Runtime 仍保留不可关闭的内部 connect/idle/attempt 上限并在错误中说明命中阶段。

三项都使用相同 retry-by-phase 表；接收任何 canonical response event 后不自动重放 logical request，所有方案还受 Runtime/turn 总预算。

推荐 A。它最容易解释“最多等待多久”。默认数字由旧机/真实 endpoint fixture 冻结。

关联：AQ-106、AQ-126、AQ-140、AQ-141、AQ-197、AQ-221、AQ-245、NET-05 至 NET-09、LOOP-14、LOOP-27。

### M05-58 per-Model retry 配置面采用数字字段还是策略预设

通俗场景：用户可能希望一个昂贵远程 Model 少重试、一个偶尔启动较慢的本地 Model 多等几次。D-036 已确认 retry 属于每个完整 Model，而不是全局开关；M05-04 只决定 timeout/deadline 的形态。本组只决定用户在每个 `Model.*` 中看见怎样的 retry 配置面，具体默认、范围、退避公式常量、jitter 和 Runtime maximum 都必须由旧机与真实 endpoint fixture 冻结。

- A：每个 Model 只公开 `RetryCount` 与 `RetryBaseDelayMs`；`RetryCount=0` 明确关闭自动 retry。指数退避、确定的 jitter 规则和不可突破的 max delay 使用版本化 Runtime manifest，model-repl/status 显示实际公式、manifest identity 和计算出的最坏等待。（推荐）
- B：每个 Model 公开 `RetryCount`、`RetryBaseDelayMs` 与 `RetryMaxDelayMs`；三项都只能在 Runtime hard range 内取值，用户可以收紧或在允许范围内放宽单次退避上限。
- C：每个 Model 只公开 typed `RetryPolicy=none|standard|patient`；每个 preset 在当前发行 manifest 中展开成完整 count/base/max/jitter 表。REPL、self-test 和 request snapshot 必须显示展开后的实际数字与 manifest identity，不能只保存一个随后会悄悄变义的名字。

推荐 A。它保留最常用的“重试几次、起始等多久”两个直接控制点，同时把 max/jitter 这类容易破坏总预算的细节留给有证据的 Runtime hard policy；B 最透明、也最适合特殊服务，但多一个高级字段和组合校验；C 的表面最短，却让同一 preset 在升级时需要显式 generation transition，用户也较难只改一个维度。数字未实测前，任何选项都只能写“由 fixture 提案”，不能把本文示例值当默认契约。

三项共享同一失败边界：retry eligibility 严格服从前面的 Retry-by-phase 表、M05-25 streaming fallback 和 LOOP-14；request body outcome unknown、任何 canonical response event、协议畸形、auth/普通 4xx、内容拒绝和用户 cancel 都不能因配置较大而重放。`Retry-After`、退避和全部 attempts 必须落在 logical-request deadline、AL06 turn budget 与 Runtime hard maximum 内；服务器要求的等待超过剩余门时结束为 typed budget/deadline result，不在后台偷偷排队。字段缺失、混用未选路线或越界使该 Model 配置无效，不 last-wins；配置变化只影响下一 logical request，active request 保留冻结的 retry snapshot。F4-02 仍独占多个 purpose 的 per-Model scheduler/cooldown，本组不增加全局 retry、跨进程账户限速或另一个 fallback Model。

关联：D-036、`AQ-140`、`AQ-197`、`AQ-221`、`AQ-433`、`CFG-05`、`CFG-28`、`MODEL-15`、`NET-06`、`LOOP-14`、`LOOP-27`、M05-04、M05-25、F4-02、TP-006、TP-022。

### M05-05：Model 可调请求参数的范围

问题：除了连接/能力/限制，首版允许用户改哪些请求参数？

- A：核心固定字段只保留 `MaxOutputTokens`；其他生成参数只能由具体 Protocol adapter 注册为 typed optional 白名单，字段缺失就不发送。（推荐）
- B：核心 schema 提供稳定的 generation intent（例如 `creativity`、`determinism`、`seed-if-supported`）；每个 Protocol adapter 必须显式声明该 intent 能否无损映射。不能映射就静态拒绝该字段，绝不假定不同协议的 Temperature、TopP、Seed 同名同义，也不总是发送不存在的参数。
- C：除 `MaxOutputTokens` 外不提供用户生成参数；所有采样与 reasoning 参数使用 endpoint 默认。

推荐 A。它仍能支持 Temperature、TopP、Seed、reasoning effort 或 response format，但不会假装这些字段跨协议同义。B 提供跨协议的产品意图层，却要求每个 adapter 证明映射或明确拒绝；C 最简单但牺牲可调性。custom transport headers/body 只由 M05-23 决定，不能在本组交叉选择。

三项都还有一个不可省略的 release artifact：M05-01 选定每个正式 Protocol 后，必须在编码请求前冻结该 adapter 的 exact option registry，逐项列出稳定字段名、类型/范围、missing 语义、wire 名称与编码、组合冲突、secret class、XML 投影和 golden fixture。A 不是允许运行时加载任意字段的开放 registry，B 也不是让 adapter 临场猜 intent；未列入当前发行 registry 的 option 一律 unknown/error。

关联：CCA-Q-13、AQ-136、AQ-219、`AQ-282`、MODEL-08、MODEL-11、SAFE-09。

### M05-06：配置层级与 XML override 白名单

问题：Context XML 能覆盖主 INI 的哪些值？

- A：最小四项：CurrentModel、CurrentPermission、DoubleCheckOverride、ContextPrompt。（推荐最简）
- B：四项加 turn budget/CompactThreshold overrides；这些 override 只能比 INI effective 值更严格（更低预算或更早压缩），不能提高 INI/Runtime 上限。
- C：采用显式、版本化的 session-preference allowlist：完整继承 B，并再允许 `MaxQueuedMessagesOverride`、`MaxSideRequestsOverride`、`DiagnosticDetailOverride=inherit|minimal`；只有 TU-29 B/C 已建立运行中 tool preview consumer 时，才再生成 `ToolPreviewKiBOverride`。queue/side/preview 数值只能低于 Runtime/当前有效上限，detail 只减少 optional detail；它们分别在 next queue admission、next side admission、next preview block、next diagnostic event 生效，绝不减少 canonical XML 事实或隐藏阻断错误。TU-29 A 下没有 live preview，本字段必须从 parser/REPL/help/XML 同时消失。

推荐 A。B/C 的四个 turn/threshold override 条件完全相同，C 只增加上面精确列出的 session preference，不允许开放任意 key；ToolPreview 项还必须满足 TU-29 B/C 的 consumer 条件。三项都禁止 XML 覆盖任一 registered config-secret value、Endpoint/Protocol 定义、proxy/CA、Permission 定义、Exec 环境/profile 定义或 Runtime hard cap。外来 XML 的历史 Permission/DoubleCheck 只是事实；继续工作时按 D-035 和 CX 导入契约重新求值，不能由本组选项放宽本机安全。

关联：CCA-Q-11、AQ-031、AQ-151、AQ-159、AQ-164、AQ-168、AQ-235、AQ-236、CFG-01 至 CFG-03、CFG-12、CTX-27。

### M05-27 `.cautious` 的 tri-state 与生效点

- A：无参 show；`on/off` 写入 XML tri-state override；`reset` 删除 override 并回到 INI default；下一 turn 生效，显示 INI/XML/final 来源。（推荐）
- B：只接受显式 `.cautious on|off|inherit`；无参提示 grammar，当前值统一由 `.status` 查看；仍在下一 turn 生效。
- C：无参按 `inherit -> on -> off -> inherit` 循环，并提供 `.cautious reset`；每次都先显示 old/new/source，仍只改变 DoubleCheck override。

推荐 A。三项都保留 tri-state、写入当前 XML、遵守 turn freeze，而且绝不切换 Permission；差别只在命令 grammar 与误触风险。

关联：`CFG-17`。

### M05-39 新配置的 `DoubleCheck` 默认值

问题：`DoubleCheck` 已确认是全局默认开关并可由 `.cautious` 做 Context tri-state 覆盖，但“新配置在用户从未选择时是开还是关”尚未确认。它会直接改变每个正常结束和高风险动作的请求数、费用、等待与安全体验。

- A：新配置写 `DoubleCheck=false`；用户可在 config-repl 长期开启，或用 `.cautious on` 只开启当前 Context。（推荐简洁基线）
- B：新配置写 `DoubleCheck=true`；默认承担额外 review 时间/Token，用户可在 config-repl 长期关闭，或用 `.cautious off` 只关闭当前 Context。
- C：没有内置 true/false 默认；`DoubleCheck` 是新 INI 的 required 字段，model/config REPL 建立首份配置时必须明确选择，手工文件缺失就校验失败。

推荐 A。它让基本 AgentLoop 不因未表达的费用偏好自动增加请求，同时保留清楚的安全开关与会话覆盖；B 把 slogan 对应的更高安全设为开箱基线；C 最尊重显式选择，但会让首份配置多一个必答项。三项都不重新引入 `Cautious` profile 或独立终止评估开关，实际有效值仍完整写入 Context snapshot。

关联：`AQ-019`、`AQ-020`、`CFG-12`、`MODEL-12`、D-027。

### M05-07：手工 INI、多行与 unknown 字段

问题：是否正式支持手工编辑，并要求 REPL 保留注释/顺序？

- A：正式支持；quoted string 用明确换行转义；REPL 保留 concrete syntax；unknown 当前字段阻断但原文保留。（推荐）
- B：正式支持三引号 multiline block，其余同 A。
- C：正式支持缩进行 continuation line；续行只属于前一个已知 string 字段，空白与结束规则固定，其余同 A。

推荐 A。parser 最小且跨平台确定，REPL 可以把转义值显示为真正多行。B/C 更适合手写长 Prompt，但都扩大 grammar/golden fixture。unknown/deprecated 与外部冲突由 M05-28 独占。

关联：AQ-131 至 AQ-133、AQ-152、AQ-160、AQ-185、AQ-200、`AQ-287`、`AQ-288`、FMT-02、FMT-04、CFG-10、CFG-19、CFG-22。

### M05-28 unknown/deprecated 字段的读取与迁移

- A：缺失 required、疑似拼错和安全相关 unknown 阻断；已登记 deprecated 给精确迁移；已登记 future namespace 中不影响安全的 optional unknown 原文保留并警告。（推荐）
- B：当前 core section 的所有 unknown 都阻断并原文保留；只有 schema header 明确声明、且当前程序登记可往返的 extension namespace 可以保留。
- C：只要 schema major 受支持，non-security unknown 都原文保留并警告；安全/权限/secret/network/process 相关 unknown 仍阻断，deprecated 仍按迁移表处理。

推荐 A。B 最严格、前向兼容较差；C 最宽松，却需要稳定的字段分类以免把拼错的行为字段当作无害扩展。三项都不能把 unknown 当作生效配置，也不能在 REPL 保存时丢掉被允许保留的原文。

**跨包投影，不是本组第二个选择：** REPL draft、运行中 Agent 或其他 writer 发现 source identity/digest 已变化时怎样 reload/compare/merge/阻断，统一由 F4-01 的 generation/stale-write 契约决定。本组只定义读到某个字段名时它属于 error、deprecated migration 还是 preserved future text。

关联：`AQ-290`、`CFG-08`。

### M05-08：默认顺序、disabled Model 草稿与删除

问题：物理顺序第一项继续是普通 Agent 的默认 Model；这里只决定 disabled Model 草稿要完整到什么程度。“INI 能被管理入口完整解析”和“普通 Agent 可启动”是两个独立结果；M05-30 B 可以产生只能管理、尚无可用 Model 的 schema-valid generation。资源 selector 是否存在 Abbreviation 及其 requiredness 只由 M05-57 决定；下文“与 enabled 一样完整”必须应用 M05-57 已选政策，不能在本组暗中增加简称。

- A：disabled Model 只需 section 名、Protocol 与 `Enabled=false` 合法；M05-57 允许的 Abbreviation、Endpoint、remote model、Key 可暂缺，启用前必须全量验证。若可选字段已出现，它仍必须通过类型、唯一性、秘密和跨字段校验，不能用 disabled 吞掉错值。（推荐）
- B：disabled Model 必须填写 enabled Model 所需的全部 connection/capability/limit 字段，只允许实际 auth 所需 Key 暂缺；selector 字段独立服从 M05-57：A 下不存在、B 下始终可选、C 下 disabled 草稿可暂缺但启用前必须补齐。Key 可在启用事务中最后输入。
- C：disabled Model 也必须填写全部 connection/capability/limit 字段和实际 auth 必需的 Key，只跳过联网测试；selector 字段仍严格服从 M05-57，而不是由本项单独变成 required。

推荐 A。它允许分步准备连接；B/C 提前发现更多错误但不是真正草稿。M05-30 B 下“没有 enabled Model”或“第一项 disabled”可以是可持久的管理态，但普通 Agent 必须返回明确的 eligibility error；只要第一项 disabled/无效，就不静默跳到下一项 enabled Model。启用事务必须同时补齐所选路线的全部 required 字段并重新验证整个 section。删除引用中的 Model 由 M05-34 独占。

关联：AQ-080、AQ-134 至 AQ-137、AQ-152、AQ-236、`AQ-286`、CFG-05、CFG-06、CFG-09。

### M05-57 Model/Permission 资源 selector 是否提供 Abbreviation

通俗场景：如果同时存在 `[Model.DeepSeek]`、`[Model.DS]` 和 `Abbreviation=ds`，或者 Linux 上写 `DS`、Windows 上写 `ds`，CLI/REPL 不能按配置顺序猜用户指谁。另一方面，yaca 的 Model/Permission 数量通常很少，强迫每个资源再起一个简称也会增加无意义字段。本组只决定 Model 与 Permission 资源的 selector policy；顶层命令和 chat dot-command 的简称仍由 TU-10/TU-32 独占，ExecProfile 继续只有完整 logical name。

- A：删除 Model/Permission 的 `Abbreviation` 字段；完整 logical name 是唯一持久资源 selector。（推荐最简）
- B：允许可选 `Abbreviation`；没有简称的资源始终可用完整 logical name，REPL 可以建议但不得自动保存或从名称暗中生成。
- C：每个可用资源都必须有显式 `Abbreviation`：所有 Permission 和 enabled Model 保存前必须填写；disabled Model 草稿可以暂缺，但 enable transaction 必须先补齐。完整 logical name 仍然始终可输入，不建立“只能用简称”的第二类资源。

推荐 A。Model/Permission 是低数量、可浏览的命名资源，完整名称已经足够清楚，也避免让 `model-repl`、`config-repl`、XML mapping 和迁移维护第二套 token；B 给频繁切换者便利且不强加负担；C 输入最短，却让每次新增资源都多一个必填身份，并扩大重命名与冲突修复面。三项都不改变物理第一项是默认资源，也不把 section 名、RemoteModel 或 Description 混成同一个身份。

三项共享一套跨平台确定规则：resource selector 是 typed string token，显示时保留配置中的原始 UTF-8 拼写；匹配时只把 ASCII `A-Z` fold 为 `a-z`，其他合法 UTF-8 bytes 精确比较，不跟随文件系统、locale、Unicode normalization 或 Unicode case mapping。Model/Permission logical name 属于 D-029 允许的 Unicode user data，而不是 English/ASCII UI chrome：只接受 well-formed UTF-8 Unicode scalar sequence，不能为空、不能含 NUL/CR/LF、ASCII control、INI section delimiters `[`/`]` 或首尾 ASCII whitespace；内部空格、点、连字符、下划线与其他有效非控制 Unicode scalar 可保留。最大 UTF-8 bytes、parser round-trip vectors 和旧配置迁移门由 TP-019 在两个目标平台冻结，所有平台使用同一 grammar，不能按当前代码页或文件系统改写。Abbreviation 本身只接受 schema/TP-019 冻结的短 ASCII token。每个 Model namespace 和 Permission namespace 分开判定，跨类型同名合法，因为调用 action 已经给出资源类型。A 要求同类型 logical name 折叠后唯一；B/C 还要求同类型内所有 logical name 与 Abbreviation 共用一个折叠 namespace，简称不得与自己的完整名折叠相同，任何冲突都使整代配置无效，绝不按物理顺序选第一项。用户输入简称后，Runtime 在动作 admission 时立即解析并冻结完整 logical name；Context XML 的当前引用只保存完整 logical name，非秘密历史 snapshot 可以记录当时简称用于解释，但简称变化不改写旧事件、不成为永久 ID。

M05-34 仍独占 Model 被 Context 引用时的 rename/delete，Permission 的同类管理事务服从 M05-48/F4-09；本组只决定 selector token 集合。外部编辑导致 selector 冲突时，普通 Agent 不能启动，bootstrap REPL 必须列出全部冲突来源并要求显式改名；不得临时关闭某个资源、自动加数字、把大小写差异当两个对象或跨 Model/Permission namespace 猜测。

关联：`AQ-135`、`AQ-136`、`AQ-199`、`AQ-432`、`CFG-05`、`CFG-06`、`CFG-12`、`CFG-27`、M05-08、M05-34、M05-48、F4-09、TU-10、TU-32、TP-019。

### M05-34 删除或重命名仍被 Context 引用的 Model

- A：允许完成管理事务，但先列出受影响 Context；历史 snapshot 不改写，后续恢复进入只读 mapping，绝不静默改名或 fallback。（推荐）
- B：只要任何 Context 当前引用就拒绝删除/重命名；用户必须先逐 Context 显式 remap。
- C：允许同一 `ManagementMutation` 中为选中的 Context 建立显式 old-name -> new-name mapping；未选中的仍进入只读恢复，历史 snapshot 不改写。

推荐 A。它不让旧 Context 永远阻止清理配置，也保留每个依赖缺口的真实状态；C 更省操作，但跨多个 XML 只能是 durable/recoverable transaction 与逐目标 outcome，不能宣传普通文件系统原子提交。

关联：`AQ-080`、`AQ-236`、`AQ-347`、`ARCH-05`、`CTX-27`。

### M05-09：model-repl 与 config-repl 的责任分工

问题：两个 REPL 怎样避免重复功能？

- A：model-repl 专门编辑/测试/reorder Model；config-repl 管其余配置并只显示 Model 摘要/跳转。（推荐）
- B：config-repl 可以完整编辑所有字段，model-repl 只是别名入口。
- C：config-repl 可编辑 Model 的 non-secret 普通字段；Key、连接测试、复制和重排跳到 model-repl；两者仍投影同一 draft/validation service。

推荐 A。Key 输入、测试、顺序和 Model 能力集中；B 最统一但让 model-repl 名义变弱，C 减少跳转但增加两套页面。三项都必须走同一个 draft/validate/redacted-diff/atomic-replace 服务，不能各自定义字段语义。

产品已建立 `model-repl` 与 `config-repl` semantic actions；`--model-repl` / `--config-repl` 只是 TU-18 A 的条件拼写，B/C 由同一 registry 生成各自入口。项目负责人原话中的 `--interactive-config-changer` 是否保留兼容别名留给 CLI 包。

这里同时冻结编辑正确性不变量：无论从哪个 REPL 编辑既有 Model，都从当前 generation 复制内存草稿，整体静态/跨字段校验，显示脱敏 diff，复核 source identity/digest 未 stale 后一次原子替换；取消不改变活动配置。M05-45 只决定新增 Model 的交互节奏，不能降低这条共同事务。

关联：AQ-014、AQ-076、AQ-079、AQ-131、CFG-19、CFG-20、CFG-23、F4-01。

### M05-44 model-repl 列表的字段密度

本组只决定 Model 列表页默认显示什么；secret 永不回显，字段编辑/测试语义仍由各自 owner 决定，40 列换行由 TU-01 投影。

- A：稳定列出 order、logical name、enabled/current/default、Protocol、RemoteModel、Streaming、Tools、最近 self-test 状态；Endpoint 只显示 sanitized origin，Key 只显示 `set|missing`，其余进入 `show <row-id>`。（推荐）
- B：首页只列 order、logical name、enabled/current/default 和最近状态；Protocol/endpoint/model/capability 全部进入 details。
- C：首页逐项显示完整 non-secret Model effective field 与来源，类似展开后的 section；Key 仍只显示 secret state，不打印原始 INI。

推荐 A。选择、排错和重排所需信息一屏可见，又不会让每个高级参数挤满旧终端；B 最简洁，C 最透明但列表很长。三项都使用 view-generation + stable row ID，列宽不足时改为单项多行，不省略状态含义；列表顺序就是默认选择事实，不能按名称重排后误导用户。

`current` 只是当前 Context 的有效 Model，`default` 只由配置顺序第一项派生，不新增隐藏 DefaultModel ID。最近 self-test badge 必须绑定 exact Model config generation、adapter/schema digest 和测试范围；Endpoint/Auth/RemoteModel/Streaming/Tools/retry 等相关字段任一变化后立刻显示 `stale` 或 `untested`，绝不能继续保留绿色 PASS。

关联：`AQ-077`、`CFG-04`、`CFG-14`、`TUI-11`、M05-08、M05-29、TU-01、TP-024。

### M05-45 Add Model 的交互节奏

本组不再让“立即写每个字段”成为合法路线：所有方案都先建立未激活 draft，完成 required/conditional schema、静态与跨字段校验，显示 sanitized preview/diff，复核 generation 后原子发布；Key 输入遮蔽且不能进入 terminal history。区别只在用户怎样填这份草稿。

- A：分步向导：先 logical name/Protocol，再按 adapter schema 只询问 required 字段，最后可进入 Advanced optional fields；每步可 back，完成后统一 validate/preview/save。（推荐）
- B：命令式草稿页面：`show/set/unset/validate/test/save/discard`，字段可按任意顺序填写；save 前集中列出缺失/冲突，不逐步引导。
- C：进入 Add Model 时先选择 `guided|editor`，之后分别严格使用 A/B 的同一 draft service；选择只影响本次交互，不保存成新的 UI mode 配置。

推荐 A。初次配置最容易理解，adapter 条件字段也不会一次倾倒；B 对熟悉 schema 的用户最快，C 同时照顾两类用户但每次多一步。是否可从 existing Model clone 由 M05-47 独立决定，不能借编辑器路线暗中出现。连接测试始终显式且可跳过，跳过只表示 untested，不影响 schema-valid publish；第一份配置的特殊发布 gate仍由 M05-30 独占。

关联：`AQ-078`、`CFG-04`、`CFG-19`、M05-08、M05-09、M05-30、F4-01、TU-22、TP-024。

### M05-47 Add Model 是否提供 clone existing

本组与 M05-45 的 guided/editor 正交；若启用 clone，克隆结果仍进入所选草稿交互并走完整校验/preview/publish。

- A：v0.1 不提供 Model clone；新增总从 blank typed draft 开始。（推荐简洁路线）
- B：提供显式 `clone <source-row-id> <new-logical-name>`，只复制由 typed schema 标为 non-secret、non-observation 的配置字段；任一 registered config-secret value、self-test badge、current/default 和 Context mapping 永不复制。

推荐 A。字段数量可由向导承担，不必为首版新增“哪些元数据可复制”的第二条路径；B 适合多个连接共享 endpoint/adapter 参数。B 必须在 preview 中逐项标 source 与 reset 字段，source/target generation stale 或目标名已存在就拒绝，不能因同 endpoint 自动共享 credential。

关联：`AQ-407`、`CFG-04`、`SAFE-09`、M05-02、M05-20、M05-44、M05-45、F4-01、TP-024。

### M05-29 config-repl 首页与 typed effective field view

- A：首页按 General/AgentLoop/Network/Exec/Permission/Context/Compaction/TUI/Logging/Storage 等 schema group 列 errors、overrides、restart/effective-time 摘要；打开字段后同时显示 schema default、INI、Context override、final effective、source/effective-time 和 secret 状态。（推荐）
- B：首页平铺所有字段且只显示 final value；来源/default/override 需要查看原始 INI/XML，secret 仍只显示状态。
- C：首页按 A 分组，但组内只显示 `final + source` 紧凑行；字段 details 再显示完整 default/INI/XML/effective-time/secret 状态，底层仍是同一 typed field-view。

推荐 A。这不是繁杂页面，而是解释“为什么现在生效这个值”的直接证据。B 表面直接但排错最慢，C 在窄终端更干净。secret 值在任何视图都不回显，Model group 只投影 M05-09 所选摘要/跳转，不复制一套编辑器。

关联：`AQ-082`、`CFG-14`、`CFG-19`、`TUI-11`、M05-09、TU-01、TP-024。

## M05-10 损坏/缺失配置时的 bootstrap 投影（不是负责人投票）

哪些入口仍可用只由 PJ-02 选择；本包不能再用同样的 A/B/C 产生第二答案。配置系统必须为 PJ-02 选中的每个 bootstrap 入口提供一个只依赖内置 typed schema 的受限 reader/service：不启动 Agent、不加载 Context/工具、不联网、不把损坏字段当有效配置，也不自动生成/重置 INI。

若选择允许 config/model REPL，它们只可编辑恢复到合法配置所需的 draft；若选择允许 self-test Stage 1，它只报告静态 parser/schema/资源事实。任何入口在完整 validate + publish 前都不能把候选 generation 激活。页面/exit 结果仍由 PJ/TU/ED 投影，本组只形成配置服务契约。

关联：AQ-012、AQ-013、AQ-201、AQ-217、`AQ-289`、ARCH-01、CFG-09、CFG-21、PJ-02。

### M05-30 第一份配置的事务发布

- A：没有首次页面；用户显式进入 bootstrap `model-repl` action，先在内存/受控草稿中填最低 Model 字段，连接测试可跳过，secret/非 secret 一起通过完整静态校验后原子发布。（推荐）
- B：显式 `model-repl` action 可以发布一份 schema-valid、没有 enabled Model 的正式 INI；其中 disabled Model 草稿按 M05-08 的选择校验。普通 Agent 明确失败，后续事务补齐并启用第一 Model。

推荐 A。这里不重问是否有首次页面：D-031 已确认显式使用 model-repl。B 最适合跨进程分步配置，却要清楚区分“INI 合法”和“Agent 可启动”。两项都允许跳过连接测试且不留下半写 INI。首版不创建额外的长期 `setup-draft.xml`；若以后确实需要第三类草稿生命周期，必须明确重开 D-035 的数据角色与恢复/清除契约，不能从本组暗中加入。

关联：`PROD-13`。

### M05-11：Self-Test Stage 2 的真实检查范围

问题：完整 self-test 的 Stage 2 对 enabled/disabled Model 覆盖到什么程度？进入 Stage 3 的全绿 gate 已由 D-031 固定。

- A：全部 enabled Model 都是 required；逐个检查 auth/protocol 与声明的 stream/control/tool 能力：`Tools=native` 才用 inert synthetic schema 验证 native tool wire，`Tools=off` 验证不发送/不宣称 executable tools，并只在 M05-26 所选路线要求时验证 AL06-02 control carrier；disabled draft 只做静态检查。（推荐）
- B：A 加上所有字段完整的 disabled Model 作为 optional online checks；它们失败不改变 enabled 全绿 gate，但报告明确失败。
- C：全部 enabled Model 做 required 最小连接/协议检查；stream/tool/control 使用独立的显式 deep-check 阶段，deep-check 未跑时结果只能是 partial，不能称完整通过。

推荐 A。它兑现“真实检查各个 LLM 配置”，又不把合法的 `Tools=off` 非 main Model 错判为缺少工具。任何联网前都显示 consent；Stage 2 的每个请求使用 `self-test phase=capability`，工具测试只解析 inert synthetic call，绝不执行或授予 Tool Runtime；Stage 3 使用 `phase=semantic`。用户若显式缩小范围，报告必须标 partial，且不得进入完整 Stage 3。

关联：AQ-013、AQ-081、AQ-085、AQ-139、AQ-198、NET-12、DIAG-01、DIAG-05。

### M05-46 Self-Test Stage 2 联网 consent 的批次边界

Stage 1 永远只做静态/本地检查且不联网；D-031 已固定 Stage 1 后先询问是否进入 Stage 2，Stage 2 required 全绿后再单独询问是否进入 Stage 3。本组不重开这两个边界，只决定 Stage 2 内部在看到 exact endpoint/Model/check/request-attempt/token/time/可能费用与数据类别后，一次 consent 覆盖多大范围。实际检查内容仍由 M05-11/12/31/41 决定。

- A：进入 Stage 2 的确认同时覆盖本次 exact Stage 2 batch；每个 Model/检查仍逐项显示进度，但不重复询问。（推荐）
- B：先确认进入 Stage 2 并查看总 manifest；每个 Model 在首个真实请求前再分别 consent，同一 Model 已列 checks/attempts 形成一批。
- C：先确认进入 Stage 2；每个 logical check 在首次 HTTP attempt 前分别 consent，retry/fallback 只在该 check 已展示的 worst-case 范围内继承。

推荐 A。它用一次清楚的 Stage 2 清单控制所有连接检查；B 适合不同 Model/endpoint 费用差异很大时逐个决定，C 最细但会频繁打断。三项都没有 Enter 默认同意、不会因历史 self-test consent 自动联网，也不允许 retry/fallback 超过 manifest；取消/关闭只收口已开始请求，其余未开始项标 skipped。Stage 3 永远按 D-031/M05-12 另行展示 reviewer/request 并 consent，不能被本组任何选择预授权。

关联：`AQ-085`、`NET-12`、`SAFE-08`、M05-11、M05-12、M05-31、M05-41、TU-07、TP-018、TP-024。

### M05-53 Self-Test 的 rerun 选择范围

页面怎样排版由 TU-26 决定；本组只决定一次 run 结束/部分结束后，用户能用多细的范围重新执行。rerun 永远建立新 run-id，引用旧结果但不把它原地变绿；任何联网范围都重新展示当前 generation 的 manifest，并按 M05-46 fresh consent。

- A：只允许 `rerun stage <1|2|3>`；阶段内所有当前适用 checks 重新执行。（最简单）
- B：允许整阶段或 `rerun failed`，后者只选择旧 run 中 failed/incomplete/stale 且在当前 generation 仍适用的 checks。（推荐）
- C：允许整阶段、failed-only，以及用户从 stable check/Model ID 列表显式选择任意合法子集；结果明确标 partial，除非 required 集合在同一兼容 evidence generation 中全部 green。

推荐 B。常见“只重试失败 Model”无需重复成功费用，又不引入复杂多选；A parser 最小，C 最灵活但 partial/gate 解释最多。三项都不重放已经产生外部副作用（self-test 本身无 Tool Runtime），不复用旧 transport attempt/request ID；配置、adapter/schema、endpoint 或 consent binding 变化使旧 success stale，Stage 3 只能消费当前有效的 Stage 2 green evidence。

关联：`AQ-411`、`DIAG-05`、M05-11、M05-12、M05-31、M05-35、M05-41、M05-46、TU-26、TP-018、TP-024。

### M05-31 Stage 2 部分失败后是否继续检查其余 Model

- A：某项失败仍继续测其余已经同意、尚未开始的 Model，以便形成一份完整结果；只有全部已选 required Model 都通过才能进入 Stage 3。（推荐）
- B：任一 required Model 失败就停止尚未开始的 Stage 2 检查；已测通的 Model 也不能进入 Stage 3。
- C：每个 required Model 失败后询问 `continue remaining / stop`；无论选择什么，只要任一 required Model 未测或失败就不能进入 Stage 3。

推荐 A。它保留完整诊断，又严格服从 D-031 的全绿 gate；B 最省失败后的费用，C 把每次剩余费用交给用户决定。本组只决定失败后的遍历，不决定一次检查内部是否 retry 或 streaming fallback。

关联：`AQ-317`、`AQ-319`。

### M05-41 Self-Test Stage 2 是否复现配置的 retry 与 streaming fallback

问题：在线自检既可以验证“用户实际运行时会经历的完整传输策略”，也可以做“一次请求的纯能力探测”。两者的 request 数、费用和诊断含义不同，不能藏在 consent 文案里。

- A：Stage 2 复现当前 Model 的有效 retry-by-phase 与 M05-25 `Streaming=try` fallback；consent 分别列 logical checks、最坏 HTTP attempts、fallback、token/可能计费和总 deadline，结果逐 attempt 说明。（推荐）
- B：Stage 2 对每个 check 只允许一次 HTTP attempt，禁用 retry；`Streaming=try` 只测试流式并报告 supported/unsupported/error，不做 non-stream fallback。报告标成 single-attempt capability result，不能声称验证了实际 resilience policy。
- C：先运行 B 的单次能力检查；用户再次 consent 后才运行独立 resilience subtest，后者复现 configured retry/fallback。两部分分别计费、分别给结果，只有两部分都完成才称“完整传输策略已验证”。

推荐 A。它最接近正常 Agent 的真实网络行为，而且所有最坏成本在发请求前可见；B 请求数最少，C 证据最清楚但交互和费用最高。无论选择哪项，已经收到 canonical event 后都不重放 logical request，用户取消也绝不 retry。

关联：`AQ-139`、`AQ-197`、`AQ-198`、`AQ-317`、`NET-06`、`NET-12`、M05-04、M05-25。

### M05-12：Self-Test Stage 3 的 reviewer 与结果地位

问题：语义审阅由谁执行、看到什么、是否写回配置？

- A：进入 Stage 3 时列出本次已通过的 Model，用户明确选择一个 reviewer；当前默认 Model 只作为预选项，不能在 Enter/consent 前发请求。结果仅 advisory，绝不自动改配置。（推荐）
- B：配置显式 `SelfTestReviewerModel`；进入 Stage 3 时显示这个选择并再次 consent。它必须在本次 Stage 2 通过，缺失、被禁用或失败就不能进入 Stage 3，不自动换另一个 Model。
- C：进入 Stage 3 时显示全部本次已通过的 required Model 和最坏请求/Token；用户一次 consent 后由它们分别审阅同一脱敏摘要，并列呈现分歧，不投票改变 deterministic pass/fail。

推荐 A。它每次都明确选择真实已验证 reviewer，又不增加持久字段。三项结果都仅 advisory，绝不覆盖 typed schema、自动修配置或改变 Stage 1/2 pass；必须显示 reviewer、Prompt 版本、输入 digest 和不确定性。Stage 3 不发送任何 registered config-secret value、完整 Context 或工作区正文；允许字段由同一 registry 生成最小投影，不能维护手写排除名单。报告持久性由 M05-35 独占。

关联：AQ-013、AQ-085、AQ-202、`AQ-318`、CFG-04、DIAG-05、DIAG-06、SAFE-09。

### M05-35 self-test 报告是否持久化

- A：默认只显示；用户显式 `--output <report.xml>` 才写一份脱敏、版本化 XML 报告，并在写前预览目的地与包含项。（推荐）
- B：每次完整 self-test 都在 `__yaca__` 下保留最新一份 XML 报告，成功替换旧报告；不建立历史目录。
- C：不提供持久报告；机器调用只能消费 stdout 的版本化结果，用户如需保留自行重定向。

三项都不修改 config.ini 或 Context XML 来伪装观测为配置事实，不保存任何 registered config-secret value 或 raw request body；报告 schema 的排除集合由 typed registry 机械生成。

推荐 A。它既能交付可审计证据，又不让普通检查持续制造长期文件。

关联：`AQ-318`、`DIAG-05`、`DIAG-06`、`D-035`。

## 配置完整性审计展开的产品轴

下面各组不是为了增加配置项数量，而是把原来捆绑在一起的 HTTP、资源、shell 环境、Permission、日志、reset、metadata、显示与传输选择拆成唯一 owner。每项选择之后仍要通过真实平台验证；“选择推荐”不能替代 HTTP redirect、ACL、curl、旧终端或原子替换测试。

### M05-13：明文 HTTP Endpoint 与 Key 的组合

问题：当 `Model.*.Endpoint` 使用 `http://` 时，哪些地址和鉴权组合可以真正发出请求？这和“跳过 TLS 证书验证”不是一回事；HTTP 本身会明文传输 Prompt、源码、工具结果和凭据。

- A：HTTPS 正常允许；HTTP 只允许 Runtime 能证明是 loopback、强制绕过代理且 `AuthMode=none` 的本地 endpoint。任何 Key、SecretHeader 或含凭据 Proxy 与 HTTP 的组合都是静态错误。（推荐）
- B：在 A 之外，允许显式开启 private/LAN HTTP；仍强制 `AuthMode=none`、不带任何 secret、绕过含凭据代理，并在保存/切换/self-test/每个新 Context 首次请求时提示明文内容风险。
- C：允许显式开启任意 HTTP host；同样绝不发送 Key/SecretHeader/proxy credential，每次进程首次向该 origin 发送前都显示目标与将发送的数据类别并可取消。

推荐 A。它保留常见本地无鉴权模型；B/C 是明确接受 Prompt/源码明文暴露的兼容路线，但都不能把风险接受扩大为 secret 明文传输。loopback/private/DNS、代理绕行和 redirect downgrade 仍需技术证明；任何方案都不新增 `SkipTlsVerify`。

关联：CCA-Q-01、AQ-137、AQ-146、AQ-219、AQ-220、`NET-13`、M05-01、M05-02。

### M05-14：传输资源上限是否成为用户配置

问题：header、单 SSE event、缓冲、压缩体、解压后正文、错误正文、tool arguments 和 logical response 都必须有硬上限；其中多少应出现在 INI？

- A：所有类别都有版本化 Runtime hard cap；INI 只公开已有清楚用户场景的少数较低上限，首版候选只保留 `MaxHeaderKiB`、`MaxEventKiB`、`MaxBufferedKiB`，其余由 self-test/status 解释但不可调高。（推荐）
- B：把用户可下调的完整传输集合公开为 Advanced typed 字段：`MaxHeaderKiB`、`MaxEventKiB`、`MaxBufferedKiB`、`MaxCompressedBodyKiB`、`MaxDecompressedBodyKiB`、`MaxErrorBodyKiB`、`MaxToolArgumentsKiB`、`MaxLogicalResponseKiB` 与 `MaxDecompressionRatio`；每项仍只能低于 Runtime hard cap，config-repl 必须解释组合内存成本。（完整公开）
- C：所有限制只使用版本化 Runtime hard cap，不在 INI 暴露任何传输大小字段；超限错误显示实际类别和固定上限。

推荐 A。它让 Win32 x86 的内存保护完整，却不要求普通用户理解压缩炸弹 ratio、SSE parser 深度和 error-body cap。选择 A 后仍可在证据证明真实用户需要时，把某一内部 limit 升级为 schema 字段；不能先暴露全部再把“调大”当故障修复。

**不可投票的持久化门：** Context XML 只能覆盖已登记的会话策略和 Runtime hard cap 以下的会话预算；完整历史、operation 先行、commit/repair、writer 一致性和 Runtime hard cap 不可关闭。外来 XML 在未经 CX-14 的本机映射与显式激活流程前，不得放宽 Permission、降低 DoubleCheck 或激活 ContextPrompt；这必须通过 schema parity 与故障注入证明。本组不替 CX-14 决定用户确认后可以激活到什么程度。

关联：CCA-Q-05、AQ-155、AQ-245、AQ-322、`CFG-15`、NET-08、CONC-03、PERF-02、M05-04。

### M05-15：raw shell 的环境配置面

问题：模型调用的 raw shell 是否允许用户在主 INI 中全局重写环境？本项只讨论用户/模型 shell。yaca 内部 curl、Git evidence 和 helper 不受这个选择影响，必须隔离宿主的隐式配置。

- A：raw shell 继承 M05-55 选定的宿主 baseline snapshot；不提供 `EnvironmentSet`、`EnvironmentUnset` 或 `ExposeConfiguredProxy`。需要特殊变量时，模型把它明确写进获批 raw 命令；全局 Proxy credential 不自动传播。（推荐最简）
- B：提供 `EnvironmentMode=inherit|clean` 和 typed set/unset；`inherit` 使用 M05-55 选定的 baseline，`clean` 使用版本化最小环境。每个变量有名称、大小、大小写与保留变量规则。为保持简单且避免误标，所有 `EnvironmentSet` value 一律按 secret 处理：名称可进入脱敏 snapshot，值不进入 XML/public digest/诊断/clone/export；仍不自动暴露 Proxy credential。
- C：raw shell 始终使用固定 clean baseline；不提供持久 set/unset，额外变量只能在获批 raw command 中显式设置，Network proxy/credential 不自动传播；M05-55 在本路线为 `not-applicable`。

推荐 A。B 适合可复现构建但扩大配置/secret 面，C 最可重复却与用户日常 shell 差异最大。所有方案记录非秘密 environment snapshot 摘要，并诚实说明 raw shell 是宽能力、不是 OS sandbox。

**不可投票的唯一合成算法：** M05-15 B 按 `selected baseline -> canonical EnvironmentUnset -> canonical EnvironmentSet -> reserved/size validation -> final private generation` 生成环境，任何阶段失败都不 spawn。字段 collection 中重复名称、set/unset 同名和对 Runtime 保留变量的写入一律整代拒绝，不使用 last-wins；Windows 名称按不区分大小写的 canonical key 比较，Linux 按精确 ASCII name 比较，writer 的排序只影响规范序列化，不改变 OS environment 的 map 语义。M05-55 B 剔除的是当前 generation 已登记为 yaca 管理 secret 的环境项或 exact value match；比较只在进程内完成，不能形成可离线比对的持久 digest，也不声称能识别改名、编码或派生后的秘密。最终 `ExecEnvironmentSnapshot` 的公开部分只含 baseline ID/version、mode、source、canonical 变量名集合和 public digest；值相等性由进程内临时 keyed fingerprint/observation binding 判定，用于让旧 approval stale，绝不进入 XML、日志或 support。

**不可投票的环境隔离门：** raw shell cwd 只服从 TS-37，本组及 M05-55 只提供环境 snapshot。内部 curl/Git/helper 始终使用独立最小环境、随包绝对路径和显式参数，不继承 raw shell override、curlrc/netrc、Git system/global config、credential helper、external diff/textconv、pager/editor。这是防 workspace/HOME 篡改内部请求和证据的运行时不变量，由 HCFG-04/TP-029 证明。

关联：CCA-Q-04、CCA-Q-06、AQ-145、AQ-148、NET-11、`PROC-06`、PROC-13、TS-37、M05-55。

### M05-55：raw shell 的 inherit baseline 到底包含什么

适用条件：M05-15 A/B。M05-15 C 始终使用 clean baseline，本组记为 `not-applicable`。本组只决定 `inherit` 的宿主变量集合政策；是否提供 set/unset、变量值怎样作为 secret 保存仍只归 M05-15。

通俗场景：构建命令通常需要 PATH、系统目录、临时目录和 locale，但宿主环境也可能带着云 token、代理密码、SSH agent socket 或 CI credential。只写“继承受控环境”无法告诉用户获批 Shell 实际拿到了什么，也无法让审批、恢复和 self-test 对同一代环境达成一致。

- A：采用随发行版本化的 compatibility allowlist，只继承运行普通 shell/toolchain 所需的有限类别，例如系统/可执行搜索、临时目录和 locale；不在 allowlist 的变量默认不进入 raw shell。（推荐）
- B：继承启动 yaca 时的完整宿主环境，只剔除 yaca 自己管理的 Key、SecretHeader、配置 proxy credential 与其他 typed secret registry 值；配置页、self-test 和首次 Shell 风险说明必须显著标注“未知宿主秘密可能被继承”。
- C：广泛继承宿主环境，但使用随发行版本化的高置信 denylist 剔除已知 credential、proxy、agent/socket 和同类秘密变量；未知名称仍可能被继承，界面必须明确这种局限。

推荐 A。它用较小、可审计的基线兼顾常见编译/测试与凭据最小暴露；B 兼容性最高但等价于把宿主绝大部分环境交给已获批 raw Shell；C 比 B 收敛，却永远追不上所有自定义 secret 名。三项都在 `exec` admission/spawn 时冻结 exact environment generation，审批/operation 保存 `ExecEnvironmentSnapshot` 的公开部分，私有 value binding 只在进程内用于使未执行审批 stale；**结构化环境快照**绝不写变量值。这个承诺不等于“Shell 输出自动无秘密”：获准命令仍可打印环境、读取当前用户可访问文件、运行凭据工具或发现 Runtime 不认识的秘密，环境过滤不是 OS sandbox。达到 M05-59 所选扫描门的 registered config-secret exact raw bytes 若出现在任一工具结果，必须在进入 TS-16/TS-39 canonical retention/digest 前替换为 typed redaction marker；过短值按 M05-59 A/B/C 分别禁用 consumer、收缩正文保证或接受误匹配。未知用户/ambient secret 可能作为完整 tool/user content 进入 XML，export/support 必须预览并诚实警告，不能承诺自动找全。yaca 内部 curl/Git/helper 继续服从 HCFG-04 的独立最小环境，绝不消费本组 baseline。

关联：`AQ-121`、`AQ-423`、`PROC-06`、`SAFE-09`、M05-15、HCFG-04。

### M05-16：Permission 的 workspace 外能力采用粗粒度还是分动作

问题：首版 direct file tools 访问 workspace 外路径时，是 read/write/delete 共用一个三态，还是分别配置？本项只冻结外部路径字段粒度，不决定敏感路径怎样分类、动作怎样映射字段，也不决定各内置 profile 的默认值。

- A：保留粗粒度 `OutsideWorkspace`；它同时约束 direct read/write/delete，不能分别表达。（推荐最简）
- B：改为 `OutsideRead`、`OutsideWrite`、`OutsideDelete` 三个独立三态字段；不再保留 `OutsideWorkspace`。

推荐 A。它让 Permission 表最短，但用户必须接受外部 direct read/write/delete 共用一个 modifier；如果希望“允许读取仓库外 SDK，但拒绝写入任何仓库外文件”，就应选择 B。无论选哪项，基础 `Read`、`Write`、`Delete`、`Shell` 始终存在；若 TS-11 选择 direct HTTP tool，`DirectNetwork` 作为该工具必需的真实能力列自动存在，不再让 M05-16 以无关选项决定。`SensitiveRead` 是否存在已拆给 M05-56，因此可以与 A/B 任意组合。

关联：CCA-Q-07、AQ-149、AQ-150、AQ-224、SAFE-06、SAFE-09、TOOL-04。

### M05-56：是否提供独立 `SensitiveRead` 能力

通俗场景：`.env`、SSH key、credential 文件和用户额外标出的路径，往往比普通源码更敏感。单独的 `SensitiveRead` 可以让 Std 对源码直接读、对敏感文件再确认；代价是任何分类器都不可能发现所有秘密，错误命中也会增加打断。

- A：不增加 `SensitiveRead`；所有 direct file read 只服从 `Read` 与 M05-16 所选 workspace 外字段，UI 明说 yaca 不对“敏感”作额外安全判断。（推荐最简）
- B：增加独立 `SensitiveRead` 三态字段；它只对 TS-21 所定义的版本化敏感路径分类结果叠加求更严格值，未命中绝不等于文件安全。

推荐 A。它最符合“简单、相信模型、没有 OS sandbox”的产品方向，也避免把不完整的文件名启发式宣传成秘密防护；B 提供更细的审批控制，但必须承担分类来源、误报/漏报、配置预览和跨平台路径 fixture。M05-56 只决定字段是否存在，分类来源与求值顺序仍由 TS-21 独占，内置 profile 的实际默认矩阵仍由 TS-04 独占；它与 M05-16 的粗/细 workspace 外字段可以任意组合，不能再被绑成一个选项。

关联：`AQ-430`、`SAFE-06`、`SAFE-09`、`TOOL-04`、M05-16、TS-04、TS-21、TP-027。

### M05-48 Permission profile 的管理面

M05-16 只决定每个 Permission section 有哪些字段，TS-04 只决定内置模板矩阵；本组决定 config-repl 是否能完成自定义 profile 的生命周期管理。

- A：config-repl 提供 list/show/add/edit/rename/delete/reorder；所有动作走同一 typed draft/validate/diff/stale-check/atomic publish，引用影响在确认前完整列出。（推荐）
- B：config-repl 只能 list/show/edit 已存在 profile；add/rename/delete/reorder 要手工编辑 INI，再显式 reload/重启验证。
- C：config-repl 只管理发行内置模板的可编辑副本；自定义 section 只能手工 INI，页面对它们只读。

推荐 A。Permission 是高频且高风险配置，完整浏览器应该能安全管理，而不是把破坏动作赶到裸文本；B/C 的实现面较小，但用户更容易制造无默认项、重复名或悬空 Context 引用。任何路线都禁止发布“零个合法 Permission”或无效第一项；第一项仍是新 Context 默认，不增加隐藏 DefaultPermission ID。rename/delete 必须列出所有已知 Context 引用，历史 snapshot 不改写；名称/Description 永远不授予能力，实际矩阵才是权威。

关联：`AQ-408`、`CFG-07`、`CFG-19`、`SAFE-02`、M05-09、M05-16、TS-04、F4-01、F4-09、TP-024、TP-027。

### M05-49 活动 Context 执行 Permission-switch semantic action 时怎样确认

本组只决定一个合法目标 profile 已存在时的用户确认门；切换一律从下一 turn 生效，不追溯改变 active turn 或 pending approval。

- A：old/new effective capability matrix 相同或更严格时直接 stage 并回显；任一能力从 deny->confirm/allow 或 confirm->allow，尤其 Shell/Outside/DirectNetwork，必须显示 exact diff 并明确确认。（推荐）
- B：每次切换都显示完整 old/new matrix 并确认，即使只变严格或矩阵相同。
- C：输入 exact profile name 后总是直接 stage，只追加 matrix-diff receipt，不另询问。

推荐 A。收紧权限不制造额外打断，扩权仍由用户看到具体变化；B 知情最强但切换 Readonly 会多一步，C 最快却容易因相似名称扩权。三项都要求目标 profile/generation 合法且未 stale，任何旧 action review/approval/grant 在实际切换生效时失效；transition、old/new snapshot 和来源进入 XML，不能借 profile switch 越过 Runtime hard deny或把历史 Permission 改写成新值。

关联：`AQ-409`、`SAFE-03`、`SAFE-04`、`CTX-07`、M05-16、M05-48、TS-04、TS-05、TU-17、TU-32。

### M05-50 金额价格从哪里来

request/token/time 的硬预算由 AL06-09/42 决定；本组只决定 yaca 是否拥有“金额”事实或估算来源。它不联网抓价，也不根据 Model 名、endpoint 或品牌猜费率。

- A：v0.1 不计算金额；只显示 request、input/output token、active time 和 provider usage 的 reported/estimated 区分。（推荐简洁路线）
- B：只有 provider 响应明确返回 amount + currency + billing scope 时才保存/显示 reported amount；没有就显示 unavailable，不补本地估算。
- C：允许每个 Model 配置版本化 price snapshot：currency、as-of/source label、input/output 单价，以及 adapter 明确支持时的 cache/reasoning 类别；请求按冻结 snapshot 产生 local estimate，provider reported amount 若存在则另列，绝不互相覆盖。

推荐 A。它不会因为经常变化的价格和缓存计费制造虚假精度；B 能显示少数 provider 的真实回报，C 支持本地预算体验但增加完整 schema、迁移和过期提示。B/C 都必须把 amount/currency/source/generation 写入 Context usage event，estimated 与 reported 分栏，不声称等于最终账单；进行中的请求不会因后验金额被逆向取消。只有 C 才让 AL06-43 的金额 warning/admission 策略生效。

关联：`AQ-283`、`MODEL-09`、`CFG-04`、`CTX-07`、AL06-09、AL06-42、AL06-43、TP-018。

### M05-51 全局 Exec 配置表面

M05-15 只决定 raw shell 环境，TS-13 只决定方言，AL06-42 只决定 turn guard；本组决定用户能否调整单次 `exec` 的少量资源默认。任何方案都没有任意 shell/executable path、OS sandbox 或 kill-tree correctness 开关。

- A：单一全局 `[Exec]` 的**资源字段**只公开 `MaxExecTimeMs` 与 `MaxOutputKiB`，均只能在发行 Runtime hard cap 内收紧/调整；仅 TS-23 A 的 typed envelope 可让 tool call 请求更短 deadline，不能突破有效上限，TS-23 B/C 使用已经冻结的有效默认。`MaxOutputKiB` 是 stdout+stderr canonical captured bytes 合计上限；M05-15 B 的条件环境字段可在同一 singleton section 共存。（推荐）
- B：不公开 Exec 资源字段；timeout/output cap 全部来自每个发行 manifest 的版本化只读常量，config-repl/status 只显示。M05-15 B 仍可因全局环境字段建立 `[Exec]`，但不得混入本组资源字段。
- C：允许多个 `[ExecProfile.<LogicalName>]`，每个只含 A 的两个字段；物理顺序第一项是新 Context 默认，config-repl 完整管理 list/show/add/edit/rename/delete/reorder。当前 Context 通过条件 XML 会话项 `CurrentExecProfile` 由用户显式选择，从下一 turn 生效并保存 selector + 非秘密 profile snapshot；仅 TS-23 A 的 typed envelope 可让 Model tool call 在当前 profile 内请求更短限制，TS-23 B/C 使用 profile 的冻结有效值；Model 不能选 profile 或扩大值。用户操作面由 TU-32 的同一 registry 条件生成：TU-32 A 使用 `.exec-profile show|use <exact-name>|reset`，TU-32 B 使用 `.use exec-profile [show|use <exact-name>|reset]`。`show` 显示 current/default/source/generation 和 staged next-turn；`use` 只接受未 stale 的精确名；`reset` 选择并持久写入当前 INI 顺序的第一个合法 profile，不保存“无 selector 便永久动态跟随第一项”的含糊状态。引用缺失/失效时，`show/use/reset` 仍可用于修复，但新 exec 必须阻断；不自动 fallback。M05-15 B 的全局环境字段仍在 singleton `[Exec]`，不复制进 profile。

推荐 A。一个全局小节足以兼顾长测试和旧机内存，保持用户提出的“全局环境/代理、Model 自己重试”边界；B 最简单但无法适配任务，C 灵活却新增 profile 管理、选择、历史 snapshot 和审批差异。三项都从 next tool call 生效，active call 不热改；C 的 profile selector 从 next turn 生效，每次 use/reset 都保存 old/new/source/generation transition，并使全部未执行的旧 exec action review、approval 和 session grant stale。XML 只保存实际 selector/非秘密 snapshot，不定义或覆盖 INI profile。达到 capture cap 后 Runtime 仍持续 drain-and-discard 两条 pipe 以免子进程阻塞，同时记录各通道 observed/captured/discarded bytes、digest 能力和 `truncated=true`；termination grace、decoder、orphan drain、进程树观察和 hard maximum 是 Runtime/manifest 常量，不能配置成无限或关闭。

**C 路线的恢复/跨机激活门：** XML 中的 selector 和历史 snapshot 不因本机恰好有同名 section 就自动等价。打开 Context 时要比较逻辑名、两个 effective resource 值、schema/profile-definition identity 和非秘密 digest。本机原有 Context 只有在当前定义与最后已接受 snapshot 精确一致时才直接激活；同名但 timeout/output 更宽、更窄、缺 snapshot 或 identity 不同都形成 typed `exec-profile-definition` gap，新 exec 阻断，用户用条件 use/reset 显式接受当前本机定义。外来 XML 即使名称/值/digest 全部相同，也只能在 CX-07 的用户确认 import/mapping generation 中激活，不使用历史 approval；CX-18 决定其他 unresolved gap 的全局或 action-specific 继续门。

关联：`AQ-147`、`AQ-236`、`AQ-380`、`PROC-07`、`CFG-04`、M05-15、AL06-42、TS-13、TS-22、TS-24、TU-32、CX-07、CX-18、TP-005。

### M05-52 idle Model-switch semantic action 的兼容与隐私确认

AL06-10 只决定 active turn 中何时生效，AL06-29 只处理恢复时旧 Model 缺失；本组决定 durable idle 时选择另一合法 Model 的确认门。

- A：normalized endpoint origin/path、credential-policy identity、AuthMode、tenant-routing/public-secret-header policy、proxy route 与数据边界都相同，且 window/tool/control/role 预检兼容时直接 stage 并回显；任一身份变化、跨 endpoint、将更多历史发送给新目的地、费用/usage 来源变化或能力降级时显示 exact preview 并确认。（推荐）
- B：每次切换都显示 endpoint、Protocol/RemoteModel、上下文窗口、tool/control、将发送历史范围和金额/usage差异，并明确确认。
- C：输入 exact Model logical name 后直接 stage；仍做 compatibility hard check并追加完整 transition receipt，但不另询问隐私/费用变化。

推荐 A。常见同服务切换顺滑，真正改变外发边界时醒目；B 最可控但频繁，C 最快却可能把完整 Context 发往新 endpoint。三项都不 fallback、不显示或复制任一 registered config-secret value，只显示 credential slot/policy 的非秘密 identity；目标不兼容就拒绝而不是缩水 tools/history。M05-50 A 时费用只能显示 usage/amount unavailable，不能伪造金额差。transition 与 old/new non-secret snapshot 进入 XML，从下一 turn 生效，不改变 active turn 或 pending approval，旧 action snapshot 全部 stale。

关联：`AQ-235`、`MODEL-07`、`MODEL-10`、`SAFE-08`、`CTX-07`、AL06-10、AL06-29、M05-20、M05-50、TU-32。

### M05-17：`LogLevel` 是否保留以及写到哪里

问题：项目长期文件只有 INI/XML，没有独立 `.log`。那么 `LogLevel` 是控制终端与 XML 中可选诊断，还是一个没有真实目的地的空字段？

- A：保留五级 `error|warn|info|debug|trace`；缺失/新配置写 `info`。它只影响以后显示的终端诊断和 Context XML 中标成 diagnostic 的可选事件。canonical 用户/模型消息、tool/approval/operation/recovery 事实永远完整，不受级别影响。（推荐，前提是需要排障细节）
- B：v0.1 删除 `LogLevel`，使用固定简洁诊断；用户通过 self-test 的本地 details 动作或全局 details 语义动作显式请求更详细的当前视图。chat 中后者的实际拼写只投影 TU-32：A 为 `.details <target>`，B 为 `.show <target>`。
- C：只保留精简 `normal|trace` 两级；缺失/新配置写 `normal`。normal 只有必要 warning/error，trace 增加有界技术 cause/timing，仍不保存 secret/raw body。

推荐 A。B 最简，C 更容易理解。三项都服从 D-035/D-036：canonical 用户/模型/tool/approval/operation/recovery 事实不受显示/诊断级别影响，不建立独立长期 `.log`，数据分类和资源上限先于日志级别。

关联：CCA-Q-08、AQ-158、DIAG-03、CTX-01、M05-12、TU-32。

### M05-18：`config reset` 只重置哪些配置字段

问题：配置损坏或用户想重来时，`config reset` 的精确目标是什么？本组不拥有 registered config-secret backup/export，也不拥有 Context purge。

- A：只把 General/Agent/Context singleton 与 Exec 的非环境资源字段中有 schema default 的 non-secret 字段恢复默认；`EnvironmentMode/EnvironmentSet/EnvironmentUnset` 作为一个安全组合全部保持原样，整个 Network、Model、registered config secrets、Permission 和所有 Context 也原样保留。保存前显示脱敏 plan 与引用/启动影响。（推荐）
- B：提供 typed `config reset <section|field>`；只能重置目标 schema 明确拥有 default/missing 语义的 non-secret 字段，任何会让完整 INI 无效的结果都拒绝发布。Model Key 永不由 reset 清除。
- C：不提供 bulk reset；config-repl 只允许对单个 non-secret 字段执行 `reset-to-schema-default`，用户逐项保存一个事务。Model/Key/Permission/Context 都没有隐式 reset。

推荐 A。它提供一个真正有用而范围闭合的“恢复普通默认”，不会把修配置和销毁秘密/历史揉在一起。B/C 若逐项触碰 Exec environment family，事务预览必须把 baseline、mode、公开名称集合和暴露面变化作为一个整体显示并要求专门确认；不能把 `clean` 重置为 `inherit`、清掉 unset 却静默保留 secret set。三项都不递归删除 `__yaca__`、不清除或导出任何 registered config secret、不删除 Context；secret-bearing backup/export 由 M05-42 独占，Context 删除/清除由 CX/F4 的管理事务独占。

关联：CCA-Q-09、AQ-132、AQ-178、CFG-10、`CFG-15`、ARCH-05、F4-09。

### M05-42 是否提供含配置秘密的 backup/export

问题：原子替换所需的短期 temp/recovery 不是用户备份。产品是否另外提供会复制任一 registered `source=config-file` secret（当前包括 Key、显式 proxy credential、SecretHeader、EnvironmentSet value 和 adapter 登记秘密）的长期 backup/export？eligible set 必须由 typed registry 生成，不能手写一份会漏掉未来字段的名单。

- A：不提供内置 secret-bearing backup/export；只提供显式、脱敏的 non-secret 配置导出。RF-03 的升级/迁移只投影 non-secret 配置与其他获准数据，目标实例必须重新输入全部需要的 config-file secret；原源文件可按 RF-03 保持不动，但 yaca 不为迁移制造第二份秘密。（推荐最简）
- B：提供显式 `config export --include-secrets <path.ini>`，RF-03 也只能在用户对本次迁移明确选择 include-secrets 后复制这些值；逐项预览 secret 类别和目标，要求再次确认，以 no-replace、最小可证明权限写一份完整 INI；不自动留存、轮换或删除，结果明确提醒用户自行保管/清除。
- C：每次 schema migration、高风险 config mutation 或 RF-03 管理的迁移发布前自动保留一份含 secrets 的上一代 INI，在 `__yaca__` 中只轮换一份；UI 永久显示其存在并提供显式清除，导出/打包默认排除。

推荐 A。它最符合“配置秘密已经明文在主 INI，但不要继续扩大副本”的简单边界。B 为人工迁机提供完整出口，C 恢复能力最强但建立新的长期秘密生命周期。M05-42 独占所有 config migration 的 secret-copy policy；RF-03 只决定版本/data-root 的迁移拓扑并消费这里的 A/B/C，不得自行新增 secret 副本。选择 B/C 都必须用 registry 自动枚举副本里的 secret class/source，并纳入 canary、文件权限、磁盘满、崩溃残留、support/export 排除和清除测试；不得把 Context purge 顺带放进同一动作。

关联：`AQ-132`、`AQ-178`、`CFG-10`、`SAFE-09`、`D-035`、F4-09。

### M05-19：optional 值的唯一语法

问题：配置中的“自动计算”“未知”“使用 provider 默认”“继承 INI”和“真正关闭”是否使用互不混淆的拼写？旧模板曾让 `false` 同时表示无限、未设置和关闭。

- A：每种 optional 类型只接受 schema 声明的 ASCII sentinel，例如 `auto`、`unknown`、`provider-default`、`inherit`；数字字段不接受 bool `false`，缺失与显式 sentinel 的迁移语义逐字段定义。（推荐）
- B：只保留 `auto` 与 `inherit` 两个通用 sentinel；每个字段 schema 明确 `auto` 的单一计算规则，无法表达的 unknown/provider-default 必须用独立 typed 字段。
- C：不使用 sentinel；optional 只靠字段缺失，schema 为每个字段定义唯一 missing result，REPL reset 就是删除该 key。

推荐 A。它多几个明确单词，却能区分不同状态；B/C grammar 更小，但会增加辅助字段或让“reset=missing”成为正式契约。任何方案都不接受一个 `false` 被不同消费者解释成关闭、未知、无限或 provider default。

**不可投票的 schema parity 门：** typed schema 逐字段声明 required、missing result、schema default、合法 sentinel、inherit 与 effective type；parser、REPL、XML、migration 和 self-test 共用同一状态。这是配置检查、恢复和跨机接盘得到相同结果的前提，由 HCFG-05 与 schema parity fixture 验证。

关联：CCA-Q-10、AQ-142、AQ-185、AQ-200、`AQ-291`、CFG-07、FMT-04、M05-07。

### M05-20：conditional metadata 在 XML、reviewer 与支持输出中的可见性

问题：M05-32 决定 XML 内 Endpoint 投影；本组只决定这个 non-secret Model snapshot 向 reviewer/support/export 再最小化到什么程度。

- A：XML 使用 M05-32 投影；Stage 3 reviewer/support/export 默认只获得 protocol、remote model ID、origin class 与 public digest，用户预览后可显式增加 non-secret host/path。（推荐）
- B：Stage 3 reviewer 默认获得 XML 中完整 non-secret Endpoint 投影，以便判断名字/模型/服务是否明显不符；support/export 仍最小化并预览。
- C：reviewer/support/export 都只获得 Model 名、Protocol、remote model ID 与 digest；exact non-secret host/path 只能由用户另行显式附加。

推荐 A。它平衡语义审阅与网络结构隐私。三项都不发送任何 registered config-secret value 或 URL userinfo/query/fragment；用户正文可能含未知秘密，仍需独立预览。

关联：CCA-Q-12、AQ-040、AQ-168、AQ-202、AQ-358、SAFE-09、M05-06、M05-12。

### M05-32 Context XML 中的 Endpoint 投影精度

- A：保存 scheme + host + explicit/effective port + adapter 继续工作必需的规范 path；移除 userinfo、query、fragment 和所有 secret 值。内网 hostname 会进 XML 以解释历史，但 reviewer/support/export 默认只发最小投影并先预览。（推荐）
- B：保存 scheme + host + explicit/effective port；path 只保存 adapter/path kind 与 digest，目标机必须显式重新映射部署前缀。
- C：只保存 origin class、Protocol、remote model ID、adapter identity 与 Endpoint digest；不保存 exact host/path，导入报告明确列为 portability gap。

推荐 A。它最接近“复制 XML 能解释原环境”；B/C 更少暴露内部拓扑，但接收机需要更多 mapping。三项都完整记录投影级别和已知 gap，绝不把 query/fragment/userinfo 或任何 secret 写进 XML。

关联：CCA-Q-12、AQ-040、AQ-168、AQ-202、AQ-358、SAFE-09。

### M05-43 Model/Permission Description 的 Context XML 投影

问题：Model 与 Permission 的 `Description` 只用于 UI 和 Stage 3 advisory，不决定连接能力或安全 policy；但它仍是可能含敏感信息的用户文本。Context XML 为解释历史环境应保存全文、只保存 metadata+digest，还是明确省略？

- A：保存 schema 有界的完整 UTF-8 `Description` 文本，并标记为 `user-content/advisory`；它进入对应 Model/Permission snapshot 与 snapshot digest，copy/export 明确提示 XML 可能包含用户敏感文字。（推荐）
- B：不保存正文，只保存 configured/present 状态、规范 UTF-8 byte length 与内容 digest；目标机能识别同一/不同描述，但无法从 XML 恢复原文。
- C：正文、长度和内容 digest 都不保存；snapshot 明确记录 `description-projection=omitted`，第三方 reader 不得把省略误报为配置中原本为空。

推荐 A。Context XML 已承担可移交的历史环境说明，保留有界原文最能解释当时 UI/advisory 意图；B/C 减少附带披露，但会降低第三方接盘时的可解释性。三项都禁止根据 Description 推断 provider、Model capability、Permission、DoubleCheck 或任何授权，也不声称能自动发现其中所有秘密；reviewer/support/export 的二次最小化仍由 M05-20 独占，Endpoint 投影仍只由 M05-32 独占。

关联：CCA-Q-12、`CFG-25`、AQ-168、AQ-202、AQ-358、`AQ-378`、SAFE-09、M05-20、M05-32、CX-16。

### M05-21：Model/Permission 是否配置自定义颜色

问题：`Color` 是否成为 Model/Permission 的持久字段？本组只决定字段存在性，不决定 warning/error/tool/diff 等语义角色用什么颜色。

- A：Model 与 Permission 都没有 `Color` 字段。（推荐最简）
- B：Model 与 Permission 都允许一个 fixed basic 8/16-color enum；缺失时由 renderer 确定性分配，字段只影响标签显示。
- C：只有 Model 允许 `Color`，Permission 没有；用颜色辅助区分多个连接，但不把权限高低映射成用户可配色。

推荐 A。若多个自定义 Model 仅靠文字难区分可以选 C，同时确实需要给 Permission 自定义标签色才选 B。三项都服从 D-029：没有 theme/vivid/真彩自定义，颜色不能决定 Permission、Model capability 或错误严重度。实际语义色、无色 fallback、对比度与状态优先级只由 TU-02 决定，本组不能借字段存在性改写它。

关联：CCA-Q-14、AQ-191、TUI-10、TUI-14。

### M05-22：是否提供 generic CLI 一次性 override

问题：CLI 是否有 `--set Section.Key=value` 之类的第三套任意配置层？当前 Model 切换、Permission 切换、DoubleCheck 覆盖和 ContextPrompt 编辑等注册过的 semantic action 已经可以表达会话选择；chat root 只由 TU-32 投影。

- A：不提供 generic `--set`；CLI/TUI 只提供注册过的命名 session action，长期值通过 model/config REPL 事务保存。每个动作有独立类型、help、生效点和 XML 规则。（推荐）
- B：只对白名单字段提供 typed `--set` 本次覆盖；启动前显示来源，secret/endpoint/Permission 定义仍禁止，是否写 XML 逐动作声明。
- C：不提供 generic `--set`，但允许注册过的启动参数（例如 `--model`、`--permission`、`--double-check`）作为本次明确 override；每项单独定义是否写入新 Context。

推荐 A。B 适合脚本但增加一个来源层，C 只把少数高频选择放在启动 grammar。三项都禁止 secret、Endpoint、Permission 定义、unknown 字段和 Runtime hard cap 通过 generic argv 覆盖。

关联：CCA-Q-15、AQ-159、AQ-200、CFG-01、CFG-12、CLI-01、M05-06、M05-09。

### M05-23 自定义 request header/body 的扩展面

问题：非标准 endpoint 需要额外 header 或 body 参数时，Model section 允许到什么程度？Proxy、CA 和 redirect 分别由 M05-36/37/38 独占。

- A：只允许 Protocol adapter 注册的 typed extension fields；adapter 生成 header/body，Model 不能写自由名称。（推荐最稳）
- B：在 A 上允许有界 `PublicHeader` 与 `SecretHeader` 列表；名称/值类型、重复、大小和目的地受 registry 管理，不能覆盖 auth/content/tool/runtime 保留字段。
- C：只允许有界 `PublicHeader`，不提供自定义 SecretHeader；body 仍只能由 adapter typed fields 生成。

推荐 A。B 对私有网关最灵活但扩大 secret 生命周期；C 支持普通路由 header 而不新增第二类 secret。所有方案都有 header/body/response hard cap，不能覆盖 canonical messages/tools/control，也不能绕过 AuthMode。

关联：`MODEL-11`、`AQ-219`、`AQ-348`、`SAFE-09`。

### M05-36 全局 ProxyMode 的来源

- A：`off|environment|explicit`；字段缺失和新配置都写/解释为 `off`。environment 只有用户明确选择后才在 generation 创建时读取、校验并冻结为显式 snapshot，内部 curl 不再自行读取 ambient proxy。（推荐）
- B：只允许 `off|explicit`；字段缺失和新配置为 `off`，完全忽略宿主 proxy 环境。
- C：只允许 `off|environment`；字段缺失和新配置为 `off`，不在 INI 保存 proxy URL/credential；明确选择 environment 后每次 generation 都显示实际 non-secret origin 投影。

三项都保持 proxy 全局、凭据进入带 source 的 typed secret registry、raw shell 不自动继承 configured proxy。`explicit` URL 中的凭据是 `source=config-file`，服从 M05-54；`environment` 路线冻结的凭据是 `source=ambient-environment`，服从环境 observation/请求生命周期而不服从 config.ini ACL，不能把两个来源合成一个权限结论。

推荐 A。它兼顾企业环境与可重复配置；B 最可预测，C 最少持久秘密。

关联：`AQ-145`、`NET-05`、`PROC-13`、`HCFG-04`。

### M05-37 CA trust source

- A：全局 `bundled|system|custom|combined`；字段缺失和新配置为 `bundled`，model/config REPL 显示有效来源；没有 insecure/skip-verify。（推荐）
- B：只支持 `bundled|custom`；字段缺失和新配置为 `bundled`，避免系统 trust store 在机器间漂移。
- C：只支持 `system|custom`；字段缺失和新配置为 `system`，不随包维护 CA bundle；目标机缺少所需 trust 时明确失败。

推荐 A，覆盖旧系统、企业 CA 与可移植包；B 更可重复，C 减少随包维护但旧 Windows/Linux 兼容风险最高。具体 XP/system-store/curl API 由 TP 证明，证明失败时不能假装某来源可用。

关联：`AQ-146`、`NET-02`、`NET-06`、`TP-007`。

### M05-38 HTTP redirect policy

- A：允许有界 same-origin redirect；跨 origin 和 HTTPS->HTTP downgrade 拒绝，credential 永不跨 origin。（推荐）
- B：所有 redirect 都拒绝，用户必须把 Endpoint 改成最终 URL。
- C：same-origin 自动；跨 origin 只在新 origin 无 credential、显示 old/new 与数据类别并由用户明确同意后重发，HTTPS->HTTP 仍按 M05-13 且不带 secret。

推荐 A。B 最确定但兼容较差；C 支持网关迁移却增加交互和新的 logical request 证据。无论选择哪项，redirect 次数、响应大小与循环检测都是不可关闭 hard cap。

关联：`AQ-220`、`NET-04`、`NET-10`。

## M05-24 配置 catalog 完整性门（不是负责人投票）

“配置完整”不能由项目负责人选择 A 变成事实。进入实施计划前，最终 typed schema 必须机械证明：每个真实可调行为恰有 owner/consumer/type/default/missing/secret/source/effective-time/snapshot；每个字段被 parser、REPL、XML whitelist、redaction、migration、self-test 和文档一致消费；Mode/Vivid/Language/Update/UseStunnel 等无消费者或已被 D-029/D-038 排除的旧字段必须删除或有明确迁移错误；不得追加笼统 `Advanced` 自由区。精确默认仍由 schema、旧机证据与资源预算冻结。

关联：`CFG-13`。

验收 artifact：`05-configuration.md` 中的最终 section/field catalog、删除字段清单、字段 owner/consumer/source/effective-time/snapshot 矩阵和 schema parity gate。任一 orphan field、双 owner、secret 漏标或 consumer 缺口都使 readiness 失败，不能由“接受推荐”豁免。

## 不交给配置开关的五条技术硬不变量

这五条不增加负责人题目，也不表示当前已经实测通过。它们是任何选项都必须满足的实现/测试责任：

| ID | 硬不变量 | 验证重点 |
| --- | --- | --- |
| `HCFG-01` | 一个 active turn 只消费一个 immutable effective configuration generation；外部编辑、REPL 保存和 reload 都不能在 turn 中途替换任何 registered config secret、Endpoint、Permission、Prompt、ExecEnvironmentSnapshot 或预算 | active request/tool 中改配置、环境或 ACL，删除当前 Model、损坏文件、cancel/reload race |
| `HCFG-02` | private source digest 与 public effective digest 分离；前者对原始 INI bytes 做冲突检测且不得离开进程，后者只 hash 可进入历史的非秘密规范投影；secret registry 每项带 source，目的地规则由 registry 生成；普通正文 exact scan 的短值边界只服从 M05-59 | 每类 registered config secret canary 搜索 XML、support、错误、日志、工具输出与 backup/export，并覆盖门槛前后值 |
| `HCFG-03` | header/event/compressed/decompressed/error/tool-argument/aggregate response、队列、循环和内存均有不可关闭的 Runtime hard cap；用户值只能更严格 | Win32 x86 组合压力、压缩炸弹、无限 SSE、多个“小上限”叠加 |
| `HCFG-04` | Runtime 内部 curl/Git/helper 使用随包绝对路径和完整显式参数，禁默认 curlrc/netrc、system/global Git config、pager/editor/external diff/textconv/credential helper 与隐式 CA/proxy；repository semantics 只读 allowlist 另行证明 | 恶意 cwd/PATH/HOME/config/env、最终随包版本和目标平台 canary |
| `HCFG-05` | parser、REPL、show-config、XML whitelist、遵循 M05-59 的 tool-output exact-value redaction、migration 和 self-test 都从同一 typed schema/secret registry 生成或机械校验；安全/core unknown 必须 fail-closed，已登记 future namespace 的非安全 unknown 按 M05-28 选择保留策略；任何消费者都不能自造字段语义 | schema parity、golden round-trip、门槛前后及跨 chunk/重复/重叠 secret canary、kill/disk-full/concurrent writer、含任一 config secret 的备份权限 |

## `CCA-Q-01` 至 `CCA-Q-15` 完整归档表

这里的“技术硬不变量”表示负责人不能用配置关闭，但仍需要实现规格、fault fixture 和目标平台证据；它不是“已经验证通过”。

| 审计问题 | 唯一负责人入口或技术归属 | 为什么不再另问 |
| --- | --- | --- |
| CCA-Q-01 明文 HTTP | M05-13 | 明文 origin 与 secret 组合由这一组独占 |
| CCA-Q-02 per-Model rate/cooldown | F4-02 | F4-02 已完整询问 `MaxConcurrentRequests`、间隔、共享 scheduler 和本地总账 |
| CCA-Q-03 运行中外部 INI | F4-01 | F4-01 已完整询问显式 reload、turn-boundary 检测与热更新 |
| CCA-Q-04 宿主工具配置 | 技术硬不变量 `HCFG-04`；raw shell 可配置面见 M05-15；全局代理见 M05-36 | internal curl/Git/helper 必须把所选来源冻结成显式参数；不能暗读 ambient rc/helper |
| CCA-Q-05 传输上限公开范围 | M05-14 | hard cap 必须存在，负责人只决定多少字段进入 INI |
| CCA-Q-06 Exec 环境配置面 | M05-15 + M05-55 | 前者只决定 set/unset 配置面，后者独占 inherit baseline；两者都不改变 internal tool 隔离 |
| CCA-Q-07 Permission 精简字段 | M05-16 | 字段面在完整配置包冻结；动作到能力的映射仍由工具/安全规格承担 |
| CCA-Q-08 LogLevel | M05-17 | 明确长期只有 INI/XML 时的真实目的地 |
| CCA-Q-09 reset | M05-18 + F4-09 的事务 | M05 决定范围；F4-09 决定共同 ManagementMutation 正确性协议 |
| CCA-Q-10 optional 语法 | M05-19 | 原 M05-07 只比较 multiline，不能表达 optional scalar 语义 |
| CCA-Q-11 XML budget override | M05-06 | 现有 A/B/C 已准确表达最小四项、只下调的预算覆盖与 C 的四项精确 session preference；不存在任意 key 路线 |
| CCA-Q-12 conditional metadata | M05-20 + M05-32 | M05-32 独占 XML Endpoint 投影，M05-20 独占 reviewer/support/export 最小化 |
| CCA-Q-13 generation options | M05-05 + M05-23 | M05-05 独占生成参数，M05-23 独占 custom header/body |
| CCA-Q-14 自定义颜色 | M05-21 | 不让纯显示字段混入 Permission/Model 领域语义 |
| CCA-Q-15 generic CLI override | M05-22 | 明确命名 action 与第三配置层的边界 |

## 推荐的整包组合

若希望一次确认推荐基线，可以回复：

`M05-26 A` 是条件回答：本模板同时推荐 `M05-03 A`，因此该组在这套基线中有效；若把 M05-03 改为 B，则 M05-26 自动记为 `not-applicable`，模板中的 A 只保留为预先回答，不生成无工具 main 分支。

~~~text
M05-01 A
M05-33 A
M05-02 A
M05-54 A
M05-59 A
M05-03 A
M05-25 A
M05-40 A
M05-26 A
M05-04 A
M05-58 A
M05-05 A
M05-06 A
M05-27 A
M05-39 A
M05-07 A
M05-28 A
M05-08 A
M05-57 A
M05-34 A
M05-09 A
M05-44 A
M05-45 A
M05-47 A
M05-29 A
M05-30 A
M05-11 A
M05-46 A
M05-53 B
M05-31 A
M05-41 A
M05-12 A
M05-35 A
M05-13 A
M05-14 A
M05-15 A
M05-55 A
M05-51 A
M05-16 A
M05-56 A
M05-48 A
M05-49 A
M05-50 A
M05-52 A
M05-17 A
M05-18 A
M05-42 A
M05-19 A
M05-20 A
M05-32 A
M05-43 A
M05-21 A
M05-22 A
M05-23 A
M05-36 A
M05-37 A
M05-38 A
~~~

也可以只回复差异，例如：

~~~text
本包其余接受推荐；
M05-01 改 B，v0.1 同时完整支持 Anthropic native；
M05-06 改 B，Context 允许下调 turn budgets；
M05-35 改 C，不提供持久 self-test report。
~~~

`F4-01`（运行中 reload）和 `F4-02`（per-Model scheduler）仍在 11 号包回复，不在本包复制选项。没有明确回复的条目继续保持待决。回复“整体看起来可以”不自动把字段名、默认数字或所有推荐升级成决定。

## 本包确认后的文档产物

确认后应分别更新，而不是让本包长期成为唯一事实：

- DECISIONS.md：记录本包 57 个正式组中实际确认的选择，并引用 PJ-02 的 bootstrap 路由与 F4 的 reload/scheduler 选择；M05-10/M05-24 都是非回复式规格门。
- subsystems/03-network-transport.md：timeout、retry-by-phase、proxy、CA、redirect、curl secret 与资源上限。
- subsystems/05-configuration.md：配置层级、INI grammar、XML whitelist、默认顺序和 REPL 事务。
- subsystems/06-model-protocols.md：Protocol、Endpoint、Auth、Streaming、Tools、normalized events 与 capability。
- subsystems/15-diagnostics-and-logging.md：三阶段 self-test、consent、advisory 和报告边界。
- CONFIG-SCHEMA-CANDIDATE.md：把已确认候选改为正式逐字段 registry，按 M05-43 冻结 Model/Permission Description 的 XML projection/digest/omitted 语义，并保留仍待测试的默认常量。
- model-repl/config-repl/TUI/CLI 精确包：冻结最终命令、简称、页面文字和旧终端后备。

进入实现计划前，至少还要有：

- 每个 Protocol 的 request/stream/tool/error golden fixtures；
- retry phase 与 outcome-unknown fault tests；
- secret 不进入 argv/XML/log/diff 的测试；
- INI 注释/顺序/multiline/unknown-field round-trip tests；
- XML override 安全降级和 Model 映射 tests；
- Model/Permission Description 全文、metadata+digest 或 omitted 的 XML/reference-reader/data-classification fixtures；
- model/config REPL transaction transcripts；
- self-test 四屏和“未同意绝不联网”测试；
- XP x86/CentOS 7 的 curl/TLS/timeout/backpressure 验证。
