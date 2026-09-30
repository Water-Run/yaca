# 内核审查与收尾验收

日期：2026-09-30。基于 `344f864` 及当前工作区修改。
本轮从状态转换、异步所有权、权限和持久化顺序核对内核，发现问题先保留反例，
再修改实现及机读不变量。执行范围按 [D-077](DECISIONS.md#d-077-本次收尾的兼容检查与实机范围2026-09-30)。

## 内核判断

内核应继续由一个 reducer 串行决定主任务的状态。ConfigGeneration 冻结本轮
配置，Permission 决定能力，Tool/Model 端口拥有外部活动，Context journal
拥有唯一的持久化回执；Runtime 消费这些事实，不用自然语言或取消请求代替事实。
这几条边界比增加调度层或状态枚举更直接地决定正确性。

```mermaid
flowchart LR
    C[冻结配置与 Prompt] --> R[Runtime 状态机]
    R --> J[Context intent 与精确回执]
    J --> P[权限与一次性审批]
    P --> E[Model / Tool 异步所有者]
    E --> F[实际响应或终态]
    F --> J2[结果与唯一 turn outcome 落盘]
    J2 --> R
```

审批和 intent 的具体次序由对应 Tool/Operation 协议控制；图表示必要边界，
不是把一次审批当成任意动作的通行证。审查器只能保持或收紧权限，不能授权。

本轮重点是时间与所有权：`cancel_requested`、取消端口的 ACK、活动的终态是
不同事实。ACK 为 pending/unknown 时所有者必须保留；实际成功结果也必须保留，
但本轮的取消 intent 会阻止后续动作。副作用未知优先于取消、转向和完成；
转向只能在已知安全点重新发出请求。关闭则须等待主任务和独立 Ask 都结束。

## R55--R67：状态机缺陷与修复

| 范围 | 反例 | 修复后的保证 |
| --- | --- | --- |
| Tool 取消竞态 | 取消 pending 后工具成功/失败，仍执行后续工具 | 保存真实首结果，剩余调用各配一个 synthetic result，本轮结束；unknown 保持 unknown_side_effect |
| 转向与未知结果 | pending steer 在 unknown 结果前处理，继续发 Model 请求 | 先处理未知副作用，再处理取消，之后才处理 steer |
| Model 超时 | tick 直接 finalize，未取消底层请求；pending cancellation 被丢弃 | 发出一次取消，保留请求 ID，直到真实响应结束；保持 budget_exhausted |
| 审查取消 | action reviewer pending 被丢弃；finish reviewer 晚到 pass 可完成任务 | 保留审查所有者；晚到 verdict 只用于结束活动，取消后的 Tool/finish 不执行 |
| 旧 Model 响应 | 旧 ID 的坏响应先触发验证/超时，结束当前请求 | 先核对 ID，再观察时钟或验证内容；旧响应不修改当前水位与计数 |
| 取消后再转向 | 取消中的主任务又接纳 steer；cleanup 超时改变用户取消原因 | 关闭 steer admission，取消幂等，保留原 terminal intent |
| 工具间 deadline | 未先 tick，晚到首工具结果仍接纳第二工具 | 在实际结果与新 Tool admission 边界复核时间；不接纳后续权限/副作用 |
| 回执丢失 | fail-stop 关闭 admission，却未请求停止正在运行的 Model/Tool/reviewer | 在失去回执后只尝试安全取消；不生成终态、不清掉恢复所需句柄事实 |
| cancel 容量拒绝 | cancel Fact 无法落盘，却取消底层并继续保持可接纳状态 | 转为 fail-stop，尝试一次安全停止，保留未完成事实 |
| 审查 deadline | verdict 到达时已超时，未经过 tick，仍执行 Tool 或完成 turn | 在 verdict 与 Tool 开始处复核时间；配齐预算跳过结果，结束为 budget_exhausted |
| Ask 关闭 | 主任务 Idle/结束时直接 Closing，Ask 仍 pending 或 unknown | 关闭新工作 admission，等待 Ask 实际结束，之后才 Closing/释放 Context |
| 旧 Ask 响应 | 错 request ID 的坏响应或超时结束当前 Ask | Ask ID 和 request ID 都先绑定，再做验证/计时 |

实现集中在 `src/runtime.lua`，机读不变量同步到 `contracts/runtime.lua`。
新增 11 项 fault 回归与 2 项 Ask 集成回归，包含同一测试内的多种真实/未知终态。
三个阶段的修复前证据分别为 `kernel-before.log`（6 项失败）、
`kernel-boundaries-before.log`（2 项）、`kernel-halt-before.log`（2 项）；
审查 deadline 与 Ask 的后续反例保留在各自 `*-before.log`。
最终内核专项 **52/52**。

人工核对了主任务结果配对、cancel/steer 优先级、两类 review 的收尾、失败回执的
安全停止、Ask 与关闭之间的归属，以及生产 activity driver 继续轮询所有者的路径。
没有新增远程控制、子 Agent、后台服务或持久日志。

## R68--R69：附带索引的输入边界

旧记事本写入 UTF-8 BOM 时，INDEX 首行会被当成非法字段；坏 UTF-8 则可能通过
字节字段检查，再进入可选环境说明，使后续 Prompt admission 失败。
现在先验证 UTF-8，接受且剥除文件开头的 BOM；无效内容作为 BundledIndex 拒绝。
环境说明继续跳过无效索引并保留核心说明。没有自动猜测索引字符集。

新增两项解析回归并扩展环境投影用例；修复前专项 25 项中 3 项失败，之后
**25/25**。早一轮 EOF/无进展/不完整前缀修复见
[R51--R54](CODE-REVIEW-2026-09-30.md)。

## 当前验证

本轮日志根目录：`out/review-20260930/`。

| 检查 | 实际结果 |
| --- | --- |
| 完整 Lua suite | **697/697**，资源守卫下串行运行；13 项内核与 2 项索引新增回归 |
| 注释反例 / 全仓结构 | **15/15**；219 文件 / 5256 声明 / 0 缺项 |
| 完整 coding readiness 链 | PASS，含 TP-003/006/008/010 和 RP-001；TP-010 实际 5,564,779 条断言 |
| 契约 / 证明登记 / readiness / 公开文档 | 7739 / 56 / 565 条断言和 5 项文档真值检查通过；Gate R 仍关闭。契约计数含 xmllint 外部 Relax NG 校验，开发机未安装该工具时为 7738 并打印跳过说明 |
| Linux native 构建 | GCC 13、C99、-Wall -Wextra -Werror 通过 |
| open/create 分配故障 | 四端口 0 句柄泄漏，同状态恢复通过 |
| 文件读取 / 进程流故障 | 13 / 20 个分配位置 0 native 泄漏；恢复与终态监督通过 |
| 编码故障与严格 Unicode | decode/encode/lossy 各 18 个分配位置、0 failures/ownership_errors；1,114,113 个标量候选及 8 类坏 UTF-8 通过 |
| 编码与 seek smoke | 13 类代码页往返、12 个偏移与无效/关闭句柄拒绝通过 |
| 实际 Linux 进程监督 | 6 组通过，含 detached descendants、GC；异常父进程退出后子进程停止 |

上述开发机探针不能表述为 XP 或 CentOS 7 实机测量。随后实际 Win64 检查发现
原生发布缺陷，修复和重建记录如下；Win32/Win64 的最低 WINVER 与导入限制保留。

## Server 2008 与工具构建续推

此前提供的 `Administrator@192.168.5.10` 可达，系统为
`CYGWIN_NT-6.0-6003`。在新建的 `/tmp/yaca-kernel-20260930-SOw1IV/` 隔离目录
运行当前源码：**697/697**，原始完整日志已取回 `server2008-full-raw.log`。
重建的当前单文件能显示 `yaca 0.1.0 (win32-x86)`；SHA-256 为
`79a877b4645aa7a532e0f905444521f898ac9d5c5be917d79b8366bb3b1ee4f1`，
源码快照为 `d70b38b5c6cf3112aa493b61ebce942a51a05ba385dc9d279385b5e8b48c2a97`。

首次 Stage 1 因尚未建立相邻数据目录而失败；建立隔离的 `__yaca__` 后，
结果为 **12 PASSED / 0 FAILED**，`outcome=partial`、exit 1。
未初始化配置和 SSH 管道非 TTY 的三个警告保留；`online-requests=0`。
两次日志分别保存，不把 partial 或初始化条件掩盖为全量 passed。

该环境的 tar 工具未完成源码展开，改用其已安装 Python 2.7 在同一隔离目录
校验 archive member 并展开。SCP 映射的 DLL ACL 缺少 execute 权限时，Lua 首次
启动失败；只对隔离目录里的解释器及 DLL 补执行权限后通过。上述为部署通道条件，
没有放宽 yaca 的加载允许表或配置权限。

Windows full 的一项历史阻塞已经解决：微软 SDK 7.1 原始 ISO 的官方 SHA-1
`cde254e83677c34c8fd509d6b733c32002fe3572` 匹配，SHA-256 为
`27cb38f76095c0acb9b558109f8693b39cbceb796856c15bd575f9e9d0b316c3`。
仅提取私有编译输入，未运行安装动作；来源见
[微软原始 SDK 下载](https://www.microsoft.com/en-us/download/details.aspx?id=8442)。
在本机用这套 VC++ 2010 / SDK 从源码完成 **Python 3.4.10** 的完整构建，
14 个扩展模块及 app-local CRT 的便携探针通过；随后 Server 2008 的
ssl/sqlite3/bz2/lzma/ctypes 与实际版本探针也通过。该闭包位于
`out/review-20260930/python34-portable.zip`，没有把 Python 3.4.4 改名成 3.4.10。
构建、源码准备、SHA 验证、stage 日志均保留在本轮日志根目录。

## R70--R71：NTFS 普通用户与目录身份

Win64 当前包在本机 NTFS 的 Stage 1 原子发布失败。生产 native smoke 进一步
复现 `direct Windows replacement candidate changed`：候选文件无论是否需要
修改 owner/group，都请求 WRITE_OWNER。目录继承只给 Modify 的普通用户不能
打开该句柄；管理员 Server 2008 路径没有覆盖这项权限条件。

现在从完整安全描述符比较 owner/group SID 及其 defaulted 状态，选择真正需要
写回的安全字段，再只请求对应的访问权。SID 相同不请求 WRITE_OWNER，也不重新
设置所有者；DACL 和属性仍按原协议保持并在发布后逐项确认。需要改变 owner/group
而权限不足时仍拒绝，未使用宽松 fallback。预发布打不开 metadata 句柄时保留
真实 Windows 错误码，不把访问失败伪装为文件身份变化。

随后 native smoke 的“长名称 rename → 在同目录建立新临时文件 → replace”
复现第二项 `replacement binding changed`：父目录身份比较包含 size/mtime，
正常新增目录项使同一个目录被误判成替换对象。现在父目录独立绑定 kind/volume/
object；目标文件继续核对完整身份与版本，祖先/路径/handle 检查保留。

结果：普通用户 Win64 的 legacy replacement、实际 inherited DACL、长名称文件
及目录 rename/replace/delete、XML 均通过；新的单文件 Stage 1 **12 PASSED /
0 FAILED**，未初始化配置和非 TTY 仍为预期 partial。Win32 重新构建后，指定
Server 2008 Stage 1 同样 **12 PASSED / 0 FAILED**。
现行核心 SHA-256：

| 目标 | SHA-256 |
| --- | --- |
| Win32 | `857680865d91c0a8cbc7f1540717c8c51631392a8cf018913b3b60150cca0a04` |
| Win64 | `a75a106cfecd7a3b053f0e895baf39bb7ea169655530868bbdab86f3fadb72f3` |

先前 79a877... / 5521ec... 等候选保留为中间证据；不再作为最终核心。
日志 `win64-publication-probe.log` 为修复前，`win64-publication-fixed.log`、
`win64-inherited-final.log`、`win64-native-proof-final.log` 和
`server2008-stage1-native-final.log` 为修复后。人工核对最小访问权、描述符字段、
关闭路径和父目录/文件验证的区别；结构检查为 219 文件 / 5256 声明 / 0 缺项。

最终新增原生回归：Linux、Win64 本机及 Server 2008 Win32 的 open/create 四端口
均 0 句柄泄漏；read 13 个分配位置 0 native 泄漏，process stream 在三环境分别
20/11/16 个位置 0 泄漏；codec 故障/恢复与全部 Unicode 标量检查通过。
对应 `native-final-summary.log`、`windows-faults-final.log` 与
`server2008-native-faults-final.log`。最新完整 Lua suite 697/697 再通过，
`closure-readiness.log` 为后续完整 readiness PASS。

## R72：clean 装配与收尾边界

Python 发行装配测试复现 clean 不提供 tool-inputs 时的 UnboundLocalError：
INDEX 位置在 edition 条件前访问尚未定义的 input_path。现在只有非 clean 才
读取该位置，clean 仍只有核心；原有无输入 clean 回归重新通过，发行装配 5/5。
日志 `all-tests-native-final.log` 保留修复前失败，`editions-final.log` 为修复后。

Windows x64 Python 的 VS2019 候选清单未被当作验证通过：channel 声明大小
19,253,644 与 SHA fb642c...，两个请求实际都是 11,154,648 / 406969...；换行
和编码也未还原期望 SHA。失败结果保留，不降低检查、改版本或运行该候选工具链。
因此当前完成的是已列出的实现修复、Windows 当前 core/clean 与 Python 3.4.10
闭包；Linux 当前包、Windows 两个完整 full 与全仓人工审查仍按 TRACKING 收口，
不能宣布整个项目或 Release Gate R 已完成。

## 尚未可宣称完成的部分

这里的结论覆盖列出的内核路径，不等于整个 30 模块、原生层及所有构建工具的
全仓人工语义审查已经完成。现有分页/编码/发布和恢复的历史 Review 继续适用其
记录范围；缺失的审查结论不能用结构检查或测试数替代。

九包的装配与完整工具闭包也与内核测试分别验收。历史 7/9 不是当前源码的最终
通过数；新代码必须进入实际构建。执行队列见 [TRACKING.md](TRACKING.md)。
