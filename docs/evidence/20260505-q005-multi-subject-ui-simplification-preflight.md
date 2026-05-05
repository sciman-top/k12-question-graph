# 20260505 Q005 multi-subject UI simplification preflight

## 目标
- 在跳过人工现场任务期间，为 `Q005` 建立可执行 preflight 合同与 checklist。

## 结论
- `Q005` 保持 `待办`，本轮不改完成态。
- 已新增 `tools/run-q005-multi-subject-ui-simplification-preflight-contract.ps1` 与 `docs/templates/q005-multi-subject-ui-simplification-checklist.md`。

## 本轮边界
- 本轮不执行多学科真实 UI 简化验收。
- 本轮只验证四入口约束、学科切换约束与证据入口。

## N/A 记录
- `platform_na`:
  - reason: `Q004` 未闭环，缺少跨学科差异报告输入，不能进入最终 UI 简化复核。
  - alternative_verification: 运行 Q005 preflight contract，确认四入口和学科切换约束项完整。
  - evidence_link: `docs/evidence/20260505-q005-multi-subject-ui-simplification-preflight.md`
  - expires_at: `2026-05-20`
- `gate_na`:
  - reason: Q005 需基于真实多学科输入做 UI smoke 与教师效率复测，preflight 不可替代完成态。
  - alternative_verification: 先完成 checklist 与 contract，待 Q004 闭环后执行真实 UI 验收。
  - evidence_link: `docs/templates/q005-multi-subject-ui-simplification-checklist.md`
  - expires_at: `2026-05-20`

## 下一步
1. Q004 闭环后执行多学科 UI smoke 与 teacher efficiency 复测。
2. 回填 UI evidence，再将 `Q005` 从 `待办` 切到 `已完成`。
