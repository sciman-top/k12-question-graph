# 20260505 Q003 second-subject active drill preflight

## 目标
- 在跳过人工现场任务期间，为 `Q003` 建立可执行 preflight 合同与 checklist。

## 结论
- `Q003` 保持 `待办`，本轮不改完成态。
- 已新增 `tools/run-q003-second-subject-active-drill-preflight-contract.ps1` 与 `docs/templates/q003-second-subject-active-drill-checklist.md`。

## 本轮边界
- 本轮不执行第二学科 active apply。
- 本轮只验证 backup/readiness/reviewed/rollback snapshot 演练入口与证据链。

## N/A 记录
- `platform_na`:
  - reason: 当前会话仅做自动 preflight 推进，`Q002` 未闭环，active 演练执行条件不满足。
  - alternative_verification: 运行 Q003 preflight contract，确认演练前置条件和回滚入口完整。
  - evidence_link: `docs/evidence/20260505-q003-second-subject-active-drill-preflight.md`
  - expires_at: `2026-05-20`
- `gate_na`:
  - reason: Q003 验收需要真实 activation drill，不可由 preflight 直接替代。
  - alternative_verification: 先完成 checklist 与 contract，待 Q002 闭环后再做真实演练证据。
  - evidence_link: `docs/templates/q003-second-subject-active-drill-checklist.md`
  - expires_at: `2026-05-20`

## 下一步
1. Q002 闭环后执行第二学科 activation dry-run/apply 演练。
2. 回填 activation evidence，再将 `Q003` 从 `待办` 切到 `已完成`。
