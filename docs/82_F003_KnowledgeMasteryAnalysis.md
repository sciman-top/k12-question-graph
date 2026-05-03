# 82 · F003 得分率知识点分析

F003 建立 P5 学情分析的最小闭环：基于 synthetic 小题分和知识点映射，输出班级得分率、题目区分度、知识点掌握摘要和学生掌握摘要。

当前实现只验证 draft/test 合同，不使用真实学生数据，不暴露学生端，不写正式历史学情。

## 合同

- Gate: `tools/run-f003-knowledge-mastery-analysis-contract.ps1`
- Analyzer: `tools/f003_knowledge_mastery_analysis.py`
- Mode: `draft_test`
- `productionEligible`: `false`
- `realStudentDataUsed`: `false`
- `noProductionHistoryWrite`: `true`
- Evidence: `docs/evidence/f003-knowledge-mastery-analysis-report.json`
- Temp output: `tmp/f003-knowledge-mastery/f003-knowledge-mastery-summary.json`

## 验收

合同检查：

- 至少覆盖 2 个 synthetic 学生、2 道小题和 2 个知识点。
- 计算班级总分得分率。
- 计算知识点得分率、区分度、空白率和掌握分层。
- 输出至少 1 个薄弱知识点。
- 输出学生个人知识点掌握摘要。
- 明确引用当前 active 知识版本，但不改写任何正式历史学情。
- 所有统计结果保持 `draft_test` 和 `productionEligible=false`。

## 后续归宿

G001 在此基础上做自动备份到本机与共享目录演练。后续真实学情生产化需要单独处理真实学生数据授权、脱敏、备份恢复、历史口径冻结和权限边界。

## 回滚

```powershell
git restore --source=HEAD -- README.md docs/13_AssessmentAnalytics.md docs/19_Roadmap.md docs/20_TaskBreakdown.md tasks/backlog.csv tools/run-gates.ps1
git clean -f -- tools/f003_knowledge_mastery_analysis.py tools/run-f003-knowledge-mastery-analysis-contract.ps1 docs/82_F003_KnowledgeMasteryAnalysis.md docs/evidence/f003-knowledge-mastery-analysis-report.json
git clean -fd -- tmp/f003-knowledge-mastery
```
