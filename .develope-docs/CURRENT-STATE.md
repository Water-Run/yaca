# 当前状态分析

更新日期：2026-07-18

## yaca 仓库

yaca 当前是“产品说明、配置草案、模块骨架和本地运行工具集合”，还不是可执行的 Coding Agent。

已有内容：

- 中英文 README 已描述目标产品、命令、模型、上下文和权限概念。
- `_CONFIG_.ini` 已形成较完整的配置 schema 草案。
- `_CONTEXT_.xml` 提供了上下文文件头部草案。
- `bin/` 本地放置 Lua 5.5.0、curl、BusyBox、jq、diff、patch、iconv、file、sqlite3 等 32 位工具。
- `coding-style.txt` 规定了 Lua 5.5、旧终端、旧浏览器和保守工具链要求。
- 核心 Lua 文件已经按职责命名，但当前均为空。

缺失内容：

- 没有可运行入口、模块接口、测试、安装脚本或发布脚本。
- README 目前描述的是目标行为，尚不能视为已实现契约。
- CLI 短参数存在冲突：`-dc` 和 `-rc` 各自对应两个操作。
- 旧 README 曾混用 `_yaca_` 与 `__yaca__`；设计与公开文档现已统一为逻辑根名 `__yaca__`，但它最终位于用户数据目录、安装目录旁还是便携目录仍待确认。
- README 的模型预设清单与配置模板中的模型条目不一致。
- `_CONFIG_.ini` 仍包含 `[Permission.Cautious]` 和 profile 内 `DoubleCheck`，尚未迁移到 D-021 的全局默认开关与 `.cautious` 会话覆盖设计。
- `_CONTEXT_.xml` 仍只有头部注释，尚未表达 D-022 的镜像路径、完整对话、会话参数元数据和实时索引契约。
- Web 目录只有占位内容，应与核心版本解耦。

### `bin/` 不是可直接发布的依赖集合

2026-07-18 的静态检查进一步证明，`bin/` 只能作为历史来源和候选清单，不能整体复制进发行包：

- Linux 侧 `lua55`、`curl`、BusyBox、diff、patch、jq、sqlite3 等都是 `ELF 32-bit`；其中 curl 自报 `x86_64-pc-linux-muslx32`，属于 x32 ABI，也不是已经确认的 CentOS 7 x86_64 普通 64 位发布基线。
- Windows 侧文件是 PE32 x86，架构方向正确，但“PE32、子系统版本 4.0”只能说明文件头，不能证明它以及全部 DLL、TLS 后端和 CRT 真能在 XP SP3 上启动并工作。
- 当前 `curl.exe` 经 UPX 压缩。静态导入表主要显示 UPX 解压 stub，而不是完整程序真实导入；在取得未压缩的可追溯构建物或先安全解包前，不能完成最低 Win32 API 审计。
- `bin/list.txt` 收录了 7za、BusyBox、file、iconv、jq、sqlite3 等大量候选工具；“仓库里已经有”不等于产品真正需要，也不等于可以进入发布攻击面。
- `cacert.pem` 的内容是 PEM 文本，但其编码、换行、来源版本、证书集合更新时间和 curl 读取结果仍须由发布测试确定，不能只相信 `file` 的标签。

因此发布系统必须从零生成按平台区分的最小 allowlist；每个组件记录来源、版本、架构/ABI、构建选项、hash、许可证、真实动态导入和目标系统运行证据。UPX 等打包步骤只能在未压缩产物已经完成导入审计后考虑，且压缩后的最终文件仍需重新跑完整平台测试。

## luainstaller 能力

相邻的 `../luainstaller` 已经是可用的 1.0.0 打包项目：

- 支持官方 Lua 5.1--5.5；yaca 将固定使用 Lua 5.5 ABI。
- 能生成目录包和自解压单文件；官方建议先验证目录包。
- 入口和纯 Lua 模块会嵌入生成的 C launcher。
- Lua C 模块及匹配的 Lua runtime 可以复制到包内。
- 打包必须在目标平台家族上原生完成，不提供跨平台编译。
- Lua 5.5 安装路径要求 LuaRocks 3.13.0 或更新版本。

但它当前不能直接完成已经确认的 Windows 发布目标：`luainstaller` 1.0 的 Windows native profile 只接受 x86_64，源码会拒绝 Windows x86。yaca 的“Windows XP SP3 x86 + Win32 x86 单一产物 + 使用 luainstaller”三项约束因此存在明确前置阻塞；需要先扩展相邻项目的 Win32/XP profile 与验证契约，不能把“尚未公开测试”误写成“已经可以打包、以后再测”。

## XML 库候选现状

上下文 XML 的当前领先技术候选是 LuaExpat 1.5.2 + Expat 2.8.2，写入端使用 yaca 自有的受限流式 writer；具体库由 CX-06 下游的 `TP-010` 兼容性、实体安全、流式内存和目标机证据决定，不再要求项目负责人替技术侧投库名。本轮临时 Linux x86_64 smoke test 证明 LuaExpat 1.5.2 源码可以针对 Lua 5.5.0 构建并完成分块解析，但还没有归档为可复现测试证据，更不是 CentOS 7 或 Windows XP 验收。上游公开支持目前止于 Lua 5.4，Windows XP x86 也没有现成上游保证。因此 Windows `lxp.dll` 与 Linux `lxp.so` 都必须针对 Lua 5.5 和目标架构原生构建；库选型不能替代单 XML 的原子提交、锁和崩溃恢复设计。

## 与 yaca 的接入结论

luainstaller 负责把 Lua 入口与 Lua 模块变成原生可执行程序，但不能自动代替 yaca 的完整发布装配：

- yaca 的 curl、BusyBox、CA 证书等普通资源需要单独进入发布目录。
- luainstaller 的 `--include` 面向 Lua 依赖，不是通用资源打包接口。
- yaca 应先采用目录式发布装配：luainstaller 产物加受控的 `bin/` 和默认模板。
- 是否提供单文件版本应在目录包稳定后单独决策。
- 发布脚本不应直接修改 luainstaller 生成目录中的所有权清单；更稳妥的做法是把它作为一个组件放进更外层的 yaca 发布目录。

## 主要风险

### 旧 Windows

luainstaller 当前公开验证的是现代 Windows x86_64 + MSVC，并明确拒绝 Windows x86；它不是一个当前可用但未测试 XP 的打包器。解除架构限制后，目录 launcher 是否能在 XP 上运行还取决于编译器、CRT、最低 Win32 API、Lua DLL、LuaExpat/Expat 和依赖工具。单文件提取器还包含更复杂的权限与文件安全逻辑，风险更高。

### CentOS 7

Linux 包依赖构建环境中的匹配 Lua 5.5 头文件与共享库。为了获得可在 CentOS 7 上运行的 glibc 基线，原则上应在该目标环境类别中原生构建并验证。

当前 Linux `bin/` 不是简单的“i686 工具”：至少 curl 是 ELF32/x32 ABI，整组文件也都不是目标的普通 ELF64 x86_64 发行输入。后续不能通过重命名或只检查 `uname -m` 放行，必须检查 ELF class、machine、interpreter/静态链接方式和实际目标机启动结果。

### 外部命令

依赖随包 curl 等工具有利于旧系统兼容，但必须定义：工具查找顺序、版本契约、输出编码、超时、退出码、证书路径以及用户自行替换工具后的支持边界。
