# P006 release decision checklist

用途：用于 `P006` v0.1 发布裁决。该清单只约束裁决依据与证据，不替代真实发布审批。

填写本清单前，必须先更新 `docs/109_ReleaseGoNoGoCard.md`。

## 0. 前置依赖
- [ ] `P005` 已完成并形成反馈分流结果。

## 1. 发布硬条件
- [ ] 先生成绑定 commit、证据哈希和时间戳的一页远程证据摘要；硬门禁缺失时自动保持 `No-Go`，无需召开发布会补证据。
- [ ] 门禁通过（build/test/contract/invariant/hotspot 或有效 N/A）。
- [ ] `NS904` / `NS906` 或等价非现场客观检查证据已刷新；未闭合时不得到发布会或现场再补做。
- [ ] 备份链路可验证。
- [ ] 恢复链路可验证。
- [ ] 教师效率指标达标或有可接受例外说明。
- [ ] 隐私边界与授权边界满足要求。

## 2. 裁决输出
- [ ] 形成 release decision record（含 go/no-go、风险、回滚）。
- [ ] `docs/109_ReleaseGoNoGoCard.md` 已填写 release candidate、deployment mode、hard gates、residual risks、rollback window 和 sign-off 角色。
- [ ] 若 go，形成 tag candidate 策略与回退策略。
- [ ] 最终 sign-off 仍由发布负责人、管理员负责人、数据责任方代表和试点支持负责人签署，不由 AI 或代理代签。
- [ ] 签收默认异步电子完成，不要求纸质或同场；身份、时间、commit、证据包哈希和 named exception 必须可审计。
- [ ] `No-Go` 延续且无新增例外时可由自动摘要通知，不要求四方重复开会；从 `No-Go` 转 `Go`、`go_with_named_exceptions` 或批准例外时必须完成四方确认。
- [ ] 记录 rollback window；远程异步签收不改变回滚窗口、责任人和恢复入口要求。
- [ ] 在 `docs/evidence/` 留存证据与审批结论。
