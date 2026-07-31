# 课程标准与中考真题多层证据提炼任务清单

- 状态：CEK-01..35 本机 repo-side 专题已收口；真实教师签字、身份授权、学校网络、隔离机、生产激活和 `REAL005` 仍开放
- 设计：`docs/superpowers/specs/2026-07-28-curriculum-exam-knowledge-extraction-design.md`
- 详细计划：`docs/superpowers/plans/2026-07-28-curriculum-exam-knowledge-extraction-implementation-plan.md`
- 范围：初中物理、2022 年版 2025 年修订课标、广州 2015-2025 真题/答案/年报

本清单是现有 `tasks/plan.md` 的下级专题清单，不替代 T7d-T10、`tasks/backlog.csv` 或 P001 -> P006 live-pilot 顺序。

## Phase A：来源 inventory、迁移与准入

- [x] CEK-01 课程标准来源 inventory 与可逆迁移工具
- [x] CEK-02 执行版本目录迁移并更新本地 manifest
- [x] CEK-03 来源准入和 SourceDocument 幂等登记
- [x] Checkpoint A：来源可追溯，C002 active 指纹不变

## Phase B：课程要求、要求分面与知识映射

- [x] CEK-04 EvidenceAnchor 存储合同与 SourceRegion metadata
- [x] CEK-05 CurriculumRequirement / RequirementFacet schema 与模板
- [x] CEK-06 OCR 课程标准层级与页码提取
- [x] Checkpoint B1：课标结构可靠，无无证据条目
- [x] CEK-07 要求分面候选与 AI schema/eval
- [x] CEK-08 课程要求到知识节点的候选 crosswalk
- [x] CEK-09 课程要求/分面 candidate 持久化与查询 smoke
- [x] Checkpoint B2：课标候选进入治理链，无 active 写入

## Phase C：题目范围、考查目标与三源对齐

- [x] CEK-09A 2015-2025 真题候选全量入库就绪门禁
  - 结果：234/234 题、题干、答案内容、试卷锚点和答案锚点齐全；`questionCorpusReady=true`。
  - 结果：题级年报锚点 234/234；`reportEvidenceReady=true`、`allFieldExtractionReady=true`，共物化 268 个年报候选 SourceRegion。
  - 边界：2015 的 24 个题级区域由题号标题与题干相似度定位，仍须教师审核。
- [x] CEK-10 整题/小问/评分点范围正规化
- [x] CEK-11 AssessmentTarget 与 CurriculumAlignment schema
- [x] CEK-12 广州试卷/答案/年报证据索引
- [x] Checkpoint C1：题目/答案范围成立，题级年报证据缺口显式 fail-closed
- [x] CEK-13 三源对齐、课标制度窗口与冲突报告
- [x] CEK-14 AssessmentTarget 候选提炼与 eval
- [x] CEK-15 AssessmentTarget、知识角色与课标对齐持久化
- [x] Checkpoint C2：考查目标合同可持久化，旧 API 兼容
- [x] CEK-16 考查目标幂等导入、只读 API 与审核队列
  - 边界：444 条考查目标、234 条整题主知识映射、133 条课标对齐和 444 个审核项仍全部为 candidate/pending_review，未 active。

## Phase D：实测表现、错误证据与教学建议

- [x] CEK-17 年报实测/错误/建议 schema 合同
  - 证据：`docs/evidence/cek017-observed-exam-evidence-contract.json`
  - 结果：ObservedPerformanceEvidence、ObservedErrorEvidence、TeachingRecommendation 三类 schema 正负样例通过；实测难度固定 `higher_is_easier`，缺失值保持 `null`。
- [x] CEK-18 广州年报实测与解释证据提取
  - 证据：`docs/evidence/cek018-guangzhou-year-report-evidence.json`
  - 结果：11 份 PDF、210 条原 C003 观察和 24 条 2015 派生观察生成 157 条 performance、35 条 error、25 条 recommendation candidate；342 个统计指标锚点均有真实 SourceRegion。
  - 边界：37 个 blocked 审核项对应源年报字段不足或解析异常，保持缺失/待审，不补造。
- [x] Checkpoint D1：目标与年报候选分层成立，难度来源不混用
  - 边界：全部候选仍为 `pending_review/productionEligible=false`；CEK-20 的 ErrorPattern 仅为未持久化内存候选，未审核、未提升为 active misconception。
- [x] CEK-19 实测表现、错误证据和教学建议持久化结构
  - 证据：`docs/evidence/cek019-observed-evidence-migration.json`
  - 结果：三张候选安全证据表已迁移到本机 PostgreSQL，26 个 CHECK（含 4 个 schema 跨字段门禁）、6 个 FK、5 个 JSONB 列生效。
- [x] CEK-19A 年报候选幂等导入与只读 API
  - 证据：`docs/evidence/cek019a-observed-exam-evidence-api-smoke.json`
  - 结果：157/35/25 三类候选和 234 个审核项已入库；连续 apply 幂等、API 全量/目标过滤通过，234 题旧字段指纹与 452 个 active 资产不变。
- [x] CEK-20 ErrorPattern 归一化与 misconception 提升门禁
  - 证据：`docs/evidence/cek020-error-pattern-promotion-guard.json`
  - 结果：8 类受控 taxonomy、8/8 API 合同测试；同年跨题或同题跨年且语义代码一致时生成 `error_pattern` DomainAssetVersion candidate，并保存证据/题目/年份计数、target IDs、normalization method 和 reviewer status。
  - 边界：单条、单题单年重复、未知代码和语义不一致均 fail-closed；misconception 只生成 `pending_review` 提升决定，必须人工审核、C002R impact report 和 rollback snapshot，未写数据库或 active KnowledgeNode。
- [x] CEK-21 RegionalExamPointProfile schema 与旧 exam_point 兼容
  - 证据：`docs/evidence/cek021-regional-exam-profile-contract.json`
  - 结果：canonical semantic type 固定为 `RegionalExamPointProfile`，存储/API asset type 继续使用 `exam_point`；frequency/score/difficulty/trend 均要求分母、可比年份和 evidence target IDs。
  - 边界：旧 CSV 前 19 列原序保留；少于 3 个 trend 可比年份时只能是 `insufficient_evidence`，未聚合、入库、审核或激活任何画像。
- [x] Checkpoint D2：年报持久化、错误与画像语义锁定

## Phase E：地区考查画像与 C002R 影响

- [x] CEK-22 多年画像聚合与可比性门禁
  - 证据：`docs/evidence/cek022-regional-exam-profile-aggregation.json`
  - 结果：234 个整题主目标和 157 条实测表现进入只读聚合，生成 24 个 schema 合法画像候选（完整 2015-2025 窗口 14 个、最近可比窗口 10 个）；能力、认知、题型、情境、表征、知识共现、分值权重和实测难度分布均保留分母与 target IDs。
  - 边界：最近同分值/同课标制度 cohort 只有 2021-2024 四年，明确 `recentComparableComplete=false`；47 个主题窗口因题分值或实测难度不足 fail-closed，完整跨制度窗口的 14 个趋势全部为 `insufficient_evidence`。
  - 安全：11 份原卷 SHA-256 与总分来源复核通过，active 资产保持 452，234 题旧字段指纹前后一致；未写数据库或 active。
- [x] CEK-23 画像 candidate 导入与兼容查询
  - 证据：`docs/evidence/cek023-regional-exam-profile-query-smoke.json`
  - 结果：使用 fresh verified backup `D:\KQG_Backups\20260730-223504\manifest.json`，dry-run 无写入、连续两次 apply 幂等；24 个 `exam_point` profile candidates、1 条 pending migration 和 1 个 open review item 已入库。
  - 查询：新 profile detail API 返回时间窗口、频率/分值分母、难度分布、课标制度和 evidence target IDs；旧 `examPointCandidateId=EPHY-C003-001` 过滤仍返回原 1 题。
  - 安全：全部保持 `candidate/pending_review/productionEligible=false`，active 资产保持 452，234 题完整字段指纹不变；按 import key 的删除条件在事务内删至 0 后已 rollback，最终候选仍保留。
- [x] CEK-24 真实 C002R 修订计划与影响报告
  - 证据：`docs/evidence/cek024-curriculum-exam-c002r-plan.json`
  - 结果：基于 452 个 active C002 资产，只读汇总 273 个课程候选、24 个画像候选和 94 条真实 pending mappings；生成 92 条复杂映射、40 条低置信度映射、24 个画像及 5 类高影响审核组。
  - 影响：题目绑定、组卷蓝图、检索索引、历史分析、导出和成绩模板六类影响均有独立 rollback key；历史题单/分析/导出只保留版本或冻结快照，禁止静默重写。
  - 边界：CEK-20 只有 promotion contract、没有持久化 error-pattern candidates，已明确标记 `blocked_no_persisted_candidates`；计划只读，未写 migration、candidate 或 active。
- [x] Checkpoint E：画像进入 C002R，active/历史指纹不变
  - CEK-22..24 证据通过；24 个画像进入 C002R candidate plan，active C002 保持 452，生成前后数据库快照 hash 一致。
  - review groups、六类 snapshot requirements 和 rollback keys 已生成；所有候选仍待教师审核。

## Phase F：审核与隔离激活演练

- [x] CEK-25 多层证据审核 API 与决策审计
  - 证据：`docs/evidence/cek025-curriculum-evidence-review-api.json`
  - 结果：分页汇总 968 个候选审核对象（课标要求 273、考查目标 444、复杂映射 92、地区画像 24，错误模式 0 且保持 blocked）；批准/退回/保持待审、低风险批量批准、映射修订、审计、陈旧 undo 拒绝和逆序恢复均通过，14/14 定向测试通过。
  - 安全：active candidate ID、active/外来 replacement、target `change_mapping` 和普通教师 active apply 均 fail-closed；7 个 smoke decisions 全部 undo，active 452、画像 24、广州 234 题及 target/alignment/mapping 指纹恢复。
  - 边界：`reviewer/actorRole` 仍是本地请求审计字段，不证明真实认证授权；CEK-20 错误模式持久化、教师审核、C002R active switch 和 `REAL005` 仍开放。
- [x] CEK-26 教师证据审核 UI
  - 证据：`docs/evidence/cek026-curriculum-evidence-review-ui.json`
  - 结果：五类审核队列、分页、刷新、理由必填、approve/return/change mapping/keep pending/undo、主次知识、估计/实测难度分层和三类证据原页链接已接入现有管理面板；Web 5 文件 30/30、API 全量 58/58、定向 21/21 及 Web/API build 通过。
  - 只读实测：复杂映射 92 条，首个复杂映射返回 105 个同资产族合法替换目标，`productionEligible=false`；普通教师面板不暴露 storage path、hash、migration key、模型路由或 active switch。
  - 浏览器：fresh 1440x900、390x844 实跑确认整页/面板/审核行无横向溢出；CEK-33 后续把移动审核分组改为五项全部可见的 `3 + 2` 布局。空理由阻断、刷新后未提交理由保留和合法改映射候选加载通过，控制台 0 error。
  - 边界：未提交真实审核决定，未执行 active apply 或 C002 切换；身份认证/授权仍未由 `reviewer/actorRole` 证明，CEK-33 继续负责跨审核、检索、组卷和分析的完整浏览器 E2E。
- [x] CEK-27 隔离库 reviewed -> active -> rollback 演练与生产决策包
  - 证据：`docs/evidence/cek027-curriculum-exam-c002r-isolated-drill.json`
  - 结果：已验证备份克隆到唯一临时 DB/FileStore；模拟审核后 297 个修订资产、444 个目标、133 条对齐、94 条映射和 2 条 migration 完成 reviewed -> active，历史消费者指纹未变化，显式 snapshot rollback 后数据库/FileStore parity 均为 true。
  - 清理：生产 active 保持 452，修订数据全部恢复 candidate/pending；生产指纹前后一致，临时数据库和目录均已删除。C002S 30 个样本/210 个质量项正式化前审查通过，K004 历史版本解释合同通过。
  - 决策：生产 `NO-GO`；`drill_reviewer` 不等于真实教师审核。CEK-33/34 后续已通过，但身份授权、CEK-20 持久化、`REAL005` 和生产切换明确授权仍开放。
- [ ] Checkpoint F：审核与回滚可证明，生产 active 未切换
  - repo-side 隔离回滚已证明，但真实教师对 968 个审核对象的决定和身份授权未完成，故保持开放。

## Phase G：教师检索、组卷、分析与浏览器验收

- [x] CEK-28 多层证据题库搜索 API
  - 证据：`docs/evidence/cek028-question-evidence-search-api.json`
  - 结果：新增独立只读证据搜索端点；默认 active、candidate/reviewed 显式 preview、全部证据筛选、分页、课标 provenance、考查目标、地区画像和两类难度投影通过，candidate preview 当前返回 234 题。
  - 兼容与安全：旧 `/questions` 2015 查询仍为 24/1；candidate/reviewed 未显式预览和倒置难度区间均返回 400，数据库指纹不变，candidate 永远 `productionEligible=false`。API 全量 68/68、定向 10/10 和独立 smoke 通过。
- [x] CEK-29 Web 搜索 contract 与 client
  - 证据：`docs/evidence/cek029-question-evidence-web-contract.json`
  - 结果：新增证据搜索参数/响应类型、递归 normalizer、client 和独立 query key/hook；空白筛选省略、`0` 值与显式 preview 标志保留，课标/画像/实测与估计难度/review status 分层不混用。
  - 兼容与安全：旧/缺字段 payload 使用 `unknown/pending_review/productionEligible=false` 默认值且忽略未知字段；定向 22/22、Web 全量 30/30 和生产构建通过，尚未接入 CEK-30 UI。
- [x] CEK-30 教师搜索筛选和证据卡片
  - 证据：`docs/evidence/cek030-question-evidence-search-ui.json`
  - 结果：正式/已审核/候选分段模式、教师筛选菜单、课标/考查目标/广州画像/实测与估计难度卡片、试卷/答案/课标/年报原页入口及加载/空/错状态已接入找题组卷工作台。
  - 安全与验证：预览结果在 UI/App 两层禁入正式题篮；清空、重试、返回题篮路径齐全，定向 26/26、Web 全量 32/32 和构建通过，CEK-33 浏览器视觉验收仍开放。
- [x] Checkpoint G1：教师检索闭环（repo-side；浏览器实际交互仍由 CEK-33 承接）
- [x] CEK-31 组卷蓝图接入考查目标与历史版本解释
  - 证据：`docs/evidence/cek031-paper-evidence-constraint-smoke.json`
  - 结果：旧 `POST /paper-blueprints` 请求保持兼容；可选证据约束覆盖知识、课标要求、能力/认知、方法/实验、情境和地区画像，并冻结匹配题目、约束解释、缺口和版本引用。
  - 安全与验证：candidate/reviewed 仅显式预览且不能确认成正式题篮；active 不足返回 shortage，不自动放宽。fresh smoke 精确清理临时 review，paper 三表指纹恢复一致；隔离 Release build、API 71/71、定向 3/3、K004/S009C 和两项 guard 通过。`NU1903` 供应链风险及真实教师/生产门禁仍开放。
- [x] CEK-32 学情分析接入考查目标、能力和错误模式
  - 证据：`docs/evidence/cek032-score-evidence-analysis-smoke.json`
  - 结果：只读 preview API 与 Web 分析面板已区分成绩推导表现、知识/能力认知、历史年报背景、相关错因、来源作者建议和教师确认诊断；旧静态摘要不再冒充真实分析。
  - 安全与验证：PII、缺 target、未审核 target 和知识版本歧义 fail-closed，不写正式历史；fresh smoke 指纹一致，live 5290 返回新合同。隔离 Release build、API 77/77、定向 3/3、Web 34/34、lint/build、F003/I005 和两项 guard 通过。`NU1903` 与真实教师诊断/生产门禁仍开放。
- [x] CEK-33 浏览器 E2E、视觉与证据可回看验收
  - 证据：`docs/evidence/cek033-browser-e2e-visual.md` 及 7 张桌面/移动/原页 PNG。
  - 结果：active/reviewed/candidate 三模式、preview 禁入题篮、3 行蓝图到 8 题 draft 题篮、课标/年报原页和成绩分析 fail-closed 均由 fresh Browser 实际点击；临时 reviewed 样本和题篮均撤销/精确清理，试卷三表指纹恢复。
  - 审核：原页证据 target、retrospective alignment、高影响冲突及临时 reviewed 样本均完成决定和 undo，审计为 `dismissed`、候选恢复 `pending_review/productionEligible=false`。真实库无 `source_cited` alignment（128 retrospective、5 contemporaneous），未伪造原命题依据，精确分支由既有 UI contract fixture 覆盖。
  - 视觉与验证：移动审核分组修复为 `3 + 2`，桌面/移动无页面横向溢出或控件重叠，fresh 控制台 0 error/warn；Web 36/36、lint/build、CEK-26/30 UI contract 和 7 张截图非空像素检查通过。
- [x] Checkpoint G2：教师工作流可用（repo-side 本机浏览器），但不代替真实教师签字、身份授权、学校网络或隔离机现场验收

## Phase H：门禁、恢复与状态收口

- [x] CEK-34 专题 suite、供应链、备份恢复与完整门禁
  - 当前证据：`docs/evidence/cek034-curriculum-exam-knowledge-evidence-suite.json` 为 `status=pass/cek34Complete=true/fullGateAuthorized=true`。
  - 已通过：API/Web build，API 78/78、Worker 182/182、Web 38/38、lint，完整 `tools/run-gates.ps1`，10 个 JSON contract、19 个 CEK evidence 引用、roadmap/reference guards；NuGet API/Test 与 npm production 漏洞均为 0。
  - 恢复/迁移：从 `D:\KQG_Backups\20260730-232646\manifest.json` 恢复唯一临时库和 4,571 个 FileStore 文件（395,953,878 bytes），SHA-256 全部一致；CEK-15/19 Down/Up 到正确 head，生产 452/0/0/444 边界计数前后一致，临时库/目录均已删除。
  - 供应链：显式覆盖 `Microsoft.OpenApi 2.7.5` 修复 `GHSA-v5pm-xwqc-g5wc`；MIT、Windows build/test、离线 NuGet cache 与回滚入口已记录。
  - 完整门禁：本轮已获明确授权并从头执行，`repository-full-gate=pass`；生产边界前后均为 452/0/0/444，未发生 active write。
- [x] CEK-35 状态文档、任务真值与完成边界收口
  - 已同步 README、roadmap、task breakdown、control board、专题计划和任务入口；本专题完成不等于生产激活、教师验收或项目发布。
- [x] Final Checkpoint：CEK-01..35 的本机 repo-side 验收、验证、证据和回滚全部满足

## 持续边界

- 所有自动提炼结果保持 `candidate/pending_review/productionEligible=false`，直至正式审核门禁通过。
- CEK-27 只在隔离环境做 active/rollback 演练；生产切换另需明确授权。
- 后续重跑 CEK-34 `tools/run-gates.ps1` 前仍须重新确认 PostgreSQL/API 进程影响。
- `REAL005=not_closed`、release No-Go 和 onsite/manual 待办不因本专题 repo-side 通过而关闭。
