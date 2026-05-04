# I006 新手示例与默认值闭环证据

## Goal
- 当前落点：`apps/web/src/App.tsx`、`apps/web/src/App.css`、`tools/run-i006-starter-defaults-ui-contract.ps1`、`tools/run-gates.ps1`、`tasks/backlog.csv`。
- 目标归宿：让首次使用者不读文档即可用默认样例走完导入、组卷、成绩导入和分析。
- 本轮 slice：低风险 UI/合同增强；不触碰数据库、真实资料、真实 AI、权限、备份恢复或 active switch。

## Changes
- 在普通教师首页新增 `first-run-starter-demo` 新手示例。
- 四个默认步骤分别跳转导入、组卷、成绩、分析入口，保持 I001 四入口导航合同。
- 文案避免脚本、evidence、schema 等技术术语，强调默认样例和无需先准备真实资料。

## Verification
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-i006-starter-defaults-ui-contract.ps1`
- `npm run build`
- `npm run lint`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gates.ps1`

## Risk And Rollback
- 风险等级：低。仅新增首页新手示例 UI 和本地合同脚本。
- 教师效率复核：首次使用路径减少到四个显式样例步骤，默认值为样卷、30 分草稿卷、样例成绩和讲评摘要。
- 回滚：Git 回滚上述文件；无数据、备份、权限或 active switch 回滚需求。
