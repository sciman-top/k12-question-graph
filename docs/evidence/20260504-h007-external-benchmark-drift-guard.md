# 2026-05-04 H007 external benchmark drift guard

## 规则 ID

- R1：当前落点为 H0 阶段收口的 `H007`；目标归宿是把外部 benchmark 复核变成路线漂移守卫。
- R2：本轮只固化已完成的外部复核结论和周期性守卫，不改运行功能。
- R4：低风险规划层变更；不引入新依赖、不改技术栈、不执行数据库/AI/active switch。
- R6：H007 的验证为 `docs/88` source list、backlog 补强项和 roadmap guard。
- R8：依据、命令、证据和回滚如下。

## 漂移守卫结论

- `docs/88_EngineeringEndStateExternalReview_20260504.md` 已完成 2026-05-04 外部复核。
- 当前工程终态保持：Windows/LAN first teacher workstation + ASP.NET Core modular monolith + PostgreSQL fact store + local file store + Python document/OCR/AI adapters + React/Vite/Ant Design teacher workbench + versioned domain assets + structured AI candidate pipeline + release/backup/restore evidence。
- 不建议换成纯云 SaaS、Supabase/Firebase-first、公网多租户、微服务/Kubernetes/独立图数据库或 Next.js 默认路线。
- 需要补强的不是换栈，而是把外部最佳实践转成可执行 gate/backlog。

## 已落地补强项

| ID | 归属 | 来源差异 | 当前落点 |
|---|---|---|---|
| H007 | H0 | 工程终态、技术栈和路线图会随官方文档和成熟项目变化 | 本漂移守卫 evidence + `docs/88` |
| I007 | I0 | 前端状态边界、typed API、bundle warning 不能只靠人工约定 | `tasks/backlog.csv` I007 + `docs/88` |
| L007 | L0 | 真实 AI 前必须覆盖 LLM security/red-team 风险 | `tasks/backlog.csv` L007 + `docs/88` |
| O007 | O0 | EF migration bundle、升级、回滚、restore drill 是发布前硬缺口 | `tasks/backlog.csv` O007 + `docs/88` |
| R007 | R0 | 标准互操作应先做 profile map，再决定 import/export | `tasks/backlog.csv` R007 + `docs/88` |

## 复核来源范围

已在 `docs/88_EngineeringEndStateExternalReview_20260504.md` 记录 source list，覆盖：

- Microsoft .NET / ASP.NET Core / EF Core / Windows Service / Health Checks。
- PostgreSQL、Npgsql、pgvector、`pg_dump`、`pg_trgm`。
- React、Vite、Ant Design、TanStack Query。
- OpenAI Structured Outputs、Batch、Prompt Caching、Evals。
- Docling、PaddleOCR、OCRmyPDF。
- OWASP LLM Top 10、NIST AI RMF / GenAI Profile。
- 1EdTech QTI、CASE、OneRoster、Caliper，以及 Moodle/TAO/OpenOLAT/Open edX 等成熟项目的边界参考。

## 周期规则

- 每个重要发布周期至少复核一次。
- 若外部文档或成熟项目实践改变当前路线，先写 `docs/88` 的后续复核记录，再落到 backlog 或 ADR。
- 外部文本只作为待核事实，不覆盖项目规则、代码事实和本机 gate。

## 已执行验证

```powershell
rg -n "H007|I007|L007|O007|R007|参考来源|工程终态" docs\88_EngineeringEndStateExternalReview_20260504.md tasks\backlog.csv
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-roadmap-guard.ps1
```

## 回滚

```powershell
git diff -- tasks/backlog.csv docs/evidence/20260504-h007-external-benchmark-drift-guard.md
```

如需撤销 H007 收口，只把 `tasks/backlog.csv` 中 `H007` 状态改回 `待办`，并删除本证据文件。本轮未改运行代码、技术栈、依赖、数据库、真实 AI 或 active 状态。
