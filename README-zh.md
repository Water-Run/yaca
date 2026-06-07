# yaca: Yet Another Coding Agent

[English](./README.md)

`yaca`是一个简单, 基础的Coding Agent, 以`GPL v3`协议开源于[GitHub](https://github.com/Water-Run/yaca).  
`yaca`使用`lua`+`c`开发, 简洁简单, 但有强大的兼容性 -- 它可以很好的在Windows XP或者Cent OS 7等老旧系统上运行, 且开箱即用.  

> 测试于: `Windows XP(VM)`, `Windows 7(VM)`, `React OS(VM)`, `Cent OS 7`, `Windows 11`, `Fedora 44`, `Debian 13`

## 安装  

从[GitHub Release]()上下载对应系统的压缩包. 解压缩.  
运行`INSTALL.bat`或`install.sh`, 根据向导继续.  
安装完成后, 你可以运行`yaca /v`验证安装, 应该输出:  

```cmd
yaca v26.01
Yet Another Coding Agent.
```

使用`yaca /h`获取帮助.  

> 不要手动修改安装目录下的`_yaca_`目录下的内容  

## 基本  

### 配置文件  

### 上下文机制  

## 使用前准备  

## 命令一览  

直接运行`yaca`会在目录下直接进入TUI. `yaca`二进制本身可接受以下参数:  

- `/h` / `/help`: 获取帮助  
- `/v` / `/version`: 输出版本  
- `/c` / `/config`: 输出配置
- `/r` / `/reset`: 重置  
- `/icc` / `/interactive-config-changer`: 交互式配置修改器  
- `/dc` / `/dir-context`: 输出目录下的上下文清单  
- `/gc` / `/global-context`: 输出全局上下文清单  
- `/st` / `/self-test`: 运行自检  

在使用`TUI`是, 可以使用`.`命令形式唤起命令. 这些包括:  

- `.quit`: 退出程序  
- `.context`: 切换目录下可用的上下文  
- `.archive`: 归档当前上下文  
- `.ping`: 检查模型的连通性
- `.index`: 覆写当前上下文的名称
- `.export`: 以Markdown格式输出当前上下文  
