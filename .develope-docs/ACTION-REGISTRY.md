# W2-A Semantic Action Registry

更新日期：2026-08-29

状态：**规格侧已冻结**；精确机读真源为 [`contracts/actions.lua`](contracts/actions.lua)，本页保留人读投影。
消费方：CLI parser、TUI 点命令/快捷键、help、completion、测试。  
**非** headless/remote 公共 API。

对齐：D-054、D-061、D-062、D-065、D-066、D-042、D-068。

## 1. 注册表记录字段

| 字段 | 说明 |
| --- | --- |
| `id` | 稳定 semantic id（kebab-case） |
| `long` | 规范 `--` 拼写或默认入口 |
| `short` | 唯一跨平台 `-` 简写 |
| `slash` | Windows-only `/`；Linux 不注册 |
| `surface` | `top` / `chat` / `both` |
| `args` | 参数摘要 |
| `tty` | `any` / `prefer-tty` / `tty-required` |
| `confirm` | 是否需人确认；非 TTY 缺确认则失败 |
| `notes` | 不变量 |

解析：长名 canonical；`--` 结束选项；Linux 上 `/` 永不为选项。

## 2. 顶层 argv

| id | long | short | slash | args | notes |
| --- | --- | --- | --- | --- | --- |
| `run-chat` | （默认无 flag） | — | — | `[directory]` | 缺省 `.` |
| `help` | `--help` | `-h` | `/h` | optional topic | |
| `version` | `--version` | `-v` | `/v` | none | |
| `self-test` | `--self-test` | `-st` | `/st` | 见下 | D-062 |
| `model-repl` | `--model-repl` | `-mr` | `/mr` | none | |
| `config-repl` | `--config-repl` | `-cfg` | `/cfg` | none | |
| `context-repl` | `--context-repl` | `-ctx` | `/ctx` | `recent`\|`full` 必选 | |
| `continue` | `--continue` | `-c` | `/c` | `<selector>` | D-061 |
| `export-context` | `--export` | `-ex` | `/ex` | optional selector | D-068 主路径 |
| `status` | `--status` | `-stt` | `/stt` | none | 当前句柄；短名避开与 self-test 冲突 |

不恢复旧冲突 `-dc`/`-rc`。

### self-test 子参

| 语义 | argv 候选 |
| --- | --- |
| through_stage | `--through-stage 1\|2\|3` |
| list_checks | `--list-checks` |
| exclude_model | `--exclude-model NAME`（可重复） |
| exclude_check | `--exclude-check ID`（可重复） |
| select_check | `--check ID`（可重复） |
| online_consent | **`--i-accept-online-self-test`**（非 TTY 且 stage≥2 **必须**，D-062） |

## 3. Chat 点命令与快捷键

| id | dot | key | args | notes |
| --- | --- | --- | --- | --- |
| `queue-add` | `.queue` | Enter（忙时） | message | D-066 |
| `queue-list` | `.queue list` | — | — | 显示 `#N` |
| `queue-delete` | `.queue delete` | — | `#N` | |
| `queue-move` | `.queue move` | — | from to | |
| `queue-edit` | `.queue edit` | — | `#N` text | |
| `queue-clear` | `.queue clear` | — | — | |
| `steer` | `.immediate` | Ctrl+Enter | message | 非 immidiate |
| `side` | `.side` | Alt+Enter | message | 最多一个 |
| `multiline` | `.multiline` | Shift+Enter | — | delimiter 后冻 |
| `cancel` | `.cancel` | Esc | — | 最内层 |
| `cautious` | `.cautious` | — | 空\|on\|off\|toggle\|reset | D-065 |
| `select-model` | `.model` | — | 空\|selector | |
| `status-chat` | `.status` | — | — | 句柄 hash |
| `help-chat` | `.help` | — | optional | |
| `details` | `.details` | — | optional id | D-055 |
| `prompt-edit` | `.prompt` | — | 子语法后补 | ContextPrompt |
| `compact-manual` | `.compact` | — | — | D-067 STATUS |
| `quit` | `.quit` | — | — | close；无额外确认 |

## 4. Context 领域动作

| id | 用途 | confirm |
| --- | --- | --- |
| `context-list` | 列表 | no |
| `context-rename` | 重命名 | no |
| `context-rebind` | 改 root | **yes** |
| `context-delete` | 永久删除 | **yes**（非默认） |
| `context-set-auto-rename-disabled` | marker | no |
| `context-export` | 同 export-context | no |

非 TTY 且 `confirm=yes`：需要 `--yes`（唯一确认拼写候选），否则失败。

## 5. command × 状态（粗表）

| id | Idle | Busy(tools/stream/review) | WaitingUser | Finalizing |
| --- | --- | --- | --- | --- |
| queue-add | 作 main | 可入队 | 回答槽优先 | N |
| steer | N | Y | 有限 | N |
| side | Y* | Y* | Y* | N |
| cancel | N | Y | Y | N |
| cautious/model/prompt | Y | 多 next-turn | Y | N |
| quit | Y | Y | Y | Y |
| compact-manual | Y | gate | Y | N |

\* 无第二个 in-flight side。细节服从 09 W1-A。

## 6. 退出码

| code | 含义 |
| ---: | --- |
| 0 | 成功 |
| 1 | 一般/业务错误 |
| 2 | 用法 |
| 3 | 配置无效 |
| 4 | 锁冲突 |
| 5 | 需 TTY 或缺 online-consent |
| 6 | NotFound / Resolver 否定 |
| 7 | 用户取消 |

stdout 主结果；stderr 诊断与 STATUS。

机器契约还补齐 `.context`、Context inspect/search/import/repair/refresh，以及每个动作的 args、admission state、confirm 与 typed result。这里的 CLI 等价投影包含 argv、chat 命令行和管理 REPL 命令行，不注册 daemon/IPC/RPC。

## 7. 完成度

- [x] 顶层/chat/context id 与拼写初表  
- [x] D-062 flag 候选  
- [x] 粗 state 表与退出码  
- [x] 机读 schema 生成
- [x] synthetic golden argv/chat/REPL fixtures
- [x] AR-P0-13 规格侧勾选；gate 仍等待 parser/非 TTY 与目标平台 proof
