# 负责人答复原话归档：正式决策批次 02

received_at:             `2026-07-22T11:29:28+08:00`
source:                  当前项目会话；负责人先在决策包 02 内直接批注，随后按重新提问的 1..20 编号回复
inventory_version:       `decision-inventory-v9`
structural_sha256:       `22e724986251bd63ae75e1c7964b3a2f6d3412a4e0f9b01019662790d68df6ef`
semantic_sha256:         `80efc73d45ed32e05ea991f35a8cc484700a276f6664c77bc339c7957648b044`
inventory_git_commit:    `ddc95723ebdb0969dcc925ca6a562613aa1f66a9`
packet_worktree_sha256:  `8f05fbda9f52f3d27b92dbef53138a29c9854c7e21ab4f9c7e9a7ccd4d0fe4f4`；负责人批注后的 packet 02 原始文件
raw_verbatim_ids:        `RB-002-01`, `RB-002-02`
explicit_group_ids:      `PJ-01`, `PJ-02`, `PJ-03`, `PJ-04`, `PJ-05`, `PJ-06`, `PJ-08`, `PJ-09`, `PJ-10`, `PJ-11`, `PJ-12`, `PJ-13`, `PJ-14`, `PJ-15`, `PJ-16`, `PJ-17`, `PJ-19`, `PJ-20`, `CX-13`
blanket_scope:           none
expanded_active_ids:     none
inactive_ids:            `PJ-19`，由 `PJ-16=A` 导出；负责人仍明确给出不提供方向
unresolved_condition_ids: none
unanswered_ids:          `PJ-18`
open_followups:          `PJ-12` 的手工名称是否阻止后续周期自动命名
assertion_ids:           `AS-002-01..AS-002-15`

## RB-002-01：负责人在 packet 02 中的原始批注

以下只保存负责人增加的原话；前后候选正文由答复时绑定的 packet hash 证明。语法、错字和标点不改写。

```text
就和主流的一样, 比如codex, 进入就是一个新的. 切换用.context就行
结束对话时, (一个开光)自动命名尝试. 模式包括:
- 仅第一次: 仅NotSave的时候调用LLM(有超时)
- 每次退出(包括覆盖用户的手动命名)
- 不自动命名

不自动命名时, 或者超时, 初始Prompt的固定长度(重名处理)

一样的, 大部分coding agent都是

不需要首页

配置中无Model就是配置不通过, 拒绝启动, 提示配置

创建即Save

不用什么为正常不正常结束的概念 保持简单

输出保持简练美观

开头:

yaca: Yet Another Coding Agent.
[环境信息]
[提示运行.status查看]
输入用 >>
启动展示那些开头信息可在配置TUI中定义 包括yaca: 那个第一行: true/false显示行

不需要这种功能

可以, context锁, 提示context被PID多少占用

用户发送第一个对话开始.
初始化名称 -> 判断是否自动命名, 如果调用LLM命名(超时时长可设置)成功, 覆盖
```

## RB-002-02：负责人对重新编号问题的原始回复

```text
1. 每个字段单独开端. 合适的总选项, 包括Slogan
2. A; context-repl也没问题, 编辑不涉及模型(context本身增删查改)
3. A; 额外一个开关: 自检通过后启动: 启动之前运行一遍自检
4. A
5. A
6. 最合适的自动命名兜底方式. 那就直接"未命名的对话[随机Hash 4位](用英文)"吧. 说到这个, 注意在XP之类的老系统中文编码之类的
7. B
8. B
9. 各个repl, 对应各个自行修复程序(self-fix-program)选单
10. context的work dir是固定的
11. chat页面只能.model切换模型吧?repl都是独立的命令
12. 或者自动命名放在后台, 配置改为多少次对话触发一次自动命名请求? 默认10, 可以不启用功能, 退出就直接退出中断
13. 不用, 统一的Permission模型, 名字只是名字实际行为看配置, 默认有Readonly名称. Permission也有System Prompt等更多可定义内容
14. 完全不提供Web功能. 只要TUI, 保持简单
15. 不支持. 用户要输入叫模型自己读取剪贴板/目录
16. 一样
17. 保持简单 不需要
19. 20. 同

确保程序完整的CLI调用兼容. 比如自检阶段选择排除等; 配置也可以定义自检是否包括第二,第三阶段(阶段是顺序的, 前一个条件满足了才能下一个)
合理设置配置项目
确保程序的简洁, 我发觉你似乎想的过于复杂, 比如Web机制等
```

## 编号解释与原子断言

`RB-002-02` 的数字绑定上一轮重新提问的顺序，而不是把同一字母直接套到 packet 02 的旧 A/B/C。特别是第 4 项结合 `RB-002-01`，含义是“裸启动不扫描旧 Context”，与 packet 02 的 `PJ-04 A` 相反。第 18 项被跳过，因此 `PJ-18` 继续待决。

### AS-002-01：可配置的简洁启动头

- group_id: `PJ-01`
- normalized_assertion: 启动头有总开关，Slogan、版本、work directory、data root、配置状态、Context、实时 hash、Model、Permission、DoubleCheck 与 `.status` 提示分别可显示/隐藏；每个启用字段独占一行并从行首开始。固定 Slogan 为 `yaca: Yet Another Coding Agent.`，输入提示为 `>>`。错误、警告和要求动作不能被显示偏好隐藏。
- kind: experience / constant

### AS-002-02：损坏配置时的 bootstrap 边界

- group_id: `PJ-02`
- normalized_assertion: 正常 Agent 被无效配置阻断；help/version、model-repl、config-repl、self-test Stage 1 和不依赖 Model 的 context-repl 仍可进入。context-repl 的“增加”指 import/restore 已有 XML，不制造与 PJ-05 冲突的空 Context。
- kind: product / safety

### AS-002-03：显式启动前 self-test

- group_id: `PJ-03`
- normalized_assertion: 默认启动不探网；配置可显式要求进入 chat 前运行 self-test 到指定最高阶段。阶段严格按 1→2→3 执行，前一阶段未通过就不运行后一阶段；Stage 2/3 继续取得可见联网/费用同意。拒绝、取消或 required failure 阻止本次 chat。
- kind: product / safety

### AS-002-04：裸启动不扫描历史

- group_id: `PJ-04`
- normalized_assertion: 裸 `yaca [directory]` 永远开始新任务，不扫描 Context Catalog、不提示 recent，也不维护“正常/异常结束”启动分类；旧 Context 只由 `.context`、continue 或 context-repl 等显式动作读取。
- kind: product / experience

### AS-002-05：第一条 main 消息建立 Context

- group_id: `PJ-05`
- normalized_assertion: 第一条 main 用户消息被接受时，先生成初始名称、no-replace 建立 XML并 durable 保存消息及内存会话设置，然后才允许任何 Model 请求；此前空退出不留 XML。
- kind: product / safety

### AS-002-06：ASCII 初始名与周期后台命名

- group_id: `PJ-12`
- normalized_assertion: 初始 basename 为 `Untitled Conversation [XXXX]`，`XXXX` 是四位大写十六进制随机短标签；它不是永久 ID，也不是 16 位实时路径 hash。碰撞时在 no-replace 下重试。`AutoNameEveryMainTurns` 默认 10、0 表示关闭；每 N 个已完成并持久化的 main turn 可发一次低优先级、无工具后台命名请求，失败/取消/退出不阻断 main，也不在退出时等待。
- unresolved: 手工重命名后，周期自动命名是否仍可覆盖。
- kind: product / constant / technical-target

### AS-002-07：显式发现问题、对应 REPL 修复

- group_id: `PJ-06`, `PJ-08`
- normalized_assertion: 不设置 recovery 表面。用户显式打开目标后若发现问题，显示事实、已保存范围和对应 self-fix-program 入口并退出；model/config/context REPL 各自只修自己的领域，self-test 只诊断。
- kind: product / experience

### AS-002-08：活动 writer 完全拒绝打开

- group_id: `CX-13`
- normalized_assertion: 活动 writer 存在时拒绝打开正文；只显示名称、路径、busy 和可证明的 PID。PID 无法证明就显示 unknown，绝不只按锁龄解锁。
- kind: safety / experience

### AS-002-09：Context 的 work directory 固定

- group_id: `PJ-13`
- normalized_assertion: Context 使用其记录的固定 work directory；缺失、不可进入或 identity 不符时失败并进入 context-repl self-fix，不提供 ordinary jump/keep。显式跨机 rebind 成功后，新目录成为新的固定目录并写 durable transition。
- kind: product / safety

### AS-002-10：管理 REPL 只从顶层 CLI 进入

- group_id: `PJ-09`
- normalized_assertion: chat 不打开管理 REPL。`.model` 只切换现有有效 Model；`.context`、`.prompt`、`.cautious`、`.status` 等仍是会话动作，不等同于管理 REPL。
- kind: product / experience

### AS-002-11：直接退出但诚实收口

- group_id: `PJ-10`
- normalized_assertion: 退出不额外确认、不等待后台自动命名；统一 close 立即取消/中断活动与未开始 queue，并在 deadline 内把真实结果保存为 completed/interrupted/unknown，不能把“直接”实现成跳过 XML 收口。
- kind: product / safety

### AS-002-12：没有独立 plan state

- group_id: `PJ-11`
- normalized_assertion: 不提供 PlanArtifact、`.plan` 或 `.execute`；模型可在普通 turn 中陈述计划，仍服从同一 Permission 与工具契约。
- kind: product

### AS-002-13：Permission 名称与 Prompt 不授予能力

- group_id: `PJ-11`
- normalized_assertion: Permission 是命名 typed profile；名称、Description 与 `SystemPrompt` 只影响显示/模型指令，实际行为只由 capability 字段决定。发行模板含 `Readonly`，默认选择仍由既有配置顺序/默认引用决定，不能从名称推导授权。
- kind: safety / product

### AS-002-14：终端-only 零表面

- group_id: `PJ-14`, `PJ-15`, `PJ-16`, `PJ-17`, `PJ-19`, `PJ-20`
- normalized_assertion: v0.1 不提供 Web、图像/clipboard-media/screenshot、音频/麦克风、公共 headless/remote controller、transcription 或 TTS；这些能力在配置、CLI/help、Prompt/Model purpose、工具、XML、Runtime、自检和发行 zip 中都没有空壳。
- kind: product / safety

### AS-002-15：self-test CLI 必须完整且简洁

- group_id: `PJ-03`
- normalized_assertion: self-test 领域 action 支持从 Stage 1 开始运行到指定最高阶段、列出检查、按稳定 check ID/Model selector 做显式 inclusion/exclusion，并以 typed result 区分 pass/partial/fail/cancel；不可排除的核心静态检查不得被语法绕过。最终 argv 拼写仍由 CLI 决策组拥有。
- kind: product / technical-target

## 当前未替负责人决定的两点

1. `PJ-18`：一个 Context 是否恰好只有一个 workspace root。固定 work directory 不能逻辑推出 root 数量。
2. `PJ-12`：用户手工重命名后，周期后台命名停止，还是以后继续覆盖手工名。

除此之外，本批没有因为“保持简单”而暗中删掉错误收口、XML durability、Permission enforcement、旧系统 Unicode 或完整 CLI 这些正确性责任；简化的是产品表面和不必要的模式。
