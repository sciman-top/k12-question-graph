# 20260505 Q004 cross-subject diff report preflight

## 目标
- 在跳过人工现场任务期间，为 `Q004` 建立可执行 preflight 合同与 checklist。

## 结论
- `Q004` 保持 `待办`，本轮不改完成态。
- 已新增 `tools/run-q004-cross-subject-diff-report-preflight-contract.ps1` 与 `docs/templates/q004-cross-subject-diff-report-checklist.md`。

## 本轮边界
- 本轮不生成最终跨学科差异报告正文。
- 本轮只验证差异报告范围、依赖关系与证据入口。

## N/A 记录
- `platform_na`:
  - reason: `Q003` 未完成，跨学科差异报告缺少上游真实激活演练输入。
  - alternative_verification: 运行 Q004 preflight contract，验证题型/标签/评分/导出/分析差异检查项完整。
  - evidence_link: `docs/evidence/20260505-q004-cross-subject-diff-report-preflight.md`
  - expires_at: `2026-05-20`
- `gate_na`:
  - reason: Q004 验收需要基于真实第二学科演练输出，不可由 preflight 替代。
  - alternative_verification: 先完成 checklist 与 contract，待 Q003 闭环后再提交正式差异报告。
  - evidence_link: `docs/templates/q004-cross-subject-diff-report-checklist.md`
  - expires_at: `2026-05-20`

## 下一步
1. Q003 闭环后补充跨学科差异报告与 `docs/58` 更新。
2. 回填 diff report evidence，再将 `Q004` 从 `待办` 切到 `已完成`。
