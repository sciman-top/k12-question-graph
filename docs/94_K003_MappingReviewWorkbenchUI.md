# 94 · K003 映射审核工作台 UI

K003 把 C002H 的映射审核预处理合同承接到 Web UI。目标不是直接修改生产知识体系，而是让教师、备课组或管理员能低负担审核高影响映射。

## UI 合同

工作台默认聚焦：

- `pending_review`
- 低置信度
- 高影响
- 一对多、多对一、多对多等复杂基数

每个审核项并排显示：

- 旧对象。
- 新对象。
- 映射边。
- 来源证据。
- 影响预览。
- 回滚预览。
- 审核记录。

本轮样例覆盖 `split`、`merge`、`deprecated` 三类高风险映射。允许教师执行确认、改目标、拆分、合并和撤销；批量确认只允许低风险一对一映射，高风险项不得批量直接通过。

## 验证入口

```powershell
.\tools\run-k003-mapping-review-workbench-ui-contract.ps1
```

该合同会先运行 `tools/run-c002h-mapping-review-workbench-contract.ps1`，再检查 Web UI：

- `data-flow="c002h-mapping-review-workbench-ui"` 存在。
- split/merge/deprecated、高影响、复杂基数 marker 存在。
- 旧对象、新对象、映射边、来源证据、影响预览和回滚预览完整。
- 审核记录包含 `reviewer`、`decision`、`reviewReason`、`beforeSnapshot`、`afterSnapshot`。
- 高风险批量确认、直接 active apply、直接 migration action 不存在。

报告写入 `docs/evidence/k003-mapping-review-workbench-ui-report.json`，并纳入 `tools/run-gates.ps1`。

## 边界

- 不写数据库。
- 不修改 active C002 v1。
- 不执行 migration。
- 不调用外部 AI。
- 不使用真实学生数据。

## 回滚

代码回滚优先使用 Git revert。本任务只有 UI、合同脚本、文档和证据报告；无需数据库或文件仓库回滚。
