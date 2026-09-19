# C32 目标机资格执行手册（就绪件）

日期：2026-09-19。本手册与 `qualify_windows_target.sh` 是拿到目标机后的
立即可执行件。所有脚本已在 win2008（Server 2008）、evader-admin
（Windows 11）与 CentOS 7 容器上以同型流程预演通过；正式资格以目标机
上的实际执行与证据为准，一平台失败不能被另两平台替代。

## 1. Windows 目标（XP SP3 x86 → win32-x86；Win7 SP1 x64 → win64-x86_64）

前置：目标机可 ssh 登录；无其他 yaca 进程；离线段无需凭据。

```sh
# 构建机上（锁定源码缓存就绪）：
bash .tools/qualification/build_windows_candidate.sh <sources> <out-win32>   # XP 用
bash .tools/qualification/build_win64_candidate.sh   <sources> <out-win64>   # Win7 用

# 离线资格（自动：分发/解包/清单/version/Stage1/升级演练/卸载/残留）：
bash .tools/qualification/qualify_windows_target.sh <ssh-host> win32-x86 \
  <out>/yaca-0.1.0-preview-win32-x86.zip

# 在线段（需私有配置，输出进入证据目录）：
YACA_CONFIG_INI=<私有config.ini> \
  bash .tools/qualification/qualify_windows_target.sh <ssh-host> win32-x86 <zip>
```

随后在构建机补两步机器内验证：

- 零表面：目标机导出的 `02-file-list.txt` 喂给
  `check_zero_surface.verify(manifest, entries, target)`。
- 交互旅程（真实工具/审批/恢复）：`journey.py` 以
  `ssh -tt`+winpty（XP/Win7 同 win2008 方式）驱动；DeepSeek 配置经私有
  管道放置。

XP 专属注意：控制台走 winpty + `stty rows/cols`；SSH 保持真实 PTY；
断连时保留现场不要重试写操作。Win7 专属注意：默认 shell 若为
PowerShell，参照 evader-admin 的 `cmd /c`/保持 stdin 打开方式。

### 断电与文件系统矩阵（人工配合项）

XP/Win7 均需：安装目录所在卷为 NTFS；对 `__yaca__` 执行
写入中 kill（任务管理器结束 yaca.exe）→ 重启后 `--continue` 观察
保守恢复门禁；真实断电（拔电）至少一次，由用户在现场执行，
记录 `ver`、卷信息、恢复结果与出现的错误编号。

## 2. 裸机 CentOS 7（linux-x86_64 硬门）

在裸机（非容器）上以同等身份登录后：

```sh
# 资格构建（脚本自身强制 CentOS 7/glibc 2.17/GCC 4.8.5/5GiB/串行）：
bash .tools/qualification/build_linux_x86_64.sh <sources> \
  <yaca-source.tar.gz> <full-revision> <archive-sha256> <out>
python3 .tools/qualification/package_linux_zip.py <repo> <out> <sources>

# 干净机旅程（解包→零表面→version→stage1→卸载→无残留）：
bin/lua55 test/release/journeys.lua <repo> <out>/yaca-0.1.0-preview-linux-x86_64.zip \
  linux-x86_64 <scratch>

# 在线段：私有 config 放置后 stage2/3 + journey.py 交互旅程。
```

裸机专属项（容器证据不覆盖）：真实 3.10 内核下的 wait/console/process
行为；断电持久性（至少一次真实断电）；目标文件系统 replace/lock/崩溃
矩阵（kill -9 于提交窗口后 `--continue`）。

## 3. Gate R 发布提交

三目标全部通过后：`contracts/readiness.lua` 的 `gates.R.status` 改为
`passed`、`release_is_not_authorized` 撤除、manifest `release_state` 与
各 target `qualification` 同步更新，`check_documentation_truth` 的
pending 标记要求随之解除——以上必须是独立、可审计的发布提交
（保留名：`docs: publish qualified release evidence`）。
