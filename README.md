# 校本题谱：AI 原生校本题库与学情诊断平台

本仓用于本地 Codex CLI / AI Coding Agent 持续编码实现。当前目标不是“把所有未来功能一次做完”，而是按可验证小步闭环，把教师 Word/Excel 工作流迁移成可检索、可复用、可导出、可分析、可恢复的校本题库系统。

## 当前仓库状态

本仓已从**编码前设计包**进入可运行实现阶段：已有产品、架构、schema、配置、runbook、任务清单、ASP.NET Core API、React/Vite/Ant Design 前端、PostgreSQL/EF Core migration、Python Worker 占位、FileStore、ImportJob、health、backup 和统一 gate。

2026-05-02 外部资料复核后的判断：最高原则、默认技术栈、模块化单体架构和 P0/P1 纵切路线保持正确；需要在进入编码前先完成 P0 准入预检，锁定 SDK/runtime、PostgreSQL 版本、数据目录、Windows Service/content root 约束、BackgroundService job lease/retry 规则、学生数据/合规辖区边界和文档门禁。

当前 P0/P1 已打通“上传文件 -> 创建 ImportJob -> 持久化元数据 -> Python Worker 占位 -> 页面预览/人工确认/来源回看 -> health -> backup manifest -> unified gate”纵切闭环。P2 已完成 C001、C002A-C002Q：draft bootstrap 可用于测试，广州中考 33 份原始来源资料已进入 `SourceDocument/FileAsset` 证据层，cleaned candidate 已进入 `candidate/pending_review` 动态资产和审核队列，来源 PDF 已完成本地 chunk/hash/cache 证据层，候选提炼 schema/eval 已验证，分层模型路由预算门禁已证明 full extraction 必须人工预算确认，outer AI runner/subagent 编排 readiness 已证明不启用项目内生产真实模型、不写 active、不引入运行时 subagent 依赖，小批量 AI extract contract dry-run 已生成候选输出、模型层级、token/cost/cache 证据且不覆盖 C002K；正式 C002 仍必须经过人工审核、影响确认、回滚快照和 active guard。P3 已在 draft/test 模式完成 D001-D003：真实模型调用仍禁用，LLM 路由只进入 `stub_llm`、成本日志和结构化输出 eval smoke，结果保持人工审核边界。P4 已开始 E001 draft/test 题库检索和题目卡片合同，生产筛题仍等待正式 C002。

`C002` 标记为正式完成时，只表示初中物理知识体系 v1 已成为当前生产默认版本，不表示永久冻结。后续修改必须走新候选版本、映射、影响报告、审核、回滚快照和 active 切换，旧版本保留给历史题目、旧卷和学情解释。

大模型提炼候选体系要先走本地优先审查、chunk/hash/cache、schema/eval、模型路由预算和小批量 dry-run，不直接把 33 个 PDF 全量送入高强模型。文件 hash、来源 metadata、CSV/JSON/YAML/schema、SQL、导入幂等、active guard、chunk cache、token 预算和中文显示 guard 都应先由本地工具 100% 覆盖；真实模型输出仍只能进入 `candidate/pending_review`，不得直接 active。

## 当前启动与门禁

API:

```powershell
$env:KQG_CONNECTION_STRING='Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres;Password=<local-password>'
dotnet run --project apps\api\K12QuestionGraph.Api.csproj --urls http://127.0.0.1:5275
```

Web:

```powershell
cd apps\web
npm run dev -- --host 127.0.0.1
```

统一 gate:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-gates.ps1
```

无数据库密码时的 C002 动态资产 dry-run:

```powershell
.\tools\run-c002-dry-run-suite.ps1
```

该命令验证 source material admission、draft -> formal replacement mapping、migration impact、candidate admission 和 activation guard，不连接数据库、不写生产数据。完整数据库 contract 仍需要 `PGPASSWORD` 并运行 `tools/run-gates.ps1`。

C002 候选资料与真实来源资料入口：

```powershell
.\tools\prepare-c002-candidate-csvs.ps1
.\tools\prepare-c002-candidate-csvs.ps1 -InputDir 'guangzhou-physics-full-research-package-2016-2025\csv' -OutputDir 'c002-k12-question-graph-candidate-csvs\cleaned'
.\tools\import-c002-source-materials.ps1 -SourceRoot 'D:\CODE\k12-question-graph\广州中考'
```

`prepare-c002-candidate-csvs.ps1` 只清洗候选 CSV，输出 `c002-k12-question-graph-candidate-csvs\cleaned`，不写库、不激活正式资产。默认兼容旧 `c002-*` 候选包；当输入目录包含 `c003-source-material.csv` 时，会自动把 `guangzhou-physics-full-research-package-2016-2025\csv` 的完整 `c003-*full` 数据转换成既有 C002 candidate import 格式，继续保持 `candidate/pending_review/productionEligible=false`。`import-c002-source-materials.ps1` 默认只 dry-run；真实导入必须先设置正确 `PGPASSWORD/KQG_CONNECTION_STRING` 并保留备份证据，再用 `-Apply -StartApi` 把原始 PDF 导入 `SourceDocument/FileAsset` 证据层。

候选数据写库入口：

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\import-c002-candidate-assets.ps1
.\tools\import-c002-candidate-assets.ps1 -Apply -BackupManifest 'D:\KQG_Backups\<timestamp>\manifest.json'
```

该入口只导入 `candidate/pending_review` 动态资产、映射、迁移计划和审核队列，不会激活正式 C002。

证据与回滚入口：

- `docs/evidence/P0_EVIDENCE_2026-05-02.md`
- `docs/evidence/P0_ROLLBACK_2026-05-02.md`

## 最高硬约束

> **教师工作流效率最大化。**

所有功能、界面、AI 设计、数据模型、工程取舍，均必须服从该原则。当功能完整性与教师使用效率冲突时，优先教师使用效率；当字段丰富性与录入负担冲突时，优先降低录入负担；当 AI 自动化与成本/可靠性冲突时，优先成本可控和结果可靠。

该原则必须可度量，至少用以下指标验收：

- 常规组卷从需求输入到可打印导出，目标不超过 10 分钟。
- 导入试卷时教师只处理异常项，不逐题确认全部结果。
- 高频流程默认值来自教师偏好、模板和历史映射，不要求重复配置。
- 每个新字段都能证明会用于检索、组卷、分析、导出或治理。
- 所有 AI 结果结构化、可审计、可人工接管、可回滚。
- P0/P1 默认不使用真实学生个人信息作为样本、fixture 或 prompt 内容；真实外部 AI 调用必须等数据边界和人工确认契约锁定后再评估。

## v0.1 冻结范围

v0.1 聚焦：

1. 初中物理。
2. Windows-first，本机开发，终态校本局域网部署。
3. 浏览器 Web 页面。
4. Word/PDF/图片试卷导入。
5. AI + 人工异常确认的试题入库。
6. 题图、公式、表格、多模态内容保留。
7. 可版本化、可替换、可追溯的物理知识体系，课标/教材/地区考点为映射层。
8. 题库检索、自然语言组卷、一键换题、Word/PDF 导出。
9. Excel 成绩导入、小题分映射、基础学情分析。
10. 自动备份、缓存清理、恢复包、WinPE 应急恢复方案。

明确不做：在线考试、在线监考、防作弊、全学科一次上线、自动主观题阅卷、复杂 IRT、完整 QTI/CASE 实现、学生端/家长端。

## 推荐实现顺序

先按 `docs/19_Roadmap.md` 与 `tasks/backlog.csv` 执行。P0/P1 已完成；当前继续把 v0.1 完整系统能力搭起来。知识点、标签、题型、难度、组卷规则、导出模板、Excel 映射、AI prompt/schema/model routing、分析指标、组织权限和隐私策略等动态元素都不得写死，但它们的可变性也不得阻断开发：先用 draft/test、synthetic fixture、sample config 或少量临时资料完成系统能力，正式资料以后再录入、映射、审核、激活。

```text
P0/P1: 打开应用 → 上传文件 → 创建 ImportJob → 写数据库 → 文件入仓 → 页面预览 → 人工确认 → 单题入库 → 来源回看 → 备份 manifest
P2/C002 draft-test: draft 知识点 → 替换映射 dry-run → 迁移影响报告 → candidate admission → active guard
P2/C002 dynamic contract: dynamic elements → one-to-one/one-to-many/many-to-one/many-to-many mapping → review workbench → impact/rollback
P3/D001-D003 draft-test: AI task → ModelRouter → rule/stub_llm → schema/prompt/model/cost log → structured output eval → human review guard
P4/E001 draft-test: question search → filter by draft knowledge/type/difficulty/source → question card preview → non-production guard
```

完整 v0.1 闭环仍是：

```text
上传文件 → AI/人工切题 → 入库 → 检索 → 组卷 → 导出 → Excel 成绩导入 → 基础分析 → 备份恢复
```

但编码必须从 P0/P1 开始，后续阶段不得倒插高级功能。

## 文件结构

```text
apps/      P0 运行项目：API 与 Web UI
docs/       需求、架构、UX、数据、AI、备份、安全、测试、路线图
schemas/    AI 结构化输出 JSON Schema 草案
configs/    默认配置草案：模型路由、标签、保留策略、备份策略等
diagrams/   Mermaid 架构图、ER 图、工作流图
runbooks/   运维与应急恢复指南
tasks/      任务拆解 CSV
prompts/    Codex CLI 交接提示词、AI 任务提示词模板
sources/    官方文档/最佳实践参考来源
tools/      P0 门禁、备份、恢复脚本
workers/    Python document/OCR/AI adapter
tests/      自动化测试与黄金样本
```

## 当前运行入口

- `apps/api`: 已提供 `dotnet run --project apps/api`，健康检查为 `http://localhost:5275/health`。
- `apps/web`: 已提供 `npm run dev --prefix apps/web`。
- `workers/document`: 提供 worker smoke entry。
- `tools/run-gates.ps1`: 统一门禁入口。
- `tools/run-c002-dry-run-suite.ps1`: 无数据库的 C002 动态资产 dry-run 入口。
- `tools/run-d001-model-router-contract.ps1`: D001 draft/test ModelRouter 合同。
- `tools/run-d003-structured-output-eval.ps1`: D003 draft/test 结构化输出 eval smoke。
- `tools/run-e001-question-search-contract.ps1`: E001 draft/test 题库检索和题卡合同。
- `tools/prepare-c002-candidate-csvs.ps1`: C002 ChatGPT Web 候选 CSV 清洗和预检入口。
- `tools/import-c002-source-materials.ps1`: C002 原始来源资料 dry-run / evidence-layer 导入入口。
- `tools/import-c002-candidate-assets.ps1`: C002 cleaned candidate DB dry-run / apply 入口。
- `tools/run-c002l-candidate-review-readiness.ps1`: C002 candidate review readiness / active blocker 报告入口。
- `tools/run-c002m-candidate-review-apply-contract.ps1`: C002 candidate review decision apply/rollback 合同入口。
- `tools/run-local-first-ai-guard.ps1`: 本地优先 AI 消耗削减与中文显示 guard。
- `tools/run-c002n-source-chunk-cache.ps1`: C002N 来源 PDF 本地 chunk/hash/cache 和中文报告 guard。
- `tools/run-c002o-candidate-extraction-eval.ps1`: C002O 候选提炼 schema/eval golden smoke。
- `tools/run-c002p-model-budget-guard.ps1`: C002P L0-L4 模型、reasoning、预算和 fail-closed guard。
- `tools/run-c002q0-outer-ai-readiness.ps1`: C002Q0 真实模型调用与 outer subagent 编排 readiness guard。
- `tools/run-c002q-ai-extract-dry-run.ps1`: C002Q 小批量 AI extract contract dry-run guard。

快速文档/配置门禁：

```powershell
python -c "import csv; list(csv.DictReader(open('tasks/backlog.csv', encoding='utf-8-sig'))); print('csv ok')"
python -c "import json, pathlib; [json.loads(p.read_text(encoding='utf-8')) for p in pathlib.Path('schemas').rglob('*.json')]; print('json ok')"
python -c "import pathlib, yaml; [yaml.safe_load(p.read_text(encoding='utf-8')) for p in pathlib.Path('configs').rglob('*.yaml')]; print('yaml ok')"
```

关键范围文件：

- `docs/02_MVP_Scope_and_ScopeControl.md`：v0.1 范围与后置边界。
- `docs/25_FeatureAdmissionCriteria.md`：新功能准入卡。
- `docs/28_FunctionScopeReview.md`：功能保留、修改、增加、后置与不进 v0.1 的裁决。
- `docs/58_DynamicEvolvableElements.md`：必须动态化的参数、数据、标签、模板、规则和映射基数清单。
- `docs/19_Roadmap.md`：动态元素不停工原则和 draft/test 先搭系统的阶段口径。

## 编码原则

1. 先模块化单体，不做复杂微服务。
2. 前端默认：React + TypeScript + Vite + Ant Design；shadcn/ui 仅作为需要高度定制时的备选。
3. 后端默认：ASP.NET Core / .NET 10 LTS，Windows Service 部署预留。
4. 数据库默认：PostgreSQL；自定义字段用 JSONB；全文检索先用 PostgreSQL FTS；向量检索先用 pgvector；图数据库后置。
5. 任务默认：P0 先用数据库持久化 job 表 + ASP.NET Core BackgroundService；需要仪表盘、复杂重试和定时任务后再引入 Hangfire；RabbitMQ 后置。
6. Worker：Python，用于 Docling、PaddleOCR、文档/OCR/AI 任务；通过 Adapter 与稳定 JSON 契约隔离。
7. 大文件不进数据库，进入文件仓库；数据库只保存元数据、路径、hash、引用关系。
8. 模型路由是内置模块，不是 README 建议。
9. 普通教师界面默认极简；高级能力隐藏在高级模式。
10. 所有 AI 结果都要有置信度、来源、prompt 版本、schema 版本、成本记录。
11. 所有备份恢复能力都不能只依赖主程序 UI，必须有独立脚本/恢复包。
12. 学生成绩、学生身份信息、题库原始资料和备份包按高风险资产处理；进入真实部署前必须锁定适用辖区、告知/授权、外部模型传输边界、数据保留和删除策略。
