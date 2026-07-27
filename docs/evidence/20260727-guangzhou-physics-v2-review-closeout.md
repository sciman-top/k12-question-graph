# T7 广州真题审核闭环证据

- checked_at: 2026-07-27T22:23:48+08:00
- status: partial_pass
- workflow: `guangzhou-physics-2015-2025-v2`
- restore_point: `D:\KQG_Backups\20260727-215646\manifest.json`

## 已验证

- API/Web build 成功；API 全量测试 17/17，Web 测试 10/10，lint 通过。
- UI 合同覆盖年份切换、保存修订、确认、退回、来源重裁、审核撤销、重裁撤销和失败后继续处理。
- S006B、S006C、S007C 与 REAL004 兼容回归通过。
- T7 可逆真实 smoke 完成身份失败、修订、重裁、确认、重复确认冲突、撤销确认、退回和撤销退回。
- 最终 v2 队列为 234 条 `open`；2015 Q1 为 `pending_review`，`productionEligible=false`，`primaryKnowledgeId=null`，题干、难度和来源坐标均已恢复。
- legacy REAL004 与 v2 共存问题已修复：来源区域清理和计数按 workflow 关联收口，不再按 region type 全局处理。

## 证据

- `docs/evidence/20260727-guangzhou-physics-v2-review-workflow-smoke.json`
- `docs/evidence/20260727-guangzhou-physics-v2-review-ui-contract.json`
- `docs/evidence/20260512-real004-guangzhou-2015-review-smoke-report.json`
- `docs/evidence/20260506-s006b-manual-takeover-smoke-report.json`
- `docs/evidence/20260506-s006c-source-review-closure-smoke-report.json`
- `docs/evidence/20260506-s007c-teacher-confirm-writeback-smoke-report.json`

## 未关闭边界

- `platform_na`
- reason: Codex Browser/Chrome 插件在当前宿主会话拦截 localhost 非根路径，返回 `net::ERR_BLOCKED_BY_CLIENT`。
- alternative_verification: 静态 UI/client/API 合同、production build、单元测试、真实 API/PostgreSQL 可逆 smoke。
- evidence_link: `docs/evidence/20260727-guangzhou-physics-v2-review-ui-contract.json`
- expires_at: `next_browser_capability_refresh`
- recovery_condition: 浏览器插件可访问 localhost API/Vite proxy 路径后，执行逐题加载、保存、重裁、确认、退回和两类撤销的真实点击断言。

## Hotspot

- `gate_na`
- reason: 仓库尚无独立 hotspot 命令。
- alternative_verification: API/Web 合同、异步旧题防串写、非法块类型、重复审核冲突、可逆数据恢复与教师继续路径复核。
- evidence_link: `docs/18_TestStrategy.md`
- expires_at: `next_executable_change`
- recovery_condition: 建立独立 hotspot 命令并纳入固定门禁。

T7 主项保持未勾选；本证据不代表真实教师验收、C002 active 切换、生产可用、隔离机验证或正式发布。
