# fs / textcodec / process 与 tools 写发布路径语义 Review

日期：2026-10-01。起点为本地 `main` 与 `origin/main` 一致的 `9188a2e`，工作区干净；
按 [TRACKING](TRACKING.md) P0 队列推进人工语义 Review，本轮不改变产品源码、配置或发布门。
承接 [R55--R72](KERNEL-REVIEW-2026-09-30.md)；R01--R53 各批继续适用其记录范围。
同日下午续推 model/runtime/session/context 的发布与恢复边界并发现 R73，
两个 Windows 核心随源码修复刷新；见文末第二批记录。

## 范围与方法

按队列先核对 `src/fs.lua`、`src/textcodec.lua`、`src/process.lua` 的错误与资源收尾，
再补 `src/tools.lua` 写入侧发布路径的人工结论。读取/分页/尾读/搜索/身份复核与
附带索引已由 R23--R33、R51--R53 覆盖，本轮不重复。方法为整模块通读加专项探针：
对每条错误路径构造有限 fake 端口与故障注入，核对错误传播、句柄恰好一次关闭、
清理只删自己创建且身份匹配的对象、Unknown 结果不做猜测性删除。

本轮未发现缺陷，没有新增 R 编号；探针保留为后续回归的参照。

## 核对结论

| 模块 | 核对的子面 | 结论 |
| --- | --- | --- |
| fs.lua | `observe_closed_write` 的多块/空载荷/大小不符/内容不符/read 失败/句柄 stat 失败/开启后漂移/读后漂移；`acquire_lease` 的写入、flush、stat、close、回读漂移与目录持久化失败矩阵；`release_lease` 的删除失败重试与持久化未知后退役；外来租约拒绝 | 每条失败路径句柄恰关闭一次；创建失败清理只删除对象身份匹配的文件；无法绑定创建身份时不猜测删除（与租约崩溃语义一致）；目录 flush 失败在已发布/已删除两个方向都返回明确的 Unknown 码 |
| process.lua | 双通道头尾保留与配额（含截断、丢弃、观测计数）；poll 预算违反、终态后再出数据、终态后空轮询不再触达 native；join 与已观测终态矛盾；created/started/joined/closed 生命周期与二次使用拒绝；Windows 名称折叠去重、inherit_filtered 的禁用名单、minimal 白名单；组件 argv/stdin 边界 | 预算与次序违反在状态机上保持端口可用并可取消关闭；join 矛盾在迁移 joined 前抛出；配额计算与保留字节精确一致（探针逐项核对 discarded/retained/truncated） |
| textcodec.lua | 标签归一化矩阵（含 `cp0`、超长数字、`utf8-bom` 类近义拼写、ISO 部分、别名）；Windows facts 的 65001 映射；decode 严格/有损与 exact 契约；encode 必须精确；native 异常与非法形态包含；POSIX locale 优先级与未知字符集 | 无权限的有损结果按 NativeContract 拒绝；native 错误码原样透传；`utf8-bom` 等未登记拼写明确拒绝而非猜测 |
| tools.lua（写侧） | `write_all` 分块；`cleanup_created` 的再检视与对象/父目录/祖先一致性；`create_and_fill` 全部退出路径；`publish_create`/`publish_replace` 的临时冲突、Unknown 不删、目录持久化、行为摘要/保留证明/链接数与回读摘要后置条件；`execute_write`/`execute_patch` 的基摘要复核、编码一致、无变化短路；`execute_rename`/`execute_delete` 的摘要/空目录复核与后置条件 | 创建句柄在每条退出路径关闭；替换失败仅清理自己创建且未变化的临时对象；Unknown 结果（替换、改名、删除）一律不猜测删除；后置条件失败返回 PublicationUnknown/RenameUnknown/DeleteUnknown 并保留事实 |

## 探针证据

探针 `out/review-20261001/probe_fs_textcodec_process.lua` 使用仓库锁定 Lua 5.5.1
（上一轮 `out/review-20260930/runtime/` 构建）经资源守卫串行运行，36 项断言用例
**36/36 通过**，日志 `probe-run.log`。用例本身发现并改正了三处探针构造错误
（lease 元数据上限、output_limit 必填、成功路径两次关闭的期望），均属探针问题，
不涉及产品源码。

同工作区完整 Lua suite 复跑 **697/697**（日志 `full-suite.log`），与 9 月 30 日
收尾复核一致；本轮未修改任何产品源码，注释结构检查（219 文件 / 5256 声明）与
四个校验器结果继续适用。

## 边界

本轮结论覆盖上表子面，不扩展为 fs/process/textcodec/tools 四个模块全量语义
Review 完成，更不代表 model/runtime/session/context 的发布与恢复边界已核对。
后三者按 TRACKING 继续；执行到外部依赖（Windows Python 3.8.20 工具链、模型联网
配置、指定实机）时如实记录，不降低检查。

## 第二批：model / runtime / session / context 的发布与恢复边界（R73）

同日续推队列第二项。方法为整段通读加组合根取值核对，发现一个跨端口边界缺陷：

**R73：model 活动队列上限未绑定适配器事件上限。** 一次终态 Provider 响应在
排空后的空队列里最多入队 `maximum_events + 2` 个事件（canonical 标记、全部
适配器事件、终态 response）。组合根取 `maximum_queued_events = 16386` 恰好
等于 `maximum_events(16384) + 2`，但该关系只靠两个魔法数字维持：
`new_activity` 不校验它。若有人调大响应会话事件上限而不同步队列上限，终态
批量会在 `append_output` 处失败，活动永远到不了 terminal 而底层 attempt 已
关闭，请求悬挂到外层截止。与 `context.new_store` 校验 lease 上限对 hostname
的既有跨端口模式一致，修复把该不变量改为入场校验：适配器声明 `limits` 时，
`maximum_events + 2 > maximum_queued_events` 拒绝构造（`InvalidModelActivityOptions`）；
无 `limits` 声明的端口不受影响。

修复前反例失败（专项 6 项中新增用例 FAIL）、修复后 **6/6**，日志
`r73-focused.log`；完整 suite **698/698**、注释反例 **15/15**、全仓
**219 文件 / 5266 声明 / 0 缺项**、四个校验器 **PASS**，完整 coding readiness
链 **PASS**（TP-003 453、TP-006 319、TP-008 321、TP-010 5,564,743、RP-001），
`readiness-full.log`。TP-008 需要的 xmllint 使用 9 月 30 日暂存的
`proof-deps/root`（本机未装包、sudo 需密码）；RP-001 依赖的 luainstaller
v1.3.0 固定提交 `97192d1` 经远端核对仍指向该提交，兄弟仓库已重新取回标签后
通过。

第二批人工核对结论（无缺陷部分）：

| 范围 | 核对内容 | 结论 |
| --- | --- | --- |
| context.lua | `new_store` 的 acquire/recover/publish/move/delete/close 全部退出路径；`stable_read`/`write_new_document`/`copy_file_verified`/`verify_document_path`/`cleanup_file` 的句柄与身份收尾；`validate_publication_document` 的代数与不可变前缀；`new_operation_service` 的 intent/result 屏障与 fail-stop；`validate_relations` 的恢复水位推导 | 句柄在含解析失败的每条路径关闭；previous 文件先建后换、Unknown 不猜删；result 提交歧义永久封锁新副作用；恢复数据只审计不重放 |
| session.lua | `publish_first` 的随机名/冲突/未知发布重试；`open_existing` 的凭据绑定、视图重建、压缩生命周期恢复与崩溃遗留统一按 unknown 收口；`service.commit` 的批次绑定、prepare 视图、非 DestinationExists fail-stop、回执精确核对；operation/compaction journal 适配；`new_agent_session` 草稿观察与陈旧拒绝 | 恢复闭环完整；恢复失败时释放租约并如实报告 ContextLeaseUnknown；草稿只在 Runtime 接受后消费 |
| model.lua | `M.new` 的弱键状态、streaming 策略与单次回退；`new_activity` 的单调时钟、deadline 溢出、attempt 生命周期与关闭、取消归属、poll 预算与终态排空 | 单活动与取消归属与 R55--R67 内核语义一致；终态批量边界由 R73 修复补齐 |
| runtime.lua | `commit_events` 的回执精确核对与代数单调；`adopt_external_receipt` 的外部屏障采纳（不重放、水位推进） | 与工具 operation 屏障的跨模块衔接一致 |

### Windows 核心随源码刷新

R73 修改 `src/model.lua` 后，9 月 30 日刷新的两个 Windows 核心相对源码过期。
按当日 `refresh_win32.sh` 同一流程复用已核对的原生构件，重生成 Lua 载荷与
launcher/extractor 并重新打包（`refresh_r73_windows.sh`，日志
`windows-refresh-r73.log`）。本机验证：两核心 `--version` 正确；win64 Stage 1
**12 PASSED / 0 FAILED**（`win64-stage1-r73.log`）；win32 在本机 x64 上同
冒烟 **12 PASSED / 0 FAILED**（`win32-stage1-r73.log`，不作为旧系统目标资格）。
现行核心 SHA-256：

| 目标 | SHA-256 |
| --- | --- |
| Win32 | `52e9dcb260c24c05ff03de6611c7b18150caa4506423f6149bcffe3225fbfdea` |
| Win64 | `ce92edcfe77986b6aa6ddeb383a614399fed9841d532ed8c3db013dd8de5b478` |

9 月 30 日的 `857680...`/`a75a10...` 保留为上一源码代的证据。win32 的
Server 2008 目标端 Stage 1 与 Linux 当前源码重建（`build_linux_x86_64.sh`
硬性要求真实 CentOS 7 / glibc 2.17 / GCC 4.8.5 主机）继续由 TRACKING 跟踪，
本工作区不满足该主机条件，未放宽检查。

### 第二批边界

以上结论覆盖列出子面；全仓语义 Review 剩余 cli/main/tui/config/json/xml/
path/safety/prompt/permission 等模块未整册核对。发行资格与 Gate R 维持关闭。
