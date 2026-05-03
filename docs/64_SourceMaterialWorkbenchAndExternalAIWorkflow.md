# 64 · Source Material Workbench and External AI Workflow

## 1. 结论

近十年当地中考真题、考情总结年报、教材、课程标准等 PDF 最终都应进入本项目的来源资料工作台；ChatGPT Web 端可先做初提炼，但输出只能作为 `candidate` 候选数据。

正式激活必须同时具备两条证据链：

```text
外部 AI 初提炼结果 -> candidate CSV -> pending_review
本项目上传原始 PDF -> SourceDocument/FileAsset hash/page/question evidence -> verification
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
1. 在 ChatGPT Web 端上传 PDF 并输出结构化候选 CSV
2. 把候选 CSV 交给本项目导入为 candidate
3. 在本项目来源资料工作台上传同一批原始 PDF
4. 本项目记录 sha256、sourceType、region、year、license、PII、用途许可
5. 用来源页码、题号、章节和 hash 核验 candidate
6. 生成 draft/formal mapping plan 和 migration impact report
7. 高影响或低置信度映射进入人工审核
8. 审核通过后才 reviewed/active
```

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
