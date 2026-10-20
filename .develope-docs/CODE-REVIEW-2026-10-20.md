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

总目标仍为实现 yaca。R102 来源数据装配接纳、完整 readiness 与证据冻结已完成，
下一步形成干净提交边界；没有活下载、构建或测试句柄。之后继续来源缺项、完整
人工语义 Review 和最终目标资格。本机初始化中发现的 uv 符号链接解释器建 venv
问题也需修复维护入口，不能把本轮环境 workaround 当作该入口已兼容。
