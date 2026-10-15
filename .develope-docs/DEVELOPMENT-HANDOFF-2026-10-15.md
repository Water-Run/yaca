# 开发接续：2026-10-15 节点

按 [D-092](DECISIONS.md#d-092-当前节点打包推送后暂停2026-10-15) 完成打包推送后暂停。
维护源码以 main 为准；正式 Gate R 关闭，目标资格验证待完成。

## 换一个目录或电脑继续

开发环境使用 Linux 或 WSL，准备 Git、C 编译器、Make、CMake、curl、tar、patch、
xmllint，以及带 venv/pip 的 Python 3.13。初始化会从公开源取得固定依赖。

```sh
git clone https://github.com/Water-Run/yaca.git
cd yaca
bash .tools/bootstrap_development.sh
source out/development/activate.sh
bash .tools/run_with_resource_guard.sh bin/lua55 test/run.lua
bash .tools/run_coding_readiness.sh
```

已有检出可先执行 `git pull --ff-only origin main`。每次新 shell 重新 source 激活
脚本。源码和常规开发检查不依赖旧机器的 out、模型配置或来源恢复缓存。
在线模型旅程的私有配置按环境另行准备。

也提供 main 的 Git bundle。离线检出时使用：

```sh
git clone --branch main yaca-main-through-r100.bundle yaca
cd yaca
git remote set-url origin https://github.com/Water-Run/yaca.git
```

之后可从 origin 拉取新的 main；首次依赖初始化仍需联网。

## 本节点的附件

开发接续节点为
[`v1.0.0-preview.20261015`](https://github.com/Water-Run/yaca/releases/tag/v1.0.0-preview.20261015)。
附件在发布完成后可取得；实际公开回执另记录在 candidates。

| 附件 | 用途 |
| --- | --- |
| 当前源码 tar.gz | 冻结的完整维护源码，不含构建缓存 |
| `yaca-main-through-r100.bundle` | main 的完整提交历史，可离线 clone |
| `yaca-source-cache-20261015.tar.gz` | 两 Windows Git 来源锁所需的已恢复公开输入，按原缓存相对路径保存 |
| 开发证据 ZIP | R96--R100 的公开核对材料及独立检出验证日志 |
| `RUNTIME-ASSETS.json` | 未变的 R95 九包及配套附件的下载地址、大小与摘要 |
| `SHA256SUMS.txt` | 本次附件的 SHA-256 |

产品 src 与 native 的 Git 树和 R94 核心源码一致。运行包继续使用
[R95 九包](https://github.com/Water-Run/yaca/releases/tag/v1.0.0-preview.20261013)，
保留其冻结核心、实际环境与资格范围。

## 继续来源核对

先核对附件摘要，再将来源缓存解压到新目录。该附件的 `source-profile.json`
列出全部公开输入及各自摘要；其余成员按来源锁的 cache 路径保存。

```sh
mkdir -p out/source-cache
tar -xzf yaca-source-cache-20261015.tar.gz -C out/source-cache
bash .tools/run_with_resource_guard.sh python3.13 .tools/qualification/bundle_corresponding_sources.py \
  release/windows-git64-sources.lock.json out/source-cache out/git-win64-sources.tar.gz
bash .tools/run_with_resource_guard.sh python3.13 .tools/qualification/bundle_corresponding_sources.py \
  release/windows-git32-sources.lock.json out/source-cache out/git-win32-sources.tar.gz
```

来源档案接纳需要计算新生成档案的完整 SHA-256，再按
[执行手册](QUALIFICATION-RUNBOOK.md#windows-full-来源输入)传入。压缩实现的差异
可能改变归档摘要，成员仍须匹配维护锁。来源状态保留 partial。

Win64 已实际核对 18 项签名，余密钥有效性与完整二进制对应关系。Win32 去重并
归并三个拆包名称后，115 个版本已有原配方，余 6 个配方问题；4 个配方的载荷
还未尝试。当前 20 项恢复中 4 项静态摘要全部匹配、13 项取得已验证子集、3 项
保留未解决结果；未把子集写成完整恢复。具体输入和失败在 SOURCE-COVERAGE.json。

恢复开发后从 [TRACKING](TRACKING.md) 接续。最终九包资格和全仓人工语义 Review
仍待完成；本节点的开发检查与来源附件保留各自范围。
