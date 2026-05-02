# 52 · C002B Replacement Mapping Dry Run

## 1. 目的

C002B 将 draft bootstrap 与未来 source-derived formal assets 之间的替换关系做成 dry-run 合同。它不连接数据库、不写生产数据，只验证映射类型、自动/人工分流、影响报告和回滚要求。

## 2. 映射类型

支持：

- `equivalent`
- `split`
- `merge`
- `broader`
- `narrower`
- `renamed`
- `deprecated`

## 3. 自动化边界

可自动应用的条件：

- `mappingType` 是 `equivalent` 或 `renamed`。
- `confidence >= 0.95`。
- `impactLevel = low`。
- `reversible = true`。

其余情况必须进入 `pending_review`，包括一拆多、多合一、上位/下位迁移、废弃、低置信度、中高影响、不可回滚、影响历史学情或生产组卷规则的变更。

## 4. 验证

样例计划：

```text
configs/domain-assets/c002b-draft-formal-mapping.sample.json
```

验证命令：

```powershell
.\tools\run-c002b-replacement-mapping-contract.ps1
```

Full gate 已接入：

```powershell
.\tools\run-gates.ps1
```

验证内容：

- 样例保持 `dry_run`。
- asset status 和 authority 合法。
- 映射 source/target 均存在。
- 覆盖 `equivalent/split/narrower/renamed/deprecated`。
- 同时包含 `auto_apply` 和 `pending_review`。
- 影响报告包含题目绑定、标签绑定、组卷约束、学情报告和 fixture。
- rollback snapshot 必须存在。

## 5. 回滚

```powershell
git restore --source=HEAD -- tools/run-gates.ps1 tools/README.md tasks/backlog.csv docs/20_TaskBreakdown.md
git clean -f -- configs/domain-assets/c002b-draft-formal-mapping.sample.json tools/run-c002b-replacement-mapping-contract.ps1 docs/52_C002B_ReplacementMappingDryRun.md
```
