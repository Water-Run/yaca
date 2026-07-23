# 16 打包、安装与发布

状态：候选

## 职责

使用 Lua 5.5 对应的 luainstaller 生成可执行组件，装配随包工具、模板、许可证和安装脚本，并在每个目标平台完成发布验收。

## 初始方向

- 先生成和验证 luainstaller 目录包。
- 在其外层组装 yaca 发布目录，避免修改 luainstaller 所有权清单管理的生成树。
- 每个平台和架构原生构建，不假装跨平台产物。
- Windows x86 与 Linux x86_64 使用同一份 Lua 业务源码，但分别运行 luainstaller，产生互不混用的 native launcher、Lua runtime 和工具资源。
- 两个平台共用 `main.lua`；发布脚本不生成或维护平台专用 Lua 入口。
- 运行验证时清除系统 Lua 模块路径并避免宿主工具掩盖缺失资源。

## 硬门槛

- Windows XP SP3 x86。
- CentOS 7 x86_64。
- 无系统 Lua 仍可运行完整最小闭环。

## Windows 发布验证

XP SP3、Vista SP2、7 SP1、8、8.1、10 和 11 都执行完整测试，任一失败都阻断发布。所有 Windows 版本使用同一 Win32 x86 32 位产物，不另发 x64 或 ARM 版本。

## Linux 发布验证

Linux 只发布 x86_64 产物，不发布 i686 或 ARM。最终支持的发行版都执行完整测试；具体发行版矩阵以后确认。当前 `bin/` 中的 Linux 工具是 ELF32，curl 还是 x32 ABI，不符合最终普通 x86_64 发布基线；发布装配必须提供重新审计的目标 ABI 工具集。

## 风险

### 当前打包链硬阻塞

相邻 `../luainstaller` 1.0 不只是“尚未验证 XP”：它在 [`src/platform.lua`](../../../luainstaller/src/platform.lua) 中明确拒绝 Windows x86，并在 [`docs/PLATFORMS-NATIVE-LIMITS.adoc`](../../../luainstaller/docs/PLATFORMS-NATIVE-LIMITS.adoc) 中把 Windows native profile 限定为 x86_64。因此当前三项约束：

```text
Windows XP SP3 x86
+ Lua 5.5
+ 使用 ../luainstaller 打包
```

尚不能同时兑现。既然项目负责人已经确认前两项并指定第三项，当前唯一一致的推荐路线是：把“为 luainstaller 增加 Win32 x86/XP 原生 profile、launcher、Lua DLL 与测试契约”列为 yaca Windows 发布的前置工作；在获得单独开发授权前，只记录这个依赖，不在 yaca 中暗建另一套打包器。

即使解除架构拒绝，编译器、CRT、最低 Win32 API、Lua DLL、PowerShell 构建依赖和 launcher 仍需逐项验证。XP x86 原生模块候选应使用可生成 XP 程序的工具链；微软文档给出的最后一代官方 XP 工具集是 VS2017 `v141_xp`，并要求 XP SP3，见 [Configuring programs for Windows XP](https://learn.microsoft.com/en-us/cpp/build/configuring-programs-for-windows-xp?view=msvc-170)。

### 随包资源允许列表与未压缩审计

发布包不是当前 `bin/` 的镜像。每个平台从明确 allowlist 装配，每项至少冻结：用途、来源 URL/源码提交、版本、许可证、架构与 ABI、编译器/CRT、TLS 后端、动态导入、hash 和目标平台完整测试证据。未被 yaca 核心直接使用的 7za、jq、sqlite3 等默认不随包。

当前 Win32 `curl.exe` 经 UPX 压缩，现有导入表主要反映解压 stub；PE 头中的 OS/subsystem 4.0 也不是 XP 运行证明。建议发布链保留并审计未压缩产物，先做真实 import/API、DLL、TLS 和 CA 验证，再决定是否允许压缩；任何压缩后的最终文件都必须重新执行 XP 至 Windows 11 的完整测试。仅凭“能在当前开发机运行”或杀毒软件未报警不能放行。

### XML 原生模块装配

若采用 04 号系统的 LuaExpat 候选，Windows 需要针对 Lua 5.5/Win32 x86 构建 `lxp.dll`，Linux 需要针对 Lua 5.5/CentOS 7 x86_64 基线构建 `lxp.so`。建议把 Expat 静态链接进对应模块，减少额外动态依赖；luainstaller 只负责收集已经构建好的 C 模块，不会替项目重建 ABI、递归收集其 C 库依赖或自动补许可证。

## 待讨论

具体测试平台、通用包/分发行版包策略，以及是否同时提供 luainstaller 单文件模式，都在本系统进入正式讨论时决定。
