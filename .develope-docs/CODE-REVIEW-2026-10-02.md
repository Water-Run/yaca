# R74 与首批真实模型联网证据

日期：2026-10-02。基于 `0686fb3`。负责人提供两个真实模型端点后，
联网资格自测首次执行；发现并修复适配器缺陷 R74，随后双模型
Stage 2 全项与 Stage 3 通过。密钥仅存隔离部署目录（gitignored），
未入库、未入任何文档。

### R74 与首批真实模型联网证据（10-02）

负责人提供了两个真实模型端点，联网资格自测首次执行：

- **DeepSeek（外网 API）**：deepseek-flash / deepseek-v4-pro，密钥仅存
  隔离部署目录（gitignored），未入库、未入文档。
- **本地 qwen3.8-27b（DGX Spark, sglang, 262k 上下文）**：局域网端点。

**R74（真实缺陷，已修复）**：sglang 系服务器在 OpenAI 响应中显式发送
`"tool_calls": null`（规范允许的缺省拼写）。JSON null 解码为 truthy 哨兵表，
非流式 `message.tool_calls` 与流式 `delta.content/reasoning_summary/tool_calls`
只判 Lua nil 不判 JSON null，哨兵进入数组校验即触发 `openai-tool-calls`
协议错——本地 Qwen 的 WIRE 检查因此失败，DeepSeek（不发送该拼写）不受影响。
窄修复补齐四处 JSON null 守卫；新增 adapter 回归（非流式含 null 的完整
响应 + 流式含 null 的 delta）。修复前专项 11 项中 1 项失败（真实复现），
修复后 **11/11**；完整 suite **699/699**（`full-suite-r74.log`）。

**修复后的真实联网结果**（R74 刷新后的 Win64 核心 `a310ac78...`，
隔离部署于本机 NTFS）：

| 检查 | DeepSeek | 本地 Qwen |
| --- | --- | --- |
| Stage 1（离线 15 项） | **passed**（含配置解析） | 同一部署 |
| Stage 2 七项（transport/auth/wire/stream/tools/control/usage-cancel） | **7/7 PASSED** | **7/7 PASSED** |
| Stage 2 汇总 | `outcome=passed`，两模型合计 **14 次真实联网请求** | — |
| Stage 3（advisory） | **passed**，累计 **17 次真实联网请求**；三项 WARNING 为模型 advisory 按设计保留 | — |

含金量：ST2-MODEL-TOOLS 验证了真实 provider 接受**完整生产工具 schema**
的往返；ST2-MODEL-CONTROL 验证了真实 provider 发起 schema 合法的工具调用
载体；ST2-MODEL-USAGE-CANCEL 验证了类型化取消。这些是 9 月 28 日以来
"真实模型旅程因缺 API 配置未执行"缺口的直接收口。`.ask` 通道的联网路径
由上述 purpose=ask 的请求覆盖；交互式聊天/多轮恢复的旅程仍需 TTY，
按 C33 干净机旅程执行。

### A08/A09 离线旅程在 Win64 实机复跑

`gib_log_journey.lua`（600 MiB 档、9600 块）在本机 Win64 NTFS 以当前
源码运行，win64 lua.exe + R74 核心 DLL；结果见 `a08-journey/journey-win64.log`。

### A08/A09 轮转/截断步骤补齐与 Server 2008 全档复跑（10-02 后续）

旅程脚本从 10 步扩到 **15 步**，补齐 TRACKING 剩余的两项：

- **新增 5 步**：`continuation-issued`（首页发续页令牌，next_line=4）、
  `continuation-follows-offset`（续页从第 4 行起免重扫）、
  `continuation-across-truncation`（就地截断后续页必须 `TargetChanged`）、
  `rotation-fresh-read`（rename+重建后全新读看到新文件头）、
  `continuation-across-rotation`（换 inode 后续页必须 `TargetChanged`）。
  断言依据先从 `src/tools.lua` 核实：续页令牌绑定身份摘要
  （kind/volume/object/size/modified），版本变化即拒。
- **脚本宿主平台化**：分隔符与 `platform_kind` 改由 `package.config`
  推导；fixture 尺寸改为累计写入（32 位 CRT 的 `seek("end")` 在 2.4 GiB
  上返回 -1）；CP936 auto 步骤按 `text_codec.facts.file_default` 分叉——
  传统 ANSI 缺省主机（如中文 locale 的 Server 2008）auto 透明解码为
  设计行为，严格 UTF-8 主机拒绝并给 hint。
- **本地 WSL Linux 600 MiB**：15/15、0 失败
  （`a08-journey/journey-linux-rot.log`）。
- **Server 2008 实机 2.34 GiB 全档**（38400 块，D-077 指定环境）：
  **15/15、0 失败**（`a08-journey/journey-server2008-full.log`）。
  `offset-past-2gib` 首次在真实 2 GiB+ 文件上越过边界；
  `cp936-file-default-decodes ... default=cp936` 证实该机 ANSI 缺省页
  的透明回退。配对为已验证的 win32 组合：32 位 lua.exe（subsystem 5.0）
  + win32 核心 DLL（sha1 `b7960ca5...`，与 09-30 候选逐字节一致；原生
  C 层自该构建后未改，R73/R74 均为纯 Lua 修复）+ 当前源码 Lua 树
  （`4117256`）。x64 lua.exe（PE32+ 6.0）在该机装载被拒
  （Exec format error / 拒绝访问），记录为环境事实，按 D-077 以
  win32 发行目标面完成实机证据。
- 校验：注释 **220 文件 / 5276 声明 / 0 缺项**、四校验器 PASS；产品
  源码零改动（完整 suite 699/699 仍绑定 `4117256`）。

外部资源状态更新：DeepSeek 与本地 Qwen 端点已由负责人提供并接入；
win64 full 的 Python 3.8.20 工具链仍是唯一未装配版位。
