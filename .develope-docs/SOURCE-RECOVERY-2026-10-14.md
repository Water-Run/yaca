# R97 原始来源恢复与节点收尾

日期：2026-10-14。本节点接续 R96 的 Win64 Git 2.46.2 SDK 来源恢复。
按 [D-090](DECISIONS.md#d-090-来源恢复节点收尾后暂停2026-10-14) 整理、推送后暂停。
产品运行代码和已公开 R95 候选的字节未变，Release Gate R 继续关闭。

## 恢复范围

R96 首轮的 10 个整包输入缺项已恢复为原摘要匹配的必要静态或 VCS 输入；其中
7 个配方的静态摘要全部核对，3 个保留分离签名缺项。合并此前结果，38 个版本中
20 个静态摘要全部核对、18 个为静态子集。完整二进制对应关系仍待人工核对。
整个过程将 PKGBUILD 作为数据读取，没有在开发宿主执行配方。

| 原始版本 | 本节点恢复与核对 |
| --- | --- |
| GnuTLS 3.8.4-1 | 展开字面 `%.*` 变换，原始源码和补丁摘要匹配 |
| MSYS2 runtime 3.4.10-7 | 导出原 Cygwin 提交，原 VCS tar 摘要匹配 |
| CA certificates 20240203-2、mingw CA 20240203-1 | 从 Debian snapshot 恢复原始归档，两配方原摘要匹配 |
| mingw GCC 14.2.0-1 | 核对原配方 `_rc`、`_snapshot` 为空的 release 分支，原归档摘要匹配 |
| mingw winpthreads-git 12.0.0.r297.g0be496546-1 | 使用 Linux Git 导出原提交，原 VCS tar 摘要匹配 |
| mingw libzip 1.10.1-2 | 恢复项目原始 tar.xz，原 sha512 匹配 |
| ncurses 6.5.20240831-1 | 从官方 rel2 来源容器取出原 snapshot，摘要匹配 rel1 固定值；保留 rel1 配方与补丁 |
| vim 9.1.0707-1 | 核对静态默认 pkgbase，原来源摘要匹配 |
| filesystem 2023.02.07-2 | 保留原 Git blob；按原属性导出 CRLF 的 `msys2_shell.cmd`，原摘要匹配 |

CA 原始归档来自 [Debian snapshot](https://snapshot.debian.org/file/e05a7cc1cab263bc4836487f878b3056b7217101)，
SHA-256 为 `3286d3fc42c4d11b7086711a85f865b44065ce05cf1fb5376b2abed07622a9c6`。
ncurses snapshot 来自 [MSYS2 官方来源容器](https://repo.msys2.org/msys/sources/ncurses-6.5.20240831-2.src.tar.zst)，
成员 `ncurses-6.5-20240831.tgz` 的 SHA-256 为
`685161fec9c20c0896f6d7569f8d1cba9124a1884d3d8be527253a773b787577`。
较新的容器仅用于取得该原始成员，未采用其中的新配方和补丁。

## VCS 与检出字节

VCS 摘要按 [pacman 的 Git 来源实现](https://gitlab.archlinux.org/pacman/pacman/-/blob/v6.1.0/scripts/libmakepkg/source/git.sh.in)
核对提交导出的原 tar 字节；提交归档的时间与 pax 身份语义见
[Git archive 文档](https://git-scm.com/docs/git-archive)。

| 来源 | 精确提交 | 原 tar SHA-256 |
| --- | --- | --- |
| Cygwin 3.4.10 | `89a1e4a573d40b233011402f42630b970ff71291` | `4fb94e9f3bab9666dcab50c8940de6e8801d0aae900f0b5a6f79406479e757f1` |
| winpthreads | `0be496546aca8f820e00a88ccba8d28c14b73484` | `03668d86bdb5515f10ef1c2bc77cc3ca60d5ff596686269696d57859114920c9` |

winpthreads 首次 Windows 原生 Git 导出未匹配，后续 Linux Git 导出匹配；两次结果
都保留，不将未经验证的差异原因写成结论。filesystem 原提交的 `.gitattributes`
指定 `*.cmd text eol=crlf`。原 LF blob 和按属性取得的 CRLF 输入分别保存；
没有为迎合摘要任意改写第三方字节。

## 来源锁与验证

维护锁为 [`release/windows-git64-sources.lock.json`](../release/windows-git64-sources.lock.json)，
含 565 个固定成员，记录原始主源码、官方来源包、38 个精确版本的配方、补丁和恢复输入。
新来源档案保留 R95 的历史 `SOURCE-STATUS.json`，另加入当前 `SOURCE-COVERAGE.json`。

| 项目 | 结果 |
| --- | --- |
| 档案 | `git-win64-recovered-sources-20261014.tar.gz` |
| 字节数 | 614486514 |
| SHA-256 | `145943b40573df54ff8ed8c679a50faba8e66231aea5e31934072103ccd686d2` |
| 来源装配与成员验证 | PASS |
| 维护装配器来源接纳 | PASS，Git 2.46.2，`source_closure=partial` |
| 剩余输入 | 18 个分离签名条目；二进制完整对应关系另待人工核对 |

档案保存在本机 WSL 缓存
`/home/linzh/.cache/yaca-release-readiness-20261011/sources/`，尚未上传为新的公开附件。
Git 保存来源锁、摘要和证据索引；本节点没有覆盖已公开的 R95 附件。
新机器可拉取维护源码继续开发，历史缓存和本地原始日志需要另外取得。

恢复程序、失败与成功报告、冻结副本及逐文件字节绑定见
[R97 证据](tool-source-review/R97.json)，原始材料在 `out/review-20261014/r97/`。
本节点只恢复数据和验证来源档案；R96 已通过的专项 12/12、完整 Lua 735/735、
coding readiness 和结构 270/5771/0 保留其原范围，不写成本节点的新完整测试结果。
全仓人工语义 Review 仍为 partial。

收尾复核：30 项证据的当前文件与冻结副本共 60 份字节绑定一致；来源锁为
565 个输入、18 个待完成条目。资源守卫下的 documentation-truth 校验通过，
5 份公开文档与关闭的 Gate R 状态一致；`git diff --check` 通过。推送前同步远端，
main 无新增提交。

来源锁入库时统一为 Git 约定的 UTF-8/LF，并重新绑定当前文件与对应冻结副本的
摘要；原 CRLF 冻结文件另保留在 R97 证据中。JSON 数据、输入摘要和来源档案未变。

后续待办留在 [TRACKING](TRACKING.md)：分离签名与实际二进制对应关系、Win32 来源
闭包、最终九包资格及剩余语义 Review。按负责人要求，本节点推送后等待恢复指示。
