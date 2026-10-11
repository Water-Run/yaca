# 当前状态

更新日期：2026-10-11。本轮已重新拉取 `origin/main`，远端没有新增提交；本地
`main` 保留 R82--R86 节点的 7 个提交，基线为 `a1f47d8`。负责人按
[D-085](DECISIONS.md#d-085-同步仓库并推进至可发布就绪2026-10-11)
恢复开发，目标为满足发布条件的就绪版本。剩余语义 Review、九包和资格继续推进。
此前修复 R82/R83：cooked reader 的 GC detach 遗留资源，以及 Lua 关闭
后 DLL 先于存活 reader/stdin writer 被卸载。两架构的 R82 探针各从 30 个泄漏资源
降为 0；R83 共 52 个 DLL/worker 场景通过，最后一个线程退出后才释放 DLL。
R84 另修复 terminal native close 失败后无法重试同一 owner。
R85 补齐管理输入面的同一 owner 保留、join 状态及失败模式切换后的清理。
R86 让主协调器在 owner 未释放时保持 closing，并幂等重试未完成的清理。
R87 让终端适配器幂等确认已完成的原生释放，避免先前恢复错误令协调器持续 closing。
当前完整 Lua suite 714/714、完整 readiness PASS，结构检查 250/5563/0；
R86 已构建核心各 713/713，尚未包含 R87。证据见
[10 月 11 日 Review](CODE-REVIEW-2026-10-11.md)。剩余工作见 [TRACKING](TRACKING.md)。

阶段为 `implemented-unqualified`，目标资格验证待完成；Release Gate R 为 `closed`，
`release_authorized=false`。依据见 [readiness](contracts/readiness.lua)、
[发行清单](../release/manifest.lua)及[依赖锁](../release/dependencies.lock)。

## 最近开发核心（R86）

产品版本为 `1.0.0`。包含 R82--R86 的三目标核心已从同一份干净维护源码重建：
冻结提交为 `163728ea7e6f58efeb01155038da0a68a8cc9e6a`，源码归档 SHA-256 为
`0d5a0fa7937fbc7650508a8f95806a5dc9e78f44ab10aaa7b8cab34ade17f1e8`。
三份归档、清单及全部成员字节一致；开发测试、构建环境、原始日志与核心逐件绑定于
[核心节点清单](candidates/core-node-r86-20261008.json)，本地产物在
`out/core-node-r86-20261008/`。收尾文档在冻结源码后单独提交，产品代码未再改变。

| 开发核心 | SHA-256 | 完整测试及环境 |
| --- | --- | --- |
| Linux x86_64 | `60c9a92b267e42e56af71157ada78b2e14da0add4f68362fe3cc6b6e5a5a7035` | 713/713；CentOS 7.9 容器、GCC 4.8.5-44、glibc 2.17，共享 WSL2 内核 |
| Win32 x86 | `a921ae6aa186209f945397f4b989ddad2e8060cfad683c50e82f2bc7c7fd3187` | 713/713；Windows 11 x64 / WOW64 |
| Win64 x86_64 | `a27542a58af6f96553985a334ceb0b5cbbcd440fa263468eb4f72147b680bb27` | 713/713；Windows 11 x64 |

Windows 使用实际新单文件内嵌 Lua 执行冻结源码完整 suite，--version 通过；离线
Stage 1 为 partial，仅有配置未初始化及非 TTY 警告，零网络请求。Linux 使用同次构建的
Lua 和 native 运行完整 suite，另通过 onedir/onefile 版本冒烟及 ELF/glibc 导入闭包检查。
最低 Windows 系统未在此节点重新实测；新核心的九包装配、旅程和正式资格仍待完成。

## 已交付的 R81 候选

产品版本为 `1.0.0`，本节点为
[`v1.0.0-preview.20261006`](https://github.com/Water-Run/yaca/releases/tag/v1.0.0-preview.20261006)
候选预发布。源码已包含 R77--R81：Windows reparse 解码、原生文件系统资源生命周期、
发布身份验证资源保留、进程启动请求捕获，以及终端输入投影和 mode 字符串保留。
具体缺陷、反例和逐项语义核对在 [10 月 6 日 Review](CODE-REVIEW-2026-10-06.md)，
R77 原始证据在 [10 月 5 日 Review](CODE-REVIEW-2026-10-05.md)。

R81 候选三目标从同一份完整维护源码快照构建：冻结提交为
`d215a8d9d14683fb6acd2ee51e8f7879d9976f6d`，源码归档 SHA-256 为
`a6c160a9ff28a11118da7dc4606e217d763c3049f496f5bb5d5597966fbd07bf`，
406 个成员。三份归档及逐成员字节一致，冻结时工作树干净。构建后的候选清单、
交付记录和暂停文档单独提交，交付时产品源码与冻结输入一致。
当前开发源码另含 R82--R86，已发布的 R81 ZIP 不包含本轮修复。

| R81 已交付核心 | SHA-256 | 完整测试及环境 |
| --- | --- | --- |
| Linux x86_64 | `1bc7e3bd37b2b42765b437f4a7dd84b827b8c823e752d76cd9e983fc52be40b6` | 706/706；CentOS 7.9 用户态、GCC 4.8.5、glibc 2.17 |
| Win32 x86 | `82053d9fedf7fc406140b6493671969bd20fbacaae2e9d088712d96c1a1771e0` | 706/706；Server 2008 non-R2 x64 / WOW64 |
| Win64 x86_64 | `b732ebea7d014435d6c78166241995bb762183f636ad2a97c18414814ff42c73` | 706/706；Windows 11 x64 |

Windows 两目标的完整 suite 使用实际单文件的内嵌 Lua 执行冻结源码测试，核心摘要在
目标端重算一致；回执、原始日志、源码归档及核心逐字节绑定。Linux 在 C7 用户态
完成原生构建、完整 suite、onedir/onefile 冒烟与 ELF/glibc 导入闭包检查。
C7 容器共享 Fedora 宿主内核；Windows 兼容底线仍按 XP SP3 x86、Win7 SP1 x64
源码与导入核对，不把指定现代宿主结果扩展为最低系统实测。

三平台各 clean/std/full，共九个 runtime/notices ZIP 对。逐文件 SHA-256/CRC、
路径/模式、工具版本、许可证、SPDX、来源摘要、构建/测试回执和同平台核心一致性
检查通过，`missing_pairs` 与 `tool_payload_gaps` 均为空。Linux 三档使用这次
实际上传 ZIP 在 C7 用户态完成 10/10 离线核心旅程，包括真实 PTY Stage 1、移除
工具、整体移动、卸载和自有临时目录无残留。首次配置、模型、升级与完整交互不在
这一离线结论中。

字节清单及证据边界见 [本节点清单](candidates/1.0.0-preview.20261006.json)，
原始记录位于 R81 构建机的 `out/node-r81-publish-20261006/`。配套证据、三目标来源包和
`SHA256SUMS.txt` 随候选附件交付。 GitHub 的 24 个附件大小与 SHA-256
均与本地一致，远端回执见 [发布核对](candidates/1.0.0-preview.20261006-publication.json)。

## 已有能力

| 范围 | 当前能力 | 实现 |
| --- | --- | --- |
| Agent 核心 | 单 Agent、串行工具、OpenAI/Anthropic 协议、流式输出、审批、取消、压缩、Context 保存与恢复 | `runtime.lua`、`model.lua`、`session.lua`、`context.lua` |
| 交互与管理 | 首次配置、配置/模型/Context 管理、status/export、自检；`.ask` 纯问答 | `main.lua`、`cli.lua`、`terminal.lua` |
| 工具 | 八个基础工具及内嵌 `lua`，共用权限、预算、取消与收尾 | `tools.lua`、`process.lua`、`release/launcher.lua` |
| 附带软件 | 可选 tools、索引、模型环境投影、`.software` 查询；clean/std/full 三档 | `bundled.lua`、`release/tool-bundles.json`、`package_editions.py` |
| 便携与旧系统 | 单文件、Windows PTY/Unicode、异步 stdin、进程树回收、FAT32 发布、旧编码无损读写 | `native/`、`fs.lua`、`textcodec.lua` |
| 大文件 | 区间读、尾读、有界搜索、续页和长行截断；身份变化返回 `TargetChanged` | `tools.lua`、原生 seek |

附带工具输入沿用已核对且字节未改的来源。Windows 两目标输入位于
`out/win32-full-staged-20261002/`、`out/win64-full-staged-20261002/`；Linux 输入位于
`out/node-r76-20261005/linux-full-staged/`，均为原 R81 构建机路径。
已交付的 R81 九包按当时核心绑定；本轮新核心尚未装配九包，不继承旧核心测试。
Linux full 的 Git HTTPS、Perl、静态库和默认 SDK 闭包此前已构建并运行通过，来源和
逐文件摘要仍由当前装配重新核对；最终工具来源语义审计保留为待完成。

## 注释与语义 Review

本轮完整 coding readiness **PASS**；全仓注释结构为
**250 文件 / 5563 声明 / 0 缺项**。检查器反例、装配/审计/旅程回归、四校验器和
全部 TP/RP 通过，本轮构建与完整检查经资源守卫串行运行。

R78--R81 对相应生产函数及维护探针完成人工语义核对和三平台故障取证，冻结输入与
日志分别绑定于 [R78](native-review/R78.json)、[R79](native-review/R79.json)、
[R80](native-review/R80.json)、[R81](native-review/R81.json)。R80/R81 的 Linux
临时字符串 GC 反例另有 sanitizer 前后证据。Windows cooked 投影使用有界
completed reader double；该证据不替代真实控制台交互或 emergency cancellation。

本轮补齐 cooked reader detach 所有权：终端与 worker 分别持有原子引用；GC
释放终端引用和线程句柄，未结束的 worker 保留其记录，结束后释放最后引用。
本机 Win32/Win64 各覆盖 56 个实际线程场景，既有两架构 cooked reader 和
三平台 terminal input 故障回归均通过。源码与实际日志绑定于
[R82](native-review/R82.json)。R83 为 reader/writer 单独保留所属 DLL 引用，启动
失败收回，正常或错误 IO 后在终止线程的同一步释放；两架构各 26 场景、既有
terminal/process 故障回归和 Linux native 编译通过，绑定于
[R83](native-review/R83.json)。真实控制台和最低 Windows 系统实测不扩展。
R84 保留关闭失败的 started/joined 句柄，仅在原生关闭成功后推进状态；专项
10/10，含同句柄恢复、异常及先前错误优先级，见本轮 Review。
R85 对实际 Model manager 的收尾/Key 模式切换通过 27/27，保留失败关闭的
active owner 与成功 join，避免新输入覆盖，见 [R85](lua-review/R85.json)。
R86 协调器专项 42/42，terminal 或 writer 未释放前不报告 closed，重试只处理
未完成 owner；生产运行失败后再尝试清理，见 [R86](lua-review/R86.json)。
R87 关闭确认专项相关三套 80/80，实际 adapter 与 coordinator 组合确保此前释放
能够被收尾确认且不重复 native release，见 [R87](lua-review/R87.json)。

全仓人工语义 Review 仍为 **partial**。后续原生/main 交互内部和部分测试辅助代码
尚未完成，真实控制台 emergency cancellation 仍需对应运行证据，不用结构覆盖或
本节点打包通过代替这些核对。C32/C33/C34 剩余正式资格见 TRACKING，Gate R 保持关闭。

## 开发与仓库状态

本地和 GitHub 仅保留 `main`，默认分支为 `main`；候选 tag 属于发行标记。
README.md、README-zh.md 和两份 quickstart 均描述 `1.0.0` 候选及资格待完成，
中英文 README 的章节、命令参考和下载入口已对齐。开发入口、实施计划和资格手册
以 D-085 的恢复指示为准；本轮提交只保存在本地 main。

当前从 [剩余事项](TRACKING.md) 接续 Review 与资格收尾；历史过程见
[开发历程](DEVELOPMENT-HISTORY.md)。
此前已授权的模型凭据属于原构建机的忽略目录，当前工作区未恢复，未进入源码包、
候选包或公开证据。后续产物与在线旅程的依赖恢复见 TRACKING。
