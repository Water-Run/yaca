# 11 上下文定位、实时索引与交互式浏览器

状态：讨论中

## 为什么这是一个独立子系统

上下文 XML 的内容由 10 号存储系统负责，但“用户给出一个名称或 hash 后，到底连接哪个 XML”是另一类问题。它同时涉及路径映射、实时目录扫描、搜索范围、歧义、重命名后的身份变化、CLI/TUI 一致性和旧系统性能，不能散落在各条命令里分别实现。

本系统建立一个统一的上下文目录与定位服务，供 `continue`、context-select、重命名、删除、列表、浏览器和后续带上下文选择器的 semantic actions 共同使用；CLI/dot-command 的精确拼写由 TU-18/TU-32 投影。

## 命名说明

项目负责人本轮提出的“交互式配置浏览器”包含选择、重命名、删除、目录树访问和搜索。按操作对象判断，本文件把它定义为**交互式上下文浏览器/管理器**：它浏览的是 `CONTEXT` 树，不是 `config.ini` 的配置项。

真正的配置浏览器属于 05 号配置系统，负责查看和修改配置键，不应拥有重命名或删除上下文的业务权限。如果项目负责人所说的“配置浏览器”确实还包括另一套配置项树界面，应在 05 号文档中单独设计，不能把两类数据混在同一个控制器里。

## 职责

- 在 `__yaca__/CONTEXT/` 镜像树中枚举当前有效的上下文 XML。
- 把工作目录、物理 XML 路径和规范逻辑路径相互转换。
- 根据当前逻辑路径实时计算固定 16 位 hash。
- 以统一规则解析名称/hash 选择器，并报告唯一命中、歧义、碰撞、不完整扫描或未找到。
- 为上下文浏览器提供目录树、搜索、排序、选择和刷新语义。
- 为重命名、rebind 与删除提供经过重新校验的目标，但把 XML metadata/内容更新交给 10 号系统。
- 向 current-context-status semantic action 提供当前绑定路径的实时 hash 计算，不通过全局搜索反查当前会话。

## 边界

- 不保存或修改消息主体；XML schema、提交点和恢复由 10 号系统负责。
- 不决定上下文压缩内容；由 12 号系统负责。
- 不决定 CLI 参数拼写或终端绘制；CLI、TUI、plain/enhanced renderer 都只能调用这里同一份 semantic action，不能复制一套目录、选择或 mutation 规则。这个内部 action parity 不构成公共 headless/IPC/RPC 控制面。
- 不因名称/hash 搜索命中就自行 `chdir`。每个 Context 恰好一个 root；显式选中后只从当前 XML 在 `CONTEXT` 镜像树中的父目录解码该 root。XML 内历史 cwd/root 值不参与求值。解码失败、目录缺失/不可进入或身份不匹配时交给 `context-repl` self-fix，不提供 `AutoJumpToDir`、`ResumeDirectory` 或相似目录猜测。
- 自动命名可以调用模型，但枚举、hash、定位、重命名和删除在无网络时必须可用。
- 不建立永久数据库、集中索引文件或文件 watcher 作为正确性前提。

## 已确认契约

### 镜像布局与 hash 输入

每个活动上下文是 `__yaca__/CONTEXT/` 镜像树中的一个 XML。例如：

```text
关联工作目录：C:\Program Files
上下文名称：  我的任务
物理相对路径：CONTEXT/C/Program Files/我的任务.xml
逻辑路径：    /C/Program Files/我的任务.xml
hash 输入：   /C/Program Files/我的任务.xml
```

逻辑路径带前导 `/`、统一使用 `/` 分隔，并包含当前上下文名称和 `.xml`。双引号不属于输入。hash 的具体算法、字节编码、输出字母表、大小写和碰撞概率仍待确认，但对用户显示和输入的结果固定为 16 位。

### 没有永久 ContextId

- XML 内不另存一个跨重命名保持不变的永久 `ContextId`、UUID 或隐藏主键。
- 当前逻辑 XML 路径就是当前地址；16 位 hash 是该地址的运行时短表示。
- 重命名或移动导致逻辑路径变化时，立即从新路径计算新 hash。
- 旧 hash 随即失效，不自动保留为历史别名，也不能继续连接新文件。
- hash 不是可跨重命名引用的永久外键。日志可以把当时的路径/hash 保存为历史快照，但不能据此假装它以后仍指向同一个文件。
- 单个 XML 内的 turn、message、tool call 等关系仍可拥有局部序号或事件 ID；这属于 10 号 schema，不等于为上下文恢复永久身份。

由 yaca 自己执行重命名时，可以在成功后把当前运行时句柄更新到新路径。若外部程序偷偷移动或重命名活动 XML，在没有永久 ID 的前提下，yaca 不应按内容猜测哪个新文件是原会话；候选行为是把当前句柄标记为失效并要求用户重新连接。

### 实时派生

- `CONTEXT` 中当前存在的已提交 XML 文件树是目录和 hash 查找的事实源。
- 列表与 hash 查找不能要求先存在永久索引文件或数据库。
- 任何缓存都只能是可丢弃的派生数据，不能代替当前 XML 树成为事实源。

一次操作内的瞬时快照、浏览器复用和最终重新校验是本文件的当前推荐架构，不是已经确认的缓存刷新细则；完整协议见后文“实时索引的快照协议”。

### 动态地址的统一使用

- `continue(selector)` 等所有接受上下文选择器的 semantic actions 必须使用同一个解析器。
- 重命名、删除等接受选择器的命令也使用相同搜索范围和消歧规则，不能各自实现一份近似逻辑。
- `.status` 根据当前运行时绑定的逻辑路径直接计算当前 hash，不通过全树搜索寻找自己。
- Resolver 已确认距离优先，同一搜索环内精确名称优先于 hash；计算层单遍同步匹配，语义层完成当前环的必要扫描后裁决。

## 核心术语

| 术语 | 含义 | 是否持久身份 |
| --- | --- | --- |
| 物理路径 | 操作系统上实际 XML 文件路径 | 否 |
| 逻辑路径 | 从 `CONTEXT` 根开始的规范 `/.../名称.xml` | 当前地址，不保证不变 |
| 当前 hash | 由当前逻辑路径实时计算的 16 位短地址 | 否；路径变化即变化 |
| 选择器 | 用户交给 continue/context-select 等 semantic actions 的名称或 16 位 hash 文本 | 否 |
| 起点 | 发起解析时的当前工作目录及其镜像目录 | 否 |
| 搜索环 | 相对起点由近到远、互不重复的一组新增候选 | 否 |
| 目录快照 | 一次操作内按范围/页惰性取得的可丢弃有界视图 | 否，不落盘 |
| 当前句柄 | 运行中会话绑定的最新逻辑/物理路径和有效状态 | 仅进程内 |

## 建议的分层架构

```text
selector 入口 ------> ContextResolver ------> SearchScopePlanner
                            |
                            v
                    ContextCatalogScanner ------> LogicalPathCodec ------> ContextHash

浏览器 ------> ContextBrowserController ------> ContextCatalogScanner

Resolver 结果/浏览器选中项 ------> ContextTargetVerifier
                                      |              |
                                      v              v
                             ContextOpenService  ContextMutationService
                                      |              |
                                      +------> ContextStore（10 号）

.status ------> CurrentContextHandle ------> LogicalPathCodec ------> ContextHash
```

这张图表达四条不同路径：

1. 用户给出选择器时，经过统一 Resolver 搜索。
2. 浏览器按需枚举/搜索 Catalog，不自行实现 selector 规则。
3. 搜索结果或浏览器选中项先经共同复核，再分别进入只读打开或修改服务。
4. 已经连接的会话查询 `.status` 时，直接从当前句柄计算，不搜索。

### `LogicalPathCodec`

- 在唯一 workspace root、镜像物理父目录和逻辑路径之间双向转换；当前 root 只由实际父目录反向解码。
- 生成唯一且严格的 hash 输入。
- 拒绝 `..`、绝对路径注入、非法分隔符和任何逃出 `CONTEXT` 根的映射。
- 只处理路径语义，不扫描目录、不读取完整 XML、不计算业务状态。

盘符、UNC、POSIX 根、大小写、Unicode、尾随点/空格、8.3 别名、长路径和非 UTF-8 名称的具体规范仍由后续路径问题确认。

### `ContextHash`

- 只接收已经规范化的逻辑路径，输出固定 16 位文本。
- 相同规范输入必须在 Windows/Linux 得到相同结果。
- 一次解析或快照内可以按需记忆结果；不得把映射表当成永久事实源。
- 重命名后必须对新逻辑路径重新计算，不查询旧 hash 别名表。

### `ContextCatalogScanner`

- 流式遍历指定搜索环，避免一次把整棵树载入 Win32 x86 内存。
- 读取目录项和识别候选所需的最少 XML 头部，不为搜索完整解析长对话。
- 排除临时写入、备份、回收区和非已提交文件；精确规则依赖 10 号提交协议。
- 报告不可读目录、损坏候选、扫描期间变化和越界链接，而不是静默把它们当作不存在。
- 输出顺序不能决定解析结果；排序由上层显式完成。

### `SearchScopePlanner`

- 从当前工作目录对应的镜像目录开始，生成由近到远的搜索环。
- 使用结构化“排除已完成子树”规则，避免每向上一级就重新扫描已经完成的整棵子树。
- 不要求保存整棵树的全量 `visited` 集合；流式扫描只维护目录栈、祖先边界和可选的有界目录前沿。
- 同一个 XML 候选在一次解析中最多做一次有效性探测、名称比较和 hash 计算。为进入尚未扫描的深层子目录，边界目录本身可能被再次枚举，但已处理 XML 不再重复参与匹配。
- 最终扩展到 `CONTEXT` 根时，才覆盖其他顶层路径分支。

### `ContextResolver`

- 是所有名称/hash 精确定位的唯一入口。
- 只负责选择器解释、范围顺序、名称/hash 裁决、歧义和错误结果。
- 不完整加载上下文、不修改文件、不切换工作目录。
- 返回带逻辑路径、物理路径、当前 hash 和观察凭据的结果，供打开或修改前重新校验。

### `CurrentContextHandle`

- 保存运行中会话当前绑定的逻辑路径、物理路径、由父目录解码的唯一 root 快照和有效/失效状态。
- 它不是永久 ID，也不用于全局搜索。
- yaca 重命名成功后更新句柄；失败时仍保留旧路径。
- `.status` 每次从句柄的当前逻辑路径计算 hash；文件已丢失时还应同时显示失效状态。

### `ContextTargetVerifier`

- 接收 Resolver 结果或浏览器选中项，在真正打开/修改前重新打开目标并核对观察凭据。
- 统一检查目标仍位于 `CONTEXT` 根、逻辑路径仍对应当前文件、XML 头仍有效，以及目标是否已被替换。
- 返回 `Verified`、`TargetChanged` 或 `TargetUnavailable`，不负责恢复会话，也不执行重命名/删除。
- 打开与修改共用这一层安全复核，但后续进入不同服务。

### `ContextOpenService`

- 消费已经验证的候选并调用 10 号 `ContextStore` 只读加载/恢复会话。
- 负责格式不兼容、镜像父目录不可解码为可用单一 root、活动写锁等打开结果，不拥有 rename/rebind/delete 语义。
- 浏览器“选择并连接”和 `continue` action 最终都进入这里。

### `ContextMutationService`

- 消费 Resolver 或浏览器快照给出的候选描述，不再凭字符串猜测目标。
- 在重命名、rebind 或删除前经 `ContextTargetVerifier` 复核，再取得修改锁/lease。
- 目标已有活动 writer lease 时，任何外部管理入口的 rename、rebind、delete 或 `AutoRenameDisabled` 修改都返回 `LockConflict`；context-repl 只能显示无需解析正文即可证明的 busy/PID 元数据并等待用户稍后重试，不能用确认或锁龄强夺。
- 调用 10 号 `ContextStore` 完成 XML metadata 提交与 no-replace、可恢复路径更新；rebind 的目标必须是另一个可解码的 workspace 镜像目录。
- 重命名、rebind、删除成功后废弃相关快照，并通知活动句柄更新或失效。

### `ContextBrowserController`

- 保存当前目录节点、展开状态、搜索条件、排序、分页/选择和待确认动作。
- 接收 renderer 产生的 `OpenNode`、`SelectContext`、`RenameContext`、`RebindContext`、`SetAutoRenameDisabled`、`DeleteContext`、`Refresh` 等语义动作。`SetAutoRenameDisabled` 只接受 typed boolean，不引入通用 flags bag。
- 输出新的可渲染视图状态、确认请求或调用目录/打开/修改应用服务的意图。
- 不知道 ANSI、颜色、方向键或鼠标，也不直接操作 XML。
- plain 与 enhanced renderer 必须共享它，避免两个界面产生两套业务规则。

## 候选条目的最小数据

一次快照中的条目建议只包含：

```text
physical_path       实际文件路径
logical_path        规范逻辑路径
display_name        去掉 .xml 的名称
canonical_name      XML header 的 canonical Name
created_at          XML header 的 canonical CreatedAt
updated_at          XML header 的 canonical UpdatedAt
scope_rank          第几个搜索环首次包含该条目
hash16              按需计算，可暂时为空
observed_stat       大小、修改时间及平台可提供的文件标识
header_state        valid / corrupt / unavailable / changed
```

这里没有 `ContextId`。`observed_stat` 只是防止“看见后被替换”的一次性观察凭据，也不是永久身份。

## 哪些入口怎样使用目录服务

| 入口类型 | Semantic action 例子（不是 CLI 拼写） | 行为 |
| --- | --- | --- |
| 精确选择器 | `continue(X)`、`context-select(X)`、`context-rename(X, ...)`、`context-delete(X)` | 调用统一 Resolver |
| 当前会话操作 | `current-context-status`、`current-context-mutation`，以及仅在上游启用时存在的 `manual-compaction` | 使用 CurrentContextHandle，不搜索；chat root 只由 TU-32 投影；若以后增加 selector 参数才调用 Resolver |
| 列表枚举 | `context-list(scope)`、`context-repl` | 取得 Catalog 快照，不把列表每一项再解析一次 |
| 浏览器手工精确输入 | 输入完整名称或 16 位 hash | 调用统一 Resolver |
| 浏览器选中一行 | `select 7` 或 enhanced 中确认 | 携带该快照条目的直接定位信息，TargetVerifier 复核后由 OpenService 连接，不按名称重新搜索 |
| 浏览器普通搜索 | 名称/逻辑路径的前缀或包含搜索 | 过滤/排序快照，只展示结果，不自动连接 |

“所有连接入口共用解析器”不等于从菜单选中一行后还要丢弃已选条目、再用名称猜一遍。菜单行已经指向快照中的明确候选；正确做法是直接携带候选并在使用前复核。

## 已确认：由近到远的增量搜索环

设当前工作目录对应镜像目录 `D0`，父目录依次为 `D1`、`D2`，最终到 `CONTEXT` 根。为保留项目负责人描述的搜索范围、同时不重复遍历，定义：

```text
R0 = D0 目录直属的上下文 XML
R1 = D1 整棵子树，减去 R0 已检查的直属 XML
R2 = D2 整棵子树，减去 D1 已经覆盖的整棵子树
R3 = D3 整棵子树，减去 D2 已经覆盖的整棵子树
...
```

因此：

- `R0` 只处理当前目录的直接上下文。
- 第一次扩大到父目录时，会加入父目录直属上下文、兄弟分支，以及当前目录下尚未检查的更深子目录。
- 再向上时，只加入新祖先带来的目录和兄弟分支。
- 到 `CONTEXT` 根后，全局范围被覆盖，但每个 XML 候选最多做一次探测和匹配。

这比“每上一级递归扫描整棵子树”更省 I/O，也不会因为重复处理同一 XML 得到不同优先级。实现可以保存有界的子目录前沿来直接进入 `D0` 的深层分支；若前沿超过内存预算，也允许为发现这些子目录再次枚举 `D0` 这一层目录项，但不能重新探测其中已经处理过的直属 XML。这里承诺“不重复整棵已完成子树”，不虚假承诺每个目录项在所有情况下只由操作系统返回一次。

## 名称/hash 算法比较

选择器不是 16 位时，不可能是 hash，完全不需要计算任何候选 hash。选择器恰好 16 位时有三种主要做法：

| 方案 | 目录遍历 | 优点 | 代价/语义问题 |
| --- | --- | --- | --- |
| 严格两遍：先名称、后 hash（未采用） | 最坏每个范围两遍 | 规则最直观，名称命中时少算 hash | 老硬盘上目录 I/O 最坏近乎翻倍 |
| 16 位 hash 先行并命中即返回（未采用） | 最好可能很快 | 明确按 hash 查询时延迟低 | 会改变“名称后 hash”的语义；16 位名称、碰撞和枚举顺序可能产生意外结果 |
| 单遍双判定，范围结束后裁决（已确认） | 每个 XML 最多探测/匹配一次 | 同时保留语义优先级与最低目录遍历 | 名称最终命中时可能多做少量短路径 hash |

路径 hash 只处理较短字符串；在 XP 时代机械硬盘或大型网络盘上，目录枚举通常比这点计算昂贵得多。因此已经确认第三种：**计算层同时判断，语义层再决定谁优先**。

这也回答“16 位是否应优先判断 hash”：可以先用长度/字母表判断它“有可能是 hash”，并在扫描时同步计算；但不能遇到第一个 hash 就提前返回。计算顺序不等于结果优先级。

## 已确认的解析流程

正式语义为“距离优先，每个搜索环内名称优先于 hash”：

```text
resolve(selector, origin):
    name_candidate = selector 是否可作为安全的精确上下文名称
    hash_candidate = selector 是否恰好符合 16 位 hash token 规则

    for ring in 由近到远的增量搜索环:
        name_observations = []
        hash_observations = []
        ring_complete = true

        if ring 是 R0 且 name_candidate:
            只探测一次 D0/selector.xml，并把观察结果标记为已访问
            若路径规则能证明它是唯一等价名称且文件有效，直接返回名称命中
            否则缓存该观察，后续遍历不得再次探测同一候选

        流式遍历 ring 中尚未访问的候选:
            记录候选可用性，比较精确名称并收集名称观察
            若 hash_candidate 且尚无可用名称命中:
                从逻辑路径计算 hash，并收集 hash 观察
            若应扫描目录不可读，记录范围错误并令 ring_complete = false

        完成本 ring 后:
            若 ring_complete = false，返回 ScanIncomplete，不宣称任何单个命中唯一
            若有名称观察，按名称可用性/歧义策略裁决；产生终止结果就返回
            若有 hash 观察，按 hash 可用性/碰撞策略裁决；产生终止结果就返回
            若上述策略均未产生终止结果，进入下一个 ring

    返回 NotFound 或 ScanIncomplete
```

重要约束：

- 当前范围的 hash 命中仍早于更远范围的名称命中；“距离优先”是第一层规则。
- 同一范围必须完成必要扫描后再裁决，不能把文件系统“先枚举到谁”当成优先级。
- 当前范围不可完整扫描时，`ScanIncomplete` 是终止本次解析的结构化错误；不能把已观察到的单个名称/hash 当作唯一，也不能跳到外层继续找一个看似可用的结果。
- R0 快路径的探测结果必须缓存并纳入本环裁决；即使文件损坏或不可读，也不能在流式遍历中再次探测同一路径。损坏匹配最终映射为 `MatchedUnavailable` 还是另一错误仍待 10、15 号系统确认，但不得因快路径丢失该观察。
- 一旦发现可用名称命中，余下扫描只需排查其他同名项，不必继续计算 hash；只有损坏/不可读名称观察时仍保留 hash 观察，最终是否允许回退由待确认的损坏匹配策略决定。
- 搜索环完整时，多个可用同名项不能任选第一个；Resolver 返回 `AmbiguousName`。若环不完整，前述 `ScanIncomplete` 优先；非交互候选输出和交互选择方式仍待确认。
- 搜索环完整时，多个可用候选具有相同 hash 不能任选第一个；Resolver 返回 `HashCollision`。若环不完整，前述 `ScanIncomplete` 优先；碰撞的候选显示方式仍待确认。
- 当前范围得到唯一 hash 后立即结束，不扫描更远范围排查全局碰撞；更远结果不能推翻近层结果。
- 未来 hash 字母表确定后，应以“固定 16 位 + 合法字母表”判断 hash，而不只是接受任意 16 个用户字符。

### 复杂度

设实际检查到 `D` 个目录、`F` 个 XML，平均逻辑路径长度为 `L`，边界目录因有界内存而再次枚举的条目数为 `B`：

```text
目录枚举：O(D + F + B)，保存足够前沿时 B = 0
名称比较：O(F)
hash 计算：非 hash 形态输入为 0；hash 形态输入最坏 O(F * L)
Resolver 额外内存：O(目录深度 + 有界前沿 + 当前命中项数)
```

算法必须流式工作，不能为了稍后再算 hash 保存整棵树的所有路径。这样才能在 Win32 x86 的有限地址空间中保持有界内存。

## Resolver 结果模型

建议返回结构化结果，而不是 `nil + 字符串`：

| 结果 | 含义 |
| --- | --- |
| `Unique` | 唯一有效候选，附路径、当前 hash 和观察凭据 |
| `AmbiguousName` | 完整扫描的当前最高优先范围有多个可用同名候选 |
| `HashCollision` | 完整扫描的当前最高优先范围有多个可用的相同 hash 候选 |
| `InvalidSelector` | 既不是安全名称，也不是合法 hash token |
| `MatchedUnavailable` | 高优先候选路径存在，但 XML 损坏或不可读 |
| `ScanIncomplete` | 某个应搜索范围不可读，无法证明更高优先候选不存在 |
| `NotFound` | 所有可读范围均无匹配 |

候选建议是：高优先名称存在但 XML 损坏时返回 `MatchedUnavailable`，不能悄悄跳到远处同名会话。这个错误优先级，以及“一个可用候选 + 一个损坏同名候选”等混合状态，仍需和 10、15 号系统共同确认。

Resolver 结束后还有三组不同结果，不能继续塞回 `ResolveResult`：

| 层 | 候选结果 | 含义 |
| --- | --- | --- |
| `ContextTargetVerifier` | `Verified` / `TargetChanged` / `TargetUnavailable` | 扫描后目标是否仍是同一可用文件 |
| `ContextOpenService` | `Opened` / `OpenConflict` / `Incompatible` / `StorageFailure` | 是否成功加载/恢复会话 |
| `ContextMutationService` | `Applied` / `DestinationExists` / `LockConflict` / `StorageFailure` / `Cancelled` | rename/rebind/delete/metadata 修改是否执行及失败原因 |

这样可以明确区分“搜索时没找到”“找到后被外部替换”“打开格式不兼容”和“修改时锁冲突”。最终错误 ID、重试属性和用户文字由 15 号统一错误模型确认。

## “实时索引”的有界快照协议

这里的“快照”不是把整棵 `CONTEXT` 树复制进内存，而是**带范围、惰性加载并受内存预算约束的观察集**：当前目录页、已展开节点和当前搜索结果页各自保留少量候选及其观察凭据。折叠、翻页或超过预算后可以淘汰旧页；任何页都能从文件树重建。

### CLI

- 每条独立命令开始时建立新的瞬时视图。
- 单次解析的多个搜索环共享祖先边界与“已完成子树”规则，不建立全树常驻索引。
- 选出候选后交给 `ContextTargetVerifier`；若扫描期间发生变化，有限重试或返回 `TargetChanged`。
- 命令结束后丢弃快照。

### 交互式浏览器

- 打开浏览器时为当前节点建立带扫描时间的有界页快照，不读取整棵树。
- 展开节点时惰性扫描该节点；折叠、分页、排序和普通搜索可以复用未过期页，避免每次按键访问磁盘。
- 全局搜索流式扫描，只保留有上限的结果页；后续页使用稳定排序游标重新扫描或继续受控扫描，不能把全部命中无限保存在内存。
- `refresh` 显式重扫。
- `select`、`rename`、`rebind`、命名标记修改和 `delete` 在确认前重新校验选中项。
- 修改成功后立即废弃旧快照并刷新受影响范围。
- 浏览器长时间停留时可显示“目录可能已变化”；不依赖 inotify、USN Journal 或 watcher 才能正确工作。

快照复用不违背实时派生，因为它有界、可淘汰且随时可以丢弃，文件树仍是唯一事实源。页大小、最大展开节点数、结果上限、单次扫描 hard cap 和游标格式属于版本化 Runtime/browser 契约；目标旧机复杂度与内存测试把不可放宽的 cap 冻结进发行 manifest，不生成 `MaxScanEntries` INI/XML 字段。浏览器、status 与 self-test 只读显示当前 cap；命中后返回 incomplete/`ScanLimit`，不能把未扫描范围当作不存在。

## 交互式上下文浏览器

### 用户能做什么

- 从当前镜像目录进入子目录、返回上级或回到 `CONTEXT` 根。
- 展开/折叠目录树；plain 模式可以用“进入/返回”代替视觉折叠。
- 查看上下文名称、逻辑路径、当前 hash、更新时间、大小和可用/损坏状态。
- 选择一个上下文并连接。
- 按精确名称、名称前缀、名称包含或逻辑路径包含搜索。
- 输入 16 位 hash 做精确定位。
- 重命名上下文。
- 查看当前 root 与专用 `AutoRenameDisabled` 状态，添加/取消该标记；取消不立即发起命名。
- 通过 self-fix 把 Context rebind 到另一个明确 workspace 的镜像目录；这是移动 XML 的独立动作，不是增加第二 root。
- 删除上下文；软删除还是永久删除尚未确认。
- 手动刷新并查看扫描警告。
- 取消操作并返回原会话，不产生副作用。

### 搜索与排序

首版只做确定性的元数据搜索，不扫描完整消息和工具输出。普通 Context 列表由两个 INI 字段控制：

```ini
[Context]
ListSortBy=updated
ListSortDirection=descending
```

`ListSortBy` 只接受 `created|updated|name`，分别读取 XML header 中 canonical `CreatedAt`、`UpdatedAt`、`Name`；`CreatedAt` 是初次 durable 创建时间，`UpdatedAt` 是最后一次成功发布的 durable XML mutation 时间，inspect/失败尝试不推进。`ListSortDirection` 只接受 `ascending|descending`，默认是 `updated + descending`，即最近更新在前。不得使用文件系统 ctime/mtime、目录枚举顺序或当前 locale/code page 代替这些规范值。主键相同时始终用 canonical `LogicalPath` 的稳定升序作为最终 tie-break；损坏/不可读、无法取得规范排序键的候选必须进入显式状态分组并按 `LogicalPath` 稳定展示，不能伪造时间。

排序只改变列表、浏览器页和搜索同一相关性等级内的展示顺序，不改变 Resolver 的距离优先、同环名称优先于 hash、歧义和碰撞裁决。目录节点仍使用版本化的规范名称/路径稳定顺序；搜索先按匹配类型和范围形成相关性等级，再在同等级应用上述 Context 排序。

完整展示规则为：

1. 目录在前，上下文在后。
2. 普通目录列表按规范名称/路径稳定排序，不依赖文件系统枚举顺序；Context 条目使用 `ListSortBy`/`ListSortDirection`。
3. 搜索结果依次为精确名称、名称前缀、名称包含、逻辑路径包含。
4. 同等级先按搜索范围距离，再按配置的 Context 排序键，最后按规范逻辑路径稳定裁决。
5. hash 搜索只接受精确 16 位 token，不做 hash 前缀。
6. 首版不因模糊拼写结果自动连接；模糊搜索是否作为显示辅助以后决定。

普通搜索只产生候选列表；即使只有一项，也应由用户明确选择。精确 selector 输入则走 Resolver 的正式规则。

### Plain renderer 候选

XP、`TERM=dumb` 和非 raw 终端必须能使用编号与逐行命令完成所有动作：

```text
CONTEXT: /C/Program Files
SNAPSHOT: 2026-07-18 14:30:00

1  [DIR] Common Files
2  [CTX] 我的任务   8A21F5C0...   ready
3  [CTX] 测试任务   19C4B10D...   damaged

open 1
select 2
search 我的
rename 2 新名称
delete 2
up
root
refresh
quit
```

具体命令词、分页和确认提示尚未确认；示例只证明不依赖 ANSI、方向键、鼠标或全屏也能完成目录树访问、搜索和管理。

### Enhanced renderer 候选

增强模式可以增加方向键、可折叠树、颜色和详情面板，但只能把输入翻译为与 plain 模式相同的控制器动作。任何增强能力失效后都能回退到 plain，不改变选择、重命名、删除和错误语义。

## 重命名、删除与并发安全

目录展示到用户确认之间，目标可能被另一个 yaca 或外部程序修改。所有破坏性操作建议遵守：

```text
选中候选
-> 展示完整逻辑路径、当前 hash 和操作
-> 用户确认
-> 验证仍在 CONTEXT 根内
-> 重新打开并核对观察凭据
-> 取得上下文操作锁/lease
-> 再次确认目标与目的路径
-> 执行
-> 更新句柄/废弃快照/刷新
```

### 初始名称与周期命名

新 Context 第一次落盘时使用 ASCII basename `Untitled Conversation [XXXX]`，其中 `XXXX` 为四位大写十六进制随机短标签。它只负责产生简洁的碰撞候选：平台层取得安全随机 bytes，编码后直接尝试 `publish_new_no_replace`；碰撞就在固定 hard cap 内重新生成，不能用 `math.random`、时间/PID 或“先 exists 后普通 rename”作为正确性保证。随机源失败或重试耗尽时 Context 创建失败，绝不覆盖旧 XML。

周期自动命名成功时复用下面的 rename transaction；因此逻辑路径、当前 16 位 hash、活动句柄和 Catalog 快照一起改变，旧 hash 立即失效。后台请求失败、取消、进程退出或迟到结果不改变名称。只有 `AutoNameEveryMainTurns>0`、已经 durable 收口的 main-turn 水位达到下一周期，且当前 XML metadata 的 `AutoRenameDisabled` 缺失/`false` 时才具备 admission 资格；`true` 直接跳过。把 marker 从 `true` 取消时，以取消时的 durable 水位建立新 baseline：不立即命名、不补发 marker 生效期间错过的请求，也不把旧累计 turn 带入新周期。添加 marker 或手工 rename 将其置为 `true` 时，已经在途的命名 request 取消/逻辑失效；迟到结果不得再进入 rename transaction。

四位 tag 不单独作为 XML identity 或 Resolver key。Context 的唯一动态地址仍是完整逻辑 XML 路径及其实时 16 位 hash。

### 重命名

首版候选是只改变同一镜像目录下的 basename，不同时移动关联工作目录：

```text
重新校验 -> 取得修改锁
-> 构建并验证完整 XML generation：Name=<new basename>,
   UpdatedAt=<commit time>, CreatedAt=<unchanged>, marker=<manual/auto rule>
-> publish/move_no_replace -> 更新活动句柄
-> 从新逻辑路径计算新 hash -> 刷新
```

- `move_no_replace` 必须在非协作程序竞态下也不覆盖已有目标；“检查后普通 rename”不满足契约。若平台只能用多步恢复协议，崩溃后必须能识别并收口双路径状态。
- 成功后旧 hash 立即失效，新 hash 立即出现在 `.status` 和浏览器中。
- 失败时文件仍在旧路径，运行时句柄和旧 hash 不提前变化。
- 如果操作开始前目标已经被替换，返回冲突并要求刷新；不得用原名称重新解析后误改另一个文件。
- 手工 rename 成功的默认事务把 canonical `Name`、`UpdatedAt` 与 `AutoRenameDisabled=true` 一起发布；自动 rename 同样原子发布 `Name`、`UpdatedAt` 与新路径，但保持 marker 缺失/`false`，绝不创建禁用标记。两者都保持 `CreatedAt` 不变；路径移动或任一 metadata 提交失败时全部保持旧值，不得对外声称完成。

### Rebind

rebind 不在 XML 内修改一个 root/workdir 字段，而是由 context-repl 在同一可恢复管理事务中追加 rebind 历史事件、原子推进 `UpdatedAt`，并把完整 XML generation 发布到目标 workspace 对应的镜像父目录；`CreatedAt` 不变。它复用 TargetVerifier、操作锁、no-replace 与可恢复发布协议；目标根必须可由同一 LogicalPathCodec 双向无损转换。只有事件、metadata 与目标路径全部成功发布，活动句柄、逻辑路径和 hash 才一起更新，旧 hash 失效；失败/崩溃/inspect 不推进 `UpdatedAt`，并按恢复协议收口为唯一可证明位置。XML 中的 rebind 记录和历史工具 cwd 只供审计，不反向覆盖当前父目录派生 root。

### 删除

删除动作已确认必须存在，但以下语义尚未确认：

- 默认移动到不参与 Resolver 扫描的回收区，还是直接永久删除。
- 删除当前已连接会话后立即结束、建立新会话，还是保留只读视图。
- 回收区保留期、恢复和彻底清除命令。

无论最终选择哪种方式，都必须显示完整目标、明确确认、最终复核，并保证损坏或过期快照不会指向另一个文件。当前推荐软删除，永久清除作为另一项明确操作，但这不是已确认决定。

## Self-Test Stage 1 的 Catalog 检查

Stage 1 不调用 Model。它使用与正常 Resolver/Browser 相同的 `LogicalPathCodec`、scanner 与发行 hard cap，至少检查：镜像路径能否无损解码为唯一可进入的 workspace root；XML header 与 basename、canonical `Name/CreatedAt/UpdatedAt` 是否一致且可解析；临时/恢复文件是否被正确排除；目录不可读、损坏候选、失效 root 和扫描中变化是否形成 typed partial result。

Stage 1 还必须报告 Catalog 数量、实际扫描范围、hash 计算数、耗时、是否触及页/扫描 hard cap，以及明显超过最低平台预算的目录或 Context。遇到 `ScanIncomplete`/`ScanLimit` 时只能报告“检查不完整”和未覆盖范围，不能声称整个 Catalog 健康；self-test 只诊断并给出 context-repl self-fix 入口，不在扫描时重命名、rebind、删除或修改 marker。

## 旧 Windows/Linux 约束

- Windows 枚举与路径访问需要能正确处理 XP 上的 Unicode 路径，不能依赖当前 ANSI 代码页碰运气。
- 程序生成的初始 basename、协议键和 UI chrome 使用 ASCII；用户手工名称、路径和内容仍是 UTF-8。XP launcher/console/filesystem 使用宽字符 API，控制台无法显示时只做 ASCII escape/编号展示，不能把展示串送回路径、Resolver、审批或 hash。
- 不依赖 PowerShell、现代搜索 API、USN Journal、inotify、SQLite 或守护进程。
- Win32 x86 中使用流式目录栈和小型命中集合，禁止无界加载全树或完整 XML。
- 默认不跟随 symlink、junction 或 reparse point 是当前安全建议，以避免循环和逃出根目录；最终规则待路径问题确认。
- CentOS 7 的大小写与可能的非 UTF-8 文件名、Windows 的大小写不敏感和保留名不能由业务层自行猜测。
- 临时写文件必须使用不会被 Scanner 当成已提交 XML 的名称/后缀。
- no-replace 发布/移动、原子替换、文件标识和锁的能力差异由 01、10 号系统提供显式能力，不假设所有平台相同。

## 设计不变量

- 相同文件树、起点和选择器得到与目录枚举顺序无关的结果。
- 非 16 位选择器不计算候选 hash。
- hash 永远从候选的当前规范逻辑路径计算。
- 重命名成功后旧 hash 不再解析到新文件。
- 所有 selector 入口共享一套范围和歧义规则。
- `.status` 不为显示当前 hash 扫描全局树。
- 浏览器选中项在修改前重新校验，不能“看见 A、最后操作 B”。
- 原生快捷键路径与逐行文本后备对相同语义动作产生相同结果。
- 一次解析中每个 XML 候选至多在一个搜索环中做有效性探测和名称/hash 匹配；边界目录项是否因内存约束再次枚举不影响结果。

## 测试重点

- 当前目录名称、16 位名称、当前目录 hash、外层名称和外层 hash 的组合优先级。
- 同一范围同名、名称/hash 交叉冲突和人工制造的 hash 碰撞。
- 打乱目录枚举顺序后结果完全一致。
- 非 hash 输入零次 hash 计算；每个 XML 在一次解析中最多探测并匹配一次。
- 当前目录唯一名称可直接命中，不触发全树扫描。
- 大型目录树使用流式内存上限，适配 Win32 x86。
- rename 后 `.status` 显示新 hash，旧 hash 无法连接。
- 扫描与确认之间替换、移动或删除文件时安全失败。
- 不可读目录、损坏 XML、临时文件、回收区和链接循环。
- 浏览器选择、目录导航、搜索、刷新、取消、重命名和删除确认。
- `created|updated|name` 与正序/倒序的六种组合只读取 XML canonical metadata；相同主键始终以 `LogicalPath` 稳定收口，打乱目录枚举和文件系统时间不改变结果。
- 活动 writer 存在时，TUI 与 CLI/context-repl 的 rename、rebind、delete、marker 修改都得到相同 `LockConflict`，释放后同一 semantic action 才可成功。
- marker 取消以当前 durable 水位建立新 baseline；没有立即请求、历史追赶或重启补跑。
- Stage 1 在缺失 root、大量 Context、慢目录、hash 预算和扫描 hard cap 下如实报告 partial/slow，不越界修复。
- 有界页/全局搜索在巨大目录树下不保存全部候选，翻页结果仍按稳定游标确定。
- 原生快捷键路径与逐行文本后备对同一动作脚本得到相同控制器结果。
- Windows XP x86 与 CentOS 7 上验证 CJK、大小写、路径边界、no-replace 移动和崩溃恢复差异。

## 待逐项确认的决策

1. `AmbiguousName` 在非交互命令中的候选输出，以及交互浏览器是否允许用户从候选中选择。
2. hash 的算法、编码、16 位字母表、大小写和 `HashCollision` 的候选显示。
3. 显式 `name:`、`hash:`、`path:` 前缀已由项目负责人排除；仍需冻结同名/hash 碰撞候选页和非交互错误格式。
4. Windows/Linux 路径规范化、UNC、根目录、链接、Unicode 与非法名称。
5. 损坏但名称匹配的 XML 是否阻止继续搜索。
6. 重命名是否只允许改变 basename；跨目录移动是否是另一个动作。
7. 删除默认软删除还是永久删除，以及当前会话被删除后的状态。
8. 浏览器普通搜索的默认范围、是否显示损坏 XML、是否提供模糊搜索。
9. 活动 XML 被外部移动/删除时是否立即进入失效状态并要求重新连接。

## 当前讨论入口

Q-015 已确认统一 Resolver 的范围、裁决与最低遍历算法。下一步继续确认同环歧义、路径规范化、浏览器修改语义与上下文 XML 内容。
