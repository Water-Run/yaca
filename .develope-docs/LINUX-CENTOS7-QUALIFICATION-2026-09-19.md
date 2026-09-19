# CentOS 7 容器资格构建与 C33 工具（2026-09-19 第二轮）

本轮在 `remote`（Rocky Linux 10.2）上以 rootless podman 运行真实
CentOS 7.9.2009 用户态容器，完成 `linux-x86_64` 目标的锁定工具链构建、
全套测试与安装验收；同时落地 C33 的零表面检查器与套件用例。

## linux-x86_64 资格构建（CentOS 7 容器）

构建环境：`centos:7` 容器（Aliyun vault 源安装锁定工具链），宿主内核
6.12（如实记入 build-summary，容器共享宿主内核是该证据的边界）。

- `/etc/centos-release`：CentOS Linux release 7.9.2009 (Core)
- `getconf GNU_LIBC_VERSION`：glibc 2.17
- 编译器：gcc (GCC) 4.8.5 20150623 (Red Hat 4.8.5-44)
- 源输入：`yaca-1772fc6.tar.gz`（`git archive` 于 Linux 生成，
  SHA-256 `ad2c7b1fa9405e39856aa0eec9a9bb38c8be291674b0957f855b9aeb492abf10`；
  Windows 生成的归档会经 autocrlf 转成 CRLF 并被补丁基线校验拒绝，
  已实测确认并以 Linux 侧归档重跑）
- 全部锁定输入（含 luainstaller resources 补丁）SHA-256 校验通过；
  串行构建 Lua/Expat/LuaExpat/yaca_native/native probe/Mbed TLS/curl。

`build-summary.txt`：`status=PASS target=linux-x86_64`，构建器自身的
ELF64/x86-64、系统依赖闭包（仅 libc/libdl/libm/libpthread/librt/
libgcc_s）、glibc 符号基线 ≤2.17 审计全部通过，
`full_tests=575/575`，`release_authorized=false`、
`target_qualification_complete=false`。

| 产物 | SHA-256 |
| --- | --- |
| `yaca`（onefile） | `3a12e840d193f6f25e3db6bed778886573f4e6880875f1279a7b0d22bc1fbc6d` |
| `curl` | `28f2a805cb12b83f65e03349e89d4cc3308013a50d3efefafb370b6b2d1d1491` |
| `yaca_native.so` | `d43abd27807185558d1c9678580fffd66062aa47ac8c20e9b5f59556a5d290ee` |
| `lxp.so` | `ed34e49e9c29d3da5ed3b02903348f72efd8c55eafe788142be670e52921377e` |

`env -i`（空环境、空 HOME/TMPDIR）下 onedir 与 onefile 的
`--version` 冒烟均输出 `yaca 0.1.0 (linux-x86_64)`。

## CentOS 7 安装验收（真实 DeepSeek）

onefile 部署到验收容器 `/opt/yaca/yaca`；私有配置由 win2008 经
base64 管道字节精确传入（用后即删宿主副本）。

| 项目 | 结果 |
| --- | --- |
| `--version` / `--status` | linux-x86_64；config-generation-1，DeepSeek/Std/double-check |
| Stage 1（`podman exec -t` 真实 TTY） | 全部 PASSED，含 TTY-INPUT、CA-BUNDLE、ZERO-SURFACE |
| Stage 2/3（显式同意） | 7/7 PASSED；completed-stage=3、online-requests=10、auto-fixes=0；3 项 advisory WARNING 同既有模式 |
| 文件工具 | `/root/work/VERIFY.txt` = `LINUX_C7_OK` 精确 11 字节无末尾换行（od 核对） |
| Shell | `uname -s -r` exit 0；`Linux 6.12.0-211.49.1.el10_2.x86_64` |
| 审批 | write/shell 两轮 `allow approval-N once` 逐次放行 |
| 保存与恢复 | `.quit` 干净退出后 `--continue AF508DD55FD48B98`；模型基于持久化事实精确复述（文件 digest、raw_size=11、审批编号、uname 输出），未重放任何操作 |

## C33 工具落地

- 新增 `.tools/check_zero_surface.lua`：对解包后的发行树做最小许可面
  验证（manifest 根条目 + 版本化 docs 允许清单 + 禁运组件名 +
  不得随包的 config/`__yaca__`/Context 工件），模块化设计支持注入式
  测试。对真实 win32/win64 包均输出
  `zero-surface=PASS files=15 surface=minimal-allowlist`。
- 新增 `test/release/clean_machine_test.lua`：9 个套件用例覆盖判定表
  （两 Windows 目标与 Linux 的最小树、额外/缺失/重复条目、禁运组件、
  随包配置与数据、Context 工件、未知目标、坏 manifest fail-closed）。
- 完整 suite 升至 **584/584**（575 + 9）。

仍缺的 C33 内容：`test/release/journeys.lua` 干净机旅程驱动与三个最终
zip 的干净机安装/升级/卸载执行——依赖尚不存在的 Linux zip 装配器与
最终合格 zip，未在本轮实现。C34 的 `check_documentation_truth.lua`
同样未实现。

## 边界

- 容器共享宿主内核：文件系统语义、断电持久性与 CentOS 7 原生内核
  （3.10）下的行为仍属 C32 硬门范围，本证据不替代裸机 CentOS 7。
- 三目标现状：win32-x86（Server 2008 实机）、win64-x86_64（Win11
  实机）、linux-x86_64（CentOS 7 容器）各有完整基本可用+在线验收；
  XP SP3 x86、Win7 SP1 x64、裸机 CentOS 7 仍无证据。
  Release Gate R 保持关闭，机读阶段 `implemented-unqualified`。
