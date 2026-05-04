# 96 · K005 C002 第二批修订演练

## 目标

K005 在 C002R 已建立的版本化修订合同之上，补一轮第二批 synthetic 修订演练。它验证从 `candidate` 到 `reviewed` 再到 `active_dry_run` 的完整链路，但不执行真实 active 切换。

## 验证入口

```powershell
.\tools\run-k005-c002-second-revision-drill-contract.ps1
```

该合同会先运行 C002R 依赖合同，再读取：

```text
configs/domain-assets/k005-c002-second-revision-drill.sample.json
```

证据报告写入：

```text
docs/evidence/k005-c002-second-revision-drill-report.json
```

## 覆盖范围

- `candidate`: 基于当前 active C002 v1 生成第二批 candidate，`productionEligible=false`，不原地编辑旧 active。
- `reviewed`: synthetic 备课组长审查通过，只批准进入 active dry-run，要求 review reason，且 blocker 为 0。
- `active_dry_run`: 仅预演管理员切换，`apply=false`，普通教师不能切换 active，旧 active 保留。
- mapping: 覆盖 `broader`、`split`、`deprecated` 三类第二批高影响样例。
- impact: 覆盖题目绑定、组卷蓝图和历史学情指标，学情指标继续冻结历史快照。
- rollback: active pointer、mapping edges、impact targets、historical analysis snapshots 都必须进入 rollback snapshot。

## 边界

K005 是 dry-run 合同，不写数据库、不修改 active 知识资产、不使用真实教师或学生数据、不改写生产历史。真实生产修订仍必须走 C002R 管理员审核、备份、回滚和 active switch guard。

## 回滚

回滚优先使用 Git revert K005 变更。K005 合同不执行 DB 或 active 写入，因此无需额外数据库恢复或 active pointer 回退。
