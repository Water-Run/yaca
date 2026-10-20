# 2026-10-20 开发接续与 Review

负责人要求“继续 实现 yaca”。本轮恢复 D-092 后暂停的开发，既有功能、D-077
实机范围、三目标九包、注释规范和资源守卫继续适用。

## 原目标与当前任务

原目标为实现 yaca，完成 TRACKING 中的来源闭包、人工语义 Review 和最终目标
资格。C01--C31 已实现，不重新开工；正式 Gate R 仍关闭。

当前先处理 P0 Windows Git 来源核对。仓库基线为 `5e0922c`；已 fetch origin，
本地与远端一致，起始工作区干净。来源、签名、密钥的原始固定数据保留不变。
恢复依据为 [D-093](DECISIONS.md#d-093-从-r100-恢复实现2026-10-20)。

## 环境与执行记录

- 本机既有 `bin/lua55` 是 Lua 5.5.0。初始化按预期拒绝了旧解释器，没有覆盖它。
  原文件保存在 `out/development/lua55-before-20261020`，开发入口改用初始化取得并
  构建的固定 Lua 5.5.1。
- 本机 Python 3.13 来自 uv，符号链接入口生成的 venv 未找到标准库；失败目录
  保存在 `out/development/python-failed-shim-20261020`。用同一解释器的实际路径
  创建隔离环境后，初始化成功，固定解析器均可导入。未修改公开初始化脚本。
- 初始化 session `43135` 已退出失败，实际解释器建环境的 `64322` 和最终初始化
  `79021` 均已确认退出零。最终日志为 `out/development-bootstrap-20261020-final.log`；
  首次及重试失败日志分别保存在同目录的 `development-bootstrap-20261020.log`、
  `development-bootstrap-20261020-retry.log`，原始日志未删除。
- R100 来源缓存下载 session `71748` 已确认退出零。1042834167 字节档案的
  SHA-256 为 `84ce47581c381f27ed732e94ecf27b7f4fece05e4342c6d3073c71dc33b6f176`，
  与 R100 发布记录一致；结构及全部 1168 个固定成员摘要通过后在新目录
  `out/source-cache/` 恢复。恢复 session `48021` 已退出零，报告为
  `out/review-20261020/cache-restore.json`。

## R101 固定公钥的过期与撤销状态

[GnuPG 的 gpgv 文档](https://gnupg.org/documentation/manuals/gnupg/gpgv.html) 明确保留
密钥过期和撤销检查边界；R99 也如实记录了这个限制。本轮使用独立生成的公开
夹具，确认旧工具会把过期主密钥、过期签名子密钥、带真实撤销证书的主密钥都
判为 PASS。反例使用真实离线 gpgv，不用模拟字符串冒充签名验证。

现在仍先固定来源、签名和公钥的 SHA-256，在临时目录用 gpgv 核对密码学签名及
完整主密钥身份；随后用相同公钥字节执行隔离的离线 gpg 验证。禁用用户配置、
默认密钥环、自动取钥及 agent 启动，不修改用户密钥库。显式指纹作为信任输入，
不要求维护者的本地 Web of Trust。

按 [GnuPG 状态协议](https://github.com/gpg/gnupg/blob/master/doc/DETAILS) 读取完整
签名/主密钥指纹；两次实际签名记录必须一致，且每个签名均有 GOODSIG。已知过期、
撤销、坏签名和验证错误状态均拒绝。仅有 VALIDSIG 或进程退出零不能通过。
报告把 `signature_status` 与 `key_validity` 分开，保留两次实际状态流和检查时刻。
命令或签名/密钥状态失败均使总状态失败，命令返回非零。

检查只覆盖固定公钥快照，`key_revocation_freshness=not-checked`；没有联网刷新，
也不从某个快照没有撤销证书推断当前在线状态。历史签名仍有效、密钥是否更新与
是否接纳来源，是需要记录证据的独立判断，不能改检查时钟取得 PASS。

### 实际来源结果

原 `release/windows-git64-signatures.lock.json` 与全部来源、签名、公钥固定值未变。
18 项密码学签名全部匹配；10 项固定快照的当前密钥状态通过，以下 8 项失败。
这 8 项的 gpg 实际退出码也全部为零，但均有 EXPKEYSIG/KEYEXPIRED，说明只检查
进程退出码仍会误报。

| 来源项 | 固定快照中的过期时刻（UTC） |
| --- | --- |
| file 5.45-3 | 2026-08-15 13:52:38 |
| nettle 3.10-1、mingw nettle 3.10-1 | 2025-01-15 17:12:43 |
| mingw gettext 0.22.5-2、mingw libiconv 1.17-4、两份 libunistring 1.2-1 | 2025-02-10 19:59:36 |
| libxcrypt 4.4.36-1 | 2026-01-01 11:00:00 |

完整报告为 `out/review-20261020/source-key-validity.json`，CLI 按预期返回 1。
来源仍为 partial；更新公钥、历史签名的接纳依据、撤销新鲜度、实际二进制对应关系
和 Win32 来源缺项继续保留。没有改写 R99 的历史 PASS 或 R100 的公开附件。

### 人工语义 Review

- `signature_records`：核对状态字段位置、可选主指纹回退、完整指纹格式和未知状态
  的向前兼容；不解析翻译诊断或用户 ID 来决定结果。
- `assess_key_validity`：核对相同临时 keyring、相对文件名、禁用自动取钥及默认配置、
  单次 60 秒超时、拒绝状态、签名数量及身份一致性、时间记录和返回值。
- `verify_entry` / `verify_manifest` / `main`：逐项核对参数、原字节固定、允许身份、
  临时目录清理、逐项失败保留、总状态与 CLI 非零退出语义。
- 新测试 helper 与四项回归：逐项核对参数、fixture 写入副作用、断言对应的真实
  签名/密钥状态。公开 JSON 只含公钥与签名；临时生成私钥和 agent 已清理。
  生成器保存在 `out/review-20261020/generate_key_state_fixtures.py`，含完整文件头及
  函数契约；其参数、临时时间、导出与最终清理也已人工核对。

## 验收状态

| 检查 | 结果与证据 |
| --- | --- |
| 真实验签/密钥专项 | 修复前 4/9，修复后 9/9；`key-states-before.log`、`key-states-after.log` |
| 完整 Lua 基线与修复后 | 两次均 735/735；`baseline-lua.log`、`lua-r101.log` |
| 完整 coding readiness | PASS，session `96410` 已确认退出零；`readiness-r101.log` |
| 全仓注释结构 | 273 文件 / 5798 声明 / 0 缺项；inventory session `1244` 已退出零，`comment-inventory-r101.json` |
| 人工语义 Review | 本轮修改与维护生成器已逐项核对；全仓仍为 partial |
| 真实来源与密钥快照 | 签名 18/18，密钥状态 10/18；8 项过期失败按原样保留 |

以上日志除另有说明外均位于 `out/review-20261020/`。R101 完整 Lua session `90470`
已确认退出零；上述初始化、下载、恢复与验证句柄均已结束，无需重启或等待。
结构及测试只代表本轮宿主和源码范围，不替代目标资格、完整来源闭包或最终九包。
产品 src/native 字节未变，正式 Gate R 继续关闭，发布未授权。
14 项实现、测试、生成器和结果的当前/冻结字节绑定见
[R101 证据](tool-source-review/R101.json)。文档真实性校验与 `git diff --check` 通过。

## R101 后接续

先冻结 R101 的实现、测试及实际结果，在提交边界干净后继续 P0。下一项接续 Win32
来源缓存中的 6 个配方问题和 Bash/readline/ncurses/vim 四个尚未尝试的载荷版本；
同时保留本轮发现的密钥有效性待办。总目标“实现 yaca”仍未完成。

## R102 Win32 四个未尝试载荷版本

R101 已提交为 `7c20297`，提交后工作区干净。从原 SOURCE-COVERAGE 中提取 Bash
4.3.046-1、readline 6.3.008-7、ncurses 6.0.20160220-1、vim 7.4.1721-1 的固定配方，
仅作为数据展开来源列表，不执行 PKGBUILD。

Bash、readline 和 vim 原始归档已取得，SHA-256 均匹配原配方；前两者的分离签名
也已取得，但不把下载与记录摘要当作验签通过。初始下载 session `3210`、`45486`、
`11812` 均已确认退出零；ncurses 原镜像下载 `4940` 已确认返回 22，两次均为 404。
原始下载位于 `out/review-20261020/r102/downloads/`。ncurses 另外两次检查 session
`38386`、`56086` 也均已确认返回 22/404；本轮所有下载句柄已结束。三个实际检查的
地址与工具回执保存在 `r102/recovery-report.json`、`r102/download-receipts.json`。

### 来源与静态摘要

| 原始来源 | 原配方 SHA-256 | 本轮结果 |
| --- | --- | --- |
| [Bash 4.3](https://ftp.gnu.org/gnu/bash/bash-4.3.tar.gz) | `afc687a28e0e24dc21b988fa159ff9dbcf6b7caa92ade8645cc6d5605cd024d4` | 原归档、8 项维护补丁、46 项上游补丁摘要全部匹配；47 项分离签名保留待验证 |
| [readline 6.3](https://ftp.gnu.org/gnu/readline/readline-6.3.tar.gz) | `56ba6071b9462f980c5a72ab0023893b65ba6debb4eeb475d7a563dc65cafd43` | 原归档、3 项维护补丁、8 项上游补丁摘要全部匹配；9 项分离签名保留待验证 |
| [vim 7.4.1721](https://github.com/vim/vim/archive/v7.4.1721.tar.gz) | `fb0cbb2eb2523a2f13347da85523ac1734944c08b30124002b23ff6f7b0b0015` | 原归档及 7 项维护输入摘要全部匹配 |
| ncurses 6.0-20160220 | `34387d968a37cbc2362f62d44d44bb9c27cd288261262bd06f3b053994c90401` | 原归档仍缺；维护补丁摘要匹配，保留静态子集 |

检查了 [ncurses 官方归档](https://invisible-island.net/archives/ncurses/6.0/) 与
[MSYS2 官方来源目录](https://repo.msys2.org/msys/sources/)，本轮没有取得原快照。
未用普通 6.0 发布包、不同快照或重新打包的数据替代该原摘要。

恢复程序 `out/review-20261020/r102/recover_four_payloads.py` 对四份已固定配方作
人工核对后的字面展开。Bash/readline 的 10# 补丁计数及顺序分别为 46/8；文件数
与原 sha256sums 逐项对齐。原配方、缓存补丁、原归档均先验证摘要，再以排他创建
保存到新缓存路径；SKIP 的签名只记录实际摘要，状态保持 signature-pending。

新锁新增 132 个来源成员，固定成员共 1221。原 1087 个非覆盖报告输入保持
path/destination/hash 完全一致；旧 R100 的覆盖报告按原字节移入
`history/R100-SOURCE-COVERAGE.json`，新逐成员结果作为当前 SOURCE-COVERAGE。
来源状态、手工 Review 和发布授权不提升。

### 档案与验收

| 项目 | 实际结果 |
| --- | --- |
| 当前来源归档 | `out/review-20261020/r102/git-win32-recovered-sources-20261020.tar.gz` |
| 字节数 | 452667221 |
| SHA-256 | `b072ff907cb46a5f375094deb47fa2c371226bed5464cd4c4f8c4c45ebf4fda1` |
| 固定成员 | 1221，另有归档自己的 source-profile.json |
| 生产打包器 | PASS，session `43421` 已退出零；每个归档成员摘要已核对 |
| 维护来源接纳 | PASS，session `22715` 已退出零；Git 2.10.0，source_closure=partial |
| 115 个已恢复配方版本 | 98 个静态摘要全部匹配、14 个静态子集、3 个无已核对静态载荷 |
| 配方问题 | 原 6 项保留；四个原未尝试载荷版本均已有本轮实际结果 |

人工 Review 核对了恢复程序的全部函数及参数/返回注释、四份原 source/checksum
数组的顺序、SKIP 与来源闭包边界、排他写入和历史覆盖报告保留；也核对当前锁
全部新增成员与实际缓存的一致性。源码、签名和配方没有执行或改署。
本轮未修改产品 src/native 或验签工具，R101 的完整 Lua 735/735 与结构覆盖保留
原范围。R102 完整 readiness PASS，session `82609` 已确认退出零；结构仍为
273/5798/0，全部装配/来源回归与现代证明均通过。12 项当前/冻结输入与结果绑定
见 [R102 证据](tool-source-review/R102.json)；原档案和大缓存保存在本机，未公开。

## 接续状态

总目标仍为实现 yaca。R102 已提交为 `21d927f`，提交后工作区干净。继续来源缺项、
完整人工语义 Review 和最终目标资格；R101/R102 的所有下载、构建和测试句柄已结束。

## R103 初始化解释器的实际路径

在 `out/review-20261020/r103/before/` 从本地已提交的 `21d927f` 作独立 Git clone，
只复用三份已固定公开源码归档和固定 luainstaller Git 对象，没有复制解释器或 venv。
原样初始化 session `32160` 已确认返回 1，失败于 ensurepip。生成的 pyvenv.cfg
记录 home 为符号链接所在的 `.local/bin`，而实际标准库在独立 Python 安装目录。
直接导入 encodings 也失败，诊断保存在 `r103/python-before.log`。

修改 bootstrap，使创建 venv 时使用当前可用 Python 解释器的真实绝对路径；没有
替换 Python 版本或降低固定依赖要求。另一个带空格路径的独立检出
`out/review-20261020/r103/after checkout/` 完成实际验证，bootstrap 日志为
`r103/bootstrap-after.log`。Bootstrap session `55519` 已确认返回零，fresh venv 的
home 指向实际 Python 安装目录，标准库、pip 与 6 个固定解析器可正常导入，环境
核对见 `r103/environment-after.json`。当前源码与独立检出的 bootstrap SHA-256
一致。完整 Lua session `78731` 已退出零，735/735；同一独立检出的完整 readiness
session `75475` 已确认退出零，全部回归、契约及现代证明通过，结构为 273/5798/0。
R103 全部构建、初始化和测试句柄已结束，没有排队或后台验证待等待。

人工 Review 核对了解析当前可用解释器实际路径的内嵌 Python 语句、Shell 赋值和
引用、只在新建环境时进入的原分支、固定版本及源码摘要、共享资源守卫，以及
带空格路径的参数传递。没有新增函数或匿名回调；文件头日期与实际更新一致。
证据记录器的函数契约、排他写入和当前/冻结副本的字节绑定也已逐项核对。
全仓语义 Review 仍为 partial，R103 不作为目标或最终九包资格通过。

12 项实现及独立检出结果的当前/冻结绑定见 [R103 证据](tool-source-review/R103.json)。
这些检出来自本机 `21d927f`，仅复制本次 bootstrap 改动，三份公开源缓存与固定
luainstaller Git 对象复用；没有复制已构建 Lua、venv、私有配置或其他运行缓存。
验证是在已有宿主开发依赖下完成，不宣称另一台全新电脑已通过。

## R103 后接续记录

原目标仍为“实现 yaca”，按 D-093 保持活动。R101、R102 和 R103 的实现、实际验证
与原始证据已保存；R101/R102 已提交，R103 的实现与验收已完成。目前没有活跃
构建、下载或测试进程。来源缓存为 `out/source-cache/`，R100 原缓存档案及 R102 新
档案的身份见上文，接续时复用这些已核对输入，不重复恢复或重启操作。

剩余事项以 TRACKING 为准：Windows Git 的六个配方问题、ncurses 原快照、其余
静态子集/VCS/签名、R101 的过期快照与撤销新鲜度、完整二进制对应关系，以及
全仓语义 Review 和最终 C32/C33/C34。正式 Gate R 保持关闭，总目标未完成。

## R104 Win32 未恢复输入接续

R103 已提交为 `2f093e0`，提交后工作区干净。当前检查原三个 source-payload-pending
条目及其关联配方。Dash 0.5.8 已从 Debian 官方归档取得，SHA-256
`c6db3a237747b02d20382a761397563d813b306c020ae28ce25a1c3915fac60f` 匹配原配方；
原 HTTPS 上游握手失败，Kernel 候选路径返回 404。Connect 的 Bitbucket 原归档
session `86456` 已确认返回 22/404。

MSYS2 runtime 的当前配方列出旧 0001--0006 文件名，而目录只保留重编号后的
0017--0022；新文件的完整摘要不匹配旧固定值，不能重命名后当成原输入。
正在通过固定 Git 历史检查原始文件，同时按字面 `_ver` 和 pacman 版本变换核对
两份 OpenSSL 1.0.2.h-1 配方，不执行 shell 配方。

候选下载与 API 材料放 `out/review-20261020/r104/`。历史恢复 session `65485`、
OpenSSL 归档/签名下载 session `8520`、`73214` 均已确认退出零；没有活下载任务。
20 个 GitHub 原文件已核对 Git blob SHA-1 与实际 SHA-256，六项 runtime 原补丁
全部匹配原配方，而不同版本的重编号补丁及错误候选历史记录保留原样。

来源锁现有 1259 个固定成员：两份 OpenSSL 原配方与补丁、原归档/未验证签名、
Dash 归档和六项 runtime 原补丁已加入。配方恢复 117/121，余 4 项；静态结果为
101 个全部匹配、15 个子集、1 个仍无已核对静态载荷。Runtime 原 moving branch
尚未绑定到分发二进制，保持子集；全部来源与发布状态仍为 partial/未授权。
原 R102 覆盖报告按原字节保存在新 history 项，不删除原失败记录。

新档案已完成生产打包与来源接纳，session `17499`、`28816` 均已确认退出零。
日志为 `r104/bundle.log`、`r104/admission.log`；完整 readiness、证据冻结和干净
提交边界仍待收尾。R101--R103 的产物和所有原始失败记录继续保留。

### 精确输入与语义核对

两份 OpenSSL 配方分别来自
[MSYS2 原提交](https://github.com/git-for-windows/MSYS2-packages/tree/a8db1609f29a3777eb28f030b007f939f7ffc169/openssl)
与 [MINGW 原提交](https://github.com/git-for-windows/MINGW-packages/tree/096064b1bff4ca8ff7bed3c23b7b8c40861f73a4/mingw-w64-openssl)。
原 `_ver=1.0.2h` 的字面变换将字母后缀写成 `.h`，pkgrel=1，准确对应 1.0.2.h-1；
没有修改第三方配方来符合目标。原归档来自
[OpenSSL 官方旧版本归档](https://www.openssl.org/source/old/1.0.2/openssl-1.0.2h.tar.gz)，
SHA-256 `1d4007e53aad94a5b2002fe045ee7bb0b3d98f1a47f8b2bc851dcd1c74332919`
同时匹配两份配方。11 项本地补丁也全部匹配；分离签名只固定字节，保留待验证。

[Dash 原归档的 Debian 副本](https://archive.debian.org/debian/pool/main/d/dash/dash_0.5.8.orig.tar.gz)
SHA-256 匹配原声明，没有重新打包。六项 runtime 旧文件从
[固定 Git 历史](https://github.com/git-for-windows/MSYS2-packages/tree/69ed9dac86ecf03321f4a78494423ce1659ea280/msys2-runtime)
取得，全部匹配原声明。原配方的 source 与 prepare 名称存在不一致，其 moving
branch 与实际分发二进制还未完成对应核对；保留 verified-static-subset，未使用
今天的 master 充当旧源码。不同候选补丁的失败摘要与原始 API 返回均保留。

人工 Review 核对了历史收集器的全部函数、完整提交和 Git blob 身份、base64 内容
及字节数、递归目录与普通文件边界、排他保存；核对保存程序的原始 checksum
字面解析、source 顺序、两份版本变换、SKIP、VCS 待办、覆盖报告历史及部分状态。
使用的 R102 摘要/排他写入 helper 沿用其原实现与已核对契约。所有新辅助函数均有
完整文件头和参数/返回/错误/副作用注释，第三方原文件作者和字节未修改。

| 档案项目 | 实际值 |
| --- | --- |
| 本机档案 | `out/review-20261020/r104/git-win32-recovered-sources-r104-20261020.tar.gz` |
| SHA-256 | `1e8d3960b8ff5414f3a3cbfc32c14e2d650d144b441f3cfcd0b9724487b08146` |
| 字节数 | 463514142 |
| 固定来源成员 | 1259，另有档案自己的 source-profile.json |
| 来源装配/维护接纳 | 均 PASS，Git 2.10.0，source_closure=partial |
| 历史输入保留 | 原 1220 个非覆盖报告输入逐项保持一致；R102 覆盖报告按原字节移入 history |

档案尚未公开。源码与最终目标资格、全部语义 Review 的缺项继续保留。

完整 coding readiness PASS，session `10048` 已确认退出零，结构保持 273/5798/0。
密码学签名专项仍为 9/9。产品 src/native 无改动，完整 Lua 735/735 保留 R103
独立检出的实际范围，本节点未把其写成一次新的目标或逐包测试。
47 项当前/冻结来源、辅助程序、原始 GitHub 返回、失败候选和完成结果的字节绑定
见 [R104 证据](tool-source-review/R104.json)。记录器也已逐项核对注释和实际行为。

## R104 后接续记录

总目标为“实现 yaca”，按 D-093 保持 active，尚未完成。R101 `7c20297`、R102
`21d927f`、R103 `2f093e0` 已提交；R104 来源装配、来源接纳、完整 readiness、
本轮人工语义 Review 和证据冻结均已完成，可以从本节点继续。

当前不存在需要等待或重启的后台操作：R104 历史收集 `65485`、OpenSSL 下载
`8520`/`73214`、来源装配 `17499`、来源接纳 `28816`、readiness `10048` 和失败
候选保留检查 `39919` 都已确认成功退出；Connect 原归档 `86456` 的 404 失败已
保留。R101--R103 句柄也已结束。产物和原始日志位于 `out/review-20261020/`，
来源缓存为 `out/source-cache/`；复用前按对应节点摘要核对，不重启生产操作。

下一项仍按 TRACKING。Win32 剩余 4 个原配方问题为 git-extra、Git Credential
Manager、MPFR 3.1.4.-1、Net-SMTP-SSL 1.02-1。只读查询已确认 git-extra 的候选
仓库为 build-extra，版本中的短提交对应
`6a8c8570cfa9578af798d7b03d33b81f9f414a97`；尚未恢复/接纳它的原配方。
MPFR 候选 `2f187729af77224bb80064a68b1e58f16631973e` 声明 3.1.4-1，缺少目标
中的尾点，不能直接写成精确匹配。查询到的 Net-SMTP-SSL 历史配方仍为 1.01-2，
不冒充 1.02-1。上述只读线索未作为已完成来源计数。

后续还需处理 Connect/ncurses 原归档、其他静态子集、runtime VCS、分离签名、
R101 的密钥有效性/撤销新鲜度及全部二进制对应关系；全仓人工语义 Review、
最终 C32/C33/C34 与独立 Gate R 评审仍待完成。没有扩大产品功能或历史资格范围。

## R105 精确旧配方接续

上一轮属于实际进展：四个本地提交改变实现、恢复原来源并完成对应验证。当前
HEAD 为 `8f64c77`，起始工作区干净。R101--R104 的生产、下载与测试句柄均已结束。

在新目录 `out/review-20261020/r105/build-extra.git` 获取固定完整提交
`6a8c8570cfa9578af798d7b03d33b81f9f414a97`，fetch session `41644` 已确认退出零。
实际 `git rev-list --count <commit> -- git-extra` 为 120，短提交为 6a8c857，与原
pkgver() 的作用范围一致，动态版本为 1.1.120.6a8c857-1。相同提交还有 Credential
Manager 1.6.1-1 配方。MPFR 的更早提交
`b98235867c2366c62ac177bfad42ced92fb547f8` 保留空补丁号后的尾点，匹配 3.1.4.-1。

原 GCM 配方输入为编译后的 ZIP。它只能作为独立二进制对应核对输入；本轮另取
上游 v1.6.1 对应源码提交 `96a2c6a2789ba3cf27e4e3edba0cb4db9e5457cb`，不会把
二进制 ZIP 加入对应来源锁。配方收集器复用已核对并验证摘要的 R104 helper，
收集与原始对象记录在 `r105/collect-recipes.log` 和 `r105/github/`。

候选下载位于 `r105/downloads/`，MPFR/签名、GCM 源码/二进制及三个旧来源容器
分别使用 session `94605`/`38293`、`15222`/`59727`、`72335`/`11922`/`88132`。
初始下载已核对终态：MPFR、GCM 二进制、ncurses 容器成功；GCM 源码与 Connect
容器首次 TLS 失败，明确退出后有界重试取得。SMTP 容器候选保留 404/TLS 失败。
完整回执见 `r105/download-receipts.json`，没有活下载句柄。

收集 session `23963` 在 GitHub 只读请求失败后明确退出 1，原代码、已取得对象和
失败日志保留。验证相同不可变对象请求恢复后，使用另一个 receipt 目录继续，
每次只读失败最多三次有界请求，中间实际等待 2 秒；session `98306` 已退出零。
30 个原始文件及全部 Git blob/字节记录均已恢复，Git-extra 18 项原 MD5 同时匹配，
并另以 Git blob 与 SHA-256 固定来源身份。

两份历史来源容器分别含原 ncurses 和 Connect 归档；内层文件 SHA-256 全部匹配
仓库先前从原 Git 配方取得的固定值。ncurses 容器配方也逐字匹配；Connect 容器
配方仅 checksum 字段使用原 SHA-1，仓库原配方使用 SHA-256，差异保留，没有
用容器配方替换原 Git 配方或降低实际接纳的 SHA-256。第一轮过严的容器配方
逐字比较失败记录及原辅助程序保留，修正后只用独立 primary pin 接纳内层来源。

R105 来源锁已更新，恢复 120/121 个精确配方，剩 Net-SMTP-SSL 1.02-1；已恢复
配方的 120 个版本中，静态结果为 105 个全部匹配、15 个子集，没有完全未核对
静态载荷的条目。GCM 原二进制 ZIP
摘要匹配配方但排除于来源锁；另加入上游 v1.6.1 的真实源码提交、源码档案和
MIT 原许可，依赖及二进制对应关系继续待核对。新档案已完成装配与接纳，session
`36660`、`1276` 均确认退出零。完整 readiness session `77842` 也已确认退出零，
结构仍为 273/5798/0。日志分别为 `r105/bundle.log`、`r105/admission.log` 和
`r105/readiness.log`；最后还需完成本节证据冻结与干净提交边界。

### 版本与来源身份

git-extra 和 GCM 原配方来自
[build-extra 固定提交](https://github.com/git-for-windows/build-extra/tree/6a8c8570cfa9578af798d7b03d33b81f9f414a97)。
git-extra 的静态 pkgver 旧值没有直接当成当前版本：读取原 pkgver() 的目录和
命令语义，实际 Git 路径历史计数为 120；18 项原 MD5 均匹配，所有原文件另绑定
Git blob 与 SHA-256。没有运行第三方函数来取得版本。
MPFR 来自 [保留尾点的原提交](https://github.com/git-for-windows/MSYS2-packages/tree/b98235867c2366c62ac177bfad42ced92fb547f8/mpfr)，
原配方的空 `_patchlevel` 与明确的点一起生成 3.1.4.，pkgrel=1。原 tar.xz 的
SHA-256 `761413b16d749c53e2bfd2b1dfaa3b027b0e793e404b90b5fbaeef60af6517f5`
匹配，补丁匹配，分离签名保留待验证。

历史 [ncurses 容器](https://downloads.sourceforge.net/project/sources.msys2-snapshot.p/msys2/msys/sources/ncurses-6.0.20160220-1.src.tar.gz)
与 [Connect 容器](https://downloads.sourceforge.net/project/sources.msys2-snapshot.p/msys2/mingw/sources/mingw-w64-connect-1.104-1.src.tar.gz)
仅作为字节载体。内层文件分别匹配原 SHA-256
`34387d968a37cbc2362f62d44d44bb9c27cd288261262bd06f3b053994c90401` 与
`e262cd3a6ee66e65187f3780ca808bc8dddee03dc5c5755b2b9c4db10274eb40`。
容器自己的摘要、普通成员检查和配方差异均保留，原 Git 配方和前轮失败未覆盖。

GCM [v1.6.1 上游提交](https://github.com/microsoft/Git-Credential-Manager-for-Windows/commit/96a2c6a2789ba3cf27e4e3edba0cb4db9e5457cb)
与原来源档案的 Git pax comment 一致，档案含真实 C# 源码。原二进制 ZIP 的
`0701e05077c3c56f79ca136c9897b1689455d580f87b201552d147e6dd7751b8`
仅用于二进制对应核对，生产来源档案中实际没有该 ZIP。
源码与已发布二进制的原许可字节不相同；检查确认差别为 CRLF 与末尾一个 DOS
EOF 标记，解释这两个表示差异后 MIT 文本逐字相同。两份原字节都保留，没有改写
上游文件来令摘要一致。原始比较和明确的 EOF 比较见 `r105/gcm-license-*.json`。
NuGet/依赖、实际二进制重建对应关系仍待审核。

### 人工 Review 与本批验证

逐项核对了收集器、嵌套有界重试回调、源文件保存、字面数组解析、原摘要比较、
镜像成员读取、GCM 源码/二进制分离及历史覆盖报告的参数、返回、异常和实际
副作用。首次收集与容器过严检查的失败、对应源程序、已保存对象与后续成功日志
分别保留。未执行 PKGBUILD、C#、安装器或任何下载的软件。

| R105 档案 | 实际值 |
| --- | --- |
| 本机路径 | `out/review-20261020/r105/git-win32-recovered-sources-r105-20261020.tar.gz` |
| SHA-256 | `6bbc38cff8a4e0a9ab6c32bb71a2a77a86bea508103b4bb36d3637b2f4d51663` |
| 字节数 | 471355560 |
| 固定成员 | 1319，另有档案自己的 source-profile.json |
| 装配与来源接纳 | PASS；source_closure=partial，编译 GCM ZIP 实际排除 |
| 原输入保留 | 原 1258 个非覆盖报告输入保持一致，R104 覆盖报告按原字节移入 history |
| 完整 coding readiness | PASS；源码/打包/来源/验签回归、契约与现代证明均通过，结构 273/5798/0 |

产品 src/native 未变，完整 Lua 735/735 保留 R103 的实际独立检出范围。
本轮源文件与注释 Review 不扩大为全仓语义 Review 完成，正式 Gate R 保持关闭。

### 辅助代码注释补查与 Python 变参

额外使用同一个 AST 检查器审查本轮本地辅助程序，发现 R101 的正确 `@param ...`
被 Python 分支误判为应写收集变量名。新增三项实际语法反例，旧实现为 15/18；
修复后为 18/18。现在直接和带类型的 *args/**kwargs 都按签名位置标为 `...`，
不把单独的 keyword-only `*` 或默认值中的嵌套 lambda 错当成外层变参。
两处已有回调注释同步修正，函数行为未改；本地 14 个辅助程序 / 39 个声明的
实际 AST 审查为 0 缺项。

全仓结构增加三项回归声明，为 273/5801/0。最终 readiness session `24771`
在 proof-evidence 的双重来源 pin 检查处明确退出 1：TP-006 的注释修正已改变
文件摘要，manifest 已更新，而校验器的独立固定值仍旧。先单独执行新 TP-006，
核对通过结果后再同步校验器 pin 并复跑；原失败日志为 `r105/readiness-final.log`，
未覆盖或当作成功。

新 TP-006 单独执行 319 断言通过后，manifest 与校验器的独立 pin 同步为
`92c4b6c581832e03ff4e1a714d2329372024bec9e01490f6df1e1f1615857297`。
最终完整 readiness session `47912` 已确认退出零，proof-evidence 56 断言、
TP-006 的 319 断言与其余全部检查通过；完整日志为
`r105/readiness-final-refresh.log`。辅助脚本补查仍是 14 文件 / 39 声明 / 0 缺项；
全仓结构为 273/5801/0。两个已有 Python 回调只修改注释，原生 Windows 的旧
旅程证据保留其原源字节范围，没有宣称重跑物理机。

81 项来源、原始对象、辅助程序、真实失败、前后回归、全仓/辅助注释与最终
readiness 结果的当前/冻结绑定见 [R105 证据](tool-source-review/R105.json)，162 份
字节核对一致。新档案尚未公开，不修改原 R95/R100 公开附件或提升来源状态。

## 最新接续记录

目标仍为“实现 yaca”，按 D-093 保持 active，未完成。R105 已完成来源恢复、
来源装配与接纳、注释检查器修复、反例/全仓/本地辅助结构检查、TP-006 刷新、
最终 readiness 和本轮人工语义 Review；下一步在干净提交边界后继续 TRACKING。

所有本轮已启动句柄均有终态，无后台生产任务要重启：Git 历史 fetch `41644`
成功；首次收集 `23963` 已失败退出，后续收集 `98306` 成功；候选下载与失败
终态完整记录在 `r105/download-receipts.json`；装配 `36660`、接纳 `1276`、首次
readiness `77842` 成功。后续变参修复的 readiness `24771` 在双重 pin 校验处
失败，修复并单独重跑 TP-006 后，最终 `47912` 已成功退出。所有失败原文保留。

本机权威输入为 `out/source-cache/` 和 R105 的 1319 成员档案，摘要见本节；原
R104 及更早档案保留历史身份。当前没有活构建、下载或测试句柄，不因旧 session
过期重新开始恢复操作。代码与当前状态以 Git 和 TRACKING 为准。

剩余精确配方为 Net-SMTP-SSL 1.02-1。原候选源容器 404/TLS 失败，不能用已
找到的 1.01-2 配方或其他版本替代。后续继续其来源核对、其余 15 个静态子集、
runtime VCS、分离签名与密钥有效性/撤销新鲜度、GCM 依赖及全部二进制对应关系。
全仓人工语义 Review、最终 C32/C33/C34 与独立 Gate R 评审仍未完成。
