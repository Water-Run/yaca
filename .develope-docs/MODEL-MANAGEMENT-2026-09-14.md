# N6 离线 Model 管理

日期：2026-09-14。基于 N5 `ab7f4ad`，接通有效配置的 Model 管理表面。
完整 suite **556/556**；design-contract / proof-evidence / coding-readiness validators
**7612/56/553**；TP-003/006/008/010 与 RP-001 PASS。Release Gate R 保持关闭。

## 范围与行为

- `--model-repl` 的 list/show/set/unset/add/rename/delete/move、preview/save、
  reset/reload/cancel/quit 已接通；新增空白向导含 `.back`，没有 clone。
  首次设置也使用完整验证后的私有候选，再显示 APPLY；取消不创建数据。
- 每轮变更递增 `model-edit-N`，行绑定为 `model-edit-N:ordinal`；排序后不能复用旧行号。
  物理首项为默认 Model，禁用默认项如实显示 Agent 不就绪；至少保留一个启用 Model。
- 字段输入沿用完整 typed INI schema，Key/AdapterOptions 隐藏；endpoint query 不显示值。
  新增不继承凭据，预览扫描旧/新 generation 的已注册秘密，列表联网状态为 untested。
- 新增、精确重命名、删除与物理顺序调整共享配置 owner 的私有草稿、源 digest、
  文件 identity、临时文件验证与原子发布。INI reviewer 引用随 rename 一起更新。
  未改变的 section block、BOM、换行和注释保留；移动 EOF block 时只补必要分隔。
- 涉及原名称消失/禁用时，预览必须获得完整 Context catalog 和经复核的规范正文，
  并列出引用 Context。busy/corrupt/partial/解析失败拒绝保存。
  M05-34 已选 A 允许影响确认后保存，不能误作 B 的一律阻断。
  不改写 XML/历史；后续继续时仍需显式映射，不创建失败 fallback。
- 保存确认绑定本次预览；创建临时文件前和发布前复核所有引用绑定。
  变化、已知失败保留草稿；新的 save 需要新预览；ConfigPublishUnknown 消耗草稿并停止。
  复核不声称对多个 Context 文件提供跨进程全局原子快照。
- config-repl 中 Model 仅摘要；Permission 按 M05-48 **已选 B / AS-006-12** 编辑现有
  字段，增删改名排序通过手工 INI。此前的“完整 Permission 管理待办”已校正。
- 资源名称新增同类型 ASCII fold 碰撞拒绝；全部 selector 入口的 M05-57 语义复核仍待办。

## 验证

新增 14 个测试覆盖 concrete section 变换、完整配置失败与 stale、双重 admission guard
及清理、精确 parser、隐藏输入、空白新增/back/排序、预览确认、完整引用扫描、
损坏/占用/不完整/正文失败及确认后目标身份变化。首次运行中的旧隐藏输入测试已改为
配置 REPL 的 ProxyUrl；更新后的完整测试通过。

远端为用户指定 `Administrator@192.168.10.104:26222`，实际系统 Server 2025 x64。
源码控制台试验使用独立 `n6-app`，复制既有无真实凭据的 N4 fixture：

1. 将 Primary 改为 ManagedPrimary，预览精确列出两个 Context。
2. 确认前将一个 XML 用同字节新文件对象替换，ModelImpactStale；配置未变、无临时残留。
3. 显式新预览并保存成功，配置仅 header 名称改变，两个 XML SHA-256 与 N4 原件一致。
4. 空白添加 NewRemote，通过 .back 修正远端名称，输入合成 Key，移动为默认。
   旧行号拒绝；预览/保存成功，合成 Key 未在控制台回显。不发送 Model 请求。

详细可丢弃日志在 `out/model-management-20260914/`；Windows exe 仅在远端运行。
源码试验开始时 fixture 缺少 application executable 身份文件，补齐后成功；该次失败日志
单独保留，不作为应用功能或目标资格通过证据。
本检查点的最终构建和打包实测证据随 `out/windows-preview-20260914-n6/` 交付；
不能将现代 Windows x86 smoke 当作 XP / Server 2008 非 R2 真机资格。

## 后续

Model 联网测试及在线 Stage 2/3 production adapter、资源 selector 语义审计、
C32--C34 三目标资格仍未完成。首版不是仅剩构建，也尚未达到 Gate R 发布条件。
