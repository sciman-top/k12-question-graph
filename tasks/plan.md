# Implementation Plan: 2015-2025 广州中考物理本机闭环

## Overview

按已批准的版本化重导入设计，将 `D:\KQG_Data\guangzhou_physics_2015_2025` 中 32 份真实 PDF 建立为可审计来源批次，并打通真实 PostgreSQL、FileStore、API、Worker、Web、浏览器和导出链。所有写入先有备份和回滚入口；所有完成声明以新鲜运行证据为准。

## Architecture Decisions

- 批次键固定为 `guangzhou-physics-2015-2025-20260726-v2`，所有新增数据库事实、FileStore 工件和 evidence 均可追到该键。
- 原始 PDF 迁移到版本化目录，FileStore 继续 content-addressed 去重；2015 相同 hash 复用旧原件。
- 现有 C003 CSV 只作为候选基线，必须与新 PDF 的页、题号、答案和年报证据重新对齐。
- C002 active 不直接修改；知识点、考点、难度和能力标签先进入 candidate/review 流程。
- 本机闭环只提升本机可运行和非现场证据，不替代隔离机、学校网络、真实教师签字或最终发布。

## Dependency Graph

```text
Task 1 来源 inventory/迁移工具
  -> Task 2 数据备份与迁移
     -> Task 3 来源登记与 C003 重基线
        -> Task 4 逐年解析与切题
           -> Task 5 答案/资产关联
              -> Task 6 知识与标签候选
                 -> Task 7 审核工作台闭环
                    -> Task 8 教师主工作流
                       -> Task 9 浏览器/视觉验收
                          -> Task 10 全门禁与状态收口
```

## Task 1: 版本化来源 inventory 与迁移工具

**Description:** 新增仓库脚本，识别平铺的试卷、答案/解析和年报文件，兼容 2020 合并卷，生成 immutable inventory、迁移预演和 hash parity 报告。

**Acceptance criteria:**

- [ ] 32 份 PDF 全部识别到年份和逻辑角色，2015-2025 无缺年。
- [ ] dry-run 不改文件，apply 只移动到版本化目录并在前后验证 SHA-256。
- [ ] 回滚命令只恢复本批次文件，目标冲突时 fail-closed。

**Verification:**

- [ ] `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-guangzhou-physics-source-batch-stage.ps1`
- [ ] inventory JSON schema/CSV parse 与 32/32 hash parity 测试。

**Dependencies:** None

**Files likely touched:**

- `tools/run-guangzhou-physics-source-batch-stage.ps1`
- `tools/guangzhou_physics_source_batch.py`
- `tests/workers/test_guangzhou_physics_source_batch.py`
- `tools/README.md`

**Estimated scope:** Medium

## Task 2: 数据库与 FileStore 备份后执行迁移

**Description:** 解析本机数据库凭据，生成数据库备份、FileStore manifest、现有来源映射快照和恢复命令，再执行来源文件版本化迁移。

**Acceptance criteria:**

- [ ] backup manifest 和数据库 dump 均通过校验。
- [ ] 32 份 PDF 移动后 hash 与迁移前完全一致，输入目录无遗留 PDF。
- [ ] 执行一次非破坏性 restore/rollback dry-run，证明恢复入口可用。

**Verification:**

- [ ] `tools/backup.ps1`、`tools/verify-backup.ps1` 与批次 stage `-Apply` 报告通过。
- [ ] `Get-FileHash` 独立复核来源目录和目标目录。

**Dependencies:** Task 1

**Files likely touched:**

- `D:\KQG_Backups\...`
- `D:\KQG_Data\source_materials\imported\guangzhou_physics_2015_2025\20260726-v2\raw`
- `docs/evidence/20260726-guangzhou-physics-source-batch-stage.json`

**Estimated scope:** Medium

## Task 3: 来源登记与 C003 重基线

**Description:** 修正来源类型推断和稳定标识，导入 32 份 SourceDocument/FileAsset，重建新旧来源、题号和年报映射差异报告。

**Acceptance criteria:**

- [ ] 32 个逻辑来源组登记成功，2020 物理文件去重但具备双角色映射。
- [ ] 2015 复用旧 hash，其余来源不覆盖旧记录；重复导入幂等。
- [ ] 210 个旧候选均得到 matched/changed/blocked 分类和来源证据。

**Verification:**

- [ ] `import-c002-source-materials.ps1` dry-run/apply 与 API source query 通过。
- [ ] SourceDocument/FileAsset 数量、hash、路径、批次键和孤儿记录 SQL 不变量通过。

**Dependencies:** Task 2

**Files likely touched:**

- `tools/import-c002-source-materials.ps1`
- `tools/prepare_c002_candidate_csvs.py`
- `tools/real005_yearly_adapter_diagnostics.py`
- `docs/evidence/`

**Estimated scope:** Medium

## Checkpoint: 来源与恢复

- [ ] 32/32 来源可追溯且无 hash 漂移。
- [ ] 数据库和 FileStore 均有可验证恢复入口。
- [ ] 新旧候选差异已分类，未发生 active 覆盖。

## Task 4: 逐年 PDF 解析、页面渲染与切题

**Description:** 对 2015-2025 每年运行文本/OCR profile、页级渲染、题号检测、切题和来源区域生成，并修复真实材料暴露的解析缺口。

**Acceptance criteria:**

- [ ] 每年题数、题号连续性、页码和区域覆盖有机器报告。
- [ ] 所有题目区域为非空有效图片，跨页/共图/异常项明确分类。
- [ ] 解析失败不会创建伪成功题目，均进入人工接管队列。

**Verification:**

- [ ] `run-guangzhou-physics-year-batch-ingest.ps1` 与 REAL005 yearly diagnostics 通过。
- [ ] 逐年页面/区域像素非空、边界范围和重复区域检查通过。

**Dependencies:** Task 3

**Files likely touched:**

- `workers/document/worker.py`
- `tools/guangzhou_physics_year_batch_ingest.py`
- `tools/guangzhou_physics_2016_2025_source_region_screenshots.py`
- `tests/workers/test_worker.py`

**Estimated scope:** Medium

## Task 5: 答案、解析、题图、表格与公式关联

**Description:** 将题目与答案/解析、小题、题图、表格和公式按来源锚点关联，处理 2020 合并卷和新旧文件差异。

**Acceptance criteria:**

- [ ] 每道客观题答案唯一，主观题评分点顺序稳定且可回看。
- [ ] 题图、表格、公式与题目关联无孤儿，缺失项进入审核队列。
- [ ] 2020 试题页和答案页边界不会互相污染。

**Verification:**

- [ ] REAL008/REAL009/REAL010 与 structured-question diagnostics 通过。
- [ ] 答案覆盖、QuestionBlock/QuestionAsset 外键和来源路径 SQL 检查通过。

**Dependencies:** Task 4

**Files likely touched:**

- `tools/real005b_reviewed_question_materialize.py`
- `tools/real005b_structured_question_diagnostics.py`
- `apps/api/Application/Workflows/ImportReviewWorkflowService.cs`
- `docs/evidence/`

**Estimated scope:** Medium

## Task 6: 知识点、考点、难度与能力标签

**Description:** 以 C002 active 为基础重核 82 个知识节点、47 个考点和逐题映射，区分年报实测、规则估计、AI 估计和教师确认难度。

**Acceptance criteria:**

- [ ] 每道题的标签候选均有来源、生成方式、置信度和审核状态。
- [ ] 年报指标与估计值不混用；冲突项保留多来源和裁决记录。
- [ ] 新知识资产只进入 C002R candidate/review，不直接写 active。

**Verification:**

- [ ] C002 dry-run suite、AI schema/eval/no-active-write guards 通过。
- [ ] 无来源标签、失效知识版本和错误 active 引用 SQL 检查通过。

**Dependencies:** Task 5

**Files likely touched:**

- `schemas/ai/knowledge_mapping.schema.json`
- `apps/api/Application/Workflows/ImportReviewWorkflowService.cs`
- `tools/prepare_c002_candidate_csvs.py`
- `configs/ai-evals/`

**Estimated scope:** Medium

## Checkpoint: 真实题库事实

- [ ] 2015-2025 题目、答案、来源、资产和标签均可查询。
- [ ] 未解决异常明确进入审核队列。
- [ ] active 知识体系与历史数据未被绕过。

## Task 7: 审核工作台与 API 数据闭环

**Description:** 使用真实批次验证并补齐原页/切题区域、题干、答案、解析、标签、难度、重裁、资产关联、确认/退回/修订/撤销和审计回放。

**Acceptance criteria:**

- [ ] 真实题目可从审核队列打开、修改、保存并回看来源。
- [ ] 确认、退回、修订、撤销均生成一致审计记录。
- [ ] API 失败、冲突和权限不足均有可继续路径且不丢数据。

**Verification:**

- [ ] REAL004、S006B/S006C/S007C 和 API tests 通过。
- [ ] 浏览器完成至少一条确认、一条退回、一条重裁和一次撤销。

**Dependencies:** Task 6

**Files likely touched:**

- `apps/api/Application/Workflows/ImportReviewWorkflowService.cs`
- `apps/web/src/ui/`
- `apps/web/src/api/`
- `tests/api/`

**Estimated scope:** Medium

## Task 8: 检索、智能组卷、导出、成绩与分析

**Description:** 使用真实已审核题目走通题库检索、题篮、自然语言组卷、蓝图、换题/撤销、Word/PDF 导出，以及匿名成绩和讲评报告。

**Acceptance criteria:**

- [ ] 可按年份、题型、知识点、考点和难度找到真实题目并建立题篮。
- [ ] 组卷、换题、撤销和 Word/PDF 工件可重复生成且来源清楚。
- [ ] 匿名成绩导入和确定性分析不写真实学生数据或正式历史。

**Verification:**

- [ ] E001-E004、S009-S011、REAL005C1/C2 和 S012B 通过。
- [ ] Word/PDF 工件打开、页数、题号、公式、题图和表格检查通过。

**Dependencies:** Task 7

**Files likely touched:**

- `apps/api/Application/Workflows/PaperWorkflowService.cs`
- `apps/api/Application/Workflows/ScoreAnalysisWorkflowService.cs`
- `apps/web/src/ui/PaperWorkbenchPanels.tsx`
- `apps/web/src/ui/ScoreWorkbenchPanelContent.tsx`
- `apps/web/src/ui/AnalysisPanelContent.tsx`

**Estimated scope:** Medium

## Task 9: 浏览器 E2E 与视觉审查

**Description:** 启动本机 API/Web，使用真实批次操控教师和管理员界面，检查功能、网络、控制台、状态、响应式布局和视觉证据。

**Acceptance criteria:**

- [ ] 四个教师入口和审核主链路均由浏览器真实完成。
- [ ] 桌面/移动无关键遮挡、溢出、空白画布、不可操作状态或未处理控制台错误。
- [ ] 截图与 API/数据库 evidence 绑定到同一 commit 和批次键。

**Verification:**

- [ ] 浏览器截图、控制台/网络日志和交互记录通过复核。
- [ ] NS906 visual surrogate 与受影响 UI tests 通过。

**Dependencies:** Task 8

**Files likely touched:**

- `apps/web/src/`
- `docs/evidence/`
- `tmp/browser-e2e/`

**Estimated scope:** Medium

## Task 10: 全门禁、恢复演练和状态收口

**Description:** 按固定门禁顺序验证全仓，重跑 REAL005 证据链，执行恢复演练并同步状态文档、路线图和任务真值。

**Acceptance criteria:**

- [ ] build、full test、contract/invariant 和 hotspot 按顺序通过或有完整 N/A 记录。
- [ ] 批次 rollback/restore 可验证，失败不会损坏旧来源或 active 数据。
- [ ] README、roadmap、backlog、dashboard 和 evidence 与实际结果一致。

**Verification:**

- [ ] `tools/run-gates.ps1`、REAL005 fresh sequence、roadmap guard 和 repo preflight Release 通过。
- [ ] `git diff --check`、工作树审查和完成边界复核通过。

**Dependencies:** Task 9

**Files likely touched:**

- `README.md`
- `docs/19_Roadmap.md`
- `docs/20_TaskBreakdown.md`
- `docs/103_ExecutionControlBoard.md`
- `docs/112_CurrentClosureStatus_20260609.md`
- `tasks/backlog.csv`
- `tasks/completion-state-dashboard.csv`
- `docs/evidence/`

**Estimated scope:** Medium

## Checkpoint: Complete

- [ ] 32 份来源、2015-2025 真实题库和教师主链路完成本机验证。
- [ ] 数据、工件、浏览器和恢复证据均绑定到同一批次和 commit。
- [ ] repo-side/non-site、onsite/manual、release/live acceptance 边界表述准确。

## Risks And Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| 新 PDF 与旧候选内容不同 | 题号、答案或标签错配 | 版本化批次、逐题 diff、禁止文件名覆盖 |
| 解析/OCR 对扫描页失败 | 切题区域为空或错位 | profile 诊断、像素检查、人工接管队列 |
| 数据写入污染旧库 | 旧题和 active 资产不可恢复 | 写前备份、批次键、事务、restore drill |
| 年报指标语义误用 | 难度被错误解释为官方实测 | 强制 difficulty source type 和冲突审计 |
| 合同通过但 UI 不可用 | 教师主链路仍不能工作 | 真实浏览器 E2E、视觉审查、工件打开验证 |
| 证据刷新制造错误完成态 | `REAL005` 或发布边界被夸大 | fresh sequence、dashboard 真值和 No-Go 守卫 |

## Open Questions

当前实施无需新的产品选择。出现无法从资料、代码或现有契约判断的版权授权、生产 active 切换或责任签字问题时，保持 fail-closed 并记录为外部阻断，不阻塞其余本机闭环工作。
