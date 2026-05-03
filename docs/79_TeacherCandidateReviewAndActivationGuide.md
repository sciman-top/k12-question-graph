# 79 · 教师候选复核与激活确认指南

## 1. 这一步要解决什么

系统可以自动整理教材、课标、真题和年报，生成候选知识点、教材章节、课程标准条目、地区考点和映射关系。但正式激活前，必须由教师或备课组确认“这些东西是否适合成为本校当前默认版本”。

教师不需要理解数据库、脚本或 JSON。只需要做两类判断：

- 候选结果是否明显正确。
- 激活前摘要是否显示没有待处理风险。

## 2. 使用的模板

复核候选结果用：

```text
docs/templates/subject-candidate-review-checklist.md
```

确认激活前摘要用：

```text
docs/templates/subject-activation-approval-form.md
```

这两个模板可以复制成某一学科的实际记录，例如：

```text
docs/evidence/chemistry-2026-review-checklist.md
docs/evidence/chemistry-2026-activation-approval.md
```

## 3. 推荐操作过程

### 第一步：只跑检查，不激活

由管理员或代理运行：

```powershell
.\tools\run-domain-asset-activation.ps1 `
  -ImportKey '<subject_candidate_import_key>' `
  -MaterialBatchKey '<source_material_batch_key>' `
  -EvidencePrefix '<subject>-activation' `
  -ExpectedSourceDocumentCount 0
```

教师看输出摘要和 `docs/evidence/<subject>-activation-summary.json`。

### 第二步：教师复核候选

教师打开候选结果页面或导出的候选表，按 `subject-candidate-review-checklist.md` 复核。

重点不是逐条看完全部内容，而是优先看：

- 低置信度。
- 高影响。
- 一对多、多对一、多对多。
- 高频考点。
- 每个一级主题的代表样本。
- 教师一眼觉得不符合日常教学表达的名称。

### 第三步：处理问题项

发现问题后不要激活。按情况处理：

| 问题 | 处理 |
| --- | --- |
| 名称不顺 | 修改名称或备注建议改名 |
| 层级不合理 | 改父级或拆分 |
| 映射方向错 | 改映射类型或目标 |
| 来源证据不足 | 补资料或暂缓 |
| 影响历史学情 | 暂缓，交管理员复核 |

### 第四步：应用审核决策

确认可以通过后，由管理员或代理运行：

```powershell
.\tools\run-domain-asset-activation.ps1 `
  -ImportKey '<subject_candidate_import_key>' `
  -MaterialBatchKey '<source_material_batch_key>' `
  -EvidencePrefix '<subject>-activation' `
  -ExpectedSourceDocumentCount 0 `
  -GenerateDecisionFile `
  -ApplyReview
```

这一步只把候选结果推进到 `reviewed/approved/dry_run`，仍不激活。

### 第五步：填写激活前确认表

教师或备课组填写 `subject-activation-approval-form.md`。必须确认：

- 来源资料 hash 完整。
- 待审资产为 0。
- 待审映射为 0。
- 待审 migration 为 0。
- 审核队列为 0。
- 有回滚快照。
- active dry-run 没有 blocker。
- backup manifest 已生成并校验。

### 第六步：激活

确认表完成后，由管理员或代理运行：

```powershell
.\tools\run-domain-asset-activation.ps1 `
  -ImportKey '<subject_candidate_import_key>' `
  -MaterialBatchKey '<source_material_batch_key>' `
  -EvidencePrefix '<subject>-activation' `
  -ExpectedSourceDocumentCount 0 `
  -ApplyActivation
```

脚本会先备份并校验，再执行 active 切换。

## 4. 教师如何判断“可以通过”

可以通过：

- 来源能追到教材、课标、真题或年报。
- 名称符合教师平时表达。
- 层级大体合理。
- 高频考点没有明显漏项。
- 映射关系没有明显反向或错配。
- 高影响项已经有人确认。

不要通过：

- 来源资料缺失或 hash 不完整。
- 大量名称不像教学用语。
- 把题型、考点、知识点混在一起。
- 多个章节被错误合并。
- 影响历史学情但没人确认。
- 系统摘要仍有 blocker。

## 5. 给教师看的简短口径

可以这样解释：

```text
这一步不是让老师逐条录入知识点，而是让老师抽查系统整理的候选知识体系。
机器会先保证来源、hash、映射、回滚和备份都齐全。
老师只需要重点看低置信度、高影响、复杂映射和典型样本。
确认后系统才会把这一版设为当前默认版本；以后还能通过新版本继续修订。
```
