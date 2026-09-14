# Context 管理交互实现计划（2026-09-14）

**检查点更新：N1/N2、N3a rebind、N3b import、N3c repair 已完成；完整 suite 520/520 和 coding-readiness 通过。下一项管理器导出/继续与跨 workspace 确认。**
见 [N3c 检查点](CONTEXT-REPAIR-2026-09-14.md)。下文保留实施前调查。

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

## 阻塞项状态

**已修复（`7a34715`）**：`new_model_setup_input` 原先用
`label == "Configuration"` 二选一推导 `cancel_code`，其余标签一律落到
`ModelSetupCancelled`；Context 回路复用该 helper 会把 Esc 取消误报成
model setup 的错误码。现已改为显式 `SETUP_INPUT_CANCEL_CODES` 映射并对
未注册标签 fail closed，`Context` → `ContextReplCancelled` 已登记，
两处调用点均已传播错误。N1 可直接以 `"Context"` 标签复用该 helper。

**测试入口缺口（已实测缩小）**：`src/main.lua:9590` 已有
`if MODULE_NAME == nil and _G.YACA_TEST_ROOT == nil then os.exit(...)` 守卫，
即 main.lua **本就可在测试环境按普通模块加载**。实测（设置 `YACA_TEST_ROOT`
后按现有 `load_module` 模式加载）导出 10 个函数，其中已含
`run_config_repl`、`run_model_repl`、`run_interactive_chat`、`compose_runtime`。
因此 `M.run_context_repl` 一旦加入即可被 suite 直接调用，**无需新建加载器**。

仍缺的只是端口替身：`composed`（`config` 服务、`layout.config_path`、
`backend.new_terminal` / `clock_port.monotonic_now` / `clock_port.sleep_ms` /
`system.secure_random`）与 `runtime`（`cli.parse_context_repl`、
`cli.render_help`、`stdout`）。终端替身须满足
`poll` / `cancel` / `join` / `restore` 事件契约（见 `src/terminal.lua`
与 `src/main.lua:7817` 起的用法），事件形如
`{kind="user_action", action="text"|"cancel"|"eof", text=...}` 与
`{kind="io_terminal"}`。
N1 的第一项工作是写这组替身，可先用 `run_config_repl` 作参照面校准，
该夹具同时是 N2/N3 的前置。

注意 `new_model_setup_input` 仍是 main.lua 的局部函数，只能经
`run_*_repl` 间接覆盖，不要为测试把它导出。

## 验证

定向 suite 为 `test/fault/context_management_test.lua`（650 行，已存在，
覆盖底层事务而非入口）。N1 需在其旁新增入口级用例。
一律经 `.tools/run_with_resource_guard.sh` 串行执行，不复用暂停前资源数字。
