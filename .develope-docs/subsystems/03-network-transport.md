# 03 网络传输

状态：候选

## 职责

提供与模型厂商无关的 HTTP 传输：URL、headers、请求体、代理、CA、TLS、超时、重试、状态码、响应体和可取消请求。

## 初始方向

优先利用随包 curl，使 TLS 和代理能力不依赖旧操作系统自带组件。调用 curl 的细节必须封装在本系统内。

流式响应已经是正式配置面，不再询问“首版是否流式”。每个 Model 的 `Streaming` 具有三态：

- `force`：端点不能完成流式协议时明确失败，不能静默改成非流式。
- `try`：按协议规则尝试；只有在尚未产生规范响应事件且能够证明是“不支持流式”时才允许受控降级。
- `off`：明确请求非流式。

传输仍只产生 bytes/header/status/cancel 等事件；SSE/JSON 和 Model finish reason 由 06 号系统解释。

## 边界

- 不理解 OpenAI 或 Anthropic JSON；由 06 号子系统承担。
- 不直接读取全局配置；调用者传入已验证的传输选项。
- 不把密钥写入命令行、普通日志或错误文本。
- Runtime 自己启动 curl 时使用 02 号结构化 process port，不经过模型 raw shell。
- 选择 Model 已经授权 provider 网络；Permission 中未来 direct-tool network 与 raw shell 属于另一权限域。

## 旧系统重点

- Windows XP 系统证书与 SNI/TLS 能力不足，必须明确随包 CA 与 curl 的契约。
- CentOS 7 系统 OpenSSL 不能成为隐式依赖。
- 代理环境变量大小写和 no-proxy 语义。

## 请求、attempt 与重试边界候选

一个逻辑 Model request 有稳定本地 ID，每次 curl/网络尝试另有 attempt ID。自动重试不能只按错误码决定：

| 失败阶段 | 候选行为 |
| --- | --- |
| DNS/connect/TLS，确认请求体尚未发送 | 受 Model/turn 预算限制重试 |
| 请求体可能已发送，但没有收到 HTTP response | 标记 outcome unknown；没有 provider 幂等保证时不自动重放 |
| 明确 429/503 与合法 `Retry-After`，且尚无规范响应事件 | 可做受限退避 |
| 已收到任何 text/tool/reasoning/usage 等规范事件 | 禁止整请求重放 |
| SSE/JSON 畸形、资源超限或用户取消 | 不重试同一请求 |

connect、first-event、idle 和 total deadline 需要分开；单个 Model 的 retry 配置不能突破 Runtime 的 turn 总 deadline 和硬资源上限。

## 秘密和资源上限

“Key 不进 argv/日志”仍不足以实现。curl 的 stdin 不能同时无歧义承载 secret config 和 request body，候选需要用目标平台原型比较：config 走 stdin/body 走私有 temp、body 走 stdin/secret config 走私有 temp，或窄 libcurl bridge。任何方案都要定义最小文件权限、取消、崩溃残留、启动回收和错误脱敏；详见 `AQ-277`、`AQ-278`。

header、压缩体、解压后 body、单 SSE event、tool arguments、总响应和待消费缓冲分别有硬上限。达到上限时返回 typed limit error，不能先无限装入 Lua table 再交给 TUI 截断。

## 待讨论

v0.1 的精确 HTTP/curl profile、Key 传递路线、代理/CA 优先级、redirect 凭据规则、重试阶段表与所有资源上限。具体毫秒和字节值由 XP/CentOS 基准校准，不由负责人凭感觉填写。
