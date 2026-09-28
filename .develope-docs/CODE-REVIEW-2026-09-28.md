# 编码与区间读取 Review

日期：2026-09-28。R23--R28 接续 `9aed60f`，已提交为 `9724797`；
R29 已提交为 `f3a69f2`，R30--R33 已提交为 `d2bc3a9`；R34--R36 已提交为 `18adc05`，
R37--R38 已提交为 `4b54dc8`；随后接续 Lua 工具层的错误传播。
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
| R29 | read 只计算显示文本字节，search/list 只限制条数；JSON 转义、记录字段和调用信息使结果超限后，整页内容与续页信息一起被省略 | 接纳调用时记录固定结果字段的编码大小；分页按记录的实际 JSON 字节选取，超大单条仅截断显示文字并保持 UTF-8 边界；未返回的记录留在下一页。三组原始反例均先失败，修复及连续翻页验证后直接工具 29/29 通过 |
| R30 | 范围读取把空块但非 EOF 当作正常结束；页末预读的原生失败被吞为 scan-limit | 空读返回 FilesystemContract；只有真实预算耗尽才标记 scan_limited，原生读错误原样传播。采样、正向、尾读和搜索的无进展路径，以及页末预读失败均通过故障注入验证 |
| R31 | 范围读取只比较对象标识，大文件搜索没有完成时的身份复核；同对象等长改写、增长、截断或路径替换可能仍产出成功结果 | 共用结束检查比较句柄的完整身份，关闭后复核命名路径和祖先；覆盖读取及搜索 EOF、匹配上限、扫描上限退出。20 组外部修改组合返回 TargetChanged；结束 stat/close 的 8 组故障均保留原错误并只关闭一次 |
| R32 | read 续页只绑定对象，不绑定大小和修改时间；文件改变后仍会复用旧编码判定与缓存的半行 | 续页绑定完整身份摘要，发现改变时消费旧令牌并返回 TargetChanged；模型工具说明要求重新读取。等长改写、增长、截断三个用例均在新读取前拒绝复用缓存 |
| R33 | Lua 模式对空字符串的验证不能发现所有语法错误；模式的坏后缀在真实内容上才触发异常，绕过大文件句柄关闭 | 对实际匹配做受保护调用，返回 InvalidSearchPattern 并关闭流；大小文件都验证错误后的下一次读取仍可成功。反例 `alpha[` 在 `alpha` 上触发，旧实现实测留下未关闭句柄 |
| R34 | Windows malloc 缓冲和 POSIX iconv 描述符跨越可抛出内存错误的 Lua API；异常跳转绕过 free/iconv_close | 外层 C 调用持有资源，受保护转换返回后直接清理，再传播原错误。Linux 原实现复现 24 个未释放位置；修复后 Linux 和两个 Windows 架构的全部观测分配位置均通过，错误后同一 Lua 状态可继续转换 |
| R35 | POSIX 空输入绕过 iconv_open，未安装的代码页也返回成功；与非空输入和 Windows 的可用性语义不一致 | 空输入同样检查转换器。编码、解码的不可用空输入原先都错误接受，修复后均返回 EncodingUnavailable；有效代码页的空输入仍成功 |
| R36 | iconv 失败后先调用 Lua 缓冲 API，再读取 errno；后续分配可能覆盖真实 E2BIG/EILSEQ/EINVAL | iconv 返回后立即保存 errno，再追加 Lua 缓冲。分配器在成功分配后改写 errno 的反例使合法 CP1252 编码和解码失败，修复后输出逐字节相符 |
| R37 | Windows 原生 malloc 失败被误报为 InvalidEncoding 或 EncodingLossy；有损路径可能继续尝试转换 | 外层资源记录保留分配失败，后续原生分配不再重试；先释放已有资源，再统一返回 OutOfMemory。严格解码、有损解码、编码各三个分配位置均先复现错误，修正后两种 Windows 架构通过 |
| R38 | Windows 编码器成功和失败均返回两个值，调用者一律追加 exact=true，导致错误结果变成 false/error/true | 编码器直接返回成功三值或失败两值，外层不再按值数量猜测成功；非法 UTF-8、不可映射文字和原生内存不足均验证错误码与返回数量 |
| R39 | read/search 把不可用代码页或资源失败变成内容分类、跳过二进制文件，或改用 UTF-8 修复；有损重试还会覆盖原错误 | 只对 InvalidEncoding 重试有损解码；其余结构化错误保留并向上传播。整文件、采样、正向/尾读和搜索均覆盖，范围错误先关闭句柄；后续读取可恢复 |
| R40 | Lua codec 把所有原生异常或异常返回都报 EncodingUnavailable，且把非精确的严格转换当成成功 | 原生异常为 NativeFailure，格式/精确性违约为 NativeContract，原生结构化错误保留；严格解码与编码拒绝非精确成功 |
| R41 | write(replace) 在原子替换后才解码新内容计算行数；此时转换器失败会抛错，但原文件已经被改变 | 候选解码移到替换前，和旧内容解码/patch 一样保留资源错误；故障回归要求原字节和完整身份不变，旧源码复现候选解码失败后原字节已改变 |

`read`/`search` 的模型可见工具说明已同步续页、尾部片段及搜索不完整的含义。
没有新增配置项或运行依赖。

R23 的代码页编号与语义对照 [Microsoft Code Page Identifiers](https://learn.microsoft.com/en-us/windows/win32/intl/code-page-identifiers)；
本机 `iconv -l` 及原生探针验证了实际转换器，未将文档或 Python 编码器结果当作 yaca 原生执行证据。

## R23--R28 验证范围

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

## R29 验证与人工 Review

收口范围为 `src/tools.lua` 的调用大小记录、read/search/list 分页预算与记录截断，
以及 `test/integration/direct_tools_test.lua` 中的三个回归用例。

- 核对 `json_escape` 的引号、反斜杠、控制字符和多字节字符编码，与单条截断的计数一致。
- 调用信息按已接纳的实际 JSON 长度预留；另留 4096 字节容纳当前原生端口的固定长度
  generation、摘要、续页令牌和页元数据。最终结果的硬上限检查继续保留。
- 分页依据已返回记录推进，不能因预算提前结束而跳过记录；单条缩短使用副本，
  不改写已保存的匹配记录。目录项的路径和身份信息不截断。
- 完整文件与区间读取、正向连续翻页与尾读、多页搜索、单条超长搜索片段均有回归；
  断言最终运行时 JSON 大小、UTF-8 合法性、行顺序及完整页链。
- 对本批修改函数及测试的参数、返回值、状态修改和异常注释逐项核对。
  这部分结论不扩展为全仓语义 Review 完成。

最新完整 suite **657/657**；全仓注释结构 **207 文件、5068 声明、0 缺项**。
检查器反例 **14/14**，完整 coding readiness 链通过。日志在
`out/page-review-20260928/`：`budget-before.log` 保留三个原始失败，
`budget-final.log` 为强化后的定向回归，`full.log` 和 `readiness.log` 为完整复核。
本批未改原生转换器，也未重建或重验目标发行包。

## R30--R33 验证与人工 Review

在 `f3a69f2` 上新增六个回归用例，覆盖 38 组阶段、修改和错误组合。
`out/range-stability-20260928/before.log` 保留四个原始失败；
`pattern-before.log` 保留实际模式异常导致未关闭句柄的失败；
`final.log` 为直接工具 **35/35**，`full-final.log` 为完整 suite **663/663**。
完整 readiness 链通过，全仓注释结构 **207 文件、5084 声明、0 缺项**，
检查器反例 **14/14**；其余契约/证明/readiness 计数仍为 **7687 / 56 / 562**。

人工语义 Review 覆盖：范围采样与结束检查、EOF/扫描限制分支、预读及偏移定位失败、
续页完整身份绑定、搜索三类正常/部分退出、真实内容上的模式异常，以及新增测试端口的
参数、返回值、状态修改和句柄生命周期。关闭发生在错误返回前，关闭失败不会变成成功页；
模式错误不再绕过流清理。未修改区域的全仓语义 Review 仍未完成。

文件版本复核使用对象、大小和修改时间等身份字段，是乐观检查，不是文件系统快照。
持续增长的日志可能要求重试；保留原时间戳的等长外部修改和旧文件系统时间精度仍属
A08/A09 目标验证范围。本轮未改原生层，也未增加对热写文件无重试读取的承诺。

## R34--R36 原生复核

新增 [text_codec_faults.c](../.tools/qualification/text_codec_faults.c)，直接包含当前
`native/yaca_text.h`，使用真实 Lua 5.5.1 和系统转换器。逐个拒绝观测到的 Lua 增长分配，
持续拒绝紧急 GC 后的重试；在受保护调用刚返回时检查原生资源已释放，再解除故障，
在同一 Lua 状态完成一次转换。输出按实际字节及 exact 标记核对，重复释放单独计数。

| 环境 / 探针 | 结果 | 范围 |
| --- | --- | --- |
| Linux 分配失败与恢复 | 编码、解码各 18 个分配位置；0 失败，0 所有权错误 | 当前转换实现；有效/不可用代码页的空输入及 errno 覆盖同时验证 |
| Wine Win32 / Win64 分配失败与恢复 | 各架构编码、解码各 4 个分配位置；0 失败，0 所有权错误 | 当前 Windows C 分支，配各架构已有 Lua 5.5.1 DLL；不等于 XP/Win7 资格 |
| 完整原生模块构建 | Linux、Win32、Win64 均以 `-Wall -Wextra -Werror` 通过 | Windows 编译底线分别为 0x0501 / 0x0601 |
| 当前原生模块编码 smoke | Linux 12 组；Wine 两架构各 11 组，另报 cp54936 unavailable | 严格拒绝非法 GBK 和不可映射输出通过；不可用项不计为通过 |
| 全仓 | suite 663/663；注释 208 文件、5098 声明、0 缺项；完整 readiness 通过 | 原生故障探针独立计数，不加入 Lua suite 数字 |

本机复现 Linux 故障探针：

```sh
mkdir -p out/native-codec-review-20260928
.tools/run_with_resource_guard.sh gcc -std=c99 -Wall -Wextra -Werror -O2 \
  -Iout/qualification/runtime-deps/lua-5.5.1/src \
  .tools/qualification/text_codec_faults.c \
  out/qualification/runtime-deps/lua-5.5.1/src/liblua.a -lm -ldl \
  -o out/native-codec-review-20260928/text_codec_faults
.tools/run_with_resource_guard.sh out/native-codec-review-20260928/text_codec_faults
```

日志在 `out/native-codec-review-20260928/`。`fault-before.log` 保留原实现的资源泄漏和
空输入失败，`errno-before.log` 保留 errno 覆盖反例。最终结果为 `fault-final.log`、
`win32-faults-final.log`、`win64-faults-final.log`、`linux-codec.log`、`win32-codec-final.log`、
`win64-codec.log`、`full.log`、`readiness.log`。

人工语义核对了转换资源的获取/释放顺序、Lua 错误边界、往返缓冲的有效期、
空输入处理、errno 保存及新探针的观察与清理。全仓语义 Review 仍未完成。
Windows XP 在未使用 MB_ERR_INVALID_CHARS 时可能丢弃非法序列，仍须修正并实测；
依据 [Microsoft MultiByteToWideChar 文档](https://learn.microsoft.com/en-us/windows/win32/api/stringapiset/nf-stringapiset-multibytetowidechar)，
不能从现代 Windows 或 Wine 的行为推出 XP 的替换语义。

## R37--R38 Windows 原生分配与错误返回

接续 `8c21dd4`，修改涉及 `native/yaca_text.h` 与原生故障探针。
`out/codec-errors-20260928/malloc-before.log` 保留九个分配位置的原始错误分类；
其中三个编码错误还带有多余的第三个返回值。

- `text_resources` 单独记录原生分配失败，避免依赖 errno 或 Windows last-error。
  UTF-16、目标代码页和 UTF-8 输出的分配均经同一窄函数；失败后不重试原生分配。
- 外层受保护调用结束后先清理，再生成 OutOfMemory；Lua 自身的异常仍保留原异常传播。
  编码成功直接返回 true/bytes/true，失败只返回 false/error。
- Windows 探针覆盖严格解码、有损解码、编码各三个 malloc 位置及超出最后位置的正常调用，
  每次随后在同一 Lua 状态重新转换；无资源遗留或重复释放。
  非故障注入的非法 UTF-8、不可映射文字另外验证两值错误返回。
- 人工核对本批所有新增/修改函数与结构体的参数、返回值、失败标志和缓冲所有权注释。
  这不代表全仓语义 Review 已完成。

Linux、Win32、Win64 完整 native 构建通过。Linux 探针仍覆盖 Lua 分配各 18 个位置，
Wine 两种架构各 4 个位置；Windows 的九个原生 malloc 位置均通过。
编码 smoke 为 Linux 12 组、Wine 两架构各 11 组；后者 cp54936 不可用单列。
完整 readiness 通过，注释结构 208 文件、5101 声明、0 缺项。
日志为 `out/codec-errors-20260928/` 的 `*-faults.log`、`*-codec.log`、`native-*-build.log`
及 `readiness.log`。XP/Win7 目标资格以及 Lua 层错误传播仍待完成。

## R39--R41 工具层错误传播与写入顺序

接续 `4b54dc8`。`decode_legacy` 只把内容确实无效映射成内容分类；
EncodingUnavailable、OutOfMemory 和原生端口错误沿调用链返回。
采样确认显式代码页可用性；自动回退也保留资源错误。已选定旧代码页后，
行解码失败不再拿原字节按 UTF-8 修复。尾读在解码前已关闭句柄；正向读取和搜索在错误返回前关闭。

新增四个 suite 用例：24 组编码可用性/资源错误组合、6 组采样后严格/有损解码错误及恢复、
3 组 write/patch 解码失败、双方向 6 类原生错误/异常返回。定向 **45/45**，完整 **667/667**；
全仓注释结构 **208 文件、5111 声明、0 缺项**；完整 readiness 通过。
Linux 真实 native 编码 smoke 仍为 12 组通过。

日志为 `out/codec-propagation-20260928/`：`before.log` 保留原始读/搜索/codec 失败，
其中写入用例最初用了原始 digest 而非十六进制，先失败在参数接纳；夹具修正后，
`write-before.log` 单独对保存的 `4b54dc8` 工具源码复现候选解码失败时原文件已改变。
`targeted-final.log`、`full.log`、`readiness.log` 和 `linux-codec.log` 为修复后证据。

人工核对解码返回类型、重试条件、采样和全部行调用点、关闭路径，以及 write 在发布前完成校验的顺序；
改动函数与测试的注释逐项核对。exec 输出显示的降级策略未在本批改变，仍需后续语义 Review。
本批不扩展为全仓 Review 或旧目标资格完成。

## 继续审查与目标验证

1. 旧系统的有损替换、编码别名及 exec 输出降级的语义 Review；不能以 Wine 替代旧目标。
2. 重建三目标产物，把本批修正与 R21/R22 一同用于 XP/Win7/CentOS 7 以及指定 Server 2008 的实测。
3. A08/A09 的真实 GiB 级文件、中文命令、编码写回与模型续页旅程。现有小规模注入用例不能替代这些目标证据。

Release Gate R 继续关闭。
