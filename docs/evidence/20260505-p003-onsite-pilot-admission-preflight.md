# 20260505 P003 onsite pilot admission preflight

## 目标
- 在不伪造现场准入结论的前提下，建立 `P003` preflight 合同与准入清单。
- 本轮范围：现场教师试点准入 preflight，仅验证依赖与准入入口，不执行现场动作。

## 结论
- `P003` 保持 `待办`，不提前宣称现场准入完成。
- `P003` 依赖 `P002`，当前 `P002` 仍为 `待办`，依赖链一致。
- 已新增 `tools/run-p003-onsite-pilot-admission-preflight-contract.ps1` 与 `docs/templates/p003-onsite-pilot-admission-checklist.md`。

## N/A 记录
- `platform_na`:
  - reason: 当前会话不在真实现场试点准入环境，缺少现场教师参与与授权签署上下文。
  - alternative_verification: 先执行 P003 preflight contract，确认依赖、清单和证据入口完整。
  - evidence_link: `docs/evidence/20260505-p003-onsite-pilot-admission-preflight.md`
  - expires_at: `2026-05-20`
- `gate_na`:
  - reason: P003 验收需要现场准入卡，不可由本机 dry-run 替代。
  - alternative_verification: 完成 checklist 与 preflight 合同，待现场执行后回填准入证据。
  - evidence_link: `docs/templates/p003-onsite-pilot-admission-checklist.md`
  - expires_at: `2026-05-20`

## 下一步
1. 先完成 `P002` teacher proxy report。
2. 再按 P003 checklist 完成现场准入卡并回填 evidence。
