# 20260505 P004 onsite pilot round1 preflight

## 目标
- 在不伪造现场试点第 1 轮结果的前提下，建立 `P004` preflight 合同与执行清单。

## 结论
- `P004` 保持 `待办`，不提前宣称现场试点完成。
- `P004` 依赖 `P003`，当前 `P003` 仍为 `待办`，依赖链一致。
- 已新增 `tools/run-p004-onsite-pilot-round1-preflight-contract.ps1` 与 `docs/templates/p004-onsite-pilot-round1-checklist.md`。

## N/A 记录
- `platform_na`:
  - reason: 当前会话不在现场试点执行环境，缺少真实教师操作数据和现场记录。
  - alternative_verification: 先执行 P004 preflight contract，确认依赖、清单和证据入口完整。
  - evidence_link: `docs/evidence/20260505-p004-onsite-pilot-round1-preflight.md`
  - expires_at: `2026-05-20`
- `gate_na`:
  - reason: P004 验收要求真实现场耗时/卡点/回滚事件记录，不可由本机 dry-run 替代。
  - alternative_verification: 完成 checklist 与 preflight 合同，待现场执行后回填 teacher pilot evidence。
  - evidence_link: `docs/templates/p004-onsite-pilot-round1-checklist.md`
  - expires_at: `2026-05-20`

## 下一步
1. 先完成 `P003` pilot admission card。
2. 再按 P004 checklist 执行现场教师试点第 1 轮并回填 evidence。
