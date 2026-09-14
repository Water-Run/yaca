# N4 Context 导出、选择和跨工作目录继续

日期：2026-09-14。基于 N3c `11e0fa2`，完成 Context 管理器剩余两项投影。
完整 suite **531/531**；validators **7612/56/553**，TP-003/006/008/010 与 RP-001 PASS。
Release Gate R 仍关闭，首版整体未完成。

## 行为

- 管理器 `export <selector>` 复用公开 `--export` 的精确只读验证和 Markdown 格式化。
  含已登记秘密值、变化目标或活动 writer 时拒绝正文输出；无 selector 返回 NoActiveContext。
- 管理器 `select <selector>` 先创建只读预览，再恢复并关闭管理终端，最后交接给 chat。
  不在管理终端内部申请 writer 或构建 Agent。
- `--continue`、`select` 与聊天 `.context` 共用私有、一次性预览。
  预览绑定原文件凭据、精确 hash/路径、来源目录身份和记录目录身份。
  新预览使前一预览失效；伪造、重复或跨配置 owner 的交接拒绝。
- 跨目录时展示两个目录，精确输入 `CONTINUE <hash>` 才取得新 writer。
  管理器取消保留管理回路，CLI 取消正常退出；聊天取消保留原会话。
  同目录不增加确认。管理器 EOF/Esc 恢复终端并退出。
- 聊天确认期间允许状态/帮助/详情/取消/退出，不把确认文本发送给 Model。
  原 owner 在接受确认且 queue、side、approval、compaction 状态均安全后才关闭。
  新 composition 再复核原选择，关闭后的竞态会结束本次调用，不打开替代文件。
- 新 Agent 的 workspace 来自 Context 记录目录；Tools 使用该显式目录，XML 不搬迁，
  进程 cwd 不改变。聊天后续预览以当前 Agent 的 workspace 为来源，不退回进程 cwd。
- 确认的目录身份传入 Agent 组合：初始快照、端口构建及后续 main/side 快照前后复核，
  Tool 授权保持同一个身份。目录替换返回 ContextTargetChanged，不能静默绑定新根目录。
- 确认不绕过未决 operation/tool、unknown、queue、compaction、完整配置或 ModelReady 门禁。
  不自动重放任何历史操作；打开失败释放 writer。原生 API 与 N3c 相同。

## 验证

新增回归覆盖管理器导出/交接/取消/EOF、私有提案防伪与失效、同 hash 文件替换、
两个目录在确认/打开/配置后的变化、未决历史和无效配置、聊天取消及目录切换、
Agent 组合前/初始快照中/端口构建中与后续 main/side 快照的目录替换。

用户指定 SSH 远端实际为 Windows Server 2025 x64；Windows 程序只在该远端运行。
隔离根目录 `C:\Users\Administrator\yaca-preview-20260914-01` 下使用独立 `n4-app`。
测试没有真实服务商凭据、Model 请求或计费：

1. 管理器导出完整 Markdown；目标被活动 writer 占用时，第二进程导出拒绝正文。
2. 选择跨目录目标后取消，继续管理；确认期间替换为同内容新文件对象，TargetChanged。
3. 管理器选择后进入记录目录的 Idle Agent；聊天取消切换保留原 Context。
4. 聊天确认切换到第二个目录，再确认返回；重复选择当前 hash 保持当前会话。
5. 公开 `--continue` 确认后进入记录目录，状态为 generation 46、Idle、queue 0。
6. 正常退出后，两份 XML 的 SHA-256 不变，没有新增 writer/临时文件残留。

合成数据 hash：`EAE693F1F10BC3BC`（repair-packaged）、`D80943A340519867`（repair-missing）。
对应 XML SHA-256：

```text
79DBCDB2137979E58A3409C48230F6E922BCBF137D0828D4A1D40053AE4006FF
699D644E78EB28500A2EE7E6FE059C51667F76542AE9500F072E04F895FCEB5F
```

本轮日志在 `out/context-continue-20260914/`。最终包目录为
`out/windows-preview-20260914-n4`，含 zip、对应源码归档和 SHA256SUMS.txt；
构建摘要记录提交与干净源码快照。部署后的验证日志复制至 `remote-evidence/`。

## 剩余工作

无效 INI 的交互修复、Model/Permission 区域管理、在线 Stage 2/3 production adapter，
以及 C32--C34 真实目标资格仍未完成。XP SP3 / Server 2008 非 R2 的兼容方向不变，
现代 Windows x86 烟测和静态导入审计不能替代旧系统执行证据。
