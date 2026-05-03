# 59 · C002H Mapping Review Workbench Contract

## 1. 目的

C002H 先定义人工修订新旧对象映射关系的工作台合同。它解决的问题是：AI 可以先生成候选映射，但复杂映射最终需要教师、备课组或管理员用低负担方式决定。

本合同不实现完整 UI，不连接数据库，不激活生产资产；它先锁定后续 UI/API 必须支持的操作模型、影响预览、审核记录和回滚边界。

## 2. 工作台必须支持

- 只默认展示 `pending_review`、低置信度、高影响和复杂基数映射。
- 支持按影响从大到小、置信度从低到高排序。
- 并排展示旧对象、新对象、映射边、来源证据、影响预览、回滚预览和审核历史。
- 支持快捷操作：确认、拒绝、跳过、改目标、拆分、合并、创建迁移组、撤销。
- 支持批量确认，但只能用于低风险、高置信度、可回滚的一对一映射。
- 支持一对一、一对多、多对一、多对多。
- 多对多必须以 `mappingGroupId` / migration plan 分组显示，不能拆散成无业务语义的多条边。
- 修改映射前必须显示影响：题目绑定、标签、组卷约束、历史学情、自动可迁移数量、仍需人工确认数量。
- 进入正式 apply 前必须有 `beforeSnapshot`、`afterSnapshot` 和可撤销路径。

## 3. 人工决策边界

必须人工决定：

- 一对多、多对一、多对多。
- 高影响或低置信度。
- 影响历史学情、正式组卷、校级统计、评分标准、共享权限或隐私策略。

可批量确认：

- 一对一。
- 高置信度。
- 低影响。
- 可回滚。
- 不改变历史统计口径。

## 4. 验证

```powershell
.\tools\run-c002h-mapping-review-workbench-contract.ps1
```

验证内容：

- 必要筛选器、视图和快捷操作存在。
- review item 覆盖一对一、一对多、多对多。
- 复杂和高风险映射必须要求人工决策与审核理由。
- 每个 review item 都有 impact preview 与 rollback preview。
- 批量确认被限制在一对一低风险场景。
- 审核记录包含 reviewer、decision、reason、before/after snapshot。

`tools/run-c002-dry-run-suite.ps1` 和 `tools/run-gates.ps1` 已纳入该合同。

## 5. 回滚

```powershell
git restore --source=HEAD -- README.md docs/20_TaskBreakdown.md docs/56_C002_DryRunSuite.md tasks/backlog.csv tools/README.md tools/run-c002-dry-run-suite.ps1 tools/run-gates.ps1
git clean -f -- configs/domain-assets/c002h-mapping-review-workbench.sample.json tools/run-c002h-mapping-review-workbench-contract.ps1 docs/59_C002H_MappingReviewWorkbench.md
```
