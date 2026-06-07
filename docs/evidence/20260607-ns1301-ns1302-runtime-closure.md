# 2026-06-07 · NS1301 / NS1302 运行闭环

## Goal

把 `NS1301` 与 `NS1302` 从任务描述推进到仓内可执行证据：

- `NS1301`：教师工作台结构瘦身、页面拆分、service 边界 inventory。
- `NS1302`：Windows Service 主形态 + 管理员服务控制面板合同。

## Changes

- `apps/web/src/App.tsx`
  - 保留状态、query、动作编排和 section 组装。
- `apps/web/src/ui/workbenchData.tsx`
  - 收口教师首页、组卷、成绩相关静态配置与 helper。
- `apps/web/src/ui/TeacherHomePanelContent.tsx`
- `apps/web/src/ui/ScoreWorkbenchPanelContent.tsx`
- `apps/web/src/ui/AnalysisPanelContent.tsx`
- `apps/web/src/ui/PaperWorkbenchPanels.tsx`
- `apps/web/src/ui/ServiceControlPanel.tsx`
  - 新增管理员服务控制面板合同，只覆盖服务状态、诊断、配置、备份恢复、升级演练和打开 Web。
- `apps/web/src/ui/AdminGovernancePanels.tsx`
  - 挂载 `ServiceControlPanel`，不把教师工作流塞进控制面板。
- `apps/web/src/App.css`
  - 新增 `service-control-panel` 相关布局与样式。
- `docs/03_Architecture.md`
  - 回写当前前端/API 归宿盘点。
- `docs/04_TechnologyStack.md`
  - 说明当前仓内用 `service-control-panel` contract 固化控制面板信息结构。
- `tools/run-ns1301-architecture-slimming-guard.ps1`
- `tools/run-ns1302-service-control-panel-contract.ps1`
- `tools/run-gates.ps1`
  - 接入 `NS1301` / `NS1302`。
- `tasks/non-site-implementation-plan.csv`
  - `NS1301 -> runtime_verified`
  - `NS1302 -> runtime_verified`
- `tasks/productization-roadmap.csv`
  - `NS1301 -> 已完成`
  - `NS1302 -> 已完成`

## Verification

```powershell
npm --prefix apps/web run build
npm --prefix apps/web run lint
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-ns1301-architecture-slimming-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-ns1302-service-control-panel-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-automation-first-feature-contract-guard.ps1
```

结果：

- `NS1301`: `pass`
- `NS1302`: `pass`
- `run-roadmap-guard.ps1`: `pass`
- `run-automation-first-feature-contract-guard.ps1`: `pass`

## Decision

- `tasks/non-site-implementation-plan.csv`
  - `NS1301 -> runtime_verified`
  - `NS1302 -> runtime_verified`
- `tasks/productization-roadmap.csv`
  - `NS1301 -> 已完成`
  - `NS1302 -> 已完成`
- `tasks/backlog.csv`
  - 暂不改状态，继续作为 `NS13` 主线待办入口。

理由：本轮已经形成真实可执行 guard、具体 evidence 和任务清单回写，符合实现清单的 `runtime_verified` 口径；但 `NS13` 主线和 `P001/P006` 现场发布链仍未闭合，不宜把 backlog 顶层任务提前全部关闭。

## Risks

- `NS1302` 当前是管理员控制面板合同，不代表已经在独立目标机上真实安装/启动 Windows Service。
- 控制面板当前先以仓内管理员 staging surface 固化信息结构，未来切独立 Windows shell 时仍需复用同一字段/动作/evidence 边界。

## Rollback

```powershell
git restore apps/web/src/App.tsx apps/web/src/ui docs/03_Architecture.md docs/04_TechnologyStack.md tasks/non-site-implementation-plan.csv tasks/productization-roadmap.csv tools/run-gates.ps1
Remove-Item -LiteralPath docs/evidence/20260607-ns1301-architecture-slimming.json -Force
Remove-Item -LiteralPath docs/evidence/20260607-ns1302-service-control-panel.json -Force
Remove-Item -LiteralPath docs/evidence/20260607-ns1301-ns1302-runtime-closure.md -Force
Remove-Item -LiteralPath tools/run-ns1301-architecture-slimming-guard.ps1 -Force
Remove-Item -LiteralPath tools/run-ns1302-service-control-panel-contract.ps1 -Force
```
