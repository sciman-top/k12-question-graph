# AGENTS.md - k12-question-graph Shared Project Rules / Codex Direct
**项目**: k12-question-graph
**类型**: K-12 teacher-first question graph platform
**承接来源**: `GlobalUser/AGENTS.md v9.52`
**适用范围**: 项目级（仓库根）
**最后更新**: 2026-05-04

## 1. 阅读指引
- 本文件是三工具共同项目规则主体；Codex 直接读取，Claude/Gemini 通过各自 wrapper 的 `AGENTS.md` import 承接并只追加平台差异。
- 固定结构：本文件保持 `1 / A / B / C / D`；Claude/Gemini wrapper 保持 `1 / B / D`，并通过 import 承接本文件 `A/C/D`。
- 裁决链：`运行事实/代码 > README/backlog/schema/gate > 项目级规则 > 全局规则 > 临时上下文`。
- 自包含边界：根文件必须保留项目边界、门禁、证据和回滚；长产品说明、研究材料和 runbook 放入 `docs/`、`runbooks/`、`tasks/` 或 `sources/`。
- 渐进披露：编码前按任务读取相关 docs；不要把 `README.md`、PRD、架构文档或 backlog 全文复制进规则。

## A. 项目基线
### A.1 事实边界
- 本仓是校本题谱 / School-Based Question Graph，v0.1 聚焦初中物理，核心目标是让教师题库、组卷、导入和学情诊断更省事。
- 最高硬约束：教师工作流效率最大化；新增功能必须减少教师工作量、降低认知负担，并优先兼容现有 Word/Excel 工作流。
- 普通教师侧默认少步骤、少选择、少术语；脚本参数、证据、备份、回滚、迁移、权限和审计细节下沉到管理员/代理/系统层。
- 当前已有 API、Web、Worker、PostgreSQL/EF Core migrations、FileStore、backup、统一 gate、P1 导入闭环、C002/C002R 动态资产合同、P3/P4/P5 draft/test 合同。
- `C002` 初中物理 v1 是当前生产默认；后续修改必须走 C002R：`candidate -> mapping -> impact report -> review -> rollback snapshot -> admin active switch`，不得直接改旧 `active`。
- 动态领域资产不得写死：知识点、章节、课标、题型、标签、难度、评分、组卷规则、AI prompt/schema/model routing、分析指标、导出模板、隐私策略和组织结构都必须带版本/状态/来源/映射/迁移/回滚。
- 真实教材、真题、学生成绩、隐私数据和版权敏感材料不得提交进 Git；临时资料放 `sources/raw/` 或本机 staging 路径，并记录来源与可删除边界。

### A.2 必读与落点
- 代码、架构、规则或任务拆解变更前，按需读取：`README.md`、`ALL_IN_ONE_EXECUTIVE_SPEC.md`、`docs/00_ProjectConstitution.md`、`docs/01_PRD.md`、`docs/02_MVP_Scope_and_ScopeControl.md`、`docs/03_Architecture.md`、`docs/05_DomainModel.md`、`docs/11_UX_Workflows.md`、`docs/14_BackupRecoveryMigration.md`、`docs/18_TestStrategy.md`、`docs/19_Roadmap.md`、`docs/20_TaskBreakdown.md`、`tasks/backlog.csv`。
- 当前最小里程碑按 `tasks/backlog.csv` 顺序推进；动态元素未来会变化不能成为停工理由，可先用 synthetic/draft/sample 完成 draft/test 能力并纳入 gate。
- 每轮先检查 `git status --short --branch`；若已有脏改动，区分用户改动、治理生成文件和本轮改动。
- 当前模块归宿：`apps/api` 后端，`apps/web` 前端，`workers/document` 文档/OCR/AI adapter，`tools` gate/backup/restore，`tests` 测试，`docs/evidence` 或任务指定 evidence 路径存证。

### A.3 治理运行时接入
- 本仓已纳入 `D:\CODE\governed-ai-coding-runtime` target catalog，`target_repo_id=k12-question-graph`。
- 本项目规则由控制仓 `rules/manifest.json` 管理；目标仓现场修改必须先回写控制仓源文件，再通过同步入口下发。
- 受管治理资产归 `.governed-ai/` 与 `.claude/`；应用代码、README、业务 docs、项目规则和 `tools/` 不应由一键治理盲覆盖。
- `.governed-ai/repo-profile.json` 是机器可读承接点；人工阅读和跨工具项目规则以 `AGENTS.md` 为共同主体。
- 控制仓治理入口：`pwsh -NoProfile -ExecutionPolicy Bypass -File D:\CODE\governed-ai-coding-runtime\scripts\runtime-flow-preset.ps1 -Target k12-question-graph -ApplyGovernanceBaselineOnly -ApplyCodingSpeedProfile -Json`。

## B. Codex 平台差异
- Codex 直接读取本文件；不要假定 Codex 会自动读取 `CLAUDE.md`、`GEMINI.md` 或未配置的 fallback 文件。
- 规则变更后用新 Codex run/session 复核，不假定当前会话热加载。
- 诊断优先：`codex --version`、`codex --help`；加载链可疑时新会话询问已加载规则来源，并记录 `active_rule_path`。
- `AGENTS.md` 是上下文规则；危险命令、权限、沙箱和重复 allowlist 应落到 `.codex/rules/*.rules`、控制仓门禁、hooks 或 CI。

## C. 项目差异
### C.1 门禁命令与顺序
- fixed order：`build -> test -> contract/invariant -> hotspot`。
- build：`dotnet build apps/api/K12QuestionGraph.Api.csproj`
- test：`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gates.ps1`
- contract/invariant：`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`
- hotspot：当前无独立 hotspot 命令；本轮改动必须记录受影响的 API/UI/worker/data/AI/export/analysis 合同与教师效率复核。无法单独执行时按 `gate_na` 写明替代验证和复测条件。

### C.2 快速反馈边界
- quick：`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-c002-dry-run-suite.ps1`
- quick contract：`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`
- 控制仓 daily quick：`pwsh -NoProfile -ExecutionPolicy Bypass -File D:\CODE\governed-ai-coding-runtime\scripts\runtime-flow-preset.ps1 -Target k12-question-graph -FlowMode daily -Mode quick -Json`
- quick 只证明无数据库 C002 dry-run 与 roadmap 依赖一致性；不能替代 `tools/run-gates.ps1` full gate。

### C.3 失败分流与阻断
- `tasks/backlog.csv`、roadmap、task breakdown、README 对 P0/P1 顺序不一致时，先收口事实再编码。
- CSV/JSON/YAML/schema 解析失败必须先修格式或 schema；不得降级为普通 `gate_na`。
- PostgreSQL、YAML parser、CLI 或外部工具缺失可记 `platform_na/gate_na`，但必须给替代验证和复测条件。
- 数据目录、备份恢复、DB migration、权限、外部 AI 调用、真实数据处理和生产 active 切换属于中高风险；先说明回滚路径和验证证据。
- `.governed-ai/repo-profile.json`、`.claude/settings.json` 或 hooks 与控制仓 catalog/baseline 不一致时，先跑控制仓一致性校验并整合漂移，不手工扩大 allowlist。

### C.4 证据与回滚
- 默认证据路径：`docs/evidence/`；治理接入或控制仓同步证据落 `D:\CODE\governed-ai-coding-runtime\docs\change-evidence\`。
- 证据最低字段：规则 ID、风险等级、执行命令、关键输出、兼容性判断、回滚动作。
- 默认回滚优先 Git；数据库/文件/备份/active 切换必须额外记录 snapshot、manifest 或 restore 命令。
- 文档/规则轻量门禁可用 CSV/JSON/YAML parse 与 `rg` 检索；若 `yaml` 模块缺失，不因规则修改安装依赖，按 `gate_na` 给替代读取证据。

### C.5 数据、安全与教师效率
- 数据与程序文件分离；大文件不进数据库，数据库只存 metadata/path/hash/status。
- AI 输出默认 `draft/test/pending_review`；真实外部 AI 自动写入生产、真实学生数据处理、正式统计口径切换必须有人审、可回滚、可追踪。
- 新增功能、字段、页面、AI 调用或外部工具前，必须回答：减少哪一步教师工作、是否增加配置/维护负担、失败后教师如何继续、是否影响成本/隐私/备份/恢复、是否属于 P0/P1 当前 slice。

## D. 维护校验清单
- 仅落地本仓事实，不复述全局规则正文。
- 协同链完整：`规则 -> 落点 -> 命令 -> 证据 -> 回滚`。
- 仅凭全局 + 本项目规则，必须能推出当前落点、目标归宿、门禁顺序、证据路径和回滚入口。
- `Global Rule -> Repo Action`：
  - `R1`: 每轮声明 `当前仓库状态 -> 当前落点 -> 目标归宿 -> 本轮 slice`。
  - `R2`: 使用 backlog 顺序、quick/full gate 和 evidence 小步闭环。
  - `R3`: 动态资产、AI、DB、备份问题先追模型/来源/迁移/同步链；止血补丁写回收点。
  - `R4`: 真实数据、migration、active 切换、权限、备份恢复和外部 AI 自动写入按中高风险处理。
  - `R5`: 不因未来全量题库/多学科/复杂测评扩张当前 v0.1；先交付 teacher-first vertical slice。
  - `R6`: C.1 门禁顺序不可绕过；quick 只能作日常反馈。
  - `R7`: 不破坏现有 schema、migration、backup manifest、C002/C002R 状态语义和教师工作流。
  - `R8`: 每次变更必须留下命令、关键输出、证据路径和回滚动作。
  - `E4`: `tools/run-gates.ps1`、roadmap guard 和控制仓 target-run evidence 承接健康指标。
  - `E5`: NuGet/npm/Python/AI provider/OCR/外部工具变化必须记录供应链和成本/隐私边界。
  - `E6`: domain asset、DB、backup、export template 和 analysis metric 结构变化必须记录迁移、兼容和回滚。
- 本文件属于控制仓 manifest 管理；目标仓现场修改必须回写控制仓源文件后同步。
- 三工具协同约束：`AGENTS.md` 承载共同 A/C/D 项目事实；`CLAUDE.md` / `GEMINI.md` 通过 import 追加 B/D 平台差异，不复制共同正文。
