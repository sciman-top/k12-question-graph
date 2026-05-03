# 54 · C002D Source-Derived Admission

## 1. 目的

C002D 将“来源提炼正式知识点”拆成可验证的候选准入合同。它不把 C002 标记为正式完成，也不激活生产知识体系；只验证候选资产是否具备来源证据、审核边界和后续替换/影响计划入口。

## 2. 准入要求

候选资产必须：

- 引用 `configs/knowledge/source-material-manifest.example.json` 或本地等价 manifest。
- 覆盖教材、课程标准、当地考试资料三类来源。
- `status = candidate`。
- `authority = source_derived`。
- `reviewStatus = pending_review`。
- 禁止 `active`。
- 禁止引用仓库内真实资料路径。
- 禁止使用未脱敏学生 PII。
- 指向 C002B replacement plan 和 C002C impact plan。

## 3. 验证

样例计划：

```text
configs/domain-assets/c002d-source-derived-admission.sample.json
```

验证命令：

```powershell
.\tools\run-c002d-source-derived-admission-contract.ps1
```

Full gate 已接入：

```powershell
.\tools\run-gates.ps1
```

## 4. 仍不代表正式 C002 完成

C002D 只证明候选正式资产的准入合同成立。当前正式 C002 v1 已由 C002S/C002M/C002T 完成质量审查、审核决策、回滚快照和 active 受控切换；后续修订仍必须重新走 candidate、review、impact、rollback 和 active guard。

## 5. 回滚

```powershell
git restore --source=HEAD -- tools/run-gates.ps1 tools/README.md tasks/backlog.csv docs/20_TaskBreakdown.md
git clean -f -- configs/domain-assets/c002d-source-derived-admission.sample.json tools/run-c002d-source-derived-admission-contract.ps1 docs/54_C002D_SourceDerivedAdmission.md
```
