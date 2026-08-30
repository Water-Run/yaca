# Harness、Permission 与 Context Compaction 参考实现审查

更新日期：2026-08-30

状态：实施输入；不是目标平台资格证明

## 1. 审查目的与产品定位

yaca 是通用 Agent。代码阅读、修改、构建、测试和项目推进仍是常见且必须可靠的核心场景；同时，产品特别重视系统诊断、获取本机信息和受控调整系统等“本机事务”。后者使以下边界比单纯代码补全工具更重要：

- workspace 外路径和 raw shell 的真实权限边界；
- 命令进程树、取消、超时、输出上限和结果未知；
- 副作用前后的 durable intent/result 与崩溃恢复；
- 长输出、长会话和 compaction 不得伪造已经完成的事实；
- Win32 x86、Windows XP 时代 `cmd.exe` 和低资源机器上的诚实退化；
- 测试 Harness 自身不能通过无界并发、重复链接或残留进程拖垮长程任务宿主。

本轮按负责人指定的优先级逐一核对源码：CodeWhale、OpenClaude、DSH、OpenCode、Pi、CodeX。比较结论只用于发现实现机制和失败边界，不按功能数量照抄产品形态。

## 2. 固定样本与证据边界

| 优先级 | 实现 | 核对版本 / 提交 | 主要证据入口 | XP / 旧 CMD 适用性 |
| ---: | --- | --- | --- | --- |
| 1 | CodeWhale | `0.9.6` / [`9237a577`](https://github.com/Hmbown/CodeWhale/tree/9237a5778facc391a5bcffc91e89d8350ba95761) | `crates/tui/src/compaction.rs`、engine/session、sandbox 与测试 Harness | Windows 没有真实 OS sandbox；不是 XP 目标实现 |
| 2 | OpenClaude | `0.23.0` / [`338f9ad8`](https://github.com/Gitlawb/openclaude/tree/338f9ad85fc93dce6b0702ebf9147f3b49a21e34) | compaction、permission/sandbox、query 与测试设施 | Node 22、PowerShell/现代 Windows；不是 XP 参考 |
| 3 | DSH | `0.1.0-rc.6` / [`15148dbd`](https://github.com/deepseek-ai/deepseek-harness/tree/15148dbd9a1d1f1ef1a26e5749b32af0cd663935) | compaction、journal、approval/sandbox、Harness | Node 22/24；Windows 隔离明确为部分能力，不是 XP 参考 |
| 4 | OpenCode | `1.18.23` / [`ef2880f3`](https://github.com/anomalyco/opencode/tree/ef2880f379129aa048be9e9353e30aa168d42c17) | session compaction、permission、shell parser、Bun tests | 有 `cmd /c`，但安全解析复用 Bash AST；不能作为旧 CMD 授权证明 |
| 5 | Pi | `0.73.1` / [`781152fc`](https://github.com/badlogic/pi-mono/tree/781152fc24841dc54b22284514604048ebe5e2c9) | coding-agent compaction/session、extension sandbox、test suite | Node 20.6+；Windows 倾向 Git Bash/Cygwin/MSYS/WSL，不支持原生旧 CMD |
| 6 | OpenAI Codex | `rust-v0.151.0` / [`78c29080`](https://github.com/openai/codex/tree/78c290807ce710180111df227df3b7a4fe845452) | core compaction、approval/sandbox、unified exec、rollout、nextest | 官方 Windows 路线是现代 Win10/11、x64/arm64；不是 XP 实现参考 |

本机安装件与上表 tag/commit 做了身份核对。CodeWhale 本机可读 crate 缓存是较旧的 `0.8.67`，因此机制结论以官方 `0.9.6` 源码为准；Pi 未安装，本轮只读取官方 tag。OpenAI 产品当前行为另以官方文档核对：[sandbox](https://learn.chatgpt.com/docs/sandboxing)、[approval/security](https://learn.chatgpt.com/docs/agent-approvals-security)、[Windows sandbox](https://learn.chatgpt.com/docs/windows/windows-sandbox)、[slash commands](https://learn.chatgpt.com/docs/reference/slash-commands)。

这些现代实现都不能替代 yaca 在真实 XP SP3 x86、Win7 SP1 x64 和 CentOS 7 x64 上的原生证据。源码交叉编译、合成 `cmd.exe` fixture 或现代 Windows 成功，只能是候选证据。

## 3. 分项目结论

### 3.1 CodeWhale（最高优先级）

#### Compaction

- 手工 `/compact [focus]` 与 context pressure 自动触发共用一个生命周期。
- 在调用摘要 Model 前先机械移除旧的大型/重复 tool results；provider context 的缩减与持久 session receipt 分离。
- active history 最终只保留一个当前 summary marker；旧 marker 和 legacy marker 会被替换。
- 最近用户消息有独立保留预算；context overflow 时按“丢最旧历史并清理孤儿 tool result”的有界阶梯重试。
- summary 请求禁用工具；provider 声明 incomplete 时拒绝发布部分摘要。
- transient retry 有界，确定性错误不盲目重试。
- 不足：注释声称 summary 有最低可用性，但空摘要仍可落为 `(no summary available)`，没有真正的非空/收缩验证。

#### Permission / sandbox

- approval 和 sandbox 是两套控制；approval 不能把 read-only sandbox 变成可写。
- denial 指纹比 session grouping 更精确；规则具有 deny/ask precedence 和动态复核。
- persistent ask/allow 可以形成比单次调用更宽的规则，yaca 不应复制这种默认授权面。
- `0.9.6` 在 Windows 没有真实 OS sandbox；Linux bubblewrap 是可选且可能不可用。对 yaca 的直接结论是：XP 上必须继续把 `exec` 明示为 `opaque-uncontained`，不得把 Permission 文案宣传成隔离。

#### Harness

- 有临时 workspace、真实 list/read/search/edit/patch/Bash 循环和 JSONL record/replay。
- mock 边界位于 `LlmClient`，README 明确说明并非完整 engine 证明。
- 曾把 26 个 TUI 测试 binary 收拢为 3 个 harness，以降低链接耗时和内存；PTY suite 串行。

#### 对 yaca 的采用

采用分层 compaction、唯一 active summary、incomplete 拒绝、overflow 阶梯、测试 binary 收拢和 PTY 串行。拒绝默认持久 grant、Windows sandbox 暗示和空摘要占位发布。

### 3.2 OpenClaude

#### Compaction

- microcompaction 先清除较旧、可压缩的 tool result；完整 `/compact` 接受定向指令且禁用工具。
- boundary metadata 保存 trigger、压缩前 token、parent、工具和保留段；重建时重新附加 attachment、plan/skill/deferred/MCP 和 transcript 元信息。
- 自动阈值在 window 减固定安全余量处触发；连续失败达到阈值后进入 circuit breaker/cooldown/half-open。
- compaction 失败且请求仍超窗时在发出 oversized request 前停止。

#### Permission / sandbox

- deny 优先于 ask/allow；noninteractive 无回答时 fail closed。
- workspace 外动作单独提示。
- sandbox 只覆盖 macOS/Linux/WSL2；unsupported 默认会警告后无 sandbox 运行，也可用 `failIfUnavailable` 拒绝。
- native Windows/XP 不在支持面。

#### Harness

- 大量 test-like 文件，但完整 suite 最大并发为 1。
- 对全局 mutation 加锁、按 scope 恢复，并检查 stub 泄漏。

#### 对 yaca 的采用

采用跨生命周期的 compaction circuit breaker、超窗 fail-stop、noninteractive approval fail closed、全局可变测试串行。拒绝 unsupported sandbox 默认 fail-open。

### 3.3 DSH

#### Compaction

- service/provider/command 分层；手工 `/compact` 与自动路径共用 canonical envelope。
- 可选 model-free tool-result pruner；保留 call/result pair，处理 runaway 或不可拆 tail。
- 有 convergence/shrink 检查与有界重试；摘要请求 one-shot/no-tools，不把 reasoning/tool call 当摘要。
- durable start/summary/replacement/end bracket 明确；orphan lock 保留“曾经忙”的证据，stale lock 有严格规则。
- provider overflow 只在 durable surface 确认进展后重试一次。
- 大结果在可见视图里保留有界 head/marker/tail，原始日志不被改写，重复 pruning 幂等。

#### Journal / recovery

- Model 前、side-effect tool 前、下一 Agent step 前均有 flush barrier。
- cancel 发生在 dispatch 前可记录 `ABORTED_BEFORE_DISPATCH`；未配对工具收口为 `TOOL_OUTCOME_UNKNOWN`，不宣称 exactly-once。
- JSONL publish 使用 no-overwrite；POSIX hardlink + parent fsync，Windows `MoveFileEx` + `WRITE_THROUGH`；写/sync 失败会回滚长度。
- 只修复 torn tail，中段损坏拒绝加载；sequence 连续且单 writer。

#### Permission / sandbox

- preset、sandbox、approval 分离；read-only 是默认 fail-safe。
- approval ask/never，缺少回答 fail closed，具有审计记录。
- 不足：approval request 只有 tool name/reason/call ID，没有完整参数；yaca 必须保留自己的 exact action fingerprint。
- filesystem edit 使用 read-before-edit CAS 和重新 canonicalize。
- Windows restricted token/ACL 明示为部分隔离，存在 read/network/process visibility、FAT/hardlink 限制；不是 XP sandbox。

#### Harness

- unit、逐文件 100%、real-API e2e、snapshot/browser 分层；只 mock 昂贵或不确定边界。
- 断言真实外部状态和未触碰字节；测试发布入口/loader composition、crash/recovery/cancel/order/race/HMR、跨平台和构建产物。

#### 对 yaca 的采用

DSH 是 durable operation 和恢复方面最强参考。采用 tail-only repair、中段损坏拒绝、明确 unknown、发布入口 composition 测试和字节未变证明。拒绝不含参数的审批绑定。

### 3.4 OpenCode

#### Compaction

- 当前配置支持 auto/prune/keep/buffer；估算会计入完整 JSON，保留最近完整 message，tool result 有独立预算。
- structured prior summary 可合并，具有 start/end event 和 overflow 重试。
- 不足：摘要可包含 reasoning，只检查 failed/providerError/empty，没有 completeness、shrink 或 convergence；失败路径可能留下 Started 而没有 Ended。

#### Permission / shell

- rule 以 action/resources/save/metadata/source 表达，last-match；agent deny 优先；支持 once/always。
- 没有 OS sandbox。
- Windows 运行走 `COMSPEC` / `cmd /c`，但除 PowerShell 外的 shell 统一交给 Bash parser，包括 CMD。Bash AST 不能证明旧 `cmd.exe` 的真实命令边界或副作用。
- `--auto` 可批准没有显式 deny 的动作，授权面不适合 yaca 的本机变更场景。

#### Harness

- package 级 Bun tests；隔离 XDG/home、清除凭据、in-memory DB，并处理 Windows `EBUSY` cleanup。
- root test 故意失败以阻止错误入口；但没有资源预检，turbo/Vitest 仍可能并行制造峰值。

#### 对 yaca 的采用

采用精确 cwd/external-dir metadata、隔离 home/凭据和 Windows cleanup retry。拒绝 Bash AST 作为 CMD 授权证明、宽 `always` pattern、reasoning summary 和 dangling Started。

### 3.5 Pi

#### Compaction / session

- 超过 `window-reserve` 后触发；手工路径接受额外指令，保留最近约 20k token。
- 只有成功才 append compaction entry；旧 summary 合并；mid-turn 可以先生成两份摘要再合并。
- cut point 避免拆 call/result，累计 file operation，并把 tool result 限到前约 2k。
- 不足：摘要包含 reasoning；只看 stopReason error，没有 empty/truncated/shrink/convergence；overflow 只恢复一次。
- JSONL append 没有 fsync/atomic checkpoint；parser 会跳过任意位置 malformed line，可能把中段损坏误当可恢复 tail。

#### Permission / shell

- core 没有完整授权系统；extension 示例用 regex 拦截 `rm/sudo/chmod`，无 UI 时示例 fail closed。
- sandbox 示例依赖 Anthropic runtime，限 macOS/Linux，unsupported/init failure 会 fail open。
- Windows 偏向 Git Bash/Cygwin/MSYS/WSL，不是原生 CMD；Node 20.6+ 排除 XP。

#### Harness

- 新 harness 围绕 AgentSession/Runtime，以 faux provider 替代真实付费 API，临时目录、内存 Session/Settings/Auth，结束时 dispose/unregister/remove。
- Vitest timeout 30s，但没有 worker/pool 上限和宿主资源预检；CI 只有 Ubuntu Node 22。

#### 对 yaca 的采用

采用确定性 provider boundary fake 和显式 cleanup。拒绝中段损坏跳过、无 fsync session、unsupported sandbox fail-open 和 Windows shell 旁路。

### 3.6 OpenAI Codex

#### Compaction

- local、remote、remote-v2 三条路径；手工与自动均存在。
- local path 使用结构化 handoff prompt；同一 model session 生成 summary，stream retry 有界，context overflow 时逐步移除最旧 history。
- 保留最近 user message（有独立预算），移除既有 summary marker，最终追加一个 summary；replacement history 持久化并在训练边界重新注入。
- 测试覆盖多次 compaction、resume、model switch 和 mid-turn。
- 不足：完成响应没有 assistant text 仍会被接受为 `(no summary available)`；local path 没有完整 stop-reason/shrink/convergence 验证；已存在 manual `/compact` 非 context failure 的 known-incorrect test；pre-turn compact 不包含即将进入的 user message。

#### Permission / sandbox

- approval event 绑定 command tokens、cwd、call/approval/turn/environment ID、parsed command、network context、额外权限和 policy amendment。
- cache key 绑定 environment、executable、canonical command、cwd、TTY、sandbox/additional permissions 和 exec-policy fingerprint。
- denied-read restriction 不会因 unsandboxed escalation 消失；unsupported Windows split policy 会拒绝无 sandbox 运行。
- sandbox 与 approval 分离；Windows elevated/unelevated sandbox 面向现代 Windows。官方文档当前建议 Windows 11，更新后的 Windows 10 为 best effort，ConPTY 依赖 Windows 10 1809+；不适用于 XP。

#### Process / rollout / Harness

- unified exec 对保留输出设 1 MiB 上限，稳定保留 50/50 head/tail 和 omitted-byte marker；最多跟踪 64 个进程。
- live process 在初次 wait 前就登记，turn 中断不会立刻丢 handle；有 terminal interaction lock、cancel/terminate 和 completion timeout。
- process handle 只在内存中，不是 crash-durable。
- rollout writer 有界队列和 flush barrier，但不做 `sync_data/fsync`；loader 会跳过中段 malformed JSON，弱于 DSH。
- integration suites 聚合到较少 binary；nextest 对 protocol codegen、app-server integration、apply-patch、Windows sandbox、Windows process-heavy 分组限并发。源码注释明确提到 resource contention/global desktop exhaustion；Windows full CI 把 test threads 限到 8。

#### 对 yaca 的采用

采用完整 approval fingerprint、denied-read 不随提权消失、稳定 head/tail 输出和资源重型 suite 分组。拒绝空摘要占位、中段日志损坏容忍和现代 Windows 假设。

## 4. yaca 当前实现审查

### 4.1 Compaction：算法与 Context journal 已闭合，公开生产组合仍缺失

已经实现且优于多数参考的部分：

- 七个强制非空结构槽：目标/决定、约束/权限、文件、验证、未知副作用、TODO、Prompt/Model transition。
- 长度标记的 canonical summary envelope，绑定 schema、source first/last/digest；canonical body、digest 和结构字段必须互相一致。
- union-find 构造不可拆 atomic group；turn/request/toolCall/operation/queue ID 会联结。
- 未配对 tool call、未决 operation、active turn、unknown operation 和 unknown side effect 强制留在 tail，不能被摘要掩盖。
- 预算包含 Prompt、tool/control schema、最大输出、reserve、correction；单 group 超窗或 mandatory view 无法容纳时等待用户。
- intent 在 Model start 前 durable；response/rejection/publication 各自要求精确 generation/manifest receipt。
- 只有新 view 有实际收益、低于阈值且 manifest 可验证时才发布；旧 view 保留到原子 publish。
- 失败最多一次纠错重试；取消 request/result durable，pending cancel 有明确状态；summary correction 是追加事实，不回写旧摘要。
- Model 层已有独立 no-tool compaction builder/port：冻结 config/Model/Prompt/source/manifest binding，只发送一次 quoted source，provider incomplete、非 stop、tool/control 和结构不完整输出均不能成为摘要。
- 连续 automatic compaction 失败已有 service-lifetime cooldown/half-open；canonical summary envelope 超限会作为可 durable 拒绝的 Model 输出返回，不会把端口永久卡在 busy。
- `session.lua` 已提供 production Context compaction journal：request、response、rejection、cancel request/result、publication 与 correction 都按精确 generation、旧 manifest、source range/digest 和 lifecycle 绑定。
- accepted summary 先独立重建 structured summary、canonical source 与 manifest，再把 terminal `compaction`、`CompactionRecord` 和 `model_view_published` 在一个 Context generation 内提交；任一验证或 publication 失败时旧 XML 与旧 active manifest 保持不变。
- accepted view 的恢复不依赖内存 cache：启动或 cache miss 时从完整 XML 重新校验 accepted bracket、source/summary digest、publication adjacency 和 active manifest，再确定性重建 summary-prefix view；后续事实只追加 tail，不会把内部 compaction request/response 重送给 main Model。

已确认的 P0 缺口：

1. `main.lua` 尚未实例化 `compact.new`、Model compaction port 与 Context journal 的完整生产 lifecycle。
2. CLI 注册 `.compact`，但 ApplicationCoordinator 没有该 action 分支，当前会返回 `InteractiveActionUnavailable`。
3. Model compaction builder/port 尚未经过 `main.lua` 的 endpoint-disclosure admission 与真实 transport composition；当前已完成 no-tool/frozen-binding 边界和 isolated adapter 测试。
4. Runtime 没有 automatic threshold admission、跨进程恢复的 failure cooldown，或恢复 pending compaction marker 的 owner；现有 circuit 状态只覆盖同一 service lifetime。
5. response wrapper 已在 Model port 与 `compact.lua` 双层验证 provider `incomplete`/finish class/tool/control，但仍需 production adapter 黑盒测试证明这些字段没有在组合层丢失。

2026-08-30 的受资源门禁串行 suite 为 `391/391`，其中已含 canonical manifest 伪造拒绝、失败前后 Context 字节/代不变、accepted summary + view 原子发布、cache-miss 恢复和取消 terminal truth；这些证据关闭 Context publication 缺口，但仍不能证明公开 `.compact` 可用。README 的“implementation complete”只有在剩余生产组合闭合后才成立。

### 4.2 Permission：精确单动作授权是强项

`src/permission.lua` 与 `src/tools.lua` 已实现：

- 固定 `Read/Write/Delete/Shell/OutsideWorkspace` 三态矩阵，deny 取更严格结果；reserved tree 是 hard deny。
- direct path 工具做 canonical path、physical ancestry、link/hardlink/special-file、target identity 和 expected raw digest 复核。
- approval snapshot 绑定 tool/schema/registry、完整 canonical arguments、canonical target、expected digest、cwd、workspace identity、operation/tool-call ID、Permission/profile/config generation 和 review 状态。
- approval 只在当前进程有效、不可复用、一次消费；历史/外进程 approval 只有审计意义。
- high-risk action reviewer 只能收紧，`uncertain` 阻断；prompt 文本不能授权。
- `os_sandbox=false`、`shell_scope=opaque-uncontained`、`historical_approval_authority=false` 明确公开。

需要保持而不是“增强掉”的设计：`OutsideWorkspace` 只约束可证明路径的 direct tools。raw `exec` 即使 cwd 在 workspace 内，也可能通过绝对路径、子进程或网络触达 OS 允许的任意资源；它只由宽 `Shell` 能力和完整 action approval 管理。把 Bash/PowerShell/CMD parser 加进来只能做额外警告，不能成为 containment 证明。

后续补强项：

- non-TTY / 无人工输入时，所有 confirm 必须从生产入口一致 fail closed；
- 审批 UI 必须一直显示完整 command、cwd、`opaque-uncontained` 和无 OS sandbox，而不是只显示摘要；
- shell 环境、平台 shell snapshot、deadline/output cap 也应进入或间接绑定 exact approval fingerprint；当前 tool call 绑定 command/cwd，authorization 又绑定 config generation，需用 production composition test 证明二者没有脱节。

### 4.3 Durable operation、process 与旧 CMD

已有强项：

- mutating direct tool 和 `exec` 均在 dispatch 前写 durable operation intent；result durable 失败会阻断后续 operation。
- 未证明子孙进程停止、native exception、rename/delete durability 不明时收口为 `unknown`，不自动重放。
- Windows shell 固定由 native `GetSystemDirectoryW` 得到系统 `cmd.exe`，不信任 `COMSPEC`、PATH wrapper 或用户 shell；参数固定为 `/D /S /C`。
- command 是 opaque text，不用 Bash AST 冒充 CMD 语义；stdin 关闭，环境 minimal/inherit-filtered，stdout/stderr 各自有固定 quota。
- 输出使用稳定 head/tail 累积和精确 observed/retained/discarded accounting；registered secret 支持跨 chunk 扫描。
- native Windows 使用 Job Object 管理进程树；取消和超时必须证明 job empty，否则结果 unknown。

仍需真实目标证明：

- XP SP3 x86 的 `CreateProcessW` quoting、OEM/ANSI/Unicode command behavior、`/D /S /C`、路径含空格/括号/`&|<>^%!`、关闭 stdin 和双 pipe backpressure；
- XP 在宿主已处于 Job Object、FAT/FAT32、无硬链接/目录 flush 能力时的 fail-safe 行为；
- synthetic Enter 取消 cooked console thread 后，旧 XP 控制台 echo/backspace/IME 与后续输入不被污染；
- 进程树无法证明停止时确实输出 unknown，而非错误地标 cancelled/success。

Release Gate R 在这些原生证据完成前保持关闭。

### 4.4 Session / Context durability

已有强项：

- 第一条 main message 在任何 Model/side effect 前创建并 durable publish generation 1。
- 每个 Runtime barrier 生成完整 XML replacement；writer 单 owner、临时文件 no-replace、发布 receipt 精确绑定 generation/sequence。
- operation intent/result 被翻译成同一 Context 事件流，Runtime 必须领取外部 receipt 后才能推进自己的 sequence waterline。
- next turn 从 durable Context override 重新加载完整 Config generation；active turn 不漂移。

Compaction publication 已能构造并提交完整 generation：terminal event、`CompactionRecord` 与新 ModelView 必须同批匹配，accepted view 可从 XML 重建；error/cancel 不能偷换 active manifest。剩余恢复缺口只在**未收口** lifecycle：启动时尚未把 intent/response-only bracket 归并为明确 cancelled/unknown，跨进程 circuit 状态也尚未恢复。

### 4.5 Test Harness 与 OOM 风险

已有措施：

- Lua runner 按稳定顺序发现 suite，测试文件使用隔离 global，case 失败不阻止后续 case，package.loaded/path/cpath 在 case 后恢复。
- suite 本身串行执行，避免 Lua case 级并发。
- `.tools/run_with_resource_guard.sh` 在重任务前获取每用户独占锁，并检查 host/cgroup 可用内存、Swap、每 CPU load 和 Linux memory PSI；不安全时在目标命令启动前以 75 拒绝。
- coding readiness、target proof 和 Linux qualification 入口自动进入 guard；README 要求完整 Lua suite 也通过 guard。

审查发现的 Harness 缺口：

1. 组件单测全绿不等于生产 composition 已接线；`.compact` 是现实反例。
2. 应枚举公开 action registry，要求每个 action 在对应生产 dispatcher 中有 executable route，或明确标成不可用且不出现在公开 help；不能依赖手写数量。
3. native/PTY/target suites 需要显式 group 和串行策略，不能只依赖顶层脚本目前恰好顺序执行。
4. full suite 的资源守卫是 shell 入口能力；直接执行 `bin/lua55 test/run.lua` 仍可绕过。发布/CI 文档和脚本必须只调用 guarded entrypoint，并由 readiness 检查该调用图。
5. 临时目录/文件 cleanup 要覆盖 Windows `EBUSY`/残留 handle，测试结束还要检查 yaca 子进程树；不得扫描后误杀其他 Codex、浏览器或用户进程。

## 5. 采用、调整与拒绝矩阵

| 机制 | 决定 | yaca 投影 |
| --- | --- | --- |
| 一个 active summary，原事实不删 | 采用 | 保持 `compact.lua` 的 structured prefix + durable XML facts |
| compaction 前机械清理大/重复 tool result | 调整采用 | 只改变 provider view；保留 canonical result 与 digest；必须 call/result 成组且幂等 |
| provider incomplete / 空摘要拒绝 | 采用 | response wrapper 增加完整性字段；七槽非空继续作为硬门 |
| shrink/convergence 检查 | 采用 | 现有 `minimum_benefit_tokens` 继续；补跨 lifecycle circuit breaker |
| 宽 persistent allow/always rule | 拒绝 | v0.1 保持 exact one-action、current-process、consume-once |
| sandbox unsupported 后无隔离运行 | 拒绝 | 若未来声明 sandbox，unsupported 必须 fail closed；v0.1 继续明确 `os_sandbox=false` |
| Bash AST 解析 CMD 作为授权证明 | 拒绝 | CMD command 保持 opaque；parser 最多只收紧/警告 |
| malformed JSONL 中段静默跳过 | 拒绝 | 只允许有证据的 torn-tail repair，中段损坏阻断 |
| 大输出稳定 head/marker/tail | 采用 | yaca 已有 head/tail/accounting；补用户可见 omitted marker 和 artifact 边界时不得虚构可取回性 |
| faux provider + 黑盒 production composition | 采用 | Model wire 使用 deterministic fake；同时必须走真实 builder/activity/publication/coordinator |
| 无界 test workers / 多重链接 | 拒绝 | 重 suite 分组串行、资源 guard、单宿主重任务锁 |
| 现代 Windows 证明替代 XP | 拒绝 | Win32 XP、Win64 Win7、Linux CentOS 7 各自独立资格证据 |

## 6. 实施顺序

### P0：生产闭环

1. [x] 为 Model 增加 no-tool compaction request builder/port，冻结当前 turn 的 Model/Global prompt、view/source binding 和输出上限。
2. [x] 为 Context publication 增加 compaction snapshot/journal；request、response/rejection/cancel/correction 和 accepted summary 均有精确 generation/manifest receipt。
3. [x] accepted summary 与新 ModelView manifest 在一个 publication generation 中提交；旧 manifest 在成功前保持 sole active。
4. [ ] ApplicationCoordinator 接通 `.compact`，只在 durable Idle/WaitingUser admission；STATUS 开始/完成/失败可见，可取消。
5. [ ] 自动 compaction 在下一 Model request 前按 manifest threshold 触发；失败仍超窗时停止，不发送 oversized request。
6. [x] response 必须证明 `incomplete=false`、finish class 完整、无 tool/control；空或无收益摘要拒绝。
7. [ ] 连续自动失败进入有界 circuit breaker/cooldown/half-open；手工请求仍给明确结果，不递归重试；当前仅同一 service lifetime 已实现。
8. [ ] 恢复 incomplete compaction bracket 时保留旧 view并落 cancelled/unknown，绝不把未发布摘要当 active；accepted bracket 的恢复已实现。

### P0：Harness 证明

1. 增加 public action registry → production dispatcher composition audit，覆盖 `.compact`。
2. 增加 compaction 的真实 builder/activity/fake-provider/journal/XML/coordinator black-box journey。
3. 增加 crash 点：intent 后、response 后、publish 前、publish receipt 丢失、cancel pending、重启恢复。
4. 每次测试前通过 resource guard；native/PTY/target suite 单独 group 并串行。

### P1：Permission 与本机事务

1. 生产 approval transcript 明示完整 command、cwd、Shell 宽权限、无 OS sandbox、deadline/output/env snapshot。
2. 非交互 confirm 全路径 fail closed；拒绝任何 prompt/历史 approval 取得 authority。
3. direct tools 增加更多真实 filesystem byte/metadata/alias/race 证明；raw shell 继续报告无法推断的副作用。

### P1：代码开发体验

1. 保持 list/read/search/patch/write/exec 的完整闭环，不因本机事务侧重而削弱常规项目开发。
2. 长构建/测试输出使用有界 head/tail、准确截断和 continuation/artifact 语义；没有 artifact 时明确不可恢复全文。
3. compaction summary 的 `files_touched`、`verification_evidence` 和 `open_todos` 保留精确路径、命令、错误与未验证状态。

### P2：目标资格

1. Win32 XP SP3 x86、Win64 Win7 SP1 x64、CentOS 7 x64 各自原生 build/run/full-suite/proof。
2. 干净机完成配置、新建/恢复、代码修改、系统信息读取、受控 Shell、取消、compaction、退出/升级/卸载 journey。
3. 只有三目标全部通过、最终 archive 证据齐全时才能打开 Release Gate R。

## 7. 当前结论

yaca 的 Permission exact binding、direct filesystem 复核、durable operation、compaction algorithm 与 Context 原子 publication 已经具有很强的底层约束；当前最大风险不是“算法太弱”，而是 Model transport、Runtime admission、ApplicationCoordinator 与公开 action 还没有进入同一个生产 Harness。下一里程碑必须以 `.compact` 的端到端组合、未收口 lifecycle 恢复和公开 action 接线审计为核心，而不是继续增加只在单元 fixture 中成立的能力。
