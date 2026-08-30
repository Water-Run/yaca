# 旧环境网络与 HTTPS 底层审查

更新日期：2026-08-30

状态：**Win32/XP 交叉构建与静态导入审计通过，真实 XP HTTPS 资格待执行；Release Gate R 关闭**

## 审查边界

本审查只处理 yaca 自己的 Model 传输闭包：锁定的 curl、Mbed TLS、CA bundle、代理 TLS、DNS、CRT/API 导入以及 native stdin carrier。它不把 raw shell 的外部网络访问变成 yaca 网络能力，也不开放 direct HTTP Tool、自动更新或系统 CA 回退。

静态交叉构建回答“候选能否由当前锁定源码生成，PE 头和显式导入是否已经排除已知 Vista+ 依赖”；它不能回答“同一最终包是否真的在 XP SP3 上完成 DNS、TLS 握手、证书验证、代理、流式响应和取消”。后一个问题仍必须由 C32 的真实目标机证据回答。

## 上游事实与选择

1. curl 8.19.0 把 Windows 最低版本提高到 Vista；对应变更移除了 XP 分支并采用 SRW lock、condition variable、`InitializeCriticalSectionEx`、BCrypt、Vista 计时/接口假设。来源：[curl 8.19.0 changes](https://curl.se/ch/8.19.0.html)、[remove Windows XP support commit](https://github.com/curl/curl/commit/b17ef873ae2151263667f4b6fb6abfe337e687dc)。
2. 当前锁定的 Mbed TLS 3.6.7 Windows entropy poll 直接调用 `BCryptGenRandom`。Microsoft 把 `BCryptGenRandom` 的最低客户端列为 Vista，因此未经适配不能成为 XP TLS 后端。来源：[Mbed TLS 3.6.7 entropy source](https://github.com/Mbed-TLS/mbedtls/blob/mbedtls-3.6.7/library/entropy_poll.c)、[BCryptGenRandom requirements](https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/nf-bcrypt-bcryptgenrandom)。
3. Microsoft 把 `CryptAcquireContextW` 和 `CryptGenRandom` 的最低客户端列为 Windows XP；`CryptGenRandom` 文档将其定义为生成加密随机数据。因此 XP compatibility branch 采用 CryptoAPI，并在所有成功/失败路径释放 provider。来源：[CryptAcquireContextW](https://learn.microsoft.com/en-us/windows/win32/api/wincrypt/nf-wincrypt-cryptacquirecontextw)、[CryptGenRandom](https://learn.microsoft.com/en-us/windows/win32/api/wincrypt/nf-wincrypt-cryptgenrandom)。
4. 不回退到较旧 curl 二进制。项目继续锁定 curl 8.21.0 源码并维护窄补丁，以避免为了 XP 引入旧版本已经公开的安全缺陷；版本升级时必须重做基文件哈希、补丁、导入和目标机证据。来源：[curl 8.18.0 vulnerabilities](https://curl.se/docs/vuln-8.18.0.html)、[curl 8.21.0 vulnerabilities](https://curl.se/docs/vuln-8.21.0.html)。
5. MinGW 的 `msvcrt` 路线使用系统 `msvcrt.dll`，适合不预装 UCRT 的旧 Windows；但现代头文件/导入库可让源码无意导入 XP 系统 CRT 未证明存在的新 `_s` 符号。因此最终 PE 导入表而非编译成功是资格输入。来源：[mingw-w64 UCRT vs MSVCRT](https://github.com/mingw-w64/mingw-w64/blob/master/mingw-w64-doc/howto-build/ucrt-vs-msvcrt.txt)。

## 锁定补丁

### curl 8.21.0

`release/patches/curl-8.21.0-winxp.patch` 绑定源压缩包 SHA-256 和九个上游基文件哈希，仅适用于 `win32-x86`：

- 最低 `_WIN32_WINNT` 降到 `0x0501`，但 XP profile 硬拒绝 IPv6 与 threaded resolver；Win64/Linux 不继承该限制。
- XP 使用 C11 atomic simple lock、`InitializeCriticalSection` 和 blocking resolver；Vista+ 仍使用上游 SRW/condition 路径。
- Windows RNG 从 BCrypt 改为 CryptoAPI，configure 不再无条件链接 `bcrypt`。
- XP 计时恢复 `GetTickCount` 分支；Vista+ 保留 QPC。
- XP 避免动态导入 `freopen_s`、`mbstowcs_s`、`wcstombs_s`、`wcscpy_s`、`wcsncpy_s`，以有界转换/复制和旧 CRT 调用替代；Vista+ 保留上游安全 CRT 路径。
- XP 不声明 `HAVE_IF_NAMETOINDEX`。

### Mbed TLS 3.6.7

`release/patches/mbedtls-3.6.7-winxp.patch` 绑定源压缩包 SHA-256 和两个上游基文件哈希，仅适用于 `win32-x86`：

- entropy provider 改为 `CryptAcquireContextW` + 分块 `CryptGenRandom`，错误路径不泄漏 provider，输出指针按块推进。
- XP 的格式化回退到旧 CRT `vsnprintf`，并保留上游的显式 NUL 终止检查；Vista+ 仍使用 `vsnprintf_s`。

两个补丁的路径、用途、目标、补丁 SHA-256、源包 SHA-256 和每个基文件 SHA-256 同时镜像在 `release/dependencies.lock`、`release/manifest.lua` 和 release planner 的内置 pin 中；任一字段漂移均 fail closed。SBOM 与 component/license manifest 记录补丁来源。

## HTTPS 安全策略

- 发行 curl 只开放 HTTP/HTTPS，禁用 ambient curl config、netrc、自动 redirect、curl 自身 retry、系统/搜索 CA、压缩与持久网络状态。
- HTTPS 和 HTTPS proxy 都必须验证证书，使用同一随包 CA bundle；不存在 `insecure` 或 native CA fallback。
- TLS 最低为 1.2，语义为 TLS 1.2 或更新版本；XP 系统 TLS 能力不参与握手。
- secret config 只经 trusted component 的匿名 stdin pipe 进入 curl；request body 和 response header 使用 owner-only、create-new、identity-checked 临时文件。该内部进程不经过 XP `cmd.exe`、POSIX shell、argv secret 或 ambient proxy 环境。
- HTTP endpoint 是既有显式产品能力，绝不由 HTTPS 失败自动降级；其明文风险由 Model 配置负责展示。

## 2026-08-30 可重复候选证据

`.tools/qualification/build_win32_xp_https_candidate.sh` 从锁定压缩包重新开始，顺序执行：

1. 资源门检查且全程 `-j1`；
2. 校验两个 archive、两个 patch 和 11 个基文件的 SHA-256；
3. `patch --fuzz=0` 应用补丁；
4. 用 i686 MinGW、`_WIN32_WINNT=0x0501`、PE subsystem 5.01 静态构建 Mbed TLS 与 curl；
5. 对最终 `curl.exe` 执行 object format、subsystem、DLL closure、required import 与 banned import 审计。

本次全新复现结果：

```text
status=PASS
target=win32-x86
minimum-image-subsystem=Windows-5.01
evidence=cross-build-and-static-import-audit
protocols=http,https
resolver=blocking
ipv6=false
entropy=CryptoAPI-CryptGenRandom
runtime_qualified=false
real_xp_https_proof=pending
release_authorized=false
```

最终候选只显式依赖 `ADVAPI32.dll`、`KERNEL32.dll`、`WS2_32.dll` 和 `msvcrt.dll`。已自动拒绝 BCrypt/bcrypt DLL、SRW/condition API、`InitializeCriticalSectionEx`、`if_nametoindex`、UCRT/API-set、六个新 `_s` CRT 导入以及一组常见 Vista+ 文件/取消 API。

这仍是**候选证据**。没有把当前开发机/Wine 行为写成 XP 运行证据，也没有把 PE 5.01 头写成完整 API 兼容证明。

## C32 必须补齐的真实目标证据

- 同一最终 Win32 zip 在 XP SP3 x86 上从干净目录启动，验证 `curl -V` 闭包、DNS、HTTP、TLS 1.2 公网/本地 fixture、正确 CA、错误 CA、过期/错 host/未知根。
- 显式 HTTP proxy 与 HTTPS CONNECT proxy：代理证书成功、代理证书失败、407、代理 secret 脱敏、`NO_PROXY` 精确语义。
- 旧 DNS/IPv4、连接超时、握手超时、断流、服务端 close、时钟明显错误、CA 文件缺失/权限拒绝与错误分类。
- SSE 双管道 backpressure、取消、进程树/句柄清理、临时文件权限/残留与 XP CMD 特殊字符路径；内部 component 始终不经过 CMD。
- 同一闭包分别在 Win7 SP1 x64 和 CentOS 7 x64 重建、运行；不得用 Win32 静态结果替代。

只有上述目标证据与完整 yaca package journey 同时通过，才可把 `runtime_qualified`、target qualification 和 Release Gate R 改为 true。
