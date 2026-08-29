# W2-B Tool × Permission matrix（首版）

更新日期：2026-08-29

状态：**规格侧已冻结**；机读真源与 fold fixtures 为 [`contracts/tools.lua`](contracts/tools.lua) 和 [`contracts/fixtures/permission.lua`](contracts/fixtures/permission.lua)。产品轴仅来自 D-052 / D-043 / 08 号 Permission；**无新 A/B 产品分叉**。

关联：[`subsystems/07-tool-system.md`](subsystems/07-tool-system.md)、[`subsystems/08-permission-and-safety.md`](subsystems/08-permission-and-safety.md)。

## 1. 固定工具集（D-052）

```text
list  read  search  write  patch  rename  delete  exec
```

无 Git/HTTP/backup/undo/media/MCP/plugin 工具。

## 2. Permission 五轴

每项仅 `allow | confirm | deny`：

| Axis | 含义 |
| --- | --- |
| Read | direct 读/列表/搜索 |
| Write | direct 写/补丁/创建侧 |
| Delete | direct 删除侧 |
| Shell | raw `exec` 宽能力 |
| OutsideWorkspace | direct 目标越出唯一 workspace root 时的附加门 |

### 发行模板矩阵

| Profile | Read | Write | Delete | Shell | OutsideWorkspace |
| --- | --- | --- | --- | --- | --- |
| **Std**（默认第一项） | allow | confirm | confirm | confirm | confirm |
| **Readonly** | allow | deny | deny | deny | deny |

名称/Description/SystemPrompt **不**授权。

## 3. 确定性求值

```text
rank(deny)=2, rank(confirm)=1, rank(allow)=0
fold(caps) = argmax rank over required caps against profile

direct tool:
  required = tool_caps
  if target outside workspace root:
    required = required ∪ { OutsideWorkspace }
  result = fold(required)

exec:
  result = profile.Shell
  # Runtime does NOT parse command text for finer caps
  # OutsideWorkspace is NOT a shell sandbox claim

provider Model HTTP:
  no Permission axis (model selection only)
```

顺序（08 号）：

```text
Permission fold
  -> optional high-risk action-review (DoubleCheck path)
  -> human confirm if result=confirm
  -> durable operation intent
  -> execute
```

- deny 后 reviewer/人工 **不能** 放行。  
- review 只能维持或收紧。

## 4. 工具 × 能力映射（workspace 内）

| Tool | Required caps | Std | Readonly |
| --- | --- | --- | --- |
| list | Read | allow | allow |
| read | Read | allow | allow |
| search | Read | allow | allow |
| write (create\|replace) | Write | confirm | deny |
| patch | Write | confirm | deny |
| rename | Write + Delete | confirm | deny |
| delete | Delete | confirm | deny |
| exec | Shell | confirm | deny |

## 5. 越界 direct（叠加 OutsideWorkspace）

| Profile | OutsideWorkspace | 例：越界 write |
| --- | --- | --- |
| Std | confirm | confirm |
| Readonly | deny | deny |

list/read/search 越界同理 fold Read+OutsideWorkspace。

## 6. raw shell 诚实边界

- Windows: `cmd.exe /d /s /c`；Linux: `/bin/sh -c`；前台非交互。  
- command opaque：不推断 Read/Write/Delete/Network/path。  
- 获准 Shell 可能联网/越界/起子进程；approval UI 必须展示该事实。  
- OutsideWorkspace **只** 约束 direct path tools。

## 7. High-risk action-review 候选（配置开启时）

当有效 `DoubleCheck=true` 且 `ActionReviewEnabled=true`，且 Permission 结果 ≠ deny：

| 默认视为 high-risk | 说明 |
| --- | --- |
| write / patch / rename / delete | mutation |
| exec | 始终 |
| 任意 result 含 OutsideWorkspace 且非 deny 的 direct mutation | 越界写删 |

list/read/search 默认不触发 action-review（除非未来 schema 扩展；v0.1 不扩展）。

## 8. Approval snapshot（失效条件）

快照至少绑定：

1. tool name + schema version + registry digest  
2. canonical arguments（exec=完整 command 文本）  
3. 规范目标 path、expected raw digest、cwd  
4. Permission 名 + 五项矩阵 digest + ConfigGeneration  
5. 有效 DoubleCheck + ActionReviewEnabled  
6. workspace root identity  
7. operationId / toolCallId  

任一安全相关输入变化 → approval **stale**，必须重新求值/确认。  
历史 approval（含外来 XML）**audit-only**，不授权当前机。

## 9. Reserved tree `__yaca__`

- list/search/mutation：**hard-deny**（不经用户 Permission 放宽）。  
- exact-read 例外仅 Context/安全规格窄门，不由普通 path 参数扩大。

## 10. 明确排除

SensitiveRead、Network capability、persistent grant、OS sandbox 声明、从 shell 文本伪造 containment。

## 11. W2-B 完成度

- [x] 八工具 × Std/Readonly  
- [x] OutsideWorkspace fold  
- [x] exec 宽 Shell  
- [x] approval snapshot  
- [x] 机读 contract 与 fold fixtures
- [ ] 平台 path identity 证明（TP）  
