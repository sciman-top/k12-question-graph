# 2026-05-04 H003 教师效率基线复测

## 规则 ID

- R1：当前落点为 H0 阶段收口的 `H003`；目标归宿是建立下一轮 I/J/M/N/P 可对比的教师效率 baseline。
- R2：本轮只记录代理 walkthrough 和现有合同支撑下的步骤/耗时/接管点，不改运行功能。
- R4：低风险证据与 backlog 状态变更；不处理真实学生数据，不调用真实外部 AI，不执行新的 active switch。
- R6：H003 的 hotspot 是教师效率复核；本轮用 P1 proxy scenario、E/F 合同证据和文档指标形成替代基线。
- R8：依据、命令、证据和回滚如下。

## 基线口径

本文件是代理基线，不是现场教师实测。后续 `P002/P004` 试点必须用真实授权或脱敏材料、真实教师或教师代理记录重新测量。

| 流程 | 当前代理步骤数 | 当前代理耗时 | 异常接管点 | 证据 |
|---|---:|---:|---|---|
| 导入试卷 | 5 | 8 分钟 | 6 个确认项；6 个失败接管步骤 | `tools/run-p1-proxy-scenario.ps1` fresh run |
| 找题组卷 | 6 | 目标 <= 10 分钟，当前仅 proxy target | 检索无结果、系统理解偏差、换题不合适、约束迁移影响 | E001-E003 draft/test 合同；README 10 分钟目标 |
| Word/PDF 导出 | 3 | 代理估算 1-2 分钟 | DOCX/PDF 生成失败、公式/题图/表格缺失、导出前审校缺失 | `docs/evidence/e004-paper-export-report.json` |
| 成绩导入与分析 | 6 | 代理估算 6-8 分钟 | 字段缺失、题号不匹配、异常行、真实学生数据禁用 | `docs/evidence/f002-score-import-report.json`、`docs/evidence/f003-knowledge-mastery-analysis-report.json` |

## 导入试卷 fresh walkthrough

`tools\run-p1-proxy-scenario.ps1` 输出：

```json
{
  "status": "pass",
  "scenario": "P1 proxy import walkthrough",
  "uploadedSampleCount": 5,
  "previewVerified": true,
  "questionSaved": true,
  "sourceReviewVerified": true,
  "confirmationItemCount": 6,
  "estimatedTeacherMinutes": 8
}
```

确认项：

- merge cross-page segments
- split over-cut segment
- associate shared image
- review formula dense item
- review scanned placeholder
- separate answer and solution

失败接管步骤：

- keep original file
- keep adapter diagnostics
- manual box source region
- split or merge affected segments
- skip bad page when needed
- rerun adapter when source is fixed

## 组卷与导出基线

- `README.md` 与 PRD 目标：普通教师从自然语言需求到可打印 Word/PDF 初稿不超过 10 分钟。
- 当前 E001-E004 证明的是 draft/test 合同：题库检索、系统理解、一键换题/撤销和 Word/PDF 导出工件可用。
- 当前还没有真实教师现场耗时，也没有完成 I0/M0 产品化工作台，因此 H003 只把 10 分钟作为后续 I004/M006 的对比目标，不把它声明为已现场达成。
- E004 证据显示 DOCX/PDF 均生成，公式文本、题图媒体和表格检查通过，`productionEligible=false`。

## 成绩导入与分析基线

- F002 证据：3 行 synthetic Excel 中 2 行导入成功，1 行异常集中返回；字段映射模板可复用；`realStudentDataUsed=false`。
- F003 证据：基于 synthetic 小题分输出班级得分率、知识点得分率、区分度、薄弱知识点和学生掌握摘要；`noProductionHistoryWrite=true`。
- 当前成绩链路只证明 draft/test 合同和代理步骤，不代表已经处理真实学生数据或正式学情口径。

## 已执行命令

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-p1-proxy-scenario.ps1
rg -n "teacher-efficiency|教师效率|proxy walkthrough|proxy scenario|步骤数|耗时|异常接管|10 分钟|工作量|teacher" README.md docs tasks tools tests apps
```

## 后续使用

- `I001-I006`：减少普通教师入口、跳转、设置和术语负担。
- `J006`：用真实文档解析报告补充切题准确率、人工确认题数和失败接管耗时。
- `M006`：重新验证 10 分钟组卷场景。
- `P002/P004`：用试点材料和现场教师反馈替换本代理基线。

## 回滚

```powershell
git diff -- tasks/backlog.csv docs/evidence/20260504-h003-teacher-efficiency-baseline.md
```

如需撤销 H003 收口，只把 `tasks/backlog.csv` 中 `H003` 状态改回 `待办`，并删除本证据文件。本轮未修改运行代码、数据库、备份包、真实资料、权限或 active 状态。
