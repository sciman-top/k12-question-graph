# 73 · C002S 广州物理正式化前审查闭环

C002S 是正式 C002 active 前的阻断性审查，不是激活任务。它把 `guangzhou-physics-full-research-package-2016-2025` 从“高质量候选包”推到“可审查、可阻断、可复跑”的状态，但在质量问题清零前仍保持 `candidate/pending_review/production_eligible=false`。

当前自动化入口：

```powershell
.\tools\run-c002s-formalization-precheck.ps1
```

该入口读取 `guangzhou-physics-full-research-package-2016-2025\csv`，每年抽样 3 道题，核对：

- 原题文本非空。
- 答案/评分来源存在。
- 年报页码锚点存在。
- 主知识点和主考点引用存在。
- 教材与课标映射引用存在。

报告写入 `docs/evidence/c002s-formalization-precheck-report.json`。当前抽样核对通过，但 `c003-quality-issue-registry.csv` 仍有 210 条年报页码/指标质量问题处于生产阻断状态，所以报告状态为 `blocked`，`productionActivationAllowed=false`。

后续归宿：

1. 逐条关闭 210 条年报质量问题，并保留人工核验证据。
2. 重新运行 C002S precheck，确认 `qualityIssuesOpenForProduction=0`。
3. 再运行 candidate DB dry-run、backup manifest、C002L review readiness 和 active guard。
4. 只有 C002S 与 C002L hard blockers 都清零后，才允许进入正式 C002 active 切换。

回滚方式：

```powershell
git restore --source=HEAD -- tools/run-gates.ps1 tools/README.md README.md docs/19_Roadmap.md docs/20_TaskBreakdown.md tasks/backlog.csv
git clean -f -- tools/c002s_formalization_precheck.py tools/run-c002s-formalization-precheck.ps1 docs/73_C002S_FormalizationPrecheck.md docs/evidence/c002s-formalization-precheck-report.json
```
