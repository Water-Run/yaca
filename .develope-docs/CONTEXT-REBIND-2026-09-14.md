# N3a 显式 workspace rebind 检查点

日期：2026-09-14。基于 N2 `986e0ca` 接通 `rebind <selector> <target-root>`。
N3 的 import/typed repair 尚未完成；首版整体目标与 Release Gate R 仍未完成。

## 行为与事务

- 只读规划不取得 writer、不读取正文、不创建镜像目录。当前 owner 只保留一份
  私有一次性提案，绑定 Resolver credential、目标逻辑路径与完整目录快照。
- 目标必须是已有、可进入、无重定向的普通目录。显示原 Context 与新目录/路径/hash
  后要求 `REBIND <旧hash>`；取消不修改文件。确认后重新验证同一 Context selection。
- writer 取得前、发布前与发布后复核目标目录的路径、对象身份、元数据和祖先。
  提案过期、目录替换、来源变化、活动 writer 或重名目标均拒绝；发布期间目录变化
  按 unknown 停止管理器，不声称绑定有效。writer 获取发生 unknown 同样停止 owner。
- 复用 no-replace `store.move(..., "rebind")`：完整 XML 同时写入 rebind 事件和新的
  UpdatedAt；CreatedAt、名称、命名设置及历史保持。事件记录 old/new logical path
  和已观察目录身份的 digest；原目录不可观察时明确写 `unavailable`，不伪造旧身份。
- 新 generation 的真实 ModelView 包含迁移事实，保留已接受的压缩摘要及后续事实。
  成功后新镜像父目录成为唯一绑定，旧 hash 失效。继续仍须从新目录调用 `--continue`。
- 没有新增 Win32 API；旧 Windows ABI/API 基线保持不变。

## 验证

完整 suite **506/506**，其中定向 publication/REPL/store 管理 suite **41/41**。
覆盖只读计划、私有/过期/伪造提案、取消、缺失/别名/不可进入目录、同目录拒绝、
确认后来源变化、目录在获取 writer 前/后或发布期间变化、busy/collision/unknown，
以及普通和已压缩历史的重开。

validators **7612/56/553**；TP-003/006/008/010 和 RP-001 均 PASS。
TP-010 的上游下载两次遇到 TLS EOF，新增显式 `YACA_PROOF_SOURCE_CACHE` 读取已缓存
归档；每次仍核对锁定 SHA-256 并在临时目录重新编译，不降低检查。TP-010 当前脚本
hash 已更新，历史 proof manifest 的原始 source digest 保持；本次源码与结果另存。

指定远端为 Windows Server 2025 x64，SSH 26222。测试使用独立 `n3-app` 和此前合成
模型 Context，未访问用户正式目录中的会话/密钥，也没有发送真实模型请求：

1. 预览后取消，原文件保持。
2. 在确认提示期间将目标目录改名并创建同名新目录，确认返回 ContextWorkspaceChanged。
3. 重新规划并确认成功：`393AC7EC24DBFB81` → `03A1CC3FBD9A1B92`；原官方 XML 消失，
   CreatedAt 保持，generation 41 包含两个真实 root identity digest，没有事务残留。
4. 在旧位置放入测试用同名文件后尝试回迁，返回 DestinationExists；随后删除该测试副本。
5. 从新目录 `rebound-work` 用新 hash 重开，生产 Agent 进入 Idle，`.status` 确认新绑定，
   `.quit` 正常释放 writer。

证据位于 `out/context-rebind-20260914/`，包含原始终端输出、XML、检查日志与回归结果。
这些只证明现代 Windows 的 x86 运行结果，不替代 XP/Server 2008、Win7、CentOS 7 资格。

## 接续

下一项是 N3 in-place import 与 typed repair：import 必须实际应用有效 Session 的
Model/Permission 映射；repair 必须先有只读身份绑定计划，确认前不能调用有恢复副作用的
store.repair。之后继续管理器 export/continue、无效 INI 修复、区域管理、在线自检
Stage 2/3 与 C32--C34。
