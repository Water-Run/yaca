# 离线自动开发交接笔记（2026-08-10）

状态：负责人已答复授权问卷；**自动规格硬化进行中 / 待启动**  
权威授权：[`DECISIONS.md`](DECISIONS.md) **D-070**

## 负责人授权摘要

| 项 | 选择 |
| --- | --- |
| 工作范围 | **仅规格硬化**（`.develope-docs`）；**不** 写产品 `src/*.lua`；**不** 做 modern proof 可执行原型 |
| 主线 | **Wave 3 全线**：Runtime ABI → Path/Index → 数据/秘密 → 改动/压缩 |
| hard-cap | 技术推导 + 用户可配置收紧；不写假精确偏好数字 |
| 路径 | hash/Resolver = `LogicalPath` 规范形；显示可友好，显示≠hash |
| TP 失败改保证 | 停 → 最小 O 决策包；不擅自 WAL/弱 cancel |
| Permission | Std/Readonly **冻结** |
| Git | main；批次 commit；**仅重大里程碑 push**（少数次） |
| 停止 | 自然断点；无固定时限 |
| 技术择优 | 最保守可证明；记录备选 |

## 启动前基线（已完成）

- 产品选择：`unanswered=0` / `conflict=0`
- D-001..D-069；SQ 主队列完成
- W1-A/B/C + W2-A/B/C 首版；TP-003/004/005/006/008/010 计划 specified
- `src/*.lua` 全空；门 A/B 未通过

## 计划产出（Wave 3）

| 包 | 目标文件（拟） | 对应门 |
| --- | --- | --- |
| W3-A | `subsystems/01` / `02` / `03` / `22` 窄 ABI + 事件泵组合 | P0-04、14、15 |
| W3-B | `subsystems/11` LogicalPathCodec + hash vectors + Resolver 结果 | P0-11 |
| W3-C | 数据分类收口 + Key 生命周期表（从 candidate 收口） | P0-08 |
| W3-D | `19` 事务/fault 矩阵 + `12` model-view schema | P0-07、12 |

加深（并行，不挡 Wave 3）：W1/W2 首版向「设计已确认」检查表推进。

## 进度日志

| 时间 | 事件 |
| --- | --- |
| 2026-08-10 ~17:15–17:30 | 负责人完成交接问卷 → D-070 起草 |
| （自动） | 待：归档 commit → 启动 W3-A |

## 回来后请先读

1. 本文件进度日志  
2. `TRACKING.md` 当前阶段  
3. 若有 `O-DECISION-NEEDED-*.md`：TP/保证冲突最小包  
4. `git log` 自 `D-070` 起的设计提交  

## 明确不做

- 产品编码、Permission 改矩阵、Web 实现、无授权 push 风暴、假造目标机「已证明」
