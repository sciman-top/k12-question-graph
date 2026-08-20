# 发布 Go / No-Go 卡

本卡只负责当前发布裁决；任务状态来自 `tasks/backlog.csv`，repo-side closure 来自 `docs/CurrentClosureStatus.md`，current evidence 来自 `docs/evidence/index.json`。

## 当前裁决

**No-Go**

原因：

- `REAL005=not_closed`，`fullClosureAllowed=false`。
- P001–P006 均为待办。
- 隔离机安装、学校网络、打印、权限域、真实教师使用和操作者签字未完成。
- 自动提炼仍为 `candidate/pending_review/productionEligible=false`，没有因 repo-side 通过而切换 production active。

## 发布前必须关闭

1. P001：隔离机安装、备份恢复、权限审计和四入口 smoke。
2. P002：授权或脱敏材料的教师代理试点。
3. P003：现场数据授权、支持负责人和回滚责任。
4. P004：真实教师操作、耗时、卡点和回滚记录。
5. P005：反馈进入 keep / modify / defer / do_not_do 决策。
6. P006：签字后的正式发布裁决与 tag candidate。

最小执行顺序见 `tasks/live-pilot-closeout-plan.csv`。

## 发布前验证

The rollback window must be explicit in the signed release decision and remain linked to a tested recovery entry.

- `tools/run-verification.ps1 -Profile Quick`
- 获得当前任务授权后运行 `tools/run-verification.ps1 -Profile Release -AuthorizeStateful`
- backup manifest 可验证，隔离 restore 成功，migration/数据库形状/FileStore 对账无意外变化
- `docs/evidence/index.json` 无悬空 current path
- REAL005 current evidence 仍如实反映现场关闭状态

Quick/Release 的 repo-side pass 只是发布输入，不会自动改变本卡裁决。

## Go 条件

只有同时满足以下条件，才允许把本卡改为 `Go`：

- P001–P006 在 backlog 和 closeout plan 中全部关闭；
- 真实环境、操作者、输入、时间和签字证据齐全；
- backup/restore、隐私、权限、教师效率和回滚均通过；
- REAL005 current evidence 允许完整关闭；
- 发布负责人明确签署 release decision。

当前未满足，故保持 **No-Go**。
