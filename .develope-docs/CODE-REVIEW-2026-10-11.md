# 恢复开发与关闭、压缩边界 R87--R88

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

## R88 压缩响应身份先于时钟与重试

完整通读 compact.lua 的参数/返回/副作用注释与实现：canonical event/summary/manifest
编码、输入限额、union-find 原子分组、完整前缀切点、ModelView 容量、意图和精确回执、
两次尝试、响应/发布绑定、取消、自动断路器及恢复冷却。发现 accept_response 在身份
核对前读取时钟并处理超时。第一尝试的晚到响应可取消正在运行的第二尝试；未知或缺少
ID 的对象还可能消耗当前重试与回执。

现在只接纳当前 request_id 的 envelope；旧、外来、缺少身份或非 table 的 envelope
先返回 StaleCompactionResponse，未读取时钟、启动/取消 Model 或写入 journal。
已绑定响应的时钟、超时、schema、摘要、容量与发布顺序不变。

新回归包含晚到/时钟失败/外来 ID/缺少 ID/非 table 五个边界，核对当前 ID、attempt、
Model 启动与取消次数、journal 数量及 generation 不变，随后当前真实响应仍能完成。
基线专项 **12/13**，失败为晚到响应触发当前取消；修复 **13/13**，完整 suite **715/715**。
完整 readiness **PASS**，结构为 **252 文件 / 5572 声明 / 0 缺项**，包含新的输入恢复工具。
源码、当前维护回归、精确基线及原始日志见 [R88](lua-review/R88.json)。
该结论覆盖 compact.lua 全册；生产 main 组合层、其他剩余原生/辅助代码与正式资格
继续保留待完成，全仓语义 Review 仍为 partial。

## 工具输入恢复与来源缺项

24 个原 R81 附件已恢复并逐件核对 publication 的大小和 SHA-256。
维护工具 restore_edition_inputs.py 验证 runtime/notices 的真实成员、CRC、摘要、版本、
SPDX 和路径，只恢复 tools、对应附件及索引；旧核心和其资格不作为新核心证据。
三目标各十工具恢复通过，三项独立回归通过，支持替换核心后重新装配，并拒绝错目标
与修改过的归档。恢复工具、测试的每个参数、返回、所有权和写盘边界已人工核对。

Linux SDK 存在 xt_CONNMARK.h / xt_connmark.h 等大小写不同的真实成员；NTFS 暂存
在新文件排他创建时正确拒绝。维护工具补齐 Linux 区分大小写的文件系统预检，本轮
Linux 输入移至 `/home/linzh/.cache/yaca-release-readiness-20261011/tool-inputs/linux-x86_64`，
两个 Windows 输入在 `out/review-20261011/recovered-tool-inputs/`。保留失败日志，
未重命名头文件或改变归档字节。缓存恢复不是新的运行或发布资格。

来源附件实查发现两 Windows 各三个缺项：Git、w64devkit 的 source_archive 是 MZ
二进制分发，Python 3 的 closure 仅包一份 portable ZIP。摘要与二进制版本通过不能
代替对应源码及依赖来源。检查记录为 `out/review-20261011/tool-source-inspection.json`；
当前正在按官方标签、版本和摘要取得真实对应源码与构建输入，Source 审计未完成。
上游 w64devkit v2.9.0 的 Dockerfile 已经由 HTTPS 取得并解析其版本/摘要资料；
未执行上游构建命令，也未沿用其中的 TLS 跳过选项。
