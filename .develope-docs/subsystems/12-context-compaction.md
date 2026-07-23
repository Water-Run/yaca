# 12 上下文压缩

状态：候选

## 职责

在上下文接近模型窗口时生成可验证的摘要，保留关键目标、决定、文件状态、未完成工作和最近消息，并支持手动压缩。

## 边界

- token 预算来自模型配置与估算器。
- 摘要生成通过 06、09 号系统，不直接发送 HTTP。
- 原始上下文的保留、归档与替换由 10 号系统完成。
- D-022 要求活动 XML 保存完整对话，因此压缩只能改变发送给模型的运行视图，不能把被摘要覆盖的原对话从 XML 中静默删除。

## 设计要求

- 无官方 tokenizer 时必须承认估算误差并保留安全余量。
- 安全余量由 Runtime 按当前有效 Model、最大输出、Prompt、tool schema、不可拆原子组和估算误差实时计算；它是只读 effective value，不生成 `CompactReserveTokens` INI/XML 字段。request/view manifest 可以保存本次派生值、输入摘要与算法版本作为证据。
- 压缩失败不能破坏原始上下文。
- 工具调用与工具结果不可被拆成无效半对。
- 摘要需要标明来源范围与压缩代次，避免递归失真不可追踪。
- 已有摘要只有在来源事件范围完整、版本兼容且校验有效时才能复用，否则必须从事实历史重建。

## 当前领先算法

下一次 Model view 由以下四层确定性组合，而不是删除 XML 历史：

```text
不可压缩的有效 Prompt + tool schema
+ 最新有效 prefix summary（若需要）
+ 从新到旧选择的完整事件原子组
+ 当前状态、unknown side effects 与未完成事项
```

不可拆原子组至少包括 tool call/result、operation/approval/result、用户输入/直接回复、当前 active turn。Model/Prompt/Permission/DoubleCheck 切换必须以明确控制事实进入新 Model 的 view，不能让模型只看到“现在换了”却不知道原来使用什么。

结构化摘要候选必填：目标、用户决定、限制、工作区/文件变化、验证证据、失败尝试、未知副作用、待办、Model/Prompt 切换。摘要还记录 source event range/digest、生成 Model、Prompt 版本和代次；用户纠正产生 superseding event，不改写旧摘要。

当历史曾使用且仍配置的较大窗口 Model 足够时，先提示切回；其次列其他已启用大窗口 Model，并在跨 endpoint 前做隐私/费用/工具能力预检。切回大窗口后可从完整历史重建更丰富原文 view，旧摘要事实仍保留但不必继续发送。

压缩 request 是独立 purpose，无工具权限和独立预算。当前 Model 无法容纳压缩输入、摘要 schema 无效、仍超限或连续无收益时，保持旧 view 并停止自动循环；不能递归计费直到成功。

## 待讨论

token 估算与安全余量、压缩边界算法、summary schema 字段、当前/专用 Model、无收益上限、用户纠正和切回大窗口后的 view 恢复。当前推荐“一个 prefix summary + 最近完整事件组”，不先实现复杂分层摘要树。
