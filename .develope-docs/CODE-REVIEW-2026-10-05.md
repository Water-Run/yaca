# win32 full 最终包在 Server 2008 的干净机旅程

日期：2026-10-05。基于 `caa7860`。九包 9/9 无挂账后，按 TRACKING C33
推进 win32 版位的干净机旅程：最终装配件
`yaca-0.1.0-win32-x86-full.zip`（`96fc32cf...`，10-02 第四批）在指定实机
Server 2008（192.168.5.10，D-077 指定环境）以 std 版 7za 自举解包，
逐项走完布局/零表面/工具面/便携性/卸载。

| 旅程项 | 结果 |
| --- | --- |
| 自举解包 | std 7za.exe 解包成功；布局为 `yaca.exe` + 10 工具目录 + README |
| 核心一致性 | 实机以包内 py34 hashlib 复算 SHA-256 = `acd58d83...`，与构建件/装配件逐字节一致；亦是 py34 闭包在最低目标面的首次原生实测 |
| 非 TTY 拒绝 | 无 pty 时 `--status` 报 `TtyRequired` 且**零写入**（无 `__yaca__`） |
| 首次状态 | pty 下 `--status` 如实 `ConfigMissing`/`agent ready: false` |
| Stage 1 自检 | 建立隔离 `__yaca__` 后 **12 PASSED + 2 WARNING（配置未初始化，设计内）、0 FAILED、online-requests=0**；含 ATOMIC-WRITE、CONTEXT-CATALOG/LOCK、CA-BUNDLE、ZERO-SURFACE |
| 工具面（原生） | busybox、**git 2.10.0.windows.1**（wine i386 崩溃确认非产品问题）、Python 2.7.18、py34（hashlib/jq 输入）、jq `42`、make 4.4.1、**gcc -O2 编译链接运行 `s2k8-gcc-ok`**（PATH 含 compiler\bin；`as` 需 PATH 为既定行为） |
| 移除 tools | 改名移走后核心 `--version` 与 `--lua -E -e print(6*7)`（42）照常——与 clean 等价性在实机验证 |
| 整体移动 | 目录 move 后核心与 py34 闭包照常运行、哈希复算一致 |
| 网络 | 局域网 qwen 端点（spark:30000）可达（无密钥 401，密钥在不可达的 WSL2 机隔离目录）；出网 TLS 被路径上的拦截代理重签（呈现证书签发者 `C=US, O=Let's Encrypt, CN=YR1`，非真实 LE 中间人链）——**固定 CA 按设计正确拒绝**；未拦截出网 TLS 已由 R74 轮 Win64/DeepSeek 覆盖 |
| 卸载 | 删除目录后 C 盘与 HKCU 注册表零 yaca 残留 |

如实保留的剩余项（C33）：交互式聊天与多轮恢复的 TTY 旅程、持密钥的
授权模型往返（密钥在 WSL2 机）、win64 full 于 Win7 实机、linux full 于
CentOS 7 实机的对应旅程、九包统一 SHA-256/许可/SBOM 汇总（C34）后评审
Gate R。本轮产品源码与装配零改动，无新增提交需求（本文档与状态更新除外）。

### win64 full 最终包在 Windows 主机的旅程（10-05 续）

同日以 `yaca-0.1.0-win64-x86_64-full.zip`（`ade7ea70...`）在现代 Windows
宿主（192.168.10.104，Win11 26100）走完同型旅程；诚实边界：这是现代宿主
面，Win7 SP1 最低目标面仍属 C33。

| 旅程项 | 结果 |
| --- | --- |
| 解包与完整性 | Expand-Archive 解包；上传 zip 实机哈希 = `ade7ea70...` 与装配件一致；zip 实际 14648 文件全数解出（并以此纠正第三批记录中 14741 的误计） |
| 核心一致性 | 实机 Get-FileHash 复算 `a81a3f32...` 与构建件逐字节一致 |
| Stage 1 自检 | 计划任务内 **12 PASSED + 2 WARNING（配置未初始化）、0 FAILED、online-requests=0**（含 TTY-INPUT PASSED）；pty 直连会进 TUI，输出被终端转义吞没，以计划任务重定向取证 |
| 工具面 | yaca 0.1.0、py3.8.20/OpenSSL 1.1.1w/sqlite 3.35.5、git 2.46.2.windows.1、jq 管道、gcc 编译运行 `w64j-gcc-ok`（PATH 含 compiler\bin） |
| 移除 tools / 移动 | 改名移走后核心 `--version` 与 `--lua`（42）照常；目录 move 后核心运行、哈希复算一致 |
| 卸载 | 删除目录零残留；zip 与临时件清理，计划任务删除 |

win32/win64 两个 Windows 版位的 C33 旅程至此同型收口。剩余：linux 版位、
TTY 交互与授权模型往返、九包汇总（C34）。

### linux clean 版位随 HEAD 重建与 C7 容器旅程（10-05 终章）

Fedora 宿主如实拒绝 linux 核心构建（脚本检查 `/etc/centos-release`），
按 10-01 先例在 Docker `centos:7` 容器（vault=archive.kernel.org 源，
GCC 4.8.5-44.el7，与记录环境一致）内执行：

- **核心随 HEAD（`3a61427`）重建 PASS**：源码归档以 `git archive HEAD`
  生成（`17ce3515...`）；构建内嵌完整 Lua suite **699/699**；
  onefile `e7bb24ede41f9919803ed2f6a775eca51e3018b93027616dea012595393c6daf`，
  构建摘要 status=PASS。容器以 root 写挂载目录的权限边界以辅助容器
  收拾，如实记录。
- **clean 版位装配 editions=PASS**：companion 按既有 notices 形状从
  构建源码树重组（Expat/Mbed-TLS/curl/Lua/LuaExpat/luainstaller 许可 +
  Mozilla CA + build-summary + LINUX-QUICKSTART）；
  `yaca-0.1.0-linux-x86_64-clean.zip` = `1088d979...`（3.5 MiB）、
  notices `b7fa2147...`。
- **C7 干净机旅程**（`docker run -t` 提供 TTY）：解包布局 `yaca` 单文件；
  容器内哈希复算 `e7bb24ed...` 一致；`--version` 正常；**Stage 1 自检
  12 PASSED + 2 配置 WARNING / 0 FAILED**（含 TTY-INPUT PASSED）；
  `--lua` 输出 42；整体移动后运行正常；删除后零残留。

三平台 C33 旅程子集（布局/哈希/Stage 1/工具面/移动/卸载）至此各走一遍：
win32（Server 2008 实机，full）、win64（现代 Windows 宿主，full）、
linux（C7 容器，clean；std/full 的最终 zip 在 WSL2 机，待其回归后走同型
旅程）。剩余：TTY 交互与授权模型往返、Win7 最低面、九包统一汇总（C34）
后评审 Gate R。产品源码零改动。
