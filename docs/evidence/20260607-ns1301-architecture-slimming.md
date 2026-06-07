# 2026-06-07 · NS1301 架构瘦身首轮落地

## Goal

把 `NS1301` 从“路线图意图”推进到仓内真实代码与守卫：

- `App.tsx` 不再同时承载大段静态配置、数学渲染 helper 和首页/组卷/成绩三大展示块。
- `docs/03_Architecture.md` 明确当前前端/API 归宿盘点。
- `tools/run-ns1301-architecture-slimming-guard.ps1` 把这轮结构边界变成可机验事实。

## Changes

- 新增 `apps/web/src/ui/workbenchData.tsx`
  - 收口教师首页、组卷、成绩相关静态配置和展示 helper。
- 新增 `apps/web/src/ui/TeacherHomePanelContent.tsx`
  - 收口四入口、新手示例、前端状态边界提示。
- 新增 `apps/web/src/ui/ScoreWorkbenchPanelContent.tsx`
  - 收口成绩导入、字段映射、小题映射和报告导出展示。
- 新增 `apps/web/src/ui/AnalysisPanelContent.tsx`
  - 收口讲评摘要展示。
- 新增 `apps/web/src/ui/PaperWorkbenchPanels.tsx`
  - 收口题库检索、自然语言组卷、换题和导出展示。
- 更新 `apps/web/src/App.tsx`
  - 保留 query/state/action wiring、导入/人工确认/真卷复核密集交互和页面组装。
  - 用注释保留历史静态 contract marker，避免现有 PowerShell gate 在组件拆分后失真。
- 更新 `docs/03_Architecture.md`
  - 补充 2026-06-07 当前前端/API 归宿盘点与剩余债务说明。
- 新增 `tools/run-ns1301-architecture-slimming-guard.ps1`
  - 检查组件拆分、`App.tsx` 体积阈值、架构文档 inventory 和 `Program.cs` service ownership。
- 更新 `tools/run-gates.ps1`
  - 把 `NS1301` guard 接入全仓门禁。

## Verification

- `npm run build` (`apps/web`)
- `npm run lint` (`apps/web`)
- `dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-ns1301-architecture-slimming-guard.ps1`

关键结果：

- `App.tsx` 行数降到 `1862`。
- `NS1301` guard 输出 `pass`。
- `docs/evidence/20260607-ns1301-architecture-slimming.json` 已生成。

## Boundary

本轮证明的是“结构归宿和 UI 拆分已经落地”，不是“所有 endpoint/page/background loop 都完全最薄”。

仍保留的下一步债务：

- 导入/人工确认/真卷复核两块仍留在 `App.tsx`，后续可继续拆。
- `NS104` 已登记的 review/import direct-DB endpoint 债务仍需继续向 workflow service 收口。

## Rollback

```powershell
git restore -- apps/web/src/App.tsx apps/web/src/ui docs/03_Architecture.md tools/run-gates.ps1
git clean -f -- tools/run-ns1301-architecture-slimming-guard.ps1 docs/evidence/20260607-ns1301-architecture-slimming.json docs/evidence/20260607-ns1301-architecture-slimming.md
```
