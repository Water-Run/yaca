# 数据分类与秘密生命周期（W3-C 权威矩阵）

更新日期：2026-08-10

状态：**W3-C 规格首版** — 由 [`DATA-CLASSIFICATION-CANDIDATE.md`](DATA-CLASSIFICATION-CANDIDATE.md) 按 D-049..D-070 **收口** 的现行矩阵；候选文件仅作审计底稿，**不再** 作为实现真源。

对齐：D-028、D-044、D-049、D-051、D-052、D-055、D-068、D-070；AR-P0-08；08 号 Permission 矩阵 **冻结**（本文件不改 Std/Readonly 格）。

## 标记

| 标记 | 含义 |
| --- | --- |
| `never` | Runtime 硬禁止进入该目的地 |
| `needed` | purpose 正常工作所需；仍受范围/大小限制 |
| `minimized` | 只发结构化摘要或完成判断子集 |
| `derived` | 只发脱敏/截断/digest/类型投影 |
| `audit` | 可持久化供接盘；不自动授权 |

## Source（与值正交）

| source | 例子 | 要点 |
| --- | --- | --- |
| `config-file` | INI Key、proxy secret、SecretHeader | 文件 ACL 与 M05-54；过短值 M05-59 |
| `ambient-environment` | 宿主环境变量 | 不继承 config 文件权限结论 |
| `user-content` | 聊天、文件、shell 输出 | 可能含未登记秘密；启发式未命中≠安全 |
| `runtime` | 临时 carrier | 禁止写入 XML/argv/普通日志 |

## 类别 → 目的地表（核心）

| 数据类别 | main | side | action-review | termination-review | compaction | context-name | XML durable | TUI/stderr | export/support |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Registered config secret **值** | never | never | never | never | never | never | never | never（可遮罩类名） | never |
| Connection public（host/model id/TLS mode） | needed | needed | derived | derived | needed | needed | audit 快照无 Key | ok | 可脱敏 |
| Built-in + Global/Model system instruction | needed | needed | minimized | minimized | needed | built-in only | version/digest | 不默认全文 | 可选 |
| Permission SystemPrompt | needed（独立 component） | never | never | never | never | never | 采用原文快照 | 管理界面 | 可 |
| ContextPrompt | needed | 有界快照 | never | minimized | 范围内 | never | yes | 可编辑投影 | 可 |
| 当前用户输入 | needed | 快照 | 若需理由则 minimized | 目标相关 | 范围内 | never | yes | yes | 可 |
| 历史对话（model view 窗） | needed | 创建时快照 | 相关片段 | 摘要 | 范围内 | 有界完成摘要 | full facts | 截断显示 | export |
| Tool schema | needed | never | never | never | never | never | schema id/digest | help | 可 |
| Tool invocation/result | needed | 历史只读 | exact action | derived | 范围内 | never | bounded+标记 | 截断 | 警告 possibly-secret |
| Approval/verdict | needed | 历史 | 当前 exact；**无**旧 token 授权 | derived | audit | never | yes | status | 可 |
| Hidden provider reasoning | never 默认 | never | never | never | never | never | 通常不存 | never | never |
| Usage token 计数 | metadata | never | never | never | derived | usage 可记 | yes | 可显示 | 可 |
| 金额/币种/price | never | never | never | never | never | never | never | never | never |
| Diagnostic 细节 | 非 prompt 默认 | never | never | never | derived | never | 有界 | stderr | 脱敏 |
| AutoRenameDisabled | — | — | — | — | — | gate | metadata bool | 可显示 | 可 |
| Preimage / undo backup | never | never | never | never | never | never | **零元素**（D-052） | never | never |
| Web/media/remote/telemetry payload | never | never | never | never | never | never | **零**（D-044/055） | never | never |
| 外来 XML 历史 approval | — | — | **audit-only** | — | — | — | 原位；**不**授予当前动作 | 提示 mapping | 警告 |

**transport 例外**：adapter 可为已授权 Model 请求在 **最小精确 carrier** 中消费该 Model 的 Key；值不得进入模型正文、XML、argv、stderr 明文（TP-006）。

## Key / secret 生命周期

```text
ingress (typed registry)
  -> admit (schema + ACL + min-length eligibility)
  -> process-private carrier only
  -> use in single attempt (03 port)
  -> redact errors
  -> destroy carrier on close/cancel/crash best-effort
  -> never copy to XML / export / tool argv / support body
```

| 阶段 | 规则 |
| --- | --- |
| 登记 | 开放 registry：Key、proxy、SecretHeader、EnvironmentSet value、adapter 扩展；消费者不得硬编码“只认三项” |
| 过短 secret | M05-59 A：精确 consumer ineligible，仅管理/替换/删除 |
| 聊天粘贴命中 exact registry | 拒绝 submit；显示 class + span；不回显值 |
| 工具输出命中 | 已发生副作用保留；canonical 前替换为 redaction marker |
| 删除 Context | 枚举 yaca 已知副本；**不** 承诺 provider 侧撤回或磁盘物理擦除 |
| 轮换 Key | 新 generation；旧 Key 不写历史 XML |

## 跨 endpoint

- 首次把敏感历史发往 **另一 origin** 的特殊 purpose：需显式确认（既有 AL06-51 等路线）。  
- 切换 Model 不自动发送 registered secret 到新连接以外的 carrier。  
- 历史 approval **永不** 在目标机自动授权。

## Permission 交叉声明（冻结）

本矩阵 **不** 修改 [08](subsystems/08-permission-and-safety.md) / [TOOL-PERMISSION-MATRIX.md](TOOL-PERMISSION-MATRIX.md) 的 Std/Readonly allow|confirm|deny 格（D-070）。  
Shell 宽边界：raw 输出视为 possibly-secret；不因 Permission 名放宽 secret `never`。

## 负向扫描清单（实现/发布）

| 表面 | 必须为零 |
| --- | --- |
| XML element | undo preimage、telemetry、media、remote session |
| config field | cost budget currency、upload endpoint |
| purpose | image/audio/transcription/speech/update |
| export | secret-bearing 附件 |

## 与候选稿关系

| 文件 | 角色 |
| --- | --- |
| `DATA-CLASSIFICATION.md`（本文件） | **现行** W3-C 权威 |
| `DATA-CLASSIFICATION-CANDIDATE.md` | 历史分析；冲突时以本文件与 DECISIONS 为准 |

## 完成度（W3-C）

- [x] purpose × 类别矩阵  
- [x] Key 生命周期与负向清单  
- [ ] 目标机 canary / exact-scan 阈值证据（TP-028 等）  
