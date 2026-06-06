# 2026-06-06 规划治理优化落地证据

## Goal

把外部评审中提出的文档治理改进建议，落成项目内可执行入口：执行总控板、未决事项、角色审批矩阵、教师元数据预算、AI 信任合同、互操作边界和发布 go/no-go 卡，并接回 PRD、测试策略、路线图和发布清单。

## Changes

- 新增：
  - `docs/103_ExecutionControlBoard.md`
  - `docs/104_OpenQuestionsAndAssumptions.md`
  - `docs/105_RoleApprovalAndExceptionMatrix.md`
  - `docs/106_TeacherVisibleMetadataBudget.md`
  - `docs/107_AITrustAndReviewContract.md`
  - `docs/108_InteroperabilityProfileBoundary.md`
  - `docs/109_ReleaseGoNoGoCard.md`
- 更新：
  - `README.md`
  - `ALL_IN_ONE_EXECUTIVE_SPEC.md`
  - `docs/01_PRD.md`
  - `docs/04_TechnologyStack.md`
  - `docs/09_AI_ModelRouting_CostControl.md`
  - `docs/11_UX_Workflows.md`
  - `docs/17_SecurityPrivacyCompliance.md`
  - `docs/18_TestStrategy.md`
  - `docs/99_ProductizationFullRoadmapAndTaskPlan.md`
  - `docs/101_NonSiteCapabilityImplementationRoadmap.md`
  - `docs/templates/p006-release-decision-checklist.md`

## Verification

- `rg -n "103_ExecutionControlBoard|104_OpenQuestionsAndAssumptions|105_RoleApprovalAndExceptionMatrix|106_TeacherVisibleMetadataBudget|107_AITrustAndReviewContract|108_InteroperabilityProfileBoundary|109_ReleaseGoNoGoCard" README.md ALL_IN_ONE_EXECUTIVE_SPEC.md docs`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`
- `Import-Csv tasks/backlog.csv | Measure-Object`
- `Import-Csv tasks/completion-state-dashboard.csv | Measure-Object`

## Gate / N/A

- build：`gate_na`。reason：本轮只改 Markdown 文档与发布清单模板，不改应用代码、依赖、配置、schema 或运行路径。alternative_verification：运行 roadmap guard 与文档检索。evidence_link：本文件。expires_at：下一次代码、依赖、配置或门禁脚本改动。
- test：`gate_na`。reason：同上。alternative_verification：CSV 解析和文档入口检索。evidence_link：本文件。expires_at：下一次代码、依赖、配置或门禁脚本改动。
- hotspot：`gate_na`。reason：本轮无 API/UI/worker/data/AI/export/analysis 行为变化。alternative_verification：人工复核新增文档只改变治理入口，不改变运行行为。evidence_link：本文件。expires_at：下一次行为改动。

## Rollback

```powershell
git restore -- README.md ALL_IN_ONE_EXECUTIVE_SPEC.md docs/01_PRD.md docs/04_TechnologyStack.md docs/09_AI_ModelRouting_CostControl.md docs/11_UX_Workflows.md docs/17_SecurityPrivacyCompliance.md docs/18_TestStrategy.md docs/99_ProductizationFullRoadmapAndTaskPlan.md docs/101_NonSiteCapabilityImplementationRoadmap.md docs/templates/p006-release-decision-checklist.md
git clean -f -- docs/103_ExecutionControlBoard.md docs/104_OpenQuestionsAndAssumptions.md docs/105_RoleApprovalAndExceptionMatrix.md docs/106_TeacherVisibleMetadataBudget.md docs/107_AITrustAndReviewContract.md docs/108_InteroperabilityProfileBoundary.md docs/109_ReleaseGoNoGoCard.md docs/evidence/20260606-planning-governance-optimization.md
```
