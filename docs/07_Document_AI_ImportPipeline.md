# 07 · 试题导入与 AI 入库流水线

## 1. 目标

把杂乱的 Word/PDF/图片试卷低人工成本地变成结构化题目。规则、脚本和专用 Adapter 默认处理确定性部分；AI 只处理语义候选、复杂映射和异常复核，人工只处理系统标出的异常。

## 2. 总流程

```text
上传文件
→ 文件 hash 去重
→ 文档安全检查
→ 文档优化/压缩/缩略图
→ 文档解析：OpenXML/OMML → PDF text/layout → Docling → PaddleOCR
→ 页面与版面块识别
→ 题号锚点识别
→ 题目边界预测
→ 题干/选项/小问/答案/解析分离
→ 公式/图片/表格/共用材料识别
→ AI 结构化校正
→ 知识点/题型/难度/来源标注
→ 答案解析初步校验
→ 查重与相似题检测
→ 质量信号计算
→ 自动入库 / 人工确认队列
```

## 3. 专用 Adapter 选择顺序

OCR 和公式识别是专用功能，不是 AI agent。导入流水线必须按以下顺序选择最低成本、最高可追溯的工具：

1. `.docx` 优先读取 OpenXML，公式优先保留 OMML/MathML/LaTeX 表示，图片只作为兜底证据。
2. 文本型 PDF 优先抽取原生 text stream、页码、阅读顺序和 layout block；只有无文本或质量不足时才进入 OCR。
3. Docling 用作结构化文档和版面编排层，输出必须转成 `DocumentModel`、`PageModel`、`LayoutBlock`、`SourceRegion` 和 `AdapterDiagnostic`。
4. 扫描版 PDF 和图片默认走本地 PaddleOCR PP-OCRv5 / PP-StructureV3；低置信度进入 `pending_review`，不得伪装成自动通过。
5. 图片公式和扫描公式默认评估 PaddleOCR FormulaRecognition，先用 `PP-FormulaNet_plus-M` 做质量基线，再按 golden set 证据决定是否评估 `PP-FormulaNet_plus-L`。
6. Mathpix、Azure Document Intelligence 等云端服务只允许作为对照或兜底候选；启用前必须有授权、隐私、成本、缓存、失败回滚和人工确认证据。

## 4. 人工低成本预处理

对人容易、对 AI 贵的任务，应提供快捷手动处理：

- 合并跨页题。
- 拖拽题图关联到题目或题组。
- 标记答案解析开始位置。
- 删除水印页/空白页。
- 标记共用材料对应题号。

这些操作应写入用户教程，因为能显著降低 AI token 消耗。

## 5. 置信度策略

| 置信度 | 处理 |
|---:|---|
| ≥ 0.90 | 自动入库 |
| 0.75-0.90 | 自动入库，进入抽检池 |
| 0.60-0.75 | 人工确认 |
| < 0.60 | 不入库，标记失败/需重扫 |

每个环节单独记录：切题、OCR、公式、表格、答案、知识点、难度、查重。

## 6. ReviewQueueItem

字段：

```text
id
item_type: cut/question_image/formula/answer/knowledge/difficulty/table/shared_material
question_id/source_document_id
ai_result_id
confidence
suspected_issue
suggested_action
priority
assigned_to
status
```

## 7. 教师操作按钮

导入确认页应提供：

```text
[确认]
[批量确认]
[合并为一题]
[拆分为两题]
[这张图属于本题]
[这张图属于第 N-M 题]
[标记答案开始]
[标记解析开始]
[跳过此页]
[重跑解析/AI]
```

## 8. 人工修改自动反馈

教师修改任何 AI 结果，程序自动 diff 旧值/新值，生成 FeedbackEvent。教师最多点一个原因标签，不额外填表。

## 9. 失败降级

| 失败 | 降级 |
|---|---|
| AI 不可用 | 手动切题和入库 |
| OCR 失败 | 保留原图，允许手动输入 |
| 公式识别失败 | 保存截图，LaTeX 待补 |
| 图文归属失败 | 拖拽关联 |
| 文档解析失败 | 原始文件存档，人工框选 |
