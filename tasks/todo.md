# 2015-2025 广州中考物理本机闭环任务清单

- [x] T1 来源 inventory、角色识别、版本化迁移与回滚工具
- [x] T2 数据库/FileStore 备份并迁移 32 份 PDF
- [x] T3 登记真实来源并完成 C003 新旧候选重基线
- [x] T4 逐年解析、页面渲染、切题和来源区域
- [x] T5 答案、解析、题图、表格和公式关联
- [x] T6 知识点、考点、难度和能力标签候选
- [x] T7 审核工作台、API、审计和撤销闭环（本机 repo-side）
  - [x] T7a 2015-2025 队列、题目修订、来源重裁、确认/退回与撤销 API
  - [x] T7b 234 题可逆真实数据库 smoke，最终全部恢复 open/pending_review
  - [x] T7c Web UI/client/API 静态合同与错误继续路径
  - [x] T7d 浏览器实际点击路径：2015 第 1 题、题干/答案来源回看和重复载入 console 复核
- [x] T8 检索、智能组卷、导出、成绩和分析闭环（本机 repo-side reversible smoke）
- [x] T9 浏览器 E2E、桌面/移动视觉审查和错误修复（1280x720、390x844，无横向溢出）
- [x] T10 完整门禁、备份校验、状态守卫和证据收口（2026-07-30 本机 fresh full gate）

当前边界：只推进本机 PostgreSQL/FileStore/API/Worker/Web；隔离机、学校网络、真实教师签字与最终发布继续保持开放。

## 后续专题：课程标准与真题多层证据提炼

- [x] 用户已批准详细实施计划；CEK-33 与 Checkpoint G2 已完成 repo-side 本机浏览器闭环，下一实现项为 CEK-34
  - 设计：`docs/superpowers/specs/2026-07-28-curriculum-exam-knowledge-extraction-design.md`
  - 计划：`docs/superpowers/plans/2026-07-28-curriculum-exam-knowledge-extraction-implementation-plan.md`
  - 清单：`tasks/curriculum-exam-knowledge-extraction-todo.md`
  - 当前：CEK-33 已完成 active/reviewed/candidate、审核与撤销、3 行蓝图到 8 题 draft 题篮、课标/年报原页、学情 fail-closed 和桌面/移动视觉验收；临时 reviewed/题篮数据已恢复，Checkpoint G2 仅按 repo-side 本机浏览器口径关闭。下一步执行 CEK-34 专题 suite、供应链、备份恢复与完整门禁。
  - 入库门禁：2015-2025 共 234 题，234 条题干、234 条答案内容、234 个试卷锚点和 234 个答案锚点均已在 PostgreSQL 候选链中；`questionCorpusReady=true`。
  - 三源门禁：234/234 题具备题级年报锚点，另有 34 个统计页锚点，共 268 个候选 SourceRegion；`reportEvidenceReady=true`、`allFieldExtractionReady=true`。
  - 当前候选：273 个课程要求/分面资产、444 个考查目标、234 个整题主知识映射、133 条课标对齐、444 个考查目标审核项；全部 `candidate/pending_review/productionEligible=false`。
  - 年报候选：210 条原 C003 观察和 24 条 2015 派生观察生成 157 条实测表现、35 条错误摘要、25 条教学建议；37 个 blocked 审核项继续 fail-closed，不补造源年报缺失字段。
  - CEK-19A 数据库：157/35/25 三类候选和 234 个独立审核项已幂等入库，234 题旧难度/状态指纹和 452 个 active 资产均未变化；证据见 `docs/evidence/cek019a-observed-exam-evidence-api-smoke.json`。
  - CEK-20 门禁：8/8 ErrorPattern 测试和完整 full gate 通过；单条/未知/语义不一致拒绝，misconception 禁止自动 apply；证据见 `docs/evidence/cek020-error-pattern-promotion-guard.json`。
  - CEK-21 门禁：profile schema 正负样例、旧 CSV 19 列前缀和新增 10 列兼容投影通过；少于 3 个 trend 可比年份时禁止趋势结论，证据见 `docs/evidence/cek021-regional-exam-profile-contract.json`。
  - CEK-22 门禁：234 个整题主目标聚合为 24 个 schema 合法画像候选，47 个缺分值/实测难度窗口保持 blocked；最近可比 cohort 为 2021-2024 且明确未满五年，active 资产 452 和题目指纹不变，证据见 `docs/evidence/cek022-regional-exam-profile-aggregation.json`。
  - CEK-23 门禁：24 个画像 candidates、1 条 pending migration 和 1 个 open review item 经 dry-run/双 apply 幂等入库；详情 API 和旧 `examPointCandidateId` 查询通过，active 资产与 234 题指纹不变，事务内 rollback key 验证通过，证据见 `docs/evidence/cek023-regional-exam-profile-query-smoke.json`。
  - CEK-24 门禁：只读汇总 297 个课程/画像候选和 94 条映射，六类历史影响均生成 rollback key；active 452 与规划输入快照 hash 不变，CEK-20 未持久化错误模式候选保持 blocked，证据见 `docs/evidence/cek024-curriculum-exam-c002r-plan.json`。
  - CEK-25 门禁：968 个审核对象、14/14 定向测试和真实 API 决策/undo smoke 通过；active/foreign replacement、target change_mapping、active candidate ID 和 active apply 绕过均被拒绝，7 条决策全部撤销，active 452、画像 24、广州 234 题及 target/alignment/mapping 指纹恢复，证据见 `docs/evidence/cek025-curriculum-evidence-review-api.json`。
  - CEK-26 门禁：只读 API probe 确认 92 条复杂映射和 105 个同资产族合法替换目标，`productionEligible=false`；fresh 1440x900、390x844 浏览器实跑确认无页面/面板/审核行溢出，CEK-33 已将移动分组改为五项全可见的 `3 + 2` 布局；空理由阻断、未提交理由保留和改映射候选加载通过，证据见 `docs/evidence/cek026-curriculum-evidence-review-ui.json`。
  - CEK-33 门禁：fresh Browser 实际完成三种搜索生命周期、preview 禁入题篮、真实审核/undo、临时 reviewed 样本、蓝图确认、8 题 draft 题篮、分析 fail-closed 和课标/年报原页回看；临时数据恢复且试卷指纹一致。真实库 `source_cited=0`，未补造原命题依据；证据见 `docs/evidence/cek033-browser-e2e-visual.md`。
  - CEK-27 门禁：隔离库内 297 个资产、444 个目标、133 条对齐和 94 条映射完成 reviewed -> active 后完整回滚，数据库/FileStore/历史指纹恢复，生产 active 保持 452，临时资源已删除；模拟审核不替代真实教师决定，生产为 `NO-GO`，证据见 `docs/evidence/cek027-curriculum-exam-c002r-isolated-drill.json`。
  - CEK-28 门禁：candidate preview 234 题，ability/context/representation/实测难度/profile/requirement/facet 过滤、课标 provenance 和独立估计/实测难度投影通过；旧 2015 `/questions` 查询保持 24/1，数据库指纹不变，证据见 `docs/evidence/cek028-question-evidence-search-api.json`。
  - CEK-29 门禁：全部证据筛选参数类型化并保留 `0`/显式 preview，空白值不发送；卡片分层承载课标、画像、实测/估计难度和审核状态，旧 payload fail-closed；Web 定向 22/22、全量 30/30 及构建通过，证据见 `docs/evidence/cek029-question-evidence-web-contract.json`。
  - CEK-30 门禁：正式/已审核/候选模式单次隔离请求，预览卡 UI/App 双层禁入正式题篮；教师筛选、证据卡片、试卷/答案/课标/年报原页、清空/重试/返回题篮及响应式合同通过，Web 定向 26/26、全量 32/32 和构建通过，证据见 `docs/evidence/cek030-question-evidence-search-ui.json`；浏览器视觉仍由 CEK-33 承接。
