# 剩余开发与验收

更新日期：2026-10-08。当前能力和候选产物只在
[CURRENT-STATE.md](CURRENT-STATE.md)维护；已完成工作的过程只在日期 Review 与
[开发历程](DEVELOPMENT-HISTORY.md)保留。C01--C31 已实现，不重新开工。

核心功能与九包候选已装配。本节点包含 R77--R81，三目标重建与完整 suite 各
706/706、九包完整性/文件证据及 Linux 三档离线核心旅程通过。
目标资格验证待完成，Gate R 保持关闭。
负责人最新指示按 [D-083](DECISIONS.md#d-083-同步项目并恢复开发2026-10-08)
同步项目并恢复开发，覆盖 D-082 的暂停。以下剩余事项继续执行，既定功能与实机范围不变。
R75/R76 节点已按 D-081 推送并发布九包候选预发布；正式资格条件保留。
续推已修复 R77 Windows reparse，指定两目标生产函数探针各 20/20；本节点单文件已纳入修复。
R78 的 snapshot/metadata/walk 与 verified open/create 所有权修复已在三平台完成
重复故障与同状态恢复取证，源码与证据已收口；本节点单文件已纳入修复。
R78 已提交推送为 `7b616ad`；R79 的删除/替换/改名验证资源修复完成三平台零泄漏、
逐字段异常零修改与重复恢复取证。本节点单文件和九包已重建；正式资格仍待后续 Review 收口。
R80 已完成启动字段捕获、借用字符串保留及参数/环境一致性修复，三平台零泄漏、
零协议失败与重复恢复取证通过；Linux sanitizer 临时路径 GC 回归及 Windows
接收件摘要核对通过；本节点单文件已纳入修复。
R81 已完成这些输入投影与 mode 保留修复，三平台零泄漏/零所有权错误、同 owner
两次恢复取证通过。Windows cooked 证据是有界 double，真实控制台资格不扩展。
本节点单文件已纳入修复。R82 已修复取消失败后的 detach 所有权，两台指定 Windows
目标各 176 例零泄漏及同 owner 重试通过；完整 suite 706/706 和 readiness PASS。
R83 已修复 raw 键盘重复、surrogate 和字节限额，两指定目标各 86 个真实控制台
检查零失败、实际模式恢复与 cooked 取消通过；分配故障及 R82/R81 回归通过。
R84 已修复异步 reader/writer 超出 Lua 状态生命周期时的 DLL 保留，指定两目标的
实际 DLL unload/延迟 join、六个 startup 拒绝及 R80--R83 回归通过。
R85 已修复 adapter 失败关闭/确认值/输入代状态及 Linux raw 空闲 EOF，新增十场景和
五个 actual native/PTY 模式恢复通过。当前开发宿主完整 suite 716/716、readiness PASS，
255 文件 / 5603 声明 / 0 注释缺项。已发布 R81 不包含 R82--R85。

## 剩余事项

| 优先级 / 任务 | 剩余工作 | 完成条件 |
| --- | --- | --- |
| P0 · 正式版源码与产物 | R81 候选已交付；R82--R85 形成终端/worker/adapter 修复及专项证据；余完成 Review 后冻结并重建三目标九包与对应旅程 | 将修复源码、最终核心与目标证据重新绑定，预发布或窄探针不能转写为正式资格 |
| P0 · Linux full 输入 | C7 Perl/Git 静态 crypt/HTTP/TLS 闭包、默认 SDK、十工具移动运行和真实 HTTPS 已过；余最终包旅程和来源审计 | `tool_payload_gaps` 清空且完整闭包运行通过；不按版本号复用早期 payload；维护脚本应复现结果，不依赖手改缓存 |
| P0 · C34 证据与来源 | 当前 1.0.0 Windows 两目标实机 706/706 摘要已绑定；余最终九包和完整来源语义审计 | 将目标、源码、核心 SHA-256、环境和通过/失败数绑定；不得用另一个平台或旧源码结果代填；`audit_editions.py --require-nine --require-evidence` 通过只证明文件证据齐备 |
| P1 · C33 交互 | 当前 1.0.0 Linux 双模型各 7/7、随机 token 跨进程召回与 XML operation 证据已过，驱动专项 7/7；余首次配置、保留数据的升级与最终三平台九包的对应旅程 | 使用已授权配置及 TTY；最终源码与字节重新验收；审批核对实际代码，提议与执行分开记录，保留失败日志 |
| P1 · C32/C33 目标运行 | 按 D-077 补指定环境的编码、取消/进程树、发布/恢复及附带工具运行证据 | 使用已有指定实机；分别记录 Windows 最低兼容面和 CentOS 7 容器共享内核边界，不重新索取整套旧系统矩阵 |
| P1 · 注释语义 Review | compact 已通读；R77--R85 所核对子面已复核并取证；余 main 输入协调器失败关闭、Cygwin PTY 失败路径、其余交互内部和测试辅助代码 | 逐项核对参数、返回值、失败/所有权和副作用；异常路径须有实际故障注入证据，全仓结构覆盖不能代替语义审核 |
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

本轮负责人重新提供模型访问：DeepSeek 与本地 sglang qwen3.8-27b；已核对服务可达并
准备隔离配置。凭据在 `out/goal-20261005/private/`，不入库、不投影到日志或 Prompt。
旧核心 14 次请求揭示 R75，后续直接用当前授权配置复跑，不用历史 Stage 2/3 代替。

本机已复现 Linux full Git HTTP(S)/Perl 和完整 SDK 闭包，当前工具输入与九包位于
`out/node-r76-20261005/`；早期 `out/review-20261005/` 结果保留为历史。
使用前核对报告所列摘要，不依赖目录日期判断源码资格。
原构建机与外部目标证据按实际可用性复用，无法核实的面继续标为待验收。

修改前阅读[编码规范](CODING-STANDARD.md)，所有新增/改动函数、类型和回调完整注释。
构建、完整测试、容器和 VM 通过 `.tools/run_with_resource_guard.sh` 串行执行。
每轮按反例、窄修复、专项回归、完整检查、语义核对、状态更新收口。

任务定义与依赖见[实施计划](IMPLEMENTATION-PLAN.md)及
[readiness](contracts/readiness.lua)。旧日期记录的“下一项”是历史资料，不是当前队列。
