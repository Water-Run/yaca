# 编码与区间读取 Review

日期：2026-09-28。R49--R50 见文末原生 open/create 与进程流一节。
R23--R28 接续 `9aed60f`，已提交为 `9724797`；
R29 已提交为 `f3a69f2`，R30--R33 已提交为 `d2bc3a9`；R34--R36 已提交为 `18adc05`，
R37--R38 已提交为 `4b54dc8`，R39--R41 已提交为 `ca6d7c5`，R42--R44 已提交为 `8af7397`；
R45 已提交为 `21eb615`，R46--R47 已提交为 `709aa85`；R48 与 seek 探针已提交为 `5384b8e`。
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
| R42 | XP 的 flag-zero 有损解码丢弃非法字节，可能同时丢掉周围有效文字；CP932 重复映射旁的错误也受影响 | 显式检查合法序列并逐字节替换无法解码的输入；保留有效重复映射；7 组损坏 GBK、2 组 CP932 重复映射与分配失败恢复均通过 XP 实测 |
| R43 | XP 已安装 GB18030，但 MultiByteToWideChar 拒绝 MB_ERR_INVALID_CHARS，合法补充字符编码/解码都失败 | GB18030 使用 XP 支持的零标志，并保留严格往返校验；有损逐段解码同样检查往返，避免静默丢字；XP 正常往返和损坏后保留补充字符通过 |
| R44 | XP 的严格 UTF-8 API 仍接受孤立代理项等非法形式，导致写入错误分类随系统变化 | 在原生编码入口和 Windows UTF-8 输出增加无分配的标量校验；穷举 1,114,113 个候选、截断前缀与非法形式；XP 的 8 组非法输入均明确返回 InvalidEncoding |
| R45 | Big5-HKSCS、EUC-CN、EUC-KR、TIS-620 被直接映射到语义不同的 Windows 代码页，可能错误解码或写出所选编码不支持的文字 | 删除六个错误别名（含缩写）；未实现的名称返回 InvalidEncoding，保留实际支持的 Windows 代码页名称及惯用别名；glibc 实际转换对照与规范化回归通过 |
| R46 | exec/Lua 输出转换器的资源、可用性及端口故障被静默改成 UTF-8 修复，原字节只剩摘要且诊断消失 | 转为完整 Base64 投影并记录 decode_error 错误码，保留已完成进程的真实状态；32 组错误/阶段/通道/工具组合及恢复通过，错误消息不进入输出 |
| R47 | BOM 标记的 UTF-16 输出尾部半个码元被截掉，坏代理项可能按其他编码重解释；真实 UTF-8 仍标记为策略默认解码器 | 对识别出的 UTF-16 整体严格校验，失败时保留原字节并记录 InvalidEncoding；UTF-8 成功使用真实标签；坏尾字节、孤立代理项和标签回归通过 |
| R48 | fs_read 的 malloc 缓冲跨越 Lua 表/字符串分配，内存异常绕过 free；原实现五个注入位置留下读取缓冲 | 读取缓冲改为 Lua 所有，在发布结果表字段前完成缓冲收口；故障后保留调用方文件句柄，原生读错误先保存再清理；真实 native 注入及同句柄恢复验证 |

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

## R42--R44 XP 原生转换与目标对照

接续 `ca6d7c5`，修改仅涉及原生文本转换及两个资格探针。使用独立 qcow2 覆盖盘和
FAT 便携介质，在 Windows XP SP3 x86（5.1.2600，活动代码页 936）运行旧/新原生组件对照。
旧组件为 `4b54dc8` 当次构建；Lua 包装源码为 `ca6d7c5`，新组件包含本批修正。
当次介质输入及 SHA-256 保存在 `out/codec-xp-20260928/xp/media/` 和 `payload-final.sha256`。

旧组件在最终探针中复现 **12 项失败**，覆盖 GB18030 双方向、7 个 GBK 替换场景、
CP932 有效重复映射旁的坏字节，以及两类 UTF-8 错误分类。新组件全部通过。
原始 NLS API 探针同时记录 GB18030 严格标志返回 ERROR_INVALID_FLAGS（1004），
以及 XP 严格 UTF-8 接受孤立代理项的行为。依据与实测相符：
[Microsoft MultiByteToWideChar](https://learn.microsoft.com/en-us/windows/win32/api/stringapiset/nf-stringapiset-multibytetowidechar)。

| 检查 | 当前结果 |
| --- | --- |
| Linux / Win32 / Win64 native 构建 | 均以 `-Wall -Wextra -Werror` 通过，Windows 底线仍为 XP / Win7 |
| Linux 编码 smoke | 13 组往返、7 组 GBK 替换、2 组 CP932 重复映射、8 组非法 UTF-8、1 组 GB18030 修复通过 |
| Wine Win32 / Win64 编码 smoke | 各 12 组往返及相同替换/UTF-8 检查通过；GB18030 不可用单列 |
| XP 当前 native 编码 smoke | 13 组往返及全部替换/UTF-8/GB18030 检查通过，0 不可用项 |
| Lua 分配失败与恢复 | Linux 解码/编码/有损各 18 个位置；Wine Win32 为 4/4/20，Win64 为 4/4/18；XP 为 4/4/20；0 失败、0 所有权错误 |
| Windows malloc 故障 | Wine 两架构及 XP 各九个位置，清理、OutOfMemory 与同状态恢复通过 |
| UTF-8 标量校验 | 上述各环境均检查 1,114,113 个候选及多字节截断前缀，另有 8 组非法形式；全部通过 |
| XP 完整 Lua suite | 667/667，通过当前 Lua 源码与新 native 介质执行 |
| 全仓 readiness | 完整链通过；注释结构 208 文件、5115 声明、0 缺项；检查器反例 14/14 |

日志根目录为 `out/codec-xp-20260928/`，开发机最终记录为 `*-final.log`、
`win32-codec-xp-final.log`、`win64-codec-xp-final.log` 和 `readiness-final.log`。
XP 最终结果在 `xp/evidence-final/`；`new-codec.exit`、`new-faults.exit`、`core-suite.exit`
均为 0，旧组件失败日志也保留。前两轮在 `xp/evidence/`、`xp/evidence-api/`：
首轮 suite 的相对根路径含 `..`，被安全加载器拒绝，造成夹具失败；改为进入规范源码目录
启动后完整通过，未为夹具调整产品路径校验。中间轮仍有两个 GB18030 失败，最终修复后通过。

人工语义 Review 核对了无分配 UTF-8 校验的边界、ASCII 快路径的真实代码页探测、
逐段替换与 CP932 多对一映射、GB18030 往返、Lua 缓冲所有权及异常收尾；
新增/修改函数的注释与签名、返回值、分配和副作用逐项核对。
此次 XP 证据覆盖当前原生组件和源码 suite；尚未重建最终单文件和三档发行包，
不等于整个平台资格完成。全仓语义 Review 与其余目标矩阵继续保留为未完成。

同批 Win7 独立覆盖盘已启动，但两个已有账户均停在密码入口，未获得可用登录上下文，
没有执行 guest 探针。保留 `win7/login-retry.png`、`win7/selected-user.png` 与运行日志后
正常关机；本批 Win64 证据限于交叉构建和 Wine，不把该启动尝试计为 Win7 通过。

## R45 不同字符集的名称边界

接续 `8af7397`，审查 `src/textcodec.lua` 名称表及其全部引用。
实际系统 iconv 对照记录在 `out/codec-alias-20260928/native-alias-before.log`：
CP950 拒绝 `88 62`，Big5-HKSCS 将其解码为 U+00CA U+0304；CP936 / CP874
将 `80` 解码为欧元符号，EUC-CN / TIS-620 拒绝；CP949 将 `81 41` 解码为 U+AC02，
本机 EUC-KR 转换器返回 U+0081 和 ASCII A。它们不是可互换的转换器。

[IANA Big5-HKSCS 注册](https://www.iana.org/assignments/charset-reg/Big5-HKSCS)
明确其为 Big5 的扩展；[Microsoft 代码页表](https://learn.microsoft.com/en-us/windows/win32/intl/code-page-identifiers)
也将 EUC-CN / EUC-KR 与 Windows 936 / 949 分列。
实现仍以 Windows 代码页为规范名称；gb2312、shift_jis、ks_c_5601-1987 保留其
Microsoft 代码页名称含义，不据此声明实现了同名标准的所有独立变体。

删除 big5-hkscs、euc-cn、euccn、euc-kr、euckr、tis-620 的错误映射。
现有规范化用例增加这些拒绝项及大小写检查，同时核对 UHC、Windows-31J、x-gbk、
Windows-874 仍可用。`before.log` 保留原实现错误接受 HKSCS 的反例；
修改后的完整 suite **667/667**，日志为 `full.log`。
完整 readiness 通过，日志为 `readiness.log`；注释结构仍为 208 文件、5115 声明、0 缺项。
人工核对名称表、POSIX locale 回退和工具参数接纳路径：不支持的显式名称会被拒绝；
不支持的 locale 不再错误宣称另一套代码页。未增加运行依赖或扩大支持编码范围。

## R46--R47 进程输出与执行结果

接续 `21eb615`。转换器基础设施错误只影响通道的显示形式，不改变已完成进程的
`process_outcome`、退出信息或 durable 工具结果。通道使用 `representation=base64`，
`decode_error` 仅保留错误码，原始字节、摘要和字节计数一致；正常或脱敏通道该字段为 false。
已识别的 UTF-16LE 不裁剪尾部字节，也不在校验失败后尝试另一套编码。

新增三个完整用例：OutOfMemory、EncodingUnavailable、NativeFailure、NativeContract
在严格/有损两个阶段、stdout/stderr 两通道、exec/Lua 两工具上的 **32 组组合**，
每组验证 Base64、摘要、执行完成状态、持久结果和同服务后续调用恢复；另外检查两种
损坏 UTF-16、真实 UTF-8 标签，以及注册秘密先于转换器脱敏。
后者明确验证故障转换器没有被调用，秘密不通过 Base64 绕过既有保护。

日志目录 `out/exec-projection-20260928/`。最初两个故障夹具漏了 codec.encode，
被依赖校验拒绝，不能当作产品缺陷证据。补齐夹具后，在独立源码副本上用
`21eb615:src/tools.lua` 重放，`before-replayed.log` 复现两个真实失败；
`targeted-complete-fixture.log` 为修正后 **12/12**，`full.log` 为完整 **670/670**。
完整 readiness 通过，日志为 `readiness.log`；注释结构 **208 文件、5122 声明、0 缺项**。

人工核对修改函数的全部返回路径与注释、通道摘要/计数、脱敏先行、错误消息不外传、
`settle_process` 的完成与失败分支，以及测试夹具的资源关闭和第二次调用。
随后将 `709aa85` 的完整源码快照放入独立 XP 介质，以同一当前 native 重新执行：
完整 suite **670/670**，编码 smoke 与故障探针再次通过。
日志在 `out/xp-closeout-20260928/evidence/`，三个新组件退出码均为 0；
`media/source-commit.txt` 固定源码提交，`payload.sha256` 固定 366 个介质输入文件。
它补齐新输出用例在 XP Lua 环境的回归；进程事件使用测试夹具，仍不替代真实外部命令旅程。

## 原生 seek 与 R48 文件读取资源

新增 [filesystem_seek_smoke.lua](../.tools/qualification/filesystem_seek_smoke.lua)，
用一个小文件测试 12 个字节位置，跨 2 GiB / 4 GiB 边界、文件尾和文件尾之后；
不生成大文件，也不增长文件。还核对负偏移拒绝不改变位置、关闭句柄拒绝和读取前后完整身份。
Linux、Wine Win32/Win64，以及 XP NTFS/FAT32 均通过。日志在
`out/seek-qualification-20260928/`，XP 两个退出码均为 0。
这证明原生偏移与读取行为，不替代 GiB 日志扫描、轮转或容量验证。

随后资源审查确认 `l_fs_read` 的读取缓冲在 Lua 分配异常时泄漏。
`out/native-io-review-20260928/fs-read-faults.log` 记录原实现的 6 个 Lua 分配位置中
5 个留下 8192 字节原生缓冲；探针观察后自行清理，未积累泄漏。
修复使用 `luaL_Buffer` 管理读取内存，结果表在读取前分配；成功、原生错误和 Lua 异常
均保留明确所有权。原生错误码在缓冲收口前保存，文件句柄仍由调用者持有。

新增维护的 [filesystem_read_faults.c](../.tools/qualification/filesystem_read_faults.c)
直接包含生产原生模块，持续拒绝选中位置及紧急 GC 重试的增长分配。
Linux 与 Wine 两架构各 **13 个分配位置、0 原生泄漏**；每次在同一 Lua 状态、
同一文件句柄恢复 seek/read，另验证实际 OS 读取错误的两值返回和缓冲清理。
三平台完整 native 与故障探针均以 `-Wall -Wextra -Werror` 重新构建通过。
Windows 探针最初直接调用带 DLL import 声明的模块入口，链接失败；改用生产文件元表
注册函数后构建通过。此为探针链接修正，没有改变产品模块导出。

最后以 R48 新 Win32 DLL / 探针启动独立 XP 覆盖盘：**13 个分配位置、0 泄漏、
同句柄恢复及 OS 错误路径通过**；NTFS/FAT32 的 12 偏移检查再次通过。
日志在 `out/native-io-review-20260928/evidence/`，三个退出码均为 0；
`final-inputs.sha256` 绑定原生源码、两个探针、DLL、故障程序和 guest 驱动。
Lua 产品源码仍为 `709aa85`，XP 完整 suite 670/670 见上一节；本轮 native 单独复验。

R48 最终开发机完整 suite **670/670**，完整 readiness 链通过；注释结构
**210 文件、5129 声明、0 缺项**，检查器反例 14/14。
对应 `out/native-io-review-20260928/full-final.log` 与 `readiness-final.log`。

人工核对本批读取成功/错误路径、Lua 栈中的表索引与缓冲生命周期、调用方句柄所有权，
以及新增探针每个函数、结构字段、故障清理和恢复步骤的注释。
下一轮需继续核对原生 open/create 取得句柄后建立 userdata 的顺序，以及
`read_windows_process_stream` / `read_posix_process_stream` 的临时缓冲跨 Lua 分配问题；
这些尚未注入故障，不能从 R48 通过推出整个原生层已完成资源审查。

## R49--R50 原生 open/create 与进程流读取资源

接续 `5384b8e` 的下一项原生 I/O 审查。新增两个维护探针
[filesystem_open_faults.c](../.tools/qualification/filesystem_open_faults.c) 与
[process_stream_faults.c](../.tools/qualification/process_stream_faults.c)，
直接包含生产原生模块并注入 Lua 分配失败。

- R49：四个 open/create 端口在取得操作系统句柄**之后**才创建 userdata；
  `lua_newuserdatauv` 抛出内存错误时句柄无处归属。Windows verified 变体在该位置
  还持有整个 snapshot，泄漏更多。探针在 Linux 用 `/proc/self/fd` 差集、
  Windows 用包装 `CreateFileW`/`CloseHandle` 的值级审计（Wine 的
  GetProcessHandleCount 是未实现 stub，不能作为观测）。修正将 `push_file`
  移到句柄获取之前，与 `l_process_start` 的既有范式对齐；各失败路径补 `lua_pop`
  后返回类型化错误。恢复流程先释放引用并完全收集再删除 create 目标，
  因为 Windows 句柄未关闭时 `DeleteFileW` 会失败。
- R50：`read_windows_process_stream` 与 `read_posix_process_stream` 的原生
  malloc 缓冲跨越 `lua_createtable`/`lua_pushstring`/`lua_pushlstring` 等
  可抛分配，异常路径泄漏缓冲。修正改用 `luaL_Buffer`（Lua 持有），
  错误码在缓冲收口前保存、收口后恢复（Windows 为 SetLastError，
  POSIX 为 errno），句柄仍归调用方所有。

| 检查 | 结果 |
| --- | --- |
| before 证据（`f5dd112` 原生源码） | Linux、Wine Win32/Win64 均 4 个 open/create 端口各泄漏 1 个句柄（Win32 verified open 为 2 个）；进程流首读各 9 个分配位置泄漏原生缓冲 |
| 修正后 open/create | 三环境各 4 端口 0 句柄泄漏；同状态恢复调用含 write/seek/read 回读全部通过 |
| 修正后进程流 | Linux 20 个、Wine 两架构各 11 个分配位置 0 缓冲泄漏；同一进程监督到 terminal 事件且 outcome=completed；基线两通道字节完整 |
| R48 与编码回归 | fs_read 故障探针 13 位置 0 泄漏；text_codec_faults 解码/编码/有损各 18 位置 0 失败 0 所有权错误 |
| 编码 smoke | Linux 13 组；Wine 两架构各 12 组加 cp54936 不可用单列 |
| 原生模块构建 | Linux、Win32（0x0501）、Win64（0x0601）均 `-Wall -Wextra -Werror` 通过 |
| 全仓 | 完整 suite **670/670**；注释结构 **212 文件、5163 声明、0 缺项**；完整 readiness 链通过，Gate R 继续关闭 |

日志根目录 `out/native-open-review-20260928/`：`open-before.log`、`stream-before.log`
为 Linux 旧实现失败；`open-win32-before.log`、`open-win64-before.log`、
`stream-win32-before.log`、`stream-win64-before.log` 为 Wine 旧实现失败；
`*-final.log` 与 `win32/win64` 下的结果为修正后证据；
`recheck/` 为 R48 与编码探针复跑。旧代码对照探针对 `f5dd112` 的影子源码树构建。

人工核对：六个函数的 userdata/句柄/缓冲所有权顺序与注释、各失败路径的
`lua_pop` 与错误码保存、恢复段 write/seek/read 的栈序，以及两个探针每个
函数、结构、包装器和阶段的注释与清理。`identity_matches_lua` 仅在
yaca 自产普通字符串表上运行，其对带元表输入的理论抛错不在本批范围。
本批未重建发行包；XP/Win7 当前组件实测仍未完成。


## 目标资格批次(2026-09-28/29)

接续 `ce47834` 的三目标产物重建与四环境当前组件实测。

### 产物与构建

- Win32/Win64 单文件由 `build_windows_candidate.sh` 交叉构建,均产出 clean 版 zip、
  notices zip 与 SHA256SUMS(`out/windows-candidate-20260928-n1/`、
  `out/windows64-candidate-20260928-n1/`)。
- Linux 单文件在 CentOS 7.9.2009 VM(gcc 4.8.5、glibc 2.17、内核 3.10.0-1160)原生构建:
  `full_tests=670/670`,产物与摘要见 `out/centos7-20260928/`(VM 内 c32-linux-ce47834-r1),
  zip 由 `package_linux_zip.py` 在构建机以 LC_ALL=C 装配(`out/linux-candidate-20260928-n1/`)。
  VM 上的旧版构建脚本钉死 SUMMARY total=329,已替换为当前仓库脚本后通过。

### 四环境当前组件实测

| 环境 | 结果 | 缺口 |
| --- | --- | --- |
| XP SP3 x86 VM | 三故障探针 0 泄漏/0 失败、codec smoke 13 组、seek 12 偏移、完整套件 670/670、onefile stage-1 自检 DATA-ROOT 通过 | 无(自检 outcome=partial 为干净机未初始化配置的预期) |
| Win7 SP1 x64 VM | 登录上下文解决(口令取自 autounattend 软盘);codec-faults/pstream/codec-smoke/seek 探针通过、完整套件 670/670、onefile stage-1 自检同上 | fs-open 探针因驱动脚本引用了不存在的短文件名未在真机执行;该二进制的 0 泄漏证据由 Wine Win64 覆盖 |
| CentOS 7.9 VM | 上行构建全部产物;三故障探针 0 泄漏/0 失败、codec smoke 13 组、seek 12 偏移、完整套件 670/670 | 无 |
| Server 2008 SP2 真机 | `yaca --version` 退出 0;stage-1 自检 12 PASSED/0 FAILED(仅配置未初始化与 SSH 管道 TTY 两项预期警告) | 在线阶段与真实模型旅程未执行 |

证据目录:`out/xp-qual-20260928/`、`out/win7-qual-20260928/`、`out/centos7-20260928/`
与 `out/release-20260928/`。Win7 首轮批次期间发生一次未归因的系统中途重启,FAT
写缓存丢失该轮证据;后续批次以干净关机落盘复核。

### A08/A09 真实 GiB 旅程

新增维护的 [gib_log_journey.lua](../.tools/qualification/gib_log_journey.lua) 以生产形态的
16 MiB 整文件上限驱动真实工具层。CentOS 7 上对 2344 MiB 真实文件 **10/10 通过**:
首/尾区间、有界搜索(complete=false 按扫描预算如实报告)、2 GiB 后偏移读取、
超限写入在接纳层拒绝、CP936 显式解码、auto 严格 UTF-8 拒绝(classification=
invalid-encoding 带重试提示)、增长后尾部重读。开发过程证实:把整文件上限配置为
4 GiB 时同一文件走整文件路径并在受限内存环境正确失败——与已记录行为边界一致,
旅程已按生产边界修正。旅程在开发机小夹具与 CentOS 全尺寸夹具均通过。

### 包矩阵现状

clean 三平台全部装配(win32/win64 来自候选构建,Linux zip 另含 SBOM/许可/构建摘要);
win32 std 以当前二进制刷新(`out/editions-win32-20260928/`)。win64/Linux std 与三个
full 的可移植工具闭包未构建,仍为 Gate R 前剩余项;`tool-bundles.json` 状态本身即为
candidate-versions-not-qualified-artifacts。

本批后完整套件 670/670,readiness 全链通过,注释结构 213 文件、5172 声明、0 缺项。


## std 三平台装配批次(2026-09-29)

接续资格批次,补齐 std 档的三个包。

- Win64 std:新增 [build_win64_std.sh](../.tools/qualification/build_win64_std.sh) 与
  [prepare_win64_std.py](../.tools/qualification/prepare_win64_std.py),复用 win32 管线:
  amd64 Python 2.7.18 MSI(MSI 清单沿用 Win7 实机生成的 TSV)、putty 0.85 以
  x86_64 mingw(WinVER 0x0601)构建、7-Zip extra 的 x64 控制台、核心构建的 x64 curl。
  四工具在 Wine 下冒烟通过(python 2.7.18/maxsize 64 位、plink 64-bit x86、curl 8.21.0、7za)。
  装配为 `out/editions-win64-20260929/` 的 std 包。
- Linux std:在 CentOS 7 容器(vault/EPEL 存档,cmake3 3.17.5、gcc 4.8.5)内构建
  putty CLI(64-bit Unix)、Python 2.7.18(zlib 可用;容器无 OpenSSL 头,_ssl 不含,
  HTTPS 由 curl 承担)与 7zz 26.03(gcc4.8 需 -maes/-mpclmul/-mavx2 内建开关与去掉
  -Werror;7-Zip 运行时分发保持 x86-64 基线);curl 复用 CentOS 资格构建的产物加
  核心证书。新增 [prepare_linux_std.py](../.tools/qualification/prepare_linux_std.py)。
  四工具在 CentOS 7 容器冒烟通过;装配为 `out/editions-linux-20260929/` 的 std 包。
- win32 std 之前已用当前核心刷新;tool-sources.lock 增补 amd64 MSI 条目并将
  target 标注为 win32-x86+win64-x86_64。

九包现状:clean×3 + std×3 共六包齐;三个 full 需 git/python3/sqlite/jq/busybox/
compiler 六个附加工具的完整可移植闭包,仍为 Gate R 前最大剩余项
(compiler 在工具清单中尚无钉定版本)。本批后 readiness 全链通过,
注释结构 216 文件、5183 声明、0 缺项。


## full 档启动批次(2026-09-29)

- 版本钉定写入[工具清单](../release/tool-bundles.json):busybox 1.36.1、git 2.39.5、
  python3 3.4.4(复用既有 python34 管线)、compiler=w64devkit 2.0.0(Windows 便携
  C/C++ 全套,沿清单既定来源;jq 1.8.2 与 sqlite 3.53.4 原已钉定)。
  新增 [full-tool-sources.lock.json](../release/full-tool-sources.lock.json)
  (busybox/jq/oniguruma/sqlite autoconf+src/tcc/git 七源,SHA-256 全钉)。
- Linux 三个小工具在 CentOS 7 容器(yaca/c7builder)构建完成并冒烟通过:
  busybox 1.36.1(禁 seedrng——glibc 2.17 无 sys/random.h;401 个 applet、
  sh/awk 可用)、jq 1.8.2(对 oniguruma 6.9.10 静态链接,UTF-8 与数组聚合通过)、
  sqlite 3.53.4(sqlite3 + sqldiff,后者由 sqlite-src 拼包以 amalgamation 编出,
  链接 -lpthread -ldl)。证据 `out/linux-full-20260929/smoke-c7.log`。
- busybox 1.37.0 在 CentOS 7 头文件下不可编译(iplink 的 CAN 常量需新内核头),
  故钉定回退到 1.36.1;该取舍连同 seedrng 禁用一并记录。
- 剩余:git 2.39.5、python3 3.4.4、w64devkit 2.0.0 三个大闭包的取得与三平台
  full 装配(本批启动,未完成);真实模型旅程仍待模型 API 凭证。


## full 档闭包取得批次(2026-09-29,第二批)

- 目录订正:tools[] 的通用版本字段回退为空,以各 target 的 versions 表为唯一权威
  (win32:git 2.10.0/python3 3.4.10/busybox-w32 FRP-6075/w64devkit-2.9.0-x86;
  win64:git 2.46.2/python3 3.8.20/busybox-w32 FRP-6075/w64devkit-2.9.0-x64;
  linux:git 2.55.0/python3 3.14.7/busybox 1.37.0/GCC-13.5.0+Binutils-2.47+Make-4.4.1
  含可重定位 sysroot)。
- 已取得并 SHA 记录(`out/full-payloads-20260929/payloads.lock.json`):
  PortableGit 2.10.0 32-bit 与 2.46.2 64-bit 官方便携包、w64devkit 2.9.0 x86/x64
  官方发布包。
- busybox-w32 FRP-6075-g169694ebd 以 mingw 双架构从标签源码构建:
  mingw32/mingw64 defconfig,产物 PE32/PE32+,Wine 下 echo 与 --list(179 个
  applet)通过。源码 tarball 入 full 锁。
- 既有 out/python34-build-20260922 树经核为未完成的 configure 残骸(无 Makefile),
  不能当 3.4.10 产物复用,win32/win64 的 python3 目标构建仍需从源码完整执行。
- 剩余:win32 python3 3.4.10 与 win64 3.8.20 的源码构建、linux 侧 GCC13.5
  sysroot 自举(git 2.55/python 3.14.7 依赖它)、三平台 full stager 与装配。
  真实模型旅程仍待模型 API 凭证。

## 继续审查与目标验证

1. Win7 当前组件复验；将新的输出路径纳入真实旧终端旅程。
2. 重建三目标产物，把本批修正与 R21/R22 一同用于 XP/Win7/CentOS 7 以及指定 Server 2008 的实测。
3. A08/A09 的真实 GiB 级文件、中文命令、编码写回与模型续页旅程。现有小规模注入用例不能替代这些目标证据。

Release Gate R 继续关闭。
