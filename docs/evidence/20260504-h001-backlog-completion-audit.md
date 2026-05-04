# 2026-05-04 H001 旧 backlog 完成态核验

## 规则 ID

- R1：当前落点为 H0 阶段收口的 `H001`；目标归宿是证明旧 `A000-G004` backlog 的完成态、证据、门禁和 README 口径一致。
- R2：本轮只做审计证据和 `H001` 状态更新，不新增运行功能。
- R4：低风险文档/backlog 状态变更；不触碰数据库、真实资料、真实 AI、备份包、权限或 active switch。
- R6：按 H001 verification 执行 CSV/JSON/YAML parse、roadmap guard 和 evidence report；full gate 已由 H0 full gate 证据记录，H001 不重复执行重型门禁。
- R8：依据、命令、证据和回滚如下。

## 审计结论

- `tasks/backlog.csv` 共 131 项。
- `A000-G004` 共 61 项，全部为 `已完成`。
- `A000-G004` 完成项中显式引用的 `docs/evidence/*` 共 21 个，当前缺失数为 0。
- README、roadmap 和 task breakdown 的完成态口径一致：旧 P0-P6 已完成的是系统骨架、合同门禁、draft/test 闭环和 C002 active v1；并未把真实 AI、真实学生数据、正式学情口径、生产权限模型或所有教师现场验收冒充为已完成。
- `C002` 生产默认的边界清楚：初中物理 v1 已 active，但后续修订必须走 C002R 的 candidate、mapping、impact、review、rollback、admin active switch。
- `D001-D003`、`E001-E004`、`F001-F003`、`G001-G004` 均保持 draft/test 或 dry-run 边界；真实外部 AI 自动写入、真实学生数据处理和生产角色/审计权限仍属于后续任务。

## 已执行命令

```powershell
git status --short --branch
python -c "import csv, collections; rows=list(csv.DictReader(open('tasks/backlog.csv', encoding='utf-8-sig'))); print('total', len(rows)); print('status', dict(collections.Counter(r['status'] for r in rows)))"
python -c "import csv,re,pathlib; rows=list(csv.DictReader(open('tasks/backlog.csv',encoding='utf-8-sig'))); done=[r for r in rows if r['id'] <= 'G004']; missing=[]; refs=[]; [refs.append((r['id'],m)) or (missing.append((r['id'],m)) if not pathlib.Path(m).exists() else None) for r in done for m in re.findall(r'docs/evidence/[A-Za-z0-9_.\-]+', (r.get('acceptance','')+' '+r.get('verification','')))]; print('done_through_g004', len(done)); print('evidence_refs', len(refs)); print('missing_refs', len(missing))"
rg -n "旧 A000-G004|draft/test|真实模型|真实学生|active|生产完成|G004" README.md docs\19_Roadmap.md docs\20_TaskBreakdown.md docs\87_PhaseCloseoutAndFullRoadmap.md
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-roadmap-guard.ps1
```

## 关键输出

- `total 131`
- `status {'已完成': 61, '待办': 70}`，更新 H001 前。
- `done_through_g004 61`
- `evidence_refs 21`
- `missing_refs 0`
- `tools\run-roadmap-guard.ps1` 返回 `status=pass`。

## 非完成项边界

- H0 还未完成：`H002-H007`。
- I0 以后还未开始：教师工作流产品化、真实文档解析、真实 AI 安全试点、准生产部署、试点验收等仍在后续路线图。
- Vite chunk warning 不作为 H001 阻断；已归入 `I007` 的 `bundle analysis`。

## 回滚

```powershell
git diff -- tasks/backlog.csv docs/evidence/20260504-h001-backlog-completion-audit.md
```

如需撤销 H001 收口，只把 `tasks/backlog.csv` 中 `H001` 状态改回 `待办`，并删除本证据文件。本轮未修改运行代码、数据库、备份包、真实资料、权限或 active 状态。
