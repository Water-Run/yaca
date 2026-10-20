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

## 下一步

先冻结 R101 的实现、测试及实际结果，在提交边界干净后继续 P0。下一项接续 Win32
来源缓存中的 6 个配方问题和 Bash/readline/ncurses/vim 四个尚未尝试的载荷版本；
同时保留本轮发现的密钥有效性待办。总目标“实现 yaca”仍未完成。
