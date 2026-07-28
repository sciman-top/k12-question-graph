# 课程标准与中考真题多层证据提炼任务清单

- 状态：实施中；CEK-01..07 与 Checkpoint B1 已完成，CEK-08 待执行
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
- [ ] CEK-08 课程要求到知识节点的候选 crosswalk
- [ ] CEK-09 课程要求/分面 candidate 持久化与查询 smoke
- [ ] Checkpoint B2：课标候选进入治理链，无 active 写入

## Phase C：题目范围、考查目标与三源对齐

- [ ] CEK-10 整题/小问/评分点范围正规化
- [ ] CEK-11 AssessmentTarget 与 CurriculumAlignment schema
- [ ] CEK-12 广州试卷/答案/年报证据索引
- [ ] Checkpoint C1：题目证据范围成立
- [ ] CEK-13 三源对齐、课标制度窗口与冲突报告
- [ ] CEK-14 AssessmentTarget 候选提炼与 eval
- [ ] CEK-15 AssessmentTarget、知识角色与课标对齐持久化
- [ ] Checkpoint C2：考查目标合同可持久化，旧 API 兼容
- [ ] CEK-16 考查目标幂等导入、只读 API 与审核队列

## Phase D：实测表现、错误证据与教学建议

- [ ] CEK-17 年报实测/错误/建议 schema 合同
- [ ] CEK-18 广州年报实测与解释证据提取
- [ ] Checkpoint D1：目标与年报候选分层成立，难度来源不混用
- [ ] CEK-19 实测表现、错误证据和教学建议持久化
- [ ] CEK-20 ErrorPattern 归一化与 misconception 提升门禁
- [ ] CEK-21 RegionalExamPointProfile schema 与旧 exam_point 兼容
- [ ] Checkpoint D2：年报持久化、错误与画像语义锁定

## Phase E：地区考查画像与 C002R 影响

- [ ] CEK-22 多年画像聚合与可比性门禁
- [ ] CEK-23 画像 candidate 导入与兼容查询
- [ ] CEK-24 真实 C002R 修订计划与影响报告
- [ ] Checkpoint E：画像进入 C002R，active/历史指纹不变

## Phase F：审核与隔离激活演练

- [ ] CEK-25 多层证据审核 API 与决策审计
- [ ] CEK-26 教师证据审核 UI
- [ ] CEK-27 隔离库 reviewed -> active -> rollback 演练与生产决策包
- [ ] Checkpoint F：审核与回滚可证明，生产 active 未切换

## Phase G：教师检索、组卷、分析与浏览器验收

- [ ] CEK-28 多层证据题库搜索 API
- [ ] CEK-29 Web 搜索 contract 与 client
- [ ] CEK-30 教师搜索筛选和证据卡片
- [ ] Checkpoint G1：教师检索闭环
- [ ] CEK-31 组卷蓝图接入考查目标与历史版本解释
- [ ] CEK-32 学情分析接入考查目标、能力和错误模式
- [ ] CEK-33 浏览器 E2E、视觉与证据可回看验收
- [ ] Checkpoint G2：教师工作流可用，但不代替现场验收

## Phase H：门禁、恢复与状态收口

- [ ] CEK-34 专题 suite、供应链、备份恢复与完整门禁
- [ ] CEK-35 状态文档、任务真值与完成边界收口
- [ ] Final Checkpoint：CEK-01..35 的验收、验证、证据和回滚全部满足

## 持续边界

- 所有自动提炼结果保持 `candidate/pending_review/productionEligible=false`，直至正式审核门禁通过。
- CEK-27 只在隔离环境做 active/rollback 演练；生产切换另需明确授权。
- CEK-34 运行 `tools/run-gates.ps1` 前重新确认 PostgreSQL/API 进程影响。
- `REAL005=not_closed`、release No-Go 和 onsite/manual 待办不因本专题 repo-side 通过而关闭。
