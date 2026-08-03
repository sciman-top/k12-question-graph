# Verification Governance Simplification v1

**状态**: accepted_for_repo_side_execution
**当前阶段**: VGOV-001..010 的治理减负已完成；Release core 收缩修复已落盘并进入验证
**产品行为**: 不变
**发布边界**: `REAL005=not_closed`，P001/P003/P005/P006 仍依赖现场/人工事实，release No-Go

## 1. Problem statement

本仓已具备 API、Web、Worker、PostgreSQL、FileStore、候选审核、版本化知识资产、真题证据链和备份恢复能力，但验证与治理外围已明显膨胀：`tools/run-gates.ps1` 同时承载编译、测试、静态 UI 合同、数据库 smoke、备份恢复、安装预检、现场准入和未来能力评估；状态又被 README、roadmap、task breakdown、dashboard、release card、closure status 与日期化 evidence 重复投影。

该结构导致普通编码任务难以快速反馈、门禁失败难以归因、AI 容易选择旧“下一步”，并持续生成重复证据。治理减负必须在不削弱数据、隐私、人工审核、迁移和回滚边界的前提下完成。

## 2. Goals and non-goals

### Goals

- `tasks/backlog.csv` 是任务顺序和状态的唯一机器真源。
- `docs/103_ExecutionControlBoard.md` 只投影一个 Now、一个 Next 和明确 Later/Blocked。
- AI 通过短入口即可确定 task、write-set、禁止边界、验证 profile、证据策略和完成口径。
- 将现有 gate 分为 `Quick / Slice / Release / Onsite`，普通任务不触发数据库、常驻进程停止或 tracked evidence 写入。
- 停止 Q/R 未来能力进入默认 Quick/Slice，除非 changed paths 或当前 task 明确命中。
- 日常运行结果进入 `tmp/`；只有 release、迁移/恢复和 onsite/live acceptance 证据进入 Git。
- 逐步用行为测试替换低信号的 UI 源码字符串合同。

### Non-goals

- 不改变教师功能、API、数据库 schema、C002/C002R 或 active 数据。
- 不删除候选审核、来源锚点、隐私、备份恢复或人工签字门禁。
- 不在本切片推进多学科、向量检索、消息队列、SaaS 或高级分析。
- 不建立新的服务化治理平台、跨仓 registry 或第二套任务数据库。
- 第一阶段不删除历史 evidence；只停止继续生成无价值的重复快照。

## 3. Canonical information model

| 信息 | 唯一 owner | 其他文件职责 |
|---|---|---|
| 产品目标、用户和成功指标 | `docs/01_PRD.md` | 不含日期化状态 |
| v0.1 范围 | `docs/02_MVP_Scope_and_ScopeControl.md` | 不含日常进度 |
| 任务顺序和状态 | `tasks/backlog.csv` | 其他状态页只投影 |
| 当前执行切片 | `docs/103_ExecutionControlBoard.md` | 只保留 Now/Next/Later/Blocked |
| 当前 closure truth | `docs/CurrentClosureStatus.md` | 不以文件名日期表达 current |
| 发布裁决 | `docs/109_ReleaseGoNoGoCard.md` | 只负责 Go/No-Go |
| 历史事实 | `docs/evidence/` 与 Git 历史 | 不决定下一任务 |

生成或投影文件不得成为上游。发生冲突时，先核对代码、数据库/API 运行事实和 `tasks/backlog.csv`，再修复投影。

## 4. AI executable task contract

当前编码 task 的 spec 必须提供：

```yaml
task_id:
parent_id:
objective:
user_outcome:
current_truth:
preconditions:
depends_on:
in_scope:
out_of_scope:
write_set:
protected_paths:
implementation_steps:
acceptance_criteria:
verification_profile:
focused_verifiers:
stateful_verifiers:
evidence_policy:
rollback:
truth_boundary:
next_task_on_success:
blocker_routing:
```

`evidence_policy` 仅允许：`none / local_artifact / tracked_release / live_acceptance`。`truth_boundary` 必须区分 repo-side、deployed、onsite/manual 和 live accepted。

## 5. Verification profiles

### Quick

- backend/frontend/worker build、lint、unit tests、schema/config parse。
- 禁止连接 PostgreSQL、停止/启动常驻 API/Web、写入 FileStore 或 `docs/evidence/`。
- 报告只写 `tmp/verification/<run-id>/`。

### Slice

- 不隐式包含整套 Quick；只执行当前 task/changed paths 命中的最小 build/test/contract/invariant/hotspot 链。
- API 切片运行 backend build/test，Web 切片运行 frontend build/lint/test，Worker 切片运行 compile/test；docs/governance 切片不得拉起无关产品栈。
- unknown path 必须 fail-closed 或提升验证级别，不能静默跳过。
- 无 changed path、无匹配 task 的空选择必须 fail-closed，不能产出零步骤 pass。
- stateful step 必须在 task spec 中显式声明并单独授权。

### Release

- 默认入口是 `tools/run-verification.ps1 -Profile Release -AuthorizeStateful`：先 Quick，再执行 `release-contracts`（migration/privacy/no-active-write/API/service boundary）、`release-upgrade-recovery`（NS806 的 migration bundle + isolated backup/restore）和 `release-closure-invariants`（reference/evidence/coverage/hotspot/UI/release-pack/REAL005/roadmap）。
- 默认 Release 不调用 `tools/run-gates.ps1`，不刷新日期化 tracked evidence，不向共享 FileStore 写 fixture；报告与恢复工件写入 `tmp/verification/<run>/`，前后指纹必须证明 migration、数据库 shape、共享 FileStore 与进程未发生未声明变化。
- `tools/run-verification.ps1 -Profile Release -AuthorizeStateful -IncludeLegacyCompatibility` 才运行 235-step legacy compatibility audit。它是显式、低频、stateful、隔离审计，不是默认发布阻断链；旧节点 inventory 仍可查询、可追溯、可按需审计。
- 指纹相同不能替代数据库 row-level 等值证明；指纹变化不能被 pass 状态掩盖。`sharedFileStoreWriteExpected=false` 是默认 Release 的硬不变量。

### Onsite

- 隔离机、学校网络、打印、权限域、真实教师操作和签字。
- repo-side automation 只能生成执行包和导入真实证据，不得代签或合成通过。

## 6. Existing gate migration contract

每个现有 gate step 必须记录：`id / command / owner_module / profile / risk / requires_database / stops_process / writes_repo / writes_filestore / trigger_paths / evidence_output`。

迁移已按以下顺序完成：

1. inventory；
2. classify；
3. implement new profile；
4. compare old/new coverage；
5. remove duplicate default execution；
6. authorized Release parity exit 0 后，将 compatibility wrapper 固定为低频 Release 入口。

禁止以“脚本太多”为理由直接删除回归覆盖。

## 7. Evidence lifecycle

| 类型 | 位置 | tracked |
|---|---|---:|
| Quick/Slice 日志 | `tmp/verification/` | no |
| 临时诊断和截图 | `tmp/` | no |
| migration/backup/restore/release | `docs/evidence/` | yes |
| onsite/live acceptance | `docs/evidence/attachments/` 与签收报告 | yes |

后续 VGOV-008 建立 `docs/evidence/index.json`，记录 current、superseded 和 authority level。第一阶段不批量删除历史证据。

## 8. UI contract migration

静态 UI 合同按 `keep / replace / delete_after_parity` 分类：

- keep：权限、no-active-write、教师/管理员边界和安全 fail-closed。
- replace：class、CSS selector、固定 DOM 片段、固定文案存在性。
- delete_after_parity：已被 Testing Library/Playwright 行为测试等价覆盖的检查。

新行为测试必须先通过，旧合同才能退出默认 profile。

## 9. Acceptance criteria

- Executive Spec 不再声明“下一步只做 P0”。
- PRD、scope 和 roadmap 不保存日期化当前状态。
- Execution Control Board 只有一个 Now。
- `tasks/backlog.csv` 登记 VGOV-001..010 的依赖、验收和 verifier。
- 235 个旧 gate step 已由 AST inventory 完整分类；默认 Release 不执行 legacy monolith，235 个节点全部退出默认主路径，其中 151 个操作上无状态节点和 22 个 future-trigger-only 节点不再被默认 Release 重复执行；legacy audit 仍可显式运行。
- 默认 Release 由 Quick + 3 个聚焦阶段承接必要风险覆盖；Slice 只运行所选最小链；Quick/Slice 都不访问 DB、不停止进程、不产生 tracked diff。
- Q001-Q005、R001-R007 不进入默认 Quick。
- Release 继续保护 migration、backup/restore、active write、真实数据和发布证据。
- coverage reconciliation 必须同时记录 legacy inventory（Quick=7、Release=228、unmapped=0）、default release-core coverage、optional legacy audit coverage、retired default execution count、future-trigger-only count；不得再把 228 个 legacy 节点写成默认 Release coverage。
- VGOV-010 只抽取真实 Score/Admin AI endpoint seam，并用一个 canonical hotspot budget 防止稳定模块重新增长；不为每项能力新增永久主门禁。
- 本治理计划不能改变 `REAL005=not_closed` 或 release No-Go。

## 10. Completion decision

VGOV-001..010 只有在 Release core 收缩和 Slice 真正按 changed path/task 聚焦后才算治理减负完成：日常验证入口为 Quick/Slice，默认 Release 为聚焦 core，legacy 235-step 仅在 `-IncludeLegacyCompatibility` 下作为显式审计；current evidence、任务状态、当前投影和历史记录分层，默认 Release 不产生共享 FileStore 或日期化 tracked evidence 副作用。

此完成裁决不等于项目发布：P001-P006、`REAL005=not_closed`、`fullClosureAllowed=false` 和 release No-Go 保持不变。

## 11. Risks and rollback

- 漏测：旧 full gate 作为显式 legacy audit 保留；inventory 与 coverage reconciliation 可按需证明完整性，默认 Release 只运行风险聚焦 core。
- changed-path 映射遗漏：unknown path fail-closed。
- 状态投影漂移：投影只从 canonical source 生成或验证。
- evidence 误删：第一阶段零删除。
- 治理再次过度设计：只使用 repo-local PowerShell、CSV/JSON/YAML 和现有测试工具，不引入常驻治理服务。
- Release 副作用被忽略：稳定 reconciliation 必须展示 FileStore delta、数据库比较粒度和进程差异，禁止用单一 pass 覆盖。

回滚只撤销 VGOV 当前切片的文档、配置和 verifier 变更，不回滚产品数据或用户已有工作树变更。
