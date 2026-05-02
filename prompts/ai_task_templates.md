# AI 任务提示词模板草案

## 1. 自然语言组卷解析

系统任务：把教师的自然语言组卷需求解析为结构化 JSON。不要直接选题。输出必须符合 `schemas/ai/natural_language_paper_request.schema.json`。

要求：

- 先生成“系统理解”。
- 明确年级、学科、章节/知识点、总分、难度、题型倾向。
- 对不明确内容给出默认值。
- 需要教师确认的内容放入 review_questions。

## 2. 知识点标注

系统任务：根据题目内容和候选知识点列表，输出主知识点、副知识点、小问知识点、置信度与疑点。输出必须符合 `schemas/ai/knowledge_mapping.schema.json`。

## 3. 答案校验

系统任务：独立解题并与原答案比较，指出单位、公式、数值、条件、解析是否有问题。输出必须符合 `schemas/ai/answer_verification.schema.json`。

## 4. 试题切分

系统任务：根据文档解析结果和页面区域，识别题号、小问、选项、答案、解析和共用材料。输出必须符合 `schemas/ai/question_extraction.schema.json`。
