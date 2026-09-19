# Linux 首次使用

本预览包是 `linux-x86_64`，按 CentOS 7（glibc 2.17、GCC 4.8.5 锁定
工具链）基线构建。程序、Lua 5.5、XML 解析器、HTTPS 客户端和 CA 均随包
提供，不需要安装 Lua、Python、Node.js 或开发工具。资格按 D-072（2026-09-19）于三个实测环境通过；裸机 CentOS 7 断电与文件系统资格属后续增强。

## 解压与配置

1. 将完整 zip 解压到有写权限的本地目录，例如 `/opt/yaca` 或
   `~/yaca`；普通用户建议放在自己的家目录内。
2. 运行 `./yaca --version`，应输出 `yaca 0.1.0 (linux-x86_64)`。
3. 运行 `./yaca --model-repl`，按提示依次填写：

   - Model name：直接回车使用 `Primary`。
   - Protocol：`openai-chat` 或 `anthropic-messages`。
   - Enable：`yes`。
   - Endpoint：服务商的**完整请求 URL**，包含 API 路径；不能只填域名。
   - Remote model：服务商给出的模型 ID，需要支持原生工具调用。
   - Context length / Maximum output tokens：按服务商支持范围填写；
     默认预算 `32768` / `4096`，不要超过模型实际限制。
   - Key：API key，输入隐藏。没有 key 的本地服务可留空。
   - 最后输入 `APPLY` 保存。

配置器离线工作，保存本身不联网。不要向普通聊天输入 API key。配置位于
`yaca` 可执行文件旁的 `__yaca__/config.ini`，可重新运行 `--model-repl`
修改。其他配置字段用 `--config-repl` 编辑；代理在 `[Network]` 的
`ProxyUrl` 配置，证书校验使用随包 CA，不要关闭校验。

## 开始使用

选择一个普通、可写、可丢弃的测试工作目录：

```sh
mkdir -p ~/yaca-test
./yaca --self-test --through-stage 1
./yaca ~/yaca-test
```

在交互界面依次确认：

1. 输入“只回复 OK”，收到真实模型回复，证明配置和 HTTPS 链路可用。
2. 请求列出当前目录、创建 `hello.txt`、读取它；写操作出现确认时核对
   内容并按显示的编号批准。
3. 输入 `.status` 记下 Context hash；`.quit` 退出。
4. `./yaca --continue <hash>` 检查历史并继续对话。

在线自检逐次显式同意：

```sh
./yaca --self-test --through-stage 2 --i-accept-online-self-test
./yaca --self-test --through-stage 3 --i-accept-online-self-test
```

`.help` 查看聊天命令，`--help` 查看命令行说明；`.details` 查看最近
诊断。双重检查终审未通过时按提示输入澄清或 `.cancel`，不会显示任务
完成。

## 数据、升级和退出

数据始终放在 `yaca` 可执行文件旁的 `__yaca__`，不随工作目录变化。
升级前退出所有 yaca 进程，另行备份 `__yaca__`，再解压替换程序；不要
删除数据目录。首版没有自动更新和通用撤销；保存结果 unknown 时停止
操作并保留现场。`Install.sh` 只把解压目录加入当前 shell 的 `PATH`。

## 开发机复现

在具备锁定源码缓存与 CentOS 7（glibc 2.17、GCC 4.8.5）环境的主机运行：

```sh
bash .tools/qualification/build_linux_x86_64.sh \
  <sources> <yaca-source-archive> <revision> <archive-sha256> <output>
python3 .tools/qualification/package_linux_zip.py <repo> <output> <sources>
```

输入逐个校验锁定 SHA-256；编译串行并经内存门禁。构建成功不打开
Release Gate R；裸机 CentOS 7 断电/文件系统资格仍属 C32。
