# AGENTS.md - k12-question-graph
**项目契约**: 2.0
**全局规则复核**: 9.55
**类型**: K-12 teacher-first question graph platform
**最后更新**: 2026-07-10

## 1. 当前落点与目标归宿
- 当前落点：本仓是校本题谱平台，v0.1 聚焦初中物理，已有 API/Web/Worker/PostgreSQL/FileStore/backup 与版本化领域资产。
- 目标归宿：以 teacher-first vertical slice 降低题库、组卷、导入和学情诊断工作量，同时保持 Word/Excel 兼容、数据可迁移与生产切换可回滚。
- 下一最小里程碑：按 `tasks/backlog.csv` 顺序交付当前 P0/P1 slice；未来多学科/全量资产不构成停工理由。

## A. 仓库事实与模块边界
- `apps/`：API 与 Web；`workers/document`：文档/OCR/AI adapter；`tools/`：gate/backup/restore；`tests/`：回归；`schemas/`：结构合同。
- 规划与产品真源按需读取 `README.md`、constitution/PRD/architecture/domain/test/roadmap/task docs 与 `tasks/backlog.csv`，叙述冲突时先收口。
- 教师侧默认少步骤、少选择、少术语；权限、审计、备份、迁移和脚本参数下沉到管理层。
- `C002` 是当前生产默认；修订必须走 C002R 的 `candidate -> mapping -> impact report -> review -> rollback snapshot -> admin active switch`，禁止直接改旧 active。
- 动态领域资产必须带版本/状态/来源/映射/迁移/回滚；真实教材、真题、学生成绩、隐私和版权材料不得提交。

## B. 执行与风险边界
- DB migration、active 切换、备份恢复、权限、外部 AI、真实数据与生产统计口径属于中高风险，先说明 snapshot/restore 与验收证据。
- AI 输出默认 `draft/test/pending_review`；不得自动写入生产或绕过人工审核。
- 大文件与程序分离，数据库只存 metadata/path/hash/status；不得把 FileStore 内容塞入数据库。
- `tools/run-gates.ps1` 会使用 PostgreSQL 并可能暂停/恢复仓库 API 进程；运行前必须获得当前任务明确确认，不能把它当作无副作用 quick gate。
- 新功能必须说明减少的教师步骤、增加的维护负担、失败后的继续路径及成本/隐私/备份影响。

## C. 门禁、证据与回滚
- fixed order：`build -> test -> contract/invariant -> hotspot`。
- agent-rule contract CI：`.github/workflows/agent-rule-contract.yml` 只验证规则契约，不替代本仓产品门禁。
- build：`dotnet build apps/api/K12QuestionGraph.Api.csproj`
- test/full：`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gates.ps1`，仅在 PostgreSQL/进程影响获确认后执行。
- contract/invariant：`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`
- hotspot：当前无独立命令；按 `gate_na` 记录 `reason=仓库尚无独立 hotspot`、`alternative_verification=受影响 API/UI/worker/data/AI/export 合同与教师效率复核`、`evidence_link=docs/18_TestStrategy.md`、`expires_at=next_executable_change`。
- quick：`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-c002-dry-run-suite.ps1`；只证明无数据库 C002 dry-run，不能替代 full gate。
- 规则/文档 slice 若因数据库与进程影响不运行 full gate，必须逐项记录 `gate_na` 四字段，并至少解析 CSV/JSON/YAML、运行 roadmap guard 与静态项目规则审计。
- backlog/roadmap/README 顺序冲突、schema parse 失败或 C002R 状态语义破坏时阻断。
- 证据放入 `docs/evidence/`；DB/FileStore/active 变化额外记录 snapshot、manifest 或 restore 命令。
- 回滚只撤销当前代码/规则/证据 slice；数据变化必须使用已记录 backup/restore，不能用 Git 回滚代替。

## D. Global Rule -> Repo Action
- `R1-R5`：声明仓库状态/落点/slice，按 backlog 小步交付；不扩张 v0.1，不把未来资产写死。
- `R6`：C 章固定顺序；full gate 的环境/进程影响必须先确认，quick 不替代 full。
- `R7`：保护 schema、migration、backup manifest、C002/C002R 与教师工作流兼容。
- `R8`：`docs/evidence/` 记录命令、兼容、数据证据和回滚。
- `E4`：full gate/roadmap guard 承接健康；`E5`：NuGet/npm/Python/AI/OCR 变化记录供应链与成本/隐私；`E6`：领域资产、DB、backup/export/metric 变化必须有迁移、兼容和回滚。
