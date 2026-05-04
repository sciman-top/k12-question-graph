# K004 Historical Version Explanation

## Goal

K004 gives teachers a read-only explanation for legacy questions, legacy papers, and historical learning-analysis reports when their original knowledge version differs from the current active version.

The contract preserves the historical view and resolves the current mapping without rewriting old questions, papers, analysis reports, or production history.

## API Contract

- Endpoint: `POST /knowledge-version-explanations/resolve`
- Fixture: `configs/domain-assets/k004-historical-version-explanation.sample.json`
- Verification: `tools/run-k004-historical-version-explanation-contract.ps1`
- Evidence: `docs/evidence/k004-historical-version-explanation-report.json`

The endpoint accepts synthetic artifact metadata:

- `artifactType`: `question`, `paper`, or `analysis_report`
- `artifactId`
- `historicalKnowledgeStableId`
- `historicalKnowledgeVersion`
- `currentKnowledgeVersion`
- `mappingType`: for example `renamed`, `split`, or `deprecated`
- `currentKnowledgeStableIds`
- `affectsHistoricalAnalysis`

The response is explicitly non-production:

- `productionEligible = false`
- `readOnly = true`
- `realStudentDataUsed = false`
- `writesProductionHistory = false`
- `frozenHistoricalView = true`

## Teacher Workflow Boundary

普通教师看到的是一句解释：旧题、旧卷或旧学情报告保留当时的知识版本，同时显示当前版本的映射结果。教师不需要理解 migration、active switch、rollback snapshot 或知识资产内部状态。

当 `affectsHistoricalAnalysis = true` 时，历史学情结论保持冻结；系统只展示当前版本映射解释，不回写旧统计口径。

## Rollback

回滚优先使用 Git revert K004 变更。K004 不执行数据库写入、不修改 active 知识资产、不改写生产历史，因此无需额外 DB snapshot 或 active switch 回滚。
