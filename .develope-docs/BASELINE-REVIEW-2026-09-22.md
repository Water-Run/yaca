# 通用 Agent 大改基线复核（2026-09-22）

本次为定位和开发排序提供证据；没有生成新发行包，没有运行在线模型请求。

## 仓库与本地测试

- 起始提交：`36abd51cf74ab3cd51f3a1ea7def464b90c48a0e`，开始时工作树干净。
- 运行 `bash .tools/run_with_resource_guard.sh bin/lua55 test/run.lua`。
- 结果：`SUMMARY total=575 passed=575 failed=0`。
- 临时日志：开发机 `/tmp/yaca-baseline-20260922.log`；此路径不是长期发行证据。
- 该 suite 证明当前本地回归基线，不证明三个旧系统目标或 USB 文件系统资格。

本次文档改动后的 design/proof/readiness 校验结果见文末。

## 指定测试机

通过负责人提供的 `Administrator@192.168.5.10` 接入，观察到：

```text
Caption: Microsoft Windows Server 2008 Enterprise without Hyper-V
Version: 6.0.6003
OSArchitecture: 64-bit
Cygwin: CYGWIN_NT-6.0-6003, 3.3.4-341.x86_64
```

测试对象为已有 N13：

```text
C:\Users\Administrator\yaca-0.1.0-preview-n13\yaca.exe
version: yaca 0.1.0 (win32-x86)
SHA-256: 136feb2ea7abe507f2a777ad01d7fd9f4a0f3a4f3652a2c6d9a73e327eed7920
```

其哈希与[9 月 16 日交付记录](BASIC-USABILITY-ACCEPTANCE-2026-09-16.md)一致。
系统已有 Python、curl、旧 Lua 等工具，且测试账户为管理员；这不是无依赖干净机验收。

## 直接 SSH 路径

本地分配 PTY、SSH 使用 `-tt`，进入 N13 目录运行：

```text
./yaca.exe --version
./yaca.exe --self-test --through-stage 1
./yaca.exe work
```

version 成功。直接 chat 明确返回：

```text
yaca: TtyRequired: this action requires both stdin and stdout to be interactive terminals
```

原生 Windows 的 `stdio_facts` 使用 `GetConsoleMode` 判断标准句柄
（`native/yaca_native.c`）；远端 Cygwin PTY 不因此自动成为 Windows console handle。
这说明当前 `ssh -tt` 本身不足以满足该入口的要求。

该次直接 self-test 中，platform/package/native/data/config/atomic-write/codec 等检查 passed，
Catalog 为 unknown/incomplete，lock 被跳过，TTY 为 warning；最终
`outcome=error completed-stage=1 online-requests=0 auto-fixes=0`。
仅凭这次观察不能判定 Catalog 根因，也不能声称旧历史损坏。

## Windows 控制台路径

同一 SSH PTY、同一目录，经 `winpty cmd` 打开持续存在的原生控制台，再运行：

```bat
yaca.exe --self-test --through-stage 1
```

完整观察到全部 15 项 `PASSED`（含 Catalog、lock、TTY），末行：

```text
self-test outcome=passed completed-stage=1 online-requests=0 auto-fixes=0
```

另一次 machine 输出显示 Catalog 为 1 个 valid Context，0 个 corrupt/unavailable/changed，
0 个 busy，workspace roots=1、invalid roots=0。
因此原始 SSH 路径的 incomplete 与控制台路径成功需保留为对照，不能简单归因为文件损坏。

直接运行 `winpty ./yaca.exe ...` 也观察到各项通过，但进程关闭时捕获尾部会被截断；
上述持续 CMD 的完整摘要是采用的自检证据。测试结束后退出测试控制台。

## 可得结论与限制

1. N13 在指定服务器的原生控制台路径仍能通过离线自检。
2. 用户期望的 SSH 中直接 `./yaca.exe` 交互当前失败，是 F1 的可复现验收起点。
3. 尚未验证本次真实模型连接、故障代理、错时钟、干净标准用户、实际 U 盘、
   FAT32/exFAT、工具包、XP/Win7/CentOS 完整矩阵；旧在线证据仍只引用此前报告。
4. 离线 self-test 的原子发布探针会创建并清理独立临时文件；它不是完全无写入的检查。
   本次没有修改已有配置/业务文件，没有自动修复、破锁或重放 Context 操作。

## 新增静态源码发现

以下为源码结构观察，不是本次真机复现的故障；实施方案见
[大改蓝图](MAJOR-REDESIGN-PLAN-2026-09-22.md)。

- `src/main.lua` 的 `build_context_services` 将 Context 限为 256 事件、1 MiB XML，
  单字段 64 KiB；`AGENT_RELEASE_OPTIONS.runtime.hard_caps` 则允许 256 次工具调用
  和 16 MiB result 预算。事件与工具次数不是一一对应，不能按差值推算还能执行几次。
  需要跨层容量接纳与收尾预留，模型压缩不删除原始事实。
- `src/tools.lua` 的 `read_bytes` 先整文件读取，`read` 再选择行范围；main 配置的
  文件上限为 16 MiB，search 跳过超大文件并报告。大文件读取/搜索需要有界流式路径。
- `channel_projection` 对不能作为严格 UTF-8 文本投影的进程输出保留 base64。
  这不是已完成的 ACP/OEM/CP936 解码支持。
- Windows builder 已生成 `inner.exe`、`lua55.dll`、`.luai` staging，再制成 onefile；
  可复用它验证 onedir，但现有产物不能直接被称作已验证目录发行包。
- native 已有内部组件的 argv/stdin 直接进程启动能力；当前 Agent `exec` 仍是
  `command/cwd/deadline_ms` 接口。结构化调用内置 Lua 是拟议扩展，不是现成功能。

## 文档一致性验证

文档更新后，经过同一 resource guard 串行执行三个现有校验器，结果：

```text
design-contract validation PASS: 7612 assertions across 16 contracts and 12 fixture sets
proof-evidence validation PASS: 56 assertions across 4 modern proofs
coding-readiness validation PASS: 553 assertions; Gate A/B passed, Release Gate R closed
```

这里校验了既有 proof 证据，没有重新构建/运行整套 modern proofs。
纳入负责人后续通用 Agent / 可选 tools、内嵌 Lua / 三档发行澄清后，再次通过上述三个校验器。
另检查本次 13 份 Markdown 的 98 个本地链接及其中 2 个标题锚点，全部有效；
三个参考源码的提交号和报告中的
固定提交文件路径均与检出的源码一致。`git diff --check` 通过。
本次未改变产品代码，因此未在文档编辑后重复运行先前已通过的完整 Lua suite。
