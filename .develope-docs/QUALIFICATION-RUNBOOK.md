# 发行验收执行手册

更新日期：2026-10-05。适用于当前 clean/std/full 布局，三目标共九包。
当前任务与证据边界见[TRACKING](TRACKING.md)和
[CURRENT-STATE](CURRENT-STATE.md)。旧 9 月候选命令保留在 Git 历史，不再作为执行入口。

本手册使用实际 ZIP 字节，所有结果保持 `qualification=pending`。
按 D-077 使用已有指定环境，不要求重新准备整套旧系统实机/VM 矩阵。
构建、完整测试和容器/VM 均经资源守卫串行运行。

## 1. 开发检查

使用 Python 3.13 及 `.tools/comment_check_requirements.txt` 的固定解析器，执行：

```sh
bash .tools/run_with_resource_guard.sh bin/lua55 test/run.lua
bash .tools/run_coding_readiness.sh
```

若使用隔离环境，把其 `bin/` 放在当前命令的 PATH 前端。完整 readiness 包含全仓注释
检查与反例、装配/发行校验/PTY 回归、四个校验器和 TP-003/006/008/010、RP-001。
人工语义 Review 单独记录，不由结构检查替代。

## 2. 显式包对完整性检查

runtime ZIP 与同名 `-notices.zip` 配对。检查器不解包、不执行工具、不联网。

```sh
bash .tools/run_with_resource_guard.sh python3.13 .tools/qualification/audit_editions.py \
  --pair out/node-r76-20261005/upload/yaca-1.0.0-linux-x86_64-clean.zip \
         out/node-r76-20261005/upload/yaca-1.0.0-linux-x86_64-clean-notices.zip \
  --output out/single-edition-audit.json
```

报告记录 runtime/notices SHA-256、核心 SHA-256、成员数、工具数、源码/构建/测试
摘要及缺项。CRC、成员摘要、版本、来源、模式、路径冲突或 SPDX 不一致时非零退出。
已存在的输出文件不会覆盖。
`tool_payload_gaps` 单列 Git HTTP(S) helper 等载荷缺项，不能用版本号替代闭包检查。

九包汇总用显式矩阵，不扫描目录猜包：

```sh
audit_pairs=()
for target in win32-x86 win64-x86_64 linux-x86_64; do
  for edition in clean std full; do
    stem="out/node-r76-20261005/upload/yaca-1.0.0-$target-$edition"
    audit_pairs+=(--pair "$stem.zip" "$stem-notices.zip")
  done
done
bash .tools/run_with_resource_guard.sh python3.13 .tools/qualification/audit_editions.py \
  "${audit_pairs[@]}" --require-nine --require-evidence --output out/nine-edition-audit.json
```

同平台三档核心不一致、产品版本混用或席位重复均失败。`--require-nine` 只要求九包
完整性矩阵；再加 `--require-evidence` 才要求 C34 文件证据及已检查的工具载荷齐备。缺项时仍留下 JSON
便于 Review，并以非零退出停止验收。两个选项都不会开启 Gate R。

## 3. Linux 三档离线核心旅程

使用 Linux x86_64 宿主，以及可运行候选核心的用户态：

```sh
bin/lua55 test/release/journeys.lua "$PWD" \
  "$PWD/out/node-r76-20261005/upload/yaca-1.0.0-linux-x86_64-full.zip" \
  linux-x86_64 "$PWD/out/journey-scratch" \
  --report "$PWD/out/linux-full-offline-journey.json"
```

Lua 入口会调用资源守卫。也可在匹配用户态中直接以 Python 3 调用
`.tools/qualification/edition_journey.py`，参数相同，外层仍须用资源守卫。
本轮 CentOS 7 容器可用已核对 full 工具包的 Python 3.14 启动开发驱动；这不是
产品运行时依赖。

10 步覆盖包完整性、解包、版本、非 TTY 零写入拒绝、内嵌 Lua、真实 PTY Stage 1、
移除 tools、整体移动、卸载和自有临时目录无残留。Stage 1 的未初始化配置 WARNING
可为 partial；失败项、未完成阶段、在线请求或不匹配的退出码均拒绝。

只删除脚本在 scratch 中新建的唯一临时目录。日志中的“无残留”指该目录，
不扩展为宿主注册表或全部用户目录检查。clean/std/full 分别执行。
输出明确为 `scope=offline-core`，不替代首次配置、模型、恢复、升级及附带工具运行。

## 4. 目标交互与在线旅程

使用已有指定实机、隔离部署目录和此前已授权的配置。现有 TTY 驱动为：

```sh
bash .tools/run_with_resource_guard.sh python3.13 .tools/qualification/agent_terminal_smoke.py \
  <ssh-host> <isolated-directory> <transcript-path> --executable yaca --online
```

Windows 使用 `--executable yaca.exe`。配置不写入仓库；记录实际 Ask、工具审批、取消、
退出和恢复。首次配置及保留数据的升级另按 C33 逐项取证。
离线驱动收到在线选项或 Windows 运行目标会在执行前拒绝，不能以跳过转为通过。
现代 Windows 与 CentOS 7 容器结果各保留宿主/共享内核边界。

## 5. 发布门

C32/C33/C34 与注释语义 Review 都满足后，再评审 Gate R。
逐包 SHA-256、来源/许可证/SPDX、源码/构建/测试、目标旅程必须绑定精确产物。
发布门与 manifest 的状态变更以独立可审计提交处理，不以改标记代替证据。
