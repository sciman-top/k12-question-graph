# 2026-05-09 P0-live 自动连续推进记录

## Scope
- 仓库：`D:\CODE\k12-question-graph`
- 分支：`main`（起始状态 `main...origin/main`）
- 目标：按 backlog 从首个待办任务开始，连续执行 P0-live preflight 链并校验全量门禁基线。

## Executed
1. `tools/run-p001-live-pilot-readiness-preflight-contract.ps1`
2. `tools/run-p002-teacher-proxy-pilot-preflight-contract.ps1`
3. `tools/run-p003-onsite-pilot-admission-preflight-contract.ps1`
4. `tools/run-p004-onsite-pilot-round1-preflight-contract.ps1`
5. `tools/run-p005-pilot-feedback-backlog-preflight-contract.ps1`
6. `tools/run-p006-release-decision-preflight-contract.ps1`
7. `tools/run-c002-dry-run-suite.ps1`
8. `tools/run-roadmap-guard.ps1`
9. `tools/run-gates.ps1`

## Result
- P001~P006 preflight 均 `status=pass`，依赖链完整。
- P001~P006 当前 `status=待办` 保持不变，原因是这些脚本均为 `mode=preflight_only`，不执行现场或发布动作。
- 全量门禁 `tools/run-gates.ps1` 通过，未发现代码级回退。

## Blocking Facts
- `P001` 仍要求隔离机器真实部署预演证据（安装向导、备份恢复、权限审计、四入口 smoke）。
- `P002~P006` 依次被上一环节现场证据阻断；阻断属于试点执行事实，不是代码缺陷。

## Evidence
- 预检证据模板：
  - `docs/templates/p001-live-pilot-release-checklist.md`
  - `docs/templates/p002-teacher-proxy-pilot-checklist.md`
  - `docs/templates/p003-onsite-pilot-admission-checklist.md`
  - `docs/templates/p004-onsite-pilot-round1-checklist.md`
  - `docs/templates/p005-pilot-feedback-backlog-checklist.md`
  - `docs/templates/p006-release-decision-checklist.md`
- 既有 preflight 证据路径（由脚本返回）：
  - `docs/evidence/20260505-p001-live-pilot-readiness-preflight.md`
  - `docs/evidence/20260505-p002-teacher-proxy-pilot-preflight.md`
  - `docs/evidence/20260505-p003-onsite-pilot-admission-preflight.md`
  - `docs/evidence/20260505-p004-onsite-pilot-round1-preflight.md`
  - `docs/evidence/20260505-p005-pilot-feedback-backlog-preflight.md`
  - `docs/evidence/20260505-p006-release-decision-preflight.md`

## Rollback
- 本轮未改动业务代码、配置契约或数据库结构。
- 如需回退，仅需还原本次 evidence 文档改动（Git revert/reset 对应提交）。
