# 64 · Source Material Workbench and External AI Workflow

## 1. 结论

近十年当地中考真题、考情总结年报、教材、课程标准等 PDF 必须先进入本项目的来源资料工作台和本地 chunk/cache 链路；外部 AI 只能在来源 hash、页码、chunk、schema、预算和小批量 dry-run guard 之后处理必要片段。ChatGPT Web 端或其他外部 AI 的初提炼输出只能作为 `candidate` 候选数据。

正式激活必须同时具备两条证据链：

```text
本项目上传原始 PDF -> SourceDocument/FileAsset hash/page/chunk evidence -> local cache/budget/eval
外部 AI 初提炼结果 -> candidate CSV -> pending_review
candidate CSV -> source hash/page/question/chunk verification -> review/impact/rollback
```

## 2. 必需与可选资料

| 资料类型 | sourceType | 准入状态 | 用途 |
| --- | --- | --- | --- |
| 教材 | `textbook` | 必需 | 教材章节体系、章节到知识点映射 |
| 课程标准 | `curriculum_standard` | 必需 | 课标条目、能力要求、知识要求 |
| 当地近十年中考真题 | `local_exam_paper` | 必需 | 考点、题型、分值、地区命题口径 |
| 考情总结年报 | `exam_analysis_report` | 强烈建议 | 高频考点、趋势、易错点、权重 |
| 校本资料 | `school_paper` / `teacher_original` | 可选 | 校本重点、教师经验、校本题库 |

不是所有入口都必须填写。最低正式资料集仍是教材、课程标准、当地真题；考情年报用于提高考点和趋势质量；校本资料可以晚些补。

## 3. 工作流

推荐执行顺序：

```text
1. 在本项目来源资料工作台上传原始 PDF
2. 本项目记录 sha256、sourceType、region、year、license、PII、用途许可
3. C002N 本地抽取页级文本、来源锚点、chunk hash、去重和 cache，不调用外部 AI
4. C002O 本地验证结构化输出 schema、golden fixture 和 pending_review 边界
5. C002P 本地验证 L0-L4 模型路由、reasoning 档位、token 预算、cache key 和超预算 fail closed
6. C002Q 只抽样课标、教材、年报、真题的小批 chunk 运行外部 AI dry-run
7. 把外部 AI 输出导入为 candidate，并用来源页码、题号、章节、chunk hash 和 source hash 核验
8. 生成 draft/formal mapping plan 和 migration impact report
9. 高影响或低置信度映射进入人工审核
10. 审核通过、影响确认、回滚快照和 active guard 全部通过后才 reviewed/active
```

不得直接把 33 份 PDF 全量上传给强模型。`gpt-5.5` 只用于少量最高风险、难回滚、影响长期口径的争议裁决，不用于批量格式检查、普通候选提炼或常规 CSV 清洗。

## 4. 项目内存储

真实文件不进 Git。上传后文件进入：

```text
D:\KQG_Data\file_store\
```

后续可按工作台语义展示为：

```text
D:\KQG_Data\source_materials\
```

数据库保存 `SourceDocument` metadata，包括 `sourceType`、`region`、`year`、`gradeOrScope`、`editionOrVersion`、`materialBatchKey`、授权、PII 和三类用途许可。

## 5. 候选数据模板

项目提供以下可提交空模板：

- `configs/knowledge/c002-formal-knowledge-template.csv`
- `configs/knowledge/c002-exam-point-template.csv`
- `configs/knowledge/c002-textbook-chapter-template.csv`
- `configs/knowledge/c002-curriculum-standard-template.csv`
- `configs/knowledge/c002-asset-mapping-template.csv`
- `configs/knowledge/c002-external-ai-candidate-template.csv`

外部 AI 输出必须至少带 `source_files/source_type/region/year/page_or_location/question_number/evidence_summary/confidence`，否则不能进入正式审核。

## 6. 变化兼容

新增资料类型、教材版本、地区考试口径或年度报告时，不覆盖旧体系；应新增 source material batch，生成候选动态资产、映射计划、影响报告和回滚快照。

旧试卷、旧学情报告继续指向旧版本；新组卷和新分析使用当前 reviewed/active 版本。
