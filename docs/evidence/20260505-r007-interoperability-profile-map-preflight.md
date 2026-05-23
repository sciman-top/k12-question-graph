# 20260505 R007 interoperability profile map preflight
- preflight only；`R007` 保持待办，不改完成态。
- platform_na：`P006` 未闭环，暂不进入标准映射的真实落地评估。
- gate_na：仅完成 checklist/contract 预检，不替代 interoperability profile map 正式文档与 admission 证据。
- 下一步：P006 完成后输出 profile map（QTI/CASE/OneRoster/Caliper）并按需做 spike。
- 2026-05-22 refresh：`tools/run-r007-interoperability-profile-map-preflight-contract.ps1` 会生成机器可读 profile map admission report；当前只允许 profile map，不做 QTI/CASE/OneRoster/Caliper import/export spike。
- 2026-05-22 refresh：`docs/decisions/ADR-009-interoperability-profile-map-admission.md` 已接受 fail-closed 裁决；标准适配层必须保持 adapter/view model 边界，不污染内部主模型。
