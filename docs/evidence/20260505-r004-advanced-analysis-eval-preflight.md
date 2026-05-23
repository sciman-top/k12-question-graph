# 20260505 R004 advanced analysis eval preflight
- preflight only；`R004` 保持待办，不改完成态。
- platform_na：复杂高级分析需要样本量与解释边界，不在当前会话直接落地（高级分析）。
- gate_na：仅完成 checklist/contract 预检，不替代 research note + feature admission。
- 下一步：在 N004 基础上补样本与解释责任，再决定是否进入 IRT/等值评估。
- 2026-05-19 refresh：`tools/run-r004-advanced-analysis-eval-preflight-contract.ps1` 会生成机器可读 admission report；当前只允许基础 CTT/draft-test 讲评指标，IRT、等值、长期成长分析保持 fail-closed。
- 2026-05-20 refresh：`docs/decisions/ADR-006-advanced-analysis-admission.md` 已接受 fail-closed 裁决；后续任何 IRT/等值/长期成长实现必须先过 ADR 后的 feature admission。
