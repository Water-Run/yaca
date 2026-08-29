# yaca v0.1 全程序实施计划

版本：2026-08-29.1
状态：**计划已确认 / Gate B passed / 产品实现进行中**
首个编码任务：**C01 — 建立测试 harness 与 release manifest**

## 1. 计划边界

本计划只实现 D-001..D-071 已确认的 terminal-only v0.1。Web、media、remote/headless、MCP/plugin、telemetry/upload/update、通用 undo/WAL、multi-root 和 plan-state 均不进入实现。

权威输入按优先级为：

1. [`DECISIONS.md`](DECISIONS.md) 的现行产品保证；
2. [`contracts/`](contracts/README.md) 的 16 份 machine contract 与 12 组 fixtures；
3. [`GATE-AUDIT-2026-08-29.md`](GATE-AUDIT-2026-08-29.md) 的阶段门；
4. 本文的文件、依赖、测试、退出和提交边界；
5. 子系统文档只解释 rationale，不得覆盖上述 machine truth。

实现遵守 D-002：一次只推进一个 task；前项测试通过、提交边界干净后才进入下一项。target-dependent task 可以先写纯核心和 fake adapter，但对应 milestone 的 hard gate 未通过前不得标成完成。Release Gate R 在三目标资格证据齐全前始终关闭。

## 2. 目标文件树

```text
src/
  backend_linux.lua   backend_windows.lua
  cli.lua             clock.lua
  compact.lua         config.lua
  context.lua         diagnostics.lua
  fs.lua              index.lua
  ini.lua             json.lua
  main.lua            model.lua
  network.lua         path.lua
  permission.lua      platform.lua
  process.lua         prompt.lua
  runtime.lua         safety.lua
  session.lua         terminal.lua
  text.lua            tools.lua
  tui.lua             xml.lua

native/
  yaca_native.c       lxp_build.lua

release/
  manifest.lua        luainstaller.lua
  dependencies.lock  evidence/

test/
  run.lua             support/
  self/               unit/
  integration/        fault/
  golden/             reference/
  performance/        qualification/
  release/
```

加载器只接受 `release/manifest.lua` 列出的 28 个 Lua 模块与 `yaca_native`/`lxp` 两个 native 模块；cwd、`LUA_PATH`、`LUA_CPATH`、用户目录和动态 extension discovery 永远不参与查找。

## 3. 里程碑依赖

```text
M0 harness
 ├─ M1 platform/event core
 └─ M2 formats/path
       └─ M3 config/bootstrap
            └─ M4 actions/CLI/TUI
M1 + M2 + M3 ── M5 Context
M1 + M2 + M3 ── M6 network/model/prompt
M5 + M6 ─────── M7 tools/permission/change
M5 + M6 + M7 ─ M8 AgentLoop/compaction
M8 ──────────── M9 diagnostics/self-test
M9 ──────────── M10 packaging/qualification
```

Task dependency 的 machine truth 在 [`contracts/readiness.lua`](contracts/readiness.lua)；校验器要求所有 dependency 只指向更早 `C` ID，避免隐式环。

## 4. M0 — Harness 与 manifest

### C01 测试 harness 与安全加载 manifest

- Files: `test/run.lua`, `test/support/assert.lua`, `release/manifest.lua`, `.tools/check_loader.lua`
- Inputs: `release.lua`, `platform.lua`, `readiness.lua`, `zero_surface.lua`
- Tests: `test/self/harness_test.lua`, `test/self/manifest_test.lua`
- Exit: `bin/lua55 test/run.lua` 能发现/隔离测试并稳定返回；manifest 精确列出 28+2 allowlist、target/dependency/candidate 状态；恶意 cwd 与环境路径不能注入模块；此时不要求任何业务模块可运行。
- Commit: `test: establish harness and release manifest`

M0 完成后推送一个核心节点；若 loader 负向测试未过，不进入 M1/M2。

## 5. M1 — Platform 与事件核心

| Task | Files | Tests 与唯一退出条件 | Commit |
| --- | --- | --- | --- |
| C02 | `src/platform.lua`, `test/support/fake_native.lua`, `.develope-docs/contracts/readiness.lua`, `.develope-docs/IMPLEMENTATION-PLAN.md`, `.develope-docs/subsystems/01-platform-abstraction.md`, `README.md`, `README-zh.md` | `platform_test.lua`；只产生一次 immutable `os/arch/target/supported`，拒绝未知字段/target；业务层不读取 OS version 分支；首次写产品源码时把 phase 切为 `implementing` 并同步计划/公开状态 | `feat: add validated platform identity port` |
| C03 | `src/runtime.lua`, `src/clock.lua` | `event_pump_test.lua` 复用 TP-003 oracle；单 mutable thread、bounded queue、progress 可合并、terminal 不丢、cancel 下一 tick 可见 | `feat: add deterministic runtime event pump` |
| C04 | `src/backend_linux.lua`, `src/backend_windows.lua`, `src/fs.lua`, `src/process.lua`, `src/terminal.lua`, `native/yaca_native.c` | `native_ports_test.lua`, `loader_path_test.lua`；五方法 AsyncPort、独立 stdout/stderr、typed terminal outcome、absolute safe load；目标 adapter 必须完成 TP-004/005/029 后才算 M1 complete | `feat: add narrow native platform adapters` |

M1 hard gate：XP/CentOS wait/console/process 证据若失败，只能换窄 adapter；不得给领域层增加平台分支或弱化取消事实。

## 6. M2 — Formats 与 path

| Task | Files | Tests 与唯一退出条件 | Commit |
| --- | --- | --- | --- |
| C05 | `src/text.lua` | `text_test.lua`；严格 Unicode scalar UTF-8，非法序列拒绝，binary 保留 exact bytes，显示降级不改 canonical bytes | `feat: add strict utf8 and byte carriers` |
| C06 | `src/json.lua` | `json_test.lua`；RFC 8259 strict subset、object/array top-level、duplicate key/BOM/nonfinite/unpaired surrogate 拒绝、canonical writer | `feat: add strict canonical json codec` |
| C07 | `src/ini.lua` | `ini_test.lua`；消费 config fixture，quoted text/escape/duplicate/unknown 规则唯一，semantic writer 与 safe concrete preservation 均通过 | `feat: add strict ini parser and writer` |
| C08 | `src/xml.lua`, `native/lxp_build.lua` | `xml_test.lua`, `lxp_corpus_test.lua`；LuaExpat/Expat pins、DTD/entity hard reject、text/base64 carrier、RNG/reference reader 通过 | `feat: add bounded xml codec` |
| C09 | `src/path.lua` | `path_test.lua`；drive/UNC/POSIX codec、dot escape、case preservation、SHA-256 first-8/network-order/uppercase vectors逐字通过 | `feat: add logical path and context hash codec` |

M2 只冻结正确性实现；最终 ABI 与旧机吞吐数字仍由 C32 target calibration 冻结到 release manifest。

## 7. M3 — Configuration 与 bootstrap

| Task | Files | Tests 与唯一退出条件 | Commit |
| --- | --- | --- | --- |
| C10 | `src/config.lua`, `src/safety.lua` | `config_test.lua`, `config_generation_test.lua`；完整 catalog/default/secret/migration、每 turn immutable generation、无效 reload fail-closed、原子写通过 | `feat: add typed configuration generations` |
| C11 | `src/session.lua`, `src/main.lua` | `bootstrap_test.lua`；help/version/Stage1 管理在坏配置可用；Agent 无有效 Model 时阻断；裸启动不扫 Context；无隐式联网 | `feat: add offline bootstrap lifecycle` |

M3 hard gate：目标文件权限与 replace 语义未通过时不能标记 config writer complete；RuntimeMax 只从 manifest 注入，用户只能收紧。

## 8. M4 — Actions、CLI 与 TUI

| Task | Files | Tests 与唯一退出条件 | Commit |
| --- | --- | --- | --- |
| C12 | `src/cli.lua` | `cli_parser_test.lua`, `test/golden/help`；39 action、别名、`--`、Windows-only slash、显式 `--machine`、JSON/JSONL、exit class 全由 registry 生成 | `feat: generate cli from semantic actions` |
| C13 | `src/tui.lua` | `tui_renderer_test.lua`, `test/golden/tui`；40 列 transcript 逐字通过；ASCII chrome、控制字符 escape、无颜色语义等价、append-only blocks | `feat: add deterministic transcript renderer` |
| C14 | `src/terminal.lua`, `src/tui.lua` | `line_editor_test.lua`, `terminal_transcript_test.lua`；native/raw editor 隐藏→整块输出→原 draft 重绘；cooked 后备不污染 draft；XP/TTY/dumb/SSH 目标 transcript 通过 | `feat: add draft-safe terminal editor` |

非 TTY 不自动切 machine；interactive 只在 stdin+stdout 均为 TTY 且未请求 machine 时启动，stderr 重定向不改变资格。

## 9. M5 — Context storage 与 index

| Task | Files | Tests 与唯一退出条件 | Commit |
| --- | --- | --- | --- |
| C15 | `src/context.lua` | `context_schema_test.lua`, `context_reader_test.lua`；RNG/event schema、missing vs empty、完整事实、export/internal reader roundtrip，零 root/secret 元素 | `feat: add canonical context document model` |
| C16 | `src/index.lua`, `src/path.lua` | `index_test.lua`, `test/golden/resolver`；实时树、增量环、LogicalPath 稳定排序、短名首个可用、hash 唯一/碰撞/scan-incomplete fail-closed | `feat: add deterministic context resolver` |
| C17 | `src/context.lua`, `src/fs.lua` | `context_commit_test.lua`, `context_lock_test.lua`；单 writer、publication mutex、flush/validate/replace、intent 无 result→unknown、无 auto replay；目标 kill/lock/replace matrix 通过 | `feat: add recoverable context publication` |
| C18 | `src/context.lua`, `src/index.lua` | `context_management_test.lua`；rename/rebind/import/delete/repair 的 identity reverify、no-replace、hash 失效、四已知 target 删除语义逐项通过 | `feat: add context lifecycle transactions` |

M5 hard gate：Windows 与 Linux 目标文件系统矩阵、双进程和长 XML benchmark 均通过；证明失败不得引入长期 WAL/backup/trash。

## 10. M6 — Network、Model 与 Prompt

| Task | Files | Tests 与唯一退出条件 | Commit |
| --- | --- | --- | --- |
| C19 | `src/network.lua`, `src/process.lua` | `curl_carrier_test.lua`, `network_target_test.lua`；absolute bundled curl、`--disable` first、secret 仅 anonymous config stdin、body/header private no-replace temp、ambient isolation/canary scan | `feat: add secret-safe curl transport` |
| C20 | `src/network.lua` | `sse_test.lua`, `network_retry_test.lua`；SSE exact rules、same-origin 307/308 controller、首次 canonical event 后零自动 replay、Retry-After/budget/cancel 收口 | `feat: add bounded sse and retry controller` |
| C21 | `src/model.lua` | `test/golden/provider_wire`, `model_adapter_test.lua`；OpenAI/Anthropic synthetic inventory 全通过，TP-015 recorded fixtures 归档，事件/control/finish mapping 唯一 | `feat: add canonical model adapters` |
| C22 | `src/prompt.lua`, `src/model.lua` | `test/golden/prompts`, `control_mapping_test.lua`；七 purpose、六段主层序、quoted review inputs、三个 native controls 与 schema/digest 逐字一致 | `feat: add versioned prompt and control bundles` |

M6 hard gate：bundled target curl/TLS/proxy/CA 与真实 provider wire 通过；任一协议不能无损承载 core registry/control 时，该 Model 不具备 main 资格，不能静默缩水工具集。

## 11. M7 — Tools、Permission 与 change

| Task | Files | Tests 与唯一退出条件 | Commit |
| --- | --- | --- | --- |
| C23 | `src/permission.lua`, `src/safety.lua` | `permission_test.lua`；8 tools×5 capabilities×Std/Readonly、OutsideWorkspace fold、prompt 不授权、approval snapshot/staleness 全通过 | `feat: add permission admission service` |
| C24 | `src/tools.lua`, `src/fs.lua` | `direct_tools_test.lua`, `target_reverify_test.lua`；list/read/search/write/patch/rename/delete exact schema、path identity、reserved tree 与 side-effect 前复核 | `feat: add verified direct tools` |
| C25 | `src/tools.lua`, `src/process.lua`, `src/context.lua` | `exec_tool_test.lua`, `operation_outcome_test.lua`；opaque shell command、closed stdin、minimal/filtered env、bounded dual output、durable intent/result、unknown 不重放 | `feat: add raw exec and durable operations` |

M7 hard gate：目标进程树取消、pipe backpressure、shell dialect、filesystem identity/fault injection 通过；无法证明停止时只能报告 unknown。

## 12. M8 — AgentLoop 与 compaction

| Task | Files | Tests 与唯一退出条件 | Commit |
| --- | --- | --- | --- |
| C26 | `src/runtime.lua` | `test/golden/agentloop`, `agentloop_test.lua`；所有 state/outcome/control、call/result 配对、budget/stuck/cancel/finalization 与 durable 顺序通过 | `feat: connect typed agent loop` |
| C27 | `src/runtime.lua`, `src/session.lua` | `review_queue_side_test.lua`；action/termination reviewer 独立，queue/steer/side 单并发与 next-turn snapshot、ask-user reply 因果唯一 | `feat: add reviews queue and side turns` |
| C28 | `src/compact.lua` | `compact_test.lua`, `long_context_test.lua`；仅重建 model view、不删 XML、atomic groups 不拆、失败保留旧 view、阈值/cap 来自 manifest | `feat: add lossless model-view compaction` |

M8 完成才得到最小端到端 Agent；在此之前 README 仍必须写“未实现”。任何 provider stop/natural-language done 都不能替代 typed control。

## 13. M9 — Diagnostics 与 self-test

| Task | Files | Tests 与唯一退出条件 | Commit |
| --- | --- | --- | --- |
| C29 | `src/diagnostics.lua` | `diagnostics_test.lua`, `test/golden/errors`；stable error ID/ASCII summary/exit class、secret-safe details、stdout/stderr/Context projection，无独立 log | `feat: add stable diagnostics projection` |
| C30 | `src/diagnostics.lua`, `src/main.lua`, `.develope-docs/contracts/readiness.lua`, `.develope-docs/IMPLEMENTATION-PLAN.md`, `README.md`, `README-zh.md` | `self_test_test.lua`；Stage1 offline、Stage2 consent+全部 enabled Model、Stage3 advisory；dependency graph、partial/required semantics 和 no-auto-fix 通过；产品实现闭合时把 phase 切为 `implemented-unqualified` 并同步计划/公开状态，但 Gate R 仍关闭 | `feat: add staged self-test runner` |

## 14. M10 — Packaging 与 qualification

| Task | Files | Tests 与唯一退出条件 | Commit |
| --- | --- | --- | --- |
| C31 | `release/manifest.lua`, `release/luainstaller.lua`, `release/dependencies.lock` | `package_layout_test.lua`, `sbom_test.lua`；luainstaller 1.3.0 pin、最小 allowlist、curl/CA final lock、license/SBOM、无历史 `bin/` 整包复制 | `build: assemble minimal target packages` |
| C32 | `test/qualification/win32.lua`, `test/qualification/win64.lua`, `test/qualification/linux.lua` | `test/qualification/`；三目标各自原生构建、运行、全测试与 target proofs；一平台失败不能被另两平台替代 | `test: qualify all release targets` |
| C33 | `.tools/check_zero_surface.lua`, `test/release/journeys.lua` | `clean_machine_test.lua`, `journeys.lua`；三个最终 zip 在干净机完成安装→配置→新建/恢复→退出→升级→卸载，零排除表面 | `test: prove release journeys and zero surface` |
| C34 | `README.md`, `README-zh.md`, `docs/`, `release/evidence/` | `.tools/check_documentation_truth.lua`；公开声明只描述已通过能力，每包 SHA-256/license/SBOM/build/test summary 齐全 | `docs: publish qualified release evidence` |

C32/C33/C34 全通过后才能把 Release Gate R 从 `closed` 改为 `passed`。修改状态本身必须是独立、可审计的发布提交。

## 15. 首轮编码执行单

开始编码时严格执行：

1. **C01**：先写 harness/manifest 和负向 loader 测试；不填任何业务 skeleton。
2. 运行 `bin/lua55 .tools/validate_design_contracts.lua`、`bin/lua55 .tools/validate_coding_readiness.lua`、`bin/lua55 test/run.lua`。
3. 以 `test: establish harness and release manifest` 单独提交并推送 M0 核心节点。
4. **C02**：只实现 pure platform identity 和 fake-native 注入，不碰真实 Win32/POSIX I/O。
5. **C03**：把 TP-003 的确定性 oracle 转为产品 event-pump 单测，再实现最小核心；不复制 proof 脚本为产品模块。
6. C02/C03 各自保持独立提交；C04 开始前重新跑全量 readiness + product tests。

C02 必须在同一提交把 `contracts/readiness.lua` 的 phase 从 `pre-coding` 切到 `implementing`，并同步本文状态及中英文 README；C30 同理切到 `implemented-unqualified`。校验器按 phase 检查源码 inventory、计划状态与公开状态，因此实施开始后不会被采证时的空 skeleton 条件反向锁死。

这三项结束时应得到“可测试的加载/平台/事件核心”，仍没有网络、文件修改或 Agent 行为。

## 16. 每项 task 的完成定义

每个 `Cxx` 只有同时满足以下条件才可完成：

- contract/fixture 先于或同提交更新，且没有未登记语义；
- unit/golden/fault/integration 中与风险相称的测试先失败后通过；
- 全部已有测试、contract validator、proof-evidence validator 通过；
- `git diff --check` 通过，未混入无关用户变更；
- secret、路径、控制字符、cancel、unknown side-effect、resource cap 有负向用例；
- commit 只覆盖该 task 的 file boundary；需要跨 task 修正时先更新 machine dependency；
- target-bound task 的 hard gate 未通过时明确标成 in-progress，不以 modern result 完成 milestone。

## 17. 核心节点提交与推送

每个 C task 独立 commit；以下 milestone 在全量自检后作为核心节点推送 `main`：

| Push node | 内容 |
| --- | --- |
| M0 | harness + manifest，首次源码写入前置 |
| M1 | platform/event core + target-adapter evidence disposition |
| M2/M3 | formats/path/config/bootstrap 可独立运行 |
| M4 | CLI/TUI contract 完整投影 |
| M5 | Context durability/index/lifecycle |
| M6 | transport/model/prompt |
| M7/M8 | tools/Permission + end-to-end AgentLoop |
| M9 | diagnostics/self-test |
| M10 | 三目标 package qualification + release evidence |

若某 milestone 只完成纯核心、目标 hard gate 仍失败，可推送诚实标记的实现进度，但不得把该 milestone 或 Gate R 标为 passed。
