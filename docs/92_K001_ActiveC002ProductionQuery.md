# 92 · K001 C002 active 生产查询接入

K001 把 C002 active v1 作为生产查询默认知识版本。它不执行新的 active switch，不修改旧 active 资产，只用只读数据库合同证明题库检索、组卷约束和学情分析都引用同一个 active version。

## 合同

- Gate: `tools/run-k001-active-c002-production-query-contract.ps1`
- Runner: `tools/k001_active_c002_production_query.py`
- Evidence: `docs/evidence/k001-active-c002-production-query-report.json`
- Active version: `junior-physics-guangzhou-source-derived-v1`
- Import key: `c002_candidate_import_guangzhou_physics_2016_2025_v1`
- Source batch: `guangzhou_physics_2016_2025`

## 验收

- C002 默认批次全部为 `active`。
- 默认批次无 `candidate`、无 `reviewed` 残留。
- 默认批次无 `pending_review` mappings。
- 至少一个 migration 为 `applied`。
- 来源资料批次为 33 份。
- 题库检索、组卷约束和学情分析三个 surface 都返回 `active_c002_v1` 和同一个 version reference。

## 边界

K001 是生产查询合同，不是新版本修订。后续教师修正、新教材、新课标或新考情必须进入 C002R：新 candidate 版本、映射、影响报告、审核、回滚演练和管理员 active 切换。

本合同不使用真实学生数据，不写生产历史学情，不调用外部 AI。

## 回滚

```powershell
git restore --source=HEAD -- README.md docs/20_TaskBreakdown.md tasks/backlog.csv tools/README.md tools/run-gates.ps1
git clean -fd -- tools/k001_active_c002_production_query.py tools/run-k001-active-c002-production-query-contract.ps1 docs/92_K001_ActiveC002ProductionQuery.md docs/evidence/k001-active-c002-production-query-report.json
```
