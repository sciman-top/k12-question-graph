# 学科激活工作台 v0

## 目标

把新学科知识体系激活流程从“脚本 + 模板 + runbook”收敛成教师能理解的 Web 工作台。

v0 只做只读状态和复核入口，不在教师端直接执行正式激活。正式激活仍由管理员/代理通过 `tools/run-domain-asset-activation.ps1`、备份、证据报告和回滚说明完成。

## 教师侧原则

教师不需要理解 `ImportKey`、`MaterialBatchKey`、`migration`、`backup manifest` 或 evidence JSON。

教师只需要看到：

- 当前学科、地区和年份范围。
- 系统整理出的候选数量。
- 是否还有阻断问题。
- 需要复核哪些内容。
- 复核后由谁确认正式启用。

## UI 合同

页面标记为 `data-flow="subject-activation-workbench"`。

必须保留以下边界：

- `data-contract="teacher-review"`：教师只做候选复核。
- `data-contract="role-split"`：教师复核与管理员激活分层。
- `data-contract="no-direct-activation"`：教师端不暴露直接激活动作。
- `data-contract="rollback-ready"`：管理员确认前必须看到备份和回滚说明。

禁止在教师端出现直接执行动作：

- `data-action="apply-activation"`
- `data-action="run-activation-script"`

## 验证

```powershell
.\tools\run-subject-activation-workbench-ui-contract.ps1
```

该守卫已纳入 `tools/run-gates.ps1`。
