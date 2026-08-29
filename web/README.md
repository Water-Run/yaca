# web/ — 设计预留目录（非 v0.1 产品面）

**状态：空预留。2026-08-29 已移除历史页面/server/config 占位；不要在这里实现可运行的 Web 服务或页面。**

## 现行决定

| 决定 | 含义 |
| --- | --- |
| D-044 | yaca **v0.1** 为 terminal-only；核心 zip **零 Web 表面** |
| D-058 | 允许为未来 **本机本地 Web** 产品族做 **设计预留**；实现未授权 |

## 两条未来产品线

| 产品线 | 浏览器意图 | 服务端栈（D-058） |
| --- | --- | --- |
| `yaca-web` | 可宽于 IE6（仍保守） | **Java 8** |
| `yaca-ie6` | **有意** 兼容 IE6 | **PHP 5.4** |

设计正文在：

- [`.develope-docs/web-tracks/README.md`](../.develope-docs/web-tracks/README.md)
- [`.develope-docs/web-tracks/yaca-web.md`](../.develope-docs/web-tracks/yaca-web.md) — 本机 Web 主线 / Java 8
- [`.develope-docs/web-tracks/yaca-ie6.md`](../.develope-docs/web-tracks/yaca-ie6.md) — IE6 线 / PHP 5.4
- [`.develope-docs/subsystems/17-web.md`](../.develope-docs/subsystems/17-web.md) — 排除记录与重开门

## 本目录允许什么

- 仅本 README（或未来指向设计文档的索引）。
- 在 Web 决策包完成并获准实现之后，再按 `yaca-web` / `yaca-ie6` 分轨放入真实资源。

## 本目录禁止什么

- 可启动的 server、路由、假配置、未审计框架依赖。
- 被核心 `main.lua` / 安装脚本 / 自检误加载的资源。
- 把“目录存在”写成“功能已支持”。

历史占位（空 `page.htm`、`server.lua`、`yaca-web.conf` 等）若仍存在，一律视为待清理的非产品文件，不构成契约。
