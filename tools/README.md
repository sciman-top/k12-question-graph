# tools

本目录存放仓库自动化。脚本参数和行为以各文件的 `param()` 与实现为准；本页只保留稳定入口和风险边界，不维护逐脚本历史目录。

## 验证

唯一入口：

```powershell
.\tools\run-verification.ps1 -Profile Slice -ChangedPaths apps/api/Program.cs
.\tools\run-verification.ps1 -Profile Quick
.\tools\run-verification.ps1 -Profile Release -AuthorizeStateful
```

- `Slice`：按 changed paths 运行对应 API/Web/Worker build/test；工具变更只做脚本质量；纯文档为 `gate_na`。
- `Quick`：无状态跨栈基线，不连接 PostgreSQL、不停止仓库进程、不写 FileStore 或 tracked evidence。
- `Release`：只在当前任务明确授权后运行；包含 PostgreSQL/migration、隐私、no-active-write、隔离备份恢复和状态对账。
- onsite/live acceptance 不提供可执行 profile，只接受外部真实证据。
- 旧 full-gate monolith、兼容 wrapper、gate group、inventory/parser 与覆盖对账已退役；历史只从 Git 读取。

远程优先证据包（默认 DryRun；`Collect` 只写指定的 `tmp/verification` 输出）：

```powershell
.\tools\run-remote-first-evidence-pack.ps1 -Mode DryRun
.\tools\run-remote-first-evidence-pack.ps1 -Mode Collect
```

该入口汇总 current evidence、Release/roadmap/closeout receipt、目标机诊断、视觉代理和 Word/PDF 工件哈希，并 fail-closed 报告仍需远程目标机事实、真实教师原始反馈、数据授权和责任人电子签收的最小残余面。它不会改 backlog、数据库、FileStore、active、发布卡、签字、tag 或外部服务。

可问责电子确认包（模板允许按当前阶段逐步填写，不要求所有签字人同场）：

```powershell
.\tools\run-accountable-acceptance-bundle.ps1 -Mode DryRun -BundlePath <filled-bundle.json>
.\tools\run-accountable-acceptance-bundle.ps1 -Mode Collect -BundlePath <filled-bundle.json>
.\tools\run-remote-first-evidence-pack.ps1 -Mode Collect -AcceptanceBundleReportPath tmp/verification/accountable-acceptance/current/accountable-acceptance-report.json
```

模板为 `docs/templates/accountable-acceptance-bundle-template.json`。校验器自动检查阶段最低角色、签署时间、commit、证据文件 SHA-256、身份验证方式和外部审计引用；`pass` 只表示材料结构完整并已绑定当前证据，可交给责任人正式接受。脚本不验证外部身份系统真伪，不代签，也不自动关闭 P001-P006、改变 `No-Go` 或创建 tag。

P005 反馈摘要（只做确定性去重/聚类/统计，不自动裁决）：

```powershell
.\tools\run-p005-feedback-summary.ps1 -Mode DryRun -InputPath docs/templates/p005-pilot-feedback-triage-template.json
.\tools\run-p005-feedback-summary.ps1 -Mode Collect -InputPath <p004-or-p005-json>
```

## 本地运行

```powershell
.\tools\start-local-api.ps1
.\tools\start-local-api.ps1 -Status
.\tools\start-local-web.ps1
.\tools\start-local-web.ps1 -Status
```

未经当前任务授权，不停止、重启或替换已有 API/Web 进程。

## 参考依据

高风险板块的机器真源：

- `tasks/reference-basis-requirements.csv`
- `tasks/reference-basis-module-map.csv`
- `sources/reference-shelf.manifest.snapshot.json`
- `tools/run-reference-basis-guard.ps1`

本机外置参考库为 `D:\CODE\external\k12-question-graph-references`。只读查阅；复制或执行前核对固定 revision、license、数据和隐私边界。

```powershell
.\tools\run-reference-basis-guard.ps1 -ValidationMode Ci
.\tools\run-reference-basis-guard.ps1 -ValidationMode Local
```

## 现场与发布边界

- `NS904`：P001 readiness 只能证明 repo/release-side 准备度。
- `NS906`：视觉代理审查仍不能替代真实教师、学校网络、打印、权限域或签字。
- `REAL005=not_closed` 与 `P001/P003/P005/P006` 的 onsite/manual 状态不能由脚本改写为 live accepted。
- AI/OCR 输出默认 `candidate`、`draft/test` 或 `pending_review`；不得自动 active write。

## 备份恢复

```powershell
.\tools\backup.ps1
.\tools\verify-backup.ps1
.\tools\restore.ps1 -ManifestPath '<backup>\manifest.json' -ApplyDatabase -ApplyFileStore -DryRun
```

restore apply、migration、active switch 和真实数据操作必须先声明 snapshot、rollback 与验收证据并获得授权。恢复默认拒绝覆盖非空 FileStore/config 目标；只有已取得 pre-restore snapshot 时才可显式传入 `-AllowOverlay -DryRun:$false`。

## 查找专用脚本

不要把所有专用脚本塞回本页。按任务或领域动态发现：

```powershell
Get-ChildItem tools/run-*.ps1 | Select-Object -ExpandProperty Name
rg -n "<TASK_ID>|<domain keyword>" tools tasks README.md
Get-Content -LiteralPath tools/<script>.ps1 -TotalCount 80
```

专用脚本默认只证明其自身合同；不能因为脚本 pass 就扩大为 full project、onsite 或 live acceptance。
