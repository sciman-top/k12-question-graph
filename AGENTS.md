# AGENTS.md - K12 Question Graph Project Rules

**承接来源**: `GlobalUser/AGENTS.md v9.50`
**适用范围**: `D:\CODE\k12-question-graph`
**最后更新**: 2026-05-04

## 1. 项目定位与当前状态

本仓是 **校本题谱 / School-Based Question Graph / K12 Question Graph**，目标是面向 K-12 教师的 AI 原生校本题库、组卷和学情诊断平台。v0.1 只聚焦初中物理。

最高硬约束：**教师工作流效率最大化**。任何功能、架构、UI、AI、数据模型和实施顺序，都必须证明能减少教师工作量、降低认知负担，并优先改善现有 Word/Excel 工作流。

长期产品约束：**一切流程、界面、文案和操作入口都必须力求简化、便捷**。普通教师侧默认只暴露最少步骤、最少选择、最少术语和明确下一步；脚本参数、证据、备份、回滚、迁移、权限和审计细节应下沉到管理员/代理/系统层。新增流程或 UI 若不能证明比当前做法更省事、更清楚、更少打扰，默认后置或重设计。

当前仓库事实：

- 已初始化 Git；`main` 跟踪 `origin/main`。每轮变更前必须检查 `git status --short --branch`，若已有脏改动，先区分用户改动与本轮改动。
- 当前已有 API、Web、Worker、PostgreSQL/EF Core migrations、FileStore、backup、统一 gate、P1 导入闭环、P2 动态资产合同、C002 初中物理 v1 active、C002R active 后修订合同、P3 draft/test AI 合同、P4 draft/test 组卷导出合同、P5 draft/test 学情分析合同和 P6 draft/test 备份/存储运维合同。
- `C002` 正式知识体系已成为当前初中物理生产默认 v1，但不表示永久冻结；后续修改必须走 C002R：新建 `candidate` 版本、映射、影响报告、审核、回滚快照和管理员 active 切换，不直接改旧 `active`。所有其他依赖动态元素的任务仍应先以 `draft/test`、`candidate`、`pending_review`、`productionEligible=false` 的方式推进，正式数据录入、映射审核和 active 激活后再切换生产口径。
- 下一最小可执行里程碑按 `tasks/backlog.csv` 顺序推进，优先补齐完整 v0.1 系统闭环；不要因为知识点、标签、题型、难度、模板、评分规则、组织权限、隐私策略等动态元素未来会变化而停工。

## A. 仓库事实与范围边界

### A.1 v0.1/P0/P1 范围

只实现 P0/P1 起步能力：

1. Windows-first local/LAN Web app foundation。
2. ASP.NET Core backend。
3. React + TypeScript + Vite + Ant Design frontend。
4. PostgreSQL database。
5. Python Worker placeholder for document/OCR/AI tasks。
6. File-store layout。
7. Basic backup/restore script stubs。
8. Basic domain model migrations。
9. Basic upload/import task skeleton。
10. Simple teacher-first UI shell。

v0.1 不做：在线考试、在线监考、防作弊、学生端/家长端、公网 SaaS、全学科正式支持、自动主观题阅卷、复杂 IRT、完整 QTI/CASE/OneRoster/Caliper 实现、微服务/RabbitMQ/Kubernetes/图数据库优先方案。

### A.2 必读顺序

变更代码、架构、规则或任务拆解前，按需读取以下文件；涉及编码或范围裁决时必须完整读取：

1. `README.md`
2. `ALL_IN_ONE_EXECUTIVE_SPEC.md`
3. `docs/00_ProjectConstitution.md`
4. `docs/01_PRD.md`
5. `docs/02_MVP_Scope_and_ScopeControl.md`
6. `docs/03_Architecture.md`
7. `docs/04_TechnologyStack.md`
8. `docs/05_DomainModel.md`
9. `docs/07_Document_AI_ImportPipeline.md`
10. `docs/09_AI_ModelRouting_CostControl.md`
11. `docs/11_UX_Workflows.md`
12. `docs/14_BackupRecoveryMigration.md`
13. `docs/18_TestStrategy.md`
14. `docs/19_Roadmap.md`
15. `docs/20_TaskBreakdown.md`
16. `tasks/backlog.csv`

### A.3 模块目标归宿

- `apps/api`: ASP.NET Core modular monolith API、Domain、EF Core migrations、job store、health checks。
- `apps/web`: React + TypeScript + Vite + Ant Design teacher-first UI。
- `workers/document`: Python adapter placeholder for Docling/OpenXML/PaddleOCR/OCR/AI tasks。
- `tools`: backup/restore/verify/gate scripts independent from Web UI。
- `tests`: backend/frontend/worker smoke tests、schema/config/CSV gates、future golden import fixtures。
- `docs/evidence`: A011 后存放 gate 命令、退出码、关键输出、`gate_na` 和回滚记录。

### A.4 治理运行时接入

- 本仓已纳入 `D:\CODE\governed-ai-coding-runtime` 目标仓 catalog，`repo_id` 为 `k12-question-graph`。
- 受管治理资产归 `.governed-ai/` 与 `.claude/`；应用代码、项目规则、README、业务 docs 和 `tools/` 不应由一键治理盲覆盖。
- `.governed-ai/repo-profile.json` 是当前治理 profile 的机器可读承接点；人工阅读和跨工具项目规则仍以 `AGENTS.md` 为主，`CLAUDE.md` / `GEMINI.md` 只写平台差异。
- 一键应用入口由控制仓执行：`pwsh -NoProfile -ExecutionPolicy Bypass -File D:\CODE\governed-ai-coding-runtime\scripts\runtime-flow-preset.ps1 -Target k12-question-graph -ApplyGovernanceBaselineOnly -ApplyCodingSpeedProfile -Json`。
- 同名受管文件漂移必须 fail-closed 后整合；不得为了“通用”复制其他目标仓的私有规则、目录、CI、脚本或测试。

## B. 项目执行规则

### B.1 默认工作流

每次改动前先简述：

1. 当前仓库状态。
2. 当前落点与目标归宿。
3. 下一最小可执行里程碑。
4. 本轮只实现的最小 slice。

然后执行，不要停在建议层。低风险文档/规则修复可直接做；中高风险编码、数据结构、迁移、备份、权限和删除类操作必须先说明回滚路径。

### B.2 P0 执行顺序

严格按 `tasks/backlog.csv`：

1. `A000` P0 准入预检。
2. `A000A` P0 编码前契约收口。
3. `A001` 创建 monorepo 目录结构。
4. `A002-A011` 建立 API/Web/DB/Worker/FileStore/Backup/Gate/证据包。

`A000/A000A` 未完成前，只允许补文档、规则、schema、准入检查和任务一致性；不要创建大块业务实现。

### B.3 教师效率准入

新增功能、字段、页面、AI 调用或外部工具前，必须回答：

- 减少哪一步教师工作？
- 是否增加确认、配置或维护负担？
- 是否把复杂脚本、参数、证据、备份、回滚、迁移或权限细节转嫁给普通教师？
- 能否用默认值、模板、自动判断、后台任务或管理员层入口继续简化？
- 失败后教师如何继续？
- 是否影响成本、隐私、备份或恢复？
- 是否属于 P0/P1 必需能力？

不能证明高频、高价值、低负担、可测试、可回滚的需求，进入 backlog，不进入当前 slice。
不能证明“更简化、更便捷”的流程或界面，不得直接交给普通教师使用。

### B.4 动态领域资产与不停工原则

知识点、教材章节、课程标准、地区考点、题型、标签、难度/能力维度、评分标准、组卷规则、AI prompt/schema/model routing、文档解析 pipeline、分析指标、导出模板、隐私策略和学校组织结构都不得作为静态常量写死。它们必须按 version/status/source/mapping/migration/rollback 建模，属于可演进领域资产。

规则和 AI 可以自动生成映射、替换和迁移建议，高置信度、低影响、可回滚的一对一变更可自动应用；一拆多、多合一、低置信度、高影响、影响历史学情口径或生产规则的变更必须进入人工审核。

C002 正式完成前，draft bootstrap 可用于 API/UI/回归测试、组卷约束、AI schema、Evals、成本日志和迁移建议；不得把 draft 知识点或真实模型输出标记为生产正式完成。正式来源提炼后的 active 资产必须保留草稿历史、替换映射、影响报告和回滚入口。

动态元素的可变性不得成为停工理由。除“正式生产激活/正式统计口径/真实外部 AI 自动写入/真实学生数据处理”外，相关任务都可以先用少量 synthetic、draft、sample 或教师临时提供的原始资料完成 draft/test 版本，并纳入 gate。后续正式资料录入后，通过映射、替换、迁移影响报告、人工审核和回滚快照更新已有系统能力。

需要临时资料时，只提出最小集合和存放位置，例如 `sources/raw/` 或 `D:\KQG_Data\source_materials\staging\`；真实教材、课标、真题、学生成绩和含版权/隐私风险资料不得提交进 Git。没有正式资料时，优先使用 synthetic fixtures 和 draft bootstrap 完成系统搭建。

### B.5 全局/项目协同边界

- 全局规则给通用行为、风险语义、N/A 口径和 Codex/Claude/Gemini 平台差异；本文件只给 K12 Question Graph 的仓库事实、门禁、归宿和领域不变量。
- Codex 直接读取 `AGENTS.md`；Claude/Gemini 的项目文件只 import 本文件并追加平台差异，不复制共同规则。
- 若全局规则与本仓事实冲突，先以代码、README、backlog、schema 和当前命令结果为准，再修正规则；不要用聊天里的临时说法覆盖仓库事实。
- 任何项目规则新增项都必须指向一个可验证入口：文件、命令、schema、任务编号、证据路径或明确禁止边界。

## C. 门禁与证据

### C.1 硬门禁顺序与当前命令

固定顺序：`build -> test -> contract/invariant -> hotspot`。

当前 full gate 由统一入口承接：

```powershell
tools/run-gates.ps1
```

治理 profile 中的当前 gate 映射：

- `build`: `dotnet build apps/api/K12QuestionGraph.Api.csproj`
- `test`: `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gates.ps1`
- `contract/invariant`: `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`
- `hotspot`: 当前无独立 hotspot 命令；由 full gate 中的 database、backup、import、dynamic asset、AI stub、paper export 和 assessment analytics contracts 承接。若单独交付需要热点证据，必须在报告中写明覆盖到的脚本和 `gate_na` 边界。

### C.2 快速反馈与 daily quick

日常快速反馈优先使用治理 profile 中的 quick gates：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-c002-dry-run-suite.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1
```

控制仓 daily quick 入口：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\CODE\governed-ai-coding-runtime\scripts\runtime-flow-preset.ps1 -Target k12-question-graph -FlowMode daily -Mode quick -Json
```

quick gates 只证明无数据库 C002 动态资产 dry-run 与 roadmap 依赖一致性；不能替代 `tools/run-gates.ps1` full gate。

### C.3 Full gate 边界

```powershell
tools/run-gates.ps1
```

该入口覆盖：

- backend build/test。
- frontend build/test/typecheck。
- worker syntax/import smoke。
- JSON schema parse。
- YAML/CSV parse。
- migration smoke 或明确 `gate_na`。
- backup manifest generate/verify。
- upload/import job/file store/backup manifest hotspot。
- C001/C002/C002R/C002T、P3 AI stub、P4 组卷导出、P5 学情分析等当前合同。

局部测试只能作为快速反馈，不能替代 full gate。

### C.4 文档/规则轻量门禁

纯文档或规则修改可先跑轻量解析和检索：

```powershell
python -c "import csv; list(csv.DictReader(open('tasks/backlog.csv', encoding='utf-8-sig'))); print('csv ok')"
python -c "import json, pathlib; [json.loads(p.read_text(encoding='utf-8')) for p in pathlib.Path('schemas').rglob('*.json')]; print('json ok')"
python -c "import pathlib, yaml; [yaml.safe_load(p.read_text(encoding='utf-8')) for p in pathlib.Path('configs').rglob('*.yaml')]; print('yaml ok')"
rg -n "GlobalUser/.*v9.50|run-gates|run-c002-dry-run-suite|run-roadmap-guard|P0|P1|C002|F003" AGENTS.md CLAUDE.md GEMINI.md README.md docs/19_Roadmap.md docs/20_TaskBreakdown.md tasks/backlog.csv
```

若 `yaml` 模块不存在，不要安装依赖作为规则修改的副作用；记录 `gate_na`，并用 `rg --files configs -g "*.yaml"` 与 UTF-8 读取作为替代证据。

### C.5 失败分流与阻断条件

- `A000/A000A` 未完成时，阻断业务代码和大目录骨架生成；只允许修文档、schema、配置、准入检查和任务一致性。
- CSV/JSON/YAML 解析失败时，先修格式或 schema 事实；不得把失败降级成普通 `gate_na`。
- YAML parser 缺失、PostgreSQL 未安装、CLI 命令不存在等环境缺口可记 `platform_na/gate_na`，但必须给替代验证和复测条件。
- README、roadmap、task breakdown、backlog 对 P0/P1 顺序不一致时，先收口文档一致性，再进入编码。
- 任何数据目录、备份恢复、数据库 migration、权限、外部工具或真实 AI 调用变更，都视为中高风险；先说明回滚路径和验证证据。
- `.governed-ai/repo-profile.json`、`.claude/settings.json` 或 hooks 与控制仓 catalog/baseline 不一致时，先跑控制仓一致性校验并整合漂移，不手工扩大 allowlist 或复制其他目标仓配置。

## D. 安全、数据与回滚

### D.1 数据与文件

- 数据和程序文件必须分离。
- 大文件不得直接进数据库；数据库只保存 metadata/path/hash/status。
- 默认数据目录、备份目录、日志目录、FileStore 必须显式配置，不依赖当前工作目录。
- Windows Service 发布时不得依赖当前 shell 或工作目录。

### D.2 AI 与外部工具

- AI/model routing 是后端内部服务抽象，不暴露给普通教师。
- 所有 AI 输出必须结构化、可审计、可人工接管、可回滚。
- Docling/PaddleOCR/OpenXML/Pandoc 等外部工具必须经 Adapter 转内部模型；不得把原始工具输出直接当领域模型。
- P0/P1 不以真实 AI 调用作为完成条件；只能建立 schema、AIJob/AIResult 字段和可替换 worker/adapter 占位。

### D.3 回滚与证据

- 当前仓已初始化 Git；做代码级或多文件结构性变更前，先确认 `git status --short --branch`，必要时先提交基线或记录可逆补丁。
- 规则/文档变更后，至少报告 changed files、执行命令、退出码、关键输出、`gate_na` 和剩余风险。
- A011 后证据归档到 `docs/evidence/`；A011 前证据可先保留在会话报告中。
- 受管治理资产回滚优先使用 Git；若需移除一键治理资产，先核对 `.governed-ai/managed-files/` provenance，再删除对应 `.governed-ai/` 或 `.claude/` 受管文件并复跑控制仓 consistency。

### D.4 规则源与同步

- 本仓项目级规则源是仓库根 `AGENTS.md`、`CLAUDE.md`、`GEMINI.md`；共同规则只在 `AGENTS.md` 维护，Claude/Gemini 文件只承接并追加平台差异。
- 本仓已纳入 `governed-ai-coding-runtime` 目标仓 catalog；控制仓只管理 `.governed-ai/` 与声明的受管 settings/hooks，不把其他目标仓项目规则同步到本仓。
- 若后续纳入更广的 manifest/同步管线管理，必须先回写源规则，再同步到目标副本；同版本内容漂移不得盲目覆盖。
- 修改全局用户级规则时，不以本仓项目文件为源；应更新全局源规则和已分发用户级副本，并复核三工具加载模型。

## E. Global Rule -> Repo Action

- `R1`: 每轮先声明当前落点：设计包、规则、A000/A000A、或具体 P0 子项目。
- `R2`: 只做 `tasks/backlog.csv` 中下一可验证任务；动态元素未正式确定时继续完成 draft/test 系统能力，不因等待正式数据而停工。
- `R3`: 文档止血必须写明后续归宿，例如 A000A、ADR、schema、runbook 或 gate。
- `R4`: 数据库迁移、备份恢复、删除、权限和外部工具引入视为中高风险。
- `R5`: 不提前引入微服务、RabbitMQ、图数据库、完整标准互操作或多学科实现。
- `R6`: full gate 使用 `tools/run-gates.ps1`；daily quick 使用 `tools/run-c002-dry-run-suite.ps1` + `tools/run-roadmap-guard.ps1`，不能替代 full gate。
- `R7`: 不破坏 v0.1/P0/P1 范围、教师效率原则、文件/数据库分离和 AI 可审计契约。
- `R8`: 报告必须包含依据、命令、证据、回滚方式。
- `E4`: gate、合同和治理接入证据进入 `docs/evidence/`，控制仓接入证据保留在 `D:\CODE\governed-ai-coding-runtime\docs\change-evidence\`。
- `E5`: 依赖、外部工具、PostgreSQL、Node/npm、Python worker 与 AI/OCR adapter 必须由 full gate、版本记录或明确 `gate_na` 承接。
- `E6`: 任一 schema/migration/status transition 变更必须有迁移与回滚说明。
