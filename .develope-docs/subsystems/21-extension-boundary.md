# 21 扩展边界与未来重入

状态：v0.1 已确认关闭；本文只记录零表面要求和未来重入门

## 现行结论

D-038 已确认 yaca v0.1 是封闭的单 Agent Coding Agent。运行时只装载随发行包提供的内置工具和内部生命周期逻辑；下列能力全部不进入 v0.1：

- MCP client/server 与任何第三方工具协议；
- 自定义工具注册、发现或执行；
- 进程内 Lua 插件、公共 Lua API/ABI 与热加载；
- 用户 hook 或可修改 AgentLoop/Prompt 的 callback；
- skill runtime、skill manifest/市场/依赖解析；
- 子 Agent、后台执行者、委派协议与自动权限继承。

这不是“默认关闭但已经预留”。配置、INI/XML schema、CLI/help/completion、Prompt、工具 registry、事件 namespace、Runtime loader、self-test、依赖和平台 zip 中都不得为这些能力保留可触发空壳。遇到相应配置或调用只能返回稳定 `UnsupportedFeature`，不能静默忽略，也不能把未知字段当作未来兼容文本继续运行。

D-044 另行排除了 Web、remote/headless controller 和媒体表面；内部 application service、测试 adapter 或 typed Lua module 也不构成扩展 API。

## 与核心内部抽象的边界

内置工具仍需要 typed tool identity、参数/结果 schema、call/result 配对、Permission、取消、预算和 Context 事实。这些字段只服务当前内置能力：

- 不增加 extension/source/install-instance identity；
- 不增加第三方 namespace、manifest/protocol version 或 capability negotiation；
- 不为未来 actor/executor 预建可选 ID；当前单 Agent 的本地 turn/request/tool/operation ID 已足够；
- 不把内部模块接口、事件 table、测试 fake 或 provider adapter 宣传成稳定公共 API；
- 不因某个通用字段将来可能复用，就把扩展 loader、注册表或兼容窗口提前实现。

普通项目说明文件继续由指令发现系统作为不可信内容读取；用户也可以让模型通过获准的文件工具或 raw shell 使用自己准备的脚本。两者都不会注册 skill、plugin、hook 或 custom tool。

## 安全与恢复不变量

扩展关闭不会削弱核心不变量：

1. 每个已接受的内置 tool call 都必须配对真实或合成 result。
2. Permission、DoubleCheck、Context durable 屏障和 Runtime hard deny 不由 Prompt 或工具文字授予。
3. raw shell 是用户批准的宽能力内置工具，不伪装成第三方扩展 sandbox。
4. 外来 XML 若含 extension/plugin/MCP/hook/skill/sub-agent required fact，compatibility 检查必须显示 unsupported gap；不得加载代码、启动进程或自动重放副作用。
5. 历史中的普通名称、来源说明或工具 ID 不能反向证明本机已经安装某项扩展。

## 旧 Windows/Linux 影响

关闭扩展意味着 Windows XP x86 与 CentOS 7 的 v0.1 发行测试不包含插件 ABI、MCP runtime、第三方 daemon、扩展 IPC、包管理器或扩展依赖树。随包 allowlist 只列核心实际使用的组件；不能因为仓库或 luainstaller 能携带某个二进制，就把它当成可发现扩展。

这同时避免把 named pipe、Unix socket、fork、现代 Windows API、额外 TLS/runtime 或任意 native Lua module 变成最低平台依赖。

## 零表面验收

每个平台发布候选都必须通过以下负面检查：

- 配置模板、typed schema、REPL、help/completion 中 extension/MCP/plugin/hook/skill/sub-agent 字段和命令数为零；
- Runtime module graph、loader registry、监听端口、IPC endpoint 与第三方代码搜索路径数为零；
- Context XML namespace/element、Prompt purpose、tool source/manifest/executor 字段中没有只为未来扩展保留的项；
- zip 中没有 MCP server、plugin SDK、hook runner、skill manager、第三方工具 host 或无消费者依赖；
- 对外来扩展配置、XML requirement 或命令返回一致的 unsupported 结果，不部分激活、不忽略后继续；
- 内置工具、测试 adapter 和 provider protocol 不能被文档或机器输出标记为“扩展已支持”。

这些检查由 D-038、AR-P0-01/04/06/16、TP-029 和发布供应链清单共同承担。

## 未来重入门

未来只有项目负责人针对一个具体 use case 明确重开，才进入新的设计批次；“以后可能需要”“已有 source ID/schema version”“内部接口足够通用”都不是授权。

重入时必须一次说明：

1. 只重开什么能力及用户旅程，其他扩展种类仍保持关闭；
2. 代码运行位置、信任主体、来源身份与安装/启用/禁用生命周期；
3. Permission、秘密、工具配对、取消、预算和未知副作用边界；
4. 配置、CLI/TUI、错误、Context XML、迁移和缺失依赖行为；
5. Windows XP x86、Windows 后续版本与 CentOS 7 的打包、兼容和故障证据；
6. 公共协议/API 的版本窗口，或明确仍不承诺公共兼容。

在该批次明确完成前，不创建 placeholder 字段、namespace、ID、adapter、loader、目录或 SDK。

## 历史说明

早期曾比较“封闭核心但预留语义接缝”“进程外工具协议”和“进程内 Lua 插件”三条候选路线。D-038 已选择更严格的封闭路线，并明确禁止由来源 ID、namespace 或 future adapter 推导预留支持；旧候选只保留在 Git 历史和冻结问题证据中，不再作为本子系统的现行规格。
