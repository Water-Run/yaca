# yaca: Yet Another Coding Agent

[English](./README.md)

`yaca`是一个简单, 单Agent的基础Coding Agent, 以`GPL v3`协议开源于[GitHub](https://github.com/Water-Run/yaca).  
`yaca`使用`lua`开发, 和琳然满目的其它强大的Coding Agent不同的是, 它可以很好的在Windows XP或者Cent OS 7等老旧系统上运行, 且开箱即用.  

## 安装  

从[GitHub Release](https://github.com/Water-Run/yaca/releases)上下载对应系统的压缩包. 解压缩.  
运行`INSTALL.bat`或`install.sh`, 根据向导继续.  
安装完成后, 你可以运行`yaca --version`验证安装, 应该输出:  

```cmd
yaca v0.1.0
Yet Another Coding Agent.
```

使用`yaca --help`获取帮助.  
作为一个Coding Agent, 配置模型是必须的. 使用`yaca --model-repl`进入模型管理, 选择`Add Model`添加你的模型, 已经预设如下快速配置:  

- `DeepSeek`  
- `MiniMax`(`Token Plan China`, `Token Plan Global`, `API China`, `API Global`)  
- `MiMo`(`Token Plan China`, `Token Plan Singapore`, `Token Plan Europe`, `API`)  
- `Zhipu GLM`(`Coding Plan China`, `Coding Plan Global`, `API`)  
- `Kimi`(`Code`, `API`)  
- `Qwen`  
- `OpenAI`  
- `Anthropic`  
- `Gemini`  
- `Grok`  
- `Poe`  
- `Ollama`  

> 不要手动修改安装目录下的`_yaca_`目录下的内容  

## 配置  

`yaca`使用位于`__yaca__`下的`config.ini`作为配置文件.  
配置文件中有详细的注释. 你可以依照修改, 然后运行`yaca --self-test`进行自检. 使用`yaca --show-config`输出配置; `yaca --reset-config`进行还原.  
更推荐的配置修改方式是使用`yaca --interactive-config-changer`进行交互式修改. 对于模型管理, 使用`yaca --model-repl`.  
配置文件的第一项是进入对话时的默认模型. 上下文会保留退出前最后使用的模型, 如果此模型已经失效, 将回归至默认模型. 在对话中, 可以使用`.model`进行模型切换.  

## 上下文机制  

`yaca`使用位于`__yaca__`下的, 结合实际对应位置的树形结构下的`[命名名称].xml`作为上下文文件.  
上下文文件详细的存储了和对应对话有关的一切元数据, 可作日志使用. 上下文包括命名名称, 和结合目录计算的哈希. 使用`yaca --dir-context`输出目录下的上下文清单, `yaca --global--context`输出全局的上下文清单.  
使用`yaca --continue [哈希值]`可跳转至对应的对话, 包括非当前目录下的对话(当启用`AutoJumpToDir`时). 也可以使用`yaca --continue 对话名称`直接跳转至对应对话, 不过这仅支持当前目录下的上下文. 当对话名称非常刚好的和哈希名一样时, 跳转至对应哈希名称. `yaca --delete-context`用于删除上下文, 对应逻辑和`continue`一致. `yaca --rename-context`重命名上下文也是如此.  
更简易的上下文管理方式可以使用交互式的`yaca --manage-context`, 包括展示, 删除和重命名等.  

## 权限机制  

`yaca`的权限组位于配置文件的`Permission`下, 预设了四个权限: `Std`, `Cautious`, `TrustMeBro`和`Readonly`. 名称可在配置中自定义, 不代表权限的真实功能.  
和模型配置一样, 配置文件的第一项是进入对话时的默认权限. 上下文会保留退出前最后使用的权限, 如果此模型已经失效, 将回归至默认权限. 在对话中, 可以使用`.permission`进行模型切换.  

## 命令一览  

直接运行`yaca`会在目录下直接进入TUI. `yaca`二进制本身可接受以下参数:  

- `--help` / `-h`(Unix) / `/h`(Windows): 获取帮助  
- `--version` / `-v`(Unix) / `/v`(Windows): 输出版本  
- `--show-config` / `-sc`(Unix) / `/sc`(Windows): 输出配置  
- `--reset-config` / `-rc`(Unix) / `/rc`(Windows): 重置配置  
- `--interactive-config-changer` / `-icc`(Unix) / `/icc`(Windows): 交互式配置修改器  
- `--dir-context` / `-dc`(Unix) / `/dc`(Windows): 输出目录下的上下文清单  
- `--global-context` / `-gc`(Unix) / `/gc`(Windows): 输出全局上下文清单  
- `--delete-context` / `-dc`(Unix) / `/dc`(Windows): 删除上下文  
- `--rename-context` / `-rc`(Unix) / `/rc`(Windows): 重命名上下文  
- `--manage-context` / `-mc`(Unix) / `/mc`(Windows): 上下文管理器  
- `--self-test` / `-st`(Unix) / `/st`(Windows): 运行自检. 当LLM可用时, 可使用LLM进入深度检查.  
- `--continue` / `-c`(Unix) / `/c`(Windows): 以某上下文恢复会话  
- `--set-default-permission` / `-sdp`(Unix) / `/sdp`(Windows): 设置默认权限  
- `--set-default-model` / `-sdm`(Unix) / `/sdm`(Windows): 设置默认模型  
- `--model-repl` / `-mr`(Unix) / `/mr`(Windows): 模型添加, 测试和删除REPL  

在使用`TUI`是, 可以使用`.`命令形式唤起命令. 这些包括:  

- `.quit`: 退出程序  
- `.context`: 切换目录下可用的上下文. 直接`.context`进入选单, 或`.context 全局上下文哈希`/`.context 当前目录上下文名称`  
- `.archive`: 归档当前上下文(随后进入一个新的干净会话). `.archive rename`同时触发自动重命名  
- `.ping`: 检查模型的连通性. 默认测试当前模型, 或`.ping 模型名称`测试其他模型  
- `.index`: 覆写当前上下文的名称(可选自动和手动). `.index 手动重命名名称`直接重命名  
- `.compact`: 触发上下文压缩  
- `.model`: 切换模型. 直接`.model`进入选单, 或`.model 模型名称`进行切换  
- `.permission`: 切换权限. 直接`.permission`进入选单, 或`.permission 权限名称`进行切换  
- `.status`: 当前情况说明, 如已用上下文等  
- `.delete`: 删除本对话上下文  
