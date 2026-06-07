# 2026-06-07 · NS1308 release evidence pack 闭环

## Goal

把 `NS1308` 收口成一份统一的非现场 release evidence pack：

- installer dry-run
- Windows Service package
- backup / restore / upgrade rehearsal
- 权限审计 evidence
- 四入口现场 smoke checklist
- `P001 readiness pack`

## Changes

- `tools/run-ns1308-release-evidence-pack-contract.ps1`
  - 新增 `NS1308` 汇总 contract。
- `docs/evidence/20260607-ns1308-release-evidence-pack.json`
  - 生成当前 release evidence pack。
- `docs/103_ExecutionControlBoard.md`
  - 把当前主线从 `NS13` 收口转移到 `P001 / P005 / P006`。
- `docs/109_ReleaseGoNoGoCard.md`
  - 移除 “`NS1301-NS1308` 尚未完成” 的旧阻断口径。
- `tasks/non-site-implementation-plan.csv`
  - `NS1308 -> runtime_verified`
- `tasks/productization-roadmap.csv`
  - `NS1308 -> 已完成`
- `tasks/backlog.csv`
  - `NS1301-NS1308 -> 已完成`

## Verification

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-ns1308-release-evidence-pack-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-non-site-implementation-plan-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-automation-first-feature-contract-guard.ps1
```

结果：

- `NS1308`: `pass`
- `run-non-site-implementation-plan-guard.ps1`: `pass`
- `run-roadmap-guard.ps1`: `pass`
- `run-automation-first-feature-contract-guard.ps1`: `pass`

## Decision

- `NS13` 仓内非现场闭环已经完成。
- 当前主线转入 `P001` 及后续 `P005/P006`。
- `releaseReady`、`nonSiteValidated`、`P001 can close` 仍保持 `false`，不提前宣称现场或发布已完成。

## Risks

- 当前 evidence pack 仍不替代隔离机安装、打印、网络、权限域、现场教师观察和操作者签收。
- “卸载”目前是回滚/移除边界已文档化，不是真实现场卸载演练。

## Rollback

```powershell
git restore docs/103_ExecutionControlBoard.md docs/109_ReleaseGoNoGoCard.md tasks/backlog.csv tasks/non-site-implementation-plan.csv tasks/productization-roadmap.csv tools/run-gates.ps1 tools/README.md
Remove-Item -LiteralPath docs/evidence/20260607-ns1308-release-evidence-pack.json -Force
Remove-Item -LiteralPath docs/evidence/20260607-ns1308-release-evidence-pack-closure.md -Force
Remove-Item -LiteralPath tools/run-ns1308-release-evidence-pack-contract.ps1 -Force
```
