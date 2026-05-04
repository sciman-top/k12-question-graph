# 2026-05-04 I002 导入试卷向导产品化

## 规则 ID

- R1：当前落点为 I0 的 `I002`；目标归宿是把上传、任务状态、异常确认、来源回看和失败接管收敛到普通教师导入向导。
- R2：本轮只做前端导入向导窄切、UI contract 和统一 gate 接入，不扩大到 I003 批量确认优化。
- R4：低风险前端和门禁脚本变更；不改 API、数据库 schema、真实资料、真实 AI、权限或 active 状态。
- R6：验证顺序为 I002 UI contract、frontend build/lint、P1 proxy scenario、full gate。
- R8：依据、命令、证据和回滚如下。

## 变更

- `apps/web/src/App.tsx`
  - 在导入视图新增 `paper-import-wizard`。
  - 四步导入路径：上传文件、查看状态、确认异常、回看来源。
  - 上传入口、任务状态、异常确认、来源页预览和失败接管保持在 `teacher-view-import` 下。
  - `manual-review` 面板新增 `import-wizard-review` 与 `source-review` contract。
- `apps/web/src/App.css`
  - `status-panel` 只在导入视图展示。
  - 新增导入步骤和上传区域样式。
- `tools/run-i002-import-wizard-ui-contract.ps1`
  - 校验上传、状态、异常确认、来源回看、失败接管 marker。
- `tools/run-gates.ps1`
  - 接入 `i001 teacher home ui contract`。
  - 接入 `i002 import wizard ui contract`。

## 已执行命令

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-i002-import-wizard-ui-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-i001-teacher-home-ui-contract.ps1
npm run build
npm run lint
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-p1-proxy-scenario.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-gates.ps1
```

## 关键输出

I002 UI contract：

```json
{
  "status": "pass",
  "task": "I002",
  "wizardSteps": [
    "upload",
    "job_status",
    "exception_review",
    "source_review"
  ],
  "failureTakeover": true,
  "sameTeacherView": "import"
}
```

P1 proxy scenario：

```json
{
  "status": "pass",
  "uploadedSampleCount": 5,
  "previewVerified": true,
  "questionSaved": true,
  "sourceReviewVerified": true,
  "confirmationItemCount": 6,
  "estimatedTeacherMinutes": 8
}
```

frontend build/lint 均退出码 0。Vite chunk warning 仍归 `I007 bundle analysis`。

full gate：

```json
{
  "status": "pass",
  "steps": [
    "i001 teacher home ui contract",
    "i002 import wizard ui contract",
    "b001 duplicate upload smoke",
    "b003 source preview smoke",
    "b005 save question api smoke",
    "b006 question source review smoke",
    "b007 golden import regression",
    "b008 p1 proxy scenario",
    "backup verify"
  ]
}
```

本次 full gate 备份校验通过：

```text
D:\KQG_Backups\20260504-111729\manifest.json
```

## 回滚

```powershell
git diff -- apps/web/src/App.tsx apps/web/src/App.css tools/run-i002-import-wizard-ui-contract.ps1 tools/run-gates.ps1 tasks/backlog.csv docs/evidence/20260504-i002-import-wizard-ui.md
```

如需撤销 I002，只还原上述文件，并把 `tasks/backlog.csv` 中 `I002` 状态改回 `待办`。本轮未修改数据库 schema、真实资料、权限、真实 AI 或 active 状态。
