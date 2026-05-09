# 20260509 onsite/manual execution boundary (temporary)

- scope: 当前阶段按用户指令暂时跳过现场与人工现场执行环节，持续自动推进非现场可验证链路。
- applies_to:
  - `P003` onsite pilot admission execution
  - `P004` onsite pilot round1 execution
  - 任何需要真实现场人员参与和现场环境签署的执行面动作
- still_allowed:
  - preflight contract checks
  - checklist completeness checks
  - 非现场脚本、门禁、证据刷新与回滚链验证

## N/A record

- `platform_na`:
  - reason: 当前会话不进入现场执行环境，且用户明确要求暂缓现场人工环节。
  - alternative_verification: 保持 `P001-P006` preflight 合同可复跑，持续刷新非现场证据与依赖状态。
  - evidence_link: `docs/evidence/20260509-onsite-skip-boundary.md`
  - expires_at: until user re-enables onsite/manual execution
- `gate_na`:
  - reason: 现场执行类验收项（特别是 `P003/P004`）无法由本机会话 dry-run 替代。
  - alternative_verification: 执行对应 preflight 脚本与 checklist 结构校验，任务状态维持 `待办`。
  - evidence_link: `docs/templates/p003-onsite-pilot-admission-checklist.md`, `docs/templates/p004-onsite-pilot-round1-checklist.md`
  - expires_at: until user re-enables onsite/manual execution

## next

1. 继续自动推进非现场链路与门禁证据，不将 `P003/P004` 标记为完成。
2. 用户解除限制后，按 `P001 -> P002 -> P003 -> P004 -> P005 -> P006` 顺序执行现场链路并回填证据。
