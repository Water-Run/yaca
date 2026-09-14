# Context 管理交互实现计划（2026-09-14）

本文件把 [HANDOFF-2026-09-08](HANDOFF-2026-09-08.md) 的只读调查收敛成可执行计划。
所有签名与行号均已对照当前 `main`（`067dce8`）源码核实，未修改任何源码。

## 当前实况

`--context-repl` 不是交互回路。`src/main.lua:4043` 的 `management_service`
对 `context-repl` 只做一次 `observe_context_catalog` + `context_catalog_page`，
返回 `catalog-ready` / `scan-incomplete` 行集后即结束；
`default_runtime_dispatch`（`src/main.lua:9518`）只为 `model-repl` 与
`config-repl` 分派交互回路，**没有 `context-repl` 分支**，
因此 `src/cli.lua:1752` 的 `parse_context_repl` 目前没有任何生产调用方。

注册表侧已完备：`src/cli.lua:305-375` 已声明 10 个 `context-repl` 面语义动作
（list / inspect / search / rename / rebind / delete /
set-auto-rename-disabled / import / repair / refresh）。
另有 `export-context`（`src/cli.lua:160`，`both` 面）与
`select-context`（`src/cli.lua:255`，`chat` 面）把各自的投影也挂在
`context-repl-line` 上，故该行类共 12 个投影，回路解析须全部接住。
`confirm` 类别与 `results` 取值均已就位，无需新增注册条目。

## 分节点切分

该节点一次做完风险过高（5 条边界、5 类写事务）。按下列顺序分三次推进，
每个子节点各自走定向 suite → 完整 suite → coding readiness：

1. **N1 只读回路**：`help` / `list [recent|full]` / `inspect <selector>` /
   `search <query>` / `refresh` / `quit`。覆盖边界 1。
2. **N2 就地元数据写**：`rename`、`set-auto-rename-disabled`、`delete`。
   覆盖边界 2（真实 ModelView）与 5 的事务纪律，不含跨 workspace。
3. **N3 跨界写**：`rebind`、`import`、`repair`。覆盖边界 3、4、5。

## N1 实现要点

新增 `M.run_context_repl(composed, runtime)`，置于 `M.run_config_repl`
（`src/main.lua:9113`）之后，形状对齐 `run_config_repl`：
端口完整性校验 → `input` → `result()` → `while true` 读取回路。
在 `default_runtime_dispatch` 的 `config-repl` 分支后加入
`request.id == "context-repl" and result.state == "catalog-ready"` 分支。

可直接复用：

| 用途 | 复用点 |
| --- | --- |
| 行解析 | `runtime.cli.parse_context_repl(source, facts)`（`src/cli.lua:1752`） |
| 帮助 | `runtime.cli.render_help("context-repl")`（`src/cli.lua:1364`） |
| 目录快照 | `observe_context_catalog`（`src/main.lua:3426`） |
| 分页投影 | `context_catalog_page`（`management_service` 已在用） |
| 选择器解析 | `context_services.catalog.resolve(selector, origin_logical)`（`src/index.lua:469`） |
| 目标捕获 | `context_services.catalog.capture_target(candidate)`（`src/index.lua:580`） |
| 目标复核 | `context_services.catalog.verify_target(selection, purpose)`（`src/index.lua:608`） |

边界 1 的落地顺序固定为
`resolve` → `capture_target` → `verify_target(selection, "open")` → 读取，
不得由 `list` 显示行重建目标；`verify_target` 逐字段比对
logical/physical/display/canonical/created/updated/header_state 与
`observed_stat`，identity 变化返回 `TargetChanged`，直接映射为
`inspect` 的 `target-changed` 结果，不重扫替身。
`header_state` 指示活动 writer 时走 `busy-metadata-only`，
只输出候选元数据，不得打开 Context 正文。

## 接入前必须先修的阻塞项

`new_model_setup_input`（`src/main.lua:8522`）用
`label == "Configuration"` 二选一推导 `cancel_code`，
其余标签一律落到 `ModelSetupCancelled`。Context 回路若直接复用该 helper，
Esc 取消会报出 model setup 的错误码，属于错误归因。
N1 开工第一步是把 `cancel_code` 改为按标签显式映射
（新增 `Context` → `ContextReplCancelled`），再实现回路。

## 验证

定向 suite 为 `test/fault/context_management_test.lua`（650 行，已存在，
覆盖底层事务而非入口）。N1 需在其旁新增入口级用例。
一律经 `.tools/run_with_resource_guard.sh` 串行执行，不复用暂停前资源数字。
