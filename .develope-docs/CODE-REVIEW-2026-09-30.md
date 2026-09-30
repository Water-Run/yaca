# 同步、索引读取与 Windows 开发检查复核

日期：2026-09-30。起点是无未提交改动的 `main` / `23bf913`，执行 fetch/prune
和 `git pull --ff-only origin main` 后同步到 `344f864`。本轮修改基于该提交，
未改变产品范围或发布门；当前状态与执行队列分别归入 CURRENT-STATE / TRACKING。

## R51--R53：附带软件索引读取

核对 `src/bundled.lua` 的 `read_file` 与 `src/tools.lua` 的
`describe_environment` 后发现三个实际问题：

| 编号 | 修复前行为 | 修复与证据 |
| --- | --- | --- |
| R51 | `read_file` 先按 EOF 退出，再检查累计大小；16,384 字节后末块带 1 字节且 EOF=true 时返回超限内容 | 累计字节在 EOF 判定之前校验；16,384 可接受、16,385 返回 BundledIndex，句柄各关闭一次 |
| R52 | 两条读取路径均未拒绝 bytes="" / eof=false，无进展时可一直循环 | 共用读取服务，在首个空非 EOF 块返回 BundledIndex 并关闭；有限 fake 流验证只读一次，不以超时掩盖问题 |
| R53 | 环境说明的独立循环读失败后仍 parse 已读前缀；前缀恰好是有效索引时把不完整内容投影给模型 | `describe_environment` 复用 `bundled.read_file`，完整读取成功后才解析；失败保留基础环境说明，不投影前缀 |

读取使用增量字节计数，循环中不再反复拼接整个前缀。`.software` 沿用同一
`read_file`；大小/无进展错误为 BundledIndex，底层 read 失败原样返回，成功或
已报告失败后关闭句柄。生产 filesystem 负责 chunk 形态与单块上限校验，
本轮不新增另一套 native 端口协议。

新增四项 Lua 回归：末块大小边界、无进展拒绝、read 错误及所有权、完整索引
环境投影。修复前专项 `total=23 passed=20 failed=3`；错误传播用例原先已通过，
本轮保留它约束共用入口。修复后 **23/23**，日志 `before.log` / `focused.log`。

人工核对了读取成功/EOF/超限/空块/read-error 的收尾、唯一关闭次数、错误对象
传递，以及模型环境投影只消费完整 bytes 的调用关系。同步修正 failure 和
bounded_field 的注释，不把普通 table 或未执行 UTF-8 校验的字节字段说成 frozen
或已校验 Unicode。这不扩展为整个 tools.lua 或全仓语义 Review 完成。

## R54：CRLF 文件头与 checkout 字节

Windows checkout 的 Lua/C/PowerShell 头使用 CRLF。检查器直接匹配 `\n` 分隔
的块头，对本工作区 **182** 个文件误报缺少固定头；声明覆盖本身未缺失。
修正仅规范化文件头校验所用的解码文本，语法树仍读取原始字节，因此节点偏移
和行号不受影响，参数/返回值检查也未放宽。

新增六种后缀（Lua/C/H/PowerShell/Python/Shell）的 CRLF 正反例，含 Python
shebang/编码声明；错误作者及字段重排仍拒绝。修复前 15 项中 4 个子场景失败；
修复后 **15/15**。全仓结果 **219 文件 / 5234 声明 / 0 缺项**。

首次完整 Lua suite 在 Windows 的自动换行转换下为 **669/682**，13 项失败
均来自 byte-exact golden、固定补丁 SHA 或 native 源码片段的 CRLF 差异。
添加 `.gitattributes`，以 `* text=auto eol=lf` 固定文本 checkout 的 LF；
本地源码、补丁和 golden 按仓库 canonical 字节还原，未改锁定摘要或断言。
233 个文件的本地换行还原不产生对应的 Git 内容变更。
还原后完整套件 **682/682**，保留初次失败与最终成功日志。

人工核对 CRLF 转换只作用于 header 文本副本、日期/文件名/字段次序校验保留，
`.gitattributes` 使用 auto 保留二进制识别，未降低补丁和 golden 的字节要求。

## 验证环境与复现

- Windows 宿主；Ubuntu 24.04.4 / WSL2，内核 6.6.87.2-microsoft-standard-WSL2。
- Lua 5.5.1 官方源码 SHA-256：`1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce`，与仓库 proof pin 一致；Linux 配置本地构建。
- Python 3.13.15 隔离在 `out/review-20260930/python/`；解析器使用仓库锁定版本，tree-sitter 0.25.2。
- 构建和完整 Lua suite 使用资源守卫串行运行；最初 checkout 的 guard CRLF 无法被 bash 读取，准备阶段仅使用它的 LF 等价副本，后续使用原入口。

本轮日志根目录为 `out/review-20260930/`：

| 文件 | 用途 |
| --- | --- |
| `before.log` / `focused.log` | 索引三个反例与修复后专项 |
| `full.log` / `full-final.log` | checkout 换行导致的失败与最终 682/682 |
| `comment-before.log` / `comment-tests.log` | CRLF 文件头反例与 15/15 |
| `comments.log` / `comments.json` | 全仓结构摘要及逐声明清单 |
| `validators.log` | 契约 7738、证明登记 56、readiness 565 条断言与 5 项公开文档真值检查通过；未安装 xmllint，外部 Relax NG 检查未执行 |
| `runtime/build.log` / `runtime/rebuild.log` | 固定 Lua 的本地准备与 Linux 构建 |

在 WSL 的仓库根复现本轮 Lua 检查：

```sh
bash .tools/run_with_resource_guard.sh \
  out/review-20260930/runtime/lua-5.5.1/src/lua test/run.lua
```

在 PowerShell 的仓库根复现注释检查：

```powershell
$env:PYTHONPATH = "$PWD/out/review-20260930/parsers"
$reviewPython = "$PWD/out/review-20260930/python/cpython-3.13.15-windows-x86_64-none/python.exe"
& $reviewPython test/self/code_comments_test.py
& $reviewPython .tools/check_code_comments.py --inventory out/review-20260930/comments.json
```

本轮不重新构建最终发行包，不运行 XP/Win7/CentOS 7 目标或真实模型旅程；
重量级 proof 链也未重跑。开发机 suite 和注释结果不能替代上述证据。
历史候选为 7/9，Windows 两个 full、Win7 fs-open、真实模型旅程及最终九包
验收继续由 [TRACKING.md](TRACKING.md) 跟踪，Release Gate R 保持关闭。
