# 55 · C002E Activation Guard

## 1. 目的

C002E 定义 source-derived candidate 进入 `active` 的阻断条件。它仍是 dry-run，不激活正式知识体系，只验证“什么时候绝对不能激活”。

## 2. 当前样例结论

样例必须阻断激活，因为仍存在：

- 候选资产待教师/备课组审核。
- C002B 中仍有 `pending_review` 映射。
- C002C 中仍有待审影响项。
- 历史学情报告已冻结但未确认接受。

## 3. 激活前硬条件

进入 `active` 前必须满足：

- 所有 candidate assets 已审核通过。
- `pendingReviewMappings = 0`。
- `pendingReviewImpacts = 0`。
- 历史学情冻结结果已确认。
- 来源证据完整。
- 回滚快照已准备。
- 有明确 `activationApprovedBy`。

## 4. 验证

样例计划：

```text
configs/domain-assets/c002e-activation-guard.sample.json
```

验证命令：

```powershell
.\tools\run-c002e-activation-guard-contract.ps1
```

Full gate 已接入：

```powershell
.\tools\run-gates.ps1
```

## 5. 回滚

```powershell
git restore --source=HEAD -- tools/run-gates.ps1 tools/README.md tasks/backlog.csv docs/20_TaskBreakdown.md
git clean -f -- configs/domain-assets/c002e-activation-guard.sample.json tools/run-c002e-activation-guard-contract.ps1 docs/55_C002E_ActivationGuard.md
```
