# 2026-06-06 项目导航总览落地证据

## Goal

新增一个统一导航入口，把 `PRD / roadmap / OQ / release card / ADR-014 / references manifest` 等关键文档串起来，减少后续“这类问题先看哪份文档”的沟通成本。

## Changes

- 新增 `docs/111_ProjectNavigationOverview.md`
- 更新：
  - `README.md`
  - `ALL_IN_ONE_EXECUTIVE_SPEC.md`
  - `docs/103_ExecutionControlBoard.md`

## Verification

- `rg -n "111_ProjectNavigationOverview|项目导航总览|导航入口" README.md ALL_IN_ONE_EXECUTIVE_SPEC.md docs/103_ExecutionControlBoard.md docs/111_ProjectNavigationOverview.md`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`

## Gate / N/A

- build：`gate_na`。reason：本轮只新增/更新导航文档，不改应用代码、依赖、配置、schema 或运行行为。alternative_verification：文档检索与 roadmap guard。evidence_link：本文件。expires_at：下一次代码、依赖、配置或门禁脚本改动。
- test：`gate_na`。reason：同上。alternative_verification：引用既有 full gate 基线并运行 roadmap guard。evidence_link：本文件。expires_at：下一次代码、依赖、配置或门禁脚本改动。
- hotspot：`gate_na`。reason：本轮没有 API/UI/worker/data/AI/export/analysis 行为变化，只增加导航层入口。alternative_verification：人工复核本轮仅改变文档导航，不改行为边界。evidence_link：本文件。expires_at：下一次行为改动。

## Rollback

```powershell
git restore -- README.md ALL_IN_ONE_EXECUTIVE_SPEC.md docs/103_ExecutionControlBoard.md
git clean -f -- docs/111_ProjectNavigationOverview.md docs/evidence/20260606-project-navigation-overview.md
```
