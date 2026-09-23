# Windows 上手

适用于 Windows XP SP3 到 Windows 11（32 位包），以及 Windows 7 SP1 以上（64 位包）。
yaca 目前是试用候选版，各目标系统的资格验证还在进行，待完成后才正式发布。

yaca 不需要安装。Lua、HTTPS 和证书都在 `yaca.exe` 里，机器上不用装 Lua、
Python、Node.js 或任何开发工具。

## 1. 解压并连接模型

1. 把压缩包解压到一个能写入的地方，比如 `C:\yaca` 或 U 盘。
   老系统上路径尽量用短的英文。
2. 打开 `cmd.exe`，运行：

   ```bat
   C:\yaca\yaca.exe
   ```

3. 第一次运行会进入设置向导，按提示填：

   | 项目 | 填什么 |
   |---|---|
   | Model name | 直接回车，用默认的 `Primary` |
   | Protocol | `openai-chat` 或 `anthropic-messages` |
   | Endpoint | 完整的接口地址，包含 API 路径，比如 `https://api.example.com/v1/chat/completions` |
   | Remote model | 服务商给的模型 ID，需要支持工具调用 |
   | Context length / Max output | 按模型实际能力填；不确定就用默认的 `32768` / `4096` |
   | Key | API key，输入时不显示；本地服务没有 key 可以留空 |

   最后输入 `APPLY` 保存。填错了可以输入 `.back` 回到上一项。

保存不联网，也不花额度。之后想改模型，运行 `yaca.exe --model-repl`。

> [!TIP]
> 需要代理的话，运行 `yaca.exe --config-repl`，在 `[Network]` 里设置 `ProxyUrl`。
> 连不上时别去关证书校验，yaca 自带的证书就是为老系统准备的。

## 2. 试一试

找一个可以随便折腾的文件夹：

```bat
mkdir C:\work\yaca-test
C:\yaca\yaca.exe C:\work\yaca-test
```

然后依次试：

1. 输入“只回复 OK”。收到回复，说明模型和网络都通了。
2. 让它列出当前目录、新建 `hello.txt` 再读出来。写文件前它会问你，核对内容后
   输入它显示的编号批准。
3. 让它执行 `ver`。执行命令前同样会先问你。
4. 输入 `.status` 记下对话的 hash，再输入 `.quit` 退出。
5. 运行 `C:\yaca\yaca.exe --continue <hash>`，确认历史还在，可以接着聊。

聊天里输入 `.help` 查看全部命令。

## 3. 检查整条链路（可选）

`--self-test` 分三步。第一步只检查本机，不联网：

```bat
C:\yaca\yaca.exe --self-test --through-stage 1
```

第二、三步会真正调用模型、消耗少量额度，所以要明确同意：

```bat
C:\yaca\yaca.exe --self-test --through-stage 2 --i-accept-online-self-test
C:\yaca\yaca.exe --self-test --through-stage 3 --i-accept-online-self-test
```

第二步检查连接、认证和流式回复；第三步对你的配置给出建议，不会自动修改。

## 通过 SSH 使用

在 Cygwin 的 SSH 会话里可以直接运行 `./yaca.exe`。这需要主机上的 Cygwin 自带
`stty.exe`，yaca 用它切换终端输入模式。普通管道不能用来聊天。

## 数据和升级

配置和对话都在 `yaca.exe` 旁边的 `__yaca__` 文件夹里，和你从哪里启动无关。
换电脑时连同这个文件夹一起拷走就行。

升级：退出所有 yaca，备份 `__yaca__`，再用新的 `yaca.exe` 覆盖旧的。
不要删掉 `__yaca__`。

std 和 full 包还带一个 `tools/` 文件夹（Python、SSH、curl 等），放在 `yaca.exe`
旁边即可，不需要改 PATH。

## 遇到问题

<details>
<summary><b>配置文件坏了</b></summary>

运行 `yaca.exe --config-repl`。配置无效时会进入修复模式，显示出错的行号：

- `replace 39`：替换第 39 行，然后输入完整的新行
- `insert 39` / `delete 39`：在第 39 行前插入 / 删除第 39 行
- `validate`：检查改好的配置
- 按提示输入 `save config-repair-N` 保存；`quit` 放弃

没改动的内容、注释和换行都会原样保留。

</details>

<details>
<summary><b>把对话移到别的文件夹，或导入别人的对话</b></summary>

运行 `yaca.exe --context-repl full` 打开对话管理器：

- `list`、`search <关键词>`、`inspect <hash>`：查看对话
- `rename <hash> <新名字>`、`delete <hash>`：改名、删除（删除不可撤销）
- `rebind <hash> <新文件夹>`：工作目录搬家后，把对话绑到新位置
- `import <XML 路径>`：导入从别的机器拷来的对话
- `repair <hash>`：对话文件损坏时，从自动保留的上一版恢复
- `export <hash>`：导出为 Markdown

改动类操作都会让你输入确认词（如 `REBIND <hash>`）后才执行。

</details>

<details>
<summary><b>模型没有完成任务就停了</b></summary>

开启了双重检查时，模型的收尾可能被审查退回。界面会提示你补充说明继续，或输入
`.cancel` 结束这一轮。`.status` 可以看到当前在等什么，`.details` 查看最近的错误信息。

</details>
