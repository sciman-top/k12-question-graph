# 校本题谱

面向教师的本地题库、组卷与学情诊断平台。当前实现聚焦初中物理，采用 ASP.NET Core API、React Web、PostgreSQL、Python 文档 Worker 和本地 FileStore。

## 当前结论

- API、Web、Worker、数据库、FileStore、备份恢复和版本化领域资产均已落地。
- `C002` 是当前 active 知识体系；任何修订必须走 candidate -> review -> backup -> active switch，不直接改旧 active。
- 2015–2025 广州真题的 repo-side 候选/审核链已收口，但自动结果仍是 `candidate/pending_review/productionEligible=false`。
- `REAL005=not_closed`、`fullClosureAllowed=false`，P001–P006 仍未完成，发布裁决是 `No-Go`。
- repo-side 验证不能替代隔离机、学校网络、打印、权限域、真实教师使用和签字。

当前任务与状态只看 [tasks/backlog.csv](tasks/backlog.csv)；最短状态入口是 [docs/CurrentClosureStatus.md](docs/CurrentClosureStatus.md) 和 [docs/103_ExecutionControlBoard.md](docs/103_ExecutionControlBoard.md)。

## 教师主链

```text
导入/建题 -> 题谱映射 -> 检索/组卷或成绩诊断 -> Word/Excel 交付 -> 教师复核
```

教师默认只接触少步骤、少选择、少术语的工作台。权限、审计、备份、迁移、AI provider 和 active switch 均属于管理员层。

## 本地启动

API：

```powershell
$env:KQG_CONNECTION_STRING='Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres;Password=<local-password>'
.\tools\start-local-api.ps1
.\tools\start-local-api.ps1 -Status
```

Web：

```powershell
.\tools\start-local-web.ps1
.\tools\start-local-web.ps1 -Status
```

默认地址为 API `http://127.0.0.1:5275`、Web `http://127.0.0.1:5173`。停止或重启使用启动脚本的 `-Stop` / `-Restart`。详见 [docs/113_LocalRuntimeOperations_20260609.md](docs/113_LocalRuntimeOperations_20260609.md)。

## AI 配置边界

- 根目录 `.env` 只提供本地 bootstrap；模板见 `.env.example`。
- 管理员保存后的本机配置优先于 `.env`，默认路径为 `D:\KQG_Data\config\admin\ai-provider-settings.local.json`。
- 默认使用一组 base URL + API key；只有图片网关确实分流时才填写图片专用覆盖。
- real model、外部 AI、成本预算和 provider smoke 均不得绕过 `pending_review` 与 no-active-write。

## 验证

日常代码变更优先运行 Slice：

```powershell
.\tools\run-verification.ps1 -Profile Slice -ChangedPaths <PATHS>
```

全栈无状态基线：

```powershell
.\tools\run-verification.ps1 -Profile Quick
```

`Slice` 只运行受影响产品 build/test 或 changed-script 解析；纯文档返回 `gate_na`。`Quick` 运行 API、Web 和核心 Worker，不扫描全部历史工具。两者只写 `tmp/verification/`，不访问 PostgreSQL、不停止常驻进程、不写 FileStore 或 tracked evidence。

数据库 migration、备份恢复和发布前状态对账只在明确授权后运行：

```powershell
.\tools\run-verification.ps1 -Profile Release -AuthorizeStateful
```

Release 只增加 migration/privacy/no-active-write、隔离备份恢复、reference/current-evidence/closeout 检查；不会重新审计全部历史任务或生成日期化 tracked evidence。

## 数据与运维

常用低层入口：

```powershell
.\tools\backup.ps1
.\tools\verify-backup.ps1
.\tools\restore.ps1
.\tools\run-c002-dry-run-suite.ps1
.\tools\prepare-c002-candidate-csvs.ps1
.\tools\import-c002-source-materials.ps1
.\tools\import-c002-candidate-assets.ps1
.\tools\run-domain-asset-activation.ps1
```

写数据库、恢复、active switch 或真实资料导入前必须先生成并验证 backup manifest；默认运行必须是 dry-run。真实学生信息、版权受限原文和凭据不得提交。

## 当前发布链

```text
P001 隔离机预演
  -> P002 教师代理试点
  -> P003 现场准入
  -> P004 现场试点
  -> P005 反馈分流
  -> P006 发布裁决
```

细化顺序在 [tasks/live-pilot-closeout-plan.csv](tasks/live-pilot-closeout-plan.csv)。只要 P001–P006 未全部关闭，就保持 `No-Go`，不创建 release tag，不宣称 live accepted。

## 文档导航

- 产品与范围：[docs/01_PRD.md](docs/01_PRD.md)、[docs/02_MVP_Scope_and_ScopeControl.md](docs/02_MVP_Scope_and_ScopeControl.md)
- 架构与领域：[docs/03_Architecture.md](docs/03_Architecture.md)、[docs/05_DomainModel.md](docs/05_DomainModel.md)
- 测试与恢复：[docs/18_TestStrategy.md](docs/18_TestStrategy.md)、[docs/14_BackupRecoveryMigration.md](docs/14_BackupRecoveryMigration.md)
- 当前执行：[docs/103_ExecutionControlBoard.md](docs/103_ExecutionControlBoard.md)、[docs/CurrentClosureStatus.md](docs/CurrentClosureStatus.md)
- 发布裁决：[docs/109_ReleaseGoNoGoCard.md](docs/109_ReleaseGoNoGoCard.md)
- current evidence：[docs/evidence/index.json](docs/evidence/index.json)
- 参考依据：[docs/26_References.md](docs/26_References.md)、[tasks/reference-basis-requirements.csv](tasks/reference-basis-requirements.csv)

未被 evidence index 指向的旧报告只属于 Git 历史，不参与当前任务选择或默认门禁。
