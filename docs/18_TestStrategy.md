# 18 · 测试与验证策略

## 1. 目标

验证必须优先发现真实产品风险，同时保持反馈快速、失败可归因、副作用可见。测试数量或 evidence 数量不是质量指标；教师工作流、数据兼容、来源可信、人工审核、隐私和可恢复性才是质量目标。

## 2. 固定门禁语义

```text
build -> test -> contract/invariant -> hotspot
```

- build：编译、类型、依赖和基本打包。
- test：业务规则、组件行为、API/service、worker 单元与集成测试。
- contract/invariant：schema、API、数据状态、权限、no-active-write、迁移和兼容边界。
- hotspot：当前切片最可能破坏的真实用户/数据路径。

不得用大量静态字符串检查替代行为测试，也不得以 full gate 通过代替现场事实。

## 3. Verification profiles

### Quick

适用于普通本地反馈：backend/frontend/worker build、lint、unit tests、JSON/YAML/CSV parse。禁止 PostgreSQL、停止/启动常驻进程、FileStore 写入和 tracked evidence。

### Slice

适用于当前 task：不先跑整套 Quick，而是根据 task ID、changed paths、风险和 owner module 选择最小 build/test/contract/invariant/hotspot 链。API、Web、Worker 各自保留 build/test 闭环；docs/governance 不拉起无关产品栈。unknown path、空选择必须 fail-closed 或提升 profile。

### Release

适用于 release candidate 或明确授权的 stateful closeout。默认 Release = Quick + migration/privacy/API/no-active-write contracts + NS806 isolated backup/restore/upgrade + closure invariants + 状态指纹对账；不遍历 legacy monolith，不刷新日期化 tracked evidence，不写共享 FileStore fixture。允许的 DB 影响必须提前声明。

只有显式 `-IncludeLegacyCompatibility` 才运行 legacy audit（当前 inventory 208 steps）；它用于低频兼容审计，不是默认发布阻断链。

### Onsite

适用于隔离机、学校网络、打印、权限域、真实教师操作和签字。自动化可以准备执行包、采集客观 trace、验证导入证据，但不得合成签字或把 proxy/synthetic 写成 live accepted。

## 4. 选择规则

每个 task spec 必须声明：

- `verification_profile`
- `focused_verifiers`
- `stateful_verifiers`
- `requires_database`
- `stops_process`
- `writes_filestore`
- `evidence_policy`

Q001-Q005 和 R001-R007 在 P006 前不进入默认 Quick；仅在 changed paths、当前 task 或 Release 显式命中时运行。

## 5. 测试类型和 owner

| 类型 | 首选实现 | 主要证明 |
|---|---|---|
| 业务规则 | .NET/Python/TypeScript unit test | 输入输出和边界 |
| API/workflow | API/service integration test | 协议、状态和事务 |
| UI | Testing Library/Playwright | 用户能否完成动作 |
| 静态合同 | 少量 PowerShell/schema guard | 安全、权限、结构不变量 |
| OCR/AI | golden/eval + source anchor | 质量、失败接管、candidate 边界 |
| 导出 | artifact regression | Word/PDF/公式/题图/表格 |
| 数据 | migration/backup/restore drill | 兼容与可恢复 |
| 现场 | checklist + trace + signoff | 实际环境和教师验收 |

## 6. UI 静态合同策略

- keep：权限、no-active-write、教师/管理员边界、安全 fail-closed。
- replace：class、CSS selector、固定 DOM 结构和文案存在性，迁移到行为测试。
- delete_after_parity：新行为测试已覆盖且通过覆盖对账后退出默认 profile。

先补等价测试，再移除旧检查；不按脚本数量机械删除。

## 7. Golden samples

导入/OCR/公式/表格/题图/导出/成绩映射保留代表性 golden set。样本必须是合成、公开授权或充分匿名化材料，并记录 source、license/privacy、expected output、失败接管和适用范围。

真实题目候选、proxy 流程或 synthetic fixture 不能替代教师/现场 acceptance。

## 8. Evidence policy

| 运行 | 默认输出 | 是否 tracked |
|---|---|---:|
| Quick/Slice | `tmp/verification/<run-id>/` | no |
| 临时诊断 | `tmp/` | no |
| 默认 Release/migration/restore rehearsal | `tmp/verification/<run-id>/` | no |
| 稳定 release reconciliation / onsite acceptance | `docs/evidence/` | yes |
| Onsite/live | 签收报告与附件 | yes |

同一未变化 guard 不应每天生成新的 tracked 快照。后续由 `docs/evidence/index.json` 标识 current/superseded/authority。

## 9. 完成声明

- Quick/Slice pass：只证明当前 repo-side slice。
- Release pass：只证明授权环境的 release-side 技术门禁。
- Onsite pass：必须绑定真实环境、操作者、时间、输入和签字。
- `REAL005`、production active、release 或 live accepted 只能由各自权威事实改变。

## 10. 当前迁移边界

当前迁移状态：

- `tools/run-verification.ps1 -Profile Quick|Slice` 是普通入口；Quick 是全栈无状态基线，Slice 是 task/path 聚焦链，报告只进入 `tmp/verification/`；
- 默认 Release 通过 `tools/run-verification.ps1 -Profile Release -AuthorizeStateful` 执行聚焦 core；`tools/run-gates.ps1` 只能由 `-IncludeLegacyCompatibility` 显式进入；
- 默认 Release 必须记录 DB/FileStore/进程前后指纹，`sharedFileStoreWriteExpected=false`；状态 pass 不得掩盖 FileStore 变化或数据库 row-level 未比较的边界；
- Onsite 仍只接受真实环境、操作者、输入、时间与签字证据。
