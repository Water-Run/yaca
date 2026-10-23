# 当前状态

更新日期：2026-10-23。产品版本为 `1.0.0`，阶段为 `implemented-unqualified`。
R95 候选已发布，24 个远端附件的 SHA-256 与大小均核对一致；源码及开发入口已推送 main。
R100 开发接续节点已公开，8 个附件的远端 SHA-256 与大小均核对一致。
按 [D-095](DECISIONS.md#d-095-恢复开发并优先修复实际使用与-agentloop2026-10-23) 恢复开发。
当前优先修复实际交互与 AgentLoop。10 月 23 日已复现并修复提示符换行、未接通的
Windows Tab 补全、普通最终回复不能收口、可恢复工具错误终止整轮、Anthropic 环境
消息编码失败和大文件续读丢失跳行进度；验证与剩余限制见
[本轮 Review](CODE-REVIEW-2026-10-23.md)。新源码不扩大 R95/R100 的冻结资格结论。

已发布产品 src/native 保留 R94 范围；当前工作区包含上述后续修复。开发验签与初始化入口
已修复，R106 进一步恢复对应来源并校正 runtime 配方；具体修改、失败和实际验证见
[10 月 20 日 Review](CODE-REVIEW-2026-10-20.md)，历史节点见
[开发历程](DEVELOPMENT-HISTORY.md)。

| Windows Git 来源 | 当前固定成员 | 当前核对范围与缺项 |
| --- | --- | --- |
| Win32 | 1361 | 精确配方恢复 120/121；117 个版本静态摘要全部匹配、3 个静态子集；Net-SMTP-SSL 1.02 原源码已固定、1.02-1 原 MSYS 配方仍待恢复，VCS/签名和完整二进制对应关系待审查 |
| Win64 | 605 | 18 项密码学签名通过；固定公钥快照的当前状态 10 项通过、8 项过期，撤销新鲜度和二进制完整对应关系待审查 |

Win32 的 ncurses/Connect 原归档已从历史容器恢复，内层 SHA-256 匹配原 Git
配方；镜像只作为字节载体，不用其中不同的配方替换原配方。GCM 原编译 ZIP 与
配方摘要匹配，但排除于对应来源；另固定上游真实源码和许可，依赖与二进制对应
关系仍待核对。两 Windows 来源均保持 `partial`，SKIP 和记录摘要不表示验签通过。

R106 恢复 15 项原配方摘要匹配输入和 4 项尚未验签的签名字节，校正 runtime 为
3 月原配方及五项原补丁，旧配方和补丁按原字节移入 history。Net-SMTP-SSL 1.02
的 CPAN 原源码及 Makefile.PL 已固定，模块逐字匹配 R88 full 包和清单；该对应
证据限于 R88，不扩大为 R95 或最终包。剩余三个静态子集是 wineditline、runtime
和 GCM；静态摘要分类不表示分离签名或整体来源闭包通过。

R106 的 1361 成员档案已装配并通过维护接纳，完整 coding readiness PASS；档案
与新增来源缓存目前保存在本机，尚未公开。R100 的公开缓存仍对应其原锁，不能
直接当作当前锁的完整输入。当前档案和固定输入摘要见当日 Review 与来源锁。

本机开发检查：R103 在两个独立检出中复现并修复符号链接 Python 建 venv 失败；
带空格目录完成初始化、固定解析器导入、完整 Lua 735/735 和 readiness。R105 的
Python 变参注释检查器的三项反例从 15/18 修复为 18/18；两处已有回调注释同步
规范，TP-006 实际重跑 319 断言后刷新双重来源 pin。R106 最终完整 readiness 与
全仓结构 273 文件 / 5801 声明 / 0 缺项通过，本轮本地辅助程序的补充结构检查
也通过。本轮修改已逐项核对注释语义，全仓人工语义 Review 仍为 partial。
结果限于当前宿主、固定公开缓存
和已有开发依赖，不扩大为目标或最终九包资格。

R100 已公开开发源码、离线 Git bundle 和恢复资料，其独立 clone/pull、初始化、
Lua 735/735、readiness 与离线 bundle 检出通过记录保留原范围。原节点的八个
附件、冻结源码与摘要见 [接续说明](DEVELOPMENT-HANDOFF-2026-10-15.md)和
[发布回执](candidates/1.0.0-preview.20261015-publication.json)。

## 当前源码与核心

候选核心来自干净源码 `e06d9f93d542892a28970a06f3f1bce9ff161f73`。
共同源码归档 SHA-256 为
`e01becc04f0676fe8612916282f9faad6874924e95a79465fd26cbc7c24ec97f`，464 个维护文件。
本次交付的开发初始化、装配元数据和文档更新不改变这些核心字节。

| 目标 | 核心 SHA-256 | 完整测试与实际环境 |
| --- | --- | --- |
| Win32 x86 | `2a5adf75823deb52861080b5f5540028dc39820baa8593d7e5210987781d65c7` | 735/735；Server 2008 non-R2 x64 / WOW64；实际单文件内嵌 Lua |
| Win64 x86_64 | `be2574f45b8253f76c77150337a960460b9e361334635ee8c0ddd3e3b09e8f4e` | 735/735；Windows 11 10.0.26100 x64；实际单文件内嵌 Lua |
| Linux x86_64 | `ab05517ff0314d59a90999111ac44f086ebda071e52567c9f239763a9abc29dc` | 735/735；CentOS 7.9 用户态、GCC 4.8.5-44、glibc 2.17；共享 Rocky Linux 6.12 内核 |

Windows 两目标重算核心和全部源码成员摘要；Linux 完成原生构建、完整 suite、
onefile/onedir 冒烟与 ELF/glibc 导入闭包检查。最低 Windows 兼容底线仍是 XP SP3 x86、
Win7 SP1 x64，不把指定实际目标的通过结果扩大为最低系统实测。

当前源码已包含两边合并后的所有权和响应身份修复、输入/PTY 生命周期收尾、原生分配
失败保护、luainstaller 1.5.0，以及 `.software` 只读索引修复。Ask 使用选定模型的输出
额度；length/cancelled 终态分别保留为预算耗尽/取消。显式配置的 `reasoning_effort`
经过注册和枚举校验后才发送，未配置时请求保持原样。

## 交互与升级证据

R94 Win64 Qwen `low` 的真实原生控制台旅程已通过：首次 Ask、一次经核验的 Lua
批准/执行、随机 token 保存、进程退出后同一 Context 重开召回、观察到的模式恢复。
额外工具提议被明确拒绝。该配置使用已授权私有模型配置与有界测试设置，不把结果
扩展为所有模型的默认审查路线。先前默认推理档位的时间预算失败仍保留在历史证据中。

三目标已有从已发布 `dc6ce14` 到 R92 核心的保留数据升级证据；配置、Context 和
工作目录字节保持一致，再打开同一 Context 召回 token 并恢复模式。Linux 范围为
授权现代宿主的真实 SSH PTY；Windows 为原生控制台。这些升级结果保留 R92 核心范围，
不能当作 R94 最终九包的逐包升级通过。

源码与交互历史分别见 [R92](lua-review/R92.json)、[R93](qualification-review/R93.json)、
[R94](lua-review/R94.json) 和 [10 月 11 日 Review](CODE-REVIEW-2026-10-11.md)。

## 本次候选交付

交付入口为
[`v1.0.0-preview.20261013`](https://github.com/Water-Run/yaca/releases/tag/v1.0.0-preview.20261013)。
三平台各有 clean/std/full、配套 notices、核心对应源码、摘要和 qualification-evidence。
冻结资料见 [R95 清单](candidates/1.0.0-preview.20261013.json)，实际公开状态及全部远端摘要
见 [发布回执](candidates/1.0.0-preview.20261013-publication.json)。清单保留装配时的 prepared
记录，发布回执记录之后的实际公开步骤；R95 交付后按 D-088 暂停，本轮按 D-089 恢复，
R97 来源恢复节点按 D-090 收尾后再次暂停。

独立干净检出完成初始化、Lua 735/735 和完整 coding readiness；结构检查为
270 文件 / 5765 声明 / 0 缺项。Linux 三个候选 ZIP 在现代 WSL 宿主完成十步
offline-core 旅程，保留该宿主和离线范围。完整记录见 [10 月 13 日 Review](CODE-REVIEW-2026-10-13.md)。

Windows 编译器、curl、Python 的附件已改用经核对的源码及维护配方。Git 附件包含
真实主源码、已恢复 SDK 源码、精确配方/补丁和来源状态；闭包明确标记为 `partial`。
旧二进制安装包不再充当源码。结构及字节核对不替代全部对应来源的人工语义审计。

Release Gate R 为 `closed`，`release_authorized=false`，目标资格验证待完成。
完整来源闭包、最终九包实际旅程及全仓人工语义 Review 仍待完成；全仓语义 Review
为 `partial`。发行清单与 [readiness](contracts/readiness.lua) 保持未资格状态。

## 接续开发

当前按 D-095 推进实际使用修复，剩余事项见 [TRACKING](TRACKING.md)。新机器按
[开发环境准备](QUALIFICATION-RUNBOOK.md#1-开发检查) 拉取 main 并初始化。
源码、测试、契约、依赖锁和初始化入口由 Git 维护；历史日志随候选发布。
本地缓存和模型密钥按环境准备，公开仓库与候选附件不包含私有配置。
