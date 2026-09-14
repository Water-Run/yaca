# Windows 首次使用

本次便携预览包是 `win32-x86`，按 Windows XP SP3 API 基线构建，部署目标为
Windows Server 2008（非 R2）。程序、Lua 5.5、XML 解析器、HTTPS 客户端和 CA
均随包提供，不需要在服务器安装 Lua、Python、Node.js 或开发工具。
真实 XP / Server 2008 验收尚未完成；现代 Windows 上的测试不能替代旧系统验收。

## 解压与配置

1. 将完整 zip 解压到有写权限的本地目录，首轮建议 `C:\yaca`。工作目录和临时
   目录也先使用短的英文路径；旧系统非 ASCII 路径仍需单独验收。
2. 打开普通 `cmd.exe`，运行 `C:\yaca\yaca.exe --version`。
3. 运行 `C:\yaca\yaca.exe --model-repl`，按提示依次填写：

   - Model name：直接回车使用 `Primary`。
   - Protocol：`openai-chat` 或 `anthropic-messages`。
   - Enable：`yes`。
   - Endpoint：服务商的**完整请求 URL**，包含 API 路径；不能只填域名。
   - Remote model：服务商给出的模型 ID，需要支持原生工具调用。
   - Context length / Maximum output tokens：按服务商支持的范围填写；默认预算
     分别为 `32768` / `4096`。若模型支持 128K 窗口，可填写 `128000` / `4096`；
     当前保守预算会使小窗口较早触发压缩，不要超过模型的实际限制。
   - Key：API key，输入隐藏。没有 key 的本地服务可留空。
   - 最后输入 `APPLY` 保存。

配置器离线工作，保存本身不会测试网络或消耗 API 额度。不要向普通聊天输入 API key。
配置在 `C:\yaca\__yaca__\config.ini`，以后可重新运行 `--model-repl` 修改模型。
配置字段编辑使用 `--config-repl`。如需代理，在 `[Network]` 中配置 `ProxyUrl`；
证书检查默认使用随包 CA，不要通过关闭证书校验解决连接错误。

## 开始使用与服务器验收

先选择一个普通、可写、可丢弃的测试工作目录，例如 `C:\work\yaca-test`：

```bat
mkdir C:\work\yaca-test
C:\yaca\yaca.exe --self-test --through-stage 1
C:\yaca\yaca.exe C:\work\yaca-test
```

Stage 1 中的 `ST1-ATOMIC-WRITE` 目前固定报告 `unknown`（旧系统资格待验收），
因此总结果可能返回非零退出码；这不是一项已通过的断电持久性证明。其他检查项
应逐项核对，实际创建和恢复会话另按下面步骤验证。

在交互界面依次确认：

1. 输入“只回复 OK”，收到真实模型回复，证明配置和 HTTPS 链路可用。
2. 请求列出当前目录、创建 `hello.txt`、读取它；写操作出现确认时核对内容并确认。
3. 输入 `.status`，记下 Context hash；输入 `.quit` 退出。
4. `cd /d C:\work\yaca-test` 后运行 `C:\yaca\yaca.exe --continue <hash>`，
   检查历史并再发一条消息，确认保存与重开。
5. 请求执行 `ver`，核对 Shell 确认提示、命令输出和退出结果。

请记录服务器的 `ver`、32/64 位、文件系统、上述结果及出现的错误编号；这些是
本机验收依据。`.details` 可以查看当前进程最近的清理后诊断。

可用 `.help` 查看聊天命令，`--help` 查看命令行说明。在线 self-test Stage 2/3
尚未接通，首次网络验证使用上面的真实聊天。Context 管理器提供列表、检查、搜索，以及 `rename <selector> <new-name>`、
`set-auto-rename-disabled <selector> <true|false>`、`delete <selector> [--yes]`。
删除需要精确 hash 确认，且没有撤销。跨工作目录继续、导入、rebind 和修复仍待完成。

## 数据、升级和退出

数据始终放在实际 `yaca.exe` 旁边的 `__yaca__`，不随工作目录变化。
升级前退出所有 yaca 进程，另行备份 `__yaca__`，再解压替换程序；不要删除数据目录。
首版没有自动更新和通用撤销。出现保存结果 unknown 时先停止操作并保留现场，不要
反复重试有副作用的请求。

`Install.cmd` 可从当前 CMD 窗口运行，只把解压目录加入这个窗口的 `PATH`，
不需要管理员权限。也可以始终使用上面的完整路径调用。

## 开发机复现

在具备 MinGW i686、Lua 5.5、Python 3 及仓库现有构建依赖的 Linux 开发机运行：

```sh
bash .tools/qualification/build_windows_candidate.sh \
  out/qualification/sources out/windows-preview
```

输入源码缓存逐个校验锁定 SHA-256；所有编译串行执行并经过内存门禁。输出包含
Windows zip、对应源码包、SHA256SUMS 和导入审计。构建成功不会打开正式 Release Gate R。
