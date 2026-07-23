# 07 Agent 工具系统

状态：候选

## 职责

定义模型可见 raw tools 的规范名称、描述、参数 schema、执行入口和标准结果。候选最小闭环包括 list/read/search、create/write/patch、rename/delete 和一个原始 shell `exec`；是否全部进入 v0.1 仍由工具决策包确认。Git 专用模型 wrapper、网页工具和第三方扩展不因未来可能需要而自动加入。

## 边界

- 工具声明与实际执行绑定，但执行前必须经过 08 号权限系统。
- 文件与进程能力来自 01、02 号子系统。
- 不负责对话循环；09 号系统负责调度。
- 模型只看到原始 shell 字符串工具；yaca 自己启动 curl/helper 使用 Runtime 内部结构化 argv port，不额外暴露第二个 argv 模型工具。

## 设计要求

- 参数验证必须在权限询问之前完成。
- 工具结果需要区分成功、业务失败、拒绝、超时和截断。
- 每个已接受 tool call 必须得到真实或 synthetic result；拒绝、steer 后跳过、前项失败、取消和恢复都不能遗失配对。
- 流式参数只有在完整 provider response 收口并整体通过 schema 后才能接受，不能边生成边执行。
- direct file tools 使用 expected digest/目标身份复核、no-replace/安全替换和文件类型检查；默认拒绝 device/FIFO/socket 等特殊对象。
- raw shell 是有意提供的宽能力，不假装受 direct tools 的 Read/Write/Delete/Network 细分隔离；这一事实由 08 号系统展示和审批。
- 工具输出是有界 canonical result；实时 UI delta、完整结果、截断信息和外部引用必须区分。

## 候选 tool result 共同字段

每个结果至少需要本地 tool call/operation ID、工具版本、规范参数摘要、cwd/目标身份、开始/结束状态、stdout/stderr 或 direct result、退出/错误类别、截断与编码证据、取消结果以及已知/未知副作用。provider 原始 call ID 只是外部证据。

多调用首版候选全部串行。一个调用失败或被 steer/cancel 后，尚未开始的调用生成 `skipped` result；以后若开放只读并行，必须另有资源键与顺序契约。

## 待讨论

首版精确 tool registry、字段拼写、direct write 的安全保证、raw shell 宽权限、输出上限，以及 v0.1 是否明确不承诺通用自动 undo。
