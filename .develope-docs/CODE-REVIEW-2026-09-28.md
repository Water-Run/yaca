# 编码与区间读取 Review

日期：2026-09-28。基线：`9aed60f`（产品源码来自 `32d053e`）上的本批修正。
接续 [R01--R22](CODE-REVIEW-2026-09-22.md)，本轮集中审查旧编码与区间读取，
不代表全仓人工语义 Review 或目标资格已完成。

## 已复现并修复

| 编号 | 缺陷 | 修正与证据 |
| --- | --- | --- |
| R23 | POSIX 把 ISO-8859-1..9 转为 glibc 不接受的 `CP2859x`，把 Windows CP874 转为缺少扩展字符的 TIS-620 | 使用对应 ISO 名称及 CP874/CP950；原生 Linux 上 Latin-1 原来报 EncodingUnavailable，CP874 的欧元符号报 InvalidEncoding，修正后通过；新增映射回归与 12 组原生往返探针 |
| R24 | UTF-16 的 CRLF 跨奇数字节分块时拆成两个终止符；末尾半个码元被丢弃；一个孤立代理项使整行显示为一个替换字符 | 等待完整的下一码元后判断 CRLF；保留末尾字节与 raw span；逐个修复无效码元并标记 lossy，保留周围文字。三个定向反例先失败、修正后通过 |
| R25 | 一行超过扫描预算时，续页仍从该行开头重读，重复调用无法前进 | 续页只保留有界行前缀、已消费字节数与行起点；未完整的终止符留待下次读取。70,000 字节长行跨多个 32 KiB 预算后只返回一次，随后短行可读 |
| R26 | 大文件搜索丢弃长行后半段却声明 complete；多个小文件不共同受扫描预算限制 | 返回 `truncated_lines` 与 `line-limit`，不宣称完整搜索；小文件读取前检查剩余预算，超限以 `scan-limit` 结束。反例验证隐藏在长行后部的匹配不会变成“完整搜索无结果” |
| R27 | 尾读遇到超过内存窗口的单行时返回空页，无法查看实际末尾 | 返回有界后缀与实际 raw span；`partial_start=true` 明确行首在窗口之外，保留 truncated、from_end 与 scan_limited。无换行及 CRLF 两种尾部均回归通过 |
| R28 | 前缀采样内没有 LF 时拿空字符串判断 UTF-8，将长 GBK 行错误标为 UTF-8 | 检查真实采样字节；允许末尾尚未读全的码元，仍拒绝已知非法 UTF-8。GBK 超长首行无采样换行时回退 CP936 并正确显示 |

`read`/`search` 的模型可见工具说明已同步续页、尾部片段及搜索不完整的含义。
没有新增配置项或运行依赖。

R23 的代码页编号与语义对照 [Microsoft Code Page Identifiers](https://learn.microsoft.com/en-us/windows/win32/intl/code-page-identifiers)；
本机 `iconv -l` 及原生探针验证了实际转换器，未将文档或 Python 编码器结果当作 yaca 原生执行证据。

## 验证范围

- 新增 8 个 Lua 回归用例；完整 suite **654/654**。
- 全仓注释结构 **207 文件、5064 声明、0 缺项**；检查器反例 **14/14**。
- 完整 readiness 链通过：契约 **7687**、证明登记 **56**、readiness **562**、
  公开文档 **5**；TP-003/006/008/010 与 RP-001 通过。
- 本轮人工语义核对覆盖修改过的编码映射、UTF-16 解码、分块/续页/尾读、搜索预算、
  对应测试及新增原生探针的注释。未修改区域的全量语义审核仍在队列中。
- Fedora 44 / Linux 7.2.7 / x86_64：当前 `yaca_native.c` 以 GCC 16.2.1、
  `-std=c99 -Wall -Wextra -Werror -O2 -fPIC` 构建；Lua 5.5.1 加载后执行
  [text_codec_smoke.lua](../.tools/qualification/text_codec_smoke.lua)，12 组解码/编码往返、
  无效 GBK 拒绝及不可映射写入拒绝通过，`unavailable=0`。

原生探针使用方式为 `lua text_codec_smoke.lua <repo-root>`，运行环境需能加载当次构建的
`yaca_native`。它读取仓库的 `src/textcodec.lua`，用于资格验证，不进入发行运行包。
Windows 缺失可选 NLS 代码页会单列 unavailable，不计入通过的转换组。

日志在 `out/f4-review-20260928/`：`codec-before.log`、`range-before.log`、
`long-line-before.log`、`search-before.log`、`tail-before.log` 保留修正前失败；
`native-build.log`、`native-codec.log`、`full-final.log`、`readiness.log` 为本轮复核。
构建和完整测试均由资源守卫串行执行。

## 继续审查与目标验证

1. read/search 的页大小与最终 JSON 编码预算，尤其是转义膨胀和大匹配片段；目前按文本字节预算，仍须证明最终结果不会整体被省略。
2. 范围读取期间的同对象外部修改、截断/增长与续页身份；检查错误路径是否会被当作 EOF 或预算结束。
3. 原生转换器的内存/句柄生命周期、不可用代码页及有损路径；UTF-16/旧编码的其余边界。
4. 重建三目标产物，把本批修正与 R21/R22 一同用于 XP/Win7/CentOS 7 以及指定 Server 2008 的实测。
5. A08/A09 的真实 GiB 级文件、中文命令、编码写回与模型续页旅程。现有小规模注入用例不能替代这些目标证据。

Release Gate R 继续关闭。
