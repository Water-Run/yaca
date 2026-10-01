# fs / textcodec / process 与 tools 写发布路径语义 Review

日期：2026-10-01。起点为本地 `main` 与 `origin/main` 一致的 `9188a2e`，工作区干净；
按 [TRACKING](TRACKING.md) P0 队列推进人工语义 Review，本轮不改变产品源码、配置或发布门。
承接 [R55--R72](KERNEL-REVIEW-2026-09-30.md)；R01--R53 各批继续适用其记录范围。

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
