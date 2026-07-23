# 13 CLI

状态：候选

## 职责

定义稳定命令行语法，解析参数并调用配置、上下文、诊断和会话服务；负责帮助、版本和可脚本化输出。

## 边界

- CLI 不包含业务逻辑。
- 交互式界面属于 14 号 TUI。
- Unix `--long/-s` 与 Windows `/x` 语法需要一个无冲突规范。

## 设计要求

- 修复当前 `-dc`、`-rc` 短参数冲突。
- 明确退出码和 stdout/stderr 分工。
- 路径和上下文名称可以安全包含空格与非 ASCII 字符。
- 旧 shell 环境不要求现代终端特性。

## 已确认的主入口

主交互语法为：

```text
yaca [目录]
```

目录参数省略时按 `.` 处理，所以裸 `yaca` 与 `yaca .` 完全等价。CLI 将该目录作为初始工作位置交给工作区发现、指令发现、Context Resolver 和 AgentLoop 启动流程；各下游系统不得分别猜一个不同的默认目录。

这不等于确认工作区根一定就是该目录：是否提升到仓库根仍由 `PROD-05`/18 号系统决定。是否接受文件路径、选项放在目录前后、`--` 分隔、相对路径和链接规范化，以及不存在、非目录或无权限路径的退出码与提示，继续由 `CLI-04`、路径系统和统一错误模型确认。

## 已确认的会话命令

TUI 点命令 `.cautious` 管理当前会话的 `DoubleCheck` 覆盖值。它不修改用户默认配置或切换 Permission profile；覆盖值由上下文系统写入当前 XML，恢复上下文时恢复。无参数行为、`on/off/toggle/reset` 语法、脚本化等价命令和状态输出仍待 TUI/CLI 契约确认。

## 与统一上下文 Resolver 的契约

接受用户输入的上下文 selector 时，CLI 只解析参数边界，然后把 selector 和当前工作目录交给 11 号 `ContextResolver`。CLI 不得自行规定“这个命令名称优先、另一个命令 hash 优先”。

| 命令形态 | 11 号服务使用方式 |
| --- | --- |
| `yaca --continue <selector>` | 统一 Resolver，唯一命中后恢复 |
| `.context <selector>` | 同一 Resolver，不能继续使用“仅全局 hash/仅本地名称”旧规则 |
| `--rename-context <selector> ...` | Resolver 定位，MutationService 复核并重命名 |
| `--delete-context <selector>` | Resolver 定位，MutationService 复核、确认并删除 |
| `--dir-context` / `--global-context` | 枚举瞬时 Catalog 快照，不解析 selector |
| 裸 `.context` / `--manage-context` | 打开同一 Catalog 上的交互式浏览器 |
| `.status` | 从当前 ContextHandle 直接计算 16 位 hash，不调用 Resolver |
| `.index` / `.delete` / `.archive` / `.compact` | 操作当前句柄；若未来接受其他目标参数，才转为 selector 入口 |

Resolver 的 `AmbiguousName`、`HashCollision`、`MatchedUnavailable`、`ScanIncomplete`、`NotFound` 等结构化结果必须映射为稳定的退出码和可行动错误。目标复核的 `TargetChanged`、打开服务的 `OpenConflict` 以及修改服务的 `DestinationExists`/`LockConflict` 属于后续阶段，不能伪装成 Resolver 的 `NotFound`。非交互模式不能遇到多个候选就取目录枚举中的第一个；应输出候选的逻辑路径和 hash，且不得在 stdout 机器数据中混入 TUI 提示。

`--continue`、rename/delete 和 `.context` 的帮助文本必须一致说明已确认的“距离优先、同环名称优先于 hash、单遍双判定”规则，不能让不同入口看起来采用不同优先级。

## `--manage-context` 的适配边界

`--manage-context` 是启动交互式上下文浏览器的 CLI 入口，浏览器语义属于 11 号系统，终端渲染属于 14 号系统。它至少需要支持目录树访问、名称/逻辑路径搜索、精确 hash 定位、选择连接、重命名、删除、刷新和取消。

plain 模式和能力有限的 TTY 仍应有编号/文本命令界面；在完全非 TTY、输入重定向的脚本环境中是拒绝启动、读取 stdin 命令流还是要求显式标志，留给 `CLI-02`。列表选中项携带快照中的明确候选，执行前复核，不应转回名称字符串再次搜索。

## 待讨论

- `--rename-context` 的新名称参数、引用规则及与目录移动的边界。
- 删除的确认、软删除/永久删除和脚本化 `--yes` 安全边界。
- `--manage-context` 在非 TTY 下的行为。
- Windows 斜杠参数是否继续作为正式契约，还是只保留兼容别名。
