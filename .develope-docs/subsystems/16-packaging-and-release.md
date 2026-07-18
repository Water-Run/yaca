# 16 打包、安装与发布

状态：候选

## 职责

使用 Lua 5.5 对应的 luainstaller 生成可执行组件，装配随包工具、模板、许可证和安装脚本，并在每个目标平台完成发布验收。

## 初始方向

- 先生成和验证 luainstaller 目录包。
- 在其外层组装 yaca 发布目录，避免修改 luainstaller 所有权清单管理的生成树。
- 每个平台和架构原生构建，不假装跨平台产物。
- 运行验证时清除系统 Lua 模块路径并避免宿主工具掩盖缺失资源。

## 硬门槛

- Windows XP SP3 x86。
- CentOS 7 x86_64。
- 无系统 Lua 仍可运行完整最小闭环。

## 风险

luainstaller 当前没有 Windows XP 公开验证契约；编译器、CRT、Lua DLL、PowerShell 构建依赖和单文件提取器都需要单独验证。

## 待讨论

v0.1 只发布目录包，还是把 luainstaller 单文件模式也列为硬门槛。
