# 剩余开发与验收

更新日期：2026-10-11。当前能力和候选产物只在
[CURRENT-STATE.md](CURRENT-STATE.md)维护；已完成工作的过程只在日期 Review 与
[开发历程](DEVELOPMENT-HISTORY.md)保留。C01--C31 已实现，不重新开工。

远端 `v1.0.0-preview.20261011` 已发布，冻结源码为 `dc6ce14`，三目标各 720/720，
九包完整性及 Linux 三档离线核心旅程通过。本轮已合并远端 `db9c5d5` 与本地 11 个提交。
合并后的源码保留本地压缩身份修复、协调器重试和来源档案；新源码测试、核心与九包须重新绑定。
合并后再修复 `.software` composition 越界，专项 116/116、完整 suite 730/730、
readiness PASS、全仓结构 266/5740/0，见 [R90](lua-review/R90.json)。三核心已重建，
实际目标各 730/730，见 [核心节点](candidates/core-node-r90-20261011.json)；最终九包待装配。
目标资格验证待完成，Gate R 保持关闭。
负责人按 [D-085](DECISIONS.md#d-085-同步仓库并推进至可发布就绪2026-10-11)
要求同步并继续到可发布就绪，覆盖 D-084 的暂停安排。既定功能与实机范围不变。
两条历史分别见 [远端 Review](CODE-REVIEW-2026-10-08.md) 和
[本地 Review](CODE-REVIEW-2026-10-08-LOCAL.md)，本轮见 [10 月 11 日 Review](CODE-REVIEW-2026-10-11.md)。
当前继续剩余语义核对与输入恢复，再按最终源码完成三目标九包和正式资格。

## 剩余事项

| 优先级 / 任务 | 剩余工作 | 完成条件 |
| --- | --- | --- |
| P0 · 正式版源码与产物 | R90 三核心已从共同干净源码重建并各过 730/730；资格驱动续修与完整 Review 收口后再冻结最终维护源码，装配九包和对应旅程 | 将最终源码、核心与目标证据重新绑定，预发布或窄探针不能转写为正式资格 |
| P0 · R92 Ask 修复重验 | 已证实硬编码 1024 输出额度及 length/cancelled 被误记 completed；专项 36/39 到 39/39，完整 733/733 | 重建包含修复的核心，重新执行 Qwen 召回与 Windows 真实模型控制台，不把此前配置值当成实际请求额度 |
| P0 · Linux full 输入 | C7 Perl/Git 静态 crypt/HTTP/TLS 闭包、默认 SDK、十工具移动运行和真实 HTTPS 已过；余最终包旅程和来源审计 | `tool_payload_gaps` 清空且完整闭包运行通过；不按版本号复用早期 payload；维护脚本应复现结果，不依赖手改缓存 |
| P0 · Windows full 对应源码 | 编译器、curl、Python 来源已绑定；Win64 官方 zstd 来源已补齐多项，余 45 个清单行；Win32 109 个精确配方/补丁集合已恢复，来源载荷继续补齐 | 按实际版本/标签/摘要绑定完整对应来源；二进制包不能充当对应源码；不能只用 Git 主源码代填整个依赖集合 |
| P0 · C34 证据与来源 | 已发布预览核心各 720/720；合并源码须重新绑定最终九包、指定 Windows 实机与 C7 用户态证据，完成完整来源语义审计 | 将目标、源码、核心 SHA-256、环境和通过/失败数绑定；不得用另一个平台、旧源码或现代宿主结果代填；`audit_editions.py --require-nine --require-evidence` 通过只证明文件证据齐备 |
| P1 · C33 交互 | 六组 Stage 2 各 7/7；R90 Linux 双模型 PTY 和 Windows 双目标原生首次配置通过；Win32 DeepSeek 原生真实模型旅程通过，Qwen 再次出现空白召回，进入 R92 修复重验 | 保留所有失败与配置记录；R90 Ask 实际上限为 1024，先前 16384 仅是配置值；余修复后目标、保留数据升级与最终九包旅程 |
| P1 · C32/C33 目标运行 | 按 D-077 补指定环境的编码、取消/进程树、发布/恢复及附带工具运行证据 | 使用已有指定实机；分别记录 Windows 最低兼容面和 CentOS 7 容器共享内核边界，不重新索取整套旧系统矩阵 |
| P1 · 注释语义 Review | 继续后续原生/main 交互内部和测试辅助代码；真实控制台取消路径的对应运行证据归目标验收 | 逐项核对参数、返回值、失败/所有权和副作用；异常路径须有实际故障注入证据，全仓结构覆盖不能代替语义审核 |
| P2 · C34 / Gate R | 汇总九包 SHA-256、许可证、SPDX、构建/测试和旅程记录，复核公开文档 | C32/C33/C34 均满足后，形成独立可审计的发布门评审；状态改动不作为通过证据 |

## 可复跑的当前工具

执行命令与证据格式见[资格执行手册](QUALIFICATION-RUNBOOK.md)。

- `audit_editions.py` 接收显式 runtime/notices ZIP 对；校验实际字节及元数据，汇总缺包、
  核心一致性和 C34 证据缺项。默认完整性通过仍为 `qualification=pending`。
- `test/release/journeys.lua` 调用受资源守卫保护的 `edition_journey.py`，可复跑 Linux
  clean/std/full 的 10 步离线核心旅程。已有 scratch 内容不删除。
- `agent_terminal_smoke.py --online` 是已配置目标的真实 TTY 在线驱动；应使用隔离部署目录。
  新离线驱动不执行这些步骤，收到在线选项时拒绝，不输出虚假的完整旅程通过。
- `run_coding_readiness.sh` 已纳入装配、发行校验和 PTY 驱动回归；检查均串行执行。

## 现有依赖与执行约束

负责人本轮已重新提供 DeepSeek 凭据及 DGX Spark 入口，两端模型发现通过；
私有输入在 `/home/linzh/.cache/yaca-release-readiness-20261011/private/`，实际在线旅程
待最终核心执行。凭据不入库、不投影到日志或 Prompt。原构建机的私有目录仍为历史资料。
旧核心 14 次请求揭示 R75，不用历史 Stage 2/3 代替后续源码的实际联网证据。

原构建机已复现 Linux full Git HTTP(S)/Perl 和完整 SDK 闭包，工具输入与九包记录在
`out/node-r76-20261005/`；该批目录及 R81 九包目录未在当前工作区恢复。
早期 `out/review-20261005/` 结果保留为历史。
当前已从预发布恢复并逐件核对全部 24 个附件，见
[本轮输入清单](candidates/restored-inputs-20261011.json)。三目标各十工具输入已恢复，
缓存恢复不继承 R81 的核心资格结果。Linux 输入在 WSL 区分大小写的文件系统
`/home/linzh/.cache/yaca-release-readiness-20261011/tool-inputs/linux-x86_64`；
Windows 输入在 `out/review-20261011/recovered-tool-inputs/`。
使用前核对报告所列摘要，不依赖目录日期判断源码资格。
原构建机与外部目标证据按实际可用性复用，无法核实的面继续标为待验收。

修改前阅读[编码规范](CODING-STANDARD.md)，所有新增/改动函数、类型和回调完整注释。
构建、完整测试、容器和 VM 通过 `.tools/run_with_resource_guard.sh` 串行执行。
每轮按反例、窄修复、专项回归、完整检查、语义核对、状态更新收口。

任务定义与依赖见[实施计划](IMPLEMENTATION-PLAN.md)及
[readiness](contracts/readiness.lua)。旧日期记录的“下一项”是历史资料，不是当前队列。
