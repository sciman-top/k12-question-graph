# 20260505 R005 public multischool deploy eval preflight
- preflight only；`R005` 保持待办，不改完成态。
- platform_na：`P006` 未闭环，暂不进入公网/多校部署真实评估。
- gate_na：仅完成 checklist/contract 预检，不替代 security privacy ADR。
- 下一步：P006 完成后结合采购/网络/运维边界评估 SaaS/多租户。
- 2026-05-21 refresh：`tools/run-r005-public-multischool-deploy-eval-preflight-contract.ps1` 会生成机器可读 admission report；当前只允许继续校本/LAN/single-school 路线，公网、多校、多租户 SaaS 继续 fail-closed。
- 2026-05-21 refresh：`docs/decisions/ADR-007-public-multischool-deploy-admission.md` 已接受后置准入裁决；任何公网暴露、多校共享或 SaaS 形态都必须先过 P006 后 feature admission。
