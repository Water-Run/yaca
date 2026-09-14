# N5 无效 INI 的交互修复

日期：2026-09-14。基于 N4 `657d59d`，接通 `--config-repl` 的无效配置分支。
完整 suite **542/542**；validators **7612/56/553**，全部 coding-readiness proofs PASS。
首版仍有实现待办，Release Gate R 保持关闭。

## 行为

- 有效配置继续进入原字段编辑器；缺文件继续创建原有修复模板。
  有界的无效源进入独立的私有行草稿，不启动 Model、Tool、Context 或网络。
- `list [page]` 每页显示 32 个行号和固定 schema 标签；原始值、注释、资源名称及
  无法解析的字节不显示。语法错误仅投影固定原因与行列位置。
- `replace <line>` / `insert <line>` 单独隐藏输入完整 INI 行；后者在指定行前插入，
  最后一行 + 1 表示追加。`delete <line>` 只删指定行。没有自动清洗或丢弃未知字段。
- 多次编辑可暂时无效；`preview`/`validate` 检查整份候选并列出操作位置。
  精确的 `save config-repair-N` 只在完整 schema 验证通过后创建临时文件。
- 原字段、注释、顺序、BOM、混合换行和缺少末尾换行保持；追加时仅补必要分隔符。
  最多 256 次行编辑，沿用 INI 文件、行数和输入字节上限，不截断过大源。
- `reset` 恢复打开时草稿；`reload` 丢弃编辑并重新读取仍无效的源。
  若外部已修好，退出后重新运行字段编辑器。取消/Esc/EOF 不写文件。
- 发布复用已有配置事务：private source digest 与文件 identity 的前后复核、临时文件
  重读/schema 校验、同目录原子替换与目录 flush。已知失败保留草稿可重试；
  同字节新文件对象也报 ConfigStale，要求显式 reload；ConfigPublishUnknown 消耗草稿并停止。
- 无新增原生 API、依赖、长期配置文件、备份机制或外部编辑器。

## 证据

新增 11 个测试覆盖未知/重复记录、多个无效中间态、编码错误、BOM/换行保持、
秘密值不投影、伪造/跨 owner 草稿、输入/数量/页数限制、外部写入与文件替换、
临时文件校验、已知失败重试、unknown 停止，以及完整 CLI 的隐藏输入/取消/精确保存。
Linux 与合成 Windows ports 运行同一 production composition；它们不是目标系统验收。

真实 Windows 测试全部在用户指定的 `192.168.10.104:26222` 上进行，该机实际为
Server 2025 x64。隔离目录 `C:\Users\Administrator\yaca-preview-20260914-01\n5-app`
只含合成配置及测试程序，没有真实模型凭据或请求。

1. 显示第 39 行 unknown-key；隐藏输入替换行后取消，原 SHA-256 不变。
2. 显式删除坏行，完整验证后原生发布成功。
3. 草稿形成后将配置换成同内容的新文件对象，保存报 ConfigStale。
4. 显式 reload 后重新编辑，以当前版本保存成功；全部未修改字节完全一致。
5. 终端记录没有原值或新输入标记；退出后数据目录只有 CONFIG.ini，没有临时文件或 Context。

原无效配置 SHA-256：`36E71DB5F8F6727D3F77815A383F51761683C8C385148AAEB5B5BD692CF08CC4`。
修复配置 SHA-256：`05B4DAEABD2AA2F2AED1C0395C0F0091DC50CFCE2E4EC288950A539633A633F6`。
日志在 `out/config-repair-20260914/`；`replacement-attempt.log` 是失败的 .NET fixture 准备，
有效竞态证据为后续 `replacement.log` 和 `race-console.raw.log`。

最终 zip 与对应源码归档位于 `out/windows-preview-20260914-n5`，SHA-256 见
`SHA256SUMS.txt`；构建摘要绑定干净提交，部署后的日志另存 `remote-evidence/`。

剩余：Model/Permission 区域管理、在线 Stage 2/3 production adapter、真实 XP SP3 /
Server 2008 非 R2 与其他正式目标的 C32--C34 验收；现代远端结果不替代旧系统资格。
