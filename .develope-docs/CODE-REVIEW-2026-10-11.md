# 恢复开发、来源收口与远端同步

日期：2026-10-11。负责人按 [D-085](DECISIONS.md#d-085-同步仓库并推进至可发布就绪2026-10-11)
要求同步并推进到可发布就绪。本轮最初拉取时远端无新增提交，从 `a1f47d8` 接续；
随后按再次同步要求拉取到 `db9c5d5`，发现远端新增 11 个提交并与本地 11 个提交合并。
指定 Server 2008 的 Cygwin SSH 可达。

## 合并远端 10 月 11 日预览节点

远端节点含 luainstaller 1.5.0、键盘重复、PTY stty 子进程收尾、原生熵/SHA-256
分配失败保护及 24 个已发布附件记录。原生重叠修复采用远端已取证实现，保留本地
协调器幂等收尾、成功 join 缓存、压缩请求身份拒绝和工具来源档案。
管理输入在关闭前同时使模式与缓冲失效，关闭失败保留同一 owner 及已完成 join。

terminal close 合并真实确认值校验与已关闭 owner 的幂等确认：初步 restore 失败后，
native close 的 true/true 表明恢复及释放完成；两阶段均失败仍保留初步诊断和 owner。
原本要求“成功关闭仍报告初步 restore 错误”的两项本地测试按该确认契约更新；
下文 R87 为修复当时的历史语义，冻结证据不重写。

远端 Review 原名保留。本地重叠的两份原生清单逐字节保存在
`native-review/local-20261008-R82.json`、`native-review/local-20261008-R83.json`；
本地日期 Review 改名为 `CODE-REVIEW-2026-10-08-LOCAL.md` 并修正其链接。
合并源码完整 suite **730/730**、coding readiness **PASS**；全仓注释结构
**266 文件 / 5740 声明 / 0 缺项**。TP/RP 及 luainstaller 1.5.0 资源覆盖证明通过。
日志位于 `out/review-20261011/sync/`。随后三核心已按 R90 重建并各过 730/730；已有预览证据仍保留其冻结源码范围。

## R90 附带软件索引的 composition 边界

`.software` 的嵌套 reader 在 coordinator 中访问不在词法作用域内的 `composed`，
列表查询直接抛错。新增真实 coordinator 回归注入可用索引，要求只读列表、不发布 Agent。
合并源码基线专项 **115/116**，唯一失败为 `global composed` 空值索引。

修复将有界目录/文件读取留在生产 composition 绑定，coordinator 通过可选 callable
端口读取描述；无 reader、异常或 render 错误保留结构化诊断。修复后专项 **116/116**。
同时核对 terminal ack/owner 与管理输入 close 路径，并修正 submission 的 string 参数注释。
冻结基线、当前源码、测试及日志见 [R90](lua-review/R90.json)；此人工核对仅覆盖所列子面，
全仓语义 Review 继续为 partial。

## R90 三核心与 R91 目标旅程

从干净 `b81d828` 冻结 455 个维护文件，三目标源码归档一致，SHA-256 为
`4e08a38931f59fe5753dc7e82540ec8efbbc15ad456c50da9e061a2dd3cb7aff`。
两 Windows 实际单文件内嵌 Lua 在指定 Server 2008 / WOW64 和 Windows 11 上各过
730/730；Linux 在 C7.9 / GCC 4.8.5-44 / glibc 2.17 用户态各项构建与完整测试通过，
共享 Rocky Linux 6.12 内核。50 个核心和日志字节绑定见
[核心节点](candidates/core-node-r90-20261011.json)。

本机 Docker 启动因 inference socket 报错退出。远端首次 C7 网络安装停滞，保留日志后
终止自有容器；复用既有项目 C7 环境的独立镜像，再下载缺失 RPM，以仓库元数据摘要及
C7 原始公钥校验签名后离线安装。未更改原项目容器；实际 RPM/编译器环境保留。

三平台双模型 Stage 2 共六组，各 7/7，含鉴权、流式、工具/控制载体和取消。
Linux 编译核心在授权现代 Linux 宿主完成双模型真实 SSH PTY：中文命令、首次纯 Ask、
真实 print(6*7) 提议核对与一次审批执行、随机 token 的跨进程 Context 召回、退出/重开模式恢复。
Qwen 的 4096 输出预算曾得到空白召回结果；16384 的同类旅程通过，失败文本与预算分别记录。
此结果不扩展为 C7 容器互动或默认 provider 配置的普遍结论。

实际登录装饰隐藏裸 `$ ` 提示符，驱动改为独立的无 profile Bash。Ask 系统层明确要求
不确定性说明，DeepSeek 返回精确随机 token 后又解释证据边界；旧验收误把附加说明
判为未召回。新增反例为 7/8，修复后 8/8：要求首个回答行是唯一精确 nonce、接受/输出/
完成的 Ask ID 一致，拒绝错误/重复 nonce 和工具活动。

两 Windows 原生独立隐藏控制台完成离线首次配置、中文输入、本地 mock 的纯 Ask、
Context 重开和观察到的模式恢复；保存前无请求，后续两次 loopback 请求明确属于模拟接口。
原生控制台结构、函数、参数/返回与句柄所有权已逐项注释和人工核对。ResumeThread
拒绝此前会在进入清理 try 前抛错，遗留已创建的挂起子进程；现纳入创建后的统一清理。
两目标实际创建后注入 resume 拒绝，确认自有 child 被终止、退出 124。

R91 完整 readiness PASS，结构 266 文件 / 5741 声明 / 0 缺项。
41 个源码/日志绑定、六组模型、双 Linux PTY、双 Windows 控制台和限制见
[R91](qualification-review/R91.json)；所选证据扫描实际凭据零命中。
Windows 真实模型控制台、保留数据升级、最终九包、完整对应来源闭包和剩余全仓语义核对
仍待完成。Gate R 保持关闭，开发按 D-085 继续。

## R87 已释放终端的收尾确认

R84 保留了首次 restore 错误的优先级，即使随后 native close 已完成实际恢复和关闭。
Lua port 此时正确记录 closed，但再次 close 只抛出“terminal port is closed”。
R86 协调器因首次错误保留 owner 后，无法再确认此前已经完成的释放，持续保持 closing。

终端 close 现对已确认释放的 owner 幂等返回 true，不重复调用 native restore、join 或 close。
首次调用仍如实报告较早的恢复错误；原生关闭失败仍保留相同 started/joined owner 供重试。
未启动端口的 close 继续拒绝，失败运行不会因随后清理成功被改写为成功运行。

新增真实 coordinator 与 terminal adapter 的组合回归，故障注入在 native 边界：
两次显式 restore 失败，随后 native close 完成其内部恢复并释放。协调器第一次运行
报告 TerminalRestoreFailure，第二次清理确认已释放 owner 并转为 closed；join 与 native close
均只执行一次。既有 adapter 回归补齐关闭失败后恢复和关闭成功后确认的控制。

精确基线加当前维护回归为 **50/53**，三个失败均为关闭确认；修复后相关三套为
**80/80**，完整 suite **714/714**，完整 coding readiness **PASS**，全仓结构
**250 文件 / 5563 声明 / 0 缺项**。首次 readiness 命令因未引用含空格的 PATH 而未启动，
随后使用完整注释的独立辅助脚本运行正式链，未修改检查器或降低退出码。

关闭方法的返回、首次错误优先级、重复调用、失败 owner 保留和副作用，以及所有新增
native callbacks 已逐项人工核对。来源与实际日志见 [R87](lua-review/R87.json)。
本批未修改原生 C；R86 核心与 R81 已交付包仍保持原源码范围，后续最终核心须重新绑定。
全仓语义 Review、最终九包与 C32/C33/C34 继续执行，Gate R 尚未开启。

## 模型与输入恢复

负责人本轮重新提供 DeepSeek 输入及经内网 Linux 主机进入 DGX Spark 的入口。
凭据只保存到私有验收缓存，未进入 Git 或公开证据。两端模型发现均返回 200：
DeepSeek 为 deepseek-flash / deepseek-v4-pro，DGX Spark 为 qwen3.8-27b。
模型发现不代替实际生成、工具或恢复旅程。

R81 预发布 std/full 输入按已提交 publication 的大小和 SHA-256 续传核对，
尚未完成的文件保持 partial，不接纳为装配输入。旧输入恢复不继承旧核心资格。

## R88 压缩响应身份先于时钟与重试

完整通读 compact.lua 的参数/返回/副作用注释与实现：canonical event/summary/manifest
编码、输入限额、union-find 原子分组、完整前缀切点、ModelView 容量、意图和精确回执、
两次尝试、响应/发布绑定、取消、自动断路器及恢复冷却。发现 accept_response 在身份
核对前读取时钟并处理超时。第一尝试的晚到响应可取消正在运行的第二尝试；未知或缺少
ID 的对象还可能消耗当前重试与回执。

现在只接纳当前 request_id 的 envelope；旧、外来、缺少身份或非 table 的 envelope
先返回 StaleCompactionResponse，未读取时钟、启动/取消 Model 或写入 journal。
已绑定响应的时钟、超时、schema、摘要、容量与发布顺序不变。

新回归包含晚到/时钟失败/外来 ID/缺少 ID/非 table 五个边界，核对当前 ID、attempt、
Model 启动与取消次数、journal 数量及 generation 不变，随后当前真实响应仍能完成。
基线专项 **12/13**，失败为晚到响应触发当前取消；修复 **13/13**，完整 suite **715/715**。
完整 readiness **PASS**，结构为 **252 文件 / 5572 声明 / 0 缺项**，包含新的输入恢复工具。
源码、当前维护回归、精确基线及原始日志见 [R88](lua-review/R88.json)。
该结论覆盖 compact.lua 全册；生产 main 组合层、其他剩余原生/辅助代码与正式资格
继续保留待完成，全仓语义 Review 仍为 partial。

## 工具输入恢复与来源缺项

24 个原 R81 附件已恢复并逐件核对 publication 的大小和 SHA-256。
维护工具 restore_edition_inputs.py 验证 runtime/notices 的真实成员、CRC、摘要、版本、
SPDX 和路径，只恢复 tools、对应附件及索引；旧核心和其资格不作为新核心证据。
三目标各十工具恢复通过，三项独立回归通过，支持替换核心后重新装配，并拒绝错目标
与修改过的归档。恢复工具、测试的每个参数、返回、所有权和写盘边界已人工核对。

Linux SDK 存在 xt_CONNMARK.h / xt_connmark.h 等大小写不同的真实成员；NTFS 暂存
在新文件排他创建时正确拒绝。维护工具补齐 Linux 区分大小写的文件系统预检，本轮
Linux 输入移至 `/home/linzh/.cache/yaca-release-readiness-20261011/tool-inputs/linux-x86_64`，
两个 Windows 输入在 `out/review-20261011/recovered-tool-inputs/`。保留失败日志，
未重命名头文件或改变归档字节。缓存恢复不是新的运行或发布资格。

来源附件实查发现两 Windows 各三个缺项：Git、w64devkit 的 source_archive 是 MZ
二进制分发，Python 3 的 closure 仅包一份 portable ZIP。摘要与二进制版本通过不能
代替对应源码及依赖来源。检查记录为 `out/review-20261011/tool-source-inspection.json`；
当前正在按官方标签、版本和摘要取得真实对应源码与构建输入，Source 审计未完成。
上游 w64devkit v2.9.0 的 Dockerfile 已经由 HTTPS 取得并解析其版本/摘要资料；
未执行上游构建命令，也未沿用其中的 TLS 跳过选项。

## R89 对应源码与构建资料绑定

新增 audit_corresponding_sources.py 与 bundle_corresponding_sources.py，拒绝把 PE/ELF
分发包或单份 portable ZIP 当作对应源码；显式 source-profile 逐成员核对路径、摘要与完整
成员集合，构建器只接纳已锁定的源码/配方，拒绝输入越界、二进制替代、摘要漂移和覆盖已有
输出。结构核对不代替源码闭包的人工审核，也不赋予运行或发布资格。

编译器来源改为 w64devkit v2.9.0 的 23 项上游组件档案、标签仓库和 Dockerfile，共
25 个成员。每项按官方配方 SHA-256 核对。BusyBox 原 frippery HTTPS 暂不可用，显式
使用已核对的官方 GitHub 标签档案，PAX 绑定完整 commit 169694ebdba292f6533f78aeea678bfbb907396c；
原配方摘要保留，不把不同压缩字节写成相同原档案。构建/打包配方一并提供。

Windows curl 原来源目录包含 .libs 的构建链接和生成物；改为锁定的原始 curl 8.21.0、
Mbed TLS 3.6.7 与四份维护配方，共 6 个成员。Python 3.4.10 / 3.8.20 改为各自原始
CPython 源码、实际选用的依赖来源与构建/暂存配方，分别 7 / 9 个成员；旧二进制 ZIP
不再充当来源。旧 SQLite/XZ 标签不存在时，明确记录对应版本的 SQLite 官方 amalgamation
和 XZ 官方档案，未使用其他版本替代。微软运行库仍按实际随包 notices 描述，不标作开源。

四份 Windows std/full 维护暂存脚本已调用同一来源构建器。本地为原恢复清单另写
tool-inputs-source-reviewed.json，保持工具载荷字节不变；原始 recovery 记录留存。
各 Windows 的结构来源缺项从 Git/编译器/Python/curl 收口到 Git 一项。

来源检查与构建器专项 **7/7**，完整 coding readiness **PASS**，注释结构
**255 文件 / 5586 声明 / 0 缺项**。参数、返回、归档所有权、写盘范围、错误与源码/二进制
区别已人工核对。此批未改变产品 Lua/C 行为，当前完整 Lua suite 的 715/715 继续适用。
维护源码、冻结副本、实际档案及日志见 [R89](tool-source-review/R89.json)。

Git 对应依赖继续待完成：按实际 etc/package-versions.txt 获取来源包，34 条 Win64
记录已找到，132 条暂未找到，Win32 的历史镜像缺项另列。已克隆官方 MSYS2/MINGW
配方历史，下一步按精确版本和发行 revision 回溯补来源；不能只提供 Git 主仓库代填全部
MSYS/Perl/SSL 依赖。最终三核心、九包及其旅程尚未重新验收，Gate R 关闭。

## 主交互协调器第一批语义核对

逐项通读 main.lua 的协调器局部 clock、publish/error/details、main/Ask 文本缓存与
事件投影、driver 事件排序、单次 approval card、自动压缩 preflight/终态投影、status
失效关闭、cautious 设置和 Prompt 编辑路由。核对实际参数、返回、失败优先级、缓冲
限额、回执前后及 owner 归属；本子面未建立新的行为缺陷。

补齐 route_prompt_editor 的第三返回值 chat_text 注释，说明未在编辑器消费时的聊天
路由文本；纠正 Prompt 保存失败回归及其第四次 poll callback 误抄其他用例说明的问题。
修改只影响注释，产品行为不变。协调器专项 **43/43**，结构 **255/5586/0**；
实际日志为 `coordinator-semantic-subset-tests.log` 与 `coordinator-semantic-subset-coverage.log`。
更后面的模型/Context 切换、提交/取消、管理 REPL 内部与剩余原生/辅助代码仍待核对。

历史来源回溯已验证 APR 1.5.2-1：官方 MSYS2 配方 commit
63a1162b3cf0bc64fbcc0051ae0971164335f2d5 的原始 Apache 档案及七个发行补丁
逐 SHA-256 一致，记录在 `out/review-20261011/recovered-apr-source.json`。
历史 log -G 命中可能是版本移除提交，实际选择须检查该提交及父提交的 pkgver/pkgrel。
此单件通过不扩展为整个 Git 依赖闭包完成。
