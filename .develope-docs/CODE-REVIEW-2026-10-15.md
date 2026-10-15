# 2026-10-15 来源、打包与验签 Review

按 [D-091](DECISIONS.md#d-091-从-r97-恢复开发2026-10-15) 恢复开发。同步 main 无新增，
从 R97 的 `43c8038` 接续；产品运行代码和 R95 冻结核心未变。

## R98 来源档案的原子发布

来源打包器先检查输出不存在，再调用 rename。在 POSIX 上，另一写入者恰好在
rename 前创建的文件会被替换；断开的输出符号链接也未被 exists 检出。
两项真实文件系统反例使专项从 12/12 变为 12/14。

现在使用 lexists 接纳输出占用状态，验证结束后以同目录硬链接原子创建输出。
并发占用直接失败，临时目录照常清理；文件系统不支持硬链接时保留错误，不退回
可能覆盖的发布方式。Linux 与 Windows 原生各 14/14。Windows 的 readlink 会
返回扩展路径表示，夹具保存实际原始链接文本再比较，校准失败日志一并保留。

人工语义核对覆盖存在性检查、同目录临时文件、链接发布、冲突异常、清理及新回调
的逐项参数和返回语义。证据见 [R98](tool-source-review/R98.json)。

## R99 原始签名与跨平台验证

R97 的 18 个分离签名文件已经恢复。新增维护工具
`.tools/qualification/verify_source_signatures.py`：先核对并复制来源、签名和公钥的
SHA-256，再在临时 GnuPG home 中运行已安装的 gpg/gpgv，要求真实 VALIDSIG 的
完整主密钥身份符合显式清单。缓存后续变化不会改变已经固定的验证输入。
验证结果保留每项失败，写入新报告，不修改默认密钥环。

第一轮实际验签为 8/18，补齐可用公钥后为 17/18。npth 1.7 原配方固定
`5B80C5754298F0CB55D8ED6ABCEF7E294B092E28`，当前取得的原始源码分离签名实际由
以下两把发布密钥签署。逐项核对 [GnuPG 官方发布密钥页面](https://gnupg.org/signature_key.html)
及[官方公钥文件](https://gnupg.org/signature_key.asc)后，在独立验签清单记录这次
身份更新；原配方与原密钥身份保留，未改写第三方配方来宣称原配方验签通过。

| 身份 | 完整主密钥指纹 |
| --- | --- |
| Werner Koch，dist signing 2020 | `6DAA6E64A76D2840571B4902528897B826403ADA` |
| Niibe Yutaka，GnuPG Release Key | `AC8E115BF73E2D8D47FA9908E98E9B2D19C6C8BD` |

最终全部 18 项实际验签通过。ncurses 的原签名从已核对的官方来源容器取出，与
原快照配对验证；未采用较新配方或补丁。公钥下载位置、实际字节摘要、配方原身份、
官方页面快照和签名结果均保留。

Windows 原生检查发现，Git 附带的 MSYS gpgv 会将盘符开头的 keyring 路径作为
资源 URL 拒绝。工具现在以临时目录为工作目录，使用明确的相对文件名与 keyring。
公开夹具使验签测试只需已安装的验签程序；Linux 与 Windows 原生的 5 项真实
OpenPGP 检查均通过，含改后重新计算摘要的坏签名和错误主密钥身份。

按照 [gpgv 文档](https://www.gnupg.org/documentation/manuals/gnupg/gpgv.html)，它不会
检查密钥过期和撤销。本工具明确保留这个边界，PASS 表示固定字节与允许身份的
签名匹配；密钥有效性、实际二进制对应关系和发行资格仍单独审查。

## 新来源档案与范围

当前 Win64 Git 来源锁固定 605 个成员，含 38 个精确版本的配方/来源输入、18 项
已验证签名、公钥与核对记录。旧 R95 来源状态按原字节保存在
`history/R95-SOURCE-STATUS.json`；当前范围见 `SOURCE-COVERAGE.json`。

| 项目 | 结果 |
| --- | --- |
| 档案 | `git-win64-signed-sources-20261015.tar.gz` |
| 字节数 | 614826994 |
| SHA-256 | `a934e775567660e5c3582bef08d8b33c964dcb4e54242418487d5d9316d16001` |
| 已核对分离签名 | 18/18 |
| 来源状态 | `partial`，密钥有效性与二进制完整对应关系仍待人工核对 |

来源档案位于本机 WSL 的
`/home/linzh/.cache/yaca-release-readiness-20261011/sources/`，尚未上传为新公开附件。
Git 维护工具、公开测试夹具、来源锁及证据索引。原 R95 公开附件未变。

最终完整 readiness PASS，全仓结构检查为 272 个文件 / 5788 个声明 / 0 缺项；
新来源档案通过维护装配器接纳并保持 partial。固定构建缓存的缺项、恢复和复跑日志
均保留。完整结果及逐文件绑定见 [R99](tool-source-review/R99.json)。
全仓人工语义 Review 保留 partial；未将本轮工具的审查扩大为全仓完成，未将
来源签名恢复提升为最终九包资格。剩余工作继续见 [TRACKING](TRACKING.md)。
