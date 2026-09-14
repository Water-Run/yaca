# N3c Context 显式修复检查点

日期：2026-09-14。基于 N3b `34a81c7` 接通 `repair <selector>`。
平台无关 suite **520/520**，管理相关定向 suite **72/72**。
Release Gate R 仍关闭；首版整体未完成。

## 行为与边界

- planner 只读检查精确 official、命名 `.yaca-prev`、锁和完整目录祖先身份，
  不申请 writer、不恢复文件。活动锁一律拒绝，不凭锁龄破锁。
- official 缺失时，catalog 只把它自己的 previous 投影为 unavailable 的 official 路径。
  单独绑定 recovery_stat；普通 inspect/open/delete 不能把该观察升级成有效 XML。
  损坏 official 仍绑定它本身的精确身份。任何路径都不跟随重定向。
- previous 必须通过完整 schema/关系/一致性和 ModelView 重建，Name 与目标匹配。
  有可信 CreatedAt 时必须匹配；有效 official 的 previous 还必须是同一 Context 的事实前缀。
  不猜测其他临时文件，不拼接损坏 XML，不删除有冲突的 previous。
- 确认前显示 restore-previous 或 clean-previous、来源、目标和最终清理路径；
  用户输入 `REPAIR <hash>` 后，复核原选择、文件内容、目录及文件身份。
  提案私有、一次性。取消只读；有效 official 且无 previous 时返回 unchanged，不创建 writer。
- 确认后短期持有 lease，发布新的完整 XML generation：保留 CreatedAt、原事实、有效
  Session 和普通/压缩历史，追加 PreviousValidRestored/Cleaned warning 与匹配的真实 ModelView。
  UpdatedAt 在实际确认时推进。新 official 刷盘并验证后才精确删除 previous，并再次验证 official。
- 不启动 Runtime、不调用 Model、不恢复历史审批、不清除未决 operation/tool，也不重放它们。
  no-repair-needed 只表示不需要 previous-file 修复，不宣称语义未决事项已经解决。
- 来源/目标/锁变化拒绝。发布或清理不确定、异常、lease 释放失败立即停止管理 owner；
  保留仍存在的恢复证据，不把 unknown 当作成功。旧的隐式 store.repair 未接到新 controller。

## Windows 原生替换修复

真实远端发现两个此前 fake adapter 无法发现的差异：复制继承型 DACL 时，原 setter
可能保留临时文件的旧继承标志；ReplaceFileW 替换旧式 DACL 时又可能添加 AUTO_INHERITED
和匹配 ACE 的 INHERITED_ACE 标记，导致正确内容发布被严格元数据校验拒绝。

现在复制描述符时显式请求继承控制赋值。对 ReplaceFileW 的后处理，只有发布/置换文件
身份均匹配、置换文件元数据完全匹配、发布文件的差异仅为上述继承模型转换时，才恢复
原始描述符。恢复后仍要求完整 security descriptor、属性和身份完全一致；权限主体、
access mask、ACE 顺序、其他标志或元数据变化不会被归一化为成功。失败保留恢复文件并报 unknown。
本次新增的 GetAce、GetSecurityDescriptorControl/Dacl、SetSecurityDescriptorControl 均使用 XP 基线 API；
没有引入 Vista 以上静态导入。

微软说明：[继承控制位](https://learn.microsoft.com/en-us/windows/win32/secauthz/security-descriptor-control)、
[SetSecurityDescriptorControl](https://learn.microsoft.com/en-us/windows/win32/api/securitybaseapi/nf-securitybaseapi-setsecuritydescriptorcontrol)。
保留原 handle setter 以恢复精确的旧式描述符，避免文件系统高层 setter 自动升级其继承模型；
这是一条有完整前后验证的兼容路径，仍须在真实 XP/2008 文件系统验收。

## 验证

Lua 回归覆盖缺失/损坏主文件、有效旧副本清理、无操作、取消、一次性提案、目录/文件/
锁竞态、确认后替换、写入/flush/cleanup/release 异常与 unknown、压缩历史和未决操作保留。

指定 SSH 远端实际上为 Windows Server 2025 x64。本轮只用独立 n3c-app 和合成数据：

1. 缺失主文件预览后取消，previous SHA-256 不变，未创建主文件或锁。
2. 确认期间将 previous 替换为同内容的新文件对象，ContextTargetChanged，未写主文件。
3. 重新规划后恢复缺失主文件，generation 45；损坏主文件也成功恢复到 generation 45。
4. 无 previous 时再次 repair 返回 unchanged。放入同历史旧副本后 clean-previous 成功，
   generation 46；新进程从对应 workspace 继续，重建历史并进入 Idle，未发 Model 请求。
5. Windows 原生 smoke 分别验证旧式和继承型 DACL 替换后完整 behavior digest 一致、
   内容正确、无临时/置换副本残留。继承型夹具由 Set-Content 后 Set-Acl 显式建立。
6. windows_metadata_smoke.c 验证仅继承模型转换可进入恢复分支；属性、access mask、
   SID 字节和其他 ACE flag 变化均拒绝。该测试直接编译生产 native 源码，在远端运行。

排查期间旧 native 的失败留下两份 repair-damaged 临时 XML；它们作为 unknown 现场保留，
后续成功 repair 不擅自清除未绑定的历史临时文件。对应 previous 与 writer 锁已正常清理。
最终安装包另外使用全新 repair-packaged 夹具验证，避免将排查现场混作干净安装证据。

可丢弃证据位于 `out/context-repair-20260914/`。现代 Windows x86 smoke 不替代 XP/Server 2008、
Win7、CentOS 7 正式资格。Windows 程序未在用户本机运行。

## 接续

下一项管理器 export/continue 与跨 workspace 继续确认；随后是无效 INI 修复、
Model/Permission 区域管理、在线 Stage 2/3 production adapter 和 C32--C34。
