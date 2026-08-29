# 16 打包、安装与发布

更新日期：2026-08-29

状态：**计划已确认（C31--C34），Release Gate R 关闭**；pins/allowlist/zip/evidence contract 已冻结，三目标 qualification 待执行

> Context XML 对外承诺见 D-068（内部格式；export 为主），与打包证据门独立。

## 职责

使用 Lua 5.5 对应的 luainstaller 生成可执行组件，装配随包工具、模板、许可证和安装脚本，并在每个目标平台完成发布验收。

## 已确认方向

- 最终打包阶段使用 luainstaller 生成可直接运行的二进制，并在其外层组装固定 yaca 发布目录。
- 每个平台和架构原生构建，不假装跨平台产物。
- Win32 x86、Win64 x86_64 与 Linux x86_64 使用同一份 Lua 业务源码，但分别运行 luainstaller，产生互不混用的 native launcher、Lua runtime 和工具资源。
- 三个目标共用 `main.lua`；发布脚本不生成或维护平台专用 Lua 入口。
- 运行验证时清除系统 Lua 模块路径并避免宿主工具掩盖缺失资源。
- luainstaller qualification 位于项目最后的打包阶段；届时先以实际候选产物验证，只有证据证明现有路径无法满足目标时才对 `../luainstaller` 做实现所需的最小修改，不为 yaca 建立第二套打包器。
- **D-069：** 不预写“砍 XP / 双包 / 实验性 XP”等产品退路；工作假设为 luainstaller **可以** 支撑三包含 XP。仍须目标机证据放行，假定 ≠ 免测。

## 硬门槛

- Windows XP SP3 x86。
- Windows 7 SP1 x86_64。
- CentOS 7 x86_64。
- 无系统 Lua 仍可运行完整最小闭环。

## 三个独立 zip

v0.1 恰好发布三个彼此独立构建、测试和放行的 zip：

1. Win32 x86：XP SP3 至 Windows 11。
2. Win64 x86_64：Windows 7 SP1 至 Windows 11。
3. Linux x86_64：CentOS 7 为最低基线。

不发布 ARM、Windows on ARM 原生包、Linux i686 或 macOS 包。一个包通过不能替代另一个包的构建与测试证据。

两个 Windows zip 的根目录完全相同：

```text
yaca.exe
Install.cmd
README.txt
LICENSE
docs/
```

Linux zip 使用对应布局：

```text
yaca
Install.sh
README.txt
LICENSE
docs/
```

主程序在解压位置原地运行；Lua runtime 与运行依赖由 luainstaller 嵌入，不依赖系统 Lua。`__yaca__` 永远与实际运行的 `yaca.exe`/`yaca` 相邻，不能随调用 cwd 或 PATH 查找结果之外的状态漂移。

## 薄安装脚本

`Install.cmd` 从脚本自身位置确定发行目录，只执行简单、可解释的检查：确认同目录存在 `yaca.exe`，能够启动并完成无网络基础检查，以及该发行目录适合且可写。目录不合适时向用户说明并询问；用户确认后，只把该发行目录加入 PATH。脚本不移动或复制发行文件，不建立安装数据库，不计算 MD5 或其他完整性摘要，也不负责卸载、更新或回滚。

`Install.sh` 对 Linux 提供同等的简单语义：从脚本自身位置确定发行目录，检查同目录 `yaca`、基础启动与发行目录可写性，必要时询问，再将该发行目录加入 PATH；不能扩展成另一套包管理器。具体 PATH 写入位置和平台命令必须在实现时选择最低兼容、可撤销的做法，但不能改变上述产品结果。

## Windows 发布验证

Win32 x86 候选在 XP SP3、Vista SP2、7 SP1、8、8.1、10 和 11 上完成完整测试。Win64 x86_64 候选在 7 SP1、8、8.1、10 和 11 上完成完整测试。两个候选独立放行，任一失败只阻断对应包，但不能用另一个架构冒充替代品；不另发 ARM 版本。

## Linux 发布验证

Linux 只发布 x86_64 产物，不发布 i686 或 ARM。CentOS 7 x86_64 是最低基线；最终声明支持的每个发行版都使用这个正式候选完成完整测试。当前 `bin/` 中的 Linux 工具是 ELF32，curl 还是 x32 ABI，不符合最终普通 x86_64 发布基线；发布装配必须提供重新审计的目标 ABI 工具集。

## 发行证据与升级边界

每个 zip 都必须独立附带或发布以下可核验材料：

- zip 的 SHA-256；
- component/license manifest；
- SBOM；
- 构建摘要，包括源码提交、luainstaller 版本/修改和目标 ABI；
- 对应完整平台矩阵的测试摘要与放行结论。

这些摘要由构建/发布流程产生，不由 `Install.cmd`/`Install.sh` 在用户机器上重新计算。v0.1 不做代码签名，也不内置更新检查、下载或自动安装；用户手工取得并替换 zip，yaca 不管理相邻 `__yaca__` 的更新迁移。

## 风险

### 当前 x86/XP qualification 与发布证据缺口

相邻 `../luainstaller` 已更新到 1.3.0（2026-08-24，tag `v1.3.0`）：native profile 已接受 x86/x86_64，生成的 Windows x86/x64 C surface 使用 XP API baseline，PE subsystem 为 5.01/5.02，并有 i686/x86_64 MinGW import/API 静态审计、Windows x64 MSVC 与 Linux native x86 CI。此前“profile guard 拒绝 x86、recipe 只有 x64”的风险事实已经失效。

当前三项产品约束仍为：

```text
Windows XP SP3 x86
+ Lua 5.5
+ 使用 ../luainstaller 打包
```

现在已有可执行 qualification 路线，但尚未由 yaca 候选兑现。项目必须固定 luainstaller 版本，先生成匹配 Lua 5.5 与拟用 native 模块形状的最小 onedir，随后以最终依赖闭包构建三个候选；静态 XP surface 证据只能提前发现问题，不能替代真实 XP、Win7 和 CentOS 7 完整运行。只有证据要求时才对兄弟仓库做最小修改，不在 yaca 中暗建第二套打包器。

即使解除架构拒绝，编译器、CRT、最低 Win32 API、Lua DLL、PowerShell 构建依赖和 launcher 仍需逐项验证。XP x86 原生模块候选应使用可生成 XP 程序的工具链；微软文档给出的最后一代官方 XP 工具集是 VS2017 `v141_xp`，并要求 XP SP3，见 [Configuring programs for Windows XP](https://learn.microsoft.com/en-us/cpp/build/configuring-programs-for-windows-xp?view=msvc-170)。

### 随包资源允许列表与未压缩审计

发布包不是当前 `bin/` 的镜像。每个平台从明确 allowlist 装配，每项至少冻结：用途、来源 URL/源码提交、版本、许可证、架构与 ABI、编译器/CRT、TLS 后端、动态导入、hash 和目标平台完整测试证据。未被 yaca 核心直接使用的 7za、jq、sqlite3 等默认不随包。

当前 Win32 `curl.exe` 经 UPX 压缩，现有导入表主要反映解压 stub；PE 头中的 OS/subsystem 4.0 也不是 XP 运行证明。建议发布链保留并审计未压缩产物，先做真实 import/API、DLL、TLS 和 CA 验证，再决定是否允许压缩；任何压缩后的最终文件都必须重新执行 XP 至 Windows 11 的完整测试。仅凭“能在当前开发机运行”或杀毒软件未报警不能放行。

### XML 原生模块装配

若采用 04 号系统的 LuaExpat 候选，Windows 需要分别针对 Lua 5.5/Win32 x86 与 Lua 5.5/Win64 x86_64 构建 `lxp.dll`，Linux 需要针对 Lua 5.5/CentOS 7 x86_64 基线构建 `lxp.so`。建议把 Expat 静态链接进对应模块，减少额外动态依赖；luainstaller 只负责收集已经构建好的 C 模块，不会替项目重建 ABI、递归收集其 C 库依赖或自动补许可证。

## 尚待实现阶段证明

- 三个目标的 luainstaller launcher、Lua 5.5、原生模块、随包工具和最低系统 API qualification。
- `Install.cmd`/`Install.sh` 在最低目标平台上的 PATH 修改与错误恢复实现。
- 最终 Linux 支持发行版清单；它不能改变 CentOS 7 最低基线或改成未独立测试的多 ABI 通用包。
