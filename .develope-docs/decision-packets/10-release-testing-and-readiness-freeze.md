# 决策包 10：发布、完整测试与架构就绪冻结

更新日期：2026-07-22

状态：等待项目负责人回复；本文所有推荐、路线、示例数字和问题选项都不是已确认决定

## 本包要决定什么

本包把“代码写完”与“真的可以把一个 zip 交给 XP、现代 Windows 和旧 Linux 用户”之间缺失的整条链路展开。它只收口会改变产品承诺、数据生命周期、发布范围和放行权的上游选择：

- 每个平台的 zip 是解压即运行，还是必须安装后才能运行；
- `__yaca__` 数据根放在哪里，多份 yaca 如何使用数据；
- 升级、迁移、降级和卸载时，INI、registered config secrets 与 Context XML 怎样保留；
- 当前 `luainstaller` 不支持 Windows x86/XP 时，Windows 发布如何取得可执行前置；
- 现有 `bin/` 为什么不能直接复制进正式包，怎样建立最小依赖 allowlist；
- 是否允许 UPX、怎样审计 ELF/PE/CRT/API/TLS/CA 和原生模块；
- 校验和、许可证清单、SBOM、构建配方和发布证据怎样交付；
- “完整测试”由哪些证据层组成，哪些失败一定阻断发布；
- 怎样在真实最低平台上测性能、故障恢复和长会话，而不是凭开发机感觉；
- 精确超时、队列、XML、扫描和内存常量在什么时候依据实测冻结；
- 怎样用 `requirement -> decision -> spec -> test -> evidence` 判断能否进入实施计划和正式发布。

本包不是发布脚本实施计划。负责人确认这里的产品边界后，还要由技术侧产出发布 manifest、测试目录、平台证据和具体常量，才能通过 [`ARCHITECTURE-READINESS.md`](../ARCHITECTURE-READINESS.md) 的门禁。

## 本包不让项目负责人凭感觉决定什么

以下内容必须由技术设计、最小原型、静态审计和真实平台测试得出，不设计成“喜欢 A API 还是 B API”的负责人问卷：

- Win32 helper、launcher、进程取消和文件替换使用哪一个具体系统 API；
- 选择哪一版编译器、Windows SDK、CRT 链接方式和 linker flag；
- Lua 5.5、Lua C module、curl、TLS 和 Expat 的具体构建命令；
- 某次操作应该是 200 ms、500 ms 还是 2 秒；
- 故障注入使用 shim、test port、进程 kill 还是虚拟机断电；
- SBOM 最终采用 SPDX 还是 CycloneDX，以及生成器实现；
- CI、虚拟机管理、测试 runner 和结果数据库使用什么工具；
- zip 压缩级别、文件排序和时间戳归一化的实现参数。

负责人需要决定的是：产品承诺哪一种体验、哪些证据缺失就不能发布、数据默认保留还是删除、是否授权兄弟仓库前置项目，以及是否允许某类有明确代价的发布形式。技术侧随后必须用证据选出能兑现这些承诺的实现。

## 已经确认、这次不重新询问的前提

1. yaca 使用官方 Lua 5.5 语言级别和 ABI。
2. yaca 必须使用相邻 `../luainstaller` 打包；yaca 不暗建第二套 launcher/runtime 打包器。
3. Windows 和 Linux 分别发布独立 zip，共用一个 `main.lua` 和同一份业务源码，但 native runtime、后端和资源绝不混包。
4. Windows 只发布一套 Win32 x86 32 位产物，完整覆盖 XP SP3、Vista SP2、7 SP1、8、8.1、10 和 11。
5. Linux 只发布 x86_64；CentOS 7 x86_64 是硬性最低基线。其他发行版清单不在本包形成未编号选择；没有新的编号决定与完整证据，就不新增正式支持声明。
6. 所有最终声明支持的平台都执行完整测试；没有“支持，但只冒烟”的次级承诺。
7. v0.1 不承诺旧 macOS，也不发布 macOS 包。
8. v0.1 要是完整可用版本；不能用 README、空脚本或仅现代开发机 smoke test 代替闭环。
9. 当前不自动 push；发布设计也不能把远端写入、GitHub Release 上传或签名服务视为默认授权。

关联决定：D-003、D-004、D-007 至 D-012、D-015、D-016、D-018。

## 已核对的当前事实

这些是仓库与兄弟项目的现状，不因负责人选择而改变。

### 1. Windows x86/XP 打包链当前被明确阻断

[`../luainstaller/src/platform.lua`](../../../luainstaller/src/platform.lua) 当前只接受 Windows x86_64 native profile，并会对 Windows x86 返回 `UnsupportedPlatformError`。[`PLATFORMS-NATIVE-LIMITS.adoc`](../../../luainstaller/docs/PLATFORMS-NATIVE-LIMITS.adoc) 也明确写明 1.0 拒绝 Windows x86 和 ARM64。

因此下面三项当前不能同时直接兑现：

```text
Windows XP SP3 x86
+ Lua 5.5
+ must package with ../luainstaller
```

这不是“以后找一台 XP 测一下”就能解除的普通风险。它需要一个经单独授权、设计和验证的 luainstaller Win32/x86/XP 前置项目。没有授权前，yaca 只能记录阻塞，不能越界修改兄弟仓库。

### 2. 当前 Linux `bin/` 不是目标 Linux 发布物

对当前文件执行 `file/readelf`，`bin/7za`、`busybox`、`curl`、`diff`、`file`、`iconv`、`jq`、`lua55`、`patch`、`sqlite3` 都是 ELF32/Intel 80386，而正式 Linux 目标是 ELF64 x86_64。

其中 `bin/curl` 的 ELF header 是 `ELF32`、`Machine: Intel 80386`，二进制字符串又自报 `x86_64-pc-linux-muslx32`。无论把它称为 i386 产物还是带有 x32 构建痕迹，它都不是可直接放行的普通 CentOS 7 x86_64/ELF64 产物。正式装配必须从可追溯来源重建或取得目标 ABI 文件，再检查 ELF class、machine、interpreter、动态依赖和最低符号版本。

### 3. 当前 Windows 文件只有“位数外观正确”，没有 XP 证明

当前 Windows exe/DLL 多数是 PE32 Intel i386；这与目标架构方向一致，但不能证明：

- 没有意外导入 Vista 或更高版本 API；
- 不依赖目标机缺失的 CRT/UCRT/VCRUNTIME；
- TLS、CA、代理、Unicode 路径和 console 行为在 XP 可用；
- DLL 搜索和随包依赖闭合；
- 文件来源、许可证和构建配置可追溯。

`bin/curl.exe` 还经过 UPX 压缩。压缩后的 import table 主要描述解压 stub，不能代替未压缩原始文件的 API/CRT/TLS 审计；如果最终仍压缩，还必须对最终压缩 hash 重新执行完整平台测试和恶意软件误报检查。

### 4. README 描述超前于仓库现状

当前 README 已描述 GitHub Release、安装脚本、开箱即用和旧平台运行，但核心闭环、正式 zip、安装脚本和平台证据尚未形成。发布设计必须让 README 明确区分“已实现”“已确认目标”和“仍在设计”，不能把目标写成已经交付。

## 先统一几个术语

| 术语 | 本包含义 |
| --- | --- |
| platform zip | 面向一个 OS/架构组合的完整发布档案，例如 Windows x86 或 Linux x86_64 |
| application tree | 可由同一发布 manifest 重建的程序、Lua runtime、源码/资源、native helper 和文档 |
| data root | `config.ini`、Key 所在 INI 区域和 `CONTEXT/**/*.xml` 的唯一物理根 |
| portable instance | application tree 与其数据根形成一个可以显式搬移的实例，不依赖系统安装注册 |
| release candidate | 已冻结内容并具有唯一 hash、等待完整门禁验证的候选 zip |
| component allowlist | 唯一允许进入 zip 的文件及其用途、来源、版本、hash、许可证和 ABI 记录 |
| SBOM | 机器可读的软件物料清单；不是把 `bin/` 文件名抄成一张表 |
| hard gate | 不满足就不能把对应平台/版本标为正式发布，不能用“已知问题”绕过 |
| observed evidence | 带源码提交、产物 hash、环境和测试目录版本的实际测量结果 |
| schema downgrade | 旧程序尝试打开由新程序写过的 INI/XML；默认不能假装理解未知语义 |

## 三个生命周期示例（不是捆绑选项）

三个示例都必须遵守已经确认的完整平台测试、严格依赖审计和 readiness 追踪。它们用于提前暴露不同组合的生命周期成本，不是让负责人一次打包选择；正式决策中 RF-01 只拥有程序入口，RF-02 只拥有 data root，RF-03 只拥有迁移/卸载，三组可以独立组合。

### 示例 A：便携单实例，数据邻接，显式安全迁移（参考组合）

- 每个平台 zip 解压后直接运行，不要求管理员安装、注册表或系统 Lua。
- 每份解压实例拥有明确邻接的 `__yaca__` 数据根；程序不会因目录不可写而静默切换到另一个位置。
- 安装脚本若以后提供，只做可预览的复制、快捷方式或 PATH 薄层；它不是首次运行前提。
- 升级时把新版本解压到新位置，通过显式迁移/选择动作把旧数据验证、转换到新实例；Context 与 non-secret 配置可按 RF-03 备份，secret-bearing 配置是否复制及怎样保存只消费 M05-42；旧程序和旧数据在成功前保持不动。
- 降级遇到更高 schema 只读打开或明确拒绝；不试图猜测并覆盖新版数据。
- “卸载”首先是删除 application tree；默认保留或先导出数据，永久删除数据必须单独确认。

优点：最符合“一个平台一个 zip、保持简单、可离线搬移”，也容易在 XP 上解释和排错。整个实例复制到另一台机器时，用户能看见自己带走了什么。

代价：邻接数据会让“直接删除整个解压目录”存在误删风险；多版本并存和数据迁移必须有清晰提示、备份与 no-replace 规则。

### 示例 B：zip 仍直接运行，但默认共享系统用户数据根

- application tree 可以放在任意只读位置；数据固定到每个 OS 的用户数据目录。
- 新旧程序版本天然看到同一数据根，程序目录可以独立删除。
- 便携搬移需要显式 export/import 或 `data-root` 覆盖；复制 zip 本身不等于复制工作历史。
- 多份 yaca 默认共享配置、Context 和写者锁，必须解决版本并发与 schema ownership。

优点：升级、卸载和只读 Program Files 场景更自然，误删程序目录不会带走历史。

代价：XP 与 Linux 的用户目录规则、权限和多用户行为更复杂；“解压一个文件夹即可完整搬走”的心智模型不成立，同一用户的多版本更容易争用数据。

### 示例 C：安装管理型，程序与用户数据完全分离

- zip 只是安装介质，必须运行安装脚本/安装器后才进入正式支持路径。
- 安装器管理版本、快捷方式、PATH、卸载清单和程序文件；数据进入系统用户目录。
- 升级/回滚由安装器事务管理，portable direct-run 不作为承诺。

优点：程序与数据所有权最传统，升级和卸载可以集中管理。

代价：增加管理员/每用户安装、注册、旧系统 installer、回滚和卸载测试；与当前“独立 zip、简单、离线复制”的方向最远，也会把 luainstaller 单文件/目录包与 OS installer 混成两个系统。

### 推荐结论

示例 A 是当前最小、最连贯的参考组合，但它不预先绑定 RF-01/RF-02/RF-03。无论最后怎样组合，都必须分别确认“程序入口、data root、显式迁移、默认保留数据、禁止静默换根”，不能只确认 portable 而省略最容易丢数据的升级与卸载语义。

若 RF-02 选择系统用户数据根，示例 B 展示了 direct-run 入口对应的成本；若 RF-01 选择 installed-only，示例 C 展示了额外安装生命周期。最终契约仍从三个 RF 决定组合生成，不记录“路线 B/C”这种捆绑决定。

## 推荐的发布与证据流水线

```text
confirmed requirements and accepted subsystem specs
  -> freeze source commit + schema/registry versions
  -> satisfy platform prerequisites
       Windows: luainstaller Win32/x86/XP profile proven
       Linux:   CentOS 7 x86_64 build baseline proven
  -> build Lua runtime, launcher, C modules and helpers
  -> assemble only component-allowlisted files
  -> static ABI/API/CRT/import/license/source audit
  -> deterministic unit, contract and trace tests
  -> fault-injection and recovery tests
  -> performance workloads and long-session soak
  -> create final platform zip, checksum, manifest and SBOM
  -> run the exact zip/hash on every declared platform
  -> verify requirement -> spec -> test -> evidence closure
  -> publish or block
```

任何在最终 zip 生成后的修改都会产生新 hash，并使原平台证据失效。不能先测未压缩文件、后来 UPX；不能先测构建目录、后来少带一个 DLL；不能先测某个 Windows zip，再重新打包一个“内容应该一样”的 zip 上传。

## zip 直接运行仍需要完整生命周期

“不需要安装”不等于“没有安装问题”。即使选择便携路线，也必须冻结以下状态：

| 生命周期 | 必须唯一回答的问题 |
| --- | --- |
| 解压 | 同名旧文件、只读目录、路径过长、zip 损坏和杀软隔离时怎样失败 |
| 首次运行 | application root 与 data root 怎样确定；缺失数据是建立草稿还是阻断 |
| 多份副本 | 两个版本是否各用数据、显式共享时怎样锁和校验 schema |
| 升级前 | 旧程序版本、配置 schema、Context schema、剩余空间和写者状态怎样预检 |
| 迁移中 | M05-42 允许的数据集合怎样备份，以及临时目标、flush、验证、publish 和崩溃恢复怎样排序 |
| 升级后 | 哪个程序拥有写权限；旧程序怎样避免重新写坏新版数据 |
| 降级 | 新 schema 是只读、明确拒绝还是有经过测试的逆迁移 |
| 卸载 | application tree、数据、Key、备份和发布诊断分别保留还是删除 |
| 搬到另一台机器 | XML 能否读取；缺失 Model/Permission/config-secret/ExecProfile/路径映射怎样提示而不静默替换 |

推荐的最低不变量是：程序永远显示自己实际使用的 data root；一个 invocation 内不自动切根；迁移失败保留可验证的旧数据；永久删除含 registered config secrets 的 INI/backup 或 Context XML 需要独立、明确、默认否定的动作。

## 依赖 allowlist、SBOM 与原生文件审计

### allowlist 不是当前 `bin/` 的复制清单

正式 allowlist 应由已经确认的运行时工具/模块 registry 反向生成。每一项至少记录：

| 字段 | 要证明什么 |
| --- | --- |
| logical name / purpose | yaca 哪个已确认能力确实使用它 |
| source | 上游 URL、源码提交、发行签名或内部构建 recipe |
| version and source hash | 能否重建或重新取得同一输入 |
| license | zip 与公开清单是否满足再分发义务 |
| target OS/arch/ABI | Windows PE32 x86 或 Linux ELF64 x86_64，不能靠文件名猜 |
| compiler/CRT/libc baseline | 是否能在 XP SP3/CentOS 7 最低系统加载 |
| imports/dependencies | 是否意外依赖新 API、系统 DLL、glibc symbol 或外部工具 |
| security role | 是否处理 registered config secrets、网络、XML、命令或工作区数据 |
| final artifact hash | 实际进入 zip 的文件，而不是上游另一个文件 |
| platform evidence IDs | 哪些真实测试证明它与完整包共同工作 |

未列文件使装配失败；同名但 hash 不同也必须失败。`7za`、`jq`、`sqlite3`、`file`、`iconv`、`patch`、`diff`、busybox 等只有在权威工具规格证明直接需要时才能进入，不因历史 `bin/` 中存在就保留。

### UPX 的正确审计顺序

如果负责人允许 UPX，技术侧仍必须按以下顺序工作：

1. 保留可追溯的未压缩原始文件。
2. 对未压缩文件审计 machine、subsystem、imports、CRT、DLL、TLS backend 和许可证。
3. 记录 UPX 版本、参数、输入 hash 与输出 hash。
4. 对压缩后最终文件重新做启动、行为、性能、杀软误报和 XP 至 11 完整验收。
5. 发布证据只绑定最终进入 zip 的压缩后 hash。

因为 zip 本身已经压缩，UPX 是否值得引入应由真实体积收益、启动代价、审计难度和误报证据决定。不能只因当前 `curl.exe` 已经压缩就把 UPX 变成默认依赖。

## 完整测试的六层证据

### L1：静态与确定性核心

- Lua 5.5 parser、schema、路径/hash、状态转换、预算和错误分类；
- 配置、XML、JSON/SSE 的 malformed corpus 与确定性 round-trip；
- command/tool/error/enum registry 唯一性；
- PE/ELF machine、imports、CRT/libc、native module ABI 与 package allowlist；
- 同一输入得到同一 typed result，不需要网络或真实模型。

### L2：端口、协议与事件轨迹契约

- 文件、进程、网络、终端、时钟和持久化端口；
- scripted ModelEvent、tool call/result、permission 和 AgentLoop typed outcome；
- Context durable event、compaction、模型切换与恢复；
- TUI/CLI 对同一领域动作产生同一结果。

### L3：故障注入与崩溃恢复

- 每个 durable barrier 前后注入失败；
- 模型断流、helper 崩溃、取消竞态、磁盘满、replace/flush 失败、锁冲突；
- 外部副作用已发生但结果未保存时，恢复必须保留 `unknown`，不得自动重放；
- 迁移、创建、rename 和 publish 在每个崩溃点不覆盖旧数据。

### L4：性能、资源与长会话 soak

- 小/中/压力三档 XML、目录、输出、队列和终端；
- 反复恢复、压缩、模型切换、工具输出和 Context 搜索；
- 记录峰值/稳定内存、I/O 写放大、首结果、p50/p95/最大延迟和取消收口；
- 检查事实一致性、局部 ID 不复用、队列有界以及没有随 turn 无界增长的 table。

### L5：Agent 场景与真实 Model 评估

- scripted model 完成读取、修改、验证、取消、拒绝、等待用户和恢复闭环；
- 脱敏 provider 录制物验证流式/非流式 wire profile；
- 真实 Model 评估任务质量、token、工具次数和安全违规。

确定性的安全、权限、状态、数据完整性失败永远不能被“真实模型大多数时候做得不错”抵消。真实模型质量是单独的统计证据，不是底层正确性的替身。

### L6：最终 zip 的真实平台验收

- 使用最终 zip/hash，不使用源码树或构建目录；
- 清除系统 Lua、开发仓库路径和未声明工具；
- 走完整用户旅程：解压、版本、配置、self-test、AgentLoop、工具、取消、退出、恢复、升级/降级/卸载；
- 验证真实 console、路径/代码页、文件系统、TLS、代理、进程树和低资源；
- Windows 同一 x86 zip 在 XP SP3 至 11 全部执行；
- 每个最终声明的 Linux 发行版都对实际面向它发布的 x86_64 zip 完整执行。

模拟器、Wine、容器和现代主机 compatibility mode 可以用于早期排错，不能成为唯一正式平台证据。

## 故障注入与 soak 最低矩阵

下表冻结应覆盖的风险种类，不提前指定注入 API、运行分钟数或精确 fixture 大小。

| 风险面 | 必须注入/放大的场景 | 不变量 |
| --- | --- | --- |
| Context commit | write、flush、validate、replace、directory sync 各边界失败 | 旧版或新版可解释，绝不出现被宣称成功的半事件 |
| 副作用工具 | operation durable 前、执行后/result durable 前崩溃 | 不自动重放；unknown 明确保留 |
| 创建/rename/migrate | 检查后被其他进程抢占目标、磁盘满、跨卷失败 | no-replace；旧数据不被覆盖 |
| writer lock | 双进程同时打开、stale owner、PID 重用、时钟跳变 | 最多一个 writer；不能仅凭年龄抢锁 |
| Model/network | header/SSE/JSON 半截、断流、429、代理失败、取消 | request/attempt 身份不混淆；已收响应不悄悄整次重试 |
| process/helper | stdout/stderr 背压、子进程树、helper crash、cancel race | 不死锁；结果为 completed/failed/unknown 之一 |
| TUI | 异步输出时正在编辑、窄终端、无 ANSI、EOF/Esc | 输入不丢、不误发；文本后备等价 |
| config/migration | 旧/新/未知 schema、损坏 INI/XML、外部修改 | 只对 M05-42 eligible data set 备份并验证后发布；未知语义只读或拒绝 |
| release package | 文件缺失、错误 hash、混入未列文件、zip 损坏 | 启动或装配 fail-closed；错误指出实际缺项 |
| long-session soak | 大 XML、大目录、大输出、反复压缩/恢复/模型切换 | 内存/队列有界，事实与 ID 关系保持一致 |

## 精确性能常量的冻结顺序

现在就要求负责人填写毫秒数，会把开发机直觉伪装成旧平台事实；完全不设数字，又无法实现超时、队列、取消和内存硬边界。推荐采用四阶段冻结：

### 阶段 1：现在冻结语义，不冻结数字

先决定哪些量必须有硬上限，以及超限时返回什么 typed result。例如：

- 队列、单工具输出、单 XML、目录候选和重试次数不能无界；
- 取消必须最终收口，超时后真实状态未知就报告 unknown；
- 达到内存/文件/输出上限要提前拒绝或截断并记录，不能靠 OOM；
- UI 需要保持可交互，但不先写“按键必须 37 ms”。

### 阶段 2：端口最小原型后冻结测量方法

在 XP SP3 x86、CentOS 7 x86_64 参考机上建立小/中/压力 workload，固定：硬件/虚拟机配置、磁盘状态、冷/热缓存、重复次数、统计口径和采样工具。测量方法先进入规格，避免看到结果后改变口径。

### 阶段 3：子系统实施前冻结 provisional 常量

技术侧用实测分布和安全余量提出启动、取消、XML commit、Resolver、队列、输出和内存常量；负责人只审核这些数值是否兑现已经确认的体验等级，不在 A/B API 或 200/500 ms 之间拍脑袋。

### 阶段 4：release candidate soak 后正式冻结

最终 zip 在最低平台完整 soak 后，允许依据证据修订 provisional 值；变更必须同步常量 registry、规格、测试和用户错误。v0.1 release freeze 后，任何常量调整都需要新的基准、回归分析和兼容性记录，不能作为“调一调就好”的隐藏补丁。

硬安全上限与性能目标必须分开：硬上限超出就产生确定性错误；p50/p95 是回归门和体验证据，不能因一次偶发慢盘就把正确数据写成损坏。

## requirement -> spec -> test -> evidence 发布门

### 每条记录的最低字段

```text
requirement_id      decision/checklist/readiness ID
decision_status     confirmed / rejected / open / technical
normative_spec      accepted spec file + stable anchor
contract            inputs, outputs, failure and recovery invariant
test_ids            normal + critical failure + recovery + platform tests
artifact_scope      source/build/package hashes covered by the tests
platform_scope      pure/windows-x86/linux-x86_64/specific OS version
evidence            result bundle ID, environment and timestamp
gate_status         open/specified/tested/platform-proven/release-proven
```

### 推荐门禁规则

1. 未回复的推荐、未归档回复和仍有候选分支的子系统，状态保持 `open`。
2. 每个 P0 requirement 至少有正常、关键失败、恢复和相应真实平台证据。
3. 每个公开配置字段、CLI 命令、XML 元素、tool、error ID 和 native component 都必须有规范来源。
4. 测试通过只证明它实际覆盖的 artifact hash；重新打包或替换组件后需要重跑受影响门。
5. `evidence_missing` 是失败，不是“没有观察到失败”。
6. 确定性安全/权限/存储不变量任何一次违反都阻断对应 release candidate。
7. 真实 Model 波动单独按统计阈值判断，不能豁免确定性失败。
8. 每个发布证据集至少记录源码 commit、luainstaller 版本、RF-06 所选 integrity artifact hash、zip hash、OS/架构、测试目录版本、配置非秘密摘要和逐项结果。
9. 原始大日志和 VM 镜像不必污染源码仓库；仓库/Release 保留稳定摘要与内容 hash，受控证据存储保存原附件并有保留策略。

## 真正需要项目负责人回答的十四组问题

以下十四个正式组各自只拥有一个 release 决策轴。Windows x86 与 Linux x86_64 独立 zip、Lua 5.5、luainstaller 打包、声明平台完整测试，以及“只有已证明组件才可入包”均为前提，不再作为可放弃的伪选项。RF-07 和 RF-13 只是证据/文档的内部组织门，不在回复清单。D-039 已固定正常启动、本地管理和定时器不得为了更新隐式联网；RF-16 只决定是否再提供用户显式触发的更新能力。没有明确回复的正式编号继续待决，不会因为本文写了推荐就自动进入 `DECISIONS.md`。

### RF-01 zip 的正式程序入口

- A：每个平台 zip 解压即可运行，portable 是正式支持入口；安装脚本不是前提。（推荐）
- B：每个平台 zip 内含 luainstaller 生成的安装入口，完成安装后的 application tree 才是正式支持入口。
- C：同一个平台 zip 同时提供 portable 与 installed 两条正式入口，两条都必须通过完整生命周期和 exact-hash 测试。

推荐 A。它最符合离线旧系统和简单产品。这里只决定程序入口，不顺带决定 data root；RF-02 独立拥有数据位置。

技术侧必须证明：portable 入口在干净 XP/CentOS 7、无系统 Lua/PATH 帮助时可从解压目录完整运行；installed 入口则必须从同一平台 zip 离线完成安装并完整运行。两种入口遇到不可写、路径过长或缺文件都 fail-closed。

关联：`REL-01`、`REL-02`、AQ-044、AQ-329、D-015。

### RF-02 `__yaca__` 数据根与多副本规则

- A：portable 入口使用邻接 `__yaca__`，installed 入口使用系统用户数据根；若 RF-01 只选其一，就只应用对应规则。不可写时明确失败，不静默换根。（推荐）
- B：所有正式入口都使用系统用户数据根；portable 只描述程序可搬移，不承诺数据邻接。
- C：没有默认根，每次启动都必须显式提供 data root。

推荐 A。它让 portable 可整体搬移，又让 installed 符合系统写入习惯，并与 RF-01 的三种入口选择都不冲突。多副本若显式共享根，只允许一个可写 schema/program generation；其他进程拒绝或仅在已证明安全时只读。无论选哪项，`.status`、self-test 和错误都显示实际 data root。

技术侧必须证明：路径解析、权限、锁、多进程、跨版本 schema 和目录不可写行为；不让负责人选择 Win32 known-folder API 或 Linux 环境变量细节。

关联：`PLAT-02`、`REL-02`、`UPDATE-01`、AQ-244、AQ-329。

### RF-03 升级、降级、迁移与卸载

RF-03 只消费 M05-42 的 secret-copy policy，并独立拥有程序版本、data root、迁移发布与卸载拓扑。“旧数据”“备份”和“复制”都先按 M05-42 生成 eligible data set：M05-42 A 时只有 Context 与 non-secret 配置投影，目标重新输入 secrets；B 时只有用户为本次动作显式 include-secrets 才可复制；C 时只能按其规则管理一份可见、可清除的 secret-bearing previous INI。RF-03 不得自行创造第四种 secret 副本、隐式复制 Key，或把迁移需要当成覆盖 M05-42 的理由。

- A：新版本 side-by-side 解压；显式选择旧数据，先备份 M05-42 允许的集合、迁移到临时目标、验证后发布；失败保留旧版。降级对未知新 schema 只读或拒绝。卸载默认保留数据，永久删除单独确认。（推荐）
- B：程序允许覆盖升级，但数据迁移仍只复制 M05-42 允许的集合到临时目标，验证后原子发布；失败保留旧数据。卸载默认保留数据，永久删除单独确认。
- C：始终 side-by-side；程序从不自动迁移，用户显式运行 migrate 并选择源/目标；migrate 仍只处理 M05-42 允许的集合，旧 schema 只能只读或拒绝，卸载默认保留数据。

推荐 A。它会多一步显式动作和磁盘空间，但最容易证明崩溃、磁盘满或新版 bug 不会同时毁掉程序与工作历史。三项都禁止静默寻找/迁移/删除用户数据，也都只消费 M05-42 的 secret-copy policy，不能在 RF-03 内另创新的 secret 生命周期。

一个无法由 yaca 兑现的边界必须写清：若 portable 数据根与 application tree 邻接，用户直接在 Explorer/shell 删掉整个解压目录会绕过 yaca 的卸载/永久删除确认；A/B/C 都不能保护或恢复这类外部手动删除。产品只能在 `.status`、迁移/卸载帮助和 README 中显著展示实际 data root，建议备份，并让 yaca 自己发起的删除保持默认取消。

技术侧必须证明：三类版本（程序、配置 schema、Context schema）独立兼容；每个迁移崩溃点、外部修改、no-replace、磁盘满和旧程序重开都可恢复；M05-42 A/B/C 生成的 eligible data set、重新输入 secret 或受管副本 inventory 与实际迁移结果一致。精确命令名留给 CLI 包。

关联：`CFG-07`、`FMT-06`、`REL-02`、`REL-03`、`UPDATE-01`、`UPDATE-02`、AQ-330、M05-42。

### RF-04 luainstaller Win32/x86/XP 前置

- A：明确授权把 luainstaller Win32/x86/XP profile 作为独立前置子项目；先单独设计、测试和验收，再由 yaca 消费经过证明的版本。（推荐）
- B：暂不授权兄弟仓库工作；Windows release 保持硬阻塞，yaca 只继续纯 Lua/平台无关设计和不依赖该前置的工作。
- C：不修改兄弟仓库；只消费项目负责人另行提供且已通过 Lua 5.5、Win32 x86、XP 至 11 完整证据的 luainstaller artifact，在证据到位前 Windows release 保持硬阻塞。

推荐 A。选择 A 才构成兄弟仓库工作的范围授权；本文推荐本身不授权修改。三项都保持 Lua 5.5、Windows x86/XP 和 luainstaller，不允许用换语言级别、架构或打包链来“解除”阻塞。

技术侧必须证明：XP-capable toolchain/CRT、Lua 5.5 ABI、launcher、narrow/wide path 能力、native module、PE imports、DLL closure 和 XP 至 11 的 luainstaller 自身测试。具体 compiler/API/flag 由证据选，不由负责人投票。

关联：D-004、D-007、D-010、`REL-04`、AQ-206、AQ-211。

### RF-05 依赖 allowlist、现有 `bin/` 与 UPX

- A：严格最小 allowlist；当前 `bin/` 只作来源线索，全部重新证明；v0.1 最终 native 文件不使用 UPX。（推荐）
- B：同样使用严格 allowlist，但允许某项在未压缩审计后按证据使用 UPX；最终压缩文件必须重新做完整平台测试。

推荐 A。zip 已提供压缩，v0.1 先获得透明 imports、较低误报和可追溯性通常比节省少量磁盘更重要。严格 allowlist、删除未被权威 tool registry 使用的历史工具、重新证明每个组件是共同前提；本组只决定最终 native 文件是否允许 UPX。

技术侧必须证明：每项用途、来源、hash、license、PE/ELF ABI、CRT/libc、imports、TLS/CA、UPX 前后审计和真实平台证据；最终发行完整性材料服从 RF-06。不得让负责人逐个猜应该带 jq、sqlite3 或 7za。

关联：`REL-04`、`REL-09`、`SUPPLY-01` 至 `SUPPLY-04`、AQ-207、AQ-341、AQ-342。

### RF-06 公开发布完整性材料

- A：每个 zip 同时发布 SHA-256、第三方组件/许可证 manifest、机器可读 SBOM 和构建/证据摘要。（推荐）
- B：每个 zip 发布 SHA-256、第三方组件/许可证 manifest 和构建/证据摘要；不另发机器 SBOM，manifest 必须仍可机器读取。
- C：每个 zip 发布 SHA-256 与许可证/组件摘要；完整内部 ComponentManifest 仍是 hard gate，但不作为独立公开 SBOM artifact。

推荐 A。它不承诺尚未证明的 bit-for-bit reproducibility，但让每个输入和最终文件都有来源、hash 与许可证。RF-06 独占 zip hash、component/license manifest、SBOM 和 build/evidence summary；RF-15 只决定身份签名。

技术侧决定并验证：SPDX/CycloneDX 具体格式，以及每份材料与 exact zip 的 hash 绑定。zip 命名、确定性参数、构建环境锁定与可重复程度属于 BuildAndAssembly 规范，不由本组顺带投票。

关联：`REL-10`、`REL-12`、`SUPPLY-01`、`SUPPLY-03`、`SUPPLY-04`、AQ-208、AQ-209。

## RF-07 readiness 追踪索引的技术组织（不是负责人投票）

L1 至 L6、最终 exact zip、真实声明平台和 deterministic hard gate 已是本包不可放弃的共同前提。把 requirement 主要投影为 event trace、invariant/property registry 或 versioned scenario catalog，只改变内部索引和维护方式，不改变用户承诺，因此不让负责人凭偏好选。

权威工件必须是一份机器可检查的 `requirement -> decision -> normative spec -> invariant/trace/scenario -> test -> exact artifact/platform -> evidence` 记录；trace、property 和 scenario 可作为它的三种可重建 view，不得发展成三份相互矛盾的事实源。技术证明必须产出测试 catalog、fixture schema、scripted model、端口替身、trace matcher、失败分类、证据 manifest 和“任一 view 重建后集合一致”检查。具体 runner/CI/存储形式由证据选择。

关联：`REL-05` 至 `REL-07`、`TEST-01` 至 `TEST-06`、`EVAL-01` 至 `EVAL-08`、AQ-204、[`subsystems/20-testing-and-agent-evaluation.md`](../subsystems/20-testing-and-agent-evaluation.md)。

### RF-08 “每个平台完整测试”的放行语义

已确认每个声明平台完整测试；本条不重新询问是否可以只冒烟，而是确认缺少某个平台证据时怎么办。

- A：平台独立放行；Windows 任一声明版本失败只阻断 Windows zip，Linux 任一声明发行版失败只阻断 Linux zip，另一平台可正式发布同版本。（推荐）
- B：版本同步放行；Windows 或 Linux 任一声明平台失败，都阻断该版本的两个正式 zip，直到全部通过。
- C：通过的平台可以先发布明确标记的 prerelease；只有两个平台都通过后才转为同版本正式 release，失败平台从不标支持。

推荐 A。两个发行物本来就独立装配与测试，没有必要让 Linux 的已证明 zip 被 Windows 基础设施阻塞，反之亦然；B 更强调同版本完整到齐，C 提供诚实的预发布窗口。三项都不允许给缺证据的平台贴正式支持标签。

Windows 的同一 x86 zip/hash 必须覆盖 XP SP3、Vista SP2、7 SP1、8、8.1、10、11。Linux 每个公开声称支持的发行版也必须对实际发布的 x86_64 zip 完整测试；CentOS 7 不能移除，其他发行版在新的编号决定完成前不进入正式声明。

技术侧必须定义“完整”的可执行 catalog、真实环境采集与 exact-hash 绑定；不让负责人选择 VM 软件、调度方式或脚本 API。

关联：D-009 至 D-012、`REL-08`、`REL-13`、`TEST-08`。

### RF-09 跨平台性能预算采用什么结构

精确数字都按“语义与超限结果 -> workload/测量法 -> provisional 实测 -> exact-zip soak 后冻结”四阶段产生，本组不让负责人凭感觉填写毫秒或内存。

- A：所有平台共享安全 hard caps；启动、按键反馈、扫描等体验指标按平台分别冻结。（推荐）
- B：安全 caps 与体验指标都以最低目标平台为共同上限；任一平台超过就阻断。
- C：安全 caps 与体验指标均按平台冻结；可搬移 XML/配置还必须满足接收平台的 caps，超限时给出明确只读/压缩/拒绝结果。

推荐 A。不可无限增长的安全边界应一致，而旧 Windows 与 Linux 的体验基线可以诚实分开。三项都要求有界队列、x86 内存上限、单 XML 写放大和取消 deadline 的实测数字。

技术侧必须定义参考机、workload、p50/p95/最大值、回归容忍度和安全余量，并用真实测量提出数字。负责人审核体验等级，不在 200/500 ms 或某个 API 之间凭感觉选择。

关联：`PERF-01` 至 `PERF-03`、`PROD-10`、`TEST-09`、AQ-205、AQ-343。

### RF-10 故障注入与长会话 soak 的执行节奏

deterministic fault/soak invariant（事实一致性、无越权、无自动重放、内存/队列有界）已经是 hard gate；本组只决定每个 release candidate 何时跑完整矩阵。

- A：每个 release candidate 都跑完整 fault matrix 与完整平台 soak。（推荐）
- B：每个 release candidate 跑完整 fault matrix 和缩短版 soak；最终候选的 exact zip 再跑完整长 soak。
- C：每次构建跑共同 deterministic fault 核心；每个平台最终候选的 exact zip 才跑该平台完整扩展 fault 与长 soak。

推荐 A。它最早暴露单 XML、Win32 x86 地址空间、流式 I/O 和副作用恢复问题。三项都要求最终 exact zip 完整通过，任何 deterministic invariant 失败都不能降级为 warning。

技术侧必须枚举每个 durable/side-effect barrier 并选择可重复注入机制；soak 时长、事件数和目录规模由测量与风险曲线决定，不让负责人凭感觉挑“跑 8 小时还是 24 小时”。

关联：`REL-05`、`REL-06`、`PERF-02`、`TEST-04`、`TEST-09`、AQ-344、AQ-345。

### RF-11 readiness 证据保留期

- A：P0/安全/数据/平台门无豁免；原始证据保留所有仍受支持版本及当前候选，稳定摘要/hash 长期保留。（推荐）
- B：同样无硬门豁免；原始证据至少保留当前与前一正式版本，稳定摘要/hash 长期保留；更旧版本失去原附件时撤销 `release-proven` 标记。
- C：同样无硬门豁免；每次 release 全量重跑，只保留当前版本原始附件，所有历史版本保留稳定摘要/hash 和当时的 verification manifest。

推荐 A。它让仍受支持的每一个用户承诺都能回到原始证据；代价是受控证据存储更大。requirement -> decision -> spec -> test -> evidence 是共同放行链，缺证据等于失败；本组只拥有证据保留期。

技术侧必须建立机器可校验的 trace matrix、evidence manifest 和 stale-evidence 检查；测试系统的存储实现与数据库/API 不由负责人选择。

关联：[`ARCHITECTURE-READINESS.md`](../ARCHITECTURE-READINESS.md)、`AQ-350`、`REL-05`、`REL-12`、`REL-13`、`TEST-10`、`DOC-05`。

### RF-12 项目维护到哪一层 Model fixture/adapter support contract

问题：远程 Model 会持续更新，自然语言也不可能逐字稳定。项目必须明确自己长期维护的是可重现 reference fixtures、adapter/capability 契约，还是具体命名远程 Model 的概率性行为声明。

- A：维护 protocol adapter + capability profile 的正式 support contract，并为 streaming/non-streaming、tool call、typed control、side/review/compaction 维护项目内版本化 reference Model/wire fixtures；命名远程 Model 只是配置示例与 self-test 当次观察，不成为永久可用性承诺。（推荐）
- B：在 A 之上维护明确的 named-Model compatibility matrix；每个 release 对清单项运行 reference fixture 与多样本 live evaluation，证据过期/未通过就移除该兼容声明，但不伪称能保证供应商未来行为。
- C：只维护 protocol wire adapter 契约和 malformed/streaming 参考 fixture，不宣称 tool/control/compaction 的 Model 行为兼容；每个已配置 Model 必须经本机 self-test 获得当次 qualified 状态。

推荐 A。它把项目能持续重现的 adapter/capability 不变量与供应商可能随时改变的概率行为分开；B 换取更明确的用户兼容清单，C 承诺最窄。三项都不以“一次能连上”或人工观感替代 Runtime hard gate，也都必须将 fixture 版本与 release evidence 绑定。

关联：`AQ-357`。

确认后 owner artifact：`20-testing-and-agent-evaluation.md` 的所选 Model/能力档/adapter 支持契约、对应 fixture catalog、sample/threshold 规则、hard-gate/statistical-gate 分界和 evidence manifest。

## RF-13 公开文档状态与同步门禁（不是负责人投票）

README、help、schema/template、用户旅程、故障恢复与迁移说明是否准确，是发布正确性问题，不是“喜欢生成还是手写”的产品选择。公开内容必须使用同一状态词表，至少区分 implemented、confirmed-target、proposed/deferred 和 excluded；不得把当前候选或旧草案写成已交付。

CLI help/schema/template 应从同一 typed registry 生成或做机械等价校验；README、旅程、故障、迁移/降级 prose 可以人工维护，但必须链接同一 registry 并作为 hard gate 逐项审阅。“哪些文字生成、哪些人审”由技术证明依可维护性选择；任一公开契约与 exact zip 不符都阻断发布。

关联：`DOC-01` 至 `DOC-04`、`REL-12`、TP-024、TP-030。

### RF-14 Windows x86 发行包的 CPU ISA 基线

问题：“x86 32-bit”不足以说明老 CPU 能否运行；最终 Win32 zip 的指令集底线采用哪条公开契约？

- A：把“能在目标 XP 实机/VM 上运行”作为真实门，构建先采保守 IA-32 基线，对 EXE/DLL/native module 扫描且用旧 CPU fixture 证明；精确 ISA 名称由 luainstaller/toolchain 证据冻结，不靠 compiler 默认。（推荐）
- B：公开要求 SSE2，并在支持矩阵明确排除不支持的旧 CPU；仍要对最终产物扫描/实测。

推荐 A。它把项目已确认的 XP/x86 支持变成最终产物证据，同时不让负责人选择 compiler/API/flag 这种技术事实。B 是明确、可测试的 CPU 支持面收缩；两项都要求对最终 PE/DLL/native module 扫描并在 exact zip 上实测，绝不接受 compiler default。

关联：`REL-14`、`AQ-206`、TP-001、TP-002、TP-030。

确认后 owner artifact：`18-packaging-and-release.md` 的 Windows x86 ISA/CPU support row，以及 ComponentManifest 中每个 PE/native component 的 ISA audit 与实机证据引用。

### RF-15 Release 来源身份签名

问题：RF-06 已独占并保证 zip SHA-256、manifest/SBOM 等完整性材料；本组只决定 v0.1 是否再承诺来源身份签名。

- A：v0.1 不把签名设为 release gate；按 RF-06 发布完整性材料，并明确不声称 hash 等于身份认证。（推荐）
- B：v0.1 必须同时提供可在目标平台离线验证的发行签名；缺签名阻断发布。
- C：签名是可选增强；只有密钥保护、旧 Windows/Linux 离线验证和轮换/撤销证据都通过时才随包发布，但签名缺失不阻断 v0.1，RF-06 材料始终必备。

推荐 A。它不把尚未设计的密钥运营伪装成已有保证。B 提供正式来源认证，C 允许先做充分证明再增强；本组任何选择都不能移除 RF-06 的 hash/manifest/SBOM 决定。

关联：`REL-10`、`SUPPLY-04`。

确认后 owner artifact：`18-packaging-and-release.md` 的 PublicReleaseSet 验证契约；若选 B，追加 signing key lifecycle、offline verifier compatibility 和 revocation/rotation 证据门。

### RF-16 更新发现与下载策略

问题：各平台 zip 可以完全由用户手工获取，也可以由 yaca 显式查询或下载；v0.1 承诺到哪一层？本组只拥有网络发现与 verified acquisition，不拥有程序安装/替换/数据迁移，后者仍由 RF-01/RF-03 决定。D-039 已固定正常启动、help/version、本地配置/Context 管理、静态 self-test 和定时器不得检查或下载更新。

相容性硬门：B/C 只有与 RF-15 B 的强制来源身份签名同时成立才可选。若 RF-15 选择 A 或 C，本组只能选 A，或按冲突协议重开 RF-15；TLS、同一服务器给出的 hash 和未认证 manifest 都不能独立证明更新来自项目发布者。

- A：v0.1 不内建联网更新检查或下载；只显示当前程序/schema 版本，并在文档中给出正式发布位置，用户自行获取平台 zip。（推荐）
- B：提供用户显式执行的只读 `check-update`；只获取有界、版本化且由 RF-15 B 认证的 update manifest，验证版本、目标 OS/架构、RF-06 完整性材料和签名后报告候选 zip，下载、替换和迁移仍由用户在 yaca 之外完成。
- C：在 B 上增加用户显式触发、逐步预览并确认的下载与验证；下载物先进入私有临时目标，按 RF-06 与 RF-15 B 契约验证，再以 no-replace 发布到用户选择的 download path 或明确的 private staging。它绝不覆盖/切换当前程序、不启动 installer、不迁移数据；用户之后按 RF-01/RF-03 的既有 lifecycle 操作。

推荐 A。它与独立 zip、离线旧系统和最小产品面最一致。B 增加 update manifest、TLS/CA/proxy、平台选择与失败状态；C 进一步承担下载截断、残留、磁盘满、目标冲突和 publish，却有意不进入 installer/rollback/migration。三项都禁止启动时、定时器、help/version、本地浏览或普通 `.status` 隐式联网，也不把“检查失败”当作当前版本不可用；B/C 的每次网络动作都必须来自清楚的用户命令，并显示 endpoint、目标平台、预算、取消和结果 receipt。

配置与命令必须跟选择一致：A 下 INI/XML/help/command registry 没有 update endpoint、check/download 开关或后台调度字段；B 只注册显式只读检查动作，C 才增加显式 download 动作；三项都不注册 install/migrate shortcut。B/C 可以消费已经确认的全局 proxy/CA policy，但不得复用 Model Key、遥测 consent 或工具 Network approval；顶层/chat 命令、非 TTY 结果和每种 AgentState 可用性必须从 TU-18/TU-32/CLI-11 的同一 typed action registry 生成。

RF-01/RF-03 组合不改变本组含义：RF-01 A/B/C 只决定用户拿到 verified zip 后使用 portable、installed 或两种入口；RF-03 A/C 的 side-by-side 与 RF-03 B 的“允许覆盖”都发生在下载完成之后。即使 RF-03 B 被选中，C 的 downloader 也不能覆盖正在运行的 application tree；即使 RF-03 C 被选中，C 也不能自动运行 migrate。所谓“内建下载但用户手工安装”正是 C 的有意中间路线，不是遗漏。

关联：`AQ-387`、`REL-11`、`UPDATE-01`、`UPDATE-02`、`CFG-01`、`CFG-02`、`CLI-11`、TU-18、TU-32、D-039、RF-03、RF-06、RF-15。

确认后 owner artifact：`18-packaging-and-release.md` 的 UpdateDiscovery/VerifiedDownload 契约与 D-039 触发矩阵；B 追加 manifest 获取、验证和只读报告，C 追加逐阶段 download/verify/no-replace publish、staging 清理，以及与 RF-01/RF-03 明确不越界的 handoff 表。

发布门：A 路线必须证明发行包没有内建 update endpoint、后台检查或下载入口；B/C 必须在最终 exact zip 上证明启动/定时器/纯本地动作零更新网络，并覆盖旧 TLS、proxy/CA、redirect、manifest 篡改、错误 OS/架构、取消和断网；C 还必须覆盖下载截断、磁盘满、验证失败、崩溃、目标外部修改/no-replace、staging 清理，并证明绝不调用 install/migrate 或覆盖 application tree。任何一项缺证据都不得标记 `release-proven`。

### 完整推荐回复模板

```text
RF-01 A
RF-02 A
RF-03 A
RF-04 A
RF-05 A
RF-06 A
RF-08 A
RF-09 A
RF-10 A
RF-11 A
RF-12 A
RF-14 A
RF-15 A
RF-16 A
```

## 本包确认后必须形成的权威工件

负责人回复后，不是立刻开始写打包脚本，而是按决定形成以下规范：

1. `ReleaseLifecycle`：zip、application tree、data root、安装/升级/降级/卸载状态表，以及逐项消费 M05-42 的 secret-copy policy/eligible-data-set 投影。
2. `PlatformPrerequisites`：luainstaller Win32/x86/XP 前置与 Linux x86_64 baseline。
3. `ComponentManifest`：每平台 allowlist、来源、license、ABI、hash 和依赖闭合。
4. `BuildAndAssembly`：固定输入、luainstaller 输出、外层装配、static audit 与 final zip。
5. `ReleaseEvidence`：六层测试 catalog、失败分类、exact-hash 证据和 release veto。
6. `PerformanceWorkloads`：参考机、workload、测量口径、provisional/final 常量 registry。
7. `FaultAndSoakMatrix`：每个 durable/副作用边界、注入方法和不变量。
8. `TraceMatrix`：requirement、decision、spec、test、artifact、platform、evidence 状态。
9. `UpgradeCompatibility`：程序/INI schema/XML schema 的迁移、只读、拒绝和回滚矩阵。
10. `PublicReleaseSet`：zip、RF-06 所选完整性材料、licenses、README 状态、证据摘要，以及 RF-15 所选签名材料。
11. `UpdateDiscovery`：RF-16 所选发现/下载表面、D-039 零隐式联网触发矩阵，以及 B/C 条件下的 manifest、下载/验证/no-replace publish、RF-15 身份材料与 RF-01/RF-03 handoff 契约。

候选文档不能直接充当这些权威工件。每份最终规格必须删除被否决分支、固定输入输出/失败结果，并能生成可执行验收。

## 负责人回复后的归档顺序

1. 只把明确选择写入 `DECISIONS.md`；“接受大方向”不能自动展开成全部 RF 条目。
2. 若 RF-04 选择 A，先建立 luainstaller 独立目标、范围、设计与测试授权，不在 yaca 仓库暗改。
3. 用 RF-01 至 RF-03 写发布全生命周期；先解决 data root，后写升级脚本规格。
4. 用 RF-05、RF-06 生成 component manifest/SBOM 契约，当前 `bin/` 一律保持未证明状态。
5. 按 RF-07 技术门生成单一可校验追踪记录；用 RF-08 至 RF-10 冻结平台放行、性能测量和故障/soak 节奏。
6. 用 RF-11 冻结证据保留期并填写 trace matrix；用 RF-12 建立正式 Model 支持/验证口径。
7. 按 RF-13 技术门把公开文档同步纳入发布阻断；用 RF-14 固定 Win32 x86 CPU/ISA 公开契约；用 RF-15 固定签名承诺；用 RF-16 固定显式更新范围及其对 RF-03/RF-15 的消费。
8. 重新评估 `AR-P0-16`、`AR-P1-08`、`AR-P1-11`、`AR-P1-12`。

## 本包的完成标准

本包只有在下面问题都有唯一答案时才算决策完成：

1. 用户下载 zip 后是否可以直接运行，是否需要管理员或安装器。
2. yaca 在任何一次启动中只使用哪个 data root，怎样向用户显示。
3. 两个版本并存、升级失败、降级和卸载时，INI/registered-config-secret/XML 哪些绝不会被静默删除或改写，并且 RF-03 不会在 M05-42 之外制造任何 secret 副本。
4. luainstaller Win32/x86/XP 阻塞由谁在什么授权下解除，未解除时 Windows release 怎样保持诚实阻断。
5. 当前 ELF32/i386/x32 痕迹、PE32 与 UPX 文件为什么不能凭文件名放行。
6. 每个进入 zip 的文件能否说明用途、来源、版本、hash、license、ABI 和测试证据。
7. 哪些测试结果拥有 release veto，真实模型评分与确定性不变量怎样分开。
8. “所有平台完整测试”是否绑定最终 zip/hash，缺失一台平台证据时怎样处理。
9. 性能常量何时、在哪台参考机、用什么 workload 形成证据，而不是由负责人猜毫秒。
10. 故障注入和 soak 是否真正阻断数据损坏、无界资源与错误重放。
11. 每个发布承诺是否能沿 requirement -> spec -> test -> evidence 找到仍然有效的证据。
12. 正式支持的 Model/adapter 到底承诺到哪一层，怎样用版本化 fixture 证明。
13. README/help/schema/template 怎样避免把 proposed 写成 implemented。
14. Windows x86 的 CPU/ISA 门怎样由最终 PE 与旧 CPU fixture 证明。
15. RF-06 的完整性材料之外，v0.1 是否还承诺可离线验证的来源签名。
16. v0.1 是否内建更新检查或 verified download；任何存在的入口怎样证明只由用户显式触发、与 RF-15 B 相容，并把安装/迁移明确交回 RF-01/RF-03 而不在启动/定时器中隐式联网。

任何未回复推荐仍然是候选。即使负责人回答完十四个正式组，如果 RF-07/RF-13 技术门、luainstaller 前置、权威规格、真实平台基准或 exact-hash 证据尚不存在，项目也只能说“产品决策已收口”，不能说“已经通过发布门”或“可以凭当前资源直接打包”。
