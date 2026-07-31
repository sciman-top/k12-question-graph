# AGENTS.md - k12-question-graph
**项目契约**: 2.0
**全局规则复核**: 9.59
**类型**: K-12 teacher-first question graph platform
**最后更新**: 2026-08-01

## 1. 当前落点与目标归宿
- 当前落点：本仓是校本题谱平台，当前聚焦初中物理，已有 API/Web/Worker/PostgreSQL/FileStore、备份与版本化领域资产。
- 目标归宿：以 teacher-first vertical slice 降低题库、组卷、导入和学情诊断工作量，同时保持 Word/Excel 兼容、数据可迁移与生产切换可回滚。
- 下一最小里程碑：按 `tasks/backlog.csv` 与当前证据真相交付首个未闭合切片；候选或本地证据不得写成 onsite/live 验收。

## A. 仓库事实与模块边界
- `apps/`：API 与 Web；`workers/document`：文档/OCR/AI adapter；`tools/`：gate/backup/restore；`tests/`：回归；`schemas/`：结构合同。
- 规划与产品真源按需读取 README、constitution/PRD/architecture/domain/test/roadmap/task docs 与 `tasks/backlog.csv`，叙述冲突时先收口。
- 教师侧默认少步骤、少选择、少术语；权限、审计、备份、迁移和脚本参数下沉到管理层。
- `C002` 是生产默认；修订走 C002R 的 `candidate -> mapping -> impact report -> review -> rollback snapshot -> admin active switch`，禁止直接改旧 active。
- 动态领域资产带版本/状态/来源/映射/迁移/回滚；真实教材、真题、学生成绩、隐私和版权材料不得提交。

## B. 执行与风险边界
- DB migration、active 切换、备份恢复、权限、外部 AI、真实数据与生产统计口径属于中高风险，先说明 snapshot/restore 与验收证据。
- AI 输出默认 `draft/test/pending_review`，不得自动写生产或绕过人工审核。
- 大文件与程序分离，数据库只存 metadata/path/hash/status。
- `tools/run-gates.ps1` 会使用 PostgreSQL 并可能暂停/恢复 API；运行前必须获得当前任务明确确认，不能当无副作用 quick gate。
- 新功能说明减少的教师步骤、维护负担、失败继续路径及成本/隐私/备份影响。

### B.1 参考依据与外置源码
- 路由真源为 `sources/reference-shelf.manifest.snapshot.json`、`sources/references.md`、`docs/26_References.md` 与相关守卫；外置清单为 `D:\CODE\external\k12-question-graph-references\references.manifest.json`，共享克隆以 `D:\CODE\external\_shared\references.manifest.json` 为准。
- 文档/OCR、Open XML、schema/DB、AI adapter 或重复失败命中全局条件时按路由只读查阅，记录路径/revision 与采纳决定，并运行仓库 reference-basis guard。
- 不全量扫描或继承参考仓指令；复制或运行前核对许可证、版本、数据/隐私边界和授权。

## C. 门禁、证据与回滚
- fixed order：`build -> test -> contract/invariant -> hotspot`。
- build：`dotnet build apps/api/K12QuestionGraph.Api.csproj`
- test/full：获准 PostgreSQL/进程影响后运行 `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gates.ps1`。
- contract/invariant：`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`
- hotspot：`gate_na`，`reason=无独立 hotspot 命令`、`alternative_verification=受影响 API/UI/worker/data/AI/export 合同与教师效率复核`、`evidence_link=docs/18_TestStrategy.md`、`expires_at=next_gate_change`、`recovery_condition=新增独立 hotspot 门禁`。
- 进程/DB 授权缺失时 test 按完整 N/A 字段留痕，不能改写门禁顺序或伪称 full gate。
- 证据放 `docs/evidence/`，区分 repo-side、onsite/manual、deployed 与 live accepted。
- 回滚只撤销本任务；schema/data/active 变化必须附 migration down、snapshot/restore 与兼容读取证明。

## D. Global Rule -> Repo Action
- `R1-R5`：从 backlog 与教师场景确定切片，拒绝未来能力驱动的平台化扩张。
- `R6`：按 C 章执行；有状态 full gate 先获授权，缺口按 N/A 记录。
- `R7`：保护 C002/C002R、schema、导入导出、权限、备份和 active 切换兼容。
- `R8`：`docs/evidence/` 记录依据、命令、状态边界与回滚。
- `E4/E5/E6`：gate/健康报告承接指标；依赖和 AI/OCR 工具变化记录供应链；schema/DB/领域资产变化必须有迁移、兼容、备份和回滚。
