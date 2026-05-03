# 78 · 学科知识体系激活流水线

## 1. 目的

本 runbook 把 C002 广州初中物理的复杂激活链路沉淀成可复用流程。后续新增化学、生物、数学等学科时，教师和备课组不需要手工理解每个底层任务，只需要准备来源资料和候选 CSV，由统一脚本完成检查、审核决策、备份、激活和证据归档。

激活的含义是：某一批来源可追溯的动态资产从 `candidate/reviewed` 进入 `active`，成为当前生产默认版本。它不表示永久冻结。后续修订仍走新候选批次、映射、影响报告、审核、回滚和 active 切换。

## 2. 教师侧最小动作

教师或备课组只需要完成三件事：

1. 提供来源资料：教材、课程标准、当地真题、年报或校本资料，统一放在 Git 外数据目录。
2. 复核候选结果：重点看明显错误、章节/考点错配、低置信度映射和影响较大的合并/拆分。
3. 确认激活前摘要：确认 source hash 完整、待审项清零、备份 manifest 已生成。

其余动作由脚本执行，证据写入 `docs/evidence/`。

教师复核和激活确认必须使用模板：

- `docs/templates/subject-candidate-review-checklist.md`
- `docs/templates/subject-activation-approval-form.md`

详细操作说明见 `docs/79_TeacherCandidateReviewAndActivationGuide.md`。

## 3. 统一入口

激活前只检查，不写 active：

```powershell
.\tools\run-domain-asset-activation.ps1 `
  -ImportKey '<subject_candidate_import_key>' `
  -MaterialBatchKey '<source_material_batch_key>' `
  -EvidencePrefix '<subject>-activation' `
  -ExpectedSourceDocumentCount 0
```

自动生成审核决策并应用到 `reviewed/approved/dry_run`：

```powershell
.\tools\run-domain-asset-activation.ps1 `
  -ImportKey '<subject_candidate_import_key>' `
  -MaterialBatchKey '<source_material_batch_key>' `
  -EvidencePrefix '<subject>-activation' `
  -ExpectedSourceDocumentCount 0 `
  -GenerateDecisionFile `
  -ApplyReview
```

在审核清零后执行 active 切换：

```powershell
.\tools\run-domain-asset-activation.ps1 `
  -ImportKey '<subject_candidate_import_key>' `
  -MaterialBatchKey '<source_material_batch_key>' `
  -EvidencePrefix '<subject>-activation' `
  -ExpectedSourceDocumentCount 0 `
  -ApplyActivation
```

`-ExpectedSourceDocumentCount 0` 表示不固定资料数量，只要求大于 0 且全部有 sha256。正式批次已知数量时应传入具体数字，例如广州物理为 `33`。

## 4. 机器检查顺序

统一入口内部固定执行：

1. readiness：检查 candidate/reviewed/active 生命周期、source hash、pending mapping、migration、review queue、rollback snapshot。
2. review decision：可选生成并应用审核决策，进入 `reviewed/approved/dry_run`。
3. active dry-run：验证能否切换 active，不写库。
4. backup：执行 `tools/backup.ps1` 并用 `tools/verify-backup.ps1` 校验 manifest。
5. active apply：将 reviewed 资产切换为 active，并把 migration 标记为 applied。
6. final dry-run：确认已激活后可幂等复跑。

任何一步失败都保持当前状态，不继续执行下一步高风险动作。

## 5. 完成判定

完成必须同时满足：

- `formalActivationComplete = true`。
- `candidateAssets = 0`。
- `reviewedAssets = 0`。
- `activeAssets = totalAssets`。
- `pendingMappings = 0`。
- `pendingMigrations = 0`。
- `openReviewItems = 0`。
- `sourceDocuments = sourceDocumentsWithSha256`。
- `rollbackSnapshots >= 1`。
- full gate 通过。

## 6. C002 参考证据

广州初中物理 C002 已完成：

- 来源批次：`guangzhou_physics_2016_2025`。
- 导入批次：`c002_candidate_import_guangzhou_physics_2016_2025_v1`。
- active 资产：452。
- approved 映射：400。
- applied migration：1。
- 激活前备份：`D:\KQG_Backups\20260504-015358\manifest.json`。
- 激活报告：`docs/evidence/c002t-active-switch-report.json`。

该批次可以作为后续学科流水线验收样板，但新学科不得复制 C002 的文件名、批次号或资料数量。
