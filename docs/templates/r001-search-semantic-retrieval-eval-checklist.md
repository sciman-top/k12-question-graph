# R001 search semantic retrieval evaluation checklist
- [ ] `P006` 已完成并有 release decision record；未完成前只允许 preflight/admission report，不做 pgvector 或外部搜索落地。
- [ ] 当前默认路线必须保持 PostgreSQL FTS + `pg_trgm` first；pgvector 只能在真实 benchmark 证明不足后进入评估。
- [ ] benchmark report 必须覆盖真实题量、查询集合、miss case、latency p50/p95、排序质量、教师找题耗时和回滚动作。
- [ ] 语义检索候选必须先证明不破坏 active C002 默认知识版本、题号排序、来源引用、题图/公式/表格状态和权限边界。
- [ ] pgvector 评估必须有 extension 可用性、embedding 来源、模型/成本/缓存策略、隐私边界、重建索引脚本和 disable switch。
- [ ] 外部搜索引擎评估必须有事实源重建策略、数据同步延迟、备份恢复、权限过滤、运维成本和故障降级方案。
- [ ] AI/embedding 只能生成候选排序或召回建议，不得绕过教师审核、来源证据或 active 知识版本。
- [ ] ADR 必须记录 PostgreSQL first 基线、升级触发阈值、替代方案、教师效率收益、供应链风险和 rollback。
- [ ] 缺少 benchmark、miss case、privacy review、extension evidence 或 rollback 任一项时，R001 必须 fail-closed。
