# 2026-05-04 工程终态外部复核证据

## 规则 ID

- R1：当前落点为 `D:\CODE\k12-question-graph` 工程终态复核；目标归宿为项目文档和 backlog。
- R2：只做文档和任务清单补强，可用 CSV/JSON/YAML parse、roadmap guard 和 diff check 验证。
- R4：低风险规划层变更；不触碰数据库、真实资料、真实 AI、权限、备份或 active switch。
- R6：本轮为文档/backlog 变更，执行 build/test 的替代门禁为文档 parse、roadmap guard、diff check。
- R8：依据、命令、证据和回滚如下。

## 依据

- Microsoft .NET support policy、ASP.NET Core hosted services、Windows Service、health checks、EF Core migrations。
- PostgreSQL `pg_dump`、`pg_trgm`、pgvector、Npgsql EF Core provider。
- React、Vite、Ant Design、TanStack Query 官方文档。
- OpenAI Structured Outputs、Batch、Prompt Caching、Evals 官方文档。
- Docling、PaddleOCR、OCRmyPDF。
- OWASP Top 10 for LLM Applications、NIST AI RMF、1EdTech QTI、Moodle question bank。

## 变更

- 新增 `docs/88_EngineeringEndStateExternalReview_20260504.md`。
- 补充 `docs/03_Architecture.md` 模块化单体边界。
- 补充 `docs/04_TechnologyStack.md` 2026-05-04 外部复核补强项。
- 更新 `README.md`、`docs/19_Roadmap.md`、`docs/20_TaskBreakdown.md`、`docs/87_PhaseCloseoutAndFullRoadmap.md`。
- 在 `tasks/backlog.csv` 追加 H007、I007、L007、O007、R007。

## 已执行验证命令

```powershell
python -c "import csv, json, pathlib, yaml; rows=list(csv.DictReader(open('tasks/backlog.csv', encoding='utf-8-sig'))); [json.loads(p.read_text(encoding='utf-8')) for p in pathlib.Path('schemas').rglob('*.json')]; [yaml.safe_load(p.read_text(encoding='utf-8')) for p in pathlib.Path('configs').rglob('*.yaml')]; assert rows[-1]['id']=='R007'; print('doc gates ok', len(rows), rows[-1]['id'])"
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-roadmap-guard.ps1
git diff --check
rg -n "[ \t]+$" README.md docs/03_Architecture.md docs/04_TechnologyStack.md docs/19_Roadmap.md docs/20_TaskBreakdown.md docs/87_PhaseCloseoutAndFullRoadmap.md docs/88_EngineeringEndStateExternalReview_20260504.md docs/evidence/20260504-engineering-endstate-external-review.md tasks/backlog.csv
```

结果：

- `doc gates ok 131 R007`
- `tools/run-roadmap-guard.ps1` 返回 `status=pass`。
- `git diff --check` 退出码 0；仅提示若干既有治理文件 CRLF/LF warning，本轮未触碰这些治理文件。
- trailing whitespace 检索无命中，`rg` 退出码 1 属无匹配预期结果。

## 回滚

规划层回滚优先 Git：

```powershell
git diff -- README.md docs/03_Architecture.md docs/04_TechnologyStack.md docs/19_Roadmap.md docs/20_TaskBreakdown.md docs/87_PhaseCloseoutAndFullRoadmap.md tasks/backlog.csv
```

如需撤销，仅还原上述文档、删除 `docs/88_EngineeringEndStateExternalReview_20260504.md` 和本证据文件；本轮未改数据库、文件仓库、备份包、active 状态或真实 AI 配置。
