# 08 权限与安全

状态：Permission 形状与 DoubleCheck 边界已确认；发行模板数值和平台证明待收口

## 职责

根据结构化工具动作、规范路径、当前 Permission profile、`DoubleCheck` 和人工审批，返回 typed `allow|confirm|deny` 决定并产生可审计事实。CLI、TUI、快捷键和测试 adapter 都调用同一 semantic action/Permission 接口，不各自实现安全规则。

## 已确认的 Permission 形状

Permission 是 `[Permission.<LogicalName>]` 形式的命名 profile。v0.1 只定义五个三态能力：

- `Read`
- `Write`
- `Delete`
- `Shell`
- `OutsideWorkspace`

每项只取 `allow|confirm|deny`。`OutsideWorkspace` 是 direct file tool 的粗粒度附加门：direct 动作一旦目标越出唯一 workspace root，必须同时满足该动作本身的能力和 `OutsideWorkspace`，取两者中更严格的结果。不拆成 OutsideRead/OutsideWrite/OutsideDelete。

发行模板只包含 `Std` 和 `Readonly`，并继续把 `Std` 放在物理第一项作为新 Context 默认：

| Profile | Read | Write | Delete | Shell | OutsideWorkspace |
| --- | --- | --- | --- | --- | --- |
| `Std` | allow | confirm | confirm | confirm | confirm |
| `Readonly` | allow | deny | deny | deny | deny |

这是一份发行默认配置，不是名称启发式。名称、顺序、`Description` 和 `SystemPrompt` 都不产生隐藏行为；用户可以修改或增加 profile，Runtime 始终只按当时实际五项矩阵求值。schema、发行模板和 self-test fixture 必须逐格一致，self-test 显示真实矩阵而不是根据名称猜测。

v0.1 不增加 `Trusted`、`Cautious`、`SensitiveRead`、`Autonomy`、persistent grant、turn/session grant 或“always allow”。人工批准只绑定当前精确动作；需要减少确认时由用户显式切换 Permission profile。

## tool × capability 映射

| 动作 | 强制能力 |
| --- | --- |
| direct list/read/search | `Read`；越界时再叠加 `OutsideWorkspace` |
| direct create/write/patch | `Write`；越界时再叠加 `OutsideWorkspace` |
| direct delete | `Delete`；越界时再叠加 `OutsideWorkspace` |
| direct rename | `Write` + `Delete`；任一端越界时再叠加 `OutsideWorkspace` |
| raw `exec` | 宽 `Shell` |
| Model provider HTTP | 选择当前 Model 即授权，不消费 Permission capability |

v0.1 没有 direct Web/HTTP/network tool，因此没有 `Network` 或 `DirectNetwork` capability。获准的 raw shell 可能通过 curl、脚本或子进程联网，这是 `Shell` 宽能力的已知后果，Runtime 不解析 command 来伪造 origin、文件或网络 containment。

## raw shell 的诚实边界

Windows raw shell 固定走已证明的 `cmd.exe /d /s /c` 路线，Linux 固定 `/bin/sh -c`；只支持非交互 foreground process。Runtime 可以展示完整 command、cwd、冻结且脱敏的环境摘要并收口进程树，却不能证明 command 只触及 workspace、不会联网或不会再启动程序。

因此 `OutsideWorkspace` 只约束 yaca 能规范化目标的 direct tools，不能把获准 Shell 宣传成 root-scoped sandbox。Shell approval 必须清楚说明这一点，并绑定 tool/schema 版本、完整 command、cwd、环境 snapshot identity、operation ID 和目标新鲜度；任一安全相关输入变化都使旧 approval 失效。Regex 或 LLM review 只能增加拒绝/警告，不能成为隔离证明。

## `Permission.SystemPrompt` 不是权限

每个 Permission 可以有独立 `SystemPrompt`。它是严格 UTF-8、有界的 Prompt component，不支持把自然语言解析成 capability，也不能改变五项矩阵、workspace、工具 registry、人工确认或 Runtime invariant。

按 18 号已确认顺序，`main`/`side` 依次装配 Global、Model、Permission、Context 四层 Prompt；Permission component 独立标记和快照，不覆盖其他层。action/termination review、compaction、self-test 和 context-name 不继承它的指令权威；确实需要审查 Permission 语义时只把它作为有边界的 quoted data。

某个 Permission Prompt 可以自然语言建议模型把副本放进 `backup/`，但那只是 Prompt 文案。安全系统不创建 `backup/` 特权、不自动备份/恢复、不提供 undo，也不放宽 Write/Delete/Shell/OutsideWorkspace。模型据此提出的文件或 Shell 动作仍按普通目标完整求值。

## DoubleCheck 与 Permission 的顺序

`DoubleCheck` 不是 Permission profile；`.cautious` 只覆盖当前 Context 的 DoubleCheck 有效值，不重排或修改当前 capability matrix。

建议动作顺序固定为：

```text
deterministic Permission
-> optional DoubleCheck high-risk action review
-> required human confirmation when effective result=confirm
-> durable operation intent
-> execute
```

- `DoubleCheck=false` 时没有 action/finish review，Permission 仍完整生效。
- `DoubleCheck=true` 时 finish review 固定启用，不能单独关闭；高风险 action review 是否启用是独立配置。
- action reviewer 只能维持或收紧确定性 Permission 结果，绝不能把 `deny` 授权为可执行。
- reviewer uncertain、失败、超时或超过 hard cap 时不执行动作并进入 waiting-user；人工只能处理 reviewer 建议，不能覆盖 Permission=`deny`、Context writer 锁或未知目标。
- approval 恢复、动作参数变化、config/Permission/root/tool schema generation 变化都必须重新求值和确认。

## workspace 与 Context

每个 Context 恰好一个固定 workspace root，由活动 XML 在 `__yaca__/CONTEXT/` 镜像树中的父目录解码并验证；传入且可进入的真实目录就是新 Context root。上级 Git root、历史 cwd、显示路径、Prompt、外来 XML 字段或一次越界批准都不能扩大边界。

活动 root 消失、不可进入或 identity 改变时停止新副作用并进入 Context self-fix。Context write lease 是独立 Runtime/存储不变量；任何 Permission、DoubleCheck、Prompt 或人工批准都不能越过另一个活动 writer 的锁。

## Config generation 与外来 XML

每个顶层 `main`/`side` admission 冻结完整 config generation、Permission logical identity、五项 capability matrix、Permission.SystemPrompt、DoubleCheck、workspace 和 tool registry。该 turn 的工具、review、retry 与审批始终使用同一快照；INI 变化最早影响下一顶层 turn。

复制/导入 XML 可以保存历史 capability/Prompt/approval snapshot，用来解释过去发生了什么，但它不是授权令牌。继续运行前必须按目标机器当前 INI/schema 重新映射 Permission 并计算矩阵；同名 profile 不等于同一权限，历史 approval 永远 audit-only，外来 Prompt 不能创建或覆盖本机 Permission。

## Self-Test

- Stage 1 确定性检查 schema、五项矩阵、默认顺序、引用和 profile 完整性。
- Stage 3 可以让 Stage 2 已通过的 Model 检查逻辑名称、Description、SystemPrompt 与实际矩阵是否明显矛盾，例如名为 `Readonly` 却允许 Shell。
- Stage 3 结果始终是 advisory：显示依据，但不改名、不修配置、不授予能力，也不能推翻 Stage 1/2 结果。

## 明确排除

v0.1 不宣称 OS sandbox，不提供 Web、媒体、remote/headless、direct network、background job 或 plugin 权限位，也不为空能力保留 parser/help/schema 空壳。Git commit/push/reset/stash 只有在用户明确要求、并通过普通 Shell 流程时才可能发生；Runtime 不自动执行或把 Git 当作 undo。

## 仍需技术证明

冻结 direct path canonicalization、审批页面字段、五项矩阵 fixture、Shell 环境/进程树收口与 Win32 x86、Win64 x64、Linux x86_64 旧平台行为。不得重新引入 outside 细分、direct network、Prompt 驱动权限、backup 特权或持久 grant。

## W2-B

Std/Readonly 与八工具 fold 表、越界 OutsideWorkspace、action-review 范围见
[TOOL-PERMISSION-MATRIX.md](../TOOL-PERMISSION-MATRIX.md)。

