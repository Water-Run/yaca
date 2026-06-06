# yaca: Yet Another Coding Agent

[English](./README.md)

`yaca`是一个简单, 基础的Coding Agent, 以`GPL v3`协议开源于[GitHub](https://github.com/Water-Run/yaca).  
`yaca`使用`lua`+`c`开发, 简洁简单, 但有强大的兼容性 -- 它可以很好的在Windows XP或者Cent OS 7等老旧系统上运行, 且开箱即用.  

> 测试于: `Windows XP(VM)`, `Windows 7(VM)`, `Cent OS 7`, `Windows 11`, `Fedora 44`

## 安装

从[GitHub Release]()下载对应系统版本的`.zip`包, 解压.  
运行`INSTALL.bat`或`INSTALL.sh`.  
完成后, 在终端中验证:  

```cmd
yaca /v
```

有对应输出即完成安装.  

## 源码结构

- `src/c/app`: C入口代码.
- `src/c/core`: C运行时模块.
- `src/c/include`: C公共头文件.
- `src/lua`: Lua Agent脚本.
