# I004 找题组卷工作台整合证据

## Goal
- 当前落点：`apps/web/src/App.tsx`、`apps/web/src/App.css`、`tools/run-i004-paper-workbench-ui-contract.ps1`、`tools/run-gates.ps1`、`tasks/backlog.csv`。
- 目标归宿：把 E001 题库检索、E002 自然语言组卷、E003 换题、E004 导出入口汇总为普通教师同一屏可理解的组卷工作台。
- 本轮 slice：低风险 UI/合同增强，不触碰数据库、真实资料、真实 AI、active switch、权限或备份恢复链路。

## Changes
- 新增 `data-flow="paper-assembly-workbench"` 顶层工作台，直接暴露找题、题篮、细目表、换题和导出 5 个步骤。
- 增加 `question-basket`、`blueprint-table-entry`、`replacement-entry`、`export-entry` 和 `ten-minute-target` 合同标记。
- 保留原 E001-E004 面板和合同标记，避免破坏既有 API/导出/换题验证。
- 移除 `.guardrail-panel` 后置 `display:flex` 覆盖，保持 I001 普通教师首页不暴露治理面板的显示合同。

## Verification
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-i004-paper-workbench-ui-contract.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-e001-question-search-contract.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-e002-paper-request-contract.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-e003-question-replacement-contract.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-e004-paper-export-contract.ps1`
- `npm run build`
- `npm run lint`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`

## Risk And Rollback
- 风险等级：低。仅新增前端静态工作台和本地合同脚本。
- 兼容性：保留 E001-E004 的 `data-flow`、`data-contract`、`data-action` 标记。
- 回滚：Git 回滚上述文件；无数据库、文件存储、真实资料或 active switch 回滚需求。
