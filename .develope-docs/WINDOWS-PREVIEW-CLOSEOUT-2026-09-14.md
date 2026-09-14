# N7 Windows 预览收尾

2026-09-14，按用户“快速收尾，搞定后推送一次”的要求冻结当前预览检查点。
不再扩展本轮功能；正式 v0.1 与 Release Gate R 的未完成项继续保留。

## 构建与交付

运行时代码提交为 `219e8514e5cf775bfc2084d94d07be41e3e3e4aa`。
此后的收尾提交只补充文档，不改变 N7 包内源码；没有把文档提交冒充构建来源。
构建目录为 `out/windows-preview-20260914-n7/`，source-changes.patch 为 0 字节。

| 产物 | SHA-256 |
| --- | --- |
| yaca-0.1.0-preview-win32-x86.zip | `9592730e18c85aabcd1886665f5906eedbb2c5644e433c1e4d6622293bb140fc` |
| yaca-0.1.0-preview-win32-x86-source.tar.gz | `4de70137343d8e178a04f897a356533cb606902ac46a71a9d64e1874f54acb79` |

源码快照 SHA-256：`76b18fecd7258958334eb783e40932800974068fd468f809fad8c1de1ea949a4`。
收尾时重新核对两个归档的 SHA-256；zip 共 15 项，不含用户数据目录。
产物和原始测试日志留在本地 out 目录，不提交二进制、测试配置或控制台原始记录。

两个归档及最终构建的 reader/metadata smoke exe 已经通过 Debian 跳板上传至
旧服务器 `C:\Users\Administrator\yaca-n7-transfer-20260914`，上传命令退出 0。
随后旧机连接断开；重连两次均在跳板 `127.0.0.1:22008` 的 SSH banner exchange
超时。因此**没有完成远端重新计算哈希、最终包解压和最终 exe 交互验收**，也没有
创建或宣称已创建可直接使用的 `yaca-0.1.0-preview-n7` 安装目录。
此前 N6 目录仍包含已知的旧控制台输入问题，不能当作最新版本交付。

部署时使用上表 N7 zip，按 [Windows 首次使用](../release/WINDOWS-QUICKSTART.md)
解压和配置。源码包与 zip 对应，可用于重建；本次不创建正式发行标签。

## 已完成的验证

- 平台无关完整 suite：556/556；validators：7612/56/553；
  TP-003/006/008/010、RP-001 均 PASS，交叉构建成功。
- 真实 Server 2008 SP2 非 R2 x64 上，N7 修复源码的独立运行目录通过中文首次设置、
  隐藏合成 Key、配置保存及 Model 重命名；控制台记录未出现合成 Key 原文。
- 同一旧机的原生文件发布、XML、legacy metadata replacement 与 inherited ACL
  replacement smoke PASS；reader 的可控 console double 单元检查 PASS。
- 随包相同版本的 curl/CA 在旧机实际访问公开 HTTPS，返回 HTTP 200。
  该检查没有 API key，不涉及实际模型请求。

上述源码运行与辅助程序检查不等同于最终 onefile exe 验收。
完整前后对照见 [Server 2008 控制台修复记录](SERVER2008-CONSOLE-2026-09-14.md)。
原始证据位于 `out/server2008-n6-20260914/`；N7 构建下的 remote-evidence
保留选定日志、产物身份和连接失败记录。准备的旧机 loopback Agent fixture 没有运行，
不能记为成功；此前 Server 2025 上的完整合成 Agent 回合是另一平台的证据。

## 下一次继续

1. 旧机 SSH 恢复后，核对上传文件哈希，在全新目录解压 N7，完成最终 exe 的首次设置、
   保存、重新打开及完整 Agent 工具回合，再验证退出与历史继续。
2. 接通 Model 联网测试、在线 self-test Stage 2/3 production adapter，完成资源
   selector 语义复核。
3. 完成 XP SP3、Win7+、CentOS 7 与 C32--C34 的完整目标资格。XP API 构建基线、
   Server 2008 的局部 smoke 均不能替代真实 XP 验收。

Windows 执行测试始终仅在用户指定远端进行，没有在开发本机运行 Windows 程序。
