# 20260505 Q001 second-subject candidate admission preflight

## 目标
- 在跳过人工现场任务期间，为 `Q001` 多学科扩展建立可执行 preflight 合同与 checklist。

## 结论
- `Q001` 保持 `待办`，本轮不改完成态。
- 已新增 `tools/run-q001-second-subject-candidate-admission-preflight-contract.ps1` 与 `docs/templates/q001-second-subject-candidate-admission-checklist.md`。

## 本轮边界
- 本轮不执行第二学科真实来源资料导入。
- 本轮不执行 candidate->reviewed->active 真实推进，仅保留 dry-run 准备。

## N/A 记录
- `platform_na`:
  - reason: 当前阶段按指令跳过人工现场链路，`P006` 尚未闭环，不能触发第二学科真实准入。
  - alternative_verification: 运行 Q001 preflight contract，验证依赖、清单与证据入口完整。
  - evidence_link: `docs/evidence/20260505-q001-second-subject-candidate-admission-preflight.md`
  - expires_at: `2026-05-20`
- `gate_na`:
  - reason: Q001 验收需要真实来源资料包准入执行，不属于本机 preflight 可替代范围。
  - alternative_verification: 先完成模板化 checklist 与 contract，待 P006 闭环后再做真实 admission。
  - evidence_link: `docs/templates/q001-second-subject-candidate-admission-checklist.md`
  - expires_at: `2026-05-20`

## 下一步
1. 等 `P006` 闭环后，执行第二学科 candidate admission dry-run/apply。
2. 回填真实 admission evidence，再将 `Q001` 从 `待办` 切到 `已完成`。
