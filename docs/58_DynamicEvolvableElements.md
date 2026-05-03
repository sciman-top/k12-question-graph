# 58 · Dynamic Evolvable Elements

## 1. 结论

必须提前写清楚。凡是未来可能因学科、地区、年份、教材、考试口径、教师习惯、模型能力、学校政策或法规变化而改变的参数、数据、标签、模板和规则，都不能只做静态常量。它们必须有版本、状态、来源、映射、迁移、审核和回滚。

这不是过度设计。K12 场景里，变化本身就是核心需求。系统要稳定的是契约和迁移机制，不是某一版知识点、某一套标签或某一个 prompt 永远不变。

## 2. 必须动态化的对象

| 类别 | 对象 | 典型变化 | 需要联动更新的对象 |
|---|---|---|---|
| 知识体系 | 知识点、知识边、能力维度、方法、易错点 | 课标、教材、地区命题、校本教研变化 | 题目绑定、检索索引、组卷约束、学情指标、eval fixture |
| 教材课标考点 | 教材版本、章节、课程标准、地区考点 | 改版、政策调整、地区考试口径变化 | 知识点映射、教学进度、组卷细目表 |
| 题目属性 | 题型、标签、难度、分值、rubric、评分细则 | 学科差异、教师习惯、考试结构变化 | 题目卡片、筛选、导出、成绩分析 |
| 导入解析 | OCR/adapter、切题策略、解析 pipeline、错误分类 | 工具升级、资料格式变化 | ImportJob、ReviewQueue、SourceRegion、golden samples |
| AI 策略 | prompt、schema、model routing、成本策略、eval 集 | 模型升级、价格变化、schema 调整 | AIJob、AIResult、ReviewQueue、FeedbackEvent |
| 组卷导出 | 组卷规则、细目表、模板、版式偏好 | 学校模板、考试要求、教师偏好变化 | Paper、PaperSection、导出文件、换题约束 |
| 成绩学情 | Excel 字段映射、小题结构、分析指标、分层规则 | 模板变化、考试结构变化、教研口径变化 | ScoreRecord、ItemScore、AnalysisReport、历史报告冻结 |
| 组织权限 | 学校、年级、班级、教研组、共享范围、角色 | 组织调整、权限政策变化 | SourceDocument、题库共享、审计日志、备份恢复 |
| 安全合规 | 隐私、保留、脱敏、外部 AI 传输边界 | 法规、校规、部署环境变化 | AI 调用、日志、备份、导出、删除策略 |
| 互操作 | QTI/CASE/OneRoster/Caliper 映射 | 标准升级、第三方系统字段差异 | 导入导出 adapter、外部 ID 映射 |

## 3. 映射基数

系统必须支持以下映射基数：

| 基数 | 示例 | 自动化策略 |
|---|---|---|
| one_to_one | 知识点改名、标签别名归一 | 高置信度、低影响、可回滚时可自动应用 |
| one_to_many | 旧知识点拆成多个新知识点 | 进入人工审核，生成影响报告 |
| many_to_one | 多个旧标签合并为一个新标签 | 进入人工审核，检查统计口径变化 |
| many_to_many | 旧能力维度和知识点边界同时重组 | 必须人工审核，不允许静默自动迁移 |

`DomainAssetMapping` 的一条记录只表达一条 source-target 边。复杂基数通过同一 migration/plan 下的多条边组合表达。这样既能保持数据库结构简单，也能完整表达多对多迁移集合。

## 4. 自动替换边界

规则和 AI 可以先生成建议，减少人工维护工作，但不能把所有变更都自动写入生产事实。

允许自动应用：

- one_to_one。
- 高置信度。
- 低影响。
- 可回滚。
- 不改变历史学情口径、正式组卷规则或校级统计。

必须人工审核：

- one_to_many、many_to_one、many_to_many。
- 低置信度或证据不足。
- 影响历史成绩、学情报告、组卷约束、评分标准、共享权限或隐私策略。
- 涉及正式 `active` 资产激活。

## 5. 写入项目计划的要求

后续每个新增功能都要回答：

- 它是否属于动态变化对象。
- 是否需要 `version/status/source/effective_scope`。
- 是否需要映射到其他资产。
- 可能出现哪些映射基数。
- 哪些变化可自动应用，哪些必须人工审核。
- 变更后要自动更新哪些依赖对象。
- 历史数据是迁移、冻结、重算还是保留旧版本解释。
- 回滚入口和影响报告在哪里。

如果某个功能暂时用静态配置或 enum 起步，任务验收必须写明迁移归宿和过期条件，不能默认永久写死。

## 6. 回滚

```powershell
git restore --source=HEAD -- docs/00_ProjectConstitution.md docs/01_PRD.md docs/05_DomainModel.md docs/19_Roadmap.md docs/20_TaskBreakdown.md docs/51_C002A_DomainAssetVersioning.md tasks/backlog.csv
git clean -f -- docs/58_DynamicEvolvableElements.md
```
