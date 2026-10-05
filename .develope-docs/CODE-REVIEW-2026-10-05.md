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
