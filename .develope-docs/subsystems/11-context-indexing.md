# 11 上下文定位、实时索引与交互式浏览器

更新日期：2026-08-10

状态：**计划已确认（C16/C18）** — SHA-256 first-8/network-order hash、LogicalPath/path/selector vectors、Resolver 与 **显示≠hash** 已机器冻结；target identity/filesystem/cap 仍是 M5 hard gate

## 为什么这是一个独立子系统

上下文 XML 的内容由 10 号存储系统负责，但“用户给出一个名称或 hash 后，到底连接哪个 XML”是另一类问题。它同时涉及路径映射、实时目录扫描、搜索范围、歧义、重命名后的身份变化、CLI/TUI 一致性和旧系统性能，不能散落在各条命令里分别实现。

本系统建立一个统一的上下文目录与定位服务，供 `continue`、context-select、重命名、删除、列表、浏览器和后续带上下文选择器的 semantic actions 共同使用；CLI、TUI 和点命令的投影统一来自 13 号 action registry。

## 命名说明

项目负责人本轮提出的“交互式配置浏览器”包含选择、重命名、删除、目录树访问和搜索。按操作对象判断，本文件把它定义为**交互式上下文浏览器/管理器**：它浏览的是 `CONTEXT` 树，不是 `config.ini` 的配置项。

真正的配置浏览器属于 05 号配置系统，负责查看和修改配置键，不应拥有重命名或删除上下文的业务权限。如果项目负责人所说的“配置浏览器”确实还包括另一套配置项树界面，应在 05 号文档中单独设计，不能把两类数据混在同一个控制器里。

## 职责

- 在 `__yaca__/CONTEXT/` 镜像树中枚举当前有效的上下文 XML。
- 把工作目录、物理 XML 路径和规范逻辑路径相互转换。
- 根据当前逻辑路径实时计算固定 16 位 hash。
- 以统一规则解析名称/hash 选择器，并报告唯一命中、歧义、碰撞、不完整扫描或未找到。
- 为 `recent` 快速列表和 `full` 完整目录树两个浏览器入口提供查看、搜索、排序、选择和刷新语义。
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

逻辑路径带前导 `/`、统一使用 `/` 分隔，并包含当前上下文名称和 `.xml`。双引号不属于输入。

**用户可见 hash（D-059 / SQ-01 = B）：**

- 固定 **16** 位；
- 字母表 **`0-9A-F`（大写十六进制）**；
- 所有面向用户的显示输出大写；
- 输入侧：长度 16 且字符属于 `0-9A-Fa-f` 时视为 hash token，先规范化为大写再匹配；否则整段按精确名称处理；
- 不得截断、补齐或把非 16 位串强行当 hash。

从逻辑路径到 16 位 hex 的摘要算法与字节编码仍待技术证明；碰撞概率分析随算法证据给出。碰撞呈现与损坏近处同名策略见 SQ-02/SQ-03。

### 没有永久 ContextId

- XML 内不另存一个跨重命名保持不变的永久 `ContextId`、UUID 或隐藏主键。
- 当前逻辑 XML 路径就是当前地址；16 位 hash 是该地址的运行时短表示。
- 重命名或移动导致逻辑路径变化时，立即从新路径计算新 hash。
- 旧 hash 随即失效，不自动保留为历史别名，也不能继续连接新文件。
- hash 不是可跨重命名引用的永久外键。日志可以把当时的路径/hash 保存为历史快照，但不能据此假装它以后仍指向同一个文件。
- 单个 XML 内的 turn、message、tool call 等关系仍可拥有局部序号或事件 ID；这属于 10 号 schema，不等于为上下文恢复永久身份。

由 yaca 自己执行重命名时，可以在成功后把当前运行时句柄更新到新路径。若外部程序移动、删除、替换或改写活动 XML，当前句柄必须立即标记为 stale 并 fail-stop；程序停止新的模型请求、工具和 XML 提交，不能按名称、hash 或内容猜测哪个文件是原会话。用户只能显式 refresh/self-fix/rebind/recovery/exit，取得新快照和必要锁后再继续。

### 实时派生

- `CONTEXT` 中当前存在的已提交 XML 文件树是目录和 hash 查找的事实源。
- 列表与 hash 查找不能要求先存在永久索引文件或数据库。
- 任何缓存都只能是可丢弃的派生数据，不能代替当前 XML 树成为事实源。

一次操作内的瞬时快照、浏览器复用和最终重新校验是本文件的当前推荐架构，不是已经确认的缓存刷新细则；完整协议见后文“实时索引的快照协议”。

### 动态地址的统一使用

- `continue(selector)` 等所有接受上下文选择器的 semantic actions 必须使用同一个解析器。
- 重命名、删除等接受选择器的命令也使用相同搜索范围和消歧规则，不能各自实现一份近似逻辑。
- `.status` 根据当前运行时绑定的逻辑路径直接计算当前 hash，不通过全树搜索寻找自己。
- Resolver 已确认距离优先；短名首个可用命中（D-061）；hash 精准且同环须唯一性证明（D-059/D-061）。

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
- 排除临时写入、恢复中间产物和非已提交文件；v0.1 不建立 Context 回收区。
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

- 接受必选初始 view `recent|full`：`recent` 直接产生快速最近列表，`full` 产生完整目录树/全部 Context；二者只改变初始投影，不建立两套 Catalog 或 mutation 服务。
- 保存当前 view、目录节点、展开状态、搜索条件、排序、分页/选择和待确认动作。
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
| 列表枚举 | `context-list(scope)`、`context-repl(recent|full)` | 取得 Catalog 快照，不把列表每一项再解析一次 |
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

## 名称与 hash 分流（D-061）

| 输入形态 | 用途 | 收口规则 |
| --- | --- | --- |
| **短名**（非 hash token） | 便捷；不承诺唯一 | 由近到远；环内按 `LogicalPath` 升序；**首个可用** 精确名称命中即返回；无 `AmbiguousName` |
| **hash**（16 位，D-059） | **精准指定** | 当前环完成 hash 唯一性扫描；唯一可用则返回；多可用相同 hash → `HashCollision`；禁止裸枚举“第一个 hash 就返回” |

- hash 输入 = **整条逻辑路径** 一次摘要（层级合并后的路径串），不是 basename alone。  
- 跨目录可以有相同显示名；身份与精准选择靠 **路径 → hash**。  
- 浏览器选中一行仍直接携带候选，不按短名重搜（既有规则）。

## 已确认的解析流程（D-061）

```text
resolve(selector, origin):
    if selector 是 hash token (D-059):
        for ring in 由近到远:
            hash_hits = []
            ring_complete = true
            按 LogicalPath 升序流式遍历 ring 内候选:
                计算逻辑路径 hash；收集相等命中及可用性
                目录不可读 -> ring_complete = false
            if not ring_complete: return ScanIncomplete
            if 多个可用相同 hash: return HashCollision
            if 恰好一个可用: return Unique
            if 有命中但均不可用: return MatchedUnavailable  # 或与 15 号统一的不可用映射
            # 无命中 -> 下一 ring
        return NotFound

    else:  # 短名
        for ring in 由近到远:
            按 LogicalPath 升序流式遍历 ring 内候选:
                if 精确名称匹配:
                    if 可用: return Unique          # 首个可用命中，立即停止
                    else: return MatchedUnavailable # D-060：不跳过损坏改连更远同名
                目录不可读 -> 本环无法证明时 return ScanIncomplete
        return NotFound
```

重要约束：

- **距离优先** 仍是第一层：近环先于远环。  
- **短名首个可用命中即停**（D-061）；不要求同环名称唯一；**不** 产生短名歧义选择页。  
- 环内顺序必须是稳定 **`LogicalPath` 升序**，禁止把 OS 目录枚举抖动当成产品语义。  
- **D-060：** 按该顺序遇到的第一个精确名称候选若不可用 → `MatchedUnavailable`，禁止跳过改连更远同名可用项。  
- **hash：** 当前环必须完成唯一性所需观察；唯一可用才返回；`HashCollision` fail-closed；更远环不能推翻近环已裁决的唯一 hash。  
- hash 形态判定使用 D-059；非 hash 输入不计算候选 hash。  
- 每个 XML 候选在一次解析中最多一次有效性探测与匹配。

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
| `Unique` | 已解析到一个可用候选（短名首个可用命中，或唯一可用 hash），附路径与当前 hash |
| `HashCollision` | 当前完整环内多个可用候选具有相同 hash（精准路径的安全网） |
| `InvalidSelector` | 既不是安全名称，也不是合法 hash token |
| `MatchedUnavailable` | 按短名顺序将命中的第一个精确名称候选存在但不可用（D-060）；或 hash 命中均不可用 |
| `ScanIncomplete` | 某个应搜索范围不可读，无法完成该形态所需证明 |
| `NotFound` | 所有可读范围均无匹配 |

**已确认：**

- D-060：短名下第一个名称候选不可用 → `MatchedUnavailable`，不跳远处同名。  
- D-061：短名 **无** `AmbiguousName`；精准靠 hash。  
- `AmbiguousName` 不再作为 v0.1 短名解析的正式结果（历史文档若仍出现，视为已取代）。  
- 15 号负责稳定 error ID 与用户文案映射。

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

- `recent` 入口直接为按配置排序的最近 Context 建立快速有界页，不先绘制或物化完整目录树；`full` 入口从 `CONTEXT` 根建立完整目录树/全部 Context 的惰性视图。两者共用后续查看、搜索和 mutation controller actions。
- 打开浏览器时为当前 view/node 建立带扫描时间的有界页快照，不把整棵树无界载入内存。
- 展开节点时惰性扫描该节点；折叠、分页、排序和普通搜索可以复用未过期页，避免每次按键访问磁盘。
- 全局搜索流式扫描，只保留有上限的结果页；后续页使用稳定排序游标重新扫描或继续受控扫描，不能把全部命中无限保存在内存。
- `refresh` 显式重扫。
- `select`、`rename`、`rebind`、命名标记修改和 `delete` 在确认前重新校验选中项。
- 修改成功后立即废弃旧快照并刷新受影响范围。
- 浏览器长时间停留时可显示“目录可能已变化”；不依赖 inotify、USN Journal 或 watcher 才能正确工作。

快照复用不违背实时派生，因为它有界、可淘汰且随时可以丢弃，文件树仍是唯一事实源。页大小、最大展开节点数、结果上限、单次扫描 hard cap 和游标格式属于版本化 Runtime/browser 契约；目标旧机复杂度与内存测试把不可放宽的 cap 冻结进发行 manifest，不生成 `MaxScanEntries` INI/XML 字段。浏览器、status 与 self-test 只读显示当前 cap；命中后返回 incomplete/`ScanLimit`，不能把未扫描范围当作不存在。

## 交互式上下文浏览器

### 两个明确入口

`context-repl` 必须显式选择一个入口：

- `recent`：快速打开最近 Context 列表。它按下面已经确认的 Context 排序配置投影最近页，不展示目录树，也不改变裸 `yaca` 的启动路线。
- `full`：打开 `CONTEXT` 的完整目录树/全部 Context。实现仍按目录/页惰性扫描并服从发行 hard cap；“完整”表示这是覆盖全部 Catalog 的正式入口，不允许静默只看工作区或 recent 子集。

两个入口进入同一个 `ContextBrowserController`，都能查看详情、搜索、选择连接、重命名、rebind、管理 `AutoRenameDisabled`、永久删除和刷新。入口只决定初始视图，Resolver、TargetVerifier、锁、确认与写入规则完全相同。普通 `yaca`/`yaca .` 不调用任何一个入口，不扫描 Catalog，也不提示 recent Context；只有用户显式调用 context action 才访问历史。

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
- 永久删除上下文；不提供软删除、trash 或 restore。
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

排序只改变列表、浏览器页和搜索同一相关性等级内的展示顺序，不改变 Resolver 的距离优先、短名首个可用命中与 hash 唯一性裁决（D-061）。目录节点仍使用版本化的规范名称/路径稳定顺序；搜索先按匹配类型和范围形成相关性等级，再在同等级应用上述 Context 排序。

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

v0.1 的 `delete` 是直接、不可恢复的永久删除；不建立回收区，不注册 soft-delete、trash、restore 或 empty-trash action。删除前必须显示完整逻辑路径、当前 16 位 hash 和明确的 permanent warning，取得用户确认后再由 `ContextTargetVerifier` 重新校验并取得修改锁。损坏或过期快照不能指向另一个文件；目标已变化就失败并要求刷新。

活动 Context 持有 writer lock，因此另一个管理入口不能删除它；返回 typed `LockConflict`，不提供按锁龄强制解锁。成功删除后立即废弃相关快照，后续名称/hash 查找不再命中。发布、崩溃和文件系统错误怎样证明“已删除/未删除/结果未知”由 10 号存储协议收口，但不能用隐藏 trash 冒充永久删除。

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
- 不可读目录、损坏 XML、临时/恢复中间文件和链接循环；确认不存在可触发的 trash/restore 表面。
- 浏览器选择、目录导航、搜索、刷新、取消、重命名和删除确认。
- `created|updated|name` 与正序/倒序的六种组合只读取 XML canonical metadata；相同主键始终以 `LogicalPath` 稳定收口，打乱目录枚举和文件系统时间不改变结果。
- 活动 writer 存在时，TUI 与 CLI/context-repl 的 rename、rebind、delete、marker 修改都得到相同 `LockConflict`，释放后同一 semantic action 才可成功。
- marker 取消以当前 durable 水位建立新 baseline；没有立即请求、历史追赶或重启补跑。
- Stage 1 在缺失 root、大量 Context、慢目录、hash 预算和扫描 hard cap 下如实报告 partial/slow，不越界修复。
- 有界页/全局搜索在巨大目录树下不保存全部候选，翻页结果仍按稳定游标确定。
- 原生快捷键路径与逐行文本后备对同一动作脚本得到相同控制器结果。
- Windows XP x86 与 CentOS 7 上验证 CJK、大小写、路径边界、no-replace 移动和崩溃恢复差异。

## 待逐项确认的决策

1. （已取代）短名 `AmbiguousName` 选择页——D-061 改为首个可用命中；精准用 hash。HashCollision 的非交互错误格式仍由 13/15 号冻结文案。
2. hash 的算法、编码、16 位字母表、大小写和 `HashCollision` 的候选显示。
3. 显式 `name:`、`hash:`、`path:` 前缀已由项目负责人排除；仍需冻结同名/hash 碰撞候选页和非交互错误格式。
4. Windows/Linux 路径规范化、UNC、根目录、链接、Unicode 与非法名称。
5. 损坏但名称匹配的 XML 是否阻止继续搜索。
6. 重命名是否只允许改变 basename；跨目录移动是否是另一个动作。
7. 浏览器普通搜索在 `recent` 初始视图中的精确默认范围、是否显示损坏 XML、是否提供模糊搜索。

## 当前讨论入口

Q-015 已确认统一 Resolver 的范围、裁决与最低遍历算法，D-053 已确认 recent/full、永久删除和活动 XML 外改后的 stale fail-stop。**W3-B 已冻结** LogicalPathCodec、hash 与 display 规则；下列历史“待确认”项状态更新见文末完成度。

---

## W3-B：LogicalPathCodec、hash 与显示路径（规范）

对齐：D-022、D-023、D-024、D-059、D-060、D-061、**D-070**；AR-P0-11。

### 核心不变量（D-070）

| 概念 | 定义 | 用于 |
| --- | --- | --- |
| **DisplayPath** | 面向用户的本机友好路径（可保留 `C:\...`、`\\server\share`、POSIX 原貌） | TUI/列表/错误展示、复制给用户 |
| **LogicalPath** | 规范化、可跨平台比较的逻辑路径字符串 | **hash 输入**、Resolver 排序 tie-break、镜像树定位 |
| 关系 | DisplayPath **不得** 单独充当 hash 输入；用户抄显示路径若需精确命中，应用 hash 或精确 Name | 文档/help 必须写明「显示 ≠ hash 输入」 |

### LogicalPath 规范算法（Context XML 在 `CONTEXT` 树内）

输入：XML 文件相对 `CONTEXT` 根的位置（已通过 fs 打开的真实项，非用户自由文本猜路径）。

| 步骤 | 规则 |
| --- | --- |
| 1. 分隔 | 统一为 `/`；去掉多余连续 `/` |
| 2. 前导 | **始终** 以 `/` 开头（例如 `/C/Program Files/task.xml`） |
| 3. `.` / `..` | 解析时折叠；越出 `CONTEXT` 根 → 无效 |
| 4. 段字符 | 保留 Unicode 段原文（NFC 规范化优先；无法 NFC 则按 UTF-8 原字节稳定） |
| 5. Windows 盘符 | `C:\foo` 镜像 → 段 `C`（单字母盘）+ 其余段；**不** 保留冒号 |
| 6. UNC | `\\server\share\a` → `/UNC/server/share/a` 形式（固定前缀 `UNC`） |
| 7. 大小写 | LogicalPath **保留** 文件系统呈现的大小写用于显示映射；**比较** 在 Windows 上对路径段使用 case-insensitive 等价（实现：比较键另存），hash **输入字节** 固定为 UTF-8 LogicalPath 规范串（见下） |
| 8. 尾 | 文件名含扩展名；目录段无尾 `/`（根除外概念上只有前导 `/`） |

**hash 输入字节**：`UTF-8(LogicalPath 规范串)` 的完整字节序列（含文件名）。  
**hash 输出**：固定 **16** 位大写十六进制 `0-9A-F`（D-059）；算法实现为可版本化 digest（发行锁定一种，如截断的 SHA-256 前 64 bit 的 hex 大写——**具体密码学原语 TP 冻结**，用户可见长度/字母表不变）。

### 用户可见 vs 机器

| 场景 | 展示 | 机器 |
| --- | --- | --- |
| `.status` | DisplayPath + 16 位 hash | hash 由 LogicalPath 重算 |
| 列表排序 tie-break | 可显示 DisplayPath | 排序键 = LogicalPath 升序 |
| 选择器 hash 形态 | 用户输入 16 hex（大小写不敏感输入→大写比较） | 与候选 LogicalPath 的 hash 比 |
| 选择器名称 | 精确 basename/Name | **不** 用 DisplayPath 模糊匹配 |
| symlink/junction | 显示可提示 link | LogicalPath 以 **打开后 identity** 解析的最终树位置为准；无法证明 → `Unverifiable` / 不可用 |

### Hash 向量（验收形状，非完整 corpus）

| # | LogicalPath | 说明 |
| --- | --- | --- |
| V1 | `/C/work/a.xml` | 基本盘符 |
| V2 | `/C/work/A.xml` | 与 V1 不同字节 → **不同 hash**（即便 Windows 上可能同文件，规范串不同则 hash 不同；打开后 identity 另核） |
| V3 | `/home/u/proj/t.xml` | Linux |
| V4 | `/UNC/server/share/t.xml` | UNC |
| V5 | 重命名 basename | hash **变**；旧 hash NotFound |
| V6 | rebind 换父目录 | LogicalPath 与 hash **变**；旧 approval 快照 stale |

### Resolver 结果 schema（机读字段）

```text
ResolveResult =
  | { tag: Unique, logical_path, display_path, hash, physical_hint? }
  | { tag: HashCollision, candidates: [{logical_path, hash}, ...] }  -- 有界
  | { tag: InvalidSelector, reason }
  | { tag: MatchedUnavailable, logical_path?, reason }   -- D-060
  | { tag: ScanIncomplete, scope, reason }
  | { tag: NotFound }
```

短名：**无** `AmbiguousName`（D-061）。  
后续层：`TargetVerifier` / `OpenService` / `MutationService` 结果不得塞回本 schema。

### 备选否决

| 方案 | 否决 |
| --- | --- |
| 显示路径直接 hash | D-070；跨机/盘符漂移 |
| 双 hash（显示+逻辑） | 复杂度与用户困惑 |
| 永久 ContextId | D-023 排除 |

### 历史“待确认”收口

| 原项 | W3-B 状态 |
| --- | --- |
| hash 字母表/大小写 | D-059 + 上表 |
| 损坏近处同名 | D-060 MatchedUnavailable |
| 短名歧义页 | D-061 取消 |
| 路径规范化 | LogicalPathCodec 上表 |
| basename rename vs rebind | rename=basename；跨目录=rebind 独立动作（既有） |

### 完成度（W3-B）

- [x] DisplayPath vs LogicalPath  
- [x] Codec 步骤与 hash 输入  
- [x] Resolver 结果 schema  
- [ ] 密码学原语最终选型与跨 OS golden 文件（TP）  
