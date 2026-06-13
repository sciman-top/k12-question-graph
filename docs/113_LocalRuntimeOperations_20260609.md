# 113 · 本地运行模型与日常运维入口

日期：2026-06-09。

## 1. 这份文档解决什么问题

这份文档只回答一个高频问题：

> 现在本仓本地联调的推荐运行模型到底是什么？Web 和 API 分别怎么拉起、怎么看是不是还活着、何时只是本地联调而不是发布闭环？

它不是安装器 runbook，也不是现场发布手册。它只覆盖开发机 / 验证机上的日常本地运行。

## 2. 当前推荐运行模型

当前最实用的默认模型是：

1. `Web` 可以长期常驻。
2. `API` 按需拉起，也可以在联调时一起常驻。
3. 判断“可用”优先看状态命令和 `ready` 字段，不靠感觉。
4. 页面能打开，不等于发布完成；现场闭环仍受 `REAL005 not_closed` 和 `P001` 阻断。

默认地址：

- Web：`http://127.0.0.1:5173/`
- API：`http://127.0.0.1:5275`
- API readiness：`http://127.0.0.1:5275/health/ready`

## 3. 最常用命令

### 3.1 Web

```powershell
.\tools\start-local-web.ps1
.\tools\start-local-web.ps1 -Status
.\tools\start-local-web.ps1 -Restart
.\tools\start-local-web.ps1 -Stop
```

默认行为：

- 固定监听 `127.0.0.1:5173`
- 后台启动 Vite
- PID 与日志写入 `logs/dev-web/`
- 若 `apps/web/node_modules` 缺失，会先补依赖再启动

### 3.2 API

```powershell
.\tools\start-local-api.ps1
.\tools\start-local-api.ps1 -Status
.\tools\start-local-api.ps1 -Restart
.\tools\start-local-api.ps1 -Stop
```

默认行为：

- 固定监听 `127.0.0.1:5275`
- 后台启动 ASP.NET Core API
- PID 与日志写入 `logs/dev-api/`
- 优先读取本机 `KQG_CONNECTION_STRING`
- 若未提供连接串，则回退到 `PGPASSWORD` / 脚本参数拼接本地 PostgreSQL 连接
- 2026-06-09 起，`tools/run-gates.ps1` 若检测到这个标准本地 API 正在占用默认 Release 输出，会在 full gate 期间自动暂停并在结束后恢复，不再要求人工先停后启

若完全没有数据库凭据，脚本会直接报错，而不是假启动。

## 4. 状态输出怎么读

两个脚本的 `-Status` / 默认启动输出都会返回 JSON。日常最关键的是下面几个字段：

- `status`
- `ready`
- `url`
- `listenerPid`
- `stdoutLog`
- `stderrLog`

常见状态语义：

- `started`
  - 本次执行刚拉起成功，且 ready 检查已通过。
- `already_running`
  - 端口上已有目标服务在监听；这是正常复用，不是报错。
- `running`
  - 用 `-Status` 查询时发现服务正在监听。
- `stopped`
  - 当前没在跑，或已经执行了 `-Stop`。
- `starting_or_failed`
  - 进程已尝试启动，但在等待窗口内没通过 ready 检查；优先看 `stderrLog`。

判断顺序建议：

1. 先看 `status`。
2. 再看 `ready` 是否为 `true`。
3. 若不正常，再看 `stdoutLog` / `stderrLog`。
4. 不要只看 PID 文件是否存在。

## 5. 两种常见联调场景

### 5.1 只开 Web

适用场景：

- 看教师壳布局
- 看默认四入口
- 做不依赖数据库的页面检查

此时要接受的真实行为：

- 页面可以打开
- 教师四入口可见
- 页面会退回本地证据预览或离线友好状态
- 这不代表 API 故障，更不代表前端坏了

### 5.2 Web + API 一起开

适用场景：

- 看真实联调状态
- 看数据库队列、审核区、服务状态、分析工作区
- 做浏览器 walkthrough 或联调 smoke

2026-06-09 已验证的可见结果：

- 页面顶部显示 `服务状态 正常`
- 真卷复核区可切到 `数据库队列 / 24 题待复核`
- 教师四入口都能落到主要工作区
- 控制台错误为 `0`

对应证据：

- `docs/evidence/20260609-teacher-visible-walkthrough.md`

## 6. 日常排查入口

先看状态：

```powershell
.\tools\start-local-web.ps1 -Status
.\tools\start-local-api.ps1 -Status
```

再看日志：

- Web stdout：`logs/dev-web/vite.out.log`
- Web stderr：`logs/dev-web/vite.err.log`
- API stdout：`logs/dev-api/api.out.log`
- API stderr：`logs/dev-api/api.err.log`

再看 API readiness：

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:5275/health/ready
```

如果还是不确定，再打开浏览器看：

- 是否能打开 `http://127.0.0.1:5173/`
- 页面顶部是 `服务状态 正常` 还是离线友好状态
- 控制台是否出现错误

## 7. 真实边界

这套运行模型能证明的是：

- 本地开发与联调入口已经收口，不需要每次手工拼启动命令。
- Web / API 的活性、ready 状态、日志路径和 PID 路径都有稳定入口。
- 教师可见主界面已经可以在本机真实联调。

这套运行模型不能证明的是：

- 不能据此宣称现场发布闭环完成。
- 不能据此宣称 `REAL005` 已关闭。
- 不能据此替代隔离机、打印机、域权限、真实网络和操作者签收证据。

## 8. 推荐搭配阅读

1. `docs/112_CurrentClosureStatus_20260609.md`
2. `docs/evidence/20260609-teacher-visible-walkthrough.md`
3. `docs/109_ReleaseGoNoGoCard.md`
4. `tasks/live-pilot-closeout-plan.csv`
