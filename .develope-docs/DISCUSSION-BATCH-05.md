# 负责人答复原话归档：正式决策批次 05

received_at: `2026-07-22`

source: 当前项目会话

status: 收到一项证据口径修订与一项决策流程修订；尚未收到集中问题选择

## 原话

```text
luainstaller可能支持x86,只是每测试.
还有问题是吗?整理到更明确的询问,梳理为有意义的问题(248太多),我一并回答
```

## AS-005-01：不能把未验证写成底层不支持

- 当前检出的 luainstaller 1.0 的公开 profile guard 实际会拒绝 Windows x86，随附 MSVC recipe 和测试矩阵也只覆盖 x86_64。
- 这些事实只证明当前默认路径尚不能交付 yaca 的 x86/XP 包；它们不证明 launcher/bundler 的底层设计无法支持 x86，也不构成 XP 不兼容证据。
- Windows release 在取得 x86 产物、PE/CRT/API 审计与 XP 至 11 目标机证据前保持 `evidence-blocked`。正确顺序是先 qualification，按证据判断无需修改或只做必要的 guard/toolchain/profile 适配。

本断言修正 CURRENT-STATE/readiness/packaging 文档中的能力定性，但不伪造“x86 已支持”或“XP 已测试”。

## AS-005-02：原子登记表不再直接充当负责人问卷

- 248 个 `unanswered` 继续保留为完整性、追踪和冲突审计，不再代表负责人需要逐条回答 248 次。
- 负责人入口改为 `OWNER-QUESTIONS-01.md` 的集中产品问题；库、内部结构、错误码、常量和性能数值由规格与目标机技术证明选择。
- 集中回复必须先投影和冲突检查，再写入原子 register；不能用“全部最佳实现”暗中选择没有被集中问题覆盖的产品能力。
