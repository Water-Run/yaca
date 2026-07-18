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
- 安装目录名存在 `_yaca_` 与 `__yaca__` 两种写法。
- README 的模型预设清单与配置模板中的模型条目不一致。
- Web 目录只有占位内容，应与核心版本解耦。

## luainstaller 能力

相邻的 `../luainstaller` 已经是可用的 1.0.0 打包项目：

- 支持官方 Lua 5.1--5.5；yaca 将固定使用 Lua 5.5 ABI。
- 能生成目录包和自解压单文件；官方建议先验证目录包。
- 入口和纯 Lua 模块会嵌入生成的 C launcher。
- Lua C 模块及匹配的 Lua runtime 可以复制到包内。
- 打包必须在目标平台家族上原生完成，不提供跨平台编译。
- Lua 5.5 安装路径要求 LuaRocks 3.13.0 或更新版本。

## 与 yaca 的接入结论

luainstaller 负责把 Lua 入口与 Lua 模块变成原生可执行程序，但不能自动代替 yaca 的完整发布装配：

- yaca 的 curl、BusyBox、CA 证书等普通资源需要单独进入发布目录。
- luainstaller 的 `--include` 面向 Lua 依赖，不是通用资源打包接口。
- yaca 应先采用目录式发布装配：luainstaller 产物加受控的 `bin/` 和默认模板。
- 是否提供单文件版本应在目录包稳定后单独决策。
- 发布脚本不应直接修改 luainstaller 生成目录中的所有权清单；更稳妥的做法是把它作为一个组件放进更外层的 yaca 发布目录。

## 主要风险

### 旧 Windows

luainstaller 当前公开验证的是现代 Windows + MSVC，未承诺 Windows XP。目录 launcher 使用的 Win32 API 较基础，但最终可执行文件是否能在 XP 上运行还取决于编译器、CRT、Lua DLL 和依赖工具。单文件提取器还包含更复杂的权限与文件安全逻辑，风险更高。

### CentOS 7

Linux 包依赖构建环境中的匹配 Lua 5.5 头文件与共享库。为了获得可在 CentOS 7 上运行的 glibc 基线，原则上应在该目标环境类别中原生构建并验证。

### 外部命令

依赖随包 curl 等工具有利于旧系统兼容，但必须定义：工具查找顺序、版本契约、输出编码、超时、退出码、证书路径以及用户自行替换工具后的支持边界。
