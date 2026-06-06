# 2026-06-06 ADR-014 工程终态与技术栈边界落地证据

## Goal

把“本项目最佳工程终态、默认技术栈、默认架构与明确不建议提前做的方向”从长评审结论，沉淀成可长期引用的 ADR 和短清单入口。

## Changes

- 新增 `docs/decisions/ADR-014-recommended-engineering-endstate-and-stack-boundary.md`
- 新增 `docs/110_EngineeringEndStateChecklist.md`
- 更新：
  - `docs/04_TechnologyStack.md`
  - `docs/26_References.md`
  - `README.md`
  - `ALL_IN_ONE_EXECUTIVE_SPEC.md`

## Verification

- `rg -n "ADR-014|110_EngineeringEndStateChecklist|推荐工程终态|默认技术栈边界" README.md ALL_IN_ONE_EXECUTIVE_SPEC.md docs`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`

## Gate / N/A

- build：`gate_na`。reason：本轮只新增/更新 Markdown 文档与 ADR，不改应用代码、依赖、配置、schema 或运行行为。alternative_verification：检索入口与 roadmap guard。evidence_link：本文件。expires_at：下一次代码、依赖、配置或门禁脚本改动。
- test：`gate_na`。reason：同上。alternative_verification：引用现有 full gate 基线并运行 roadmap guard。evidence_link：本文件。expires_at：下一次代码、依赖、配置或门禁脚本改动。
- hotspot：`gate_na`。reason：本轮没有新增 API/UI/worker/data/AI/export/analysis 行为变化，只固化长期决策。alternative_verification：人工复核 ADR 只约束长期边界，不改当前运行路径。evidence_link：本文件。expires_at：下一次行为改动。

## Rollback

```powershell
git restore -- docs/04_TechnologyStack.md docs/26_References.md README.md ALL_IN_ONE_EXECUTIVE_SPEC.md
git clean -f -- docs/decisions/ADR-014-recommended-engineering-endstate-and-stack-boundary.md docs/110_EngineeringEndStateChecklist.md docs/evidence/20260606-adr014-engineering-endstate.md
```
