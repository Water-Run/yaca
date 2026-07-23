# 03 网络传输

状态：产品契约已确认；curl 接入、资源限额与旧平台行为待技术证明

## 职责

提供与模型厂商无关的 HTTP 传输：URL、headers、请求体、代理、CA、TLS、超时、重试、状态码、响应体和可取消请求。`openai-chat` 与 `anthropic-messages` 的 wire JSON、流式事件和 finish reason 由 06 号系统解释。

## 已确认的兼容性基线

- 每个平台发行包携带经过该平台验证的 curl 与 CA 基线，使 HTTPS 不依赖 Windows XP/Vista 的系统 TLS 能力，也不把 CentOS 7 的系统 OpenSSL 当作隐式前提。
- Model 中显式配置的 `https://` 与 `http://` endpoint 都允许使用；HTTP 可以承载 Key、Prompt 和回复，这是为旧系统、本地网关和现有内网服务保留的明确兼容路线。
- 每次保存一个 HTTP endpoint，以及把现有 endpoint 改为任何 HTTP endpoint（包括 HTTP 改到另一个 HTTP origin）时，配置界面都必须清楚说明 Key、Prompt 与回复将以明文经过对应链路。成功保存后的每次模型请求不重复询问，但 self-test 和详情始终如实显示传输安全状态。
- Runtime 永不把 HTTPS 自动降级成 HTTP，也不因 TLS 失败猜测另一个 scheme、端口或 endpoint。
- stunnel 只是用户可以在 yaca 之外安装和配置的兼容方案，不随包、不自动安装，也没有 `UseStunnel` 特殊模式。只有当前实际选择的随包 curl/CA TLS 路线不可用或无法连接目标 endpoint 时，self-test 才可以建议安装/配置 stunnel；不能只因运行于 XP 等旧系统、或系统 TLS 本身较旧就提示。用户随后把 Model endpoint 显式指向本机 stunnel 监听地址即可。
- 全局代理继续只服务 yaca 自己的 Model HTTP。redirect 只自动跟随 same-origin；cross-origin 必须通过修改 Model 配置建立新的显式 endpoint，不能在一次请求中携带凭据悄然跳转。
- v0.1 不提供 direct Web/HTTP/network tool。模型获准使用 raw shell 后启动 curl 等外部程序，属于宽 `Shell` 动作，不复用本系统的 Model 凭据、代理或传输授权。

## 流式配置

流式响应是正式能力。每个 Model 的 `Streaming` 具有三态：

- `force`：端点不能完成对应 adapter 的流式协议时明确失败，不能静默改成非流式。
- `try`：按协议规则尝试；只有尚未产生任何 canonical response event，并且能够证明端点不支持流式时，才允许受控降级一次。
- `off`：明确请求非流式。

传输层只产生 bytes/header/status/cancel 等事件；SSE/JSON 和 Model finish reason 由 06 号系统解释。

## 边界

- 不理解 OpenAI 或 Anthropic JSON；由 06 号子系统承担。
- 不直接读取全局配置；调用者传入已经验证、冻结的 Model 与全局 Network 快照。
- 不把 Key 或代理凭据写入 argv、普通日志、错误文本或 Context XML。
- Runtime 自己启动 curl 时使用 02 号结构化 process port，不经过模型 raw shell。
- 选择 Model 已经授权该 Model 的 provider 网络请求；Permission 不重复增加一个 Model-network capability。

## request、attempt 与重试边界

一个逻辑 Model request 有稳定本地 ID，每次 curl/网络尝试另有 attempt ID。自动重试不能只按错误码决定：

| 失败阶段 | 已确认行为 |
| --- | --- |
| DNS/connect/TLS，确认请求体尚未发送 | 可在该 Model retry 与 turn 硬预算内重试 |
| 请求体可能已发送，但没有收到 HTTP response | 标记 outcome unknown；没有 provider 幂等保证时不自动重放 |
| 明确 429/503 与合法 `Retry-After`，且尚无 canonical response event | 可做受限退避 |
| 已收到任何 text/tool/reasoning/usage 等 canonical event | 禁止整请求重放 |
| 流式协议/JSON 畸形、资源超限或用户取消 | 不重试同一请求 |

connect、first-event、idle 和 total deadline 分开计算。单个 Model 的 retry 配置不能突破 request、turn 和进程级不可关闭硬上限；用户配置只能在发布允许范围内收紧这些上限。

## 秘密与资源上限

curl 的 stdin 不能同时无歧义承载 secret config 和 request body，因此 Key/body 的具体传递路线必须由 Win32 x86、Win64 x64 与 Linux x86_64 原型证明后冻结。候选可以是私有短寿命临时输入、窄 libcurl bridge 或等价方案；无论选择哪条，都必须证明最小文件权限、取消、崩溃残留回收和错误脱敏，且不得把 Key 放进 argv。

header、压缩体、解压后 body、单个流式 event、tool arguments、总响应和待消费缓冲分别有不可关闭硬上限。达到上限返回 typed limit error，不能先无限装入 Lua table 再由 TUI 截断。

## 仍需技术证明

剩余工作不再是产品选择：冻结各平台 curl/CA 版本与最小功能集、Key/body 传递路线、proxy/CA 解析细节、deadline/重试数值和所有字节上限，并在目标旧系统上验证 HTTP、HTTPS、显式代理、外部 stunnel 路线、取消、断流和凭据脱敏。
