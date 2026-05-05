# 20260505 Q002 second-subject teacher review template preflight

## 目标
- 在跳过人工现场任务期间，为 `Q002` 建立可执行 preflight 合同与 checklist。

## 结论
- `Q002` 保持 `待办`，本轮不改完成态。
- 已新增 `tools/run-q002-second-subject-teacher-review-template-preflight-contract.ps1` 与 `docs/templates/q002-second-subject-teacher-review-template-checklist.md`。

## 本轮边界
- 本轮不执行教师真实复核。
- 本轮只验证复核模板字段、依赖与证据入口是否可用。

## N/A 记录
- `platform_na`:
  - reason: 按当前策略先跳过现场链路，`Q001` 尚未真实闭环，无法进入教师复核执行面。
  - alternative_verification: 运行 Q002 preflight contract，确认模板和证据口径完整。
  - evidence_link: `docs/evidence/20260505-q002-second-subject-teacher-review-template-preflight.md`
  - expires_at: `2026-05-20`
- `gate_na`:
  - reason: Q002 需基于 Q001 实际候选包做教师复核，不可由本机 preflight 替代完成。
  - alternative_verification: 先完成 checklist 与 contract，待 Q001 完成后再补真实 review evidence。
  - evidence_link: `docs/templates/q002-second-subject-teacher-review-template-checklist.md`
  - expires_at: `2026-05-20`

## 下一步
1. Q001 闭环后，进入教师复核模板的真实演练与留痕。
2. 回填 review evidence，再将 `Q002` 从 `待办` 切到 `已完成`。
