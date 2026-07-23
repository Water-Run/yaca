# 07 Agent 工具系统

状态：正式设计；产品能力由 `D-052` 确认，平台文件/进程原语仍须通过对应技术证明

## 职责与边界

本系统定义模型能够调用的固定工具 registry、版本化输入 envelope、调用 admission、规范结果和串行调度语义。v0.1 的 registry 精确为：

```text
list read search write patch rename delete exec
```

除此之外不注册 Git、HTTP、backup、undo、媒体、插件、MCP、hook 或第三方自定义工具。用户需要宿主程序时，由模型在 `Shell` Permission 允许后调用 `exec`；这不会把宿主程序升级为 yaca 的结构化工具保证。

职责分界固定如下：

- 08 号系统对已经通过 schema admission 的动作求值 Permission、DoubleCheck 和人工确认；工具描述与 Prompt 不能授予能力。
- 01 号系统提供规范路径、文件身份、no-replace、同目录临时文件、flush 和安全发布原语。
- 02 号系统执行 `exec` 并提供取消、deadline、stdout/stderr 和进程收口事实。
- 09 号 AgentLoop 分配本地 call/operation ID、保存 accepted batch 顺序，并保证调用与结果一一配对。
- 10 号 Context 系统持久化模型当时看到的 registry/schema digest、canonical accepted arguments、权限决定、operation intent 和真实或合成结果。
- 19 号系统从 operation/result 派生归属与 diff evidence；它不提供 backup、undo 或 rollback。

## 固定 ToolInputRegistry

每个工具都使用版本化 typed object envelope。共同外层至少绑定 tool name、schema version、provider call identity、本地 call identity 和 exact arguments；具体安全字段必须是 registry 已登记字段，unknown field、缺失 required field、错误类型、无效 Unicode、NUL、超限或无法无损跨 Protocol/XML 的值都在 accepted call 之前拒绝。

`exec` 仍是原始命令工具：它的 typed arguments 中有一个必填 `command` string，命令内容是 opaque bytes 对应的规范文本。Runtime 不分词、不改写、不插入 quoting、不从文本推断 Read/Write/Delete/Network/OutsideWorkspace，也不把命令内的 `cd` 解析成状态。可选 `cwd` 与只会收紧的 deadline 等外围字段仍是明确的 typed metadata，不改变 `command` 的 opaque 性质。

| Tool | v0.1 规范语义 | 明确不提供 |
| --- | --- | --- |
| `list` | 有界目录枚举；显式 depth/page/continuation；稳定排序；返回 type、相对路径和必要属性 | 宿主 `dir`/`ls` 文本、无界递归、特殊文件读取 |
| `read` | 对 ordinary text file 按 `start_line/max_lines` 读取；返回稳定行号、raw-byte digest、byte span、newline/encoding、next/eof | 把无效编码或 binary 用 replacement text 冒充正文 |
| `search` | 固定、版本化的文本查找方言；literal 是基线，已登记 regex 可显式使用；返回 file/line/column/snippet/truncated，稳定排序且有 continuation | binary search、宿主 `grep` 文本、无界全盘扫描 |
| `write` | 必须显式 `mode=create|replace`；create 使用 no-replace；replace 要求 expected ordinary-file identity 与 raw-byte digest | upsert、force overwrite、direct binary mutation、任意 metadata 修改 |
| `patch` | 单一 ordinary text file；版本化 structured hunks，包含 old range、context、delete/insert lines 与 newline metadata；要求 expected identity/digest | 多文件 patch、宿主 `patch`、binary/mode/rename patch、部分 hunk 发布 |
| `rename` | 单一 source/target；target 必须不存在；no-clobber；只接受平台可证明的同文件系统 rename | 自动改名、覆盖 target、cross-device copy+delete fallback |
| `delete` | 单一精确 ordinary file 或空目录；执行前复核 expected identity；非空目录冲突 | 递归删除、trash、恢复副本、跟随 link 删除目标 |
| `exec` | Windows 为 `cmd.exe /d /s /c`，Linux 为 `/bin/sh -c`；前台非交互；每次调用有明确实际 cwd | PTY、交互程序、一等 background job、detached-job 管理、direct HTTP tool |

direct 文件工具不跟随 symlink/junction/reparse；它们只可返回链接元数据与规范目标，模型必须以真实目标发起新的调用。device、FIFO、socket 和其他特殊对象拒绝。`__yaca__` reserved tree 的 list/search/mutation 始终 hard-deny；其窄 exact-read 例外由 Context/安全规格单独约束，不得由普通路径参数扩大。

文本 direct tools 只把 ASCII 与严格 UTF-8（可识别并保留 UTF-8 BOM）当作可往返文本；digest 始终基于 raw bytes。其他编码、非法序列、NUL 或 binary 内容返回 typed 分类，不进行有损替换。binary `read` 只返回类型、raw size、digest 和有界 metadata，不返回正文；`write`/`patch` 不提供 base64 或 byte-range mutation。需要其他编码或二进制处理时只能使用获批的 raw `exec`，且不继承 direct tool 保证。

## Registry 与调用 admission

一次工具调用按以下唯一顺序进入执行：

1. Model request 在发出前取得完整 registry、每个 schema version 和 registry digest；不同 provider adapter 只能无损投影同一语义。
2. provider response 完整收口后，adapter 解析 call identity 和 typed arguments；流式参数不得边生成边执行。
3. Runtime 进行 required/unknown/type/size/encoding、canonical scalar、路径形式与资源 hard-limit 校验。失败的 wire call 不建立可执行 operation。
4. 规范目标、expected identity/digest、cwd 和 effective config/Permission generation 被解析并冻结。
5. 08 号系统求值 Permission、可选 high-risk review 和必要人工确认。任一安全相关输入变化都会使旧 action stale。
6. accepted call、canonical arguments、action snapshot 和 operation intent 达到 Context durable barrier 后，才允许产生副作用。
7. 工具串行执行；结果达到 durable barrier 后，AgentLoop 才可开始下一项副作用或把结果送入下一次 Model request。

Protocol wire、canonical scalar、XML carrier 与执行端 carrier 必须逐 byte 无损 round-trip。显示层可以 escape 控制字符或无法显示的 Unicode，但不能改变真实路径、command、content、digest 或 accepted arguments。

## direct 写入与发布不变量

`write`、`patch`、`rename` 和 `delete` 共同遵守：

- admission 与真正 open/publish/delete 前都复核 canonical path、final object identity、ordinary-file/directory 类型和 Permission generation；路径别名、link 或外部并发变化使动作 stale。
- `replace`、`patch`、`rename` source 和 `delete` 必须带模型所依据版本的 expected raw-byte digest/identity；不匹配直接返回 conflict，不能静默覆盖。
- `write(create)` 只能 no-replace；目标在发布时已存在就冲突，不自动选择新名称。
- `write(replace)` 与 `patch` 先完整解析和校验候选内容，在目标同目录生成受控临时对象，完成写入、flush、内容/metadata 验证后才执行平台已证明的安全发布。任一 hunk 失败时正式目标零修改。
- replace/patch 不接受文件属性变更参数。create 使用平台安全默认；replace/patch 必须保留 registry 声明可证明的行为与安全 metadata。遇到 hardlink、ADS 或无法可靠保留/复核的 owner、ACL、xattr、attribute 时拒绝，不退化为 content-only。
- `rename` target 存在即冲突；跨设备或无法证明原子 no-clobber 时返回 `CrossDeviceRenameUnsupported`，不自动 copy+delete。
- `delete` 仅删除一个 ordinary file 或已经证明为空的目录；不递归、不跟随链接、不保存 preimage。
- 发布完成后重新打开并核验实际 identity、raw digest 和必须保留的 metadata。不能证明发布是否发生时必须返回 `unknown`，阻止后续副作用并进入恢复流程。
- diff 是 old/new canonical text 和 digest 的审阅证据，不是备份。平台只在技术证明覆盖的文件系统上使用“atomic”字样；单文件安全发布不扩张成多文件 ACID 承诺。

## `exec` 的诚实边界

`exec` 是一个宽能力 `Shell` action。它可能读取、写入、删除、联网、越过 workspace、启动子进程或改变外部系统；Runtime 不解析 opaque command，因此不能给予 direct tools 的路径 containment、expected digest、no-replace 或 diff 保证。

每次调用可以有独立 canonical `cwd`；缺失时使用该 turn 冻结的 workspace root。admission 与 spawn 前都复核 cwd 存在、可进入、identity 未变和 `OutsideWorkspace` 结果。Windows/Linux shell 方言固定，不跟随用户 `SHELL`、`COMSPEC` 或 PATH 中同名 wrapper。

Runtime 等待直接 root shell，随后只进行有界 pipe drain。若仍可能存在后代，结果必须携带 `descendant_state` 与 `external_effects_unsettled=true`；不能把 root process exit 或 pipe EOF宣称为所有外部副作用都已结束。取消/超时尽力终止可证明的进程树，不能证明的部分收口为 `unknown`。

Git 没有专用 tool、内部 adapter 或隐式工作流。模型可以把只读 `git status`/`git diff` 作为改动证据提出普通 `exec`，但它们仍完整服从 Shell Permission、必要确认和 opaque-command 风险；Runtime 不在模型调用之外隐式注入 Git。`commit`、`push`、`reset`、`stash` 等写入或工作流动作只有用户明确要求时才可提出，Runtime 不自动执行，也不用 Git rollback。

## 串行调度与调用配对

v0.1 所有工具严格串行，包括只读调用；协程和事件泵只保证输入、输出、取消与持久化可推进，不改变领域顺序。一个 accepted batch 中，第一个 observed failure、denied、cancelled、timeout、partial 或 unknown 之后，不再 admission 尚未开始的调用；这些调用各自产生 `skipped` synthetic result。已经完成的副作用保持真实结果，不自动回滚。

每个 accepted call 必须恰好有一个最终真实或 synthetic result。provider call ID 只是外部证据；本地 call/operation ID 才决定唯一配对。恢复、steer、拒绝、取消、前项失败和关闭都不能遗失结果，也不能用一个结果配对多个调用。

## 规范 ToolResult

所有工具使用同一结果外层，并由工具专属 payload 补充细节。共同字段至少包括：

- registry/schema version、provider call identity、本地 call/operation ID；
- canonical arguments 摘要、实际 cwd、规范目标和执行时 identity/generation；
- `success|failed|denied|cancelled|timeout|partial|unknown|skipped` outcome；
- started/finished 时间、错误 ID/category/stage、retryable 事实与取消结果；
- direct result 或 stdout/stderr channel evidence、observed/retained/discarded byte counts；
- raw/canonical digest scope、encoding/decoder、truncation/redaction/partial 范围；
- 已知 postcondition、diff 或无法生成 diff 的原因、仍可能存在的外部副作用。

direct result 有界但尽量保留完整 canonical evidence；超过 hard cap 时必须保存原始大小、实际保留范围、digest scope、continuation 或拒绝原因，绝不把截断内容标成完整。`exec` 的 stdout/stderr 分通道采集，每个 chunk 在进入单线程事件泵时取得 observed sequence；这只是 Runtime 观察顺序，不冒充子进程内部写入顺序。达到 cap 后继续 drain，但规范结果只保存确定性的 head+tail、各通道统计和明确不可恢复范围，不能为补回输出自动重跑命令。

## 失败、恢复与 unknown 矩阵

| 窗口或结果 | 规范收口 | 禁止行为 |
| --- | --- | --- |
| schema/canonical carrier 校验失败 | wire call typed reject；不建立 operation | 尽量解析后执行、截断 command/path/content |
| Permission deny 或用户拒绝 | accepted call 配对 `denied` synthetic result | 当作工具没被调用、让 reviewer 扩权 |
| durable intent 前失败 | `failed`，证明未开始副作用 | 先执行再补 XML |
| intent 已 durable、direct mutation 尚未开始时崩溃 | 用 expected identity/digest 与目标现状证明 `not-applied`，生成 synthetic result；不能证明则 `unknown` | 无条件重放 |
| temp 写入、flush 或 validation 失败 | 正式目标保持旧 identity/digest；报告失败与残留 temp 清理状态 | 删除旧文件、发布半文件 |
| publish API 返回不确定结果 | 重新打开目标并比较 old/new identity/digest；只能证明 old、证明 new 或记 `unknown/conflicted` | 猜 success/failure、自动 rollback |
| rename 返回 cross-device/not-atomic | typed `CrossDeviceRenameUnsupported`，source/target 保持可证明状态 | 自动 copy+delete |
| delete 后结果提交前崩溃 | 依据 exact target identity 与存在/缺失事实收口 applied/not-applied；身份无法证明时 `unknown` | 恢复猜测、创建替代内容 |
| `exec` root 退出但后代不明 | 保存 exit/capture 证据并标记 unsettled/unknown external effects | 宣称命令所有副作用完成 |
| cancel/timeout 无法证明进程树已停 | 保存已观察输出和 `unknown` 副作用 | 自动重跑或宣称已取消全部效果 |
| batch 中一项失败或 unknown | 已完成项保持；当前项真实收口；后续项逐个 `skipped` | 回滚前项或继续执行后续副作用 |
| result durable 失败 | fail-stop，禁止下一副作用；恢复时依据现状生成真实/合成结果 | 继续循环、重复执行 operation |

用户或 self-fix 可以日后为 unknown operation 追加 `completed|not-completed|still-unknown` 结论和证据；原 unknown 事实不删除，Runtime 从不自动重放原 operation。

## 明确非目标与未来重开

v0.1 不提供通用自动 undo、reverse patch、preimage attachment、checkpoint、shadow workspace、overlay、递归 direct delete、direct binary mutation、Git workflow controller 或 background-job manager。`backup/` 也不是 tool、保留目录或 Runtime 机制；它只能是用户某段 Prompt 中的普通文字。模型据此提出的动作仍是普通 `write`/`exec`，完整服从 registry、Permission、审批和结果契约。

未来若要增加任何工具或保证，必须由项目负责人显式重开，并同时版本化 registry/schema、Permission mapping、Context XML、provider fixture、旧平台实现与迁移测试；不能以隐藏字段、Prompt 约定或宿主程序存在为由自动扩展 v0.1 registry。

## 发布证明

Win32 x86、Win64 x86_64 与 Linux x86_64 必须分别证明：

- 两套 provider adapter 都能无损承载完整 registry、typed arguments 和 call/result identity；
- ordinary file、link/reparse/special object、reserved tree、并发替换与权限变化会得到一致 admission；
- no-replace、same-directory publish、flush、metadata 保留、rename conflict/cross-device 和空目录 delete 满足上述矩阵；
- kill、磁盘满、只读文件、杀软/共享占用、输出超限、取消、进程后代与 XML result 提交失败不会自动重放或丢失配对；
- 所有工具实际串行，首个失败后剩余调用稳定 `skipped`；
- direct binary mutation、recursive delete、Git/HTTP/undo/backup tools 与 background job 表面确实不存在。
