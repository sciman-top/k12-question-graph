# 115 · REAL005 细化执行树

日期：2026-06-15。

## 1. 用途

本文件不改变 `tasks/live-pilot-closeout-plan.csv` 的顶层结构，也不改写 `REAL005 = not_closed` 的 truth boundary。

它只回答两个问题：

1. `REAL005B / REAL005C` 再往下到底怎么切，才适合单次执行和单次验证？
2. 每个细切片失败时，应该继续保持 `not_closed` 的哪一条 gap？

顶层执行顺序仍以 `tasks/live-pilot-closeout-plan.csv` 为准：

- `REAL005A`：逐年来源与 adapter 覆盖
- `REAL005B`：逐题结构化与审核覆盖
- `REAL005C`：真实题使用链与回滚隐私覆盖
- `REAL005D`：闭环口径复核与对外文案收口

## 2. 当前边界

- `REAL005A` 已完成，但不代表真卷闭环已完成。
- 当前 next open slice 仍是 `REAL005B`。
- 只有 `REAL005A/B/C` 全部通过后，`REAL005D` 才允许改写对外文案。
- 任一细切片未通过时，`docs/112_CurrentClosureStatus_20260609.md`、`docs/109_ReleaseGoNoGoCard.md`、`tasks/completion-state-dashboard.csv` 都必须继续保持 `not_closed`。

## 3. REAL005B 细化

### REAL005B1 · `RG003` 逐年题数与题号连续性

- 目标：逐年建立 expected question count，并确认 `question_items / cut_candidates / review_queue_items` 与题号连续性一致。
- 负责人：题库/导入负责人
- 主要证据：
  - `docs/evidence/*-real005-guangzhou-2015-2025-closure-standard-report.json`
  - 逐年 ingest / diagnostics 报告
- 验证：
  - `tools/run-real005-guangzhou-2015-2025-closure-standard.ps1`
- 未通过时保持的 gap：
  - `missing expected count or any missing question keeps closure not_closed`

### REAL005B2 · `RG004` 逐题答案锚定

- 目标：每题都要么有答案锚点，要么有明确人工接管原因。
- 负责人：题库/导入负责人
- 主要证据：
  - `docs/evidence/*-real005-guangzhou-2015-2025-closure-standard-report.json`
- 验证：
  - 复用 `tools/run-real005-guangzhou-2015-2025-closure-standard.ps1`
- 未通过时保持的 gap：
  - `missing answer without takeover reason keeps closure not_closed`

### REAL005B3 · `RG005` 来源区域与题图资产完备性

- 目标：每题都有可回看来源页和 `SourceRegion`；图题/实验题/作图题具备截图级区域或题图资产。
- 负责人：题库/导入负责人
- 主要证据：
  - `docs/evidence/*-real005-guangzhou-2015-2025-closure-standard-report.json`
  - `docs/evidence/*-real005b-question-structure-diagnostics.json`
- 验证：
  - `tools/run-real005-guangzhou-2015-2025-closure-standard.ps1`
  - `tools/run-real005b-question-structure-diagnostics.ps1`
- 未通过时保持的 gap：
  - `placeholder bbox without gate_na evidence keeps closure not_closed`

### REAL005B4 · `RG006` 结构化题目字段完备性

- 目标：题干、选项、小问、答案、解析、公式、表格、图片字段必须结构化保存，或明确进入 `pending_review`。
- 负责人：题库/导入负责人
- 主要证据：
  - `docs/evidence/*-real005-guangzhou-2015-2025-closure-standard-report.json`
  - `docs/evidence/*-real005b-question-structure-diagnostics.json`
- 验证：
  - `tools/run-real005b-question-structure-diagnostics.ps1`
- 未通过时保持的 gap：
  - `raw text only without review reason keeps closure not_closed`

### REAL005B5 · `RG007` 标签/难度/题型建议来源与 no-active-write

- 目标：知识点、题型、难度、标签来自 deterministic seed 或 AI candidate，并保持 `pending_review` 直到教师确认。
- 负责人：题库/导入负责人
- 主要证据：
  - `docs/evidence/*-real005-guangzhou-2015-2025-closure-standard-report.json`
  - 相关 tagging / no-active-write 报告
- 验证：
  - 复用 `tools/run-real005-guangzhou-2015-2025-closure-standard.ps1`
- 未通过时保持的 gap：
  - `tag missing or AI direct active write keeps closure not_closed`

### REAL005B6 · `RG008-RG009` 审核终态与来源回看链路

- 目标：审核必须形成 terminal status、audit 记录，且审核后题目仍能从详情页回看来源页、区域、答案、标签和风险。
- 负责人：题库/导入负责人
- 主要证据：
  - `docs/evidence/*-real005-guangzhou-2015-2025-closure-standard-report.json`
  - 真实题审核 smoke / source review smoke
- 验证：
  - `tools/run-real005-guangzhou-2015-2025-review-smoke.ps1` 或等价真实题审核 smoke
  - 复用 `tools/run-real005-guangzhou-2015-2025-closure-standard.ps1`
- 未通过时保持的 gap：
  - `open queue or no audit keeps closure not_closed`
  - `source review failure keeps closure not_closed`

## 4. REAL005C 细化

### REAL005C1 · `RG010` 真实题检索 / 题篮 / 导出链

- 目标：真实已审核题进入检索、题篮、组卷、导出预检和 Word/PDF 导出链。
- 负责人：题库/导入负责人
- 主要证据：
  - `docs/evidence/*-real005-guangzhou-2015-2025-closure-standard-report.json`
  - `REAL012` 相关真实题生产链 smoke
- 验证：
  - 复用 `tools/run-real005-guangzhou-2015-2025-closure-standard.ps1`
  - `tools/run-real012-production-flow-quality-smoke.ps1`
- 未通过时保持的 gap：
  - `only synthetic fixture proof keeps closure not_closed`

### REAL005C2 · `RG011` 学情分析只引用已审核题与 active 知识版本

- 目标：学情分析和讲评报告只引用已审核题和 active 知识版本；AI 只写 draft 文案。
- 负责人：题库/导入负责人
- 主要证据：
  - `docs/evidence/*-real005-guangzhou-2015-2025-closure-standard-report.json`
  - 分析 smoke / commentary smoke
- 验证：
  - 复用 `tools/run-real005-guangzhou-2015-2025-closure-standard.ps1`
- 未通过时保持的 gap：
  - `synthetic-only analysis proof keeps closure not_closed`

### REAL005C3 · `RG012` rollback / privacy / no-active-write 批次证据

- 目标：每个写库批次保留 dry-run/apply 证据、定向 rollback SQL、privacy=0、external AI policy、cost/cache、no-active-write 证据。
- 负责人：题库/导入负责人
- 主要证据：
  - `docs/evidence/*-real005-guangzhou-2015-2025-closure-standard-report.json`
  - rollback / privacy / AI boundary 报告
- 验证：
  - 复用 `tools/run-real005-guangzhou-2015-2025-closure-standard.ps1`
- 未通过时保持的 gap：
  - `missing rollback or privacy evidence keeps closure not_closed`

### REAL005C4 · `RG013-RG015` 版面噪声 / 公式保真 / 表格结构化

- 目标：页眉页脚等噪声被显式排除；公式保留 OMML/fallback/reviewStatus；表格以 `table block JSON` 结构化保存。
- 负责人：题库/导入负责人
- 主要证据：
  - `docs/evidence/*-real005-guangzhou-2015-2025-closure-standard-report.json`
  - `REAL007 / REAL009 / REAL010` 相关报告
- 验证：
  - `tools/run-real007-guangzhou-2015-layout-quality.ps1`
  - `tools/run-real009-table-structure-smoke.ps1`
  - `tools/run-real010-formula-fidelity-smoke.ps1`
- 未通过时保持的 gap：
  - `noise retained in question content without review reason keeps closure not_closed`
  - `formula OCR candidate without fallback image or reviewStatus keeps closure not_closed`
  - `table only stored as image without pending_review reason keeps closure not_closed`

### REAL005C5 · `RG016` 编辑 / 重裁 / 审计闭环

- 目标：题干、答案、解析、标签、bbox、题图、表格、公式的修改都必须通过可审计编辑或重裁入口完成。
- 负责人：题库/导入负责人
- 主要证据：
  - `docs/evidence/*-real005-guangzhou-2015-2025-closure-standard-report.json`
  - `REAL011` 相关异常编辑/重裁 smoke
- 验证：
  - `tools/run-real011-question-edit-smoke.ps1`
- 未通过时保持的 gap：
  - `manual correction path missing or no audit keeps closure not_closed`

## 5. REAL005D 什么时候才能开始

只有在以下条件同时满足时，才允许进入 `REAL005D`：

1. `REAL005A` 仍为已完成。
2. `REAL005B1-B6` 全部完成。
3. `REAL005C1-C5` 全部完成。
4. `tools/run-real005-guangzhou-2015-2025-closure-standard.ps1` 最新报告允许 `fullClosureAllowed = true`。

在此之前：

- `docs/112_CurrentClosureStatus_20260609.md` 继续写 `not_closed`
- `docs/109_ReleaseGoNoGoCard.md` 继续写 `No-Go`
- `tasks/completion-state-dashboard.csv` 继续保留 `REAL005 当前只能输出 not_closed`
