# 20260505 P006 release decision preflight

## 目标
- 在不伪造发布裁决结论的前提下，建立 `P006` preflight 合同与发布裁决清单。

## 结论
- `P006` 保持 `待办`，不提前宣称 v0.1 发布裁决完成。
- `P006` 依赖 `P005`，当前 `P005` 仍为 `待办`，依赖链一致。
- 已新增 `tools/run-p006-release-decision-preflight-contract.ps1` 与 `docs/templates/p006-release-decision-checklist.md`。

## N/A 记录
- `platform_na`:
  - reason: 当前会话不包含真实发布审批上下文与最终 go/no-go 决策输入。
  - alternative_verification: 先执行 P006 preflight contract，确认发布裁决入口、清单与证据结构完整。
  - evidence_link: `docs/evidence/20260505-p006-release-decision-preflight.md`
  - expires_at: `2026-05-20`
- `gate_na`:
  - reason: P006 验收要求真实发布裁决记录，不可由本机 dry-run 替代。
  - alternative_verification: 完成 checklist 与 preflight 合同，待 P005 完成后回填 release decision record。
  - evidence_link: `docs/templates/p006-release-decision-checklist.md`
  - expires_at: `2026-05-20`

## 下一步
1. 先完成 `P005` 反馈分流结果。
2. 再按 P006 checklist 形成 release decision record 与 tag candidate 策略。
