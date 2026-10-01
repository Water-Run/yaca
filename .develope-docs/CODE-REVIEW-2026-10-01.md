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

## 第四批：main.lua 组合根与剩余支撑模块

整册推进 TRACKING 队列尾段，本批未发现缺陷、未修改源码：

| 范围 | 核对内容 | 结论与既有证据 |
| --- | --- | --- |
| main.lua（组合/准入/发布面，1--7476 行整读） | CLI 入口的 native 白名单加载与 ABI/平台准入；应用根的请求字段白名单与生命周期；continue 的三重工作区复核与 `release_opened` 全失败路径关租约；`start_published_agent` 每条构造失败关闭草稿、目录仅空闲替换、恢复串号回填；压缩 owner 的 Runtime 回执采纳与 fail-stop；`compose_runtime` 根仅取自可执行身份、contexts 失败降级不掩错 | 发布/恢复纪律与 context/session 两层一致 |
| main.lua（交互协调器与 REPL，7476--13502 行） | 准入端口/上限校验、`run` 恰一次、关闭次序（等 loop 至 Closing 真值→关草稿→关终端、主错误优先）、生命周期迁移点（8 处 closing→closed）整读；事件分发与渲染内部按结构级核对并由 application_coordinator/repl_input_surface/line_editor 集成面交叉 | UI 状态机内部未逐行通读，如实保留 |
| text.lua | 严格 UTF-8 解码拒收 overlong/代理/超上限；标量编码精确；text/binary 载体弱注册；display 转义含 bidi/不可见区 | TP-010 的 1,112,064 标量与 12 类坏 UTF-8 为实测证据 |
| clock.lua / platform.lua | 单调时钟粘性降级、deadline 溢出检查；平台探针恰一次缓存、目标匹配 | — |
| backend_windows / backend_linux | 架构与目标绑定、固定 cmd//bin/sh 载体、secure_random ≤64 字节边界、UTC/PID 包装的异常包含 | 与 process/terminal 前批结论衔接 |
| ini.lua（解析核） | 引号转义有界、控制字节拒绝、键绑 schema、重复键拒绝、单 BOM、具体前后缀保留供 preserve_concrete 写 | 写端由 config 编辑流“写→重解析→全 schema 校验”闭环验证；ini_test 28 项 |
| diagnostics.lua（脱敏面） | 相邻/重叠秘密区间合并、扫描不可信时 ordinary/path 整条省略；scanner-unavailable 仅在无 ConfigGeneration（即无已注册秘密）时可达 | Stage 1--3 每日实跑为运行证据 |
| network.lua（重试控制器） | 单活动状态机、fresh attempt ID、logical/turn/runtime 截止底线、尝试上限 2+重试+重定向、canonical 事件后禁回退/禁重放 | attempt 载体由 TP-006 真实 curl 链路实测 |
| compact.lua | 断路器/恢复子面沿用 9 月既有结论；source/summary 编码由 `verified_compaction_projection` 的重建-摘要核对与 TP-010 字段往返锁定 | 状态机内部逐行通读仍保留 |

本批无源码修改，前批 698/698、注释与四校验器结果继续绑定当前树。
全仓产品源码的语义 Review 至此覆盖到上表口径：main.lua 交互事件分发
内部、compact.lua 状态机内部、原生 C 层（有独立故障探针）与测试辅助
代码为如实保留的剩余面。

### Windows clean 版位随 R73 源码重装配

本工作区没有 std/full 的工具输入（在原构建机，按外部依赖登记），clean
版位不需要工具输入：`package_editions.py` 以 R73 双核心与 D-078 后的
companion 重新装配 win32/win64 clean 候选（`out/review-20261001/editions/`）。
验证：载荷恰为 `yaca.exe` 且摘要逐字节等于现行核心；`editions.json` 绑定
同核心、`candidate-unqualified`、`release_authorized=false`；资格路径与
装配路径的 notices 归档在**同一核心**上成员集合 16=16 逐项一致
（`verify_clean_editions.py`、`verify_notices_shape.py`）。std/full 版位与
Linux 侧仍待外部输入。

### Server 2008 目标端随 R73 复跑（10-01 晚）

此前安装的 SSH 密钥仍可免密登录指定 Server 2008（`Administrator@192.168.5.10`，
`CYGWIN_NT-6.0-6003 / WIN-TAFWJAAWRX6`），两项目标端证据当场补齐：

| 检查 | 结果 |
| --- | --- |
| R73 Win32 单文件 Stage 1（隔离 `/tmp/yaca-r73-stage1/` + `__yaca__`） | **12 PASSED / 0 FAILED**，`outcome=partial`、`online-requests=0`；配置未初始化与非 TTY 三个警告按既往保留（`stage1-r73-win32.log`） |
| 当前源码完整 suite（`0a41727` 归档 SHA-256 `29bc77af...09ac5`，i686 lua.exe + lxp/yaca_native DLL） | **698/698**，两次运行一致（`full-suite-r73.log`）；`main.lua` 摘要与本地逐字节一致 |

部署通道与既往一致：该机 tar 损坏，改用纯 Lua ustar 展开器
（`server2008/expand_ustar.lua`，跳过 pax 头并整读其数据块）；解释器需要
相邻 `lua55.dll` 并对隔离目录内可执行文件补执行权限。原生 DLL 自 9 月 30
日以来未变（R73 只改 Lua 载荷），昨日原生故障探针继续绑定。

至此 win32 的目标端证据（Stage 1 + 源码 suite）均已绑定 R73 后源码；
Linux 重建、win64 full 的 Python 3.8.20、模型联网旅程与 std/full 工具输入
仍按外部依赖等待。

### Linux 当前源码在真实 CentOS 7 用户态内重建（10-01 晚）

本机 Docker Desktop 可用后，改用**真实 centos:7 用户态**执行
`build_linux_x86_64.sh`：脚本未做任何修改，其自身的主机准入
（`/etc/centos-release` 为 CentOS Linux 7.9.2009、`getconf` 为 glibc 2.17、
`gcc -dumpversion` 为 4.8.5，均为 CentOS 7 官方包 4.8.5-44.el7 /
glibc 2.17-326.el7）原样通过；EOL 的 yum 指向 vault.centos.org 安装工具链。
七项锁定输入按脚本内置 SHA-256 逐项校验通过。

| 结果 | 值 |
| --- | --- |
| 构建状态 | `build-summary.txt` status=PASS；ELF64/x86-64、系统依赖白名单、GLIBC 符号 ≤2.17 基线均由脚本断言通过 |
| 源码 | `b5c0c9ff...`（HEAD），归档 SHA `ea7f597e...` |
| 目标端 suite | **698/698**（构建内 `full-test.log`） |
| 冒烟 | 单文件与 onedir 均输出 `yaca 0.1.0 (linux-x86_64)`；WSL 内实跑同版本 |
| 产物 SHA-256 | `yaca`（单文件）`d06ec9618c73aead0f90bd2d018da9cb9839da80794487ded2c8945f381b5c1c`；`yaca_native.so` `14ebc048...`、`lxp.so` `53f4bb64...`、`curl` `28f2a805...` |

如实边界：容器共享宿主内核（summary 的 kernel 行为 WSL2），CentOS 7 的
真实性与兼容保证来自其用户态工具链/运行库及脚本自身的 ABI 断言；物理
CentOS 7 主机上的干净机旅程（含既有 2.3 GiB 旅程口径）仍属 C33 待办，
本结果不写成实机通过。

### 三平台 clean 版位全部绑定当前源码

以该 Linux 核心装配 `linux-x86_64` clean 版位（core-notices 由构建自身
锁定源码的许可证文本构造，`stage_linux_notices.sh`）；载荷恰为 `yaca`
且摘要逐字节等于 `d06ec961...`，`editions.json` 未授权（
`verify_linux_clean.py`）。至此 clean 版位 win32 `52e9dcb2...`、win64
`ce92edcf...`、linux `d06ec961...` 三席全部绑定 `b5c0c9ff` 源码；std/full
六席仍待原构建机的工具输入。

### Windows std 工具从锁定源码复现并装配两席（10-01 深夜）

重新审视“std 工具输入在原构建机”的前提：输入是**锁定源码 + 仓库脚本**
的确定性产物，而七项 std 源（两个 Python 2.7.18 MSI、Python 源码、
bsddb、7-Zip extra/src、putty 0.85）全部带 URL 与 SHA-256 锁定。据此
按记录管线复现，未改任何构建脚本：

| 步骤 | 结果 |
| --- | --- |
| 源下载校验 | 七文件按锁 URL 获取，SHA-256 逐项一致（`fetch_std_sources.py` → `VERIFIED`） |
| MSI 清单 | `msi_inventory.c` 以 `-municode` 交叉编译后在本机 Windows 上运行，win32/amd64 两份 TSV（3509/3503 行，File 3231/—） |
| 工具构建 | `build_win32_std.sh`/`build_win64_std.sh` 原样运行（WSL 仓库交叉链 + 上游 7zz 26.03 + proof-deps cabextract 1.11），双目标 `staging=PASS tools=4` |
| 版位装配 | 两席 std 以 R73 核心装配；`verify_std_editions.py`：4 工具、3016/3015 文件、入口点/许可证/逐文件摘要精确、notices 形状正确、`candidate-unqualified` 未授权 |
| 本机工具冒烟 | Python 2.7.18（32/64 位，ssl/sqlite3/bz2/ctypes 导入通过）、plink 0.85（32/64 位，NO_GSSAPI，源提交 a3cce3a）、curl 8.21.0+mbedTLS 3.6.7（http/https）、7za 26.03 |

如实边界：工具二进制由本工作区 mingw-w64 13 交叉链构建，与原构建机
产物摘要必然不同；装配器记录 `qualification=pending`，原 std 工具面的
Wine/实机资格不因重建转移，std 版位的实机旅程仍属 C33。`lzma` 模块在
两份 MSI 中均不存在（TSV 零命中），暂存忠实于 MSI 清单。win64 核心
构建树中 `https/` 与 `onedir/.luai/components/cacert.pem` 由 WSL 缓存
复制到挂载路径供 prepare 只读使用。九包进度：clean 3/3、std 2/3
（linux std 待同管线的 Linux 侧构建）、full 0/3（win32 缺 w64devkit/
PortableGit 锁定源，win64 缺 Python 3.8.20，linux full 为重型 sysroot
管线，均维持登记）。

### linux std 版位随当前源码复现装配（10-01 深夜续）

仓库只提交了 linux std 的暂存半程（`prepare_linux_std.py`），构建配方
按其契约与已提交 README 重建并在真实 CentOS 7 用户态执行（容器、
archive.kernel.org/epel 存档源）。配方选择全部入档：

- **python2 2.7.18**：C7 基线系统库（openssl 1.0.2k/zlib/bz2/sqlite/
  gdbm/ffi/expat）构建，`--prefix=/yaca/tools/python2` 后 DESTDIR 落
  `python-root`。锁内 bsddb 树经核实是 MSI 依赖源（无 configure，供
  源码再分发），Linux 构建按 C7 基线**不含** `_bsddb`。
- **putty 0.85**：已提交的 portable 补丁 + cmake3（EPEL 存档，C7 自带
  cmake 2.8 与 putty 的 `-S/-B`/最低版本要求不兼容），原生构建
  plink/pscp/psftp，`-DPUTTY_GSSAPI=OFF -DYACA_PORTABLE_TOOLS`。
- **7zz 26.03**：`makefile.gcc`（Alone2 的 `makefile` 是 NMAKE 语法）；
  C7 的 make 3.82 与 gcc 4.8 均不足，先按 full 锁的 make-4.4.1 源构建
  GNU make，再用 SCL 存档的 devtoolset-11 编译——仍链接系统 glibc 2.17。
- **curl 8.21.0**：复用 Linux 核心构建的静态 curl（mbedTLS 静态链，
  NEEDED 仅 libc/libpthread）与核心锁源码。
- **暂存**：`prepare_linux_std.py` 原样运行，`staging=PASS tools=4`。

装配与验证：`linux-x86_64` std 以 `d06ec961...` 核心装配；
`verify_linux_std.py`——4 工具、4511 文件、入口点/许可证/逐文件摘要
精确、notices 形状正确、未授权。工具冒烟在 CentOS 7 容器内以**副本**
执行（教训：D: 挂载的 mtime 语义会让 python2 直接在暂存树上重写
.pyc、破坏 tool-inputs 摘要，冒烟必须跑在拷贝上）：
`py2-ok OpenSSL 1.0.2k-fips`（ssl/sqlite3/bz2/ctypes 导入通过）、
`plink 0.85 64-bit Unix`、`curl 8.21.0 + mbedTLS 3.6.7`、
`7-Zip 26.03 (x64)`。

九包进度更新：**clean 3/3、std 3/3 全部绑定 `b5c0c9ff` 源码**；full
0/3 维持登记（win32 缺 w64devkit/PortableGit 锁定下载源——其
`payloads.lock.json` 仅在原构建机；win64 缺 Python 3.8.20；linux full
为重型 sysroot 管线）。std 重建产物的 `qualification=pending` 与实机
旅程边界同 Windows std。

### win32 full 随当前源码装配（D-079，10-01 深夜续）

按 D-079 三档信任分级取得外部件后，补齐 win32 full 最后一席：

| 步骤 | 结果 |
| --- | --- |
| 外部件 | PortableGit-2.10.0-32-bit 官方 SHA-256 验证通过；w64devkit-x86-2.9.0 重派生 d05b743d...；sqlite-src-3530400.zip 重派生 d18fa15a...；jq/onig/sqlite-autoconf/busybox-w32 full 锁逐项验证 |
| 交叉构建 | jq 1.8.2（onig 静态链，初版误动态链 libwinpthread 已改 -static 重链）、sqlite3 3.53.4 与 sqldiff（src 包 tool/sqldiff.c + autoconf amalgamation + ext/misc/sqlite3_stdio）、busybox-w32 FRP-6075（mingw32_defconfig） |
| 暂存脚本 | prepare_win32_full.py 入库 .tools/qualification（220 文件注释检查通过），合并 std 4 工具记录共 10 工具 |
| 装配验证 | editions=PASS；10 工具 12478 文件逐摘要、入口点/许可证齐全、R73 核心、notices 形状、未授权（verify_win32_full.py） |
| 本机冒烟 | git version 2.10.0.windows.1（cmd/git.exe 相对布局）、py34-ok OpenSSL 1.0.2k、GCC 16.1.0、GNU Make 4.4.1、jq-1.8.2、sqlite3 3.53.4 32-bit、sqldiff --help、busybox echo；std 四工具此前已过 |

九包进度：**7/9**（clean 3/3、std 3/3、win32 full）。剩余 win64 full
（Python 3.8.20）与 linux full（重型 sysroot 管线）维持登记；全部产物
candidate-unqualified，实机旅程属 C33。
