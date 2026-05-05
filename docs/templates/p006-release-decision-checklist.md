# P006 release decision checklist

用途：用于 `P006` v0.1 发布裁决。该清单只约束裁决依据与证据，不替代真实发布审批。

## 0. 前置依赖
- [ ] `P005` 已完成并形成反馈分流结果。

## 1. 发布硬条件
- [ ] 门禁通过（build/test/contract/invariant/hotspot 或有效 N/A）。
- [ ] 备份链路可验证。
- [ ] 恢复链路可验证。
- [ ] 教师效率指标达标或有可接受例外说明。
- [ ] 隐私边界与授权边界满足要求。

## 2. 裁决输出
- [ ] 形成 release decision record（含 go/no-go、风险、回滚）。
- [ ] 若 go，形成 tag candidate 策略与回退策略。
- [ ] 在 `docs/evidence/` 留存证据与审批结论。
