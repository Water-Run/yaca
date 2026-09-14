# N3b Context 原位导入检查点

日期：2026-09-14。基于 N3a `89fee2c` 接通 `import <in-place-xml-path>`。
完整 suite **511/511**，定向 suite **46/46**；validators **7612/56/553**，
TP-003/006/008/010 与 RP-001 全部通过。N3 typed repair 尚未完成，Gate R 仍关闭。

## 行为

- 用户先把 XML 放到正确镜像位置。controller 从明确文件路径经过生产 verifier、
  capture_target 与 verify_target 捕获精确选择；不依赖列表投影、不复制来源、不猜同名替身。
- 先只读校验 schema/大小/一致性，显示 validated-readonly。busy 对象不会打开正文。
  随后列出可用本机 Model/Permission，要求明确选择；只有原名仍可用时提供同名默认值。
- 以选择的 Model/Permission 加上原 XML 的其他 overrides 重载完整 INI，生成绑定
  source credential、canonical document digest、config generation 和 workspace 身份的
  私有一次性提案。预览前构造完整可验证的新 generation，尚未取得 writer。
- 目标 workspace 必须存在、可进入且符合镜像绑定；缺失/重定向时明确要求 rebind。
  预览显示旧/新映射、workspace 与未决 operation/tool 数，要求 `IMPORT <hash>`。
- 确认后重新验证同一 selection 并完整重读 INI；配置 generation 变化即拒绝。
  短期 writer 取得后再核对 canonical document digest，并在发布前后复核 workspace。
- 在同一次 whole-XML publish 中更新 Session.CurrentModel、CurrentPermission 及真实
  local snapshot digest，追加含旧/新名称和 snapshot 的 import_mapping 事件并推进 UpdatedAt。
  CreatedAt、路径/hash、ContextPrompt、命名与 DoubleCheck overrides、历史事实保持。
- plain/compacted ModelView 都由真实事实生成，保存后下一进程可重建；保留已接受摘要。
  历史 approval 只作审计，pending/unknown operation 保持未决；import 不启动 Runtime，
  不发 Model 请求，不取得历史 grant，不自动恢复或重放操作。
- 已知失败释放 writer 后可继续；unknown、异常或清理失败停止管理 owner。
  没有新增 native/Win32 API。

## 验证

新增/扩展回归覆盖有效双映射与真实 snapshot、只读规划/取消、镜像外路径、busy、
不可用 Model/Permission/workspace、其他 overrides 意外变化、确认期间配置和来源变化、
目录变化、publish/unknown 失败、一次性提案、普通与压缩历史重建。
带历史 approval 和未决 operation/tool 的 XML 导入后仍保留未决集合，重开 auto_continue=false。
真实 store fault 用例同时断言有效 Session 映射和禁止自动继续。

指定 Windows Server 2025 x64 远端使用独立 `n3b-app`、合成配置与此前测试 Context：

1. 只读预览后取消，XML SHA-256 保持 `DE9DDE593FA76B05E60881EE15B931996EB0E14AA080FC4095E334DC89D67DD5`。
2. 在最终确认提示期间修改测试 INI，返回 ConfigGenerationChanged，未发布映射。
3. 重新规划并确认后，generation 43 将 Primary/Std 映射到 ImportedLocal/ImportedStd；
   Session 元素保存新名称和真实 digest，事件包含相同映射，hash 仍是 `72EC41AB918537EA`。
4. 新进程 `--continue` 进入 Idle，显示 ImportedLocal/ImportedStd，历史成功重建。
5. 保持该 writer 时，另一 Context 管理器的 import 被拒绝，不出现 validated-readonly。
6. 退出正常释放 writer。全过程未请求真实模型、未操作正式用户目录。

证据在 `out/context-import-20260914/`。现代 Windows x86 运行结果不替代 XP/Server 2008、
Win7、CentOS 7 正式资格。

## 接续

下一项 N3c typed repair：先生成绑定 official/previous/lock 身份的只读计划；确认前不能
调用会申请 writer 并恢复 previous 的 store.repair。随后是管理器 export/continue、无效 INI
修复、Model/Permission 区域管理、在线 Stage 2/3 adapter，以及 C32--C34。首版整体仍未完成。
