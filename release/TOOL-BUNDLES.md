# 发行分档与默认 tools 清单

整理日期：2026-09-22。用户已确定：Lua 解释器内嵌在 yaca；每个平台发行 clean、std、
重版本三档。用户已选择重版本为开发工具箱；暂命名 `full`，按平台兼容性取舍。
三档装配、内嵌解释器、可选 tools 说明及相关 manifest/契约已实现。默认版本仍是
待逐目标验收的候选；机读清单为 [tool-bundles.json](tool-bundles.json)，
win32 std 的来源哈希为 [tool-sources.lock.json](tool-sources.lock.json)。

## 1. 三个版本使用同一个 yaca

同一 release、同一平台的三档使用完全相同的 yaca 二进制和核心功能，SHA-256 相同。
分档只决定是否携带 `tools/` 以及其中内容。推荐日常下载 std。

| 版本 | 运行包内容 | 适用情况 |
| --- | --- | --- |
| clean（干净版） | 只有 `yaca.exe`，Linux 为 `yaca`；Lua 已在其中 | 最小携带、使用系统现有工具或用户自备工具 |
| std（标准版） | clean + Python 2.7、SSH/SCP/SFTP、curl、7-Zip | 常见脚本、远程命令、文件传输、下载与解压 |
| full（重版本） | std + Git、Python 3、C/C++ 编译/构建工具、SQLite、jq、文本工具 | 无需安装开发环境即可完成代码修改、脚本与编译验证 |

“只有 yaca”指分发时的运行文件：不要求旁置 `lua.exe`、Lua DLL、配置模板或安装脚本。
运行后仍按既有规则生成相邻 `__yaca__` 保存配置与历史。核心网络/解析等必要依赖
仍由 yaca 自包含交付；onefile 的私有提取是实现细节，不由用户手工组装。
许可、源码、构建材料及使用文档作为配套发行附件提供，并保持离线许可查看入口；
具体嵌入/附件装配沿用项目既有许可与源码交付要求核对，不为 clean 略去这些材料。

## 2. 内嵌 Lua 的调用方式

Agent 使用正式内置 `lua` 工具，输入 `code` 和可选 `args`、`cwd`、`deadline_ms`。
代码经匿名 stdin 输入，参数使用结构化 argv，不经 shell，不要求旁置解释器。
手动使用时也提供 yaca 自身的解释器入口，采用锁定官方 Lua CLI：

```text
yaca.exe --lua -v
yaca.exe --lua -E script.lua arg1 arg2
yaca.exe --lua -E -e "print(6 * 7)"
yaca.exe --lua -E -
```

`-E` 忽略外部 Lua 初始化环境变量。`lua` 工具直接启动已运行的 yaca 内层程序，
避免旧 Windows 不支持嵌套 Job 的限制，由父进程管理输出、退出码、超时、取消。
解释器模式在新进程中使用内嵌 Lua，和核心取同一源码/完整版本，当前锁定为 5.5.1。
不运行第二份外部 Lua、不把模型脚本直接注入持有 Context/Key 的主 Lua 状态。
该入口不依赖模型配置、tools、聊天 TTY 或历史，不递归启动 AgentLoop。
它是解释器入口，不扩展为通用远程/headless Agent API，也不新增一套工具调度框架。

保持既有 Shell 权限与副作用语义；同一 exe 的子进程也必须能被超时/取消收拢。
内部重入标志不能绕过权限：直接运行解释器与直接运行其他本机程序一样拥有用户权限。
`--lua -v` 应显示完整构建版本；`_VERSION` 的主次版本输出不足以证明 patch 版本相同。

## 3. 默认组件版本清单

下表为当前建议输入版本。除 Lua/curl 已在核心依赖锁中外，其他组件须在 F3 完成
来源、构建选项、依赖闭包、许可证、SHA-256 和各平台 smoke test 后才进入正式锁文件。
“存在 x86 二进制”不等于“通过 XP 验收”；不静默用系统同名工具充数。

| 组件 / 建议版本 | clean | std | full | 交付与用途 |
| --- | --- | --- | --- | --- |
| Lua **5.5.1** | 内嵌 | 内嵌 | 内嵌 | 与核心共享锁定版本，经 yaca 自身入口调用；不是 tools 文件 |
| Python **2.7.18** | — | 有 | 有 | `tools/python2/`；解释器、标准库及运行库闭包，用于兼容脚本 |
| PuTTY CLI **0.85** | — | 有 | 有 | `tools/ssh/`；`plink`、`pscp`、`psftp` 提供 SSH/SCP/SFTP；不带 GUI/Pageant |
| curl **8.21.0** | 核心内部使用 | 另提供 CLI | 另提供 CLI | `tools/curl/`；复用核心已锁定的目标构建及 CA，不暴露内部认证载体 |
| 7-Zip **26.03** | — | 有 | 有 | `tools/7zip/`；Windows CLI 及所需库，Linux 对应 `7zz`；不装 Shell 扩展 |
| SQLite **3.53.4** | — | — | 有 | `tools/sqlite/`；`sqlite3`、`sqldiff`；作为外部工具，不变更 yaca 历史存储 |
| jq **1.8.2** | — | — | 有 | `tools/jq/`；JSON 查询、筛选、转换 |
| BusyBox Windows **FRP-6075-g169694ebd** / Linux **1.37.0** | — | — | 有 | `tools/busybox/`；固定常用文本/文件 applets，不替换系统 shell |
| Git（下表分平台） | — | — | 有 | `tools/git/`；完整运行闭包，不只复制 git.exe |
| Python 3（下表分平台） | — | — | 有 | `tools/python3/`；与 Python 2 分开说明版本和入口 |
| C/C++ 开发工具链（下表分平台） | — | — | 有 | `tools/devkit/`；编译器、链接器、构建命令及所需头文件/库 |

Python 2.7.18 是 Python 2 最终版且已结束支持，按用户要求保留为兼容工具。
核心 HTTPS 与启动不依赖它；默认不附带 pip/第三方包自动安装流程。
测试至少覆盖 json、csv、re、hashlib、zipfile、sqlite3、ctypes、encodings 等声明能力。

SSH 默认选择 PuTTY 的命令行工具，Windows 与 Linux 均按对应平台生成原生产物。
Agent 收到真实程序名与参数说明，不把 Plink 假称为 OpenSSH 命令语法。
PuTTY 需要验证无注册表写入的调用方式（例如显式核实并传入 host key、避免保存会话）；
不能仅因 exe 可直接下载就宣称绿色。若候选无法满足目标兼容/绿色要求，修正构建或
明确换选版本并更新清单；不把未经验证的程序塞进 std。

BusyBox 首批只声明实际编入且通过检查的 awk、sed、grep、find、diff、head、tail、
sort、uniq、wc、hexdump 等 applets。Windows 若开发包已有同一产物就复用并登记其路径，
不重复塞两份；不向系统目录铺链接。Linux 不借用现代宿主库冒充兼容。

### full 的开发组件候选

| 目标 | Git | Python 3 | 编译/构建工具 |
| --- | --- | --- | --- |
| win32-x86 / XP SP3 | Git for Windows **2.10.0** Portable | CPython **3.4.10** 目标构建 | **w64devkit 2.9.0 x86** 的 XP 可用子集：GCC/G++、Binutils、Make 等；见 CPU/组件限制 |
| win64-x86_64 / Win7 SP1 | Git for Windows **2.46.2** Portable | CPython **3.8.20** 目标构建 | **w64devkit 2.9.0 x64**；按 Win7 实测保留构建/调试组件 |
| linux-x86_64 / CentOS 7 | Git **2.55.0** 目标构建 | CPython **3.14.7** 目标构建 | **GCC 13.5.0 + Binutils 2.47 + Make 4.4.1**，可搬移目录与目标 sysroot |

这些是可执行的选型起点，不表示已有便携成品。Python 3.4.10/3.8.20 的官方对应发布
只有源码，不能把更早的 Windows 安装包改名当作这些版本。其分支已结束维护，清单
明确标为旧系统兼容版本；Agent 必须知道实际语法/库版本，不能默认都有现代 Python 特性。
Linux 组合需在 CentOS 7 基线构建并证明 kernel/glibc 兼容，不直接搬开发机二进制。

Python 官方还注明 Win7 上的 Python 3.8 需要 KB2533623，嵌入包不会替用户检测它。
因此 3.8.20 只是候选：必须验证 app-local CRT 和未安装该补丁的干净机；若仍有系统
前置条件，采用可验证的兼容构建或调整该目标版本清单，不让用户为 full 临时装补丁，
也不把官方嵌入 zip 直接称作已达成开箱即用。

w64devkit 上游说明 x86 工具链需要 SSE2；CMake、Ninja、CCache 至少需要 Win7。
XP full 不带/不宣告这三项及不支持 XP 的 C11 threads 能力；编译器的 SSE2 要求
必须在 full 清单和能力摘要显式列出。若机器无 SSE2，应使用 clean/std 或另外验证
兼容编译器，不因此提高 yaca 核心的 CPU 要求。Win7 的 Unicode 路径限制也需独立验收。
工具链可运行与它生成的程序可运行是两项检查：C/C++ 样本须在该目标上实际编译、链接、执行。

Linux devkit 需要可重定位的编译器、Binutils、运行库、头文件、启动对象和相应 sysroot；
不能只带 gcc/g++ 再要求目标机安装 devel 包。环境只对工具子进程生效。
Git 保留所需脚本/helper/TLS 运行闭包；旧 Windows Git 的远程兼容必须单独测，
不能借 std curl 可联网就声称 Git clone 可用。

Node、其他语言 SDK、file/iconv 和驱动型网络工具暂不列为默认项，可按需要自行增补。
full 不设置人为包体积目标，也不改变通用 Agent 的定位。

## 4. 平台与包名

延续原来三个目标，每个目标三档，共九个计划发行物：

| target | 最低目标 | clean / std / full |
| --- | --- | --- |
| `win32-x86` | Windows XP SP3 x86 | 三档，各自验收 |
| `win64-x86_64` | Windows 7 SP1 x64 | 三档，各自验收 |
| `linux-x86_64` | CentOS 7 x86_64 | 三档，各自验收 |

包名统一为 `yaca-<version>-<target>-<edition>.zip`，例如
`yaca-<version>-win32-x86-clean.zip`、`...-std.zip`、`...-full.zip`。
版本号使用当次实际产品版本，不因为换工具组合另造核心版本。
指定 Server 2008 是 win32 候选的附加实测环境，不能替代 XP/Win7/Linux 资格。

工具允许按目标选择不同版本/子集，清单明确差异；不悄悄提高核心最低系统要求。
若某项在最低目标不可交付，先调整该目标清单并说明能力/CPU 差异，再完成资格。

## 5. 工具说明与增删

std/full 的 `tools/README.txt` 或简单描述清单提供版本、相对位置、用途和用法摘要；
详细许可/来源材料随工具包交付。该清单不是强制注册表，也不是插件配置。
Agent 可以使用系统工具和用户自备工具；内置 Lua、随包工具、系统工具标明来源。
用户删除整个 tools 后，核心应与 clean 等价；删掉单项只改变该项能力说明。
不修改系统 PATH/注册表/服务，不自动下载补件，不在发现阶段执行程序或连接远端。

## 6. 实施与验收增量

1. **内嵌 Lua 入口**：在早期入口识别解释器模式，接入既有进程与权限；验证无配置、
   无 tools、中文路径、脚本参数、stdin/stdout、异常、超时、取消及完整版本一致性。
2. **分档装配**：同平台只构建一次核心；clean 运行包只有 yaca；std 增加标准闭包；
   full 在同一 std 上追加工具；三档核心哈希一致，移除 tools 不影响核心运行。
   核心哈希一致时复用同目标的核心测试证据；三档包布局、启动旅程与附加工具分别验收。
3. **工具资格**：每个目标/组件独立记录版本/哈希/许可证、依赖、运行结果和数据落点。
   SSH 验证真实连接/文件传输/host key；curl 验证 CA/代理；7-Zip 做打包与解包往返；
   Python 和 full 工具执行实际样本；Git 完成本地仓库与受控远程操作，C/C++ 项目
   实际编译/链接/运行，Python 2/3 入口不串用；均在无系统同名工具的环境验证。
4. **契约传播**：将旧“每平台一个包/固定根项/一律禁止这些外部工具”的规则改为
   core 与 edition 两层；更新 package-layout/loader/release fixtures。
   SQLite 等进入 full 不授权将其引入核心存储，也不引入 MCP/插件/后台服务。

这些是原有计划的有限增量，不要求先换 AgentLoop、默认值或历史格式。
当前机读发行状态仍为 unqualified，Release Gate R 关闭。

## 7. 构建与装配

核心由既有平台构建脚本生成。Win32 std 另使用
`.tools/qualification/build_win32_std.sh SOURCE_CACHE CORE_BUILD MSI_INVENTORY_TSV NEW_OUTPUT`：
先核对 `tool-sources.lock.json`，提取 Python 的标准库/DLL 与完整 app-local VC90 CRT，
交叉编译便携 PuTTY CLI，并复用核心的 curl/Mbed TLS/CA。MSI 布局由
`msi_inventory.c` 以只读数据库查询取得，不安装 Python，不执行安装动作。
PuTTY 补丁拒绝 HKCU 设置和持久随机种子文件；连接使用明确、可信的 `-hostkey`，
不能采用会跳过主机密钥校验的 no-storage stub。
DLL 与 `.pyd` 同 exe 一并保留执行权限，兼容 Cygwin unzip 的 NTFS ACL 映射。
`windows_std_smoke.py <解压目录>` 检查迁移后的 Python 来源与归档回读；网络检查
另需 `--ssh-host` / `--ssh-host-key`、`--https-url`，没有默认联网或内置凭据。

装配使用构建机 Python 3，运行时无需 Python 3：

```sh
python3 .tools/package_editions.py --target win32-x86 \
  --core /build/package/yaca.exe --core-sha256 <SHA256> \
  --core-notices /build/companion \
  --tool-inputs /tool-build/staged/tool-inputs.json \
  --edition std --output /new-output
```

clean 可省略 `--tool-inputs`；`--edition all` 需要完整 full 输入，不能以 std 内容充数。
输入 JSON schema 为 `yaca-tool-inputs-v1`，顶层有 `target` 与 `tools`。
每个工具声明 `id`、`version`、`entry_points`、`license_id`、`license_files`、
`source_url`、`source_archive`、`files`。文件项包含相对清单的 `source`、包内
`destination`、`sha256`、可选 `executable`；源码项包含 `source` 与 `sha256`。
`prepare_win32_std.py` 生成可直接使用的示例。

输出包括运行 zip、`-notices.zip`、`SHA256SUMS.txt` 和 `editions.json`。附件含工具
对应源码、edition SBOM 与逐文件哈希；核心依赖细节保留在随附 core SBOM 中。
核心对应源码和重链接材料仍须随核心构建附件一起分发。所有输出保持 candidate，
装配通过不等于目标系统资格通过。

## 8. 版本来源与兼容性证据范围

- Lua/curl：仓库 [dependencies.lock](dependencies.lock) 与 [manifest.lua](manifest.lua)。
  curl 8.21.0 是沿用已锁定候选，不在本轮随网页版本自动升级。
- [Python 2.7.18 官方发布页](https://www.python.org/downloads/release/python-2718/)：
  最终 Python 2 版本、源码及 Windows 安装产物；安装产物须整理为已验证便携闭包。
- [PuTTY 官方下载页](https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html)：
  本次查询为 0.85；[官方 FAQ](https://www.chiark.greenend.org.uk/~sgtatham/putty/faq.html)
  明确旧 Windows 兼容可能随版本变化，不能将 0.83 的 XP 结果外推给 0.85。
- [7-Zip 官方页](https://www.7-zip.org/)与[下载页](https://www.7-zip.org/download.html)：
  本次查询为 26.03；官网列出 XP 等系统，但 yaca 的具体 CLI 组合仍需实测。
- [SQLite 下载页](https://www.sqlite.org/download.html)：3.53.4 源码与工具；
  Windows x86 DLL 的存在不等于提供了满足 XP 的 sqlite3 CLI。
- [jq 下载页](https://jqlang.org/download/)：1.8.2 与目标产物，最低旧系统兼容须另证。
- [busybox-w32 标签](https://github.com/rmyorston/busybox-w32/tags)：固定 FRP-6075-g169694ebd；
  [Linux BusyBox 下载](https://www.busybox.net/downloads/)：选择 1.37.0 作为初始构建候选，
  不追每日 snapshot；两者独立构建，不把 Windows 移植版当 Linux 相同版本。
- [Git for Windows 官方要求](https://gitforwindows.org/requirements.html)：XP 最后支持版为
  2.10.0，Win7 为 2.46.2；[Git 官方页](https://git-scm.com/)本次列出 2.55.0 源码版本。
- Python [3.4.10](https://www.python.org/downloads/release/python-3410/)、
  [3.8.20](https://www.python.org/downloads/release/python-3820/)、
  [3.14.7](https://www.python.org/downloads/release/python-3147/)；
  [Python 3.5 的 XP 支持变化](https://docs.python.org/3/whatsnew/3.5.html)说明旧系统分支边界。
  [Python 3.8 Windows 文档](https://docs.python.org/es/3.8/using/windows.html)列出 Win7 的
  KB2533623 前置条件，属于便携资格必须处理的已知缺口。
- [w64devkit 2.9.0](https://github.com/skeeto/w64devkit/releases/tag/v2.9.0)及
  [该版本系统要求](https://github.com/skeeto/w64devkit/blob/v2.9.0/README.md)：x86/x64、SSE2、
  部分工具的 Win7/Unicode 边界；2.9.0 发行说明列出 Binutils 2.47。
- [GCC 官方发行列表](https://gcc.gnu.org/releases.html)：13.5；
  [GNU Make 4.4.1 公告](https://lists.gnu.org/archive/html/info-gnu/2023-02/msg00011.html)。

以上为版本选择依据；后续实际构建/运行结果以本轮实现记录与各候选目录的证据为准。
