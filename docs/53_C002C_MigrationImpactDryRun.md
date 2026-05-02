# 53 · C002C Migration Impact Dry Run

## 1. 目的

C002C 将 draft -> formal 映射对题库和衍生数据的影响做成 dry-run 报告。它不连接数据库、不改生产数据，只验证哪些对象可自动更新，哪些必须人工审核，哪些历史结果必须冻结。

## 2. 覆盖对象

- `question_primary_knowledge`
- `question_secondary_knowledge`
- `tag_binding`
- `search_index`
- `assembly_constraint`
- `analysis_metric`
- `fixture_expected_mapping`

## 3. 自动化边界

自动更新只允许来自 C002B 的 `auto_apply` 映射，并且动作只能是：

- `update_binding`
- `rebuild_derived_index`
- `update_fixture_expectation`

`pending_review` 映射只能进入：

- `hold_for_review`
- `freeze_historical_snapshot`

历史学情指标不得自动改写；如果知识点迁移会影响历史分析口径，必须冻结历史快照并生成新版本分析。

## 4. 验证

样例计划：

```text
configs/domain-assets/c002c-migration-impact.sample.json
```

验证命令：

```powershell
.\tools\run-c002c-migration-impact-contract.ps1
```

Full gate 已接入：

```powershell
.\tools\run-gates.ps1
```

验证内容：

- 样例保持 `dry_run`。
- 引用的 C002B replacement plan 一致。
- 七类影响对象全覆盖。
- `auto_apply` 只执行低风险自动动作。
- `pending_review` 必须人工审核或冻结历史。
- summary 数量与逐项影响一致。
- rollback snapshot 必须存在。

## 5. 回滚

```powershell
git restore --source=HEAD -- tools/run-gates.ps1 tools/README.md tasks/backlog.csv docs/20_TaskBreakdown.md
git clean -f -- configs/domain-assets/c002c-migration-impact.sample.json tools/run-c002c-migration-impact-contract.ps1 docs/53_C002C_MigrationImpactDryRun.md
```
