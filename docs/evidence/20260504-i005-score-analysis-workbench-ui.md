# I005 成绩导入分析工作台整合证据

## Goal
- 当前落点：`apps/web/src/App.tsx`、`apps/web/src/App.css`、`tools/run-i005-score-analysis-workbench-ui-contract.ps1`、`tools/run-gates.ps1`、`tasks/backlog.csv`。
- 目标归宿：把 F001/F002/F003 已验证的成绩模型、Excel 字段映射导入和知识点分析，用普通教师可理解的单屏工作台承接。
- 本轮 slice：低风险 UI/合同增强；不使用真实学生数据，不写正式历史学情，不触碰 active switch、权限、备份恢复或真实 AI。

## Changes
- 成绩入口改为“成绩导入分析工作台”，同屏展示上传 Excel、生成分析、导出报告。
- 增加字段映射预览、异常行、知识点分析摘要和报告导出路径的合同标记。
- 保留 `score-import-workbench` 与 `teacher-analysis-workbench` 既有入口，避免破坏 I001 首页导航合同。
- 明确展示 `productionEligible=false`、synthetic fixture、无真实学生数据和无正式历史学情写入边界。

## Verification
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-i005-score-analysis-workbench-ui-contract.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-f001-assessment-model-contract.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-f002-score-import-contract.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-f003-knowledge-mastery-analysis-contract.ps1`
- `npm run build`
- `npm run lint`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`

## Risk And Rollback
- 风险等级：低。仅新增前端工作台和本地合同脚本。
- 兼容性：保留 F001-F003 数据/合同边界和 I001 teacher view。
- 回滚：Git 回滚上述文件；无数据库迁移、真实数据、备份或 active switch 回滚需求。
