# Windows 首个可用预览检查点

日期：2026-09-14。部署方向：Windows Server 2008（非 R2），统一使用 XP SP3
API 基线的 win32-x86 便携包。正式三目标资格仍未完成，Release Gate R 保持关闭。

## 交付与复现

- 构建入口：`.tools/qualification/build_windows_candidate.sh`，使用
  `out/qualification/sources` 的锁定归档，输出必须为新目录。
- 最终输出目录：`out/windows-preview-20260914-final`。
- 产物：`yaca-0.1.0-preview-win32-x86.zip`、对应 `-source.tar.gz`、
  `SHA256SUMS.txt`。zip 包含单文件程序、CMD PATH helper、许可证、SBOM 和首次使用说明。
- 完整源码包包含当前项目快照、上游源码归档、实际使用的 luainstaller 源码及生成的
  launcher/extractor/payload，允许重新构建和重新链接。导入与组件哈希见 `logs/`
  和 `package/docs/build-summary.json`。
- 本次为 MinGW i686 cross-build；按 PE32/Subsystem 5.01 审计导入，禁止 UCRT、
  BCrypt 和已列出的 Vista+ 静态导入。静态审计不能证明整个 XP API/CRT 行为闭包。

## 修复的实际阻塞

1. 模型配置向导补齐 ContextLength / MaxOutputTokens，校验范围并保留原有值；
   避免保存成功后第一次请求因缺失容量信息失败。
2. 首次发布后重新取得 Context hash，再组合活动端口；失败若已关闭草稿，则关闭
   交互会话并恢复终端，避免留在无法继续的草稿状态。
3. 继续已有会话时使用已保存的 Model owner，不再要求只存在于未保存草稿的 update。
4. Windows 目录 flush 以读写访问打开句柄，符合 FlushFileBuffers 访问要求。
5. Windows direct read 在流元数据检查后将句柄重置到文件起点；BackupRead / BackupSeek
   曾把句柄留在 EOF，导致刚创建的普通文件校验失败。
6. 空 argv 转换为合法空 UTF-16 字符串；最小子进程环境使用系统 API 补入 SystemRoot，
   使 Winsock/curl 初始化正常，同时继续排除环境中的代理、CA 和凭据变量。
7. onefile 外层 Job 允许显式 breakaway，native 在允许时创建可进入独立 Job 的挂起
   子进程；用于 XP--Win7 单 Job 限制，仍需旧系统实测。Windows native 搜索模板使用 DLL。

## 验证范围

平台无关 suite 为 **491/491**。回归覆盖首消息发布身份、已关闭草稿的失败退出、
配置向导容量、继续会话的 Model owner 以及终端失败时释放 writer。
完整 coding readiness、TP-003/006/008/010 与 RP-001 的结果另保存在构建证据目录。

用户指定远端通过 SSH 26222 测试。该机实际是 **Windows Server 2025 Standard
10.0.26100.33438 x64**，PowerShell 7.6.6，x86 包通过 WOW64 运行；它不是 Server 2008。
遵照用户要求，Windows 运行测试在远端执行，不使用本机 Wine 作为验收。

远端隔离目录为 `C:\Users\Administrator\yaca-preview-20260914-01`。测试已覆盖：

- 单文件启动、版本/帮助、实际离线配置向导、XML native 模块和文件发布原语。
- 空参数的原生组件进程，以及无凭据的真实 HTTPS 请求；匿名 curl carrier 使用随包 CA。
- 真实终端输入、SSE 回合、列目录、审批创建 hello.txt、读取实际文件、审批执行
  `echo REMOTE-SHELL-OK`、保存操作结果、正常结束、退出、精确 hash 重开和再次完成回合。
- 完整工具回合 Context hash：`40365FD6E1A97195`；重开的下一请求包含原工具结果、
  实际 Shell 输出和结束摘要，证据在 `out/windows-remote-evidence-20260914/`。

模型服务是仓库脚本提供的 **loopback 合成响应**，无 API key、无真实模型计费；该测试
不代表实际服务商的端到端兼容性。测试配置为 128000/4096 token，`.cautious off`，
Std 写入与 Shell 审批仍正常生效。32768 窗口在四项工具后触发保守压缩门禁；因此
首次使用说明要求按服务商实际容量填写，不把大容量当成服务商保证。

## 尚未验收

- 真实 XP SP3 / Server 2008、Win7 x64、CentOS 7 及其代理/证书/故障矩阵。
- 旧系统非 ASCII 路径、断电/设备持久性、完整进程树与旧 Job 行为。
- 真实模型服务商的 main/review/compaction 请求。
- Stage 1 的 ST1-ATOMIC-WRITE 固定 unknown；在线 self-test Stage 2/3 仍未接通。
- Context 管理器写事务及跨工作目录继续的确认流程；N2/N3 后续另行推进。

用户部署步骤见 [Windows 首次使用](../release/WINDOWS-QUICKSTART.md)。此预览包仅供
初步实际使用和继续验收，不能把这里的远端烟测写成正式三目标发行资格。
