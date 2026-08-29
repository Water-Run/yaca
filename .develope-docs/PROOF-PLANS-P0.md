# 关键技术证明计划（TP-003 / 004 / 005 / 006 / 008 / 010）

更新日期：2026-08-29

状态：TP-003/006/008/010 已取得范围受限、可复现的 **`proven-modern`**；TP-004/005 仍为 `specified`；全部条目均 **尚未** `proven-target`。
细节与失败退路仍以 [TECHNICAL-PROOF-BACKLOG.md](TECHNICAL-PROOF-BACKLOG.md) 为准。

现代机证据、精确命令、输出和目标残项归档在 [`proofs/modern-2026-08-29/`](proofs/modern-2026-08-29/README.md)。统一复现入口为：

    bash .tools/run_coding_readiness.sh

---

## TP-003 统一事件泵

状态：`proven-modern`（确定性 fake-port/core 范围）；Win32/XP、CentOS 真实 wait/console/process/network adapter 与 suspend/resume 仍待 target proof。

### 范围

单线程领域 + port `start/poll/cancel/join/close`；源含 console、curl 管道、工具进程、timer、XML commit、context-name。  
负向：无 Web/media/remote worker。

### 步骤

1. 现代机实现 fake ports + 单测：慢 SSE ∥ 慢 stdout ∥ 输入 cancel ∥ timer。  
2. 事件序 golden 与有界 backpressure。  
3. context-name：marker 门、baseline、退出不 join。  
4. 各源 cancel → 唯一终态 completed|cancelled|failed|unknown。  
5. XP x86 / CentOS 重复最小集（qualification 批）。  
6. 负向扫描无排除 listener。

### 产物

`proof/TP-003/`：ABI 说明、trace、结果表。  
路径：先 `proven-modern` 再 `proven-target`。

---

## TP-006 curl 流式与密钥

状态：`proven-modern`（现代 curl + loopback carrier/cancel/scanner/retry oracle）；随包 curl、旧 TLS/proxy/CA、真实 target timer 与 redirect controller 联调仍待证明。门槛 `8` 与 `tp006-modern-candidate-v1` 只是在现代夹具中通过的候选，尚非发行 manifest 冻结值。

### 范围

Key 不进 argv；carrier bake-off；ambient 隔离；retry；短 secret 门；零 telemetry purpose。

### 步骤

1. 现代机 canary：cmdline/env/temp/stderr 扫 Key。  
2. 选定 stdin/temp 组合。  
3. 恶意 `.curlrc`/环境 → manifest 不变。  
4. 慢 SSE、断流、首 event 后不 retry。  
5. Retry 矩阵（0/max、429、auth 4xx）。  
6. 短 secret 跨 chunk。  
7. XP + CentOS 最小集。  
8. 负向无 upload/update purpose。

### 产物

carrier 决策记录、canary 报告、jitter golden。

---

## TP-008 单 XML 提交正确性

状态：`proven-modern`（Linux/POSIX 完整重写、31 个进程崩溃切点、lock、rename/rebind recovery）；Windows 原语、目标文件系统、断电与 AV/share 行为仍待 target proof。

### 范围

W1-C 流水线；崩溃点；rename/rebind 事务；不重放 unknown。

### 步骤

1. 现代机 stream writer + round-trip。  
2. 故障注入：写 temp / validate / replace / 清理。  
3. 对照 W1-C 崩溃表断言。  
4. rename+marker、rebind 全成全败。  
5. intent 无 result → 打开 unknown。  
6. 目标机重复。  
7. 永久删枚举正式/tmp/prev。

### 产物

崩溃矩阵记录、恢复样例树。

---

---

## TP-004 Windows XP console / QuickEdit

状态：`specified`；尚未 proven-modern/target。

### 范围

Enter / Ctrl+Enter / Shift+Enter / Alt+Enter / Esc 识别或诚实能力报告；点命令后备；QuickEdit 不永久挂死；退出后模式恢复。

### 步骤

1. 能力矩阵表：raw vs cooked vs 重定向。  
2. 逐键 trace fixture（现代 conhost 先跑）。  
3. 无法区分的组合键 → 只宣传点命令，不误映射。  
4. QuickEdit 选中阻塞：诊断可见 + 不丢 draft 策略。  
5. 异常退出后 code page/cursor 恢复 best-effort。  
6. 真实 XP SP3 重复最小集。

### 产物

`proof/TP-004/` 键矩阵与 transcript。失败时仅降快捷键、不删 semantic action。

---

## TP-005 子进程树、取消与 unknown

状态：`specified`；尚未 proven-modern/target。

### 范围

`cmd.exe /d /s /c` 与 `/bin/sh -c`；stdin 不喂 TUI；双管道；取消/超时；descendant unknown；命令长度/编码硬错。

### 步骤

1. 直接子进程 + 孙进程夹具。  
2. 子进程读 stdin → 稳定 EOF / non-interactive result。  
3. cancel 竞态：kill 后未证明停止 → unknown。  
4. 超长/不可编码 command → typed error，不拆脚本偷换。  
5. 输出 cap head+tail 确定性。  
6. 负向：无 media/codec helper 路由。  
7. XP + CentOS 最小集。

### 产物

process result schema 样例 + unknown 恢复说明。

---

## TP-010 XML parser/writer + Lua 5.5

状态：`proven-modern`（Linux x86_64 固定源码 hash 构建与安全/Unicode/carrier corpus）；Win32 x86、Win64 和 CentOS 7 仍待 build/load/limit target proof。

### 范围

流式安全子集；禁 DTD/entity；Lua 5.5 ABI 三目标；scalar text|base64 round-trip；与 W1-C 事件兼容。

### 步骤

1. 选定绑定（领先候选 LuaExpat+Expat）现代机 smoke → 已部分有。  
2. 恶意 entity/炸弹 corpus 硬拒绝。  
3. writer 转义确定性 + parse round-trip。  
4. UTF-8 / base64 / 控制字符矩阵。  
5. Win32 x86 / Win64 / Linux 原生构建加载。  
6. 与 W1-C temp publish 联调（接 TP-008）。

### 产物

绑定版本 hash、corpus 报告、三架构加载日志。

---

## 建议并行序

```text
TP-008 writer || TP-003 fake pump || TP-010 parser corpus
        \            |              /
         \       TP-006 carrier
          \          |
           TP-004 console (可后于 pump ABI)
           TP-005 process (可后于 pump)
                    |
          目标机 qualification 批
```

其余 TP（001/002/007/009/…）在下一 owner 批之后或发布轨再 `specified`；见 TRACKING 交接。
