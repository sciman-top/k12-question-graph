# AGENTS.md - k12-question-graph
**项目契约**: 2.0
**全局规则复核**: 9.77
**类型**: K-12 teacher-first question graph platform
**最后更新**: 2026-08-19

## 1. 当前落点与目标归宿
- 当前落点：本仓是校本题谱平台，当前聚焦初中物理，已有 API、Web、Worker、PostgreSQL、FileStore、备份与版本化领域资产。
- 目标归宿：以 teacher-first vertical slice 降低题库、组卷、导入和学情诊断工作量，同时保持 Word/Excel 兼容、数据可迁移与生产切换可回滚。
- 下一最小里程碑：按 `tasks/backlog.csv` 与当前证据真相交付首个未闭合切片；候选或本地证据不得写成 onsite/live 验收。
- task 状态、active 版本、部署和 onsite/live 结论从 backlog、数据库/运行探针及 `docs/evidence/` fresh read；根规则不复制计数或阶段快照。

## A. 仓库事实与模块边界
- `apps/`：API 与 Web；`workers/document`：文档、OCR 和 AI adapter；`tools/`：gate、backup 和 restore；`tests/`：回归；`schemas/`：结构合同。
- 规划与产品真源按需读取 README、constitution、PRD、architecture、domain、test、roadmap、task docs 与 `tasks/backlog.csv`，叙述冲突时先收口。
- 教师侧默认少步骤、少选择、少术语；权限、审计、备份、迁移和脚本参数下沉到管理层。
- `C002` 是生产默认；修订走 C002R 的 `candidate -> mapping -> impact report -> review -> rollback snapshot -> admin active switch`，禁止直接改旧 active。
- 动态领域资产带版本、状态、来源、映射、迁移和回滚；真实教材、真题、学生成绩、隐私和版权材料不得提交。
- 真实主链是“教师导入/建题 -> 题谱映射 -> 组卷或诊断 -> Word/Excel 交付 -> 教师复核”；先证明一条最薄 vertical slice，再扩平台能力。

## B. 执行与风险边界
- DB migration、active 切换、备份恢复、权限、外部 AI、真实数据与生产统计口径属于中高风险，先说明 snapshot/restore 与验收证据。
- AI 输出默认 `draft/test/pending_review`，不得自动写生产或绕过人工审核。
- 大文件与程序分离，数据库只存 metadata、path、hash 和 status。
- `tools/run-verification.ps1 -Profile Release -AuthorizeStateful` 会使用 PostgreSQL 并执行隔离备份恢复演练；只能在当前任务明确授权后运行，不能当无副作用 quick gate。
- 新功能说明减少的教师步骤、维护负担、失败继续路径及成本、隐私和备份影响。
- Markdown 规则只指导教师价值与风险；权限、schema、active switch、备份恢复和 gate 选择由 API/DB 约束、脚本、测试与 CI 强制。

### B.1 参考依据与外置源码
- 路由真源为 `sources/reference-shelf.manifest.snapshot.json`、`sources/references.md`、`docs/26_References.md` 与相关守卫；外置清单为 `D:\CODE\external\k12-question-graph-references\references.manifest.json`，共享克隆以 `D:\CODE\external\_shared\references.manifest.json` 为准。
- 文档、OCR、Open XML、schema/DB、AI adapter 或重复失败命中全局条件时按路由只读查阅，记录来源 URL、固定 revision、license、消费模块与采纳/适配/拒绝决定，并运行仓库 reference-basis guard。
- 不全量扫描或继承参考仓指令；复制或运行前核对许可证、版本、数据和隐私边界与授权。

## C. 门禁、证据与回滚
- fixed order：`build -> test -> contract/invariant -> hotspot`。
- 日常切片：`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-verification.ps1 -Profile Slice -ChangedPaths <PATHS>`；产品路径只运行对应 build/test，工具路径只运行脚本质量，纯文档按全局 A.4 的 gate N/A 口径返回，空选择或未知路径 fail-closed。
- 全栈无状态基线：`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-verification.ps1 -Profile Quick`；不得访问 PostgreSQL、停止进程、写 FileStore 或 tracked evidence。
- 发布门禁：明确授权后运行 `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-verification.ps1 -Profile Release -AuthorizeStateful`；已退役的 legacy monolith 只保留在 Git 历史中，不再有可执行兼容入口。
- contract/invariant 仅在当前变更触发相应风险时运行；不以历史任务、固定行数预算或迁移对账作为永久门禁。
- 进程或 DB 授权缺失时，Release 按全局 A.4 临时缺口字段记录，不能改写门禁顺序或伪称 full gate。
- 证据放 `docs/evidence/`，区分 repo-side、onsite/manual、deployed 与 live accepted。
- 回滚只撤销本任务；schema、data 或 active 变化必须附 migration down、snapshot/restore 与兼容读取证明。

## D. Git 与回滚
- Git baseline=`main`; upstream=`origin/main`; closeout=`proportional_slice_or_authorized_release`。
- 回滚只撤销本任务；schema、data 或 active 变化必须附 migration down、snapshot/restore 与兼容读取证明。
