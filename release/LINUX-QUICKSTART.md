# Linux 上手

适用于 x86_64 Linux，最低 CentOS 7（glibc 2.17）。yaca 目前是试用候选版，
目标系统的资格验证还在进行，待完成后才正式发布。

yaca 不需要安装。Lua、HTTPS 和证书都在 `yaca` 里，系统上不用装 Lua、Python、
Node.js 或开发工具。

## 1. 解压并连接模型

```sh
unzip <下载的压缩包>.zip -d ~/yaca
~/yaca/yaca
```

第一次运行会进入设置向导：

| 项目 | 填什么 |
|---|---|
| Model name | 直接回车，用默认的 `Primary` |
| Protocol | `openai-chat` 或 `anthropic-messages` |
| Endpoint | 完整的接口地址，包含 API 路径，比如 `https://api.example.com/v1/chat/completions` |
| Remote model | 服务商给的模型 ID，需要支持工具调用 |
| Context length / Max output | 按模型实际能力填；不确定就用默认的 `32768` / `4096` |
| Key | API key，输入时不显示；本地服务没有 key 可以留空 |

最后输入 `APPLY` 保存。保存不联网，也不花额度。之后想改模型，运行
`~/yaca/yaca --model-repl`；代理在 `--config-repl` 的 `[Network]` 里设置 `ProxyUrl`。

## 2. 试一试

```sh
mkdir -p ~/yaca-test
~/yaca/yaca ~/yaca-test
```

1. 输入“只回复 OK”。收到回复，说明模型和网络都通了。
2. 让它列出当前目录、新建 `hello.txt` 再读出来。写文件前它会问你，核对后批准。
3. 输入 `.status` 记下 hash，`.quit` 退出。
4. 运行 `~/yaca/yaca --continue <hash>`，确认可以接着聊。

聊天里输入 `.help` 查看全部命令。

## 3. 检查整条链路（可选）

```sh
~/yaca/yaca --self-test --through-stage 1
~/yaca/yaca --self-test --through-stage 2 --i-accept-online-self-test
~/yaca/yaca --self-test --through-stage 3 --i-accept-online-self-test
```

第一步只检查本机；后两步会调用模型、消耗少量额度。

## 数据和升级

配置和对话都在 `yaca` 旁边的 `__yaca__` 文件夹里。升级时退出所有 yaca，
备份 `__yaca__`，再替换 `yaca`。不要删掉 `__yaca__`。

想在任何目录直接输入 `yaca`，把解压目录加进 `PATH` 即可。

配置文件坏了、对话要搬家或导入时，见
[Windows 上手](WINDOWS-QUICKSTART.md#遇到问题)，命令是一样的。
