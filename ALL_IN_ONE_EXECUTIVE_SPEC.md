# 校本题谱 · AI Coding Executive Spec

本文件是人和 AI Coding Agent 的短入口，只描述稳定边界与当前路由。任务顺序以 `tasks/backlog.csv` 为唯一机器真源；当前投影看 `docs/103_ExecutionControlBoard.md`；发布裁决看 `docs/109_ReleaseGoNoGoCard.md`。

## 1. 产品目标

校本题谱面向 K-12 教师与备课组，当前聚焦初中物理，把 Word、PDF、图片和 Excel 中的题库、组卷、导出和学情工作低摩擦转成可检索、可复用、可分析、可恢复的校本资产。

最高原则是减少教师步骤、等待、重复录入和治理术语暴露，而不是扩大平台功能面。

## 2. v0.1 用户闭环

```text
上传 -> 解析/切题 -> 异常审核 -> 入库/来源回看
     -> 检索/题篮/组卷 -> Word/PDF 导出
     -> Excel 成绩导入 -> 基础分析/讲评 -> 备份恢复
```

普通教师默认只看导入、组卷、成绩、分析四个入口。高级治理、模型路由、迁移、备份、权限和证据下沉到管理员或系统层。

## 3. 当前事实边界

- API、Web、Worker、PostgreSQL、FileStore、备份与版本化领域资产已存在。
- C002 是当前生产默认；修订走 C002R candidate/review/impact/snapshot/active-switch。
- CEK-01..35 已完成 repo-side 候选链与验证收口，但自动结果仍为 `candidate/pending_review/productionEligible=false`。
- `REAL005=not_closed`；repo-side 完成不等于教师签字、学校网络、隔离机或 live acceptance。
- P001/P003/P005/P006 仍依赖外部现场/人工事实，当前 release No-Go。
- VGOV-001..010 验证治理减负已完成 repo-side 收口；当前进入 P001-P006 外部现场与发布链路，不在 P006 前扩展第二学科或高级平台能力。

## 4. 明确不做

- 学生端、家长端、在线监考和自动主观题阅卷。
- 未经真实瓶颈证明的 RabbitMQ、外部搜索、图数据库或多租户 SaaS。
- P006 前的第二学科 active。
- AI 自动写 active、自动代签、用 synthetic evidence 替代现场事实。
- 为治理减负再建立常驻治理服务、跨仓 registry 或第二套任务数据库。

## 5. 核心不变量

- AI 输出默认 `draft/test/pending_review`。
- 正式写入必须可追溯到来源、版本、审核和回滚。
- 动态领域资产保留版本、状态、来源、映射、迁移和 rollback snapshot。
- 数据库只存 metadata/path/hash/status，大文件进入 FileStore。
- 真实学生数据、凭据、版权敏感原文不得进入仓库、prompt 或普通 evidence。
- 任何 repo-side pass 都不能自动升级为 deployed、onsite/manual 或 live accepted。

## 6. 默认技术边界

| 层 | 当前选择 |
|---|---|
| Web | React + TypeScript + Vite + Ant Design |
| API | ASP.NET Core / .NET 10 |
| 数据 | PostgreSQL + EF Core + Npgsql |
| 文件 | 本地 FileStore |
| Worker | Python document/OCR adapter |
| 后台任务 | PostgreSQL job + BackgroundService |
| 部署 | Windows-first，Windows Service/LAN |
| 备份 | pg_dump + FileStore manifest + config + sha256 |

pgvector、独立搜索、Hangfire、RabbitMQ、对象存储和多租户均为触发式 Later，不是默认依赖。

## 7. AI 任务读取顺序

1. `AGENTS.md`
2. 本文件
3. `docs/103_ExecutionControlBoard.md`
4. `tasks/backlog.csv` 中当前 task
5. 当前 task 对应 spec
6. 相关模块代码和测试
7. 命中高风险路由时才读取 reference-basis、release 或历史 evidence

不要默认通读全部 `docs/` 或 `docs/evidence/`，不要从历史完成说明推断当前任务。

## 8. AI 可执行 task 最小合同

每个 task 必须给出：objective、user outcome、current truth、depends_on、in/out of scope、write-set、protected paths、implementation steps、acceptance、verification profile、focused/stateful verifier、evidence policy、rollback、truth boundary 和 next task。

AI 不得修改 write-set 外的用户资产；遇到版权授权、生产 active、真实身份签字或不可逆外部操作时 fail-closed。

## 9. 验证策略

固定语义仍为：

```text
build -> test -> contract/invariant -> hotspot
```

执行 profile：

- Quick：无 DB、无进程停止、无 tracked evidence。
- Slice：Quick + task/changed-path 对应合同与热点。
- Release：Quick + migration/privacy/API/no-active-write + isolated backup/restore/upgrade + closure invariants + 状态对账；执行前明确授权，默认工件只进 `tmp/verification/`。
- Onsite：隔离机、网络、打印、权限域、真实教师和签字；不能由 repo-side 自动化替代。

235-step legacy monolith 及其 compatibility audit 已退役，只从 Git 历史取证。日常 AI 编码只走 changed-path Slice，跨栈基线才走 Quick；Release 前后必须报告 DB/migration、FileStore 和进程差异，并要求共享 FileStore 无写入。

## 10. 文档和任务真源

- 产品准则：`docs/00_ProjectConstitution.md`
- PRD：`docs/01_PRD.md`
- 范围：`docs/02_MVP_Scope_and_ScopeControl.md`
- 架构：`docs/03_Architecture.md`
- 测试：`docs/18_TestStrategy.md`
- 路线图：`docs/19_Roadmap.md`
- 当前执行：`docs/103_ExecutionControlBoard.md`
- 当前 closure：`docs/CurrentClosureStatus.md`
- 发布裁决：`docs/109_ReleaseGoNoGoCard.md`
- 机器任务真源：`tasks/backlog.csv`
- 治理减负规格：`docs/specs/verification-governance-simplification-v1.md`

## 11. 当前路由

```text
Now:  P001 隔离机部署与真实环境 preflight
Next: P002 -> P003 -> P004 -> P005 -> P006
Repo: VGOV-001..010 已完成；无剩余 repo-side VGOV task
Later: Q001-Q005 / R001-R007，仅在触发条件满足后进入
```

VGOV-001..010 已实现 repo-side verifier、evidence 分流、聚焦 Release core、可选 legacy audit、状态对账和 hotspot 收口；这仍不代表现场发布、REAL005 或 live acceptance 完成。
