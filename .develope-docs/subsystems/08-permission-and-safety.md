# 08 权限与安全

状态：候选

## 职责

根据工具动作、路径、网络访问和权限组决定允许、拒绝、请求用户确认或调用 LLM 二次检查，并产生可审计决定。

## 边界

- 安全策略独立于 TUI；CLI、未来 Web 和测试都调用同一接口。
- 本系统不直接执行工具。
- Regex 只能作为附加过滤条件，不能成为唯一危险动作分类机制。

## 设计要求

- 直接工具的权限判断基于结构化动作，而不是事后解析完整 shell 字符串；raw shell 只能被视为宽 `Execute` 能力。
- `Readonly` 必须拒绝 raw shell，否则无法承诺“只读”；Model provider 网络不属于工具权限。
- 用户确认内容必须准确显示将要访问的路径、程序或主机。
- LLM 二次检查失败时采用保守策略。

## raw shell 的诚实安全边界

项目负责人要求向模型提供类似 Codex 的原始工具，但又明确不提供 OS sandbox。在这个组合下，Runtime 可以决定“是否允许调用 shell”、展示完整命令并记录结果，却不能可靠证明该命令只读、不会联网或不会启动另一个程序。基于 regex 或 LLM 对命令文本分类可以增加警告，不能变成隔离保证。

因此候选能力映射是：read/write/delete/network/outside-workspace 等细粒度规则只约束 yaca 直接实现且参数结构化的工具；shell 统一映射到宽 `Execute`。用户批准必须绑定 tool 版本、完整命令、cwd、相关环境非秘密摘要、operation ID 和目标新鲜度，批准后任一安全相关输入变化都要重新确认。`DoubleCheck` 只能在确定性 Permission 已经允许的范围内追加复核或否决，不能反向授予 Runtime 拒绝的动作。

候选权威矩阵应至少呈现：

| 动作 | 可强制能力 | `Readonly` 候选 | `Std` 候选 |
| --- | --- | --- | --- |
| direct list/read/search | `Read`，敏感读取可另加限制 | allow/敏感项 confirm | allow/敏感项 confirm |
| direct create/write/patch | `Write` | deny | confirm |
| direct delete | `Delete` | deny | confirm |
| direct rename | `Write`/`Delete` + outside modifier | deny | confirm |
| raw shell | 宽 `Execute/Shell` | deny | confirm |
| Model provider HTTP | 选择当前 Model 即授权 | 可用 | 可用 |
| 未来 direct network tool | `Network` | deny | confirm |

具体 profile 名、顺序与每格仍待确认；表的关键不是当前候选值，而是不能再显示一个实际上约束不了 shell 的 Network/Write 开关。若 v0.1 没有 direct network tool，建议先不暴露 `Permission.Network`。

## 外来 XML 不是授权令牌

复制/导入的 XML 可以忠实保存历史 Permission、`DoubleCheck=false`、ContextPrompt 和 approval，但这些只说明过去发生过什么。继续运行前必须使用目标机器当前 INI/schema 重新计算有效权限；历史 approval 永远 audit-only。任何会降低本机默认安全程度的会话覆盖都应显著显示来源并由当前用户确认，不能因 digest chain 完整就自动信任。

推荐动作顺序为：确定性 Permission → DoubleCheck action review → 人工确认 → operation durable → 执行。reviewer 只能追加拒绝或修改建议；失败后若允许人工 bypass，也只绑定这一精确动作并写入 XML。

## 已确认的模式边界

`Cautious` 不再是独立权限模式或内置权限组。权限 profile 回答“哪些动作允许、拒绝或需要人工确认”；默认配置 `DoubleCheck` 和会话命令 `.cautious` 回答“是否启用额外谨慎复核”。因此 `.cautious` 不能暗中改变 `AllowWrite`、`AllowDelete`、`AllowNetwork` 或当前权限组。

当前 `_CONFIG_.ini` 中的 `[Permission.Cautious]` 与每个 profile 内的 `DoubleCheck` 属于待迁移旧草案，不能继续作为目标 schema。D-027 已确认 `DoubleCheck` 包含主模型正常结束前的完成复核；它还复核哪些写入、删除、执行、联网或外部路径动作，仍需由配置、工具与 AgentLoop 共同确认。

## 待讨论

剩余 profile 的精确定义、tool×capability 矩阵、action/termination review verdict、人工 override、批量调用逐项审批，以及导入 XML 安全降级的页面。
