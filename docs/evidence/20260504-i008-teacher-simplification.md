# I008 教师简洁模式硬收口证据

日期：2026-05-04

## 依据

- 最高原则：普通教师侧少步骤、少选择、少术语，管理员和治理细节下沉。
- 复核发现：普通教师分析页曾混入 C002R 修订、映射审核、candidate、active、rollback、migration 等治理概念。
- 本轮 slice：把普通教师四入口收口为导入、组卷、成绩、分析；高级治理工作台默认隐藏，并用合同检查实际可见面。

## 变更

- `apps/web/src/App.tsx`：教师分析页只保留薄弱点、班级表现和讲评摘要；C002R 修订和映射审核移到 `admin-knowledge-panel`。
- `apps/web/src/App.tsx`：教师可见文案把 `draft_test`、`synthetic fixture`、`productionEligible=false`、`不进入生产` 等替换为“示例流程”“示例数据”“正式启用前预览”“可撤销”“自动检查”。
- `apps/web/src/App.css`：`admin-knowledge-panel` 默认隐藏，不被任何 `teacher-view-*` CSS 打开。
- `tools/run-i001-teacher-home-ui-contract.ps1`：从 marker 检查升级为检查教师分析页不得包含治理工作台。
- `tools/run-i008-teacher-simplification-contract.ps1`：新增教师可见面负面术语和高级面板隐藏合同。
- `tasks/backlog.csv`、`docs/11_UX_Workflows.md`、`docs/28_FunctionScopeReview.md`、`docs/87_PhaseCloseoutAndFullRoadmap.md`：同步 I008 减法裁决和当前看板。
- `tasks/backlog.csv` 的 O004：把 `/api/admin/*` 与 `/internal/ai/*` authentication/authorization 角色守卫明确为试点或 live 前阻断项。

## 执行命令与结果

```powershell
dotnet build apps\api\K12QuestionGraph.Api.csproj
```

结果：pass，0 warning，0 error。

```powershell
npm --prefix apps\web run build
npm --prefix apps\web run lint
```

结果：pass。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-i001-teacher-home-ui-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-i006-starter-defaults-ui-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-i008-teacher-simplification-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-local-first-ai-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-roadmap-guard.ps1
```

结果：全部 pass。关键输出：

- I001：`adminGovernanceMovedOutOfTeacherAnalysis=true`
- I006：`firstRunSteps=["import-sample-paper","assemble-sample-paper","import-sample-scores","open-analysis-summary"]`
- I008：`adminGovernanceHiddenByDefault=true`，`analysisPanelAdminLeakBlocked=true`
- roadmap guard：`status=pass`，`c002Status=已完成`

```powershell
python -c "import csv, json, pathlib, yaml; rows=list(csv.DictReader(open('tasks/backlog.csv', encoding='utf-8-sig'))); [json.loads(p.read_text(encoding='utf-8')) for p in pathlib.Path('schemas').rglob('*.json')]; [yaml.safe_load(p.read_text(encoding='utf-8')) for p in pathlib.Path('configs').rglob('*.yaml')]; print('doc gates ok', len(rows))"
```

结果：`doc gates ok 132`。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-gates.ps1
```

结果：pass。full gate 覆盖 backend build、frontend build/lint、I001-I008、J001-J006、K001-K006、C002/C002R、D/E/F/G、P1 API smoke、P1 proxy scenario 和 backup verify。

O004 权限角色验收文字补充后，重新执行：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-roadmap-guard.ps1
python -c "import csv, json, pathlib, yaml; rows=list(csv.DictReader(open('tasks/backlog.csv', encoding='utf-8-sig'))); [json.loads(p.read_text(encoding='utf-8')) for p in pathlib.Path('schemas').rglob('*.json')]; [yaml.safe_load(p.read_text(encoding='utf-8')) for p in pathlib.Path('configs').rglob('*.yaml')]; print('doc gates ok', len(rows))"
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-i008-teacher-simplification-contract.ps1
```

结果：全部 pass，CSV/schema/config 仍为 `doc gates ok 132`。

## 中途阻断与修复

- 第一次 full gate 阻断在 I006：旧合同仍要求 `生成草稿卷`。已同步为 `生成样卷`。
- 第二次 full gate 阻断在 local-first AI guard：旧守卫仍要求 `draft_test: '草稿测试'`。已同步为 `draft_test: '示例流程'` 与“正式启用前预览”。

## 回滚

- 代码与文档默认使用 Git 回滚本轮变更。
- 本轮未执行 active 切换、DB migration、真实 AI 调用或真实学生数据写入。
- full gate 生成的临时 evidence、backup 和 tmp 文件按既有门禁语义保留；若需清理，只清理本轮生成的临时目录，不删除正式数据目录或共享备份。
