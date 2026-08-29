# Gate A / B 编码就绪审计

审计日期：2026-08-29
基线：`main@157f59c` + 本节点的 contracts / fixtures / plan 变更
结论：**Gate A 通过；Gate B 通过；Release Gate R 关闭**

## 1. 审计结论

yaca 已经可以开始编写产品代码，但不能声称已经实现、可发布或通过最低平台资格验证。

- **Gate A（实施计划就绪）= PASS**：当前产品语义不存在需要开发者临场选择的 A/B 分支；16 份 machine contract、12 组 fixtures 和 proof backlog 给出了实现输入、失败语义、待测事实及失败退路。
- **Gate B（编码就绪）= PASS**：[`IMPLEMENTATION-PLAN.md`](IMPLEMENTATION-PLAN.md) 与 [`contracts/readiness.lua`](contracts/readiness.lua) 已冻结 `M0..M10`、`C01..C34` 的文件、依赖、测试、退出条件和提交边界；首个任务唯一为 `C01`。
- **Release Gate R（资格与发布）= CLOSED**：Win32 x86/XP、Win64 x86_64/Win7+、Linux x86_64/CentOS 7 的 yaca-specific 构建、运行、故障注入、干净机和最终 zip 证据仍未完成。任何 target failure 都阻止发布。

本判定不把 `proven-modern` 外推成 `proven-target`，也不降低 D-007、D-009、D-056 的三目标保证。

## 2. 修正的门禁语义

旧版 [`ARCHITECTURE-READINESS.md`](ARCHITECTURE-READINESS.md) 同时写了“全程序实施计划前所有 P0/P1 实现/目标证据必须 passed”和“最终 XP/x64 qualification 位于打包阶段”。这形成循环：没有实现和最终包就无法产生目标证据，但没有目标证据又不允许写实现计划或代码。

现统一为三个阶段：

```text
Gate A: specification / proof-plan ready
  -> Gate B: executable whole-program plan ready
  -> implementation and bounded integration proofs
  -> Gate R: all target/package evidence passed
  -> release
```

Gate A 只在以下条件同时成立时通过：

1. 当前产品选择唯一，register 为 `unanswered=0/conflict=0`。
2. 每项 P0/P1 都有唯一 machine contract 或不改变产品保证的明确实现任务。
3. 现在能验证的关键候选已经 modern-proven；只能在实现后或目标机上验证的事实，已经绑定任务、通过条件、失败退路和不可绕过的 hard gate。
4. 未冻结的 MB/ms/count 等发行常量只从注入的 release manifest 消费，不伪装成产品配置或无限值。

Gate B 只在全程序计划写出精确文件、依赖、测试、退出条件和提交边界后通过。Gate R 才要求实现完成、三目标 `proven-target`、最终 zip、SBOM、许可证、构建摘要和干净机旅程全部通过。

## 3. 审计输入

| 输入 | 审计结果 |
| --- | --- |
| 产品选择 | D-001..D-071；register `unanswered=0/conflict=0` |
| Machine contracts | 16 份，版本 `0.1.0-readiness.1` |
| Synthetic fixtures | 12 组；含 argv、Permission、AgentLoop、Context、formats、path、transport、Prompt、wire、TUI |
| Contract validator | 通过；同时校验 module/file/task/target/proof crosswalk |
| Modern proof | TP-003/006/008/010 = `proven-modern`，各自保留 `target_pending` |
| 产品源码 | `src/*.lua` 仍为零字节 skeleton；未把 proof 当产品实现 |
| 发布资格 | 无 `proven-target`，Gate R 保持关闭 |

## 4. P0 明细

`plan-ready` 表示实现输入和本地验收已经闭合；`qualification-bound` 表示规格已闭合，但某项事实只能在实现/目标机/最终包阶段证明，且已绑定 hard gate。

| Gate | 计划状态 | 权威输入 | 现有证据 / 待证事实 | 任务与 hard gate |
| --- | --- | --- | --- | --- |
| AR-P0-01 | qualification-bound | `product.lua`, `zero_surface.lua`, `release.lua` | 本地零表面通过；最终旅程/zip 待测 | C33；发布前 |
| AR-P0-02 | plan-ready | `runtime.lua`, `model.lua`, AgentLoop fixtures | synthetic trace 通过；fault/cap 进入实现测试 | C26；M8 完成前 |
| AR-P0-03 | qualification-bound | `model.lua`, wire fixtures | synthetic exact bytes；TP-015 录制待做 | C21；M6 完成前 |
| AR-P0-04 | qualification-bound | `platform.lua`, `transport.lua` | TP-003 modern；TP-004/005 target 待做 | C04；目标 adapter 完成前 |
| AR-P0-05 | qualification-bound | `tui.lua`, 40-column transcripts | synthetic chrome/draft 通过；目标终端待测 | C14；M4 完成前 |
| AR-P0-06 | qualification-bound | `tools.lua`, `transport.lua`, Permission fixtures | fold 通过；process/path target 待测 | C25；M7 完成前 |
| AR-P0-07 | qualification-bound | `tools.lua`, `context.lua`, subsystem 19 | TP-008 modern；目标 fault matrix 待做 | C25；M7 完成前 |
| AR-P0-08 | qualification-bound | `formats.lua`, `transport.lua`, data classification | TP-006 scanner/carrier modern；目标 carrier 待测 | C19；M6 完成前 |
| AR-P0-09 | qualification-bound | `config.lua`, `formats.lua`, config fixtures | grammar 通过；目标原子写/caps 待测 | C10；M3 完成前 |
| AR-P0-10 | qualification-bound | `context.lua`, `context.rng`, `formats.lua` | TP-008/010 modern；Windows FS/性能待测 | C17；M5 完成前 |
| AR-P0-11 | qualification-bound | `context.lua`, `formats.lua`, path fixtures | SHA-256/path vectors 通过；target identity 待测 | C16；M5 完成前 |
| AR-P0-12 | plan-ready | `runtime.lua`, `context.lua`, subsystem 12 | view 语义闭合；阈值/长会话测试已排期 | C28；M8 完成前 |
| AR-P0-13 | qualification-bound | `actions.lua`, argv/TUI fixtures | parser/machine contract 通过；目标 argv/TTY 待测 | C12/C14；M4 完成前 |
| AR-P0-14 | qualification-bound | `platform.lua`, `release.lua`, `zero_surface.lua` | allowlist 闭合；TP-029 target 待做 | C04/C31；M10 完成前 |
| AR-P0-15 | qualification-bound | `platform.lua`, `context.lua`, `transport.lua` | TP-008 process-crash modern；目标锁/kill 待测 | C17；M5 完成前 |
| AR-P0-16 | qualification-bound | `product.lua`, `release.lua`, implementation plan | luainstaller 1.3.0 modern；三目标待测 | C32；发布前 |

## 5. P1 明细

| Gate | 计划状态 | 权威输入 | 现有证据 / 待证事实 | 任务与 hard gate |
| --- | --- | --- | --- | --- |
| AR-P1-01 | qualification-bound | `formats.lua`, format fixtures | TP-010 modern；三 ABI load 待测 | C08/C32；M10 完成前 |
| AR-P1-02 | qualification-bound | `transport.lua`, transport fixtures | TP-006 modern；TLS/proxy/CA target 待测 | C19；M6 完成前 |
| AR-P1-03 | qualification-bound | `transport.lua`, `platform.lua` | shell carrier 闭合；进程树 target 待测 | C25；M7 完成前 |
| AR-P1-04 | plan-ready | `runtime.lua`, `release.lua` | cap 维度已定；数字由实现 benchmark 注入 | C26；M8 完成前 |
| AR-P1-05 | plan-ready | `prompts.lua`, prompt fixtures | 原文、层序、controls crosswalk 通过 | C22；M6 完成前 |
| AR-P1-06 | qualification-bound | `context.lua`, `release.lua` | 无 archive 语义闭合；size/latency target 待测 | C18；M5 完成前 |
| AR-P1-07 | plan-ready | `diagnostics.lua`, `actions.lua` | stable error/check registry 通过 | C30；M9 完成前 |
| AR-P1-08 | qualification-bound | `release.lua`, proof backlog | 维度/夹具已定；target calibration 待测 | C32；发布前 |
| AR-P1-09 | plan-ready | `release.lua`, `formats.lua`, all contracts | 稳定名称与 candidate manifest 闭合 | C01；各消费 milestone 前 |
| AR-P1-10 | plan-ready | `context.rng`, `context.lua`, `formats.lua` | 内部 reader/export 验收已排期 | C15；M5 完成前 |
| AR-P1-11 | qualification-bound | `release.lua`, proof manifest | Lua/Expat pins 已定；curl/CA/SBOM 待定 | C31；发布前 |
| AR-P1-12 | plan-ready | public README + current state | “目标/未实现”边界已同步 | C34；发布前再同步 |

## 6. Gate A 通过条件核验

- [x] `DECISION-REGISTER.md` 没有现行 unanswered/conflict。
- [x] P0/P1 28 项全部有唯一 artifact、proof disposition、implementation task 与 hard gate。
- [x] formats/path/wire/Prompt/transport/TUI 边角规格已机器化，无 “choose A or B”。
- [x] TP-003/006/008/010 有可复现 modern evidence，且 manifest 明确 `target_qualification_complete=false`。
- [x] 所有目标依赖事实保留 `proven-target` 义务；失败会阻断对应 milestone 或发布。
- [x] 发行常量未伪造为已校准；candidate 与 release-frozen 状态分离。

## 7. Gate B 通过条件核验

- [x] 28 个规划 Lua 模块各有唯一任务归属。
- [x] `C01..C34` ID 唯一，依赖只指向更早任务，无环。
- [x] 每项任务都有文件边界、测试边界、退出条件和 conventional commit 边界。
- [x] `M0..M10` 顺序固定；遵守 D-002 的串行实施，不铺开并行半成品。
- [x] 首个任务固定为 C01，随后 C02、C03；无需在编码中重新选架构。
- [x] 核心 milestone 完成并自检后提交/推送 `main`；未通过本阶段自检的中间态不推送，目标 hard gate 尚未完成时只可推送诚实标记的纯核心进度。

## 8. Release Gate R 未通过项

以下任一项缺失都保持 R=CLOSED：

1. Win32 x86/XP、Win64 x86_64/Win7+、Linux x86_64/CentOS 7 分别完成原生构建和完整测试。
2. curl/CA、Lua 5.5.1、LuaExpat 1.5.2、Expat 2.8.2、`yaca_native` 的最终来源、hash、ABI、import/dependency closure 通过。
3. 事件泵、console、process tree、TLS/proxy/CA、path identity、lock/replace/power-loss、长 Context 的 target proof 通过。
4. 三个最终 zip 的布局、零表面、干净机旅程、SHA-256、许可证 manifest、SBOM、构建摘要和完整测试摘要齐全。

## 9. 失败路由

- proof 失败但能保持用户保证：在对应 C 任务内更换为更保守、可证明的内部方案，并更新 contract/fixture/proof。
- proof 失败且退路会改变用户保证：停止该 milestone，提交最小 O 决策包；不得私自弱化 XP、取消、单 XML、零表面或安全边界。
- target qualification 失败：Gate R 继续关闭；不得以 modern proof、静态 header 或部分平台通过替代。
