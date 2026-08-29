# 01 平台兼容抽象

更新日期：2026-08-29

状态：**W3-A 规格侧已冻结** — 窄端口 ABI、safe-load、target identity 与 lock 边界已投影到 [`contracts/platform.lua`](../contracts/platform.lua)；目标机数值与 XP 原语证明仍属 TP

## 职责

规定所有平台相关能力的依赖方向，让配置、会话、上下文和 Agent 核心不直接依赖 Windows/Linux 细节。平台层提供操作系统事实与窄能力接口，但不吞并进程、网络和 TUI 的业务职责。

## 已确认约束

- Windows 有 Win32 x86 与 Win64 x86_64 两个独立发布物。Win32 覆盖 XP SP3 至 Windows 11；Win64 覆盖 Windows 7 SP1 至 Windows 11。
- 两种 Windows 架构与全部受支持版本共用核心代码和接口，不在业务层堆叠版本判断。
- Linux 以 CentOS 7 的旧环境约束为兼容基线。
- 不承诺旧 macOS，也不为其建立专用适配器。
- 不发布 ARM 或其他未确认的 OS/架构适配器。
- 只使用 Lua 5.5 和项目自带能力，不引入平台框架。

## 应隔离的平台事实

- OS 与 CPU 架构识别。
- 路径语法、当前目录、环境变量和临时目录。
- 文件系统能力、权限与原子替换能力。
- 控制台代码页、locale、换行和终端能力。
- 时钟、随机临时名和进程级限制。

进程启动属于 02 号系统，HTTP 传输属于 03 号系统，界面绘制属于 14 号系统；它们使用平台层的事实，但不被塞进一个巨大平台模块。

## 方案比较

### A. 多个窄模块与显式依赖（已选择）

`main.lua` 是组合入口。高层模块只接收自己需要的接口；例如上下文只依赖路径与文件系统，模型只依赖网络传输，TUI 只依赖终端能力与输入输出。

候选模块边界：

- `platform.lua`：只返回规范化 OS、架构和目标身份，不执行平台操作，也不汇总其他子系统的能力。
- `path.lua`：纯路径运算，不读写文件。
- `fs.lua`：文件与目录操作、原子替换。
- `text.lua`：UTF-8、控制台编码、换行与安全截断。
- `clock.lua`：时间与单调计时能力；如无法可靠提供则显式降级。
- 02/03/14 号系统分别提供 process、network、terminal/TUI 接口。

优点是边界清楚、可独立测试、旧平台差异不会扩散；代价是需要明确接口与组合代码。

### B. 统一 `platform` 大门面

调用方统一使用 `platform.fs`、`platform.process`、`platform.network`、`platform.terminal`。开始时文件较少，但平台模块会快速成为全局依赖，产生循环依赖和难以替换的“大对象”。

### C. 各业务模块内部判断平台

每个模块自行检查路径分隔符、环境变量或 Windows 版本。短期直接，长期会让兼容规则重复且互相矛盾，不适合 XP 至现代系统的跨度。

## 已确认依赖方向

```text
main（组合）
  -> CLI / TUI 适配器
  -> Agent / Context / Config 应用核心
  -> path / fs / text / clock 等窄接口
  -> Windows x86 / Windows x86_64 / Linux x86_64 的具体实现
```

依赖只向下。底层模块不能反向读取会话、配置或 TUI 状态；配置值由组合入口验证后显式传入使用者。

## 具体实现选择方案

总体依赖方向确认后，还需要决定 Windows/Linux 后端由谁选择。

### A. 组合入口显式选择并注入（已选择）

`main.lua` 先取得不可变的平台描述，再以字面量 `require` 选择 Windows 或 Linux 的具体能力模块，最后把 `path`、`fs`、`text`、`clock` 等接口分别传入需要它们的高层对象。

优点：

- 依赖完全可见，测试可以注入内存文件系统、假时钟等替身。
- 业务模块不触发平台探测，也不会在加载阶段产生隐式副作用。
- 所有平台分支集中在组合入口附近。
- 字面量 `require` 能被 luainstaller 的静态依赖发现识别。

代价是 `main.lua` 需要少量明确的组合代码，但这正是组合入口的职责。

### B. 公共模块内部自动选择后端

例如 `fs.lua` 加载时检测系统并选择 `fs_windows` 或 `fs_linux`。调用更短，但选择过程隐藏在模块加载中，测试替换困难，也容易让多个模块重复探测平台。

### C. 每次调用时判断平台

每个函数内部根据当前 OS 分支。没有额外组合代码，但平台判断散落在热路径中，最难审计和测试。

## 分平台发行与 Lua 入口

Windows x86、Windows x86_64 与 Linux x86_64 分别在目标平台由 luainstaller 原生打包。分目标发行不必等于分裂应用入口，仍需选择源代码组织方式。

### A. 共用 `main.lua`，分平台原生打包（已选择）

三个发行包使用同一份 `main.lua` 和业务源码。`main.lua` 根据实际平台选择后端，luainstaller 为 Win32 x86、Win64 x86_64 和 Linux x86_64 分别生成对应 launcher、Lua runtime 和原生产物；外层发布装配加入各自的工具资源。

为了让 luainstaller 静态发现依赖，平台后端使用字面量 `require`。因此两个很小的纯 Lua 后端可能都被嵌入 launcher，但运行时只实例化目标后端；另一平台的外部工具、DLL、共享库绝不进入发行包。

优点是入口和启动语义唯一，不会出现 Windows/Linux 功能漂移。少量未使用的纯 Lua 后端代码是可以接受的体积换一致性。

### B. `main_windows.lua` 与 `main_linux.lua`

每个入口只加载自己的后端，包内容更纯，但会形成两个组合入口。任何新增服务都必须同步修改两个文件，容易发生启动顺序和默认值漂移。

### C. 构建时生成平台专用入口

模板生成单一平台入口，兼顾包内容与统一逻辑，但引入生成步骤、模板与构建状态，增加当前阶段不需要的复杂度。

## `platform.lua` 身份契约方案

统一入口确认后，需要限制 `platform.lua` 的职责，避免它重新长成 platform 大门面。

### A. 最小不可变身份（已选择）

启动时只产生一次平台描述，包含：

- `os`：`windows` 或 `linux`。
- `arch`：`x86` 或 `x86_64`。
- `target`：规范化组合，只允许当前三个发行目标：`windows-x86`、`windows-x86_64`、`linux-x86_64`。
- `supported`：该 OS/架构组合是否属于本发行版允许的目标。

平台描述创建后不可修改。操作系统具体版本可以由诊断系统读取并记录，但不能作为业务模块的平台分支依据。

文件系统、进程、网络和终端能力分别由对应适配器报告，例如 `fs.capabilities()`、`process.capabilities()` 和 `terminal.capabilities()`；它们不集中塞进 `platform.lua`。

### B. 集中能力表

`platform.lua` 同时返回文件系统、进程、网络、编码和终端的全部能力。查询方便，但会重新形成统一 platform 大门面，而且任何子系统变化都会修改平台契约。

### C. 只返回原始系统字符串

直接暴露未经规范化的 OS 名称、版本和环境变量，让调用方自行判断。实现最少，但上层会重新出现字符串比较和版本分支。

## 推荐约束

- 身份用于选择后端与拒绝不支持的发行包/运行环境组合。
- 能力用于决定某个适配器如何降级，不用于改变 Agent 业务语义。
- OS 版本只进入诊断和测试证据，不成为业务逻辑条件。

## 可执行文件目录与数据根

平台层必须提供可靠的可执行文件所在目录，不得用进程当前目录代替。应用由该目录派生唯一 `__yaca__` 数据根，因此从 PATH、快捷方式或其他工作目录启动时，配置与 Context 仍与当前发行包相邻。

这个契约只需要稳定、可测试的窄接口；不引入安装登记表、注册表数据库或路径猜测。平台身份与当前发行包目标不一致时应在启动基础检查中拒绝，而不是尝试加载另一架构的原生组件。

## 适配器文件布局方案

项目已经有意采用扁平英文 `src/` 布局，因此平台适配器应在不复制业务模块的前提下保持一致。

### 扁平后缀模块（推荐）

- 跨平台且真正共享的逻辑保留普通名称，例如 `path.lua`、`text.lua`、`clock.lua`。
- 只有行为确实不同的能力才增加后端，例如 `fs_windows.lua`、`fs_linux.lua`、`process_windows.lua`、`process_linux.lua`。
- `main.lua` 将选中的模块表以统一依赖名注入，例如上层只知道 `fs`，不知道文件名后缀。
- 如果某项能力后来出现真实共享逻辑，再增加 `<capability>_common.lua`；不提前创建空公共层。
- 不为对称外观创建无内容的 Windows/Linux 文件。

这种布局符合当前仓库、Lua `require` 和 luainstaller 静态发现习惯。文件名能直接显示平台归属，同时避免深目录和重复入口。

### 平台目录树

另一种做法是在 `src/windows/`、`src/linux/` 下建立平行目录。隔离更显眼，但会把同一能力的两个实现分开较远，并鼓励复制整套模块；对于目前规模偏重。

### 完整双实现树

Windows/Linux 各维护一套 path、fs、text、process、network、terminal。平台包内容最独立，但共享规则极易漂移，与统一业务源码目标冲突。

## 文件契约原则

- 接口由子系统文档和契约测试定义，不用空的“抽象 Lua 模块”模拟类继承。
- 平台后端必须返回相同形状的模块表与结构化错误。
- 只有 `main.lua` 知道 `_windows` / `_linux` 文件名。
- 高层源码与配置文件中禁止引用平台后缀模块。
- `fs` 必须把“原子替换已有文件”和“仅当目标不存在时发布新文件”分成不同操作。后者可暂记为 `publish_new_no_replace(temp, target)`，只能返回成功或 `DestinationExists`，绝不能覆盖陌生目标。
- `fs` 还需要为上下文 rename 提供 `move_no_replace(source, target)` 或等价恢复协议。禁止用“先检查目标不存在，再调用可能覆盖目标的普通 rename”模拟原子 no-replace；该检查存在 TOCTOU。
- Windows/Linux 后端可以使用不同原语或带提交标记的恢复协议，但上层语义必须一致。某文件系统无法安全满足时应明确返回 capability/storage error，不能为了成功率降级为可能丢失用户文件的覆盖操作。

## Windows XP 文件 API 可行性边界

不能把“Windows wide API”写成一个没有版本差异的承诺。Microsoft 的官方要求表显示：

- [`ReplaceFileW`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-replacefilew)、[`MoveFileExW`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw) 和 [`FlushFileBuffers`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-flushfilebuffers) 的最低客户端包含 Windows XP，为同卷替换/移动与 flush 提供候选原语；具体掉电、共享句柄、FAT/NTFS/网络盘语义仍需实测。
- [`GetFinalPathNameByHandleW`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfinalpathnamebyhandlew) 最低是 Windows Vista，XP 后端不能用它实现审批后路径身份复核。

因此“安全替换”与“最终路径/链接身份”要分别设计 capability。XP 的路径 fallback 可能需要父目录 handle、reparse point 查询、稳定文件身份或更保守地拒绝无法证明的 direct 操作；任何候选都要先在 XP/NTFS、FAT 和常见共享场景做原型，不能因为函数名带 `W` 就假定可用或原子。

## 当前问题

建议采用扁平后缀模块，并且只在行为真正不同处拆平台文件。这个布局是否需要调整？  
**W3-A 答复（技术择优，D-070）**：保持扁平 `*_windows.lua` / `*_linux.lua` 后缀；仅 `main` 字面量 require。不改为大门面或生成入口。

---

## W3-A：窄端口 ABI（规范）

对齐：D-013、D-014、D-017、D-070；门 AR-P0-04 / P0-14 / P0-15；事件泵组合见 [22](22-application-runtime-and-concurrency.md)。

### 共同约定

| 项 | 规则 |
| --- | --- |
| 错误形状 | 所有端口返回 `ok, result_or_err`；`err = { code, message, retryable?, detail? }`；`message` 永不含 secret |
| 阻塞 | 端口 **不** 在业务线程上无限阻塞；长 I/O 必须经 22 号 `AsyncPort`（start→poll→cancel→join→close） |
| 平台分支 | 业务模块 **禁止** `if os=="windows"`；只消费 capability 与统一错误码 |
| 负向 | 无 Web listener、无 remote client、无 media device port |

### `platform` 身份（只读事实）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `os` | `"windows"\|"linux"` | 发行包身份 |
| `arch` | `"x86"\|"x86_64"` | Win32=x86；Win64/Linux=x86_64 |
| `package_id` | string | 与 manifest 一致；错误架构立即退出 |
| `executable_dir` | path | 程序所在目录（绝对） |
| `data_root` | path | 邻接 `__yaca__`（D-056） |

### `path` 端口（纯计算，无 I/O）

| 操作 | 语义 |
| --- | --- |
| `join(parts...)` | 平台分隔符合成；不解析 symlink |
| `normalize_display(os_path)` | **显示用** 本机友好形（可保留盘符/UNC 外观） |
| `to_logical_path(os_path, root_kind)` | 产出 Context/hash 用的 **LogicalPath 规范形**（见 11 号 W3-B；D-070：显示≠hash） |
| `is_within_root(logical, root_logical)` | 规范前缀判定；禁止裸字符串前缀 |

### `fs` 端口

| 操作 | 语义 | 失败码（例） |
| --- | --- | --- |
| `open_read` / `open_write_temp` | 有界读写；写走 temp | `NotFound`, `AccessDenied`, `Limit` |
| `publish_new_no_replace(temp, target)` | 仅目标不存在时发布；**禁止覆盖** | `DestinationExists` |
| `replace_existing(temp, target)` | 原子替换已有文件（平台原语 + flush） | `TargetChanged`, `Storage` |
| `move_no_replace(src, dst)` | 无覆盖移动 | `DestinationExists`, `CrossDevice` |
| `identity(handle_or_path)` | 打开后复核（inode/file-id/size/mtime 或等价）；XP 无 `GetFinalPathNameByHandleW` 时用已证明 fallback | `Unverifiable` |
| `flush` | 尽力 flush 到稳定存储 | — |

### `text` / `clock`

| 端口 | 操作摘要 |
| --- | --- |
| `text` | UTF-8 校验/替换；控制台 codec 探测；安全截断（保留计数） |
| `clock` | wall UTC 与 monotonic；不可靠时显式 `degraded`，禁止静默用墙钟冒充 monotonic |

### 备选否决

| 方案 | 否决理由 |
| --- | --- |
| 统一 `platform.*` 大门面 | D-013 已否；循环依赖风险 |
| 业务内散落 OS 判断 | 兼容规则分叉 |
| 依赖系统 PATH 解析内部工具 | AR-P0-14；cwd 劫持 |

### 完成度（W3-A）

- [x] 窄端口清单与错误形状  
- [x] no-replace / identity 语义  
- [ ] 目标机数值与 XP identity fallback 实测（TP）  
