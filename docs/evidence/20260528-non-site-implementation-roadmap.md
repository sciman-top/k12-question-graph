# 20260528 非现场能力落地路线图证据

## Goal

回应“除人工现场以外，大量非人工、非现场功能模块仍未实现落地，是否应先落盘”的判断，将长期完整路线图、详尽实施计划、细化拆分任务和机器可读任务清单先落到仓库。

## Scope

- 新增 `docs/101_NonSiteCapabilityImplementationRoadmap.md`。
- 新增 `tasks/non-site-implementation-plan.csv`。
- 在 `README.md`、`docs/19_Roadmap.md`、`docs/20_TaskBreakdown.md` 增加入口和执行口径。
- 不修改业务代码、不修改数据库、不改写既有 evidence 完成态。

## Result

- 当前落点：`D:\CODE\k12-question-graph`。
- 目标归宿：以 `docs/101_NonSiteCapabilityImplementationRoadmap.md` 作为非现场能力落地总控入口，以 `tasks/non-site-implementation-plan.csv` 作为机器可读任务清单。
- 新状态口径：`planned -> contract_only -> repo_landed -> runtime_verified -> non_site_validated -> blocked_by_onsite`。
- 任务规模：72 个 NS 任务，覆盖状态重基线、运行底座、数据安全、来源解析、切题审核、AI 候选、检索组卷导出、成绩学情、运维安装、非现场端到端、现场阻断、多学科和长期平台。

## Verification

```powershell
git diff --check
```

结果：exit code 0。仅输出既有工作树 CRLF/LF warning，未发现本轮新增 trailing whitespace 或 patch 格式错误。

```powershell
@'
import csv
from pathlib import Path
path = Path('tasks/non-site-implementation-plan.csv')
rows = list(csv.DictReader(path.open(encoding='utf-8-sig')))
required = {'id','phase','wave','category','task','priority','status','depends_on','acceptance','verification','likely_touched','evidence','rollback'}
missing = required - set(rows[0].keys()) if rows else required
ids = [r['id'] for r in rows]
dupes = sorted({i for i in ids if ids.count(i) > 1})
empty_required = [(r.get('id'), k) for r in rows for k in required if not (r.get(k) or '').strip() and k not in {'depends_on'}]
print({'rows': len(rows), 'missing_columns': sorted(missing), 'duplicate_ids': dupes[:10], 'empty_required_count': len(empty_required)})
'@ | python -
```

结果：`{'rows': 72, 'missing_columns': [], 'duplicate_ids': [], 'empty_required_count': 0}`。

```powershell
rg -n "101_NonSiteCapabilityImplementationRoadmap|non-site-implementation-plan|非现场能力落地" README.md docs/19_Roadmap.md docs/20_TaskBreakdown.md docs/101_NonSiteCapabilityImplementationRoadmap.md tasks/non-site-implementation-plan.csv
```

结果：README、路线图、任务拆解、新总控文档和新 CSV 均能检索到入口。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1
```

结果：`status=pass`；`realFullClosureStatus=not_closed` 仍保持当前真实边界。

## Gate N/A

- `build`: gate_na
  - reason: 本轮仅新增规划文档和 CSV 清单，未改业务代码、项目文件、schema 或脚本执行逻辑。
  - alternative_verification: `git diff --check`、CSV parse、入口检索、`tools/run-roadmap-guard.ps1`。
  - evidence_link: `docs/evidence/20260528-non-site-implementation-roadmap.md`
  - expires_at: 进入任一 `repo_landed` 实现任务时恢复 `dotnet build apps/api/K12QuestionGraph.Api.csproj`。
- `test`: gate_na
  - reason: 本轮没有 API/UI/worker 行为变更。
  - alternative_verification: CSV parse 与 roadmap guard。
  - evidence_link: `docs/evidence/20260528-non-site-implementation-roadmap.md`
  - expires_at: 进入任一代码、脚本或 UI 实现任务时恢复任务级测试和 `tools/run-gates.ps1`。
- `hotspot`: gate_na
  - reason: 本轮不改运行热点；教师效率热点已在路线图中作为后续 NS 任务验收字段。
  - alternative_verification: 新计划要求每个后续 NS 任务记录教师效率判断、失败接管和回滚。
  - evidence_link: `docs/evidence/20260528-non-site-implementation-roadmap.md`
  - expires_at: 第一个 `runtime_verified` 或 `non_site_validated` 任务完成前。

## Rollback

```powershell
git restore -- README.md docs/19_Roadmap.md docs/20_TaskBreakdown.md docs/101_NonSiteCapabilityImplementationRoadmap.md tasks/non-site-implementation-plan.csv docs/evidence/20260528-non-site-implementation-roadmap.md
```
