# yaca: Yet Another Coding Agent

[English](./README.md)

`yaca`是一款简单、单 Agent Coding Agent 的设计，以`GPL v3`协议开源于[GitHub](https://github.com/Water-Run/yaca)。目标为 Lua 5.5、Windows XP SP3 至 Windows 11 的 Win32 x86，以及包含 CentOS 7 的 Linux x86_64。

> **项目状态（2026-07-22）：设计阶段。** 当前没有已经完成的 v0.1 二进制或通过验证的 Release。平台支持、安装、命令、预设和下面的示例都是设计目标，不是已实现行为。现行决定和待回复批次见 [`.develope-docs`](.develope-docs/README.md)。

## 安装  

计划的发布单元是由上级目录`luainstaller`构建的各平台独立`.zip`。打包、安装入口和真实机器证据仍是设计/发布门；通过这些门之前，仓库不能宣称已有可下载发行包。

语义上的`version`动作将用于识别构建后的发行版；它的顶层 CLI 确切拼写仍等待设计决策`TU-18`。目标输出形态为：

```cmd
yaca v0.1.0
Yet Another Coding Agent.
```

产品具有语义上的`help`和`model-repl`入口。Agent chat 在采样 LLM 前必须有一个可用的完整 Model 连接。最终协议/预设清单和精确命令仍待决；旧 README 中出现过的 provider 名称不是兼容承诺。

> `__yaca__`是设计使用的逻辑数据根；它最终位于安装用户数据目录还是便携目录仍待决。不能从仓库中的旧资源反推已经实现的布局。

## 配置  

目标设计使用逻辑`__yaca__`下的一份完整 INI，并允许每个 Context XML 保存明确的会话覆盖。配置查看、还原和交互式修改属于`config-repl`，Model 生命周期属于`model-repl`，三阶段`self-test`是显式验证路径。

Model 的物理顺序决定新 Context 的默认项。Context 保存所选 Model 和历史连接快照；逻辑 Model 被改名、删除、禁用或发生不兼容变化时，yaca 必须在运行时提示映射/修复，不得静默 fallback 到另一个 Model 或 endpoint。会话内切换 Model 是语义动作，其最终 chat 拼写等待`TU-32`。

## 上下文机制  

设计把每个 Context 保存为`__yaca__/CONTEXT/`镜像路径树中的`[命名名称].xml`。例如 Windows 上的一个 Context 可以保存为`CONTEXT/C/Program Files/我的任务.xml`。

哈希输入是从`CONTEXT`根开始的逻辑路径: 带前导`/`, 统一使用`/`分隔, 并包含 XML 文件名. 上述示例严格使用`/C/Program Files/我的任务.xml`计算固定 16 位哈希. yaca 不为上下文另存永久 ID; 名称或路径变化后哈希实时重算, 旧哈希立即失效. 上下文清单与哈希查找从当前 XML 树实时派生.

上下文 XML 保存完整对话、日志相关信息、会话级参数及其元数据. 语义上的`context-list`动作按范围枚举上下文; `context-repl`提供交互式浏览和管理.

语义上的`continue(selector)`动作接受上下文精确名称或固定 16 位哈希. 所有连接、重命名和删除入口共用一套解析器: 从当前目录对应的镜像位置开始, 再由近到远扩展到祖先的递归范围和`CONTEXT`根. 距离优先; 在同一个搜索范围内名称优先于哈希. 解析器单遍同时检查两者, 当前范围得到可裁决结果后不再扫描更远范围. 解析后的工作目录策略仍等待决策`PJ-13`: A/B 保留布尔字段`AutoJumpToDir`, C 则以`ResumeDirectory=jump|ask|keep`取代它.

更简易的上下文管理方式可以使用交互式`context-repl`入口: 访问目录树、搜索、选择并连接, 以及重命名、删除和刷新. 它与命令行共用同一套路径、哈希和安全复核规则.

## 权限机制  

Permission profile 位于 INI。计划的发行模板把`Std`放在第一项，因此它是新 Context 默认项；内置 profile 的最终能力矩阵仍待安全决策。`Cautious`不是独立 Permission 模式：谨慎复核由`DoubleCheck`控制，当前 Context 可通过语义上的`.cautious`动作覆盖。名称和 Description 永远不授予能力。

Context 保存所选 Permission 和历史 effective snapshot；本地 profile 被改名、删除或发生不兼容变化时，yaca 必须提示映射/修复，并在需要处 fail-closed，不得静默采用第一项。Permission 切换的 chat 拼写等待`TU-32`。

## 命令一览  

主入口是`yaca [目录]`. 裸`yaca`与`yaca .`完全等价: 都以当前目录作为初始工作区位置进入TUI. `yaca <目录>`则从指定目录启动.

产品设计还确认了`help`、`version`、`self-test`、`model-repl`、`config-repl`、`context-repl`、`context-list(scope)`和`continue(selector)`等语义动作. 决策`TU-18`仍需把它们投影为确切的顶层 grammar: flag、subcommand 或混合形式, 以及是否提供简称. 因此本 README 中的动作标签目前不是可直接执行的命令拼写. 旧草案的 flag 名称及其互相冲突的简称不属于已确认契约.

Chat 还具有 status/help、queue/steer/side/cancel、Prompt 与 DoubleCheck 覆盖、Model/Permission/Context 管理、typed retry/recovery 和优雅退出等语义动作。`TU-32`仍需决定 canonical dot-command namespace；手动压缩等条件动作只有在自己的上游决定启用时才存在。旧草案中的 dot-command 清单不是可执行契约或兼容承诺。
