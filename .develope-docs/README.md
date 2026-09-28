# yaca 开发入口

更新日期：2026-09-28。

当前实现包含 `9724797` 的编码/区间读取修正及其后的分页预算收口，
最近的审查见 [R23--R29](CODE-REVIEW-2026-09-28.md)。
yaca 已有通用 Agent 实现，正在补齐 Review、目标环境验收和
三档发行物；阶段为 `implemented-unqualified`，Release Gate R 关闭。

## 从这里继续

先读当前状态和剩余工作即可接手；需要追溯依据时再按历史索引查阅日期资料。

| 资料 | 用途 |
| --- | --- |
| [编码规范与注释约束](CODING-STANDARD.md) | 修改前必读；文件头、全部函数/类型注释及语义 Review 要求 |
| [当前状态](CURRENT-STATE.md) | 当前已有能力、最新复核结果、证据边界 |
| [剩余工作](TRACKING.md) | 下一项、执行顺序和完成条件 |
| [开发历程与历史资料](DEVELOPMENT-HISTORY.md) | 已完成工作的索引、旧候选和旧决策的适用范围 |
| [实施计划](IMPLEMENTATION-PLAN.md) | C01--C34 的文件、依赖和退出条件 |
| [机读契约](contracts/README.md) | 接口、平台、发行与阶段门的可执行约束 |

## 已确定的方向

yaca 是通用终端 Agent。老设备兼容、单文件便携和开箱即用是产品特性；
U 盘排障是典型场景。延续现有核心，按实际缺陷修补，不以重写架构作为收尾前提。

- `lua` 是正式内置工具，调用 yaca 内嵌的同版本解释器。
- `.ask` 为纯问答；未发布接口直接整理，不增加旧名称别名或迁移层。
- `tools/` 可选。每个平台提供 clean、std、full；full 是开发工具箱。
- 保持 XP SP3 x86、Win7 SP1 x64、CentOS 7 x86_64 的兼容底线。
- 完整代码 Review、注释结构检查和人工语义 Review 都属于验收。

原始要求见 [D-072--D-076](DECISIONS.md#d-072-通用-agent旧设备兼容与可选工具2026-09-22)；
工具候选见 [默认工具清单](../release/TOOL-BUNDLES.md)。

## 记录规则

`CURRENT-STATE.md` 只保留当前快照；`TRACKING.md` 只保留剩余工作。
日期文档记录当时的设计、缺陷和证据，由[历史索引](DEVELOPMENT-HISTORY.md)导航。
旧问卷、旧候选测试和旧 Gate R 结论不能替代当前源码与九个发行包的验收。

修改实现时同步相关契约和测试。构建、完整测试、虚拟机通过
`.tools/run_with_resource_guard.sh` 串行执行。现代开发机通过、目标机通过、
最终发行包通过分别记录；注释覆盖通过也不能写成人工 Review 完成。
