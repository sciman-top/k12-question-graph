# 2026-05-04 I001 普通教师首页与导航产品化

## 规则 ID

- R1：当前落点为 I0 的 `I001`；目标归宿是让普通教师首页默认只面对四个高频入口。
- R2：本轮做前端窄切和 UI contract，不扩大到 I002-I007。
- R4：低风险前端改动；不改 API、数据库、真实资料、真实 AI、权限、备份或 active 状态。
- R6：验证顺序为 UI contract、frontend build、frontend lint；Vite chunk warning 继续归 I007。
- R8：依据、命令、证据和回滚如下。

## 变更

- `apps/web/src/App.tsx`
  - 新增 `TeacherView` 和 `activeTeacherView`。
  - 四个默认入口成为真实导航：导入试卷、找题组卷、导入成绩、查看分析。
  - 新增普通教师侧成绩导入和讲评分析工作台。
  - 首页文案改为教师可理解口径，不再把默认入口写成 P0/P4/P5。
- `apps/web/src/App.css`
  - 默认隐藏管理员/治理面板。
  - 根据当前教师入口只展示对应工作区。
  - 增加四入口 active state、成绩导入步骤和讲评摘要样式。
- `tools/run-i001-teacher-home-ui-contract.ps1`
  - 校验四入口、默认视图、管理员面板默认隐藏和关键 UI marker。

## 已执行命令

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-i001-teacher-home-ui-contract.ps1
npm run build
npm run lint
```

## 关键输出

UI contract：

```json
{
  "status": "pass",
  "task": "I001",
  "defaultEntryCount": 4,
  "defaultView": "import",
  "adminPanelsHiddenByDefault": true
}
```

frontend build：

```text
✓ built
dist/assets/index-C2jENt-G.js   576.83 kB │ gzip: 185.92 kB
```

frontend lint：

```text
eslint .
```

退出码为 0。

## 已知非阻断项

- Vite 仍提示部分 chunk 超过 500 kB。该问题已归入 `I007 server-state 与 typed API boundary` 的 `bundle analysis`，本轮不通过提高阈值处理。
- I001 只证明首页和导航默认面向普通教师；导入向导、人工确认队列、组卷工作台、成绩工作台的完整产品化分别归 `I002-I005`。

## 回滚

```powershell
git diff -- apps/web/src/App.tsx apps/web/src/App.css tools/run-i001-teacher-home-ui-contract.ps1 tasks/backlog.csv docs/evidence/20260504-i001-teacher-home-ui.md
```

如需撤销 I001，只还原上述文件，并把 `tasks/backlog.csv` 中 `I001` 状态改回 `待办`。本轮未修改数据库、备份包、真实资料、权限、真实 AI 或 active 状态。
