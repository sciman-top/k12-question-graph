# 20260505 R006 techdebt cadence preflight
- preflight only；`R006` 保持待办，不改完成态。
- platform_na：`P006` 未闭环，长期技术债节奏只做预检不做正式排期决策。
- gate_na：仅完成 checklist/contract 预检，不替代 quality dashboard + dependency gate 真实运行策略。
- 下一步：P006 完成后按发布节奏执行门禁维护/依赖升级/性能基线。
- 2026-05-22 refresh：`tools/run-r006-techdebt-cadence-preflight-contract.ps1` 会生成机器可读 admission report；当前只允许 report-only 技术情报、draft/test 健康看板和配置化 cache root 清理。
- 2026-05-22 refresh：`docs/decisions/ADR-008-techdebt-cadence-admission.md` 已接受 fail-closed 裁决；依赖升级、性能优化和实验删除必须先有 owner、baseline、dry-run preview 和 rollback。
