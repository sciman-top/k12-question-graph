# 2026-06-06 · NS1306 / NS1307 运行闭环

## Goal

把 `NS1306` 与 `NS1307` 从路线图/任务描述层推进到仓内可执行 gate，并让实现清单状态与实际脚本/evidence 对齐。

## Changes

- 新增 `configs/agent-tool-orchestration.allowlist.json`
- 新增 `tools/run-ns1306-agent-tool-orchestration-contract.ps1`
- 新增 `tools/run-ns1307-golden-visual-llm-security-gate.ps1`
- 调整 `tools/run-gates.ps1`
  - `C002Q` 提前到 `L007` 之前，避免读取旧 dry-run 证据
  - 接入 `NS1306`
  - 接入 `NS1307`
- 更新 `tools/README.md`
- 回写：
  - `tasks/productization-roadmap.csv`
  - `tasks/non-site-implementation-plan.csv`

## Verification

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-ns1306-agent-tool-orchestration-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-ns1307-golden-visual-llm-security-gate.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-automation-first-feature-contract-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gate-group.ps1 -Group roadmap
```

结果：

- `NS1306`: `pass`
- `NS1307`: `pass`
- `run-roadmap-guard.ps1`: `pass`
- `run-automation-first-feature-contract-guard.ps1`: `pass`
- `run-gate-group.ps1 -Group roadmap`: `pass`

## Decision

- `tasks/non-site-implementation-plan.csv` 中：
  - `NS1306 -> runtime_verified`
  - `NS1307 -> runtime_verified`
- `tasks/productization-roadmap.csv` 中：
  - `NS1306 -> 已完成`
  - `NS1307 -> 已完成`
- `tasks/backlog.csv` 暂不改状态。

理由：本轮已经形成真实可执行脚本和 evidence，符合实现清单的 `runtime_verified` 口径；但 `NS13` 主线和 `P001/P006` 高层发布链还未完成，不宜提前把更高层任务全部关闭。

## Risks

- `NS1306` 当前是 allowlist 与 boundary guard，不代表已有真正的 agent runtime 执行框架。
- `NS1307` 当前是组合 gate，不代表已经做了真实多模型/多 provider 生产试点。
- `run-gates.ps1` 顺序已修正，但 full gate 尚未完整重跑。

## Gate

- `build`: `gate_na`
- `test`: 脚本级验证已执行
- `contract/invariant`: 已执行 `run-roadmap-guard` 与 `automation-first guard`
- `hotspot`: `NS1306/NS1307` 边界已显式留痕

## Rollback

```powershell
git restore configs/agent-tool-orchestration.allowlist.json tools/run-ns1306-agent-tool-orchestration-contract.ps1 tools/run-ns1307-golden-visual-llm-security-gate.ps1 tools/run-gates.ps1 tools/README.md tasks/productization-roadmap.csv tasks/non-site-implementation-plan.csv
Remove-Item -LiteralPath docs/evidence/20260606-ns1306-agent-tool-orchestration.json -Force
Remove-Item -LiteralPath docs/evidence/20260606-ns1307-golden-visual-llm-security.json -Force
Remove-Item -LiteralPath docs/evidence/20260606-ns1306-ns1307-runtime-closure.md -Force
```
