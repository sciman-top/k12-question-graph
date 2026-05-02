# 30 · A000A P0 编码前契约收口记录

执行日期：2026-05-02。

## 1. 结论

`A000A` 已完成编码前文档契约收口。API DTO、错误码、幂等、分页、OpenAPI snapshot、数据库约束/索引、job 状态转移、威胁模型、RPO/RTO、UX 状态、学生数据边界、外部 AI 边界和黄金样本隐私规则均已有明确文档入口。

本轮修正了一个字段命名漂移：`docs/03_Architecture.md` 中 job 错误字段从 `last_error` 收口为 `last_error_code` 与 `last_error_message`，与数据库草案一致。

## 2. 契约入口

| 契约 | 文档入口 | 判定 |
|---|---|---|
| P0 API DTO | `docs/23_API_Draft.md` 9.2 | pass |
| 通用错误与 ProblemDetails | `docs/23_API_Draft.md` 9.1, 9.3 | pass |
| 幂等 | `docs/23_API_Draft.md` 9.1, 9.4 | pass |
| 分页 | `docs/23_API_Draft.md` 9.1 | pass |
| OpenAPI snapshot gate | `docs/23_API_Draft.md` 9.4 | pass |
| P0 DB constraints/indexes | `docs/24_DatabasePhysicalModel_Draft.md` 8 | pass |
| Job status transition | `docs/24_DatabasePhysicalModel_Draft.md` 8.2 | pass |
| `locked_by`/`locked_until` 命名 | `docs/03_Architecture.md`, `docs/24_DatabasePhysicalModel_Draft.md`, `docs/decisions/ADR-004-verified-p0-stack-and-gate-contract.md` | pass |
| P0/P1 threat model | `docs/17_SecurityPrivacyCompliance.md` 8 | pass |
| RPO/RTO | `docs/14_BackupRecoveryMigration.md` 9 | pass |
| UX 状态清单 | `docs/11_UX_Workflows.md` 11 | pass |
| 学生数据/合规辖区 | `docs/17_SecurityPrivacyCompliance.md` 6 | pass |
| 外部 AI 数据边界 | `docs/09_AI_ModelRouting_CostControl.md`, `docs/17_SecurityPrivacyCompliance.md` | pass |
| 黄金样本目录与隐私规则 | `docs/18_TestStrategy.md` 3 | pass |

## 3. 检索证据

执行的关键检索：

```powershell
rg -n "ProblemDetails|errorCode|Idempotency-Key|OpenAPI|DTO|pageSize|cursor|status in queued|queued -> running|locked_by|locked_until|deployment_jurisdiction|student_pii_allowed_in_external_ai|privacy_and_license|RPO|RTO|empty|loading|error|ready" docs README.md tasks prompts
rg -n "真实学生|学生姓名|学号|成绩|外部 AI|fixture|PII|API key|数据库密码|license_or_permission|sharing_allowed|contains_student_pii" README.md docs prompts tasks schemas configs sources
```

关键命中：

- `docs/23_API_Draft.md`: P0 DTO、ProblemDetails、`Idempotency-Key`、分页、OpenAPI snapshot gate。
- `docs/24_DatabasePhysicalModel_Draft.md`: job 字段、状态枚举、状态转移、SourceDocument 隐私约束。
- `docs/17_SecurityPrivacyCompliance.md`: `deployment_jurisdiction`、`student_pii_allowed_in_external_ai`、P0/P1 threat model。
- `docs/11_UX_Workflows.md`: 首页、上传、ImportJob、错误页、ReviewQueue、来源预览、备份状态。
- `docs/18_TestStrategy.md`: `privacy_and_license.md`、黄金样本脱敏和 privacy gate。

## 4. 文档门禁

| 门禁 | 结果 |
|---|---|
| CSV backlog parse | pass: `csv ok 37` |
| JSON schema parse | pass: `json ok 6` |
| YAML config parse | pass: `yaml ok 6` |
| P0/P1 consistency rg | pass |
| sensitive boundary rg | pass |

## 5. 剩余风险

- PostgreSQL 未就绪仍阻断 `A004`，详见 `docs/29_A000_Preflight.md`。
- `dotnet --info` 退出码为 1 仍是 host readiness 风险；`A002` 的 `dotnet build` 若失败，先排查本机 .NET 安装链路。
- A000A 只锁定文档契约，尚未生成 OpenAPI snapshot 或 migration；这些必须在 `A002/A004/A010` 实现时进入真实 gate。
