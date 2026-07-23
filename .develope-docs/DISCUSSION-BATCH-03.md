# 负责人答复原话归档：正式决策批次 03

received_at:             `2026-07-22T13:47:39+08:00`
source:                  当前项目会话；负责人补答 `PJ-18` 与 `PJ-12` 手工名称优先级，并随后确认标记存储位置
inventory_version:       `decision-inventory-v9`
structural_sha256:       `22e724986251bd63ae75e1c7964b3a2f6d3412a4e0f9b01019662790d68df6ef`
semantic_sha256:         `80efc73d45ed32e05ea991f35a8cc484700a276f6664c77bc339c7957648b044`
inventory_git_commit:    `233f5f613dd6afd1167243dfae1de4ea691c96d9`
packet_worktree_sha256:  `afb055438142fd9e3ce2d4864feac34f8ac89f3944483f5f0aaa93926721b295`；答复时 packet 02 原始文件
raw_verbatim_ids:        `RB-003-01`, `RB-003-02`
explicit_group_ids:      `PJ-18`, `PJ-12`
blanket_scope:           none
expanded_active_ids:     none
inactive_ids:            none
unresolved_condition_ids: none
unanswered_ids:          none
open_followups:          none
assertion_ids:           `AS-003-01..AS-003-02`

## RB-003-01：负责人补答两个窄问题

```text
1. 是的. 实际上不体现在context文件中, 而是在__yaca__的CONTEXT下, yaca程序读取时
2. 可配置吧, 默认是--"不自动重命名"标记. context-repl可以添加/取消此标记.
我正在阅读你提供的文档
```

## RB-003-02：负责人确认标记存入 Context XML metadata

负责人收到的确认问题是：`AutoRenameDisabled` 是否存入 Context XML metadata。

```text
是的
```

## 原子断言

### AS-003-01：一个 Context 只有一个由镜像位置决定的 workspace root

- group_id: `PJ-18`；同时细化 `PJ-13` 的固定 work directory 表达
- normalized_assertion: v0.1 每个 Context 恰好绑定一个 workspace root。当前绑定不保存为 Context XML 内的 `current workdir` 字段；yaca 打开 Context 时，从该 XML 位于 `__yaca__/CONTEXT/` 下的规范镜像父目录解码唯一 root。显式 rebind 是把 XML 安全发布到新 root 对应的镜像目录，成功后逻辑路径和实时 16 位 hash 随位置变化，旧 hash 失效。初始唯一 root 怎样由 invocation directory/Git root 产生仍由 `F4-14` 决定。
- kind: product / storage-address / safety

### AS-003-02：手工名称默认停止周期自动重命名

- group_id: `PJ-12` 补缝
- normalized_assertion: Context XML metadata 保存布尔 `AutoRenameDisabled`。用户手工 rename 成功时，名称移动与把该标记置为 `true` 属于同一管理事务；context-repl 可以显式添加或取消该标记。取消标记只允许以后继续按全局 `AutoNameEveryMainTurns` 的正常间隔调度，不立即触发命名请求，也不改变全局间隔。自动命名自身成功改名不把该标记置为 `true`。
- kind: product / configuration / context-metadata

## 本批收口结果

- `PJ-18` 选择正式路线 A；不生成附加 root、root alias 或 root list。
- `PJ-12` 的手工名称优先级补缝已关闭；全局命名间隔与每 Context 禁用标记彼此独立。
- 本批没有回答 `F4-14` 的初始 root 发现，也没有冻结镜像路径的 Windows drive、UNC、Linux root 或链接编码。
