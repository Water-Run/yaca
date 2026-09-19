# Windows 首次使用

本次便携预览包是 `win32-x86`，按 Windows XP SP3 API 基线构建，部署目标为
Windows Server 2008（非 R2）。程序、Lua 5.5、XML 解析器、HTTPS 客户端和 CA
均随包提供，不需要在服务器安装 Lua、Python、Node.js 或开发工具。
N7 已针对 Server 2008 SP2 非 R2 x64 的实际控制台修复首次输入失败，
并验证中文配置、隐藏 Key 和配置事务。资格按 D-072（2026-09-19）于三个实测环境通过；真实 XP 验收属后续增强。

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
已有有效配置时，`--model-repl` 进入管理列表：`add` 新增，`show <row-id>` 查看，
`set <row-id> <key>` 编辑，`rename` / `delete` / `move` 管理名称、删除和顺序。
行号形如 `model-edit-1:1`，每次编辑后用 `list` 获取新行号；`preview` 查看变更和
受影响 Context，再按提示输入 `save model-edit-N` 保存。保存后重新进入管理器，运行
`test model-edit-1:1`，核对服务地址及费用范围，再输入 `TEST model-edit-1:1` 进行
连接测试。结果仅针对本次配置；修改或重载后清除。未保存草稿不能联网测试。
首次向导及 `add` 支持 `.back` 返回上一项；取消不保存。
其他配置字段和已有 Permission 的编辑使用 `--config-repl`。如需代理，在 `[Network]` 中配置 `ProxyUrl`；
证书检查默认使用随包 CA，不要通过关闭证书校验解决连接错误。

## 开始使用与服务器验收

先选择一个普通、可写、可丢弃的测试工作目录，例如 `C:\work\yaca-test`：

```bat
mkdir C:\work\yaca-test
C:\yaca\yaca.exe --self-test --through-stage 1
C:\yaca\yaca.exe C:\work\yaca-test
```

Stage 1 的 `ST1-ATOMIC-WRITE` 使用独立随机临时文件，实际验证创建、刷新、
无覆盖重命名、替换、读取和清理。通过表示本次文件系统操作成功，不是断电
持久性或所有旧系统的资格证明；失败或清理结果不确定会阻止后续在线阶段。

在交互界面依次确认：

1. 输入“只回复 OK”，收到真实模型回复，证明配置和 HTTPS 链路可用。
2. 请求列出当前目录、创建 `hello.txt`、读取它；写操作出现确认时核对内容并确认。
3. 输入 `.status`，记下 Context hash；输入 `.quit` 退出。
4. `cd /d C:\work\yaca-test` 后运行 `C:\yaca\yaca.exe --continue <hash>`，
   检查历史并再发一条消息，确认保存与重开。
5. 请求执行 `ver`，核对 Shell 确认提示、命令输出和退出结果。

请记录服务器的 `ver`、32/64 位、文件系统、上述结果及出现的错误编号；这些是
本机验收依据。`.details` 可以查看当前进程最近的清理后诊断。

双重检查中的模型可能返回不符合约定的结果。终审未通过时，界面明确提示输入澄清
继续，或用 `.cancel` 结束本轮；此时不会显示任务完成。动作审查未决时，候选工具
尚未运行，先 `.cancel`，再修改请求或 review Model 配置。`.status` 可查看具体等待状态。

可用 `.help` 查看聊天命令，`--help` 查看命令行说明。在线自检须在真实 CMD
控制台运行，并逐次显式同意消耗 API 额度：

```bat
yaca.exe --self-test --through-stage 2 --i-accept-online-self-test
yaca.exe --self-test --through-stage 3 --i-accept-online-self-test
```

Stage 2 检查配置中启用 Model 的连接、认证、协议、流式回复、惰性工具载体和取消；
Stage 3 给出配置语义建议，不自动修改配置。失败的前置阶段不会被跳过。
Cygwin SSH 测试需保持真实 PTY，再运行 `winpty cmd`；普通管道不满足 TTY 条件。
工具相对路径以当前 Context 的工作目录为基准；仍须遵守 Permission 和保留目录限制。

Context 管理器提供列表、检查、搜索，以及 `rename <selector> <new-name>`、
`set-auto-rename-disabled <selector> <true|false>`、`delete <selector> [--yes]`。
删除需要精确 hash 确认，且没有撤销。`rebind <selector> <target-root>` 可迁移到已存在的
工作目录；核对新目录、路径与 hash 后输入 `REBIND <旧hash>`。成功后从新工作目录
用新 hash 运行 `--continue`。接收外来 XML 时，先手工放到正确的 Context 镜像目录，
然后运行 `import <XML完整路径>`；按提示选择本机 Model/Permission 并以 `IMPORT <hash>`
确认。它原位保存映射，不复制文件、不启动聊天、不重放历史操作。目录缺失时先 rebind。
主 XML 缺失/损坏且有有效 `.yaca-prev` 时，可运行 `repair <hash>`，核对恢复来源、
目标和清理路径后输入 `REPAIR <hash>`。它也可清理同一历史的过期 previous；新文件
验证成功后才删除副本，不破锁、不重放操作。没有有效来源时会拒绝修复。
管理器内 `export <hash>` 导出 Markdown，`select <hash>` 继续已有 Context。
`--continue <hash>`、管理器 `select` 和聊天 `.context <hash>` 均支持跨工作目录：
核对两个目录后输入 `CONTINUE <hash>`。取消保留当前状态；确认后 Tools 使用 Context
记录的目录，不移动 XML，不重放未决工作。目录或文件在确认期间变化会拒绝。
恢复后新的工具操作仍需按当前权限审批；输入界面本次显示的审批编号，历史同意不复用。

## 修复无效配置

`--config-repl` 遇到无效 INI 时进入行修复模式，显示错误位置和有界的行号/字段标签。
原文、注释、资源名称和替换输入隐藏；`list 2` 查看下一页。
例如错误位于第 39 行，可输入 `replace 39`，再单独输入完整 INI 行。
`insert 39` 在该行前插入，`delete 39` 仅删除该行；尚未保存时都只是内存草稿。

`preview` 或 `validate` 检查整份候选；有效后输入显示的 `save config-repair-N` 保存。
`reset` 恢复打开时草稿，`reload` 丢弃草稿并重新读取，`quit`/Esc/EOF 放弃未保存修改。
原文件在编辑期间变化会拒绝保存；原子发布结果 unknown 时程序停止。
未修改字节、BOM 和换行保留，未知字段不会自动删除；超过现有字节/行数上限的源文件拒绝载入。

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
