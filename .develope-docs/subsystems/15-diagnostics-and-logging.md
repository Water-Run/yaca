# 15 诊断、自检与日志

更新日期：2026-08-29

状态：产品契约与规格侧已冻结；[`contracts/diagnostics.lua`](../contracts/diagnostics.lua) 已提供稳定 error/exit/check registry 与依赖图，目标平台输出、脱敏和真实 Model 证据待测试

## 职责

检查平台能力、配置、模型连通性、随包工具、CA、目录权限和上下文完整性，并把可脱敏、可定位的问题投影到终端、self-test/support stdout 或健康 Context XML。v0.1 不建立独立日志文件系统。

## 边界

- 确定性检查优先；LLM 深度检查只能补充，不能替代。
- canonical 诊断事实不应与 TUI 渲染耦合；物理长期数据仍遵守当前“只有 INI/XML”的项目约束。
- 各子系统返回结构化错误，本系统负责聚合与呈现建议。
- CLI、TUI、self-test 和 `.details` 消费同一 error/action registry；入口不同不能产生不同错误含义或修复授权。

## 设计要求

- 每个用户可见错误都有稳定 English/ASCII error ID、简短摘要和可执行下一步；`.details` 展示同一错误的阶段、retryable 状态、安全技术 cause、已保存范围和可能的 unknown 副作用，不建立第二条诊断事实。
- 默认不记录 API key、完整请求头或敏感文件内容。
- XML 内诊断/审计事件与正文一样有明确上限、脱敏和等级；不能靠关闭 LogLevel 删除恢复所需事实。
- 自检区分警告、不可用能力与阻断性失败。
- 自动 retry 必须显示稳定错误 ID、原因和当前次数，并可取消；同一根因只显示一次主错误，后续层通过 cause 链引用它。

## 三阶段 Self-Test

三个阶段严格按 `Stage 1 -> Stage 2 -> Stage 3` 执行；用户选择的阶段上限、Model/check 范围和合法排除都必须进入同一 self-test semantic action。TUI 选单与 CLI 参数只是同一 typed request 的不同投影，检查 ID、依赖、结果和退出类别完全一致；这项 CLI parity 不开放公共 headless/remote controller。非 TTY 不得默认批准联网或费用：无本次显式 online-consent 时 Stage≥2 硬失败（D-062）。

### Stage 1：静态、离线、确定性

Stage 1 不调用 Model、不探测 endpoint，且在主配置缺失/损坏时仍可运行其 bootstrap 子集。除平台、发行组件、schema/INI、路径/文件能力和 CA 静态检查外，必须包含有界 Context Catalog 检查：

- 验证 `__yaca__/CONTEXT/` 镜像路径能否无损解码为每个 Context 唯一、存在且可进入的 workspace root；XML 内不存在可覆盖父目录的 root authority 字段。
- 以最小 XML header 检查 schema/version、canonical `Name/CreatedAt/UpdatedAt`、basename 一致性、损坏候选、临时/恢复残留和不可读范围，不为此加载完整长对话。
- 报告扫描的目录/Context 数、实际范围、hash 计算数、耗时、hard cap 与是否为 partial。Context 太多、目录或 hash 计算超过最低平台预算时给出明确 slow/cap 诊断；遇到 `ScanIncomplete`/`ScanLimit` 时不得声称全局健康。
- 活动 writer 的 Context 只检查无需打开正文即可证明的名称、路径、busy 和 PID/unknown 元数据；self-test 不借诊断越过 lease，也不执行 rename、rebind、delete、marker 修改或其他修复。

### Stage 2：真实连接与能力

只有 Stage 1 满足所选 Stage 2 的前置条件后才能进入。开始前显示将联网的 Model/endpoint、检查目的、最坏请求/Token/费用和合法排除，并取得对应 consent。每个被选 Model 的真实连接、协议、流式/工具等能力结果独立记录；取消、失败或排除不能伪造成通过，也不能让 Stage 3 使用未确认 Model。

### Stage 3：语义合理性 advisory

Stage 3 只能调用 Stage 2 已确认可用且由用户纳入范围的 Model。它可以检查配置语义、命名和常见拼写，其中 Permission 输入明确包括逻辑名称、`Description`、有界 `SystemPrompt` 和确定性 capability matrix；例如识别名为 `Readonly` 却允许宽 `Execute`，或名称/说明与实际矩阵明显相反。结果必须显示实际字段与依据并标记为 advisory：不能自动改配置、改 profile 名、授予/撤销能力，不能推翻 Stage 1/2 的确定性结果，也不能阻断一个仅因命名古怪但 schema 合法的配置。

## 上下文目录诊断

11 号上下文目录与应用服务的错误不能压成同一个“找不到上下文”。其中 Resolver 负责：

- （已取代）`AmbiguousName`：D-061 下短名不再产生该结果；`HashCollision` 须显示冲突候选的逻辑路径与 hash。
- `HashCollision` 明确说明发生碰撞，不能建议用户反复重试碰运气。
- `MatchedUnavailable` 区分损坏 XML 和匹配文件不可读。
- `ScanIncomplete` 列出未能读取的范围，不能在漏扫后声称全局不存在。

Resolver 已返回候选之后，`TargetChanged` 属于目标复核，`OpenConflict` 属于打开服务，`DestinationExists`/`LockConflict` 属于修改服务。浏览器展示后目标变化时应要求刷新并重新确认，但日志和退出码必须保留实际发生阶段。

当前 ContextHandle 对应 XML 被外部移动、删除、替换或改写时立即 fail-stop：停止新的模型请求、工具和 XML 提交，把 handle 标为 stale，并要求显式 refresh/self-fix/rebind/recovery/exit。`.status` 显示最后绑定路径、由该逻辑路径实时计算的 hash 和可证明的失效原因；程序不按名称、hash 或内容自动追踪移动目标。

自检可报告非法候选、临时文件残留、损坏 XML、路径映射冲突和扫描性能，但修复动作必须由对应 `context-repl` self-fix-program 另行明确选择，不能边检查边静默重命名、rebind、删除或清理 marker。永久 delete 没有 trash/restore 诊断分支。

## Config generation 诊断

Runtime 在每个顶层 `main`/`side` turn admission 前完整读取一次受大小上限约束的 INI bytes 并计算 digest。digest 未变时复用当前 immutable generation；变化时必须完整 parse、schema validate 和 cross-validate，成功才原子激活。活动 turn 及其工具、review、retry 始终保留旧 generation；新文件无效时拒绝下一 turn 并显示精确配置错误，不能悄悄回退后继续。

这里没有文件 watcher、轮询周期或 reload interval 配置。诊断应区分 `unchanged/reused`、`changed/activated` 和 `changed/rejected`，并只记录 public effective generation digest/非秘密版本引用与错误位置，不记录 private source digest、secret 值或完整敏感 INI。显式 self-test 在开始时取得自己的稳定配置快照；运行中配置变化留给下一次 self-test 或下一顶层 turn，不让 Stage 1/2/3 各读到不同 generation。

## 无第三种长期诊断文件

D-022/D-055 已确认长期文件只有 INI/XML。Context 已打开且健康可写时，恢复所需的 canonical 审计/诊断事实进入该 Context XML；配置缺失、schema 损坏、Context 尚未建立或 XML 已 stale/不可写时，fatal error 只写 stderr 并返回稳定 exit code。显式 self-test/support 只输出到 stdout；用户自行 shell redirect 属于 yaca 外部行为，不产生 yaca 管理的 artifact。

v0.1 不生成 standalone diagnostic XML、独立轮换日志、后台 spool、telemetry 或 diagnostic upload，也没有相关配置、endpoint、命令或空 loader。启动、定时器、support 和诊断都不得因此隐式联网。

`LogLevel` 只控制可丢弃的诊断细节和终端显示密度，不能删除消息、工具/审批/副作用、close outcome、unknown 或恢复所需事件。精确稳定 ID/severity/exit-class 表与脱敏 fixtures 属于规格和测试证明，不再是负责人产品候选。22 号关闭流程只提交 XML 中可提交的必要诊断并 best-effort flush stdout/stderr；stderr 本身没有持久保证。
