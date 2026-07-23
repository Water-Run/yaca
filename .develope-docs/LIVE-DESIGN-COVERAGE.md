# 实时设计覆盖审计

更新日期：2026-07-22

状态：当前 `decision-inventory-v9` 快照已随本批机械验证；正式组 `270` 个，checklist 标题 `384` 个，配置校验 `CV-001..CV-076`，原子问题为连续且唯一的 `AQ-001..AQ-437`；checklist/AQ orphan 均为 `0`

## 本文件只回答什么

本文件只回答“每个设计编号由哪条现行路线关闭”。它不是第二份决定表，也不把“已有 owner”误写成“已经回答”。

- 正式组的答复状态只由 [`DECISION-REGISTER.md`](DECISION-REGISTER.md) 维护。
- 已确认事实只由 [`DECISIONS.md`](DECISIONS.md) 维护。
- 技术证明状态只由 [`TECHNICAL-PROOF-BACKLOG.md`](TECHNICAL-PROOF-BACKLOG.md) 维护。
- readiness 只由 [`ARCHITECTURE-READINESS.md`](ARCHITECTURE-READINESS.md) 维护；readiness 的 `主要来源` 是实施依赖投影，不是负责人 owner。
- 本文件只保存可重算的 route projection、窄例外及其来源锚点。

所以 orphan 为零只表示没有“无人负责的题”。270 组的负责人输入现已收口，但这仍不表示 owner 规格、技术证明已经通过或实现可以开始。

## 本轮修正了什么

旧版审计有四个会制造假绿灯的错误：

1. checklist 先经过 `dict/set` 去重，再断言数量；源文件即使重复一项也可能被静默吞掉。
2. 正式组只看全局同名标题或在整段正文搜索 ID；跨包的投影标题、依赖说明和一句“仍负责”都可能被误认成 owner。
3. `DECISIONS.md`、readiness 和非投票段的整段正文被扫描；例如 D-035 提到一批“仍待决定”的 AQ，旧算法却把它们算成已确认。
4. 旧例外用相邻主题代替真实 owner，例如曾让 `PJ-11` 假装覆盖 Web；这不能证明 Web、图像、音频输入、standalone transcription、TTS、remote 或 multi-root 已有负责人。

本版改为先验证原始输入，再从精确来源行构建路线：

- checklist 只从真实标题行 `^- **ID ...` 提取；先断言 raw count，再断言 unique count。
- AQ 只从 `#### AQ-NNN` 标题提取；raw 序列必须精确等于 `001..437`。
- 配置校验只从 `CONFIG-SCHEMA-CANDIDATE.md` 的 `CV-NNN` 表格首列提取；raw 序列必须精确等于 `001..075`。
- 正式组的唯一成员事实来自各 owner packet 底部裸行 `GROUP A|B|C`；原始出现次数与唯一组数都必须是 `270`，并匹配下表的精确列表和逐包分布。
- 同一个正式组还必须在**同一 owner packet** 恰有一个正式 H2/H3 section，并与 register、queue 的集合完全相同。别包中类似 `PJ-11 ... 投影（不是本包新投票）` 的标题不会被误收。
- register 不只核对成员：脚本会独立重建每组 title、推荐字母、`active_when`、结构摘要、完整语义摘要与逐组 `Sem`，再与 `decision-inventory-v9` manifest 比较。
- queue 必须精确为 `B01..B49`；每批 3--6 组，270 组各出现一次。
- checklist/AQ 的正式 owner 默认只从该正式 section 内、以 `关联：` 开头的独立物理行解析；正文中任何其他 ID 都不参与 owner 计算。下表另锁定 v8 的五条间接 cross-index 和 v9 六个新 owner 的 checklist/AQ/formal 三向一致性；它们不是主题模糊匹配。
- `X-01 至 X-03`、`X-01--X-03` 和 queue 使用的 `X-01..X-03` 都按闭区间展开。
- `D-*` 不做正文自动命中；只有下面窄账本列出的真正已确认项才能走 `confirmed`。
- `TP-*` 与明确写着“不是负责人投票/技术证明/无需回复”的固定 gate，只解析其显式关联行。没有显式关联的少量实现不变量必须进入人工审阅过、带来源锚点的窄技术账本。
- `ARCHITECTURE-READINESS.md` 不参与 owner 分类。

## 当前正式清单与最后一次反向闭环

现行清单不是按总数“凑齐”，而是从 checklist、AQ、配置 schema、跨系统接缝和失败路径反向追到唯一负责人。精确列表如下；缺号是已经确认的非投票 gate，不得补成伪问题。

| 包 | 数量 | 精确正式组列表 |
| --- | ---: | --- |
| PJ | 19 | `PJ-01..PJ-06`, `PJ-08..PJ-20` |
| PP | 18 | `PP-01..PP-09`, `PP-11..PP-19` |
| TU | 32 | `TU-01..TU-08`, `TU-10..TU-11`, `TU-13..TU-34` |
| M05 | 57 | `M05-01..M05-09`, `M05-11..M05-23`, `M05-25..M05-59` |
| AL06 | 49 | `AL06-01..AL06-02`, `AL06-04..AL06-20`, `AL06-22..AL06-51` |
| TS | 35 | `TS-02`, `TS-04..TS-05`, `TS-07..TS-08`, `TS-10..TS-14`, `TS-16..TS-40` |
| CX | 16 | `CX-01..CX-02`, `CX-05`, `CX-07..CX-11`, `CX-13..CX-20` |
| ED | 14 | `ED-01..ED-14` |
| RF | 14 | `RF-01..RF-06`, `RF-08..RF-12`, `RF-14..RF-16` |
| F4 | 16 | `F4-01..F4-12`, `F4-14..F4-17` |

`decision-inventory-v9` 在 v8 的 264 组基础上又拆出六个不能由相邻主题代答的 owner：

| 新组 | 独占的负责人轴 | 原子问题 |
| --- | --- | --- |
| `M05-57` | Model/Permission 是否存在 `Abbreviation`；不再由候选表格暗定 | `AQ-432` / `CFG-27` |
| `M05-58` | per-Model retry 暴露数字字段还是 typed preset | `AQ-433` / `CFG-28` |
| `AL06-50` | stuck/no-progress 阈值由 manifest、单值还是 detector map 提供 | `AQ-434` / `LOOP-31` |
| `AL06-51` | 特殊 purpose 跨 Endpoint 同意是逐次、进程内还是 Context durable | `AQ-435` / `MODEL-17` |
| `TS-40` | `__yaca__` reserved tree 的 exact direct-read 是否有窄出口 | `AQ-436` / `SAFE-18` |
| `M05-59` | 过短 config-secret 的 consumer 与 exact-scan 保证 | `AQ-437` / `CFG-29` |

因此当前机械不变量是 `270 / 384 / 437 / 75 / 49`。删除任一组或用相邻 owner 兜底都会让集合、route 或语义摘要失败；不能靠增加例外把 orphan 涂绿。

十个 owner packet 的 raw-source guard 为 `9345b940ae2c45ac5f84f81d0badf809996d6db63929760298b958c6604b411b`（829237 bytes）。它按 basename `02..11` 升序串联，每条精确为 `<filename UTF-8><NUL><raw file bytes><NUL>`，末条也保留终止 NUL；不包含 packet README，不做换行、空白或 Unicode 规范化。这个 guard 只证明两次验证读取了同一批原始输入，结构/语义含义仍由下面独立重建的 manifest 负责。

## 当前覆盖结果

每个 ID 只取一个主类别，优先级为 `formal → excluded → confirmed → technical → ORPHAN`。同一 ID 的多个直接正式 owner 会全部保留在 route 中。

| 输入集合 | `formal` | `confirmed` | `technical` | `excluded` | orphan | 合计 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| checklist | 331 | 5 | 42 | 6 | 0 | 384 |
| AQ | 413 | 2 | 21 | 1 | 0 | 437 |

canonical route projection 的 SHA-256 为：

- checklist：`3a819b54d295f9982b4b6fd0ef80e34a52a834691a6b1ee0e4a5e7ec2c1f8060`
- AQ：`b3a5656aa551642d9bb52894d7e6e5a864b49bf8c2ba5886d2e4f580ea218d48`

digest 只用于发现 route projection 是否变化，不是决策签名。owner、关联行、固定 gate 或输入清单变化后，digest 理应变化并重新审阅。

## 容易再次被错误合并的正式 owner

下面这些能力现在都有显式正式 owner，不能再退回旧的兜底映射：

| 能力 | 正式 owner | 边界 |
| --- | --- | --- |
| Web | `PJ-14` | 是否进入 v0.1；不是 `PJ-11` 的 plan state |
| 图像输入 | `PJ-15` | 图像内容类型与模型资格 |
| chat 语音/音频输入 | `PJ-16` | 主会话输入能力 |
| standalone transcription | `PJ-19` | 独立转写动作 |
| TTS/speech output | `PJ-20` | 输出播报能力 |
| remote/headless | `PJ-17` | 远程控制面与信任边界 |
| multi-root | `PJ-18` | 一个 Context 的 workspace root 拓扑 |
| model-yield 后继续 | `AL06-48` | 完整 response 的对象化 continuation；不由 ask-user 或 queue 顺带定义 |
| raw shell inherit baseline | `M05-55` | 仅在 M05-15 A/B active；不拥有 set/unset 配置面 |
| `exec` cwd / decode / retention | `TS-37` / `TS-38` / `TS-39` | 三条互不替代的进程调用轴 |
| composer recall | `TU-31` | 与 canonical `.history`、draft 持久化和外部终端历史分离 |
| chat command roots / prompt / approval grammar | `TU-32` / `TU-33` / `TU-34` | command namespace、输入目标和审批动作是三个正交体验轴 |
| independent SensitiveRead | `M05-56` | 是否生成独立 capability；TS-21 只在 B 路线 active |
| termination-review Model | `AL06-49` | 与 action-review 的 Model 和开关分离 |
| resource selector / retry / short secret | `M05-57` / `M05-58` / `M05-59` | 三个完整配置面分别拥有存在性、字段形态与正文扫描保证 |
| no-progress threshold source | `AL06-50` | detector 算法是技术证明；用户可调粒度由本组决定 |
| special-purpose endpoint consent | `AL06-51` | action/termination/compaction purpose 分离并各自失效 |
| reserved-tree exact read | `TS-40` | list/search 与 mutation 固定拒绝；只投票 direct exact-read 窄出口 |
| telemetry policy | `ED-13` | 长期/自动遥测政策 |
| one-shot diagnostic upload | `ED-14` | 用户单次显式上传；仅在 ED-07 A/B 生成 standalone diagnostic XML 时适用 |
| update discovery/download | `RF-16` | 发现与下载；安装、迁移、回滚仍由 `RF-03` 独占 |
| raw/direct tool schema | `TS-23` | input carrier/schema；shell dialect 仍由 `TS-13` 独占 |

`PROD-11` 可以被多个能力组共同关联，因为它是总体产品范围检查项；这不允许任一相邻组取代上表的独立产品轴。

## 条件组完整投影

除下表外，其余 `248` 组全部为 `always`。这里复制的是可机械比较的 route projection；条件语义和答复状态仍由 register 唯一维护。

| 条件组 | 精确 `active_when` |
| --- | --- |
| `PJ-19` | `choice(PJ-16) in [B,C]` |
| `TU-30` | `choice(TU-27) in [B,C]` |
| `ED-14` | `choice(ED-07) in [A,B]` |
| `M05-26` | `choice(M05-03) in [A,C]` |
| `M05-55` | `choice(M05-15) in [A,B]` |
| `AL06-08`, `AL06-24`, `AL06-25` | `choice(AL06-07) in [A,B]` |
| `AL06-30`, `AL06-31`, `AL06-34` | `choice(AL06-11) == A` |
| `AL06-39`, `AL06-47` | `choice(AL06-11) in [A,B]` |
| `AL06-43` | `choice(M05-50) == C` |
| `TS-21` | `choice(M05-56) == B` |
| `TS-25`, `TS-26`, `TS-34`, `TS-35` | `choice(TS-02) in [A,C]` |
| `TS-28`, `TS-29`, `TS-31` | `choice(TS-02) == A` |

脚本把上表展开为 22 个精确 group-to-condition 映射，并断言 register 没有遗漏、额外条件或自然语言变体。条件为假时的 `not-applicable`/no-projection 事务不由本文件重新定义。

### v8/v9 新增 owner cross-index

| checklist ID | 精确 AQ | 正式 owner |
| --- | --- | --- |
| `CLI-19` | `AQ-427` | `TU-32` |
| `TUI-30` | `AQ-428` | `TU-33` |
| `TUI-31` | `AQ-429` | `TU-34` |
| `CFG-26` | `AQ-430` | `M05-56` |
| `LOOP-30` | `AQ-431` | `AL06-49` |
| `CFG-27` | `AQ-432` | `M05-57` |
| `CFG-28` | `AQ-433` | `M05-58` |
| `LOOP-31` | `AQ-434` | `AL06-50` |
| `MODEL-17` | `AQ-435` | `AL06-51` |
| `SAFE-18` | `AQ-436` | `TS-40` |
| `CFG-29` | `AQ-437` | `M05-59` |

前五条是显式两跳 cross-index：`checklist ID -> AQ -> formal group`；后六条还要求 owner section 的独立 `关联：` 行同时直连 checklist 与 AQ。validator 要求 checklist 物理行唯一存在、AQ section 唯一存在且明确登记表内 owner，并按两类路由拒绝重复、缺失或归属不一致；它不会根据标题相似度猜 owner。

## 窄例外账本

“例外”只表示现行源没有正式 owner 的 `关联：`，但已有真实归档决定或不可投票的固定技术 gate。它不能用于“主题看起来相近”。脚本还会断言这里的每个 ID 没有直接 formal/TP/gate route；一旦上游补了直接关联，就必须删除对应例外。

### 真正已确认的 D 路线

| ID | 路线 | 证据边界 |
| --- | --- | --- |
| `PROD-09` | `D-029` | 独立本地化项已被 English/ASCII chrome + Unicode 用户数据边界取代。 |
| `ARCH-03` | `D-013,D-014` | 唯一 composition root、字面量后端选择与窄依赖注入已经确认；生命周期细节仍未被假装回答。 |
| `CFG-16` | `D-027` | 独立 `UseTerminationEvaluator` 已并入 `DoubleCheck`；剩余迁移诊断仍走规格。 |
| `SAFE-17` | `D-034` | v0.1 明确不承诺统一 OS sandbox。 |
| `INDEX-13` | `D-030` | `name:/hash:/path:` 前缀已明确排除。 |
| `AQ-016` | `D-028` | Model 是完整连接实例、明文 Key 与不静默 fallback 的负责人选择已归档。 |
| `AQ-157` | `D-029` | 多语言/多显示模式删除方向已归档。 |

没有其他 AQ 因为“在某个 D 正文中出现过”而进入 confirmed。尤其 `AQ-034` 由 `TS-23` 正式询问；D-034 明确说 schema 仍待决定。

### 固定技术 gate 路线

| ID 或集合 | 固定 gate | 为什么不是新的负责人偏好 |
| --- | --- | --- |
| `ARCH-04` | `RuntimeDomainRegistry` | 只有应用核心产生领域转换，adapter/durable/UI event 的映射是状态机不变量。 |
| `RUNTIME-03` | `LuaModuleLifecycle` | `require` 路径、顶层零 I/O、协程与 close 纪律是可测试模块契约。 |
| `RUNTIME-04` | `TP-029-AmbientLoad` | CWD/PATH/module/DLL 注入必须由恶意 fixture 证明拒绝。 |
| `PLAT-01` | `TP-012-PathCodec` | 规范路径、Unicode 与 logical hash 是跨平台 codec 证明。 |
| `PLAT-03` | `PlatformEnvironmentText` | HOME/环境/locale/codepage 读取属于窄平台 port。 |
| `PLAT-06` | `PlatformClockTemp` | wall/monotonic clock、随机临时名与碰撞降级属于平台 contract。 |
| `PLAT-07` | `PlatformAdapterLayout` | 已确认依赖方向下的后端文件布局是实现规格。 |
| `PLAT-08` | `PlatformIdentityGuard` | 错 OS/arch 必须由启动 guard 确定拒绝。 |
| `PLAT-12` | `TP-023,TP-024-OldTerminal` | 旧终端、无 TTY、错误 TERM/locale 是兼容证据矩阵。 |
| `PROC-01` | `ProcessPortABI` | 可轮询、取消、join、close 的进程 port 由目标平台原型决定。 |
| `PROC-08` | `TP-029-BundledToolSearch` | 随包工具的唯一搜索来源是供应链/启动证据；`PROC-09` 现在有 `TS-24/TS-30` 的直接 formal route。 |
| `FMT-05` | `TP-008-CommitRecord` | 完整 canonical event/footer、崩溃点与恢复是提交协议正确性。 |
| `FMT-07` | `TP-010,TP-019-DeterministicWriter` | XML/INI writer 的确定性转义、round-trip 与 fixture 是格式证明。 |
| `CFG-18` | `TypedSchemaSource` | 默认、类型、约束、help、模板与 REPL 必须由同一 typed schema 投影。 |
| `TOOL-16` | `ToolRegistryVersion` | 名称、输入/结果 schema 与 capability metadata 的版本是 registry ABI。 |
| `AQ-171` | `ContextIdentityDigest` | ContextIdentity 固定局部 seq/full digest/previous digest，并明确不冒充签名。 |
| `AQ-270` | `TP-003,TP-005-Clock` | 问题自身标为技术规格：持久时间用 wall clock，deadline 用 monotonic clock。 |
| `AQ-323` | `TP-015,TP-021-SafeJSON` | 问题自身标为安全硬不变量：重复 key、深度、大小、UTF-8 与数值必须严格验证。 |

除此之外的 technical route 都来自 TP 或明确非投票 gate 的显式关联行。`AQ-336/AQ-337` 例如由 REPL 导航技术 gate 与 TP-024/TP-026 收口，不靠 readiness 模糊兜底。

### 明确排除与重入

原 `F4-13` 的标题明确为“扩展运行时关闭与未来重入门”，且有显式关联行。它自动关闭 `PROD-04`、`TOOL-14`、`LOOP-21`、`EXT-01..03` 与 `AQ-373`；未来重开必须建立新的正式 owner/威胁模型，不能把今天的关闭门解释成已设计实现。

Web、图像、音频输入、standalone transcription、TTS、remote、multi-root、aggregate telemetry、one-shot diagnostic upload 和 update discovery/download 已有正式 owner，所以不在 exclusion/exception ledger 中。

## 可直接执行的只读审计

从仓库根目录执行。脚本只读 `.develope-docs`，会独立重建 packet raw-source guard 与 manifest、检查全部相对链接、输出每条 canonical route，最后输出 inventory、结构/语义摘要、分类计数与 route digest；任何 raw 重复、缺号、组列表/标题/推荐/条件/摘要漂移、queue 批次越界、宽松例外或 orphan 都会非零退出。

```bash
python3 - <<'PY'
from pathlib import Path
from urllib.parse import unquote
import collections
import hashlib
import re

root = Path('.develope-docs')
packet_dir = root / 'decision-packets'

EXPECTED_INVENTORY_VERSION = 'decision-inventory-v9'
EXPECTED_FORMAL = 270
EXPECTED_CHECKLIST = 384
EXPECTED_AQ = 437
EXPECTED_CV = 76
EXPECTED_BATCHES = 49
EXPECTED_PACKET_SOURCE_SHA256 = '13b0a7cbad9556db50bbd81bdee76554900d252deb79b3ab68bd41e5f59c49f6'
EXPECTED_STRUCTURAL_SHA256 = '22e724986251bd63ae75e1c7964b3a2f6d3412a4e0f9b01019662790d68df6ef'
EXPECTED_STRUCTURAL_BYTES = 13575
EXPECTED_SEMANTIC_SHA256 = '80efc73d45ed32e05ea991f35a8cc484700a276f6664c77bc339c7957648b044'
EXPECTED_SEMANTIC_BYTES = 471107

GROUP_PATTERN = r'(?:PJ|PP|TU|M05|AL06|TS|CX|ED|RF|F4)-\d+'
ITEM_PATTERN = r'[A-Z][A-Z0-9]*-\d+'

EXPECTED_NUMBERED_GATES = {
    'PJ-07', 'M05-10', 'M05-24', 'RF-07', 'RF-13',
    'TS-01', 'TS-03', 'TS-06', 'TS-09', 'TS-15',
    'AL06-03', 'AL06-21',
    'CX-03', 'CX-04', 'CX-06', 'CX-12',
}
EXPECTED_SPECIAL_GATES = {'PP-10', 'TU-09', 'TU-12', 'F4-13'}

EXPECTED_GROUP_LISTS = {
    'PJ': 'PJ-01..PJ-06, PJ-08..PJ-20',
    'PP': 'PP-01..PP-09, PP-11..PP-19',
    'TU': 'TU-01..TU-08, TU-10..TU-11, TU-13..TU-34',
    'M05': 'M05-01..M05-09, M05-11..M05-23, M05-25..M05-59',
    'AL06': 'AL06-01..AL06-02, AL06-04..AL06-20, AL06-22..AL06-51',
    'TS': 'TS-02, TS-04..TS-05, TS-07..TS-08, TS-10..TS-14, TS-16..TS-40',
    'CX': 'CX-01..CX-02, CX-05, CX-07..CX-11, CX-13..CX-20',
    'ED': 'ED-01..ED-14',
    'RF': 'RF-01..RF-06, RF-08..RF-12, RF-14..RF-16',
    'F4': 'F4-01..F4-12, F4-14..F4-17',
}
EXPECTED_DISTRIBUTION = {
    'PJ': 19, 'PP': 18, 'TU': 32, 'M05': 57, 'AL06': 49,
    'TS': 35, 'CX': 16, 'ED': 14, 'RF': 14, 'F4': 16,
}
EXPECTED_ACTIVE = {
    'PJ-19': 'choice(PJ-16) in [B,C]',
    'TU-30': 'choice(TU-27) in [B,C]',
    'ED-14': 'choice(ED-07) in [A,B]',
    'M05-26': 'choice(M05-03) in [A,C]',
    'M05-55': 'choice(M05-15) in [A,B]',
    'AL06-08': 'choice(AL06-07) in [A,B]',
    'AL06-24': 'choice(AL06-07) in [A,B]',
    'AL06-25': 'choice(AL06-07) in [A,B]',
    'AL06-30': 'choice(AL06-11) == A',
    'AL06-31': 'choice(AL06-11) == A',
    'AL06-34': 'choice(AL06-11) == A',
    'AL06-39': 'choice(AL06-11) in [A,B]',
    'AL06-47': 'choice(AL06-11) in [A,B]',
    'AL06-43': 'choice(M05-50) == C',
    'TS-21': 'choice(M05-56) == B',
    'TS-25': 'choice(TS-02) in [A,C]',
    'TS-26': 'choice(TS-02) in [A,C]',
    'TS-34': 'choice(TS-02) in [A,C]',
    'TS-35': 'choice(TS-02) in [A,C]',
    'TS-28': 'choice(TS-02) == A',
    'TS-29': 'choice(TS-02) == A',
    'TS-31': 'choice(TS-02) == A',
}
FORMAL_CHECKLIST_PROJECTION = {
    'CLI-19': ('AQ-427', 'TU-32'),
    'TUI-30': ('AQ-428', 'TU-33'),
    'TUI-31': ('AQ-429', 'TU-34'),
    'CFG-26': ('AQ-430', 'M05-56'),
    'LOOP-30': ('AQ-431', 'AL06-49'),
}
DIRECT_FORMAL_CHECKLIST_PROJECTION = {
    'CFG-27': ('AQ-432', 'M05-57'),
    'CFG-28': ('AQ-433', 'M05-58'),
    'LOOP-31': ('AQ-434', 'AL06-50'),
    'MODEL-17': ('AQ-435', 'AL06-51'),
    'SAFE-18': ('AQ-436', 'TS-40'),
    'CFG-29': ('AQ-437', 'M05-59'),
}

EXPECTED_COUNTS = {
    'checklist': {'formal': 331, 'confirmed': 5, 'technical': 42, 'excluded': 6},
    'aq': {'formal': 413, 'confirmed': 2, 'technical': 21, 'excluded': 1},
}
EXPECTED_DIGEST = {
    'checklist': '3a819b54d295f9982b4b6fd0ef80e34a52a834691a6b1ee0e4a5e7ec2c1f8060',
    'aq': 'b3a5656aa551642d9bb52894d7e6e5a864b49bf8c2ba5886d2e4f580ea218d48',
}


def expand_ids(text):
    """Expand closed ranges, then return remaining literal IDs without double endpoints."""
    text = text.replace('`', '')
    range_re = re.compile(
        r'([A-Z][A-Z0-9]*-)(\d+)\s*'
        r'(?:至|--|\.\.)\s*'
        r'(?:([A-Z][A-Z0-9]*-))?(\d+)'
    )
    result = []
    masked = list(text)
    for match in range_re.finditer(text):
        prefix, start, end_prefix, end = match.groups()
        end_prefix = end_prefix or prefix
        if end_prefix != prefix:
            raise AssertionError(f'mixed-prefix range: {match.group(0)!r}')
        lo, hi = int(start), int(end)
        if hi < lo:
            raise AssertionError(f'descending range: {match.group(0)!r}')
        width = max(len(start), len(end))
        result.extend(f'{prefix}{number:0{width}d}' for number in range(lo, hi + 1))
        masked[match.start():match.end()] = ' ' * (match.end() - match.start())
    result.extend(re.findall(ITEM_PATTERN, ''.join(masked)))
    return result


def markdown_sections(path):
    """Return H2/H3 sections, ending at the next same-or-higher heading."""
    lines = path.read_text().splitlines()
    headings = []
    for index, line in enumerate(lines):
        match = re.match(r'^(#{2,3}) (.+)$', line)
        if match:
            headings.append((index, len(match.group(1)), match.group(2)))
    result = []
    for index, level, title in headings:
        end = len(lines)
        for cursor in range(index + 1, len(lines)):
            match = re.match(r'^(#+) ', lines[cursor])
            if match and len(match.group(1)) <= level:
                end = cursor
                break
        result.append((title, lines[index:end]))
    return result


def normalized_section(lines):
    """Apply the register's conservative UTF-8/LF section normalization."""
    normalized = [line.rstrip() for line in lines]
    while normalized and not normalized[0]:
        normalized.pop(0)
    while normalized and not normalized[-1]:
        normalized.pop()
    return '\n'.join(normalized) + '\n'


def group_sort_key(group):
    return int(group.rsplit('-', 1)[1])


def topic_from_heading(group, heading):
    match = re.fullmatch(re.escape(group) + r'(?:：|:|\s)+(.*)', heading)
    assert match and match.group(1), (group, heading)
    return match.group(1)


def assert_relative_links_exist():
    """Check filesystem targets for every relative Markdown link in live docs."""
    broken = []
    for markdown in root.rglob('*.md'):
        text = markdown.read_text()
        # Verbatim reply/code examples may legitimately contain Markdown-like
        # bytes that are data, not links. Link validation only consumes prose.
        prose = re.sub(r'(?ms)^```[^\n]*\n.*?^```[ \t]*$', '', text)
        for raw in re.findall(r'(?<!!)\[[^\]]*\]\(([^)]+)\)', prose):
            target = raw.strip()
            if target.startswith('<') and '>' in target:
                target = target[1:target.index('>')]
            else:
                target = target.split()[0]
            if target.startswith(('#', 'http://', 'https://', 'mailto:', 'data:')):
                continue
            path_part = unquote(target.split('#', 1)[0])
            if path_part and not (markdown.parent / path_part).resolve().exists():
                broken.append((str(markdown), raw))
    assert not broken, broken


def association_payloads(lines, formal=False):
    """Read only an explicit physical association line, never general prose."""
    if formal:
        return [line[len('关联：'):] for line in lines if line.startswith('关联：')]
    result = []
    for line in lines:
        match = re.search(r'关联(?:\*\*)?：(.*)$', line)
        if match:
            result.append(match.group(1))
    return result


def add_routes(target, owner, payloads):
    for payload in payloads:
        for item in expand_ids(payload):
            target[item].add(owner)


def require_anchors(anchor_sets):
    cache = {}
    for gate, anchors in anchor_sets.items():
        for relative_path, needle in anchors:
            text = cache.setdefault(relative_path, (root / relative_path).read_text())
            assert needle in text, (gate, relative_path, needle)


# Raw inventories are asserted before any set/dict deduplication.
checklist_text = (root / 'DESIGN-CHECKLIST.md').read_text()
checklist_raw = re.findall(
    r'^- \*\*([A-Z][A-Z0-9]*-\d+)\b', checklist_text, re.M
)
assert len(checklist_raw) == EXPECTED_CHECKLIST, len(checklist_raw)
assert len(set(checklist_raw)) == EXPECTED_CHECKLIST, [
    item for item, count in collections.Counter(checklist_raw).items() if count != 1
]

questions_text = (root / 'QUESTIONS.md').read_text()
aq_raw = re.findall(r'^#### (AQ-\d+)\b', questions_text, re.M)
expected_aq_sequence = [f'AQ-{number:03d}' for number in range(1, EXPECTED_AQ + 1)]
assert len(aq_raw) == EXPECTED_AQ
assert len(set(aq_raw)) == EXPECTED_AQ
assert aq_raw == expected_aq_sequence, (aq_raw[:3], aq_raw[-3:])

schema_text = (root / 'CONFIG-SCHEMA-CANDIDATE.md').read_text()
cv_raw = re.findall(r'^\| (CV-\d+) \|', schema_text, re.M)
expected_cv_sequence = [f'CV-{number:03d}' for number in range(1, EXPECTED_CV + 1)]
assert len(cv_raw) == EXPECTED_CV, len(cv_raw)
assert len(set(cv_raw)) == EXPECTED_CV
assert cv_raw == expected_cv_sequence, (cv_raw[:3], cv_raw[-3:])

decision_raw = re.findall(r'^## (D-\d+)\b', (root / 'DECISIONS.md').read_text(), re.M)
assert decision_raw == [f'D-{number:03d}' for number in range(1, 58)], decision_raw

discussion3_text = (root / 'DISCUSSION-BATCH-03.md').read_text()
rb003_raw = re.findall(r'^## (RB-003-\d{2})：', discussion3_text, re.M)
as003_raw = re.findall(r'^### (AS-003-\d{2})：', discussion3_text, re.M)
assert rb003_raw == [f'RB-003-{number:02d}' for number in range(1, 3)], rb003_raw
assert as003_raw == [f'AS-003-{number:02d}' for number in range(1, 3)], as003_raw

discussion4_text = (root / 'DISCUSSION-BATCH-04.md').read_text()
rb004_raw = re.findall(r'^## (RB-004-\d{2})：', discussion4_text, re.M)
as004_raw = re.findall(r'^### (AS-004-\d{2})：', discussion4_text, re.M)
assert rb004_raw == [f'RB-004-{number:02d}' for number in range(1, 12)], rb004_raw
assert as004_raw == [f'AS-004-{number:02d}' for number in range(1, 11)], as004_raw

proof_raw = re.findall(
    r'^### (TP-\d+)\b', (root / 'TECHNICAL-PROOF-BACKLOG.md').read_text(), re.M
)
assert proof_raw == [f'TP-{number:03d}' for number in range(1, 31)], proof_raw

assert_relative_links_exist()


# The bottom bare response templates are the only formal membership source.
packets = sorted(packet_dir.glob('[0-9][0-9]-*.md'))
assert len(packets) == 10, [packet.name for packet in packets]
packet_source_bytes = b''.join(
    packet.name.encode('utf-8') + b'\0' + packet.read_bytes() + b'\0'
    for packet in packets
)
packet_source_digest = hashlib.sha256(packet_source_bytes).hexdigest()
assert packet_source_digest == EXPECTED_PACKET_SOURCE_SHA256, packet_source_digest
template_raw = []
owner_packet = {}
template_choice = {}
for packet in packets:
    for group, choice in re.findall(
        r'^(' + GROUP_PATTERN + r') ([ABC])$', packet.read_text(), re.M
    ):
        template_raw.append((group, choice, packet))
        assert group not in owner_packet, ('duplicate formal template group', group)
        owner_packet[group] = packet
        template_choice[group] = choice

assert len(template_raw) == EXPECTED_FORMAL, len(template_raw)
assert len(owner_packet) == EXPECTED_FORMAL, len(owner_packet)
formal_set = set(owner_packet)
assert len(EXPECTED_ACTIVE) == 22
assert set(EXPECTED_ACTIVE) <= formal_set, sorted(set(EXPECTED_ACTIVE) - formal_set)

actual_distribution = collections.Counter(group.split('-', 1)[0] for group in formal_set)
assert actual_distribution == collections.Counter(EXPECTED_DISTRIBUTION), actual_distribution
for prefix, specification in EXPECTED_GROUP_LISTS.items():
    expected = sorted(expand_ids(specification), key=group_sort_key)
    actual = sorted(
        (group for group in formal_set if group.startswith(prefix + '-')),
        key=group_sort_key,
    )
    assert actual == expected, (prefix, actual, expected)


# A formal heading must be unique inside the packet whose template owns it.
packet_sections = {packet: markdown_sections(packet) for packet in packets}
formal_section_records = []
for group, packet in owner_packet.items():
    candidates = [
        (title, lines)
        for title, lines in packet_sections[packet]
        if re.match(re.escape(group) + r'\b', title)
    ]
    assert len(candidates) == 1, (group, packet, [title for title, _ in candidates])
    formal_section_records.append((group, packet, *candidates[0]))

formal_heading_raw = [record[0] for record in formal_section_records]
assert len(formal_heading_raw) == EXPECTED_FORMAL
assert len(set(formal_heading_raw)) == EXPECTED_FORMAL
assert set(formal_heading_raw) == formal_set

formal_section_by_group = {
    group: (packet, title, lines)
    for group, packet, title, lines in formal_section_records
}
canonical_groups = []
for packet in packets:
    canonical_groups.extend(sorted(
        (group for group in formal_set if owner_packet[group] == packet),
        key=group_sort_key,
    ))
assert len(canonical_groups) == EXPECTED_FORMAL


# Independently rebuild the register's structural and semantic manifests.
structural_parts = []
semantic_parts = []
expected_register = {}
for group in canonical_groups:
    packet, heading, lines = formal_section_by_group[group]
    topic = topic_from_heading(group, heading)
    recommendation = template_choice[group]
    active_when = EXPECTED_ACTIVE.get(group, 'always')
    section = normalized_section(lines)
    structural_parts.append(f'{group}\t{topic}\t{recommendation}\n')
    semantic_record = (
        f'@@group\t{group}\n'
        f'packet\t{packet.name}\n'
        f'recommendation\t{recommendation}\n'
        f'active_when\t{active_when}\n'
        f'{section}'
        '@@end\n'
    )
    semantic_parts.append(semantic_record)
    expected_register[group] = {
        'topic': topic,
        'recommendation': recommendation,
        'active_when': active_when,
        'sem': hashlib.sha256(semantic_record.encode()).hexdigest()[:16],
    }

structural_bytes = ''.join(structural_parts).encode()
semantic_bytes = ''.join(semantic_parts).encode()
structural_digest = hashlib.sha256(structural_bytes).hexdigest()
semantic_digest = hashlib.sha256(semantic_bytes).hexdigest()
assert len(structural_bytes) == EXPECTED_STRUCTURAL_BYTES, len(structural_bytes)
assert structural_digest == EXPECTED_STRUCTURAL_SHA256, structural_digest
assert len(semantic_bytes) == EXPECTED_SEMANTIC_BYTES, len(semantic_bytes)
assert semantic_digest == EXPECTED_SEMANTIC_SHA256, semantic_digest


# Register membership and every immutable manifest column must match that rebuild.
register_text = (root / 'DECISION-REGISTER.md').read_text()
version_match = re.search(r'^\| Inventory version \| `([^`]+)` \|$', register_text, re.M)
assert version_match and version_match.group(1) == EXPECTED_INVENTORY_VERSION
packet_source_header = re.search(
    r'^\| Packet-source SHA-256 \| `([0-9a-f]{64})`；(\d+) bytes',
    register_text,
    re.M,
)
assert packet_source_header and packet_source_header.groups() == (
    packet_source_digest, str(len(packet_source_bytes))
), packet_source_header.groups() if packet_source_header else None
assert re.search(r'^\| Formal groups \| 270 \|$', register_text, re.M)
assert re.search(r'^\| Activation split \| `22 conditional / 248 always` \|$', register_text, re.M)
assert re.search(r'^\| Checklist IDs \| 384 \|$', register_text, re.M)
assert re.search(r'^\| Atomic questions \| `AQ-001\.\.AQ-437` \|$', register_text, re.M)
structural_header = re.search(
    r'^\| Structural SHA-256 \| `([0-9a-f]{64})`；(\d+) records / (\d+) bytes',
    register_text,
    re.M,
)
semantic_header = re.search(
    r'^\| Semantic SHA-256 \| `([0-9a-f]{64})`；(\d+) records / (\d+) bytes',
    register_text,
    re.M,
)
assert structural_header and structural_header.groups() == (
    structural_digest, str(EXPECTED_FORMAL), str(len(structural_bytes))
), structural_header.groups() if structural_header else None
assert semantic_header and semantic_header.groups() == (
    semantic_digest, str(EXPECTED_FORMAL), str(len(semantic_bytes))
), semantic_header.groups() if semantic_header else None

register_match = re.search(
    r'^## 逐组实时登记\s*$\n(.*?)(?=^## |\Z)', register_text, re.M | re.S
)
assert register_match, 'missing register section'
register_rows = re.findall(
    r'^\| `(' + GROUP_PATTERN + r')` \| (.*?) \| ([ABC]) \| '
    r'`([0-9a-f]{16})` \| `([^`]+)` \| `([^`]+)` \| '
    r'(.*?) \| (.*?) \| (.*?) \|$',
    register_match.group(1),
    re.M,
)
register_raw = [row[0] for row in register_rows]
assert len(register_raw) == EXPECTED_FORMAL, len(register_raw)
assert len(set(register_raw)) == EXPECTED_FORMAL
assert register_raw == canonical_groups, (register_raw[:3], register_raw[-3:])
assert set(register_raw) == formal_set, (
    sorted(formal_set - set(register_raw)), sorted(set(register_raw) - formal_set)
)
for group, topic, recommendation, sem, active_when, _state, *_mutable in register_rows:
    expected = expected_register[group]
    assert topic == expected['topic'], (group, topic, expected['topic'])
    assert recommendation == expected['recommendation'], (group, recommendation)
    assert active_when == expected['active_when'], (group, active_when)
    assert sem == expected['sem'], (group, sem, expected['sem'])

register_states = collections.Counter(row[5] for row in register_rows)
expected_register_states = collections.Counter({
    'selected': 110,
    'selected-with-exception': 150,
    'excluded': 5,
    'not-applicable': 5,
})
assert register_states == expected_register_states, register_states

projected_groups = {}
for row in register_rows:
    group, state, projection = row[0], row[5], row[8]
    if state == 'unanswered':
        assert projection == '—', (group, state, projection)
        continue
    projection_match = re.fullmatch(r'`(PR-\d{3}-(?:\d{2}|[A-Z0-9-]+))`', projection)
    assert projection_match, (group, state, projection)
    projected_groups[group] = projection_match.group(1)

sparse_match = re.search(
    r'^## 稀疏传播记录\s*$\n(.*?)(?=^## |\Z)', register_text, re.M | re.S
)
assert sparse_match, 'missing sparse projection section'
projection_rows = re.findall(
    r'^\| `(PR-\d{3}-\d{2})` \| (' + GROUP_PATTERN + r') \|',
    sparse_match.group(1),
    re.M,
)
expected_projection_ids = {
    *(f'PR-002-{number:02d}' for number in range(1, 21)),
    'PR-004-01',
    'PR-011-01',
}
assert len(projection_rows) == len(expected_projection_ids), projection_rows
assert len({projection_id for projection_id, _group in projection_rows}) == len(projection_rows)
assert len({group for _projection_id, group in projection_rows}) == len(projection_rows)
assert {projection_id for projection_id, _group in projection_rows} == expected_projection_ids
legacy_projected_groups = {
    group: projection_id
    for group, projection_id in projected_groups.items()
    if not projection_id.startswith('PR-006-')
}
assert {
    group: projection_id for projection_id, group in projection_rows
} == legacy_projected_groups, (projection_rows, legacy_projected_groups)

# Batch 06 uses a deterministic per-group expansion instead of copying 248
# identical PR metadata rows into the register. Its member set must exactly
# equal the frozen OWNER-QUESTIONS coverage and each ID must encode its group.
owner_questions_text = (root / 'OWNER-QUESTIONS-01.md').read_text()
batch06_coverage = []
for coverage_line in re.findall(r'^覆盖：(.*)$', owner_questions_text, re.M):
    batch06_coverage.extend(re.findall(r'`(' + GROUP_PATTERN + r')`', coverage_line))
assert len(batch06_coverage) == 248, len(batch06_coverage)
assert len(set(batch06_coverage)) == 248
batch06_projected_groups = {
    group: projection_id
    for group, projection_id in projected_groups.items()
    if projection_id.startswith('PR-006-')
}
assert set(batch06_projected_groups) == set(batch06_coverage), (
    sorted(set(batch06_coverage) - set(batch06_projected_groups)),
    sorted(set(batch06_projected_groups) - set(batch06_coverage)),
)
for group, projection_id in batch06_projected_groups.items():
    assert projection_id == f'PR-006-{group}', (group, projection_id)
batch06_projection_text = (root / 'DECISION-PROJECTION-BATCH-06.md').read_text()
assert 'PR-006-<GROUP-ID>' in batch06_projection_text
assert '对于下表某行的每个覆盖 group `G`' in batch06_projection_text


# Queue membership comes only from the `formal groups` cell of B01..B49.
queue_text = (root / 'DECISION-BATCH-QUEUE.md').read_text()
batch_rows = re.findall(r'^\| `(B\d+)` \| ([^|\n]+) \|', queue_text, re.M)
assert [batch for batch, _ in batch_rows] == [
    f'B{number:02d}' for number in range(1, EXPECTED_BATCHES + 1)
], [batch for batch, _ in batch_rows]
queue_raw = []
for batch, cell in batch_rows:
    members = expand_ids(cell)
    assert members, (batch, cell)
    assert 3 <= len(members) <= 6, (batch, len(members), members)
    assert all(re.fullmatch(GROUP_PATTERN, member) for member in members), (batch, members)
    queue_raw.extend(members)
assert len(queue_raw) == EXPECTED_FORMAL, len(queue_raw)
assert len(set(queue_raw)) == EXPECTED_FORMAL, [
    item for item, count in collections.Counter(queue_raw).items() if count != 1
]
assert set(queue_raw) == formal_set, (
    sorted(formal_set - set(queue_raw)), sorted(set(queue_raw) - formal_set)
)


# Direct formal ownership: only the owner section's standalone `关联：` line.
formal_owners = collections.defaultdict(set)
for group, packet, title, lines in formal_section_records:
    payloads = association_payloads(lines, formal=True)
    assert len(payloads) == 1, (group, packet, title, payloads)
    add_routes(formal_owners, group, payloads)

# v8's five checklist labels are indirect cross-index projections. They are
# accepted only when the unique AQ section explicitly names the same owner.
checklist_lines = checklist_text.splitlines()
for item, (question, group) in FORMAL_CHECKLIST_PROJECTION.items():
    rows = [line for line in checklist_lines if line.startswith(f'- **{item} ')]
    assert len(rows) == 1, (item, rows)
    question_section = re.search(
        rf'^#### {re.escape(question)}\b(.*?)(?=^#### AQ-|\Z)',
        questions_text,
        re.M | re.S,
    )
    assert question_section, (item, question)
    assert f'正式 owner：{group}' in question_section.group(1), (
        item, question, group
    )
    assert not formal_owners.get(item), (item, formal_owners[item])
    assert group in formal_set, (item, group)
    formal_owners[item].add(group)

# v9's six additions are stricter: the checklist ID and AQ must both appear on
# the exact owner's standalone association line, while the AQ section names it.
for item, (question, group) in DIRECT_FORMAL_CHECKLIST_PROJECTION.items():
    rows = [line for line in checklist_lines if line.startswith(f'- **{item} ')]
    assert len(rows) == 1, (item, rows)
    question_section = re.search(
        rf'^#### {re.escape(question)}\b(.*?)(?=^#### AQ-|\Z)',
        questions_text,
        re.M | re.S,
    )
    assert question_section, (item, question)
    assert f'正式 owner：{group}' in question_section.group(1), (
        item, question, group
    )
    assert formal_owners.get(item) == {group}, (item, formal_owners.get(item))
    assert formal_owners.get(question) == {group}, (
        question, formal_owners.get(question)
    )


# Explicit fixed non-vote sections; cross-packet projections of formal IDs are ignored.
numbered_gate_records = []
special_gate_records = []
for packet in packets:
    for title, lines in packet_sections[packet]:
        group_match = re.match(r'(' + GROUP_PATTERN + r')\b', title)
        if (
            group_match
            and group_match.group(1) not in formal_set
            and ('不是负责人投票' in title or '技术证明' in title)
        ):
            numbered_gate_records.append((group_match.group(1), packet, title, lines))

        special_match = re.search(r'原 (' + GROUP_PATTERN + r')', title)
        if special_match and ('无需回复' in title or '不需回复' in title):
            special_gate_records.append((special_match.group(1), packet, title, lines))

numbered_gate_raw = [record[0] for record in numbered_gate_records]
special_gate_raw = [record[0] for record in special_gate_records]
assert len(numbered_gate_raw) == len(set(numbered_gate_raw))
assert set(numbered_gate_raw) == EXPECTED_NUMBERED_GATES, numbered_gate_raw
assert len(special_gate_raw) == len(set(special_gate_raw))
assert set(special_gate_raw) == EXPECTED_SPECIAL_GATES, special_gate_raw

technical_owners = collections.defaultdict(set)
excluded_owners = collections.defaultdict(set)
for group, packet, title, lines in numbered_gate_records + special_gate_records:
    payloads = association_payloads(lines)
    assert payloads, (group, packet, title)
    target = excluded_owners if group == 'F4-13' else technical_owners
    add_routes(target, group, payloads)


# TP routes also require an explicit association marker inside that exact TP section.
for title, lines in markdown_sections(root / 'TECHNICAL-PROOF-BACKLOG.md'):
    match = re.match(r'(TP-\d+)\b', title)
    if not match:
        continue
    proof = match.group(1)
    payloads = association_payloads(lines)
    assert payloads, proof
    add_routes(technical_owners, proof, payloads)


# No D body scanning. Each confirmed exception is exact and independently anchored.
CONFIRMED = {
    'PROD-09': 'D-029',
    'ARCH-03': 'D-013,D-014',
    'CFG-16': 'D-027',
    'SAFE-17': 'D-034',
    'INDEX-13': 'D-030',
    'AQ-016': 'D-028',
    'AQ-157': 'D-029',
}
CONFIRMED_ANCHORS = {
    'PROD-09': [('DECISIONS.md', '本决定使 `PROD-09` 的独立本地化问题')],
    'ARCH-03': [
        ('DESIGN-CHECKLIST.md', 'ARCH-03 依赖装配（已确认核心）'),
        ('DESIGN-CHECKLIST.md', 'D-013/D-014 已确认'),
    ],
    'CFG-16': [
        ('DESIGN-CHECKLIST.md', 'CFG-16 独立终止评估开关迁移（已确认方向）'),
        ('DECISIONS.md', '不再提供与 `DoubleCheck` 并列的 `UseTerminationEvaluator`'),
    ],
    'SAFE-17': [('DECISIONS.md', 'v0.1 不承诺或实现统一 OS sandbox')],
    'INDEX-13': [('DECISIONS.md', '本决定归档 `INDEX-13`')],
    'AQ-016': [('DECISIONS.md', '本决定归档 `AQ-016`')],
    'AQ-157': [('DECISIONS.md', '并归档 `AQ-157`')],
}


# These gates are exact implementation/proof contracts, not thematic neighbors.
FIXED_GATES = {
    'RuntimeDomainRegistry': [
        ('subsystems/22-application-runtime-and-concurrency.md', '定义领域状态、领域事件、适配器事件和 UI 投影的所有权'),
        ('subsystems/22-application-runtime-and-concurrency.md', '只有应用核心产生领域状态转换'),
    ],
    'LuaModuleLifecycle': [
        ('subsystems/22-application-runtime-and-concurrency.md', '模块加载本身不得联网、写文件、修改终端或取得锁'),
        ('subsystems/22-application-runtime-and-concurrency.md', '`require` 只加载受控发行路径'),
    ],
    'TP-029-AmbientLoad': [
        ('TECHNICAL-PROOF-BACKLOG.md', '### TP-029 模块/DLL/tool 搜索、ambient config 与完整性'),
    ],
    'TP-012-PathCodec': [
        ('TECHNICAL-PROOF-BACKLOG.md', '### TP-012 Unicode 路径、LogicalPathCodec 与 hash'),
    ],
    'PlatformEnvironmentText': [
        ('subsystems/01-platform-abstraction.md', '路径语法、当前目录、环境变量和临时目录'),
        ('subsystems/01-platform-abstraction.md', '控制台代码页、locale、换行和终端能力'),
    ],
    'PlatformClockTemp': [
        ('subsystems/01-platform-abstraction.md', '时钟、随机临时名和进程级限制'),
        ('subsystems/01-platform-abstraction.md', '`clock.lua`：时间与单调计时能力'),
    ],
    'PlatformAdapterLayout': [
        ('subsystems/01-platform-abstraction.md', '## 适配器文件布局方案'),
        ('subsystems/01-platform-abstraction.md', '只有 `main.lua` 知道 `_windows` / `_linux` 文件名'),
    ],
    'PlatformIdentityGuard': [
        ('subsystems/01-platform-abstraction.md', '## `platform.lua` 身份契约方案'),
        ('subsystems/22-application-runtime-and-concurrency.md', '读取最小平台身份并拒绝错误 OS/架构的发行包'),
    ],
    'TP-023,TP-024-OldTerminal': [
        ('TECHNICAL-PROOF-BACKLOG.md', '### TP-023 terminal renderer 安全与确定性'),
        ('TECHNICAL-PROOF-BACKLOG.md', '### TP-024 CLI、dot command 与非 TTY grammar'),
    ],
    'ProcessPortABI': [
        ('subsystems/02-process-and-resources.md', '必须接入同一可轮询/可通知的运行时端口'),
        ('subsystems/02-process-and-resources.md', '取消后如何等待真实完成'),
    ],
    'TP-029-BundledToolSearch': [
        ('TECHNICAL-PROOF-BACKLOG.md', '### TP-029 模块/DLL/tool 搜索、ambient config 与完整性'),
    ],
    'TP-008-CommitRecord': [
        ('TECHNICAL-PROOF-BACKLOG.md', '### TP-008 单 XML 完整重写的正确性'),
        ('TECHNICAL-PROOF-BACKLOG.md', '不产生半个正式 XML'),
    ],
    'TP-010,TP-019-DeterministicWriter': [
        ('TECHNICAL-PROOF-BACKLOG.md', 'writer 能确定性转义'),
        ('decision-packets/08-context-xml-index-recovery.md', '确定性 writer 与重建测试'),
    ],
    'TypedSchemaSource': [
        ('subsystems/05-configuration.md', '长期来源只有：'),
        ('subsystems/05-configuration.md', '逐字段 schema 的正式实现必须从以下已确认表面生成'),
    ],
    'ToolRegistryVersion': [
        ('subsystems/07-tool-system.md', '完整 registry、每个 schema version 和 registry digest'),
        ('decision-packets/07-tools-safety-process-runtime.md', '首版 tool registry、TS-23 所选 input carrier/schema、TS-37 cwd state、版本'),
    ],
    'ContextIdentityDigest': [
        ('decision-packets/08-context-xml-index-recovery.md', '每个事件还可以有完整 SHA-256 内容 digest 和 previous-event digest'),
        ('decision-packets/08-context-xml-index-recovery.md', '`ContextIdentity`：所有局部 ID、provider ID、event digest 和引用不变量'),
    ],
    'TP-003,TP-005-Clock': [
        ('QUESTIONS.md', 'AQ-270 时间戳与 deadline 使用什么时钟'),
        ('QUESTIONS.md', '状态：技术规格/证明，不进入负责人正式回复清单'),
    ],
    'TP-015,TP-021-SafeJSON': [
        ('QUESTIONS.md', 'AQ-323 tool arguments JSON 的安全解析规则'),
        ('QUESTIONS.md', '状态：安全硬不变量/技术证明，不进入负责人正式回复清单'),
    ],
}
FIXED_ITEMS = {
    'ARCH-04': 'RuntimeDomainRegistry',
    'RUNTIME-03': 'LuaModuleLifecycle',
    'RUNTIME-04': 'TP-029-AmbientLoad',
    'PLAT-01': 'TP-012-PathCodec',
    'PLAT-03': 'PlatformEnvironmentText',
    'PLAT-06': 'PlatformClockTemp',
    'PLAT-07': 'PlatformAdapterLayout',
    'PLAT-08': 'PlatformIdentityGuard',
    'PLAT-12': 'TP-023,TP-024-OldTerminal',
    'PROC-01': 'ProcessPortABI',
    'PROC-08': 'TP-029-BundledToolSearch',
    'FMT-05': 'TP-008-CommitRecord',
    'FMT-07': 'TP-010,TP-019-DeterministicWriter',
    'CFG-18': 'TypedSchemaSource',
    'TOOL-16': 'ToolRegistryVersion',
    'AQ-171': 'ContextIdentityDigest',
    'AQ-270': 'TP-003,TP-005-Clock',
    'AQ-323': 'TP-015,TP-021-SafeJSON',
}

require_anchors(CONFIRMED_ANCHORS)
require_anchors(FIXED_GATES)

all_inputs = set(checklist_raw) | set(aq_raw)
assert set(CONFIRMED) | set(FIXED_ITEMS) <= all_inputs
assert set(CONFIRMED).isdisjoint(FIXED_ITEMS)
direct_ids = set(formal_owners) | set(excluded_owners) | set(technical_owners)
assert set(CONFIRMED).isdisjoint(direct_ids), set(CONFIRMED) & direct_ids
assert set(FIXED_ITEMS).isdisjoint(direct_ids), set(FIXED_ITEMS) & direct_ids

decision_set = set(decision_raw)
for item, route in CONFIRMED.items():
    referenced = set(re.findall(r'D-\d+', route))
    assert referenced and referenced <= decision_set, (item, route, referenced)


def classify(item):
    if formal_owners.get(item):
        return 'formal', ','.join(sorted(formal_owners[item]))
    if excluded_owners.get(item):
        return 'excluded', ','.join(sorted(excluded_owners[item]))
    if item in CONFIRMED:
        return 'confirmed', CONFIRMED[item]
    if technical_owners.get(item):
        return 'technical', ','.join(sorted(technical_owners[item]))
    if item in FIXED_ITEMS:
        return 'technical', 'gate:' + FIXED_ITEMS[item]
    return 'ORPHAN', '-'


print(
    'INVENTORY',
    f'formal_raw={len(template_raw)}',
    f'formal_unique={len(formal_set)}',
    f'headings={len(formal_heading_raw)}',
    f'register={len(register_raw)}',
    f'queue={len(queue_raw)}',
    f'batches={len(batch_rows)}',
    f'checklist_raw={len(checklist_raw)}',
    f'checklist_unique={len(set(checklist_raw))}',
    f'aq_raw={len(aq_raw)}',
    f'aq_unique={len(set(aq_raw))}',
    f'cv_raw={len(cv_raw)}',
    f'cv_unique={len(set(cv_raw))}',
    'links=ok',
    sep='\t',
)
print(
    'MANIFEST',
    f'version={EXPECTED_INVENTORY_VERSION}',
    f'packet_source_sha256={packet_source_digest}',
    f'structural_bytes={len(structural_bytes)}',
    f'structural_sha256={structural_digest}',
    f'semantic_bytes={len(semantic_bytes)}',
    f'semantic_sha256={semantic_digest}',
    sep='\t',
)

for label, items in [('checklist', checklist_raw), ('aq', aq_raw)]:
    routes = [(item, *classify(item)) for item in items]
    for route in routes:
        print('ROUTE', *route, sep='\t')

    orphan = [route for route in routes if route[1] == 'ORPHAN']
    counts = collections.Counter(route[1] for route in routes)
    canonical = ''.join('\t'.join(route) + '\n' for route in routes).encode()
    digest = hashlib.sha256(canonical).hexdigest()

    assert not orphan, orphan
    assert counts == collections.Counter(EXPECTED_COUNTS[label]), counts
    assert digest == EXPECTED_DIGEST[label], (digest, EXPECTED_DIGEST[label])

    print(
        'SUMMARY',
        label,
        f'total={len(routes)}',
        f'formal={counts["formal"]}',
        f'confirmed={counts["confirmed"]}',
        f'technical={counts["technical"]}',
        f'excluded={counts["excluded"]}',
        f'orphan={len(orphan)}',
        f'sha256={digest}',
        sep='\t',
    )
PY
```

成功执行的四条汇总为：

```text
INVENTORY	formal_raw=270	formal_unique=270	headings=270	register=270	queue=270	batches=49	checklist_raw=384	checklist_unique=384	aq_raw=437	aq_unique=437	cv_raw=76	cv_unique=76	links=ok
MANIFEST	version=decision-inventory-v9	packet_source_sha256=13b0a7cbad9556db50bbd81bdee76554900d252deb79b3ab68bd41e5f59c49f6	structural_bytes=13575	structural_sha256=22e724986251bd63ae75e1c7964b3a2f6d3412a4e0f9b01019662790d68df6ef	semantic_bytes=471107	semantic_sha256=80efc73d45ed32e05ea991f35a8cc484700a276f6664c77bc339c7957648b044
SUMMARY	checklist	total=384	formal=331	confirmed=5	technical=42	excluded=6	orphan=0	sha256=3a819b54d295f9982b4b6fd0ef80e34a52a834691a6b1ee0e4a5e7ec2c1f8060
SUMMARY	aq	total=437	formal=413	confirmed=2	technical=21	excluded=1	orphan=0	sha256=b3a5656aa551642d9bb52894d7e6e5a864b49bf8c2ba5886d2e4f580ea218d48
```

## 何时必须重跑

以下任一变化都必须在同一文档事务中重跑：

- 新增、删除、重命名或重复 checklist/AQ/CV 条目；
- 十个 owner packet 的任一原始字节变化，包括新增正式组、回复模板、标题、推荐、选项正文或正式 `关联：` 行；
- register 的 inventory version/title/Rec/Active/Sem/总摘要，或 queue 成员、顺序、批次变化；
- `.develope-docs` 内任一相对 Markdown 链接目标变化；
- 新增 D/TP，或把待决问题提升为正式 owner、技术 gate、排除/re-entry；
- 固定 gate 的权威工件、语义锚点或边界改变；
- scope 重新开放，尤其 Web、媒体、remote、multi-root、telemetry、update 或扩展运行时。

若出现 orphan，应先在真正的 owner packet/技术证明中补齐边界。禁止只把 ID 加入 `CONFIRMED`/`FIXED_ITEMS` 来让计数变绿；每个例外必须满足“真实已确认 D、明确非投票的 proof/fixed gate、或明确 exclusion/re-entry owner”之一，并带能被脚本验证的现行来源锚点。
