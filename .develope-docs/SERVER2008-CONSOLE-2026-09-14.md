# N7 Server 2008 控制台读取修复

日期：2026-09-14。基于 N6 `61cdca2`。用户补充真实旧 Windows 入口后发现并修复
原生 cooked 输入失败；完整 suite **556/556**，validators **7612/56/553**，
TP-003/006/008/010 与 RP-001 PASS。仍为 preview，Release Gate R 关闭。

本轮已按用户要求冻结收尾，最终归档身份及旧机断连导致的未验收范围见
[N7 收尾记录](WINDOWS-PREVIEW-CLOSEOUT-2026-09-14.md)。下面的交互成功记录来自
修复源码的独立运行目录，不应解读为最终 N7 onefile exe 已完成现场验收。

## 真实环境和问题

连接为 `ssh -p 26022 yynicepc@192.168.10.57` 后 `ssh fx6100`；别名实际使用该
Debian 跳板上的 `127.0.0.1:22008`。目标 WMI 返回 Server 2008 Enterprise without
Hyper-V、SP2、64-bit、6.0.6002；Cygwin 为 3.3.4 x86_64，已安装 winpty。
没有在开发本机运行 Windows 程序，也没有改动远端系统 shell 或安装软件。

N6 的最终 exe 能执行 --version，同构建 metadata predicate 检查 PASS；
原生 cmd 中的 Model 向导却在第一次输入报 TerminalPollFailure。独立原生探针
在相同控制台对 ReadConsoleW 预注入 X+Enter 后测得：

| 单次请求 UTF-16 字符数 | 返回 | 错误码 |
| --- | --- | --- |
| 65538 / 32768 | 失败，读取 0 字符 | 8 |
| 16384 / 8192 / 4096 | 成功，读取 X 与 CRLF | 0 |

原实现把应用输入上限 65536 加 2 后直接交给单次 OS 读取。进程端内存分配成功，
并不代表旧 console server 能处理该请求。API 参数以字符计数，参见
[Microsoft ReadConsole 文档](https://learn.microsoft.com/en-us/windows/console/readconsole)。
上表是这台服务器的观测，不声明为所有 Windows 版本的固定阈值。

## 修复与验证

- Windows cooked worker 每次最多请求 4096 个 UTF-16 字符；完整应用缓冲区和
  输入字节上限不变，分段先汇合再严格转 UTF-8，避免切断 surrogate pair。
  短读、EOF、换行完成即返回；失败保留错误状态，超额计数拒绝。
  控制台自身行编辑容量仍受宿主限制，不声称所有宿主都能输入应用上限长度。
- 保留真实 ReadConsoleW 的宿主编辑行为、工作线程与既有 XP 合成 Enter 取消协议，
  没有引入 Vista+ 的同步 I/O 取消 API。raw 隐藏输入路径不变。
- 新增独立 Windows reader fixture，验证跨段 UTF-16/UTF-8、完整块末尾换行不再等第二行、
  短行、EOF、分段后失败及不合法返回计数。它使用可控 console double，
  清楚标为 reader unit；真实控制台由下面的交互记录补充。
- Server 2008 上的修复源码通过中文 Model 名称、隐藏合成 Key、APPLY 首次保存、
  再打开配置编辑器、LogLevel 修改与精确保存、Model 重命名/空目录引用预览/保存。
  原生 Windows publication smoke 通过 create/write/flush/read/rename/verified delete、
  direct read、带元数据复核的替换及 LuaExpat XML 解析。
- 发布构建继续使用 XP API 基线、串行编译、资源 guard 和静态 libgcc；
  `windows_console_reader_smoke.exe` 随独立构建证据输出，不增加产品组件。

完整源码、zip 和最终打包实测以 `out/windows-preview-20260914-n7/` 的 build summary、
SHA256SUMS 和后附远端证据为准。当前详细日志位于 `out/server2008-n6-20260914/`，
前缀保留为 N6 是为了保存原失败与 N7 修复前后的同一条证据链。

## 测试夹具的失败记录

- 远端 `/usr/bin/bash --version` 实际进入 cmd；嵌套 bash 的最初部署脚本未执行。
  改由 SSH 现有 shell 执行脚本后成功，不改系统文件。
- 初次直接 winpty 向导在报错时 SSH 输出被切断；改在 winpty cmd 内运行得到明确
  TerminalPollFailure，不把切断的输出算成功。
- 临时调试 DLL 首编未带静态 libgcc，出现缺模块；按正式 builder 的链接规则修正。
  正式 N6/N7 构建始终使用静态 libgcc。
- Native smoke 的首次脚本参数误用 Cygwin 路径；改为 Windows 绝对路径后通过。
- 继承 ACL fixture 初用旧 PowerShell 不支持的 LiteralPath 参数，改用 .NET File ACL
  方法；其最终结果单独记录，不与产品故障混淆。

## 边界

这证明了当前 Server 2008 上的所列路径，尚不是完整 v0.1 或全部旧系统资格。
Model 在线测试与 Stage 2/3 production adapter、selector 语义复核、C32--C34 仍待完成。
XP SP3、Win7+、CentOS 7 的 hard gate 不能由 Server 2008 smoke 推定通过。
