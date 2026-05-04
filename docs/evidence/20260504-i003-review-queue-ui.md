# 2026-05-04 I003 人工确认队列可用性强化

## 规则 ID

- R1：当前落点为 I0 的 `I003`；目标归宿是减少人工确认队列中的重复操作。
- R2：本轮只做确认队列 UI 快捷路径，不扩大到真实 OCR/AI 准确率或 J006 工作量报告。
- R4：低风险前端和门禁脚本变更；不改 API、数据库 schema、真实资料、真实 AI、权限或 active 状态。
- R6：验证顺序为 I003 UI contract、frontend build/lint、P1 proxy scenario；full gate 已接入 I003 contract，后续 full gate 会覆盖。
- R8：依据、命令、证据和回滚如下。

## 变更

- `apps/web/src/App.tsx`
  - 人工确认队列新增摘要：待确认、已选择、预计处理。
  - 新增 `只看异常` 快捷动作。
  - 新增 `批量确认` 动作，减少逐项确认负担。
  - 保留既有合并、拆分、题图关联、撤销和失败接管合同。
- `apps/web/src/App.css`
  - 新增确认队列摘要样式。
- `tools/run-i003-review-queue-ui-contract.ps1`
  - 校验 `review-queue-summary`、`filter-exceptions`、`batch-confirm` 和既有 B004 操作 marker。
- `tools/run-gates.ps1`
  - 接入 `i003 review queue ui contract`。

## 已执行命令

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-i003-review-queue-ui-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-i002-import-wizard-ui-contract.ps1
npm run build
npm run lint
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-p1-proxy-scenario.ps1
```

## 关键输出

I003 UI contract：

```json
{
  "status": "pass",
  "task": "I003",
  "summaryVisible": true,
  "shortcutActions": [
    "filter-exceptions",
    "merge",
    "split",
    "associate",
    "undo",
    "batch-confirm"
  ],
  "batchConfirm": true
}
```

P1 proxy scenario：

```json
{
  "status": "pass",
  "uploadedSampleCount": 5,
  "sourceReviewVerified": true,
  "confirmationItemCount": 6,
  "estimatedTeacherMinutes": 8
}
```

frontend build/lint 均退出码 0。Vite chunk warning 仍归 `I007 bundle analysis`。

## 回滚

```powershell
git diff -- apps/web/src/App.tsx apps/web/src/App.css tools/run-i003-review-queue-ui-contract.ps1 tools/run-gates.ps1 tasks/backlog.csv docs/evidence/20260504-i003-review-queue-ui.md
```

如需撤销 I003，只还原上述文件，并把 `tasks/backlog.csv` 中 `I003` 状态改回 `待办`。本轮未修改数据库 schema、真实资料、权限、真实 AI 或 active 状态。
