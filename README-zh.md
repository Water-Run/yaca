# YACA - Yet Another Coding Agent  

*[English](./README.md)*  

`yaca`是一个半自动, 人在回路的轻量编码辅助Agent. 这意味着, 和`OpenCode`, `ClaudeCode`不同, `yaca`需要你在编码过程中更多的参与.  
`yaca`的开发源于个人Vibe Coding经验所得, 创作的起点在于, 现成的全自动Coding Agent往往消耗许多对话在与当前任务无关的部分上, 比如问题分析和工具链调用. 这会导致数倍的Token消耗增加, 同时挤压上下文空间, 且任务完成往往和你的需求并不那么一致.  
`yaca`基于这样的一个信条: 更多的人类参与, 更少的Token消耗, 更好的任务完成.  

## 安装  

`yaca`发布在[PyPi](), 使用`pipx`进行安装:  

```bash
pipx install yaca
```

验证安装:  

```bash
yaca --version
```
