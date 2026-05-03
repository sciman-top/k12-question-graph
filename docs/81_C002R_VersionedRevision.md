# 81 · C002R 知识体系版本治理与便捷修订闭环

## 目标

C002 已经完成为当前初中物理生产默认 v1，但这不表示知识体系永久冻结。C002R 把后续教材、课标、中考趋势或教师修正收敛成一个可验证修订闭环：不直接改旧 active，先生成新 candidate 版本，再生成映射、影响报告、审核记录、回滚快照，最后才允许管理员通过既有 active guard 切换。

## 教师侧最小动作

教师只提交四类信息：

1. 修订原因。
2. 来源证据，例如资料、页码、截图或题号。
3. 影响范围，例如某一章、某一类考点或某批题。
4. 紧急程度。

教师不需要填写 `ImportKey`、`MigrationKey`、mapping type、rollback key 或 evidence JSON。系统把这些细节下沉到管理员和脚本层。

## 机器合同

验证入口：

```powershell
.\tools\run-c002r-versioned-revision-contract.ps1
```

该合同当前只做 dry-run，不写数据库、不写 active。报告写入 `docs/evidence/c002r-versioned-revision-report.json`。它验证：

- 起点必须是已 active 的 C002 v1。
- 修订必须创建 `candidate` 版本，且 `productionEligible=false`。
- 旧 active 不允许原地编辑。
- 映射必须覆盖 `equivalent/split/merge/broader/narrower/renamed/deprecated`。
- 一拆多、多合一、低置信度、高影响或废弃类变更必须人工审核并填写理由。
- 影响报告必须覆盖题目绑定、组卷蓝图、搜索索引、学情指标、导出模板和 Excel 字段模板。
- 学情指标只能冻结历史快照，不得静默改写旧学情口径。
- active 切换仍只能由管理员通过激活流水线执行，普通教师端不暴露直接切换动作。
- 回滚演练必须覆盖 active 版本、映射边、影响目标和历史学情复核。

## 后续生产化入口

C002R 只定义 active 后修订合同。真实持久化生产化时应复用现有动态资产表和激活流水线：

```powershell
.\tools\run-domain-asset-activation.ps1 `
  -ImportKey '<revision_candidate_import_key>' `
  -MaterialBatchKey '<revision_source_material_batch_key>' `
  -EvidencePrefix '<subject>-revision' `
  -GenerateDecisionFile `
  -ApplyReview
```

审核和回滚快照齐备后，才允许：

```powershell
.\tools\run-domain-asset-activation.ps1 `
  -ImportKey '<revision_candidate_import_key>' `
  -MaterialBatchKey '<revision_source_material_batch_key>' `
  -EvidencePrefix '<subject>-revision' `
  -ApplyActivation
```

## 完成判定

C002R 当前完成标准是合同层完成：`tools/run-c002r-versioned-revision-contract.ps1` 通过，并纳入 `tools/run-gates.ps1`。它不表示已经发生新的知识体系修订，也不表示真实教师修订已生产应用。
