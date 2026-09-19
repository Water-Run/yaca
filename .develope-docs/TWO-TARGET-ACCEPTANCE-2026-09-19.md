# 两测试系统安装验收与 Win64 构建路径（2026-09-19）

本轮从 `36abd51` 干净检出出发，在 Linux 构建机（el10，MinGW i686/x86_64
交叉工具链）重建全部锁定源码缓存，复现平台无关基线，新增
`win64-x86_64` 候选构建路径，并把两个包分别安装到用户指定的两台
测试系统做真实验收：

- **win2008**（Windows Server 2008 非 R2 x64，6.0.6003，Cygwin sshd）
  ← `win32-x86` 包（XP 5.01 基线，沿用既有闭包）。
- **evader-admin**（Windows 11 x64，10.0.26100.33438，PowerShell 7 默认
  shell 的 OpenSSH）← 新 `win64-x86_64` 包（Win7 SP1 6.1 基线）。

两台机器均使用真实 DeepSeek（openai-chat / deepseek-flash / 流式）完成
在线验收。凭据经授权位置与私有管道传输，未进入源码、包、日志或本文；
win2008 沿用既有授权配置，evader-admin 的配置由 win2008 经 base64
字节精确管道传入（SHA-256 一致核对）。

本页是首版基本可用与两台真实机器的验收记录。C32 的 XP SP3 x86、
Win7 SP1 x64、CentOS 7 x64 完整资格仍未执行：Win11 不等于 Win7 SP1，
机读阶段保持 `implemented-unqualified`，Release Gate R 关闭。

## 构建环境重建

原 Linux 开发机不可达，在 `remote`（el10）从零搭建：仓库克隆、
`bin/lua55` 由锁定的 lua-5.5.1 源码构建、7 个锁定输入逐一 SHA-256
验证。GitHub 直连不稳定，源码经本地中转；`luainstaller-97192d1.tar.gz`
的 GitHub 自动归档与锁不一致（归档方式差异），改从 win2008 保留的
N7 源码包内 `dependencies/` 提取原始字节，SHA-256 与锁精确一致。

基线复现（构建机、`36abd51` + 本轮构建脚本变更）：

| 项目 | 结果 |
| --- | --- |
| 完整 Lua suite | `SUMMARY total=575 passed=575 failed=0`（最终脚本复核第二次通过） |
| design-contract | 7612 条断言 PASS（xmllint 在 PATH） |
| proof-evidence | 56 条 PASS |
| coding-readiness | 553 条 PASS，Gate A/B passed，Gate R closed |
| TP-003 / TP-006 / TP-008 / TP-010 | 全部 PASS（TP-010 5,564,743 断言，锁定缓存重建） |
| RP-001 | PASS（luainstaller 仓库经 git bundle 传入，`../luainstaller` 覆盖） |

## 新增 win64-x86_64 构建路径

新文件：`.tools/qualification/build_win64_candidate.sh`、
`build_win64_https_candidate.sh`、`windows_package_win64.py`。
与 win32 路径的差异严格限定为：

- 工具链 `x86_64-w64-mingw32-*`；`_WIN32_WINNT=0x0601`；
  PE subsystem 6.1（依赖锁 `target_policy["win64-x86_64"]` 的既定定义）。
- curl/mbedtls 使用同一锁定源码**不打 winxp 下游补丁**（锁中该补丁
  只绑定 `win32-x86`）；熵源回到上游 BCryptGenRandom。
- 审计预期：`pei-x86-64`、subsystem 6/1、DLL 闭包
  {ADVAPI32, KERNEL32, WS2_32, bcrypt, msvcrt}，禁 api-ms-win-crt/ucrtbase。

真实构建发现并修复的三个问题（均为构建驱动层，不动产品源码）：

1. **上游 curl configure 的 mbedtls 探测在 Windows 目标缺 `-lbcrypt`**，
   未打补丁的 64 位熵源在探测链接期即失败。修复：configure 环境
   `LIBS=-lbcrypt`（autoconf 标准初始 LIBS 用法）。
2. 64 位 `msvcrt.dll` 自带完整 secure-CRT 面（`wcstombs_s` 按序数导入），
   win32 的 `_s` 禁令语义是"XP msvcrt 无此导出"，win64 审计相应收窄为
   仅禁未捆绑 CRT（api-ms-win-crt/ucrtbase），DLL 闭包检查保持硬保证。
3. `windows_console_reader_smoke.c` 固定 `0x0501` 与命令行 `0x0601`
   重定义冲突：改为 `#ifndef` 可覆盖默认，win64 构建以 6.1 基线编译
   同一 fixture。

同时把 `build_win32_xp_https_candidate.sh` 的 `file(1)` 文本匹配放宽到
file-5.45 的措辞（objdump 的 subsystem 字段始终是权威检查，win32 审计
实质不变），`windows_native_smoke.lua` 的架构断言改为显式参数
（默认 `x86`，win64 传 `x86_64`）。

## 交付产物（均含 SHA256SUMS、SBOM、导入审计、可重建源码包）

| 产物 | SHA-256 |
| --- | --- |
| `yaca-0.1.0-preview-win32-x86.zip` | `ea30c9bd616748bb23de3f3707ab01d41ea0376c24bf36295916d9285484877b` |
| win32 `yaca.exe` | `b19ed493273dedd34e7652f1e95b2bcc5632d34cffd6e83f458649126a1a9bea` |
| `yaca-0.1.0-preview-win64-x86_64.zip` | `8cb79d67a1364240b67bd582bfd1eed8413cb1c44c77f39a6a73d5a3e3159849` |
| win64 `yaca.exe` | `08d78074eb08dd6b4463777dcf566431915e63a9d154a01a948b2ba6288d3ce2` |

构建基线 `36abd51` + 本轮提交的构建脚本变更；两次构建记录的
`source-changes.patch` 与该提交的构建脚本差异一致（win32 包构建时
console-reader fixture 修复尚未落盘，其后 win64 包包含全部变更）。
编译器均为 `*-w64-mingw32-gcc (GCC) 15.1.1 (Fedora MinGW)`。
win64 HTTPS 候选 `status=PASS`：TLS1.2+、HTTP/HTTPS、standalone
no-option 语法、BCrypt 熵、subsystem 6.1。

## win2008（win32-x86 包）验收

安装目录 `C:\Users\Administrator\yaca-0.1.0-preview-n14`（zip 解压，
传输前后 SHA-256 一致）；私有配置由既有 n13 目录服务器内复制。

| 项目 | 结果 |
| --- | --- |
| `--version` | `yaca 0.1.0 (win32-x86)` |
| `--status` | config-generation-1；DeepSeek / Std / double-check；agent ready |
| Stage 1（winpty 真实控制台） | 15/15 PASSED，含 TTY-INPUT；outcome=passed online-requests=0 |
| Stage 2（显式同意，非 TTY） | 7/7 PASSED；outcome=passed completed-stage=2 online-requests=7 |
| Stage 3 | outcome=passed completed-stage=3 online-requests=10 auto-fixes=0；3 项 advisory WARNING（非 TTY 的 TTY-INPUT、供应商 JSON 形状、命名建议），与 N10/N11 模式一致 |
| 文件工具 | `VERIFY.txt` = `BASIC_N14_OK` 精确 12 字节无末尾换行（od 核对）；读取复述正确 |
| Shell | `ver` exit 0、子进程停止证明；报告 6.0.6003 |
| 审批 | write/shell 均 AwaitingApproval → `allow approval-N once` 逐次放行 |
| 保存与恢复 | 干净退出（`.quit`）后 `--continue 39C840722C42EFD9` 恢复；模型精确复述历史（"你要求我只回复 RESTORE_READY"）；hash 前后一致 |
| 异常终止观察 | 进程被强杀的 Context 留下 `.yaca-lock`，`--continue` 保守返回 `MatchedUnavailable`（符合设计：有效锁即拒绝，不做 PID 存活推测） |

供应商行为波动如实保留：deepseek-flash 多次出现 yielded-without-finish、
终审 uncertain（一次需澄清后通过）、以及一轮 24 次连续工具请求；界面均
按契约显示状态，未伪造完成。

## evader-admin / Windows 11（win64-x86_64 包）验收

安装目录 `C:\Users\Administrator\yaca-0.1.0-preview-n14`（`scp -O` +
`Expand-Archive`，zip 哈希传输前后一致）。PowerShell 7 默认 shell 下，
交互控制台由 `ssh -tt` + ConPTY 提供（发现并规避：PS7 登录 shell 在
stdin EOF 时立即退出并终止子进程，需保持 stdin 打开）。

| 项目 | 结果 |
| --- | --- |
| `--version` | `yaca 0.1.0 (win64-x86_64)` |
| `--status` | config-generation-1；DeepSeek / Std / double-check；agent ready |
| Stage 1（非 TTY） | 14 项 PASSED + TTY-INPUT WARNING（非交互运行的预期项）；outcome=passed |
| Stage 2 | 7/7 PASSED（transport/auth/wire/stream/tools/control/cancel） |
| Stage 3 | outcome=passed completed-stage=3 online-requests=10 auto-fixes=0；同型 advisory WARNING |
| 文件工具 | `VERIFY.txt` = `WIN64_N14_OK` 精确 12 字节；读取复述正确 |
| Shell | `ver` exit 0、子进程停止证明；版本 10.0.26100.33438；GBK 字节按契约以 base64 保留 |
| 审批 | write/read/shell 三次 approval 逐次放行；一次 `mode:create` 遇已存在文件正确报错（no-replace 纪律）后由后续旅程干净重做 |
| 保存与恢复 | 干净退出后 `--continue 902A9A3872BA89EB`；模型精确复述"请只回复 RESTORE_OK"；hash 一致；再次干净退出 |

这是 Win64 包首次在真实 64 位 Windows 上完成完整基本可用旅程；
此前仅有的 Windows 实机证据全部来自 32 位包。

## 边界

- Win11 证据不能外推 Win7 SP1（C32 的 Win64 硬门）；XP SP3 x86 与
  CentOS 7 x64 目标仍无任何实机证据。
- 两台机器的非 TTY Stage 1 差异（TTY-INPUT WARNING）由运行方式决定，
  winpty 真实控制台路径已在 win2008 证明 15/15。
- 交互旅程由 expect 式脚本驱动（本地管道 + `ssh -tt`），每步输入按
  界面状态触发；完整原始会话日志在本地 `out/acceptance/`（忽略提交）。
- 本轮未运行 `--model-repl` 管理器联网 TEST（Stage 2 已覆盖等价的
  真实连接面）。
