# 05 · 领域模型设计

## 1. 核心原则

试题不是 Word 片段。试题是结构化数据 + 多模态素材 + 原始来源证据 + 可导出内容。

## 2. 核心实体

```text
QuestionItem             试题
QuestionBlock            题目内容块：文本、公式、图片、表格、图表
QuestionOption           选项
SubQuestion              小问
QuestionAnswer           答案
QuestionSolution         解析
Rubric                   评分标准
QuestionAsset            图片/公式/表格/音频/附件
SharedMaterial           共用题图/共用材料/阅读材料
SourceDocument           原始文档
SourceRegion             原始页码、区域坐标、截图
KnowledgeNode            知识点本体节点
KnowledgeEdge            知识点关系
KnowledgeMapping         试题/教材/课标/考点与知识点映射
Paper                    试卷
PaperSection             大题
PaperQuestion            试卷中的题目实例
Exam                     考试/测验记录
Student                  学生
ClassGroup               班级
ScoreRecord              总分记录
ItemScore                小题分记录
AnalysisReport           学情报告
AIJob                    AI 任务
AIResult                 AI 结果
ReviewQueueItem          人工确认项
FeedbackEvent            教师修改反馈事件
FileAsset                文件资产
BackupJob                备份任务
TeacherPreference        教师偏好
DomainAssetVersion       动态领域资产版本
DomainAssetMapping       资产替换/拆分/合并/废弃映射
DomainAssetMigration     资产迁移任务与影响报告
```

## 3. QuestionItem 字段草案

| 字段 | 说明 |
|---|---|
| id | 稳定 ID |
| subject | 学科 |
| stage | 学段 |
| grade | 年级 |
| question_type | 题型 |
| default_score | 默认分值 |
| difficulty_estimated | AI/教师预估难度 |
| difficulty_observed | 多次考试实测难度汇总 |
| source_type | 真题/模拟/校本/练习/未知 |
| status | 草稿/待确认/可用/推荐/需优化/暂停/弃用 |
| primary_knowledge_id | 主知识点 |
| blocks | 多模态内容块 JSON |
| custom_fields | JSONB 自定义字段 |
| quality_signals | 技术/测量/教学质量信号 |
| created_by | 创建人 |
| created_at | 创建时间 |
| updated_at | 更新时间 |

## 4. 多模态内容块

```json
{
  "type": "text | formula | image | table | chart | blank | group_ref",
  "order": 1,
  "content": "...",
  "asset_id": "...",
  "latex": "...",
  "omml_id": "...",
  "source_region_id": "...",
  "confidence": 0.93
}
```

## 5. 题图与共用材料

几道题共用题图时，不把图片复制给每道题，而是创建 SharedMaterial：

```text
SharedMaterial
├── material_type: image / table / passage / experiment_setup
├── source_page
├── bounding_box
├── asset_id
└── linked_questions: [Q12, Q13, Q14]
```

## 6. SourceDocument 来源与授权字段

题库原始资料可能有版权、传播和隐私边界。P1 起 SourceDocument 至少记录：

| 字段 | 说明 |
|---|---|
| source_type | 教师原创/校本试卷/真题/教材/网络/商业资料/未知 |
| source_title | 原始资料标题或可读名称 |
| owner_scope | personal/school/department/public/unknown |
| license_or_permission | 授权、购买、公开来源或未知 |
| sharing_allowed | 是否允许校级共享或导出传播 |
| contains_student_pii | 是否含学生姓名、学号、成绩等 |
| anonymization_status | none/anonymized/synthetic/not_applicable |
| retention_class | formal/ordinary/temporary/archive |
| evidence_file_asset_id | 原文件或授权证明引用 |

未知来源默认只能个人使用，不进入校级共享和公开导出。

## 7. 自定义字段

自定义字段使用定义表 + JSONB 值：

```text
CustomFieldDefinition
- field_key
- display_name
- scope: system/school/subject/personal
- field_type: single_select/multi_select/rating/boolean/number/text/ref
- allowed_values
- searchable
- analyzable
- required
- version
```

不要让用户直接改数据库字段。

## 8. 标签治理

标签分为：系统标签、学校标签、学科标签、个人标签。个人标签默认不进入校级统计。标签修改支持新增、改名、合并、停用、迁移、别名、版本化。

## 9. 动态领域资产

凡是会随学科、地区、年份、教材、课程标准、考试口径、教师习惯、AI 模型或学校政策变化的对象，都不能只做静态 enum 或散乱字符串。至少包括：

- 知识点本体、知识边和知识映射。
- 教材版本、章节目录、课程标准节点、地区考点。
- 题型体系、难度层级、能力维度、标签体系、自定义字段。
- 答案、解析、rubric、评分细则。
- 组卷规则、细目表模板、导出模板。
- AI prompt/schema/model routing policy。
- 文档解析 pipeline、adapter 配置、分析指标、隐私和保留策略。

动态领域资产必须记录：

| 字段 | 说明 |
|---|---|
| asset_type | knowledge_node/tag/question_type/rubric/assembly_policy 等 |
| stable_id | 跨版本稳定标识 |
| version | 资产版本 |
| status | draft/candidate/reviewed/active/deprecated/merged/superseded |
| authority | bootstrap/source_derived/school_approved/policy |
| effective_scope | 学科、学段、地区、学校、班级或时间范围 |
| source_evidence | 来源文档、页码、hash、审核记录或 policy 文件 |
| replacement_mapping | 等价、拆分、合并、上位/下位、废弃、重命名 |
| confidence | 规则/AI/人工映射置信度 |
| review_status | auto_applied/pending_review/approved/rejected |
| migration_report_id | 影响数量、自动更新项、需人工确认项和回滚入口 |

规则和 AI 可以先做自动匹配、替换和迁移建议，目标是减少教师维护工作。自动化只能处理高置信度、低影响、可回滚的变更；影响历史成绩、正式组卷、校级统计或一拆多/多合一的变更必须保留人工审核。
