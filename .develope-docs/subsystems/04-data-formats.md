# 04 数据格式

状态：候选

## 职责

定义并实现 JSON、INI 以及上下文文件所需底层格式能力，统一解析错误、编码、转义、顺序保留和安全限制。

## 边界

- JSON 服务于模型协议和工具 schema。
- INI 服务于配置，但 schema 验证属于 05 号子系统。
- 上下文的业务结构属于 10 号子系统，本系统只提供必要的格式读写能力。

## 兼容性重点

- 主体使用 Lua 5.5 标准能力；只有经过目标平台、许可、供应链和资源上限审阅的窄格式库才可进入发行包。
- 所有持久化文本明确使用 UTF-8；控制台编码由边界层转换。
- 限制最大深度、最大输入和异常数字，避免恶意或损坏数据拖垮进程。

## XML 库候选研究

当前最合适的候选组合是：

- [LuaExpat 1.5.2](https://lunarmodules.github.io/luaexpat/) 提供面向 Lua 的分块 SAX 解析。
- [Expat 2.8.2](https://github.com/libexpat/libexpat/tree/R_2_8_2) 作为固定版本的底层解析器。
- yaca 自己提供只面向项目 schema 的窄流式 writer，不自行实现 XML parser。

选择它的原因不是“功能最多”，而是解析可以按块推进，不必在 Win32 x86 中同时保留完整 XML 和完整 DOM。LuaExpat 的 threat protection 可限制文档、buffer、深度、属性和文本大小，但其 `allowDTD` 默认允许 DTD；yaca 必须显式设为 `false`，并让任何外部实体请求立即拒绝且绝不读取本地或网络资源。`lxp.threat` 自身会包装 `ExternalEntityRef`，因此安全契约不能写成“没有注册回调”；还应优先在 Expat 构建时关闭 DTD/general entity 支持。参考：[LuaExpat 分块解析手册](https://lunarmodules.github.io/luaexpat/manual.html)、[threat protection](https://lunarmodules.github.io/luaexpat/threat.html)。

LuaExpat 没有 writer。候选 writer 只接受固定 ASCII 元素/属性名，正确转义文本和属性，拒绝 XML 1.0 禁止字符，不生成 DTD、CDATA、实体声明或处理指令，稳定排序属性，并直接写入二进制 sink。完整临时文件写完后，再使用 LuaExpat 从头流式验证，而不是相信 writer 没有出错。

LuaExpat 1.5.2 的官方支持说明目前止于 Lua 5.4；不能把 Lua 5.4 的 C 模块直接用于 Lua 5.5。本轮在临时 Linux x86_64 环境完成的源码 smoke test 只证明“Lua 5.5.0 + LuaExpat 1.5.2 + Expat 2.8.2”存在可构建和分块解析路径，不是 CentOS 7 或 Windows XP 证据；正式选型前还要把源码 hash、构建命令和输出保存为可审计 fixture。正式发行仍必须为 Windows x86 和 Linux x86_64 分别重新编译、审计依赖并在目标系统验证。Lua 官方也明确不承诺不同 Lua 版本间的 C ABI 二进制兼容，见 [Lua 5.5 手册](https://www.lua.org/manual/5.5/manual.html)。

不建议的候选：libxml2 的 Lua 绑定过重或依赖 LuaJIT/长期无人维护；`xml2lua` 需要整份字符串且 writer 转义边界不足；SLAXML 明确会接受一部分不良格式 XML；自行实现 parser 会把实体、编码、错误恢复和资源攻击重新变成项目责任。

库选型只解决流式解析、转义、格式验证和资源上限，不解决单 XML 的安全提交。整文件重写的累计 I/O、flush/`FlushFileBuffers`、临时文件发布、锁、掉电恢复和 XML 根结束标签后的追加限制仍由 10 号上下文存储与平台文件能力共同设计和实测。

## 待讨论

D-022 已确认活动上下文继续使用 XML。仍需由项目负责人确认上述库方向，并决定项目专用 XML 子集的声明与编码、元素/属性、最大深度/大小、未知字段往返和损坏定位；不实现无边界的通用 XML 处理器。
