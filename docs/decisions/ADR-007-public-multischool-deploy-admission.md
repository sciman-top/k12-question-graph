# ADR-007 · 公网与多校部署准入边界

## Status

Accepted

## Date

2026-05-21

## Context

本仓 v0.1 的架构默认是 Windows-first、校本局域网、单校可恢复部署。`docs/03_Architecture.md` 已明确纯云 SaaS 和公网多租户会过早增加数据、采购、隐私、网络和运维成本；`docs/17_SecurityPrivacyCompliance.md` 要求先锁定 deployment jurisdiction、data controller/owner、operator/processor、外部模型传输边界、备份访问控制和保留删除策略。

当前 `P006` 仍是待办，`P001` 只完成 preflight，隔离机器安装、备份恢复、权限审计和四个教师入口 smoke 尚未形成现场证据。此时评估公网、多校或 SaaS 会把尚未完成的单校发布风险放大为跨组织风险。

## Decision

R005 采取 fail-closed 准入策略。

继续允许推进的范围：

- 校本/LAN/single-school 部署合同、安装向导、备份恢复、权限审计和 smoke 证据。
- read-only 风险矩阵、security privacy ADR、feature admission 草案和退出路径设计。
- 外部 AI/OCR/云服务只作为 report-only 或可禁用候选，不作为生产依赖。

阻断进入产品或生产默认的范围：

- public internet exposure。
- multi-school shared deployment。
- multi-tenant SaaS。
- 跨校数据汇聚、统一账号池、集中备份或集中学情分析。
- 任何未通过 P006、数据责任、采购、网络、运维和 rollback 准入的部署形态。

公网或多校部署进入 feature admission 前，至少需要：

- P006 release decision record。
- P001 isolated-machine install/backup/role-audit/four-entry smoke evidence。
- deployment jurisdiction 与 data controller/owner 明确。
- operator/processor、采购主体、SLA、数据处理协议和退出责任明确。
- tenant isolation、权限隔离、数据隔离、审计隔离和备份隔离方案。
- TLS/证书、身份认证、访问控制、远程运维、日志审计和异常流量处置方案。
- RPO/RTO、备份恢复演练、密钥轮换、事故响应和下线/迁出计划。

## Consequences

- R005 可以产出 admission report，但不得因为 checklist 通过就把公网、多校或 SaaS 标为可用。
- `deployment-install` 和 `live-pilot` 在 P001/P006 之前继续保持不可发布或不可使用。
- 新增公网端口、反向代理、远程访问、tenant 字段、跨校账号、集中备份或多校分析指标前，必须先通过 R005 合同和后续 feature admission。
- 若缺少任一数据责任、采购、网络、运维、tenant isolation 或 rollback 证据，产品路线回退到单校/LAN。

## Alternatives Considered

### 先做公网 SaaS 版本

Rejected. 当前教师效率瓶颈仍在导入、组卷、导出、复核、备份恢复和现场可用性；公网 SaaS 会把采购、合规、运维和数据责任提前复杂化。

### 只做隐藏管理员公网开关

Rejected. 公网暴露不是 UI 入口问题，而是身份、网络、日志、备份、数据责任和事故响应问题；隐藏开关不能降低系统风险。

### 继续校本/LAN 优先

Accepted for v0.1. 这条路线最贴近学校低运维、Word/Excel 工作流、本地数据责任和可回滚目标。
