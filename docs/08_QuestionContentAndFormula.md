# 08 · 试题文本、公式、图片、表格处理

## 1. 多模态块模型

一道题由多个内容块组成：文本、公式、图片、表格、图表、共用材料引用。不要保存成一个长字符串。

```text
QuestionItem
├── StemBlocks
├── Options
├── SubQuestions
├── Answer
├── Solution
├── Rubric
├── Assets
└── SourceRegions
```

## 2. 公式四层模型

```text
FormulaObject
├── latex_source        内部主格式
├── omml_docx           Word/docx 原生公式
├── svg_or_html         Web 显示
├── png_fallback        WPS/兼容性兜底
└── original_crop       原始公式截图
```

## 3. 公式策略

| 场景 | 格式 |
|---|---|
| 数据库存储 | LaTeX |
| 浏览器显示 | KaTeX 优先，MathJax 兜底 |
| Word/docx 导出 | OMML |
| PDF 导出 | HTML/SVG/PDF 渲染 |
| WPS 兼容 | OMML + 高清图片兜底 |

自动转换可以做，但不能假设 100% 无损。转换失败时使用截图兜底并标记。

## 4. 图片与表格

每个素材保存：

```text
asset_id
asset_type: image/formula/table/chart/shared_material
original_file_id
optimized_file_id
thumbnail_file_id
source_page
bounding_box
linked_question_ids
ocr_text
confidence
```

## 5. 共用题图

共用题图通过 SharedMaterial 与多题关联，不复制素材。

## 6. 质量检查

导入和导出前检查：

- 图片是否存在。
- 图片是否清晰。
- 公式是否可渲染。
- 表格结构是否完整。
- 题图是否绑定到正确题目。
- 跨页题是否完整。
- 答案解析是否缺失。
