# 20260528 NS003 模块归宿盘点

## Goal

为非现场能力落地建立模块归宿，避免后续实现继续散落为“有 evidence、没有稳定模块边界”的状态。

## Ownership Map

| 能力域 | 主归宿 | 协作归宿 | 证据与门禁 |
|---|---|---|---|
| 运行底座、health、配置、EF Core、核心 endpoint | `apps/api` | `tools`、`docs/evidence` | `dotnet build`、`tools/run-gates.ps1` |
| 教师四入口、题库、组卷、成绩、后台隔离面板 | `apps/web/src/App.tsx`、`apps/web/src/api`、`apps/web/src/ui`、`apps/web/src/state` | `tools/run-i*.ps1`、`tools/run-s*.ps1` | `npm run build --prefix apps/web`、UI contract |
| 导入/审核/组卷/成绩应用服务 | `apps/api/Application/Workflows` | `apps/api/Program.cs`、`tests`、`tools/run-s002*.ps1` | workflow contract、thin endpoint guard |
| DB 模型、migration、查询面 | `apps/api/Domain`、`apps/api/Data` | `tools/*_contract.ps1`、`docs/evidence` | migration smoke、DB-backed smoke |
| 文档/OCR/公式/表格 adapter | `workers/document` | `tests/golden-import`、`tools/run-j*.ps1` | adapter contract、golden import |
| 来源资料、SourceRegion、截图、质量报告 | `apps/api`、`tools/guangzhou_*` | `workers/document`、`docs/evidence` | REAL/NS source-region smoke |
| AI 候选、ModelRouter、成本缓存、schema/eval | `apps/api/Ai`、`schemas/ai`、`configs/ai-*` | `tools/run-c002*.ps1`、`tools/run-l*.ps1` | no-active-write、budget/eval guard |
| 题库检索、题篮、组卷、换题、导出审校 | `apps/api/Application/Workflows/PaperWorkflowService.cs`、`apps/web/src/api` | `tools/run-s008*.ps1`、`tools/run-s009*.ps1`、`tools/run-s010*.ps1` | API/UI smoke、artifact regression |
| 成绩导入、学情分析、讲评报告 | `apps/api/Application/Workflows/ScoreAnalysisWorkflowService.cs` | `tools/run-s011*.ps1`、`tools/f00*.py` | score import smoke、analysis report smoke |
| 备份、恢复、安装、升级、host/worker profile | `tools`、`configs` | `apps/api`、`docs/evidence` | backup/restore/installer/upgrade contracts |
| 非现场端到端和完成态看板 | `tools/run-s012*.ps1`、`tasks/*.csv` | `docs/evidence`、`docs/templates` | E2E rehearsal、completion dashboard guard |
| 现场试点与发布裁决 | `docs/templates`、`tools/run-p*.ps1` | `docs/evidence`、`tasks/backlog.csv` | P001-P006 checklist；保持 `blocked_by_onsite` |
| 多学科和长期平台 | `docs/decisions`、`tools/run-q*.ps1`、`tools/run-r*.ps1` | `schemas`、`configs`、`tasks` | Q/R preflight、ADR、profile map |

## Current Evidence From Repo Probe

- 后端 workflow 已存在：`ImportReviewWorkflowService.cs`、`PaperWorkflowService.cs`、`ScoreAnalysisWorkflowService.cs`、`CutCandidateGenerationService.cs`。
- 前端 typed API 已存在：`apps/web/src/api/client.ts`、`contracts.ts`、`queries.ts`。
- 前端后台隔离面板已存在：`apps/web/src/ui/AdminGovernancePanels.tsx`。
- worker 主入口已存在：`workers/document/worker.py`。
- 任务合同脚本集中在 `tools/run-*.ps1`，包括 S0、REAL、P/Q/R preflight 和 adapter/backup/restore 相关 guard。
- golden/proxy fixture 入口已存在：`tests/golden-import`、`tests/e2e`。

## Forward Rule

后续 NS 任务必须优先落到上表归宿。若必须新增目录或跨边界实现，先在任务 evidence 中说明：

- 为什么现有归宿不足。
- 新归宿如何被 gate 或 contract 覆盖。
- 回滚后如何不破坏旧 API/UI/worker/tool 入口。

## Verification

```powershell
rg --files apps/api
rg --files apps/web
rg --files workers/document tools tests
rg -n "WorkflowService|ReviewQueue|QuestionAsset|SourceRegion|Paper|Score|Backup|Audit|apiClient|fetch" apps/api apps/web workers/document tools tests
```

结果：确认上述归宿文件和合同脚本存在。

## Gate N/A

- `build`: gate_na
  - reason: 本轮只记录模块归宿，不改业务代码。
  - alternative_verification: `rg --files` 与符号检索。
  - evidence_link: `docs/evidence/20260528-ns003-module-ownership.md`
  - expires_at: 进入 NS101 或任一代码落地任务时。
- `test`: gate_na
  - reason: 本轮不改变 API/UI/worker 行为。
  - alternative_verification: 模块归宿检索。
  - evidence_link: `docs/evidence/20260528-ns003-module-ownership.md`
  - expires_at: 进入对应模块实现任务时。

## Rollback

```powershell
git restore -- docs/evidence/20260528-ns003-module-ownership.md tasks/non-site-implementation-plan.csv
```

