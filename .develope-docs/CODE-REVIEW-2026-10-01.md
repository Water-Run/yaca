# fs / textcodec / process 与 tools 写发布路径语义 Review

日期：2026-10-01。起点为本地 `main` 与 `origin/main` 一致的 `9188a2e`，工作区干净；
按 [TRACKING](TRACKING.md) P0 队列推进人工语义 Review，本轮不改变产品源码、配置或发布门。
承接 [R55--R72](KERNEL-REVIEW-2026-09-30.md)；R01--R53 各批继续适用其记录范围。
同日下午续推 model/runtime/session/context 的发布与恢复边界并发现 R73，
两个 Windows 核心随源码修复刷新；随后完成剩余命名模块的语义 Review 并按
D-078 收敛 notices 布局；见文末第二、三批记录。

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

## 第三批：剩余命名模块语义 Review 与 C33 notices 布局收敛

按队列核对 TRACKING 点名的剩余模块，方法为整册通读加与既有测试/证明的
交叉引用；本批未发现缺陷，无新增 R 编号。

| 模块 | 核对内容 | 结论与既有证据 |
| --- | --- | --- |
| safety.lua | 流式摘要句柄收尾、绑定编码的无歧义长度前缀、秘密注册表的按目的地揭示、流扫描器跨块重叠（最长模式-1 的保留尾）与新观察边界去重 | 跨块匹配的数学关系逐步推演成立；TP-006 的 scanner 统计即该扫描器的真实注入证据 |
| permission.lua | 能力 rank 取最严、审查只升不降且 blocked 粘性、审批快照绑定摘要/操作/调用三重身份、单次消费、历史审批仅审计 | 与 R55--R67 的审查者语义一致 |
| path.lua | 三根（posix/drive/UNC）解析与 `..` 底线、逻辑路径规范性、`from_logical` 对 `\`/`:` 段的拒绝、整段式 `is_within_root`、Context 名控制字符拒绝 | UNC/驱动器往返与折叠比较已有 path_test 覆盖 |
| json.lua | RFC 8259 数单词法、`\u` 代理对的字节级索引推进、控制字节与重复键拒绝、深度/节点/字节预算、写端 active 标记全错误路径清理、减法式上限防溢出 | 代理对与控制转义有 json_test 专项用例 |
| prompt.lua | 构造时以注入摘要端口验证固定控制契约摘要、四类 authority 分层、review 场景把层内容降为 quoted-data、组件 NUL 分隔清单 | 控制契约摘要与 wire 清单的绑定方式自洽 |
| xml.lua | 读端禁 PI/DTD/实体/外部实体的安全回调面、全部结构上限、abort 后首错优先；写端事件配额与读端对称、多根/序号/关闭名校验 | unit/xml 的 12 组安全与限额用例覆盖 |
| tui.lua | 铬层仿冒前缀保护、Unicode 隐藏控制可见化、append-only 序列、输出不确定即 fault | tui_renderer_test 覆盖渲染面 |
| config.lua | 草稿不可变链、编辑/新增/改名/移动的全代复验、`write_temporary`/`verify_temporary` 的对象绑定清理、`commit_draft` 的准入守卫前后复核与 Unknown 不猜删 | 与 context store 同一发布纪律 |
| cli.lua | argv 的 end-of-options、单主命令、命名值禁选项前缀、行命令引号转义、布尔仅末位、非 TTY 确认需 `--yes` | cli_parser_test 覆盖解析面 |
| main.lua | 运行时根仅来自可执行文件身份（不取 cwd/PATH）、外内可执行必须不同、Windows 折叠比较；组合根其余接线由集成测试面覆盖 | bootstrap/first_run/production_agent_composition 集成套件；13.5k 全册人工通读仍留待后续批次，如实记录 |

### C33 notices 布局收敛（D-078）

按 [D-078](DECISIONS.md#d-078-notices-归档统一为装配布局2026-10-01) 把
`windows_package.py` 的 notices 归档改为装配布局：companion 全部成员置于
`core/` 下，根级新增与 `package_editions.py` 逐字段同构的 `edition.json`
（`yaca-edition-v1`、clean、`release_authorized=false`）与 `SBOM.spdx.json`。
两个 Windows 目标已重打包；资格与装配两路径的 notices 成员名集合逐项一致
（**16=16**），edition/SBOM 结构一致，验证脚本 `verify_notices_shape.py`
输出 `notices-shape=CONVERGED`。载荷 zip、源码包与既有装配证据不受影响；
装配单测 **5/5**、注释 **219 文件 / 5266 声明 / 0 缺项**、四校验器与完整
suite **698/698** 复跑通过（`verify-r2.log`）。

九包的最终干净机旅程仍按 TRACKING P1 队列执行；本批只收敛形状，不宣称
发行资格。发行资格与 Gate R 维持关闭。
