# yaca 仓库工作约束

修改前阅读并执行 [编码规范与注释约束](.develope-docs/CODING-STANDARD.md)。

- 文件头固定包含 Author: WaterRun、Date、File、Description，顺序按规范，使用所在语言
  合法的注释语法。
- 所有具名、局部、嵌套和匿名函数、回调、方法、元方法及元表、类和结构体必须完整注释。
  参数和返回值逐项标明，测试、脚本和辅助代码同样适用，不允许遗漏或占位注释。
- 注释覆盖检查与人工语义 Review 都是验收要求；尚未完成时如实记录。
- 构建、完整测试和虚拟机通过 `.tools/run_with_resource_guard.sh` 串行运行。

# 文档风格

用户文档（`README.md`、`README-zh.md`）是写给人看的，不是写给 agent 的。修改时保持这样：

- 只写当前版本。不写变更记录、发布背书，也不写“自 vX.Y 起”这类历史。日志在 git 里。
- 说到用户需要的地方就停。砍掉边界情况穷举、参数语义铺陈和实现内部细节。只有出错才用得上的细节不进 README。
- 用人会说的短句。不写规格书腔，不写层层限定，不写“every X is Y; Z may differ when...”这种对冲链。
- 语气平静，陈述事实。用 “doesn't” / “不会”，不用 “never” / “绝不”；行为上的绝对说法用 “by design” / “设计上” 放软。描述程序做什么，不说教。
- 有意识地用 GitHub Markdown：参考数据用表格，长列表放进 `<details>`，注意事项用引用块。标题下面只放语言切换链接，不放徽章，也不放导航行。`README.md` 和 `README-zh.md` 结构对齐。
- 定位写在开头：通用 Agent；兼容老设备（Win32 到 XP SP3、Win64 到 Win7 SP1、
  Linux 到 CentOS 7）；单文件便携、开箱即用（U 盘插上就用）；能长程开发，
  但更常用于排障修复。不要写成“又一个编程 Agent”。
- `release/*-QUICKSTART.md` 也是用户文档，同样的风格；它们会打进发行包。
  验收记录、资格证据、构建复现步骤放 `.develope-docs/`，不进 README 或 quickstart。
- 发布状态标记由 `.tools/check_documentation_truth.lua` 和
  `.tools/validate_coding_readiness.lua` 检查：未发布时 README 须含
  “target qualification pending”，README-zh 须含“目标资格验证待完成”，
  quickstart 须写明资格验证“待”完成。
- 只给机器看的说明留在这里，不进用户文档。
