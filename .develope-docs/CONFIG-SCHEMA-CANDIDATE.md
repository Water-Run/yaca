# 配置 Schema 候选注册表

更新日期：2026-07-18

状态：候选讨论稿；不是已确认决定，也不是可直接使用的 config.ini 模板

## 本文解决什么

项目负责人已经确认两个大方向：

- 一个 Model section 表示一个完整的 LLM 连接实例，不再拆 Provider、Credential 和 Model。
- API Key 直接以明文写在主 INI。

本文进一步推荐 Context XML 不复制 Key、只保存经过允许的会话覆盖和非秘密快照；这个泄漏边界仍是候选，不能从“明文存 Key”自动推导成已确认决定。

但“配置项很多”不等于配置完整。实现者还必须知道每个值的类型、单位、缺失含义、默认、来源、生效时间、是否属于秘密、是否进入 Context 快照，以及它和其他字段组合后是否仍然有效。本文把这些信息收进一份候选注册表，供后续逐项决策。

本文不会修改 src/_CONFIG_.ini，也不把下列候选自动升级为正式契约。正式决定仍以 DECISIONS.md 为准。主要关联问题是 QUESTIONS.md 中的 AQ-131 至 AQ-160、AQ-185、AQ-196 至 AQ-201、AQ-218 至 AQ-221、AQ-235、AQ-236、AQ-244、AQ-245、AQ-361 与 AQ-362；主要设计条目是 CFG-01 至 CFG-24、NET-01 至 NET-13、MODEL-01 至 MODEL-12、MODEL-14、MODEL-15、PROC-13、SAFE-01 至 SAFE-17、LOOP-04、LOOP-15、CTX-06 与 CTX-07。

第四轮配置完整性审计把字段表之外的生命周期缺口补进本文：运行中 reload、双 digest、内部工具的 ambient-config 隔离、reset/backup、optional grammar、XML override 和 generic CLI 来源。新增内容仍只是候选；负责人选择集中在 [决策包 05](decision-packets/05-model-configuration-network-selftest.md) 的 40 个正式 `M05-*` 组，reload/scheduler 分别集中在 [决策包 11](decision-packets/11-cross-system-operational-seams.md) 的 `F4-01`/`F4-02`。本表不得把未选择的方案字段混成一份“全都支持”的 INI：每个条件字段必须标出 owner 选择，未命中的字段从 parser、REPL、help、XML projection 和 self-test 同时消失。

## 先统一几个通俗概念

### Schema 是配置的说明书，不是示例文件

Schema 负责回答“什么值才算合法”。config.ini 只是 Schema 的一个实例。建议由同一份版本化、typed schema 驱动：

- 内置默认值；
- INI 解析和逐字段校验；
- 跨字段校验；
- config-repl 与 model-repl 的字段帮助；
- 默认配置模板；
- show-config 的来源显示与秘密脱敏；
- Context XML 覆盖白名单；
- self-test 第一阶段；
- 配置迁移和废弃字段诊断。

否则很容易出现模板说允许、程序拒绝，或者 UI 忘记把新 secret 字段遮住。关联 AQ-131、CFG-18。

### 默认值、缺失值和空值不是一回事

候选规则：

- 字段“缺失”表示 INI 根本没有这个 key。
- 空字符串表示用户明确写了一个空文本。
- optional integer 的 unset 表示不设置用户上限或使用 provider 默认；最终 INI 拼写仍待 AQ-200 决定。
- required 字段缺失是结构错误，不允许实现时猜测。
- Schema 可以有“生成模板时写入的候选默认”，但正常 reader 是否允许省略该字段需要逐字段说明。

M05-19 需要冻结 optional scalar 的唯一 grammar。当前推荐候选是按含义使用不同 ASCII sentinel，而不是复用布尔值：

| sentinel | 精确含义 | 典型字段 | 不能被解释成 |
| --- | --- | --- | --- |
| `unknown` | 用户不知道该事实，Runtime 采用保守路径 | ContextLength | provider-default、0 |
| `provider-default` | 请求中不发送该 optional 参数 | MaxOutputTokens 或 adapter generation option | yaca 自己选一个数字 |
| `inherit` | Context 不覆盖 INI 值 | XML override | 缺失定义、允许任意上调 |
| `off` | 仅在该字段 schema 明确允许时关闭某项能力 | Streaming 等枚举的一部分 | unknown、无限 |

字段缺失、空字符串与这些 sentinel 仍分别定义。数字字段候选不再接受 `false`；旧 `false` 必须通过版本化迁移表解释，不能由消费者临场猜测。

### 配置来源与优先级

候选来源链如下：

    Runtime 不可降低的安全/资源硬上限
      -> typed schema 内置默认
      -> 完整用户 INI
      -> 当前 Context XML 白名单覆盖
      -> 注册过的命名 session action

仓库文件不属于配置来源。XML 只能选择或覆盖白名单会话值，不能带来 endpoint、Key、代理或新的 Permission 定义。`.model`、`.permission`、`.cautious`、`.prompt` 这类命名动作必须各自声明类型、生效点和是否形成 XML 事件；是否再提供 generic `--set Section.Key=value` 是 M05-22 的负责人选择，在确认前不能把“当前命令参数”当成一个开放配置层。关联 CFG-01 至 CFG-03、AQ-159、CCA-Q-15。

### 生效点

本文使用四种生效点：

- bootstrap：在普通 Agent 启动之前决定；修改后需要重新装载应用服务。
- next-turn：不改变已经开始的 turn；下一 turn 重新冻结配置快照时生效。
- next-request：不改变在途 HTTP/进程；下一次同类请求生效。
- immediate-display：只影响之后产生的诊断显示，不改变领域事实。

候选总原则是：一个 active turn 冻结 Model、Permission、DoubleCheck、Prompt、工作目录、工具集合和预算。手工编辑 INI 不应在 turn 中途偷偷改变行为。关联 AQ-031、AQ-107、LOOP-15。

### 配置 generation 与运行中 reload

字段的 `next-turn`/`next-request` 只描述“新 generation 获准后何时消费”，不能替代“谁发现磁盘变化、坏文件怎么办”的生命周期。候选统一流程是：

~~~text
locate portable data root before reading INI
  -> parse bootstrap schema/version
  -> parse and validate the complete INI
  -> create immutable ConfigGeneration
  -> open Context and apply exact XML whitelist
  -> freeze EffectiveTurnSnapshot
  -> requests/tools consume only that snapshot
  -> explicit reload or chosen safe-boundary detection
  -> accept one complete new generation or fail closed
  -> write a non-secret transition to Context XML
~~~

`ConfigGeneration` 是 Runtime 内部版本化对象，不是 INI 字段。F4-01 仍需在“显式 reload/restart”与“idle/turn 边界检测并确认”之间选择；无论选哪项，以下规则不可改变：

- active turn、在途 HTTP attempt 和已启动进程继续使用创建时 snapshot，不能逐字段热替换；
- 新 INI 必须作为完整文件 parse + cross-validate，一项错误就不能开始新 turn；
- 无效、删除或半写文件不能让 Runtime 静默用 last-known-good 继续产生新副作用；旧 generation 只可用于只读诊断和修复入口；
- 当前 Model/Permission 被删除或重命名时，Context 进入显式 mapping/switch，不自动选第一项；
- 只改注释会改变磁盘冲突身份，但若规范有效投影不变，不产生虚假的行为 transition；
- REPL、普通 chat、self-test 和 show-config 共用一个 generation service，不各缓存一份 mutable table。

### private source digest 与 public effective digest

必须维护两个用途不同、绝不互换的 digest：

| 名称 | 输入 | 可以去哪里 | 禁止用途 |
| --- | --- | --- | --- |
| private source digest | 原始 INI bytes，包含明文 Key 所在 bytes | 只在当前进程做外部修改/stale writer 检测 | XML、终端、日志、support、导出和 Model request |
| public effective digest | typed schema 规范化后的非秘密有效投影 | Context transition/snapshot、status、跨机映射证据 | 不包含 Key、SecretHeader 值、Proxy credential、secret query 或 secret 环境值 |

不能用“整份 INI 的 hash”同时完成两件事：即使 hash 不直接显示 Key，它仍是 secret-derived identifier，会给离线比对和错误日志制造额外泄漏面。digest 算法、canonicalization、版本和字段投影必须进入 schema/测试元数据；本规则是技术不变量，不新增用户开关。

### Runtime 硬上限与用户上限

用户配置只能把资源预算调到 Runtime 允许的有界范围内，不能把队列、XML、HTTP event、工具输出或循环设成真正无界。Schema 中的 unset 只表示“没有更低的用户上限”，仍受发行物硬上限约束。硬上限应由旧机性能和故障测试确定，不一定全部暴露为配置字段。

## 注册表列说明

下列表格中：

- “缺失/默认候选”同时说明 reader 看见字段缺失时怎么办，以及生成新配置时建议写什么。
- “来源”说明字段能否来自 INI 或 XML。snapshot 表示 XML 只保存当时有效的非秘密投影，用于解释历史，不表示 XML 可以覆盖定义。
- “秘密”中的 conditional 表示值可能含凭据，例如带用户名密码的代理 URL。
- “未决”表示必须经过对应 AQ 确认；推荐值不是决定。

当前 Markdown 表为了可读性合并了一些列；它还不是可供实现直接加载的最终 schema。负责人答复后，每个保留字段必须补齐并由同一 registry 驱动 parser/REPL/help/self-test：稳定 field ID 与 introduced version、唯一领域 consumer、为何需要用户可调、完整 grammar/字节界限、missing/empty/sentinel、secret class、允许来源/merge、effective boundary、turn freeze/transition、migration、UI/redaction 以及 XP x86/CentOS 7 proof IDs。缺少任一项时只能继续标候选，不能让某个消费者自行补默认。

## General

| 字段 | 类型、单位与范围 | 缺失/默认候选 | 来源 | 秘密 | 生效点 | Context 快照 | 跨字段约束与状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SchemaMajor | ASCII 十进制整数，1..65535 | 缺失为硬错误；新文件候选 1 | INI only | no | bootstrap | 保存观察到的版本号 | 旧程序遇到更大 major 只读或拒绝写；格式仍待 AQ-185 |
| SchemaMinor | ASCII 十进制整数，0..65535 | 缺失为硬错误；新文件候选 0 | INI only | no | bootstrap | 保存观察到的版本号 | 更大 minor 只有在未知 required feature 不存在时才可读取；待 AQ-185 |
| SystemPrompt | UTF-8 文本；字节和估算 Token 都有硬上限 | 缺失候选等同空字符串；新文件写空值 | INI only | user-content | next-turn | 进入去重 Prompt snapshot，request 引用其 digest | 只能补充用户人格/偏好，不能覆盖 Runtime 规则；多行语法待 AQ-002、AQ-055、AQ-062、AQ-200 |
| LogLevel | M05-17 A：error/warn/info/debug/trace；B：字段不存在；C：normal/trace | A 缺失/新配置为 info；C 为 normal；B 遇到旧字段给迁移诊断 | INI only | no | 载入完整新 generation 后的 next diagnostic event | turn 保存有效级别 | 只控制终端与 XML optional diagnostic；绝不能省略 canonical 对话、审批、工具或恢复事实；A/C 的 enum 不可混用 |
| SelfTestReviewerModel | **仅 M05-12 B 时存在**；引用一个 Model logical name | 缺失为 Stage 3 unavailable，不影响普通 Agent 或 Stage 1/2 | INI only | no | next self-test Stage 3 | 报告保存所选 reviewer 与当次 non-secret snapshot | 必须 enabled、在本次 Stage 2 通过；缺失/失败不 fallback；请求前仍需再次 consent |

候选不增加 Language、含糊的通用 Mode、Vivid、Theme 或自动更新字段。只有 TS-18 明确选择 B 时才在 Agent 中生成语义窄化的 `Autonomy`；它不是旧 `Mode` 的自动改名。固定 English UI、自动终端能力降级、无隐式遥测/更新已经有更简单的候选边界；是否正式删除旧字段见 AQ-157、AQ-246。

数据根位置也不建议放在 General。程序必须先找到配置才能读取该字段，会产生 bootstrap 循环；便携 zip 的数据根由发行布局决定，见 AQ-244。

## Agent

| 字段 | 类型、单位与范围 | 缺失/默认候选 | 来源 | 秘密 | 生效点 | Context 快照 | 跨字段约束与状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DoubleCheck | bool；M05-39 C 时 required，否则新配置写所选默认 | 缺失/新文件行为由 M05-39 冻结 | INI default + XML tri-state override | no | next-turn | 保存 INI 默认、XML override 与最终值 | 开启包含结束复核；动作范围、失败与导入降级由 AL06/CX-14；不再有独立终止评估字段 |
| Autonomy | **仅 TS-18 选 B 时存在**；direct、explanatory | 缺失/新文件候选 direct | INI only | no | next-turn | 保存有效值与来源，不作为 XML override | 只控制主动说明和可选额外验证；不能改变 Permission、DoubleCheck、必需验证、budget 或 control flow；A/C 下字段为 unknown/deprecated |
| ReviewModel | **仅 AL06-08 选 B 时存在**；引用一个 Model logical name | 缺失表示所需 action/termination review unavailable；绝不 fallback | INI only | no | next-turn | 保存 logical name、解析结果和每类实际 request manifest | AL06-07 A/B 下 action-review 与 termination-review 共用该实例；C 下只有 termination；必须 enabled，失效/未确认跨 endpoint 时 waiting-user |
| CompactionModel | **仅 AL06-11 选 A 且 AL06-30 选 B 时存在**；引用一个 Model logical name | 缺失表示 model-generated structured compaction unavailable；绝不 fallback | INI only | no | next-turn | 保存 logical name、解析结果和实际 request manifest | 必须 enabled 且能容纳最小 request；AL06-11 B 是 Runtime deterministic checkpoint、C 是 latest-fit，两者出现字段均为 orphan error |
| MaxModelRequests | **仅 AL06-09 选 A/B 时存在**；正整数，count/turn，1..RuntimeMax | 缺失候选 24 | INI；是否允许 XML 下调待决 | no | next-turn | 保存有效值 | AL06-09 C 使用版本化、不可配置为无限的固定 turn safety cap，出现本字段即 orphan error；side/review/compaction 归账服从 AL06-22/27 |
| MaxToolCalls | **仅 AL06-09 选 A/B 时存在**；非负整数，count/turn，0..RuntimeMax | 缺失候选 64 | INI；是否允许 XML 下调待决 | no | next-turn | 保存有效值 | 0 表示本 turn 禁止工具，不表示 Model 没有 native tool 能力；AL06-09 C 下字段不存在 |
| MaxTurnTimeMs | **仅 AL06-09 选 A/B 时存在**；正整数，毫秒，1..RuntimeMax | 缺失候选 1800000（30 分钟） | INI；是否允许 XML 下调待决 | no | next-turn | 保存 deadline 基准与有效值 | 各 request timeout、retry delay、工具 deadline 总体受它限制；AL06-09 C 改受固定 turn safety cap |
| MaxTurnTokens | **仅 AL06-09 选 A/B 时存在**；optional 正整数，normalized token/turn | 缺失候选 unset；仍受 Runtime hard cap | INI；XML 下调候选 | no | next-turn | 保存有效值和 measured/estimated 标记 | 必须定义 main、side、DoubleCheck、compaction 的实际归账；AL06-09 C 不暴露字段；没有价格 schema 时不等于费用上限 |
| MaxNoProgressRepeats | 正整数，1..16 | 缺失候选 3 | INI only | no | next-turn | 保存有效值 | 同调用重复、ABAB、无状态变化的判定算法仍属 LOOP-05；AQ-029、AQ-154、AQ-196 |
| MaxActionReviewRounds / MaxTerminationReviewRounds | **仅 AL06-27 选 A 时存在**；termination 字段始终存在，action 字段还要求 AL06-07 A/B；正整数，1..RuntimeMax | 缺失候选由预算 fixture 提案 | INI only | no | next-turn | 分别保存实际存在项的有效值 | AL06-07 C 下 `MaxActionReviewRounds` 是 orphan error；局部 cap 共同消耗 AL06-09 所选 turn 边界：A/B 可配置、C 固定；不能无限 |
| MaxDoubleCheckRequests | **仅 AL06-27 选 B 时存在**；正整数，1..RuntimeMax | 缺失候选由预算 fixture 提案 | INI only | no | next-turn | 保存有效值 | action/termination 共用该局部 cap，并共同受 AL06-09 所选 turn 边界约束 |

暂不建议增加 MaxCost。要把费用当作硬预算，Model 还必须配置币种、input/output/cache/reasoning 价格和生效日期，并处理 provider 价格变化；当前只有 token/request 能形成确定上限。若负责人要求费用预算，应新开一组字段和决策，不能用本地猜价伪装成硬保证。

AL06-09 选 C 时，turn safety cap 是发行物中有版本、有 fixture 的硬边界，不生成上述四个 `Max*` INI 字段；AL06-27 选 C 时同理使用固定 review reserve。Queue、steer、side 的语义、Esc、协议纠错次数和是否自动开启下一 turn 是稳定产品行为，不做成大量开关；队列、side、纠错和事件泵仍有不可关闭的 Runtime 硬上限。若以后真实使用证明需要用户调低某个上限，必须把它作为有 consumer/source/snapshot 的 typed 字段重新过 catalog gate，不能先放一个通用 `Advanced`。

## Network

这里的 Network 主要配置 yaca 自己的 Model HTTP；仅当 TS-11 B/C 加入 direct HTTP tool 时，同一 section 还条件性出现带 `DirectHttp` 前缀的独立 policy。两套 CA/proxy/origin/credential 不互相借值。raw shell 启动的 curl 等程序仍属于 Exec/Permission，不能由本 section 假装拦截。

| 字段 | 类型、单位与范围 | 缺失/默认候选 | 来源 | 秘密 | 生效点 | Context 快照 | 跨字段约束与状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ProxyMode | M05-36 A：off/environment/explicit；B：off/explicit；C：off/environment | 三项缺失/新配置均为 off；environment 必须显式选择 | INI only | no | next-request | 保存模式名；environment 还保存当次 non-secret 来源投影 | explicit 要求 ProxyUrl；environment 必须在 generation 建立时解析成显式 snapshot，内部 curl 不自行读取 ambient proxy |
| ProxyUrl | **仅 M05-36 允许 explicit 时存在**；绝对 HTTP/HTTPS proxy URL | 缺失/空表示未配置 | INI only | conditional | next-request | 不保存值；最多保存“configured”和 non-secret origin 投影 | 只有 ProxyMode=explicit 时使用；userinfo 凭据进入 secret registry；AQ-145、SAFE-09 |
| NoProxy | **仅所选 ProxyMode 支持 proxy 时存在**；有序 host/domain/IP/port typed 规则列表 | 缺失候选空列表 | INI only | conditional | next-request | 只保存允许的投影与规则 digest | 禁止把 shell glob、Lua pattern 和 curl NO_PROXY 语法混为一谈；environment 模式也必须规范化成同一内部规则；AQ-145、NET-04 |
| CaMode | M05-37 A：bundled/system/custom/combined；B：bundled/custom；C：system/custom | A/B 缺失及新配置为 bundled；C 为 system | INI only | no | next-request | 保存模式、bundle/system adapter 版本 | custom 要求 CaFile；目标平台证明失败的 enum 不能只因 schema 写了就接受；永不提供 insecure/skip-verify |
| CaFile | 可读普通文件路径 | 缺失/空表示无 custom CA | INI only | conditional | next-request | 保存允许的非秘密规范路径投影和 digest | 仅含 custom 的 CaMode 合法；请求前 open/identity recheck；AQ-146、NET-02 |
| DirectHttpCaMode | **仅 TS-11 B/C 时存在**；enum 集合服从 M05-37 所选且目标发行证明可用的来源 | M05-37 A/B 下缺失/new=bundled；C 下=system | INI only | no | next direct HTTP call | 保存模式和 trust adapter/version | 值独立于 Model CaMode，不读取其 active value；没有 insecure/skip-verify；custom 要求 DirectHttpCaFile |
| DirectHttpCaFile | **仅 TS-11 B/C 且 DirectHttpCaMode 含 custom 时存在**；可读普通文件路径 | 缺失/空表示无 custom CA | INI only | conditional | next direct HTTP call | 保存规范路径投影/digest | 只供 direct HTTP tool，不能被 Model transport 暗读 |
| DirectHttpProxyMode | **仅 TS-11 B/C 时存在**；off/environment/explicit | 缺失/新配置 off | INI only | no | next direct HTTP call | 保存模式与 environment non-secret snapshot | 独立于 Model ProxyMode；environment 也在 generation 建立时冻结 |
| DirectHttpProxyUrl | **仅 TS-11 B/C 且 DirectHttpProxyMode=explicit 时存在**；绝对 HTTP/HTTPS proxy URL | 缺失/空表示未配置 | INI only | conditional secret | next direct HTTP call | 不保存 credential；只存 configured/origin 投影 | 绝不复制 Model ProxyUrl/credential；userinfo 进入 direct-tool secret registry |
| DirectHttpNoProxy | **仅 TS-11 B/C 时存在**；与 Network.NoProxy 共用 grammar 的有序规则 | 缺失空列表 | INI only | conditional | next direct HTTP call | 保存规则投影/digest | 只匹配 direct HTTP transport；不能改变 Model 或 raw shell |
| DirectHttpRedirectMode | **仅 TS-11 B/C 时存在**；deny/same-origin | 缺失/新配置 same-origin | INI only | no | next direct HTTP call | 保存有效值和实际 redirect chain | cross-origin 与 HTTPS->HTTP 始终拒绝；次数/循环仍有 hard cap |
| DirectHttpAllowedOrigin | **仅 TS-11 B/C 时存在**；exact normalized scheme+host+port 列表，无 wildcard | 缺失/空列表表示 direct HTTP 不可调用，但不阻断其他 Agent 能力 | INI only | conditional metadata | next direct HTTP call | 保存 matched rule/digest | HTTPS 可列入；HTTP 只允许可证明 loopback 且无 registered secret；call/approval 显示 exact origin |
| MaxHeaderKiB | **仅 M05-14 A/B 时公开**；正整数，KiB，1..RuntimeMax | 缺失候选需旧机 fixture 校准 | INI only | no | next-request | 保存有效值 | 所有 attempts 共同受 Runtime/turn 内存硬门；M05-14 C 时字段必须 unknown/deprecated |
| MaxEventKiB | **仅 M05-14 A/B 时公开**；正整数，KiB/SSE event，1..RuntimeMax | 缺失候选需 fixture 校准 | INI only | no | next-request | 保存有效值 | 还受 JSON 深度、tool argument 和 response 总硬门约束 |
| MaxBufferedKiB | **仅 M05-14 A/B 时公开**；正整数，KiB，1..RuntimeMax | 缺失候选需 fixture 校准 | INI only | no | next-request | 保存有效值 | 消费者落后时暂停读取或取消，不能无限 Lua table；AQ-245、CONC-03 |
| MaxCompressedBodyKiB | **仅 M05-14 B 时公开**；正整数，KiB，1..RuntimeMax | 缺失候选需 fixture 校准 | INI only | no | next-request | 保存有效值 | 约束压缩 wire body；不替代解压后与 logical response cap |
| MaxDecompressedBodyKiB | **仅 M05-14 B 时公开**；正整数，KiB，1..RuntimeMax | 缺失候选需 fixture 校准 | INI only | no | next-request | 保存有效值 | 必须与 ratio、buffer、logical response 组合校验 |
| MaxErrorBodyKiB | **仅 M05-14 B 时公开**；正整数，KiB，1..RuntimeMax | 缺失候选需 fixture 校准 | INI only | no | next-request | 保存有效值 | 错误正文仍需脱敏/截断，不因诊断需要解除 hard cap |
| MaxToolArgumentsKiB | **仅 M05-14 B 时公开**；正整数，KiB/call，1..RuntimeMax | 缺失候选需 fixture 校准 | INI only | no | next-request | 保存有效值 | 还受 JSON depth、batch 与 turn memory hard cap |
| MaxLogicalResponseKiB | **仅 M05-14 B 时公开**；正整数，KiB/logical request，1..RuntimeMax | 缺失候选需 fixture 校准 | INI only | no | next-request | 保存有效值 | 汇总 text/tool/reasoning/usage canonical bytes，不被 retry/fallback 重置 |
| MaxDecompressionRatio | **仅 M05-14 B 时公开**；正 decimal ratio，1..RuntimeMax | 缺失候选需 fixture 校准 | INI only | no | next-request | 保存有效值 | 与 compressed/decompressed cap 同时执行，不能单独调大绕过内存门 |

候选固定而不配置的安全规则：

- 不提供 SkipTlsVerify 或 Insecure。
- `http://` 与 Key/SecretHeader 的组合由 M05-13 选择；在选择前不能把“URL 语法合法”当成“允许发送”。当前推荐候选仅允许强制 direct/bypass、无鉴权且可证明的 loopback HTTP。
- redirect 由 M05-38 冻结；无论选择哪条路线，credential 永不跨 origin，HTTPS 降级必须服从 M05-13 且不能携带 secret，次数/循环/正文都有硬门。
- curl 自带 retry 必须关闭，由 Model/Runtime 记录 request/attempt 后决定。
- 启动、配置浏览、Context 浏览和离线 self-test 不隐式联网。
- compressed body、decompressed body、error body、tool arguments、logical response total 和 decompression ratio 都有 Runtime hard cap；M05-14 只决定其中哪些成为可调低的 INI 字段。

Runtime 内部 curl 不继承宿主 `.curlrc`/`_curlrc`、`.netrc`、HOME 定位、隐式 proxy/CA 环境或 cwd/PATH 同名工具。它使用发行 manifest 中的绝对路径、首参数禁 default config、完整显式 CA/proxy/redirect/protocol/output 规则和受控 stdin。这个 ambient-config 隔离是 `HCFG-04` 技术不变量，不增加 `InheritCurlConfig` 开关；最终随包 curl 在 XP x86/CentOS 7 是否能兑现必须用恶意 canary 实测。

## Exec

候选把 Exec 作为全局 raw-shell/子进程运行策略，不把每个可执行程序做成命名配置对象。模型可见 exec 接受原始命令；底层 Process port 仍以结构化 executable/argv 启动平台 shell。AQ-119、AQ-147 还需确认这一简化方向。

| 字段 | 类型、单位与范围 | 缺失/默认候选 | 来源 | 秘密 | 生效点 | Context 快照 | 跨字段约束与状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TimeoutMs | positive integer，毫秒/call | 缺失候选 600000（10 分钟）；未决 | INI only | no | next tool call / next-turn snapshot | 保存有效值 | 每次调用 deadline 不得越过 MaxTurnTimeMs；AQ-126、AQ-147 |
| MaxOutputKiB | positive integer，stdout+stderr canonical 总量 | 缺失候选 128 KiB；需 AQ-195/fixture 确认 | INI only | no | next tool call | 保存有效值 | 超限保留头尾、总量、截断标记；TUI 临时流也有独立队列上限 |
| EnvironmentMode | **仅 M05-15 选 B 时存在**；枚举 inherit、clean | 缺失候选 inherit | INI only | no | next tool call | 保存模式，不复制完整宿主环境 | A 固定受控继承、C 固定 clean，都没有此字段；clean 仍需 Runtime 最小 PATH/TEMP 契约 |
| EnvironmentSet | **仅 M05-15 选 B 时存在**；有序 NAME=value 列表，名称 ASCII，具体 INI 表达待决 | 缺失候选空列表 | INI only | conditional | next tool call | 只保存允许的 secret-aware 投影 | 不能覆盖 Runtime 保留变量；secret 值不进 XML/诊断；AQ-148、SAFE-09 |
| EnvironmentUnset | **仅 M05-15 选 B 时存在**；有序 ASCII NAME 列表 | 缺失候选空列表 | INI only | no | next tool call | 保存名称列表 | 同名同时 set/unset 为硬错误；AQ-148 |
| ShellDialect | **仅 TS-13 选 C 时存在**；目标平台注册的 ASCII enum | 缺失候选目标平台规范 shell | INI only | no | next tool call | 保存 exact dialect/adapter ID | 只能选择随平台发布并通过 quoting/cancel/encoding 证明的 allowlist，不接受任意 executable 路径 |

`TerminateGraceMs` 与 `OutputEncoding` 不进入 INI、XML override 或 session parameter schema：

- 终止 grace 是各平台 Process adapter 的版本化常量，由最终发行 zip manifest 携带，并由子进程树/取消技术证明冻结。status、self-test 和 operation result 可以只读显示实际 adapter ID 与 grace；用户不能把它调成无限或绕过 unknown 结果。
- 输出解码以 Runtime 内建 `auto` 为唯一基线，每次 result 记录实际采用的 decoder、替换/失败与原始字节计数。只有旧平台技术证明显示 `auto` 无法可靠判定时，技术侧才可提出窄 typed troubleshooting override；在该证明、字段 grammar、适用平台和退出条件全部审阅前，当前 schema 不存在这个字段，也不接受 generic override 偷渡。

候选永不公开任意 `ShellProgram` 路径。TS-13 A 固定目标 OS 的 `cmd.exe`/`/bin/sh`，B 由每个发行 zip manifest 固定一个不可切换的 canonical dialect；只有 C 出现上面的 typed `ShellDialect`，且选项来自发行 allowlist。任意路径会同时改变 quoting、取消、ambient config 和安全说明，不能借 generic 配置字段绕开 adapter 证明。stdout/stderr 是否保存 observed cross-stream sequence 是 TS-22 的结果契约，不产生配置字段。

以下规则不可关闭：

- 输出、时间、进程数量和进程树始终有硬门；stdin 只采用 F4-07 的 EOF 或有界 immutable `stdin_text` 路线；v0.1 两条路线都不支持继承 TUI stdin、交互 PTY/console，也不生成对应配置；
- 每次调用显式 cwd，默认是 turn 冻结工作目录；
- 取消尝试终止进程树，无法证明时结果为 termination-uncertain；
- raw shell 不承诺工作区、网络或文件隔离。

M05-15 若选择推荐 A，三个环境字段全部从正式 schema 删除；选择 C 时也不出现这些字段，而由 Runtime 固定 clean baseline。不存在 `ExposeConfiguredProxy`：任何选项下全局 proxy/credential 都不自动传播给 raw shell。内部 curl/Git/helper 永远不使用 raw-shell 环境：它们服从 `HCFG-04`，不能因 M05-15 的选择而读取用户 curlrc、Git external diff、pager、credential helper 或隐式 CA。

## Context

Context section 只配置用户体验和预算偏好。自动保存、canonical durable 屏障、XML 验证、损坏隔离和 no-replace 不应成为可以关闭的普通配置。

| 字段 | 类型、单位与范围 | 缺失/默认候选 | 来源 | 秘密 | 生效点 | Context 快照 | 跨字段约束与状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AutoJumpToDir | **仅 PJ-13 选 A/B 时存在**；bool | 缺失候选 true | INI only | no | Context open / resume | 保存字段值、边界判定、用户选择和实际结果 | 跨 initial boundary/Git root/identity 时即使 true 也要显式确认；目录不存在或无权限时进入 mapping/recovery，不猜目录 |
| ResumeDirectory | **仅 PJ-13 选 C 时存在**；jump、ask、keep | 缺失/新文件候选 ask | INI only | no | Context open / resume | 保存字段值、边界判定、用户选择和实际结果 | `jump` 也不能绕过跨 boundary/identity 确认；`keep` 要先显式 rebind；与 AutoJumpToDir 互斥 |
| CompactThreshold | **仅 AL06-11 选 A/B 时存在**；decimal ratio，0 < value < 1 | 缺失候选 0.75 | INI；M05-06 B/C 才允许 XML 下调 | no | next-turn / next compaction/checkpoint check | 保存有效值与 A structured-summary/B deterministic-checkpoint consumer | C 只做 latest-fit view，不生成 threshold 字段；触发计算还要扣除 Prompt/tool/output reserve |
| MaxContextMiB | **仅 CX-11 选 B 时存在**；positive integer，MiB | 缺失候选由 Runtime hard ceiling/fixture 提案且只能更低 | INI only | no | Context create/open/next commit admission | 保存有效值和 hard ceiling identity | 单 active XML 软配额；达到后 fail-stop/只读，不静默删历史 |
| MaxActiveContexts | **仅 CX-11 选 B 时存在**；positive integer，count | 缺失候选由 fixture 提案且只能低于 Runtime cap | INI only | no | next create/archive/restore | 保存有效值 | 只计 active；archive 可降低此计数，但仍计总量 |
| MaxContextTotalMiB | **仅 CX-11 选 B 时存在**；positive integer，MiB | 缺失候选由 fixture 提案且只能低于 Runtime cap | INI only | no | next Context mutation/commit admission | 保存有效值和扫描 generation | active/archive/trash 全计入；超额不自动删除 |
| AutoPurgeTrash | **仅 CX-11 选 C 时存在**；bool | 缺失/新文件 false | INI only | no | next maintenance scan | 保存值、generation 与每次 purge plan/result | true 要求 TrashGraceDays；只处理可证明属于 trash 的 item，不能触及 active/archive |
| TrashGraceDays | **仅 CX-11 选 C 且 AutoPurgeTrash=true 时 required**；positive integer days，1..RuntimeMax | false 时字段必须缺失；true 时无隐式默认，由 config-repl 要求用户输入 | INI only | no | next maintenance scan | 保存有效值和每项 durable trashed_at/eligibility | 无可靠 trashed_at、锁定、stale scan 或预告失败都不得 purge |

`CompactReserveTokens` 与 `MaxScanEntries` 也不属于配置 schema：

- compaction/view builder 每次按有效 Model 窗口、最大输出、固定 Prompt、tool schema、当前不可拆原子组和估算误差计算只读 effective reserve；Model/view 变化就重新计算。INI 与 XML 都不能设置它。request/view manifest 可以记录本次派生值、输入摘要与算法版本作为历史证据，但它不是可恢复的会话偏好。
- Resolver 的扫描量由各发行 zip manifest 与 Runtime 共同执行不可放宽的 hard cap；数值由目标旧机的复杂度、内存和响应测试冻结。context-repl/status/self-test 只读显示当前 cap 与 manifest identity；命中上限返回 `ScanLimit`/incomplete，不把未扫描范围报告为不存在。

候选不放 RootDir、AutoSave、RepairOnOpen、ExportSecrets 或通用 RetentionDelete；只有 CX-11 C 才有上表严格限于 trash 的两个 auto-purge 字段：

- RootDir 在配置加载前就必须确定，见 AQ-244。
- `AutoNameOnExit` 与 `SuggestContextNameAfterFirstTurn` 都不进入 schema：PJ-12 B 已把首个完成 main turn 后的一次建议定义成固定行为，A/C 也不需要开关；旧字段只给 deprecated diagnostic。
- AutoSave=false 会破坏 XML 作为核心事实源的恢复契约。
- 损坏修复必须保守且留证据，不能按偏好静默截断。
- export 每次都应显式预览。
- 自动年龄删除与“完整接盘”冲突，若未来需要保留策略应独立讨论。

## Permission.*

section suffix 是本地逻辑名称，例如 Permission.Std。它本身就是用户选择器，不再重复保存 Name 字段。所有 Permission section 都必须完整有效，不设置 Enabled；物理顺序第一项是新 Context 默认项，见 D-021、AQ-037、AQ-134。

每个能力字段候选使用 deny、confirm、allow 三态。缺失是硬错误，不按字段默认，以免新增安全能力时旧 profile 被静默放行。关联 AQ-149、AQ-150。

| 字段 | 类型、单位与范围 | 缺失/默认候选 | 来源 | 秘密 | 生效点 | Context 快照 | 跨字段约束与状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Abbreviation | 1..16 个 ASCII letter/digit/hyphen；首字符 letter | 缺失候选允许由 REPL 建议但保存前必须显式 | INI definition；XML 只选 section | no | next-turn | 保存逻辑名、简称与 policy snapshot | 在 Permission 命名空间内与所有长名/简称折叠后唯一；AQ-135、AQ-199 |
| Description | UTF-8 user text，0..256 bytes | 缺失候选空字符串 | INI definition | user-content | next-turn | 保存非秘密文本或 digest；待定 | 名称/描述不决定真实安全语义；self-test 第三阶段只能 advisory；AQ-202 |
| Color | **仅 M05-21 B 才存在**；basic 8/16-color ASCII enum | 缺失由 TUI 确定性分配 | INI definition | no | next-turn/display | 保存枚举 | 只影响 Permission label；颜色不能是唯一语义，语义角色/后备由 TU-02；A/C 时删除 |
| Read | deny/confirm/allow | 缺失硬错误 | INI definition | no | next-turn | 保存有效值 | 只约束 yaca 直接 read/list/search；raw shell 不受它隔离 |
| SensitiveRead | **仅 M05-16 C 才存在**；deny/confirm/allow | 若存在则缺失硬错误，内置模板候选 confirm | INI definition | no | next-turn | 保存有效值与分类器版本/原因 | 字段存在性由 M05-16；分类来源与 `Read` 的更严格求值由 TS-21；未命中绝不表示安全 |
| Write | deny/confirm/allow | 缺失硬错误 | INI definition | no | next-turn | 保存有效值 | 约束直接 create/write/patch；raw shell 仍只看 Shell |
| Delete | deny/confirm/allow | 缺失硬错误 | INI definition | no | next-turn | 保存有效值 | delete/replace-existing/rename source 的映射需工具表冻结；AQ-117、AQ-118 |
| Shell | deny/confirm/allow | 缺失硬错误 | INI definition | no | next-turn | 保存有效值及“broad capability”标志 | 一旦允许，Runtime 不能证明命令不写文件、不联网或不越界；AQ-224 |
| DirectNetwork | **只有 TS-11 B/C 选择 direct HTTP tool 时存在**；deny/confirm/allow | 若存在则缺失硬错误，内置模板候选 confirm | INI definition | no | next-turn | 保存有效值 | 这是 direct HTTP 的必需真实消费者字段；不由 M05-16 再开关，不约束 Model provider HTTP，也不能隔离 raw shell；NET-11 |
| OutsideWorkspace | **仅 M05-16 选 A 时存在**；deny/confirm/allow | 缺失硬错误 | INI definition | no | next-turn | 保存有效值 | 作为 direct Read/Write/Delete 的共同 modifier，与基本能力取更严格结果；不能单独表达外读/外写差异 |
| OutsideRead | **仅 M05-16 选 B/C 时存在**；deny/confirm/allow | 缺失硬错误 | INI definition | no | next-turn | 保存有效值 | 与 Read 取更严格结果；链接目标按真实规范路径判定 |
| OutsideWrite | **仅 M05-16 选 B/C 时存在**；deny/confirm/allow | 缺失硬错误 | INI definition | no | next-turn | 保存有效值 | 与 Write 取更严格结果；raw shell 不受它隔离 |
| OutsideDelete | **仅 M05-16 选 B/C 时存在**；deny/confirm/allow | 缺失硬错误 | INI definition | no | next-turn | 保存有效值 | 与 Delete 取更严格结果；rename/replace 映射由 tool matrix 冻结 |

候选内置 profile 只是生成模板，不让名称决定含义：

| Profile | Read | Write | Delete | Shell | Outside（按 M05-16 展开） | SensitiveRead（仅 M05-16 C） | DirectNetwork（仅 TS-11 B/C） |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Std | allow | confirm | confirm | confirm | confirm | confirm | confirm |
| Trusted（仅 TS-04 选择提供第三预设时） | allow | allow | allow | allow 或 confirm，依 TS-04 | allow | allow | allow |
| Readonly | allow | deny | deny | deny | deny | confirm | deny |

以上具体矩阵仍待负责人确认。Cautious 不是 profile，DoubleCheck 不出现在 Permission section。上表只是 TS-04、M05-16 与 TS-11 组合后的生成示意：若 outside 字段拆分，应展开成三列；M05-16 C 的 SensitiveRead 分类仍服从 TS-21；若没有 direct HTTP tool，DirectNetwork 列必须完全消失，而不是保留一个永远无消费者的 deny。

候选删除 AllowRegex/ExcludeRegex。正则无法证明复合 shell 的副作用；若保留，只能作为附加 deny/warn 规则，绝不能凭匹配授予原本没有的能力。关联 SAFE-07、AQ-224。

## Model.*

section suffix 是 yaca 本地 Model 逻辑名，例如 Model.DeepSeek。一个 section 自含协议、endpoint、远端模型、Key、能力、超时和 retry，落实 B-06/AQ-016。不要再添加另一个含义模糊的 Name；远端 ID 使用 RemoteModel。

| 字段 | 类型、单位与范围 | 缺失/默认候选 | 来源 | 秘密 | 生效点 | Context 快照 | 跨字段约束与状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Enabled | bool | 缺失硬错误；新建草稿候选 false | INI definition；XML 只选逻辑名 | no | next-turn | 保存当时值 | 第一 Model 必须 enabled 且完整；disabled section 类型仍需合法，但连接必填项可为空；AQ-134 |
| Abbreviation | 1..16 个 ASCII letter/digit/hyphen；首字符 letter | 缺失在保存前硬错误 | INI definition | no | next-turn | 保存逻辑名与简称 | Model 命名空间内长名/简称折叠后唯一；AQ-135、AQ-199 |
| Description | UTF-8 user text，0..256 bytes | 缺失候选空字符串 | INI definition | user-content | next-turn | 保存文本或 digest，待数据分类 | 不用于自动判断 provider/model 是否匹配；AQ-202 |
| CustomPrompt | **仅 PP-11 选 B/C 时存在**；有界 UTF-8 user-configured text | 缺失候选空字符串 | INI definition only | user-content | next-turn | 保存完整 Prompt component snapshot/digest、PP-11 route 与 Model transition 引用 | B 是高于 SystemPrompt 的 Model-specific 用户层；C 是受限 adapter compatibility instruction；两者都低于 Runtime，C 不能改 serializer/role/tool/control；A 下字段必须 unknown/deprecated |
| Color | **仅 M05-21 B/C 才存在**；basic 8/16-color ASCII enum | 缺失由 TUI 确定性分配 | INI definition | no | next-turn/display | 保存枚举 | 只影响 Model label；颜色非语义，TU-02 拥有语义角色/后备；A 时删除 |
| Protocol | 稳定 ASCII enum；首版候选 openai-chat | enabled 时缺失硬错误 | INI definition | no | next-turn | 完整保存 | 不从 Endpoint 猜；v0.1 是否只支持一种见 AQ-138、AQ-218 |
| Endpoint | M05-33 A：完整请求 URL；B：origin/base URL；C：可含部署前缀的 base URL；长度受限 | enabled 时缺失/空为硬错误 | INI definition | conditional | next-turn / next request | 仅保存 M05-20/M05-32 允许的 secret-aware 非秘密投影与 public digest | adapter 不得猜未被 M05-33 选择的 path 规则；HTTP/Auth/Proxy、userinfo/query secret 与 redirect 由 M05-13/36/38 冻结 |
| ApiPath | **仅 M05-33 选 C 时存在**；以 `/` 开始的受限 path，不含 scheme/host/query/fragment | enabled 时缺失为硬错误 | INI definition | conditional | next-turn / next request | 保存允许的规范 path 投影与 digest | 与 Endpoint 只按唯一规范算法拼接；不能覆盖 origin、携带 secret 或使用 `..` 猜部署路径 |
| RemoteModel | UTF-8/ASCII provider model ID，1..512 bytes | enabled 时缺失/空为硬错误 | INI definition | conditional | next-turn | 保存非秘密投影 | 不能从本地 section 名推断；AQ-136 |
| AuthMode | M05-02 A：protocol/none；B：再加 adapter 注册的 typed auth enum；M05-02 C 时字段不存在 | 缺失候选取决于 M05-02；未确认前不冻结 | INI definition | no | next-turn | 保存枚举/adapter identity | 空 Key、header 名和 none endpoint 全由 adapter schema 校验；自由 header 不得冒充 Runtime auth |
| AllowPlainHttp | **仅 M05-13 选 B/C 时存在**；bool，逐 Model 风险确认 | 缺失 false | INI definition | no | next-turn / first request to origin | 保存选择、实际 origin class 与确认事件 | 只放开 M05-13 已选定的 private/any scope，永不放开 Key/SecretHeader/proxy credential 的 HTTP 发送；A 时字段必须不存在 |
| Key | 任意非 NUL 文本；字节上限 | 缺失候选空；enabled 时按 M05-02 选中的 auth/adapter schema 校验 | INI definition only | yes | next-turn / next request | 永不进入 XML、public effective/Model snapshot digest、诊断或支持输出 | private source digest 只留进程内；明文风险与 carrier 证明见后文；AQ-017、AQ-040、SAFE-09 |
| ContextLength | optional positive integer，tokens | 缺失候选 unknown | INI definition | no | next-turn | 保存值及 declared/observed 来源 | unknown 进入保守预算；必须大于必要 Prompt/工具/输出余量；AQ-142 |
| MaxOutputTokens | optional positive integer，tokens | 缺失候选 provider-default | INI definition | no | next-turn | 保存有效值 | 已知 ContextLength 时必须更小；provider 实际 cap 可进一步限制；MODEL-08 |
| Streaming | enum force、try、off | 缺失候选 try | INI definition | no | next-turn / next request | 保存值与实际使用模式 | force 不可静默降级；try 只在任何规范响应事件前按明确能力错误回退；AQ-018、AQ-139、AQ-198 |
| Tools | M05-03 A：native/off；B：字段不存在，Protocol adapter 静态必须 native；C：native/off/required-native | A/C 的缺失行为由选择冻结；B 遇到字段为 unknown/migration diagnostic | INI definition | no | next-turn | A/C 保存声明与 observation；B 保存 adapter manifest capability snapshot | 不做文本 emulation；B 的在线 observation 只 support/warn，不是启用 gate；Tools=off 的 main 资格由 M05-26 |
| PublicReasoning | **仅 M05-40 C 时存在**；off/summary/full-public，且 enum 受 Protocol adapter capability 约束 | 缺失候选 off | INI definition | user-content policy | next-turn / next request | 保存选择、实际公开 kind 与来源 | A 自动消费明确公开 summary 而无字段，B 完全不消费；任何路线都不请求/伪造 hidden reasoning |
| ConnectTimeoutMs | **M05-04 A/B 时公开**；positive integer，毫秒 | 缺失候选由网络 fixture 提案 | INI definition | no | next request | 保存有效值 | 不得越过 logical/turn deadline；M05-04 C 时字段不存在 |
| FirstEventTimeoutMs | **M05-04 A/B 时公开**；positive integer，毫秒 | 缺失候选由网络 fixture 提案 | INI definition | no | next request | 保存有效值 | 从 request 发送完成到首个 canonical event；M05-04 C 时字段不存在 |
| IdleTimeoutMs | **M05-04 A/B 时公开**；positive integer，毫秒 | 缺失候选由网络 fixture 提案 | INI definition | no | next request | 保存有效值 | 只有有效 canonical event 重置；M05-04 C 时字段不存在 |
| TotalTimeoutMs | **仅 M05-04 A 时公开**；positive integer，毫秒/logical request | 缺失候选由网络 fixture 提案 | INI definition | no | next request | 保存有效值 | 覆盖 attempts 与 backoff，且受 turn deadline；不能在每 attempt 重置 |
| MaxLogicalElapsedMs | **仅 M05-04 B 时公开**；positive integer，毫秒/logical request | 缺失候选由网络 fixture 提案 | INI definition | no | next request | 保存有效值 | 封顶各 attempt total + retry/backoff；每 attempt 内部 cap 仍不可关闭 |
| RequestDeadlineMs | **仅 M05-04 C 时公开**；positive integer，毫秒/logical request | 缺失候选由网络 fixture 提案 | INI definition | no | next request | 保存有效值 | Runtime 仍有不可关闭的内部 connect/idle/attempt 上限，错误必须说明命中阶段 |
| RetryCount | non-negative integer，attempts after first，0..RuntimeMax | 缺失候选 2 | INI definition | no | next request | 保存有效值 | 只有明确可重试阶段；发送结果 unknown 或收到规范事件后不盲重放；AQ-140、AQ-197、AQ-221 |
| RetryBaseDelayMs | non-negative integer，毫秒 | 缺失候选 1000 | INI definition | no | next request | 保存有效值 | 指数退避加 Runtime 固定 jitter；AQ-140、AQ-197 |
| RetryMaxDelayMs | non-negative integer，毫秒 | 缺失候选 10000 | INI definition | no | next request | 保存有效值 | 必须 >= base；Retry-After 仍受该值或独立 hard cap，待 NET-06 |
| MaxConcurrentRequests | **仅 F4-02 选 B 才存在**；positive integer，1..RuntimeMax | 缺失候选 1；精确默认待负责人/fixture | INI definition | no | next request / scheduler admission | 保存声明值与实际排队原因 | 同一 Model 的六个核心 purpose 与 PJ-12 B 条件 `context-name` 共用；只约束当前进程，不宣称账户级跨进程配额；AQ-362、MODEL-15 |
| MinRequestIntervalMs | **仅 F4-02 选 B 才存在**；non-negative integer，毫秒 | 缺失候选 0；精确默认待负责人/fixture | INI definition | no | next request / scheduler admission | 保存声明值与实际等待 | 与有界 Retry-After/cooldown 取更严格值；等待可取消且不得越过 local/aggregate deadline；AQ-362、MODEL-15 |
| AdapterOption.<Name> | **M05-05 A 时由 M05-01 选中 Protocol 的发行 artifact 登记的 exact typed 字段族**；类型/范围/secret/wire encoding 逐项冻结 | 缺失表示该 registry 项声明的 provider-default/不发送语义 | INI definition | per option | next-turn / next request | 只保存实际发送的允许投影及 registry version | 不是开放任意字段；编码前 registry 必须列齐并有 fixture，未登记名为 unknown；禁止覆盖核心 body；MODEL-11 |
| GenerationIntent.<Name> | **仅 M05-05 B 时存在**；核心登记 exact intent，M05-01 选中 Protocol 的发行 artifact 逐项声明 mapping/support/wire fixture | 缺失表示不发送相关参数 | INI definition | no | next-turn | 保存 intent、adapter mapping/version 与实际 wire projection | 不是开放名称；未登记或不能无损映射就静态拒绝，不假定不同 Protocol 同名参数同义，也不总是发送 |
| PublicHeader | **仅 M05-23 选 B/C 时存在**；有序、有界 header name/value | 缺失空列表 | INI definition | conditional | next-turn / next request | 只保存经过允许的非秘密投影 | 禁止覆盖 auth、content、host、tool/control 和 Runtime 保留 header；选择 A 时字段必须 unknown/deprecated |
| SecretHeader | **仅 M05-23 选 B 时存在**；有序、有界 header name/value | 缺失空列表 | INI definition only | yes | next-turn / next request | 只保存 header 名、数量与 configured 标志 | 值不进 XML/public digest/诊断/reviewer；选择 A/C 时字段必须 unknown/deprecated |

### Model request scheduler 不是 retry 的别名

F4-02 决定是否加入 `MaxConcurrentRequests`/`MinRequestIntervalMs`。如果选择候选 B，单进程内所有引用同一 Model 的 purpose 必须经过同一个 scheduler：六个核心 purpose 与 PJ-12 B 的条件 `context-name` 不能各自拥有互不相知的 retry timer。

- scheduler admission 只决定“何时允许开始 attempt”，不扩大 turn/request/tool hard budget；
- 服务端 `Retry-After` 与连续明确限流形成有界进程内 cooldown，所有 purpose 共同看见；
- 等待必须可取消，deadline 先到则返回 local scheduling timeout，不伪装成 provider response；
- 每个 purpose 有 local request/token/time cap；main/side/review/compaction 进入所属 Context/turn aggregate ledger，显式 self-test 在无 Context/turn 时进入独立 `self_test_run` aggregate；PJ-12 B 的 `context-name` 使用每 Context 一次的 lifecycle budget，计入 Context/runtime 而不回记已结束 turn；scheduler admission 与账本归属是两张表，不能因为共享排队就伪造共同 turn；
- v0.1 候选不承诺同 Key、同 endpoint 的多个 yaca 进程共享账户配额，进程重启也不伪造持久 cooldown；
- self-test 仍进入 scheduler，不能为“测试”绕过服务端保护。

如果 F4-02 选择 A，两个 per-Model 字段和共享公平队列不进入正式 schema；Runtime 仍必须有不可关闭的进程并发 hard cap、Retry-After 上限、可取消等待和 aggregate ledger，不能让“没有可调字段”变成“没有边界”。

待单独决定而不先加入无条件字段：

- Model.CustomPrompt：只有 PP-11 B/C 才按上表生成，A 删除；无论路线，真正协议 serializer/template 都属于内置版本化 adapter，不能被用户文字替换；AQ-143。
- Model 级 Proxy：用户已要求代理全局，不重复；AQ-145。
- FallbackModel：失败时不静默换 endpoint、费用和隐私域；MODEL-10。
- 价格字段和 MaxCost：只有决定做可校验费用预算后才增加。
- reasoning effort、response format、provider API version 等协议专用项：只通过明确的 `AdapterOption.<Name>` typed schema 增加，不能用 generic `ExtraParameter` 任意覆盖 JSON body。

## 旧配置草案的候选迁移

这一表只说明新旧语义怎样对应，不授权现在修改模板。迁移器必须先识别旧 schema 版本；没有版本证据时，不可按字段名字猜测并静默重写。

| 旧字段/结构 | 新候选 | 迁移与诊断 |
| --- | --- | --- |
| Network.FollowProxy | Network.ProxyMode | true 候选迁到 environment，false 候选迁到 off；保存前展示 |
| Network.UseStunnel | 删除 | 当前发行资源没有 stunnel；硬诊断，不保留一个实际无效的开关 |
| Network.MaxRetry / RetryDelayMs | 每个 Model 的 RetryCount / RetryBaseDelayMs | 不能静默复制给未来新增 Model；迁移时逐 Model 显示 |
| Exec.TimeoutMs=false / MaxOutputKB=false | typed optional 或有界 Runtime default | “false 等于无限”的旧语义不能突破 Runtime hard limit |
| Permission.Allow* + Confirm* | deny/confirm/allow 三态 | Allow=false 映射 deny；Allow=true + Confirm=true 映射 confirm；Allow=true + Confirm=false 映射 allow |
| Permission.*.DoubleCheck | Agent.DoubleCheck | 多个 profile 值可能互相冲突，不能自动选择；要求用户确认全局默认 |
| Permission.Cautious 的内置身份 | 删除特殊身份 | 同名 section 可以保留为普通自定义 profile，但名称不再自动开启 DoubleCheck |
| Permission.AllowRegex / ExcludeRegex | 候选删除 | 若负责人保留，只能作为附加 deny/warn，不能授予 raw shell 能力 |
| Tui.CheckModelOnStart / CheckModelPerformanceOnStart | 删除 | 启动不隐式联网；真实检查只由显式 self-test/model-repl 发起 |
| Tui.DotCommandCompletion | 候选固定能力自动降级 | 不再建立 TUI mode；旧终端不支持时使用完整文本命令 |
| Model.Style | Model.Protocol | 必须通过受支持枚举迁移，不能从 URL 猜 |
| Model.Name | Model.RemoteModel | 消除和 section 逻辑名的歧义 |
| Model.Url | Model.Endpoint | 迁移后验证是完整 endpoint 还是 base URL，等待该契约确认 |
| Model.TimeoutMs | Connect/FirstEvent/Idle/TotalTimeoutMs | 一个旧值无法无损推导四个值；迁移器提出候选并要求确认 |
| Model.CustomPrompt | PP-11 A 删除并展示后让用户合并到 SystemPrompt/ContextPrompt；B/C 保留为上表各自 typed 语义 | 不静默丢内容，也不能把旧自由文本无提示提升为 C 的 adapter compatibility instruction；迁移预览 owner route、authority 与 Model switch 影响 |

## Context XML 覆盖白名单

### 候选可覆盖项

| XML 会话项 | 缺失语义 | 有效值 | 生效点 | 安全/恢复规则 |
| --- | --- | --- | --- | --- |
| CurrentModel | 新 Context 继承 INI 第一 Model；已有 Context 缺失视为旧 schema 迁移 | INI 中 enabled Model 的逻辑名 | next-turn | 不复制 Model 定义；失效时先只读打开并要求显式映射，不能静默改用第一项；AQ-235、AQ-236 |
| CurrentPermission | 新 Context 继承 INI 第一 Permission | INI 中 Permission 逻辑名 | next-turn | 引用失效或比本机默认更宽松时显著显示并确认；不能从 XML创建 profile |
| DoubleCheckOverride | inherit | inherit、true、false | next-turn | 复制/导入来的 false 若降低本机默认，需要确认；AQ-151 |
| ContextPrompt | 空字符串 | UTF-8 文本及大小上限 | next-turn | 保存当前值、变更事件和 Prompt snapshot；不能覆盖 Runtime 规则；AQ-003、AQ-058、AQ-163 |
| ReviewModelMapping | 缺失表示尚未为本 Context 选择 | **仅 AL06-08 选 C 时存在**；INI 中 enabled Model 的逻辑名 | next action/termination review | AL06-07 A/B 下两类 review 共用映射，C 下只有 termination；首次选择与 remap 写事件，失效时 waiting-user，不 fallback/复制定义 |
| CompactionConsent | 缺失表示尚未询问 | **仅 AL06-11 选 A 且 AL06-34 选 C 时存在**；auto、ask-each | next compaction | 首次选择写事件；cancel 不持久化伪偏好；只决定 model request consent，执行 Model 仍由 AL06-30；B/C 下禁止出现 |
| WorkspaceAcknowledgement | 缺失表示未确认 | **仅 TS-14 选 C 时存在**；acknowledged + exact workspace identity/schema binding | Context open/resume | identity/path/schema 任一不匹配即失效并重新询问；只减少提示，不授予能力，也不形成跨 Context trust registry |
| MaxModelRequestsOverride | inherit | 1..INI effective 值 | next-turn | 仅 M05-06 选 B/C 且 AL06-09 选 A/B 时存在；只允许下调；AQ-159 |
| MaxToolCallsOverride | inherit | 0..INI effective 值 | next-turn | 仅 M05-06 选 B/C 且 AL06-09 选 A/B 时存在；只允许下调；AQ-159 |
| MaxTurnTimeMsOverride | inherit | 1..INI effective 值 | next-turn | 仅 M05-06 选 B/C 且 AL06-09 选 A/B 时存在；只允许下调；AQ-159 |
| MaxTurnTokensOverride | inherit | positive integer、且不高于 INI effective 值 | next-turn | 仅 M05-06 选 B/C 且 AL06-09 选 A/B 时存在；usage 定义必须先确认 |
| CompactThresholdOverride | inherit | 0 < value <= INI effective threshold，或 inherit | next-turn | 仅 M05-06 选 B/C 且 AL06-11 选 A/B 时存在；数值更低表示更早执行 structured summary/extractive checkpoint；AQ-159、COMP-02 |
| MaxQueuedMessagesOverride | inherit | **仅 M05-06 C 时存在**；0..Runtime/有效 queue cap | next queue admission | 限制本 Context 未消费 queue 项；0 禁止新增但不删除已 durable 项；不能扩大 AL06 queue policy |
| MaxSideRequestsOverride | inherit | **仅 M05-06 C 时存在**；0..Runtime/有效 outstanding-side cap | next side admission | pending + active 合计；0 禁止新增，不能扩大 AL06-06 的并发/排队路线 |
| ToolPreviewKiBOverride | inherit | **仅 M05-06 C 时存在**；0..有效 TUI preview cap | next display block | 只减少临时预览；不改变 canonical tool result、XML、`.details` 可声明的实际保留边界 |
| DiagnosticDetailOverride | inherit | **仅 M05-06 C 时存在**；inherit、minimal | next diagnostic event | minimal 只减少 optional detail；阻断错误、canonical events、恢复证据和 typed outcome 不能被隐藏 |

预算/偏好覆盖、AL06 条件字段和 TS-14 C 的 acknowledgement 都是候选扩展，不是用户已经确认的字段。无条件最小白名单只有 CurrentModel、CurrentPermission、DoubleCheckOverride 和 ContextPrompt；M05-06 B/C 共享四个 budget/threshold override，只有 C 再增加精确四项 session preference；`ReviewModelMapping`、`CompactionConsent`、`WorkspaceAcknowledgement` 也只有选中对应路线才进入 schema，不能由旧 XML 自行启用功能或授予信任。

### 明确禁止 XML 覆盖

- Schema 本身和 Runtime hard limits；
- SystemPrompt；
- Agent.Autonomy（TS-18 B 时只允许保存有效 snapshot，不允许 XML override）；
- Endpoint、Protocol、RemoteModel、Key、AuthMode、headers 与 Model retry；
- Proxy、CA 和所有 Network 字段；
- Permission profile 的任何能力定义；
- Exec 环境、timeout 和代理暴露；
- 数据根、锁、原子提交和修复策略。

### 快照不等于覆盖

为了让另一台机器解释历史，XML 可以保存当时有效的非秘密 Model、Permission、Prompt、工具 schema 和预算 snapshot。恢复时仍要把 snapshot 映射到目标机当前 INI；snapshot 不会在目标机临时创建一个有 Key 的 Model，也不能越过本机 Permission。

M05-20 还需冻结 conditional metadata 的目的地矩阵；当前推荐候选不是“一律保存”或“一律删除”，而是 purpose-specific projection：

| 目的地 | 候选最小信息 | 始终禁止 |
| --- | --- | --- |
| Context XML / 跨机接盘 | Protocol、RemoteModel、窗口、Streaming/Tools、允许的 Endpoint origin/path 投影、public effective digest、切换前后关系 | Key、SecretHeader 值、Proxy credential、secret query、private source digest |
| Stage 3 reviewer | 判断名称/权限/能力一致性所需的脱敏结构；exact internal hostname 默认最小化 | Key、完整 URL query、NoProxy 明文、Context/工作区正文 |
| support/sanitized export | 用户预览后选择的诊断字段、版本、typed errors 和 secret-aware projection | 未经预览的正文、secret、private digest、无限 raw body |
| Model request | 该 request purpose 必需的 Prompt/消息/工具与连接 metadata | 不属于该 purpose 的其他 Context、配置浏览内容和 support 数据 |

字段的 `conditional` 分类必须在 typed schema 中列出每个目的地规则；不能只在 renderer 临时用字符串替换“看起来像 token”的内容。

## 明文 Key：已经接受的风险与仍需关闭的泄漏面

项目负责人已经选择 Key 明文保存在主 INI。这意味着 yaca 不承诺“磁盘被读取后 Key 仍保密”。实现仍应缩小其他泄漏面：

- config.ini 创建后尽力设置仅当前用户可读；FAT、旧 Windows ACL 或共享目录无法兑现时 self-test 必须明确警告。
- show-config、REPL 列表、错误、diff、XML、日志、支持输出和剪贴板默认只显示 configured/replace/clear，不回显原值。
- Key 不参与 Model snapshot digest，避免形成可离线比对的凭据指纹。
- Key 不进入 argv、shell 命令、环境变量、Context XML、普通 stderr/stdout。
- Key 输入不写终端历史；终端无法安全隐藏输入时必须先说明能力限制。
- 进程内字符串、崩溃 dump、swap、同用户恶意进程和已经感染的机器仍可能读取 Key，UI masking 不是加密。
- ProxyUrl userinfo、SecretHeader、EnvironmentSet 中标为 secret 的值使用同一秘密策略。
- 用户自己把 Key 粘进消息或 shell 命令属于 conversation/tool content；“完整历史”和自动脱敏存在冲突，应在导出时显著预览，不能声称已自动识别所有秘密。
- 配置 backup/previous-valid 复制了明文 Key，因此它们也是 secret 配置文件：使用同级权限、固定位置、有界数量和显式清除/恢复规则；不得把备份路径或 digest 当普通诊断上传。

## 把 Key 交给 curl 的三个候选方案

### A. curl 配置经 stdin，request body 使用受保护临时文件（CLI curl 首选候选）

流程：

1. yaca 把 Key、proxy credential 和 secret headers 写入 curl 的 stdin config stream。
2. 规范 JSON request body 写入同一受控临时目录中的 no-replace 文件。
3. curl 从 body 文件读取请求，stdout/stderr 由 Process adapter 有界流式捕获。
4. 请求结束后清理 body；崩溃恢复识别并安全删除残留。

优点：

- Key 不进入 argv、环境变量或磁盘；
- 可继续使用随包 curl；
- stdout 可以流式处理。

代价：

- 对话/request body 暂时落盘，可能含用户秘密；
- Windows XP 上临时文件权限、no-replace、清理和杀进程必须实测；
- config stdin 与 curl 生命周期要避免写入错误日志。

### B. request body 经 stdin，secret curl config 使用受保护临时文件

优点：

- 完整对话 body 不落盘；
- request 可直接流向 curl。

代价：

- Key/代理密码进入临时文件，泄漏后果更高；
- 必须证明创建权限、删除和崩溃残留；
- 配置文件路径可能出现在 argv，虽然内容不应出现。

在“明文只长期保存在 INI”之外又产生一份 Key 临时副本，因此不推荐作为默认。

### C. 极小 native libcurl/helper 在内存中接收 headers 和 body

优点：

- Key 与 request body 都不需要 argv、环境或临时文件；
- 流式、取消、headers/status 通道和 backpressure 更容易形成结构化 ABI。

代价：

- 增加 Windows XP x86 与 CentOS 7 的 native 构建、TLS、libcurl ABI、供应链和 luainstaller 打包负担；
- helper 崩溃与内存清理仍需测试；
- 原生层必须保持窄接口，不能拥有 Model 或 AgentLoop 状态。

当前候选建议：若继续采用 CLI curl，先验证 A；若 02/03/22 号系统最终已经需要 native helper，再比较 C。最终选择必须和 AQ-043（临时文件）、AQ-219、AQ-223、AQ-250 一起确认。绝不采用“Key 直接放 curl argv”或“把 Key 放通用子进程环境”。

## INI 语法与往返候选

### 基础语法

- 文件编码固定 UTF-8；reader 可接受一个 UTF-8 BOM，writer 候选不生成 BOM。
- section/key 名、枚举和机器字段固定 ASCII；用户文本值仍可为 UTF-8，服从 AQ-045。
- section/key 名候选大小写敏感，以便准确发现拼写错误；选择器的 ASCII 大小写规则另见 AQ-199。
- bool 只接受 true/false；整数只接受 ASCII 十进制；单位写在字段名。
- 字符串使用双引号并定义反斜杠转义；不接受依赖平台的本地代码页。
- 分号或井号只在引号外开始注释；精确选择仍待 FMT-04。
- 重复 singleton section、重复非列表 key 和同名 Model/Permission section 是硬错误。
- 物理 section 顺序保留；第一个 Permission 与第一个 Model 的顺序具有默认选择语义。

### 多行文本

需要支持全局 SystemPrompt，但不值得实现多个含糊的 INI continuation 方言。三种候选：

1. 双引号字符串内使用明确的反斜杠 n 转义；parser 最简单、跨平台最确定，REPL 可用真正多行编辑后编码。当前推荐。
2. 自定义三引号 block；手改更直观，但必须定义结束标记转义、缩进、换行和注释。
3. 行尾反斜杠 continuation；容易与 Windows 路径、尾随空格和注释混淆，不推荐。

在 AQ-200/FMT-04 决定前，模板和实现不能各选一种。

### 注释、顺序与未知字段

若 AQ-133 确认支持手工编辑，推荐 parser 保留 concrete syntax tree：

- 未修改字段的注释、空行、原始顺序和换行风格继续存在；
- REPL 只修改目标节点；新增字段放到 schema 定义的位置；
- move-first/move-before/move-after 是显式事务，并在保存前显示默认项变化；
- secret diff 只显示 unchanged/replaced/cleared；
- disabled Model 草稿也保留，不因暂时未配置 Key 被自动删除。

未知字段不能简单忽略，精确宽严由 M05-28 选择：

- 缺失 required、疑似拼错和安全/权限/secret/network/process unknown 必须阻断；错误包含 section/key/行号，parser/REPL 仍保留原文供修复。
- 明确废弃字段由迁移表给出 warning/error 和替代字段，不能与新字段同时生效。
- config 的 major 高于程序支持时只读诊断或拒绝，绝不重写。
- 已登记 future namespace 或 non-security unknown 能否往返保留按 M05-28 A/B/C；保留只表示不丢原文，从不表示字段生效。

这既避免一个拼错的安全字段被静默忽略，也避免 REPL 为了报错就毁掉用户手写内容。

### 手工编辑与 REPL 的事务

手工编辑是外部写者；REPL 保存必须执行：

1. 读取原始 bytes、文件身份和 digest。
2. 解析成保留注释/顺序的草稿树。
3. 所有编辑只改内存草稿，显示 dirty。
4. 运行逐字段和完整跨字段校验。
5. 显示脱敏 diff、第一 Model/Permission 变化和生效点。
6. 保存前重新检查文件身份/digest；外部改变后的 reload/compare/merge/阻断统一服从 F4-01，不由 unknown-field 策略另选一套。
7. 在同目录创建 no-replace 临时文件，写完、flush、重新解析验证。
8. 使用目标平台已证明的安全替换协议发布；失败保持旧文件。
9. 原子发布需要的受控 temp/recovery 服从写入协议；是否另外产生含 Key 的用户 backup/export 只由 M05-42 决定，任何这种副本都按完整 secret 文件处理。

普通 Agent 启动必须严格加载完整配置。首次 model-repl、config-repl 和 self-test 静态阶段则需要一个只依赖内置 schema 的 bootstrap reader，否则主配置缺失/损坏时无法创建或修复第一份配置。这个管理入口不启动 Agent、不联网，符合 B-02 的“没有首次向导”；边界仍待 AQ-012、AQ-013、AQ-217 确认。

### reset 不是 parser 默认值操作

M05-18 只冻结 non-secret `config reset` 的字段范围；M05-42 独占含 Key 的 backup/export，Context purge 由 CX/F4 管理事务独占。无论选择哪项，reset 都不是“把内存 table 清空后直接 save”。候选事务必须先生成：

~~~text
reset plan
  targets: exact config generation and sections
  non-secret defaults to rebuild
  Model/Key/Permission disposition: preserved
  Context references affected: report only, never purge
  secret-bearing backup/export: separate M05-42 action only
  -> redacted confirmation
  -> stale generation check
  -> one atomic ManagementMutation commit
  -> completed | failed | recovery-required
~~~

默认候选不清除 Key、不删除 Context、不递归删除 `__yaca__`，也不把“修复配置”与“销毁历史”合成一个确认。reset、Model 删除/重排、migration 和 config import 共用 F4-09 的 `ManagementMutation` 正确性协议，但各自仍有独立 typed plan。

## 完整跨字段与生命周期校验表

严重度候选：

- error：普通 Agent 不得启动或不得保存草稿。
- warning：配置可以使用，但用户必须看见风险或能力降级。
- advisory：只由 self-test 第三阶段给建议，绝不改变确定性结果。

| ID | 条件 | 候选严重度与处理 | 关联 |
| --- | --- | --- | --- |
| CV-001 | SchemaMajor/Minor 缺失、越界或程序不支持 | error；旧程序不写新版配置 | AQ-185、CFG-07 |
| CV-002 | singleton section 缺失/重复 | error；精确指出 section | FMT-04、CFG-08 |
| CV-003 | 未知 key/section 或废弃字段与新字段同时出现 | error 或 migration warning；安全字段绝不静默忽略 | CFG-08、CFG-22 |
| CV-004 | bool/int/decimal/enum/string 不符合规范拼写 | error；显示脱敏实际值和期望类型 | AQ-200、AQ-201 |
| CV-005 | Model/Permission 长名或简称在各自命名空间冲突 | error；不按文件顺序猜 | AQ-135、AQ-199 |
| CV-006 | 没有任何 Permission section | error | CFG-06 |
| CV-007 | 没有任何 Model section | 管理入口可打开；普通 Agent error | AQ-217、CFG-09 |
| CV-008 | 第一 Model disabled 或连接字段无效 | 普通 Agent error；不静默跳到下一个 | AQ-134 |
| CV-009 | disabled Model 字段类型/名称非法 | error；disabled 不是跳过 parser | CFG-08 |
| CV-010 | enabled Model 缺 Protocol/Endpoint/RemoteModel | error | AQ-136、AQ-138 |
| CV-011 | AuthMode=protocol 但协议要求 Key 且 Key 空 | error；none 不能从空 Key 自动推断 | AQ-137 |
| CV-012 | Endpoint 不是允许的绝对 http/https URL | error | NET-10、AQ-220 |
| CV-013 | Endpoint 含 userinfo、secret query 或跨 origin redirect 行为不明确 | warning/error 按策略；值脱敏 | AQ-219、AQ-220、SAFE-09 |
| CV-014 | Protocol 不受发行物支持，或 PublicReasoning/adapter option 声明了该 adapter 没有的能力 | error；不联网猜协议/能力，也不把 hidden reasoning 当兼容 fallback | AQ-138、AQ-218、M05-40 |
| CV-015 | Streaming=force 但 protocol/Model 明确不支持 | error；不降成 try/off | AQ-139 |
| CV-016 | M05-03 A/C 的 Tools 声明与 adapter 静态 schema 不兼容、B 的 Protocol adapter manifest 不是 native，或 required-native 的显式在线证据失败 | 静态不兼容为 error；B 的未测试/普通 observation failure 只 support/warn，不把联网测试变成启用 gate；不做文本 emulation | AQ-144、M05-03、D-031 |
| CV-017 | ContextLength/MaxOutputTokens 非正数或 output >= context | error | AQ-142、MODEL-08 |
| CV-018 | 已知 context 无法容纳固定 Prompt/tool schema/output reserve | error/warning；不得先发请求再碰运气 | AQ-062、COMP-05 |
| CV-019 | Connect/FirstEvent/Idle/Total timeout 越界或相互矛盾 | error；具体不等式由 NET-05 冻结 | AQ-141 |
| CV-020 | RetryMaxDelayMs < RetryBaseDelayMs | error | AQ-140 |
| CV-021 | Retry 最坏等待或单 request total 明显越过 AL06-09 的 turn 边界 | error/warning；A/B 对照 MaxTurnTimeMs，C 对照发行物固定 safety cap；Runtime始终截断 | LOOP-27、AL06-09 |
| CV-022 | RetryCount 超过 RuntimeMax 或配置成无限 | error | AQ-140、AQ-197 |
| CV-023 | PublicHeader/SecretHeader 名非法、重复冲突或覆盖 Runtime 核心 header | error | AQ-219、MODEL-11 |
| CV-024 | AdapterOption/GenerationIntent/PublicHeader/SecretHeader/CustomPrompt 尝试覆盖 model/messages/tools/stream/auth/Runtime limit；对应 M05-05/23 或 PP-11 方案未启用却出现条件字段；或 adapter 无法映射 GenerationIntent | error；PP-11 C 的 CustomPrompt 也只是用户 instruction component，不能改写 serializer/role/tool/control | M05-05、M05-23、PP-11、AQ-219 |
| CV-025 | Model 或 DirectHttp ProxyMode=explicit，但对应 ProxyUrl 空/非法 | error；两个 policy 不互相借值 | AQ-145、TS-11 |
| CV-026 | Model 或 DirectHttp ProxyMode=off/environment 时，对应 explicit ProxyUrl 非空 | error；不能悄悄使用，也不能跨 policy 复制 credential | AQ-145、TS-11 |
| CV-027 | NoProxy/DirectHttpNoProxy 规则非法、混用未声明语法或被错误用于另一 transport | error | NET-04、TS-11 |
| CV-028 | Model 或 DirectHttp CaMode 含 custom，但对应 CaFile 空、不可读或变化 | error before request；两个 trust policy 独立 snapshot | AQ-146、TS-11 |
| CV-029 | 配置试图关闭 TLS 验证 | unknown field/error；不提供这种 schema | AQ-146 |
| CV-030 | 所选 M05-14 字段集不完整/混入另一分支，任一 transport limit 为 0/超 RuntimeMax，或 compressed/decompressed/ratio/logical-response 组合无法容纳最小协议消息 | error；B 的九字段与 Runtime hard cap 机械对齐 | AQ-245、M05-14 |
| CV-031 | AL06-09 A/B 的 Agent turn budget 为 0/负数/超 RuntimeMax，或 C 下出现四个用户 turn budget 字段 | error；只有 A/B 明确允许 0 的 MaxToolCalls 例外；C 使用版本化固定 cap，不接受 orphan 字段 | AQ-153、AL06-09 |
| CV-032 | AL06-27 A 下所需局部 cap 缺失/越界（termination 始终；action 仅 AL06-07 A/B）；AL06-07 C 下出现 MaxActionReviewRounds；AL06-27 B 下 MaxDoubleCheckRequests 缺失/越界；C 下出现上述用户字段 | error；局部 cap 始终再受 AL06-09 所选 turn 边界约束：A/B 可配置、C 固定 | AQ-019 至 AQ-023、AL06-07、AL06-09、AL06-27 |
| CV-033 | AL06-09 A/B 的 MaxTurnTokens 小于固定 Prompt/工具 schema/最小输出预算 | error/warning；不能开始 turn；C 对固定 safety cap 做同类发行 fixture，不读取该字段 | AQ-062、AQ-153、AL06-09 |
| CV-034 | MaxCost 被配置但没有可信价格 schema | error/unknown field；当前不支持硬费用预算 | MODEL-09 |
| CV-035 | Exec TimeoutMs > AL06-09 的可配置或固定 turn deadline | error/warning；调用时取更早 deadline；终止 grace 是 adapter/manifest release gate，不读取配置 | AQ-126、AL06-09 |
| CV-036 | MaxOutputKiB 或条件环境列表超限 | error；输出 decoder 是 Runtime `auto` 契约，不读取配置 | AQ-123 至 AQ-125 |
| CV-037 | EnvironmentSet/Unset 同名冲突、名称非法或覆盖 Runtime 保留变量 | error | AQ-148 |
| CV-038 | 出现已排除的 ExposeConfiguredProxy，或 raw-shell environment 字段尝试引用全局 ProxyUrl/credential | unknown/deprecated error；全局 proxy 永不自动传播给 raw shell | M05-15、NET-11、SAFE-09 |
| CV-039 | AL06-11 A/B 的 CompactThreshold 不在开区间 (0,1)，或 C 下出现该字段/override | error；C 的 latest-fit view 只消费 Runtime 计算的 effective reserve，不伪造 compaction trigger | COMP-02、AL06-11 |
| CV-040 | Runtime 计算的 effective reserve、Model 输出与 Prompt/tool 余量合计超过 ContextLength；AL06-11 B/C 下出现 CompactionModel/CompactionConsent；或 CompactionModel 无法容纳最小请求 | error；提示更大 Model/调整真实配置；不允许无消费者的 compaction 字段反向启用压缩，也不允许 INI/XML 提供 reserve | AQ-156、AQ-240、AL06-11、AL06-30、AL06-34 |
| CV-041 | CX-11 B 的三个 quota 缺失/非正/超过发行硬门，A/C 下出现这些字段；或 C 的 AutoPurgeTrash/TrashGraceDays 条件不闭合 | error；A 无用户 quota/purge 字段，B/C 字段族互斥；auto purge 无 durable trashed_at/预告/稳定 scan 时 fail closed；resolver scan cap 属于 manifest release gate | CTX-12、PERF-02、CX-11 |
| CV-042 | Permission 能力缺失或不是 deny/confirm/allow | error；不补“安全默认”掩盖旧 schema | AQ-149、AQ-150 |
| CV-043 | Permission 同时保留旧 Allow*/Confirm* 与新三态字段 | migration error；禁止双重求值 | CFG-16、AQ-150 |
| CV-044 | Permission section 含 profile 内 DoubleCheck 或名为 Cautious 的旧内置语义 | migration diagnostic；不自动改变用户自定义同名 section | D-021、CFG-16 |
| CV-045 | DirectNetwork=deny 但 Shell=allow | warning：shell 仍可能联网；不得声称隔离 | AQ-224、NET-11 |
| CV-046 | Read/Write/Delete=deny 但 Shell=allow | warning：shell 仍可能绕过细粒度直接工具策略 | AQ-224 |
| CV-047 | OutsideWorkspace=deny 但 Shell=allow | warning：Runtime不能证明 raw command 不越界 | AQ-224、SAFE-06 |
| CV-048 | XML 覆盖不在无条件白名单，或 AL06/M05/TS 条件未启用却出现 ReviewModelMapping、CompactionConsent、WorkspaceAcknowledgement、预算覆盖 | error/read-only diagnostic；绝不合并任意 key，也不由数据文件反向启用功能/信任 | AQ-159、AL06-08、AL06-34、TS-14 |
| CV-049 | XML CurrentModel/Permission/ReviewModelMapping 引用不存在，或 INI ReviewModel/CompactionModel 引用不存在 | 只读打开或对应 purpose 转 waiting-user 并提示显式映射/修复；不静默 fallback | AQ-236、CTX-27、AL06-08、AL06-30 |
| CV-050 | XML 选择的 Permission 或 DoubleCheck 比本机默认更宽松 | 继续前显著确认；精确策略未决 | SAFE-04、CTX-27 |
| CV-051 | XML snapshot 含 Key、secret header、proxy credential 或 secret digest | error/quarantine；不得载入为配置 | AQ-040、AQ-168 |
| CV-052 | XML budget/threshold override 在 M05-06 A、turn override 在 AL06-09 C、threshold override 在 AL06-11 C 下出现；M05-06 B 下出现 C-only session preference；或任一允许项高于有效上限/使用未登记值 | error；不 clamp 后继续，也不允许外来 XML 提高预算、扩大 queue/side 或减少 canonical 事实 | CCA-Q-11、AQ-159、M05-06、AL06-09、AL06-11 |
| CV-053 | ContextPrompt 超大小/Token 上限或编码无效 | error；不静默截断后当完整 Prompt | AQ-062、AQ-063 |
| CV-054 | LogLevel 较低导致实现试图不保存 canonical 事实 | 实现/契约测试失败，不是用户配置错误 | CTX-01、DIAG-03 |
| CV-055 | self-test LLM 认为名称与行为“不合理” | advisory only；不覆盖以上确定性结果 | AQ-202 |
| CV-056 | Model Endpoint 使用 HTTP/发生 scheme downgrade，或 DirectHttpAllowedOrigin/redirect 违反 exact-origin、loopback-HTTP、no-downgrade 规则 | Model 按 M05-13；direct HTTP 非 loopback HTTP、registered secret、cross-origin redirect 或 downgrade 一律 error | CCA-Q-01、NET-13、AQ-220、TS-11 |
| CV-057 | MaxConcurrentRequests/MinRequestIntervalMs 非法、超 RuntimeMax，或 Retry-After/cooldown 等待越过 request/turn deadline | error 或 typed local scheduling timeout；不报告为 provider 拒绝 | CCA-Q-02、AQ-362、MODEL-15 |
| CV-058 | optional scalar 使用未注册 sentinel、数字字段用 false 同时表达关闭/未知/无限，或 PJ-13 分支混入/缺失 `AutoJumpToDir` 与 `ResumeDirectory` | error + versioned migration diagnostic；两种 resume 字段互斥，旧 bool 迁到 C 必须显示转换候选，不交给消费者猜 | CCA-Q-10、AQ-200、M05-19、PJ-13 |
| CV-059 | generic CLI override 尝试覆盖未注册字段、secret、endpoint、Permission 定义或 unknown key | M05-22 A 时 unknown option；B 时只接受逐字段 typed allowlist；永不绕过完整 validator | CCA-Q-15、CFG-01、CFG-12 |
| CV-060 | public effective digest、XML、status/support 中出现 private source digest 或 secret-derived bytes | 实现/secret-canary 失败；不得发布该 transition/snapshot | SAFE-09、HCFG-02 |
| CV-061 | reload 检测到新 INI 无效、删除、半写，或 current Model/Permission 失效 | 阻止新 turn并进入只读修复/mapping；active turn 保持旧 snapshot；不静默 last-known-good 继续 | AQ-361、CFG-24、F4-01 |
| CV-062 | reset/migration/backup/export 会复制或清除 Key，或 config reset 试图顺带 purge Context，但 plan 未按 M05-18/M05-42/CX owner 分离 secret 副本、引用、stale generation 与恢复路径 | ManagementMutation validation error；不提交 | CCA-Q-09、AQ-132、ARCH-05、M05-18、M05-42 |
| CV-063 | conditional metadata 被投影到 XML/reviewer/support/request 之外的目的地，目的地策略未登记，或 Autonomy/CustomPrompt/workspace acknowledgement 被赋予其 owner 禁止的权限、安全或协议含义 | error/contract-test failure；按 typed data-classification matrix 最小化 | CCA-Q-12、AQ-358、M05-20、PP-11、TS-14、TS-18 |
| CV-064 | internal curl/Git/helper 读取宿主 default config、cwd/PATH 同名工具、隐式 CA/proxy、pager/editor/external diff/textconv/credential helper | self-test/release gate failure；不是可忽略 warning 或用户配置选项 | PROC-13、HCFG-04 |
| CV-065 | compressed/decompressed/error/tool-argument/aggregate response 或多个用户上限组合可越过 Runtime hard cap/Win32 x86 内存预算 | error/release gate failure；字段缺失或任何已登记 sentinel 也不得解除 hard cap | AQ-245、AQ-322、HCFG-03 |

`TerminateGraceMs`、`OutputEncoding`、`CompactReserveTokens`、`MaxScanEntries` 若出现在 INI 或 XML，统一由 CV-003 当作 unknown/deprecated 字段处理；不得为了兼容旧草案而把它们悄悄恢复为可调配置。它们各自的 adapter/Runtime/manifest 值与技术证明属于发行 gate，不另造一个假的用户字段校验。

## 字段生效与快照总表

| 字段类别 | active turn 中编辑 | 下一 turn | XML 保存 |
| --- | --- | --- | --- |
| SystemPrompt | 不改变当前 turn | 使用新 Prompt snapshot | 保存历史有效 Prompt snapshot；不作为 XML override |
| Model definition | 不改变在途/当前 turn | 若仍选择该逻辑名，先做能力/隐私预检后使用新 snapshot | 保存非秘密旧/新 snapshot 与切换/映射事件 |
| CurrentModel | 忙时记为 pending | 下一 turn 生效 | 白名单 selector |
| Permission definition | 不改变当前授权/turn | 下一 turn 使用新 policy snapshot | 保存历史 snapshot；不复制定义为本机配置 |
| CurrentPermission | 忙时记为 pending | 下一 turn 生效 | 白名单 selector |
| DoubleCheck | 不改变当前 turn；是否允许审批前立即提高限制待决 | 下一 turn | tri-state override + 最终值 |
| Agent budgets | 当前 turn 继续用冻结值 | 下一 turn | snapshot；白名单 override 待决 |
| Network/Model retry | 不改变在途 attempt | 下一 request/turn | 每个 request 保存实际非秘密选项和 attempt 事实 |
| DirectHttp policy（仅 TS-11 B/C） | 不改变已启动 direct HTTP call | 下一 direct HTTP call | operation 保存 exact origin、CA/proxy/redirect non-secret snapshot；credential 永不复制 Model 值或进入 XML |
| Model scheduler 字段 | 不移动已经 admission 的 request；等待项继续使用入队 generation | 下一次 scheduler admission | 保存声明值、实际等待/cooldown 原因与非秘密 Model identity |
| Exec | 不改变已启动进程 | 下一 tool call/turn | 保存有效非秘密值 |
| ContextPrompt | 当前候选不改变 active turn | 下一 turn | 当前值 + 变更事件 + snapshot |
| LogLevel | 只有完整新 generation 载入后才影响以后可选诊断 | 继续有效 | 保存当时级别；canonical 事件不受影响 |
| 外部 INI bytes | active turn 永不逐字段重读；按 F4-01 排队 reload 或在 safe boundary 发现 | 完整验证后一次替换 generation；无效则阻止新 turn | 只写 non-secret transition/public digest，不写 private digest |
| 命名 session action | 按动作契约形成 pending/事件，不开放任意 key | 声明的 next-turn/next-request | 只有白名单 selector/override 写 XML；generic `--set` 待 M05-22 |

## 仍需项目负责人明确的高杠杆选择

1. DoubleCheck 的 INI 默认是 false 还是 true；Imported XML 能否降低本机默认。
2. XML 最小覆盖白名单是否只有 Model、Permission、DoubleCheck、ContextPrompt，还是还允许预算/压缩阈值覆盖。
3. Permission 是否采用 M05-16 的粗粒度 outside、拆分 outside 或再增加 SensitiveRead；若增加，TS-21 选择分类来源。DirectNetwork 只随 TS-11 的 direct HTTP tool 存在。
4. raw shell 允许即意味着可能读写/联网/越界的宽能力说明是否接受。
5. Model 首版协议是否只有 openai-chat；Endpoint 是完整 URL 还是 base URL。
6. AuthMode 是否需要显式字段；M05-13 对 HTTP loopback、Key、proxy 与 redirect downgrade 采用哪条策略。
7. Tools 是否只支持 native/off；首版是否拒绝主 Agent 使用 Tools=off Model；在线 observation 是否只作为 support/warn。
8. Model generation options 采用 adapter typed optional whitelist、可证明映射的跨协议 intent，还是完全使用 provider default；缺失是否明确“不发送”。
9. Network 默认 bundled CA、ProxyMode=environment 是否接受。
10. Exec 是否保持最小全局 raw-shell section；M05-15 是否删除 EnvironmentSet/Unset/ExposeProxy。
11. SystemPrompt 多行采用反斜杠 n、三引号还是其他唯一语法；optional scalar 是否采用 M05-19 的唯一 sentinel。
12. 手工编辑是否成为正式支持入口，以及 REPL 是否必须保留注释/顺序。
13. M05-18 的 non-secret config reset 范围，以及 M05-42 是否另外提供会复制明文 Key 的 backup/export；Context purge 始终由 CX/F4 管理动作决定。
14. 是否暂不做费用硬预算与自动 preimage/undo，保持首版配置和单 XML 简洁。
15. M05-14 选择公开哪些 transport limits；MaxContextMiB、Network buffer、Exec output 和循环默认数字在 XP/CentOS 7 fixture 后怎样冻结。
16. F4-01 选择显式 reload/restart、safe-boundary 检测还是即时 watcher。
17. F4-02 是否加入 MaxConcurrentRequests/MinRequestIntervalMs，并怎样共享 Retry-After/cooldown。
18. M05-17 保留 LogLevel 还是删除；若保留，其唯一目的地是否只为终端和 XML optional diagnostics。
19. M05-20 怎样分别投影 conditional metadata 到 XML、reviewer、support 和 Model request。
20. M05-21 是否存在 Model/Permission Color 字段；实际语义色与 fallback 由 TU-02 独占。
21. M05-22 是否拒绝 generic `--set`，只保留注册过的命名 session actions。
22. M05-40 是否保存 provider 明确公开的 reasoning summary，以及 M05-41 的 online self-test 是否复现配置的 retry/fallback。
23. M05-12 是每次显式选择 Stage 3 reviewer，还是使用条件字段 `SelfTestReviewerModel`/全部通过模型。
24. TS-11 是否增加 direct HTTP；若增加，是否接受独立 `DirectHttp*` CA/proxy/no-proxy/redirect/exact-origin 字段族及不复用 Model credential 的边界。

## 从候选到正式 schema 的验收物

负责人确认上述选择后，配置子系统设计至少应生成：

- 最终字段注册表和版本迁移表；
- 一份合法的最小配置、一份完整注释配置和每类无效 fixture；
- INI grammar 与多行/转义测试向量；
- Context XML override whitelist 与安全降级 fixture；
- secret 字段列表和 show-config/REPL/XML/curl 泄漏测试；
- 全部 CV-* 跨字段校验的 table-driven 测试；
- 配置草稿、外部修改冲突、临时写入、flush、替换和恢复测试；
- self-test 三阶段输入/输出和不会隐式联网的测试；
- 文档、模板、REPL help 和 typed schema 一致性检查。

在这些证据完成前，本文只能叫“候选注册表”，不能据此宣称配置已经完整或可运行。
