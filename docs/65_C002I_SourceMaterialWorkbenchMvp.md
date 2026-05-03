# 65 · C002I Source Material Workbench MVP

## 1. 完成范围

C002I 建立来源资料工作台 MVP，用同一底层上传链路管理不同类型资料：

- `textbook`
- `curriculum_standard`
- `local_exam_paper`
- `exam_analysis_report`
- `school_paper`
- `teacher_original`

当前 MVP 只负责上传、metadata、hash、列表和准入边界，不做真实 OCR/AI 提取。

## 2. API 合同

- `POST /files`: 上传来源资料，保存 `FileAsset` 和 `SourceDocument`。
- `GET /source-documents`: 列出来源资料，可按 `sourceType` 和 `materialBatchKey` 过滤。

新增 metadata：

- `region`
- `year`
- `gradeOrScope`
- `editionOrVersion`
- `materialBatchKey`
- `mayUseForKnowledgeExtraction`
- `mayUseForExamPointExtraction`
- `mayUseForTrendAnalysis`

## 3. UI 合同

Web 页面包含 `data-flow="source-material-workbench"`。

入口不是“所有文件混传”，而是同一工作台内按资料类型分组。必需/建议/可选状态在页面上明确呈现，避免教师误以为校本资料必须一开始上传。

## 4. 验证

独立命令：

```powershell
.\tools\run-c002i-source-material-workbench-contract.ps1
```

Full gate：

```powershell
$env:PGPASSWORD='postgres'
.\tools\run-gates.ps1
```

## 5. 生产边界

上传资料只形成来源证据，不自动激活知识点、考点、教材章节或课标条目。ChatGPT Web 输出和本项目上传 PDF 必须交叉核验后，候选资产才能进入 `reviewed/active`。
