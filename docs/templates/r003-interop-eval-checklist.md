# R003 interoperability evaluation checklist

- [ ] `P006` 已完成并有 release decision record。
- [ ] 明确 QTI / CASE / OneRoster / Caliper 的真实对接需求来源，而不是因为标准存在就实现。
- [ ] 已引用 `R007` profile map，并明确哪些字段只能进入 adapter/view model 或 versioned mapping。
- [ ] 有授权样例包、conformance target、field-difference report 和 lossy round-trip risk report。
- [ ] 有学生/成绩/分析数据 privacy review，尤其是 OneRoster 与 Caliper。
- [ ] 形成 admission card、adapter owner、dry-run preview、人工复核入口和 rollback/disable switch。
- [ ] 如需要，形成 integration spike 证据；spike 只能 dry-run，不写正式数据。
- [ ] fail-closed：缺真实对接需求、样例授权、隐私审查、字段差异或回滚证据时，不实现 QTI import/export、CASE sync、OneRoster SIS sync 或 Caliper event stream。
