# 04 数据格式

更新日期：2026-08-29

状态：**计划已确认（C05--C09）** — [`formats.lua`](../contracts/formats.lua) 与 fixtures 已冻结 strict UTF-8/SHA-256/JSON/SSE/XML/INI；TP-010 modern 通过，三目标 ABI/资源上限仍待 qualification

## 职责

定义并实现 JSON、INI 以及 Context XML 所需的窄底层格式能力，统一解析错误、编码、转义、顺序保留、流式处理和安全限制。长期用户事实只有主 INI 与每个 Context 的单个正式 XML；本系统不能借格式库引入长期 WAL、索引数据库或第二事实源。

## 边界

- JSON 服务于模型协议和工具 schema。
- INI 服务于配置，但 schema 验证属于 05 号子系统。
- 上下文的业务结构属于 10 号子系统，本系统只提供必要的格式读写能力。
- 同目录 temp/lock/previous-valid 的生命周期、发布和恢复属于 10 号子系统与平台文件 adapter；格式层只提供分块读写、验证和明确错误，不把它们暴露为另一种用户数据格式。

## 兼容性重点

- 主体使用 Lua 5.5 标准能力；只有经过目标平台、许可、供应链和资源上限审阅的窄格式库才可进入发行包。
- 所有持久化文本明确使用 UTF-8；控制台编码由边界层转换。
- 限制最大深度、最大输入和异常数字，避免恶意或损坏数据拖垮进程。
- Context XML 的 parser 和 writer 必须支持分块工作；不能要求 Win32 x86 同时持有旧 XML、新 XML 和完整 DOM。
- XML schema 不定义 Model `Key`、代理凭据、Authorization header 或环境变量秘密字段。Model 的非秘密历史 snapshot 可以进入 XML，新请求使用的凭据只从当前机器 INI 取得。

## 已确认的 XML 能力契约

D-053 已确认：每次 canonical mutation 都从旧 generation 流式生成一份完整新 XML，同目录 temp 写完后先 flush/关闭，再从头进行 XML/schema/关系验证，最后使用目标平台已证明的原子 replace 或 target + previous-valid 的确定性两代恢复协议发布。正式 XML 始终 well-formed；根未闭合、根后追加、长期 WAL/sidecar 和先提交内存状态后补写 XML 均不允许。

格式层必须提供窄接口，而不是通用 XML 编辑器：

- 分块 SAX/pull 等有界解析，能够报告 byte/line/element path 等可行动位置；精确诊断字段以后由错误规格冻结。
- 只面向 yaca schema 的流式 writer：固定 ASCII 元素/属性名，正确转义 text/attribute，拒绝 XML 1.0 禁止字符，不生成 DTD、CDATA、实体声明或处理指令，并以确定顺序输出。
- 解析时显式禁止 DTD/external entity 和任何本地/网络 entity 读取，并限制总 bytes、深度、元素、属性、单文本和累计文本。
- temp 完整写出、flush 后必须由独立读取路径从头验证；不能因为 writer 是项目自有实现就跳过验证。
- parser/writer 不拥有 lock、replace 或 durability。flush、目录同步、no-replace、previous-valid 和崩溃恢复由平台与 10 号系统组合证明。

外来 XML 与本机 XML 使用同一安全 parser 和上限。用户把外来 XML 放在正确镜像位置后，`context-repl` 原位只读校验并完成 workspace/Model/Permission mapping，随后才取得 writer；格式层不复制文件、不激活历史 approval，也不从 XML 恢复 Key。

## 尚未选定的 XML 库研究

目前研究最深入、但**尚未正式选定**的候选组合是：

- [LuaExpat 1.5.2](https://lunarmodules.github.io/luaexpat/) 提供面向 Lua 的分块 SAX 解析。
- [Expat 2.8.2](https://github.com/libexpat/libexpat/tree/R_2_8_2) 作为固定版本的底层解析器。
- yaca 自己提供只面向项目 schema 的窄流式 writer，不自行实现 XML parser。writer 的最终实现同样要经过 golden/fault tests，不能因代码较小就视为已证明。

它值得继续验证的原因不是“功能最多”，而是解析可以按块推进，不必在 Win32 x86 中同时保留完整 XML 和完整 DOM。若采用 LuaExpat，其 threat protection 可限制文档、buffer、深度、属性和文本大小，但 `allowDTD` 默认允许 DTD；yaca 必须显式设为 `false`，并让任何 external entity 请求立即拒绝且绝不读取本地或网络资源。`lxp.threat` 自身会包装 `ExternalEntityRef`，因此安全契约不能写成“没有注册回调”；还应验证在 Expat 构建时关闭 DTD/general entity 支持。参考：[LuaExpat 分块解析手册](https://lunarmodules.github.io/luaexpat/manual.html)、[threat protection](https://lunarmodules.github.io/luaexpat/threat.html)。

LuaExpat 没有 writer。若使用该组合，项目窄 writer 必须满足上一节固定契约，并直接写入二进制 sink；完整 temp flush 后再使用最终选定 parser 从头流式验证，而不是相信 writer 没有出错。

LuaExpat 1.5.2 的官方支持说明目前止于 Lua 5.4；不能把 Lua 5.4 的 C 模块直接用于 Lua 5.5。本轮在临时 Linux x86_64 环境完成的源码 smoke test 只证明“Lua 5.5.0 + LuaExpat 1.5.2 + Expat 2.8.2”存在可构建和分块解析路径，不是 CentOS 7、Windows XP x86 或 Windows x64 发行证据；正式选型前还要把源码 hash、构建命令和输出保存为可审计 fixture。正式发行仍必须为 Windows x86、Windows x64 和 Linux x86_64 分别重新编译、审计依赖并在目标系统验证。Lua 官方也明确不承诺不同 Lua 版本间的 C ABI 二进制兼容，见 [Lua 5.5 手册](https://www.lua.org/manual/5.5/manual.html)。

不建议的候选：libxml2 的 Lua 绑定过重或依赖 LuaJIT/长期无人维护；`xml2lua` 需要整份字符串且 writer 转义边界不足；SLAXML 明确会接受一部分不良格式 XML；自行实现 parser 会把实体、编码、错误恢复和资源攻击重新变成项目责任。

库选型只解决流式解析、转义、格式验证和资源上限，不解决单 XML 的安全提交。整文件重写的累计 I/O、flush/`FlushFileBuffers`、临时文件发布、锁与掉电恢复仍由 10 号上下文存储和平台文件能力共同实测。Windows XP x86/CentOS 7 必须证明大 XML、慢盘、磁盘满、异常终止时的内存、延迟与恢复，并据此冻结 hard limits；其他发行目标执行对应回归。

## 技术证明与失败退路

D-022/D-053 已确认活动 Context 使用单 XML 及完整重写提交协议，不再要求项目负责人从库候选或 WAL 路线中选择。尚待技术证明的是：具体 parser 及版本、Lua 5.5/各目标架构构建、窄 writer、项目 XML 子集的声明与元素/属性、未知字段策略、资源 hard limits、损坏定位，以及各平台 flush/replace/recovery 原语。

如果 LuaExpat/Expat 候选不能通过 ABI、XP/CentOS、供应链、安全或 fault tests，则更换另一种满足同一流式窄接口的 parser；不能降低 DTD/entity 防护或改用全量 DOM 来掩盖失败。如果平台没有满足条件的单步原子 replace，则由 10 号系统采用已经验证的 target + previous-valid 两代恢复协议。若更换库、两代恢复和证据化 hard limits 后仍不能兑现单 XML 保证，必须重新打开 D-053 的最小产品保证，不能自行添加长期 WAL 或第二事实源。
