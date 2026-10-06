# 当前状态

更新日期：2026-10-06。核心已实现，R81 节点已打包、推送并发布候选预发布；开发已暂停。
负责人按 [D-082](DECISIONS.md#d-082-r81-节点打包推送后暂停开发2026-10-06)
要求在本节点停止开发；剩余工作暂存于 [TRACKING](TRACKING.md)，明确恢复前不启动。

阶段为 `implemented-unqualified`，目标资格验证待完成；Release Gate R 为 `closed`，
`release_authorized=false`。依据见 [readiness](contracts/readiness.lua)、
[发行清单](../release/manifest.lua)及[依赖锁](../release/dependencies.lock)。

## 当前候选

产品版本为 `1.0.0`，本节点为
[`v1.0.0-preview.20261006`](https://github.com/Water-Run/yaca/releases/tag/v1.0.0-preview.20261006)
候选预发布。源码已包含 R77--R81：Windows reparse 解码、原生文件系统资源生命周期、
发布身份验证资源保留、进程启动请求捕获，以及终端输入投影和 mode 字符串保留。
具体缺陷、反例和逐项语义核对在 [10 月 6 日 Review](CODE-REVIEW-2026-10-06.md)，
R77 原始证据在 [10 月 5 日 Review](CODE-REVIEW-2026-10-05.md)。

本节点三目标从同一份完整维护源码快照构建：冻结提交为
`d215a8d9d14683fb6acd2ee51e8f7879d9976f6d`，源码归档 SHA-256 为
`a6c160a9ff28a11118da7dc4606e217d763c3049f496f5bb5d5597966fbd07bf`，
406 个成员。三份归档及逐成员字节一致，冻结时工作树干净。构建后的候选清单、
交付记录和暂停文档单独提交，产品源码保持与冻结输入一致。

| 当前核心 | SHA-256 | 完整测试及环境 |
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
原始记录位于 `out/node-r81-publish-20261006/`。配套证据、三目标来源包和
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
`out/node-r76-20261005/linux-full-staged/`。这次九包重新绑定当前核心，不继承旧核心测试。
Linux full 的 Git HTTPS、Perl、静态库和默认 SDK 闭包此前已构建并运行通过，来源和
逐文件摘要仍由当前装配重新核对；最终工具来源语义审计保留为待完成。

## 注释与语义 Review

当前完整 coding readiness **PASS**；全仓注释结构为
**246 文件 / 5505 声明 / 0 缺项**。检查器反例、装配/审计/旅程回归、四校验器和
全部 TP/RP 通过，构建、完整测试和容器均经资源守卫串行运行。

R78--R81 对相应生产函数及维护探针完成人工语义核对和三平台故障取证，冻结输入与
日志分别绑定于 [R78](native-review/R78.json)、[R79](native-review/R79.json)、
[R80](native-review/R80.json)、[R81](native-review/R81.json)。R80/R81 的 Linux
临时字符串 GC 反例另有 sanitizer 前后证据。Windows cooked 投影使用有界
completed reader double；该证据不替代真实控制台交互或 emergency cancellation。

全仓人工语义 Review 仍为 **partial**。Windows cooked reader 取消失败后的 detach
所有权、后续原生/main 交互内部和部分测试辅助代码尚未完成，不用结构覆盖或
本节点打包通过代替这些核对。C32/C33/C34 剩余正式资格见 TRACKING，Gate R 保持关闭。

## 开发与仓库状态

本地和 GitHub 仅保留 `main`，默认分支为 `main`；候选 tag 属于发行标记。
README.md、README-zh.md 和两份 quickstart 均描述 `1.0.0` 候选及资格待完成，
中英文 README 的章节、命令参考和下载入口已对齐。开发入口、实施计划和资格手册
以 D-082 的暂停指示为准。

暂停期间不启动新实现、Review、在线模型调用或正式资格推进。负责人明确恢复后，
从 [暂存剩余事项](TRACKING.md) 接续；历史过程见 [开发历程](DEVELOPMENT-HISTORY.md)。
此前已授权的模型凭据仍留在忽略的私有目录，未进入源码包、候选包或公开证据。
