# 开发追踪

更新日期：2026-09-08

## 当前阶段

**平台无关核心已实现至 M9，正在收口 controller 与发布准备。**
C01--C31 已有核心实现、测试 harness、最小发行规划和现代 Linux 候选证据；
这不表示全部目标相关 hard gate 已完成。机读阶段维持
`implemented-unqualified`，Gate A/B 已通过，Release Gate R 关闭。

本轮开发起点为 `289a3c8`（2026-08-30 暂停交接）；此前核心节点
`95a0e9c` 的完整串行 suite 为 **442/442**。本轮变更与验证记录见下表。
原来的“源码 0%、从 C01 开始”是 2026-08-29 编码前快照，已被现有代码取代。

## 进度与证据

| 范围 | 已有结果 | 仍需完成 |
| --- | --- | --- |
| 产品决策与契约 | D-001--D-071；16 contracts、12 fixture sets；无未答产品分支 | 实现变化持续同步契约与负向用例 |
| M0 / C01 | 测试发现与隔离、loader allowlist、release manifest | 最终 zip 零表面检查 |
| M1 / C02--C04 | 平台 identity、event pump、native ports；现代 Linux 探针与 Windows 交叉编译 | 真实旧 Windows / CentOS wait、console、process 资格 |
| M2 / C05--C09 | UTF-8、JSON、INI、XML、路径/hash 核心与测试 | 三目标 native XML ABI 和资源校准 |
| M3--M4 / C10--C14 | immutable config、bootstrap、action/CLI、兼容 TUI/editor | 未接通 controller 及真实旧终端 transcript |
| M5 / C15--C18 | 单 XML、索引、writer/lock、publication/recovery、管理事务核心 | 目标文件系统 replace/lock/崩溃矩阵；跨 workspace 确认/rebind |
| M6 / C19--C22 | curl/SSE/retry/cancel、双 Model 协议、Prompt/control；XP HTTPS 静态候选 | 真实目标 TLS/CA/代理、provider wire 和取消证据 |
| M7--M8 / C23--C28 | 8 Tools、Permission、operation、AgentLoop、queue/side/review、手工/自动 compaction | 目标进程树/路径/资源上限验证 |
| M9 / C29--C30 | typed diagnostics、self-test 调度/Stage 1、`.details` | Stage 2/3 production adapter、controller 与目标端到端验证 |
| M10 / C31 | 最小包 allowlist、依赖锁/license/SBOM、资源 overlay、候选构建脚本 | C32--C34 |
| C32 | 三目标资格计划与部分候选工具 | XP SP3 x86、Win7 SP1 x64、CentOS 7 x64 真实构建/运行/完整测试 |
| C33 | 发行旅程与零表面契约 | 三个最终 zip 的干净机安装、配置、新建/恢复、退出、升级、卸载 |
| C34 | 文档与 evidence 布局规划 | 最终 SHA-256/license/SBOM/build/test evidence，公开声明复核 |

已接通的近期 controller 包括 `--continue`、同 workspace `.context`、
`.details`、`.cautious`、`.prompt show|set|clear|edit`、`.model`、`--status`、chat `.status`
和 `--export <selector>`。
显式跨 workspace 确认/rebind 尚未开放。

本轮直接核对 `main.lua` 后补记管理缺口：`config-repl` 当前提供配置校验与
缺文件时的修复模板，`context-repl` 当前提供 Catalog 列表，尚无完整管理交互。
在线 self-test Stage 2/3 的 production adapter 仍返回 failed 占位结果。
这些属于实现待办，不能归入“仅差目标资格”。

## 本轮推进（2026-09-07）

代码节点：`87ea74f`（模型切换秘密复核与代理展示）、`c828830`
（Linux qualification 资源门槛与动态测试证据）。

| 工作项 | 改动 | 验证状态 |
| --- | --- | --- |
| 模型切换代理展示 | config 生成去 userinfo、隐藏 query 值的规范代理 route；picker/确认详情展示 | 定向 54/54、完整 449/449 通过 |
| 凭据变更复核 | 保存态 apply 重载后，在同一 config service 内比较目标 Key、secret adapter option、代理凭据的精确值；不公开秘密或摘要 | 公开 shape 不变的轮换与 stale-before-publication 用例通过 |
| Linux 构建资源 | 所有 make 串行；至少 5120 MiB 可用内存；已有较低级别 guard 也重新检查 builder 门槛 | 语法/静态契约及 4 组模拟 admission 边界通过 |
| 构建测试证据 | 从唯一、正数、全通过的 SUMMARY 动态取数；拒绝重复/缺失/畸形/失败摘要 | 完整 suite 与摘要正负用例通过 |
| 进度整理 | TRACKING、CURRENT-STATE、实施计划、开发入口和中英文 README 统一状态 | 补记 production 入口缺口，Gate R 仍关闭 |
| 只读状态入口 | `--status` 显示当前进程、workspace 和配置状态；不查历史、不建目录/XML，缺失或无效配置也可查看 | production/TTY/零副作用测试通过 |
| chat 状态准确性 | 显示最新 writer 的 Context hash 和有效 Model/Permission/DoubleCheck；只复核当前 XML 的身份与规范文档，失效后关闭 admission 与 publication | 外部替换/写入/删除/读后换路径、sticky fail-stop 和同批后续输入阻断测试通过 |
| Markdown export | 精确 selector → 只读校验 → 既有 Markdown → 最终目标复核；缺失/无效配置仍可导出，不启动 writer/恢复/Model | production CLI、TTY gate、竞态和 registered-secret 零输出测试通过；解码后与最终 Markdown 均扫描 |

验证：design-contract **7612**、proof-evidence **56**、coding-readiness **553**
条断言通过；TP-003/006/008/010 与 RP-001 全部通过。readiness 首次运行在
TP-010 下载 Lua 源码时遭遇 TLS EOF，随后 TP-010/RP-001 使用 SHA-256 与锁
完全一致的本地源码包重新构建并通过；下载来源切换已单独记录，未关闭校验。
本轮日志在 `out/development-2026-09-07-sTXXIy/`，属于本机可丢弃证据，
不作为三目标资格或发布授权。

状态 controller 节点：完整 suite **457/457**，coding readiness 入口及上述五项
modern proofs 全部通过；构建证明沿用每次复核 SHA-256 的锁定源码缓存。
日志为同目录的 `status-full-suite.log` 与 `status-readiness.log`。

导出 controller 节点：完整 suite **462/462**，coding readiness 入口及五项
modern proofs 全部通过；日志为 `export-full-suite.log` 与 `export-readiness.log`。
同样使用校验后的锁定源码缓存，不代表 XP/Win7/CentOS 7 已通过资格验证。

## Prompt 编辑器节点（2026-09-08）

`.prompt edit` 已接入内置有界多行事务：以当前 Prompt 初始化，追加文本保留
空白，`.show|clear|reset` 操作草稿，`.save prompt-edit-N` 绑定本次编辑实例。
保存前复核原 Session owner、Prompt 与 ConfigGeneration，并复用原有完整配置
重载、secret scan、Context/ModelView 原子发布及下一 turn 生效边界。错误保留
安全草稿供显式重试；取消、Esc、EOF、退出与新 Tool approval 均丢弃未保存编辑。
不新增域动作、不调用外部编辑器、不在首条消息前创建 Context。

定向 suite **62/62**、bootstrap suite **27/27**、完整 suite **471/471** 通过。
完整 coding readiness 入口与 TP-003/006/008/010、RP-001 全部通过，三项 validator
仍为 **7612/56/553** 条断言。构建证明使用逐次 SHA-256 校验的锁定源码缓存；
日志仍位于上述可丢弃目录，前缀为 `prompt-editor-`，不作为三目标资格。

## 下一步顺序

1. 补齐管理 REPL 操作与
   在线 self-test Stage 2/3 的真实 adapter，保留逐次联网同意和零副作用检查。
2. 实现显式跨 workspace 确认/rebind controller，保留精确目标与 writer 复核。
3. 在真实目标环境执行 C32；只有完整目标证据通过后才推进 C33/C34 和 Gate R。
4. Web 继续只维护预留文档，核心 v0.1 不增加 Web 实现。

## 持续约束

- 单 Agent、terminal-only、单 Context/workspace、工具串行；实现主体 Lua 5.5。
- 三个独立发行目标：Win32 x86（XP SP3 至 Windows 11）、Win64 x86_64
  （Windows 7 SP1 至 11）、Linux x86_64（CentOS 7 硬基线）。
- 现代 Linux、fake adapter、交叉编译和静态 import 结果不能替代真实目标资格。
- 长期用户数据只有主 INI 与各 Context 的完整 XML；不引入 WAL、备份历史或 undo。
- Std/Readonly、严格审批、secret 隔离、unknown 不自动重放和零扩展表面保持不变。
- 历史 `bin/` 是候选输入，不能整体复制到发行包；相邻 `luainstaller`
  1.3.0 的 upstream 证据不能替代 yaca-specific qualification。
- 开发沿用 `main` 和 D-071 的核心节点约定；验证未闭合不标记为完成。
- 每次验证重新查看内存、memory pressure 和遗留 runner；守住资源门禁，串行执行
  targeted → full suite → coding readiness/proofs，不复用旧的 preflight 数字。

## 阅读入口与历史

当前实现细节见 [CURRENT-STATE.md](CURRENT-STATE.md)，任务退出条件见
[IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md)，阶段门见
[GATE-AUDIT-2026-08-29.md](GATE-AUDIT-2026-08-29.md)，机读真源见
[contracts/README.md](contracts/README.md)。

设计讨论、问卷与旧 Wave 快照保留在 `DISCUSSION-BATCH-*.md`、
`DECISIONS.md`、`READINESS-GAP.md` 和
[HANDOFF-AUTO-2026-08-10.md](HANDOFF-AUTO-2026-08-10.md)。
这些历史记录不再充当当前源码进度。
