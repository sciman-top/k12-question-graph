# 73 · C002S 广州物理正式化前审查闭环

C002S 是正式 C002 active 前的阻断性审查，不是激活任务。它把 `guangzhou-physics-full-research-package-2016-2025` 从“高质量候选包”推到“可审查、可阻断、可复跑”的状态。质量问题清零后，C002S 可通过；但候选资产、映射、migration 和审核队列未清零前，仍必须保持 `candidate/pending_review/production_eligible=false`，不得直接 active。

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

当 `guangzhou-physics-full-research-package-2016-2025\quality-review-complete-csv-package` 存在时，该入口会先调用 `tools/merge-c003-quality-review-package.ps1`，把完整 C003 `csv` 包与质量复核完成包合并到 `D:\KQG_Data\candidate_packages\c003-merged-quality-review-2016-2025`，再执行审查。该合并包保留核心本体/映射文件，并用质量复核包覆盖题目、答案、年报观察和质量问题证据。

报告写入 `docs/evidence/c002s-formalization-precheck-report.json`。当前抽样核对通过，210 条年报页码/指标质量问题已清零，报告状态为 `pass`，`productionActivationAllowed=true`。这只表示 C002S 阻断已解除，不表示正式 C002 active 已完成。

后续归宿：

1. 使用合并包生成 cleaned C002 candidate 输入。
2. 运行 candidate DB dry-run，确认 source hash 对齐和 active/reviewed overwrite guard。
3. 生成 backup manifest 后只执行 candidate import apply。
4. 运行 C002L readiness 和 C002M 审核决策合同。
5. 只有 C002S 与 C002L hard blockers 都清零后，才允许进入正式 C002 active 切换。

回滚方式：

```powershell
git restore --source=HEAD -- tools/c002s_formalization_precheck.py tools/run-c002s-formalization-precheck.ps1 tools/README.md README.md docs/19_Roadmap.md docs/20_TaskBreakdown.md docs/73_C002S_FormalizationPrecheck.md tasks/backlog.csv docs/evidence/c002s-formalization-precheck-report.json docs/evidence/c002-candidate-import-report.json docs/evidence/c002l-candidate-review-readiness-report.json docs/evidence/c002m-candidate-review-apply-contract-report.json
git clean -f -- tools/merge-c003-quality-review-package.ps1
```
