# 20260505 R001 search semantic retrieval eval preflight
- preflight only；`R001` 保持待办，不改完成态。
- platform_na：`P006` 未闭环，语义检索升级评估不进入真实 benchmark。
- gate_na：仅完成 checklist/contract 预检，不替代 benchmark report + ADR。
- 下一步：P006 完成后执行真实基准并产出 ADR。
- 2026-05-22 refresh：`tools/run-r001-search-semantic-retrieval-eval-preflight-contract.ps1` 会生成机器可读 admission report；当前只允许 PostgreSQL FTS/pg_trgm first 路线和 benchmark 设计，不启用 pgvector 或外部搜索。
- 2026-05-22 refresh：`docs/decisions/ADR-010-search-semantic-retrieval-admission.md` 已接受 fail-closed 裁决；任何语义检索、embedding 或外部搜索必须先有真实不足证据、隐私边界和 rollback。
