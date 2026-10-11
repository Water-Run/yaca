# 恢复开发与终端收尾 R87

日期：2026-10-11。负责人按 [D-085](DECISIONS.md#d-085-同步仓库并推进至可发布就绪2026-10-11)
要求同步并推进到可发布就绪。本轮已拉取 `origin/main`，远端无新增提交；本地保留
R82--R86 的 7 个提交，从 `a1f47d8` 接续。指定 Server 2008 的 Cygwin SSH 可达。

## R87 已释放终端的收尾确认

R84 保留了首次 restore 错误的优先级，即使随后 native close 已完成实际恢复和关闭。
Lua port 此时正确记录 closed，但再次 close 只抛出“terminal port is closed”。
R86 协调器因首次错误保留 owner 后，无法再确认此前已经完成的释放，持续保持 closing。

终端 close 现对已确认释放的 owner 幂等返回 true，不重复调用 native restore、join 或 close。
首次调用仍如实报告较早的恢复错误；原生关闭失败仍保留相同 started/joined owner 供重试。
未启动端口的 close 继续拒绝，失败运行不会因随后清理成功被改写为成功运行。

新增真实 coordinator 与 terminal adapter 的组合回归，故障注入在 native 边界：
两次显式 restore 失败，随后 native close 完成其内部恢复并释放。协调器第一次运行
报告 TerminalRestoreFailure，第二次清理确认已释放 owner 并转为 closed；join 与 native close
均只执行一次。既有 adapter 回归补齐关闭失败后恢复和关闭成功后确认的控制。

精确基线加当前维护回归为 **50/53**，三个失败均为关闭确认；修复后相关三套为
**80/80**，完整 suite **714/714**，完整 coding readiness **PASS**，全仓结构
**250 文件 / 5563 声明 / 0 缺项**。首次 readiness 命令因未引用含空格的 PATH 而未启动，
随后使用完整注释的独立辅助脚本运行正式链，未修改检查器或降低退出码。

关闭方法的返回、首次错误优先级、重复调用、失败 owner 保留和副作用，以及所有新增
native callbacks 已逐项人工核对。来源与实际日志见 [R87](lua-review/R87.json)。
本批未修改原生 C；R86 核心与 R81 已交付包仍保持原源码范围，后续最终核心须重新绑定。
全仓语义 Review、最终九包与 C32/C33/C34 继续执行，Gate R 尚未开启。

## 模型与输入恢复

负责人本轮重新提供 DeepSeek 输入及经内网 Linux 主机进入 DGX Spark 的入口。
凭据只保存到私有验收缓存，未进入 Git 或公开证据。两端模型发现均返回 200：
DeepSeek 为 deepseek-flash / deepseek-v4-pro，DGX Spark 为 qwen3.8-27b。
模型发现不代替实际生成、工具或恢复旅程。

R81 预发布 std/full 输入按已提交 publication 的大小和 SHA-256 续传核对，
尚未完成的文件保持 partial，不接纳为装配输入。旧输入恢复不继承旧核心资格。
