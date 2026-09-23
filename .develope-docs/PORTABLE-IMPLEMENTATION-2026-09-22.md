# 便携通用 Agent 实现记录

日期：2026-09-22。接续 D-072/D-073/D-074，保留 C/Lua、单 Agent、原八个串行工具并新增内置 `lua`、
Context XML、Permission 与默认 DoubleCheck。此轮没有重写 AgentLoop。

## 已落地

- `yaca --lua` 在 C 入口选择同一锁定 Lua 5.5.1 的官方解释器，先于应用引导执行。
  不读取配置、不创建 Context，不要求外部 Lua。`-E` 使用官方忽略环境变量语义。
  Agent 直接调用 `lua` 工具，结构化 argv 启动已运行的内层程序，代码经匿名 stdin
  输入，避免 shell 转义和 XP/Win7 的嵌套 Job 限制；不创建临时脚本。
  沿用 Shell 权限及既有审查/审批、intent/result、输出/时间上限和取消回收。
- 命令与内部语义统一为 `ask`，界面使用 ASK，首次输入也可直接提问。生产 chat 使用
  系统行编辑和 Enter，增强组合键不作为可用能力展示；`.multiline` 提供多行输入。保持无工具纯问答；
  未发布的数据模型直接使用 ask，不增加历史迁移和兼容别名。
- Prompt 包含有界、引用数据形式的解释器路径与可选 tools 目录；不自动执行工具、
  不注册插件、不修改 PATH、不把工具文档当成授权。外部工具不进入核心依赖闭包。
- 无配置时直接启动进入已有离线 Model 向导，成功保存后重新读取配置并进入聊天。
  取消不启动聊天；无效配置仍由配置修复流程处理；普通管道仍被 TTY 门禁拒绝。
- Windows 识别 Cygwin 的 PTY 管道（包括 `-nat` 名称），通过宿主 stty 设置并恢复
  终端状态；交互输出立即 flush，修复非控制台 stdout 缓冲到退出才显示的问题。
- 同目标 clean/std/full 使用同一核心。clean 运行 zip 只有 yaca；许可证和对应源码
  使用附件。装配器要求工具版本、SHA-256、入口、许可证和对应源码，拒绝缺件、
  路径穿越、符号链接和目标架构不符，不生成空壳 full。
- 默认工具版本已机读化。win32 std 的可复现准备流程直接提取官方 Python 2.7.18 MSI，
  闭合 app-local VC90 CRT；PuTTY CLI 使用明确的便携补丁禁用 HKCU 配置和持久随机种子，
  保留主机密钥校验，批处理连接须提供可信 `-hostkey`。不执行 MSI 安装动作。
- std 的 DLL、Python 扩展和 exe 都保留执行权限，避免 Cygwin unzip 把模式映射到
  NTFS ACL 后阻止加载。MSI 所有嵌入 CAB 均只读提取，合并模块中的 CRT 三个 DLL
  逐一闭合；Python 对应源码附件包含其 Berkeley DB 依赖。

## 验证与边界

CentOS 7.9 / glibc 2.17 客体内完整 Lua suite **581/581** 通过，单文件解释器已运行。
Windows Server 2008 非 R2 / Cygwin 3.3.4 的 PTY 探针 **11 项**通过，真实隐藏输入
未回显测试标记，退出后 stty 状态逐字节一致。指定服务器历史 N13 数据保持原位，
本轮使用独立候选目录。

同一核心在开发机的完整 suite 也为 **581/581**。内嵌解释器在 Linux 与指定 Windows
服务器均通过 **8 项**脚本、参数（空值/空格）、stdin、异常、退出码、模块隔离与
环境初始化隔离检查。分档装配 **5 项**测试通过；design/proof/readiness 分别
**7646 / 56 / 553** 项断言通过，脚本语法和 `git diff --check` 通过。

指定 Windows 服务器直接运行 N16：首次向导立即显示，隐藏测试 Key 不回显，取消
不发布配置；Stage 1 **15 项**全部 passed。通过真实 DeepSeek 完成 main → action
review → Shell 一次确认 → 内嵌 Lua `print(6*7)` → termination review，结果 **42**、
exit **0**、子进程结束可证明，turn completed。Context 为 `1E94129A776DAF3E`，
位于独立测试工作目录。退出后仍可在原 SSH shell 执行命令。
另在 std 的带空格目录以空 Key、回环地址离线填写向导并 APPLY，已实际验证
配置发布后自动进入聊天；没有提交聊天消息或联网请求，随后正常退出。

Win32 std 已实际构建，包含 Python **2.7.18**、PuTTY CLI **0.85**、curl **8.21.0**
及 7-Zip **26.03**。新的 zip 用 Cygwin 解压到带空格目录后，Python 标准库来源
确认为该便携目录，SQLite 内存查询、已知 SSH 主机密钥握手、错误主机密钥拒绝、
随包 CA 的 HTTPS 200 与 7-Zip 打包/解包逐字节回读通过。SSH 测试不提供认证凭据，
不声称完成了远端命令/SCP/SFTP 登录旅程。实测环境已有 Python 安装，仍须在干净
XP/Win7 上验证最终 CRT/SxS 闭包；当前导入路径检查排除了依赖系统 Python 标准库。

可重跑的 std 探针为 `.tools/qualification/windows_std_smoke.py`，兼容 Python 2.7，
只有明确传入 `--ssh-host` / `--ssh-host-key` 或 `--https-url` 才执行联网检查。

## 候选产物

汇总交付目录为 `out/yaca-preview-20260922/`，含 clean/std 运行包、许可/源码附件、
SHA256SUMS 和验证证据。所有运行包已扫描，不含 config.ini、Context 或用户密钥。

- Windows 核心：`out/windows-preview-20260922-n16/`，clean zip 根只有 `yaca.exe`；
  核心 SHA-256 为 `377f0dd4191a8e1e96e1cc98c1a07f940773435ecfbb282bfd1f0057b399c7a4`。
- Windows std：`out/editions-win32-20260922-r2/`，与上述 clean 核心逐字节相同；
  构建/实机证据为 `out/win32-std-20260922-r2/logs/`。
- Linux clean：`out/editions-linux-20260922/`，核心 SHA-256 为
  `c6ebc928e3ea03c017b8643e12e5fca658f011c4a593cb2d7e84a4b3744fc9db`。
  在原 CentOS 7 客体复用锁定依赖，重建当前 native 模块和启动器；原依赖来源与
  本轮源码快照在随包构建记录中说明，没有声称重建所有第三方组件。
- 服务器便携目录：`C:\Users\Administrator\yaca-20260922-n16`。运行 `./yaca.exe`
  即可进入聊天，配置沿用测试服务器已存在的授权配置，未进入任何发行包。

## 尚待完成

D-074 最新源码在开发机完整 suite **584/584**、design/proof/readiness
**7656 / 56 / 553** 通过；含 Lua 结构化参数、权限、持久化次序、超时和解释器替换
拒绝，以及 `.ask` 交互回归。这是源码验证；上文 N16 和 581 项 CentOS 7 证据
仍属于此前候选，待重建/复测后才升级产物状态。

Win32 std 工具输入与 full 开发工具箱不是同一资格状态：full 清单及装配已实现，
但各目标实际工具闭包仍须分别构建、测试；缺件时构建会失败。XP SP3、Win7 SP1、
三目标九个最终包、断电恢复与完整发行旅程尚未全部验收。Gate R 保持关闭。
大文件流式处理、旧编码回写和长会话容量问题仍按原路线处理，不能因本轮兼容修复
而标记为已完成。

## 开发入口

- Windows 核心：`.tools/qualification/build_windows_candidate.sh`。
- CentOS 7 核心：`.tools/qualification/build_linux_x86_64.sh`。
- 内嵌解释器验收：`.tools/qualification/interpreter_smoke.py <yaca>`。
- Win32 std：`.tools/qualification/build_win32_std.sh`，只读 MSI 元数据由
  `.tools/qualification/msi_inventory.c` 提取。
- 三档装配：`.tools/package_editions.py`；输入格式、默认版本见
  [TOOL-BUNDLES.md](../release/TOOL-BUNDLES.md)。
- 契约、Prompt/TUI goldens、打包测试随实现更新。源码对照结论见
  [MiniMax Code / ZCode / DeepSeek Harness](references/agent-loop-source-review-2026-09-22.md)。
