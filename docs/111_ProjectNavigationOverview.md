# 111 · 项目导航总览

本文件定义最短读取路径，避免人和 AI 通读全部 docs/evidence 后自行拼接当前状态。

## 1. Canonical / projection / history

| 类型 | 文件 | 职责 |
|---|---|---|
| canonical | `docs/00_ProjectConstitution.md` | 最高准则 |
| canonical | `docs/01_PRD.md` | 稳定产品目标和成功指标 |
| canonical | `docs/02_MVP_Scope_and_ScopeControl.md` | v0.1 范围 |
| canonical | `tasks/backlog.csv` | 任务顺序和状态 |
| canonical | 当前 task spec | AI 可执行合同 |
| projection | `docs/103_ExecutionControlBoard.md` | Now/Next/Later/Blocked |
| projection | `docs/CurrentClosureStatus.md` | closure 边界 |
| authority | `docs/109_ReleaseGoNoGoCard.md` | 发布裁决 |
| history | `docs/evidence/`、完成切片文档、Git | 历史事实 |

## 2. AI 进入项目

固定读取顺序：

1. `AGENTS.md`
2. `docs/103_ExecutionControlBoard.md`
3. `tasks/backlog.csv` 当前行
4. 当前 task spec
5. 相关代码和测试

只有以下情况再扩读：

- 产品范围冲突：读 PRD/scope。
- 架构或验证变更：读 architecture/test strategy/对应 ADR。
- 高风险模块：读 reference-basis requirements/module map。
- release/onsite：读 release card、closeout plan 和真实 evidence。

## 3. 当前验证入口

- 日常切片：`tools/run-verification.ps1 -Profile Slice -ChangedPaths <PATHS>`
- 无状态基线：`tools/run-verification.ps1 -Profile Quick`
- 授权发布检查：`tools/run-verification.ps1 -Profile Release -AuthorizeStateful`
- Slice/Quick 结果只进 `tmp/verification/`；历史 evidence 不参与默认门禁。

## 4. 按模块导航

- API/数据：`apps/api`、`docs/03_Architecture.md`、`docs/05_DomainModel.md`。
- Web/UX：`apps/web`、`docs/11_UX_Workflows.md`、`docs/106_TeacherVisibleMetadataBudget.md`。
- Worker/OCR/AI：`workers/document`、`docs/07_Document_AI_ImportPipeline.md`、`docs/107_AITrustAndReviewContract.md`。
- 数据/迁移/恢复：`docs/14_BackupRecoveryMigration.md`、相关 tools 和 Release profile。
- 现场/发布：`tasks/live-pilot-closeout-plan.csv`、`docs/109_ReleaseGoNoGoCard.md`。

当前边界：`REAL005=not_closed`；`P001`、`P003`、`P005`、`P006` 仍依赖现场或人工证据，发布裁决保持 `No-Go`。repo-side verifier 通过不得改变这些状态。

高风险参考依据入口固定为：

- `tasks/reference-basis-requirements.csv`
- `tasks/reference-basis-module-map.csv`
- `sources/reference-shelf.manifest.snapshot.json`
- `tools/run-reference-basis-guard.ps1`

## 5. 禁止读取方式

- 不默认通读全部 docs。
- 不从日期化 evidence 选择下一任务。
- 不只看 backlog 的“已完成”推断 production/live。
- 不从旧完成切片文档或日期化 evidence 推导 current 状态。
- 不让 Q/R 未来能力因已有 ADR/模板进入当前实现。

## 6. 维护规则

- 新增 canonical owner 必须先证明现有 owner 无法承接。
- projection 必须从 canonical source 生成或通过一致性 verifier。
- 历史文档冻结后不持续刷新当前状态。
- 文件职责变化时同步更新本导航和 Executive Spec。
