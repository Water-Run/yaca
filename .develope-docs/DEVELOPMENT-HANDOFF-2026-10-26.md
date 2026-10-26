# 2026-10-26 开发交接

已按 D-098 收束异步粘贴修复、完成打包推送并暂停开发。目标“实现 yaca”未完成，正式 Gate R 关闭。
本节点不再启动下一批实现、来源查找或目标部署；剩余队列见 [TRACKING](TRACKING.md)。

## 本次交付

开发预览为
[`v1.0.0-preview.20261026`](https://github.com/Water-Run/yaca/releases/tag/v1.0.0-preview.20261026)。
维护源码以 main 为准，附件的源码提交、核心与各项摘要见 `NODE-MANIFEST.json`、
`SHA256SUMS.txt`。12 个附件共 74,876,771 字节，实际 GitHub 服务端摘要与大小全部匹配；
tag 对应源码提交已核对。见 [发布回执](candidates/1.0.0-preview.20261026-publication.json)。
附件固定在代码提交 `5fe13de3c854309adf1441d609ebbf8b650df0f6`，后续 main 只补交付记录。

| 附件 | 用途与边界 |
| --- | --- |
| Win32 / Win64 ZIP | 当前本机通过回归的单文件核心，含上手说明与许可证；目标资格待完成 |
| `linux-x86_64-host` ZIP | WSL 本机回归核心；不代表 CentOS 7/glibc 2.17 资格 |
| 各平台 `core-sources` tar.gz | 当前维护源码、生成的 launcher/extractor/payload 与保留的第三方来源；旧报告只描述其原始基线 |
| `yaca-source-20261026.tar.gz` | 当前维护源码，不含构建缓存、模型私有配置或 Context |
| `yaca-main-20261026.bundle` | main 的完整提交历史，可离线恢复 |
| 开发证据 ZIP | 复现、原生故障、完整 suite、实际终端、PE 审计及 readiness 的公开记录 |
| `DEVELOPMENT-START.md` | 下载、恢复与接续说明 |

此次推送包含 10 月 23 日的三个功能提交和日终交接，以及本次异步粘贴修复。
源码提交与随后只补交付回执的提交分开，便于核对归档和实际核心。

## 修改与验证

原同步剪贴板在隔离延迟夹具下阻塞按键处理 422 毫秒。现独立有界读取，按键分发为
0 毫秒；完整接纳后回放后续编辑/Enter，取消、超时和迟到结果不会插入旧文本。
拒绝粘贴只丢弃后续按键，保留 terminal outcome；输入队列有字节和观察项上限。
实现、失败、注释语义 Review 与所有权边界见 [本轮 Review](CODE-REVIEW-2026-10-26.md)。

最终 WSL Lua、Win32 单文件和 Win64 单文件各 756/756；完整 readiness 退出零。
原生剪贴板严格文本、九项原分配失败、七项开始发布失败、六项结果发布失败，以及
取消、超时和单个读取上限通过。reader/生命周期、输入故障及 54 项键盘分配故障通过。
全仓注释结构覆盖为 276 文件 / 5914 声明 / 0 缺项，全仓人工语义 Review 仍为 partial。

最终字节的 Windows 两协议/两架构控制台、Linux 40/80 列 PTY 与 dumb 后备、12 项
PE 导入审计均通过。完整 bundle 已独立 clone，756/756 通过，运行后检出干净；新 ZIP 的
三个核心字节及三套来源的当前源码/generated 成员与原构建输入逐字核对通过。
所有重活经资源守卫串行，具体失败与通过日志保存在公开开发证据 ZIP。

| 核心 | SHA-256 |
| --- | --- |
| Win32 | `44b43cf18bb6a797bb329a2d5d085d9d3586c89e882e074f14be03cbba106131` |
| Win64 | `8560e04ea3de5022e14833e2e9456600fd32b2a13e168f2395cdcc28f1394aa7` |
| Linux 本机 | `dec17c7f68a3a6006f120b01f949455aa37445faef71dc08d4959f790b2bb55d` |

维护源码归档为 502 个文件，SHA-256 为
`59f6dfa3c1df336fd5a5601b1ef679dc0bb8ca9452ed5f94c3068a0b4353b977`。

## 接着开发

已有检出可 `git pull --ff-only origin main`。离线时用附件 bundle clone，再将 origin
设为 `https://github.com/Water-Run/yaca.git`。开发初始化和检查入口见
[资格执行手册](QUALIFICATION-RUNBOOK.md)。不要依赖本机绝对缓存路径接续开发。

恢复后先检查等待期间重复粘贴手势的顺序、真实跨程序延迟剪贴板、IME/字体、Cygwin、
动态缩放和长会话，再按 TRACKING 推进指定环境与最终九包。当前等待的第二次粘贴手势会
忽略，未把该交互限制写成完成。来源闭包、签名新鲜度、完整二进制对应关系和 Gate R 均保留。

10 月 23 日的截止 heartbeat 已保持 PAUSED；实现 yaca 目标按负责人要求暂停。
本节点结束时没有仍在运行的候选或测试进程。
