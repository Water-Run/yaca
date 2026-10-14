# 当前状态

更新日期：2026-10-14。产品版本为 `1.0.0`，阶段为 `implemented-unqualified`。
R95 候选已发布，24 个远端附件的 SHA-256 与大小均核对一致；源码及开发入口已推送 main。
按 [D-090](DECISIONS.md#d-090-来源恢复节点收尾后暂停2026-10-14) 在 R97 收尾并推送 main 后暂停。

R96 已修复维护装配器的二进制 Git 来源回退，并在写入输出前验证显式来源档案；
伪装成来源的编译成员也会拒绝。两 Windows 收集器统一归档路径分隔符并保留来源
状态。专项 7/11 到 12/12，真实两目标来源子集保持 partial；完整 Lua 735/735、
coding readiness PASS、结构 270/5771/0。记录见 [10 月 14 日 Review](CODE-REVIEW-2026-10-14.md)
与 [R96](tool-source-review/R96.json)。产品核心字节仍保留 R95 范围。

R97 已恢复首轮 10 个整包来源输入缺项，两份原 VCS tar 摘要匹配。新 Win64 Git
来源锁固定 565 个成员，实际来源档案装配与接纳通过；合计 38 个版本中 20 个静态
摘要全部核对、18 个为静态子集。18 个分离签名及完整二进制对应关系仍待核对，
`source_closure=partial`。记录见[来源恢复](SOURCE-RECOVERY-2026-10-14.md)和
[R97](tool-source-review/R97.json)；本节点无产品运行代码变更。

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

当前暂停，负责人恢复后从 [TRACKING](TRACKING.md) 的剩余事项接续。新机器按
[开发环境准备](QUALIFICATION-RUNBOOK.md#1-开发检查) 拉取 main 并初始化。
源码、测试、契约、依赖锁和初始化入口由 Git 维护；历史日志随候选发布。
本地缓存和模型密钥按环境准备，公开仓库与候选附件不包含私有配置。
